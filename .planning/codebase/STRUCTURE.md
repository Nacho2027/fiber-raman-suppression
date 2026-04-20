# Codebase Structure

**Analysis Date:** 2026-04-19

## Directory Layout

```
fiber-raman-suppression/
├── CLAUDE.md                      # Project + parallel-session + compute discipline rules
├── README.md, LICENSE, Makefile
├── Project.toml, Manifest.toml    # Julia package manifest (Julia ≥ 1.9.3, resolved under 1.12.4)
├── LocalPreferences.toml          # Pkg preferences (FFTW/MKL)
├── src/                           # MultiModeNoise.jl core (physics, typed)
│   ├── MultiModeNoise.jl          # Module entry — `include()`s the submodules
│   ├── mmf_cost.jl                # MMF cost variants (sum / fundamental / worst_mode)
│   ├── simulation/
│   │   ├── simulate_disp_mmf.jl       # Forward RHS `disp_mmf!` + preallocator
│   │   ├── sensitivity_disp_mmf.jl    # Adjoint RHS `adjoint_disp_mmf!`
│   │   ├── simulate_disp_gain_mmf.jl  # Forward + YDFA gain (MMF)
│   │   ├── simulate_mmf.jl            # Fiber-mode solver without dispersion (Session C reference)
│   │   └── fibers.jl                  # GRIN eigensolver + overlap tensor γ[i,j,k,l]
│   ├── gain_simulation/
│   │   ├── gain.jl                    # `YDFAParams` struct + rate equations
│   │   ├── Yb_absorption.npz          # Yb³⁺ absorption cross-section
│   │   └── Yb_emission.npz            # Yb³⁺ emission cross-section
│   ├── analysis/
│   │   ├── analysis.jl                # Quantum-noise variance maps (Tullio contractions)
│   │   └── plotting.jl                # Mode cross-section plots
│   ├── helpers/
│   │   └── helpers.jl                 # `get_disp_sim_params`, `get_disp_fiber_params{,_user_defined}`, `get_initial_state`, `meshgrid`, `lin_to_dB`
│   └── _archived/
│       ├── README.md
│       └── analysis_modem.jl          # Historical — do not import
├── scripts/                       # Drivers, optimizers, plotting, launchers
│   ├── common.jl                      # [SHARED] FIBER_PRESETS, setup_raman_problem, spectral_band_cost, recommended_time_window
│   ├── visualization.jl               # [SHARED] plot_optimization_result_v2, plot_spectral_evolution, plot_phase_diagnostic (~2 kLOC)
│   ├── standard_images.jl             # [SHARED] save_standard_set — mandatory 4-PNG post-run contract
│   ├── determinism.jl                 # [SHARED] ensure_deterministic_environment (FFTW ESTIMATE + wisdom + BLAS threads)
│   ├── raman_optimization.jl          # Canonical SMF phase-only driver
│   ├── amplitude_optimization.jl      # Amplitude-only driver
│   ├── sharpness_optimization.jl      # Sharpness-aware (Hessian-trace) optimizer
│   ├── multivar_optimization.jl       # [A] Joint {phase, amplitude, energy} optimizer + MVConfig
│   ├── multivar_demo.jl               # [A] End-to-end single-config demo
│   ├── test_multivar_gradients.jl     # [A] Finite-difference gradient checks
│   ├── test_multivar_unit.jl          # [A] Unit tests
│   ├── mmf_fiber_presets.jl           # [C] MMF_FIBER_PRESETS (:GRIN_50 M=6, :STEP_9 M=4)
│   ├── mmf_setup.jl                   # [C] setup_mmf_raman_problem (NPZ-cached GRIN eigensolve)
│   ├── mmf_raman_optimization.jl      # [C] MMF phase-only optimizer (shared φ across modes)
│   ├── mmf_joint_optimization.jl      # [C] Phase 17 — joint (φ, c_m) optimization
│   ├── mmf_run_phase16_all.jl         # [C] Batch runner for Phase 16 configs
│   ├── mmf_run_phase16_aggressive.jl  # [C] Aggressive-regularization variant
│   ├── mmf_m1_limit_run.jl            # [C] M=1 sanity check (MMF → SMF limit)
│   ├── mmf_smoke_test.jl              # [C] Pipeline smoke test
│   ├── mmf_analyze_phase16.jl         # [C] Post-hoc analysis
│   ├── sweep_simple_param.jl          # [E] Low-dim cosine phase basis + parameterization
│   ├── sweep_simple_run.jl            # [E] Session E sweep driver (N_φ × L × P × fiber)
│   ├── sweep_simple_analyze.jl        # [E] Pareto front extraction
│   ├── sweep_simple_visualize_candidates.jl  # [E] Visualize sweep winners
│   ├── simple_profile_driver.jl       # [D] Simple-profile stability driver (Phase 17)
│   ├── simple_profile_metrics.jl      # [D] Profile metrics
│   ├── simple_profile_stdimages.jl    # [D] Standard-image wrapper
│   ├── simple_profile_synthesis.jl    # [D] Synthesis / A-B plots
│   ├── render_simple_phases.jl        # [D] Render phase families
│   ├── longfiber_setup.jl             # [F] Long-fiber problem setup (no auto-sizing)
│   ├── longfiber_forward_100m.jl      # [F] Forward-only 100 m run
│   ├── longfiber_optimize_100m.jl     # [F] Optimizer on 100 m fiber
│   ├── longfiber_checkpoint.jl        # [F] Resume-from-checkpoint optimizer
│   ├── longfiber_validate_50m.jl      # [F] 50 m validation
│   ├── longfiber_validate_100m.jl     # [F] 100 m validation
│   ├── longfiber_validate_100m_fix.jl # [F] 100 m validation — fix variant
│   ├── longfiber_regenerate_standard_images.jl  # [F] Backfill 4-PNG set
│   ├── longfiber_burst_launcher.sh    # [F] Burst-VM launcher (bash)
│   ├── sharp_ab_slim.jl               # [G] Slim A/B sharpness vs vanilla (3 λ)
│   ├── sharp_ab_figures.jl            # [G] A/B figures
│   ├── sharp_robustness_slim.jl       # [G] Robustness probe
│   ├── cost_audit_driver.jl           # [H] 3 configs × 4 cost variants = 12 runs
│   ├── cost_audit_analyze.jl          # [H] Analysis
│   ├── cost_audit_noise_aware.jl      # [H] Noise-aware cost variant
│   ├── cost_audit_run_batch.sh        # [H] Batch launcher
│   ├── cost_audit_run_BC.sh           # [H] Configs B+C launcher
│   ├── cost_audit_run_B_only.sh       # [H] Config B launcher
│   ├── cost_audit_run_final.sh        # [H] Final launcher
│   ├── cost_audit_spawn_direct.sh     # [H] Ephemeral-VM spawner
│   ├── cost_audit_spawn_direct_BC.sh  # [H] Ephemeral-VM spawner (BC)
│   ├── cost_audit_spawn_direct_final.sh  # [H] Ephemeral-VM spawner (final)
│   ├── phase13_primitives.jl          # Landscape diagnostics (gauge fix, polynomials)
│   ├── phase13_hvp.jl                 # Hessian-vector products
│   ├── phase13_gauge_and_polynomial.jl
│   ├── phase13_hessian_eigspec.jl     # Top-k eigenspectrum
│   ├── phase13_hessian_figures.jl
│   ├── phase14_ab_comparison.jl       # Sharpness A/B (full, Phase 14)
│   ├── phase14_figures.jl
│   ├── phase14_robustness_test.jl
│   ├── phase14_snapshot_vanilla.jl
│   ├── phase15_benchmark.jl           # Deterministic environment benchmark
│   ├── _phase15_benchmark_run.jl      # Internal run file for phase15
│   ├── benchmark_optimization.jl      # Grid / window / multi-start / parallel-gradient suites
│   ├── benchmark_threading.jl         # Threading scaling benchmark
│   ├── run_benchmarks.jl              # Legacy orchestrator
│   ├── run_comparison.jl              # Legacy
│   ├── run_sweep.jl                   # Legacy sweep
│   ├── propagation_reach.jl           # Phase 12 — SMF reach study
│   ├── propagation_z_resolved.jl      # Phase 10 — z-resolved physics
│   ├── physics_completion.jl          # Phase 11
│   ├── physics_insight.jl             # Phase 9
│   ├── phase_ablation.jl              # Phase 10 ablation
│   ├── phase_analysis.jl              # Phase 9 analysis
│   ├── verification.jl                # Physics sanity checks
│   ├── polish_output_format.jl        # Phase 16 repo-polish helper
│   ├── generate_presentation_figures.jl  # 2026-04-17 advisor presentation
│   ├── generate_sweep_reports.jl      # Sweep report writer
│   ├── regenerate_standard_images.jl  # Backfill 4-PNG set over all results/raman/
│   ├── test_optimization.jl           # Script-layer tests (978 LOC TDD log)
│   ├── test_visualization_smoke.jl    # Viz smoke test
│   └── burst/                         # Burst-VM tooling (bash)
│       ├── README.md
│       ├── install.sh                 # Provision `~/bin/burst-*` helpers
│       ├── run-heavy.sh               # [MANDATORY] Heavy-lock wrapper (Rule P5)
│       ├── spawn-temp.sh              # Ephemeral-VM launcher
│       ├── list-ephemerals.sh         # Enumerate running ephemerals
│       └── watchdog.sh                # systemd user service for load/mem watchdog
├── test/                          # Julia Pkg test suite
│   ├── runtests.jl                    # Entry point — imports MultiModeNoise smoke test
│   ├── tier_fast.jl                   # Fast tier (unit + smoke)
│   ├── tier_slow.jl                   # Slow tier (integration)
│   ├── tier_full.jl                   # Full tier (regression)
│   ├── test_determinism.jl            # FFTW planner + wisdom reproducibility
│   ├── test_phase13_primitives.jl     # Gauge-fix + polynomial param
│   ├── test_phase13_hvp.jl            # HVP correctness
│   ├── test_phase14_sharpness.jl      # Sharpness estimator
│   ├── test_phase14_regression.jl     # Phase 14 regression
│   ├── test_phase16_mmf.jl            # [C] MMF Raman pipeline integration
│   ├── test_cost_audit_unit.jl        # [H] Unit
│   ├── test_cost_audit_integration_A.jl  # [H] Config A integration
│   └── test_cost_audit_analyzer.jl    # [H] Analyzer
├── notebooks/                     # Jupyter (IJulia) exploration
│   ├── EDFA.ipynb
│   ├── YDFA.ipynb
│   ├── YDFA_modular.ipynb
│   ├── YDFA_modular_old.ipynb
│   ├── MultiModeNoise_DispMMF_test.ipynb
│   ├── mmf-spmode-squeezing_FvsP.ipynb
│   ├── mmf-spmode-squeezing_dbk.ipynb
│   ├── mmf_spmode_squeezing_f_vs_p_vs_spm.ipynb
│   ├── smf_gain_YDFA.ipynb
│   ├── smf_gain_linear.ipynb
│   └── smf_supercontinuum.ipynb
├── data/                          # Experimental reference data
│   ├── 251120_data_f_vs_p.csv
│   ├── F_vs_P.csv
│   ├── Yb_absorption.npz          # (mirror of src/gain_simulation data)
│   ├── Yb_emission.npz
│   └── plotFvsP.jl                # Experimental-data plotter (uses DataFrames.jl)
├── fibers/                        # NPZ cache for GRIN eigensolves (keyed on r, M, λ0, Nt, time_window, nx, Nbeta)
│   └── DispersiveFiber_GRIN_*.npz (many)
├── docs/                          # User-facing documentation
│   ├── README.md
│   ├── installation.md
│   ├── quickstart-optimization.md
│   ├── quickstart-sweep.md
│   ├── interpreting-plots.md
│   ├── output-format.md
│   ├── cost-function-physics.md
│   ├── adding-a-fiber-preset.md
│   ├── adding-an-optimization-variable.md
│   ├── companion_explainer.{tex,pdf}
│   ├── physics_verification.{tex,pdf}
│   └── verification_document.{tex,pdf}
├── reports/                       # Generated analysis reports (untracked in earlier snapshots)
├── presentation-2026-04-17/       # Advisor meeting deck + pedagogical figures
│   └── pedagogical/
├── results/                       # All simulation outputs (PNGs, JLD2, manifests, logs)
│   ├── RESULTS_SUMMARY.md
│   ├── SYNTHESIS-2026-04-19.md    # Latest cross-session synthesis
│   ├── burst-logs/                # stdout/stderr from `burst-run-heavy`
│   ├── images/                    # Ad-hoc images
│   ├── cost_audit/                # [H] A/, B/, wall_log.csv
│   ├── raman/
│   │   ├── manifest.json          # Append-only canonical SMF run index
│   │   ├── {MATHEMATICAL_FORMULATION,PHASE9,PHASE10_ABLATION,PHASE10_ZRESOLVED,PRACTICAL_ASSESSMENT,CLASSICAL_RAMAN_SUPPRESSION,PRELUDE_companion_explainer}.md
│   │   ├── smf28/, hnlf/          # Per-fiber canonical runs
│   │   ├── validation/, research/
│   │   ├── phase13/, phase14/     # fftw_wisdom.txt, vanilla_snapshot.jld2
│   │   ├── phase15/               # Deterministic benchmarks
│   │   ├── phase16/               # [C/F] 100m_validate_fixed.jld2, FINDINGS.md, logs/, logs_run2/
│   │   ├── phase17/               # [C/D] SUMMARY.md
│   │   ├── multivar/              # [A] e.g. smf28_L2m_P030W/ with mv_{joint,warmstart,phaseonly}_{result.jld2,slm.json} + 4-PNG sets
│   │   ├── phase_sweep_simple/    # [E] sweep1_Nphi.jld2, sweep2_LP_fiber.jld2, pareto.png, candidates.md, standard_images/
│   │   ├── sharp_ab_slim/         # [G] ab_results.jld2 (referenced by scripts/sharp_ab_slim.jl)
│   │   └── raman_run_*.log        # Historical run logs
│   └── ...
├── .planning/                     # GSD workflow artifacts (mixed git + rsync)
│   ├── PROJECT.md, STATE.md, ROADMAP.md, REQUIREMENTS.md, MILESTONES.md
│   ├── config.json
│   ├── codebase/                  # THIS DIRECTORY — codebase analysis docs
│   │   ├── ARCHITECTURE.md, STRUCTURE.md
│   │   ├── STACK.md, INTEGRATIONS.md
│   │   ├── CONVENTIONS.md, TESTING.md
│   │   └── CONCERNS.md
│   ├── phases/                    # One dir per planned/executed phase
│   │   ├── 01-stop-actively-misleading/ ... 12-suppression-reach/
│   │   ├── 13-optimization-landscape-diagnostics-*
│   │   ├── 14-sharpness-aware-hessian-*
│   │   ├── 15-deterministic-numerical-environment-*
│   │   ├── 16-cost-function-head-to-head-audit-*    # Session H
│   │   ├── 16-longfiber-100m/                       # Session F
│   │   ├── 16-multimode-raman-suppression-baseline/ # Session C
│   │   ├── 16-multivar-optimizer/                   # Session A
│   │   ├── 16-repo-polish-for-team-handoff/         # Session B
│   │   ├── 16-sweep-simple-profiles/                # Session E
│   │   ├── 17-mmf-joint-phase-mode-optimization/    # Session C Phase 17
│   │   ├── 18-cost-config-c/                        # Session H Phase 18
│   │   ├── 18-mmf-baseline-execute/                 # Session C Phase 18
│   │   ├── 18-multivar-convergence-fix/             # Session A Phase 18
│   │   └── 18-sharp-ab-execution/                   # Session G Phase 18
│   ├── sessions/                  # Per-session state (append-only per Rule P3)
│   │   ├── {A,C,E,F,G}-*-{decisions,status,standdown}.md
│   ├── seeds/                     # Seed documents for future phases
│   │   ├── mmf-fiber-type-comparison.md
│   │   ├── mmf-joint-phase-mode-optimization.md
│   │   ├── mmf-phi-opt-length-generalization.md
│   │   └── newton-method-implementation.md
│   ├── notes/                     # Cross-session notes
│   │   ├── compute-infrastructure-decision.md
│   │   ├── cost-function-default.md
│   │   ├── integration-snapshot-2026-04-19.md
│   │   ├── multivar-{gradient-derivations,output-schema}.md
│   │   ├── newton-{exploration-summary,vs-lbfgs-reframe}.md
│   │   ├── longfiber-research.md, sweep-research.md, sweep-candidate-handoff.md
│   │   ├── session-update-2026-04-17.md
│   │   ├── {integration,numerical-validation,physics-validation-and-docs,tutor}-agent-prompt.md
│   │   └── gsd2-salvaged-decisions.md
│   ├── research/                  # Initial research pack (~2026-03)
│   │   ├── ARCHITECTURE.md, FEATURES.md, PITFALLS.md, RIVERA_RESEARCH.md, STACK.md, SUMMARY.md, questions.md
│   ├── milestones/                # Milestone records
│   ├── quick/                     # GSD quick-workflow artifacts
│   ├── reports/                   # Phase reports
│   ├── todos/pending/             # Deferred TODOs
│   └── archive/                   # Historical
├── tmp_scratch/                   # Throwaway scratch files — do not rely on
└── .bg-shell, .claude, .git
```

