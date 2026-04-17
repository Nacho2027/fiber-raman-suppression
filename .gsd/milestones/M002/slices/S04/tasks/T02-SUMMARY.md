---
id: T02
parent: S04
milestone: M002
provides: []
requires: []
affects: []
key_files: []
key_decisions: []
patterns_established: []
observability_surfaces: []
drill_down_paths: []
duration: 
verification_result: passed
completed_at: 
blocker_discovered: false
---
# T02: 07-parameter-sweeps 02

**# Phase 7 Plan 02: Sweep Infrastructure Summary**

## What Happened

# Phase 7 Plan 02: Sweep Infrastructure Summary

**One-liner:** Inferno heatmap sweep infrastructure (plot_sweep_heatmap + run_sweep.jl) for 36-point L×P grid with photon-drift validation, adaptive Nt, and 10-start multi-start analysis on SMF-28.

## What Was Built

### Task 1: visualization.jl — Two New Functions

Added `plot_sweep_heatmap` and `plot_multistart_histogram` to `scripts/visualization.jl` inside the existing include guard.

**`plot_sweep_heatmap(sweep_results, fiber_name; save_path)`:**
- `pcolormesh` on (P_cont, L) axes with inferno colormap, J_final [dB]
- White N contour lines at levels [1.5, 2.0, 3.0, 5.0, 8.0] — vertical because N ∝ √P only
- White "X" markers (markersize=10) for non-converged points
- White triangle markers for window-limited points (photon drift >5%)
- 300 DPI, tight_layout, figsize=(8,6)

**`plot_multistart_histogram(multistart_results; save_path)`:**
- Left panel: histogram of J_final [dB] (8 bins)
- Right panel: scatter of J_final vs σ, color-coded green/red for convergence
- 300 DPI, tight_layout, figsize=(12,5)

### Task 2: scripts/run_sweep.jl — Complete Sweep Entry Point

Full sweep script following the `run_comparison.jl` structural pattern.

**Grid definitions:**
- SMF-28: `SW_SMF28_L = [0.5, 1.0, 2.0, 5.0, 10.0]` m × `SW_SMF28_P = [0.05, 0.10, 0.20, 0.30]` W = 20 points
- HNLF: `SW_HNLF_L = [0.5, 1.0, 2.0, 5.0]` m × `SW_HNLF_P = [0.005, 0.010, 0.030, 0.050]` W = 16 points
- Total: 36 points

**Key functions:**
- `compute_photon_number(uomega, sim)` — photon number from spectral field (copied from verification.jl, abs.(sim["ωs"]) pattern preserved)
- `compute_photon_drift(result, uω0, fiber, sim)` — re-propagates optimized field, returns drift %
- `compute_peak_power(P_cont)` — sech² peak power from average continuous power
- `run_fiber_sweep(fiber_label, gamma, betas, L_vals, P_vals)` — main sweep loop
- `save_sweep_aggregate(sweep_results, fiber_label)` — saves grid matrices to JLD2
- `run_multistart(; n_starts=10, max_iter=100)` — 10-start analysis on SMF-28 L=2m P=0.30W

**Safety features:**
- `try-catch` around each `run_optimization` call — ODE NaN crashes record J_after=NaN
- `GC.gc()` after every point to free ODE solution memory
- `validate=false` for all sweep calls (gradient validated in Phase 4)
- `do_plots=false` for all calls (suppresses 3 PNGs per point = 108+ files avoided)

**Multi-start (D-04):**
- `Random.seed!(42)` for reproducibility
- 10 starts: 1 zero-phase + 3×σ=0.1 + 3×σ=0.5 + 3×σ=1.0
- `max_iter=100` per start (Phase 6 showed 50 is insufficient for this config)

## Deviations from Plan

**1. [Rule 2 - Missing critical functionality] β_order=3 added to all run_optimization calls**
- Found during: Task 2 implementation
- Issue: setup_raman_problem enforces `length(betas_user) <= β_order - 1`; with `betas_user = [-2.17e-26, 1.2e-40]` (2 elements), β_order must be ≥ 3. The plan spec omitted this kwarg.
- Fix: Added `β_order=3` to all `run_optimization` calls in both `run_fiber_sweep` and `run_multistart`.
- Files modified: scripts/run_sweep.jl
- Commit: db6a201

**2. [Rule 2 - Missing critical functionality] @__DIR__ used for include() paths**
- Found during: Task 2 implementation
- Issue: Plain `include("common.jl")` fails when script is run from a directory other than `scripts/`. The plan spec showed unqualified includes.
- Fix: Used `include(joinpath(@__DIR__, "common.jl"))` etc. for all includes in run_sweep.jl.
- Files modified: scripts/run_sweep.jl
- Commit: db6a201

**3. [Rule 2 - Missing critical functionality] Error-safe contour plotting in plot_sweep_heatmap**
- Found during: Task 1 implementation
- Issue: `ax.contour()` throws if the N_grid has fewer than 2 distinct values (e.g., crashed runs produce NaN). Needed try-catch around contour call.
- Fix: Wrapped contour call in `try ... catch e @warn ... end`.
- Files modified: scripts/visualization.jl
- Commit: d459621

None of the deviations required architectural changes.

## Known Stubs

None — all functions are complete and wired. The sweep script will produce real output when executed in Plan 03.

## Self-Check

```
FOUND: scripts/run_sweep.jl
FOUND: scripts/visualization.jl (modified)
FOUND: commit d459621
FOUND: commit db6a201
```

## Self-Check: PASSED
