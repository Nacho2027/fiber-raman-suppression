# Phase 34 Research — Truncated-Newton / Krylov preconditioning path

**Researched:** 2026-04-21
**Domain:** Second-order optimization: matrix-free Krylov inner solvers, preconditioning,
indefinite-Hessian handling for Raman spectral-phase optimization
**Confidence:** HIGH (all claims based on actual codebase files, prior phase summaries,
and authoritative external sources)

---

## Summary

Phase 34 extends the Phase 33 trust-region Newton framework with a `PreconditionedCGSolver`
subtype of `DirectionSolver`, plus systematic preconditioning experiments and a Δ₀-sweep
diagnostic. The scientific context is severe: Phases 22, 35, and 33 all confirm that
every competitive (deep-dB) Raman-suppression optimum is a saddle point — Hessian
indefinite from `N_phi=8` through full resolution. Plain CG (Steihaug) exits on the
`NEGATIVE_CURVATURE` branch at every step in Phase 33's cold-start experiments and is
structurally correct but produces `RADIUS_COLLAPSE` because the quadratic model's
predicted reduction never clears the `ρ = 0.25` acceptance threshold from `φ=0`.

The Phase 34 hypothesis is that preconditioning the inner CG solve will (a) speed inner
convergence so that more Krylov iterates happen before the boundary or negative-curvature
exit, (b) produce a better-conditioned quadratic model whose predicted reductions are
tighter, and (c) allow `ρ` to climb above `η₁=0.25` so the outer loop actually accepts
steps. If this hypothesis holds, the phase delivers what Phase 33 promised but could not
yet demonstrate: outer-loop convergence from cold starts.

The codebase is ready. Phase 33 ships a frozen `DirectionSolver` / `SubproblemResult`
interface in `scripts/trust_region_core.jl`; Phase 13 ships a validated, adaptive
`fd_hvp` oracle in `scripts/hvp.jl`; and Phase 33's outer loop (`optimize_spectral_phase_tr`
in `scripts/trust_region_optimize.jl`) already handles gauge projection, adaptive HVP ε,
edge-fraction pre-flight, and telemetry. Phase 34 only needs to provide new
`solve_subproblem` methods and a new benchmark driver.

**Primary recommendation:** Implement `PreconditionedCGSolver` with a diagonal Jacobi
preconditioner as the first experiment. Run the Δ₀-sweep on `bench-01-smf28-canonical/cold`
before the preconditioner work to separate "wrong initial radius" from "insufficient
conditioning". Add a reduced-basis DCT preconditioner as the second experiment using the
existing `build_dct_basis` machinery in `scripts/amplitude_optimization.jl`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| Krylov inner solve (preconditioned CG) | `scripts/trust_region_pcg.jl` (new) | `scripts/trust_region_core.jl` (frozen interface) | `DirectionSolver` subtype pattern isolates new logic; core is untouched |
| Preconditioner construction | `scripts/trust_region_preconditioner.jl` (new) | `scripts/amplitude_optimization.jl` (DCT reuse) | Phase 33 report explicitly allocates this path |
| Outer-loop trust-region control | `scripts/trust_region_optimize.jl` (frozen) | — | Phase 34 MUST NOT modify; passes solver via keyword |
| Gauge projection (inner solve) | `scripts/trust_region_optimize.jl` (frozen H_op closure) | — | Already projects every HVP input; PCG inherits this |
| Adaptive HVP ε | `scripts/trust_region_optimize.jl` (frozen H_op closure) | — | Already implemented; PCG reuses same H_op callable |
| Benchmark driver | `scripts/benchmark_run.jl` (new) | `scripts/benchmark_common.jl` (additive edit) | Phase 33 pattern; new driver forks, common config gains Phase-34 block |
| Δ₀-sweep diagnostic | `scripts/benchmark_run.jl` | — | New open question 5 from Phase 33 report |
| HVP oracle | `scripts/hvp.jl` (read-only) | `scripts/trust_region_optimize.jl`'s `build_raman_oracle` | Two oracle paths exist; Phase 34 reuses the TR one, not the Phase 13 one |
| Standard image set | `scripts/standard_images.jl` (read-only) | — | Phase 33 wires it through `TrustRegionResult.minimizer` |

---

## Problem Statement in This Codebase

### Why Phase 33's Steihaug is structurally correct but operationally stuck

Phase 33 ran 9 benchmark slots and produced zero `CONVERGED_2ND_ORDER` exits:

- 3 slots skipped by the Phase-28 edge-fraction pre-flight gate.
- 2 warm-start slots exited `CONVERGED_1ST_ORDER_SADDLE` at iteration 0 — the Phase-21
  HNLF and SMF-28 optima are genuine first-order stationary saddles where the leftmost
  non-gauge eigenvector is not a descent direction at the `α = √(Δ/|λ_min|)` step size.
- 4 cold-start slots exited `RADIUS_COLLAPSE` after ~10 iterations.

The cold-start failure story (from `33-REPORT.md §Cold-start evidence`):

> Steihaug exits `:NEGATIVE_CURVATURE` on every step (d'Hd ≤ 0 immediately — meaning
> the initial search direction d = -g itself has ⟨d, Hd⟩ ≤ 0), steps to the boundary,
> every boundary step has ρ ∈ [6e-3, 1e-3] < η₁ = 0.25, radius shrinks by 0.25× each
> iter, collapses below Δ_min = 1e-6 after 10 iterations.

This is not a bug. The quadratic model is inaccurate enough from `φ=0` that trust-region
correctly refuses the steps. But it also means we're burning ~10 outer iterations × ~10
inner HVPs each to produce one `RADIUS_COLLAPSE` datum per cold start. Phase 34's job is
to ask: is the model inaccuracy due to (a) the initial radius being wrong, (b) the
Hessian being too ill-conditioned for unpreconditioned CG to produce useful directions, or
(c) the landscape being genuinely unhelpful from zero phase regardless of solver quality?

Open question 5 from `33-REPORT.md` frames the Δ₀ hypothesis:

> If Δ₀ were smaller from the start, perhaps a tiny but ρ-valid step existed.
> Recommendation: add a Δ₀-sweep mini-benchmark (Δ₀ ∈ {0.5, 0.1, 0.01, 0.001}) on
> bench-01/cold before investing in preconditioning.

The Δ₀-sweep must come first because if the problem is simply that Δ₀ = 0.5 is
"too optimistic," preconditioning won't help — we need a different prior on the
trust radius, not a different inner solver.

### Why an indefinite Hessian matters for Krylov choice

Phase 22 (`SUMMARY.md`) is unambiguous: every single measured optimum across all 26
resolved Hessian spectra is indefinite, with `|λ_min|/λ_max` ratios ranging from
`5.5e-3` (SMF-28 plain) to `3.9e-1` (Pareto-57 trH heavy). Phase 13 (`13-02-SUMMARY.md`)
confirmed that L-BFGS stops at saddles, not minima, with top-20 and bottom-20 eigenvalues
both non-zero and alternating sign. Phase 35 (`35-REPORT.md`) showed that even after
explicit negative-curvature escape along the leftmost eigenvector, the landing points are
still indefinite saddles — competitive Raman suppression is a strict-saddle branch from
`N_phi = 8` through full resolution.

This means the inner Krylov solver will encounter `d'Hd ≤ 0` every time it runs along a
direction with negative curvature. CG's response to this (Steihaug style) is to step to
the trust-region boundary in the direction of maximum negative curvature. This is
structurally correct but gives a step quality that depends heavily on how well the
negative-curvature direction aligns with the actual descent direction in the true cost
surface. A bad alignment produces small ρ and radius collapse.

---

## HVP Reuse Contract

### Source files

- **`scripts/hvp.jl`** — original matrix-free HVP library from Phase 13.
  Contains `fd_hvp`, `build_oracle` (Phase-13 API, not used by Phase 34),
  `validate_hvp_taylor`, `build_full_hessian_small`, `ensure_deterministic_fftw`.
