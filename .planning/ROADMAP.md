# Roadmap: SMF Gain-Noise

## Milestones

- v1.0 **Visualization Overhaul** — Phases 1-3 (shipped 2026-03-25)
- v2.0 **Verification & Discovery** — Phases 4-7 (active)

## Phases

<details>
<summary>v1.0 Visualization Overhaul (Phases 1-3) — SHIPPED 2026-03-25</summary>

- [x] Phase 1: Stop Actively Misleading (2/2 plans) — completed 2026-03-25
- [x] Phase 2: Axis, Normalization, and Phase Correctness (2/2 plans) — completed 2026-03-25
- [x] Phase 3: Structure, Annotation, and Final Assembly (2/2 plans) — completed 2026-03-25

See: `.planning/milestones/v1.0-ROADMAP.md` for full details.

</details>

### v2.0 Verification & Discovery

- [x] **Phase 4: Correctness Verification** - Prove the forward solver and adjoint are physically correct before trusting any optimization output (completed 2026-03-25)
- [x] **Phase 5: Result Serialization** - Save structured run data to JLD2/JSON so cross-run comparison has something to load (completed 2026-03-25)
- [ ] **Phase 6: Cross-Run Comparison and Pattern Analysis** - Overlay and compare all 5 optimization runs; decompose phase profiles onto physical basis
- [ ] **Phase 7: Parameter Sweeps** - Systematically explore L x P space and multi-start robustness using verified, serialized infrastructure

## Phase Details

### Phase 4: Correctness Verification
**Goal**: The forward solver and adjoint gradient are confirmed physically correct against analytical solutions and theoretical invariants
**Depends on**: Nothing (uses only existing `common.jl` and MultiModeNoise module)
**Requirements**: VERIF-01, VERIF-02, VERIF-03, VERIF-04
**Success Criteria** (what must be TRUE):
  1. A fundamental soliton (N=1 sech pulse) propagates one soliton period and its output shape matches the analytical prediction to within 2% max deviation
  2. Photon number integral |U(w)|^2/w is conserved to <1% across a full production forward propagation, reported explicitly in the verification output
  3. A Taylor remainder gradient test produces a log-log residual vs. eps plot with slope ~2, confirming the adjoint gradient is O(eps^2) correct
  4. The cost J returned by spectral_band_cost matches direct numerical integration of the same Raman-band bins to machine precision, confirming mask correctness
  5. A human-readable verification report in `results/raman/validation/` shows PASS/FAIL for each of the four tests with numeric evidence
**Plans:** 2/2 plans complete
Plans:
- [x] 04-01-PLAN.md — Verification skeleton with VERIF-01 (soliton shape) and VERIF-04 (cost cross-check)
- [x] 04-02-PLAN.md — VERIF-02 (photon number conservation) and VERIF-03 (Taylor remainder at production grid)

### Phase 5: Result Serialization
**Goal**: Every optimization run saves structured metadata and results to disk so subsequent phases can load and compare without re-running simulations
**Depends on**: Phase 4 (verification must pass before serializing results that will be analyzed)
**Requirements**: XRUN-01
**Success Criteria** (what must be TRUE):
  1. After running `raman_optimization.jl`, each of the 5 run directories contains a `_result.jld2` file with fiber params, J_before, J_after, convergence history, and wall time
  2. A top-level `results/raman/manifest.json` exists and lists all 5 runs with their scalar summaries in a format readable by `jq` or any JSON parser
  3. The serialization adds no new positional arguments or breaking changes to `run_optimization()` — the existing call sites still work unchanged
**Plans:** 1/1 plans complete
Plans:
- [x] 05-01-PLAN.md — Add JLD2/JSON3 deps, thread store_trace, save _result.jld2 per run, update manifest.json

### Phase 6: Cross-Run Comparison and Pattern Analysis
**Goal**: All 5 optimization runs can be compared in single overlay figures, and each optimal phase profile is explained in terms of physically interpretable polynomial chirp components
**Depends on**: Phase 5 (needs `_result.jld2` files and manifest to exist)
**Requirements**: XRUN-02, XRUN-03, XRUN-04, PATT-01, PATT-02
**Success Criteria** (what must be TRUE):
  1. A single summary table shows J_before, J_after, delta-dB, iterations, and wall time for all 5 runs in one view, written to `results/images/`
  2. A single overlay convergence figure shows J vs. iteration for all 5 runs on shared axes, with each run clearly labeled by fiber type and config
  3. A single overlay spectral figure shows all optimized output spectra per fiber type on shared dB axes, enabling direct comparison of Raman suppression depth
  4. Each optimal phase profile is projected onto GDD and TOD polynomial basis, and the residual fraction (unexplained by polynomial terms) is reported in the summary
  5. The soliton number N = sqrt(gamma*P0*T0^2/|beta2|) is recorded in the metadata for each run and appears in the summary table
**Plans:** 1/2 plans executed
Plans:
- [x] 06-01-PLAN.md — Add cross-run visualization functions to visualization.jl (soliton number, phase decomposition, summary table, convergence overlay, spectral overlay)
- [ ] 06-02-PLAN.md — Create run_comparison.jl entry point, re-run all 5 configs, produce 4 comparison figures + phase analysis
**UI hint**: yes

