# T02: 07-parameter-sweeps 02

**Slice:** S04 — **Milestone:** M002

## Description

Create the complete sweep script (run_sweep.jl) and visualization functions (plot_sweep_heatmap, plot_multistart_histogram) that implement the 36-point L x P grid sweep for both fiber types and the 10-start multi-start robustness analysis.

Purpose: This is the code-writing plan. It creates all the infrastructure needed to run the sweeps. Actual execution happens in Plan 03 (separating code creation from the ~1.5 hour compute run avoids context overflow from execution output).

Output: scripts/run_sweep.jl (complete, executable), updated scripts/visualization.jl with heatmap and histogram functions.

## Must-Haves

- [ ] "A complete run_sweep.jl script exists that can execute the full 36-point L x P grid and 10-start multi-start analysis"
- [ ] "plot_sweep_heatmap() produces inferno-colormap heatmaps with N contour lines, X markers for non-converged, and triangle markers for window-limited points"
- [ ] "plot_multistart_histogram() visualizes the distribution of J_final across multi-start runs"
- [ ] "Each sweep point includes photon number drift check per D-01"
- [ ] "ODE solver crashes are caught and recorded as NaN/error, not allowed to abort the sweep"

## Files

- `scripts/run_sweep.jl`
- `scripts/visualization.jl`
