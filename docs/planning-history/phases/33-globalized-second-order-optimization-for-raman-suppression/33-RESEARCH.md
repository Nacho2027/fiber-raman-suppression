# Phase 33 Research — Safeguarded Second-Order Optimization for Raman Suppression

**Researched:** 2026-04-21
**Domain:** Nonconvex optimization / globalization / matrix-free second-order methods
**Confidence:** HIGH on problem framing and method ranking (cross-verified against Phase 13 / 22 / 27 / 35 findings and the Nocedal & Wright / Conn-Gould-Toint / Steihaug canon); MEDIUM on exact tuning of acceptance thresholds (those are empirical and must be set by wave-1 experimentation, not research).
**Valid until:** 2026-05-21 (stable literature; will drift only if upstream Phase 28/30/31 changes the conditioning contract or continuation API).

---

## Benchmark Set Substitution (addendum, 2026-04-21)

The original §Benchmark Set below named 4 pre-audit canonical warm-starts. After user-directed cross-check against the Phase 21 audit, 3 of those 4 warm-start JLD2s were unavailable (never synced) or artifact-contaminated (bc_input_ok=false). The benchmark set used in Plan 02 is therefore:

| # | Config | (fiber, L, P, Nt, time_window) | Warm-start source | J_honest | Status |
|---|---|---|---|---|---|
| bench-01 | SMF-28 canonical | (SMF28, 2.0 m, 0.2 W, 2^13, 40 ps) | `results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2` | −59.43 dB | pre-audit canonical, `bc_input_ok=false` — kept as deliberate contrast against the Phase 21 honest baseline |
| bench-02 | HNLF Phase-21 honest | (HNLF, 0.5 m, 0.01 W, 2^16, 320 ps) | `results/raman/phase21/phase13/hnlf_reanchor.jld2` | −86.68 dB | Phase 21 honest reanchor, edge_frac=2.2e-4 |
| bench-03 | SMF-28 Phase-21 honest | (SMF28, 2.0 m, 0.2 W, 2^14, 54 ps) | `results/raman/phase21/phase13/smf28_reanchor.jld2` | −66.61 dB | Phase 21 honest reanchor at same (L,P) as bench-01 — direct canonical-vs-honest comparison |
| ~~bench-04~~ | ~~Pareto-57~~ | ~~Nφ=57 reduced basis~~ | ~~`results/raman/phase22/pareto57/opt_result.jld2`~~ | ~~—~~ | DROPPED — per-row optimum was never synced from Mac to burst |

Effect on matrix: **3 configs × 3 start types = 9 TR runs** (not 12). Warm-start robustness claim still validated with 3 distinct (fiber, L, P) points. Loss: cross-validation against the reduced-basis Pareto result (Nφ=57 line-search anchor) — Phase 34 can revisit this if/when phase22 artifacts are re-synced.

Grid discipline: each config's Nt and time_window are pinned to its warm-start JLD2's grid, so `setup_raman_problem(Nt=cfg.Nt, time_window=cfg.time_window_ps*1e-12)` matches the frequency mesh exactly. Loading a phi_opt with mismatched Nt → size error → hard fail (intended).

Audit trust: all 3 surviving warm-starts have documented `edge_frac` values (bench-01: from the original JLD2, bench-02/03: Phase 21 re-anchor). Phase 33's pre-flight trust gate (pitfall P8) uses `compute_edge_fraction` on the initial forward solve and aborts any config that crosses `TRUST_THRESHOLDS.edge_frac_pass`.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions
- Second-order **search directions** and **globalization** are separate design choices. This phase designs the globalization layer and the direction-solver **interface**, not a specific Krylov inner solver.
- **Honest failure accounting is a required deliverable.** A run that exits without reaching second-order stationarity must say so, with a typed reason, not silently log "best achieved."
- Build on the **existing HVP/Lanczos assets** (`scripts/hvp.jl`, `scripts/hessian_eigspec.jl`). No dense Hessians at `Nt = 2^13`. HVP is the curvature primitive.
- This phase stays **above** truncated-Newton specifics. Krylov inner solves, preconditioning, and `forcing sequence` work belong to Phase 34. Phase 33 must leave a clean `DirectionSolver` interface so Phase 34 can plug under it.