### Phase 06.1: Physics Insight — Visualize optimizer strategy (INSERTED)

**Goal:** Discover what the optimizer is actually doing to suppress Raman scattering by visualizing phi_opt profiles, correlations, and residual structure across 5 existing optimization runs. Produce 8 exploratory figures revealing phase structure, group delay reshaping, and the 99% polynomial-unexplained residual.
**Requirements**: None (inserted exploratory phase — no mapped requirements)
**Depends on:** Phase 6
**Plans:** 2/2 plans complete

Plans:
- [x] 06.1-01-PLAN.md — Data loading, phase normalization, Figures 1-4 (phi_opt overlays freq/lambda, detail panels, correlation scatter)
- [ ] 06.1-02-PLAN.md — Figures 5-8 (before/after Raman, group delay, residual overlay, Raman zoom) + visual checkpoint

### Phase 7: Parameter Sweeps
**Goal**: The optimization cost J_final is mapped over a coarse L x P grid per fiber type, and multi-start robustness is quantified, enabling identification of favorable operating regimes
**Depends on**: Phase 6 (sweeps call run_comparison_suite at completion; needs stable comparison infrastructure)
**Requirements**: SWEEP-01, SWEEP-02
**CRITICAL PREREQUISITE (from Phase 4 VERIF-02):** `recommended_time_window()` in `common.jl` is power-blind — only accounts for linear dispersive walk-off. Phase 4 verification showed 2.7% photon number drift at low power but 38-49% at high power/long fiber, meaning the super-Gaussian attenuator absorbs significant pulse energy when the time window is undersized. Before running sweeps, this function MUST be extended with a power-aware correction (e.g., SPM broadening estimate) OR each sweep point must use a generous fixed window (safety_factor=4-5x) with Nt scaled to maintain resolution. Without this, high-P sweep points produce artificially low J values because attenuator eats energy before it reaches the Raman band. Evidence: `results/raman/validation/verification_20260325_173537.md`.
**Success Criteria** (what must be TRUE):
  1. A J_final heatmap for at least one fiber type (SMF-28) is produced over a coarse L x P grid, with axes labeled in physical units and Raman suppression depth shown in dB
  2. Each sweep point is tagged with `converged::Bool`, `iterations::Int`, and `gradient_norm::Float64`; non-converged points are visually marked distinct from converged points in the heatmap
  3. A multi-start analysis runs optimization from 5-10 random initial phases for one canonical config and reports the distribution of J_final values, revealing whether the cost landscape has multiple local minima
  4. Sweep results are saved to `results/raman/sweeps/` with one `_result.jld2` per sweep point and a `sweep_results.jld2` aggregate, enabling re-plotting without re-running
  5. Every sweep point has photon number drift <5%, confirming the time window is adequately sized (no attenuator absorption corrupting results)
**Plans:** 2/3 plans executed
Plans:
- [x] 07-01-PLAN.md — Fix recommended_time_window() with SPM broadening, add do_plots kwarg, update tests
- [x] 07-02-PLAN.md — Create run_sweep.jl script and add heatmap/histogram visualization functions
- [ ] 07-03-PLAN.md — Execute full 36-point sweep + 10-start multi-start, visual verification checkpoint
**UI hint**: yes

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 4. Correctness Verification | 2/2 | Complete   | 2026-03-25 |
| 5. Result Serialization | 1/1 | Complete   | 2026-03-25 |
| 6. Cross-Run Comparison and Pattern Analysis | 1/2 | In Progress|  |
| 6.1 Physics Insight | 1/2 | Partial | - |
| 7. Parameter Sweeps | 2/3 | Code Complete | - |
| 7.1 Grid Resolution Fix | 1/1 | Complete | 2026-03-31 |
| 8. Sweep Point Reporting | 1/1 | Complete | 2026-03-31 |
| 9. Physics of Raman Suppression | 2/2 | Complete | 2026-04-02 |
| 10. Propagation-Resolved Physics | 2/2 | Complete    | 2026-04-03 |
| 11. Classical Physics Completion | 2/2 | Complete    | 2026-04-03 |
| 12. Suppression Reach & Long-Fiber Behavior | 1/2 | Complete    | 2026-04-05 |

### Phase 12: Suppression Reach & Long-Fiber Behavior
**Goal**: Characterize the finite reach of spectral phase Raman suppression by propagating short-fiber-optimized phases through much longer fibers (10m, 30m+) and mapping how the suppression horizon scales with fiber parameters. Determine whether the optimizer's phase still provides benefit over flat phase at distances far beyond the optimization length, and explore whether segmented or iterative optimization could extend the reach.
**Depends on**: Phase 11 (needs multi-start z-data, suppression horizon baseline)
**Requirements**: Derived from Phase 11 findings and user correction of overclaimed suppression reach
**Success Criteria** (what must be TRUE):
  1. Short-fiber phi_opt (optimized at L=0.5m, 2m) propagated through L=10m and L=30m fibers with z-resolved diagnostics, showing J(z) evolution far beyond the optimization horizon
  2. Comparison of shaped vs flat phase at long distances quantified — does phi_opt still help at 10x, 60x the optimization length?
  3. Suppression horizon L_XdB mapped as a function of at least 2 parameters (power P and soliton number N_sol) for both fiber types
  4. At least one approach to extending suppression reach tested (e.g., segmented optimization where phi_opt is re-optimized at intermediate z-points, or higher Nt for finer spectral control)
  5. Corrected physical narrative: all findings documents accurately describe the finite reach without overclaiming
