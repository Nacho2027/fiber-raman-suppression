# Supported Workflows

[← docs index](../README.md) · [project README](../../README.md)

This file defines the first honest supported surface for the repository.

## Supported now

The maintained lab-facing surface is intentionally narrow:

- approved **single-mode, phase-only** Raman optimization runs through
  `scripts/canonical/optimize_raman.jl`
- approved sweeps through `scripts/canonical/run_sweep.jl`
- saved-run inspection through `scripts/canonical/inspect_run.jl`
- experiment-facing export bundles through `scripts/canonical/export_run.jl`

Approved run and sweep definitions live in:

- `configs/runs/*.toml`
- `configs/sweeps/*.toml`

List them with:

```bash
julia --project=. scripts/canonical/optimize_raman.jl --list
julia --project=. scripts/canonical/run_sweep.jl --list
```

## Supported usage pattern

Single run:

```bash
make optimize
# or explicitly:
julia --project=. -t auto scripts/canonical/optimize_raman.jl smf28_L2m_P0p2W
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
```

## Experimental, not first-line lab surface

These remain useful, but they are not part of the first supported lab contract:

- multimode workflows under `scripts/research/mmf/`
- long-fiber workflows under `scripts/research/longfiber/`
- multivariable optimization under `scripts/research/multivar/`
- trust-region / second-order / preconditioning workflows
- arbitrary notebook-authored optimization workflows
- phase-specific research drivers under `scripts/research/phases/`

Use those as research tools, not as the default interface for new lab users.

## Why this boundary exists

The repo contains more science than the first supported operational surface.
The goal is to give lab users a workflow that is:

- simple
- reproducible
- easy to inspect
- explicit about provenance

Promoting unstable research lanes too early would weaken trust in the part of
the repo that is already usable.
