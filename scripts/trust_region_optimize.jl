# ═══════════════════════════════════════════════════════════════════════════════
# Phase 33 Plan 01 — Trust-region outer loop: `optimize_spectral_phase_tr`
# ═══════════════════════════════════════════════════════════════════════════════
#
# Top-level entry point. Parallels `optimize_spectral_phase` from
# scripts/raman_optimization.jl but swaps L-BFGS + strong-Wolfe for
# trust-region Newton with Steihaug inner solve. Does NOT modify the L-BFGS
# path — both coexist.
#
# The result struct has a `.minimizer` field (Optim.jl parity) so downstream
# `save_standard_set(...)` code works unchanged.
#
# Design:
#   1. Build a cost+grad oracle around `cost_and_gradient` from
#      raman_optimization.jl, with log_cost / λ_gdd / λ_boundary as user
#      parameters. No modification to raman_optimization.jl.
#   2. Gauge-project `g` via `gauge_fix` at every iteration. Assert
#      `‖p − gauge_fix(p)‖ ≤ 1e-8·‖p‖` on every accepted step; violation →
#      GAUGE_LEAK.
#   3. Matrix-free H_op wraps `fd_hvp` with the Phase 27 adaptive ε rule:
#      `ε_hvp = √(eps·max(1, ‖g‖)) / max(1, ‖v‖)`.
#   4. λ_min / λ_max probed via Arpack :SR / :LR, filtering out gauge modes by
#      cosine similarity against `1` and `ω − ω̄`. Cadence configurable.
# ═══════════════════════════════════════════════════════════════════════════════

using LinearAlgebra
using Statistics
using Random
using Arpack

include(joinpath(@__DIR__, "trust_region_core.jl"))
include(joinpath(@__DIR__, "trust_region_telemetry.jl"))
include(joinpath(@__DIR__, "phase13_hvp.jl"))          # brings phase13_primitives + common
include(joinpath(@__DIR__, "determinism.jl"))

if !(@isdefined _TRUST_REGION_OPTIMIZE_JL_LOADED)
const _TRUST_REGION_OPTIMIZE_JL_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# Result struct (Optim.jl parity)
# ─────────────────────────────────────────────────────────────────────────────

"""
    TrustRegionResult

Return from `optimize_spectral_phase_tr`. The `minimizer` field name is
MANDATORY: downstream `save_standard_set(...)` (see scripts/standard_images.jl)
and every existing plotting path expects `.minimizer` (Optim.jl convention).
"""
struct TrustRegionResult
    minimizer::Vector{Float64}
    J_final::Float64
    exit_code::TRExitCode
    iterations::Int
    hvps_total::Int
    grad_calls_total::Int
    forward_only_calls_total::Int
    wall_time_s::Float64
    telemetry::Vector{TRIterationRecord}
    lambda_min_final::Float64
    lambda_max_final::Float64
end

# ─────────────────────────────────────────────────────────────────────────────
# Oracle abstraction — a thin (cost_fn, grad_fn) pair over user-provided
# (uω0, fiber, sim, band_mask). For the Raman physics path we lazy-load
# cost_and_gradient via `Base.invokelatest`. For the analytic-quadratic test
# path the caller injects their own (cost_fn, grad_fn) directly.
# ─────────────────────────────────────────────────────────────────────────────

"""
    RamanOracle(cost_fn, grad_fn) — abstract pair wrapping a cost + gradient oracle.

- `cost_fn(φ::Vector{Float64}) -> Float64`
- `grad_fn(φ::Vector{Float64}) -> Vector{Float64}`

Used internally so tests can inject synthetic oracles without touching
the Raman physics setup.
"""
struct RamanOracle
    cost_fn::Function
    grad_fn::Function
end