**Plans:** 1/2 plans complete
Plans:
- [x] 12-01-PLAN.md — Long-fiber propagation: take existing phi_opt from 0.5m and 2m optimizations, propagate through 10m and 30m fibers with 100 z-saves, compare shaped vs flat phase, map J(z) evolution beyond optimization horizon
- [ ] 12-02-PLAN.md — Suppression horizon mapping and reach extension: sweep L_XdB vs (P, N_sol), test segmented optimization concept, produce corrected narrative

### Phase 9: Physics of Raman Suppression
**Goal**: Understand WHY the optimizer's spectral phase patterns suppress Raman scattering — determine whether optimal phases have universal physical structure (predictable from fiber parameters) or are arbitrary inverse-design solutions with no interpretable pattern. Produce a physics-grounded explanation suitable for a paper section.
**Depends on**: Phase 7 (needs sweep JLD2 results), Phase 6.1 (builds on partial physics insight work)
**Requirements**: Derived from research direction — no mapped requirements
**Success Criteria** (what must be TRUE):
  1. Optimal phi_opt profiles across all 24 sweep points are projected onto a physical basis (polynomial chirp: GDD, TOD, FOD; sinusoidal modulation) and the explained variance fraction is reported for each
  2. Structural similarity of optimal phases is quantified across fiber parameters (L, P, N_sol, fiber type) — revealing whether phases cluster, scale predictably, or are uncorrelated
  3. Group delay profiles (d(phi)/d(omega)) before and after optimization are visualized, showing how the optimizer reshapes temporal pulse structure
  4. Literature-grounded physical mechanisms are identified and tested against the data (e.g., temporal walk-off compensation, Raman gain bandwidth avoidance, soliton fission delay)
  5. A clear answer to "universal vs arbitrary": either an analytical prediction of optimal phase from fiber parameters, or evidence that the landscape has many equivalent minima with no shared structure
**Plans:** 2/2 plans
Plans:
- [ ] 09-01-PLAN.md — Phase decomposition (polynomial orders 2-6), residual PSD analysis, cross-sweep phi_opt overlay, explained variance analysis
- [ ] 09-02-PLAN.md — Temporal intensity profiles, Raman overlap integral, group delay visualization, mechanism attribution verdict

### Phase 10: Propagation-Resolved Physics & Phase Ablation
**Goal**: Understand the 84% of Raman suppression that Phase 9 attributed to "configuration-specific nonlinear interference" by running NEW simulations with z-resolved diagnostics and spectral phase ablation experiments. Track where Raman energy builds up along the fiber, determine which frequency components of phi_opt matter most, and test robustness of optimal phases to parameter perturbations.
**Depends on**: Phase 9 (needs Phase 9 findings and sweep data)
**Requirements**: Derived from Phase 9 deferred hypothesis H5 and open questions
**Success Criteria** (what must be TRUE):
  1. Z-resolved Raman energy evolution is computed for at least 6 representative configurations (3 SMF-28 + 3 HNLF) with and without optimal phase, showing WHERE Raman energy builds up or is suppressed along the fiber
  2. Spectral phase ablation experiments reveal which frequency bands of phi_opt contribute most to suppression — zeroing out different bands and measuring suppression loss
  3. Perturbation robustness is quantified: how much can phi_opt be scaled, shifted, or truncated before suppression degrades by 3 dB?
  4. At least one NEW hypothesis about the suppression mechanism emerges from z-resolved data that was not accessible from Phase 9's input/output-only analysis
  5. All new simulations save z-resolved data to JLD2 for future analysis
**Plans:** 2/2 plans complete
Plans:
- [x] 10-01-PLAN.md — Z-resolved propagation diagnostics: re-propagate 6 configs with zsave, compute Raman band energy J(z) along fiber, spectral/temporal evolution heatmaps, N_sol regime comparison
- [x] 10-02-PLAN.md — Phase ablation & perturbation studies: 10-band frequency zeroing with super-Gaussian windows, cumulative ablation, global scaling robustness, spectral shift sensitivity