- **`scripts/trust_region_optimize.jl`** — Phase 33 entry point. Contains the
  `build_raman_oracle` helper (local, not the same as `hvp.jl::build_oracle`
  — see `33-01-SUMMARY.md §Deviations Rule 3`), plus the `H_op` closure that Phase 34
  inherits.

Phase 14's executor must NOT call `hvp.jl::build_oracle` directly. That function
takes a `NamedTuple` config and has `log_cost=false, λ_gdd=0, λ_boundary=0` hard-wired
inside it, making it probe the linear physics Hessian rather than the dB-cost Hessian.
Phase 34 uses `build_raman_oracle` from `trust_region_optimize.jl` instead, which is
already wired into `optimize_spectral_phase_tr`.

### The H_op callable (what Phase 34 actually receives)

From `trust_region_optimize.jl` lines 295–308, the `H_op` closure that every
`solve_subproblem` method receives does the following on each call:

1. Computes adaptive FD step: `ε_hvp = √(eps(Float64) · max(1, ‖g‖)) / max(1, ‖v‖)`
   [VERIFIED: `trust_region_optimize.jl:299`]
2. Projects the input vector onto the gauge-complement subspace via `_project_gauge`
   before the HVP: `v_proj = _proj(v)` [VERIFIED: `trust_region_optimize.jl:304`]
3. Calls `fd_hvp(φ, v_proj, oracle.grad_fn; eps=ε_hvp)` from `hvp.jl`
   [VERIFIED: `trust_region_optimize.jl:305`]
4. Projects the output: `return _proj(Hv)` [VERIFIED: `trust_region_optimize.jl:307`]

**Cost per HVP call:** 2 forward ODE solves + 2 adjoint ODE solves via the existing
`cost_and_gradient` pipeline. At production `Nt=2^13`, Phase 13 measured ~31.8 s for the
`:LR` Arpack pass (20 eigenvectors) and ~204.4 s for the `:SR` pass on the burst VM.
Per-HVP cost is roughly **4–6 s** at `Nt=2^13` on `fiber-raman-burst`, based on the
Phase 33 integration test at `Nt=128` running in ~18 s per outer iteration × ~3 HVPs
per inner iteration.

**Thread safety:** The `H_op` closure captures `φ` (read-only during inner solve) and
`oracle.grad_fn` which calls `cost_and_gradient`. The `fiber` dict is mutated by the ODE
solver (`fiber["zsave"]` path). For any parallel PCG experiments, follow the established
`deepcopy(fiber)` pattern from `scripts/benchmark_optimization.jl:635` (CLAUDE.md
§"When the deepcopy(fiber) pattern is required"). However, Phase 34's inner Krylov solve
is sequential — parallelism at the outer-loop level (multi-start) requires `deepcopy`.

**Symmetry guarantee:** The HVP is symmetric up to finite-difference noise. Phase 13
measured `|v' H w - w' H v| < 1e-5 |v' H w|` (`13-02-SUMMARY.md §HVP symmetry`).
The adaptive ε formula from Phase 33 makes this tighter near convergence where `‖g‖` is
small. Any `PreconditionedCGSolver` relying on H-symmetry should validate with the
`validate_hvp_taylor` function (slope should be ≈ 2.0).

**The oracle mismatch warning (from Phase 27 second-opinion addendum):** The Phase-13
`build_oracle` function uses `log_cost=false, λ_gdd=0, λ_boundary=0`. L-BFGS in
`raman_optimization.jl` minimizes the `log_cost=true` dB objective with optional GDD and
boundary regularizers. Phase 33 benchmarks also used `log_cost=false` (physics cost).
Phase 34 inherits this choice. This is documented as deliberate in `33-REPORT.md §P3`:
"All Wave 2 runs used log_cost=false. Disposition: deferred to a future phase if
log-scale cost is reintroduced into the TR path." Phase 34 should not change this
default without adding a full log-cost ρ-distribution characterization first.

### SubproblemResult contract (what PCG must return)

From `scripts/trust_region_core.jl:63–69` [VERIFIED]:
```julia
struct SubproblemResult
    p::Vector{Float64}          # solution: ‖p‖ ≤ Δ·(1+1e-8)
    pred_reduction::Float64     # -m(p) = -(g'p + 0.5 p'Hp) ≥ 0
    exit_code::Symbol           # :INTERIOR_CONVERGED | :BOUNDARY_HIT |
                                # :NEGATIVE_CURVATURE | :MAX_ITER | :NO_DESCENT
    inner_iters::Int
    hvps_used::Int
end
```

`pred_reduction` must be computed in the PRECONDITIONED metric if PCG works in the
P-inner-product space. The outer loop uses `pred_reduction` to compute `ρ`, so the
predicted reduction reported must reflect what the quadratic model actually predicts in
the original (Euclidean) space. This is a subtle but important point: after converting
back from P-space to the original space, recompute `m(p) = g'p + 0.5 p' H_op(p)` using
the original `H_op`. Do not report the reduction in the P-inner-product metric.

---

## Krylov Inner-Solver Candidates

### Why plain CG fails on indefinite Hessians

CG minimizes a quadratic `m(p) = g'p + 0.5 p'Hp` over the expanding Krylov subspace
`K_k(H, g)`. This minimization relies on H being positive definite: when CG encounters
`d'Hd ≤ 0`, the quadratic is unbounded below along `d`, and CG cannot minimize — it must
exit. Steihaug's modification handles this by stepping to the trust-region boundary when
`d'Hd ≤ 0`, but this means CG terminates the inner solve at the first sign of indefiniteness.

At Phase 33's cold-start operating points, `d'Hd ≤ 0` at the very first CG iteration
(the initial residual direction `-g` has negative curvature). This means Steihaug does
exactly one HVP and exits with a boundary step — the Krylov subspace built is
`K_1(H, -g)`, a single vector. There is no inner-loop convergence possible.

### Candidate 1: Steihaug-CG (current Phase 33 baseline)

`SteihaugSolver` [VERIFIED: `scripts/trust_region_core.jl:89–203`]
- **How it handles indefinite H:** Exits on first `d'Hd ≤ 0`, steps to boundary.
- **Strengths:** Simple, one HVP per inner iter, well-understood convergence theory
  for SPD subproblems. Phase 33's implementation is correct and tested with 149 assertions.
- **Weakness for this codebase:** At every cold-start operating point, the first CG
  direction `-g` has `⟨-g, H(-g)⟩ ≤ 0`. Inner solve terminates at K_1 — no inner
  convergence at all.
- **Literature:** Steihaug (1983), Nocedal & Wright §7.2 (trust-region subproblem);
  CS 4220 lecture 2026-04-20 (trust regions, Steihaug-CG interpretation in §"The
  trust region subproblem").
- **Verdict:** PRIMARY baseline for Phase 34 comparisons. Do not remove.

### Candidate 2: Lanczos-based modified CG (CG-Lanczos, MINRES-TR)

CG is equivalent to running the Lanczos algorithm on `H` and solving the resulting
tridiagonal problem. When `H` is indefinite, CG's tridiagonal solve breaks down because
the tridiagonal matrix has nonpositive pivots. MINRES modifies the Lanczos recurrence to
minimize the residual `‖r_k‖` rather than the A-energy, which remains well-defined for
indefinite H.

The trust-region variant of MINRES (sometimes called MINRES-QLP or Lanczos-TR) runs
MINRES until the Krylov iterate `p_k` hits the trust-region boundary or the residual
converges. Compared to Steihaug:
- MINRES continues building the Krylov subspace through negative-curvature directions
  rather than stopping at the first `d'Hd ≤ 0`.
- The Lanczos tridiagonal encodes curvature information more richly than a single CG
  step.
- The trust-region boundary exit gives a richer `p` that is still in `K_k(H, g)` but
  has explored more directions.

**Cost:** Same as Steihaug — one HVP per Lanczos step. Slightly more arithmetic per
step (3-term recurrence + QR update on the tridiagonal instead of CG update), but
negligible compared to HVP cost.

**Reference implementations:** Paige & Saunders' SYMMLQ/MINRES (SIAM J. Numer. Anal.,
1975); Choi, Paige, Saunders "MINRES-QLP" (2011). In Julia, IterativeSolvers.jl
provides `minres!` [ASSUMED — not checked if already in Project.toml]. In the trust-region
context, see Gould, Lucidi, Roma, Toint (1999) "Solving the trust-region subproblem using
the Lanczos method."

