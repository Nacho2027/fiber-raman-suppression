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
- `scripts/lib/variable_registry.jl`
  - defines the code-owned optimized-variable contracts, units,
    parameterizations, maturity, and artifact semantics for the current support
    boundary
  - discovers metadata-only lab variable extension contracts from
    `lab_extensions/variables/*.toml`
- `scripts/lib/control_layout.jl`
  - renders active controls as physical optimizer-vector blocks with units,
    bounds, shapes, and artifact hooks
- `scripts/lib/artifact_plan.jl`
  - combines regime, objective, and variable artifact hooks into an inspectable
    output plan with default view rules and future config override keys
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
  - supports `--variables`
  - supports `--validate-variables`
  - supports `--control-layout`
  - supports `--artifact-plan`
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
- `run_experiment.jl --validate-objectives`
  - validates objective extension metadata and reports promotion blockers
    before any extension can be treated as executable
- `scripts/canonical/scaffold_objective.jl`
  - creates a planning-only objective extension TOML and Julia cost/gradient
    stub with overwrite protection
- `scripts/canonical/scaffold_variable.jl`
  - creates a planning-only variable extension TOML and Julia build/projection
    stub with overwrite protection
- `lab_extensions/variables/mode_weights_demo.toml`
  - demonstrates a multimode, planning-only optimized-variable contract for
    future modal-weight research
- `docs/guides/research-extensions.md`
  - documents the UX principle: safe defaults plus open extension contracts,
    not a closed objective menu
- `docs/guides/exploratory-physics-workflow.md`
  - explains the intended lab workflow for existing science, new objectives,
    new variables, graph selection, and plot defaults in plain language
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
- Treat future variables the same way as future objectives: make units, bounds,
  projection behavior, compatible objectives, and artifacts explicit before
  execution.
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
- `--validate-objectives` reports objective-extension metadata validity and
  promotion blockers. The current `pulse_compression_demo` contract is valid
  metadata but not promotion-ready because it remains planning-only, uses the
  lab-extension backend, has research maturity, and declares unmet validation
  requirements.
- `scaffold_objective.jl` gives researchers a safe starting point for a new
  objective without copying boilerplate by hand. Generated objectives remain
  planning-only until explicitly promoted with implementation, tests, and
  output semantics.
- `--variables` prints built-in optimized-variable contracts and planning-only
  research variable extensions.
- `--validate-variables` reports variable-extension metadata validity and
  promotion blockers. The current `mode_weights_demo` contract is valid
  metadata but not promotion-ready because it remains planning-only, uses the
  lab-extension backend, has research maturity, and declares unmet validation
  requirements.
- `scaffold_variable.jl` gives researchers a safe starting point for a new
  optimized control without editing deep internals. Generated variables remain
  planning-only until units, bounds/projection behavior, objective
  compatibility, artifact semantics, implementation, and tests are promoted.
- `--control-layout` reports the active optimized variables as inspectable
  physical blocks, including units, bounds, shape, optimizer representation,
  and variable-specific artifact hooks.
- `--artifact-plan` reports the combined regime/objective/variable output
  contract, including required plots/metrics, default view rules, override
  keys, and whether each hook is implemented or still planned.
- Multivariable runs now write the current variable-specific artifact hooks:
  amplitude mask/shaped spectrum diagnostic PNG, energy metrics JSON, and pulse
  metrics JSON.
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
  deliberately and records complete/failed/skipped rows in Markdown, JSON, and
  CSV summaries
- sweep summaries now include artifact-validation, trust-report, and
  standard-image status columns per case
- `run_experiment_sweep.jl --latest` resolves and prints the newest completed
  sweep summary without requiring manual timestamp-folder inspection
- `index_results.jl` scans one or more result roots and reports discovered run
  artifacts and sweep summaries with headline metrics and standard-image
  completeness where available; it can render Markdown or CSV and filter by
  kind, config id, regime, objective, fiber, complete images, and substring
  match
- result-index rows now include ledger metadata when available: config id,
  regime, objective kind, variables, solver kind, timestamp, trust report path,
  run config path, and artifact path
- result-index comparison mode ranks run artifacts by mechanical lab readiness
  and then objective value for meeting-sized shortlists
- sweep-comparison mode prefers completed `SWEEP_SUMMARY.json` sidecars and
  falls back to Markdown tables for older sweeps; it ranks campaigns by best
  achieved case while keeping case counts and failure counts visible
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
  (`11/11`) after adding the notebook wrapper for the shared results index,
  CSV/filter options, run comparison mode, and sweep comparison mode
- `julia -t auto --project=. scripts/canonical/index_results.jl results/raman/sweeps/front_layer`
  rendered the sweep/run index read-only and confirmed small powers display as
  `0.001`, `0.002`, and `0.003 W` instead of rounding to zero
- `julia -t auto --project=. scripts/canonical/index_results.jl --csv --kind run --fiber SMF-28 --complete-images --contains power results/raman/sweeps/front_layer`
  rendered CSV for the three complete SMF-28 front-layer sweep runs
- `julia -t auto --project=. scripts/canonical/index_results.jl --csv --kind run --regime single_mode --objective raman_band --fiber SMF-28 --complete-images --contains power results/raman/sweeps/front_layer`
  rendered enriched ledger CSV with config id, regime, objective, variables,
  solver, timestamp, trust report, run config, and artifact paths
- `julia -t auto --project=. scripts/canonical/index_results.jl --compare --top 2 --kind run --config-id smf28_phase_smoke --regime single_mode --objective raman_band --fiber SMF-28 --lab-ready results/raman/sweeps/front_layer`
  rendered a ranked comparison table for the top two mechanically lab-ready
  front-layer sweep runs
- `julia -t auto --project=. scripts/canonical/index_results.jl --compare-sweeps --top 5 results/raman/sweeps/front_layer`
  rendered a sweep comparison table from completed front-layer sweep summaries,
  including case counts, failures, best case, best objective, and median
  objective