"""
    build_raman_oracle(uω0, fiber, sim, band_mask; log_cost, λ_gdd, λ_boundary)
        -> RamanOracle

Construct a cost+gradient oracle over the Raman physics problem. Uses
`cost_and_gradient` from scripts/raman_optimization.jl (loaded lazily via
`Base.invokelatest` to sidestep Julia 1.12 world-age semantics, same pattern
as `build_oracle` in phase13_hvp.jl).

Neither `uω0_shaped` nor `uωf_buffer` is cached — we pass `nothing` so
`cost_and_gradient` allocates per call. This is the cleanest choice for the
TR path: cost-only forward-solve evaluations (`J_trial`) don't populate the
buffer, so reusing it across the grad/cost split would alias.
"""
function build_raman_oracle(uω0, fiber, sim, band_mask;
                            log_cost::Bool = false,
                            λ_gdd::Real = 0.0,
                            λ_boundary::Real = 0.0)
    if !isdefined(Main, :cost_and_gradient)
        @eval Main include($(joinpath(@__DIR__, "raman_optimization.jl")))
    end
    Nt = sim["Nt"]; M = sim["M"]
    fiber["zsave"] = nothing

    function cost_fn(φ_flat::AbstractVector{<:Real})
        φ_mat = reshape(copy(φ_flat), Nt, M)
        J, _ = Base.invokelatest(Main.cost_and_gradient,
            φ_mat, uω0, fiber, sim, band_mask;
            log_cost = log_cost, λ_gdd = λ_gdd, λ_boundary = λ_boundary)
        return Float64(J)
    end
    function grad_fn(φ_flat::AbstractVector{<:Real})
        φ_mat = reshape(copy(φ_flat), Nt, M)
        _, g = Base.invokelatest(Main.cost_and_gradient,
            φ_mat, uω0, fiber, sim, band_mask;
            log_cost = log_cost, λ_gdd = λ_gdd, λ_boundary = λ_boundary)
        return vec(copy(g))
    end
    return RamanOracle(cost_fn, grad_fn)
end

# ─────────────────────────────────────────────────────────────────────────────
# Gauge projection helpers (wrap phase13_primitives.gauge_fix)
# ─────────────────────────────────────────────────────────────────────────────

"""
    _project_gauge(v, band_mask, omega) -> Vector{Float64}

Return the projection of `v` onto the gauge-complement subspace (the range of
`I − P_null` where `P_null = span{𝟙, ω − ω̄}` on the input band). Thin wrapper
around `gauge_fix` that throws away the (C, α) coefficients.
"""
function _project_gauge(v::AbstractVector{<:Real},
                        band_mask::AbstractVector{Bool},
                        omega::AbstractVector{<:Real})
    v_fixed, _ = gauge_fix(v, band_mask, omega)
    return vec(v_fixed)
end

# ─────────────────────────────────────────────────────────────────────────────
# Arpack λ_min / λ_max probe with gauge-mode filtering
# ─────────────────────────────────────────────────────────────────────────────

"""
    _probe_lambda_extremes(H_op, n, band_mask, omega;
                           nev_sr=3, nev_lr=1, tol=1e-6, maxiter=200)
        -> (λ_min, λ_max)

Estimate the leftmost and rightmost Hessian eigenvalues matrix-free via
Arpack. For `:SR` we ask `nev=3` and filter out gauge modes (constant and
linear-in-ω) by cosine similarity > 0.95 against the analytic null
directions, then return the smallest remaining eigenvalue.

On Arpack failure returns `(NaN, NaN)` so the caller falls back gracefully.
"""
function _probe_lambda_extremes(H_op, n::Integer,
                                band_mask::AbstractVector{Bool},
                                omega::AbstractVector{<:Real};
                                nev_sr::Integer = 3,
                                nev_lr::Integer = 1,
                                tol::Real = 1e-6,
                                maxiter::Integer = 200)
    # Build a minimal matrix-free operator compatible with Arpack
    op = _FunctionalHVPOperator(n, H_op)

    # Reference gauge directions, normalised over the full grid
    const_ref = ones(Float64, n); const_ref ./= norm(const_ref)
    ω_band_mean = any(band_mask) ? mean(omega[band_mask]) : 0.0
    lin_ref = omega .- ω_band_mean; lin_ref ./= max(norm(lin_ref), eps())

    λ_min = NaN
    λ_max = NaN
    try
        λ_sr, V_sr, _ = Arpack.eigs(op; nev = nev_sr, which = :SR,
                                    tol = tol, maxiter = maxiter)
        λ_sr = real.(λ_sr); V_sr = real.(V_sr)
        # Filter gauge modes
        order = sortperm(λ_sr)
        for k in order
            v = V_sr[:, k]; v_norm = norm(v)
            v_norm > 0 || continue
            vu = v ./ v_norm
            cos_c = abs(dot(vu, const_ref))
            cos_l = abs(dot(vu, lin_ref))
            if cos_c < 0.95 && cos_l < 0.95
                λ_min = λ_sr[k]
                break
            end
        end
        # Fallback: if everything looks gauge-like, return smallest anyway.
        if !isfinite(λ_min) && !isempty(λ_sr)
            λ_min = minimum(λ_sr)
        end
    catch e
        @debug "Arpack :SR failed in _probe_lambda_extremes" exception=e
    end
    try
        λ_lr, _, _ = Arpack.eigs(op; nev = nev_lr, which = :LR,
                                 tol = tol, maxiter = maxiter)
        λ_lr = real.(λ_lr)
        if !isempty(λ_lr); λ_max = maximum(λ_lr); end
    catch e
        @debug "Arpack :LR failed in _probe_lambda_extremes" exception=e
    end
    return (λ_min, λ_max)
