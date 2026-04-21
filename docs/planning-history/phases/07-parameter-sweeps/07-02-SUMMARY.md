---
phase: 07-parameter-sweeps
plan: 02
subsystem: sweep-infrastructure
tags:
  - parameter-sweep
  - visualization
  - heatmap
  - multi-start
  - run_sweep

dependency_graph:
  requires:
    - "07-01"  # do_plots kwarg, recommended_time_window SPM fix, nt_for_window
    - "05-01"  # JLD2 + JSON3 result serialization (jldsave, manifest)
    - "06-01"  # compute_soliton_number in visualization.jl
  provides:
    - "scripts/run_sweep.jl"            # full sweep entry point for Plan 03
    - "plot_sweep_heatmap in visualization.jl"
    - "plot_multistart_histogram in visualization.jl"
  affects:
    - "07-03"  # Plan 03 executes the sweep by calling julia scripts/run_sweep.jl

tech_stack:
  added: []
  patterns:
    - "SW_ prefix for constants in sweep script (avoids Julia const redefinition in REPL)"
    - "try-catch per sweep point — ODE crashes recorded as NaN, sweep continues"
    - "adaptive Nt via nt_for_window(recommended_time_window(...))"
    - "photon drift check via compute_photon_drift post-run, flags window_limited >5%"
    - "pcolormesh(P_vals, L_vals, J_grid) — center-coordinate heatmap with N contour overlay"
    - "N contour lines are vertical in L×P heatmap (N depends only on P, not L)"

key_files:
  created:
    - scripts/run_sweep.jl
  modified:
    - scripts/visualization.jl

decisions:
  - "SW_ prefix for all constants in run_sweep.jl to prevent Julia const redefinition errors when script is re-included in REPL"
  - "safety_factor=3.0 when phi_NL>20 (higher-order effects undermine first-order SPM estimate)"
  - "N contour lines are vertical in L×P heatmap — N=sqrt(γP_peak T₀²/|β₂|) is independent of L (Research Pitfall 1)"
  - "β_order=3 passed to all run_optimization calls — required when betas has 2 elements (Phase 4 decision)"
  - "try-catch wraps both inner sweep loop body and multistart start loop — catches ODE NaN crashes gracefully"
  - "include() uses @__DIR__ paths — ensures correct resolution when script is run from any working directory"

metrics:
  duration_seconds: 217
  completed_date: "2026-03-25"
  tasks_completed: 2
  files_created: 1
  files_modified: 1
---

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
