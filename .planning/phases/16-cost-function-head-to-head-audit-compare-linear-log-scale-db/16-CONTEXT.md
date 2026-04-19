# Phase 16: Cost Function Head-to-Head Audit — Context

**Gathered:** 2026-04-17 (auto mode, Session H)
**Status:** Ready for planning
**Owner session:** H (`sessions/H-cost`, `~/raman-wt-H`)

<domain>
## Phase Boundary

Systematically compare **four cost-function variants** for spectral-phase Raman-suppression optimization across **three (fiber, L, P) configurations**, and recommend a project-wide default cost with evidence. Produces a driver, an analyzer, per-config tables and figures, and `.planning/notes/cost-function-default.md`.

**In scope:**
- New wrapper scripts `scripts/cost_audit_*.jl` that call the existing optimizers unchanged.
- 4 × 3 = 12 optimization runs + Hessian eigenspectrum + perturbation robustness probes per optimum.
- Decision artifact grounding the choice in both measured data and ML loss-landscape literature (SAM/ASAM/GSAM; Li et al. 2018).

**Out of scope (deferred):**
- Implementing a full quantum-noise-aware cost from first principles (only a *scaffold* is included so it can slot in later).
- Hyperparameter tuning of any cost (use Phase 14 defaults for sharpness λ=0.1; no sweep).
- Modifying any existing optimizer file (`scripts/raman_optimization.jl`, `scripts/common.jl`, `scripts/sharpness_optimization.jl`, `src/**`) — enforced by CLAUDE.md Rule P1 and Session H owned-namespace.

</domain>

<decisions>
## Implementation Decisions

### Cost-Function Variants (the four horses)

