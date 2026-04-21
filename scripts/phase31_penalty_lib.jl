# scripts/phase31_penalty_lib.jl — Phase 31 penalty library
#
# All penalties accumulate into (J_total, grad_total) BEFORE the log_cost
# rescale in cost_and_gradient (raman_optimization.jl:167-172). This is the
# same contract as the existing GDD / boundary penalties. Per the dB-linear
# fix (project memory project_dB_linear_fix.md) and Phase 27 second-opinion
# Pitfall 1, callers that wrap cost_and_gradient with these penalties MUST
# ensure the penalty contribution is added to the LINEAR-cost gradient, and
# the subsequent log_scale multiplication then applies uniformly to physics +
# penalty. See Pitfall 1 of 31-RESEARCH.md for the annealing side-effect.
#
# Signature convention (shared across all four penalties):
#
#     apply_<name>!(J_total::Ref{Float64},
#                    grad_total::AbstractMatrix{<:Real},
#                    φ::AbstractMatrix{<:Real},
#                    bw_mask::AbstractVector{Bool};
#                    λ::Real, kwargs...) -> J_penalty::Float64
#
# Mutating: `J_total[]` and `grad_total` updated in place.
# Returns the scalar penalty contribution (for `breakdown` dict recording).
# Short-circuits and returns 0.0 when `λ == 0`.
#
# Include guard: _PHASE31_PENALTY_LIB_JL_LOADED.

using LinearAlgebra
using Statistics
using FFTW

if !(@isdefined _PHASE31_PENALTY_LIB_JL_LOADED)
const _PHASE31_PENALTY_LIB_JL_LOADED = true

const P31_PENALTY_LIB_VERSION = "1.0.0"
const P31_TV_EPSILON = 1e-6       # smooth-L1 regularizer for TV
const P31_DCT_L1_EPSILON = 1e-6   # smooth-L1 regularizer for DCT sparsity

# ─────────────────────────────────────────────────────────────────────────────
# apply_tikhonov_phi! — bandwidth-masked variance penalty on φ
# ─────────────────────────────────────────────────────────────────────────────

"""
    apply_tikhonov_phi!(J_total, grad_total, φ, bw_mask; λ) -> J_penalty

Bandwidth-masked Tikhonov (L₂) regularizer on the phase `φ` itself:

    R(φ) = λ · (1 / N_bw) · Σ_{i ∈ bw} (φ_i - φ̄)²

where `φ̄ = mean(φ[bw_mask])` per mode. Gauge-aware: subtracting the mean
cancels the constant (C) gauge mode but does NOT remove the linear (α·ω)
mode. For gauge-free downstream use, still recommended to call gauge_fix
before reporting simplicity metrics.

Gradient (per mode, for i ∈ bw):
    ∂R/∂φ_i = 2λ/N_bw · (1 - 1/N_bw) · (φ_i - φ̄)
         ≈ 2λ/N_bw · (φ_i - φ̄)   for N_bw ≫ 1
Gradient is exactly zero outside `bw_mask`.

# Applied BEFORE log_cost rescale — grad contributions are multiplied by
# log_scale in the downstream cost_and_gradient block.
"""
function apply_tikhonov_phi!(J_total::Ref{Float64},
                              grad_total::AbstractMatrix{<:Real},
                              φ::AbstractMatrix{<:Real},
                              bw_mask::AbstractVector{Bool};
                              λ::Real)
    # PRECONDITIONS
    @assert λ ≥ 0 "λ must be non-negative, got $λ"
    @assert size(grad_total) == size(φ) "grad_total size $(size(grad_total)) ≠ φ size $(size(φ))"
    @assert length(bw_mask) == size(φ, 1) "bw_mask length $(length(bw_mask)) ≠ φ rows $(size(φ, 1))"

    λ == 0 && return 0.0

    Nt, M = size(φ)
    idx = findall(bw_mask)
    N_bw = length(idx)
    N_bw < 2 && return 0.0

    inv_Nbw = 1.0 / N_bw
    J_pen = 0.0
    for m in 1:M
        φ_b = @view φ[idx, m]
        φ̄ = mean(φ_b)
        dev = φ_b .- φ̄
        J_pen += λ * inv_Nbw * sum(dev .^ 2)
        # ∂/∂φ_k of (1/N) Σ_j (φ_j - φ̄)² = (2/N)·(φ_k - φ̄):
        # Derivation: Σ_j (φ_j - φ̄)² includes an implicit dependence of φ̄ on
        # every φ_j. Taking the full derivative, the chain-rule term cancels
        # because Σ_j (φ_j - φ̄) = 0 by construction. So the coefficient is
        # simply 2λ/N (no extra (1 - 1/N) correction — gradient FD check
        # confirmed).
        coeff = 2.0 * λ * inv_Nbw
        for (k, i) in enumerate(idx)
            grad_total[i, m] += coeff * dev[k]
        end
    end

    # POSTCONDITIONS
    @assert isfinite(J_pen) "tikhonov penalty not finite: $J_pen"
    @assert all(isfinite, grad_total) "grad_total contains NaN/Inf after tikhonov"

    J_total[] += J_pen
    return J_pen
