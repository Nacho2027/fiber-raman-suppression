"""
Common utilities shared across fiber optimization scripts.

Shared functions (single source of truth):
- `FIBER_PRESETS` — named single-mode fiber parameter presets
- `get_fiber_preset` — look up a fiber preset by name
- `print_fiber_summary` — compute and display characteristic lengths and soliton number
- `recommended_time_window` — safe time window from dispersive walk-off
- `spectral_band_cost` — fractional spectral energy in a frequency band
- `check_boundary_conditions` — detect energy leakage at temporal window edges
- `setup_raman_problem` — setup for phase optimization (single-mode fibers)
- `setup_amplitude_problem` — setup for amplitude optimization (single-mode fibers)

All fiber parameters in this module are for single-mode (M=1) propagation using
`get_disp_fiber_params_user_defined`. GRIN multimode fiber code lives in
`src/simulation/fibers.jl` and is not used here.

Include guard: safe to include multiple times.
"""

if !(@isdefined _COMMON_JL_LOADED)
const _COMMON_JL_LOADED = true

using LinearAlgebra
using FFTW
using Logging
using Printf
using MultiModeNoise

# ─────────────────────────────────────────────────────────────────────────────
# Fiber presets — named single-mode fiber parameter sets
# ─────────────────────────────────────────────────────────────────────────────

"""
    FIBER_PRESETS

Dictionary of named single-mode fiber parameter presets. Each entry is a
NamedTuple with fields: `name`, `gamma`, `betas`, `fR`, `description`.

All parameters are in SI units:
- `gamma`: nonlinear coefficient [W⁻¹m⁻¹]
- `betas`: dispersion coefficients [β₂ in s²/m, β₃ in s³/m, ...]
- `fR`: fractional Raman contribution [dimensionless]

Available presets: :SMF28, :SMF28_beta2_only, :HNLF, :HNLF_zero_disp
"""
const FIBER_PRESETS = Dict(
    :SMF28 => (
        name = "SMF-28",
        gamma = 1.1e-3,
        betas = [-2.17e-26, 1.2e-40],
        fR = 0.18,
        description = "Corning SMF-28 @ 1550nm (β₂ + β₃)"
    ),
    :SMF28_beta2_only => (
        name = "SMF-28 (β₂ only)",
        gamma = 1.1e-3,
        betas = [-2.17e-26],
        fR = 0.18,
        description = "Corning SMF-28 @ 1550nm, no TOD"
    ),
    :HNLF => (
        name = "HNLF",
        gamma = 10.0e-3,
        betas = [-0.5e-26, 1.0e-40],
        fR = 0.18,
        description = "Highly Nonlinear Fiber @ 1550nm (β₂ + β₃)"
    ),
    :HNLF_zero_disp => (
        name = "HNLF (zero-disp)",
        gamma = 10.0e-3,
        betas = [-0.1e-26, 3.0e-40],
        fR = 0.18,
        description = "HNLF near zero-dispersion wavelength"
    ),
)

"""
    get_fiber_preset(name::Symbol) -> NamedTuple

Look up a single-mode fiber preset by name. Logs the selected fiber info.

# Example
```julia
p = get_fiber_preset(:SMF28)
# p.gamma, p.betas, p.fR are ready to pass to setup functions
```
"""
function get_fiber_preset(name::Symbol)
    @assert haskey(FIBER_PRESETS, name) "unknown fiber preset :$name — available: $(join(keys(FIBER_PRESETS), ", "))"
    preset = FIBER_PRESETS[name]
    @debug @sprintf("Fiber preset: %s — γ=%.2e W⁻¹m⁻¹, β₂=%.2e s²/m, fR=%.2f",
        preset.name, preset.gamma, preset.betas[1], preset.fR)
    return preset
end

"""
    _apply_fiber_preset(fiber_preset, gamma_user, betas_user, fR) -> (gamma, betas, fR)

Internal helper: resolve fiber preset into (gamma, betas, fR), falling back to
the explicit values when no preset is given.
"""
function _apply_fiber_preset(fiber_preset, gamma_user, betas_user, fR)
    if fiber_preset === nothing
        return gamma_user, betas_user, fR
    end
    preset = get_fiber_preset(fiber_preset)
    return preset.gamma, preset.betas, preset.fR
end

