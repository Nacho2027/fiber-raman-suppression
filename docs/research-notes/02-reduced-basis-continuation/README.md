# Reduced-Basis Continuation and Basin Access

- status: `strong simulated result; portability and rerun packaging still open`
- evidence snapshot: `2026-04-28`
- output: `02-reduced-basis-continuation.pdf`

## Purpose

Explain why continuation through a structured reduced basis changes basin
access, not just interpretability.

## Evidence Included In The PDF

- independent-equation cross-check for \(\phi = Bc\) and
  \(\nabla_c F = B^\top \nabla_\phi F\)
- coefficient-space finite-difference verification recipe
- provenance map connecting copied note figures to the archived evidence
  bundles
- basis-family depth summary
- reduced-basis robustness/transferability tradeoff
- full-grid penalty scan
- standard phase-profile and evolution diagnostics for deep continuation,
  simple-transferable, zero-start full-grid, and continuation-seeded full-grid
  runs
- compact full-grid refinement comparison table
- explicit page-level provenance wording that avoids vague archive claims

## Main Claim

Reduced-basis continuation is an access mechanism, not just a compression
trick. The simulation still runs on the full grid, but the optimizer first
moves inside structured subspaces \(\phi = Bc\), then selected seeds are
refined on the full phase grid.

## Current Gap

The evidence is backed by saved local artifacts, copied standard images, and
sidecar tables, but the entire reduced-basis evidence chain is not yet packaged
as one clean public rerun command.

## Generated Tables

- `tables/full_grid_refinement_path_comparison.md`
- `tables/full_grid_refinement_path_comparison.csv`

## Figure Rule

Representative pages pair the phase diagnostic with the corresponding
spectral-evolution heat map on the same page. The first paired page is the
no-optimization control.
