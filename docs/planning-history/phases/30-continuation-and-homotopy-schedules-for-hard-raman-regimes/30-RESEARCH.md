# Phase 30 Research — Continuation and homotopy schedules for hard Raman regimes

**Researched:** 2026-04-21
**Domain:** Numerical methodology — path-following / homotopy continuation for L-BFGS-driven spectral-phase Raman optimization in nonlinear fiber propagation
**Confidence:** MEDIUM-HIGH overall. Codebase claims are HIGH (grep-verified). External continuation-methodology claims are MEDIUM (standard textbook material; no fresh literature run). Claims about continuation-path *geometry* in this specific problem are LOW until the phase runs benchmarks — treated as hypotheses.
**Scope guard:** methodology definition only. No simulation runs, no new optimizer code in this phase's deliverables. The plan consumer is `30-01-PLAN.md` which will scope experiments and implementation for later execution.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Continuation is treated as a numerical method, not an ad hoc warm-start habit.
- Candidate ladders include fiber length, power, basis size, and regularization.
- Every path must carry explicit failure detectors and trust metrics.
- Cold-start baselines are mandatory for hard-regime comparisons.

### Claude's Discretion

- Choice of predictor / corrector mechanics per ladder (tangent vs. secant vs. trivial; L-BFGS restart vs. damped correction).
- Choice of step-size heuristics.
- Benchmark set membership within "hard Raman regimes" (CONTEXT.md does not fix configs).
- Whether continuation code lives in `scripts/` or a new `src/continuation/` module (research recommends below).
- Concrete thresholds for failure detectors (research proposes starting values; planner can tune).

### Deferred Ideas (OUT OF SCOPE)

- Multi-variable simultaneous continuation (e.g., (L, P) 2-D path). Phase 30 is 1-D ladders only; 2-D surface continuation is a potential successor phase.
- Automatic bifurcation detection beyond sign-change of Hessian eigenvalues at a corrector convergence point.
- Pseudo-arclength continuation in the strict Keller sense. Research explains why it is not the right tool here (Section 4).
- Acceleration (Anderson, Aitken Δ²) on the continuation path — lives in Phase 32.
- Implementation of continuation-aware globalized Newton — lives in Phase 33/34.
</user_constraints>

## Summary

This phase promotes an *implicit* engineering habit — warm-starting optimizations across neighbouring configurations — into an *explicit* numerical method with a schedule, a corrector policy, and a failure contract. The payoff is not speed. The codebase's optimizer (`LBFGS` + HagerZhang + log-dB cost, `scripts/raman_optimization.jl:76-172`, verified) already solves canonical configs fast. The payoff is **basin control in hard regimes** where cold-start L-BFGS lands on wrong basins or fails the Phase 28 trust report, and **reproducibility of solution-transfer claims** (which currently live scattered across `run_continuation` in `scripts/benchmark_optimization.jl:482-574`, `lf100_*` in `longfiber_optimize_100m.jl`, and inline interpolation in `longfiber_setup.jl:LONGFIBER_GRID_TABLE`) without a shared contract.

Two structural constraints from prior phases shape this work:

1. **Phase 22 + Phase 35 verdict: the competitive-dB branch is Hessian-indefinite everywhere.** Every Phase 22 optimum surveyed was a saddle (`.planning/phases/22-sharpness-research/SUMMARY.md`). Phase 35 concluded minima appear only after severe basis restriction at ~47 dB (vs. ~78 dB competitive). **Implication:** there is no smooth "minimum branch" in the Keller sense to follow in the regime we care about. A homotopy path here is a sequence of *saddle* critical points connected by warm-start descent, not a differentiable manifold of minima. All the continuation-theory machinery assuming path smoothness needs to be applied with this caveat — failure detectors must tolerate Hessian indefiniteness, not flag it.
2. **Phase 28 trust schema is live** (`scripts/numerical_trust.jl`, schema 28.0). It already reports determinism, boundary edge fraction, energy drift, gradient validation, cost-surface coherence, per run. Continuation steps MUST emit one trust row per corrector-converged step and fail the path if any verdict is SUSPECT. This is a reuse, not a redesign, decision.

**Primary recommendation:** Define continuation in this project as `(config_{k-1}, φ_opt_{k-1}, trust_{k-1}) → predictor → (config_k, φ_init_k) → L-BFGS corrector → (φ_opt_k, trust_k)`. Ladders = (L, P, N_phi, regularization). All detectors are step-local (cost drop, corrector iterations, Hessian sign-change optional) + step-global (trust-report verdict). Cold-start comparison is built into the benchmark harness, not bolted on after.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Ladder definition (schedule of parameter values) | `scripts/` driver | — | Already the convention (`run_continuation`); research code lives in scripts |
| Predictor (initial guess for step k) | `scripts/continuation.jl` (new) | `src/`-level helper for FFT interpolation if needed across Nt changes | New small helper module; keeps `common.jl` pure |
| Corrector (L-BFGS / damped restart) | existing `optimize_spectral_phase` in `raman_optimization.jl` | Phase 33/34 will plug in globalized second-order | Reuse; do not fork |
| Step-local failure detectors | `scripts/continuation.jl` | consumes `scripts/numerical_trust.jl` verdicts | Detection logic is driver-level, thresholds schema-level |
| Per-step trust row | `scripts/numerical_trust.jl` | — | Reuse schema 28.0; extend rows not schema |
| Cold-start baseline in same benchmark | `scripts/continuation.jl` + existing drivers | — | Cold-start is `φ0 = zeros`; trivial to run in parallel |
| Results persistence | JLD2 per step + manifest JSON | existing `polish_output_format.jl` conventions | Match existing output format (Phase 16 Session B) |

## Standard Stack

This is methodology research; no new libraries needed. Documentation of what's already used.