end

# Minimal matrix-free operator adapter
struct _FunctionalHVPOperator
    n::Int
    H_op::Function
end
Base.size(A::_FunctionalHVPOperator) = (A.n, A.n)
Base.size(A::_FunctionalHVPOperator, d::Integer) = A.n
Base.eltype(::_FunctionalHVPOperator) = Float64
LinearAlgebra.issymmetric(::_FunctionalHVPOperator) = true
LinearAlgebra.ishermitian(::_FunctionalHVPOperator) = true
function LinearAlgebra.mul!(y::AbstractVector, A::_FunctionalHVPOperator, x::AbstractVector)
    y .= A.H_op(collect(x))
    return y
end
Base.:*(A::_FunctionalHVPOperator, x::AbstractVector) = A.H_op(collect(x))

# ─────────────────────────────────────────────────────────────────────────────
# Core outer loop — analytic oracle variant (takes a RamanOracle directly)
# ─────────────────────────────────────────────────────────────────────────────

"""
    _optimize_tr_core(oracle, φ0, band_mask, omega, n; ...) -> TrustRegionResult

The actual TR outer loop. Public entries build the oracle, call this, and
pack the return. `band_mask` + `omega` are the gauge-projection inputs;
for the analytic-quadratic test path the caller uses `band_mask = trues(n)`
and `omega = 1:n` (no gauge modes, projection is identity).
"""
function _optimize_tr_core(oracle::RamanOracle,
                           φ0::AbstractVector{<:Real},
                           band_mask::AbstractVector{Bool},
                           omega::AbstractVector{<:Real},
                           n::Integer;
                           solver::DirectionSolver = SteihaugSolver(),
                           M = nothing,
                           max_iter::Int = 50,
                           Δ0::Float64 = 0.5,
                           Δ_max::Float64 = 10.0,
                           Δ_min::Float64 = 1e-6,
                           η1::Float64 = 0.25,
                           η2::Float64 = 0.75,
                           γ_shrink::Float64 = 0.25,
                           γ_grow::Float64 = 2.0,
                           g_tol::Float64 = 1e-5,
                           H_tol::Float64 = -1e-6,
                           lambda_probe_cadence::Int = 10,
                           stall_window::Int = 10,
                           stall_rtol::Float64 = 1e-8,
                           project_gauge::Bool = true,
                           telemetry_path::Union{Nothing,AbstractString} = nothing,
                           trust_report_md::Union{Nothing,AbstractString} = nothing)
    t_start = time()

    _proj(v) = project_gauge ? _project_gauge(v, band_mask, omega) : collect(Float64.(v))

    φ = Vector{Float64}(_proj(copy(φ0)))
    records = TRIterationRecord[]

    hvps_total = 0
    grad_calls_total = 0
    forward_only_calls_total = 0

    # Initial cost + gradient
    J_current = oracle.cost_fn(φ)
    forward_only_calls_total += 1
    if !isfinite(J_current)
        # Initial point itself is bad — return NAN_IN_OBJECTIVE immediately.
        return TrustRegionResult(φ, J_current, NAN_IN_OBJECTIVE, 0,
                                 hvps_total, grad_calls_total,
                                 forward_only_calls_total,
                                 time() - t_start, records, NaN, NaN)
    end
    g = _proj(oracle.grad_fn(φ))
    grad_calls_total += 1

    Δ = Δ0
    exit_code = MAX_ITER
    lambda_min_final = NaN
    lambda_max_final = NaN

    # Per-iter HVP counter + last-used ε (communicated from H_op closure)
    hvps_this_iter = Ref(0)
    eps_hvp_last = Ref(NaN)

    function H_op(v::AbstractVector{<:Real})
        # Adaptive FD step per Phase 27 §item 5 recommendation (pitfall P2).
        g_norm = norm(g)
        v_norm = norm(v)
        eps_hvp = sqrt(eps(Float64) * max(1.0, g_norm)) / max(1.0, v_norm)
        eps_hvp_last[] = eps_hvp
        hvps_this_iter[] += 1
        # Project v onto gauge-complement BEFORE the HVP — keeps the CG
        # entirely inside the gauge-complement subspace (pitfall P1).
        v_proj = _proj(v)
        Hv = fd_hvp(φ, v_proj, oracle.grad_fn; eps = eps_hvp)
        # HVP is 2 gradient calls
        return _proj(Hv)
    end

    iter_for_exit = 0
    for iter in 1:max_iter
        hvps_this_iter[] = 0
        grad_calls_this_iter = 0
        forward_only_this_iter = 0

        g_norm = norm(g)

        # Per-iter λ probe (only at cadence or explicit stopping checks)
        λ_min_iter = NaN
        λ_max_iter = NaN
        if iter % lambda_probe_cadence == 0 || g_norm < g_tol
            λ_min_iter, λ_max_iter = _probe_lambda_extremes(H_op, n, band_mask, omega)
            # Each :SR / :LR burns some HVPs inside H_op → already tracked.
        end
        kappa_eff_iter = if isfinite(λ_min_iter) && isfinite(λ_max_iter)
            abs(λ_min_iter) > eps() ? λ_max_iter / abs(λ_min_iter) : NaN
        else
            NaN
        end

        # First-order stationarity check
        if g_norm < g_tol
            if isfinite(λ_min_iter) && λ_min_iter > H_tol
                exit_code = CONVERGED_2ND_ORDER
                lambda_min_final = λ_min_iter
                lambda_max_final = λ_max_iter
                iter_for_exit = iter - 1
                # Push a terminal record for visibility
                push!(records, TRIterationRecord(
                    iter, J_current, g_norm, Δ, NaN, 0.0, 0.0, 0.0,
                    false, 0, :NO_DESCENT,
                    λ_min_iter, λ_max_iter, kappa_eff_iter,
                    hvps_this_iter[], grad_calls_this_iter,
                    forward_only_this_iter, time() - t_start, eps_hvp_last[]))
                hvps_total += hvps_this_iter[]
                break
            else
                # Try negative-curvature escape
                λmin = isfinite(λ_min_iter) ? λ_min_iter : H_tol
                if λmin < H_tol
                    # Fetch the leftmost eigenvector via Arpack (nev=3, filter gauge)
                    escaped, φ_new, J_new = _neg_curv_escape!(H_op, φ, J_current, oracle,
                                                             Δ, band_mask, omega, n;
                                                             g_tol_for_sr = g_tol)
                    # Each eigs :SR call does its own HVPs (via H_op) — tracked.
                    if escaped
                        # Record and continue
                        push!(records, TRIterationRecord(
                            iter, J_current, g_norm, Δ, NaN, 0.0,
                            J_current - J_new, NaN,  # step_norm unknown here
                            true, 0, :NEGATIVE_CURVATURE,
                            λ_min_iter, λ_max_iter, kappa_eff_iter,
                            hvps_this_iter[], grad_calls_this_iter,
                            forward_only_this_iter, time() - t_start, eps_hvp_last[]))
                        hvps_total += hvps_this_iter[]
                        φ = φ_new
                        J_current = J_new
                        g = _proj(oracle.grad_fn(φ))
                        grad_calls_total += 1
                        continue
                    else
                        exit_code = CONVERGED_1ST_ORDER_SADDLE
                        lambda_min_final = λ_min_iter
                        lambda_max_final = λ_max_iter
                        iter_for_exit = iter - 1
                        push!(records, TRIterationRecord(
                            iter, J_current, g_norm, Δ, NaN, 0.0, 0.0, 0.0,
                            false, 0, :NO_DESCENT,
                            λ_min_iter, λ_max_iter, kappa_eff_iter,
                            hvps_this_iter[], grad_calls_this_iter,
                            forward_only_this_iter, time() - t_start, eps_hvp_last[]))
                        hvps_total += hvps_this_iter[]
                        break
                    end
                end
            end
        end

        # Solve the TR subproblem
        sub = solve_subproblem(solver, g, H_op, Δ; M = M, proj = _proj)

        # Gauge-leak guard on accepted candidate. We apply the projection
        # inside H_op already, so `sub.p` should be in the gauge-complement
        # to numerical precision. Any violation is a bug.
        if project_gauge
            p_fixed = _proj(sub.p)
            leak = norm(sub.p .- p_fixed) / max(norm(sub.p), eps())
            if leak > 1e-8
                exit_code = GAUGE_LEAK
                iter_for_exit = iter - 1
                push!(records, TRIterationRecord(
                    iter, J_current, g_norm, Δ, NaN,
                    sub.pred_reduction, NaN, norm(sub.p),
                    false, sub.inner_iters, sub.exit_code,
                    λ_min_iter, λ_max_iter, kappa_eff_iter,
                    hvps_this_iter[], grad_calls_this_iter,
                    forward_only_this_iter, time() - t_start, eps_hvp_last[]))
                hvps_total += hvps_this_iter[]
                break
            end
        end

        # Evaluate the trial point
        φ_trial = φ .+ sub.p
        J_trial = oracle.cost_fn(φ_trial)
        forward_only_this_iter += 1
        forward_only_calls_total += 1

        if !isfinite(J_trial)
            exit_code = NAN_IN_OBJECTIVE
            iter_for_exit = iter - 1
            push!(records, TRIterationRecord(
                iter, J_current, g_norm, Δ, NaN,
                sub.pred_reduction, NaN, norm(sub.p),
                false, sub.inner_iters, sub.exit_code,
                λ_min_iter, λ_max_iter, kappa_eff_iter,
                hvps_this_iter[], grad_calls_this_iter,
                forward_only_this_iter, time() - t_start, eps_hvp_last[]))
            hvps_total += hvps_this_iter[]
            break
        end

        actual_red = J_current - J_trial
        step_norm = norm(sub.p)

        ρ = if sub.pred_reduction > 0
            actual_red / sub.pred_reduction
        else
            # Degenerate step (pred_reduction = 0 only in :NO_DESCENT):
            # the outer loop treats this as "no progress possible".
            NaN
        end

        step_accepted = isfinite(ρ) && ρ > η1

        if step_accepted
            φ = φ_trial
            J_current = J_trial
            g = _proj(oracle.grad_fn(φ))
            grad_calls_this_iter += 1
            grad_calls_total += 1
        end

        # Radius update uses ρ (if finite); NaN ρ → treat as below η1 (shrink).
        ρ_for_update = isfinite(ρ) ? ρ : -Inf
        Δ = update_radius(Δ, ρ_for_update, step_norm, Δ_max;
                          η1 = η1, η2 = η2,
                          γ_shrink = γ_shrink, γ_grow = γ_grow)

        push!(records, TRIterationRecord(
            iter, J_current, g_norm, Δ, ρ,
            sub.pred_reduction, actual_red, step_norm,
            step_accepted, sub.inner_iters, sub.exit_code,
            λ_min_iter, λ_max_iter, kappa_eff_iter,
            hvps_this_iter[], grad_calls_this_iter,
            forward_only_this_iter, time() - t_start, eps_hvp_last[]))
        hvps_total += hvps_this_iter[]

        if isfinite(λ_min_iter); lambda_min_final = λ_min_iter; end
        if isfinite(λ_max_iter); lambda_max_final = λ_max_iter; end

        # Radius collapse
        if Δ < Δ_min
            exit_code = RADIUS_COLLAPSE
            iter_for_exit = iter
            break
        end

        iter_for_exit = iter
    end

    # If we fell through max_iter: classify as MAX_ITER vs MAX_ITER_STALLED
    if iter_for_exit == max_iter && !(exit_code in (RADIUS_COLLAPSE, NAN_IN_OBJECTIVE,
                                                     GAUGE_LEAK, CONVERGED_2ND_ORDER,
                                                     CONVERGED_1ST_ORDER_SADDLE))
        # Stall if no improvement over the last `stall_window` iterations.
        if length(records) >= stall_window + 1
            J_old = records[end - stall_window].J
            Δ_J = J_old - J_current
            # Relative improvement threshold:
            rel = abs(Δ_J) / max(abs(J_old), eps())
            exit_code = rel < stall_rtol ? MAX_ITER_STALLED : MAX_ITER
        else
            exit_code = MAX_ITER
        end
    end

    result = TrustRegionResult(φ, J_current, exit_code, iter_for_exit,
                               hvps_total, grad_calls_total,
                               forward_only_calls_total,
                               time() - t_start, records,
                               lambda_min_final, lambda_max_final)

    if telemetry_path !== nothing
        write_telemetry_csv(telemetry_path, records)
    end
    if trust_report_md !== nothing
        summary = Dict{String,Any}(
            "exit_code" => string(exit_code),
            "iterations" => iter_for_exit,
            "J_final" => J_current,
            "hvps_total" => hvps_total,
            "grad_calls_total" => grad_calls_total,
            "forward_only_calls_total" => forward_only_calls_total,
            "wall_time_s" => time() - t_start,
            "lambda_min_final" => lambda_min_final,
            "lambda_max_final" => lambda_max_final,
        )
        append_trust_report_section(trust_report_md, summary, records)
    end
    return result
