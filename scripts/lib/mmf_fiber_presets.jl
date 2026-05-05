"""
Multimode fiber (MMF) preset library for Session C — multimode Raman suppression.

This file defines named presets for GRIN and step-index multimode fibers plus
default input mode weights. It is the MMF counterpart to the SMF `FIBER_PRESETS`
dict in `scripts/common.jl`; SMF presets are NOT modified.

Presets expose the GRIN profile geometry (radius, NA, alpha) plus material
parameters (fR, τ1, τ2). The spatial grid and β-stencil spacing are also
preset-specific because they determine eigensolver accuracy and dispersion
Taylor-series quality.

Include guard: safe to include multiple times.
"""

using Printf

if !(@isdefined _MMF_FIBER_PRESETS_JL_LOADED)
const _MMF_FIBER_PRESETS_JL_LOADED = true

using LinearAlgebra
using Logging

# ─────────────────────────────────────────────────────────────────────────────
# Preset library
# ─────────────────────────────────────────────────────────────────────────────

"""
    MMF_FIBER_PRESETS

Dict of named multimode fiber parameter presets. Each entry is a NamedTuple with:
- `name`            : human-readable label
- `description`     : citation / source
- `radius`          : core radius [μm]
- `core_NA`         : numerical aperture
- `alpha`           : GRIN exponent (2.0 = parabolic, Inf for step-index — modeled as alpha=1e3)
- `M`               : number of scalar modes to solve for
- `nx`              : spatial eigensolver grid points per dimension
- `spatial_window`  : total grid extent [μm]
- `β_order`         : highest dispersion order in the Taylor expansion
- `Δf_THz`          : finite-difference stencil spacing for β(f) [THz]
- `fR`              : fractional Raman contribution
- `τ1`, `τ2`        : Raman response time constants [fs]

Available keys: `:GRIN_50`, `:STEP_9`.
"""
const MMF_FIBER_PRESETS = Dict(
    :GRIN_50 => (
        name            = "GRIN-50 (OM4-like)",
        description     = "50-μm core parabolic GRIN, NA=0.2, silica. Standard OM4 multimode fiber.",
        radius          = 25.0,
        core_NA         = 0.2,
        alpha           = 2.0,
        M               = 6,
        nx              = 101,
        spatial_window  = 80.0,
        β_order         = 2,
        Δf_THz          = 1.0,
        fR              = 0.18,
        τ1              = 12.2,
        τ2              = 32.0,
    ),
    :STEP_9 => (
        name            = "Step-9 (few-mode)",
        description     = "9-μm core step-index fiber, NA=0.14, silica. ~4 guided LP modes at 1550 nm.",
        radius          = 4.5,
        core_NA         = 0.14,
        alpha           = 1000.0,
        M               = 4,
        nx              = 81,
        spatial_window  = 24.0,
        β_order         = 2,
        Δf_THz          = 1.0,
        fR              = 0.18,
        τ1              = 12.2,
        τ2              = 32.0,
    ),
)

"""
    MMF_DEFAULT_MODE_WEIGHTS

Default input mode-content vector for M=6 GRIN runs:
  c_m = (0.95, 0.20, 0.20, 0.05, 0.05, 0.02)   # un-normalized
then normalized to unit L²-norm. LP01-dominant with small LP11a/b, LP21a/b
content — a realistic imperfect free-space launch into an OM4 fiber.

For presets with M != 6 the first min(M, length(weights)) entries are used and
the rest defaulted to 0.02 before normalization.
"""
const MMF_DEFAULT_MODE_WEIGHTS = let
    raw = ComplexF64[0.95, 0.20, 0.20, 0.05, 0.05, 0.02]
    raw ./ norm(raw)
end

"""
    get_mmf_fiber_preset(name::Symbol) -> NamedTuple

Look up a multimode fiber preset by name.
"""
function get_mmf_fiber_preset(name::Symbol)
    @assert haskey(MMF_FIBER_PRESETS, name) "unknown MMF preset :$name — available: $(join(keys(MMF_FIBER_PRESETS), ", "))"
    preset = MMF_FIBER_PRESETS[name]
    @debug @sprintf("MMF preset: %s — M=%d, r=%.1fμm, NA=%.2f, alpha=%.1f",
        preset.name, preset.M, preset.radius, preset.core_NA, preset.alpha)
    return preset
end

"""
    default_mode_weights(M::Int) -> Vector{ComplexF64}

Return a unit-norm mode weight vector sized for M modes. Uses the first M of
`MMF_DEFAULT_MODE_WEIGHTS` padded with 0.02 if M > 6.
"""
function default_mode_weights(M::Int)
    @assert M ≥ 1 "M must be ≥ 1, got $M"
    if M ≤ length(MMF_DEFAULT_MODE_WEIGHTS)
        w = MMF_DEFAULT_MODE_WEIGHTS[1:M]
    else
        pad = fill(ComplexF64(0.02), M - length(MMF_DEFAULT_MODE_WEIGHTS))
        w = vcat(MMF_DEFAULT_MODE_WEIGHTS, pad)
    end
    return w ./ norm(w)
end

end # include guard