"""
    print_fiber_summary(; gamma, betas, P_cont, pulse_fwhm, pulse_rep_rate)

Compute and print characteristic nonlinear fiber parameters for diagnostics.

All arguments are in SI units. Printed quantities:
- Soliton number N = sqrt(γ · P_peak · T₀² / |β₂|)
- Dispersion length L_D = T₀² / |β₂|
- Nonlinear length L_NL = 1 / (γ · P_peak)
- Raman walk-off time τ_R = |β₂| · L · Δω_Raman (for L = L_D)

where T₀ = FWHM / (2·acosh(√2)) for sech² pulses and
P_peak = P_cont / (FWHM · rep_rate).

Returns a NamedTuple: (N_sol, L_D, L_NL, τ_R, P_peak, T0).
"""
function print_fiber_summary(; gamma, betas, P_cont, pulse_fwhm, pulse_rep_rate)
    @assert gamma > 0 "gamma must be positive"
    @assert length(betas) >= 1 "need at least β₂"
    @assert P_cont > 0 "P_cont must be positive"
    @assert pulse_fwhm > 0 "pulse_fwhm must be positive"
    @assert pulse_rep_rate > 0 "pulse_rep_rate must be positive"

    β2 = betas[1]
    T0 = pulse_fwhm / (2 * acosh(sqrt(2)))
    P_peak = P_cont / (pulse_fwhm * pulse_rep_rate)

    L_D = T0^2 / abs(β2)
    L_NL = 1.0 / (gamma * P_peak)
    N_sol = sqrt(gamma * P_peak * T0^2 / abs(β2))

    Δω_raman = 2π * 13e12
    τ_R = abs(β2) * L_D * Δω_raman

    lines = String[]
    push!(lines, "╔══════════════════════════════════════════════════╗")
    push!(lines, "║           Fiber Parameter Summary                ║")
    push!(lines, "╠══════════════════════════════════════════════════╣")
    push!(lines, @sprintf("║  γ            = %.3e W⁻¹m⁻¹              ║", gamma))
    push!(lines, @sprintf("║  β₂           = %.3e s²/m                ║", β2))
    if length(betas) >= 2
        push!(lines, @sprintf("║  β₃           = %.3e s³/m                ║", betas[2]))
    end
    push!(lines, @sprintf("║  P_peak       = %.2f W                        ║", P_peak))
    push!(lines, @sprintf("║  T₀           = %.1f fs                        ║", T0 * 1e15))
    push!(lines, "╠══════════════════════════════════════════════════╣")
    push!(lines, @sprintf("║  Soliton N    = %.2f                            ║", N_sol))
    push!(lines, @sprintf("║  L_D          = %.3f m                          ║", L_D))
    push!(lines, @sprintf("║  L_NL         = %.3f m                          ║", L_NL))
    push!(lines, @sprintf("║  τ_R (at L_D) = %.2f ps                         ║", τ_R * 1e12))
    push!(lines, "╚══════════════════════════════════════════════════╝")

    @info join(lines, "\n")
    return (N_sol=N_sol, L_D=L_D, L_NL=L_NL, τ_R=τ_R, P_peak=P_peak, T0=T0)
end

# ─────────────────────────────────────────────────────────────────────────────
# Time window safety
# ─────────────────────────────────────────────────────────────────────────────

