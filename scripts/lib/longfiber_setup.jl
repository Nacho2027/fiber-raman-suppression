"""
Long-Fiber Raman Suppression — Problem Setup (Phase 16 / Session F)

Provides a thin, explicit wrapper around FiberLab's simulation primitives
for long-fiber runs (L ≥ 50 m) where `setup_raman_problem` in `scripts/common.jl`
would silently auto-override the (Nt, time_window) pair chosen by the research
brief (D-F-02).

Two public functions:

  setup_longfiber_problem(; fiber_preset, L_fiber, P_cont, Nt, time_window, ...)
      -> (uω0, fiber, sim, band_mask, Δf, raman_threshold)

  longfiber_interpolate_phi(phi_old, Nt_old, tw_old_ps, Nt_new, tw_new_ps)
      -> phi_new :: Matrix{Float64}(Nt_new, 1)   # FFT-order, mapped in physical Hz

Adapted from `scripts/propagation_reach.jl` (Phase 12), with the auto-sizing
override removed and fiber preset dispatch lifted from `scripts/common.jl`'s
`_apply_fiber_preset` so this script is self-contained and never edits a shared
file (Rule P1 / D-F-11).

Include guard: `_LONGFIBER_SETUP_JL_LOADED` — safe to include multiple times.
"""

try
    using Revise
catch
end

using FFTW
using Interpolations
using Printf
using Logging
using LinearAlgebra
using FiberLab

# scripts/common.jl gives us `FIBER_PRESETS` and `check_boundary_conditions`
include(joinpath(@__DIR__, "common.jl"))

if !(@isdefined _LONGFIBER_SETUP_JL_LOADED)
const _LONGFIBER_SETUP_JL_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# Research-recommended (Nt, time_window) grid table (D-F-02)
# ─────────────────────────────────────────────────────────────────────────────

"""
Grid recommendations from the Session F research brief (D-F-02).

Keys are `Int(round(L_fiber))` in metres; values are `(Nt, time_window_ps)`.

Used only by a soft @warn: any caller is free to pass a different grid, but if
the grid deviates by more than 10% from the recommendation the script logs a
warning so the deviation is visible in the run log.
"""
const LONGFIBER_GRID_TABLE = Dict{Int, Tuple{Int, Float64}}(
    10   => (8192,  10.0),
    30   => (16384, 40.0),
    50   => (16384, 40.0),
    100  => (32768, 160.0),
    200  => (65536, 320.0),
)

# ─────────────────────────────────────────────────────────────────────────────
# Fiber preset dispatch (self-contained copy; does NOT mutate common.jl)
# ─────────────────────────────────────────────────────────────────────────────

"""
    _longfiber_resolve_fiber_preset(preset, gamma_user, betas_user, fR)
        -> (gamma, betas, fR, label)

Look up `preset` in `FIBER_PRESETS` (defined in `scripts/common.jl`). When
`preset === nothing`, use the explicit kwargs; otherwise the preset's gamma,
betas, and fR override them.

Returns a tuple including the preset label (String) for logging.
"""
function _longfiber_resolve_fiber_preset(preset, gamma_user, betas_user, fR)
    if preset === nothing
        return gamma_user, betas_user, fR, "user-defined"
    end
    @assert haskey(FIBER_PRESETS, preset) "unknown fiber preset :$preset — available: $(join(keys(FIBER_PRESETS), ", "))"
    p = FIBER_PRESETS[preset]
    return p.gamma, p.betas, p.fR, p.name
end

# ─────────────────────────────────────────────────────────────────────────────
# Public: warm-start phi interpolation (physical frequency axis)
# ─────────────────────────────────────────────────────────────────────────────