### Phase 11: Classical Physics Completion — Deep Mechanism Analysis & Multi-Start Z-Dynamics
**Goal**: Complete the classical Raman suppression physics story by testing Phase 10's new hypotheses (H1-H4), analyzing z-resolved dynamics of the 10 multi-start solutions (do structurally different phi_opt profiles create similar J(z) curves?), identifying the critical z-position where shaped/unshaped spectral evolution diverges, and exploring whether the long-fiber suppression breakdown (SMF-28 5m) can be overcome with higher Nt or modified optimization. Produce paper-ready analysis closing all open classical physics questions.
**Depends on**: Phase 10 (needs z-resolved JLD2 data and ablation findings)
**Requirements**: Derived from Phase 10 hypotheses H1-H4 and open questions
**Success Criteria** (what must be TRUE):
  1. Multi-start z-dynamics: all 10 multi-start phi_opt profiles re-propagated with z-saves, revealing whether structurally different solutions (correlation 0.109) produce similar or divergent J(z) evolution
  2. Spectral divergence point: for each of the 6 Phase 10 configs, the z-position where shaped and unshaped spectral evolution first qualitatively differ is identified and reported
  3. Phase 10 H1-H4 tested with quantitative evidence: each hypothesis receives a verdict (confirmed/rejected/inconclusive) with supporting data
  4. Long-fiber degradation mechanism identified: the SMF-28 5m breakdown at z=0.20m is explained (fiber length vs optimization horizon, accumulated phase error, or Nt-limited spectral resolution)
  5. Paper-ready findings document synthesizing Phases 9+10+11 into a coherent narrative with all open questions resolved or explicitly deferred to multimode
**Plans:** 2/2 plans complete
Plans:
- [x] 11-01-PLAN.md — Multi-start z-dynamics (10 re-propagations with zsave), spectral divergence analysis, J(z) trajectory clustering, z-resolved comparison of structurally different solutions
- [x] 11-02-PLAN.md — H1-H4 hypothesis testing, long-fiber degradation investigation, synthesis findings document merging Phases 9+10+11

### Phase 07.1: Grid Resolution Fix (INSERTED)

**Goal:** Fix Nt floor (2^13 minimum), reduce max_iter to 30, drop L=10m from SMF-28 grid, clean stale sweep results. Corrected grid: 32 points (4x4 SMF-28 + 4x4 HNLF) + 10-start multi-start.
**Requirements**: Derived from Phase 7 SWEEP-01, SWEEP-02
**Depends on:** Phase 7
**Plans:** 1/1 plans complete (code changes done; sweep re-run is a manual step)

Plans:
- [x] 07.1-01-PLAN.md — Fix run_sweep.jl (Nt floor, max_iter, drop L=10m), clean stale results

### Phase 8: Sweep Point Reporting

**Goal:** Generate human-readable per-point outputs (report card figure + markdown summary) for every sweep configuration, plus sweep-level ranked summary tables. Post-hoc script reads JLD2 files — no re-running optimization.
**Depends on:** Phase 7 (needs sweep JLD2 files to exist)
**Requirements**: Derived from SWEEP-01 (results must be interpretable)
**Success Criteria** (what must be TRUE):
  1. Each per-point directory has a single 4-panel report card PNG (spectral, phase 3-view, convergence, metrics)
  2. Each per-point directory has a `report.md` with YAML frontmatter + human-readable metrics
  3. A `SWEEP_REPORT.md` in `results/raman/sweeps/` ranks all points by suppression quality with key metrics
  4. `scripts/generate_sweep_reports.jl` regenerates all outputs from JLD2 without re-running optimization
**Plans:** 1/1
Plans:
- [ ] 08-01-PLAN.md — Create generate_sweep_reports.jl with report card figure + markdown summaries

### Phase 13: Optimization Landscape Diagnostics — gauge-fixing, polynomial projection, and Hessian eigenspectrum at L-BFGS optima (prerequisite for any Newton's method decision)

**Goal:** Determine whether the apparent "different random starts give different phases" landscape instability is real non-gauge, non-polynomial multiplicity — or gauge symmetry + high-frequency noise around a shared low-order polynomial shape. Produce the evidence the professor's Newton vs L-BFGS decision should hinge on, and reveal which directions in φ-space physically control Raman suppression.
**Depends on:** Phase 12 (uses converged multi-start optima and serialized results)
**Requirements**: Derived from `.planning/research/questions.md` Q1 and Q3, from the professor's "stable solutions" request, and from the deferred polynomial-projection plan in `.planning/research/FEATURES.md` line 53
**Success Criteria** (what must be TRUE):
  1. **Determinism baseline established** — running the same config with an identical seed twice produces byte-for-byte identical optimized φ (or the source of any divergence is identified and documented)
  2. **Gauge fix applied and reported** — every existing multi-start optimal φ has had `mean(φ)` and a linear polynomial (group-delay) fit subtracted over the input spectral band per `PITFALLS.md` Pitfall 4; post-fix phase-similarity metrics across random starts are quantified (e.g., pairwise RMS difference, cosine similarity)
  3. **GDD/TOD/FOD polynomial decomposition** of each gauge-fixed φ is computed, with explained-variance fractions tabulated for polynomial orders 2, 3, 4, 5, 6 across random starts AND across (Nt, L, P) parameter sweeps
  4. **Hessian eigenspectrum at a converged L-BFGS optimum** is computed via finite-difference HVPs on the existing adjoint gradient, with top-K and bottom-K eigenvalues via Lanczos (no full Nt×Nt construction); the count of near-zero modes beyond the two expected gauge modes is reported, and the top-K eigenvectors are visualized as phase curves over ω
  5. **Findings document** explicitly answers "is the landscape degeneracy real non-gauge, non-polynomial multiplicity?" with a verdict (yes / no / inconclusive), and routes the downstream decision to one of: (a) reduced-basis optimization, (b) sharpness-aware cost (Hessian-in-cost), (c) Newton's method implementation from `.planning/seeds/newton-method-implementation.md`, or (d) no optimizer change needed
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 13 to break down)