- `julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --execute smf28_power_micro_sweep`
  was repeated after adding sidecars and wrote `SWEEP_SUMMARY.md`,
  `SWEEP_SUMMARY.json`, and `SWEEP_SUMMARY.csv` under
  `results/raman/sweeps/front_layer/smf28_power_micro_sweep_20260426_2352316`
- `julia -t auto --project=. scripts/canonical/index_results.jl --compare-sweeps --top 3 results/raman/sweeps/front_layer --contains 2352316`
  ranked the fresh sweep from `SWEEP_SUMMARY.json`
- red-first regression was added for objective-extension promotion validation;
  it failed before `validate_objective_extension_contracts(...)` and
  `run_experiment.jl --validate-objectives`, then passed after implementation
- `julia --project=. scripts/canonical/run_experiment.jl --validate-objectives`
  reports one valid metadata contract, zero invalid contracts, and zero
  promotion-ready contracts for the current planning-only
  `pulse_compression_demo`
- `PYTHONPATH=python python3 -m unittest discover -s test/python` passed
  (`13/13`) after exposing objective-extension validation and objective
  scaffolding to notebooks
- `julia --project=. scripts/canonical/scaffold_objective.jl cli_smoke_objective --dir <tmp> --description "CLI smoke objective."`
  created a planning-only TOML contract and Julia stub in a temporary
  directory, with no real lab objective files left behind
- `TEST_TIER=fast julia -t auto --project=. test/runtests.jl` passed after the
  objective-scaffold slice: repository structure `19/19`, canonical
  lab-facing surface `150/150`, experiment front layer `251/251`, Phase 16
  fast `95/95`
- Routine sweep output generated by the final full fast-tier verification under
  timestamp `20260426_2352316` was removed from the source boundary afterward,
  and `results/raman/manifest.json` no longer contains that timestamp. The
  preexisting/shared front-layer sweep output under timestamp
  `20260426_2123863` was left in place.
- `jq empty results/raman/manifest.json` passed after cleanup.
- Regression coverage was added for variable-extension discovery, validation,
  and scaffolding through `variable_registry.jl`,
  `run_experiment.jl --variables`, `run_experiment.jl --validate-variables`,
  and `scaffold_variable.jl`.
- `julia --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_experiment_front_layer.jl")'`
  passed after the variable-extension slice (`289/289`).
- `PYTHONPATH=python python3 -m unittest discover -s test/python` passed
  after exposing variable listing, validation, and scaffolding to notebooks
  (`16/16`).
- `julia --project=. scripts/canonical/run_experiment.jl --validate-all`
  passed after variable-contract validation was wired into experiment
  validation (`7/7` approved experiment configs).
- `julia --project=. scripts/canonical/run_experiment.jl --variables` and
  `julia --project=. scripts/canonical/run_experiment.jl --validate-variables`
  passed; the current `mode_weights_demo` variable extension is valid metadata
  and not promotion-ready.
- `julia --project=. scripts/canonical/scaffold_variable.jl cli_smoke_variable --dir <tmp> --description "CLI smoke variable." --units normalized --bounds "box constrained"`
  created a planning-only TOML contract and Julia stub in a temporary
  directory, with no real lab variable files left behind.
- `TEST_TIER=fast julia -t auto --project=. test/runtests.jl` passed after the
  variable-extension slice: repository structure `19/19`, canonical
  lab-facing surface `150/150`, experiment front layer `289/289`, experiment
  sweep sidecars `13/13`, Phase 16 fast `95/95`.
- Regression coverage was added for control-layout inspection and artifact-plan
  inspection through `control_layout.jl`, `artifact_plan.jl`,
  `run_experiment.jl --control-layout`, and
  `run_experiment.jl --artifact-plan`.
- `julia --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_experiment_front_layer.jl")'`
  passed after the control/artifact planning slice (`325/325`).
- `PYTHONPATH=python python3 -m unittest discover -s test/python` passed
  after exposing control-layout and artifact-plan inspection to notebooks
  (`21/21`).
- `julia --project=. scripts/canonical/run_experiment.jl --control-layout research_engine_poc`
  printed the phase control block with optimizer length `8192`, units `rad`,
  bounds, and phase/group-delay artifact hooks.
- `julia --project=. scripts/canonical/run_experiment.jl --artifact-plan research_engine_poc`
  printed an implemented artifact plan for the supported Raman phase path.
- `julia --project=. scripts/canonical/run_experiment.jl --artifact-plan smf28_phase_amplitude_energy_poc`
  now prints `implemented_now=true`; the multivariable plan includes
  `amplitude_mask`, `shaped_input_spectrum`, `energy_throughput`,
  `energy_scale`, and `peak_power` as implemented hooks and no longer advertises
  a phase-only `trust_report` hook for that run mode.
- `julia --project=. scripts/canonical/run_experiment.jl --dry-run research_engine_poc`
  now includes `Control layout: ...` and `Artifact plan: ...` summary lines.
- `julia --project=. scripts/canonical/run_experiment.jl --validate-all`,
  `--validate-objectives`, and `--validate-variables` passed after adding
  artifact-hook metadata.
- `TEST_TIER=fast julia -t auto --project=. test/runtests.jl` passed after the
  control/artifact planning slice: repository structure `19/19`, canonical
  lab-facing surface `177/177`, experiment front layer `325/325`, experiment
  sweep sidecars `13/13`, Phase 16 fast `95/95`.
- Post-test cleanup check found no `20260427` front-layer sweep output
  directories. Existing `results/raman/manifest.json` entries for
  `smf28_phase_export_smoke_20260427_0034806` and
  `smf28_phase_export_smoke_20260427_0419457` were preexisting/shared smoke
  outputs and were left untouched.
- Regression coverage was added for `write_multivar_variable_artifacts(...)`
  with a synthetic multivariable run bundle. The test verifies generation of
  `{tag}_amplitude_mask.png`, `{tag}_energy_metrics.json`, and
  `{tag}_pulse_metrics.json`, including JSON schema markers and energy-scale
  values.
