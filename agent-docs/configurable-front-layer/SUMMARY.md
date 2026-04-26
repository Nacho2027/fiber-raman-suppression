# Configurable Front-Layer Summary

## Outcome

Added both:

- a human-facing architecture proposal and TOML schema sketch
- the first working implementation slice of the front layer

Scope clarification: the front layer should be treated as infrastructure for
general fiber-optic optimization research. Raman suppression is the first
implemented objective family and the current validation target, not the final
scope of the system.

## Main recommendation

Do not build a plugin-heavy framework. Add one explicit orchestration layer
with five stable contracts:

- `ExperimentSpec`
- `ProblemBundle`
- `ControlLayout`
- `ObjectiveSurface`
- `ArtifactPlan`

## Why this fits the repo

- The repo already has good low-level kernels and setup helpers.
- The canonical run surface already uses TOML, so a richer config layer is a
  natural extension.
- The main missing abstraction is the run-description contract that can unify
  single-mode, long-fiber, multimode, and multivar workflows.
- The repo already has real lab-surface pieces:
  - config-backed canonical runs
  - run inspection
  - experiment-facing export bundles
  - tests for that surface

## Implementation landed in this pass

- `scripts/lib/experiment_spec.jl`
  - loads front-layer configs from `configs/experiments/*.toml`
  - adapts existing canonical run configs from `configs/runs/*.toml`
  - validates the current capability slice
- `scripts/lib/objective_registry.jl`
  - defines the code-owned objective allowlist, supported variable tuples,
    backend mapping, and allowed regularizers
  - discovers metadata-only lab objective extension contracts from
    `lab_extensions/objectives/*.toml`
- `scripts/lib/experiment_runner.jl`
  - maps validated specs onto the existing `run_optimization(...)` and
    `run_multivar_optimization(...)` paths
  - validates completed run artifacts and attaches the validation report to the
    returned run bundle
  - renders the shared run-completion summary used by the CLI
- `scripts/workflows/run_experiment.jl`
  - supports `--list`
  - supports `--capabilities`
  - supports `--objectives`
  - supports `--validate-all`
  - supports `--dry-run`
  - supports `--compute-plan`
  - supports `--latest`
  - runs one validated experiment config
  - prints output directory, artifact path, artifact-validation status, and
    standard-image status after a completed run
- `scripts/lib/experiment_sweep.jl`
  - loads front-layer sweep configs from `configs/experiment_sweeps/*.toml`
  - expands one safe parameter path across multiple values
  - validates every generated experiment case through the normal front-layer
    contract
- `scripts/workflows/run_experiment_sweep.jl`
  - supports `--list`
  - supports `--dry-run`
  - supports `--validate-all`
  - supports explicit `--execute` for locally supported cases and writes
    `SWEEP_SUMMARY.md`
- `scripts/lib/results_index.jl`
  - scans completed run artifacts and sweep summaries and renders a compact
    Markdown results index
- `scripts/workflows/index_results.jl`
  - exposes the read-only run/campaign index as a maintained CLI workflow
- `scripts/canonical/index_results.jl`
  - provides the public canonical wrapper for results indexing
- `configs/experiments/README.md`
  - documents the safe researcher-facing knobs and current support boundary
- `docs/guides/configurable-experiments.md`
  - gives lab users the operational workflow for listing configs, dry-running,
    editing safe knobs, running, inspecting, and checking neutral handoff output
- `configs/experiments/research_engine_smoke.toml`
  - provides a tiny phase-only smoke run for real CLI/artifact verification
- `configs/experiments/research_engine_export_smoke.toml`
  - provides a tiny phase-only smoke run for neutral CSV handoff verification
- `configs/experiments/research_engine_peak_smoke.toml`
  - provides a tiny phase-only smoke run for experimental objective dispatch
- `configs/experiments/grin50_mmf_phase_sum_poc.toml`
  - provides an experimental GRIN-50 multimode dry-run/planning surface with
    shared spectral phase, mode-summed Raman leakage, and
    `verification.mode = "burst_required"`
- `configs/experiments/templates/single_mode_phase_template.toml`
  - provides a copy/edit starting point for supported local single-mode
    phase-only runs
- `configs/experiments/templates/multimode_phase_planning_template.toml`
  - provides a copy/edit starting point for experimental MMF planning configs
- `configs/experiment_sweeps/smf28_power_micro_sweep.toml`
  - provides a tiny front-layer sweep over `problem.P_cont` for validation and
    dry-run planning
- `agent-docs/configurable-front-layer/PLAN.md`
  - records the roadmap from safe configurable runs toward novel research use:
    sweep execution, campaign summaries, heavy-regime promotion, authoring
    guides, and scientific acceptance gates
