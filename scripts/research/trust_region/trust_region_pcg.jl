# scripts/trust_region_pcg.jl — Phase 34 Preconditioned CG (Steihaug-style).
#
# Adds PreconditionedCGSolver <: DirectionSolver and its solve_subproblem
# method via Julia multiple dispatch. Does NOT modify trust_region_core.jl.
#
# Mathematical structure (Nocedal-Wright §7.1 + §4.1, Morales-Nocedal 2000):
#   - Runs Steihaug CG in the M-inner-product metric via preconditioned residual z = M⁻¹r.
#   - On negative curvature `d'·H·d ≤ 0`, steps to the trust-region boundary in the
#     direction of d. (We use the Euclidean Δ as the hard cap, clamping on exit.)
#   - Returns SubproblemResult in the ORIGINAL Euclidean space:
#       pred_reduction = -(g'p + 0.5 p'·H_op(p))  (one extra HVP at exit)
#       ‖p‖₂ ≤ Δ·(1+1e-8)  (Euclidean clamp on exit)
#
# PCG inner-loop variables:
#   r   — residual (Euclidean space): r = g + H·p, starts as r = g
#   z   — preconditioned residual:    z = M⁻¹r
#   d   — search direction:           d = -z + β·d_prev
#   rTz — M-inner-product of r and z: rTz = r'z (replaces rTr in Steihaug)
#
# When :none / M===nothing: z = r, rTz = r'r → reduces exactly to Steihaug.
#
# Frozen-file contract: this file MUST NOT redefine DirectionSolver,
# SubproblemResult, _boundary_tau, or solve_subproblem as a generic function.
# Those live in trust_region_core.jl and are brought in via include.

using LinearAlgebra

include(joinpath(@__DIR__, "trust_region_core.jl"))
include(joinpath(@__DIR__, "trust_region_preconditioner.jl"))

if !(@isdefined _TRUST_REGION_PCG_JL_LOADED)
const _TRUST_REGION_PCG_JL_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# PreconditionedCGSolver struct
# ─────────────────────────────────────────────────────────────────────────────

"""
    PreconditionedCGSolver(; max_iter=20, preconditioner=:diagonal,
                             tol_forcing = g -> min(0.5, sqrt(norm(g))) * norm(g),
                             K_dct=64)

Preconditioned truncated-CG inner solver for the trust-region subproblem
    minimize m(p) = g'p + 0.5 p'Hp    subject to  ‖p‖₂ ≤ Δ

Frozen-interface-preserving subtype of DirectionSolver.

# Fields
- `max_iter::Int=20`: maximum inner CG iterations.
- `preconditioner::Symbol=:diagonal`: which preconditioner to apply.
  Supported: `:none`, `:diagonal`, `:dispersion`. `:dct_K64` is reserved for
  Plan 03 (DCT requires K HVPs to build; not implemented here).
- `tol_forcing::Function`: forcing sequence ε(g) for inner CG convergence.
  Default `min(0.5, √‖g‖)·‖g‖` gives superlinear local convergence
  (Nocedal-Wright §3.3), identical to SteihaugSolver default.
- `K_dct::Int=64`: DCT basis size (reserved for Plan 03 — unused in Plan 02).

# Usage
The `M` kwarg of `solve_subproblem` supplies the prebuilt preconditioner
callable (see `build_diagonal_precond`, `build_dispersion_precond`).
When `preconditioner == :none` OR `M === nothing`, behaves identically to
`SteihaugSolver` (unit-tested parity to ‖Δp‖₂ < 1e-8). When M is supplied,
runs PCG in the M-inner-product metric; the exit step is clamped to the
Euclidean Δ-ball to satisfy the SubproblemResult contract.

# SubproblemResult contract
- `‖p‖₂ ≤ Δ·(1+1e-8)` (Euclidean clamp applied on any exit)
- `pred_reduction ≥ 0` (recomputed via one extra H_op(p) call at exit)
- `hvps_used` includes this final HVP
"""
Base.@kwdef struct PreconditionedCGSolver <: DirectionSolver
    max_iter::Int = 20
    preconditioner::Symbol = :diagonal   # :none | :diagonal | :dct_K64 | :dispersion
    tol_forcing::Function = g -> min(0.5, sqrt(norm(g))) * norm(g)
    K_dct::Int = 64
end

# ─────────────────────────────────────────────────────────────────────────────
# solve_subproblem dispatch
# ─────────────────────────────────────────────────────────────────────────────

