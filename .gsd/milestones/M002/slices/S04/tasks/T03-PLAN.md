# T03: 07-parameter-sweeps 03

**Slice:** S04 — **Milestone:** M002

## Description

Execute the full parameter sweep (36 grid points + 10 multi-start runs) and verify the results with a visual checkpoint.

Purpose: This is the compute-heavy execution plan. The script from Plan 02 is run end-to-end, producing heatmaps, aggregate data, and multi-start analysis. Estimated wall time: 1-2 hours (per D-03, no time limit). The human checkpoint at the end confirms that heatmaps are physically informative and results are credible.

Output: Sweep JLD2 files in results/raman/sweeps/, heatmap PNGs in results/images/, multi-start histogram.

## Must-Haves

- [ ] "J_final heatmap for SMF-28 shows Raman suppression across the full 5x4 grid with physical axis labels"
- [ ] "J_final heatmap for HNLF shows Raman suppression across the full 4x4 grid"
- [ ] "Non-converged points are visually distinct from converged points in both heatmaps"
- [ ] "Window-limited points (photon drift >5%) are visually flagged in both heatmaps"
- [ ] "Multi-start analysis reveals whether SMF-28 L=2m P=0.30W has multiple local minima"
- [ ] "All sweep results are saved to results/raman/sweeps/ with per-point JLD2 and aggregate files"
- [ ] "Every converged sweep point has photon number drift <5%"

## Files

- `results/raman/sweeps/sweep_results_smf-28.jld2`
- `results/raman/sweeps/sweep_results_hnlf.jld2`
- `results/raman/sweeps/multistart_L2m_P030W.jld2`
- `results/images/sweep_heatmap_smf28.png`
- `results/images/sweep_heatmap_hnlf.png`
- `results/images/multistart_histogram.png`