- Verification after wiring the multivariable artifact writer:
  `julia --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_experiment_front_layer.jl")'`
  passed (`335/335`),
  `PYTHONPATH=python python3 -m unittest discover -s test/python` passed
  (`21/21`),
  `julia --project=. scripts/canonical/run_experiment.jl --validate-all`
  passed (`7/7`), and
  `TEST_TIER=fast julia -t auto --project=. test/runtests.jl` passed with
  repository structure `19/19`, canonical lab-facing surface `177/177`,
  experiment front layer `335/335`, experiment sweep sidecars `13/13`, and
  Phase 16 fast `95/95`.
- Post-verification hygiene checks found no new `20260427` front-layer sweep
  directories, `results/raman/manifest.json` parsed with `jq empty`, and
  temporary scaffold names did not appear in `results/raman` or
  `lab_extensions`.
- Artifact validation now checks implemented non-core artifact hooks from the
  artifact plan. For the phase/amplitude/energy surface this means the
  validator blocks missing `{tag}_amplitude_mask.png`,
  `{tag}_energy_metrics.json`, or `{tag}_pulse_metrics.json`, while standard
  images and phase-only trust reports remain handled by the existing core
  checks.
- The read-only results index now exposes variable-artifact completeness,
  hook names, artifact paths, and missing-artifact paths. It also supports
  multivariable `_slm.json` sidecars and direct JLD2 summary fallback for
  multivar artifacts that were not written through `MultiModeNoise.save_run`.
- The lab-user guide now documents that multivariable variable-specific outputs
  are part of mechanical artifact validation and appear in the results index.
- Verification after adding artifact validation and indexing:
  `julia --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_experiment_front_layer.jl")'`
  passed (`343/343`),
  `julia --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_canonical_lab_surface.jl")'`
  passed (`199/199`),
  `PYTHONPATH=python python3 -m unittest discover -s test/python` passed
  (`21/21`),
  `julia --project=. scripts/canonical/run_experiment.jl --validate-all`
  passed (`7/7`), and
  `TEST_TIER=fast julia -t auto --project=. test/runtests.jl` passed with
  repository structure `19/19`, canonical lab-facing surface `199/199`,
  experiment front layer `343/343`, experiment sweep sidecars `13/13`, and
  Phase 16 fast `95/95`.
- Post-verification hygiene checks again found no new `20260427` front-layer
  sweep directories, `results/raman/manifest.json` parsed with `jq empty`, and
  temporary scaffold names did not appear in `results/raman` or
  `lab_extensions`.
- The strict `lab_ready.jl` run gate now uses the same run config and artifact
  plan semantics as validation/indexing. Trust reports are required only when
  the artifact plan requests `:trust_report`, multivariable `_slm.json`
  sidecars satisfy the sidecar requirement, and missing variable artifacts add
  the `missing_variable_artifacts` blocker.
- Canonical lab-facing regression coverage now checks a complete synthetic
  phase/amplitude/energy run passes `lab_ready_run_report(...)` without a trust
  report, and that deleting `{tag}_pulse_metrics.json` fails the gate with
  `missing_variable_artifacts`.
- Verification after wiring lab-ready variable-artifact gates:
  `julia --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_canonical_lab_surface.jl")'`
  passed (`211/211`),
  `julia --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_experiment_front_layer.jl")'`
  passed (`343/343`),
  `PYTHONPATH=python python3 -m unittest discover -s test/python` passed
  (`21/21`),
  `julia --project=. scripts/canonical/run_experiment.jl --validate-all`
  passed (`7/7`),
  `julia --project=. scripts/canonical/lab_ready.jl --config smf28_phase_amplitude_energy_poc`
  passed, and `TEST_TIER=fast julia -t auto --project=. test/runtests.jl`
  passed with repository structure `19/19`, canonical lab-facing surface
  `211/211`, experiment front layer `343/343`, experiment sweep sidecars
  `13/13`, and Phase 16 fast `95/95`.
- Post-verification hygiene checks again found no new `20260427` front-layer
  sweep directories, `results/raman/manifest.json` parsed with `jq empty`, and
  temporary scaffold names did not appear in `results/raman` or
  `lab_extensions`.
- A standalone simulation-free research-engine acceptance harness now lives at
  `test/core/test_research_engine_acceptance.jl` and is included in the fast
  tier. It validates the public instrument workflow end-to-end using a
  synthetic completed supported phase/export run: config validation, dry-run,
  control layout, artifact plan, export bundle validation, artifact validation,
  results index, lab-ready gate, comparison ranking, and black-box gating for
  experimental multivariable, long-fiber, and MMF surfaces.
- `make acceptance` now runs the research-engine acceptance harness plus the
  Python wrapper tests with `PYTHONPATH=python`, giving a single preflight
  simulation-free command.
- Verification after adding the acceptance harness:
  `julia --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_research_engine_acceptance.jl")'`
  passed (`44/44`), `make acceptance` passed with Julia acceptance `44/44`
  and Python wrappers `21/21`, and
  `TEST_TIER=fast julia -t auto --project=. test/runtests.jl` passed with
  repository structure `19/19`, canonical lab-facing surface `211/211`,
  experiment front layer `343/343`, experiment sweep sidecars `13/13`,
  research-engine acceptance `44/44`, and Phase 16 fast `95/95`.
- Post-verification hygiene checks found no new `20260427` front-layer sweep
  directories, `results/raman/manifest.json` parsed with `jq empty`, and
  temporary scaffold names did not appear in `results/raman` or
  `lab_extensions`.
- Lab readiness was separated from ad hoc presentation readiness in
  `docs/guides/lab-readiness.md`. The guide defines presentation-ready, locally
  lab-ready, smoke lab-ready, milestone lab-ready, and research-promoted
  states, including explicit promotion requirements for multivariable, MMF,
  long-fiber, objective-extension, and variable-extension surfaces.