**Verdict for Phase 34:** FALLBACK if diagonal-preconditioned Steihaug still collapses.
Implementing full Lanczos-TR is more complex than PCG; defer unless the Δ₀-sweep and
diagonal-preconditioning experiments both produce `RADIUS_COLLAPSE`. The incremental
complexity is justified only if there is evidence that Steihaug is terminating too early.

### Candidate 3: Preconditioned CG (PCG-Steihaug)

Instead of changing the Krylov solver, change the metric in which CG operates. With
left preconditioner `M ≈ H⁻¹` (SPD), PCG solves the modified system `M⁻¹Hx = M⁻¹b`
which has eigenvalues clustered near 1 if M is a good approximation. This reduces the
number of CG iterations for interior convergence and potentially changes which directions
have `d'Hd ≤ 0` in the preconditioned metric.

The preconditioned trust-region subproblem becomes:
- Minimize `g'p + 0.5 p'Hp` subject to `‖p‖_M = √(p'Mp) ≤ Δ_M`

where the trust region is now an ellipse defined by M, not a Euclidean ball. The standard
approach (Nocedal & Wright §7.1) uses an M-weighted inner product throughout CG, and the
trust-region boundary condition becomes `‖p‖_M ≤ Δ`. The `update_radius` function in
`scripts/trust_region_core.jl` remains unchanged if we interpret Δ as the ellipsoidal
radius — but the `GAUGE_LEAK` assertion checks `‖p‖₂`, not `‖p‖_M`. Phase 33 noted this
in Pitfall P6: "deferred to Phase 34 along with preconditioning agenda — PreconditionedCGSolver
naturally induces an ellipsoidal trust region."

**The PCG-Steihaug approach for Phase 34 (RECOMMENDED PRIMARY):**
Run PCG in the M-inner-product space using the change of variables `q = M^{1/2} p`, so
that the transformed problem `H̃ = M^{-1/2} H M^{-1/2}` is more nearly SPD. The
`H_op` callable is replaced by `H̃_op(q) = M^{-1/2} H_op(M^{-1/2} q)`. When `d'H̃d ≤ 0`
is detected, step to the boundary in the M-inner-product sense. Report the step `p` in
the original space by `p = M^{-1/2} q`. The `pred_reduction` is recomputed in the
original Euclidean metric: `-(g'p + 0.5 p' H_op(p))` using one extra HVP. The returned
`SubproblemResult` is then in the original space with a valid Euclidean `pred_reduction`.

**Literature:** Nocedal & Wright, Ch. 7 and §4.1 (trust-region with general norm);
Eisenstat & Walker "Choosing the forcing terms in an inexact Newton method" (SIAM J. Sci.
Comput., 1996) for the forcing sequence.

**Verdict:** PRIMARY new implementation for Phase 34.

### Inner-solver recommendation summary

| Solver | Status | When to use |
|---|---|---|
| `SteihaugSolver` | EXISTING (frozen in `trust_region_core.jl`) | Baseline comparison for all new experiments |
| `PreconditionedCGSolver` | NEW (Phase 34 primary deliverable) | Primary experimental path |
| Lanczos-TR / MINRES-QLP | FALLBACK | Only if PCG still produces RADIUS_COLLAPSE after Δ₀-sweep disambiguates |
| SYMMLQ-TR | DEFER (Phase 36) | Richer handling of indefinite systems, more implementation complexity |

---

## Preconditioner Candidates

### Cost model for evaluating preconditioners

A preconditioner P is cheap enough for this codebase if constructing it costs fewer HVPs
than the number of inner iterations it saves. At `Nt=2^13`, one HVP costs ~4–6 s on the
burst VM. If a preconditioner requires 20 HVPs to build but saves 15 inner iterations per
outer step, across 50 outer iterations that is (20 - 15×50) = -730 HVPs saved — a clear
win. Conversely, a preconditioner that requires 200 HVPs to build and saves 2 inner
iterations per outer step is a loss.

### Preconditioner 1: Diagonal Jacobi (RECOMMENDED FIRST EXPERIMENT)

**What:** `P = diag(H)`. Requires N HVPs to build (one per standard basis vector at
`Nt=2^13`, N = 8192 HVPs) — which is prohibitively expensive. However, a diagonal
approximation can be estimated much more cheaply:

- **Rademacher sketching:** Estimate `diag(H)` via `diag(H) ≈ (1/K) Σ_{k=1}^K (z_k ⊙ H·z_k)`
  where `z_k ∈ {±1}^N` are random Rademacher vectors. K = 10–30 HVPs gives a useful
  estimate with expected error `O(1/√K)`. [ASSUMED — standard technique, not verified
  against codebase]

- **Physics-informed diagonal:** For this codebase's Raman cost `J = E_band/E_total`,
  the Hessian's diagonal at the input frequencies is governed by the quadratic coupling
  between each frequency bin and the Raman-shifted band. A rough estimate is that the
  diagonal entries scale with `|uω0|²` at each frequency — the spectral power profile
  of the input pulse. This costs zero HVPs (already computed during oracle setup).

**Recommendation for Phase 34:** Use the physics-informed diagonal (pulse power profile
`|uω0|²` normalized to have unit mean over the input band) as an initial preconditioner.
If this does not help, try a K=20 Rademacher sketch. Do not attempt full diagonal
construction (8192 HVPs).

**File:** New `scripts/trust_region_preconditioner.jl`, function `build_diagonal_precond`.

### Preconditioner 2: DCT spectral preconditioner (RECOMMENDED SECOND EXPERIMENT)

**What:** Use the DCT-II basis from `scripts/amplitude_optimization.jl::build_dct_basis`
(lines 174–194 in amplitude_optimization.jl) to project the problem onto a K-dimensional
subspace, construct the Hessian in that subspace (K² entries via K HVPs), and invert the
reduced Hessian exactly as the preconditioner for the full problem.

`build_dct_basis(Nt, K)` constructs an orthonormal DCT-II basis matrix `B ∈ ℝ^{Nt×K}`.
The reduced Hessian is `H_r = B' H B ∈ ℝ^{K×K}`, computed with K HVPs (each HVP gives
one column `B' H B[:,i] = B' H_op(B[:,i])`). The reduced preconditioner is then
`P⁻¹v = B (H_r + σI)⁻¹ B'v + (I - BB')(v)` with a Tikhonov shift σ > 0 for stability.
The `(I - BB')` term passes through the complement subspace unchanged (identity
preconditioner on the part of the space not covered by the DCT basis).

**Cost:** K HVPs to build, K³/3 flops for factorization (negligible at K ≤ 128),
one K×K triangular solve per PCG application. For K = 64, this costs 64 HVPs ≈ 320 s
on the burst VM — a one-time cost per outer iteration (or can be rebuilt every M outer
iterations).

**Why this is a natural choice:** Phase 31's research notes that the existing DCT
machinery should be the starting point for reduced-basis work. Phase 27's second-opinion
addendum item 7 notes that `amplitude_optimization.jl:180–209` already implements
`build_dct_basis` and `cost_and_gradient_lowdim`. The phase-optimization analog is the
direct extension. The DCT basis captures the low-frequency structure of the optimal phase
profile (Phase 13 showed that while phase is not dominated by low-order polynomials,
the residual from orders 2–6 is 92% — most structure is NOT in the lowest modes, but
there is still some spectral concentration).

