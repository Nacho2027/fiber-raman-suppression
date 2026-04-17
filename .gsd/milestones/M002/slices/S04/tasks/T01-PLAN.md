# T01: 07-parameter-sweeps 01

**Slice:** S04 — **Milestone:** M002

## Description

Fix the power-blind time window function and add sweep-mode support to run_optimization(), establishing the foundation for the parameter sweep phase.

Purpose: Without SPM-aware time windows, high-power sweep points lose 38-49% photon energy to the attenuator, producing artificially low J values. Without do_plots=false, the 36-point sweep generates 108 PNGs and runs 36 extra ODE solves. These two fixes are critical prerequisites for all sweep work.

Output: Modified common.jl (SPM-corrected recommended_time_window + nt_for_window), modified raman_optimization.jl (do_plots kwarg), updated tests.

## Must-Haves

- [ ] "recommended_time_window() returns larger windows when gamma and P_peak are provided (SPM broadening correction)"
- [ ] "recommended_time_window() is backward-compatible: existing callers without gamma/P_peak get the same result as before"
- [ ] "run_optimization() can be called with do_plots=false to skip all visualization (no PNGs generated)"
- [ ] "nt_for_window() returns next power-of-2 Nt that maintains 10.5 fs temporal resolution"
- [ ] "Existing tests still pass after the modifications"

## Files

- `scripts/common.jl`
- `scripts/raman_optimization.jl`
- `scripts/test_optimization.jl`