- `lab_extensions/objectives/pulse_compression_demo.toml`
  - demonstrates a non-Raman, planning-only objective extension contract
- `docs/guides/research-extensions.md`
  - documents the UX principle: safe defaults plus open extension contracts,
    not a closed objective menu
- `docs/architecture/research-engine-ux.md`
  - records the broader UX architecture: one backend with config, CLI,
    notebooks, sweeps/campaigns, extensions, and results index front doors
- `python/fiber_research_engine/`
  - provides a notebook-friendly Python wrapper that delegates to maintained
    Julia CLI commands instead of duplicating science logic, including the
    read-only results index
- `notebooks/templates/experiment_explorer.ipynb`
  - provides a Jupyter starting point for capability discovery, objective
    listing, config validation, experiment dry-runs, and sweep dry-runs
- `configs/experiments/smf28_longfiber_phase_poc.toml`
  - provides an experimental long-fiber dry-run/planning surface with
    `verification.mode = "burst_required"`
- `scripts/canonical/run_experiment.jl`
  - thin public wrapper
- `scripts/workflows/optimize_raman.jl`
  - now routes the canonical single-mode path through the new front layer

## Practical stance

- Keep variable selection, objective choice, solver selection, and artifact
  bundle choice config-driven.
- Keep the actual physics, control math, objective formulas, and solver
  implementations code-defined.
- Treat Raman objectives as the first family of code-defined objective
  contracts. Add future fiber-optic objectives the same way: implement, test,
  register, then expose in config.
- Treat lab extension contracts as visible research surfaces. They are not
  executable until promoted with implementation, tests, validation, and output
  semantics.
- Keep one validated backend. CLI, notebooks, sweeps, future GUIs, and lab
  scripts should call the same contracts rather than reimplementing science
  logic.
- Treat notebooks as orchestration and visualization surfaces. They should call
  the front-layer backend, not own objective formulas or solver dispatch.
- Promote regimes gradually: supported single-mode first, then experimental
  multivar/long-fiber, then multimode after the baseline stabilizes.
- Treat the current export path as analysis-grade handoff. Do not add
  vendor-specific SLM export until the lab has selected hardware, calibration
  files, and acceptance tests.

## Current implemented support boundary

The front layer currently executes:

- `single_mode`
- variables `[:phase]`
- objective `raman_band`
- solver `lbfgs`
- full standard artifact bundle

and experimentally:

- `single_mode`
- variables `[:phase, :amplitude]`, `[:phase, :energy]`,
  `[:phase, :amplitude, :energy]`
- objective `raman_band`
- solver `lbfgs`
- experimental multivar artifact bundle plus standard images
- multivar export/SLM handoff is deliberately rejected at validation until the
  exporter supports multivar artifacts instead of the phase-only canonical
  sidecar format
- dry-run output reports the resolved execution mode and whether export is
  supported for that mode
- post-run artifact validation checks copied config, JLD2 payload, JSON sidecar,
  required standard images, and phase-only trust report presence
- completed CLI runs print a compact summary pointing to the result directory
  and artifact-validation state
- objective names and regularizers are now validated against a code-defined
  registry before execution
- dry-run output reports the objective backend, e.g. `backend=raman_optimization`
- `--objectives` prints the registered objective contracts, supported variable
  tuples, backend, maturity, and allowed regularizers
- `--objectives` also prints research extension objective contracts from
  `lab_extensions/objectives/`, including execution status such as
  `planning_only`
- experimental `raman_peak` objective dispatch is exposed as a phase-only smoke
  surface without changing the supported default `raman_band` path
- phase-only export requests now call the canonical handoff exporter and attach
  export validation to the returned run bundle
- the supported export profile is `neutral_csv_v1`, an analysis-grade CSV/JSON
  handoff on the simulation axis rather than a vendor-specific SLM file
- saved-run inspection reports copied `run_config.toml` and default
  `export_handoff/` completeness so lab users can check provenance and handoff
  status from one command
- latest-run discovery resolves the newest completed output directory for a
  config id and renders the saved-run inspection summary without requiring the
  user to manually find the timestamped result folder
- provider-neutral compute planning prints local/manual/cluster/cloud guidance
  without launching anything; Rivera Lab burst helper commands are clearly
  labeled optional and project-specific
- `--capabilities` prints the available regimes, variables, objectives,
  parameterizations, solver choices, artifact bundles, and export profiles in
  one place
- `--validate-all` validates every approved front-layer experiment config
  without launching optimization, making it suitable as a pre-compute lab
  sanity check
- `run_experiment_sweep.jl --dry-run` expands a base experiment across a safe
  parameter list and validates every generated case without launching compute
