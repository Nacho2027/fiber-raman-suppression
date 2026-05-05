# Julia File Inventory

Snapshot date: 2026-05-05.

Scope: tracked `*.jl` files only. This intentionally excludes archived material, generated results, hidden agent worktrees, and untracked scratch files. Line counts are approximate working-tree counts at the time of the inventory.

Status labels:

- `Core`: package code or maintained experiment engine code that should stay.
- `Wrapper`: thin canonical entry point; keep unless the matching workflow is retired.
- `Workflow`: runnable Julia command behind a canonical entry point.
- `Extension`: lab-owned research extension surface.
- `Test`: regression coverage.
- `Review`: keep for now, but this file is a good next target for promotion, merge, or deletion once its behavior is replaced.

## Summary

The repo now has 115 tracked Julia files after removing one unreferenced legacy solver and three obsolete dev smoke files. The `src/` tree is reasonably compact and API/backend oriented. Most remaining bulk is in `scripts/lib/` and `scripts/workflows/`, where the next cleanup should be promotion into `src/fiberlab/` APIs or deletion after equivalent API coverage exists.

## Source Package

| File | Lines | Status | Summary |
|---|---:|---|---|
| `src/FiberLab.jl` | 57 | Core | Package module entry point; exports the notebook-facing FiberLab API, deterministic/runtime helpers, result IO helpers, and includes the lower-level simulation, analysis, IO, and API implementation files. |
| `src/fiberlab/api.jl` | 268 | Core | Defines the high-level notebook/agent-facing API objects (`Fiber`, `Pulse`, `Grid`, `Control`, `Objective`, `Solver`, `ArtifactPolicy`, `Experiment`) plus config rendering, file writing, and summarization helpers. |
| `src/helpers/helpers.jl` | 192 | Core | Shared backend helpers for grids, dB conversion, dispersion simulation dictionaries, GRIN fiber parameter dictionaries, and user-defined single-mode fiber parameter construction. |
| `src/io/artifacts.jl` | 45 | Core | Small artifact-path and JSON/JLD2 writing helper layer used by workflow code and public result-output utilities. |
| `src/io/results.jl` | 263 | Core | Canonical result payload and sidecar schema implementation, including save/load helpers, manifest update functions, and legacy JLD2/JSON pair resolution. |
| `src/runtime/determinism.jl` | 42 | Core | Runtime determinism guard for FFTW planning mode and BLAS threading plus a status reporter for reproducibility checks. |
| `src/simulation/simulate_disp_mmf.jl` | 201 | Core | Main dispersive Kerr/Raman propagation backend for single-mode and multimode-shaped arrays, including RHS construction, initial-state construction, and `solve_disp_mmf`. |
| `src/simulation/sensitivity_disp_mmf.jl` | 305 | Core | Adjoint propagation backend and kernel helpers used for spectral-phase gradient computation. |
| `src/simulation/simulate_disp_gain_mmf.jl` | 245 | Core | Gain-aware propagation path for signal propagation with constant gain or YDFA gain models. |
| `src/simulation/fibers.jl` | 222 | Core | GRIN fiber construction, mode solving, propagation-parameter assembly, and overlap tensor computation for multimode work. |
| `src/mmf_cost.jl` | 222 | Review | Multimode Raman objective variants and mode-fraction reports; not included by `FiberLab.jl` directly, but actively included by `scripts/lib/mmf_raman_optimization.jl`, so keep until multimode objective code is promoted into the package. |
| `src/analysis/analysis.jl` | 66 | Core | Noise-map computation helpers for multimode measurement variance decomposition. |
| `src/analysis/plotting.jl` | 26 | Review | One `plot_fiber` helper for fiber spatial mode plots; kept because it is included by the package, but it is small enough to merge into a broader plotting/visualization API later. |
| `src/gain_simulation/gain.jl` | 181 | Core | YDFA parameter model, cross-section loading/interpolation, PSD conversion, gain calculation, and gain-parameter construction. |

## Lab Extensions

