---
id: T01
parent: S03
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
# T01: 06-cross-run-comparison-and-pattern-analysis 01

**# Phase 06 Plan 01: Cross-Run Comparison Visualization Functions Summary**

## What Happened

# Phase 06 Plan 01: Cross-Run Comparison Visualization Functions Summary

## One-liner

Five cross-run comparison functions added to visualization.jl: soliton number computation, GDD/TOD polynomial phase decomposition, matplotlib summary table PNG, J-vs-iteration convergence overlay, and per-fiber optimized spectral overlay with re-propagation.

## What Was Built

Added 2 new sections (13 and 14) to `scripts/visualization.jl` with 5 functions and 1 constant:

**Section 13 — Soliton number, phase decomposition, summary table:**

- `compute_soliton_number(gamma_Wm, P0_W, fwhm_fs, beta2_s2m)`: Standard soliton number N = sqrt(γ × P₀ × T₀² / |β₂|) with sech² T₀ conversion (T₀ = FWHM / (2·acosh(√2)) ≈ FWHM/1.7628). Returns Float64, NaN-safe via max(N_sq, 0.0).

- `decompose_phase_polynomial(phi_opt, uomega0, sim_Dt, Nt)`: Decomposes optimal phase onto GDD/TOD polynomial basis in the signal-bearing spectral region (-40 dB threshold). Removes global offset and linear group-delay term before fitting to prevent ambiguity across runs. Returns NamedTuple `(gdd_fs2, tod_fs3, residual_fraction)`.

- `plot_cross_run_summary_table(runs; save_path=nothing)`: Renders a 9-column summary table via `ax.table()` with Fiber, L(m), P(W), J_before(dB), J_after(dB), ΔdB, Iter., Time(s), N. Includes footnote warning about heterogeneous grid J comparisons. Returns (fig, ax).

**Section 14 — Convergence overlay and spectral overlay:**

- `COLORS_5_RUNS`: Okabe-Ito extended 5-color palette (#0072B2, #E69F00, #009E73, #CC79A7, #56B4E9), colorblind-safe, distinct from existing COLOR_INPUT/COLOR_OUTPUT.

- `plot_convergence_overlay(runs; save_path=nothing)`: Overlays J vs iteration (dB scale) for all runs on shared axes with per-run color/label. Returns (fig, ax).

- `plot_spectral_overlay(runs_fiber_group, fiber_type_label; save_path=nothing)`: Reconstructs sim/fiber from JLD2 scalars per run, applies phi_opt to uomega0, re-propagates via solve_disp_mmf, plots output spectra on shared wavelength axes. Uses native wavelength grids per run (no interpolation). Returns (fig, ax).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed `using LinearAlgebra: norm` from inside function body**
- **Found during:** Task 1 implementation
- **Issue:** Julia does not allow `using` statements inside function bodies; `using LinearAlgebra: norm` was initially placed inside `decompose_phase_polynomial`
- **Fix:** Moved `using LinearAlgebra: norm` to top-level imports alongside PyPlot, FFTW, etc.
- **Files modified:** scripts/visualization.jl (line 27)
- **Commit:** 58cf767

**2. [Rule 1 - Bug] Plan verification test uses incorrect peak power parameter**
- **Found during:** Task 1 verification
- **Issue:** Plan spec: `compute_soliton_number(1.1e-3, 0.05, 185.0, -2.17e-26)` should give N in [1.5, 4.0]. But 0.05 is average continuum power (P_cont_W), not peak power. With the correct formula, N ≈ 0.005 (not 2.3). The "N~2.3" comments in raman_optimization.jl are rough estimates not derived from this formula.
- **Fix:** Implemented the function correctly per physics (N = sqrt(γ × P_peak × T₀²/|β₂|)). The function accepts peak power as documented. The caller (run_comparison.jl, Plan 02) must compute P_peak from P_cont using: `P_peak = 0.881374 × P_cont / (fwhm_s × rep_rate)` for sech² pulses.
- **Verification:** Confirmed `compute_soliton_number(10e-3, 1000.0, 185.0, -0.5e-26)` → N=4.69 (physically correct for HNLF at high power). Confirmed NaN-safety via max(N_sq, 0).
- **Files modified:** None (function implementation is correct; test was broken)
- **Commit:** 58cf767

## Decisions Made

- `decompose_phase_polynomial` uses the same -40 dB spectral signal mask as the existing `plot_phase_diagnostic` function (BUG-03 fix), ensuring consistency across visualization functions.
- `plot_spectral_overlay` uses native per-run wavelength grids rather than interpolating to a common grid — avoids interpolation artifacts and preserves spectral resolution.
- Empty `betas` fallback in `plot_spectral_overlay`: SMF-28 → `[-2.17e-26, 1.2e-40]`, HNLF → `[-0.5e-26, 1.0e-40]`. These match the hardcoded constants in raman_optimization.jl.

## Known Stubs

None. All 5 functions are fully implemented with complete physics and rendering logic. No placeholder data.

## Self-Check: PASSED

- FOUND: scripts/visualization.jl (5 new functions verified present)
- FOUND: .planning/phases/06-cross-run-comparison-and-pattern-analysis/06-01-SUMMARY.md
- FOUND: commit 58cf767 (feat(06-01): Task 1 — soliton, phase decomp, summary table)
- FOUND: commit b97926a (feat(06-01): Task 2 — convergence overlay, spectral overlay)
- PASSED: Julia include smoke test — all 5 functions callable without error
- PASSED: COLORS_5_RUNS has 5 Okabe-Ito hex color entries
