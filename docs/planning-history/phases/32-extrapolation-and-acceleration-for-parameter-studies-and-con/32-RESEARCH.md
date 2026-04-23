# Phase 32 Research — Extrapolation and Acceleration for Parameter Studies and Continuation

**Researched:** 2026-04-21
**Domain:** Sequence-acceleration numerical methods (Aitken, Anderson / MPE / RRE, Richardson extrapolation, polynomial predictor-warm-start) applied to L-BFGS spectral-phase Raman optimization in nonlinear fiber propagation.
**Confidence:** MEDIUM-HIGH on codebase claims (grep-verified at specific file:line). MEDIUM on external numerical-methodology claims (CS 4220 s26 lecture `lec/2026-04-15.jl` + standard textbook material). LOW on the actual numerical behavior of acceleration in *this* problem — the entire phase exists to measure it, so all quantitative predictions are labelled as hypotheses.
**Scope guard:** methodology definition + experiment design only. No new optimizer code, no full benchmark runs inside this phase's research deliverable. This RESEARCH.md is consumed by `32-01-PLAN.md`, which scopes implementation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Phase 32 only survives execution if it saves expensive solves without weakening trust.
- Candidate families come from continuation ladders AND structured study grids.
- Acceleration is compared against naive warm-start chains, NOT against an idealized oracle.
- A "not worth it" verdict is an acceptable successful outcome.

### Wait Directive

- Do NOT start `/gsd-execute-phase` until Phase 30 has merged to `origin/main` (poll for `integrate(phase30): ...` every 15 min). Research and planning may proceed in parallel.

### Research Directive

- Expand the stub RESEARCH.md substantially before touching `01-PLAN.md`.
- Draw from CS 4220 s26 class notes, Phase 27 numerics audit, Phase 13 / 22 / 28 / 35 prior findings, seeds, and external literature.
- Plan should reflect real understanding of the problem in THIS codebase, not generic template tasks.

### Claude's Discretion

- Choice of which sequence family to accelerate FIRST (section 6 ranks them cost-to-signal).
- Whether to implement Anderson / RRE from scratch in Julia vs. take a new package dependency (section 9 — open question flagged for planner).
- Concrete thresholds in the stop rule (section 5 proposes starting values, planner can tune).
- Whether acceleration code lives in `scripts/acceleration.jl` (new) vs. as an option inside `scripts/continuation.jl::run_ladder` (recommendation below).

### Deferred Ideas (OUT OF SCOPE)

- Acceleration applied to Phase 33/34 Newton / truncated-Newton correctors — the Newton corrector path is not yet in place and Phase 32 must not wait for it. Re-evaluate once Phases 33/34 land.
- Accelerating across ladder variables jointly (e.g., accelerate `(L, Nphi)` 2-D path). Phase 32 is 1-D only.
- Adaptive basis acceleration (using principal components of past `phi_opt` iterates to span a reduced search subspace). Interesting but is a Phase 31+ composition concern.

</user_constraints>

<phase_requirements>
## Phase Requirements

The ROADMAP lists Phase 32 with a single bulk requirement ("Derived from Phase 27 NMDS acceleration recommendation") rather than numbered IDs. The CONTEXT Locked Decisions function as the operational requirement set. Restating as research IDs for planner use:

| ID | Description | Research Support |
|----|-------------|------------------|
| REQ-32-A | Catalogue the concrete nearby-problem sequences the codebase actually produces, and for each classify whether acceleration is theoretically applicable. | Section 1 (Problem statement), Section 2 (classification). |
| REQ-32-B | Select candidate acceleration method families that are defensible for this codebase's dimension, storage, and failure-mode profile. | Section 3 (Candidate method families). |
| REQ-32-C | Define "acceleration saved a solve without weakening trust" in metrics the Phase 28 trust schema already carries. | Section 4 (Trust metrics). |
| REQ-32-D | Pre-register a falsifiable stop rule ("not worth it" is a success outcome). | Section 5 (Stop rule). |
| REQ-32-E | Order the first experiments by cost-to-signal. The cheapest experiment that can rule a method in or out must run first. | Section 6 (First experiments). |
| REQ-32-F | Honor the Phase 28 trust schema, the `save_standard_set(...)` mandate, the `deepcopy(fiber)` parallel-safety pattern, the `burst-run-heavy` wrapper, and the Phase 15 deterministic-environment pins. | Section 7 (Validation Architecture) + Section 8 (Integration hazards). |
| REQ-32-G | List planner-level open questions this research could not settle. | Section 9. |

</phase_requirements>

## Summary

The repo already solves families of nearby problems every day: the Phase 30 `scripts/continuation.jl::run_ladder` L-ladder, the Phase 7 36-point `(L, P)` sweep grid, the `scripts/sweep_simple_run.jl` 9-point N_phi ladder (4, 8, 16, 32, 64, 128, 256, 512, Nt), the Phase 22 sharpness-strength sweeps (26 points × multiple flavors), and the ad-hoc warm-start chains in `scripts/longfiber_optimize_100m.jl`. The question Phase 32 must answer is: **for these specific sequences, does any acceleration method reduce the count of expensive forward-adjoint solves without degrading the Phase 28 trust rollup?**

The honest baseline to beat is not cold-start — it is Phase 30's explicit continuation ladder (trivial predictor + L-BFGS corrector + budget parity) that is about to land on `main`. If Phase 30's trivial-predictor warm start already eats most of the benefit available from iterate-to-iterate similarity, then Anderson or RRE can only improve at the margin, and the marginal improvement must pay for its implementation complexity, its failure-mode bookkeeping, and its violation of the "L, P, lambda ladders traverse saddles, not a minimum branch" structural constraint inherited from Phases 22 and 35.

The second structural constraint: **L-BFGS is itself an approximation to the Anderson / MPE family**. CS 4220 s26 `lec/2026-04-15.jl` states the connection explicitly — "Anderson acceleration is a variant of RRE where the accelerated sequence directly feeds back into iterations" and RRE "when applied to stationary iterative methods for linear systems is formally identical to GMRES" [CITED: `https://raw.githubusercontent.com/dbindel/cs4220-s26/main/lec/2026-04-15.jl`]. Stacking another Anderson loop on top of L-BFGS iterates is therefore redundant in the generic case. The interesting application is one level up: accelerate the *sequence of converged phi_opt across ladder steps*, not the sequence of L-BFGS iterates within a step.

**Primary recommendation:** Focus the first experiments on **vector polynomial extrapolation (MPE / RRE) of the converged `phi_opt` across a continuation ladder**, and on **polynomial warm-start prediction** (fit a low-order polynomial in the continuation variable to `{phi_opt(s_1), ..., phi_opt(s_k)}` and predict `phi_opt(s_{k+1})` as the L-BFGS initial guess). Compare both against Phase 30's trivial predictor on the same ladder, at budget parity, with Phase 28 trust emission per step. Do the Richardson extrapolation experiment on a `Nt` ladder only if the grid-consistency audit (section 6, Experiment 0) passes — otherwise Richardson is inapplicable by construction.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Ladder definition | `scripts/continuation.jl::ContinuationSchedule` (already exists) | — | Reuse; do not fork. [VERIFIED: `scripts/continuation.jl:118` struct definition] |
| Accelerator state (past iterates `phi_opt_1..phi_opt_k`) | `scripts/acceleration.jl` (NEW) or an `AcceleratorState` field on a wrapped schedule | — | Keep `continuation.jl` pure — continuation owns the path, acceleration owns past-iterate memory |
| Predictor upgrade (polynomial warm-start) | plug into `scripts/continuation.jl::run_ladder` via the existing `corrector_fn` seam, OR extend the `predictor::Symbol` enum with `:polynomial` | — | The seam already exists at `scripts/continuation.jl:568-572` — `corrector_fn` argument and `schedule.predictor` field. Phase 32 should NOT modify the public API of `run_ladder`; adding a new enum value `:polynomial` alongside `:trivial` is additive. [VERIFIED: `scripts/continuation.jl:568`] |
| Vector extrapolation of converged iterates | `scripts/acceleration.jl` | — | Pure function over `Vector{Vector{Float64}}` → `Vector{Float64}` |
| Scalar convergence-rate estimator (Aitken Δ²) on `J_opt_dB` sequence | `scripts/acceleration.jl` | — | One-liner; used only for the stop rule + convergence diagnostics |
| Per-step trust report | existing `scripts/numerical_trust.jl::build_numerical_trust_report` + `attach_continuation_metadata!` | — | Reuse Phase 28 schema 28.0 without bump. Phase 32 adds `report["acceleration"]` sub-dict additively, same pattern as Phase 30. [VERIFIED: `scripts/numerical_trust.jl:7` constant] |
| Benchmark driver | `scripts/demo.jl` (NEW) | — | Mirrors `scripts/demo.jl` pattern for consistency. [VERIFIED template: `scripts/demo.jl` 413 lines per 30-01-SUMMARY.md] |

