# Recovery, Honest Grids, and Saddle Diagnostics

- status: `established with scoped limits`
- evidence snapshot: `2026-04-26`
- output: `10-recovery-validation.pdf`

## Purpose

This note explains how the project separates durable Raman-suppression results
from numerically suspect artifacts, then connects the surviving results to
local saddle geometry.

## Main Evidence

- Recovered SMF-28 single-mode anchor: `-66.61 dB`, edge fraction `8.10e-4`.
- Recovered HNLF single-mode anchor: `-86.68 dB`, edge fraction `2.24e-4`, but not a convergence claim.
- Validated 100 m lower bound: `-54.77 dB`, edge fraction `8.47e-6`, but not a convergence claim.
- Retired simple-control sweep: best recovered point was deep, but edge fraction stayed around `8.42e-2`.
- Saddle ladder: low-dimensional minimum-like point exists, but the competitive branch is indefinite.
- Negative-curvature escape improves depth modestly while still landing on saddle-like endpoints.

## Local Sources

- Recovery helper scripts under `scripts/research/recovery/`.
- Single-mode recovery summaries under the synced Raman results tree.
- Saddle-ladder and escape summaries under the synced Raman results tree.
- Standard images copied into `figures/` with outward-facing filenames.

## Figure Rule

Every representative result page pairs the phase diagnostic with the
corresponding spectral-evolution heat map on the same PDF page. The first
paired page is the no-optimization control.
