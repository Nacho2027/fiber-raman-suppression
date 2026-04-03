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
| 10. Propagation-Resolved Physics | 2/2 | Complete   | 2026-04-03 |

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
**Plans:** 2 plans
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
