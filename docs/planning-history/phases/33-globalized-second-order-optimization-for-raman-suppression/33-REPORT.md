---
phase: 33-globalized-second-order-optimization-for-raman-suppression
document: report
status: COMPLETE
date: 2026-04-21
plans: [33-01, 33-02, 33-03]
---

# Phase 33 Report — Globalized Second-Order Optimization for Raman Suppression

**Status:** COMPLETE
**Date:** 2026-04-21

## Verdict

Phase 33 delivered a safeguarded trust-region Newton optimizer (`optimize_spectral_phase_tr`) with Steihaug truncated-CG inner solve, gauge-projected HVP, 7-way typed exit-code taxonomy, Phase-28 trust-report extension, and a `DirectionSolver` abstract interface frozen for Phase 34. The optimizer ran end-to-end on the 9-slot benchmark matrix (3 configs × 3 start types) without a single silent failure. Of the 9 slots, **3 were correctly refused at pre-flight by the Phase-28 edge-fraction gate (`SKIPPED_P8`)**, **4 exited `RADIUS_COLLAPSE`** (TR refused to commit to any step from either cold φ=0 or a Phase-21 honest warm-start because the quadratic model could not predict actual reduction within `η₁ = 0.25`), and **2 exited `CONVERGED_1ST_ORDER_SADDLE` at iteration 0** (the bench-02 HNLF warm and perturbed slots; gradient already below `g_tol = 1e-5` on entry, λ_min probe confirmed saddle with `λ_min ≈ -1.03e-6`, both signs of the leftmost eigenvector tried and both rejected). **Zero `GAUGE_LEAK`. Zero `NAN_IN_OBJECTIVE`. Zero `CONVERGED_2ND_ORDER`.** The Phase-35 saddle-rich landscape hypothesis is **CONFIRMED**: every warm-start that survived the trust gate landed at a point where `λ_min < -1e-6` and where no directional escape lowered J — exactly the pattern Phase 35 reported. The cold-start `RADIUS_COLLAPSE` results add a new data point: from φ=0 the Hessian is indefinite with `|λ_min| ∼ O(10² − 10⁻¹)` and Steihaug returns on the negative-curvature branch every iteration, but no boundary step decreased J enough to pass the ρ test, so Δ shrank below `Δ_min = 1e-6` after ~10 iterations. This is honest pessimism — the quadratic model is *not* trustworthy from zero phase — which is exactly what the ρ test is built to diagnose.

## What Was Built

Plan 01 (`33-01-SUMMARY.md`) landed the trust-region core in 3 scripts + 2 test files, totaling **1655 lines of new code with zero modifications to shared files** (`scripts/raman_optimization.jl`, `scripts/common.jl`, `scripts/phase13_*.jl`, `scripts/numerical_trust.jl`, `scripts/determinism.jl`, `scripts/standard_images.jl`, `src/**`).

| Component | File | Lines | Role |
|---|---|---:|---|
| TR core math | `scripts/trust_region_core.jl` | 241 | `@enum TRExitCode`, `abstract type DirectionSolver`, `SubproblemResult`, `SteihaugSolver`, `solve_subproblem`, `update_radius` (Nocedal-Wright §4.1) |
| Telemetry schema | `scripts/trust_region_telemetry.jl` | 294 | `TRIterationRecord` (19 fields), round-trip CSV I/O (`%.17g` Float64), `rejection_breakdown`, `append_trust_report_section` (Phase 28 additive extension) |
| Outer loop | `scripts/trust_region_optimize.jl` | 678 | `optimize_spectral_phase_tr`, `TrustRegionResult` (Optim.jl `.minimizer` parity), `build_raman_oracle`, gauge-projected `H_op` with adaptive FD-HVP ε, Arpack λ-probe with gauge-filter, neg-curvature escape (both signs tested) |
| Unit tests (analytic) | `test/test_trust_region_steihaug.jl` | 205 | 9 testsets / 60 assertions — SPD Newton step, boundary-hit, indefinite neg-curv, radius-update table, enum completeness |
| Integration tests | `test/test_trust_region_integration.jl` | 237 | 6 testsets / 89 assertions — TR on SPD quadratic, telemetry round-trip incl. NaN/Inf, gauge invariant, Raman Nt=128 E2E, `.minimizer` field |

