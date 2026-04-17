# S04: Parameter Sweeps

**Goal:** Fix the power-blind time window function and add sweep-mode support to run_optimization(), establishing the foundation for the parameter sweep phase.
**Demo:** Fix the power-blind time window function and add sweep-mode support to run_optimization(), establishing the foundation for the parameter sweep phase.

## Must-Haves


## Tasks

- [x] **T01: 07-parameter-sweeps 01** `est:35min`
  - Fix the power-blind time window function and add sweep-mode support to run_optimization(), establishing the foundation for the parameter sweep phase.

Purpose: Without SPM-aware time windows, high-power sweep points lose 38-49% photon energy to the attenuator, producing artificially low J values. Without do_plots=false, the 36-point sweep generates 108 PNGs and runs 36 extra ODE solves. These two fixes are critical prerequisites for all sweep work.

Output: Modified common.jl (SPM-corrected recommended_time_window + nt_for_window), modified raman_optimization.jl (do_plots kwarg), updated tests.
- [x] **T02: 07-parameter-sweeps 02**
  - Create the complete sweep script (run_sweep.jl) and visualization functions (plot_sweep_heatmap, plot_multistart_histogram) that implement the 36-point L x P grid sweep for both fiber types and the 10-start multi-start robustness analysis.

Purpose: This is the code-writing plan. It creates all the infrastructure needed to run the sweeps. Actual execution happens in Plan 03 (separating code creation from the ~1.5 hour compute run avoids context overflow from execution output).

Output: scripts/run_sweep.jl (complete, executable), updated scripts/visualization.jl with heatmap and histogram functions.
- [ ] **T03: 07-parameter-sweeps 03**
  - Execute the full parameter sweep (36 grid points + 10 multi-start runs) and verify the results with a visual checkpoint.

Purpose: This is the compute-heavy execution plan. The script from Plan 02 is run end-to-end, producing heatmaps, aggregate data, and multi-start analysis. Estimated wall time: 1-2 hours (per D-03, no time limit). The human checkpoint at the end confirms that heatmaps are physically informative and results are credible.

Output: Sweep JLD2 files in results/raman/sweeps/, heatmap PNGs in results/images/, multi-start histogram.

## Files Likely Touched

- `scripts/common.jl`
- `scripts/raman_optimization.jl`
- `scripts/test_optimization.jl`
- `scripts/run_sweep.jl`
- `scripts/visualization.jl`
- `results/raman/sweeps/sweep_results_smf-28.jld2`
- `results/raman/sweeps/sweep_results_hnlf.jld2`
- `results/raman/sweeps/multistart_L2m_P030W.jld2`
- `results/images/sweep_heatmap_smf28.png`
- `results/images/sweep_heatmap_hnlf.png`
- `results/images/multistart_histogram.png`