## Standard Stack

This is methodology research; no new Julia packages are strictly required. Reuse only.

### Core (already in repo)

| Library | Version | Purpose in Phase 32 | Source |
|---------|---------|---------------------|--------|
| `Optim.jl` | 1.13.3 | L-BFGS corrector (unchanged) | [VERIFIED: `Project.toml:29`] |
| `FFTW.jl` | — | Deterministic ESTIMATE-planner FFTs; frequency-domain resampling of `phi_opt` across `Nt` changes | [VERIFIED: `scripts/determinism.jl:75`] |
| `LinearAlgebra` (stdlib) | — | Least-squares solves inside MPE/RRE (QR on `(Nt × m)` differences matrix, m ≤ 5) | [ASSUMED — standard] |
| `Interpolations.jl` | 0.16.2 | Only if ladder variable needs 1-D interpolation of a scalar (e.g., acceleration hyperparameter `alpha` vs. `s`) | [VERIFIED: `Project.toml` compat entry] |
| `JLD2` | 0.6.3 | Per-step acceleration checkpoints: `(phi_prediction, phi_corrected, iters_saved)` | [VERIFIED: `Project.toml` compat entry] |
| `scripts/continuation.jl` | `CONTINUATION_VERSION = "30.0"` | Ladder driver; Phase 32 extends `schedule.predictor` enum rather than forking the driver | [VERIFIED: `scripts/continuation.jl:99`] |
| `scripts/numerical_trust.jl` | schema `"28.0"` | Per-step trust report; Phase 32 adds `report["acceleration"]` additively, no schema bump | [VERIFIED: `scripts/numerical_trust.jl:7`] |