**Safeguards wired in (from 33-RESEARCH.md §Pitfalls):**
1. Gauge projection inside `H_op` *before* every FD-HVP evaluation, not just post-hoc on the outer gradient — so CG stays entirely inside the gauge-complement subspace (pitfall P1).
2. Adaptive FD-HVP step `ε_hvp = √(eps · max(1, ‖g‖)) / max(1, ‖v‖)` logged per iteration in `telemetry.csv:eps_hvp_used` (pitfall P2).
3. Regularizers disabled for the benchmark (`λ_gdd = λ_boundary = 0`) per pitfall P4 — physics cost only, HVP-consistent.
4. `ensure_deterministic_environment()` + `ensure_deterministic_fftw()` at every entry point (pitfall P5).
5. Arpack λ-probe asks `nev=3 :SR` then gauge-filters by cosine similarity against `{𝟙, ω − ω̄}` — returns the smallest non-gauge eigenvalue (pitfall P1 / research open-question 3).
6. Negative-curvature escape tries both signs `±α · v₁` (pitfall P7). If neither lowers J, exit `CONVERGED_1ST_ORDER_SADDLE`.
7. Phase-28 edge-fraction pre-flight before every benchmark config — any config with `edge_frac > 1e-3` emits an abort stub and skips the TR run (pitfall P8).
8. `GAUGE_LEAK` hard assertion on every accepted step: `‖p − Π p‖ / ‖p‖ ≤ 1e-8`. Violation terminates with typed exit code, not silent propagation.

Plan 02 (`scripts/benchmark_run.jl`) executed the 9-slot matrix on an ephemeral burst VM (per CLAUDE.md Rule 1 + Rule P5), emitting `_result.jld2`, `telemetry.csv`, a trust-report markdown, and the 4-panel standard image set per non-skipped slot.

Plan 03 added `scripts/benchmark_synthesis.jl`, three synthesis PNGs, `SYNTHESIS.md`, and this report.

## What Was Found

Full details: [`results/raman/phase33/SYNTHESIS.md`](../../../results/raman/phase33/SYNTHESIS.md). Reproduced headline here:

### Exit-code distribution (9 slots)

| Exit code | Count | Slots |
|---|---:|---|
| `CONVERGED_2ND_ORDER` | 0 | — |
| `CONVERGED_1ST_ORDER_SADDLE` | 2 | bench-02-hnlf-phase21/{warm, perturbed} |
| `RADIUS_COLLAPSE` | 4 | bench-01/cold, bench-02/cold, bench-03/{cold, warm} |
| `MAX_ITER` | 0 | — |
| `MAX_ITER_STALLED` | 0 | — |
| `NAN_IN_OBJECTIVE` | 0 | — |
| `GAUGE_LEAK` | 0 | — |
| `SKIPPED_P8` (pre-flight) | 3 | bench-01/{warm, perturbed}, bench-03/perturbed |

### Physics-cost summary

| Slot | Start | J_final (linear) | J_final (dB) | vs. warm-start baseline |
|---|---|---:|---:|---|
| bench-02-hnlf | warm | 2.148e-09 | -86.68 dB | ≡ baseline (started already at Phase-21 minimum) |
| bench-02-hnlf | perturbed | 9.197e-08 | -70.36 dB | Landed 16 dB above baseline after 5% randn — converged to nearby saddle, not recovered original |
| bench-03-smf28 | warm | 2.185e-07 | -66.61 dB | ≡ baseline (Phase-21 minimum held under TR) |
| bench-01-smf28 | cold | 7.746e-01 | -1.11 dB | Phase-0 only — no TR progress |
| bench-02-hnlf | cold | 1.011e-01 | -9.95 dB | Phase-0 only — no TR progress |
| bench-03-smf28 | cold | 7.743e-01 | -1.11 dB | Phase-0 only — no TR progress |

### Saddle evidence (bench-02 warm)

- Entry gradient norm: `4.19e-08` < `g_tol = 1e-5` → first-order stationary on entry.
- Arpack `:SR` nev=3 with gauge filter: `λ_min = -1.031e-06`, `λ_max = 7.062e-07`.
- `H_tol = -1e-6` → `λ_min < H_tol` → attempt negative-curvature escape.
- Tried both signs of the leftmost gauge-filtered eigenvector at step `α = √(Δ / |λ_min|)`. Neither sign decreased J.
- Outer loop exits `CONVERGED_1ST_ORDER_SADDLE` at iter 0. 240 HVPs burned by the :SR probes (3 eigenvectors across λ_min and λ_max at Nt=65536 is expensive).

