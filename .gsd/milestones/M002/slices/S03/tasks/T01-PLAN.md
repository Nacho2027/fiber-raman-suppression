# T01: 06-cross-run-comparison-and-pattern-analysis 01

**Slice:** S03 — **Milestone:** M002

## Description

Add all cross-run comparison and pattern analysis visualization functions to `scripts/visualization.jl`.

Purpose: Provide the function library that `run_comparison.jl` (Plan 02) will call. Separating function definitions from orchestration follows the established codebase pattern where visualization.jl holds all plotting functions and scripts call them.

Output: 5 new functions appended to visualization.jl before the include guard `end`, ready for Plan 02 to import and call.

## Must-Haves

- [ ] "visualization.jl exports a function that renders a summary table PNG with fiber type, L, P, J_before, J_after, delta-dB, iterations, wall time, and soliton number N columns"
- [ ] "visualization.jl exports a function that overlays convergence histories (J vs iteration) for multiple runs on a single figure with per-run colors and labels"
- [ ] "visualization.jl exports a function that overlays optimized output spectra for multiple runs on shared dB axes with per-run colors and labels"
- [ ] "visualization.jl exports a function that decomposes an optimized phase profile onto GDD/TOD polynomial basis and returns coefficients and residual fraction"
- [ ] "visualization.jl exports a function that computes the soliton number N from gamma, P_peak, fwhm, and beta2"

## Files

- `scripts/visualization.jl`