end

# ─────────────────────────────────────────────────────────────────────────────
# apply_tod_curvature! — third-derivative (TOD) penalty via 4-point stencil
# ─────────────────────────────────────────────────────────────────────────────

"""
    apply_tod_curvature!(J_total, grad_total, φ, bw_mask; λ, sim) -> J_penalty

Third-derivative (TOD) curvature penalty:

    R(φ) = λ · (1 / Δω⁵) · Σ_{i: [i-1, i, i+1, i+2] ⊂ bw}  (φ_{i+2} - 3φ_{i+1} + 3φ_i - φ_{i-1})²

Uses the 4-point forward stencil `[+1, -3, +3, -1]` for ∂³φ/∂ω³. Scaled by
Δω⁻⁵ (Δω cubed for the derivative squared + Δω for the sum→integral scaling)
to make the penalty roughly N-independent.

Gradient per stencil window at reference index `i`:
    Let d3 = φ_{i+2} - 3φ_{i+1} + 3φ_i - φ_{i-1}.
    scalar   = 2λ · inv_Δω5 · d3
    grad[i-1] += scalar · (-1)
    grad[i  ] += scalar · (+3)
    grad[i+1] += scalar · (-3)
    grad[i+2] += scalar · (+1)

Only applied when ALL four stencil points lie inside the bandwidth mask.

# Applied BEFORE log_cost rescale.
"""
function apply_tod_curvature!(J_total::Ref{Float64},
                               grad_total::AbstractMatrix{<:Real},
                               φ::AbstractMatrix{<:Real},
                               bw_mask::AbstractVector{Bool};
                               λ::Real,
                               sim::Dict)
    # PRECONDITIONS
    @assert λ ≥ 0 "λ must be non-negative, got $λ"
    @assert size(grad_total) == size(φ) "grad_total size mismatch"
    @assert length(bw_mask) == size(φ, 1) "bw_mask length mismatch"
    @assert haskey(sim, "Δt") "sim missing Δt"

    λ == 0 && return 0.0

    Nt, M = size(φ)
    Δω = 2π / (Nt * sim["Δt"])
    inv_Δω5 = 1.0 / Δω^5

    J_pen = 0.0
    for m in 1:M
        for i in 2:(Nt - 2)
            # Stencil: φ[i-1], φ[i], φ[i+1], φ[i+2]
            (bw_mask[i - 1] && bw_mask[i] && bw_mask[i + 1] && bw_mask[i + 2]) || continue
            d3 = φ[i + 2, m] - 3 * φ[i + 1, m] + 3 * φ[i, m] - φ[i - 1, m]
            J_pen += λ * inv_Δω5 * d3^2
            coeff = 2.0 * λ * inv_Δω5 * d3
            grad_total[i - 1, m] += coeff * (-1.0)
            grad_total[i,     m] += coeff * ( 3.0)
            grad_total[i + 1, m] += coeff * (-3.0)
            grad_total[i + 2, m] += coeff * ( 1.0)
        end
    end

    # POSTCONDITIONS
    @assert isfinite(J_pen) "tod penalty not finite"
    @assert all(isfinite, grad_total) "grad_total contains NaN/Inf after tod"

    J_total[] += J_pen
    return J_pen
end

# ─────────────────────────────────────────────────────────────────────────────
# apply_tv_phi! — smooth-L1 total variation of φ
# ─────────────────────────────────────────────────────────────────────────────