## Directory Purposes

**`src/`:**
- Purpose: The `MultiModeNoise` Julia package — physics core only. Every file here is protected (Rule P1 in `CLAUDE.md`).
- Contains: ODE RHS functions, fiber parameter construction, gain model, noise analysis, helper utilities.
- Key files: `MultiModeNoise.jl` (include chain), `simulation/simulate_disp_mmf.jl`, `simulation/sensitivity_disp_mmf.jl`, `helpers/helpers.jl`, `mmf_cost.jl`.

**`src/simulation/`:**
- Purpose: Forward + adjoint ODE integrators. The single source of truth for pulse propagation physics.
- Dict mutations to `fiber["zsave"]` happen through `solve_disp_mmf` — callers must `deepcopy(fiber)` for thread safety.

**`src/mmf_cost.jl`:**
- Purpose: Three MMF cost variants (`mmf_cost_sum`, `mmf_cost_fundamental`, `mmf_cost_worst_mode`). Lives in `src/` so both SMF and MMF drivers can import it without `include()`.

**`scripts/` (shared, protected):**
- `common.jl` — `FIBER_PRESETS`, `setup_raman_problem`, `setup_amplitude_problem`, `spectral_band_cost`, `recommended_time_window`, `nt_for_window`, `check_boundary_conditions`, `print_fiber_summary`. Include-guarded with `_COMMON_JL_LOADED`.
- `visualization.jl` — all PyPlot plotting. `plot_optimization_result_v2`, `plot_spectral_evolution`, `plot_phase_diagnostic`, `plot_spectrogram`. Include-guarded with `_VISUALIZATION_JL_LOADED`.
- `standard_images.jl` — `save_standard_set(phi_opt, uω0, fiber, sim, band_mask, Δf, raman_threshold; tag, fiber_name, L_m, P_W, output_dir)`. Generates 4 PNGs per run. MANDATORY per `CLAUDE.md`.
- `determinism.jl` — `ensure_deterministic_environment()`. Pins FFTW `ESTIMATE`, loads wisdom from `results/raman/phase14/fftw_wisdom.txt`, sets `BLAS.set_num_threads(1)`.