"""
    longfiber_interpolate_phi(phi_old, Nt_old, tw_old_ps, Nt_new, tw_new_ps)
        -> Matrix{Float64}(Nt_new, 1)

Interpolate a stored `phi_opt` (FFT order) to a new (Nt, time_window) grid by
linear interpolation over the physical frequency axis (Hz). Outside the stored
range the new phi is set to 0.0 (optimizer had no information there — the pulse
spectrum at those frequencies is negligible).

Adapted from `pr_interpolate_phi_to_new_grid` in `scripts/propagation_reach.jl`.

# Arguments
- `phi_old` : stored phi, Vector or Matrix of length Nt_old (FFT order)
- `Nt_old`, `tw_old_ps` : stored grid (time window in picoseconds)
- `Nt_new`, `tw_new_ps` : target grid (time window in picoseconds)

# Returns
- `phi_new` : `Matrix{Float64}(Nt_new, 1)` in FFT order for the new grid.

# Physical-range sanity
If the new grid's spectral range is narrower than the old one, the interpolation
still runs (zeros outside), but we log a @warn: normally you go from a short-L
high-resolution grid to a long-L wider-window grid, which HAS a smaller Nyquist.
That is fine — only a small fraction of information is dropped. But if the
reduction is drastic (> 50%) the call probably deserves human review.
"""
function longfiber_interpolate_phi(phi_old, Nt_old, tw_old_ps, Nt_new, tw_new_ps)
    @assert Nt_old > 0 "Nt_old must be positive"
    @assert Nt_new > 0 "Nt_new must be positive"
    @assert tw_old_ps > 0 "tw_old_ps must be positive"
    @assert tw_new_ps > 0 "tw_new_ps must be positive"

    dt_old = tw_old_ps * 1e-12 / Nt_old
    dt_new = tw_new_ps * 1e-12 / Nt_new
    freqs_old = fftfreq(Nt_old, 1.0 / dt_old)   # Hz, FFT order
    freqs_new = fftfreq(Nt_new, 1.0 / dt_new)   # Hz, FFT order

    f_nyquist_old = 1.0 / (2 * dt_old)
    f_nyquist_new = 1.0 / (2 * dt_new)
    if f_nyquist_new < 0.5 * f_nyquist_old
        @warn @sprintf("longfiber_interpolate_phi: new Nyquist %.2f THz < 0.5 * old Nyquist %.2f THz — %.0f%% of stored spectral range will be dropped",
            f_nyquist_new * 1e-12, f_nyquist_old * 1e-12,
            100 * (1 - f_nyquist_new / f_nyquist_old))
    end

    phi_1d = vec(phi_old)
    @assert length(phi_1d) == Nt_old "phi_old length $(length(phi_1d)) ≠ Nt_old $Nt_old"

    sort_idx = sortperm(freqs_old)
    freqs_sorted = freqs_old[sort_idx]
    phi_sorted   = phi_1d[sort_idx]

    itp = Interpolations.linear_interpolation(freqs_sorted, phi_sorted;
        extrapolation_bc = 0.0)

    phi_new = Matrix{Float64}(undef, Nt_new, 1)
    f_lo = freqs_sorted[1]
    f_hi = freqs_sorted[end]
    @inbounds for i in 1:Nt_new
        f = freqs_new[i]
        phi_new[i, 1] = (f_lo <= f <= f_hi) ? itp(f) : 0.0
    end

    @assert all(isfinite, phi_new) "interpolated phi contains non-finite values"
    return phi_new
end

# ─────────────────────────────────────────────────────────────────────────────
# Public: setup_longfiber_problem — direct FiberLab calls, NO auto-size
# ─────────────────────────────────────────────────────────────────────────────