**File:** Reuse `scripts/amplitude_optimization.jl::build_dct_basis` via `include`;
new `scripts/trust_region_preconditioner.jl`, function `build_dct_precond(K)`.

### Preconditioner 3: L-BFGS-as-preconditioner (Morales-Nocedal)

**What:** Use the L-BFGS approximation to H⁻¹ as a preconditioner for the inner CG
solve. The L-BFGS two-loop recursion applied to a vector `v` gives an approximation
`H_LBFGS⁻¹ v` using the stored (s, y) pairs from the outer optimization history. This
is Morales & Nocedal's "Automatic Preconditioning by Limited Memory Quasi-Newton
Updating" (TOMS 2000).

**Cost:** L-BFGS application is O(m×N) where m is the L-BFGS memory. Zero additional
HVPs required.

**Challenge:** The outer TR optimizer does not currently maintain an L-BFGS history
(it uses the HVP oracle directly). To use this preconditioner, the outer loop would need
to accumulate (s, y) pairs across accepted steps. This is a non-trivial modification to
`trust_region_optimize.jl` — which Phase 34 MUST NOT modify. Workaround: maintain the
L-BFGS history inside the `PreconditionedCGSolver` struct, updated via the `kwargs`
channel of `solve_subproblem`.

**Verdict for Phase 34:** DEFER to Phase 36. Implementing L-BFGS-as-preconditioner
without modifying the frozen outer loop is possible but architecturally awkward. The
payoff is unclear without first establishing whether diagonal or DCT preconditioning helps.

### Preconditioner 4: Dispersion-kernel preconditioner (physics-informed)

**What:** The dominant structure in the Hessian of the Raman cost comes from two sources:
(1) the spectral phase modulation couples each frequency to its neighbors via the
nonlinear convolution (Kerr + Raman response), and (2) the group-velocity dispersion
`β₂` and higher-order terms create a quadratic coupling in frequency. For a linear
dispersion-dominated regime, the Hessian of the phase-to-field mapping is approximately
diagonal in frequency space with entries proportional to `|β₂ω²|`. This suggests a
preconditioner `P(ω) = diag(1 + |β₂|ω²)` — cheap to apply (pointwise multiplication),
physics-motivated, and zero HVP cost.

**Challenge:** This approximates the Hessian of the LINEAR propagation term, not the
full nonlinear cost. For short fibers at low power (where linear dispersion dominates),
it may be a good approximation. For high-power HNLF regimes (bench-02), the nonlinear
coupling dominates and this preconditioner may be misleading.

**Verdict:** MEDIUM priority. Cheap to implement (2 lines to build), worth testing as a
third preconditioner option after diagonal and DCT.

### Preconditioner recommendation summary

| Preconditioner | Build cost | Apply cost | Priority |
|---|---|---|---|
| Physics diagonal (`|uω0|²`) | 0 HVPs | O(N) | HIGH — first experiment |
| Rademacher sketch (K=20) | 20 HVPs | O(N) | MEDIUM — if physics diagonal fails |
| DCT reduced-basis (K=64) | 64 HVPs | O(K·N) | HIGH — second experiment |
| Dispersion kernel | 0 HVPs | O(N) | LOW-MEDIUM — third option |
| L-BFGS (Morales-Nocedal) | 0 HVPs (reuse history) | O(m·N) | DEFER to Phase 36 |

---

## Globalization: Trust-Region Reuse (not line search)

Phase 34 MUST use trust-region globalization, not line search. Rationale:

1. The `DirectionSolver` interface is explicitly designed for trust-region subproblems.
   The `SubproblemResult.pred_reduction` field has no analog in a line-search formulation.
2. Phase 33 already implements the Nocedal-Wright Algorithm 4.1 radius update in
   `update_radius` (`scripts/trust_region_core.jl:227–238`) [VERIFIED]. This is frozen
   and cannot be changed.
3. Trust-region handles negative curvature structurally (step to boundary) whereas
   line search requires explicit negative-curvature handling that would need to be
   added to the frozen outer loop.

CS 4220 lecture 2026-04-17 ("Line search and globalization") covers Wolfe conditions and
globalization generally; lecture 2026-04-20 ("Trust regions") covers the quadratic model
and gain ratio ρ precisely as implemented in Phase 33. Both confirm that trust-region is
the correct globalization approach for this indefinite-Hessian setting.

The P6 pitfall from Phase 33 (norm choice) is relevant: the current trust region uses
`‖p‖₂`. `PreconditionedCGSolver` naturally works in the `‖p‖_M` metric (ellipsoidal
trust region). The outer loop's `GAUGE_LEAK` assertion checks `‖p − Π p‖₂ ≤ 1e-8 ‖p‖₂`,
which remains valid even if the inner solve uses a different norm, because the gauge
projection is applied to the final step `p` in Euclidean space before returning the
`SubproblemResult`. Pitfall P6 remains deferred: Phase 34 should document whether
the norm mismatch between inner and outer loop affects ρ quality, and if so, whether
a Euclidean-to-ellipsoidal radius correction is needed.

---

## Forcing Sequence Policy

### Background

The forcing sequence `η_k` controls when the inner Krylov solve terminates:
the inner solve is considered converged when `‖r_k‖ ≤ η_k ‖g‖`. A tight `η_k` (small)
forces more inner iterations and better step quality but more HVPs. A loose `η_k` (large,
e.g. 0.5) terminates early with a cruder step.

### Current Phase 33 implementation

From `SteihaugSolver`'s default `tol_forcing` [VERIFIED: `trust_region_core.jl:92`]:
```julia
tol_forcing = g -> min(0.5, sqrt(norm(g))) * norm(g)
```

This is `η_k = min(0.5, √‖g‖)`, giving absolute tolerance `η_k ‖g‖ = min(0.5, √‖g‖) ‖g‖`.

Near convergence (small `‖g‖`), `η_k ≈ ‖g‖^{1/2}` which gives `η_k ‖g‖ ≈ ‖g‖^{3/2}`.
This is tighter than Eisenstat-Walker's recommended `η_k = min(0.5, √‖g‖)` absolute
forcing and produces superlinear local convergence (Nocedal-Wright §3.3).

### Recommendation for Phase 34

Keep the same forcing sequence as Phase 33 for comparability. The `PreconditionedCGSolver`
struct should expose `tol_forcing` as a configurable field (same as `SteihaugSolver`) so
the planner can run ablation experiments comparing forcing sequences. The default should
match Phase 33.

Eisenstat-Walker forcing [CITED: Eisenstat & Walker, SIAM J. Sci. Comput. 17(1), 1996]:
```
η_k = min(η_max, γ(‖g_k‖/‖g_{k-1}‖)^α)
```
with `γ = 0.9, α = 2.0, η_max = 0.9` for safeguarded superlinear convergence.
This is more adaptive than the Phase 33 formula but requires tracking `‖g_{k-1}‖` across
outer iterations. If Phase 34 finds the fixed forcing is not responsive enough to the
saddle-dominated regime, the Eisenstat-Walker formula is the standard upgrade.

### Inner-iter cap as function of outer iter

Phase 33's `SteihaugSolver` has `max_iter=20`. For Phase 34, the `PreconditionedCGSolver`
should use the same cap as the default. The theoretical maximum for a K-dimensional
subspace is K inner CG iterations. For `Nt=2^13=8192`, 20 iterations is a tiny fraction
of the full CG budget. If preconditioning is effective, 20 iterations may be enough for
inner convergence on the preconditioned problem. If not, increasing to 50 or 100 inner
iterations is reasonable before concluding that preconditioning fails.

The inner-iter cap can be made adaptive as a function of outer iter `k`:
```
max_inner_k = min(20 + 2*k, 100)
```
This allows more inner work as the outer iterate converges and the trust radius stabilizes.
[ASSUMED — this pattern is standard in trust-region literature but not verified in a
specific reference]