| File | Lines | Status | Summary |
|---|---:|---|---|
| `lab_extensions/objectives/pulse_compression_planning.jl` | 17 | Extension | Planning-only objective stub for future pulse-compression work; deliberately throws until the objective and gradient are implemented and promoted. |
| `lab_extensions/objectives/temporal_peak_scalar.jl` | 25 | Extension | Executable scalar objective that minimizes `1 - peak_fraction` for temporal peak power, intended for derivative-free scalar extension smoke tests. |
| `lab_extensions/variables/cubic_phase_scalar.jl` | 37 | Extension | Executable one-scalar phase variable mapping a coefficient onto a normalized low-order phase basis and returning the standard extension control tuple. |
| `lab_extensions/variables/gain_tilt_planning.jl` | 17 | Extension | Planning-only gain/attenuation tilt variable stub; documents the extension point and blocks execution until projection, throughput, gradient, artifact, and safety semantics exist. |
| `lab_extensions/variables/mode_weights_planning.jl` | 17 | Extension | Planning-only multimode launch/modal-weight variable stub; blocks execution until bounds, gradients, artifacts, and validation are promoted. |
| `lab_extensions/variables/phase_amp_energy_control.jl` | 59 | Extension | Executable three-parameter control extension mapping vector coefficients to phase, bounded amplitude tilt, and pulse-energy scale. |
| `lab_extensions/variables/poly_phase_vector.jl` | 43 | Extension | Executable two-coefficient polynomial spectral-phase vector control used for derivative-free extension experiments. |

## Canonical Wrappers

| File | Lines | Status | Summary |
|---|---:|---|---|
| `scripts/canonical/export_run.jl` | 5 | Wrapper | Thin entry point that delegates to `scripts/workflows/export_run.jl`. |
| `scripts/canonical/generate_reports.jl` | 7 | Wrapper | Thin entry point that runs sweep-report and presentation-figure generation workflows together. |
| `scripts/canonical/index_results.jl` | 5 | Wrapper | Thin entry point that delegates to result index generation. |
| `scripts/canonical/index_telemetry.jl` | 5 | Wrapper | Thin entry point that delegates to telemetry index generation. |
| `scripts/canonical/inspect_run.jl` | 5 | Wrapper | Thin entry point that delegates to run inspection. |
| `scripts/canonical/lab_ready.jl` | 5 | Wrapper | Thin entry point that delegates to lab-readiness checks. |
| `scripts/canonical/optimize_raman.jl` | 5 | Wrapper | Thin entry point for approved Raman optimization configs. |
| `scripts/canonical/refine_amp_on_phase.jl` | 5 | Wrapper | Thin entry point for staged amplitude-on-phase refinement. |
| `scripts/canonical/regenerate_standard_images.jl` | 5 | Wrapper | Thin entry point for regenerating standard image sets from saved results. |
| `scripts/canonical/replay_slm_mask.jl` | 5 | Wrapper | Thin entry point for SLM replay bundle generation/evaluation. |
| `scripts/canonical/run_experiment.jl` | 5 | Wrapper | Thin entry point for the front-layer experiment runner. |
| `scripts/canonical/run_experiment_sweep.jl` | 5 | Wrapper | Thin entry point for front-layer experiment sweep validation/execution. |
| `scripts/canonical/run_exploration_contract.jl` | 109 | Wrapper | Runnable exploration-contract command that parses CLI args and delegates validation or execution to `scripts/lib/exploration_contract_runner.jl`; could later become a package API call. |
| `scripts/canonical/run_sweep.jl` | 5 | Wrapper | Thin entry point for approved canonical sweeps. |
| `scripts/canonical/scaffold_exploration.jl` | 344 | Review | Larger generator that creates objective, variable, and config files for runnable explorations; useful, but it is too large for `canonical/` and should eventually move behind a FiberLab API or workflow file. |
| `scripts/canonical/scaffold_objective.jl` | 5 | Wrapper | Thin entry point for objective-extension scaffolding. |
| `scripts/canonical/scaffold_scalar_config.jl` | 209 | Review | Standalone config generator for bounded scalar exploration configs; keep for now, but merge into the broader exploration scaffolder or API when stable. |
| `scripts/canonical/scaffold_variable.jl` | 5 | Wrapper | Thin entry point for variable-extension scaffolding. |
| `scripts/canonical/scaffold_vector_config.jl` | 205 | Review | Standalone config generator for vector exploration configs; keep for now, but merge into the broader exploration scaffolder or API when stable. |

## Workflows