- `make lab-ready` now runs the local lab-readiness gate: tool checks,
  `make acceptance`, experiment config validation, sweep config validation,
  `lab_ready --config research_engine_export_smoke`, and the full fast Julia
  tier. The target explicitly tells users that real generated artifact checks
  still require `make golden-smoke`, and milestone physics/numerics closure
  still requires `make test-slow` or `make test-full` on appropriate compute.
- Verification after adding the lab-ready gate:
  `make lab-ready` passed. The target included research-engine acceptance
  `44/44`, Python wrappers `21/21`, experiment config validation `7/7`, sweep
  config validation `1/1`, `lab_ready --config research_engine_export_smoke`
  `PASS`, and the fast Julia tier with repository structure `19/19`,
  canonical lab-facing surface `211/211`, experiment front layer `343/343`,
  experiment sweep sidecars `13/13`, research-engine acceptance `44/44`, and
  Phase 16 fast `95/95`.
- Post-verification hygiene checks found no new `20260427` front-layer sweep
  directories, `results/raman/manifest.json` parsed with `jq empty`, and
  temporary scaffold names did not appear in `results/raman` or
  `lab_extensions`.
- Config validation was tightened so unsafe numeric knobs fail before
  execution: positive/finite checks now cover `time_window`, `L_fiber`,
  `P_cont`, pulse settings, and solver tolerance; `beta_order` and
  `max_iter` must be positive; regularizer names must match the selected
  objective contract; and regularizer weights must be nonnegative finite
  numbers or `"auto"`.
- A simulation-free adversarial config suite was added at
  `test/core/test_experiment_config_adversarial.jl` and wired into the fast
  tier. It mutates real approved TOML configs in temporary directories to
  exercise unsafe numeric knobs, objective/variable mismatches, unsupported
  solvers/grid policies/parameterizations, export mistakes, artifact-policy
  mistakes, multivar limitations, and long-fiber/MMF planning gates.
- Verification after adding adversarial config coverage:
  `julia -t auto --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_experiment_config_adversarial.jl")'`
  passed (`150/150`), and
  `TEST_TIER=fast julia -t auto --project=. test/runtests.jl` passed with
  repository structure `19/19`, canonical lab-facing surface `211/211`,
  experiment front layer `343/343`, experiment sweep sidecars `13/13`,
  research-engine acceptance `44/44`, adversarial config coverage `150/150`,
  and Phase 16 fast `95/95`.
- Sweep validation was tightened so approved sweep files fail closed before
  case generation: maturity must be `supported` or `experimental`, values must
  be nonempty, labels must match values and be nonempty/unique, execution mode
  must remain `dry_run`, and `require_validate_all` must remain true.
- A simulation-free adversarial sweep suite was added at
  `test/core/test_experiment_sweep_adversarial.jl` and wired into the fast
  tier. It mutates real approved sweep TOML configs to exercise metadata
  mistakes, unsupported sweep axes, generated invalid experiment cases, bad
  objective choices, and planning-only long-fiber sweep execution behavior.
- Verification after adding adversarial sweep coverage:
  `julia -t auto --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_experiment_sweep_adversarial.jl")'`
  passed (`41/41`),
  `julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --validate-all`
  passed (`1/1`), and
  `TEST_TIER=fast julia -t auto --project=. test/runtests.jl` passed with
  repository structure `19/19`, canonical lab-facing surface `211/211`,
  experiment front layer `343/343`, experiment sweep sidecars `13/13`,
  research-engine acceptance `44/44`, adversarial config coverage `150/150`,
  adversarial sweep coverage `41/41`, and Phase 16 fast `95/95`.
- The lab-readiness guide now includes finite exit criteria for the current
  front-layer phase to avoid endless incremental hardening: `make lab-ready`,
  `make golden-smoke`, visual inspection of the generated standard image set,
  export validation, adversarial config/sweep tests in the fast tier, and
  honest support-boundary docs.
- Real smoke verification passed with
  `make golden-smoke`. The generated run was
  `results/raman/smoke/smf28_phase_export_smoke_20260428_0233503`.
  `lab_ready --latest research_engine_export_smoke --require-export` reported
  `PASS`, complete standard images, complete export handoff, valid phase CSV
  with `1024` rows, `converged=true`, `quality=EXCELLENT`,
  `J_after_dB=-45.96354646844482`, and
  `delta_J_dB=-0.0006783608010181297`.
- The real smoke standard image set was visually inspected:
  `opt_phase_profile.png`, `opt_evolution.png`,
  `opt_phase_diagnostic.png`, and `opt_evolution_unshaped.png`. The images
  rendered coherently for a tiny one-iteration smoke run: before/after spectra
  overlap as expected, evolution plots are smooth, phase diagnostics are finite,
  and the Raman marker/export path is present. This is mechanical lab-path
  verification, not a scientific improvement claim.
- Research-extension integration was hardened without touching active multivar,
  long-fiber, or MMF execution lanes. The objective validator now recognizes
  planning-only objective extensions referenced from config and rejects them
  with explicit promotion blockers instead of reporting a generic unknown
  objective. The experiment validator now does the same for planning-only
  variable extensions.
- Added `lab_extensions/variables/gain_tilt_demo.toml` and
  `gain_tilt_demo.jl` as a single-mode non-standard control contract for a
  smooth spectral gain/attenuation tilt. It is metadata-valid and
  planning-only, with explicit units, bounds/projection expectations,
  compatible objectives, artifact hooks, and validation requirements.
- Added `test/core/test_research_extension_integration.jl` and wired it into
  the fast tier. The test verifies that `pulse_compression_demo` and
  `gain_tilt_demo` are discoverable, metadata-valid, not promotable, and
  blocked from execution with `not promoted for execution` diagnostics when
  referenced from a temporary config.
- Verification after adding research-extension integration:
  `julia -t auto --project=. -e 'using Test; const _ROOT = pwd(); include("test/core/test_research_extension_integration.jl")'`
  passed (`25/25`),
  `TEST_TIER=fast julia -t auto --project=. test/runtests.jl` passed with
  research-extension integration `25/25`, and `make lab-ready` passed
  end-to-end with objective extensions `1/1` valid metadata, variable
  extensions `2/2` valid metadata, and zero promotion-ready extensions.

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

