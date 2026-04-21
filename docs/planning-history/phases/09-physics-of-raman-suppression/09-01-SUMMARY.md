---
phase: 09-physics-of-raman-suppression
plan: 01
subsystem: phase-decomposition
tags:
  - physics-analysis
  - polynomial-decomposition
  - cross-sweep
  - clustering
  - residual-psd

key_files:
  created:
    - scripts/phase_analysis.jl
  modified: []

decisions:
  - "Vandermonde normalized to [-1,1] before fitting (checker warning #1)"
  - "Interpolations.jl LinearInterpolation for cross-correlation on heterogeneous Nt grids"
  - "Order-6 polynomial max; factorial(k) divisor in Vandermonde basis"

metrics:
  completed_date: "2026-04-02"
  tasks_completed: 2
  files_created: 1
  figures_generated: 10
---

# Phase 9 Plan 01: Phase Decomposition & Cross-Sweep Structural Analysis — Summary

**One-liner:** Extended polynomial decomposition (orders 2-6) of all 34 phi_opt profiles reveals phase structure is fundamentally non-polynomial (10.2% mean explained variance), with weak clustering by soliton number and multiple distinct solution basins.

## Key Physics Results

### H1: Polynomial Basis Decomposition
- **Order 6 explains only 10.2% of variance on average** (max 29.8% for one HNLF point)
- GDD+TOD alone: ~1% (confirming Phase 6.1 finding)
- Adding FOD and higher orders helps marginally but never exceeds 30%
- **Verdict: Polynomial chirp is insufficient** — the optimizer uses intrinsically non-polynomial phase

### H2: Residual PSD Analysis
- Residual PSD computed for all 24 sweep points with 77 fs Raman marker
- Structure is present (not white noise) but no clear universal peak at 77 fs
- PSD shape varies across configurations

### H4: Cross-Sweep Clustering
- 24x24 correlation matrix computed
- **Best grouping: N_sol > 2** (within-between gap = 0.193)
- Fiber type grouping also shows structure but weaker
- L and P groupings less predictive

### H6: Multi-Start Comparison
- 10 multi-start profiles at L=2m, P=0.20W, N=2.6
- **Mean pairwise correlation: 0.109** — very low
- **Verdict: MULTIPLE BASINS** — the optimization landscape has distinct solution families
- Different starts find structurally different solutions achieving similar suppression depths

## Figures Generated

| # | File | Content |
|---|------|---------|
| 01 | physics_09_01_explained_variance_vs_order.png | Polynomial order 2-6, split SMF-28/HNLF |
| 02 | physics_09_02_gdd_tod_vs_params.png | GDD/TOD vs L, P, N (2x3 grid) |
| 03 | physics_09_03_residual_psd_waterfall.png | Residual PSD waterfall with 77 fs marker |
| 04 | physics_09_04_phi_overlay_all_sweep.png | All 24 normalized phi_opt overlaid |
| 05 | physics_09_05_decomposition_detail.png | Best/worst order-6 fits |
| 06 | physics_09_06_correlation_matrix.png | 24x24 pairwise correlation heatmap |
| 07 | physics_09_07_similarity_by_grouping.png | Within vs between group correlation |
| 08 | physics_09_08_multistart_overlay.png | 10 multi-start profiles with inset |
| 09 | physics_09_09_phase_by_regime.png | 2x2 colored by N_sol, L, delta_dB, fiber |
| 10 | physics_09_10_coefficient_scaling.png | Polynomial coefficients vs L/L_D and N |

## Deviations from Plan

1. Generator expression syntax fix: `count(p -> ... for i in ...)` replaced with `count(i -> ..., 1:n)` (Julia syntax)
2. PSD frequency axis: `fftfreq(N, d_omega)` corrected to `fftfreq(N, 1.0/d_omega)` with unit conversion to fs

## Self-Check: PASSED
All 10 PNG files exist in results/images/ with physics_09_0{1-10} prefix.
