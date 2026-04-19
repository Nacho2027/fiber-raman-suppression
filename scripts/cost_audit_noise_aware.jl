# scripts/cost_audit_noise_aware.jl
# ═══════════════════════════════════════════════════════════════════════════════
# Phase 16 Plan 01 — D-04: Noise-aware cost wrapper (curvature penalty)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Adds a curvature penalty localized to the Raman band on top of the EXISTING
# cost_and_gradient (scripts/raman_optimization.jl:52) WITHOUT modifying it.
# Pattern mirrors the λ_gdd analytic-gradient block at
# raman_optimization.jl:114-128.
#
#   Penalty P(φ) = (1 / N_band) · Σ_m Σ_{i ∈ band, 2≤i≤Nt-1}
#                     (φ[i+1,m] - 2φ[i,m] + φ[i-1,m])² / Δω⁴
#
# D-04 (CONTEXT.md): "⟨|∂²φ/∂ω²|²⟩_band with N_band normalization".
#
# CRITICAL INVARIANTS (enforced by tests):
#   - γ_curv == 0 → returns exactly (J_linear, grad_linear) from
#     cost_and_gradient (byte-identical, no floating-point re-association).
#   - Analytic gradient passes a Taylor-remainder test at slope ≈ 2.
# ═══════════════════════════════════════════════════════════════════════════════

if @isdefined(_COST_AUDIT_NOISE_AWARE_LOADED) && _COST_AUDIT_NOISE_AWARE_LOADED
    # Already loaded; no-op.
else

using Logging
using Printf

const _COST_AUDIT_NOISE_AWARE_LOADED = true
const CA_NA_VERSION = "1.0.0"
const CA_DEFAULT_GAMMA_CURV = 1e-4
const CA_GAMMA_CURV_FLOOR = 1e-6
const CA_GAMMA_CURV_CEIL  = 1e-2
const CA_CALIB_TARGET_FRAC = 0.1

# Require cost_and_gradient (from scripts/raman_optimization.jl) to be in scope.
# Tests include this file after raman_optimization.jl. If run standalone, fail loudly.
if !(@isdefined cost_and_gradient)
    error("cost_audit_noise_aware.jl requires cost_and_gradient in scope. " *
          "Include scripts/raman_optimization.jl first.")
end

"""
    curvature_penalty(φ, band_mask, sim) -> Float64

Compute P(φ) = (1/N_band) · Σ_m Σ_{i ∈ band, 2≤i≤Nt-1}
                 (φ[i+1,m] - 2φ[i,m] + φ[i-1,m])² / Δω⁴

Pure helper — no gradient. Used by `calibrate_gamma_curv`.
"""
function curvature_penalty(φ::AbstractMatrix{<:Real},
                           band_mask::AbstractVector{Bool}, sim::AbstractDict)
    Nt = size(φ, 1); M = size(φ, 2)
    Δω = 2π / (Nt * sim["Δt"])
    inv_Δω4 = 1.0 / Δω^4
    N_band = count(band_mask)
    @assert N_band > 0 "band_mask is empty"
    P = 0.0
    @inbounds for m in 1:M
        for i in 2:(Nt-1)
            if band_mask[i]
                d2 = φ[i+1, m] - 2.0 * φ[i, m] + φ[i-1, m]
                P += d2 * d2 * inv_Δω4 / N_band
            end
        end
    end
    return P
end

