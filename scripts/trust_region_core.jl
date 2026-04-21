# ═══════════════════════════════════════════════════════════════════════════════
# Phase 33 Plan 01 — Trust-region core
# ═══════════════════════════════════════════════════════════════════════════════
#
# Provides:
#   - `@enum TRExitCode` — the 7-way typed failure / convergence taxonomy
#   - `abstract type DirectionSolver` — the Phase 34 hand-off contract
#   - `SubproblemResult` — the return-shape of any `solve_subproblem` call
#   - `SteihaugSolver <: DirectionSolver` + `solve_subproblem(::SteihaugSolver, …)`
#     — Steihaug 1983 / Nocedal-Wright §7.2 truncated CG, matrix-free
#   - `update_radius(Δ, ρ, step_norm, Δ_max; ...)` — Nocedal-Wright §4.1
#
# Read-only consumer of LinearAlgebra; does NOT include common.jl, primitives,
# or the Raman oracle. All analytic arithmetic — no ODEs, no FFTs — so unit
# tests run in milliseconds.
#
# Include guard + outside-guard imports per STATE.md convention.
# ═══════════════════════════════════════════════════════════════════════════════

using LinearAlgebra

if !(@isdefined _TRUST_REGION_CORE_JL_LOADED)
const _TRUST_REGION_CORE_JL_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# Typed exit codes
# ─────────────────────────────────────────────────────────────────────────────
#
# These are mutually-exclusive. Every run of `optimize_spectral_phase_tr`
# returns exactly one. Downstream telemetry uses these as the TERMINAL state
# record; rejection-by-cause histograms live at the iteration level and use
# per-CG-iter :INTERIOR_CONVERGED / :BOUNDARY_HIT / :NEGATIVE_CURVATURE /
# :MAX_ITER / :NO_DESCENT symbols instead.

@enum TRExitCode begin
    CONVERGED_2ND_ORDER          # ‖g‖<g_tol AND λ_min > H_tol
    CONVERGED_1ST_ORDER_SADDLE   # ‖g‖<g_tol AND λ_min < H_tol, neg-curv escape failed
    RADIUS_COLLAPSE              # Δ < Δ_min
    MAX_ITER                     # hit max_iter, still improving
    MAX_ITER_STALLED             # hit max_iter, no improvement over stall window
    NAN_IN_OBJECTIVE             # J(φ+p) = NaN or Inf
    GAUGE_LEAK                   # ‖P_null · p‖ > 1e-8·‖p‖ — bug, not a result
end

# ─────────────────────────────────────────────────────────────────────────────
# DirectionSolver trait + concrete result shape
# ─────────────────────────────────────────────────────────────────────────────

abstract type DirectionSolver end

"""
    SubproblemResult(p, pred_reduction, exit_code, inner_iters, hvps_used)

Return from any `solve_subproblem(solver, g, H_op, Δ; ...)`.

- `p::Vector{Float64}`          — approximate subproblem solution, ‖p‖ ≤ Δ·(1+1e-8)
- `pred_reduction::Float64`     — `-m(p) = -(g'p + 0.5 p' H p) ≥ 0`
- `exit_code::Symbol`           — one of :INTERIOR_CONVERGED | :BOUNDARY_HIT |
                                    :NEGATIVE_CURVATURE | :MAX_ITER | :NO_DESCENT
- `inner_iters::Int`            — iterations taken
- `hvps_used::Int`              — HVPs consumed (= 1 per CG iter for Steihaug)
"""
struct SubproblemResult
    p::Vector{Float64}
    pred_reduction::Float64
    exit_code::Symbol
    inner_iters::Int
    hvps_used::Int
end

# ─────────────────────────────────────────────────────────────────────────────
# Steihaug solver
# ─────────────────────────────────────────────────────────────────────────────

"""
    SteihaugSolver(; max_iter=20, tol_forcing=g->min(0.5, sqrt(norm(g)))*norm(g))

Steihaug 1983 truncated-CG inner solver for the trust-region subproblem
    minimize m(p) = g'p + 0.5 p' H p    subject to  ‖p‖ ≤ Δ

Matrix-free: consumes `H_op::Function` (v → H·v). Handles indefinite H by
detecting `d'Hd ≤ 0` and stepping to the boundary in the negative-curvature
direction. Returns early with `:NO_DESCENT` when `‖g‖ < eps()` so the outer
loop can exit cleanly.

Forcing sequence `tol_forcing(g) = min(0.5, √‖g‖)·‖g‖` gives superlinear local
convergence (Nocedal-Wright §3.3).
"""
Base.@kwdef struct SteihaugSolver <: DirectionSolver
    max_iter::Int = 20
    tol_forcing::Function = g -> min(0.5, sqrt(norm(g))) * norm(g)
end

"""
    _boundary_tau(p, d, Δ) -> τ > 0

Positive root of  ‖p + τ d‖² = Δ²:

    τ = (−(p'd) + √((p'd)² + ‖d‖²·(Δ² − ‖p‖²))) / ‖d‖²

PRECONDITION: ‖p‖ ≤ Δ (so the discriminant is ≥ 0) and ‖d‖ > 0.
"""
function _boundary_tau(p::AbstractVector, d::AbstractVector, Δ::Real)
    dd = dot(d, d)
    @assert dd > 0 "_boundary_tau: zero-norm direction d"
    pd = dot(p, d)
    pp = dot(p, p)
    disc = pd * pd + dd * (Δ * Δ - pp)
    @assert disc >= -1e-14 "_boundary_tau: negative discriminant — p outside trust region? (disc=$disc)"
    disc_c = max(disc, 0.0)   # clamp tiny rounding
    τ = (-pd + sqrt(disc_c)) / dd
    return τ