**`scripts/` (session-scoped driver namespaces):**
- `multivar_*.jl` — Session A joint {φ, A, E} optimizer.
- `mmf_*.jl` — Session C multimode Raman (M=4, M=6).
- `sweep_simple_*.jl` — Session E low-res Pareto sweep.
- `simple_profile_*.jl`, `render_simple_phases.jl` — Session D simple-profile stability (Phase 17).
- `longfiber_*.jl` + `.sh` — Session F 50/100 m SMF runs.
- `sharp_*.jl` — Session G sharpness A/B.
- `cost_audit_*.jl` + `.sh` — Session H cost-function audit.
- `phase13_*.jl`, `phase14_*.jl`, `phase15_*.jl` — earlier phase drivers still referenced.

**`scripts/burst/`:**
- Purpose: Bash helpers installed to `~/bin/` on `claude-code-host` for driving the burst VM.
- `install.sh` provisions `burst-start`, `burst-stop`, `burst-ssh`, `burst-status`, `burst-run-heavy`, `burst-spawn-temp`, `burst-list-ephemerals`, `burst-watchdog`.
- `run-heavy.sh` is the mandatory wrapper (Rule P5) — enforces `/tmp/burst-heavy-lock`, names tmux sessions, tees logs.

**`test/`:**
- Purpose: Julia Pkg test suite (`Pkg.test("MultiModeNoise")`).
- `runtests.jl` — minimal smoke test (module loads).
- `tier_{fast,slow,full}.jl` — tiered harnesses selectable by env var.
- Topical tests co-locate with their driver (e.g. `test_phase16_mmf.jl` exercises `mmf_raman_optimization.jl`).