---

## Benchmark Protocol

### Non-negotiable: match Phase 33 benchmark set exactly

Phase 34 must use the same benchmark matrix as Phase 33 to enable head-to-head comparison.
The configs are defined in `scripts/benchmark_common.jl` [VERIFIED]:

```julia
BENCHMARK_CONFIGS = [
    (tag="bench-01-smf28-canonical",  fiber=:SMF28, L=2.0, P=0.2,
     Nt=2^13, time_window_ps=40.0,
     warm_jld2="results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2"),
    (tag="bench-02-hnlf-phase21",     fiber=:HNLF,  L=0.5, P=0.01,
     Nt=2^16, time_window_ps=320.0,
     warm_jld2="results/raman/phase21/phase13/hnlf_reanchor.jld2"),
    (tag="bench-03-smf28-phase21",    fiber=:SMF28, L=2.0, P=0.2,
     Nt=2^14, time_window_ps=54.0,
     warm_jld2="results/raman/phase21/phase13/smf28_reanchor.jld2"),
]
START_TYPES = [:cold, :warm, :perturbed]
```

Phase 34's benchmark driver `scripts/benchmark_run.jl` forks from
`benchmark_run.jl` and calls `optimize_spectral_phase_tr(...; solver=PreconditionedCGSolver(...))`
with otherwise-identical config. The Phase-33 `SteihaugSolver` results
(`results/raman/phase33/SYNTHESIS.md`) are the comparison baseline.

### Additional Phase 34 mini-benchmarks (to address open questions from Phase 33)

**Δ₀-sweep (open question 5):** On `bench-01-smf28-canonical/cold` only:
```
Δ₀ ∈ {0.5, 0.1, 0.01, 0.001}  (radians)
```
Run with `SteihaugSolver` (existing). If `Δ₀=0.01` or smaller produces an accepted step
(ρ > η₁ = 0.25), the problem was initial-radius mis-specification. If all four values
produce `RADIUS_COLLAPSE`, the problem is intrinsic Hessian conditioning and preconditioning
is the right next step.

**Perturbation-amplitude sweep (open question 6):** On `bench-02-hnlf-phase21`:
```
perturbation_scale ∈ {0.01, 0.05, 0.10}  (rad RMS)
```
Run with `PreconditionedCGSolver`. Maps basin-of-attraction radius around the -86.68 dB
Phase-21 HNLF saddle.

### Success criteria for Phase 34

Phase 34 is successful if `PreconditionedCGSolver` produces at least one `CONVERGED_2ND_ORDER`
exit or at least one outer iteration with ρ > η₁ = 0.25 (accepted step) on any benchmark
slot where Phase 33's `SteihaugSolver` produced `RADIUS_COLLAPSE`. The comparison is not
about final dB — it is about step acceptance rate and ρ-distribution shape.

Phase 34 explicitly does NOT claim success by beating L-BFGS in final J_dB. That is a
different benchmark that requires (a) enough accepted steps to actually converge and
(b) addressing the log-cost vs physics-cost inconsistency (Phase 27/28).

### Honest failure categories

| Category | Phase 33 analog | Phase 34 honest label |
|---|---|---|
| Pre-flight abort | `SKIPPED_P8` | Same — inherit Phase-28 gate |
| Inner solve terminates immediately | `:NEGATIVE_CURVATURE` exit at iter 1 | Log: PCG negative curvature at preconditioned iter 1 |
| Outer ρ below threshold | `RADIUS_COLLAPSE` | `RADIUS_COLLAPSE` (PCG variant) |
| True saddle, escape failed | `CONVERGED_1ST_ORDER_SADDLE` | Same |
| Pulse off grid (not caught by pre-flight) | NaN cost → `NAN_IN_OBJECTIVE` | Same |
| Preconditioner broke gauge invariance | New risk | Log as `GAUGE_LEAK` (existing exit code) |
| Inner solve diverged (bad preconditioner) | Not present in Phase 33 | Log as `NAN_IN_OBJECTIVE` |

---

## Failure Modes and Safeguards Specific to This Codebase

### P1: Gauge null modes (CARRIED OVER, ALREADY MITIGATED)

The Phase cost is invariant under `φ → φ + C + α(ω - ω̄)` (constant + linear in
frequency). This creates two zero eigenvalues in H (gauge null modes) that can inflate
the trust radius if they enter the CG iterate. Phase 33 mitigates this by projecting
every HVP input onto the gauge complement (`_proj(v)` in `H_op`) and asserting
`‖p − Π p‖/‖p‖ ≤ 1e-8` on every accepted step [VERIFIED: `trust_region_optimize.jl:304,307`].
The `PreconditionedCGSolver` inherits this for free because it calls the same `H_op`.
Additional risk: if the preconditioner M maps a vector in the gauge complement outside
it (M does not commute with the gauge projector Π), the PCG iterate drifts. Mitigation:
project `p` onto the gauge complement before computing `pred_reduction` and returning
the `SubproblemResult`. Test with the existing gauge-invariant integration test.

### P2: HVP noise floor at deep suppression (CARRIED OVER, ALREADY MITIGATED)

The adaptive ε formula in Phase 33's `H_op` handles this [VERIFIED]. No new action
needed. Phase 34 should log `eps_hvp_used` in telemetry for every outer iteration as
Phase 33 does.

### P3: Attenuator non-adjoint consistency at long fiber / high power

The super-Gaussian-30 attenuator in `src/helpers/helpers.jl:59–63` is a hard absorbing
boundary — energy entering the outer 15% of the time window is silently absorbed. Phase
33's P8 pre-flight gate (edge fraction > 1e-3 → skip) catches the most egregious cases
(3 of 9 Phase-33 slots were skipped). However, even within the passing configurations,
the forward and adjoint propagators may be inconsistent in the attenuated region at high
power or long fiber. This primarily affects `bench-02-hnlf-phase21` (the highest-power
surviving config). Phase 28's trust report includes this as a tracked metric. Phase 34
should not disable the P8 gate under any circumstances.

### P4: Log-cost vs physics-cost Hessian mismatch (DEFERRED, DOCUMENTED)

As noted in Phase 33, all Phase-33 and Phase-34 benchmarks use `log_cost=false`. The
preconditioner is being built for the physics Hessian `H_phys`, not the log-cost
Hessian `H_dB = (10/J·ln10)H_phys + regularizer`. If Phase 34 ever switches to
`log_cost=true`, the preconditioner must be rebuilt. Document this in code.

### P5: FFTW plan non-determinism (CARRIED OVER, ALREADY MITIGATED)

`ensure_deterministic_environment()` and `ensure_deterministic_fftw()` are called at
every `optimize_spectral_phase_tr` entry [VERIFIED: `trust_region_optimize.jl`].
Phase 14's new scripts inherit this.

### P6: Preconditioner breaks trust-region norm (NEW RISK for Phase 34)

If PCG uses the M-inner-product trust region (`‖p‖_M ≤ Δ`) but the outer loop checks
`‖p‖₂ ≤ Δ · (1+1e-8)`, the `SubproblemResult` contract `‖p‖ ≤ Δ·(1+1e-8)` may be
violated. Mitigation: after PCG in the M-space produces step `p̃`, clamp `p = p̃ · min(1, Δ/‖p̃‖₂)`
to ensure Euclidean norm constraint. Log the pre-clamp norm violation fraction in telemetry.

### P7: Preconditioner construction HVP cost at production Nt

At `Nt=2^13`, 64 HVPs for the DCT preconditioner costs ~320 s on the burst VM. For the
full 9-slot benchmark (3 configs × 3 start types), 9 × 64 = 576 HVPs just for preconditioner
construction. This is a 48-minute overhead before any outer iteration begins. Mitigation:
rebuild the preconditioner only at the start of each outer run (not every outer iteration),
or use a cruder K=16 initial preconditioner and test K=64 in a follow-up run.