"""
    cost_and_gradient_curvature(φ, uω0, fiber, sim, band_mask;
                                γ_curv, λ_gdd=0.0, λ_boundary=0.0,
                                log_cost=false, uω0_shaped=nothing,
                                uωf_buffer=nothing) -> (J_total, grad_total)

D-04 cost. Wraps `cost_and_gradient` (unchanged) and adds the Raman-band
curvature penalty with analytic gradient.

When `γ_curv == 0` the return tuple is byte-identical to the inner call
(no floating-point re-association). REGRESSION INVARIANT tested by
`test_cost_audit_unit.jl::d04_zero_penalty`.

# PRECONDITIONS
- `γ_curv ≥ 0`
- `size(φ) == size(uω0)`
- `length(band_mask) == size(φ, 1)`
- `count(band_mask) ≥ 1`
"""
function cost_and_gradient_curvature(φ::AbstractMatrix{<:Real},
                                      uω0, fiber, sim,
                                      band_mask::AbstractVector{Bool};
                                      γ_curv::Real,
                                      λ_gdd::Real = 0.0,
                                      λ_boundary::Real = 0.0,
                                      log_cost::Bool = false,
                                      uω0_shaped = nothing,
                                      uωf_buffer = nothing)
    @assert γ_curv ≥ 0 "γ_curv must be non-negative, got $γ_curv"
    @assert size(φ) == size(uω0) "φ shape mismatch"
    @assert length(band_mask) == size(φ, 1) "band_mask length mismatch"

    J_inner, grad_inner = cost_and_gradient(φ, uω0, fiber, sim, band_mask;
        uω0_shaped = uω0_shaped, uωf_buffer = uωf_buffer,
        λ_gdd = λ_gdd, λ_boundary = λ_boundary, log_cost = log_cost)

    # γ_curv == 0 → byte-identical return (no copy, no reassociation).
    if γ_curv == 0
        return (J_inner, grad_inner)
    end

    Nt = size(φ, 1); M = size(φ, 2)
    Δω = 2π / (Nt * sim["Δt"])
    inv_Δω4 = 1.0 / Δω^4
    N_band = count(band_mask)
    @assert N_band ≥ 1

    # Analytic curvature penalty + gradient. Pattern: raman_optimization.jl:114-128,
    # but normalized by N_band and using Δω⁻⁴ (second-derivative squared).
    grad_total = copy(grad_inner)
    P = 0.0
    norm_factor = 1.0 / (N_band * Δω^4)
    @inbounds for m in 1:M
        for i in 2:(Nt-1)
            if band_mask[i]
                d2 = φ[i+1, m] - 2.0 * φ[i, m] + φ[i-1, m]
                P += d2 * d2 * inv_Δω4 / N_band
                # ∂(d²)²/∂φ[i-1] = 2·d², ∂/∂φ[i] = -4·d², ∂/∂φ[i+1] = 2·d²
                coeff = 2.0 * d2 * norm_factor
                grad_total[i-1, m] += γ_curv * coeff
                grad_total[i,   m] -= 2.0 * γ_curv * coeff
                grad_total[i+1, m] += γ_curv * coeff
            end
        end
    end
    J_total = J_inner + γ_curv * P

    @assert isfinite(J_total) "curvature-augmented J is non-finite: $J_total"
    @assert all(isfinite, grad_total) "curvature-augmented grad is non-finite"

    return (J_total, grad_total)
end

"""
    calibrate_gamma_curv(φ0, uω0, fiber, sim, band_mask;
                         target_fraction=0.1, fallback=1e-4) -> Float64

Choose γ_curv so that γ_curv · P(φ0) ≈ target_fraction · J(φ0). If the resulting
value is outside `[CA_GAMMA_CURV_FLOOR, CA_GAMMA_CURV_CEIL]`, return `fallback`
with a warning.

Addresses Research Pitfall 3: random φ₀ curvature is not a physically meaningful
baseline and can produce pathological γ_curv values.
"""
function calibrate_gamma_curv(φ0::AbstractMatrix{<:Real},
                              uω0, fiber, sim, band_mask::AbstractVector{Bool};
                              target_fraction::Real = CA_CALIB_TARGET_FRAC,
                              fallback::Real = CA_DEFAULT_GAMMA_CURV)
    J0, _ = cost_and_gradient(φ0, uω0, fiber, sim, band_mask;
        log_cost = false, λ_gdd = 0.0, λ_boundary = 0.0)
    P0 = curvature_penalty(φ0, band_mask, sim)
    if !isfinite(P0) || P0 ≤ 0
        @warn @sprintf("calibrate_gamma_curv: P(φ0)=%.3e invalid; using fallback %.3e",
                       P0, fallback)
        return fallback
    end
    γ = target_fraction * J0 / P0
    @info @sprintf("calibrate_gamma_curv: J0=%.3e P0=%.3e → γ_curv=%.3e (target %.0f%%)",
                   J0, P0, γ, 100 * target_fraction)
    if !(CA_GAMMA_CURV_FLOOR ≤ γ ≤ CA_GAMMA_CURV_CEIL)
        @warn @sprintf("γ_curv=%.3e outside sanity range [%.0e, %.0e]; falling back to %.3e",
                       γ, CA_GAMMA_CURV_FLOOR, CA_GAMMA_CURV_CEIL, fallback)
        return fallback
    end
    return γ
end

end  # include guard