### Claude's Discretion
- Choice between line search, trust region, or hybrid as the default (subject to the trade-off analysis in §Globalization Families).
- Exact telemetry schema (must extend Phase 28's `numerical_trust.jl` rather than fork a new one).
- Benchmark set *composition* (within the constraint that it draws from locked `(fiber, L, P)` configs Phase 13/22/35 already anchored to).

### Deferred Ideas (OUT OF SCOPE)
- Cubic-regularized Newton with explicit `σ` tuning (deferred to Phase 34+ — requires preconditioning work first).
- Second-order adjoint ODE (true analytic `H v` without finite differences) — seed `newton-method-implementation.md` keeps this on the shelf; Phase 33 uses FD-HVP.
- SAM / sharpness-in-objective (Phase 22 settled this — not the right axis).
- Reduced-basis continuation as part of the optimizer (Phase 31's problem; Phase 33 should *consume* a basis, not build one).
- Dense Hessian factorization (ruled out by `Nt = 2^13` ≈ 8192; storage alone is ~500 MB and decomposition ~O(Nt³)).

---

## Summary

The Raman-suppression optimization problem is **saddle-rich, indefinite-Hessian at every observed "optimum," and expensive per evaluation** (one `cost_and_gradient` ≈ 2 ODE solves; one HVP ≈ 2 additional gradient calls = 4 ODE solves). Phase 13 measured indefinite Hessians at both canonical L-BFGS endpoints; Phase 22 showed every sharpness flavor ended indefinite too; Phase 35 confirmed that in competitive dB territory, negative-curvature escape finds *better saddles*, not minima. Plain Newton — even with an exact HVP — would diverge or step backward: along a negative-curvature eigendirection, the "Newton step" points *uphill*.

The safe design is a **trust-region method with Steihaug–Toint truncated-CG on the indefinite Hessian**, fallback to a **negative-curvature step** when CG detects `p' H p ≤ 0`, and an acceptance ratio `ρ = actual / predicted reduction` that governs radius updates. Line search with strong-Wolfe is cheaper to implement but brittle on indefinite directions; line search + modified-Hessian (e.g., absolute-value eigenflip à la saddle-free Newton) is possible but harder to make honest about failure.

**Primary recommendation:** implement a **trust-region Newton method (TRN) with a Steihaug-style inner solver operating on the existing FD-HVP**. The inner solver is opaque behind a `DirectionSolver` trait; Phase 34 replaces the Steihaug solver with its preconditioned Krylov variant. Telemetry extends `scripts/numerical_trust.jl` with per-iteration trust-region state. Benchmark on three regimes drawn from existing JLD2 optima: `SMF-28 L=2m P=0.2W` (canonical, saddle-dominated), `HNLF L=0.5m P=0.01W` (HNLF canonical, distinct geometry), and `SMF-28 L=0.5m P=0.05W` ("simple phase" from Phase 17 — sharp basin, stress-tests over-aggressive radius growth).

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REQ-33-A | Safeguarded second-order optimizer path (`optimize_spectral_phase_tr`) parallel to L-BFGS, not replacing it | §Codebase Integration; mirrors Phase 14 constraint that original L-BFGS must stay byte-identical |
| REQ-33-B | Trust-region / line-search globalization policy with explicit indefinite-Hessian and gauge-null handling | §Globalization Families, §Step-Acceptance Policy |
| REQ-33-C | Direction-solver interface that Phase 34 can plug under without rewriting globalization | §Direction-Solver API |
| REQ-33-D | Per-iteration trust-report telemetry extending Phase 28's schema | §Failure Taxonomy and Telemetry |
| REQ-33-E | Benchmark set of `(fiber, L, P)` configs with published baseline `J_dB` from Phase 7/13/17 sweeps, and a per-run pass/fail contract | §Benchmark Set |
| REQ-33-F | Validation plan that does not reduce to "did we get a lower dB this time" | §Validation Plan |
| REQ-33-G | Honest failure taxonomy: every exit condition maps to a typed reason code, not "best achieved" | §Failure Taxonomy and Telemetry |

---

## Problem Framing — Why This Codebase Is Unusual

### The optimization problem

Minimize the Raman-band energy fraction over input spectral phase:

```
φ ∈ ℝ^{Nt}    (real-valued, one scalar per frequency bin; Nt = 2^13 for production)
J(φ) = 10 · log₁₀( ∫_Raman |U(L,ω)|² dω / ∫_full |U(L,ω)|² dω )
       + λ_gdd · ∫(d²φ/dω²)² dω
       + λ_bound · (edge-energy penalty)
```

`U(L,ω)` comes from propagating `u₀(ω) = uω0(ω) · exp(iφ(ω))` through the NLSE via `MultiModeNoise.solve_disp_mmf` (forward) and back-propagating the adjoint field (backward). Gradient is exact (`scripts/raman_optimization.jl:113–114`, chain rule through the adjoint). Log-scale cost was settled in Phase 8 (commit 2026-03-31, +20–28 dB improvement over linear).

### Three structural properties dictate everything below

1. **Expensive evaluation.** One `cost_and_gradient` call is 1 forward + 1 adjoint ODE solve through `Tsit5` at `Nt = 2^13, Nz = O(100)`. Wall time: ≈ 0.4 s on burst VM per call. An HVP is 2× that (FD central difference on the gradient). A trust-region iteration that does `k` inner CG steps costs `k+1` gradient calls plus 1 forward-only call for the ratio test. **Per-iteration budget matters more than iteration count** — we are not in the regime where doing 500 cheap Krylov steps is free.

2. **Indefinite Hessian at every reached stopping point.** Phase 13 (SMF-28 L=2m P=0.2W and HNLF L=0.5m P=0.01W) and Phase 22 (26/26 sharpness flavors, canonical + pareto-57) both measured `λ_min < 0 < λ_max` with `|λ_min|/λ_max` ranging 0.005–0.38. Phase 35's reduced-basis ladder confirmed this is **branch-structural**, not a convergence artifact: the competitive-dB branch *is* indefinite from `N_φ ≥ 8` through full resolution. Any direction-solver must treat negative curvature as the normal case, not an edge case.

3. **Gauge null space.** The cost is invariant under `φ → φ + C + α·(ω−ω_0)` (global phase + linear group delay, restricted to the input band). Analytically, this produces **two exact zero Hessian eigenvalues** along `{𝟙, ω−ω_band_center}`. Phase 13 Plan 02 confirmed these live in the ≈ 10⁻⁷–10⁻⁶ eigenvalue gap between the positive and negative wings; matrix-free Lanczos without shift-invert cannot resolve them directly, but any step must either project them out or suppress them by a penalty — otherwise the trust-region solver can make the radius grow to infinity along a zero-curvature direction that has no cost effect at all. The `gauge_fix` primitive in `scripts/primitives.jl` is the canonical projection operator.

### What "globalization" actually has to do here

Four concurrent jobs:

1. **Make Newton-like steps safe when `H` is indefinite.** Classical Newton `p = -H⁻¹ g` is an ascent direction along negative-curvature modes — unusable without modification.
2. **Accept or reject each step on evidence, not on "the gradient got smaller along this line."** Line search with Armijo measures the objective at a trial point; trust region measures *how well the local model predicted the actual change*.
3. **Handle the gauge null modes.** Step must not grow arbitrarily along `{𝟙, ω-linear}`; either project the solver subspace or add a mild Tikhonov regularizer on those modes.
4. **Log a typed exit reason.** "Hit max iter," "trust radius collapsed below `Δ_min`," "indefinite curvature with no usable negative-curvature direction," "gradient tolerance reached at an indefinite point" — each is a distinct scientific finding, not a synonym for "done."

This is the operational content of "globalization." It is not optional decoration around a Newton step; it *is* the algorithm.

---

## Globalization Families — Trade-off Analysis

Three standard families are viable. I evaluate each against the four concurrent jobs above plus the per-iteration budget.

### Table — head-to-head for this problem

| Criterion | Backtracking Line Search (Armijo + strong-Wolfe) | Trust-Region (Steihaug–Toint TRN) | Hybrid (LS outer, TR fallback on failure) |
|-----------|--------------------------------------------------|-----------------------------------|-------------------------------------------|
| **Handles indefinite H natively?** | No — requires modified Hessian (Bunch-Kaufman / `\|λ\|` eigenflip / Gauss-Newton approximation). Each mod destroys some curvature info. | Yes — Steihaug terminates at trust-region boundary on first negative-curvature direction; cubic-regularized Newton handles it by construction. | Only if TR branch is hit. |
| **Accepts honest model-quality evidence?** | Weak: Wolfe conditions check gradient decrease along one line, which is consistent with ending at saddles. | Strong: `ρ = actual/predicted` is exactly a model-quality test. | Mixed. |
| **Per-iteration cost at `Nt = 8192`?** | 1 full solve (direction) + 2–6 forward-only evals (line search bracket). ≈ 1–3 gradient calls total. | 1 gradient + `k` HVPs for Steihaug inner, typically `k ≤ 10` with warm start; ≈ 3–22 gradient-call-equivalents. ~5× LS in the worst case. | TR-dominated cost envelope. |
| **Failure telemetry clarity** | Medium — "line search failed" collapses several distinct failure modes into one. | High — Steihaug exit codes (CG converged, negative curvature hit, boundary hit) + `ρ` update rule give typed reasons. | High (inherits TR). |
| **Gauge-null handling** | Requires manual pre-step projection; easy to forget. | Natural: projected Krylov subspace in Steihaug stays orthogonal to the null space if `g` is projected first. | Natural. |
| **Implementation complexity** | Low — reuse `HagerZhang` from Optim.jl, ~150 LOC wrapper. | Medium — ~400 LOC: Steihaug inner solver + ρ-based radius update + negative-curvature fallback. | High — both plus dispatch. |
| **Contract cleanliness for Phase 34** | Poor — LS wants a `direction(x)` function; swapping in truncated-Newton inner solvers is awkward because line search doesn't know about inner iteration budget. | Excellent — Phase 34 replaces the `solve_subproblem(g, H_op, Δ)` callback; trust-region outer loop is unchanged. | Good (TR side). |
| **Literature support for this exact setup** | Nocedal & Wright Ch. 3 (classical), §3.5 specifically warns against LS with indefinite Hessian. | Conn-Gould-Toint (2000), Ch. 7; Steihaug (1983); Royer-O'Neill-Wright (2018, arXiv 1803.02924) with explicit complexity bounds for smooth nonconvex. | Nocedal & Wright §7.2; less literature. |

**Verdict:** Trust-region wins on every axis that matters for this problem except raw per-iteration cost. The cost differential is real but acceptable: we run O(10²) outer iterations in practice, not O(10⁴), and the HVP budget buys back more than it spends by taking bigger safe steps and exiting cleanly at saddles.

### Why cubic-regularized Newton (ARC) is not the Phase 33 default

Cubic regularization (Nesterov-Polyak 2006; Cartis-Gould-Toint ARC 2011) is theoretically cleaner than TR — it has global complexity guarantees to `(ε_g, ε_H)` second-order stationarity without an explicit radius parameter. But it requires either:
- an approximate solve of `min_p m(p) + (σ/3)‖p‖³`, which is essentially a regularized Newton subproblem itself, or
- an ARC inner solver that is not trivially matrix-free (the cubic term couples directions).

For Phase 33 (which has to ship an interface, a benchmark, and telemetry), TR + Steihaug is the simpler, better-documented, equally-safeguarded choice. ARC belongs to Phase 34 or a successor: once we have a robust Krylov inner solver and a cleaner conditioning story (Phase 28 continues), ARC can replace the TR radius update in a local change.

---

## Recommended Approach — Trust-Region Newton with Steihaug Inner Solve

### Algorithm (concrete)

```
Inputs:
  φ₀ ∈ ℝ^Nt            initial phase (zeros or warm start)
  Δ₀ > 0               initial trust radius (default: 0.5)
  Δ_max                max radius (default: 10.0)
  Δ_min                radius collapse threshold (default: 1e-6)
  η₁, η₂               acceptance thresholds (default: 0.25, 0.75)
  γ_shrink, γ_grow     radius update factors (default: 0.25, 2.0)
  g_tol                first-order stationarity tolerance (default: 1e-5)
  H_tol                second-order stationarity tolerance on λ_min (default: -1e-6)
  max_iter             outer iterations (default: 50)
  cg_max               inner Steihaug iterations per step (default: 20)

Repeat for k = 0, 1, 2, ...:
  1. Project g_k onto gauge-complement subspace: g_k ← (I - P_null) g_k
  2. If ‖g_k‖ < g_tol:
        estimate λ_min(H_k) via Arpack single-eigenvalue Lanczos (reuse phase13 path)
        if λ_min > H_tol: exit(CONVERGED_2ND_ORDER)
        else: set d = leftmost eigenvector; try negative-curvature step (see §Negative-Curvature Fallback)
              if no improvement: exit(SADDLE_STUCK, λ_min)
              else: continue
  3. Solve trust-region subproblem via Steihaug (§Steihaug Inner Solver):
        p_k, exit_code = steihaug(g_k, H_op_k, Δ_k, cg_max)
  4. Evaluate m_k(p_k) = g_k' p_k + 0.5 p_k' H_op_k(p_k)     (predicted reduction = -m_k)
  5. Evaluate J(φ_k + p_k) — one forward-only solve, no adjoint
     actual reduction Δf_k = J(φ_k) - J(φ_k + p_k)
     ρ_k = Δf_k / (-m_k)
  6. Radius update:
        if ρ_k < η₁:      Δ_{k+1} = γ_shrink * ‖p_k‖
        elif ρ_k > η₂ and ‖p_k‖ ≈ Δ_k:   Δ_{k+1} = min(γ_grow * Δ_k, Δ_max)
        else:             Δ_{k+1} = Δ_k
  7. Step acceptance:
        if ρ_k > η₁:      φ_{k+1} = φ_k + p_k  (full adjoint + gradient at new point)
        else:             φ_{k+1} = φ_k        (no gradient call — reuse g_k next iter)
  8. If Δ_{k+1} < Δ_min: exit(RADIUS_COLLAPSE)
  9. If k = max_iter: exit(MAX_ITER)
```

### Steihaug inner solver (truncated CG on possibly-indefinite H, constrained to ‖p‖ ≤ Δ)

Standard recipe (Steihaug 1983; Nocedal & Wright §7.2 Algorithm 7.2):

```
function steihaug(g, H_op, Δ, cg_max):
    p = 0;  r = g;  d = -g
    ε = min(0.5, ‖g‖^0.5) · ‖g‖       // forcing sequence (superlinear local)
    for j = 1:cg_max:
        Hd = H_op(d)
        if d' Hd ≤ 0:
            // Negative curvature detected. Step to trust-region boundary along d.
            τ = argmax{ m(p + τd) : ‖p + τd‖ = Δ, τ > 0 }
            return (p + τ·d, NEGATIVE_CURVATURE)
        α = (r' r) / (d' Hd)
        p_new = p + α·d
        if ‖p_new‖ ≥ Δ:
            τ = root{‖p + τd‖ = Δ, τ > 0}
            return (p + τ·d, BOUNDARY_HIT)
        p = p_new
        r_new = r + α·Hd
        if ‖r_new‖ ≤ ε: return (p, INTERIOR_CONVERGED)
        β = (r_new' r_new) / (r' r)
        d = -r_new + β·d
        r = r_new
    return (p, CG_MAX_ITER)
```

Each iteration is 1 HVP = 2 gradient calls at the base point ± `ε·d`. For `cg_max = 20`, worst-case inner cost is 40 gradient calls ≈ 80 ODE solves. In practice, for our problem size, inner CG terminates in 3–8 iterations most of the time (from numerical-analysis rule of thumb: Krylov converges in ≈ √κ steps; at the current Hessian spectra `κ` ranges 20–250, so √κ ∈ [4,16], matching budget).

### Negative-curvature fallback (for exit-on-saddle)

When `‖g‖ < g_tol` but `λ_min(H) < H_tol`, we are at a first-order stationary point that is a saddle, not a minimum. Options:

1. **Take a signed negative-curvature step** (Phase 35's recipe, now formalized): estimate the leftmost eigenpair `(λ_1, v_1)` via Arpack `eigs(..., :SR, nev=1)`. Step `φ ← φ ± α · v_1` with `α = sqrt(Δ / |λ_1|)` so `m(p) ≈ -0.5 |λ_1| · (Δ/|λ_1|) = -0.5 Δ` — a guaranteed predicted decrease of `Δ/2`. Evaluate `J`, accept or reject by `ρ`.
2. **Exit with typed reason `SADDLE_STUCK`** if the signed step does not decrease `J` for any sign within `α` range. Honest: we have proven (within numerical tolerance) that this saddle does not have an obvious escape direction at current resolution.

Both are logged. Phase 35 used option 1 manually; Phase 33 makes it automatic.

---

## Step-Acceptance Policy — Concrete Conditions

### The ratio `ρ` is the only acceptance test

```
ρ_k = [J(φ_k) - J(φ_k + p_k)] / [-m_k(p_k)]
    = actual reduction / predicted reduction
```

Interpretation:
- `ρ ≈ 1`: model is perfect. Step was a good quadratic approximation.
- `ρ ≈ 0.5`: model is OK. Take step, keep radius.
- `ρ < η₁ = 0.25`: model over-promised. **Reject** the step; shrink radius to `γ_shrink · ‖p_k‖` (not `γ_shrink · Δ_k` — shrink below the size of the rejected step).
- `ρ > η₂ = 0.75` *and* `‖p_k‖ ≈ Δ_k`: model under-promised and we hit the boundary. **Expand** radius to `min(γ_grow · Δ_k, Δ_max)`.
- `ρ < 0`: step *increased* cost (model wrong-signed). Shrink aggressively; never accept.

Classical values (Nocedal & Wright §4.1): `η₁ = 0.25, η₂ = 0.75, γ_shrink = 0.25, γ_grow = 2.0`. These are starting defaults. Phase 33 Wave 1 should sanity-check them against one benchmark config; if `ρ` is systematically clustered (e.g., > 0.9 almost always), the initial radius is too small and `Δ_max` can be raised.

### Why *not* a line-search Armijo/Wolfe check here

Classical strong-Wolfe conditions for a direction `p`:

```
Armijo:   J(φ + α p) ≤ J(φ) + c_1 · α · g' p       (sufficient decrease)
Curvature: |∇J(φ + α p)' p| ≤ c_2 · |g' p|          (sufficient gradient flattening)
```

Two problems for us:
- `g' p` must be negative for Armijo to be well-posed. When `H` is indefinite, the classical Newton direction `p = -H⁻¹ g` may satisfy `g' p > 0`. Every line-search Newton paper deals with this by first modifying `H` to positive-definite. That *is* a choice — but it's a choice made outside the telemetry, which makes the "why did this step happen" story less clean.
- Strong-Wolfe is fundamentally first-order. At a saddle with `‖g‖ ≈ 0`, any descent direction satisfies Armijo trivially (with slack); curvature condition satisfies trivially too. The line-search framework gives no signal that we are at a saddle.

TR with ρ-test is the native framework for indefinite, nonconvex, saddle-rich problems. This is not a stylistic preference — it is why Moré-Sorensen (1983), Conn-Gould-Toint (2000), and Royer-O'Neill-Wright (2018) all target the TR / cubic-regularized family for nonconvex smooth optimization with complexity guarantees.

### What "safeguarded" means operationally

A step `p_k` is safeguarded iff **all** of:

1. `‖p_k‖ ≤ Δ_k` (trust-region feasibility).
2. `p_k` lies in the gauge-complement subspace: `P_null · p_k ≈ 0` with tolerance `1e-10 · ‖p_k‖`.
3. Predicted reduction `-m_k(p_k) > 0` (direction actually reduces the model).
4. Actual reduction `Δf_k / (-m_k(p_k)) ≥ η₁` (model is at least 25% accurate).
5. `J(φ_k + p_k)` is finite; no NaN / Inf propagation through the forward solve.

A step that fails any of 1–5 is rejected. The rejection reason is logged. Over the lifetime of a run we count rejections by reason — one of the most informative telemetry signals (more on this in §Failure Taxonomy).

---

## Benchmark Set Proposal

### Design principles

- Use configs the project has **already converged and serialized** so baselines are immediate (no fresh L-BFGS runs just to have a comparison point).
- Span at least three geometric regimes: one saddle-dominated competitive branch, one distinct-fiber baseline (HNLF), and one unusual sharp-basin case (Phase 17's "simple profile").
- Small enough that one full benchmark sweep of the trust-region optimizer completes in ≈ 30–45 min of burst-VM wall time (each config ~10 min at `Nt = 2^13, max_iter = 40, ~5 HVPs/iter`).
- Each config has a reference `J_dB` from prior phases the new optimizer can be compared against. **Lower dB alone is not a success criterion** — we already know we can get lower dB by starting from phase 13 φ_opt and running more iterations. The point of the benchmark is *honesty*, not depth.

### Configs

| Tag | Fiber | L (m) | P (W) | Nt | Reference J_dB | Source | Why it's in the set |
|-----|-------|-------|-------|----|---------------:|--------|---------------------|
| `bench-01-smf28-canonical` | SMF-28 | 2.0 | 0.2 | 2^13 | −76.86 to −78.59 | Phase 13, Phase 22 canonical | Saddle-dominated competitive branch; Phase 13 Hessian is indefinite; most-studied config in the repo |
| `bench-02-hnlf-canonical` | HNLF | 0.5 | 0.01 | 2^13 | see Phase 13 hnlf_canonical | Phase 13 JLD2 | Distinct fiber physics + distinct Hessian spectrum (|λ_min|/λ_max = 0.41% vs SMF's 2.6%) — tests geometry robustness |
| `bench-03-smf28-simple` | SMF-28 | 0.5 | 0.05 | 2^13 | −76.86 (baseline), σ_3dB = 0.025 rad | Phase 17 SUMMARY | "Sharp basin" case. TR should find smaller acceptable radius here. Tests over-aggressive Δ growth. |
| `bench-04-pareto57` | SMF-28 | 2.0 | 0.2, Nφ=57 | 2^13 | −82.56 | Phase 22 pareto57 | Best-known reduced-basis point with Hessian indefinite; tests whether TR can hold a reduced-basis warm start |

Warm starts and cold starts for each:
- **Cold start**: `φ₀ = 0`. Tests whether TR gets to competitive dB without warm-start help.
- **Warm start from L-BFGS converged `φ*_lbfgs`**: the interesting case — can TR refine a saddle into something with smaller `|λ_min|`?
- **Warm start from a perturbed `φ*_lbfgs + 0.05·ξ, ξ ~ 𝒩(0,I)`**: stresses the radius controller. A good policy absorbs the perturbation cleanly; a bad one oscillates.

### Total evaluation budget

4 configs × 3 start types = 12 runs. At ~10 min/run on burst = 2 h wall time. Single burst-run-heavy session. Output is one JLD2 per run plus the 4-panel standard image set (mandatory per CLAUDE.md). Phase 33 does *not* attempt a full multi-start study — that's Phase 34 territory once the direction solver is nailed.

### Non-goal

We are **not** trying to beat L-BFGS on `J_dB`. The audit history (Phase 27 second opinion, Phase 35 report) makes clear that raw dB is a weak figure of merit in a saddle-rich landscape. The benchmark measures:
- does TR converge to a claimed second-order stationary point (CONVERGED_2ND_ORDER)?
- does it converge to a claimed first-order stationary saddle with reported `λ_min`?
- how many HVPs / gradient calls did it take?
- how does `‖g‖`, `Δ`, `ρ` evolve per iteration?
- does the standard 4-panel image set show a physically sensible `φ_opt`?

These are the success signals.

---

## Failure Taxonomy and Per-Iteration Telemetry

### Exit codes (typed, mutually exclusive)

| Code | When | Scientific meaning |
|------|------|---------------------|
| `CONVERGED_2ND_ORDER` | `‖g‖ < g_tol` AND `λ_min(H) > H_tol` | True local minimum (modulo tolerances). Rare in this project. |
| `CONVERGED_1ST_ORDER_SADDLE` | `‖g‖ < g_tol` AND `λ_min(H) < H_tol` AND neg-curv step did not decrease `J` | First-order stationary saddle. Honest statement of "this is as far as local curvature-aware descent goes from here." |
| `RADIUS_COLLAPSE` | `Δ < Δ_min` | Model keeps over-promising. Either `g` computation is wrong, grid/ODE numerics are insufficient, or we are wedged between two negative-curvature directions. |
| `MAX_ITER` | `k = max_iter` with still-improving `J` | User under-budgeted. Not a pathology by itself. |
| `MAX_ITER_STALLED` | `k = max_iter` with no improvement in the last `M` iterations | Budget exhausted in a flat region. Different signal than above. |
| `NAN_IN_OBJECTIVE` | `J(φ + p) = NaN` or `Inf` | Hard numerics failure; grid / time-window audit needed. |
| `GAUGE_LEAK` | `‖P_null · p_k‖ > 1e-8 · ‖p_k‖` on any accepted step | Projection broke; bug report, not a result. |

Every run reports exactly one exit code.

### Per-iteration telemetry (extends Phase 28 `numerical_trust.jl` schema)

Every iteration appends a row:

```julia
struct TRIterationRecord
    iter::Int
    J::Float64                  # dB
    grad_norm::Float64          # ‖g_k‖ in phase-units (post gauge-projection)
    delta::Float64              # trust radius Δ_k
    rho::Float64                # actual/predicted ratio (NaN if step rejected)
    pred_reduction::Float64     # -m_k(p_k)
    actual_reduction::Float64   # J_k - J_{k+1}
    step_norm::Float64          # ‖p_k‖
    step_accepted::Bool
    cg_iters::Int               # Steihaug inner iterations taken
    cg_exit::Symbol             # :INTERIOR_CONVERGED | :BOUNDARY_HIT | :NEGATIVE_CURVATURE | :CG_MAX_ITER
    lambda_min_est::Float64     # leftmost Hessian eigenvalue estimate (only at ‖g‖ < g_tol checkpoints to amortize cost)
    lambda_max_est::Float64     # rightmost eigenvalue estimate (same cadence)
    kappa_eff::Float64          # λ_max / max(|λ_min_nonzero|, eps) — Phase 27 Sec 2nd opinion item 9
    hvps_this_iter::Int
    grad_calls_this_iter::Int
    forward_only_calls_this_iter::Int
    wall_time_s::Float64
end
```

The `kappa_eff` column is the condition-number probe Phase 27's second-opinion §item 9 flagged as "almost free." Reuse Arpack from `hessian_eigspec.jl`; run it on a schedule (every 10 iters + at exit) to amortize cost.

A run's telemetry is saved as:
- `results/raman/phase33/<tag>/telemetry.csv` — one row per iteration
- `results/raman/phase33/<tag>/trust_report.md` — extends the Phase 28 trust report with an `## Optimizer (Trust-Region)` section containing exit code, final `ρ` statistics, rejection count by cause, and HVP budget used
- `results/raman/phase33/<tag>/_result.jld2` — `phi_opt`, full telemetry, references to the benchmark tag

### Rejection breakdown

Sum across the run:
```
rejections_by_cause = Dict(
  :rho_too_small          => count(r.rho < η₁ && r.step_accepted == false),
  :negative_curvature     => count(r.cg_exit == :NEGATIVE_CURVATURE),
  :boundary_hit           => count(r.cg_exit == :BOUNDARY_HIT),
  :cg_max_iter            => count(r.cg_exit == :CG_MAX_ITER),
  :nan_at_trial_point     => count(isnan(r.rho)),
)
```

These are the most diagnostic numbers a TR run produces. A healthy run has rejection rate 5–20% and mostly `:rho_too_small`. A run that's almost all `:negative_curvature` is saddle-dodging; a run that's almost all `:boundary_hit` has `Δ_max` set too low.

---

## Direction-Solver API — The Phase 34 Hand-Off Boundary

### The interface Phase 33 must lock

```julia
abstract type DirectionSolver end

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

Returns:
  SubproblemResult with fields:
    p::Vector{Float64}           — approximate solution
    pred_reduction::Float64      — -m(p), guaranteed ≥ 0
    exit_code::Symbol            — :INTERIOR_CONVERGED | :BOUNDARY_HIT |
                                    :NEGATIVE_CURVATURE | :MAX_ITER
    inner_iters::Int             — iterations taken
    hvps_used::Int               — HVPs consumed this call
"""
function solve_subproblem end
```

### Concrete implementations

**Phase 33 ships:**
```julia
struct SteihaugSolver <: DirectionSolver
    max_iter::Int = 20
    tol_forcing::Function = g -> min(0.5, sqrt(norm(g))) * norm(g)
end
```

**Phase 34 will add (as read-only consumers of the same API):**
```julia
struct PreconditionedCGSolver <: DirectionSolver
    max_iter::Int
    preconditioner::Symbol  # :none | :diagonal | :lanczos_precond
    tol_forcing::Function
end

struct CubicRegularizedSolver <: DirectionSolver
    sigma::Float64
    inner_solver::DirectionSolver   # plugged subproblem
end
```

### What the boundary guarantees

Phase 34 adds implementations but **does not touch** the trust-region outer loop, the telemetry schema, the exit-code taxonomy, the benchmark runner, or the acceptance-ratio logic. This is the "separation of concerns" Phase 33 is contractually required to produce (CONTEXT.md locked decision: "second-order search directions and globalization are separate design choices").

Caller contract:
- `H_op` is *guaranteed* symmetric up to FD noise (see `hvp.jl:89 — HVP symmetry`). Solvers may assume this.
- `g` is *guaranteed* in the gauge-complement subspace (projection happens at the outer TR level).
- `Δ > 0` always.
- `p` on return must satisfy `‖p‖ ≤ Δ · (1 + 1e-8)` (small tolerance for numerics).
- `pred_reduction ≥ 0` always — if the solver cannot make progress, it returns `p = 0`, `pred_reduction = 0`, `exit_code = :NO_DESCENT` and the outer loop exits cleanly.

---

## Codebase Integration Plan

### Files to add (net new)

| File | Purpose | Size estimate |
|------|---------|---------------|
| `scripts/trust_region_core.jl` | `TrustRegionState`, `DirectionSolver` abstract, `SteihaugSolver`, ρ-based radius update, exit-code enum | ~450 LOC |
| `scripts/trust_region_optimize.jl` | `optimize_spectral_phase_tr(...)` — the top-level entry point. Mirrors `optimize_spectral_phase` from `raman_optimization.jl` but swaps L-BFGS for TRN | ~200 LOC |
| `scripts/trust_region_telemetry.jl` | Telemetry records + CSV/JSON writers + extension of `numerical_trust.jl` schema | ~250 LOC |
| `scripts/benchmark_run.jl` | Benchmark driver: iterates over the 4 configs × 3 start types, runs TR, emits standard images + telemetry | ~350 LOC |
| `test/test_trust_region_steihaug.jl` | Unit tests for Steihaug solver against analytic quadratic problems (easy to verify exactly); Taylor-slope test on TR step predictions | ~200 LOC |
| `test/test_trust_region_integration.jl` | Integration test: small `Nt = 2^8` Raman setup, full TR run, assert exit code + finite `phi_opt` | ~150 LOC |

### Files to read-only consume (must NOT modify)

Per CLAUDE.md Rule P1 and Phase 14 precedent (original optimizer untouched):
- `scripts/raman_optimization.jl` — `cost_and_gradient` is the HVP oracle. Do not modify.
- `scripts/common.jl` — `setup_raman_problem`, `spectral_band_cost`, fiber presets. Untouched.
- `scripts/hvp.jl` — `fd_hvp`, `build_oracle`, `ensure_deterministic_fftw`. Reuse.
- `scripts/primitives.jl` — `gauge_fix`, `input_band_mask`, `omega_vector`. Reuse.
- `scripts/hessian_eigspec.jl` — Arpack wrapper for single-eigenvalue Lanczos. Reuse for `λ_min` estimates.
- `scripts/numerical_trust.jl` — Phase 28 schema. **Extend, not fork.**
- `scripts/determinism.jl` — `ensure_deterministic_environment()` called at entry.
- `scripts/standard_images.jl` — `save_standard_set(...)` called at exit of every benchmark config. **Mandatory per CLAUDE.md.**
- `src/simulation/*.jl` — never touched.

### Entry-point contract

```julia
# scripts/trust_region_optimize.jl

function optimize_spectral_phase_tr(uω0, fiber, sim, band_mask;
    φ0 = nothing,
    solver::DirectionSolver = SteihaugSolver(),
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
    log_cost::Bool = true,
    telemetry_path::Union{Nothing,String} = nothing,
) -> TrustRegionResult
```

Signature parallels `optimize_spectral_phase` so callers can swap L-BFGS ↔ TR by renaming the function. `TrustRegionResult` has a `.minimizer` field mimicking Optim.jl's return so downstream plotting code (`save_standard_set`) works unchanged.

### Wave structure (planner will refine)

Roughly:

- **Wave 0**: test scaffolding + quadratic-model unit tests for Steihaug.
- **Wave 1**: TR core + Steihaug solver + telemetry. Integration test on `Nt = 2^8` Raman problem.
- **Wave 2**: Benchmark driver + run 4 configs × 3 starts on burst VM. Standard images mandatory.
- **Wave 3**: Trust-report synthesis + benchmark summary markdown + `SUMMARY.md`.

---

## Pitfalls and Mitigations

Drawn from Phase 13, 22, 27, 28, 35.

### P1. Gauge null modes inflate trust radius silently
**Origin:** Phase 13 Plan 02 — the analytic 2-mode null space of the cost is invisible to matrix-free Lanczos (it falls in the 10⁻⁷–10⁻⁶ eigenvalue gap), so `H v ≈ 0` for `v ∈ span{𝟙, ω-linear}`. Without projection, Steihaug's "negative curvature" test `d' H d ≤ 0` can evaluate to ≈ 0, which is *not* a CG termination condition — CG will then step arbitrarily far along the null direction until it hits the trust boundary, and `pred_reduction = 0` will give `ρ = 0/0 = NaN`.
**Mitigation:** Project `g` onto the gauge-complement subspace *at every iteration* using `gauge_fix` machinery. Also project every candidate `p_k` before the ρ test. Add a hard assertion that `‖P_null · p‖ ≤ 1e-10 · ‖p‖`; failure → `GAUGE_LEAK` exit.

### P2. HVP noise floor degrades ρ at deep suppression
**Origin:** Phase 27 second-opinion §item 5 — FD-HVP with fixed `ε = 1e-4` is well outside the optimal step for `‖g‖ ≈ 10⁻⁸` (which we reach at −75 to −80 dB). Ripple in the predicted reduction `m_k(p_k)` can be comparable to the actual reduction `Δf_k`, making ρ noise-dominated.
**Mitigation:** Use the adaptive rule `ε_hvp = sqrt(eps_mach · max(1, ‖g_k‖)) / max(1, ‖v‖)` from Phase 27's second-opinion recommendation. Plumb this through `fd_hvp(...; eps=<adaptive>)`. Log `ε_hvp` each iter in telemetry so after-the-fact we can see whether noise dominated.

### P3. Log-scale cost gradient has `1/J_dB` singularity as J → 0
**Origin:** `raman_optimization.jl:167–171`. `log_scale = 10 / (J_clamped · ln 10)`. As `J → 0` (great Raman suppression), `log_scale → ∞`. Gradient magnitude blows up; any step that tries to descend further gets amplified; ρ misbehaves.
**Mitigation:** (a) Clamp `log_scale` at an upper bound (say `1e12`) and log whenever clamp fires — this signals we are at the edge of where log-scale cost is well-defined. (b) Consider running the TR benchmark with `log_cost=false` for a sanity-check pass (linear physics cost) — this is also what `hvp.jl:build_oracle` uses for the HVP, so it keeps the Hessian probe and the optimization objective consistent. Worth planning Wave 1 around `log_cost=false` and adding `log_cost=true` runs only after the linear case works.

### P4. Regularizer gradient not log-rescaled
**Origin:** Phase 27 second-opinion §item 2. `cost_and_gradient` log-rescales the *total* gradient including regularizer gradients. Effective `λ_gdd` shifts from 1e-4 at `J = 1` to 1e-12 at `J = 10⁻⁸`, i.e., the regularizer effectively vanishes as we get better at Raman suppression. This contaminates comparisons.
**Mitigation:** For Phase 33 benchmark set, use `λ_gdd = 0, λ_boundary = 0` (pure physics cost). Document this explicitly in the run config. Phase 28 follow-up work will fix the rescaling issue structurally; Phase 33 sidesteps it rather than inheriting the contamination.

### P5. FFTW plan non-determinism across fresh processes would destroy ρ
**Origin:** Phase 15 / Phase 13 Plan 01. Without `ensure_deterministic_environment()` + `FFTW.ESTIMATE`, two forward solves of the same `(φ, fiber, sim)` differ at `1e-13` level — small, but `actual_reduction` at deep suppression can itself be `O(1e-5)`, so spurious process-to-process drift can pollute ρ.
**Mitigation:** `ensure_deterministic_environment()` + `ensure_deterministic_fftw()` at script entry, mandatory. Telemetry logs FFTW/BLAS thread counts.

### P6. Trust-region radius in what norm?
**Subtle issue:** `‖p‖` in `ℝ^{Nt}` is unit-dependent — `φ` is in radians, but if the code flattens `(Nt, M)` differently than the gradient, `‖·‖₂` misbehaves. Also, "natural" step size differs between low-frequency modes (where `φ` varies slowly) and high-frequency modes. A pure `‖·‖₂` trust region treats all modes equally, which is wrong when the spectrum has `λ_max/|λ_min_nonzero| = O(100)`.
**Mitigation:** Start with plain `‖p‖₂`. Add in the plan's Wave 3 "future work" note: an ellipsoidal trust region `p' M p ≤ Δ²` with `M ≈ diag(H)` or a cheap preconditioner matches Phase 34's preconditioning agenda naturally. Phase 33 leaves a documented TODO in the code.

### P7. Negative-curvature step amplitude is theory-sensitive
**Origin:** Phase 35 Plan 01 — the step `α · v_1` with `α = sqrt(Δ / |λ_1|)` has a sign ambiguity and requires `J`-evaluation at both `±α v_1`.
**Mitigation:** Evaluate both. Accept the sign that lowers `J` the most; reject if neither does. Log as `:negative_curvature_tried_both_signs` in telemetry if neither accepts.

### P8. Boundary absorption silent leak
**Origin:** Phase 27 second-opinion §item 6 — the super-Gaussian-30 attenuator at the time-window edge absorbs energy silently. A great `J` at deep suppression may be partly "energy that walked off the grid."
**Mitigation:** Inherit Phase 28's edge-fraction telemetry. Already wired into `numerical_trust.jl` (`TRUST_THRESHOLDS.edge_frac_pass = 1e-3`). TR benchmark aborts any run with `MARGINAL` or `SUSPECT` boundary status — it would be scientifically meaningless.

---

## Validation Plan

### How we know the optimizer is correctly implemented (not just "sometimes gets lower dB")

| Test | What it proves | Where |
|------|----------------|-------|
| **Unit: Steihaug on analytic strictly-convex quadratic** | CG inner loop is correct. For `f(p) = 0.5 p'Ap + b'p` with SPD `A`, Steihaug should either hit `A⁻¹(-b)` or boundary, with `pred_reduction = 0.5 b' A⁻¹ b - 0.5 (p-p*)'A(p-p*)` analytically. | `test/test_trust_region_steihaug.jl::test_spd_quadratic` |
| **Unit: Steihaug on analytic indefinite quadratic** | Negative-curvature detection works. For `A = diag(+1, -1)`, the step `p` should lie on the trust boundary in the −1 eigendirection for any `‖g‖ > 0`. | `test/test_trust_region_steihaug.jl::test_indefinite_quadratic` |
| **Unit: ρ update rule deterministic** | Given a synthetic sequence of `(J_k, m_k, Δ_k, p_k)`, verify Δ updates match the Nocedal & Wright Algorithm 4.1 table entries exactly. | `test/test_trust_region_steihaug.jl::test_radius_update_table` |
| **Unit: gauge projection preserves `‖Π p‖ ≤ ‖p‖`** | Our projection is a real orthogonal projection. | `test/test_trust_region_integration.jl::test_gauge_projection_properties` |
| **Integration: small-Nt Raman TR run** | End-to-end at `Nt = 2^8` completes, exit code is one of the typed set, `save_standard_set` writes images, telemetry CSV is valid. No `NAN` or `GAUGE_LEAK`. | `test/test_trust_region_integration.jl::test_raman_tr_smallNt` |
| **Regression: L-BFGS path unchanged** | Running `test/test_determinism.jl` + `test/test_phase28_trust_report.jl` still passes byte-for-byte. | Existing test files — no changes. |
| **Benchmark: TR from `φ*_lbfgs` → same `φ` within gauge** | On `bench-01-smf28-canonical`, if we start TR at the L-BFGS converged optimum, within a few iterations TR either (a) declares `CONVERGED_2ND_ORDER` if by some miracle the Hessian flipped to PD, or more realistically (b) takes a negative-curvature escape (as Phase 35 did) and reaches a deeper saddle, or (c) declares `CONVERGED_1ST_ORDER_SADDLE` if the saddle has no usable escape. All three are *valid* — the point is it doesn't diverge, NaN, or silently log "best achieved." | `scripts/benchmark_run.jl` |
| **Benchmark: ρ distribution is sensible** | Across all 12 benchmark runs, the distribution of accepted `ρ`-values has mean in [0.3, 1.5] and no more than 15% of iterations rejected. Rejection-by-cause histogram is interpretable. | Benchmark synthesis markdown |
| **Benchmark: exit-code distribution** | All 12 runs exit with a typed code. No run silently hits `max_iter` without either `MAX_ITER_STALLED` or `MAX_ITER`. `GAUGE_LEAK` never fires. | Benchmark synthesis markdown |

### Not a success criterion
- Lower `J_dB` than Phase 13's L-BFGS baseline. (Maybe yes, maybe no — both outcomes are scientifically informative. A TR that declares `CONVERGED_1ST_ORDER_SADDLE` with honest telemetry is a better phase deliverable than a TR that happens to reach −80 dB but has `GAUGE_LEAK` firings or NaN'd ρ.)

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Forward / adjoint ODE solves | `src/simulation/*.jl` | — | Physics layer; unchanged by this phase |
| HVP finite-difference | `scripts/hvp.jl` | — | Existing matrix-free curvature primitive |
| Gradient oracle | `scripts/raman_optimization.jl::cost_and_gradient` | — | Unchanged; called via `build_oracle` |
| Trust-region outer loop | `scripts/trust_region_core.jl` (NEW) | — | Globalization logic — Phase 33's core contribution |
| Direction subproblem solver | `scripts/trust_region_core.jl::SteihaugSolver` (NEW) | `DirectionSolver` trait (NEW); Phase 34 adds concrete variants | Pluggable by design |
| Gauge projection | `scripts/primitives.jl::gauge_fix` | — | Existing primitive, reused |
| λ_min/λ_max probes | `scripts/hessian_eigspec.jl` (Arpack) | — | Existing matrix-free Lanczos, reused |
| Telemetry schema | `scripts/trust_region_telemetry.jl` (NEW) + `scripts/numerical_trust.jl` (extend) | — | Extends Phase 28, does not fork |
| Standard images | `scripts/standard_images.jl::save_standard_set` | — | Mandatory per CLAUDE.md |
| Determinism | `scripts/determinism.jl` | `scripts/hvp.jl::ensure_deterministic_fftw` | Entry-point call, per Phase 15 convention |
| Benchmark driver | `scripts/benchmark_run.jl` (NEW) | — | Orchestrates the 12 runs |
| Burst-VM execution | `~/bin/burst-run-heavy` wrapper | — | Mandatory per CLAUDE.md Rule P5 |

---

## Standard Stack

### Core (already in project; no new deps)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Optim.jl | 1.13.3 | `LBFGS()` used as reference / regression baseline only | Locked by Manifest |
| Arpack.jl | project-installed | Matrix-free Lanczos for `λ_min`, `λ_max` probes | Phase 13 already uses this |
| DifferentialEquations.jl | project-installed | `Tsit5()` ODE solver, unchanged | Physics layer |
| FFTW | project-installed, ESTIMATE mode | Deterministic FFT for reproducible HVPs | Phase 15 locked |
| JLD2, JSON3 | project-installed | Result + telemetry persistence | Standard project I/O |
| PyPlot | project-installed | 4-panel standard images | Mandatory per CLAUDE.md |

### Alternatives Considered (and rejected for this phase)

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled Steihaug | `Krylov.jl::cg` with custom termination | Krylov.jl is overkill and introduces a new dep; Steihaug is 100 LOC and the termination logic is what we want to *audit*, not outsource |
| Trust region from Optim.jl | `Optim.NewtonTrustRegion` | Requires dense or approximate Hessian; does not compose with our matrix-free HVP oracle; no exposed `DirectionSolver` hook for Phase 34 |
| `ManOpt.jl` | Riemannian TR | Overkill and gauge modes are not a Riemannian problem — they are a linear null space, cleanly handled by projection |
| ARC (cubic-regularized Newton) | Cartis-Gould-Toint 2011 | Better theory; strictly more complex. Deferred to Phase 34+ |

### Installation

No new packages. Verify existing versions:

```julia
using Pkg; Pkg.status(["Optim", "Arpack", "DifferentialEquations", "FFTW", "JLD2", "JSON3"])
```

---

## State of the Art (contextualized, not survey)

Nonconvex TR and its siblings are a mature area. The methods Phase 33 uses are not research frontiers — they are the textbook canon. The *combination* (matrix-free HVP + Steihaug TR + typed failure accounting + gauge-projected step + indefinite-native acceptance) is not novel either but is applied in this codebase for the first time.

| Old approach (in this repo) | Current approach (Phase 33) | When changed | Impact |
|-----------------------------|----------------------------|--------------|--------|
| L-BFGS with HagerZhang strong-Wolfe line search | Trust-region Newton with Steihaug inner solver | This phase | Honest saddle handling, typed failure codes, direction-solver API for Phase 34 |
| Dense Hessian eigendecomposition with no optimizer feedback (Phase 13) | Matrix-free Hessian used *in* the optimizer loop | This phase | Curvature becomes a direction, not just a diagnostic |
| SAM / `trH` / MC sharpness penalties (Phase 22) | Sharpness penalty retired as the wrong axis; saddle-aware method chosen instead | Phase 35 verdict, Phase 33 execution | Aligned with the geometry evidence |
| Manual Phase 35 negative-curvature escape | Automatic within-optimizer negative-curvature fallback | This phase | Reproducible; integrated with trust-region acceptance |

---

## External References (section-specific)

- **Nocedal, J. and Wright, S. J. (2006). *Numerical Optimization* (2nd ed.). Springer.**
  - Ch. 3 (Line Search Methods): §3.1–3.2 Wolfe conditions, §3.5 caveats on indefinite Hessians.
  - Ch. 4 (Trust Region Methods): **§4.1** TR algorithm template — the `ρ`-test acceptance logic used here verbatim. **§4.2** Cauchy point and dogleg (pedagogical context for Steihaug). **§4.3** Steihaug's method.
  - Ch. 6 (Quasi-Newton): background on L-BFGS for comparison.
  - Ch. 7 (Large-Scale Unconstrained): §7.2 Inexact Newton and Steihaug-CG specifically.
- **Conn, A. R., Gould, N. I. M., Toint, P. L. (2000). *Trust-Region Methods*. MPS-SIAM.**
  - Ch. 6: global convergence for nonconvex TR (this is the proof that Phase 33's exit codes are *provably* what they claim to be, given assumptions).
  - Ch. 7: solving the TR subproblem — Steihaug in §7.5.
- **Steihaug, T. (1983). "The conjugate gradient method and trust regions in large scale optimization." *SIAM J. Numer. Anal.* 20(3), 626–637.** The original paper for the inner solver.
- **Royer, C. W., O'Neill, M., Wright, S. J. (2018). "A Newton-CG algorithm with complexity guarantees for smooth unconstrained optimization." arXiv:1803.02924.** Modern complexity analysis of exactly the Steihaug-CG + negative-curvature-step combination we plan; anchors the claim that this framework has second-order stationarity guarantees in expectation (under standard assumptions).
- **Nesterov, Y. and Polyak, B. T. (2006). "Cubic regularization of Newton method and its global performance." *Math. Program.* 108, 177–205.** For Phase 34+: ARC context.
- **Cartis, C., Gould, N. I. M., Toint, P. L. (2011). "Adaptive cubic regularisation methods for unconstrained optimization. Part I/II." *Math. Program.* 127, 245–319.** ARC algorithm (Phase 34+).
- **Jin, C., Ge, R., Netrapalli, P., Kakade, S. M., Jordan, M. I. (2017). "How to Escape Saddle Points Efficiently." *ICML 2017*, PMLR 70.** Background on strict-saddle escape that informs the negative-curvature fallback. Phase 35 already relied on this framing.
- **Phase 13 FINDINGS** (`results/raman/phase13/FINDINGS.md`) — repo-internal, primary evidence for the Hessian spectrum and gauge null structure.
- **Phase 22 SUMMARY** (`.planning/phases/22-sharpness-research/SUMMARY.md`) — 26/26 indefinite optima across sharpness flavors.
- **Phase 27 REPORT** (`.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md`) and its **second-opinion addendum** — the reason this phase exists at all.
- **Phase 35 REPORT** (`.planning/phases/35-saddle-escape/35-REPORT.md`) — the verdict that negative-curvature escape finds *better saddles*, not minima; directly motivates the choice of TR over plain Newton.

### CS 4220 (Bindel, Cornell) lecture correspondences

- Lecture/notes on line search vs trust region (expected early semester optimization block): §Globalization Families here is the direct application.
- Lecture on Krylov methods (mid semester): Steihaug-CG and the forcing sequence choice.
- Lecture on nonconvex optimization: saddle-point escape and negative-curvature steps.

Phase 27 already crosswalked these. Phase 33 does not need to re-do that crosswalk; it applies the conclusions.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Julia | All scripts | ✓ | ≥ 1.9 (Manifest pinned 1.12.4) | — |
| Optim.jl | L-BFGS baseline comparisons | ✓ | 1.13.3 | — |
| Arpack.jl | λ_min / λ_max probes | ✓ | project-installed | — |
| FFTW (ESTIMATE mode) | Deterministic HVPs | ✓ | project-installed | — |
| DifferentialEquations.jl | Forward + adjoint ODEs | ✓ | project-installed | — |
| JLD2, JSON3 | Telemetry persistence | ✓ | project-installed | — |
| PyPlot / matplotlib | Standard image set | ✓ | project-installed | — |
| burst-run-heavy wrapper | Heavy compute runs | ✓ | `~/bin/burst-run-heavy` | — |
| `fiber-raman-burst` VM | 2h benchmark suite | ✓ (on-demand) | c3-highcpu-22 | — |

All dependencies available. No new installs required.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Per-HVP cost is ≈ 2× per-gradient cost (FD central difference) | §Problem Framing | Underestimates Phase 33 wall-time budget by up to 2×. Mitigation: Wave 1 benchmark timing. |
| A2 | Steihaug inner CG converges in 3–8 iters on our spectra (√κ rule of thumb) | §Recommended Approach | Could be 20+ if conditioning is worse than measured; Phase 28 conditioning audit may reveal higher κ. Either way, the `cg_max = 20` cap bounds worst case. |
| A3 | `Δ₀ = 0.5` and classical `(η₁, η₂, γ_shrink, γ_grow) = (0.25, 0.75, 0.25, 2.0)` will work out of the box | §Step-Acceptance Policy | Nocedal & Wright defaults; empirically robust across many problems. If Wave 2 benchmark shows pathological ρ distribution, Wave 3 retunes. |
| A4 | Matrix-free Lanczos for `λ_min` estimate is affordable on schedule (every 10 iters + at exit) | §Failure Taxonomy | Arpack :SR with `nev=1` costs ≈ 20–40 HVPs per call (Phase 13 wall time: ~30 s for `nev=20`; `nev=1` is ~3–5 s); comfortable. |
| A5 | Phase 28's `numerical_trust.jl` schema is stable enough to extend | §Codebase Integration | Schema version is "28.0"; Phase 28 is partially executed. If schema changes mid-Phase-33, extension may break. Mitigation: Phase 33 subtypes `TRIterationRecord` lives in its own file. |
| A6 | Gauge projection (`gauge_fix`) correctly kills the 2 analytic null modes at each iteration, even after many TR steps | §Pitfalls P1 | Numerical drift possible over long runs. Unit test asserts `‖P_null · p‖ ≤ 1e-10 · ‖p‖` every iteration. |
| A7 | Log-cost clamp at J_clamped = 1e-15 is a safe lower bound for the benchmark regime | §Pitfalls P3 | Benchmark configs achieve J_dB ≈ -80 (J ≈ 1e-8), well above clamp. If future runs target -150 dB, clamp needs raising. |
| A8 | `λ_gdd = 0, λ_boundary = 0` for Phase 33 benchmark sidesteps the regularizer rescaling issue | §Pitfalls P4 | Phase 27 finding — waiting on Phase 28 structural fix. Benchmark documents this choice explicitly. |

**Confirmed (VERIFIED) claims (not assumed):** HVP primitive exists and is Taylor-validated (`scripts/hvp.jl:190`). Arpack Lanczos works matrix-free (`scripts/hessian_eigspec.jl:~200`). Hessian is indefinite at canonical optima (Phase 13 FINDINGS, Phase 22 SUMMARY, Phase 35 REPORT). L-BFGS with strong-Wolfe is the current 1st-order globalized baseline (`scripts/raman_optimization.jl:219–234`). Determinism contract is live (`test/test_determinism.jl` passes bit-identity). Standard-image mandate is project-wide (CLAUDE.md). Benchmark config `(SMF-28, L=2m, P=0.2W)` has an existing L-BFGS converged optimum serialized (`results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2`).

---

## Project Constraints (from CLAUDE.md)

- **Tech stack locked:** Julia + PyPlot. No new visualization deps.
- **Every optimization driver must call `save_standard_set(...)`** before exit. 4-panel per-run images are non-negotiable.
- **Heavy runs via `~/bin/burst-run-heavy`** with unique session tag `^[A-Za-z]-[A-Za-z0-9_-]+$`. Propose tag: `P-phase33-tr` for the benchmark sweep.
- **Deterministic numerics:** `ensure_deterministic_environment()` + `ensure_deterministic_fftw()` called at script entry. FFTW.ESTIMATE, single-threaded BLAS.
- **Adjoint is exact;** HVPs are finite-difference of the adjoint gradient (Phase 13).
- **Log-cost convention:** `10·log10(J)` with gradient scaling `10/(J·ln10)` is the project default (commit 2026-03-31). Phase 33 benchmark pins `log_cost=true` for apples-to-apples with L-BFGS baseline, and a `log_cost=false` sanity pass for Hessian-probe consistency.
- **GSD strict mode:** all source edits route through `/gsd-fast`, `/gsd-quick`, or `/gsd-execute-phase`. Direct edits to `scripts/*.jl` or `src/*.jl` are hard-denied by the workflow guard.
- **Burst VM hygiene:** `burst-start` → run via `burst-run-heavy` → `burst-stop` afterward. Never leave the VM up overnight without an active job.
- **Rule P1 namespace:** phase namespace is `.planning/phases/33-globalized-second-order-optimization-for-raman-suppression/` + `scripts/trust_region_*.jl` + `results/raman/phase33/`. Do not touch `scripts/common.jl`, `scripts/raman_optimization.jl`, or `src/simulation/*.jl`.

---

## Open Questions

1. **Should the TR benchmark run `log_cost=true` or `log_cost=false`?**
   - What we know: L-BFGS runs with `log_cost=true` (project default since 2026-03-31). HVP oracle uses `log_cost=false` (clean physics Hessian).
   - What's unclear: a TR optimizer that minimizes `log_cost=true` cost but uses `log_cost=false` Hessian is probing the wrong surface — Phase 27 second-opinion §item 3 flags this as a real hazard.
   - Recommendation: Wave 1 runs `log_cost=false` (physics cost, clean Hessian). Wave 2 adds `log_cost=true` runs *only if* Wave 1 ρ distribution is healthy. Both variants captured in telemetry.

2. **Is Δ₀ = 0.5 the right initial trust radius in phase radians?**
   - What we know: Typical accepted step norms in L-BFGS runs are ≈ 0.1–1.0 rad (from convergence traces in Phase 13/22 JLD2s).
   - What's unclear: no direct measurement of a "Newton step" norm at our base points — the full-space Newton step is not computable without preconditioning.
   - Recommendation: Start at 0.5. Benchmark Wave 2 records `‖p_k‖` distribution; Wave 3 retunes if needed.

3. **Does the `λ_min` probe (Arpack with `nev=1`) need a shift-invert to resolve small-magnitude eigenvalues?**
   - What we know: Phase 13 matrix-free :SR resolved bottom-20 with `|λ_min|` ranging 10⁻⁷ to 10⁻⁶. Shift-invert was impossible (requires factorization).
   - What's unclear: whether `nev=1` with `:SR` reliably finds the leftmost eigenpair at every iteration, or whether near-zero gauge modes occasionally get returned instead.
   - Recommendation: compute `nev=3` with `:SR`, explicitly project out `{𝟙, ω-linear}` by cosine similarity, take the remaining smallest. Cost: ~3× `nev=1` — still cheap.

4. **When a TR run exits `CONVERGED_1ST_ORDER_SADDLE`, should we auto-launch the negative-curvature fallback, or stop and let the benchmark driver decide?**
   - What we know: Phase 35 did this manually; it found better saddles, not minima.
   - What's unclear: whether an automatic re-launch from the escaped point (so effectively a continuation loop inside TR) is scope-creep into Phase 34 territory or a natural finishing move.
   - Recommendation: Phase 33 ships the single-launch version (escape once, then exit). A wrapper loop is a simple addition but is arguably Phase 34 scope (continuation is Phase 30's charter; repeated escape loops overlap with it).

---

## Sources

### Primary (HIGH confidence)
- Phase 13 Plan 02 SUMMARY + FINDINGS — measured Hessian spectrum, HVP API.
- Phase 22 SUMMARY — 26/26 indefinite optima across sharpness sweep.
- Phase 27 REPORT + second-opinion addendum — globalization recommendation, ρ / FD-HVP / gauge pitfalls.
- Phase 35 REPORT + RESEARCH — saddle-rich verdict, neg-curvature escape mechanics.
- `scripts/hvp.jl` — HVP primitive, Taylor-validated.
- `scripts/numerical_trust.jl` — Phase 28 schema we extend.
- `scripts/raman_optimization.jl` — `cost_and_gradient` oracle.
- `CLAUDE.md` — project-wide constraints (standard images, burst wrapper, determinism).

### Secondary (MEDIUM-HIGH confidence)
- Nocedal & Wright (2006). *Numerical Optimization* 2e. — canonical TR reference.
- Conn-Gould-Toint (2000). *Trust-Region Methods*. — definitive monograph.
- Royer-O'Neill-Wright (2018). arXiv:1803.02924. — complexity bounds for Newton-CG with neg-curv.
- Steihaug (1983). SIAM J. Numer. Anal. — original truncated-CG-in-TR paper.

### Tertiary (for deferred work, not Phase 33)
- Nesterov-Polyak (2006). Cubic regularization. — Phase 34+.
- Cartis-Gould-Toint (2011). ARC methods. — Phase 34+.
- Jin et al. (2017). ICML. — saddle-escape theory; informs neg-curv fallback framing.

---

## Metadata

**Confidence breakdown:**
- Problem framing specific to this codebase: HIGH — cross-validated with 4 prior phases + live code.
- Globalization family choice (TR over LS): HIGH — literature + project evidence both point same direction.
- Step-acceptance policy defaults: MEDIUM — classical values, will need Wave 2 tuning.
- Benchmark set composition: HIGH — all configs have published baselines.
- Failure taxonomy: HIGH — canonical Nocedal & Wright taxonomy extended with repo-specific codes.
- Direction-solver API: HIGH — directly constrains Phase 34's charter, designed for minimal coupling.
- Codebase integration plan: HIGH — every listed file exists and has been read.
- Pitfalls: HIGH — all 8 cited from measured evidence in prior phases.

**Research date:** 2026-04-21
**Valid until:** 2026-05-21 (stable references; would refresh only on major Phase 28 / 30 / 31 schema changes)

## RESEARCH COMPLETE