end

"""
    solve_subproblem(solver::SteihaugSolver, g, H_op, Δ; kwargs...) -> SubproblemResult

Steihaug truncated CG. See struct docstring.

# Guarantees
- `‖p‖ ≤ Δ · (1 + 1e-8)` on return.
- `pred_reduction ≥ 0` (guaranteed by construction; degenerate `:NO_DESCENT`
  returns exactly 0).
- Exactly one HVP per inner iteration (no duplicate evals).

# Predicted reduction accounting
We maintain a running `Hp = H·p` accumulator by updating `Hp += α·Hd` every
time we commit `p ← p + α d`. For a boundary exit along `d` with scalar `τ`,
`Hp_final = Hp + τ·Hd` and we evaluate
    m(p_final) = g'p_final + 0.5 p_final' Hp_final.
The returned `pred_reduction = -m(p_final)`; a clamp to 0 guards against
tiny negative rounding from inexact CG termination near the boundary.
"""
function solve_subproblem(solver::SteihaugSolver,
                          g::AbstractVector{<:Real},
                          H_op,
                          Δ::Real;
                          kwargs...)::SubproblemResult
    n = length(g)
    p = zeros(Float64, n)
    Hp = zeros(Float64, n)

    g_norm = norm(g)
    if g_norm < eps(Float64)
        return SubproblemResult(p, 0.0, :NO_DESCENT, 0, 0)
    end

    r = Vector{Float64}(copy(g))            # residual = g + H·p, starts = g
    d = -Vector{Float64}(copy(g))           # search direction
    ε = solver.tol_forcing(g)
    rTr = dot(r, r)
    hvps = 0

    for j in 1:solver.max_iter
        Hd = H_op(d)
        hvps += 1

        κ = dot(d, Hd)
        if κ <= 0
            # Negative (or zero) curvature → step to trust boundary.
            τ = _boundary_tau(p, d, Δ)
            p_bd = p .+ τ .* d
            Hp_bd = Hp .+ τ .* Hd
            m_val = dot(g, p_bd) + 0.5 * dot(p_bd, Hp_bd)
            pred_red = max(-m_val, 0.0)
            return SubproblemResult(p_bd, pred_red, :NEGATIVE_CURVATURE, j, hvps)
        end

        α = rTr / κ
        p_new = p .+ α .* d

        if norm(p_new) >= Δ
            τ = _boundary_tau(p, d, Δ)
            p_bd = p .+ τ .* d
            Hp_bd = Hp .+ τ .* Hd
            m_val = dot(g, p_bd) + 0.5 * dot(p_bd, Hp_bd)
            pred_red = max(-m_val, 0.0)
            return SubproblemResult(p_bd, pred_red, :BOUNDARY_HIT, j, hvps)
        end

        # Commit the step
        p = p_new
        Hp = Hp .+ α .* Hd
        r_new = r .+ α .* Hd
        rTr_new = dot(r_new, r_new)

        if sqrt(rTr_new) <= ε
            # Interior convergence
            m_val = dot(g, p) + 0.5 * dot(p, Hp)
            pred_red = max(-m_val, 0.0)
            return SubproblemResult(p, pred_red, :INTERIOR_CONVERGED, j, hvps)
        end

        β = rTr_new / rTr
        d = -r_new .+ β .* d
        r = r_new
        rTr = rTr_new
    end

    # Fell through max_iter without either interior convergence or boundary hit
    m_val = dot(g, p) + 0.5 * dot(p, Hp)
    pred_red = max(-m_val, 0.0)
    return SubproblemResult(p, pred_red, :MAX_ITER, solver.max_iter, hvps)
end

# ─────────────────────────────────────────────────────────────────────────────
# Radius update — Nocedal-Wright Algorithm 4.1
# ─────────────────────────────────────────────────────────────────────────────

"""
    update_radius(Δ, ρ, step_norm, Δ_max;
                  η1=0.25, η2=0.75, γ_shrink=0.25, γ_grow=2.0) -> Δ_next

Classical trust-region radius update (Nocedal & Wright 2nd ed., §4.1):

- `ρ < η1`:                             shrink to `γ_shrink · ‖p‖`
- `ρ > η2` AND `‖p‖ ≥ 0.9·Δ`:          grow to `min(γ_grow · Δ, Δ_max)`
- otherwise:                            keep `Δ`

The boundary threshold `‖p‖ ≥ 0.9·Δ` is the standard Nocedal-Wright "step is
on the boundary" indicator. Without it we would grow Δ even when the
subproblem solver converged INSIDE the trust region (and had no reason to
want a larger Δ), which empirically over-inflates the radius on convex
regions and is corrected by the next shrink when the next step mis-predicts.
Using 0.9 (not 1.0) tolerates Steihaug's `1 + 1e-8` boundary slack.
"""
function update_radius(Δ::Real, ρ::Real, step_norm::Real, Δ_max::Real;
                       η1::Real = 0.25,
                       η2::Real = 0.75,
                       γ_shrink::Real = 0.25,
                       γ_grow::Real = 2.0)
    if ρ < η1
        return γ_shrink * step_norm
    elseif ρ > η2 && step_norm >= 0.9 * Δ
        return min(γ_grow * Δ, Δ_max)
    else
        return Δ
    end
end

end  # include guard
