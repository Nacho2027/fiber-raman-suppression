---
id: S03
parent: M002
milestone: M002
provides:
  - ["Cross-run comparison visualization functions in visualization.jl", "run_comparison.jl pipeline script for Phase 6 figure generation", "Soliton number computation and manifest annotation", "GDD/TOD phase decomposition analysis"]
requires:
  - slice: S02
    provides: JLD2 result serialization and manifest.json infrastructure
affects:
  - ["S04"]
key_files:
  - ["scripts/visualization.jl", "scripts/run_comparison.jl"]
key_decisions:
  - ["decompose_phase_polynomial uses -40 dB spectral signal mask consistent with plot_phase_diagnostic", "plot_spectral_overlay uses native per-run wavelength grids (no interpolation) to preserve spectral resolution", "RC_ prefix for script-local fiber constants to prevent const redefinition in REPL", "P_cont to P_peak conversion uses 0.881374 sech² factor confirmed from src/simulation/simulate_disp_mmf.jl:113", "JSON3.read immutable objects must be converted via Dict{String,Any}(entry) before field mutation"]
patterns_established:
  - ["Cross-run comparison functions in visualization.jl + standalone pipeline script pattern (function library vs orchestration separation)", "RC_ prefix convention for script-local constants that shadow common.jl names", "sech² peak power conversion: P_peak = 0.881374 * P_cont / (fwhm_s * rep_rate)", "Okabe-Ito COLORS_5_RUNS palette for multi-run overlays (distinct from COLOR_INPUT/COLOR_OUTPUT)"]
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-04-17T01:36:01.697Z
blocker_discovered: false
---

# S03: Cross Run Comparison And Pattern Analysis

**Five cross-run comparison functions (soliton number, phase decomposition, summary table, convergence overlay, spectral overlay) added to visualization.jl, plus run_comparison.jl pipeline script that re-runs all 5 configs, computes derived physics, and generates 4 comparison PNGs.**

## What Happened

## What Happened

### T01: Visualization Function Library

Added Sections 13 and 14 to `scripts/visualization.jl` (5 functions + 1 constant):

**Section 13 — Physics computations and summary table:**
- `compute_soliton_number(gamma_Wm, P0_W, fwhm_fs, beta2_s2m)` — standard N = sqrt(gamma * P_peak * T0^2 / |beta2|) with sech^2 T0 conversion (T0 = FWHM/1.7628). NaN-safe via max(N_sq, 0.0).
- `decompose_phase_polynomial(phi_opt, uomega0, sim_Dt, Nt)` — GDD/TOD polynomial decomposition in the signal-bearing spectral region (-40 dB threshold, consistent with plot_phase_diagnostic). Removes global offset and linear group-delay before fitting. Returns NamedTuple (gdd_fs2, tod_fs3, residual_fraction).
- `plot_cross_run_summary_table(runs; save_path)` — 9-column matplotlib table PNG (Fiber, L, P, J_before/after in dB, delta-dB, iterations, wall time, soliton N).

**Section 14 — Overlay plots:**
- `COLORS_5_RUNS` — Okabe-Ito extended 5-color palette, colorblind-safe, distinct from existing COLOR_INPUT/COLOR_OUTPUT.
- `plot_convergence_overlay(runs; save_path)` — J vs iteration in dB for all runs on shared axes.
- `plot_spectral_overlay(runs_fiber_group, fiber_type_label; save_path)` — reconstructs sim/fiber per run from JLD2 scalars, re-propagates via solve_disp_mmf, plots output spectra on native wavelength grids (no interpolation to avoid artifacts).

**Auto-fixed bug:** `using LinearAlgebra: norm` was initially inside a function body (illegal in Julia); moved to top-level imports.

**Auto-fixed spec issue:** Plan verification expected `compute_soliton_number(1.1e-3, 0.05, 185.0, -2.17e-26)` to give N in [1.5, 4.0], but 0.05 W is average continuum power, not peak power. The function correctly takes peak power; the caller (run_comparison.jl) handles the P_cont -> P_peak conversion.

### T02: Pipeline Script

Created `scripts/run_comparison.jl` (313 lines, 7 sections):

1. **Constants** — `RC_`-prefixed fiber params to avoid const redefinition conflicts.
2. **Re-run all 5 configs** — Calls `run_optimization` 5x matching raman_optimization.jl parameters, generating JLD2 + manifest.
3. **Load from manifest** — Reads manifest.json via JSON3, merges with JLD2 arrays. Converts JSON3 immutable objects to mutable Dicts.
4. **Soliton number** — P_cont -> P_peak conversion (0.881374 sech^2 factor / fwhm_s / rep_rate), then `compute_soliton_number`. Updates manifest.json with `soliton_number_N` field.
5. **Phase decomposition** — Converts sim_Dt from picoseconds to seconds, calls `decompose_phase_polynomial`, logs GDD/TOD/residual per run.
6. **Figure generation** — 4 PNGs: summary table, convergence overlay, SMF-28 spectral overlay, HNLF spectral overlay.
7. **Summary log** — Box-drawing run summary following codebase convention.

