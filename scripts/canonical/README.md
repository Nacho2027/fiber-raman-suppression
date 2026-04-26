# Canonical Scripts

This directory is the supported command-line surface for the repository.

These scripts are the ones that `README.md`, `docs/`, and `Makefile` should
point readers toward first.

## Canonical entry points

- `optimize_raman.jl` — run one approved canonical single-mode Raman optimization
- `run_experiment.jl` — run one front-layer experiment config (single-mode phase-only slice currently implemented)
- `run_sweep.jl` — run one approved sweep workflow
- `inspect_run.jl` — inspect one saved run bundle
- `export_run.jl` — export one saved run as an experiment-facing handoff bundle
- `refine_amp_on_phase.jl` — optional experimental second-stage amplitude-on-phase refinement
- `generate_reports.jl` — regenerate sweep reports and presentation figures
- `regenerate_standard_images.jl` — backfill the mandatory standard image set
- `validate_results.jl` — run result-validation checks

Approved run and sweep definitions live in `configs/runs/*.toml` and
`configs/sweeps/*.toml`. Use `--list` on `optimize_raman.jl` or `run_sweep.jl`
to see the maintained ids.

## Implementation note

These entry points are thin wrappers over implementation files in
`scripts/workflows/` and shared helpers in `scripts/lib/`.

If you are deciding where to edit behavior, prefer changing the implementation
layers rather than growing logic directly in this directory. See
[`../../docs/architecture/repo-navigation.md`](../../docs/architecture/repo-navigation.md) for the full
boundary map.