| File | Lines | Status | Summary |
|---|---:|---|---|
| `scripts/workflows/export_run.jl` | 343 | Workflow | Builds experiment-facing export bundles from saved run artifacts, including phase/hardware handoff metadata and validation helpers. |
| `scripts/workflows/generate_presentation_figures.jl` | 392 | Workflow | Reads existing sweep/run artifacts and renders advisor/presentation figures without rerunning simulations. |
| `scripts/workflows/generate_sweep_reports.jl` | 425 | Workflow | Generates per-point report cards and ranked sweep summaries from existing sweep payloads. |
| `scripts/workflows/index_results.jl` | 210 | Workflow | CLI-facing result-index builder that scans result roots and writes/prints run index summaries. |
| `scripts/workflows/index_telemetry.jl` | 141 | Workflow | CLI-facing telemetry-index builder that summarizes `telemetry.json` files. |
| `scripts/workflows/inspect_run.jl` | 221 | Workflow | Loads a run artifact or run directory and prints normalized metrics, standard-image status, trust status, and export status. |
| `scripts/workflows/lab_ready.jl` | 332 | Workflow | Implements config/run readiness checks for supported experiments, expected artifacts, trust reports, and export bundles. |
| `scripts/workflows/optimize_raman.jl` | 65 | Workflow | Small approved-config runner for canonical Raman optimization through the experiment runner. |
| `scripts/workflows/polish_output_format.jl` | 49 | Review | One-off output-format migration/polish helper; keep only if old artifacts still need local migration. |
| `scripts/workflows/refine_amp_on_phase.jl` | 182 | Workflow | CLI planning and execution wrapper for the staged amplitude-on-phase refinement workflow. |
| `scripts/workflows/regenerate_standard_images.jl` | 177 | Workflow | Finds saved result payloads and regenerates the standard image set from stored phase and metadata. |
| `scripts/workflows/replay_slm_mask.jl` | 210 | Workflow | Loads an optimized phase, applies a generic SLM replay profile, writes a replay bundle, and can optionally evaluate replay loss. |
| `scripts/workflows/run_comparison.jl` | 228 | Review | Historical five-run comparison driver that reruns canonical configurations and produces cross-run figures; keep until equivalent comparison support is exposed through the experiment API. |
| `scripts/workflows/run_experiment.jl` | 346 | Workflow | Main front-layer experiment command, including listing, validation, dry-run, capability, artifact-plan, exploration-check, exploration-run, and latest-run paths. |
| `scripts/workflows/run_experiment_sweep.jl` | 191 | Workflow | Front-layer experiment sweep validator/executor, including execution gating and per-case artifact status. |
| `scripts/workflows/run_sweep.jl` | 534 | Workflow | Approved parameter-sweep runner over fiber length and power, including multistart support and aggregate sweep outputs. |
| `scripts/workflows/scaffold_objective.jl` | 140 | Workflow | Creates planning-only or scalar-executable objective extension contracts and Julia stubs. |
| `scripts/workflows/scaffold_variable.jl` | 192 | Workflow | Creates planning-only or executable variable/control extension contracts and Julia stubs. |

## Script Libraries