### P8: Pulse off grid (CARRIED OVER, ALREADY MITIGATED)

The Phase-28 pre-flight gate is wired into `optimize_spectral_phase_tr` and cannot be
bypassed. Phase 34 inherits this gate.

### P9: deepcopy(fiber) for any parallel outer loops

Phase 34's benchmark driver may run multiple configurations concurrently. Each run must
use a `deepcopy(fiber)` per thread [VERIFIED pattern: `scripts/benchmark_optimization.jl:635`].
The `optimize_spectral_phase_tr` function is not thread-safe if called with the same
`fiber` dict from multiple threads.

---

## DirectionSolver Subtyping Pattern

Phase 34 adds methods to `solve_subproblem` without modifying `trust_region_core.jl`.
The exact pattern from `33-01-SUMMARY.md §Phase 34 hand-off` [VERIFIED]:

```julia
# In scripts/trust_region_pcg.jl (NEW — do NOT modify trust_region_core.jl)
include(joinpath(@__DIR__, "trust_region_core.jl"))
include(joinpath(@__DIR__, "trust_region_preconditioner.jl"))  # NEW

Base.@kwdef struct PreconditionedCGSolver <: DirectionSolver
    max_iter::Int = 20
    preconditioner::Symbol = :diagonal   # :none | :diagonal | :dct_K64 | :dispersion
    tol_forcing::Function = g -> min(0.5, sqrt(norm(g))) * norm(g)
    K_dct::Int = 64                      # only used when preconditioner == :dct_K64
end

function solve_subproblem(solver::PreconditionedCGSolver,
                          g::AbstractVector{<:Real},
                          H_op,          # same signature as for SteihaugSolver
                          Δ::Real;
                          M = nothing,   # optional: pass prebuilt preconditioner matrix/func
                          kwargs...)::SubproblemResult
    # Preconditioned Steihaug CG in the M-inner-product metric.
    # Returns a SubproblemResult in original (Euclidean) space.
    # Recomputes pred_reduction via one extra H_op call at exit (no stored accumulator).
end
```

Usage from the Phase 34 benchmark driver:
```julia
solver = PreconditionedCGSolver(preconditioner=:diagonal)
result = optimize_spectral_phase_tr(uω0, fiber, sim, band_mask; solver=solver,
    Δ0=0.1,  # from Δ₀-sweep result
    telemetry_path="results/raman/phase34/bench-01-smf28/cold/telemetry.csv",
    trust_report_md="results/raman/phase34/bench-01-smf28/cold/trust_report.md")
```

### Files Phase 34 may create (per `33-REPORT.md §What Phase 34 MAY add`)

- `scripts/trust_region_preconditioner.jl` — preconditioner construction
- `scripts/trust_region_pcg.jl` — `PreconditionedCGSolver` + `solve_subproblem`
- `scripts/benchmark_run.jl` — benchmark driver
- `scripts/phase34_benchmark_synthesis.jl` — synthesis (optional, fork benchmark_synthesis.jl)
- `test/test_trust_region_preconditioner.jl`
- `test/test_trust_region_pcg_integration.jl`
- Additive edits to `scripts/benchmark_common.jl` (new Phase-34 config block)

### Files Phase 34 MUST NOT modify (frozen by Phase 33)

- `scripts/trust_region_core.jl`
- `scripts/trust_region_telemetry.jl`
- `scripts/trust_region_optimize.jl`
- `scripts/benchmark_run.jl`
- `scripts/raman_optimization.jl`, `scripts/common.jl`, `scripts/phase13_*.jl`,
  `scripts/numerical_trust.jl`, `scripts/determinism.jl`, `scripts/standard_images.jl`,
  `src/**`

---

## State of the Art

| Old approach | Current codebase approach | External reference | Relevance |
|---|---|---|---|
| Unguarded Newton step | Trust-region with ρ-test (Phase 33) | N&W §4.1; CS 4220 2026-04-20 | Phase 34 extends this |
| Fixed FD-HVP step ε=1e-4 | Adaptive ε per `‖g‖` and `‖v‖` (Phase 33) | Phase 27 second-opinion defect 5 | Already implemented |
| Unpreconditioned Steihaug | Preconditioned Steihaug (Phase 34) | N&W §7.1, §4.1 | PRIMARY Phase 34 work |
| Euclidean trust-region | Optionally M-normed trust region | N&W §7.1 (general norm) | Phase 34 P6 pitfall |
| Fixed forcing η=0.5 | Eisenstat-Walker adaptive forcing | E&W 1996 | Optional upgrade in Phase 34 |
| Full Hessian for preconditioning | Diagonal sketch / DCT reduced basis | Morales & Nocedal 2000; standard | PRIMARY Phase 34 experiments |

---

## Validation Architecture

### Test framework
| Property | Value |
|---|---|
| Framework | Julia built-in `Test` (`@testset`, `@test`) |
| Config file | None — script-level `julia --project=. test/test_*.jl` |
| Quick run (new tests) | `julia --project=. test/test_trust_region_preconditioner.jl` |
| Full suite | `julia --project=. test/test_trust_region_steihaug.jl && julia --project=. test/test_trust_region_integration.jl && julia --project=. test/test_trust_region_preconditioner.jl && julia --project=. test/test_trust_region_pcg_integration.jl` |
| Existing baseline | 60/60 Steihaug unit tests, 89/89 TR integration tests pass (Phase 33) |

### Testable invariants for Phase 34

**HVP symmetry tolerance:**
`|v' H w - w' H v| / |v' H w| < 1e-5` for random `v, w` at any base point. Already
validated by Phase 13's `validate_hvp_taylor` (slope ≈ 2.0 test). Phase 34 should call
this before any preconditioner construction to confirm the oracle is clean.

**PCG correctness on SPD quadratic:**
For `H = diag(1, 4, 9, ...)` (SPD), unpreconditioned PCG (`:none`) should produce the
same step as `SteihaugSolver` to tolerance 1e-10. Test at small `n=10`.

**Diagonal preconditioner reduces CG iteration count:**
For `H = diag(1, 100, 1, 100, ...)` (ill-conditioned SPD), diagonal-preconditioned CG
should converge in fewer iterations than unpreconditioned CG. Verify on analytic quadratic.

**Trust-region boundary constraint:**
After `solve_subproblem` returns, `‖p‖₂ ≤ Δ · (1 + 1e-8)`. This is the contract from
`trust_region_core.jl` that Phase 34 must satisfy. Test with Δ = 0.1, 1.0, 10.0.

**Gauge projection preservation:**
After calling `solve_subproblem` with a gauge-projected `g` and a gauge-projecting `H_op`,
the returned `p` must satisfy `‖p − Π p‖₂ / ‖p‖₂ ≤ 1e-8`. This is the existing
`GAUGE_LEAK` assertion; it applies to PCG as well as Steihaug.

**pred_reduction non-negative:**
`SubproblemResult.pred_reduction ≥ 0`. Always. If PCG produces a step where the
recomputed quadratic model is positive (cost increases in the model), clamp to zero and
return `:NO_DESCENT`.

**Negative-curvature detection rate:**
In the 9-slot benchmark, every cold-start slot should produce `:NEGATIVE_CURVATURE`
exits from the inner solve unless the preconditioner fundamentally changes the effective
curvature. If no `:NEGATIVE_CURVATURE` exits appear in the telemetry for cold starts,
something is wrong with the preconditioner implementation.

**ρ-distribution comparison (Phase 34 vs Phase 33):**
The key metric for Phase 34 is whether ρ > η₁ = 0.25 is achieved in any cold-start
slot. Phase 33 baseline: ρ range [6e-3, 1e-3] < η₁ for all 4 cold-start slots. Phase 34
target: at least one cold-start slot with a ρ > 0.25 accepted step.