**`notebooks/`:**
- Purpose: Interactive Jupyter (IJulia) exploration — quantum noise, YDFA gain, supercontinuum.
- Not required for batch runs; exploratory only.

**`data/`:**
- Purpose: Reference experimental data (F-vs-P sweeps) + Yb cross-section NPZs.
- `plotFvsP.jl` is the only Julia file here — uses `CSV.jl`, `DataFrames.jl`.

**`fibers/`:**
- Purpose: NPZ cache of GRIN eigensolves. Cache key is in the filename: `DispersiveFiber_GRIN_r={radius}_M={modes}_λ0={nm}um_Nt={Nt}_time_window={ps}ps_nx={grid}_Nbeta={β_order}.npz`.
- Generated: yes (by `get_disp_fiber_params`); committed: mixed (gitignored by default but some are tracked for reproducibility).

**`docs/`:**
- Purpose: User-facing documentation + LaTeX physics writeups.
- Key: `quickstart-optimization.md`, `cost-function-physics.md`, `adding-a-fiber-preset.md`, `adding-an-optimization-variable.md`.
- Compiled PDFs committed alongside `.tex` for advisor sharing.

**`presentation-2026-04-17/`:**
- Purpose: Advisor-meeting deck + pedagogical figures from the 2026-04-17 sync.
- `pedagogical/` contains teaching-oriented plots.