### Alternatives Considered (external packages NOT recommended for Phase 32 first pass)

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled Anderson in `scripts/acceleration.jl` | `NLsolve.jl::anderson` | `NLsolve` is a TRANSITIVE-only dep in `Manifest.toml:1364`, NOT a direct entry in `Project.toml`. Adding it as a direct dep requires an explicit approval. Hand-rolled Anderson is ~40 lines for the fixed-`m` variant and matches the project's "no new viz dependencies; no unnecessary package churn" posture. [VERIFIED: `grep NLsolve Project.toml` returns nothing] |
| Hand-rolled MPE/RRE | `AcceleratedAlgorithms.jl`, `NonlinearSolve.jl` acceleration hooks | Same argument + bigger blast radius. Defer until the hand-rolled versions prove the method is worth it. |
| Polynomial least-squares fit for warm-start prediction | `Polynomials.jl` | Minor dep vs. 5-line `\` on a Vandermonde matrix. Use `\` for the first pass. |

**Version verification:** `NLsolve` is NOT in `Project.toml` (grep 2026-04-21). `Optim@1.13.3`, `JLD2@0.6.3`, `Interpolations@0.16.2` are all pinned. No new packages recommended before the first experiment delivers a verdict. If Experiment 2 or 3 (section 6) signals that acceleration is worth a full treatment, revisit with a planner-user dependency decision.

## 1. Problem Statement (Codebase-Specific)

The codebase produces the following structured sequences of "nearby" optimization problems. Each row describes a concrete family currently on disk or in a plan, the ladder variable, typical sequence length, whether `phi_opt` is already reused as warm start, and the expected magnitude of iterate-to-iterate distance.

### Sequence catalogue

| # | Family | Ladder variable | Typical length | Warm-start in place? | Source | Expected `‖Δphi_opt‖` regime |
|---|--------|-----------------|----------------|----------------------|--------|------------------------------|
| S1 | Phase 30 continuation ladder (SMF-28 long-fiber) | `L ∈ {1, 10, 100} m` | 3 | YES — Phase 30 trivial predictor + `longfiber_interpolate_phi` cross-grid transfer | `.planning/phases/30-.../30-01-SUMMARY.md`, `scripts/demo.jl:const P30_LADDER_L` | LARGE — factor-10 `L` jumps cross regime (walk-off-dominated vs. dispersion-dominated); saddle branch transitions |
| S2 | Phase 7 `(L, P)` sweep grid SMF-28 | `(L_i, P_j)` 5 × 4 | 20 | NO — Phase 7 cold-starts each point | `.planning/phases/07-parameter-sweeps/07-02-SUMMARY.md:83` (`SW_SMF28_L = [0.5, 1.0, 2.0, 5.0, 10.0] × [0.05, 0.10, 0.20, 0.30]`) | UNKNOWN — never measured under warm-start; flag as Experiment 1 prerequisite |
| S3 | Phase 7 `(L, P)` sweep grid HNLF | `(L_i, P_j)` 4 × 4 | 16 | NO | same plan, `SW_HNLF_L × SW_HNLF_P` | UNKNOWN (same) |
| S4 | `sweep_simple_run.jl` N_phi ladder | `N_phi ∈ {4, 8, 16, 32, 64, 128, 256, 512, Nt}` | 9 | YES — "Continuation warm-start from the coarser level" per `scripts/sweep_simple_run.jl:8` | `scripts/sweep_simple_run.jl:57` | VARIES — at low N_phi the optimum is forced-sparse, at high N_phi it fills out. Not monotone in norm. |
| S5 | Phase 22 sharpness-strength sweep at fixed config | `λ_strength ∈ {various 4-point ladders per flavor}` | 4 per flavor × 4 flavors × 2 points = 26 | UNCLEAR — Phase 22 summary does not state warm-start discipline explicitly | `.planning/phases/22-sharpness-research/SUMMARY.md` Hessian table | LARGE at strong regularization (penalty dominates solution) |
| S6 | Implicit `longfiber_optimize_100m.jl` warm-start chain | manual `L` ladder | ~5 | YES — ad hoc, pre-Phase 30 | `scripts/longfiber_optimize_100m.jl` (precursor to Phase 30) | LARGE — same as S1 |
| S7 | Phase 31 N_phi reduced-basis ladder (PLANNED) | `N_phi ∈ {basis sizes}` | 21 per branch per Phase 31 ROADMAP | YES planned | `.planning/ROADMAP.md:432` ("Branch A (basis sweep, 21 runs on burst)") | UNKNOWN — Phase 31 has not executed |

### Per-family depth of solves

Each "point" is one `optimize_spectral_phase(...)` call. At `Nt = 2^14` with 40 L-BFGS iterations and the two-solve cost per iteration (forward + adjoint), one point costs ~80 forward-adjoint solves. Phase 30 `scripts/demo.jl` at `max_iter = 40` is representative. At burst-VM scale (22 threads, parallel across points only), S2 at 20 points × 80 = 1600 solves; S4 at 9 points × 80 = 720 solves per arm; S7 at 21 × 80 = 1680 solves per branch.

The lever worth pulling: if acceleration turns a 40-iter L-BFGS polish into a 20-iter polish at every ladder step after the third, the saving scales as `0.5 × N_solves × (K - 3) / K` — roughly 40% wall-time at `K = 9`, 30% at `K = 5`, near-zero at `K = 3`. **Ladders shorter than ~5 are not worth accelerating** even if the method works perfectly. S1 at K=3 is on the edge. S2 (20), S4 (9), S5 (per flavor = 4, too short), and S7 (21) are the candidates where the arithmetic works.

## 2. Which Sequences Admit Valid Acceleration

Not every "related sequence of solves" is a fixed-point iteration. Anderson, MPE, and RRE assume `x_{k+1} = G(x_k)` where `G` is a contraction (or at least a "reasonable" smooth map near the fixed point). Applied to a non-iterated sequence they produce numbers but no convergence guarantee — the combinations are heuristics, not extrapolations.

CS 4220 s26 `lec/2026-04-15.jl` states the precondition: RRE solves

```
minimize  (1/2) ‖F_k γ‖_2^2   subject to   Σ γ_i = 1
```

where `F_k` contains finite differences between consecutive iterates [CITED: `lec/2026-04-15.jl`]. The "iterate" semantics require the sequence to be generated by repeated application of a single map — not by solving a sequence of *different* problems.

### Classification of the S1–S7 families

| # | Family | Is the sequence a fixed-point iteration of a single map? | Anderson / MPE / RRE validity | Polynomial warm-start prediction validity |
|---|--------|----------------------------------------------------------|-------------------------------|-------------------------------------------|
| S1 | L-ladder 1→10→100 m | NO. Each step changes the problem (different `fiber["L"]` + different grid). The "map" `φ_opt_k = Corrector(Predictor(φ_opt_{k-1}))` is NOT a self-map on a fixed space. | **INVALID** as fixed-point acceleration. | **VALID** — polynomial in `log L`, `L`, or arclength. This is the main lever for S1. |
| S2 | `(L, P)` grid | NO. Two-parameter family; the natural "map" depends on a path choice through the grid. | **INVALID** directly. Can become VALID after projecting onto a 1-D path. | **VALID** — polynomial/bilinear in `(L, P)` for near-neighbor warm starts. |
| S3 | HNLF `(L, P)` grid | Same as S2 | Same | Same |
| S4 | N_phi ladder | NO in the classical sense — the *optimization variable's dimension changes* at each step. Even after zero-padding the coefficients into the full-Nt grid, the corrector objective is not identical across steps. | **PARTIALLY VALID**: once all `phi_opt_k` are up-sampled to a fixed reference grid, Anderson on the padded vectors is formally defined, but interpretation is murky. | **VALID** — polynomial in `1/N_phi` (natural variable for basis-truncation error) for warm-start prediction. This is the Richardson regime if N_phi-refinement is self-consistent (Section 6, Experiment 0). |
| S5 | Regularization-strength sweep | SEMI. At each `λ`, the problem is `∇J(φ) + λ g(φ) = 0`, a 1-parameter family with a solution path `φ(λ)`. Continuation in `λ` is the classical case. | **VALID** for Anderson only if `λ` → 0 (homotopy back to unregularized) and the L-BFGS corrector is treated as a single nonlinear solve at each `λ`. | **VALID** — polynomial in `log λ`. |
| S6 | Ad-hoc long-fiber chain | Same as S1 | **INVALID** as fixed-point | **VALID** as polynomial warm-start. Superseded by S1 under Phase 30. |
| S7 | Phase 31 N_phi reduced-basis ladder | Same as S4 | Same | **VALID** — polynomial in `1/N_phi`. |

**Key conclusions:**

- **Classical Anderson / MPE / RRE are formally inapplicable to most sequences the codebase produces**, because the sequences walk across problems, not through iterates of a single map. The exception is S5 (homotopy in `λ` with L-BFGS as corrector).
- **Polynomial warm-start prediction is valid everywhere** — it is not a sequence acceleration in the strict convergence-theory sense; it is a predictor for the first L-BFGS iterate that happens to use past solutions. This is the generalizable, low-risk lever.
- **Richardson extrapolation on an N_phi (or Nt) ladder is valid if and only if the truncation error is asymptotically `A · N^{-p}` for some `p`** — this requires the finer grids to be self-consistent, which is a separate audit (Experiment 0). If the grid behavior is dominated by absorbing-boundary mass loss (flagged by the Phase 27 second-opinion audit, defect #6) rather than by grid truncation, Richardson will not extrapolate to a meaningful limit.

## 3. Candidate Method Families — Implementability

Per method: what it does, storage cost, expected failure mode on THIS problem, explicit abandon criterion.

### 3.1 Richardson Extrapolation (grid-size / N_phi ladder)

**What it does.** Given a value `V(h)` that converges as `h → 0` with leading error `A h^p`, combine two measurements `V(h_1), V(h_2)` as `V_ext = (V(h_1) h_2^p - V(h_2) h_1^p) / (h_2^p - h_1^p)` to kill the leading error. Standard CS 4220 material — though the lectures available (`lec/2026-04-15.jl` Broyden + RRE + Anderson) do not formally derive Richardson, it is part of the standard numerical-analysis toolkit that the NMDS acceleration seed references.

**Applies to.** S4 / S7 (N_phi ladders), S1's Nt upsize at each `L` step, and potentially the ODE tolerance dimension (currently `abstol = 1e-6` default per `simulate_disp_mmf.jl:182`, flagged by Phase 27 second-opinion defect #4).

**Implementability on this problem.** Depends on a grid-refinement audit. The codebase's forward solve at `Nt = 2^11` is NOT self-consistent relative to `Nt = 2^13` (Phase 7 Plan 1 found Nt < 2^13 has noticeable drift; see `07-01-SUMMARY.md:39`). The standard rule is Nt must be large enough that halving it changes `J_opt` by less than the acceleration target. **Proposed sanity check:** run the final `phi_opt` at `Nt ∈ {2^13, 2^14, 2^15}` on a canonical SMF-28 config and plot `J_opt(Nt)` to check for a `C + A·Nt^{-p}` fit. If `p` is clean (integer or half-integer) with `R^2 > 0.98`, Richardson is applicable. If the residuals show a floor (consistent with absorbing-boundary mass loss), Richardson extrapolates to a boundary-artifact limit, not to a physics limit.

**Storage cost.** Trivial — one extra scalar per ladder rung.

**Abandon if.** The Nt-refinement fit `J_opt(Nt) = C + A·Nt^{-p}` has `R^2 < 0.95` on a canonical SMF-28 config, OR the Phase 27 second-opinion absorbing-boundary hypothesis is confirmed before we run Phase 32's experiments. In either case, Richardson is producing a meaningless limit.

### 3.2 Aitken Δ² Acceleration

**What it does.** For a scalar sequence `a_k → a*` converging linearly, `â_k = a_k − (Δa_k)^2 / Δ²a_k` accelerates convergence to `a*`. Δa_k = a_{k+1} − a_k.

**Applies to.** Scalar `J_opt_dB` sequences — a stop-rule gadget, not a solve saver. Apply to `{J_opt(s_1), J_opt(s_2), J_opt(s_3), ...}` across ladder steps to estimate the limit `J_opt_∞` and ask "did the last step move us by >1 dB vs the predicted limit?"

**Implementability.** Trivial. ~5 lines. Cannot fail pathologically — Δ²a_k near zero gives divide-by-near-zero, in which case Aitken correctly reports "no more acceleration available."

**Storage cost.** Three previous scalars.

**Abandon if.** N/A — this is not a candidate for solve savings; it is a diagnostic for the stop rule. Always include.

### 3.3 Anderson Acceleration

**What it does.** On a fixed-point iteration `x_{k+1} = g(x_k)`, keep the last `m` residuals `f_k = g(x_k) − x_k`, solve `minimize ‖Σ γ_i f_{k-m+i}‖` subject to `Σ γ_i = 1`, then set `x_{k+1} = Σ γ_i g(x_{k-m+i})`. The CS 4220 s26 lecture `lec/2026-04-15.jl` identifies it as a Gauss-Seidel variant of RRE with in-loop feedback [CITED: `lec/2026-04-15.jl`].

**Applies to, in principle.** The L-BFGS iterates within a single optimization call — i.e., accelerating the inner optimizer. This is the case Phase 32 must *not* pursue. The CS 4220 lecture notes Anderson is useful for slowly-converging fixed-point iterations; **L-BFGS with HagerZhang line search is already a superlinear quasi-Newton method** (verified in Phase 27 audit, `scripts/raman_optimization.jl:76-172`). Stacking Anderson on top of L-BFGS is the wrong optimization, unless L-BFGS is being restarted frequently (which it is not here).

**Applies to, secondarily.** S5 homotopy in `λ`, treating the map `T: φ → (solution of ∇J(φ) + λ g(φ) = 0 for new λ)` as the Anderson operator. This is a stretch — the "fixed point" drifts as `λ` changes.

**Implementability.** ~40 lines for fixed-`m` dense variant. Standard QR least-squares on an `Nt × m` differences matrix. Nt = 2^14 = 16384, m ≤ 5 → cheap `(Nt × 5)` QR.

**Storage cost.** `m × Nt` extra floats — at `Nt = 2^14, m = 5`: 655 KB. Negligible.

**Expected failure modes in this problem.**

1. **Gauge zero-modes from Phase 13.** The cost is invariant under `φ → φ + C` (constant shift) and `φ → φ + α·ω` (linear-omega shift). These are exact null modes of the Hessian [VERIFIED: Phase 13-02 SUMMARY key-decisions; `results/raman/phase13/FINDINGS.md`]. Anderson's least-squares combination can amplify motion along gauge directions because nothing in the cost resists it. **Mitigation:** either fix the gauge before combining (project out the constant + `ω`-linear components from each `f_k`) or accept that Anderson's output will have meaningless constant/linear drift that L-BFGS can clean up in one more iteration.
2. **Indefinite Hessian (Phase 22 / 35).** The competitive-dB branch is saddle-dominated. Anderson theory assumes a contraction; at a saddle, the local map has eigenvalues of both signs. Anderson *can* still help on the contracting subspace but may push the iterate along an unstable direction. Add a safeguard: reject the Anderson combination if `‖γ‖_∞` exceeds a threshold (classical safeguard from the Walker & Ni 2011 paper — LOW confidence on exact threshold, typically 1e3 to 1e5).
3. **Cost-surface incoherence (Phase 27 second-opinion defect #2).** The log-cost factor `10 / (J · ln 10)` scales the physics gradient by a J-dependent factor. Anderson residuals across iterates at different J values are not on a common scale. Before combining, normalize each `f_k` by its own gradient norm — or restrict Anderson to the phase-2 "polish" regime where J barely moves.

**Explicit abandon criterion.** If two or more of the failure modes above require mitigation to get Anderson running, the implementation complexity exceeds the policy of "survives only if it saves expensive solves." Abandon in favor of polynomial warm-start.

### 3.4 Minimal Polynomial Extrapolation (MPE) and Reduced Rank Extrapolation (RRE)

**What it does.** Given iterates `x_0, ..., x_k` of a fixed-point iteration, find coefficients `γ` that combine the iterates or differences to land near the fixed point. RRE:

```
γ = argmin ‖F_k γ‖   s.t.  Σ γ_i = 1,   F_k[:,i] = x_{i+1} − x_i
```

[CITED: `lec/2026-04-15.jl`]. For linear stationary iterations, RRE equals GMRES.

**Applies to.** The same regime as Anderson. Differences:

- RRE / MPE are *offline* (compute after the sequence is generated) — Anderson is *online* (feeds the accelerated iterate back).
- Offline use is better suited to this phase: after `run_ladder` generates `{phi_opt_1, ..., phi_opt_k}`, try MPE / RRE on the sequence and polish the combination with one more L-BFGS call. If the combined-plus-polished endpoint beats the `phi_opt_k` endpoint on `J_opt_dB` at lower iteration cost, the method buys something.

**Implementability.** ~30 lines. QR on the `(Nt × k)` differences matrix.

**Storage cost.** Same as Anderson (all iterates kept).

**Expected failure modes.** Same as Anderson (gauge, saddle, cost-surface), *plus*: MPE/RRE on a non-fixed-point sequence (which is most of our sequences — see Section 2) combines iterates from different problems. The combination is defined, but it isn't converging to anything meaningful. In practice this shows up as `γ` with wild magnitudes — same safeguard as Anderson.

**Explicit abandon criterion.** If MPE on the `scripts/demo.jl` 3-point L-ladder does not reduce `J_opt_dB` at the final point by ≥1 dB at budget parity, or if the combined `phi_init` needs MORE L-BFGS iterations than the trivial-predictor `phi_init` to converge, abandon MPE.

### 3.5 Vector Polynomial Warm-Start Prediction (the main recommendation)

**What it does.** Given past converged optima at ladder values `s_1, ..., s_k`, fit a degree-d polynomial in `s` (or in a physically motivated variable like `log L`, `1/N_phi`) for each component of `phi_opt`. Evaluate the polynomial at `s_{k+1}` to produce `phi_init`, then run L-BFGS from there.

Formally: for each `ω_j`, fit `phi_opt(s; j) ≈ Σ_{d=0}^{D} c_{j,d} · ψ_d(s)` and predict `phi_init_{k+1}(j) = Σ c_{j,d} · ψ_d(s_{k+1})`. With only 2 past points, this reduces to linear (secant) extrapolation; with 3, quadratic; with 4, cubic.

**Applies to.** EVERY sequence S1–S7 (see Section 2). Unlike Anderson / MPE / RRE, polynomial warm-start does not require fixed-point semantics — it is just an interpolation/extrapolation of a solution path, identical in spirit to the secant predictor classical continuation methods use (pseudo-arclength, tangent predictors — see `scripts/continuation.jl:48-59` where these are listed as deferred to Phases 33/34). CS 4220 s26 `lec/2026-04-22.jl` confirms this is the standard continuation-method predictor: "Predict a new solution using either a trivial guess or an Euler predictor based on Jacobian information" — our polynomial predictor is the Euler / extrapolation version without the Jacobian [CITED: `lec/2026-04-22.jl`].

**Implementability.** For each `ω_j`, a small Vandermonde system `V c_j = phi_history_j`, solved by `\`. For D = 2, V is `3 × 3`; for D = 3, `4 × 4`. Solving Nt such systems is trivial — alternatively, solve the single matrix equation `Phi = V C` where `Phi` is `(k × Nt)` and `C` is `((D+1) × Nt)`. One `\` call.

**Storage cost.** `k × Nt` past iterates, same as Anderson/MPE/RRE.

**Expected failure modes.**

1. **Non-monotone or poorly-behaved ladder variable.** Polynomial extrapolation assumes `phi_opt(s)` is smooth in `s`. At fold bifurcations (CS 4220 `lec/2026-04-22.jl` example — parameter `γ` past 3.5 gives two merging branches) the polynomial overshoots or undershoots. The saddle-branch constraint (Phase 22 / 35) makes this a live concern: crossing between saddles can produce discontinuous `phi_opt`.
2. **Wrong choice of ladder variable.** On an `L` ladder, predicting in raw `L` when the physics scales like `log L` or arclength will produce large residuals. Pick the variable from physics: `log L` for long-fiber ladders (walk-off scales as `T ~ |β1| L`, so arclength ≈ linear in `L`; but L-BFGS iteration count grows sub-linearly in L — empirical). For the `N_phi` ladder, `1/N_phi` is the obvious choice.
3. **Catastrophic cancellation at high polynomial order.** Don't go above cubic. The planning team should pre-register the max degree as D = min(k-1, 2) — i.e., use at most quadratic, even with 5+ past iterates.

**Explicit abandon criterion.** If the quadratic polynomial prediction needs ≥ 50% of the trivial-predictor's iterations to converge to the same `J_opt_dB` on S1 or S7, abandon polynomial warm-start.

### 3.6 Summary: recommended first-pass method set

| Method | Include in Phase 32 v1? | Why |
|--------|-------------------------|-----|
| Richardson extrapolation (Nt ladder) | **Only if Experiment 0 passes** (grid-refinement self-consistency). Otherwise omit. | Good signal-to-noise if applicable; meaningless otherwise. |
| Aitken Δ² | **Yes — as stop-rule diagnostic only** | Trivial cost; included for convergence-rate display in `J_opt_dB` table. |
| Anderson acceleration (on ladder outputs) | **No for v1** | Fixed-point semantics not present in most ladders. Defer. |
| MPE / RRE (offline, on ladder outputs) | **Yes on S1 only** (3-point L-ladder already generated by Phase 30) | Low implementation cost; cheap test on existing data. |
| Polynomial warm-start prediction | **Yes — the main experiment** | Valid everywhere, interpretable, reuses the existing `run_ladder` predictor seam. |

## 4. Trust Metrics

"Acceleration saved a solve without weakening trust" must reduce to numbers the Phase 28 trust schema already carries. Schema version stays `"28.0"` — Phase 32 does NOT bump it, same discipline as Phase 30 (which added `report["continuation"]` additively). Phase 32 adds `report["acceleration"]` likewise.

### Comparison protocol (same endpoints, same budget)

For a ladder of K steps with target value `s_K`:

| Arm | Description | phi_init at step k (k ≥ 2) | Corrector budget |
|-----|-------------|----------------------------|------------------|
| COLD | cold-start at target | `zeros(Nt)` | `max_iter_per_step` |
| NAIVE | Phase 30 trivial predictor warm-start | `phi_opt_{k-1}` (or `longfiber_interpolate_phi` if Nt changes) | `max_iter_per_step` |
| ACCEL | Phase 32 accelerated predictor | `poly_predict(phi_opt_{1..k-1}, s_k)` OR `MPE_combination(phi_opt_{1..k-1})` | `max_iter_per_step` |

All three arms use the **identical `max_iter_per_step`** — no reducing the cap for the accelerated arm. The comparison metric is then "how close to convergence did each arm get in the same budget?" and "if one arm converges early, how many iterations did it save?"

### Per-endpoint metrics (emit on step k)

Pull from `scripts/numerical_trust.jl::build_numerical_trust_report`:

| Field | Source | Pass threshold |
|-------|--------|----------------|
| `overall_verdict` | full trust report | Accelerated arm must be `PASS` or `MARGINAL`; `SUSPECT` disqualifies. |
| `boundary.max_edge_frac` | edge fraction in/out | `< 1e-3` per `TRUST_THRESHOLDS.edge_frac_pass` [VERIFIED: `scripts/numerical_trust.jl:13`] |
| `energy.drift` | energy conservation | `< 1e-4` per `TRUST_THRESHOLDS.energy_drift_pass` [VERIFIED: `scripts/numerical_trust.jl:10`] |
| `determinism.verdict` | FFTW/BLAS thread pins | Must be `PASS` (both threads == 1). Phase 15 contract. [VERIFIED: `scripts/determinism.jl:75`] |
| `continuation.detectors.corrector_iters` | Phase 30 additive | Count of L-BFGS iterations at this step (the solve-saving currency). |

### Acceleration-specific metrics (new, under `report["acceleration"]`)

| Field | Definition |
|-------|-----------|
| `accelerator` | one of `"trivial"` (= naive arm), `"polynomial_d2"`, `"polynomial_d3"`, `"mpe"`, `"rre"`, `"richardson"` |
| `prediction_norm` | `‖phi_prediction‖` — for sanity check; should be O(1) in radians |
| `prediction_vs_prev_norm` | `‖phi_prediction − phi_opt_{k-1}‖ / ‖phi_opt_{k-1}‖` — large means the accelerator extrapolated aggressively |
| `coefficient_max` | `max |γ_i|` for MPE/RRE / `max |c_j|` for polynomial — the safeguard sentry. If > 1e3, reject combination and fall back to trivial (the Walker-Ni safeguard) |
| `corrector_iters_saved` | `naive_iters − accel_iters` at this step. Signed — negative means acceleration cost iterations. |
| `j_opt_db_delta` | `accel_J_dB − naive_J_dB`. Positive = accel is worse (lower depth). |
| `trust_gap_vs_naive` | worst verdict rank delta: `rank(accel) − rank(naive)` using `scripts/numerical_trust.jl::_TRUST_RANK`. Positive = accel is worse. |

### Per-phase rollup

At end of ladder, aggregate across the K steps:

```
total_iters_saved     = sum(corrector_iters_saved) over steps 2..K
worst_verdict_accel   = worst_trust_verdict([step.trust for step in accel_arm])
worst_verdict_naive   = worst_trust_verdict([step.trust for step in naive_arm])
final_j_opt_db_delta  = accel_J_dB[K] - naive_J_dB[K]
```

### Determinism caveat

Per Phase 15 + Phase 27 second-opinion: FFTW.ESTIMATE costs measurable FFT throughput vs. MEASURE, but is required for bit-reproducibility. Do NOT switch to MEASURE in Phase 32 benchmarks — it would make the iteration-count comparison noisy (1e-9 relative drift in HVPs was enough to invalidate Phase 13 eigenvalues, per 13-02 SUMMARY deviation #2). `ensure_deterministic_environment()` is idempotent and already called at the top of `scripts/continuation.jl::run_ladder` [VERIFIED: `scripts/continuation.jl:575`].

## 5. Stop-Rule Design

"Not worth it" is an acceptable success outcome per CONTEXT.md. The stop rule must make that outcome identifiable with NO room for narrative after-the-fact adjustment.

### Pre-registered thresholds (planner may tune before execution — NOT after)

**The method is judged WORTH IT on a ladder if ALL the following hold:**

1. **Solve savings:** `total_iters_saved / total_naive_iters ≥ 0.15` (at least 15% fewer L-BFGS iterations across the ladder).
2. **Trust non-regression:** `rank(worst_verdict_accel) ≤ rank(worst_verdict_naive)` — the accelerated arm's worst verdict is no worse than the naive arm's.
3. **Endpoint non-regression:** `final_j_opt_db_delta ≤ 1.0` — the accelerated final `J_opt_dB` is within 1.0 dB of the naive arm's. Lower is better; we accept equal or better.
4. **No hard halts added:** the accelerated arm does not trigger any `path_status = :broken` that the naive arm does not. If naive goes :broken too, acceleration did not cause it.

**The method is judged NOT WORTH IT if ANY of these hold:**

- Criterion 1 fails (< 15% savings) regardless of everything else. Including "equal savings, better `J_opt_dB`" — equal savings means acceleration gave us nothing the naive predictor would not give.
- Criterion 2 fails (trust regression). "Faster but less trustworthy" is not a trade this phase accepts.
- Criterion 3 fails (> 1 dB endpoint loss).
- Criterion 4 fails (new hard halt caused by acceleration).

**Inconclusive outcome:** any combination that passes some criteria and fails others goes to `INCONCLUSIVE` — which per CONTEXT.md requires more experiments to resolve, OR an explicit escalation to the user for a subjective call. Planner should pre-register that `INCONCLUSIVE` on the first experiment family triggers the `abandon` path unless an obvious mitigation is available.

### Worked example (pre-registration template for 32-RESULTS.md)

```markdown
## Verdict (pre-registered)