"""
    recommended_time_window(L_fiber; safety_factor=2.0, beta2=20e-27, gamma=0.0, P_peak=0.0, pulse_fwhm=185e-15)

Compute safe time window [ps] from dispersive walk-off plus SPM spectral broadening
for single-mode fibers. Uses |β₂| and Raman shift of 13 THz for the linear walk-off
term, and adds the SPM-induced temporal broadening when gamma and P_peak are provided.
Returns at least 5 ps to avoid degenerate grids for short fibers.

SPM broadening: φ_NL = γ × P0 × L gives the nonlinear phase (radians), not a
frequency. The actual spectral broadening for sech² is δω ≈ 0.86 × φ_NL / T0
(Agrawal, Ch. 4), where T0 = FWHM/1.763. The temporal spread from this broadened
spectrum propagating through GVD is Δt_SPM = |β₂| × L × δω.

# Keyword arguments
- `safety_factor`: multiplicative safety margin (default 2.0)
- `beta2`: absolute value of β₂ in s²/m (default 20e-27, approximately SMF-28)
- `gamma`: nonlinear coefficient in W⁻¹m⁻¹ (default 0.0 = no SPM correction)
- `P_peak`: peak pulse power in W (default 0.0 = no SPM correction)
- `pulse_fwhm`: pulse FWHM duration in seconds (default 185e-15 for 185 fs sech²)
"""
function recommended_time_window(L_fiber; safety_factor=2.0, beta2=20e-27,
                                  gamma=0.0, P_peak=0.0, pulse_fwhm=185e-15)
    @assert L_fiber > 0 "fiber length must be positive, got $L_fiber"
    @assert safety_factor > 0 "safety factor must be positive"
    @assert beta2 > 0 "beta2 must be positive (pass absolute value)"
    @assert pulse_fwhm > 0 "pulse_fwhm must be positive"

    Δω_raman = 2π * 13e12
    walk_off_ps = beta2 * L_fiber * Δω_raman * 1e12
    pulse_extent = 0.5

    # SPM-induced spectral broadening causes additional temporal walkout.
    # Only active when both gamma > 0 and P_peak > 0 (backward-compatible defaults).
    # φ_NL = γ × P0 × L is nonlinear phase (radians); convert to frequency via T0.
    spm_ps = 0.0
    if gamma > 0 && P_peak > 0
        T0 = pulse_fwhm / 1.763              # sech² half-duration [s]
        φ_NL = gamma * P_peak * L_fiber       # nonlinear phase [rad]
        δω_SPM = 0.86 * φ_NL / T0            # SPM spectral broadening [rad/s]
        spm_ps = beta2 * L_fiber * δω_SPM * 1e12   # GVD temporal spread [ps]
    end

    total_ps = walk_off_ps + spm_ps + pulse_extent
    return max(5, ceil(Int, total_ps * safety_factor))
end

"""
    nt_for_window(time_window_ps; dt_min_ps=0.0105)

Return the smallest power-of-2 Nt that maintains at least `dt_min_ps` temporal
resolution for the given time window.

Default `dt_min_ps=0.0105` corresponds to ≈10.5 fs resolution, sufficient to
resolve femtosecond pulse structures without over-sampling.

# Arguments
- `time_window_ps`: total simulation time window in picoseconds (must be > 0)
- `dt_min_ps`: minimum temporal step size in ps (default 0.0105)

# Returns
- Power-of-2 integer Nt ≥ ceil(time_window_ps / dt_min_ps)
"""
function nt_for_window(time_window_ps; dt_min_ps=0.0105)
    @assert time_window_ps > 0 "time_window_ps must be positive, got $time_window_ps"
    nt_min = ceil(Int, time_window_ps / dt_min_ps)
    nt = 1
    while nt < nt_min
        nt <<= 1
    end
    return nt
end

# ─────────────────────────────────────────────────────────────────────────────
# Spectral band cost (single definition — was duplicated across files)
# ─────────────────────────────────────────────────────────────────────────────

"""
    spectral_band_cost(uωf, band_mask)

Fractional spectral energy in a frequency band and its gradient.

# Arguments
- `uωf`: Output field in frequency domain, shape (Nt, M).
- `band_mask`: Boolean vector of length Nt, true for frequencies in the band.

# Returns
- `J`: Scalar cost = E_band / E_total ∈ [0, 1].
- `dJ`: Gradient w.r.t. conj(uωf), adjoint terminal condition λ(L).
"""
function spectral_band_cost(uωf, band_mask)
    # PRECONDITIONS
    @assert size(uωf, 1) == length(band_mask) "uωf rows ($(size(uωf,1))) must match band_mask length ($(length(band_mask)))"
    @assert any(band_mask) "band_mask must have at least one true element"
    @assert sum(abs2.(uωf)) > 0 "field must have nonzero energy"

    E_band = sum(abs2.(uωf[band_mask, :]))
    E_total = sum(abs2.(uωf))
    J = E_band / E_total
    dJ = uωf .* (band_mask .- J) ./ E_total

    # POSTCONDITIONS
    @assert 0 ≤ J ≤ 1 "fractional energy J=$J out of [0,1]"
    @assert all(isfinite, dJ) "gradient contains non-finite values"

    return J, dJ
end

# ─────────────────────────────────────────────────────────────────────────────
# Boundary condition check
# ─────────────────────────────────────────────────────────────────────────────