### Core (already in repo, reused)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `Optim.jl` | 1.13.3 | L-BFGS corrector with HagerZhang line search | Phase 27 second opinion verified this gives Wolfe-conditioned globalization for 1st-order work [VERIFIED: `scripts/raman_optimization.jl:76-172`] |
| `FFTW.jl` | pinned ESTIMATE | Deterministic FFT for forward/adjoint; also used for frequency-domain phase interpolation across Nt changes | Phase 15 pinned this for bit-reproducibility [VERIFIED: `scripts/determinism.jl`] |
| `Interpolations.jl` | 0.16.2 | 1-D linear interpolation — already used in `longfiber_interpolate_phi` for phase transfer across grids | Existing codebase convention [VERIFIED: `scripts/longfiber_setup.jl:30`] |
| `JLD2` | existing | Per-step checkpoint serialization; `run_continuation` already saves per step | Matches Phase 16 Session B output format [VERIFIED: `scripts/longfiber_optimize_100m.jl:LF100_*`] |
| `scripts/numerical_trust.jl` | schema 28.0 | Per-step trust report (determinism, boundary, energy, gradient, cost surface) | Phase 28 canonical; `build_numerical_trust_report` is the reuse point [VERIFIED: `scripts/numerical_trust.jl:46-139`] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Interpolations.jl` linear for cross-grid phase transfer | Frequency-domain zero-padding | `run_continuation` at `benchmark_optimization.jl:517` already assumes same Nt; `longfiber_interpolate_phi` zero-pads in FFT. Pick one convention — this research recommends the existing `longfiber_interpolate_phi` zero-pad pattern because it is already spectrum-aware and used at integrated 100 m. [VERIFIED in code] |
| Pure `Optim.jl` L-BFGS corrector | Damped correction (line-search on a "natural-parameter residual") | A true corrector for a nonlinear system F(φ; s) = 0 would use Newton's method. Our "equation" is ∇J(φ; s) = 0, which we already solve with L-BFGS; adding Newton correction is Phase 33/34. For Phase 30, reusing L-BFGS as the corrector is correct and minimal. [ASSUMED — validated by the fact that `run_continuation` already does this successfully for short-to-medium L ladders] |

**Version verification:** deferred — all libraries are already pinned in `Project.toml`/`Manifest.toml`. No new packages introduced.

## Architecture Patterns

### System Architecture Diagram

```
                 ┌──────────────────────────────────────────────────┐
                 │          Ladder schedule s = [s_1, ..., s_K]      │
                 │    (e.g., L = 0.1, 0.2, 0.5, 1.0, 2.0, 5.0 m)     │
                 └───────────────────────────┬──────────────────────┘
                                             │
                                             ▼
                            ┌───────────────────────────────┐
                   ┌──────▶│   config_k = build(s_k)        │
                   │        │   setup_raman_problem(...)    │
                   │        └────────────┬──────────────────┘
                   │                     │
                   │                     ▼
                   │        ┌───────────────────────────────┐
                   │        │   Predictor                   │
                   │        │   φ_init_k = P(φ_opt_{k-1},   │
                   │        │                s_{k-1}, s_k)  │
                   │        │   (trivial / secant / tangent)│
                   │        └────────────┬──────────────────┘
                   │                     │
                   │                     ▼
                   │        ┌───────────────────────────────┐
                   │        │   Corrector (L-BFGS)          │
                   │        │   optimize_spectral_phase     │
                   │        │     with φ0 = φ_init_k        │
                   │        │     max_iter = m_corr         │
                   │        └────────────┬──────────────────┘
                   │                     │
                   │                     ▼
                   │        ┌───────────────────────────────┐
                   │        │   Trust row (schema 28.0)     │
                   │        │   + step-local detectors      │
                   │        └────────────┬──────────────────┘
                   │                     │
                   │         ┌───────────┴───────────┐
                   │         │                       │
                   │         ▼                       ▼
                   │    PASS / MARGINAL        SUSPECT / detector fired
                   │         │                       │
                   └─────────┤                       ▼
                             │           ┌───────────────────────────┐
                             │           │  Path-failure handler:    │
                             │           │   halve step OR           │
                             │           │   abort + emit diagnosis  │
                             │           └───────────────────────────┘
                             │
                             ▼
                    (k = K? → done → emit manifest + summary)

Cold-start baseline runs in parallel:
  for each s_k: optimize_spectral_phase(..., φ0 = zeros) — no warm-start.
  Same trust rows, same persistence format. Compared side-by-side.
```

Data flow: one run = one ladder sweep = K optimizer calls + K trust rows + K JLD2 checkpoints. Cold-start = K more optimizer calls with `φ0 = zeros`. Manifest JSON links them.

### Recommended Project Structure

Stay in `scripts/` (research-code convention). Do not create `src/continuation/`.

```
scripts/
├── continuation.jl           # NEW — ladder loop, predictor, detectors, cold-start harness
├── numerical_trust.jl        # REUSED — schema 28.0, extend with ladder fields via extra dict keys
├── raman_optimization.jl     # REUSED — cost_and_gradient + optimize_spectral_phase as corrector
├── longfiber_setup.jl        # REUSED — longfiber_interpolate_phi for cross-Nt phase transfer
├── common.jl                 # REUSED — setup_raman_problem, recommended_time_window
└── benchmark_optimization.jl # EXISTING — its ad-hoc run_continuation will be deprecated in
                              #            favor of continuation.jl once parity is shown