## 2026-04-28 Policy Closure Update

- Added first-class `controls.policy` parsing and validation to the experiment
  spec so configs distinguish naive direct multivar from staged workflows.
  Defaults are `direct` for single-mode, `fresh` for long-fiber, and
  `planning` for multimode.
- Added optional `controls.policy_options` for workflow-specific knobs. The
  first promoted use is staged `amp_on_phase` refinement with `phase_iter`,
  `amp_iter`, `delta_bound`, and `threshold_db`.
- Added `configs/experiments/smf28_amp_on_phase_refinement_poc.toml` as the
  staged multivar planning config. It is deliberately validation/dry-run only
  in the front layer and points users to
  `scripts/canonical/refine_amp_on_phase.jl` from the compute plan.
- Long-fiber compute plans now emit the actual `LF100_*` command derived from
  config values instead of a generic script call. This records the production
  parameters needed for burst/cluster execution while keeping local front-layer
  execution blocked.
- Direct-joint multivar remains available through
  `smf28_phase_amplitude_energy_poc`, but the policy split now makes clear that
  current scientific evidence favors staged `amp_on_phase` rather than cold
  direct phase/amplitude/energy optimization.
- Verification for this policy update: `run_experiment --validate-all` passed
  (`9/9` configs), staged multivar dry-run and compute-plan rendering passed,
  long-fiber compute-plan rendering passed, `test_experiment_front_layer.jl`
  passed (`361/361`), and `test_experiment_config_adversarial.jl` passed
  (`168/168`).

## 2026-04-28 Non-Raman Executable Smoke

- Added experimental built-in objective `temporal_width` for single-mode,
  phase-only optimization. It minimizes a normalized temporal second moment and
  is selected by config through `objective.kind = "temporal_width"`.
- Added `configs/experiments/research_engine_temporal_width_smoke.toml` as the
  successful non-Raman smoke path. It uses the existing single-mode phase
  backend, but the cost dispatch, objective registry, artifact plan, and plot
  labels are objective-aware.
- Added front-layer solver tolerance fields `solver.f_abstol` and
  `solver.g_abstol`. They are validated as positive finite values or `auto`
  and passed through to the phase optimizer when supplied.
- Added `test/core/test_non_raman_objective_integration.jl` and wired it into
  the fast tier. The test checks registry/config/run-kwargs plumbing and
  finite-difference agreement for the temporal-width gradient.
- Latest successful run:
  `results/raman/smoke/smf28_phase_temporal_width_smoke_20260428_0322735`.
  It completed artifact validation and the standard image set. Objective
  summary: temporal width changed from `0.94308` (`-0.3 dB`) to `0.30550`
  (`-5.1 dB`), `Delta = -4.9 dB`, boundary input/output were OK, and photon
  drift was `9.77e-15`.
- Visual inspection: the four standard images were opened. The phase-profile
  plot now reports temporal-width metrics rather than Raman leakage; the
  standalone phase diagnostic suppresses Raman-onset markers for non-Raman
  objectives; optimized and unshaped evolution waterfalls render.
- Promotion status: executable smoke, not lab-promoted science. The explicit
  `lab_ready --latest research_engine_temporal_width_smoke` check fails only on
  `not_converged`, because the smoke stops at `max_iter=10`. This is an honest
  boundary: the example proves non-Raman configurability and artifacts, but not
  final convergence-quality science.
- Verification after this slice: non-Raman integration passed (`26/26`),
  adversarial config coverage passed (`172/172`), `run_experiment
  --validate-all` passed (`9/9`), temporal-width dry-run rendered correctly,
  and `make lab-ready` passed for the supported front-layer surface.

## 2026-04-28 `fiberlab` Front Door

- Added checkout-local `./fiberlab` as the researcher-facing CLI for the
  configurable research engine. It is intentionally thin: Python parses lab
  commands, then delegates to the maintained Julia scripts for validation,
  solver dispatch, physics, and artifacts.
- Added installable console-script metadata:
  `fiberlab = "fiber_research_engine.app:main"`.
- Added Python wrapper coverage for latest experiment inspection, sweep
  execution/latest inspection, and compute-plan rendering.
- Added `python/fiber_research_engine/app.py` commands for configs,
  capabilities, validation, dry-run planning, execution, latest-run inspection,
  control layout, artifact plan, provider-neutral compute plan, objective and
  variable registries, lab-ready gates, sweeps, result indexing, and
  planning-only objective/variable scaffolds.
- Updated `README.md`, `docs/guides/configurable-experiments.md`,
  `docs/guides/research-extensions.md`, and `configs/experiments/README.md`
  so lab users see `./fiberlab ...` first instead of raw
  `julia -t auto --project=...` commands.
- Verified no-compute front-door behavior:
  `./fiberlab --help`, `./fiberlab plan research_engine_temporal_width_smoke`,
  `./fiberlab sweep plan smf28_power_micro_sweep`,
  `./fiberlab objectives --validate`, `./fiberlab variables --validate`,
  `./fiberlab compute-plan smf28_longfiber_phase_poc`, and
  `./fiberlab validate` all passed.
- Full local readiness verification after this slice: Python wrapper tests
  passed (`33/33`), `make acceptance` passed, and `make lab-ready` passed.
  The lab-ready gate included experiment config validation (`9/9`), sweep
  validation (`1/1`), fast-tier Julia tests, research-extension integration
  (`25/25`), and non-Raman objective integration (`26/26`).

## 2026-04-28 Gain-Tilt Variable Smoke

- Added experimental built-in variable `gain_tilt` for single-mode
  multivariable execution. It is deliberately narrow: one unconstrained scalar
  maps to a bounded smooth spectral transmission tilt
  `A(omega)=1+delta*tanh(x)*normalized_frequency`.
- Left `gain_tilt_demo` under `lab_extensions/variables/` as the planning-only
  research contract. The executable smoke path is the built-in
  `gain_tilt`, selected from config with
  `controls.variables = ["phase", "gain_tilt"]`.