"""
    setup_longfiber_problem(; kwargs...)
        -> (uω0, fiber, sim, band_mask, Δf, raman_threshold)

Build the Raman-suppression optimization problem for long fibers WITHOUT the
silent (Nt, time_window) override that `setup_raman_problem` applies. Passed
values of `Nt` and `time_window` are honored exactly.

Bypass rationale: for long fibers the SPM term in `recommended_time_window`
saturates physically at O(L_NL) but the formula scales linearly in L. At
L=100m SMF-28 P=0.05W, `recommended_time_window` returns a very large tw and
Nt, whereas the correct walk-off-dominated value is T_min ≈ 139 ps (research
§2), well under any formula-based override. See D-F-02.

# Keyword arguments (all required unless a default is given)
- `fiber_preset` : Symbol from `FIBER_PRESETS` (e.g. `:SMF28`, `:HNLF`) or
   `nothing` to use explicit `gamma_user`, `betas_user`, `fR`. Default `nothing`.
- `L_fiber` : fiber length [m] (required positive).
- `P_cont`  : average continuum power [W] (default 0.05).
- `Nt`      : FFT grid size (required power of 2).
- `time_window` : temporal window [ps] (required positive).
- `β_order` : beta expansion order (default 2; must be ≥ length(betas)+1).
- `λ0`      : carrier wavelength [m] (default 1550e-9).
- `M`       : spatial modes (default 1; long-fiber scope is SMF).
- `pulse_fwhm` : sech² FWHM [s] (default 185e-15).
- `pulse_rep_rate` : repetition rate [Hz] (default 80.5e6).
- `pulse_shape` : "sech_sq" (default) or other strings accepted by
   `get_initial_state`.
- `raman_threshold` : Raman-band edge in THz relative to carrier (default -5.0).
- `gamma_user`, `betas_user`, `fR` : only used when `fiber_preset === nothing`.

# Returns
Same tuple shape as `setup_raman_problem` for drop-in compatibility:
`(uω0, fiber, sim, band_mask, Δf, raman_threshold)`.
"""
function setup_longfiber_problem(;
    fiber_preset::Union{Nothing, Symbol} = nothing,
    L_fiber::Real,
    P_cont::Real = 0.05,
    Nt::Integer,
    time_window::Real,
    β_order::Integer = 2,
    λ0::Real = 1550e-9,
    M::Integer = 1,
    pulse_fwhm::Real = 185e-15,
    pulse_rep_rate::Real = 80.5e6,
    pulse_shape::AbstractString = "sech_sq",
    raman_threshold::Real = -5.0,
    gamma_user::Real = 1.3e-3,
    betas_user::AbstractVector{<:Real} = [-2.16e-26],
    fR::Real = 0.18,
)
    # PRECONDITIONS
    @assert L_fiber > 0 "L_fiber must be positive, got $L_fiber"
    @assert P_cont > 0 "P_cont must be positive, got $P_cont"
    @assert ispow2(Nt) "Nt must be a power of 2, got $Nt"
    @assert Nt >= 1024 "Nt too small for long-fiber work ($Nt < 1024)"
    @assert time_window > 0 "time_window must be positive (ps), got $time_window"
    @assert β_order >= 2 "β_order must be ≥ 2, got $β_order"
    @assert M >= 1 "M must be ≥ 1, got $M"
    @assert pulse_fwhm > 0 "pulse_fwhm must be positive"
    @assert pulse_rep_rate > 0 "pulse_rep_rate must be positive"
    @assert λ0 > 0 "λ0 must be positive"

    γ, βs, fR_used, fiber_label = _longfiber_resolve_fiber_preset(
        fiber_preset, gamma_user, collect(float.(betas_user)), fR
    )
    @assert γ > 0 "resolved nonlinear coefficient γ must be positive, got $γ"
    @assert length(βs) >= 1 "resolved betas must have at least β₂"
    @assert length(βs) <= β_order - 1 "β_order=$β_order allows at most $(β_order-1) betas, got $(length(βs)); bump β_order"

    # Soft warning if the (Nt, tw) passed deviates from the research table.
    key = Int(round(L_fiber))
    if haskey(LONGFIBER_GRID_TABLE, key)
        Nt_rec, tw_rec = LONGFIBER_GRID_TABLE[key]
        rel_Nt = abs(Nt - Nt_rec) / Nt_rec
        rel_tw = abs(time_window - tw_rec) / tw_rec
        if rel_Nt > 0.1 || rel_tw > 0.1
            @warn @sprintf("setup_longfiber_problem: (Nt=%d, tw=%.1f ps) deviates from research-recommended (%d, %.1f ps) at L=%d m",
                Nt, time_window, Nt_rec, tw_rec, key)
        end
    end

    @info @sprintf("Long-fiber setup: %s, L=%.1f m, P=%.3f W, Nt=%d, tw=%.1f ps, β_order=%d",
        fiber_label, L_fiber, P_cont, Nt, time_window, β_order)

    # Direct FiberLab calls — bypasses setup_raman_problem auto-sizing.
    sim = FiberLab.get_disp_sim_params(λ0, M, Nt, time_window, β_order)
    fiber = FiberLab.get_disp_fiber_params_user_defined(
        L_fiber, sim; fR = fR_used, gamma_user = γ, betas_user = βs,
    )
    u0_modes = ones(M) / √M
    _, uω0 = FiberLab.get_initial_state(
        u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim
    )

    Δf_fft = fftfreq(Nt, 1.0 / sim["Δt"])
    Δf = fftshift(Δf_fft)
    band_mask = Δf_fft .< raman_threshold

    # POSTCONDITIONS — the override we're working around.
    # FiberLab.get_disp_sim_params stores sim["Δt"] and sim["time_window"] in
    # PICOSECONDS (see src/helpers/helpers.jl:52). Do not multiply by 1e12.
    @assert sim["Nt"] == Nt "sim[Nt] ($(sim["Nt"])) ≠ requested Nt ($Nt) — FiberLab override?"
    tw_actual_ps = sim["Δt"] * Nt
    @assert isapprox(tw_actual_ps, float(time_window); atol = 1e-6) "sim time_window ($(tw_actual_ps) ps) ≠ requested ($(time_window) ps)"
    @assert any(band_mask) "Raman band mask is empty — check raman_threshold and grid"

    @debug @sprintf("setup_longfiber_problem done: raman_bins=%d / %d, Δf_nyquist=%.2f THz",
        sum(band_mask), Nt, 0.5 / sim["Δt"] * 1e-12)

    return uω0, fiber, sim, band_mask, Δf, float(raman_threshold)
