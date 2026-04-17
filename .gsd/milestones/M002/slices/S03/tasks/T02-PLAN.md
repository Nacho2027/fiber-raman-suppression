# T02: 06-cross-run-comparison-and-pattern-analysis 02

**Slice:** S03 — **Milestone:** M002

## Description

Create `scripts/run_comparison.jl` that re-runs all 5 optimization configs to generate JLD2 files, then loads results and produces 4 comparison figures (summary table, convergence overlay, 2 spectral overlays) plus phase decomposition analysis and soliton number annotations.

Purpose: This is the Phase 6 entry point per D-01. It produces the cross-run comparison artifacts that make all 5 optimization runs interpretable side-by-side for lab meetings and advisor reviews.

Output: 1 new script file + 4 PNG figures in results/images/ + updated manifest.json with soliton numbers.

## Must-Haves

- [ ] "A single summary table PNG in results/images/ shows J_before, J_after, delta-dB, iterations, wall time, and soliton number N for all 5 runs"
- [ ] "A convergence overlay PNG in results/images/ shows J vs iteration for all 5 runs on shared axes"
- [ ] "Two spectral overlay PNGs in results/images/ show optimized output spectra per fiber type (SMF-28, HNLF)"
- [ ] "Each optimal phase profile has GDD (fs^2), TOD (fs^3), and residual fraction reported in the script log output"
- [ ] "Soliton number N is added to manifest.json for each run"
- [ ] "All 5 JLD2 result files exist under results/raman/"

## Files

- `scripts/run_comparison.jl`