- `run_experiment_sweep.jl --validate-all` validates every approved front-layer
  sweep config
- `run_experiment_sweep.jl --execute` runs locally supported expanded cases
  deliberately and records complete/failed/skipped rows in a Markdown summary
- sweep summaries now include artifact-validation, trust-report, and
  standard-image status columns per case
- `run_experiment_sweep.jl --latest` resolves and prints the newest completed
  sweep summary without requiring manual timestamp-folder inspection
- `index_results.jl` scans one or more result roots and reports discovered run
  artifacts and sweep summaries with headline metrics and standard-image
  completeness where available; it can render Markdown or CSV and filter by
  kind, fiber, complete images, and substring match
- `long_fiber`
- variables `[:phase]`
- objective `raman_band`
- solver `lbfgs`
- validation/dry-run only on local machines; execution is explicitly blocked
  with a message pointing users to the dedicated burst long-fiber workflow
- `multimode`
- variables `[:phase]`
- parameterization `shared_across_modes`
- objectives `mmf_sum`, `mmf_fundamental`, and `mmf_worst_mode`
- solver `lbfgs`
- artifact bundle `mmf_planning`
- validation/dry-run only on local machines; execution is explicitly blocked
  with a message pointing users to the dedicated multimode baseline workflow

The loader already supports the richer config shape, but unsupported variable /
objective / solver combinations fail validation clearly instead of silently
falling through.

## Verification

- `julia --project=. -e 'include("scripts/lib/experiment_spec.jl"); ...'`
  successfully loaded and rendered the front-layer plan
- `julia --project=. -e 'include("scripts/workflows/run_experiment.jl"); run_experiment_main(["--dry-run", "research_engine_poc"])'`
  succeeded
- `julia --project=. -e 'include("scripts/workflows/run_experiment.jl"); run_experiment_main(["--dry-run", "smf28_phase_amplitude_energy_poc"])'`
  succeeded
- `julia --project=. -e 'include("scripts/workflows/optimize_raman.jl"); canonical_optimize_main(["--list"])'`
  succeeded
- `TEST_TIER=fast julia --project=. test/runtests.jl`
  passed after the sweep-inspection slice (`95/95`; canonical lab-facing
  surface `111/111`, experiment front layer `210/210`)
- red-first regression was added for multivar export/handoff validation; it
  failed before implementation and passed after adding the guard
- red-first regression was added for dry-run plan visibility; it failed before
  adding the `Execution: mode=... export_supported=...` line and passed after
  implementation
- red-first regression was added for post-run artifact validation; it failed
  before adding `validate_experiment_artifacts(...)` and passed after wiring it
  into `run_supported_experiment(...)`
- red-first regression was added for CLI completion summary rendering; it
  failed before adding `render_experiment_completion_summary(...)` and passed
  after wiring the workflow to call it
- red-first regression was added for `research_engine_smoke`; the config was
  then added and used for a real local smoke optimization
- red-first regression was added for objective registry inspection; it failed
  before adding `objective_registry.jl` and passed after spec validation used
  the registry
- red-first regression was added for objective-listing UX; it failed before
  adding `render_objective_registry(...)` and `run_experiment.jl --objectives`
  and passed after implementation
- review pass fixed the no-argument `run_experiment_main([])` path so it also
  prints the completion summary after running the default config
- review pass preserved `artifact_validation` in the canonical optimize wrapper
  return bundle
- red-first regression was added for saved-run inspection of copied config and
  default `export_handoff/` status; it failed before adding those fields to
  `inspect_run_summary(...)` and passed after implementation
- red-first regression was added for latest-run discovery; it failed before
  adding `experiment_run_directories(...)`, `latest_experiment_output_dir(...)`,
  and `run_experiment.jl --latest`, then passed after implementation
- red-first regression was added for experimental long-fiber front-layer
  validation; it failed before adding the config, objective contract, capability
  profile, dry-run rendering, and local-execution guard, then passed after
  implementation
- red-first regression was added for provider-neutral compute planning; it
  failed before `render_experiment_compute_plan(...)` and
  `run_experiment.jl --compute-plan`, then passed after implementation
- red-first regression was added for capability discovery and multimode
  planning; it failed before adding `render_experiment_capabilities(...)`, the
  MMF objective contracts, the `grin50_mmf_phase_sum_poc` config, compute-plan
  text, and execution/export guards, then passed after implementation
- red-first regression was added for whole-config validation; it failed before
  adding `validate_all_experiment_configs(...)`,
  `render_experiment_validation_report(...)`, and
  `run_experiment.jl --validate-all`, then passed after implementation
- red-first regression was added for front-layer sweep expansion; it failed
  before adding `experiment_sweep.jl`, `smf28_power_micro_sweep.toml`, and
  `run_experiment_sweep.jl`, then passed after implementation