**`results/`:**
- Purpose: All simulation outputs. Gitignored by default; large JLD2s never committed.
- `results/raman/manifest.json` — append-only canonical SMF run index.
- `results/raman/<phase-or-run>/` — each phase or tagged run owns a subdirectory with JLD2 + JSON sidecar + 4 standard PNGs + optional `FINDINGS.md`.
- `results/burst-logs/<tag>_<timestamp>.log` — captured from `burst-run-heavy`.
- `results/SYNTHESIS-2026-04-19.md` — latest cross-session rollup.

**`.planning/`:**
- Purpose: GSD workflow state. Mixed provenance: `STATE.md`, `ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`, `MILESTONES.md` are git-tracked; everything else syncs between Mac ↔ VM via `sync-planning-to-vm` / `sync-planning-from-vm` rsync helpers.
- `.planning/codebase/` — the document set you are reading.
- `.planning/phases/<NN>-<slug>/` — one dir per planned or executed phase. Contents: `GOAL.md`, `PLAN.md`, implementation notes, per-plan subdirs.
- `.planning/sessions/<Letter>-*-{decisions,status,standdown}.md` — per-session coordination files (Rule P3 — append-only).
- `.planning/seeds/` — candidate future phases.
- `.planning/notes/` — cross-session design notes (math derivations, infrastructure decisions, agent prompts).
- `.planning/research/` — initial research pack from project inception.