| Ladder | total_iters_saved | savings % | worst_verdict | final J_dB delta | hard halts | Verdict |
|--------|-------------------|-----------|---------------|------------------|------------|---------|
| S1 (L-ladder) | {fill in} | {pct} | {PASS/MARGINAL/SUSPECT} | {dB} | {count} | {WORTH_IT / NOT_WORTH_IT / INCONCLUSIVE} |
```

### Aitken-based supporting diagnostic

Alongside the stop rule, compute Aitken Δ² on the `J_opt_dB` sequence for each arm. Report:

- `J_∞_estimate_naive = aitken(J_opt_dB_naive)` — if it converges to something meaningful (denominator large enough).
- `J_∞_estimate_accel = aitken(J_opt_dB_accel)` — same.

If both extrapolate to within 0.5 dB of each other and within 0.5 dB of the last-observed value, the ladder is "already near the limit" and acceleration has little room to improve. This is a DIAGNOSTIC only — it does not change the stop-rule verdict, but informs the "do we need a longer ladder to see the benefit?" follow-up question.

## 6. Suggested First Experiments (Ordered by Cost-to-Signal)

All experiments run on `fiber-raman-burst` via `~/bin/burst-run-heavy P32-<tag>`. No experiment runs on `claude-code-host`. Follow CLAUDE.md Rule P5 and Rule 3.

### Experiment 0 — Richardson applicability audit (prerequisite, cheap)

**Purpose.** Decide whether Richardson extrapolation is meaningful before we spend a byte on implementing it.

**Inputs.**
- One converged canonical `phi_opt` from Phase 13 (e.g., `results/raman/phase13/hessian_smf28_canonical.jld2` — SMF-28 `L = 2 m`, `P = 0.2 W`, `Nt = 8192`).
- Re-evaluate `J(phi_opt)` at `Nt ∈ {2^12, 2^13, 2^14, 2^15}` — forward solve only, no optimization. The cost is 4 forward solves.
- Fit `J(Nt) = C + A · Nt^{-p}` via nonlinear least squares. Report `p`, `R^2`, residuals.

**Expected runtime on burst.** ~5 minutes.

**Outcome that kills Richardson.** `R^2 < 0.95` on the power-law fit. Concrete sign of a boundary-artifact floor rather than grid truncation.

**Outcome that promotes Richardson.** `R^2 > 0.98` AND `p` near 2 or 4 (physically plausible — the ODE uses Tsit5, a 5th-order RK; FFT is spectrally accurate so `p` may be very steep and Richardson is less useful). If `p > 6` empirically, the grid is already super-accurate and Richardson is not needed.

### Experiment 1 — Polynomial warm-start on Phase 30's 3-point L-ladder (the main experiment)

**Purpose.** Test the main recommendation: polynomial warm-start prediction.

**Inputs.**
- Run Phase 30's `scripts/demo.jl` EXACTLY AS IS for the NAIVE arm. Reuse its output. `L = [1, 10, 100] m`, `P = 0.2 W`, `Nt = 2^14`, `max_iter = 40`.
- Add a third arm called `ACCEL`: at step k=2 (`L = 10 m`), use linear extrapolation (= secant = Phase 30's deferred "secant predictor" per `scripts/continuation.jl:50-52`) from the step-1 optimum. At step k=3 (`L = 100 m`), use quadratic extrapolation in `log L` over `{phi_opt_1, phi_opt_2}` — wait, quadratic needs 3 points and we have 2 before step 3. Use linear in `log L` for step 3, and plan an expanded 4-point ladder (`L = [1, 3, 10, 30, 100]` m) for Experiment 1b if linear is not enough.

**Expected runtime on burst.** Same as Phase 30 demo (~15-30 minutes) × 2 (add ACCEL arm).

**Outcome that kills polynomial warm-start.** Either:
- `total_iters_saved ≤ 0`: the linear / quadratic prediction is no better than Phase 30's trivial (copy) predictor. Plausible outcome because at a factor-10 `L` jump, the optimum phase changes a lot and the "previous" phase is already far enough off that adding a correction term doesn't help.
- Endpoint degrades by `> 1.0 dB`.
- Any `:broken` path status that the NAIVE arm does not have.

**Outcome that promotes.** Savings `≥ 15%` AND endpoint within 1 dB AND non-regressed trust.

**Decision rule.** If Experiment 1 kills the method on S1, run Experiment 1b (longer ladder with more rungs, permitting true quadratic fit). If 1b also kills it, Phase 32 verdict tends toward `NOT_WORTH_IT` unless Experiment 2 salvages it.

### Experiment 1b — Expanded L-ladder for quadratic prediction

**Purpose.** Address "maybe linear extrapolation is too blunt for factor-10 jumps."

**Inputs.** Same setup as Experiment 1 but `L = [1, 2, 5, 10, 20, 50, 100] m` (7 rungs, lets quadratic fit start at step 3 and kick in for steps 3–7). Uses the natural variable `log L`.

**Expected runtime on burst.** ~2 hours at `max_iter = 40 × 7` per arm × 3 arms.

**Outcome that promotes.** `total_iters_saved ≥ 0.25` (tougher bar because longer ladder = bigger opportunity).

### Experiment 2 — MPE / RRE offline on Phase 30's 3-point sequence

**Purpose.** Minimum-cost test of the "vector extrapolation" family on a sequence the codebase already has. Runs on `claude-code-host` (no heavy compute — only one extra L-BFGS polish).

**Inputs.**
- Load Phase 30's three `phi_opt_k` from `results/phase30/continuation_L_100m/continuation_step_{1,2,3}.jld2`.
- Compute `phi_mpe = MPE(phi_opt_1, phi_opt_2, phi_opt_3)` offline. Also `phi_rre`.
- Polish each combination with L-BFGS at `L = 100 m`, `max_iter = 40`.
- Compare `J_opt_dB(polished(phi_mpe))` vs. `J_opt_dB(phi_opt_3)` (the Phase 30 endpoint).
- Also record the `γ` coefficients — if `max|γ| > 1e3`, mark the combination as rejected per the Walker-Ni safeguard and fall back.

**Expected runtime.** ~20 min on burst (one L-BFGS polish per method × 2 methods).

**Outcome that promotes.** `J_opt_dB` improves by `≥ 1.0 dB` with iteration count `≤ 20` (half of the naive budget).

**Outcome that kills.** `γ` coefficients blow up (gauge mode amplification, expected), OR polish needs ≥ 40 iterations anyway.

### Experiment 3 — Polynomial warm-start on the (to-be-run) Phase 31 N_phi ladder

**Purpose.** Phase 31 produces a 21-rung N_phi sweep. Polynomial extrapolation in `1/N_phi` is the physics-native variable (classical basis-truncation error decays like `N_phi^{-p}`). This is the cleanest test — but it depends on Phase 31 landing first.

**Gate.** Do NOT run Experiment 3 until Phase 31 Plan 01 is merged. If Phase 31 slips, skip Experiment 3 and write up the verdict based on Experiments 0, 1, 1b, 2 only.

**Inputs.** Phase 31 Branch A output. Fit degree-2 polynomial in `1/N_phi` using the last 3 rungs at each step. Use as warm-start for step k+1.

**Expected runtime.** ~3 hours if Phase 31 finishes Branch A (21 points × 80 solves ≈ 1680 solves, some saved by existing warm-start).

### Ordering

Run 0, 1, 2 FIRST (all cheap, combined < 1 burst-VM hour). That is the minimum viable Phase 32. If any of the three produce a clean `WORTH_IT` or `NOT_WORTH_IT` verdict on its own, Phase 32 can ship that verdict and skip the more expensive 1b / 3. The CONTEXT makes clear: "not worth it" is an acceptable success outcome — optimize for a confident verdict, not for exhaustive method coverage.

## 7. Validation Architecture

> This section is MANDATORY per the researcher contract and downstream VALIDATION.md generation.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia stdlib `Test` (already in `[targets]` in `Project.toml:34`) |
| Config file | none — tests live in `test/` and are invoked directly |
| Quick run command | `julia -t auto --project=. test/test_acceleration.jl` (new file) |
| Full suite command | `julia -t auto --project=. test/test_acceleration.jl && julia -t auto --project=. test/test_continuation.jl && julia -t auto --project=. test/test_phase28_trust_report.jl` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REQ-32-A | Sequence catalogue is accurate (S1–S7) | documentation-only | N/A | N/A |
| REQ-32-B | Polynomial warm-start gives same result as trivial when k=1 (no past iterates) | unit | `pytest`-style `@testset` in `test/test_acceleration.jl` | ❌ Wave 0 |
| REQ-32-B | Polynomial warm-start on a synthetic 2D quadratic with known optimum recovers the optimum in ≤ 2 iterations | unit | `@testset "polynomial warm-start quadratic"` | ❌ Wave 0 |
| REQ-32-B | MPE safeguard rejects when max|γ| > 1e3 and falls back to trivial | unit | `@testset "mpe safeguard"` | ❌ Wave 0 |
| REQ-32-B | Aitken Δ² on a linearly-converging synthetic sequence produces the analytic limit | unit | `@testset "aitken"` | ❌ Wave 0 |
| REQ-32-C | `report["acceleration"]` additive block does not bump `schema_version` from `"28.0"` | regression | `@testset` asserting `report["schema_version"] == "28.0"` after `attach_acceleration_metadata!` | ❌ Wave 0 |
| REQ-32-C | `write_numerical_trust_report` renders `## Acceleration` block only when `report["acceleration"]` present (regression: existing non-acceleration reports render unchanged) | regression | Diff markdown output against Phase 28 regression test baseline | ❌ Wave 0 |
| REQ-32-D | Stop rule classifier returns `WORTH_IT`/`NOT_WORTH_IT`/`INCONCLUSIVE` on hand-crafted metric dicts | unit | `@testset "stop rule"` | ❌ Wave 0 |
| REQ-32-E | `scripts/demo.jl` loads via `include` without triggering heavy run (same `abspath(PROGRAM_FILE) == @__FILE__` guard as `demo.jl`) | smoke | `julia -e 'include("scripts/demo.jl"); println("LOAD_OK")'` | ❌ Wave 0 |
| REQ-32-F | `scripts/demo.jl` calls `save_standard_set(...)` for every produced `phi_opt` at the target ladder point (ACCEL arm final + NAIVE arm final + COLD arm final) | grep check | `grep -c "save_standard_set(" scripts/demo.jl` ≥ 3 | ❌ Wave 0 |
| REQ-32-F | Demo script references `burst-run-heavy P32-<tag>` in top comment | grep check | `grep -c "burst-run-heavy P32" scripts/demo.jl` ≥ 1 | ❌ Wave 0 |
| REQ-32-F | Determinism applied: `grep -c "ensure_deterministic_environment" scripts/demo.jl` ≥ 1 | grep check | same | ❌ Wave 0 |
| REQ-32-F | Any `Threads.@threads` loop deepcopies `fiber` per thread | grep check | `grep -c "deepcopy(fiber)" scripts/demo.jl` must match `grep -c "Threads.@threads" scripts/demo.jl` | ❌ Wave 0 |
| REQ-32-G | Open questions documented in 32-RESEARCH.md | documentation-only | N/A | ✅ this file |