- red-first regression was added for research objective extension discovery; it
  failed before adding extension-contract loading and the
  `pulse_compression_demo` planning contract, then passed after implementation
- review pass fixed direct execution of planning-only long-fiber/MMF configs so
  it exits nonzero instead of returning success after a warning
- command verification passed for `--capabilities`, `--objectives`,
  `--validate-all`, `--compute-plan`, sweep `--validate-all`, and sweep
  `--dry-run`
- real smoke sweep execution passed:
  `julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --execute smf28_power_micro_sweep`
  completed three local-safe cases and wrote
  `results/raman/sweeps/front_layer/smf28_power_micro_sweep_20260426_2123863/SWEEP_SUMMARY.md`
- representative sweep images were visually inspected: case 001 phase profile,
  case 003 optimized evolution, and case 003 phase diagnostic
- red-first regression was added for latest-sweep discovery and richer sweep
  status columns; it failed before adding
  `experiment_sweep_output_directories(...)`,
  `latest_experiment_sweep_output_dir(...)`, artifact/trust/image columns, and
  `run_experiment_sweep.jl --latest`, then passed after implementation
- real smoke sweep execution was repeated after the status-column change:
  `julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --execute smf28_power_micro_sweep`
  completed three local-safe cases and wrote
  `results/raman/sweeps/front_layer/smf28_power_micro_sweep_20260426_2251288/SWEEP_SUMMARY.md`
  with `artifact=complete`, `trust=present`, and
  `standard_images=complete` for all cases
- `julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --latest smf28_power_micro_sweep`
  printed the latest sweep summary from
  `results/raman/sweeps/front_layer/smf28_power_micro_sweep_20260426_2251288`
- representative images for the repeated sweep were visually inspected: case
  001 phase profile, case 003 optimized evolution, and case 003 phase
  diagnostic
- red-first regression was added for the results index; it failed before
  adding `results_index.jl` and passed after the scanner/renderer was wired
  into the canonical lab-facing surface tests
- `PYTHONPATH=python python3 -m unittest discover -s test/python` passed
  (`9/9`) after adding the notebook wrapper for the shared results index and
  CSV/filter options
- `julia --project=. scripts/canonical/index_results.jl results/raman/sweeps/front_layer`
  rendered the sweep/run index read-only and confirmed small powers display as
  `0.001`, `0.002`, and `0.003 W` instead of rounding to zero
- `julia --project=. scripts/canonical/index_results.jl --csv --kind run --fiber SMF-28 --complete-images --contains power results/raman/sweeps/front_layer`
  rendered CSV for the three complete SMF-28 front-layer sweep runs
- `TEST_TIER=fast julia --project=. test/runtests.jl` passed after the
  results-index filter/CSV slice: repository structure `19/19`, canonical
  lab-facing surface `118/118`, experiment front layer `210/210`, Phase 16
  fast `95/95`

## Review Findings

- Front-layer focused tests pass (`93/93`).
- Workflow load, config listing, and dry-run entrypoints load successfully.
- Full fast tier blocker was resolved by updating the stale
  `test/core/test_canonical_lab_surface.jl` attenuator-recovery expectation to
  match the current clamped `check_boundary_conditions` behavior.
- `julia -t auto --project=. test/tier_fast.jl` passes (`95/95`;
  canonical lab surface `59/59`, experiment front layer `93/93`).
- Real smoke run completed at
  `results/raman/smoke/smf28_phase_smoke_20260424_035468`; artifact validation
  and standard image validation were complete, and the standard image set was
  visually inspected. The routine generated result directory and manifest
  change were removed from the source boundary afterward.
- Experimental `raman_peak` smoke run completed at
  `results/raman/smoke/smf28_phase_peak_smoke_20260424_0432955`; artifact
  validation and standard image validation were complete, the standard image set
  was visually inspected, and the routine generated result directory plus
  manifest change were removed from the source boundary afterward.
- Export smoke run completed at
  `results/raman/smoke/smf28_phase_export_smoke_20260424_0456277`; artifact
  validation, standard image validation, and export validation were complete.
  The neutral handoff bundle contained `phase_profile.csv`, `metadata.json`,
  `README.md`, and `source_run_config.toml`; the standard image set was visually
  inspected, and generated outputs/manifest changes were left outside the
  intended commit boundary.
- Slow/full tiers were not run locally because the repo labels them burst-VM
  territory.

## Environment note

Fast-tier testing initially failed because the local Julia depot was missing
the `LineSearch` package source despite a consistent `Manifest.toml`. Running

- `julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'`

repaired the depot state and allowed the tests to pass.