## Key File Locations

**Entry Points:**
- `scripts/raman_optimization.jl` — canonical SMF Raman driver
- `scripts/mmf_raman_optimization.jl` — canonical MMF driver
- `scripts/multivar_demo.jl`, `scripts/multivar_optimization.jl` — joint optimizer
- `scripts/sweep_simple_run.jl` — Pareto sweep
- `scripts/longfiber_optimize_100m.jl` — 100 m long-fiber
- `scripts/cost_audit_driver.jl` — cost-function audit
- `scripts/sharp_ab_slim.jl` — sharpness A/B
- `test/runtests.jl` — smoke test entry

**Configuration:**
- `Project.toml`, `Manifest.toml` — Julia deps (committed; Manifest pinned to 1.12.4)
- `LocalPreferences.toml` — FFTW/MKL preferences
- `CLAUDE.md` — project rules, parallel-session protocol, compute discipline
- `scripts/determinism.jl` — runtime numerical pins

**Core Physics (read-only unless explicitly changing physics):**
- `src/simulation/simulate_disp_mmf.jl` — forward RHS
- `src/simulation/sensitivity_disp_mmf.jl` — adjoint RHS
- `src/simulation/fibers.jl` — GRIN solver
- `src/helpers/helpers.jl` — parameter builders
- `src/mmf_cost.jl` — MMF cost variants

