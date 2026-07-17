"""
Multimode setup helper that wraps the existing GRIN fiber builder
(`FiberLab.get_disp_fiber_params`) and returns the tuple of objects
needed by the MMF Raman-phase optimizer.

This is the MMF counterpart to `scripts/lib/common.jl::setup_raman_problem`.
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
using SHA
using FiberLab

include(joinpath(@__DIR__, "mmf_fiber_presets.jl"))

function _resolved_mmf_grid(Nt, time_window, recommended_window=time_window;
                            wavelength_m=1550e-9)
    resolved = FiberLab.resolve_sampling_grid(
        Grid(nt=Nt, time_window_ps=time_window, policy=:auto_if_undersized);
        wavelength_m=wavelength_m,
        minimum_time_window_ps=recommended_window,
    )
    return resolved.nt, resolved.time_window_ps
end

_canonical_mmf_pulse_shape(shape) = FiberLab._pulse_shape_string(Symbol(shape))

const _MMF_MODAL_CACHE_SCHEMA = "mmf-modal-cache-v2"

function _mmf_modal_cache_path(
    cache_dir::AbstractString,
    preset::Symbol,
    p,
    sim,
)
    source_files = (
        joinpath(@__DIR__, "..", "..", "src", "simulation", "fibers.jl"),
        joinpath(@__DIR__, "..", "..", "src", "helpers", "helpers.jl"),
    )
    source_digest = bytes2hex(SHA.sha256(
        join((bytes2hex(SHA.sha256(read(path))) for path in source_files), "|")))
    signature = join((
        _MMF_MODAL_CACHE_SCHEMA,
        string(VERSION),
        source_digest,
        String(preset),
        repr(Float64(sim["f0"])),
        string(sim["M"]),
        string(sim["Nt"]),
        repr(Float64(sim["Δt"])),
        string(sim["β_order"]),
        repr(Float64(p.radius)),
        repr(Float64(p.core_NA)),
        repr(Float64(p.alpha)),
        string(p.nx),
        repr(Float64(p.spatial_window)),
        repr(Float64(p.Δf_THz)),
    ), "|")
    digest = bytes2hex(SHA.sha256(signature))[1:20]
    return joinpath(cache_dir,
        "mmf_$(String(preset))_m$(sim["M"])_nt$(sim["Nt"])_$(digest).npz")
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
    ut0 = fft(uω0, 1)
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
- `sim`            : simulation parameter dict (ω0, Δt, time window, ...)
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
- `Nt = 2^10`              : temporal grid (power of 2)
- `time_window = 10.0`     : time window [ps]
- `mode_weights = nothing` : if nothing, uses `default_mode_weights(M)`
- `raman_threshold = -5.0` : Raman band cutoff [THz]
- `λ0 = 1550e-9`
- `fiber_cache_dir = "results/raman/mmf/fiber_cache"`
- `auto_time_window = true` : conservatively upsize undersized windows

# Notes
- Uses `FiberLab.get_disp_sim_params` and `get_disp_fiber_params`.
- In auto mode, temporal sampling is resolved before the first modal build;
  the mode-dependent window recommendation is applied after that build.
- The GRIN eigensolver cost is amortized via a content-addressed NPZ cache
  covering wavelength, grid, modal geometry, finite-difference settings,
  Julia version, and the modal-source implementation.
"""
function setup_mmf_raman_problem(;
    preset::Symbol = :GRIN_50,
    L_fiber = 1.0,
    P_cont = 0.05,
    pulse_fwhm = 185e-15,
    pulse_rep_rate = 80.5e6,
    pulse_shape = "sech_sq",
    Nt = 2^10,
    time_window = 10.0,
    mode_weights::Union{Nothing, AbstractVector} = nothing,
    raman_threshold = -5.0,
    λ0 = 1550e-9,
    fiber_cache_dir::AbstractString = joinpath(@__DIR__, "..", "..", "results", "raman", "mmf", "fiber_cache"),
    auto_time_window::Bool = true,
)
    # PRECONDITIONS
    @assert ispow2(Nt) "Nt must be power of 2, got $Nt"
    @assert time_window > 0 "time_window must be positive"
    @assert L_fiber > 0 "L_fiber must be positive"
    @assert P_cont > 0 "P_cont must be positive"
    @assert pulse_fwhm > 0 "pulse_fwhm must be positive"
    pulse_shape = _canonical_mmf_pulse_shape(pulse_shape)

    p = get_mmf_fiber_preset(preset)
    M = p.M

    # Mode weights
    w = isnothing(mode_weights) ? default_mode_weights(M) : ComplexF64.(mode_weights)
    @assert length(w) == M "mode_weights length ($(length(w))) must equal M=$M"
    w = w ./ norm(w)

    if auto_time_window
        resolved_nt, resolved_window = _resolved_mmf_grid(
            Nt, time_window; wavelength_m=λ0)
        if resolved_nt != Nt || resolved_window != time_window
            @info @sprintf(
                "MMF auto-sizing: time_window %g→%g ps, Nt %d→%d before modal setup",
                time_window, resolved_window, Nt, resolved_nt,
            )
        end
        Nt, time_window = resolved_nt, resolved_window
    end

    function _build_with_window(Nt_local::Int, time_window_local::Real)
        sim_local = FiberLab.get_disp_sim_params(λ0, M, Nt_local, time_window_local, p.β_order)
        mkpath(fiber_cache_dir)
        cache_fname_local = _mmf_modal_cache_path(
            fiber_cache_dir, preset, p, sim_local)
        fiber_local = FiberLab.get_disp_fiber_params(
            L_fiber, p.radius, p.core_NA, p.alpha, p.nx, sim_local, cache_fname_local;
            spatial_window = p.spatial_window,
            Δf = p.Δf_THz,
            fR = p.fR,
            τ1 = p.τ1,
            τ2 = p.τ2,
        )
        fiber_local["L"] = L_fiber
        _, uω0_local = FiberLab.get_initial_state(
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
    if auto_time_window
        resolved_nt, resolved_window = _resolved_mmf_grid(
            Nt, time_window, window_rec.time_window_ps; wavelength_m=λ0)
        if resolved_window != time_window || resolved_nt != Nt
            @info @sprintf(
                "MMF auto-sizing: time_window %.1f→%.1f ps, Nt %d→%d (L=%.2fm, P=%.3fW, max|β₂|=%.2e, γeff=%.3e, Ppeak=%.2e W)",
                time_window, resolved_window, Nt, resolved_nt,
                L_fiber, P_cont, window_rec.beta2_abs_max, window_rec.gamma_effective, window_rec.peak_power_W,
            )
            Nt, time_window = resolved_nt, resolved_window
            sim, fiber, uω0, cache_fname = _build_with_window(Nt, time_window)
            window_rec = mmf_recommended_time_window(
                fiber, sim, uω0;
                L_fiber = L_fiber,
                pulse_fwhm = pulse_fwhm,
            )
        end
    elseif time_window < window_rec.time_window_ps
        @warn @sprintf(
            "MMF setup using undersized time_window=%.1f ps < recommended %.1f ps (L=%.2fm, P=%.3fW)",
            time_window, window_rec.time_window_ps, L_fiber, P_cont,
        )
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
