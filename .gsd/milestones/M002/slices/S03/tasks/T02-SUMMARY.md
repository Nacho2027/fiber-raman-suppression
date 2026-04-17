---
id: T02
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
# T02: 06-cross-run-comparison-and-pattern-analysis 02

**# Phase 06 Plan 02: Cross-Run Comparison Pipeline Summary**

## What Happened

# Phase 06 Plan 02: Cross-Run Comparison Pipeline Summary

## One-liner

`scripts/run_comparison.jl` created as the Phase 6 entry point: re-runs all 5 optimization configs, loads JLD2 results via manifest, computes soliton N with sech² peak-power correction, runs GDD/TOD phase decomposition, and generates 4 comparison PNGs — awaiting Task 2 human visual verification.

## Status

**Task 1 (complete):** `scripts/run_comparison.jl` written, syntax verified, committed at `533b3e6`.

**Task 2 (checkpoint:human-verify):** Requires executing the script (~15-25 min) and visual approval of the 4 output PNGs.

## What Was Built

### Task 1: scripts/run_comparison.jl

A 7-section script implementing the full cross-run comparison pipeline:

**Section 1 — Constants:**
- `RC_SMF28_GAMMA = 1.1e-3` W⁻¹m⁻¹, `RC_SMF28_BETAS = [-2.17e-26, 1.2e-40]`
- `RC_HNLF_GAMMA = 10.0e-3` W⁻¹m⁻¹, `RC_HNLF_BETAS = [-0.5e-26, 1.0e-40]`
- `RC_SECH_FACTOR = 0.881374` (sech² energy integral factor for P_cont → P_peak conversion)
- Uses `RC_` prefix to avoid const redefinition if other scripts define the same names

**Section 2 — Re-run all 5 configs:**
- Calls `run_optimization` 5 times with parameters matching `raman_optimization.jl` exactly
- Each call generates JLD2 result file and updates manifest.json (Phase 5 serialization)
- `GC.gc()` between runs to manage large FFT array memory

**Section 3 — Load results from manifest:**
- Reads `results/raman/manifest.json` via `JSON3.read`
- Merges manifest scalars with JLD2 arrays via `merge(Dict{String,Any}(entry), JLD2.load(...))`
- Asserts ≥ 5 runs loaded

**Section 4 — Soliton number computation + manifest update:**
- Converts P_cont → P_peak: `P_peak = 0.881374 * P_cont_W / (fwhm_s * rep_rate)`
- Calls `compute_soliton_number(gamma, P_peak, fwhm_fs, beta2)` per run
- Rebuilds manifest as `Vector{Dict{String,Any}}` (JSON3 immutable → mutable)
- Writes updated manifest with `soliton_number_N` field added

**Section 5 — Phase decomposition:**
- Converts `sim_Dt` from picoseconds to seconds: `sim_Dt_s = run["sim_Dt"] * 1e-12`
- Calls `decompose_phase_polynomial(phi_opt, uomega0, sim_Dt_s, Nt)` per run
- Logs GDD (fs²), TOD (fs³), residual fraction (%) for each run

**Section 6 — Figure generation:**
- `plot_cross_run_summary_table(all_runs; ...)` → `cross_run_summary_table.png`
- `plot_convergence_overlay(all_runs; ...)` → `convergence_overlay_all_runs.png`
- SMF-28 filter → `plot_spectral_overlay(smf_runs, "SMF-28"; ...)` → `spectral_overlay_SMF28.png`
- HNLF filter → `plot_spectral_overlay(hnlf_runs, "HNLF"; ...)` → `spectral_overlay_HNLF.png`

**Section 7 — Summary log:**
- Box-drawing summary log following existing codebase convention

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Avoided const redefinition conflict with RC_ prefix**
- **Found during:** Task 1 implementation
- **Issue:** The plan suggested defining `const SMF28_GAMMA`, `const SMF28_BETAS`, etc. directly. Since `include("raman_optimization.jl")` is called, and those constants are INSIDE the PROGRAM_FILE guard in raman_optimization.jl, there is no conflict at include time. However, if a user ever includes run_comparison.jl multiple times or has a session where raman_optimization.jl was already evaluated, redefining constants would cause a Julia error.
- **Fix:** Used `RC_SMF28_GAMMA`, `RC_HNLF_GAMMA` etc. as prefixed constants to avoid any potential redefinition conflict.
- **Files modified:** scripts/run_comparison.jl
- **Commit:** 533b3e6

**2. [Rule 2 - Missing critical functionality] Added sim_Dt picoseconds→seconds conversion**
- **Found during:** Task 1 analysis of JLD2 field units
- **Issue:** The plan's Section 5 calls `decompose_phase_polynomial(run["phi_opt"], run["uomega0"], run["sim_Dt"], Nt)` directly. But `sim_Dt` in JLD2 is stored as `sim["Δt"]` which is in picoseconds (time_window_ps / Nt). The `decompose_phase_polynomial` function expects seconds (confirmed by its docstring and the `fftfreq(Nt, 1.0 / sim_Dt)` computation that would produce THz, not Hz, if Δt is in ps).
- **Fix:** Added conversion: `sim_Dt_s = Float64(run["sim_Dt"]) * 1e-12` before calling `decompose_phase_polynomial`.
- **Files modified:** scripts/run_comparison.jl
- **Commit:** 533b3e6

## Decisions Made

- `RC_` prefix for fiber constants to prevent const redefinition if script is included multiple times in a REPL session
- `0.881374` sech² conversion factor confirmed in `src/simulation/simulate_disp_mmf.jl` line 113 (not common.jl formula which lacks this factor)
- `JSON3.read` returns immutable objects; manifest entries must be converted via `Dict{String,Any}(entry)` before setting `soliton_number_N`

## Known Stubs

None in the script itself. The 4 PNG output files do not yet exist — they will be generated when Task 2 is executed (the script requires ~15-25 min runtime for 5 ODE optimizations).

## Self-Check: PASSED

- FOUND: scripts/run_comparison.jl (confirmed via file creation)
- FOUND: commit 533b3e6 (feat(06-02): create run_comparison.jl)
- PASSED: Julia syntax check passes (`Meta.parse` confirms no syntax errors)
- PASSED: All 14 acceptance criteria verified via grep counts