**Shared driver infrastructure (edit only with explicit user go-ahead):**
- `scripts/common.jl`, `scripts/visualization.jl`, `scripts/standard_images.jl`, `scripts/determinism.jl`

**Testing:**
- `test/runtests.jl`, `test/tier_{fast,slow,full}.jl`
- `test/test_*.jl` topical files
- `scripts/test_optimization.jl`, `scripts/test_visualization_smoke.jl`, `scripts/test_multivar_*.jl`

**Fiber-eigensolve cache:**
- `fibers/DispersiveFiber_GRIN_*.npz`
- `results/raman/phase16/fiber_cache/*.npz` (MMF runs)

## Naming Conventions

**Files:**
- `snake_case.jl` for all Julia source
- `PascalCase.jl` reserved for module-entry files (`MultiModeNoise.jl`)
- Topic prefix for session-scoped scripts: `multivar_*`, `mmf_*`, `longfiber_*`, `sweep_simple_*`, `simple_profile_*`, `sharp_*`, `cost_audit_*`, `phase{13,14,15}_*`
- `test_*.jl` for test files
- Batch launchers: `<topic>_run_*.sh`, `<topic>_spawn_*.sh`

**Directories:**
- `snake_case` except `.planning/phases/<NN>-<kebab-case-slug>/` where NN is 2-digit numeric
- Session status dirs by capital letter: `A-*`, `C-*`, `E-*`, `F-*`, `G-*`, `H-*`

**Result tags (used in PNG filenames):**
- `{fiber}_L{len}m_P{power}W_<variant>` e.g. `smf28_L2m_P0p3W`, `hnlf_l0p25m_p0p020w_nphi16`
- Decimal separator rendered as `p` (no dots) in filenames
- 4 PNG suffixes per run: `_phase_profile.png`, `_evolution.png`, `_phase_diagnostic.png`, `_evolution_unshaped.png`

## Where to Add New Code