### Sampling Rate

- **Per task commit:** `julia -t auto --project=. test/test_acceleration.jl` (unit + regression on acceleration only).
- **Per wave merge:** the full suite command above (acceleration + continuation regression + Phase 28 trust regression).
- **Phase gate:** full suite green before any `burst-run-heavy P32-*` execution. The experiments in Section 6 are blocked on green.

### Wave 0 Gaps (all new files — this phase creates them)

- [ ] `test/test_acceleration.jl` — unit + regression tests per the map above.
- [ ] `scripts/acceleration.jl` — Aitken, polynomial_predict, mpe_combine, rre_combine, safeguard logic, `attach_acceleration_metadata!`.
- [ ] `scripts/demo.jl` — mirrors `scripts/demo.jl`; runs COLD / NAIVE / ACCEL arms, emits trust reports, saves standard images.
- [ ] Extension to `scripts/numerical_trust.jl` — add `attach_acceleration_metadata!(report, meta)` and a `## Acceleration` markdown section. Additive. Schema stays `"28.0"`.
- [ ] Extension to `scripts/continuation.jl` — add `:polynomial` to `LADDER_VARS` predictor enum OR document that `corrector_fn` seam is the integration point (prefer the latter — no `run_ladder` API change). Planner picks one path and defends it.