end

"""
    _neg_curv_escape!(H_op, φ, J_current, oracle, Δ, band_mask, omega, n;
                      g_tol_for_sr)
        -> (escaped::Bool, φ_new, J_new)

At a first-order stationary point with `λ_min < H_tol`, attempt to escape
along the leftmost gauge-filtered eigenvector by trying both signs. Returns
whether either sign decreased `J`; if so, returns the improved iterate.

Pitfall P7: evaluate BOTH ±α·v1; accept the better sign, reject if neither.
"""
function _neg_curv_escape!(H_op, φ::AbstractVector{<:Real}, J_current::Real,
                           oracle::RamanOracle, Δ::Real,
                           band_mask::AbstractVector{Bool},
                           omega::AbstractVector{<:Real},
                           n::Integer;
                           g_tol_for_sr::Real = 1e-6)
    op = _FunctionalHVPOperator(n, H_op)
    local λ_sr, V_sr
    try
        λ_sr, V_sr, _ = Arpack.eigs(op; nev = 3, which = :SR, tol = 1e-6, maxiter = 300)
    catch e
        @debug "Neg-curv escape: Arpack :SR failed" exception=e
        return (false, φ, J_current)
    end
    λ_sr = real.(λ_sr); V_sr = real.(V_sr)
    # Gauge-filter
    const_ref = ones(Float64, n); const_ref ./= norm(const_ref)
    ω_band_mean = any(band_mask) ? mean(omega[band_mask]) : 0.0
    lin_ref = omega .- ω_band_mean; lin_ref ./= max(norm(lin_ref), eps())
    order = sortperm(λ_sr)
    v1 = nothing; λ1 = NaN
    for k in order
        v = V_sr[:, k]; vn = norm(v)
        vn > 0 || continue
        vu = v ./ vn
        cos_c = abs(dot(vu, const_ref)); cos_l = abs(dot(vu, lin_ref))
        if cos_c < 0.95 && cos_l < 0.95
            v1 = vu; λ1 = λ_sr[k]
            break
        end
    end
    v1 === nothing && return (false, φ, J_current)

    α = sqrt(Δ / max(abs(λ1), eps()))
    best_J = J_current; best_φ = φ
    for s in (+1, -1)
        φ_try = φ .+ (s * α) .* v1
        J_try = oracle.cost_fn(φ_try)
        if isfinite(J_try) && J_try < best_J
            best_J = J_try; best_φ = φ_try
        end
    end
    if best_J < J_current
        return (true, best_φ, best_J)
    end
    return (false, φ, J_current)