### Phase 14: Sharpness-Aware (Hessian-in-Cost) Optimization — new optimizer path parallel to existing L-BFGS, keeping original cost function untouched

**Goal:** Implement a sharpness-aware cost function `J_sharp(φ) = J(φ) + λ · sharpness(H(φ))` and a corresponding optimization entry point that lives ALONGSIDE the existing `optimize_spectral_phase` — the original J path and L-BFGS optimizer remain fully usable and untouched. Use this new path to test whether sharpness-penalized optima are more experimentally robust (to shaper quantization and fiber-parameter drift) than vanilla-J optima. Informed by Phase 13's Hessian eigenspectrum findings so the sharpness measure excludes the expected gauge zero modes.
**Depends on:** Phase 13 (needs the Hessian eigendecomposition machinery built in Phase 13 and the landscape diagnosis to decide which sharpness measure to use)
**Requirements**: Derived from `.planning/research/questions.md` Q2 (sharpness-aware cost) and from the user's direction that the Hessian-in-cost path must be a NEW entry point keeping the original cost function intact
**Success Criteria** (what must be TRUE):
  1. **Original cost untouched** — `spectral_band_cost`, `optimize_spectral_phase`, all existing L-BFGS entry points pass their existing tests byte-for-byte unchanged; no regressions in any prior-phase verification or sweep reproduction
  2. **New sharpness-aware cost function** (`spectral_band_cost_sharp` or similar) computes `J + λ · sharpness(H)` where sharpness is one of {stochastic `tr(H)` via Hutchinson, top-eigenvalue of `H`, projected `tr(H)` excluding gauge modes}; the choice is documented and justified with Phase 13 evidence
  3. **Gradient of sharpness term** is derived and validated by a Taylor-remainder test to O(ε²) — same gradient-verification bar as Phase 4 VERIF-03 holds for the new cost
  4. **New optimization entry point** (`optimize_spectral_phase_sharp` or similar) runs end-to-end on at least one canonical SMF-28 and HNLF config; both L-BFGS and Newton variants are supported via a strategy flag
  5. **A/B comparison produced**: for 3+ configs, side-by-side results of vanilla-J optimum vs sharpness-aware optimum, including (a) final J in dB, (b) Hessian eigenspectrum at each optimum, (c) robustness test — Gaussian perturbation of φ by σ ∈ {0.01, 0.05, 0.1, 0.2} rad and re-measurement of J for both optima
  6. **Tests at every layer** — unit tests for the sharpness function, gradient-validation test, integration test for the new optimizer, regression test ensuring the original path is unchanged; all pass before the phase closes
  7. **Documentation** — a clear entry in `scripts/common.jl` and a usage example in the run scripts explaining when to use each optimizer path
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 14 to break down)

### Phase 15: Deterministic Numerical Environment — pin FFTW planner to ESTIMATE, lock thread counts, add reproducibility regression test (fixes max|Δφ|=1.04 rad determinism bug found in Phase 13)

**Goal:** Make the forward solve, adjoint solve, and full L-BFGS optimization path **bit-for-bit reproducible** given the same config and random seed. Phase 13 Plan 01's determinism check found max|Δφ| = 1.04 rad between two identical-seed runs (root cause: FFTW.MEASURE plan selection is timing-dependent). Fix by pinning FFTW planner flags to ESTIMATE, setting FFTW and BLAS thread counts to 1 for optimization runs, and centralizing the setup in a single include so every script gets the same deterministic environment. Add a regression test that runs the same config twice and asserts byte-identical phi_opt.
**Depends on:** Phase 13 (the bug was found in 13-01 and the snapshot/regression pattern from 14-01 is reused). Should run BEFORE Phase 14 Plan 02 so the A/B comparison there is reproducible.
**Requirements**: Derived from Phase 13 Plan 01 finding ("Determinism FAIL — max|Δφ| = 1.04 rad") and from the user's explicit direction "I still definitely want to fix this determinism thing"
**Success Criteria** (what must be TRUE):
  1. A new helper module `scripts/determinism.jl` exports `ensure_deterministic_environment()` that sets `FFTW.set_planner_flags(FFTW.ESTIMATE)`, `FFTW.set_num_threads(1)`, `BLAS.set_num_threads(1)` and is idempotent + safe to call from any script
  2. Existing script entry points (`scripts/raman_optimization.jl`, `scripts/amplitude_optimization.jl`, `scripts/run_sweep.jl`, `scripts/run_comparison.jl`) call `ensure_deterministic_environment()` at top level OR the function is auto-applied via a sourced-at-startup shim — pick whichever is minimally invasive. The existing optimizer LOGIC stays byte-identical; only the environment setup changes.
  3. A regression test `test/test_determinism.jl` runs the same config with `Random.seed!(42)` twice and asserts `phi_opt_a == phi_opt_b` bit-for-bit (`maximum(abs(phi_opt_a - phi_opt_b)) == 0.0`)
  4. The determinism regression test passes locally and on the burst VM — confirming the fix works in both single-threaded (this host) and multi-threaded contexts (burst should still be deterministic for optimization runs, though FFTW and BLAS stay single-threaded; Julia's outer `Threads.@threads` loops for multi-start etc. are orthogonal and don't affect per-optimization determinism)
  5. Benchmarked performance impact quantified — record wall-clock time of the SMF-28 canonical optimization before and after, report slowdown in SUMMARY (expected 5-20% from FFTW.ESTIMATE vs MEASURE)
  6. STATE.md "Resolved Issues" section gains a "[RESOLVED 2026-04-xx] FFTW.MEASURE plan-selection non-determinism" entry; "Critical Context for Future Agents" gains a note about the deterministic environment convention
  7. Phase 14 Plan 02's A/B comparison uses the deterministic path (update Plan 14-02 if it pre-dates this phase)