**Framework install:** none — `Test` stdlib is already available via `[targets] test = ["Test"]` in `Project.toml:37`.

## Security Domain

Security enforcement is not applicable to this phase (no authentication, session management, network I/O, user inputs, cryptography, or persistence of user data). `security_enforcement` is not `true` for this research-grade physics codebase. Omit this section per researcher contract.

## 8. Integration Hazards (the planner must NOT break)

These are codebase invariants the executor must preserve. Tagged `[VERIFIED: ...]` when grep-confirmed.

| Hazard | Rule | Source |
|--------|-----|--------|
| `save_standard_set(...)` must be called for every optimization run that produces a `phi_opt` | 4 PNGs per arm, for every arm, at target ladder step. `scripts/demo.jl` must emit at least 3 `save_standard_set` calls (COLD, NAIVE, ACCEL final `phi_opt` each). | [VERIFIED: `CLAUDE.md` §Standard output images mandate; `scripts/demo.jl` pattern 2 calls] |
| `deepcopy(fiber)` per thread inside `Threads.@threads` blocks | The `fiber` dict has mutable fields (`fiber["zsave"]`). Multi-start / parallel gradient validation both do this [VERIFIED: `scripts/benchmark_optimization.jl:637`, `:730`]. Any Phase 32 parallel evaluation (parallel arms, parallel ladder points) must follow the pattern. | [VERIFIED: CLAUDE.md §deepcopy pattern] |
| `burst-run-heavy` wrapper for heavy Julia | Never `tmux new -d -s run 'julia ...'` directly. Wrapper enforces session tag, heavy lock, stale-lock detection, log teeing. Session tag must match `^[A-Za-z]-[A-Za-z0-9_-]+$` — e.g. `P32-poly-warmstart`. | [VERIFIED: CLAUDE.md §Rule P5] |
| Deterministic environment | `ensure_deterministic_environment()` at module load of every Phase 32 driver. FFTW ESTIMATE + FFTW/BLAS threads pinned to 1. | [VERIFIED: `scripts/determinism.jl:75`; `scripts/continuation.jl:575`] |
| Phase 28 trust schema version | Stays `"28.0"`. Phase 32 adds `report["acceleration"]` ADDITIVELY (same pattern Phase 30 used for `report["continuation"]`). Any bump requires Phase 28 co-sign. | [VERIFIED: `scripts/numerical_trust.jl:7` — one occurrence of `"28.0"`] |
| `scripts/continuation.jl` public API stable | Do NOT change `run_ladder` signature (`corrector_fn`, `cold_start`, `setup_fn`, `baseline_iters` kwargs). Do NOT change `ContinuationSchedule` fields (Phase 33/34 inherit via the `corrector_fn` seam). Extensions go in a new `scripts/acceleration.jl`. | [VERIFIED: `scripts/continuation.jl:118` struct; `:568-572` kwargs] |
| `abspath(PROGRAM_FILE) == @__FILE__` guard | `scripts/demo.jl` must have this guard so `include()` from REPL or tests does not trigger the heavy run. | [VERIFIED: Phase 30 pattern — `scripts/demo.jl` `abspath` check 2 occurrences per 30-01-SUMMARY.md] |
| Julia launched with `-t auto` for simulation work | Every `julia ...` call in scripts or documentation must be `julia -t auto --project=.`. Bare `julia` single-threaded is a CLAUDE.md Rule 2 violation. | [VERIFIED: CLAUDE.md §Rule 2] |
| No new Julia package dependencies without approval | If Phase 32 implementation grows to need `NLsolve` or similar, STOP and escalate. Hand-rolled Anderson / MPE / RRE is the default. | [VERIFIED: `Project.toml` — no `NLsolve`] |