"""
    check_boundary_conditions(ut_z, sim; threshold=1e-6)

Check that field energy at temporal window edges is negligible.
Returns (is_ok, edge_fraction) where edge_fraction is the fraction of
total energy within the first and last 5% of the time grid.
"""
function check_boundary_conditions(ut_z, sim; threshold=1e-6)
    @assert threshold > 0 "threshold must be positive"

    Nt = sim["Nt"]
    n_edge = max(1, Nt ÷ 20)  # 5% of grid on each side
    E_total = sum(abs2.(ut_z))
    E_edges = sum(abs2.(ut_z[1:n_edge, :])) + sum(abs2.(ut_z[end-n_edge+1:end, :]))
    edge_frac = E_edges / max(E_total, eps())
    return edge_frac < threshold, edge_frac
end

# ─────────────────────────────────────────────────────────────────────────────
# Setup: phase optimization (single-mode fibers)
# ─────────────────────────────────────────────────────────────────────────────

"""
    setup_raman_problem(; kwargs...)

Create all objects needed for Raman phase optimization from single-mode fiber
parameters. Uses `get_disp_fiber_params_user_defined` with M=1 (bypasses GRIN).

When `fiber_preset` is provided, its `gamma`, `betas`, and `fR` override the
corresponding keyword arguments. Explicit kwargs take precedence when
`fiber_preset` is `nothing` (the default).

Defaults: Nt=2^14, time_window=10.0, β_order=2, P_cont=0.05, betas_user=[-2.6e-26].

Returns (uω0, fiber, sim, band_mask, Δf, raman_threshold).
"""
function setup_raman_problem(;
    λ0 = 1550e-9,
    M = 1,
    Nt = 2^14,
    time_window = 10.0,
    β_order = 2,
    L_fiber = 1.0,
    P_cont = 0.05,
    pulse_fwhm = 185e-15,
    pulse_rep_rate = 80.5e6,
    pulse_shape = "sech_sq",
    raman_threshold = -5.0,
    gamma_user = 0.0013,
    betas_user = [-2.6e-26],
    fR = 0.18,
    fiber_preset::Union{Nothing, Symbol} = nothing
)
    gamma_user, betas_user, fR = _apply_fiber_preset(fiber_preset, gamma_user, betas_user, fR)

    # PRECONDITIONS
    @assert λ0 > 0 "wavelength must be positive, got $λ0"
    @assert M ≥ 1 "need at least 1 mode"
    @assert ispow2(Nt) "Nt must be power of 2, got $Nt"
    @assert time_window > 0 "time_window must be positive"
    @assert L_fiber > 0 "fiber length must be positive, got $L_fiber"
    @assert P_cont > 0 "power must be positive"
    @assert pulse_fwhm > 0 "pulse FWHM must be positive"
    @assert gamma_user > 0 "nonlinear coefficient must be positive"
    @assert length(betas_user) ≥ 1 "need at least β₂"

    # SPM-corrected time window: auto-override if too small to prevent attenuator absorption.
    # sech² peak power: P_peak = 0.881374 * P_cont / (fwhm_s * rep_rate)
    _P_peak = 0.881374 * P_cont / (pulse_fwhm * pulse_rep_rate)
    tw_rec = recommended_time_window(L_fiber;
        beta2=abs(betas_user[1]), gamma=gamma_user, P_peak=_P_peak)
    if time_window < tw_rec
        Nt_rec = nt_for_window(tw_rec)
        @info @sprintf("Auto-sizing: time_window %d→%d ps, Nt %d→%d (for L=%.1fm P=%.3fW)",
            time_window, tw_rec, Nt, max(Nt, Nt_rec), L_fiber, P_cont)
        time_window = tw_rec
        Nt = max(Nt, Nt_rec)
    end

    sim = MultiModeNoise.get_disp_sim_params(λ0, M, Nt, time_window, β_order)
    fiber = MultiModeNoise.get_disp_fiber_params_user_defined(
        L_fiber, sim; fR=fR, gamma_user=gamma_user, betas_user=betas_user
    )
    u0_modes = ones(M) / √M
    _, uω0 = MultiModeNoise.get_initial_state(
        u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim
    )

    Δf_fft = fftfreq(Nt, 1 / sim["Δt"])
    Δf = fftshift(Δf_fft)
    band_mask = Δf_fft .< raman_threshold

    @debug "Setup (raman)" L=L_fiber P_cont=P_cont pulse=pulse_shape fwhm_fs=pulse_fwhm*1e15 γ=gamma_user β₂=betas_user[1] raman_bins=sum(band_mask) total_bins=Nt fiber_preset=fiber_preset

    return uω0, fiber, sim, band_mask, Δf, raman_threshold