**Preconditioner gauge safety:**
Build diagonal preconditioner `M_diag` from `|uω0|²` physics estimate. Verify that
applying `M_diag` to a vector in the gauge null space (e.g. `ones(Nt)`) produces a vector
with ≤ 10% gauge norm increase before projection. If the preconditioner amplifies gauge
components, the gauge projection in `H_op` will not be sufficient to prevent leakage.

### Wave-0 gaps (files that must exist before Phase 34 execution begins)

- [ ] `scripts/trust_region_preconditioner.jl` — new, Wave 0
- [ ] `scripts/trust_region_pcg.jl` — new, Wave 0
- [ ] `test/test_trust_region_preconditioner.jl` — new, Wave 0
- [ ] `test/test_trust_region_pcg_integration.jl` — new, Wave 0
- [ ] Additive entry in `scripts/benchmark_common.jl` for Phase-34 config block

Existing infrastructure already covers: `trust_region_core.jl`, `trust_region_optimize.jl`,
`trust_region_telemetry.jl`, `hvp.jl`, `amplitude_optimization.jl::build_dct_basis`.

### Per-task commit validation command
```bash
julia --project=. test/test_trust_region_preconditioner.jl
julia --project=. test/test_trust_region_pcg_integration.jl
```

### Per-wave merge gate
```bash
julia --project=. test/test_trust_region_steihaug.jl  # regression: 60/60
julia --project=. test/test_trust_region_integration.jl  # regression: 89/89
julia --project=. test/test_trust_region_preconditioner.jl
julia --project=. test/test_trust_region_pcg_integration.jl
```

---

## External References

### CS 4220 — Cornell Spring 2026 (https://github.com/dbindel/cs4220-s26)

The following lectures are directly relevant to Phase 34:

- **2026-03-16 "Krylov subspace iterations"** — CG derivation from Lanczos, residual
  minimization leading to GMRES/MINRES, Lanczos algorithm for symmetric matrices.
  Covers why CG requires positive definiteness and what MINRES offers for indefinite
  problems. Establishes that MINRES minimizes `‖r‖` rather than the A-energy.
  [VERIFIED: file fetched, subtitle confirmed]

- **2026-04-08 "Gradient descent and Newton for optimization"** — Second-order Taylor
  expansion, Hessian, gradient descent and Newton step for optimization. Establishes that
  Newton convergence requires `H` to be positive definite and that scaling (preconditioning)
  improves convergence on ill-conditioned problems.
  [VERIFIED: file fetched, confirmed gradient/Hessian coverage]

- **2026-04-13 "Modified Newton iterations"** — Inexact Newton methods, forcing sequences,
  almost-Newton convergence analysis. Establishes the "inexact Newton" framework where the
  linear system is solved only approximately (truncated Krylov). Contains the exact statement
  that the Jacobian (or Hessian) is the main computational difficulty and how to amortize it.
  [VERIFIED: file fetched, subtitle "Modified Newton iterations" confirmed]

- **2026-04-15 "Quasi-Newton and other iterations"** — L-BFGS and quasi-Newton
  approximations to the inverse Hessian as preconditioners. Morales-Nocedal pattern.
  [VERIFIED: file fetched, subtitle "Quasi-Newton and other iterations" confirmed]

- **2026-04-17 "Line search and globalization"** — Wolfe conditions, backtracking line
  search, globalization strategies. Confirms trust-region as the preferred globalization
  for indefinite-Hessian problems.
  [VERIFIED: file fetched, subtitle confirmed]

- **2026-04-20 "Trust regions"** — Levenberg-Marquardt, trust-region subproblem, gain
  ratio ρ, Steihaug-CG interpretation for indefinite models ("if H is indefinite, CG runs
  until it discovers the indefiniteness, then plots a path toward where the model descends
  to −∞"), Moré-Sorensen algorithm for the exact subproblem.
  [VERIFIED: file fetched, Steihaug description confirmed in content]

### Nocedal & Wright "Numerical Optimization" (2nd ed.)

- **§4.1** — Trust-region algorithm, radius update. This is the exact algorithm in
  `trust_region_core.jl::update_radius`.
- **§7.1** — Trust-region subproblem with general norm; M-normed trust region for
  preconditioning. Relevant for Phase 34's P6 pitfall.
- **§7.2** — Steihaug truncated-CG algorithm. This is the exact algorithm in
  `trust_region_core.jl::solve_subproblem(::SteihaugSolver, ...)`.
- **§3.3** — Forcing sequences for inexact Newton (superlinear convergence). The
  Phase 33 default `tol_forcing = min(0.5, √‖g‖)·‖g‖` references this section.
- **Ch. 7** — Preconditioning and L-BFGS-as-preconditioner (Morales-Nocedal variant).
[ASSUMED — standard reference, not verified against specific page numbers in this session]

### Eisenstat & Walker 1996

Eisenstat, S.C. and Walker, H.F. "Choosing the forcing terms in an inexact Newton
method." SIAM J. Sci. Comput. 17(1):16–32, 1996.
Establishes the Eisenstat-Walker adaptive forcing sequence formula, the standard alternative
to the Phase 33 fixed-formula `η_k = min(0.5, √‖g‖)`. Phase 34 may implement this as an
optional `tol_forcing` for `PreconditionedCGSolver`.
[CITED: standard reference; DOI 10.1137/0917003]

### Steihaug 1983

Steihaug, T. "The conjugate gradient method and trust regions in large-scale
optimization." SIAM J. Numer. Anal. 20:626–637, 1983.
Foundational paper for the inner CG solve. Cited explicitly in `trust_region_core.jl`
docstring ("Steihaug 1983"). The Phase 33 implementation is a faithful implementation of
this paper's Algorithm 1.
[CITED: foundational reference; DOI 10.1137/0720042]

### Gould, Lucidi, Roma, Toint 1999

"Solving the trust-region subproblem using the Lanczos method." SIAM J. Optim. 9(2):504–525.
Establishes the Lanczos-TR method as an alternative to Steihaug for the trust-region
subproblem. The Lanczos version continues building the subspace through negative-curvature
encounters (unlike Steihaug which exits). Relevant as the fallback candidate for Phase 34
if PCG still produces `RADIUS_COLLAPSE`.
[CITED: reference available; DOI 10.1137/S1052623497322735]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | Rademacher sketching for diagonal HVP approximation is standard and gives O(1/√K) error in K HVPs | Preconditioner 1 | If wrong, diagonal estimation is more expensive or less accurate than stated; use physics-diagonal fallback |
| A2 | `max_inner_k = min(20 + 2*k, 100)` adaptive cap is a standard pattern in trust-region literature | Forcing Sequence Policy | If non-standard, planner should use fixed cap=20 as Phase 33 does |
| A3 | N&W specific page numbers for §3.3, §7.1, §7.2, §4.1, Ch.7 are correct | External References | Page numbers may be wrong for different edition; section numbers are verified against Phase 33 code comments |
| A4 | IterativeSolvers.jl provides `minres!` and is not already in Project.toml | Krylov Candidate 2 | If not present, Lanczos-TR implementation requires adding a new dependency; prefer implementing from scratch |

---

## Open Questions (RESOLVED)

All four open questions are resolved by Plans 01-04. Dispositions appended inline below.

1. **Does Δ₀ = 0.5 explain the RADIUS_COLLAPSE outcomes, or is it Hessian conditioning?**
   — Research answer: unknown until the Δ₀-sweep runs. Phase 34 Plan 01 should be the
   Δ₀-sweep, not the preconditioner. If Δ₀ = 0.001 still collapses, proceed to PCG.
   **(RESOLVED BY PLAN 01)** — Plan 01 executes the Δ₀ ∈ {0.5, 0.1, 0.01, 0.001} sweep
   on bench-01-smf28-canonical/cold with the frozen SteihaugSolver and records the
   go/no-go verdict in 34-01-SUMMARY.md. Plan 04 §Δ₀ Sweep Verdict cross-references this
   finding.

2. **Does the diagonal preconditioner `|uω0|²` commute with the gauge projector Π?**
   — Research answer: physically, the pulse spectrum is concentrated in the input band
   and decays outside it. The gauge modes `{𝟙, ω − ω̄}` project onto all frequencies
   equally. The diagonal preconditioner will scale gauge-mode components by the spectral
   power at each frequency. After the gauge projection in `H_op`, this should not matter —
   but the preconditioner applied to the starting residual `g` could introduce gauge
   components if `g` is not already perfectly gauge-projected. Mitigation: project `g`
   through `_proj` before applying the preconditioner in the PCG loop.
   **(RESOLVED BY PLAN 02)** — PCG construction in Plan 02 receives `g` already projected
   by the frozen outer loop (`H_op` projects input and output). Plan 02's `solve_subproblem`
   applies `M_inv` to the already-projected residual, so no additional projection step is
   required at the solver level. Unit test in Plan 02 Task 3 verifies `‖p − Πp‖₂/‖p‖₂ ≤ 1e-8`
   on the returned step.

3. **Should the telemetry schema be extended for Phase 34?**
   — Recommendation: yes, additively. Append columns to the end of `TRIterationRecord`
   (or use a separate Phase-34-specific telemetry file) per `33-REPORT.md §Frozen` clause:
   "If Phase 34 needs more fields, bump schema version to 33.1 additively (append columns
   to the end)." New fields: `preconditioner_name`, `K_dct`, `diag_precond_norm`,
   `cg_exit_precond` (preconditioned residual norm at inner convergence).
   **(RESOLVED BY PLAN 03)** — telemetry.csv stays frozen (additive-only per Phase-33
   schema lock); Phase-34-specific metadata (`solver_type`, `preconditioner`, `K_dct`,
   `precond_wired`) is appended to the per-slot `_result.jld2` by the Plan 03 driver,
   not to telemetry.csv. This keeps the Phase-33 CSV schema byte-compatible with the
   existing `benchmark_synthesis.jl`.