**Plans:** 1 plan

Plans:
- [x] 15-01: Pin FFTW planner to ESTIMATE, thread pins, src/simulation patch, regression test, benchmark — COMPLETE 2026-04-16 (7/7 bit-identity tests pass; +21.4% slowdown on SMF-28 canonical)

### Phase 16: Repo Polish for Team Handoff (Session B)

**Goal:** New team member productive in 15 min from clone: README rewrite, docs/ suite (9 files), output-format spec, Makefile, tiered regression tests (fast/slow/full).
**Requirements**: See `docs/README.md` and `.planning/sessions/B-standdown.md`.
**Depends on:** Phase 15
**Plans:** 7 plans (all complete; 9/9 goal-backward criteria passed)

Plans:
- [x] 16-01..16-07: executed on sessions/B-handoff; 16 commits; merged 2026-04-19. See `.planning/sessions/B-standdown.md`.

> **Numbering note (2026-04-19 integration pass):** "Phase 16" was independently claimed by Sessions B (repo polish), C (MMF Raman), and one of A/E/F/G/H (per-session sub-phase dirs). This is an artifact of parallel operation; each session's phase dir is self-contained under `.planning/phases/16-<topic>/`. Future phases after Phase 17 should resume at Phase 18+.

### Phase 17: Simple Phase Profile Stability Study (Session D) — investigate whether the striking SMF-28 L=0.5m P=0.050W J=-77.6dB result (remarkably simple ~3-feature unwrapped phase, TV<2 rad) sits in a flat basin with large convergence radius (experimentally robust) or a coincidental sharp minimum. Baseline reproduction on burst VM, perturbation study, transferability sweep, simplicity quantification vs Phases 10/11/12 optima, synthesis figure. Feeds Session E.

**Goal:** Decide FLAT_ROBUST vs SHARP_LUCKY vs INCONCLUSIVE verdict on the L=0.5m P=0.05W optimum, with quantitative evidence on perturbation tolerance (σ_3dB), warm-start transferability, and simplicity-vs-suppression correlation.
**Requirements**: See `.planning/phases/17-simple-phase-profile-stability-study-.../17-CONTEXT.md` and `.planning/sessions/D-simple-decisions.md`.
**Depends on:** Phase 15 (determinism), Phase 13 primitives (gauge-fix, input_band_mask).
**Plans:** 1 plan (complete 2026-04-17; verdict SHARP_LUCKY).

Plans:
- [x] 17-01: Baseline reproduction + perturbation + transferability + simplicity + synthesis — COMPLETE 2026-04-17 (see 17-01-PLAN.md and `results/raman/phase17/SUMMARY.md`)

### Phase 16 (Session H): Cost Function Head-to-Head Audit — compare linear, log-scale dB, sharpness-aware, and noise-aware cost variants across 3 (fiber, L, P) configs and recommend a default

**Goal:** Recommend a project-wide default cost-function via head-to-head A/B/C/D on fixed configs.
**Requirements**: See `.planning/phases/16-cost-audit/` and `.planning/sessions/H-cost-*.md`.
**Depends on:** Phase 15
**Plans:** 7/12 runs complete (merged 2026-04-19).

Plans:
- [x] Config A (SMF-28): **log_dB wins** — -75.8 dB in 10.6s vs linear -70.5 dB in 17s.
- [~] Config B (HNLF): 3/4 complete; sharp variant DNF.
- [ ] Config C (HNLF L=1m P=0.5W): 0/4 — two burst-VM hangs > 1 h. **Blocked** — needs shorter max_iter / reduced metric set. See `.planning/phases/18-cost-config-c/`.

### Phase 18: Numerical trustworthiness audit of optimization results

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 17
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 18 to break down)

### Phase 19: Physics audit 2026-04-19 — verdict-classify every claim in SYNTHESIS-2026-04-19 + Phase 13/15/16/17 sessions, with mandatory diagnosis of Session F 100m anomaly (a2 wrong sign, R²<0.04)