end

# ─────────────────────────────────────────────────────────────────────────────
# Public entry: Raman physics path
# ─────────────────────────────────────────────────────────────────────────────

"""
    optimize_spectral_phase_tr(uω0, fiber, sim, band_mask; ...)

Globalized second-order optimizer parallel to `optimize_spectral_phase`
(L-BFGS). Same input contract:
- `uω0`         — input spectrum, (Nt, M) or (Nt, 1)
- `fiber`, `sim`, `band_mask` — standard `setup_raman_problem` outputs
- `φ0 = nothing` → zeros
- `log_cost::Bool = false`  — Wave 1 default is physics cost (HVP-consistent).
  Set to `true` for log-dB cost (gradient scales 10/(J·ln10); see pitfall P3).

See `.planning/phases/33-globalized-second-order-optimization-for-raman-suppression/33-RESEARCH.md`
for the mathematical contract. Result has `.minimizer` (Optim.jl parity).
"""
function optimize_spectral_phase_tr(uω0, fiber, sim, band_mask;
                                    φ0 = nothing,
                                    solver::DirectionSolver = SteihaugSolver(),
                                    M = nothing,
                                    max_iter::Int = 50,
                                    Δ0::Float64 = 0.5,
                                    Δ_max::Float64 = 10.0,
                                    Δ_min::Float64 = 1e-6,
                                    η1::Float64 = 0.25,
                                    η2::Float64 = 0.75,
                                    γ_shrink::Float64 = 0.25,
                                    γ_grow::Float64 = 2.0,
                                    g_tol::Float64 = 1e-5,
                                    H_tol::Float64 = -1e-6,
                                    λ_gdd::Float64 = 0.0,
                                    λ_boundary::Float64 = 0.0,
                                    log_cost::Bool = false,
                                    lambda_probe_cadence::Int = 10,
                                    stall_window::Int = 10,
                                    telemetry_path::Union{Nothing,AbstractString} = nothing,
                                    trust_report_md::Union{Nothing,AbstractString} = nothing)
    ensure_deterministic_fftw()
    ensure_deterministic_environment()

    Nt = sim["Nt"]; n_modes = sim["M"]
    n = Nt * n_modes
    fiber["zsave"] = nothing

    oracle = build_raman_oracle(uω0, fiber, sim, band_mask;
                                log_cost = log_cost,
                                λ_gdd = λ_gdd, λ_boundary = λ_boundary)

    if φ0 === nothing
        φ0v = zeros(Float64, n)
    else
        φ0v = vec(Float64.(φ0))
        @assert length(φ0v) == n "φ0 length $(length(φ0v)) ≠ Nt·M = $n"
    end

    mask = input_band_mask(uω0)
    omega = omega_vector(sim["ω0"], sim["Δt"], Nt)

    return _optimize_tr_core(oracle, φ0v, mask, omega, n;
                             solver = solver,
                             M = M,
                             max_iter = max_iter,
                             Δ0 = Δ0, Δ_max = Δ_max, Δ_min = Δ_min,
                             η1 = η1, η2 = η2,
                             γ_shrink = γ_shrink, γ_grow = γ_grow,
                             g_tol = g_tol, H_tol = H_tol,
                             lambda_probe_cadence = lambda_probe_cadence,
                             stall_window = stall_window,
                             project_gauge = true,
                             telemetry_path = telemetry_path,
                             trust_report_md = trust_report_md)
end

"""
    optimize_analytic_tr(cost_fn, grad_fn, φ0; ...) -> TrustRegionResult

Test-only variant: run the TR outer loop on a user-provided cost+gradient
pair over `ℝ^n`, with `project_gauge = false` (no Raman gauge modes to
remove). Used by `test/test_trust_region_integration.jl` to unit-test the
outer loop on analytic quadratics.
"""
function optimize_analytic_tr(cost_fn::Function, grad_fn::Function,
                              φ0::AbstractVector{<:Real};
                              solver::DirectionSolver = SteihaugSolver(),
                              max_iter::Int = 50,
                              kwargs...)
    n = length(φ0)
    oracle = RamanOracle(cost_fn, grad_fn)
    band_mask = trues(n)   # passed to gauge_fix but project_gauge=false → unused
    omega = collect(1.0:n)  # placeholder
    return _optimize_tr_core(oracle, collect(Float64.(φ0)), band_mask, omega, n;
                             solver = solver, max_iter = max_iter,
                             project_gauge = false, kwargs...)
end

end  # include guard