| File | Lines | Status | Summary |
|---|---:|---|---|
| `scripts/dev/check_agent_docs.jl` | 248 | Core | Repository documentation guard used by `make docs-check`; checks required docs, link hygiene, first-screen README vocabulary, stale public vocabulary, agent-doc registry, and sync-conflict markers. |
| `scripts/lib/adjoint_contracts.jl` | 523 | Core | First-class adjoint contract layer for reduced-basis spectral phase controls, objective terminal adjoints, pullback checks, and reduced-phase optimization. |
| `scripts/lib/amp_on_phase_refinement.jl` | 210 | Core | Implements the staged amplitude-on-phase workflow: run phase-only optimization, optimize bounded amplitude on top, save standard artifacts, and write the closure summary. |
| `scripts/lib/amplitude_optimization.jl` | 928 | Review | Experimental spectral-amplitude optimization backend with regularization, low-dimensional and full-grid optimizers, validation, plotting, and standalone runner; large and should be promoted or trimmed once multivariable API work stabilizes. |
| `scripts/lib/artifact_plan.jl` | 331 | Core | Declares artifact hooks and builds inspectable artifact plans for regimes, objectives, variables, and exploratory outputs. |
| `scripts/lib/canonical_runs.jl` | 325 | Core | Loads approved run/sweep configs, normalizes legacy canonical configs, and provides output-directory helpers and the five-run comparison registry. |
| `scripts/lib/common.jl` | 733 | Core | Shared single-mode setup and analysis layer: fiber presets, peak-power conversion, time-window sizing, Raman/temporal objectives, conservation checks, and problem setup. |
| `scripts/lib/control_layout.jl` | 112 | Core | Builds inspectable optimizer-vector layouts for active controls, including block shapes, lengths, units, bounds, and artifact hooks. |
| `scripts/lib/determinism.jl` | 9 | Core | Small compatibility shim that imports deterministic runtime functions from `FiberLab`. |
| `scripts/lib/experiment_runner.jl` | 1997 | Core | Main execution orchestrator for front-layer experiments: directories, artifact validation, export validation, manifests, supported kwargs, scalar extensions, multivar runs, exploration runs, and completion summaries. |
| `scripts/lib/experiment_spec.jl` | 1225 | Core | Config schema and validation engine for experiments, including registries, config loading, canonical-run adaptation, execution modes, promotion status, run policy, and rendered plans. |
| `scripts/lib/experiment_sweep.jl` | 455 | Core | Sweep config schema, validation, expansion, output-directory planning, and rendered sweep plans. |
| `scripts/lib/exploration_contract_runner.jl` | 1063 | Core | Freeform exploration-contract runtime: contract loading, validation, sandboxed source inclusion, optimization, artifact writing, and standard result summaries. |
| `scripts/lib/exploratory_artifacts.jl` | 437 | Core | Writes exploratory artifacts for scalar/multivariable/front-layer experiments, including sidecars, plots, and metadata summaries. |
| `scripts/lib/longfiber_checkpoint.jl` | 342 | Review | Long-fiber checkpoint support for continuation/restart workflows; keep if long-fiber work is still planned, otherwise archive after equivalent API support exists. |
| `scripts/lib/longfiber_setup.jl` | 316 | Review | Long-fiber setup helpers and reach diagnostics; planning-stage but tied to future long-fiber promotion. |
| `scripts/lib/manifest_io.jl` | 20 | Core | Thin import shim exposing run manifest helpers from `FiberLab` to script code. |
| `scripts/lib/mmf_fiber_presets.jl` | 126 | Core | Named multimode/GRIN fiber presets and lookup helpers used by multimode setup. |
| `scripts/lib/mmf_raman_optimization.jl` | 721 | Review | Multimode Raman optimization path using `src/mmf_cost.jl`, multimode setup, objective variants, and standard artifacts; keep while multimode remains a planned regime, then promote into package API. |
| `scripts/lib/mmf_setup.jl` | 264 | Core | Multimode problem setup helper using GRIN presets, mode solving, pulse construction, and band-mask generation. |
| `scripts/lib/multivar_artifacts.jl` | 206 | Core | Artifact writers for multivariable optimization outputs and metadata sidecars. |
| `scripts/lib/multivar_optimization.jl` | 1281 | Core | Multivariable optimization backend for phase/amplitude/energy/gain-tilt controls, including control mapping, regularization, gradients, validation, and run helpers. |
| `scripts/lib/numerical_trust.jl` | 406 | Core | Numerical-trust reporting for optimization runs, including gradient checks, conservation checks, boundary leakage, and report rendering. |
| `scripts/lib/objective_registry.jl` | 554 | Core | Registry and validation layer for built-in and extension objective contracts. |
| `scripts/lib/objective_surface.jl` | 54 | Core | Small objective-surface contract type and constructor used to pass cost/gradient behavior through optimizers. |
| `scripts/lib/raman_optimization.jl` | 912 | Core | Main single-mode Raman phase-optimization backend with spectral objectives, adjoint gradient, trust checks, plotting hooks, and canonical run helpers. |
| `scripts/lib/regularizers.jl` | 134 | Core | Regularization helpers for GDD, boundary penalties, and objective-surface regularizer composition. |
| `scripts/lib/results_index.jl` | 732 | Core | Result discovery and indexing library for run directories, manifests, artifact metadata, and run-index summaries. |
| `scripts/lib/results_index_rendering.jl` | 250 | Core | Markdown and tabular rendering helpers for result-index rows. |
| `scripts/lib/run_artifacts.jl` | 251 | Core | Artifact discovery/load helpers for run directories, artifact paths, manifests, and standard image status. |
| `scripts/lib/sharpness_optimization.jl` | 553 | Review | Experimental sharpness-regularized optimization lane using projected finite-difference curvature estimates; keep only if this research direction remains live. |
| `scripts/lib/slm_replay.jl` | 444 | Core | Device-agnostic SLM replay profile, loading, validation, phase replay, quantization, and replay bundle helpers. |
| `scripts/lib/standard_images.jl` | 161 | Core | Canonical standard image writer used by optimization drivers to save the required phase profile, evolution, diagnostic, and unshaped evolution plots. |
| `scripts/lib/telemetry_index.jl` | 273 | Core | Telemetry discovery, parsing, indexing, Markdown rendering, and JSON writing for run telemetry files. |
| `scripts/lib/variable_registry.jl` | 672 | Core | Registry and validation layer for built-in and extension variable/control contracts. |
| `scripts/lib/visualization.jl` | 2111 | Review | Large plotting library for spectral/temporal evolution, optimization diagnostics, cross-run summaries, and publication-style figures; it is active but should be split or promoted into `src` when the public plotting API is designed. |