**New physics primitive (e.g. new nonlinear term, new fiber model):**
- Implementation: `src/simulation/<descriptive_name>.jl` (then `include` in `src/MultiModeNoise.jl`)
- Requires explicit user approval — `src/simulation/` is Rule P1 protected.

**New fiber preset (SMF):**
- Add entry to `FIBER_PRESETS::Dict` in `scripts/common.jl:47`
- Shared file — coordinate through the user or Session B (repo-polish).
- Follow `docs/adding-a-fiber-preset.md`.

**New fiber preset (MMF):**
- Add entry to `MMF_FIBER_PRESETS::Dict` in `scripts/mmf_fiber_presets.jl:46`
- Owned by Session C namespace — safer to edit than `common.jl`.

**New driver / experiment:**
- Pick a session-unique prefix (e.g. `newton_*`, `gain_*`).
- Place in `scripts/<prefix>_<role>.jl`.
- Include `scripts/common.jl`, `scripts/visualization.jl`, `scripts/standard_images.jl`, `scripts/determinism.jl`.
- Call `ensure_deterministic_environment()` first thing.
- Call `save_standard_set(...)` before exit (mandatory).
- Save JLD2 with full state to `results/raman/<your_run_dir>/` and append to `results/raman/manifest.json`.

**New cost-function variant:**
- If SMF: follow `spectral_band_cost` signature in `scripts/common.jl` or add a new function in your driver.
- If MMF: add to `src/mmf_cost.jl` following the three-variant pattern there.
- Must return `(J::Float64, dJ::Matrix{ComplexF64})` with `dJ = ∂J/∂conj(uωf)` so `solve_adjoint_disp_mmf` accepts it directly.

**New optimization variable (e.g. GDD subspace, polynomial basis):**
- Extend `MVConfig` in `scripts/multivar_optimization.jl` (owned by Session A)
- Or write a prefixed new driver if independent.
- See `docs/adding-an-optimization-variable.md`.

**New test:**
- Unit: `test/test_<topic>.jl` (+ add to `tier_fast.jl` if fast)
- Integration: `test/tier_slow.jl` or `tier_full.jl`
- Script-level smoke: `scripts/test_<topic>.jl` (fine for quick iteration)

**New notebook:**
- `notebooks/<descriptive_name>.ipynb` — require IJulia kernel.

**New phase (planning):**
- `mkdir -p .planning/phases/<NN>-<slug>/` with `GOAL.md`, `PLAN.md`, per-task subdirs.
- Append to `.planning/ROADMAP.md` at the user's direction.

## Special Directories

**`fibers/`:**
- Purpose: GRIN eigensolve cache (NPZ).
- Generated: Yes — on first call to `get_disp_fiber_params` for a given parameter tuple.
- Committed: Mixed — small files tracked; large ones typically left uncommitted.

**`results/`:**
- Purpose: Simulation outputs (PNG, JLD2, JSON, logs, Markdown summaries).
- Generated: Yes.
- Committed: No (gitignored except for select `RESULTS_SUMMARY.md`, `SYNTHESIS-*.md`, per-phase `FINDINGS.md`).

**`results/burst-logs/`:**
- Purpose: stdout/stderr teed by `~/bin/burst-run-heavy`.
- Filename: `<session-tag>_<timestamp>.log`.

**`tmp_scratch/`:**
- Purpose: Throwaway scratch during development. Do not rely on contents.
- Committed: No.

**`.planning/archive/`:**
- Purpose: Historical planning artifacts superseded by active phases.
- Committed: Yes (git).

**`.planning/` (general):**
- Sync model: `STATE.md`, `ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`, `MILESTONES.md` via git. Everything else via `rsync --update` (no `--delete`) through the `sync-planning-to-vm` / `sync-planning-from-vm` helpers on the Mac.

**`presentation-2026-04-17/`:**
- Purpose: Advisor-meeting deck + figures. Committed.

---

*Structure refresh: 2026-04-19*