- Added `configs/experiments/research_engine_gain_tilt_smoke.toml` as a tiny
  phase-plus-gain-tilt smoke config. It uses the experimental multivar artifact
  bundle and writes variable-specific artifacts.
- Extended the multivar backend with a scalar `gain_tilt` optimizer block,
  bounded amplitude mapping, chain-rule gradients through Raman, boundary, and
  energy regularizer terms, payload fields for `gain_tilt_opt`, and linear
  `J_after` persistence so latest-run inspection works for log-cost multivar
  runs.
- Added implemented artifact hook `gain_tilt_profile`, which materializes as
  `opt_gain_tilt_profile.png`; energy-throughput metrics are written to
  `opt_energy_metrics.json`.
- Fixed two integration defects found by the first executable smoke attempts:
  the multivar runner is now loaded at runner include time instead of being
  dynamically called from an older Julia world, and multivar accepts front-layer
  solver/objective kwargs without passing unsupported keys into setup.
- Verification: red-first `test_gain_tilt_variable_integration.jl` initially
  failed because `gain_tilt` was not registered. After implementation it passed
  (`36/36`), `test_experiment_front_layer.jl` passed (`361/361`),
  adversarial config coverage passed (`181/181`), and `./fiberlab validate`
  passed (`10/10` configs, `1/1` sweeps).
- Real smoke run completed at
  `results/raman/smoke/smf28_phase_gain_tilt_smoke_20260428_1446573`.
  Artifact validation, latest-run inspection, and run-level lab-ready gate all
  passed. Metrics: `J_before=-45.9629 dB`, `J_after=-45.9651 dB`,
  `Delta=-0.0023 dB`, converged `true`, iterations `2`, `A in [0.998, 1.002]`.
  This is executable smoke evidence, not lab-promoted science.
- Visual inspection: the gain-tilt profile plot and the four standard images
  rendered without obvious corruption. The plot shows the bounded tilt and
  shaped/unshaped input spectrum overlay; the standard profile/diagnostic and
  optimized/unshaped evolution plots render.
- Full readiness recheck exposed and fixed a portable-infrastructure issue:
  macOS `/usr/bin/time` does not support GNU `-v`, so
  `scripts/ops/run_with_telemetry.sh` now detects verbose-time support before
  wrapping a command and otherwise records sampled telemetry without changing
  the command exit code. The repo-structure telemetry smoke now passes on macOS.
- Final verification after the telemetry portability fix: direct telemetry
  wrapper smoke returned `rc=0`, repository-structure tests passed (`28/28`),
  and `make lab-ready` passed. The lab-ready gate included acceptance harness
  (`44/44`), Python wrapper tests (`33/33`), config validation (`10/10`),
  sweep validation (`1/1`), front-layer tests (`361/361`), adversarial config
  coverage (`181/181`), adversarial sweep coverage (`41/41`), extension
  integration (`25/25`), non-Raman integration (`26/26`), gain-tilt variable
  integration (`36/36`), and fast-tier tests (`95/95`).

## 2026-04-28 Regime Promotion Status Contract

- Added `experiment_promotion_status(spec)` so every front-layer config reports
  a conservative stage: `planning`, `smoke`, `validated`, or `lab_ready`.
- Dry-run plans and compute plans now print `Promotion stage` and
  `Promotion blockers`. This prevents a validated/dry-runnable MMF or
  long-fiber config from looking like a promoted local execution path.
- Current staged status:
  - supported single-mode phase/export configs report `lab_ready`;
  - direct experimental single-mode multivariable configs report `smoke`;
  - staged `amp_on_phase`, long-fiber, and MMF configs report `planning`.
- Typical blockers are explicit and machine-readable, including
  `experimental_maturity`, `burst_required`, `front_layer_execution_blocked`,
  `dedicated_workflow_only`, `unimplemented_artifacts`, `no_local_smoke`,
  `no_trust_report`, `no_manifest_update`, and `no_export_handoff`.
- Updated `./fiberlab capabilities` output and human docs so lab users can tell
  the difference between "config validates", "small smoke is executable", and
  "this is lab-ready for another researcher".
- Added fast-tier regression test
  `test/core/test_regime_promotion_status.jl`, including standalone include
  behavior and assertions for phase-only, direct multivar, staged multivar,
  long-fiber, MMF, plan rendering, compute-plan rendering, and capabilities.
- Verification: red-first status test failed before implementation, then passed
  (`36/36`). Targeted checks passed: front-layer (`361/361`), acceptance
  harness (`44/44`), adversarial config coverage (`181/181`),
  `run_experiment --validate-all` (`10/10` configs), Python wrapper tests
  (`33/33`), direct `./fiberlab plan`/`compute-plan`/`capabilities` smoke, and
  final `make lab-ready`.

## 2026-04-28 Playground `explore` Lane

- Added the first explicit playground lane: `fiberlab explore`.
  - `./fiberlab explore plan <config>` renders the normal experiment plan plus
    an explore-run policy.
  - `./fiberlab explore run <config> --local-smoke` intentionally runs
    executable experimental local-smoke configs.
  - `./fiberlab explore run <config> --heavy-ok --dry-run` renders the guarded
    compute plan for heavy/dedicated workflows such as MMF, long-fiber, and
    staged multivar.
- Kept `fiberlab run` conservative. Experimental configs now have a clear
  research path without being mislabeled lab-ready.
- Added backend policy `experiment_explore_run_policy(spec; local_smoke,
  heavy_ok)` with explicit actions, blockers, and warnings. Current policy:
  - executable experimental front-layer configs require `--local-smoke`;
  - MMF, long-fiber, and staged `amp_on_phase` require `--heavy-ok`;
  - heavy/dedicated launch is not automated yet; `--dry-run` prints the compute
    plan.
- Added Julia CLI flags:
  - `--explore-plan [spec]`;
  - `--explore-run [--local-smoke] [--heavy-ok] [--dry-run] spec`.
