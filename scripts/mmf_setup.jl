"""
Multimode setup helper for Session C — wraps the existing GRIN fiber builder
(`MultiModeNoise.get_disp_fiber_params`) and returns the tuple of objects
needed by the MMF Raman-phase optimizer.

This is the MMF counterpart to `scripts/common.jl::setup_raman_problem`.
The SMF setup is NOT modified.

Include guard: safe to include multiple times.
"""

if !(@isdefined _MMF_SETUP_JL_LOADED)
const _MMF_SETUP_JL_LOADED = true

using LinearAlgebra
using FFTW
using Printf
using Logging
using MultiModeNoise

include(joinpath(@__DIR__, "mmf_fiber_presets.jl"))

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
    fiber_cache_dir::AbstractString = joinpath(@__DIR__, "..", "results", "raman", "phase16", "fiber_cache"),
)
    # PRECONDITIONS
    @assert ispow2(Nt) "Nt must be power of 2, got $Nt"
    @assert time_window > 0 "time_window must be positive"
    @assert L_fiber > 0 "L_fiber must be positive"
    @assert P_cont > 0 "P_cont must be positive"
    @assert pulse_fwhm > 0 "pulse_fwhm must be positive"

    p = get_mmf_fiber_preset(preset)
    M = p.M

    # sim dict (matches the SMF path structurally)
    sim = MultiModeNoise.get_disp_sim_params(λ0, M, Nt, time_window, p.β_order)

    # Fiber cache: unique per (preset, Nt, time_window) since Dω depends on these
    mkpath(fiber_cache_dir)
    cache_fname = joinpath(fiber_cache_dir,
        @sprintf("mmf_%s_nt%d_tw%g.npz", String(preset), Nt, time_window))

    # Build (or load) the GRIN fiber dict using the existing helper
    fiber = MultiModeNoise.get_disp_fiber_params(
        L_fiber, p.radius, p.core_NA, p.alpha, p.nx, sim, cache_fname;
        spatial_window = p.spatial_window,
        fR = p.fR,
        τ1 = p.τ1,
        τ2 = p.τ2,
    )
    fiber["L"] = L_fiber

    # Mode weights
    w = isnothing(mode_weights) ? default_mode_weights(M) : ComplexF64.(mode_weights)
    @assert length(w) == M "mode_weights length ($(length(w))) must equal M=$M"
    w = w ./ norm(w)

    # Initial field
    _, uω0 = MultiModeNoise.get_initial_state(
        w, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim
    )

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
    )
end

end # include guard
