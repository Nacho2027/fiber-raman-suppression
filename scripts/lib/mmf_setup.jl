"""
Multimode setup helper for Session C — wraps the existing GRIN fiber builder
(`MultiModeNoise.get_disp_fiber_params`) and returns the tuple of objects
needed by the MMF Raman-phase optimizer.

This is the MMF counterpart to `scripts/common.jl::setup_raman_problem`.
The SMF setup is NOT modified.

Include guard: safe to include multiple times.
"""

using Printf

if !(@isdefined _MMF_SETUP_JL_LOADED)
const _MMF_SETUP_JL_LOADED = true

using LinearAlgebra
using FFTW
using Logging
using Statistics
using MultiModeNoise

include(joinpath(@__DIR__, "mmf_fiber_presets.jl"))

"""
    mmf_nt_for_window(time_window_ps; dt_min_ps=0.0105) -> Int

Smallest power-of-2 grid that resolves the requested time window with at least
`dt_min_ps` spacing.
"""
function mmf_nt_for_window(time_window_ps; dt_min_ps=0.0105)
    @assert time_window_ps > 0 "time_window_ps must be positive, got $time_window_ps"
    nt_min = ceil(Int, time_window_ps / dt_min_ps)
    nt = 1
    while nt < nt_min
        nt <<= 1
    end
    return nt
end

function _mmf_mode_beta2_abs(fiber::Dict, sim::Dict)
    Ω_shift = fftshift(2π .* fftfreq(sim["Nt"], 1 / sim["Δt"]) .* 1e12)  # rad/s
    ΔΩ = Ω_shift[2] - Ω_shift[1]
    center = sim["Nt"] ÷ 2 + 1
    D_shift = fftshift(real.(fiber["Dω"]), 1)

    M = size(fiber["Dω"], 2)
    β2_abs = zeros(Float64, M)
    for m in 1:M
        β2_abs[m] = abs(
            (D_shift[center + 1, m] - 2 * D_shift[center, m] + D_shift[center - 1, m]) / (ΔΩ^2)
        )
    end
    return β2_abs
end

function _mmf_peak_power(uω0::AbstractMatrix)
    ut0 = ifft(uω0, 1)
    return maximum(sum(abs2.(ut0), dims = 2))
end

function _mmf_effective_gamma(fiber::Dict)
    M = size(fiber["γ"], 1)
    γdiag = [real(fiber["γ"][m, m, m, m]) for m in 1:M]
    return max(maximum(γdiag), 0.0)
end

"""
    mmf_recommended_time_window(fiber, sim, uω0; kwargs...) -> NamedTuple

Conservative MMF analogue of the single-mode time-window heuristic.
Uses the largest inferred |β₂| across modes and the largest diagonal Kerr term
`γ[m,m,m,m]`, together with the actual shaped-launch peak power.
"""
function mmf_recommended_time_window(
    fiber::Dict,
    sim::Dict,
    uω0::AbstractMatrix;
    L_fiber::Real = fiber["L"],
    pulse_fwhm::Real = 185e-15,
    safety_factor::Real = 2.0,
)
    @assert L_fiber > 0 "L_fiber must be positive"
    @assert pulse_fwhm > 0 "pulse_fwhm must be positive"
    @assert safety_factor > 0 "safety_factor must be positive"

    β2_abs_modes = _mmf_mode_beta2_abs(fiber, sim)
    beta2 = maximum(β2_abs_modes)
    gamma = _mmf_effective_gamma(fiber)
    P_peak = _mmf_peak_power(uω0)

    Δω_raman = 2π * 13e12
    walk_off_ps = beta2 * L_fiber * Δω_raman * 1e12
    T0 = pulse_fwhm / 1.763
    φ_NL = gamma * P_peak * L_fiber
    δω_SPM = gamma > 0 && P_peak > 0 ? 0.86 * φ_NL / T0 : 0.0
    spm_ps = beta2 * L_fiber * δω_SPM * 1e12
    pulse_extent_ps = 0.5

    recommended_ps = max(5, ceil(Int, (walk_off_ps + spm_ps + pulse_extent_ps) * safety_factor))
    return (
        time_window_ps = recommended_ps,
        beta2_abs_modes = β2_abs_modes,
        beta2_abs_max = beta2,
        gamma_effective = gamma,
        peak_power_W = P_peak,
        walk_off_ps = walk_off_ps,
        spm_ps = spm_ps,
        safety_factor = Float64(safety_factor),
    )