"""
    solve_subproblem(solver::PreconditionedCGSolver, g, H_op, Δ; M=nothing, kwargs...) -> SubproblemResult

Preconditioned truncated-CG (Steihaug-style) for the trust-region subproblem.

# Algorithm
Standard Steihaug CG with preconditioned residual `z = M⁻¹r`:
1. r = g,  z = M⁻¹r (or r if :none),  d = -z,  rTz = r'z
2. Per iteration:
   a. Hd = H_op(d); κ = d'Hd
   b. If κ ≤ 0: step to Δ-boundary in direction d → :NEGATIVE_CURVATURE
   c. α = rTz / κ;  p_new = p + α·d
   d. If ‖p_new‖ ≥ Δ: step to Δ-boundary → :BOUNDARY_HIT
   e. Commit p, update r_new = r + α·Hd,  z_new = M⁻¹r_new
   f. If √(r_new'z_new) ≤ ε: → :INTERIOR_CONVERGED
   g. β = (r_new'z_new) / (r'z);  d = -z_new + β·d
3. Exit (any code):
   - Clamp: if ‖p‖ > Δ·(1+1e-8), scale p → p·(Δ/‖p‖)
   - Recompute pred_reduction via one final H_op(p) in Euclidean space

# Preconditioner identity (`:none` path)
When `solver.preconditioner == :none` or `M === nothing`:
  z = r and rTz = r'r → the loop reduces to the exact Steihaug numerics.
  Unit tests verify ‖p_PCG - p_Steihaug‖₂ < 1e-8 on SPD quadratics.

# HVP accounting
`hvps_used` = (number of inner iterations) + 1 (final pred_reduction HVP).
Exception: `:NO_DESCENT` returns hvps_used = 0 (no H_op call made).

# Gauge safety
The incoming `g` is assumed already gauge-projected (the outer loop in
`trust_region_optimize.jl` calls gauge_fix before passing g here). Since
pointwise division in M⁻¹ does not preserve gauge projection in general,
callers may pass `proj = Π` to re-project preconditioned residuals and
search directions back into the gauge-complement subspace.
"""
function solve_subproblem(solver::PreconditionedCGSolver,
                          g::AbstractVector{<:Real},
                          H_op,
                          Δ::Real;
                          M = nothing,
                          proj = identity,
                          kwargs...)::SubproblemResult
    n = length(g)
    p = zeros(Float64, n)

    g_norm = norm(g)
    if g_norm < eps(Float64)
        return SubproblemResult(p, 0.0, :NO_DESCENT, 0, 0)
    end

    # Preconditioner dispatch: use identity when :none or M not provided
    use_M = !(solver.preconditioner === :none || M === nothing)
    M_inv = use_M ? M : identity
    proj_fn = proj

    function _apply_precond(v::AbstractVector{<:Real})
        w = use_M ? M_inv(v) : copy(v)
        return Vector{Float64}(proj_fn(w))
    end

    r = Vector{Float64}(copy(g))
    z = _apply_precond(r)
    d = Vector{Float64}(proj_fn(-z))
    ε = solver.tol_forcing(g)
    rTz = dot(r, z)
    hvps = 0

    exit_code = :MAX_ITER
    inner_iters = solver.max_iter

    for j in 1:solver.max_iter
        Hd = H_op(d)
        hvps += 1

        # Curvature check in Euclidean space (same as Steihaug)
        κ = dot(d, Hd)
        if κ <= 0
            # Negative (or zero) curvature → step to trust boundary in direction d
            τ = _boundary_tau(p, d, Δ)
            p = p .+ τ .* d
            exit_code = :NEGATIVE_CURVATURE
            inner_iters = j
            break
        end

        α = rTz / κ
        p_new = p .+ α .* d

        if norm(p_new) >= Δ
            # Step would exit Δ-ball → step to boundary
            τ = _boundary_tau(p, d, Δ)
            p = p .+ τ .* d
            exit_code = :BOUNDARY_HIT
            inner_iters = j
            break
        end

        # Commit step
        p = p_new
        r_new = r .+ α .* Hd
        z_new = _apply_precond(r_new)
        rTz_new = dot(r_new, z_new)

        # Convergence check in preconditioned norm (reduces to Euclidean when :none)
        if sqrt(abs(rTz_new)) <= ε   # abs() guards tiny negative rounding in M-space
            exit_code = :INTERIOR_CONVERGED
            inner_iters = j
            r = r_new
            z = z_new
            break
        end

        β = rTz_new / rTz
        d = Vector{Float64}(proj_fn(-z_new .+ β .* d))
        r = r_new
        z = z_new
        rTz = rTz_new
    end

    # Enforce subspace membership before the Euclidean clamp.
    p = Vector{Float64}(proj_fn(p))

    # Euclidean-norm clamp: PCG in M-space may exit slightly outside Δ-ball
    p_norm = norm(p)
    if p_norm > Δ * (1 + 1e-8)
        p = p .* (Δ / p_norm)
    end

    # Recompute pred_reduction in the ORIGINAL Euclidean metric via one final HVP.
    # This is necessary because the accumulated Hp in the loop is unreliable when
    # M ≠ I (the loop tracks r in Euclidean space but d is shaped by M⁻¹r).
    # The extra HVP is counted in hvps_used per the SubproblemResult contract.
    Hp_final = H_op(p)
    hvps += 1
    m_val = dot(g, p) + 0.5 * dot(p, Hp_final)
    pred_red = max(-m_val, 0.0)

    return SubproblemResult(p, pred_red, exit_code, inner_iters, hvps)
end

end  # include guard
