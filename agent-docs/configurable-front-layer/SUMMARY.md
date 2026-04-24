# Configurable Front-Layer Summary

## Outcome

Added both:

- a human-facing architecture proposal and TOML schema sketch
- the first working implementation slice of the front layer

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
- `scripts/lib/experiment_runner.jl`
  - maps validated specs onto the existing `run_optimization(...)` and
    `run_multivar_optimization(...)` paths
  - validates completed run artifacts and attaches the validation report to the
    returned run bundle
  - renders the shared run-completion summary used by the CLI
- `scripts/workflows/run_experiment.jl`
  - supports `--list`
  - supports `--objectives`
  - supports `--dry-run`
  - runs one validated experiment config
  - prints output directory, artifact path, artifact-validation status, and
    standard-image status after a completed run
- `configs/experiments/README.md`
  - documents the safe researcher-facing knobs and current support boundary
- `configs/experiments/research_engine_smoke.toml`
  - provides a tiny phase-only smoke run for real CLI/artifact verification
- `configs/experiments/research_engine_export_smoke.toml`
  - provides a tiny phase-only smoke run for neutral CSV handoff verification
- `configs/experiments/research_engine_peak_smoke.toml`
  - provides a tiny phase-only smoke run for experimental objective dispatch
- `scripts/canonical/run_experiment.jl`
  - thin public wrapper
- `scripts/workflows/optimize_raman.jl`
  - now routes the canonical single-mode path through the new front layer

## Practical stance

- Keep variable selection, objective choice, solver selection, and artifact
  bundle choice config-driven.
- Keep the actual physics, control math, objective formulas, and solver
  implementations code-defined.
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
- experimental `raman_peak` objective dispatch is exposed as a phase-only smoke
  surface without changing the supported default `raman_band` path
- phase-only export requests now call the canonical handoff exporter and attach
  export validation to the returned run bundle
- the supported export profile is `neutral_csv_v1`, an analysis-grade CSV/JSON
  handoff on the simulation axis rather than a vendor-specific SLM file

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
  passed (`95/95`)
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
