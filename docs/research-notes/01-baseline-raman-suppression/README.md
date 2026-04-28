# Baseline Raman Suppression and Core Optimization Surface

- status: `established reference workflow`
- compiled note: `01-baseline-raman-suppression.pdf`
- evidence snapshot: `2026-04-26`

## Purpose

This is the front-door note for the research-note series. It explains the canonical single-mode phase-only Raman suppression setup, the objective surface, the adjoint-gradient optimizer, numerical trust gates, and the standard image vocabulary used by later notes.

## Primary Sources

- `README.md`
- `docs/architecture/cost-function-physics.md`
- `docs/architecture/cost-convention.md`
- `scripts/lib/common.jl`
- `scripts/lib/raman_optimization.jl`
- `scripts/lib/standard_images.jl`
- `scripts/lib/visualization.jl`
- `results/raman/smf28_L2m_P0p2W_20260424_040392/`

## Local Assets

- `figures/baseline_workflow_clean.png`
- `figures/baseline_cost_anatomy.png`
- `figures/baseline_before_after_summary.png`
- `figures/baseline_trust_snapshot.png`
- paired phase-diagnostic and evolution images for the no-optimization control, canonical shaped run, and HNLF reference run

## Quality Bar

The PDF should be readable as the first handout someone sees: no internal milestone labels, no unfinished-draft language, real run images, a control page, paired phase diagnostic plus heat map pages, proper citations, and a clean compile/render inspection.
