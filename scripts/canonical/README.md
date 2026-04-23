# Canonical Scripts

This directory is the supported command-line surface for the repository.

These scripts are the ones that `README.md`, `docs/`, and `Makefile` should
point readers toward first.

## Canonical entry points

- `optimize_raman.jl` — run the canonical single-mode Raman optimization
- `run_sweep.jl` — run the supported `(L, P)` sweep workflow
- `generate_reports.jl` — regenerate sweep reports and presentation figures
- `regenerate_standard_images.jl` — backfill the mandatory standard image set
- `validate_results.jl` — run result-validation checks

## Implementation note

These entry points are thin wrappers over implementation files in
`scripts/workflows/` and shared helpers in `scripts/lib/`.