end

"""
    setup_mmf_raman_problem(; kwargs...) -> NamedTuple

Build all objects needed for multimode Raman phase optimization from a GRIN or
step-index preset.

Returns a NamedTuple with fields:
- `uω0`            : initial field in frequency domain, shape (Nt, M) [√W]
- `fiber`          : fiber parameter dict (Dω, γ, hRω, L, one_m_fR, zsave, ϕ, x, ...)
- `sim`            : simulation parameter dict (ω0, Δt, attenuator, ...)
- `band_mask`      : Bool vector length Nt, true inside the Raman-shifted band
- `Δf`             : fftshift-ordered frequency grid [THz]
- `raman_threshold`: cutoff frequency [THz] below which band_mask is true
- `mode_weights`   : unit-norm ComplexF64 vector length M (input mode content)
- `preset`         : the NamedTuple from MMF_FIBER_PRESETS
- `fiber_cache`    : path used for the NPZ eigensolver cache (reused across runs)

# Keyword arguments
- `preset::Symbol = :GRIN_50`
- `L_fiber = 1.0`          : fiber length [m]
- `P_cont = 0.05`          : average power [W]
- `pulse_fwhm = 185e-15`   : pulse FWHM [s]
- `pulse_rep_rate = 80.5e6`
- `pulse_shape = "sech_sq"`
- `Nt = 2^13`              : temporal grid (power of 2)
- `time_window = 10.0`     : time window [ps]
- `mode_weights = nothing` : if nothing, uses `default_mode_weights(M)`
- `raman_threshold = -5.0` : Raman band cutoff [THz]
- `λ0 = 1550e-9`
- `fiber_cache_dir = "results/raman/phase16/fiber_cache"`
- `auto_time_window = true` : conservatively upsize undersized windows

# Notes
- Uses `MultiModeNoise.get_disp_sim_params` and `get_disp_fiber_params` — both
  already exist in `src/helpers/helpers.jl`. No modifications to `src/`.
- Auto-sizing of time_window / Nt is NOT performed here because the MMF has
  mode-dependent β₂; the caller is responsible for choosing a safe window.
- The GRIN eigensolver cost is amortized via NPZ caching keyed on
  (preset, Nt, time_window).
"""
function setup_mmf_raman_problem(;
    preset::Symbol = :GRIN_50,
    L_fiber = 1.0,
    P_cont = 0.05,
    pulse_fwhm = 185e-15,
    pulse_rep_rate = 80.5e6,
    pulse_shape = "sech_sq",
    Nt = 2^13,
    time_window = 10.0,
    mode_weights::Union{Nothing, AbstractVector} = nothing,
    raman_threshold = -5.0,
    λ0 = 1550e-9,
    fiber_cache_dir::AbstractString = joinpath(@__DIR__, "..", "..", "results", "raman", "phase16", "fiber_cache"),
    auto_time_window::Bool = true,
)
    # PRECONDITIONS
    @assert ispow2(Nt) "Nt must be power of 2, got $Nt"
    @assert time_window > 0 "time_window must be positive"
    @assert L_fiber > 0 "L_fiber must be positive"
    @assert P_cont > 0 "P_cont must be positive"
    @assert pulse_fwhm > 0 "pulse_fwhm must be positive"

    p = get_mmf_fiber_preset(preset)
    M = p.M

    # Mode weights
    w = isnothing(mode_weights) ? default_mode_weights(M) : ComplexF64.(mode_weights)
    @assert length(w) == M "mode_weights length ($(length(w))) must equal M=$M"
    w = w ./ norm(w)

    function _build_with_window(Nt_local::Int, time_window_local::Real)
        sim_local = MultiModeNoise.get_disp_sim_params(λ0, M, Nt_local, time_window_local, p.β_order)
        mkpath(fiber_cache_dir)
        cache_fname_local = joinpath(
            fiber_cache_dir,
            @sprintf("mmf_%s_nt%d_tw%g.npz", String(preset), Nt_local, time_window_local),
        )
        fiber_local = MultiModeNoise.get_disp_fiber_params(
            L_fiber, p.radius, p.core_NA, p.alpha, p.nx, sim_local, cache_fname_local;
            spatial_window = p.spatial_window,
            fR = p.fR,
            τ1 = p.τ1,
            τ2 = p.τ2,
        )
        fiber_local["L"] = L_fiber
        _, uω0_local = MultiModeNoise.get_initial_state(
            w, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim_local
        )
        return sim_local, fiber_local, uω0_local, cache_fname_local
    end

    sim, fiber, uω0, cache_fname = _build_with_window(Nt, time_window)

    window_rec = mmf_recommended_time_window(
        fiber, sim, uω0;
        L_fiber = L_fiber,
        pulse_fwhm = pulse_fwhm,
    )
    if time_window < window_rec.time_window_ps
        Nt_rec = mmf_nt_for_window(window_rec.time_window_ps)
        if auto_time_window
            @info @sprintf(
                "MMF auto-sizing: time_window %.1f→%.1f ps, Nt %d→%d (L=%.2fm, P=%.3fW, max|β₂|=%.2e, γeff=%.3e, Ppeak=%.2e W)",
                time_window, window_rec.time_window_ps, Nt, max(Nt, Nt_rec),
                L_fiber, P_cont, window_rec.beta2_abs_max, window_rec.gamma_effective, window_rec.peak_power_W,
            )
            time_window = window_rec.time_window_ps
            Nt = max(Nt, Nt_rec)
            sim, fiber, uω0, cache_fname = _build_with_window(Nt, time_window)
            window_rec = mmf_recommended_time_window(
                fiber, sim, uω0;
                L_fiber = L_fiber,
                pulse_fwhm = pulse_fwhm,
            )
        else
            @warn @sprintf(
                "MMF setup using undersized time_window=%.1f ps < recommended %.1f ps (L=%.2fm, P=%.3fW)",
                time_window, window_rec.time_window_ps, L_fiber, P_cont,
            )
        end
    end

    # Raman band mask
    Δf_fft = fftfreq(Nt, 1 / sim["Δt"])
    Δf     = fftshift(Δf_fft)
    band_mask = Δf_fft .< raman_threshold

    # POSTCONDITIONS
    @assert size(uω0) == (Nt, M) "uω0 shape wrong"
    @assert size(fiber["Dω"]) == (Nt, M) "Dω shape wrong"
    @assert size(fiber["γ"])  == (M, M, M, M) "γ shape wrong"
    @assert sum(abs2, uω0) > 0 "initial field has zero energy"
    @assert any(band_mask) "Raman band mask is empty"

    @info @sprintf("MMF setup: preset=%s, M=%d, Nt=%d, L=%.2fm, P=%.3fW, raman_bins=%d/%d",
        String(preset), M, Nt, L_fiber, P_cont, sum(band_mask), Nt)

    return (
        uω0             = uω0,
        fiber           = fiber,
        sim             = sim,
        band_mask       = band_mask,
        Δf              = Δf,
        raman_threshold = raman_threshold,
        mode_weights    = w,
        preset          = p,
        fiber_cache     = cache_fname,
        window_recommendation = window_rec,
    )
end

end # include guard
