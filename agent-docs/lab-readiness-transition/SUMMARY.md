# Lab-Readiness Transition Summary

## Outcome

Implemented the first narrow lab-facing productization pass around the earlier
proposal.

## What was implemented

- truthful canonical single-run wrapper:
  `scripts/canonical/optimize_raman.jl` now targets
  `scripts/workflows/optimize_raman.jl` instead of inheriting the heavy
  multi-run suite from `scripts/lib/raman_optimization.jl`
- fixed canonical sweep wrapper:
  `scripts/canonical/run_sweep.jl` now targets a real `run_sweep_main(...)`
  entry point instead of calling an undefined `main()`
- approved config/spec layer:
  `configs/runs/*.toml`, `configs/sweeps/*.toml`, and
  `scripts/lib/canonical_runs.jl`
- inspect/export flows:
  `scripts/canonical/{inspect_run,export_run}.jl`,
  `scripts/workflows/{inspect_run,export_run}.jl`, and
  `scripts/lib/run_artifacts.jl`
- supported-surface docs:
  `docs/guides/supported-workflows.md` plus updates to the main README and
  quickstart guides
- regression coverage:
  `test/core/test_canonical_lab_surface.jl` added to the fast tier

## Boundary that remains

The repo is still not "fully lab-ready" across every research lane. The
supported surface is now explicitly the narrow one:

- approved single-mode, phase-only canonical runs
- approved sweeps
- saved-run inspection
- export/handoff bundle generation

Multimode, long-fiber, multivar, and advanced optimizer research remain outside
that first supported contract.

## Tests

Ran:

- `TEST_TIER=fast julia --project=. test/runtests.jl`
- `julia --project=. scripts/canonical/optimize_raman.jl --list`
- `julia --project=. scripts/canonical/run_sweep.jl --list`