end

# ─────────────────────────────────────────────────────────────────────────────
# Setup: amplitude optimization (single-mode fibers)
# ─────────────────────────────────────────────────────────────────────────────

"""
    setup_amplitude_problem(; kwargs...)

Create all objects needed for amplitude optimization from single-mode fiber
parameters. Uses `get_disp_fiber_params_user_defined` with M=1 (bypasses GRIN).

When `fiber_preset` is provided, its `gamma`, `betas`, and `fR` override the
corresponding keyword arguments.

Defaults: Nt=2^13, time_window=10.0, β_order=3, P_cont=0.05,
          betas_user=[-2.6e-26, 1.2e-40].

Returns (uω0, fiber, sim, band_mask, Δf, raman_threshold).
"""
function setup_amplitude_problem(;
    λ0 = 1550e-9,
    M = 1,
    Nt = 2^13,
    time_window = 10.0,
    β_order = 3,
    L_fiber = 1.0,
    P_cont = 0.05,
    pulse_fwhm = 185e-15,
    pulse_rep_rate = 80.5e6,
    pulse_shape = "sech_sq",
    raman_threshold = -5.0,
    gamma_user = 0.0013,
    betas_user = [-2.6e-26, 1.2e-40],
    fR = 0.18,
    fiber_preset::Union{Nothing, Symbol} = nothing
)
    gamma_user, betas_user, fR = _apply_fiber_preset(fiber_preset, gamma_user, betas_user, fR)

    # PRECONDITIONS
    @assert λ0 > 0 "wavelength must be positive, got $λ0"
    @assert M ≥ 1 "need at least 1 mode"
    @assert ispow2(Nt) "Nt must be power of 2, got $Nt"
    @assert time_window > 0 "time_window must be positive"
    @assert L_fiber > 0 "fiber length must be positive, got $L_fiber"
    @assert P_cont > 0 "power must be positive"
    @assert pulse_fwhm > 0 "pulse FWHM must be positive"
    @assert gamma_user > 0 "nonlinear coefficient must be positive"
    @assert length(betas_user) ≥ 1 "need at least β₂"

    # SPM-corrected time window: auto-override if too small to prevent attenuator absorption.
    # sech² peak power: P_peak = 0.881374 * P_cont / (fwhm_s * rep_rate)
    _P_peak = 0.881374 * P_cont / (pulse_fwhm * pulse_rep_rate)
    tw_rec = recommended_time_window(L_fiber;
        beta2=abs(betas_user[1]), gamma=gamma_user, P_peak=_P_peak)
    if time_window < tw_rec
        Nt_rec = nt_for_window(tw_rec)
        @info @sprintf("Auto-sizing: time_window %d→%d ps, Nt %d→%d (for L=%.1fm P=%.3fW)",
            time_window, tw_rec, Nt, max(Nt, Nt_rec), L_fiber, P_cont)
        time_window = tw_rec
        Nt = max(Nt, Nt_rec)
    end

    sim = MultiModeNoise.get_disp_sim_params(λ0, M, Nt, time_window, β_order)
    fiber = MultiModeNoise.get_disp_fiber_params_user_defined(
        L_fiber, sim; fR=fR, gamma_user=gamma_user, betas_user=betas_user
    )
    u0_modes = ones(M) / √M
    _, uω0 = MultiModeNoise.get_initial_state(
        u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim
    )

    Δf_fft = fftfreq(Nt, 1 / sim["Δt"])
    Δf = fftshift(Δf_fft)
    band_mask = Δf_fft .< raman_threshold

    # Soliton order for diagnostics
    β2 = betas_user[1]
    T0 = pulse_fwhm / (2 * acosh(sqrt(2)))
    P_peak = P_cont / (pulse_fwhm * pulse_rep_rate)
    N_sol = sqrt(gamma_user * P_peak * T0^2 / abs(β2))

    @debug "Setup (amplitude)" L=L_fiber P_cont=P_cont pulse=pulse_shape fwhm_fs=pulse_fwhm*1e15 γ=gamma_user β₂=betas_user[1] N_soliton=round(N_sol, digits=2) raman_bins=sum(band_mask) total_bins=Nt time_window=time_window tw_recommended=tw_rec fiber_preset=fiber_preset

    return uω0, fiber, sim, band_mask, Δf, raman_threshold
end

end # include guard
