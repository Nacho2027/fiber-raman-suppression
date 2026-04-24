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
- `scripts/lib/experiment_runner.jl`
  - maps validated specs onto the existing `run_optimization(...)` and
    `run_multivar_optimization(...)` paths
  - validates completed run artifacts and attaches the validation report to the
    returned run bundle
  - renders the shared run-completion summary used by the CLI
- `scripts/workflows/run_experiment.jl`
  - supports `--list`
  - supports `--dry-run`
  - runs one validated experiment config
  - prints output directory, artifact path, artifact-validation status, and
    standard-image status after a completed run
- `configs/experiments/README.md`
  - documents the safe researcher-facing knobs and current support boundary
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
- Treat the current export path as analysis-grade handoff, then add explicit
  device-grade export profiles for actual SLM loading.

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

## Environment note

Fast-tier testing initially failed because the local Julia depot was missing
the `LineSearch` package source despite a consistent `Manifest.toml`. Running

- `julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'`

repaired the depot state and allowed the tests to pass.