- Added Python/Jupyter helpers `explore_plan(...)` and `explore_run(...)`, plus
  `fiberlab explore plan/run` argparse coverage.
- Updated `docs/guides/configurable-experiments.md`,
  `docs/guides/exploratory-physics-workflow.md`,
  `docs/architecture/research-engine-ux.md`, and
  `configs/experiments/README.md` around the core distinction:
  `run = supported/lab-facing`, `explore = experimental playground`.
- Verification:
  - Red-first Python tests failed until `explore_plan` / `explore_run` and the
    `explore` command group existed.
  - Red-first Julia front-layer tests failed until `--explore-plan` /
    `--explore-run` existed.
  - Python wrapper tests passed (`35/35`).
  - Front-layer tests passed (`368/368`).
  - Regime promotion status tests passed (`56/56`).
  - Direct CLI dry-run checks passed for gain-tilt and MMF explore paths.
  - Refusal check passed: `./fiberlab explore run research_engine_gain_tilt_smoke`
    fails without `--local-smoke`.
  - Real explore smoke passed:
    `./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke`
    wrote `results/raman/smoke/smf28_phase_gain_tilt_smoke_20260428_161110`.
    Artifact validation passed, standard images passed, variable artifacts
    passed, `./fiberlab latest` passed, and `./fiberlab ready run ...` passed.
  - Visual inspection: opened the phase profile, phase diagnostic, optimized
    evolution, unshaped evolution, and gain-tilt profile for the new explore run;
    plots rendered without obvious corruption.
  - Final `make lab-ready` passed.

## 2026-04-28 Explore Discovery And Comparison

- Made `explore` more first-class for future researchers:
  - `./fiberlab explore list` lists configs from the playground lane.
  - `./fiberlab explore compare [roots...]` delegates to the shared result
    index with `--compare`, including filters such as `--objective`,
    `--contains`, `--complete-images`, and `--top`.
- Added notebook/Python helpers `explore_list(...)` and
  `explore_compare(...)` so CLI and Jupyter users share the same backend.
- Updated the README and front-layer docs to show `explore` as the starting
  path for novel fiber-optic inverse-design work, with `run`/`ready` kept as
  the conservative reference lane.
- Verification:
  - Red-first Python tests failed until `explore_list` / `explore_compare` and
    the corresponding argparse commands existed.
  - Targeted Python routing tests passed (`36/36`).
  - Full Python wrapper/app suite passed (`36/36`).
  - Direct `./fiberlab explore list` passed and listed supported plus
    experimental configs.
  - Direct `./fiberlab explore compare results/raman/smoke --top 5` passed and
    rendered a ranked comparison table from completed smoke results.
  - Final `make lab-ready` passed.

## 2026-04-28 Research `check config` Surface

- Replaced the proposed researcher-facing `promote check` concept with a plainer
  no-compute completeness check:
  - `./fiberlab check config <config>`;
  - backend `run_experiment.jl --check [spec]`;
  - Python/Jupyter helper `check_config(...)`.
- The report answers practical lab questions:
  - whether config validation passes;
  - which run path to use (`run`, `explore --local-smoke`, or
    `explore --heavy-ok --dry-run`);
  - whether the artifact plan is implemented;
  - whether saved metadata should be comparison-ready;
  - which concrete pieces are still missing.
- Kept `check run` and `check latest` as aliases over the existing completed-run
  lab-readiness checks so users have one obvious verb for pre-run and post-run
  inspection.
- Verification:
  - Red-first Julia test failed until `research_config_check_report` existed.
  - Red-first Python tests failed until `check_config` and `fiberlab check`
    existed.
  - Front-layer Julia test passed (`386/386`).
  - Targeted Python routing tests passed (`38/38`).

## 2026-04-28 Per-Run Playground Manifest

- Added `run_manifest.json` writing for new front-layer runs. This is the
  lightweight lab-notebook record for the playground, not a new physics layer.
- Manifest fields include:
  - schema/version and generation time;
  - run context (`run` or `explore_local_smoke`) and user-facing command;
  - output/artifact/sidecar paths;
  - config id, copied config path, and config SHA-256;
  - regime, fiber/pulse/grid parameters, variables, objective, solver;
  - pre-run check status and missing pieces;
  - artifact validation status, standard-image status, variable-artifact status;
  - export-handoff status;
  - key metrics from the saved artifact when readable;
  - lightweight git provenance with tracked-file dirty state.
- Threaded manifest command context through `run_experiment.jl` so exploratory
  smokes record `./fiberlab explore run ... --local-smoke` rather than looking
  like ordinary supported runs.
- Kept git provenance fast by avoiding untracked-file scanning, since `results/`
  can be large and dirty during research.
- Verification:
  - Red-first Julia test failed until `experiment_run_manifest_data` and
    `write_experiment_run_manifest` existed.
  - Front-layer Julia test passed (`395/395`).
  - Python wrapper/app tests passed (`38/38`).
  - Real exploratory smoke passed:
    `./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke`.
  - The run wrote
    `results/raman/smoke/smf28_phase_gain_tilt_smoke_20260428_1735311/run_manifest.json`.
  - Manifest inspection confirmed schema `run_manifest_v1`, context
    `explore_local_smoke`, variables `phase,gain_tilt`, objective `raman_band`,
    artifact completion, standard-image completion, variable-artifact completion,
    and `J_after_dB=-45.96512756899307`.
  - `./fiberlab check run` on the new run passed.
  - Visual inspection opened the full standard image set plus gain-tilt profile;
    images rendered without obvious corruption.

## 2026-04-28 Manifest-Backed Result Comparison

- Taught the read-only results index to read optional `run_manifest.json`
  metadata next to result artifacts.
- Added manifest fields to run rows:
  - `run_context`;
  - user-facing command;
  - compare-ready status;
  - missing handoff items;
  - manifest path/schema.
- Updated `fiberlab explore compare` / result comparison rendering to show
  `Run Context`, `Compare Ready`, and `Manifest Missing` columns in Markdown
  and CSV output.