- **D-01 [auto]: Linear cost.** `optimize_spectral_phase(..., log_cost=false, λ_gdd=0.0, λ_boundary=0.0)` — the original `J = E_band / E_total` as minimization target.
- **D-02 [auto]: Log-scale dB cost.** `optimize_spectral_phase(..., log_cost=true)` — Phase 8 fix. Gradient scaled by `10/(J·ln10)` via existing code.
- **D-03 [auto]: Sharpness-aware cost.** `optimize_spectral_phase_sharp(prob, φ0; lambda_sharp=0.1, n_samples=8, eps=1e-3, rng=MersenneTwister(seed))` — Phase 14 `J + λ·S(φ)` with Hutchinson-estimated sharpness under gauge-projected Rademacher directions. λ fixed at the Phase 14 default (no sweep — that was Plan 14-02's scope; we subsume it by reporting a single λ).
- **D-04 [auto]: Noise-aware scaffold.** Cost = linear `J` + `γ_curv · ⟨|∂²φ/∂ω²|²⟩_band` where the weighted average is over the Raman band frequency bins. Rationale: second-derivative penalty in the *output* Raman band is a tractable classical proxy for quantum-noise amplification (group-velocity-dispersion-like curvature structure shapes photon-number variance in multimode squeezed-vacuum propagation — see Rivera-Lab domain context). γ_curv=1e-4 chosen so the curvature term is O(10%) of the linear J at the starting phase (auto-calibrated per config at φ₀, logged). Scaffold-quality: not claimed physically rigorous, but numerically well-defined and differentiable. Gradient implemented via autodiff of the penalty term only; J and ∇J come from the existing `cost_and_gradient`. Placed in `scripts/cost_audit_noise_aware.jl` as a pure wrapper that adds the penalty to the existing J and ∇J tuple.

### Fair-Comparison Protocol (locked, identical across all 4 variants per config)

- **D-05 [auto]: Grid.** `Nt=8192`, `beta_order=3`, `M=1`. Matches Phase 14 snapshot and Phase 6 canonical so downstream cross-phase comparison is possible.
- **D-06 [auto]: Starting phase.** `φ₀ = 0.1 · randn(MersenneTwister(SEED), Nt)` with **SEED fixed per config** (42, 43, 44 for configs A, B, C respectively) and reused verbatim across all four cost variants within a config. Zero initial phase would make results degenerate (every variant would start on the same manifold symmetry point and the dB cost is undefined at φ=0 for some regimes). A small-random start is standard practice.
- **D-07 [auto]: Iteration cap.** `max_iter=100` uniformly. Phase 14 snapshot used 15 for the regression test; 100 is the production value used in Phase 6 cross-run comparison. Large enough that all methods plateau; small enough to fit the 12-run batch in ~90 min on the burst VM.
- **D-08 [auto]: Stopping criterion.** `f_abstol=0.01` (the existing `log_cost=true` default = 0.01 dB change) for all four variants. For the linear variant we override `f_tol=1e-10` to match the existing default; but both linear and log minimize the same landscape, so we report on both scales. The audit analyzer converts every trace to dB before plotting.
- **D-09 [auto]: FFTW determinism.** Load `results/raman/phase14/fftw_wisdom.txt` at the top of each run. Phase 15 (FFTW.ESTIMATE across `src/simulation/`) is already merged on main, so determinism is structural; wisdom is a belt-and-suspenders layer for sharpness runs that re-use Phase 14's snapshot conventions.
- **D-10 [auto]: Thread count.** `julia -t auto` on the 22-core burst VM. `deepcopy(fiber)` guard per solve thread follows existing pattern in `scripts/benchmark_optimization.jl:635`.

### Configurations (3 regimes spanning the landscape)

- **D-11 [auto]: Config A (simple).** SMF-28, L=0.5 m, P=0.05 W. Weak-nonlinearity regime — optimization landscape expected near-quadratic. Seeds most-conclusive signal on *convergence-rate* differences between costs (no landscape pathologies).
- **D-12 [auto]: Config B (hard).** SMF-28, L=5 m, P=0.2 W. Hard regime — Phase 11 showed landscape-limited suppression horizon L₅₀dB≈3.33 m at this power; beyond that, multi-modal landscape expected. Best signal for **flatness / sharpness** differences (many basins).
- **D-13 [auto]: Config C (high-nonlinearity).** HNLF, L=1 m, P=0.5 W. High γ regime — Phase 11 showed HNLF reach collapses to <3 dB by z=15 m; at L=1 m we are inside the usable window but dominant-nonlinearity regime tests whether cost choice matters most when physics is strongly nonlinear.

### Metrics (extracted per run)

- **D-14 [auto]: Primary metrics per run.**
  1. **Final J (linear and dB).** `MultiModeNoise.lin_to_dB(J_final)`.
  2. **Wall time (s).** `@elapsed` around the `optimize_spectral_phase*` call only (excluding setup).
  3. **Iterations** until L-BFGS termination and **iterations to 90% of final ΔJ_dB** (convergence-rate proxy — reuses Phase 6's cross-run metric).
  4. **Hessian eigenspectrum at optimum.** Reuse `scripts/phase13_primitives.jl` (or its equivalent). We take the top-32 eigenvalues via Lanczos/Arpack on the Hessian-vector product machinery already in the codebase. Report: top eigenvalue λ_max (curvature), λ₁/λ_32 (condition number proxy), full log-spectrum saved as JLD2.
  5. **Robustness under perturbation.** For each σ ∈ {0.01, 0.05, 0.1, 0.2} rad, draw `n_trials=10` `φ_perturbed = φ_opt + σ·randn(Nt)` and report mean and max `J_perturbed - J_opt` in dB (i.e. degradation). Matches Session D's perturbation framework exactly (reuse constants if visible).

- **D-15 [auto]: Secondary / diagnostic metrics.**
  - Raw convergence trace (J_dB vs. iteration), saved for the analyzer's overlay plot.
  - Starting J_dB at φ₀ (sanity check: identical across variants per config).
  - For the sharpness variant only: record `S(φ_final)` and `lambda_sharp·S(φ_final)` so the decomposition of the objective is visible.

### Reporting Artifacts (the decision doc deliverables)

- **D-16 [auto]: Per-config table (`results/cost_audit/<config>/summary.csv`).** Row per cost variant; columns: final_J_linear, final_J_dB, delta_J_dB, iterations, iter_to_90pct, wall_s, lambda_max, cond_proxy, robustness_σ=0.01_mean_dB, robustness_σ=0.01_max_dB, …, robustness_σ=0.2_max_dB.
- **D-17 [auto]: Cross-config summary (`results/cost_audit/summary_all.csv`).** Long-format: (config, cost, metric, value).
- **D-18 [auto]: Figures.**
  - Fig 1: Convergence traces (J_dB vs. iter), one subplot per config, 4 lines per subplot.
  - Fig 2: Robustness curves (mean ΔJ_dB vs. σ), one subplot per config, 4 lines per subplot; log-y.
  - Fig 3: Hessian eigenspectrum (log |λ_i| vs. i), one subplot per config, 4 lines per subplot.
  - Fig 4: Per-metric winner heatmap (rows = cost variants, cols = (config, metric) pairs; cell = rank 1..4). This is the "who wins what" panel.
  - All figures PNG @ 300 DPI per project standard.
- **D-19 [auto]: Decision doc (`.planning/notes/cost-function-default.md`).** Named recommendation + multi-paragraph rationale with explicit citations into the measured data AND a section "Connection to ML loss-landscape literature" naming SAM/ASAM/GSAM and Li et al. 2018 and how their claims map to this physics problem (experimental robustness = tolerance to SLM drift / fiber manufacturing variance).

### Execution Discipline

- **D-20 [auto]: Burst VM mandatory.** All 12 runs + 3 Hessian eigenspectrum computations execute on `fiber-raman-burst`, guarded by `/tmp/burst-heavy-lock`. Single batch run ~90 min. `burst-stop` runs at the end.
- **D-21 [auto]: Commit discipline.** All commits to `sessions/H-cost` branch. Never push to `main`. The user (or an integrator session) performs the merge at a checkpoint.
- **D-22 [auto]: Zero modification of shared files.** Protected: `scripts/common.jl`, `scripts/raman_optimization.jl`, `scripts/sharpness_optimization.jl`, `src/simulation/**`, `Project.toml`. All new code lives in `scripts/cost_audit_*.jl`.

### Claude's Discretion (downstream can decide)

- Exact Hessian-eigenvalue solver choice (Arpack `eigs` vs. KrylovKit). Default to Arpack for consistency with existing `src/simulation/fibers.jl`.
- Analyzer figure styling beyond 300 DPI + project colors (matplotlib rcParams defaults acceptable).
- Whether to snapshot intermediate `(variant, config)` JLD2 files after each run or only at the end (checkpointing). Recommend: snapshot after each to tolerate partial-batch failure on the burst VM.
- Choice of sharpness λ grid point to report: fixed at Phase 14 default (0.1) unless dramatic degeneracy shows up at φ_opt; then log and retry at 0.01.

</decisions>

<specifics>
## Specific Ideas

- **"Experimentally robust = flat minimum."** The translation between ML "generalization" and physics "robust to SLM drift and fiber manufacturing variance" is the conceptual bridge we're taking. Mention explicitly in the decision doc.
- **Li et al. 2018 visualization** — 2D random-direction loss-surface plots around each optimum. Feasible here in principle but compute-expensive; we **skip the 2D slice** in this phase (add to deferred) and use the Hessian eigenspectrum as a quantitative substitute for "is this basin flat?".
- **Condition-number proxy** via top-k eigenvalue ratio, not full conditioning — the Hessian in our problem is near-singular along gauge directions, so the full condition number is not meaningful. Project out the gauge (constant + linear-in-ω) before computing the ratio; Phase 13's `build_gauge_projector` exists and is reusable.

</specifics>

<canonical_refs>
## Canonical References

Downstream agents MUST read these before planning or implementing.

### Existing cost / optimizer implementations
- `scripts/raman_optimization.jl:166` — `optimize_spectral_phase(...; log_cost=Bool)`; D-01/D-02 dispatch through this.
- `scripts/raman_optimization.jl:99-103` — log-scale cost math (`J_dB = 10·log10(J)`, gradient by chain rule).
- `scripts/sharpness_optimization.jl:425` — `optimize_spectral_phase_sharp(prob, φ0; lambda_sharp, n_samples, eps, rng)`; D-03 dispatch.
- `scripts/sharpness_optimization.jl:142` — `build_gauge_projector(omega, u1, u2)` — reuse for Hessian gauge projection in D-14.
- `scripts/sharpness_optimization.jl:370` — `make_sharp_problem(; ...)` — convenience wrapper; use this for D-03 runs.
- `scripts/common.jl:260` — `spectral_band_cost(uωf, band_mask)` — raw cost function for sanity checks and for building D-04 noise-aware variant.
- `scripts/common.jl :: setup_raman_problem` — shared setup for all four variants. Called identically per config; the **only** thing that varies is which optimize function is called.

### Phase 14 handoff
- `.planning/phases/14-.../14-01-SUMMARY.md` — sharpness library public API, regression gate, FFTW wisdom file path.
- `results/raman/phase14/fftw_wisdom.txt` — load at the top of every run per D-09.

### Prior cost-function evidence
- `.planning/phases/08-sweep-point-reporting/` — Phase 8 introduced the log-scale cost fix; 20-28 dB improvement reported. Referenced in `.planning/notes/project_dB_linear_fix.md` (memory) — reuse in the decision doc.
- `.planning/phases/09-physics-of-raman-suppression/` — Phase 9 hypotheses tested against linear J; provides the physical context for why Raman-band energy IS the right thing to optimize.
- `.planning/phases/11-classical-physics-completion/` — Phase 11 established the landscape pathologies at L>3.3m; motivates D-12 as the "hard" config.
- `.planning/phases/13-optimization-landscape-diagnostics.../` — Phase 13 gauge projection + determinism findings. Must be respected by D-14 Hessian projection.

### Session H ownership + cross-session discipline
- `CLAUDE.md` § Parallel Session Operation Protocol — Rules P1 (namespace), P2 (branch-per-session), P5 (burst VM serialization), P6 (host distribution), P7 (integration checkpoints).
- `.planning/sessions/H-cost-status.md` — this session's status log.

### External literature to weave into the decision doc
- Foret et al. 2020 "Sharpness-Aware Minimization" (SAM) — motivation for D-03.
- Kwon et al. 2021 "ASAM: Adaptive Sharpness-Aware Minimization".
- Zhuang et al. 2022 "Surrogate Gap Guided Sharpness-Aware Minimization" (GSAM).
- Li et al. 2018 "Visualizing the Loss Landscape of Neural Nets" — justification for flatness-as-generalization claim and for the eigenspectrum proxy in D-14.
- Hochreiter & Schmidhuber 1997 "Flat Minima" — original statement of the flatness-generalization connection.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `optimize_spectral_phase` (linear and log-scale) — direct call for D-01/D-02.
- `optimize_spectral_phase_sharp` + `make_sharp_problem` — direct call for D-03.
- `cost_and_gradient` (private, but callable through the optimizer closure) — for D-04 we wrap, not replace.
- `build_gauge_projector` — for projecting the Hessian's gauge directions before eigenspectrum.
- `setup_raman_problem` — shared per-config setup, identical for all four variants.
- `results/raman/phase14/fftw_wisdom.txt` + `FFTW.import_wisdom` pattern — for determinism.
- `scripts/benchmark_optimization.jl:635` `deepcopy(fiber)` pattern — for thread-safe parallel runs if needed.

### Established Patterns
- Scripts use `include("common.jl")` with guard `_COMMON_JL_LOADED` — follow for `cost_audit_*.jl`.
- `SO_` constant prefix for Phase 14; use `CA_` for Phase 16 constants.
- JLD2 snapshots with FFTW wisdom alongside — mirror Phase 14.
- `results/<scope>/<phase-num>/…` directory layout — use `results/cost_audit/<config>/…`.
- `.planning/sessions/<session>-status.md` for append-only session logs (Rule P3).

### Integration Points
- **Phase 13 Hessian machinery** — `scripts/phase13_primitives.jl` defines HVP; Phase 16 analyzer imports it for eigenspectrum computation.
- **Phase 15 determinism** — already on main, structural guarantee for D-09 (no action needed beyond using the merged src/ code).
- **Phase 14 regression test** — Session H must not break it. We run `test/test_phase14_regression.jl` once before closing the phase as a smoke test.

</code_context>

<deferred>
## Deferred Ideas

- **Li-et-al.-style 2D loss-surface visualization** around each optimum. Valuable but ~4× the compute cost of the eigenspectrum; deferred to a later phase.
- **Sharpness-λ sweep** (Plan 14-02 scope): fold into a future follow-up ONLY if Phase 16 shows the sharpness variant is competitive enough to warrant tuning.
- **Full quantum-noise-aware cost** — D-04 is a classical-proxy scaffold only. A first-principles variant requires deriving a functional over the squeezed-vacuum modulus in the Raman band; this is the "quantum-noise-reframing" seed's territory.
- **Multimode (M>1) comparison** — Session C's territory. Phase 16 stays at M=1 to avoid stepping on C.
- **Multi-start per cost variant** — would strengthen the robustness conclusions but multiplies compute by n_starts. Single-start-per-config keeps the batch at ~90 min.
- **Burn-in warm start** — e.g., run linear cost to convergence, then hand off to sharpness. Interesting but outside the fair-comparison protocol.

</deferred>

---

*Phase: 16-cost-function-head-to-head-audit*
*Context gathered: 2026-04-17 (auto mode)*
*Owned by Session H*
