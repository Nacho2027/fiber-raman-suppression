# Supported Workflows

[← docs index](../README.md) · [project README](../../README.md)

This file defines the first honest supported surface for the repository.

## Supported now

The maintained lab-facing surface is intentionally narrow:

- approved **single-mode, phase-only** Raman optimization runs through
  `scripts/canonical/optimize_raman.jl`
- configurable experiment runs through `scripts/canonical/run_experiment.jl`
- approved sweeps through `scripts/canonical/run_sweep.jl`
- saved-run inspection through `scripts/canonical/inspect_run.jl`
- experiment-facing export bundles through `scripts/canonical/export_run.jl`

Approved run and sweep definitions live in:

- `configs/runs/*.toml`
- `configs/experiments/*.toml`
- `configs/sweeps/*.toml`

List them with:

```bash
julia --project=. scripts/canonical/optimize_raman.jl --list
julia --project=. scripts/canonical/run_experiment.jl --list
julia --project=. scripts/canonical/run_sweep.jl --list
```

## Supported usage pattern

Single run:

```bash
make optimize
# or explicitly:
julia --project=. -t auto scripts/canonical/optimize_raman.jl smf28_L2m_P0p2W
```

Configurable experiment:

```bash
julia --project=. -t auto scripts/canonical/run_experiment.jl --dry-run research_engine_poc
julia --project=. -t auto scripts/canonical/run_experiment.jl research_engine_poc
julia --project=. -t auto scripts/canonical/run_experiment.jl --latest research_engine_poc
```

Inspect a saved run:

```bash
julia --project=. scripts/canonical/inspect_run.jl results/raman/<run_id>/
```

Export an experimental handoff bundle:

```bash
julia --project=. scripts/canonical/export_run.jl results/raman/<run_id>/
```

Sweep:

```bash
julia --project=. -t auto scripts/canonical/run_sweep.jl smf28_hnlf_default
julia --project=. -t auto scripts/canonical/run_experiment_sweep.jl --latest smf28_power_micro_sweep
```

For substantial runs, record compute telemetry so future lab users can estimate
wall time and memory needs before launching similar work. See
[compute-telemetry.md](./compute-telemetry.md). Burst research lanes launched
through `scripts/ops/parallel_research_lane.sh` now record this automatically
under `results/telemetry/`.

## Minimum Lab-Ready Gate

A run is not lab-ready just because it produced a JLD2 file or PNGs. For the
supported single-run surface, acceptance requires:

- `scripts/canonical/inspect_run.jl <run_dir>` reports a complete standard
  image set
- `<prefix>_trust.md` reports overall `PASS`
- determinism, boundary, photon-number conservation, gradient validation, and
  cost-surface sections are all `PASS`
- the four standard images are visually inspected:
  `_phase_profile.png`, `_evolution.png`, `_phase_diagnostic.png`, and
  `_evolution_unshaped.png`
- an export bundle can be generated with `scripts/canonical/export_run.jl`

The primary lab baseline is `smf28_L2m_P0p2W`. It must additionally report
`converged=true` before being used as the reference baseline for lab handoff.

For the configurable front layer, use
[configurable-experiments.md](./configurable-experiments.md) as the operational
guide. Its supported path is currently single-mode phase-only. Multivariable
controls and `raman_peak` are explicitly experimental.

The `hnlf_L0p5m_P0p01W` config is an approved comparison/reference run. Its
trust report must still be `PASS`, but optimizer convergence is reported as a
separate status rather than hidden.

## Experimental, not first-line lab surface

These remain useful, but they are not part of the first supported lab contract:

- multimode workflows under `scripts/research/mmf/`
- long-fiber workflows under `scripts/research/longfiber/`
- multivariable optimization under `scripts/research/multivar/`
- trust-region / second-order / preconditioning workflows
- arbitrary notebook-authored optimization workflows
- phase-specific research drivers under `scripts/research/phases/`

Use those as research tools, not as the default interface for new lab users.

## Research Lane Status

Use this classification when deciding what blocks lab rollout:

- Multivariable optimization is research-closed for the current decision. The
  broad joint phase/amplitude/energy path should not become the default, but
  staged amp-on-phase refinement is a credible optional research workflow.
- Long-fiber is research-grade for the current 50-100 m single-mode story. It
  should be documented as an exploratory workflow, not a turnkey group platform.
- MMF is active and working as a qualified research path. The original
  unregularized positive result was boundary/window corrupted, but the newer
  boundary+GDD-regularized GRIN-50 result passes corrected temporal-edge checks
  and is presentation-ready as a constrained simulation finding. It still needs
  grid refinement, launch-composition sensitivity, and model-scope checks before
  it becomes paper-grade or lab-supported.

In practical terms: lab rollout should not wait on more multivar or long-fiber
science. It should keep the default supported workflow narrow. MMF can be shown
as a qualified research result, but not as the default lab handoff workflow.

## Why this boundary exists

The repo contains more science than the first supported operational surface.
The goal is to give lab users a workflow that is:

- simple
- reproducible
- easy to inspect
- explicit about provenance

Promoting unstable research lanes too early would weaken trust in the part of
the repo that is already usable.