end

end  # include guard

# ─────────────────────────────────────────────────────────────────────────────
# Smoke test (main-guarded so `include` does not trigger it)
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    @info "longfiber_setup smoke test"

    # L = 100 m, SMF-28, research-recommended grid
    uω0, fiber, sim, band_mask, Δf, thr = setup_longfiber_problem(
        fiber_preset = :SMF28_beta2_only,
        L_fiber      = 100.0,
        P_cont       = 0.05,
        Nt           = 32768,
        time_window  = 160.0,
        β_order      = 2,
    )
    @info @sprintf("L=100 m: sim[Nt]=%d, Nt*Δt=%.3f ps, raman_bins=%d",
        sim["Nt"], sim["Δt"] * sim["Nt"], sum(band_mask))
    @assert sim["Nt"] == 32768
    @assert isapprox(sim["Δt"] * sim["Nt"], 160.0; atol = 1e-6)

    # Interpolation roundtrip test: same grid → identity
    phi_a = randn(8192)
    phi_b = longfiber_interpolate_phi(phi_a, 8192, 10.0, 8192, 10.0)
    @assert size(phi_b) == (8192, 1)
    # Most bins must match exactly (grid identical)
    n_match = sum(isapprox.(phi_b[:, 1], phi_a; atol = 1e-10))
    @info @sprintf("Interpolation self-test: %d / 8192 bins match identity", n_match)
    @assert n_match == 8192

    # Cross-grid: 8192/10ps → 32768/160ps (phi@2m → phi@100m case)
    phi_c = longfiber_interpolate_phi(phi_a, 8192, 10.0, 32768, 160.0)
    @assert size(phi_c) == (32768, 1)
    @assert all(isfinite, phi_c)
    @info @sprintf("Cross-grid interpolation: max|phi_c|=%.3e, nonzero=%d",
        maximum(abs.(phi_c)), count(!iszero, phi_c))

    @info "longfiber_setup smoke test: PASSED"
end