## 9. Open Questions for the Planner

These are decisions this research could not settle; the plan must call them.

### Q1. Anderson vs. polynomial-predictor: commit to polynomial first?

Research recommends starting with polynomial warm-start (Section 3.5) because it is valid everywhere, including non-fixed-point sequences. Anderson is formally only valid on homotopy-in-λ (S5), which is not currently a live ladder. **Should Phase 32 entirely defer Anderson to a follow-up phase, or include a single defensive Anderson run on S5 for completeness?** Research leans toward defer.

### Q2. Extend `scripts/continuation.jl::run_ladder` predictor enum, or inject via `corrector_fn` seam?

Both are possible:
- Option A: Add `:polynomial` to the `schedule.predictor` enum. Requires one-line extensions in `scripts/continuation.jl` and `scripts/numerical_trust.jl::_CONTINUATION_LADDER_VARS` (actually the predictor string validator, not the ladder-var one). Clean integration.
- Option B: Phase 32 introduces its own `run_accelerated_ladder` that wraps `run_ladder` and overrides the `phi_init` passed to the corrector. No changes to `continuation.jl`.

Research recommends Option A because it keeps the continuation module as the one ladder driver, preventing API drift. But Option B is defensible if the planner wants to keep Phase 30 code frozen.

### Q3. Degree cap for polynomial warm-start

Research recommends `D = min(k-1, 2)` — i.e., at most quadratic. The planner should pre-register this in 32-01-PLAN.md frontmatter so it is not tweaked post-hoc. If the research ladder is only 3 rungs long (Phase 30 demo), `D` caps at 1 (linear / secant) and we never see the quadratic benefit until Experiment 1b.

### Q4. Which ladder variable encodes physics best?

- L-ladder: `log L`, raw `L`, or arclength `s = ∫ √(1 + |dphi/dL|^2) dL`? Research recommends `log L` as a starting choice because walk-off and SPM both have logarithmic character in the regimes of interest; arclength is what true pseudo-arclength continuation uses but requires Jacobians we don't have.
- N_phi ladder: `1/N_phi` is unambiguously correct (classical truncation-error scaling). No ambiguity.
- λ_gdd / regularization ladder: `log λ` (homotopy is in log-space for regularization parameters — CS 4220 lectures default to this).

Planner should lock one choice per ladder in the frontmatter of 32-01-PLAN.md.

### Q5. Dependency on Phase 30 completion

CONTEXT.md locks a Wait Directive: do not begin execution until Phase 30 has merged to `origin/main`. Research and planning may proceed in parallel. The plan MUST include the wait check as a gate task: `git fetch origin && git log origin/main --oneline | grep 'integrate(phase30)'` exits 0 before any burst-VM run.

### Q6. Use existing Phase 30 outputs, or re-run for Phase 32?

Phase 30's 3-point L-ladder output (pending burst-VM run per 30-RESULTS.md "Status: Pending") is the natural input to Experiments 1 and 2. The planner should decide:
- Option A: re-run Phase 30's demo as the NAIVE baseline inside `scripts/demo.jl` to guarantee arm parity.
- Option B: consume Phase 30's artifacts (JLD2 + trust reports) as inputs.

Option A is cleaner but wastes ~30 min of burst time. Option B is faster but fragile to Phase 30 output format changes. Research recommends Option A for Experiment 1 (re-run for parity); Option B for Experiment 2 (offline MPE/RRE on existing artifacts).

### Q7. "INCONCLUSIVE" handling