"""
    apply_tv_phi!(J_total, grad_total, φ, bw_mask; λ) -> J_penalty

Smooth-L1 total variation on φ:

    R(φ) = λ · Σ_{pairs (i, i+1) with both ∈ bw} √((φ_{i+1} - φ_i)² + ε²)

ε = P31_TV_EPSILON (1e-6). Gradient per pair:
    d = φ_{i+1} - φ_i;  s = √(d² + ε²)
    grad[i+1] += λ · d/s
    grad[i]   -= λ · d/s

Pattern copied from amplitude_optimization.jl:107-128, adapted to phase and
restricted to bandwidth-adjacent pairs.

# Applied BEFORE log_cost rescale.
"""
function apply_tv_phi!(J_total::Ref{Float64},
                        grad_total::AbstractMatrix{<:Real},
                        φ::AbstractMatrix{<:Real},
                        bw_mask::AbstractVector{Bool};
                        λ::Real)
    # PRECONDITIONS
    @assert λ ≥ 0 "λ must be non-negative, got $λ"
    @assert size(grad_total) == size(φ) "grad_total size mismatch"
    @assert length(bw_mask) == size(φ, 1) "bw_mask length mismatch"

    λ == 0 && return 0.0

    Nt, M = size(φ)
    ε = P31_TV_EPSILON
    ε2 = ε^2

    J_pen = 0.0
    for m in 1:M
        for i in 1:(Nt - 1)
            (bw_mask[i] && bw_mask[i + 1]) || continue
            d = φ[i + 1, m] - φ[i, m]
            s = sqrt(d * d + ε2)
            J_pen += λ * s
            ds = λ * d / s
            grad_total[i + 1, m] += ds
            grad_total[i,     m] -= ds
        end
    end

    # POSTCONDITIONS
    @assert isfinite(J_pen) "tv penalty not finite"
    @assert all(isfinite, grad_total) "grad_total contains NaN/Inf after tv"

    J_total[] += J_pen
    return J_pen
end

# ─────────────────────────────────────────────────────────────────────────────
# apply_dct_l1! — smooth-L1 on DCT coefficients of φ
# ─────────────────────────────────────────────────────────────────────────────

"""
    apply_dct_l1!(J_total, grad_total, φ, bw_mask; λ, B_dct) -> J_penalty

Smooth-L1 penalty on the DCT coefficients of `φ`:

    c = B_dct' * φ      (per mode)
    R(φ) = λ · Σ_k √(c_k² + ε²)

with ε = P31_DCT_L1_EPSILON (1e-6). Gradient:

    g_k = λ · c_k / √(c_k² + ε²)      (subgradient of smooth-L1)
    ∂R/∂φ = B_dct * g                 (adjoint of the DCT analysis op)

`B_dct` is passed in as a kwarg so the caller builds it once (e.g. via
`build_phase_basis(Nt, Nt; kind=:dct)` restricted or full). The columns
need not be orthonormal — the analysis-synthesis pair used here is the
same matrix, so `B_dct'` is the analysis operator and `B_dct` is the
synthesis operator of the same frame.

# Applied BEFORE log_cost rescale.
"""
function apply_dct_l1!(J_total::Ref{Float64},
                       grad_total::AbstractMatrix{<:Real},
                       φ::AbstractMatrix{<:Real},
                       bw_mask::AbstractVector{Bool};
                       λ::Real,
                       B_dct::AbstractMatrix{<:Real})
    # PRECONDITIONS
    @assert λ ≥ 0 "λ must be non-negative, got $λ"
    @assert size(grad_total) == size(φ) "grad_total size mismatch"
    @assert length(bw_mask) == size(φ, 1) "bw_mask length mismatch"
    @assert size(B_dct, 1) == size(φ, 1) "B_dct rows $(size(B_dct, 1)) ≠ φ rows $(size(φ, 1))"

    λ == 0 && return 0.0

    Nt, M = size(φ)
    K = size(B_dct, 2)
    ε2 = P31_DCT_L1_EPSILON^2

    J_pen = 0.0
    for m in 1:M
        φ_col = @view φ[:, m]
        c = B_dct' * φ_col                       # length K
        s = sqrt.(c .^ 2 .+ ε2)
        J_pen += λ * sum(s)
        g = @. λ * c / s                         # length K
        # ∂R/∂φ contribution for mode m: B_dct * g
        grad_contrib = B_dct * g                 # length Nt
        @. grad_total[:, m] += grad_contrib
    end

    # POSTCONDITIONS
    @assert isfinite(J_pen) "dct_l1 penalty not finite"
    @assert all(isfinite, grad_total) "grad_total contains NaN/Inf after dct_l1"

    J_total[] += J_pen
    return J_pen
end

end  # _PHASE31_PENALTY_LIB_JL_LOADED