## Tests

| File | Lines | Status | Summary |
|---|---:|---|---|
| `test/runtests.jl` | 23 | Test | Test entry point that selects the `fast`, `slow`, or `full` tier from `FIBERLAB_TEST_TIER`. |
| `test/tier_fast.jl` | 531 | Test | Main fast test suite aggregator plus lightweight smoke checks for core optimization, artifact, and API behavior. |
| `test/tier_slow.jl` | 56 | Test | Slow deterministic optimization check aggregator for heavier local validation. |
| `test/tier_full.jl` | 15 | Test | Full tier wrapper that runs slow tests and additional determinism checks. |
| `test/core/test_adjoint_contracts.jl` | 216 | Test | Tests reduced-phase adjoint contracts, terminal adjoint checks, control pullbacks, and reduced coefficient optimization behavior. |
| `test/core/test_canonical_lab_surface.jl` | 519 | Test | Tests run artifact loading, result indexing, inspection, export validation, lab-ready checks, and amplitude-on-phase plan surfaces. |
| `test/core/test_determinism.jl` | 131 | Test | Runs repeated small optimizations to verify deterministic setup and stable results. |
| `test/core/test_experiment_config_adversarial.jl` | 204 | Test | Mutates experiment configs to ensure validation rejects malformed, unsupported, or unsafe combinations. |
| `test/core/test_experiment_front_layer.jl` | 961 | Test | Broad front-layer coverage for registries, config loading, plans, scaffolding, promotion status, and execution-mode behavior. |
| `test/core/test_experiment_sweep_adversarial.jl` | 117 | Test | Mutates sweep configs to ensure sweep validation rejects bad dimensions, values, and unsupported execution paths. |
| `test/core/test_experiment_sweep_sidecars.jl` | 60 | Test | Verifies experiment sweep sidecar metadata behavior. |
| `test/core/test_exploration_contract_runner.jl` | 237 | Test | Tests freeform exploration contract validation, dry runs, execution, artifacts, and failure modes. |
| `test/core/test_exploration_scaffold_cli.jl` | 48 | Test | CLI smoke coverage for exploration scaffolding. |
| `test/core/test_fiberlab_api.jl` | 24 | Test | Minimal public FiberLab API smoke test for constructing/summarizing an experiment and rendering config text. |
| `test/core/test_gain_tilt_variable_integration.jl` | 215 | Test | Integration coverage for gain-tilt variable contracts and scalar-search execution behavior. |
| `test/core/test_non_raman_objective_integration.jl` | 69 | Test | Coverage for temporal-width objective registration, config lowering, and finite-difference gradient behavior. |
| `test/core/test_regime_promotion_status.jl` | 95 | Test | Tests promotion-stage reporting and execution policy for supported, experimental, long-fiber, and multimode regimes. |
| `test/core/test_repo_structure.jl` | 84 | Test | Repository-structure guard for root/docs/scripts expectations, sync-conflict absence, router syntax, and canonical include targets. |
| `test/core/test_research_engine_acceptance.jl` | 137 | Test | Acceptance harness for supported experiment config validation, dry runs, artifact completeness, export bundles, and lab-ready status. |
| `test/core/test_research_extension_integration.jl` | 264 | Test | Integration tests for planning-only and executable research extensions, including objective/variable discovery, gating, and scalar execution. |
| `test/core/test_slm_replay.jl` | 185 | Test | Tests generic SLM replay profile validation, phase replay, quantization behavior, and replay bundle support. |

## Cleanup Queue

The best remaining cleanup targets are not random files. They are coherent promotion/deletion decisions:

1. Promote notebook-facing execution APIs out of `scripts/lib/experiment_runner.jl`, `experiment_spec.jl`, and related workflow code into `src/fiberlab/`, then shrink scripts into optional wrappers.
2. Decide whether long-fiber, multimode, amplitude, and sharpness lanes are live product directions. If a lane is live, promote its API; if not, archive the lane with a verdict.
3. Split or replace `scripts/lib/visualization.jl` only when there is a real public plotting API. It is too large, but deleting it now would break maintained artifact workflows.
4. Merge the standalone scalar/vector config scaffolders into the exploration scaffolder or a FiberLab API after the extension story settles.
5. Delete `scripts/workflows/polish_output_format.jl` once there are no local legacy artifacts that still need migration.