**Auto-fixed unit bug:** Plan called `decompose_phase_polynomial(run["phi_opt"], run["uomega0"], run["sim_Dt"], Nt)` directly, but sim_Dt in JLD2 is in picoseconds. Added `* 1e-12` conversion.

## Verification

**Artifact verification (all passed):**

1. **Function presence** — All 5 functions (`compute_soliton_number`, `decompose_phase_polynomial`, `plot_cross_run_summary_table`, `plot_convergence_overlay`, `plot_spectral_overlay`) and `COLORS_5_RUNS` constant confirmed present in `scripts/visualization.jl` via grep.
2. **Include guard integrity** — Functions are inside the `_VISUALIZATION_JL_LOADED` guard block; closing `end` at line 2069 confirmed.
3. **Script structure** — `scripts/run_comparison.jl` (313 lines) contains all 7 sections with correct function calls, manifest I/O, and figure generation.
4. **Julia syntax** — Both T01 and T02 verified via `Meta.parse` (no syntax errors).
5. **T01 smoke test** — Julia `include("scripts/visualization.jl")` succeeded; all 5 functions callable without error.
6. **COLORS_5_RUNS** — Confirmed 5 Okabe-Ito hex color entries.
7. **Task summaries** — Both T01-SUMMARY.md and T02-SUMMARY.md present with verification_result: passed.

**Not yet verified (requires burst VM execution):**
- Visual quality of the 4 output PNGs (requires ~15-25 min runtime for 5 optimization re-runs)
- Correct soliton number values in updated manifest.json
- Phase decomposition GDD/TOD values physically reasonable

## Requirements Advanced

None.

## Requirements Validated

- XRUN-02 — plot_cross_run_summary_table renders 9-column table with J_before, J_after, delta-dB, iterations, wall time; function present and syntax-verified in visualization.jl
- XRUN-03 — plot_convergence_overlay plots all runs' J vs iteration on shared dB-scale axes; function present and syntax-verified
- XRUN-04 — plot_spectral_overlay plots optimized output spectra per fiber type on shared wavelength axes with re-propagation; function present and syntax-verified
- PATT-01 — decompose_phase_polynomial fits GDD/TOD polynomial basis in -40 dB signal region with residual_fraction reported; returns NamedTuple(gdd_fs2, tod_fs3, residual_fraction)
- PATT-02 — compute_soliton_number implements N = sqrt(gamma*P0*T0^2/|beta2|); run_comparison.jl computes P_peak from P_cont and annotates manifest.json with soliton_number_N

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Operational Readiness

None.

## Deviations

1. **LinearAlgebra import location** — T01 initially placed `using LinearAlgebra: norm` inside a function body (illegal in Julia). Auto-fixed by moving to top-level imports.

2. **Soliton number test spec incorrect** — Plan expected N in [1.5, 4.0] for P=0.05 W, but 0.05 W is average continuum power not peak power. Function correctly accepts peak power; caller handles conversion. No code change needed.

3. **sim_Dt unit conversion missing from plan** — Plan Section 5 called decompose_phase_polynomial with raw sim_Dt (picoseconds). Auto-fixed by adding `* 1e-12` conversion to seconds.

## Known Limitations

1. **4 output PNGs not yet generated** — Script requires ~15-25 min on burst VM for 5 optimization re-runs. Code is syntax-verified and smoke-tested but visual output awaits human execution.

2. **COLORS_5_RUNS wraps at 5** — More than 5 runs will reuse colors via mod1. Visual distinguishability not tested beyond 5.

3. **plot_spectral_overlay re-propagates from scratch** — Each spectral overlay call re-runs forward propagation per run because JLD2 does not store the optimized output field. Adds ~2-5 min compute per overlay call.

## Follow-ups

1. **Execute run_comparison.jl on burst VM** — Human visual verification of the 4 PNGs needed before presenting to advisor.

2. **Consider caching optimized output field in JLD2** — Would eliminate re-propagation overhead in plot_spectral_overlay (saves ~5 min per comparison generation at cost of ~100 MB per JLD2 file).

## Files Created/Modified

- `scripts/visualization.jl` — Added Sections 13-14: compute_soliton_number, decompose_phase_polynomial, plot_cross_run_summary_table, COLORS_5_RUNS, plot_convergence_overlay, plot_spectral_overlay
- `scripts/run_comparison.jl` — New 313-line pipeline script: re-runs 5 configs, loads results from manifest+JLD2, computes soliton N, runs phase decomposition, generates 4 comparison PNGs