- Kept old result folders compatible: runs without a manifest still index and
  compare with blank manifest fields.
- Verification:
  - Red-first canonical-surface tests failed until manifest metadata was parsed,
    searchable, and rendered.
  - Canonical lab-facing surface passed (`220/220`).
  - Research-engine acceptance harness passed (`44/44`).
  - Experiment front-layer tests passed (`395/395`).
  - Python wrapper/app tests passed (`38/38`).
  - Real CLI check passed:
    `./fiberlab explore compare results/raman/smoke --contains smf28_phase_gain_tilt_smoke_20260428_1735311 --top 1`,
    showing `explore_local_smoke`, `Compare Ready=false`, and the manifest's
    missing handoff items.

## 2026-04-28 Generic Exploratory Artifact Fallback

- Added generic fallback artifact hooks for executable experimental configs:
  `exploratory_summary` and `exploratory_overview`.
- New artifacts:
  - `{tag}_explore_summary.json`;
  - `{tag}_explore_overview.png`.
- The overview provides a first-inspection plot with input/shaped spectra,
  zoomed temporal pulse, objective trace when stored, and active control
  summary. It is intentionally a fallback, not a replacement for explicit
  physics-specific diagnostics.
- The writer loads saved phase-only artifacts when needed, so phase-only
  exploratory runs show the actual optimized phase and convergence history, not
  just the pre-run bundle state.
- Wired the writer into front-layer phase-only and multivar execution before
  artifact validation, making the fallback part of the mechanical artifact
  contract for experimental executable runs.
- Verification:
  - Red-first front-layer tests failed until the artifact hooks and writer
    existed.
  - Experiment front-layer tests passed (`412/412`).
  - Canonical lab-facing surface passed (`220/220`).
  - Gain-tilt variable integration passed (`38/38`).
  - Research-engine acceptance passed (`44/44`).
  - Real non-Raman exploratory smoke passed:
    `./fiberlab explore run research_engine_temporal_width_smoke --local-smoke`.
  - The run wrote and validated
    `results/raman/smoke/smf28_phase_temporal_width_smoke_20260428_2122978/opt_explore_summary.json`
    and `opt_explore_overview.png`.
  - Summary inspection confirmed schema `exploratory_artifacts_v1`, objective
    `temporal_width`, variable `phase`, 11 trace points, and a finite zoom
    window.
  - Visual inspection opened `opt_explore_overview.png`; spectrum, temporal
    pulse, objective trace, and phase summary rendered without obvious
    corruption.
  - `./fiberlab check run` on that smoke correctly failed only on
    `not_converged`; artifact validation itself was complete.

## 2026-04-28 Bounded Scalar Search Playground Slice

- Added the first low-dimensional derivative-free exploratory backend:
  `solver.kind = "bounded_scalar"` for `controls.variables = ["gain_tilt"]`.
- Added `configs/experiments/research_engine_gain_tilt_scalar_search_smoke.toml`
  as a local smoke config for gain-tilt-only bounded search.
- Extended the single-mode `raman_band` objective contract and capability
  profile to admit `(:gain_tilt,)`.
- Added front-layer solver fields `scalar_lower`, `scalar_upper`, and
  `scalar_x_tol`, with validation that rejects unordered bounds and prevents
  `bounded_scalar` from being used for full-grid phase/gain-tilt tuples.
- Implemented the scalar backend with `Optim.Brent` over the physical gain-tilt
  slope, while reusing the existing multivar cost evaluation and artifact
  writers. The saved output is still explicit: JLD2 payload, `_slm.json`
  sidecar, standard images, gain-tilt profile, energy metrics, exploratory
  summary/overview, and run manifest.
- Fixed the generic exploratory temporal plot convention so the fallback
  overview keeps temporal pulses centered for saved input fields.
- Verification:
  - Red-first gain-tilt and adversarial tests failed until the config,
    objective support, bounded scalar solver validation, and run kwargs existed.
  - Gain-tilt variable integration passed (`46/46`).
  - Experiment config adversarial coverage passed (`194/194`).
  - Experiment front-layer tests passed (`432/432`).
  - Real scalar-search smoke passed:
    `./fiberlab explore run research_engine_gain_tilt_scalar_search_smoke --local-smoke`.
  - Latest verified output:
    `results/raman/smoke/smf28_gain_tilt_scalar_search_smoke_20260428_2149975`.
  - Artifact validation reported complete standard images and variable
    artifacts. Summary inspection confirmed schema `exploratory_artifacts_v1`,
    variable `gain_tilt`, solver `bounded_scalar`, 9 trace points, and optimized
    gain tilt about `0.0876`.
  - Visual inspection opened the full standard image set, gain-tilt profile, and
    corrected exploratory overview. The overview temporal pulse is centered and
    the objective trace/control summary render correctly.
  - `./fiberlab explore compare` found the run with context
    `explore_local_smoke` and complete variable artifacts.
  - `./fiberlab check run` correctly failed only on `not_converged`, which is
    expected for this experimental smoke and not an artifact-completeness
    failure.

## 2026-04-28 Exploratory Plot Override Slice

- Added a thin config-driven plotting contract for exploratory overview
  artifacts:
  - `[plots.temporal_pulse] time_range`, `normalize`, `energy_low`,
    `energy_high`, and `margin_fraction`;
  - `[plots.spectrum] dynamic_range_dB`.
- The overrides affect only `{tag}_explore_overview.png` and the plot metadata
  recorded in `{tag}_explore_summary.json`; they do not alter the simulation,
  objective, or optimizer.
- Added validation so unsafe plot config fails before compute, including
  reversed manual temporal ranges.
- Updated the gain-tilt scalar-search smoke config to demonstrate a manual
  temporal range and 55 dB overview spectrum.
- Verification:
  - Red-first front-layer and adversarial tests failed until `spec.plots`,
    plot validation, summary metadata, and overview rendering support existed.
  - Experiment front-layer tests passed (`439/439`).
  - Experiment config adversarial coverage passed (`196/196`).