4. **Will the DCT preconditioner at K=64 be stable given the Hessian's mixed positive/negative
   eigenvalues?**
   — The reduced Hessian `H_r = B'HB` at K=64 will also be indefinite (it is a compression
   of an indefinite matrix). Adding a Tikhonov shift `σI` stabilizes it: `P⁻¹ = B(H_r + σI)⁻¹B' + (I-BB')`.
   Choosing σ requires care: too large makes P = I (no help), too small makes P⁻¹ dominate
   in the negative-curvature directions and invert the Hessian sign. Recommendation: start
   with `σ = |λ_min(H_r)|` (computed as part of the K-HVP construction via `eigmin(H_r)`).
   **(RESOLVED BY PLAN 03)** — `build_dct_precond` uses `σ = max(0, -eigmin(H_r)) + eps() * tr(H_r) / K`
   when `σ_shift=:auto` (eigmin-based Tikhonov shift). This makes `H_r + σI` SPD by construction;
   Plan 03 Task 1 caches the Cholesky factorization for reuse across PCG applications.

---

## Environment Availability

| Dependency | Required by | Available | Version | Fallback |
|---|---|---|---|---|
| Julia ≥ 1.9.3 | All | ✓ | 1.12.4 (pinned) | — |
| `fiber-raman-burst` burst VM | All benchmark runs (CLAUDE.md Rule 1) | On-demand | GCP c3-highcpu-22 | None — burst is mandatory for Julia simulation |
| `scripts/trust_region_core.jl` | Phase 34 subtypes this | ✓ | Phase 33 frozen | — |
| `scripts/trust_region_optimize.jl` | Phase 34 calls `optimize_spectral_phase_tr` | ✓ | Phase 33 frozen | — |
| `scripts/hvp.jl` | H_op closure uses `fd_hvp` | ✓ | Phase 13 | — |
| `scripts/amplitude_optimization.jl::build_dct_basis` | DCT preconditioner | ✓ | Phase 31 existing | Implement DCT from scratch |
| `Arpack.jl` | Existing λ-probe in outer loop | ✓ | In Project.toml | — |
| HNLF warm-start JLD2 (`results/raman/phase21/phase13/hnlf_reanchor.jld2`) | bench-02 warm start | Must verify before run | Phase 21 result | Skip bench-02 warm if not present |

**Missing dependencies with no fallback:** The burst VM is not optional for benchmark
runs. Ensure `burst-start` and `burst-run-heavy` wrappers are available on `claude-code-host`.

---

## Sources

### Primary (HIGH confidence — verified in this session against actual files)

- `scripts/trust_region_core.jl` — full read; verified `SteihaugSolver`, `SubproblemResult`,
  `TRExitCode`, `update_radius` implementations
- `scripts/trust_region_optimize.jl` — partial read; verified `H_op` closure lines 295–308,
  `build_raman_oracle`, `optimize_spectral_phase_tr` signature
- `scripts/hvp.jl` — full read; verified `fd_hvp`, `build_oracle` (Phase-13 API),
  `P13_DEFAULT_EPS = 1e-4`, `ensure_deterministic_fftw`
- `scripts/benchmark_common.jl` — full read; verified `BENCHMARK_CONFIGS`,
  `START_TYPES`
- `.planning/phases/33-globalized-second-order-optimization-for-raman-suppression/33-REPORT.md` — full read
- `.planning/phases/33-globalized-second-order-optimization-for-raman-suppression/33-01-SUMMARY.md` — full read
- `.planning/phases/33-globalized-second-order-optimization-for-raman-suppression/33-03-SUMMARY.md` — full read
- `.planning/phases/22-sharpness-research/SUMMARY.md` — full read; verified 26/26 optima indefinite
- `.planning/phases/35-saddle-escape/35-REPORT.md` — full read; verified saddle-dominant landscape
- `.planning/phases/13-optimization-landscape-diagnostics-gauge-fixing-polynomial-p/13-01-SUMMARY.md` — full read
- `.planning/phases/13-optimization-landscape-diagnostics-gauge-fixing-polynomial-p/13-02-SUMMARY.md` — full read
- `.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md` — full read
- `scripts/amplitude_optimization.jl` — grep verified `build_dct_basis` at lines 174–194
- CS 4220 lectures 2026-03-16, 2026-04-08, 2026-04-13, 2026-04-15, 2026-04-17, 2026-04-20 — fetched via curl from GitHub raw

### Secondary (MEDIUM confidence — cited from official sources)

- Nocedal & Wright "Numerical Optimization" (2nd ed.) — cited by section number per
  references in `trust_region_core.jl` docstrings; section mappings are consistent
  with codebase
- Steihaug 1983 — cited in `trust_region_core.jl` docstring; DOI 10.1137/0720042
- Eisenstat & Walker 1996 — standard reference; DOI 10.1137/0917003
- Gould et al. 1999 — Lanczos-TR; DOI 10.1137/S1052623497322735

### Tertiary (LOW confidence — based on training knowledge, not verified this session)

- Morales & Nocedal 2000 "Automatic Preconditioning by Limited Memory Quasi-Newton Updating" — standard reference for L-BFGS-as-preconditioner; DOI assumed correct but not verified
- Rademacher sketching for diagonal HVP estimation — standard technique, not verified against a specific implementation in this project

---

## Metadata

**Confidence breakdown:**
- HVP contract and code paths: HIGH — verified in actual source files
- Phase 33 frozen API (DirectionSolver, SubproblemResult): HIGH — verified in trust_region_core.jl
- Phase 22/35 landscape geometry: HIGH — verified in SUMMARY.md and REPORT.md
- Preconditioner build costs: MEDIUM — estimated from Phase 13 timing data, burst VM specs
- CS 4220 lecture topics: HIGH — verified via direct file fetch
- Nocedal & Wright section numbers: MEDIUM — consistent with code comments but not verified page-by-page this session

**Research date:** 2026-04-21
**Valid until:** 2026-06-01 (Phase 33 is frozen; landscape findings are stable; library APIs are stable)