**Goal:** Produce results/PHYSICS_AUDIT_2026-04-19.md with each substantive physics claim classified as defensible / shaky / wrong, sourced to file:line, phase summaries, validation markdowns, or new burst-VM verification runs. Diagnose the Session F 100m three-failure-mode anomaly. Flag any existing docs/*.tex claim that contradicts what survives.
**Requirements**: All forward-solve verification runs go through ~/bin/burst-run-heavy (Rule P5). Burst VM stopped on completion. Heavy literature research on chirped-pulse Raman suppression, gauge transformations in NLSE optimization, GVD scaling of optimal chirp.
**Depends on:** Phase 18
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 19 to break down)

### Phase 20: Canonical docs update — propagate audit verdicts into docs/companion_explainer.tex, docs/physics_verification.tex, docs/verification_document.tex with PDF rebuild

**Goal:** Edit the three canonical .tex files so only defensible claims enter as new assertions, shaky claims enter with explicit caveat, wrong claims do NOT enter. Every new assertion sourced to file:line, phase summary, or validation markdown. Rebuild each .pdf with two pdflatex passes. Commit .tex + .pdf together.
**Requirements**: Audit verdicts from Phase 19 are the input. Voice consistency: companion_explainer = undergrad pedagogical, physics_verification = derivations reference, verification_document = full verification artifact. results/raman/*.md is INPUT-ONLY.
**Depends on:** Phase 19
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 20 to break down)

### Phase 21: Numerical recovery of Phase 18 SUSPECT results — re-run Sweep-1, Session F 100m, Phase 13 Hessian re-anchor, opportunistic MMF aggressive regime, all at honest Nt/time-window (edge fraction < 0.1%)

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 20
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 21 to break down)

### Phase 22: Sharpness-aware cost function research — implement and compare SAM / Hessian-trace-penalty / Monte-Carlo-Gaussian flavors, sweep regularization, measure J_dB + σ_3dB + Hessian eigenspectrum across flavors to produce depth/robustness Pareto

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 21
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 22 to break down)

### Phase 23: Matched quadratic-chirp 100m baseline — decide whether the −51.5 dB warm-start transfer at L=100m is genuine nonlinear structural adaptation or trivially explained by any sufficiently-dispersive pre-chirp (settles audit §S5)

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 22
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 23 to break down)

### Phase 24: Canonical docs polish and PDF rebuild — fold Phase 21/22/23 results into verification_document.tex + companion_explainer.tex with new diagrams, bug fixes, tightened literature anchoring; rebuild PDFs via two-pass pdflatex

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 23
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 24 to break down)

### Phase 25: Project-wide bug squash and concern triage

**Goal:** Re-audit the codebase for real bugs and stale project guidance, fix the low-risk correctness/documentation issues that can be resolved safely in-place, and seed the larger architectural hazards instead of papering over them.
**Requirements**: Derived from `.planning/STATE.md` open concerns and `.planning/codebase/CONCERNS.md`
**Depends on:** Phase 24
**Plans:** 1/1 plans complete

Plans:
- [x] 25-01-PLAN.md — Audit bug reports against live code, patch real correctness/staleness issues, run fast-tier verification, seed unresolved structural hazards

### Phase 26: Verification document bug reconciliation

**Goal:** Reconcile the bug list embedded in `docs/verification_document.tex` against the live codebase and canonical findings, fixing stale or misleading document claims and seeding the remaining structural bugs that still need implementation work.
**Requirements**: Derived from `docs/verification_document.tex` issue/advisory sections
**Depends on:** Phase 25
**Plans:** 1/1 plans complete

Plans:
- [x] 26-01-PLAN.md — Audit verification-document bug claims, patch stale writeup sections, seed unresolved implementation gaps, and verify by code/doc cross-check

### Phase 27: Numerical analysis audit and CS 4220 application roadmap

**Goal:** Produce a numerics-focused audit of the codebase, grounded in Cornell CS 4220 course material, that explains what numerical-analysis ideas apply here, what is currently going wrong, what should be improved next, and which larger opportunities deserve their own future phases.
**Requirements**: Derived research phase — no mapped product requirement IDs
**Depends on:** Phase 24
**Success Criteria** (what must be TRUE):
  1. A written report maps the most relevant CS 4220 topics to concrete opportunities and blockers in this codebase
  2. The report distinguishes near-term numerics fixes from larger future work, with explicit rationale
  3. Current blockers and planning/codebase drift that undermine numerical trust are documented with evidence
  4. Seeds are planted in `.planning/seeds/` for ideas large enough to deserve their own phase
  5. No shared source files under `src/` are refactored as part of this phase
**Plans:** 1/1 plans complete

Plans:
- [x] 27-01-PLAN.md — Research CS 4220 numerics material, audit current solver/optimizer numerics, write report, and plant future-phase seeds

### Phase 28: Conditioning and backward-error framework for Raman optimization

**Goal:** Convert the numerics-governance seed into a concrete trust-contract phase with standardized error taxonomy, run-report requirements, conditioning audit targets, and implementation order for numerical acceptance gates.
**Requirements**: Derived from Phase 27 numerics-governance recommendation and second-opinion addendum
**Depends on:** Phase 27
**Plans:** 1/1 plans complete

Plans:
- [x] 28-01-PLAN.md — Define trust-report schema, conditioning audit targets, error conventions, and the future implementation plan for numerical governance

### Phase 29: Performance modeling and roofline audit for the FFT-adjoint pipeline

**Goal:** Turn the performance-modeling seed into an execution-ready benchmark phase with explicit kernels, bottleneck hypotheses, measurement protocol, and decision criteria for when tuning or more hardware is actually worth it.
**Requirements**: Derived from Phase 27 NMDS performance/roofline recommendations
**Depends on:** Phase 27
**Plans:** 1/1 plans complete

Plans:
- [x] 29-01-PLAN.md — Research FFT/adjoint performance kernels, define roofline/Amdahl benchmark protocol, and lock the implementation scope for the future execution pass

### Phase 30: Continuation and homotopy schedules for hard Raman regimes

**Goal:** Promote the continuation seed into a practical methodology phase with explicit homotopy ladders, path-failure detectors, trust checks, and benchmark comparisons against cold-start optimization in hard regimes.
**Requirements**: Derived from Phase 27 continuation recommendation
**Depends on:** Phase 28
**Plans:** 1/1 plans complete

Plans:
- [x] 30-01-PLAN.md — Define continuation variables, schedule rules, failure detectors, and benchmark set for hard-regime path-following

### Phase 31: Reduced-basis and regularized phase parameterization

**Goal:** Turn the reduced-basis seed into an execution-ready model-selection phase that compares full-grid phase optimization against explicit basis restrictions and regularization families, anchored to the repo's existing DCT infrastructure.
**Requirements**: Derived from Phase 27 regularization/model-selection recommendation
**Depends on:** Phase 28
**Plans:** 1/1 plans complete

Plans:
- [x] 31-01-PLAN.md — Define basis families, evaluation metrics, and execution waves for reduced-basis versus full-grid phase optimization

### Phase 32: Extrapolation and acceleration for parameter studies and continuation

**Goal:** Turn the acceleration seed into a concrete study phase that selects the first worthwhile sequence families, the right trust metrics, and a stop rule for when acceleration complexity is not justified.
**Requirements**: Derived from Phase 27 NMDS acceleration recommendation
**Depends on:** Phase 29, Phase 30
**Plans:** 1/1 plans complete

Plans:
- [x] 32-01-PLAN.md — Choose candidate study families, acceleration methods, trust gates, and execution ordering for the acceleration comparison phase

### Phase 33: Globalized second-order optimization for Raman suppression

**Goal:** Promote the globalization seed into a real optimizer phase with safeguarded step-acceptance policy, benchmark set, honest failure accounting, and a clear boundary between direction computation and globalization mechanics.
**Requirements**: Derived from Phase 27 globalization recommendation
**Depends on:** Phase 28, Phase 30, Phase 31
**Plans:** 1/1 plans complete

Plans:
- [x] 33-01-PLAN.md — Select globalization strategy family, benchmark configs, trust metrics, and execution waves for safeguarded second-order optimization

### Phase 34: Truncated-Newton Krylov preconditioning path

**Goal:** Convert the matrix-free second-order seed into an execution-ready solver phase with Krylov inner-solve design, preconditioning candidates, HVP reuse contract, and comparison criteria against L-BFGS and safeguarded second-order baselines.
**Requirements**: Derived from Phase 27 Krylov/Lanczos extension recommendation
**Depends on:** Phase 28, Phase 33
**Plans:** 1/1 plans complete

Plans:
- [x] 34-01-PLAN.md — Define truncated-Newton architecture, Krylov/preconditioning experiments, and benchmark/verification contract

### Phase 35: Saddle escape and genuine minima reachability study — determine whether reachable Raman optima include true minima or only Hessian-indefinite saddles, and identify optimizer paths that can reliably reach minima-quality solutions if they exist

**Goal:** Determine whether genuine minima exist in reachable Raman territory. Verdict: the competitive dB branch remains saddle-dominated, while true minima appear only after severe dimensional restriction. Recommend reduced-basis continuation plus a globalized second-order method with explicit negative-curvature handling.
**Requirements**: Derived research phase — no mapped product requirement IDs
**Depends on:** Phase 27
**Success Criteria** (what must be TRUE):
  1. The canonical reduced-basis `N_phi` ladder is classified by Hessian sign structure, not just by final `J_dB`
  2. At least one competitive saddle is perturbed along negative curvature and re-optimized with mandatory standard-image output
  3. The final report states plainly whether genuine minima exist only after severe depth loss, are reachable in competitive territory, or remain unsupported by the evidence
  4. The report recommends a specific next optimizer path for the repo and explains why
**Plans:** 1/1 plans complete

Plans:
- [x] 35-01-PLAN.md — Run reduced-basis Hessian ladder, perform negative-curvature escape study, and write the reachability report