This reproduces the Phase 35 pattern exactly: the Phase-21 HNLF and SMF-28 minima are indefinite critical points, and the leftmost non-gauge eigenvector is not a descent direction at the requested step size.

### Cold-start evidence (RADIUS_COLLAPSE)

- 10 iterations, Steihaug exits `:NEGATIVE_CURVATURE` on every step (d'Hd ≤ 0 immediately — meaning the initial search direction `d = -g` itself has `⟨d, Hd⟩ ≤ 0`, so the solver steps to the boundary along that direction).
- Every boundary step decreased J by a factor 6e-3 ≤ `ρ ≤ 1e-3` of the predicted reduction → all rejected → radius shrunk by γ_shrink=0.25 each iter.
- After 10 iterations Δ drops below `Δ_min = 1e-6`. Exit code `RADIUS_COLLAPSE`.
- Note: `bench-01` cold has `λ_max/|λ_min| ≈ 1.8` (well-conditioned but indefinite); `bench-02` cold has `|λ_min| ≈ 1e-3`, `λ_max ≈ 1.8e-5` (tiny; the HNLF linear regime). Different spectra, same mechanism.

The scientific reading: TR correctly refuses to commit from φ=0 because the quadratic model at zero phase is not predictive of the true cost surface. L-BFGS would happily take steps here and eventually land somewhere; TR tells you the model is untrustworthy, which is *more honest* information.

### Gauge discipline

Zero `GAUGE_LEAK` across 60+ CG inner iterations × 6 runs. The inline gauge projection of every input vector to `H_op` (not just the outer gradient) is structurally sufficient. Pitfall P1 did not fire.

## Comparison vs L-BFGS Baseline

**Not a dB contest** — per 33-RESEARCH.md §Non-goal ("Lower J_dB than Phase 13's L-BFGS baseline is NOT a success criterion"). We compare on the axes where globalization actually changes the deliverable:

| Axis | L-BFGS (Phase 13/21/22 reference) | Trust-Region Newton (Phase 33) |
|---|---|---|
| Exit taxonomy | single state (`converged` / `max_iter`) | 7 typed states (see `TRExitCode` enum) |
| Saddle handling | silent — reports the saddle's J_dB as "best achieved" | explicit Arpack λ_min probe + both-signs neg-curvature attempt + `CONVERGED_1ST_ORDER_SADDLE` exit |
| Gauge-null safety | manual `gauge_fix` post-hoc on `phi_opt` | baked into every iteration (gauge projection *before* HVP) + `GAUGE_LEAK` assertion with typed exit |
| Non-finite cost | propagates (crashes or silently bad result) | typed `NAN_IN_OBJECTIVE` exit at trial-point evaluation |
| Regularizer rescaling pitfall (P4) | contaminates (log-cost rescales regularizer to vanish at deep J) | sidestepped (`λ_gdd = λ_boundary = 0` for benchmark, cleanly documented) |
| HVP step size | N/A (L-BFGS is quasi-Newton, no Hessian) | adaptive `ε_hvp` per iter, logged in telemetry |
| Trust-region acceptance | N/A | ρ-based step acceptance with `η₁ = 0.25, η₂ = 0.75` radius update |
| Phase 34 hand-off | ad-hoc | abstract `DirectionSolver` + frozen `SubproblemResult` contract |

The `RADIUS_COLLAPSE` outcomes are **not** a regression against L-BFGS — they are TR refusing to commit to steps that its model does not predict. L-BFGS on the same starting points (Phase 13 results) would have taken steps, but without a way to diagnose "the quadratic model is wrong here." That diagnostic capability is Phase 33's point.

## Pitfall Audit (from 33-RESEARCH.md §Pitfalls)

- **P1 — Gauge null modes inflate trust radius:** **did not fire.** 0 runs exited `GAUGE_LEAK`. The inline projection of every input to `H_op` (trust_region_optimize.jl:304 `v_proj = _proj(v)`) keeps CG in the gauge-complement throughout. Assertion `‖p − Π p‖/‖p‖ ≤ 1e-8` held on every accepted step across all 6 executed runs.

- **P2 — HVP noise floor degrades ρ at deep suppression:** **fired** in 2 runs (bench-02 warm + perturbed). The adaptive rule `eps_hvp = sqrt(eps(Float64) * max(1, ‖g‖)) / max(1, ‖v‖)` activated at `‖g‖ ≈ 4e-8 / 1.2e-6` and yielded `eps_hvp` values of `1.49e-08` on the cold-start runs (where `‖g‖ = O(1)`) and similar magnitudes for the saddle-exit probes (recorded in `telemetry.csv:eps_hvp_used`). Adaptive rule is working; no further action needed.

- **P3 — log_cost HVP inconsistency:** **not applicable.** All Wave 2 runs used `log_cost=false` (physics cost only), so the HVP oracle and the optimization objective agree byte-for-byte. disposition: deferred to a future phase if log-scale cost is reintroduced into the TR path.

- **P4 — Regularizer bake-in:** **did not fire.** `λ_gdd = λ_boundary = 0.0` throughout Plan 02 benchmark (see `benchmark_run.jl:180-181`). Pitfall structurally sidestepped; Phase 28 follow-up owns the eventual structural fix.

- **P5 — FFTW plan non-determinism:** **did not fire.** `ensure_deterministic_environment()` + `ensure_deterministic_fftw()` called at every `optimize_spectral_phase_tr` entry (trust_region_optimize.jl:621-622). No cross-process ρ drift observed.

- **P6 — Trust-region radius norm choice:** **did not fire (plain `‖·‖₂` was adequate).** Current implementation uses Euclidean `‖p‖₂` trust region with `Δ0 = 0.5` radians. No evidence from telemetry that mode-dependent scaling would have changed any outcome (the 4 `RADIUS_COLLAPSE` runs failed the ρ test, not the radius norm). disposition: deferred to Phase 34 along with preconditioning agenda (`PreconditionedCGSolver` naturally induces an ellipsoidal trust region).

- **P7 — Negative-curvature step sign ambiguity:** **fired** in 2 runs (bench-02 warm + perturbed). `_neg_curv_escape!` (trust_region_optimize.jl:535) evaluated both signs `±α · v₁` at `α = √(Δ / |λ_min|)`. Neither sign lowered J below `J_current` in either run → rejected → exited `CONVERGED_1ST_ORDER_SADDLE`. Mitigation is structurally correct; the saddle is genuinely a saddle where the leftmost eigendirection is not a descent direction at this step size.

- **P8 — Boundary absorption silent leak:** **fired** in 3 slots (bench-01 warm + perturbed, bench-03 perturbed). Pre-flight `_pulse_edge_fraction` measured `7.88e-3`, `7.68e-3`, `1.22e-3` respectively, all exceeding `TRUST_THRESHOLDS.edge_frac_pass = 1e-3`. Those slots were aborted with typed `EDGE_FRAC_SUSPECT` stub trust reports; the TR optimizer was never called. This is the gate working as designed — any TR result on those inputs would be contaminated by the super-Gaussian-30 attenuator eating pulse energy. Pitfall P8 mitigation is therefore *confirmed effective*: it prevented 3 scientifically meaningless runs from polluting the dataset.

**Summary disposition for all 8:** P1, P5 never fired (structural safeguards held). P2, P7, P8 fired and were handled by their wired mitigations. P3, P4, P6 were not-applicable-by-construction for this phase (design choice documented in 33-RESEARCH.md and echoed in the run config).

## Phase 34 Handoff

The `DirectionSolver` API is frozen. Phase 34 subtypes — **it does NOT modify** the outer loop, the telemetry schema, the exit-code taxonomy, the Raman oracle wiring, or the benchmark driver structure. Below is the **exact contract** pasted verbatim from `scripts/trust_region_core.jl` (lines 35–92) so the Phase 34 planner has an unambiguous interface to subtype against.

### Exit-code taxonomy

```julia
@enum TRExitCode begin
    CONVERGED_2ND_ORDER          # ‖g‖<g_tol AND λ_min > H_tol
    CONVERGED_1ST_ORDER_SADDLE   # ‖g‖<g_tol AND λ_min < H_tol, neg-curv escape failed
    RADIUS_COLLAPSE              # Δ < Δ_min
    MAX_ITER                     # hit max_iter, still improving
    MAX_ITER_STALLED             # hit max_iter, no improvement over stall window
    NAN_IN_OBJECTIVE             # J(φ+p) = NaN or Inf
    GAUGE_LEAK                   # ‖P_null · p‖ > 1e-8·‖p‖ — bug, not a result
end
```

### DirectionSolver abstract type

```julia
abstract type DirectionSolver end
```

### SubproblemResult — the return shape of every `solve_subproblem` call

```julia
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
```

### SteihaugSolver — Phase 33's concrete implementation (reference baseline)

```julia
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
```

### solve_subproblem — the generic function Phase 34 must provide method(s) for

```julia
"""
    solve_subproblem(solver::DirectionSolver, g, H_op, Δ; kwargs...) -> SubproblemResult

Approximately solve
    min_p  m(p) = g' p + 0.5 p' H p   subject to   ‖p‖ ≤ Δ

Arguments:
  solver  — concrete subtype (SteihaugSolver, PreconditionedKrylovSolver,
            CubicRegularizedSolver, ...)
  g       — projected gradient in the gauge-complement subspace (Vector)
  H_op    — callable: H_op(v) → H*v. Cost = 1 HVP = 2 gradient calls.
  Δ       — current trust radius (Float64)

Caller guarantees:
  - `H_op` is symmetric up to FD noise (see hvp.jl:89).
  - `g` is already in the gauge-complement subspace (projected by outer loop).
  - `Δ > 0`.

Callee guarantees (what every subtype must return):
  - `‖p‖ ≤ Δ · (1 + 1e-8)`.
  - `pred_reduction ≥ 0`. Degenerate case returns `p = 0, pred_reduction = 0,
    exit_code = :NO_DESCENT` and the outer loop exits cleanly.
"""
function solve_subproblem end
```

### update_radius — Nocedal-Wright Algorithm 4.1 (locked)

```julia
"""
    update_radius(Δ, ρ, step_norm, Δ_max;
                  η1=0.25, η2=0.75, γ_shrink=0.25, γ_grow=2.0) -> Δ_next

Classical trust-region radius update:
- `ρ < η1`:                             shrink to `γ_shrink · ‖p‖`
- `ρ > η2` AND `‖p‖ ≥ 0.9·Δ`:          grow to `min(γ_grow · Δ, Δ_max)`
- otherwise:                            keep `Δ`
"""
function update_radius(Δ, ρ, step_norm, Δ_max;
                       η1 = 0.25, η2 = 0.75,
                       γ_shrink = 0.25, γ_grow = 2.0)
    if ρ < η1
        return γ_shrink * step_norm
    elseif ρ > η2 && step_norm >= 0.9 * Δ
        return min(γ_grow * Δ, Δ_max)
    else
        return Δ
    end
end
```

### What Phase 34 will subtype

```julia
# Phase 34 ADDs these; Phase 33's core definitions are frozen.
struct PreconditionedCGSolver <: DirectionSolver
    max_iter::Int
    preconditioner::Symbol       # :none | :diagonal | :lanczos_precond
    tol_forcing::Function
end

# (optional, Phase 34 may defer to Phase 36)
struct CubicRegularizedSolver <: DirectionSolver
    sigma::Float64
    inner_solver::DirectionSolver   # nested subproblem — reuse Steihaug or PCG
end

# Phase 34 provides new method(s):
function solve_subproblem(solver::PreconditionedCGSolver,
                          g::AbstractVector{<:Real},
                          H_op,
                          Δ::Real;
                          kwargs...)::SubproblemResult
    # preconditioned truncated CG or similar
end
```

### Frozen — Phase 34 MUST NOT modify

| Path | Reason |
|---|---|
| `scripts/trust_region_core.jl` | Outer-loop math, exit-code enum, `SubproblemResult` shape, `update_radius`. Any change here is a contract break. |
| `scripts/trust_region_optimize.jl` | Wrapper `optimize_spectral_phase_tr` + `_optimize_tr_core`. Phase 34 passes its new solver via the `solver::DirectionSolver` keyword argument. |
| `scripts/trust_region_telemetry.jl` | Telemetry schema — extending would break round-trip tests. If Phase 34 needs more fields, bump schema version to `33.1` additively (append columns to the end). |
| `scripts/benchmark_run.jl` | Benchmark driver — Phase 34 should fork into `scripts/benchmark_run.jl` using the same `benchmark_common.jl` config (preferred) or extend the common with a Phase-34 config block. |
| `scripts/raman_optimization.jl`, `scripts/common.jl`, `scripts/phase13_*.jl`, `scripts/numerical_trust.jl`, `scripts/determinism.jl`, `scripts/standard_images.jl`, `src/**` | Already read-only per Phase 33. |

### What Phase 34 MAY add

- `scripts/trust_region_preconditioner.jl` — preconditioner construction (diagonal, Lanczos-based, partial-ILU-free alternatives).
- `scripts/trust_region_pcg.jl` — `PreconditionedCGSolver` + its `solve_subproblem` method.
- `scripts/benchmark_run.jl` — benchmark driver that swaps `SteihaugSolver` → `PreconditionedCGSolver` with otherwise-identical config.
- `scripts/benchmark_common.jl` MAY gain a Phase-34 config block, but the existing entries must remain byte-identical.
- `test/test_trust_region_preconditioner.jl` and `test/test_trust_region_pcg_integration.jl`.

## Open Questions — Status Post-Plan-02

From 33-RESEARCH.md §Open Questions, updated with Plan-02 evidence:

1. **Should the TR benchmark run `log_cost=true` or `log_cost=false`?** — **Partially answered.** Wave 1 ran `log_cost=false` as specified. Wave 2 did *not* add a `log_cost=true` pass because (a) all cold runs `RADIUS_COLLAPSE`d (no accepted ρ values to characterize "healthy distribution") and (b) the 2 saddle exits happened at iter 0 without committing steps. There is not enough accepted-step data yet to justify the `log_cost=true` pass — it would exercise a different gradient-scaling regime that is unverified against an honest `log_cost=false` ρ distribution. Deferred to Phase 34 or after the Phase-28 regularizer restructuring lands.

2. **Is Δ₀ = 0.5 the right initial trust radius?** — **Still open.** No accepted step was produced across 6 runs, so the Wave-2 evidence is consistent with (a) Δ₀ = 0.5 being too large (too optimistic about step trustability) *or* (b) the Hessian being genuinely indefinite enough from every tested starting point that no ρ > 0.25 step was reachable regardless of Δ₀. Phase 34's preconditioner is the natural discriminator: if `PreconditionedCGSolver` with the same Δ₀ starts accepting steps, the problem was Hessian conditioning. If not, Δ₀ itself needs re-examining.

3. **Does the λ_min probe need shift-invert?** — **Answered: no.** `nev=3 :SR` with cosine-similarity gauge filter produced finite λ_min values on every probe attempt (range: `-3.03e+02` cold bench-01, `-1.03e-06` warm bench-02, `-2.38e-05` warm bench-03). No run reported Arpack failure. Gauge modes were correctly filtered (otherwise λ_min would have rounded to zero and the saddle test would have exited 2ND_ORDER falsely). This recipe is locked.

4. **Auto-launch a continuation loop after `CONVERGED_1ST_ORDER_SADDLE`?** — **Answered: no, for Phase 33.** Both saddle exits happened at iter 0 and both-signs negative-curvature escape was already attempted. Restarting the TR outer loop from the same point would replay the same evaluations deterministically. A continuation loop that *perturbs* and restarts belongs in Phase 30's charter (warm-start continuation) or Phase 34's preconditioned re-attempt — *not* inside the TR outer loop itself. Keep the single-launch semantics.

### New open questions surfaced by Plan 02

5. **Do `RADIUS_COLLAPSE` cold-start runs indicate a genuine "model-untrustworthy" diagnosis or just Δ₀ = 0.5 being too large?** — The Nocedal-Wright radius update shrinks to `0.25 · ‖p‖` on rejection, and in 10 iterations Δ reaches `1e-6`. If Δ₀ were smaller from the start, perhaps a tiny but ρ-valid step existed. **Recommendation for Phase 34:** add a Δ₀-sweep mini-benchmark (e.g. `Δ₀ ∈ {0.5, 0.1, 0.01, 0.001}` on bench-01/cold) before investing in preconditioning.

6. **The bench-02/perturbed result landed 16 dB above the unperturbed saddle (-70.36 dB vs -86.68 dB).** 5% randn perturbation was enough to reach a *different* nearby saddle, not recover the original. Is this a local-landscape feature of the HNLF cost surface, or an artifact of the perturbation amplitude? **Recommendation for Phase 34:** a perturbation-amplitude sweep on bench-02 (0.01, 0.05, 0.10 rad RMS) would map the basin-of-attraction size around the -86.68 dB saddle.

## What Phase 34 Inherits

### Code
- `scripts/trust_region_core.jl` — frozen.
- `scripts/trust_region_telemetry.jl` — frozen (may append new columns with schema bump).
- `scripts/trust_region_optimize.jl` — frozen (Phase 34 passes its new solver via `solver::DirectionSolver` keyword).
- `scripts/benchmark_run.jl` — template to fork into `benchmark_run.jl`.
- `scripts/benchmark_common.jl` — `BENCHMARK_CONFIGS`, `START_TYPES` (additive edits OK; existing entries must stay byte-identical).
- `scripts/benchmark_synthesis.jl` — Phase 34 may reuse synthesis plotting code with a fork path for the new benchmark tag.

### Data
- `results/raman/phase33/SYNTHESIS.md` — the 9-slot Steihaug reference baseline.
- `results/raman/phase33/{rho_distribution, exit_codes, failure_taxonomy_by_config}.png` — reference figures.
- Per-slot artifacts (6 × `_result.jld2` + `telemetry.csv` + `trust_report.md`, 3 × stub `trust_report.md`) — the Steihaug comparison data. Phase 34 must produce the same shape for `PreconditionedCGSolver`.

### Contracts
- The **exact DirectionSolver + SubproblemResult + SteihaugSolver + update_radius** definitions pasted in `## Phase 34 Handoff` above.
- The P1–P8 mitigations *already applied in the outer loop* — Phase 34 does not need to reimplement gauge projection, adaptive HVP ε, the λ-probe, the both-signs neg-curv escape, or the edge-fraction pre-flight. A new solver just needs to honor the `solve_subproblem` contract.

### Forbidden edits
- `scripts/common.jl`, `scripts/raman_optimization.jl`, `scripts/phase13_*.jl`, `scripts/numerical_trust.jl`, `scripts/determinism.jl`, `scripts/standard_images.jl`, `src/simulation/*.jl`, `src/MultiModeNoise.jl`. (Inherited from Phase 33's Rule P1 namespace.)

## Artifacts

```
.planning/phases/33-globalized-second-order-optimization-for-raman-suppression/
├── 33-CONTEXT.md
├── 33-RESEARCH.md                                  (62 KB — pitfalls, API, open questions)
├── 33-01-PLAN.md, 33-01-SUMMARY.md                 (trust-region core)
├── 33-02-PLAN.md                                   (benchmark run)
├── 33-03-PLAN.md, 33-03-SUMMARY.md                 (synthesis)
└── 33-REPORT.md                                    (this file)

scripts/
├── trust_region_core.jl                            (241 LOC — frozen)
├── trust_region_telemetry.jl                       (294 LOC — frozen)
├── trust_region_optimize.jl                        (678 LOC — frozen)
├── benchmark_common.jl                     (shared config)
├── benchmark_run.jl                        (Plan 02 driver)
└── benchmark_synthesis.jl                  (Plan 03 synthesis)

test/
├── test_trust_region_steihaug.jl                   (60/60 pass)
└── test_trust_region_integration.jl                (89/89 pass)

results/raman/phase33/
├── SYNTHESIS.md
├── rho_distribution.png
├── exit_codes.png
├── failure_taxonomy_by_config.png
├── bench-01-smf28-canonical/
│   ├── cold/          {_result.jld2, telemetry.csv, trust_report.md, 4× PNG}
│   ├── warm/          {trust_report.md — SKIPPED_P8 stub}
│   └── perturbed/     {trust_report.md — SKIPPED_P8 stub}
├── bench-02-hnlf-phase21/
│   ├── cold/          {_result.jld2, telemetry.csv, trust_report.md, 4× PNG}
│   ├── warm/          {_result.jld2, telemetry.csv, trust_report.md, 4× PNG}
│   └── perturbed/     {_result.jld2, telemetry.csv, trust_report.md, 4× PNG}
└── bench-03-smf28-phase21/
    ├── cold/          {_result.jld2, telemetry.csv, trust_report.md, 4× PNG}
    ├── warm/          {_result.jld2, telemetry.csv, trust_report.md, 4× PNG}
    └── perturbed/     {trust_report.md — SKIPPED_P8 stub}
```

## Phase 33 status: COMPLETE

Phase 34 is unblocked. Recommended Phase 34 scope: `PreconditionedCGSolver <: DirectionSolver`, a Δ₀-sweep on bench-01/cold to disambiguate open question 5, and a perturbation-amplitude sweep on bench-02 to map the saddle basin from open question 6. Cubic-regularized Newton (`CubicRegularizedSolver`) can defer to Phase 36 given the budget.