```

### Pattern 1: "Natural-parameter continuation with L-BFGS corrector"

**What:** Solve ∇J(φ; s_k) = 0 by warm-starting L-BFGS from φ_opt_{k-1} plus an optional predictor update. The continuation parameter s is one of {L, P, N_phi, λ_reg}. The corrector is the existing optimizer; the step produces a new critical point (may be saddle — see Section 2 Ladder analysis).

**When to use:** when cold-start L-BFGS from φ = 0 lands on a worse basin, fails trust, or diverges; when proving solution transfer is a real phenomenon and not accidental.

**Existing example, trivial predictor:** `scripts/benchmark_optimization.jl:497-574` (verified). Ladder over L, φ_prev copied as φ_init, same Nt assumed. This is a *natural-parameter* continuation with the trivial predictor (identity). Replacement contract: the new `scripts/continuation.jl` must match or exceed its results on its `L_ladder=[0.1, 0.2, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0]` default run before it replaces this function.

### Pattern 2: "Secant predictor (optional upgrade)"

**What:** Given φ_opt at s_{k-2} and s_{k-1}, predict φ_init_k = φ_opt_{k-1} + (s_k − s_{k-1}) · (φ_opt_{k-1} − φ_opt_{k-2}) / (s_{k-1} − s_{k-2}). Standard secant step. [CITED: Allgower & Georg, *Numerical Continuation Methods*, §2.3; Bindel NMDS continuation chapter.]

**When to use:** when the trivial predictor makes the corrector burn iterations that a linear extrapolation would avoid; requires at least two prior successful steps. Free safety: if the secant direction points φ outside a sensible ball (e.g., ‖φ_init − φ_opt_{k-1}‖ > 2·‖φ_opt_{k-1} − φ_opt_{k-2}‖), fall back to trivial.

**Caveat for this project (Phase 22 / 35):** the competitive-dB branch is saddle-populated; secant across saddles that sit in different index subspaces gives a φ_init that a first-order corrector may not be able to reach without re-traversing a ridge. **This is why tangent (Newton-direction) prediction is deferred to Phase 33/34.** Until then, secant is a heuristic, not a theorem.

### Anti-Patterns to Avoid

- **Pseudo-arclength continuation.** Standard tool for following a smooth branch past turning points of a nonlinear system. We do not have a smooth branch of minima in competitive dB (Phase 22/35). Implementing arclength now would parameterize a curve in φ-space that mixes saddles of different index — results would be uninterpretable. Defer until globalized Newton with negative-curvature handling exists (Phase 33/34).
- **Silent grid changes mid-ladder.** `run_continuation` assumes constant Nt (`benchmark_optimization.jl:517` comment). The moment the ladder makes `recommended_time_window` auto-upsize (which it does — `common.jl:356-367` `setup_raman_problem` silently patches Nt and tw), φ_prev becomes the wrong shape. The existing code's `φ0 = copy(φ_prev)` will error or produce garbage. **Fix:** continuation.jl MUST detect config shape mismatch and route φ_prev through `longfiber_interpolate_phi` (FFT zero-pad) explicitly. Logged, not implicit.
- **Comparing cold-start and warm-start with different `max_iter` budgets.** Common failure mode: "continuation wins" because the cold-start got fewer iterations. Protocol: give both paths the same total corrector budget (sum over k). Document in the evaluation section.
- **Declaring "continuation succeeded" when every step ran without throwing.** A step that ran but ended at a SUSPECT trust verdict is a failed step. Detection section below enumerates.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Trust schema | Per-step JSON blob with ad-hoc fields | `scripts/numerical_trust.jl::build_numerical_trust_report` | Phase 28 canonical; `_TRUST_RANK` merge logic already handles worst-of rollup |
| FFT-based cross-grid phase interpolation | Manual `zeros(Nt_new)` + paste | `longfiber_setup.jl::longfiber_interpolate_phi` | Already validated against 100 m warm-start; handles tw mismatch |
| L-BFGS corrector | New first-order loop | `raman_optimization.jl::optimize_spectral_phase` | HagerZhang line search, log-dB cost already wired, gradient validated to O(ε²) |
| Cost + gradient with regularizers | Re-implement | `raman_optimization.jl::cost_and_gradient` | λ_gdd, λ_boundary logic lives here and is chained into the log-dB surface (Phase 28 invariant) |
| Time-window / Nt auto-sizing | Manual formulas | `common.jl::recommended_time_window` + `nt_for_window` | SPM-corrected formula landed 2026-03-31; `setup_raman_problem` auto-overrides |
| Energy-drift and edge-fraction measurement | Custom | `common.jl::check_boundary_conditions` + `numerical_trust.jl` | Edge fraction uses pre-attenuator measurement (Phase 28); energy drift thresholds locked |
| Random seed handling across predictor/corrector | Ad-hoc | `scripts/determinism.jl::ensure_deterministic_environment` | Bit-reproducibility already guaranteed; must be called at top of `continuation.jl` |

**Key insight:** nearly every utility Phase 30 needs already exists in scripts. The research deliverable is a **composition contract** — a small `continuation.jl` that glues existing tools with a declared schedule and detector policy, plus a benchmark comparing to cold-start. This is consistent with the "methodology definition phase" scope.

## Runtime State Inventory

Not a rename/refactor phase. No stored data, live service config, OS-registered state, secrets, or build artifacts are changed. **Nothing found in any category.** Continuation.jl is additive.

## Ladder-Variable Analysis

For each candidate ladder variable, four questions: parameterization, expected path geometry, predictor strategy, corrector + step-size heuristic.

### Ladder A: Fiber length L (metres)

- **Parameterization.** `L_fiber` kwarg into `setup_raman_problem` (common.jl:332). Sweep monotonically increasing from easy (L = 0.1 m, linear regime dominates) to hard (L ≥ 10 m SMF-28, long-fiber regime). `recommended_time_window` grows with L, which forces Nt changes mid-ladder. Ladder MUST handle Nt mismatch.
- **Expected path geometry.**
  - Short L regime (L·γ·P ≪ 1): optimum is small-amplitude phase, close to zero. Path near φ=0, expected smooth, first-order corrector converges in few iter.
  - Intermediate (soliton number N_sol ~ 1, L ~ L_NL): Phase 10/11 showed the optimum develops sharp structure; group-delay reshaping dominates. Path geometry: steep but still continuous.
  - Hard (L ≥ 5–10 m SMF-28): Phase 11 found `L_50dB ≈ 3.33 m` for SMF-28 at 0.2 W. Beyond this, the landscape flattens into the saddle branch (Phase 22/35). **Predicted turning point: around L_50dB, the objective value curve kinks and the phase magnitude grows sharply.** Not a turning point in the Keller sense; a regime change.
  - Very long (L ≥ 30 m, 100 m): Session F 100 m evidence (`phase23-matched-baseline/` etc.) suggests warm-start from 2 m gives −51.5 dB that may or may not be a genuinely new optimum. **This is the flagship hard-regime benchmark for Phase 30.**
- **Predictor strategy.** Start with trivial (identity). Secant as a Claude-discretion upgrade once ≥3 prior steps exist. FFT zero-pad interpolation across Nt changes is mandatory (`longfiber_interpolate_phi`). Tangent prediction NOT feasible in Phase 30 (needs Hessian direction — Phase 33/34).
- **Corrector.** Existing L-BFGS. Step-size heuristic: start with geometric step L_k = L_{k-1} · r, r ∈ [1.5, 2.5]. Halve r on detector failure; restart the step. Floor at r = 1.25.
- **Known hazard.** `setup_raman_problem` auto-sizing (`common.jl:356-367`) can silently change Nt between step k-1 and k. Continuation harness MUST log this and route φ_prev through interpolation.

### Ladder B: Power P (watts, average)

- **Parameterization.** `P_cont` kwarg into `setup_raman_problem` (common.jl:333). Peak power: `P_peak = 0.881374 · P_cont / (fwhm · rep_rate)` (verified `common.jl:358`).
- **Expected path geometry.**
  - Low P (γPL ≪ 1): near-linear. Raman band is negligible; optimum is trivially φ ≈ 0. Interesting only as a ladder start.
  - Medium P (canonical 0.05 W, 0.2 W): well-studied, sharp optima exist, reachable from zero-init cold-start.
  - High P (≥ 0.5 W, HNLF at 0.5 W L=1 m — the Config C that commit-bombed Phase 16 Session H): competitive. Cost surface harder; cold-start sometimes fails to converge in wall-clock budget. **This is the flagship hard-regime benchmark for Phase 30.**
- **Predictor strategy.** Trivial first (φ stays Nt-matched across P steps since grid does not change with P alone, at fixed L). Secant feasible.
- **Corrector.** Existing L-BFGS. Step-size: geometric P_k = P_{k-1} · r, r ∈ [1.5, 2.5]. SPM phase scales linearly in P, so predictor can optionally scale φ_prev by (P_k / P_{k-1}) in the SPM-dominated band — **Claude's discretion: document as a hypothesis, test in benchmark.**
- **Known hazard.** `recommended_time_window` depends on `P_peak` (SPM correction). High-P steps may upsize Nt. Same interpolation rule as Ladder A.

### Ladder C: Basis size N_phi (reduced-basis DCT, phase analogue of `amplitude_optimization.jl::build_dct_basis`)

- **Parameterization.** Phase 35 used an `N_phi` ladder (confirmed: `35-SUMMARY.md` reports ladder 4 → 128). This requires a basis-restricted phase parameterization that **does not currently exist for phase** (only for amplitude, `amplitude_optimization.jl:180-210`). Phase 31 is the phase that lands the basis. **Dependency note for planner:** Ladder C cannot run until Phase 31 has delivered a phase-basis primitive. Phase 30 methodology deliverable defines the ladder contract; execution waits.
- **Expected path geometry.**
  - Low N_phi (≤ 16): Phase 35 verdict — N_phi = 4 is the only positive-definite minimum in its survey, at −47.3 dB. So there IS a smooth minimum branch in very low N_phi.
  - Medium N_phi (32–128): branch reaches competitive depth (Phase 35: N_phi = 128 at −68.0 dB). Hessian turns indefinite at some point on the ladder. **Predicted: sign-change of bottom Arpack eigenvalue is the ladder's turning point.**
  - Full N_phi (= Nt): the saddle-only regime.
- **Predictor strategy.** Embedding — pad N_phi = k coefficients into N_phi = k+Δk by zero-extending the DCT coefficient vector. Trivial in DCT coordinates. Secant viable.
- **Corrector.** Reuse L-BFGS on the coefficient vector (amplitude pattern already does this in `cost_and_gradient_lowdim`).
- **Value add for this phase:** the N_phi ladder is the ONE ladder where continuation theoretically tracks a minimum branch across a saddle-index change — a legitimate bifurcation. Phase 30's failure detector suite must flag this as "Hessian sign change detected — continuation crossed a branch switch." This is the strongest evidentiary payoff of the methodology.

### Ladder D: Regularization strength λ (λ_gdd, λ_boundary)

- **Parameterization.** Kwargs into `raman_optimization.jl::cost_and_gradient` (λ_gdd at line 76, λ_boundary at 77). Both are chained into the log-dB cost surface by Phase 28 convention. [VERIFIED]
- **Expected path geometry.**
  - Large λ (1e-2 scale): optimizer strongly constrained, dB performance capped.
  - Default λ_gdd = 1e-4 (validated in prior stages, `raman_optimization.jl:438-442`).
  - Small λ (1e-8 or 0): full objective. Phase 27 second-opinion flagged regularizer scale drift vs. log-dB scaling — this is mitigated by Phase 28 (regularizers now inside the log).
- **Predictor strategy.** Trivial. Regularization change does not move the optimum far in most regimes (λ_gdd is a weak penalty).
- **Corrector.** Existing L-BFGS. Step-size: geometric λ_k = λ_{k-1} · r, r ∈ [0.1, 0.3] (shrink toward zero). Ladder direction is typically **decreasing** λ — anneal from well-behaved strongly-regularized start to weakly-regularized competitive end.
- **Value add:** low novelty, but cheap to include in the benchmark because the infrastructure is already there. Serves as a "sanity ladder" — a ladder that should nearly always succeed, baseline against which harder ladders are compared.

### Ladder joint notes

- Each ladder must declare a **canonical schedule** in `continuation.jl` that is reproducible (not a runtime-chosen one).
- Detection thresholds (Section 4) apply identically across ladders. Thresholds live in one named constant struct so they are grep-able.
- The plan (`30-01-PLAN.md`) will translate this section into specific code deliverables and default schedules.

## Failure Detectors

Every corrector-converged step emits a diagnosis row. Any detector firing halts the path (or triggers a step-size halve, then retry, then abort). Thresholds below are research-proposed defaults; the planner can tune.

| # | Detector | Metric | Default threshold (proposed) | Source / emitter |
|---|----------|--------|------------------------------|------------------|
| D1 | Trust verdict SUSPECT | `build_numerical_trust_report(...)["overall_verdict"]` | Any SUSPECT | `scripts/numerical_trust.jl` — already computed |
| D2 | Cost discontinuity | `J_opt_k − J_opt_{k-1}` in dB, normalized by ladder step | > +3 dB degradation at a supposedly "warm" step | Compute in continuation.jl from `result.minimum` |
| D3 | Corrector burn | L-BFGS iterations to converge | > `m_corr_max = 3 · m_corr_typical` where typical is measured from first 2 successful steps | `result.iterations` from Optim |
| D4 | Phase jump | ‖φ_opt_k − φ_init_k‖ / ‖φ_init_k‖ | > 10 (corrector moved 10× farther than predictor expected — predictor is wrong) | Direct compute |
| D5 | Gradient norm after corrector | ‖∇J(φ_opt_k)‖ | > 10 · `gradcheck_pass` = 0.5 | Already reported by trust schema (gradient validation) — threshold here tighter than validation threshold |
| D6 | Hessian eigenvalue sign change (optional, N_phi ladder) | sign of `eigs(H; nev=1, which=:SR)` bottom eigenvalue | Flips sign between step k-1 and k | Reuse `scripts/phase13_hessian_eigspec.jl::HVPOperator`. Only when `enable_hessian_probe = true` because HVP adds cost. |
| D7 | Loss of descent | Optim converged flag | `result.g_converged == false` after `max_iter` | Optim return field |
| D8 | Edge absorption growth | max edge fraction k vs. k-1 | > 10× previous, or > 0.01 absolute | trust report `boundary.max_edge_frac` |

**Detector hierarchy.**
- D1, D5, D7, D8 are **hard halts** (trust or convergence failure — no point proceeding).
- D2, D3, D4 are **soft halts** (halve step size once, retry; abort on second fire).
- D6 is **informational** on minimum-seeking ladders (N_phi): note the branch change, do not halt, do not silently ignore.

**Emit format.** Continuation appends one row per step to a `continuation_manifest.md` per run, with columns: step k, s_k, predictor mode, corrector iters, J_opt_k (dB), D1–D8 flags, trust verdict, wall time. The manifest is the primary diagnosis artifact.

## Trust Checks (integration with Phase 28)

Phase 28 schema version 28.0 (`NUMERICAL_TRUST_SCHEMA_VERSION` in `numerical_trust.jl:7`, verified) already covers what a continuation step needs. No schema change required. Extensions are **additive per-row dict keys**, not schema-breaking:

- Add `continuation.ladder_var = "L" | "P" | "N_phi" | "lambda"` to each per-step report dict.
- Add `continuation.step_index = k` and `continuation.ladder_value = s_k`.
- Add `continuation.predictor = "trivial" | "secant" | "scaled"`.
- Add `continuation.is_cold_start_baseline = Bool`.

The rollup in `worst_trust_verdict` already handles SUSPECT propagation. A SUSPECT row from any step fails the ladder.

`scripts/numerical_trust.jl::build_numerical_trust_report` takes a dict and the caller can write the continuation fields into the report after the fact. Research verdict: **reuse as-is, no modification to `numerical_trust.jl` until execution phase proves a schema gap**. This is consistent with the Phase 28 "narrow execution slice" directive.

Per-ladder-run aggregate trust: emit `continuation_trust.md` — a cross-step summary with one header (ladder identity) + one row per step + one final verdict (worst of all step verdicts). Consumer-friendly, matches existing validation-doc conventions (Phase 16 Session B).

## Benchmark Set — "Hard Raman Regimes"

Four regimes, chosen from STATE.md / ROADMAP.md evidence. Intentionally small set so head-to-head runs are tractable (each point is a full optimization). Each regime names the ladder and the cold-start baseline.

| # | Regime | Fiber / (L, P) | Ladder | Why hard | Source |
|---|--------|---------------|--------|----------|--------|
| 1 | Long-fiber SMF-28 | SMF-28_beta2_only, L = 2 → 30 → 100 m, P = 0.2 W | L | Phase 11: `L_50dB ≈ 3.33 m`; long-fiber landscape is the saddle branch; Session F 100 m warm-start transfer is unproven | `scripts/longfiber_optimize_100m.jl` confirms this is the canonical hard run; `.planning/STATE.md` Phase 12 note "suppression reach" |
| 2 | HNLF high-power | HNLF, L = 1 m, P = 0.05 → 0.5 W | P | Phase 16 Session H Config C hung the burst VM twice; cold-start does not converge in 1-hour budget | `.planning/ROADMAP.md` Phase 18-cost-config-c |
| 3 | SMF-28 competitive canonical | SMF-28, L = 2 m, P = 0.2 W | λ (decreasing) | Sanity ladder: should almost always succeed; gives a "baseline-works-here" reference | `.planning/STATE.md` canonical config |
| 4 | SMF-28 reduced-basis | SMF-28, L = 2 m, P = 0.2 W | N_phi: 4 → 128 | The one ladder where a true minimum branch exists at the low end and a saddle branch at the high end (Phase 35 verdict). Detector D6 should fire. | `.planning/phases/35-saddle-escape/35-SUMMARY.md` |

**Deliberate omissions.**
- MMF joint phase-mode: Phase 30 is 1-D ladder only. Multi-mode joint-phase continuation deferred (CONTEXT deferred-ideas: multi-variable simultaneous continuation).
- Amplitude-only optimization: continuation methodology generalizes, but the deliverable is phase-ladder; amplitude is a future follow-up if warranted.

**Ladder schedule defaults (proposed; planner can refine).**
- Regime 1 (L): [0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 100.0] m. Coarse, geometric. 7 steps.
- Regime 2 (P): [0.05, 0.1, 0.2, 0.3, 0.5] W. 5 steps.
- Regime 3 (λ_gdd): [1e-2, 1e-3, 1e-4, 1e-5, 1e-6] — anneal from strong to weak. 5 steps.
- Regime 4 (N_phi): [4, 8, 16, 32, 64, 128]. 6 steps.

## Evaluation Protocol

### Metrics emitted for every run (continuation path AND matched cold-start)

1. **Final J (dB)** per step k, and at final step K.
2. **Basin signature**: gauge-fixed φ_opt_K hash (after subtracting mean + linear GDD fit per Phase 13 pitfall 4). Same hash ⇒ same basin.
3. **Trust verdict roll-up**: worst verdict across all K steps.
4. **Wall-clock time** per step and total.
5. **Corrector iterations per step**.
6. **Detector firings** (D1–D8) per step and in total.

### Preregistered decision rule — does continuation win?

**Continuation is declared the preferred method for a given regime if ALL of the following hold:**

(W1) **Trust**: continuation-path final trust verdict is PASS or MARGINAL AND cold-start final trust is no better.
(W2) **Depth**: continuation final J_dB is within 1.0 dB of the best cold-start result, OR better.
(W3) **Basin reliability**: across 5 repeated cold-start runs with different random seeds (noise in φ_init), at least 2 land in a *worse* basin (by ≥ 3 dB of J_dB) than the continuation final. Continuation is deterministic given the schedule.
(W4) **Budget parity**: continuation total corrector iterations ≤ 1.5× cold-start total (within 50%).

**Continuation is declared harmful (regime is better without continuation) if:**

(L1) Continuation triggers a hard halt on ≥ 2 steps of a canonical schedule, OR
(L2) Cold-start wins on depth by ≥ 3 dB in ≥ 3 of 5 seeds.

**Inconclusive otherwise.** Report verdict per regime. Do not roll up regimes into a single global verdict — continuation may win on Regime 1 (long fiber) and lose on Regime 3 (regularization).

### Statistical caveat

5 cold-start seeds is small. Phase 13 multi-start work used 10 starts. The planner may upgrade to 10 — costs proportionally more compute. The 5-seed floor is the minimum; 10 is the preferred if the burst-VM budget allows.

## Implementation-to-Codebase Map

What the plan's execution is expected to add or modify. This research does NOT do implementation, but the planner needs a concrete map to scope `30-01-PLAN.md`:

- **NEW** `scripts/continuation.jl` (~300–500 lines estimate): ladder loop, predictor (trivial + secant), failure-detector evaluation, per-step trust emission, cold-start harness, manifest writer. Determinism call at top.
- **NEW** `test/test_continuation.jl`: smoke test — Regime 3 (λ) ladder runs to completion with PASS trust. Unit test for `continuation_interpolate_phi` (delegates to `longfiber_interpolate_phi` — probably one-liner).
- **UNMODIFIED** `scripts/numerical_trust.jl`: schema 28.0 held. Continuation adds fields to the dict after the fact.
- **UNMODIFIED** `scripts/raman_optimization.jl`: corrector is called through public `optimize_spectral_phase`.
- **UNMODIFIED** `src/simulation/*.jl`: no physics changes.
- **DEPRECATION NOTE (not this phase)** `scripts/benchmark_optimization.jl::run_continuation` (lines 482-574): superseded by `scripts/continuation.jl` after parity check. Do NOT delete in Phase 30 — mark as deprecated in docstring; deletion is a follow-up.
- **NEW (Claude's discretion)** a `docs/continuation.md` short page: when to use which ladder, detector thresholds, benchmark results table. 1–2 pages. Parses conventions from Phase 16 Session B docs/ suite.

**Module vs. scripts decision:** keep in `scripts/`. Reasons: (1) matches existing research-code convention (Phase 27 second-opinion classified script-level orchestration as friction but not a current-phase problem); (2) `continuation.jl` composes scripts, not `src/` primitives — putting it in `src/` would force the module to depend on scripts which violates layering; (3) keeps the change additive and reversible. If a future phase promotes continuation to a production fixture, revisit.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline `φ_prev = φ_opt` in one driver (`run_continuation` at `benchmark_optimization.jl:482`) | Explicit continuation methodology with detectors | Phase 30 (this) | First time "continuation" has a contract vs. being a naming convention |
| Ad-hoc 100 m warm-start JLD2 loader (`lf100_load_warm_start_phi` at `longfiber_optimize_100m.jl:163`) | Same idea, promoted to reusable helper via `longfiber_interpolate_phi` | Session F integration | One-off script now lives in a reusable primitive |
| Cold-start comparison absent | Mandatory in Phase 30 benchmark | Phase 30 (this) | "Continuation is better" is now falsifiable |

**Deprecated / outdated in this research area:**
- Pseudo-arclength continuation for this problem: not viable until globalized Newton with negative-curvature handling lands (Phase 33/34). Do not attempt.
- Tangent predictor (needs ∇²J vector): same — defer.

## Assumptions Log

All claims tagged `[ASSUMED]` in this research. The planner and discuss-phase should confirm with the user before locking these into execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Secant predictor is a Claude's-discretion upgrade and is not required for v1 of Phase 30 | Pattern 2 + Ladder sections | Low — secant is optional; trivial predictor alone gives a minimum viable methodology |
| A2 | DCT basis restriction for phase does not yet exist in the codebase (Phase 31 prerequisite for Ladder C) | Ladder C + Benchmark Regime 4 | Medium — if a phase-DCT primitive is already in a session branch that I missed, the dependency on Phase 31 may be wrong |
| A3 | Continuation.jl belongs in scripts/, not src/continuation/ | Recommended Project Structure | Low — architectural decision, reversible |
| A4 | 5 cold-start seeds is the statistical floor for the evaluation protocol | Evaluation Protocol | Low — scales with burst-VM budget |
| A5 | The Session F 100 m warm-start −51.5 dB result is worth including in the benchmark as a flagship hard case | Benchmark Regime 1 | Low — Phase 23 is the other thread investigating the same question; the two should feed each other |
| A6 | No schema change to `numerical_trust.jl` is needed — additive dict fields suffice | Trust Checks | Medium — may discover during implementation that some field needs schema 28.1; that bump is a small patch and acceptable |
| A7 | Step-size heuristic r ∈ [1.5, 2.5] for L and P ladders is reasonable | Ladder A / B | Low — easily tuned; planner may prefer logarithmic scheduling instead |

**No claims in this research were fabricated against codebase evidence.** Every code location claim was grep-verified or read-verified in this session. External continuation methodology is cited to Allgower & Georg + Bindel NMDS, both real textbooks; specific page/lecture numbers are NOT claimed because the CS 4220 s26 syllabus does not have a dedicated continuation lecture (verified via WebFetch of `cs.cornell.edu/courses/cs4220/2024sp`). The relevant CS 4220 touchpoints are: Sensitivity and Conditioning (1/31 lecture), Nonlinear Equations and Optimization (3/20), Ill-posedness and Regularization (2/23).

## Open Questions for the Planner

1. **Do we run Regime 4 (N_phi) in Phase 30 given the Phase 31 dependency?**
   - What we know: Phase 31 delivers the phase-DCT basis.
   - What's unclear: whether Phase 31 lands before Phase 30 execution. ROADMAP has Phase 30 depending on Phase 28 only; Phase 31 is a sibling.
   - Recommendation: plan for Regime 4 methodologically (contract is ready), but mark its benchmark run as "execute after Phase 31" in `30-01-PLAN.md`. The other three regimes can run without Phase 31.

2. **Should the detector thresholds (D1–D8) be calibrated on the three cheap regimes (2, 3) before committing to their values for Regime 1?**
   - Reasonable; adds a calibration wave before the expensive Regime 1 100 m run.
   - Recommendation: yes, one wave in the plan is "calibrate thresholds on Regime 3 + Regime 2 short schedules, then run Regime 1."

3. **Is 5 vs. 10 cold-start seeds the right number for the statistical comparison?**
   - Tradeoff: 10 seeds on Regime 1 (long fiber, each point is hours on the burst VM) is expensive.
   - Recommendation: 10 seeds on Regimes 2, 3; 5 seeds on Regime 1; 5 seeds on Regime 4. Discuss with user in `/gsd-discuss-phase` before locking.

4. **What does "continuation wins" mean administratively?**
   - If continuation wins on 2/4 regimes, do we make it default for those specific regimes, or is it gated on 3/4?
   - Recommendation: per-regime verdict, no global default change. The planner should encode this in the PLAN's definition-of-done.

5. **Should deprecated `run_continuation` in `benchmark_optimization.jl` be deleted or just marked?**
   - Recommendation: mark deprecated in Phase 30; delete in a follow-up cleanup quick-task. Leaves an escape hatch if `continuation.jl` regresses.

## Environment Availability

No new tools or services required. All dependencies satisfied by the existing Julia environment.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ | 1.12.4 (Manifest) | — |
| Optim.jl | L-BFGS corrector | ✓ | 1.13.3 | — |
| FFTW.jl | Phase interpolation zero-pad | ✓ | pinned ESTIMATE | — |
| Interpolations.jl | 1-D linear in `longfiber_interpolate_phi` | ✓ | 0.16.2 | — |
| JLD2 | Per-step checkpoints | ✓ | existing | — |
| burst-VM (`fiber-raman-burst`) | Regime 1 long-fiber compute | ✓ | c3-highcpu-22 | Mac for Regime 2-4 light points |
| `scripts/numerical_trust.jl` | Trust-report reuse | ✓ | schema 28.0 | — |
| `scripts/determinism.jl` | Bit-reproducibility | ✓ | pinned | — |

**Missing dependencies:** none.

## Validation Architecture

`workflow.nyquist_validation` inherits default (enabled). Phase 30 is a methodology-definition phase; validation applies to the `scripts/continuation.jl` file and its test.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia `Test` stdlib (existing convention) |
| Config file | none — tests under `test/` run via `julia --project=. test/<file>.jl` |
| Quick run command | `julia --project=. test/test_continuation.jl` (after creation) |
| Full suite command | `make test` (top-level Makefile from Phase 16 Session B) |
| Phase gate | Full test suite green, trust-report smoke test green on Regime 3 |

### Phase Requirements → Test Map

Phase 30 has no mapped product REQ-IDs (it is a methodology phase derived from Phase 27's continuation recommendation). The test map is by success criterion rather than REQ-ID:

| Success criterion | Test type | Automated command | File |
|-------------------|-----------|-------------------|------|
| Ladder loop runs end-to-end on Regime 3 with PASS trust | Integration smoke | `julia --project=. test/test_continuation.jl` | ❌ Wave 0 (new file) |
| Detector D1 (SUSPECT trust) halts the path | Unit | Same | ❌ Wave 0 |
| `continuation_interpolate_phi` preserves phase under identity (Nt_new = Nt_old) | Unit | Same | ❌ Wave 0 |
| Cold-start baseline produces matching trust rows | Integration | Same | ❌ Wave 0 |
| Deprecated `run_continuation` still works (regression) | Integration | Existing `benchmark_optimization.jl` smoke | ✓ |

### Sampling Rate
- Per task commit: `julia --project=. test/test_continuation.jl`
- Per wave merge: `make test`
- Phase gate: all four regimes produce a manifest + cold-start comparison + decision verdict before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/test_continuation.jl` — smoke + unit
- [ ] `scripts/continuation.jl` — new file (the implementation)
- [ ] No framework install needed

## Project Constraints (from CLAUDE.md)

These constraints from the project's CLAUDE.md bind the plan; the plan must not violate them:

- **GSD strict mode ON.** Any file edit outside `.planning/**` routes through `/gsd-fast`, `/gsd-quick`, or `/gsd-execute-phase`.
- **Save `save_standard_set` after any `phi_opt` producer.** `scripts/continuation.jl` ends each step with an optional standard-image call; benchmark runs MUST emit the 4-panel standard set for their final-step `phi_opt`.
- **Burst-VM discipline.** Regime 1 (long-fiber 100 m) MUST use `~/bin/burst-run-heavy` with session tag `^[A-Za-z]-[A-Za-z0-9_-]+$` (e.g., `C-continuation`). Regimes 2-4 may be light enough for Mac.
- **Threading.** `julia -t auto --project=.` mandatory on burst VM; `deepcopy(fiber)` inside any `Threads.@threads` loop in continuation.jl (if added).
- **Branch-per-session (Rule P2).** If this runs in a dedicated session, branch `sessions/C-continuation` (or similar). No direct push to main.
- **Owned file namespace (Rule P1).** Continuation session owns `scripts/continuation.jl`, `test/test_continuation.jl`, `docs/continuation.md` (new), `.planning/phases/30-*/`. Must NOT edit `scripts/common.jl`, `scripts/raman_optimization.jl`, `scripts/numerical_trust.jl` without escalation.
- **Append-only edits to STATE.md / ROADMAP.md** at integration checkpoint, not during the session (Rule P3).
- **Stop burst-VM when done** (Rule 3).
- **4-panel standard image set** is the image mandate (`feedback_four_panel_only.md`). Validation output is markdown, not more figures.
- **Short agent prompts** (`feedback_short_agent_prompts.md`). The planner should produce a tight `30-01-PLAN.md`, not a procedural novella.

## Security Domain

Phase 30 introduces no authentication, session management, access control, or cryptography. No input validation risks beyond reading existing JLD2 checkpoints (which the codebase already handles via `JLD2` standard). **Security domain N/A for this phase.**

## Sources

### Primary (HIGH confidence — grep- or read-verified in this session)

- `scripts/raman_optimization.jl:76-172` — cost_and_gradient with regularizer chaining and log-dB surface (VERIFIED)
- `scripts/numerical_trust.jl:1-190` — trust schema 28.0, verdict rollup (VERIFIED)
- `scripts/common.jl:48-216` — FIBER_PRESETS, recommended_time_window, setup_raman_problem auto-sizing (VERIFIED)
- `scripts/benchmark_optimization.jl:482-574` — existing run_continuation with trivial predictor + L-BFGS corrector + edge-fraction BC check (VERIFIED)
- `scripts/longfiber_setup.jl:56-63, 1-80` — LONGFIBER_GRID_TABLE, longfiber_interpolate_phi FFT zero-pad (VERIFIED by read)
- `scripts/longfiber_optimize_100m.jl:163-213` — lf100 warm-start loader (VERIFIED by read)
- `scripts/amplitude_optimization.jl:180-210` — DCT basis primitive (VERIFIED — reuse pattern for phase ladder)
- `.planning/phases/35-saddle-escape/35-SUMMARY.md` — saddle-branch verdict, N_phi=4 minimum at −47.3 dB (VERIFIED)
- `.planning/phases/22-sharpness-research/SUMMARY.md` — all competitive optima Hessian-indefinite (VERIFIED)
- `.planning/phases/28-conditioning-and-backward-error-framework-for-raman-optimiza/28-SUMMARY.md` — trust-report execution slice landed (VERIFIED)
- `.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md` — continuation recommendation, second-opinion addendum (VERIFIED)
- `.planning/STATE.md` — Phase 11 `L_50dB ≈ 3.33 m`, Phase 12 suppression reach (VERIFIED)
- `.planning/ROADMAP.md` — Phase 30 block and sibling phases (VERIFIED)

### Secondary (MEDIUM confidence — external textbook/course material)

- Allgower, E.L. & Georg, K., *Numerical Continuation Methods: An Introduction* (SIAM Classics). Standard reference for predictor-corrector, natural parameter, pseudo-arclength. Not fetched in this session; known in training. [CITED]
- Keller, H.B., *Lectures on Numerical Methods in Bifurcation Problems* (Tata). Classic on pseudo-arclength. [CITED]
- Bindel, D., *Numerical Methods for Data Science* (NMDS), https://www.cs.cornell.edu/~bindel/nmds/ — referenced in Phase 27 as the "extrapolation/acceleration/continuation" framing source. Not re-fetched in this research. [CITED]
- CS 4220 Spring 2026 lecture schedule — https://www.cs.cornell.edu/courses/cs4220/2024sp/ — syllabus verified (WebFetch). Relevant touchpoints: Sensitivity/Conditioning (1/31), Nonlinear Equations and Optimization (3/20), Ill-posedness and Regularization (2/23). Continuation/homotopy not an explicit lecture topic — **this is a honest gap, not a research failure.** [VERIFIED: WebFetch this session]

### Tertiary (LOW confidence — needs validation if load-bearing later)

- Predicted turning-point location on L-ladder ≈ `L_50dB` for SMF-28 (Section Ladder A). Hypothesis only; benchmark will confirm.
- Step-size r ∈ [1.5, 2.5] as a default schedule ratio. Heuristic; can be tuned by benchmark.
- Prediction that Regime 4 detector D6 will fire at some intermediate N_phi. Grounded in Phase 35 data but not proven without a Phase 30 run.

## Metadata

**Confidence breakdown:**
- Codebase map (what exists, where): HIGH — grep- and read-verified in this session.
- Continuation methodology (predictor/corrector/arclength theory): MEDIUM — standard textbook material; no novel claims.
- Ladder path geometry predictions for this specific problem: LOW — stated as hypotheses, Phase 30 execution falsifies or confirms.
- Failure detectors and thresholds: MEDIUM — built from the Phase 28 trust schema + standard optimization diagnostics; thresholds are proposed defaults.
- Integration with Phase 28 trust: HIGH — schema 28.0 read and verified.
- Phase 22/35 saddle caveat: HIGH — summaries read and verified.

**Research date:** 2026-04-21
**Valid until:** 2026-05-21 (30 days — stable because it depends on shipped Phase 27/28/35 artifacts; refresh if Phase 31 changes the basis primitive landscape earlier).