CONTEXT.md states "not worth it" is acceptable but is silent on inconclusive. Planner should pre-register that `INCONCLUSIVE` after all mandatory experiments (0, 1, 2) triggers: either extension to 1b / 3, OR escalation to the user with a summary of the mixed evidence. Do not silently loop on more experiments.

### Q8. Gauge zero-mode projection before acceleration?

Phase 13 established that `{constant, ω-linear}` are exact gauge null-modes [VERIFIED: `results/raman/phase13/FINDINGS.md` verdict]. Acceleration methods that do least-squares combinations of `phi_opt` vectors can amplify motion along these directions harmlessly (cost is invariant) but confusingly (`‖phi_opt‖` inflates). Should Phase 32's accelerator project out gauge components from each `phi_opt` before combining? Research recommends YES as a default, with the projection implemented as a single helper call per the Phase 13 `gauge_fix` primitive (`.planning/phases/13-.../13-01-SUMMARY.md` references `gauge_fix` in `primitives.jl`). Low cost, high interpretive value.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | "L-BFGS on this problem is already a superlinear quasi-Newton method whose iterates do not benefit from Anderson stacking" | §3.3 | If actually linear on hard configs (e.g. the saddle branch), Anderson-on-L-BFGS-iterates becomes attractive again. Mitigation: Aitken Δ² on J_dB per outer iteration inside a single L-BFGS run would detect this cheaply. |
| A2 | "A factor-10 L jump produces a large iterate-to-iterate distance" | §1 | If distance is actually small (Phase 30's pending run will measure), polynomial prediction has less headroom. Measurable once Phase 30 ships. |
| A3 | "15% iteration savings is the minimum bar worth shipping a new method for" | §5 | The threshold is subjective. Planner may tune before running experiments (but not after). |
| A4 | "FFTW.ESTIMATE is required for determinism; switching to MEASURE for Phase 32 benchmarks would invalidate iteration counts" | §4 | Phase 15 proved 1e-9 drift under MEASURE; at max_iter=40 this is below L-BFGS's f_tol of 0.01 dB — plausibly not binding for iteration counts. Conservative assumption; do not relax. |
| A5 | "The competitive-dB branch remains Hessian-indefinite for all L, P in the 32 experiments" | §3.3, §3.4 | Phase 22 surveyed only L=2, P=0.2 (SMF-28) and L=0.5, P=0.01 (HNLF). Long-fiber 100 m regime is untested. If the 100 m regime had definite Hessian, Anderson / MPE would be safer. Research treats saddle-branch as the default; planner should not rely on the mitigation being unnecessary. |
| A6 | "`NLsolve.jl` is NOT a direct dep and adding it would require user approval" | §3 Stack | Verified by grep on `Project.toml`. Stands. |
| A7 | "Phase 31's Branch A output will exist in time for Experiment 3" | §6 | Phase 31 has only CONTEXT + RESEARCH-stub; no plan executed. Research treats Experiment 3 as optional-gated. |

## Sources

### Primary (HIGH confidence — this codebase or grep-verified)

- `scripts/continuation.jl:1-750` — Phase 30 continuation API (grep-verified structs, functions, determinism call site, predictor enum)
- `scripts/numerical_trust.jl:1-139` — Phase 28 trust schema 28.0 (grep-verified schema version constant, threshold tuple)
- `scripts/raman_optimization.jl:76-172` — L-BFGS + log-cost + HagerZhang (grep-verified)
- `scripts/determinism.jl:75-84` — `ensure_deterministic_environment()` (grep-verified)
- `scripts/longfiber_setup.jl:117-156` — `longfiber_interpolate_phi` cross-Nt phase transfer (verified signature)
- `scripts/benchmark_optimization.jl:482-574` — precursor `run_continuation` (grep-verified; superseded by Phase 30 per 30-01-SUMMARY.md)
- `scripts/benchmark_optimization.jl:594-685` — multi-start with `deepcopy(fiber)` per thread pattern (grep-verified)
- `scripts/sweep_simple_run.jl:1-70` — N_phi ladder definition and canonical config
- `.planning/phases/30-.../30-01-SUMMARY.md` — Phase 30 deliverables (tasks, files created, test counts)
- `.planning/phases/30-.../30-01-PLAN.md` — Phase 30 interfaces consumed
- `.planning/phases/30-.../30-RESULTS.md` — Phase 30 pre-registered decision rule (W1-W4, L1-L2)
- `.planning/phases/28-.../28-SUMMARY.md` — Phase 28 trust schema status
- `.planning/phases/27-.../27-REPORT.md` — original audit + second-opinion addendum (defects #1–#9)
- `.planning/phases/22-.../SUMMARY.md` — all 26 Hessian-indefinite optima table
- `.planning/phases/35-.../35-SUMMARY.md` — saddle-escape verdict
- `.planning/phases/13-.../13-02-SUMMARY.md` — Hessian eigenspectrum, matrix-free Lanczos, HVP deterministic pinning
- `.planning/phases/07-parameter-sweeps/07-02-SUMMARY.md:83-85` — 36-point L×P sweep size
- `CLAUDE.md` — standard-images mandate, `deepcopy(fiber)` rule, `burst-run-heavy` Rule P5, Rule 1/2/3
- `Project.toml` — dependency manifest (grep-verified: no `NLsolve` direct dep)

### Secondary (MEDIUM confidence — external, CS 4220 s26 primary sources)

- CS 4220 s26 `lec/2026-04-15.jl` [CITED: `https://raw.githubusercontent.com/dbindel/cs4220-s26/main/lec/2026-04-15.jl`] — Broyden, RRE, Anderson acceleration with explicit formulas and RRE-vs-GMRES connection
- CS 4220 s26 `lec/2026-04-13.jl` [CITED: `https://raw.githubusercontent.com/dbindel/cs4220-s26/main/lec/2026-04-13.jl`] — Modified Newton (Chord, Shamanskii, FD-Newton, inexact Newton)
- CS 4220 s26 `lec/2026-04-17.jl` [CITED: same base URL] — Line search and globalization (Armijo, Wolfe, backtracking)
- CS 4220 s26 `lec/2026-04-20.jl` [CITED: same] — Trust region methods (Steihaug, dogleg, Moré-Sorensen)
- CS 4220 s26 `lec/2026-04-22.jl` [CITED: same] — Continuation and homotopy (Euler predictor, pseudo-arclength, fold bifurcation)
- CS 4220 s26 `lec/2026-04-06.jl` [CITED: same] — Newton vs. fixed-point iteration on reaction-diffusion PDE
- Phase 27 REPORT §F "Extrapolation and acceleration for study families" — problem framing that seeded this phase

### Tertiary (LOW confidence — general numerical-methodology folklore)

- Walker & Ni (2011), "Anderson Acceleration for Fixed-Point Iterations" — the standard Anderson reference; `‖γ‖_∞` safeguard threshold is typically 1e3–1e5. Not directly cited — referenced from memory. Planner should verify the specific threshold if the Anderson arm is implemented. [ASSUMED]
- Sidi (2017) "Vector Extrapolation Methods with Applications" — canonical textbook for MPE/RRE algorithmic details. Not re-read in this session. [ASSUMED]

## Metadata

**Confidence breakdown:**
- Sequence catalogue (S1–S7): HIGH — each family cited at `file:line` or phase-summary level.
- Classification (fixed-point validity): HIGH for the theoretical claim, MEDIUM for "polynomial warm-start is valid everywhere" (it is valid as a predictor, not as a convergence-accelerator; reader should distinguish).
- Method-family failure modes (gauge, saddle, cost-surface incoherence): HIGH — all three anchored at Phase 13 / 22 / 27-second-opinion audits.
- Trust metrics: HIGH — all fields pulled directly from `scripts/numerical_trust.jl`.
- Stop rule thresholds (15%, 1 dB): MEDIUM — pre-registered but subjective; planner may tune before execution.
- Experiment runtime estimates on burst: LOW — no Phase 32 code has run. Numbers extrapolated from Phase 30 demo size and Phase 13 eigendecomposition wall clocks.

**Research date:** 2026-04-21.
**Valid until:** 2026-05-21 (30 days for the stable parts — codebase APIs, Phase 28/30 schemas). The cost-to-signal ordering of Experiments 0/1/2 may shift once Phase 30's demo run lands real numbers on the burst VM; re-evaluate then.

## RESEARCH COMPLETE
