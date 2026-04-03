---
phase: 10-propagation-resolved-physics
plan: 01
subsystem: simulation
tags: [julia, jld2, raman-suppression, z-resolved, propagation, gnlse, soliton]

# Dependency graph
requires:
  - phase: 09-physics-of-raman-suppression
    provides: phi_opt JLD2 files for 6 representative configurations in results/raman/sweeps/
  - phase: 07-parameter-sweeps
    provides: sweep results (opt_result.jld2 per config) consumed by this plan
provides:
  - Z-resolved propagation script (scripts/propagation_z_resolved.jl)
  - 12 JLD2 files with 50-z-point uω_z/ut_z/J_z arrays in results/raman/phase10/
  - 4 diagnostic figures (physics_10_01 through physics_10_04)
  - Written findings with Raman onset z-positions and N_sol regime analysis
affects:
  - 10-02 (phase ablation plan — uses phase10/ JLD2 files as input)
  - future multimode extension

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PZ_ constant prefix for script-level constants (avoiding const redefinition in REPL)"
    - "deepcopy(fiber) before setting fiber['zsave'] to avoid dict mutation"
    - "pz_load_and_repropagate: load phi_opt, reconstruct grid with stored Nt/time_window, propagate x2"
    - "Save JLD2 immediately after each config pair to release large uω_z/ut_z arrays"
    - "@sprintf with string concatenation (* operator) fails in Julia 1.12 macroexpand — must use single literal"

key-files:
  created:
    - scripts/propagation_z_resolved.jl
    - results/raman/phase10/smf28_L0.5m_P0.05W_shaped_zsolved.jld2
    - results/raman/phase10/smf28_L0.5m_P0.05W_unshaped_zsolved.jld2
    - results/raman/phase10/smf28_L0.5m_P0.2W_shaped_zsolved.jld2
    - results/raman/phase10/smf28_L0.5m_P0.2W_unshaped_zsolved.jld2
    - results/raman/phase10/smf28_L5m_P0.2W_shaped_zsolved.jld2
    - results/raman/phase10/smf28_L5m_P0.2W_unshaped_zsolved.jld2
    - results/raman/phase10/hnlf_L1m_P0.005W_shaped_zsolved.jld2
    - results/raman/phase10/hnlf_L1m_P0.005W_unshaped_zsolved.jld2
    - results/raman/phase10/hnlf_L1m_P0.01W_shaped_zsolved.jld2
    - results/raman/phase10/hnlf_L1m_P0.01W_unshaped_zsolved.jld2
    - results/raman/phase10/hnlf_L0.5m_P0.03W_shaped_zsolved.jld2
    - results/raman/phase10/hnlf_L0.5m_P0.03W_unshaped_zsolved.jld2
    - results/images/physics_10_01_raman_fraction_vs_z.png
    - results/images/physics_10_02_spectral_evolution_comparison.png
    - results/images/physics_10_03_temporal_evolution_comparison.png
    - results/images/physics_10_04_nsol_regime_comparison.png
    - results/raman/PHASE10_ZRESOLVED_FINDINGS.md
  modified: []

key-decisions:
  - "β_order=3 required in setup_raman_problem when using fiber presets with 2 betas (β₂+β₃); default β_order=2 rejects them"
  - "6 configs selected: SMF-28 N={1.3, 2.6, 2.6(5m)}, HNLF N={2.6, 3.6, 6.3} to span full N_sol range plus degraded long-fiber case"
  - "@sprintf with '*' string concatenation is not a literal format string in Julia 1.12 macroexpand — split into variable + single-literal sprintf"
  - "DocStringExtensions loads transitively via DifferentialEquations.jl and calls macroexpand on function bodies at docstring-bind time"

patterns-established:
  - "pz_load_and_repropagate pattern: load JLD2 → reconstruct exact grid with stored Nt/time_window → deepcopy fiber → set zsave → propagate"
  - "J(z) extraction: Float64[spectral_band_cost(sol['uω_z'][i, :, :], band_mask)[1] for i in 1:n_zsave]"
  - "Raman onset: z where J(z) first exceeds 2× J(z=0)"

requirements-completed:
  - "Phase 9 deferred H5: propagation-resolved diagnostics"
  - "SC-1: Z-resolved Raman energy evolution for 6 configs shaped vs unshaped"
  - "SC-4: New hypothesis from z-resolved data"
  - "SC-5: All new simulations save z-resolved data to JLD2"

# Metrics
duration: 14min
completed: 2026-04-03
---

# Phase 10 Plan 01: Z-Resolved Propagation Diagnostics Summary

**50-point z-resolved propagation of 6 configs (SMF-28 + HNLF, N_sol 1.3-6.3) reveals that optimal phase prevents Raman onset in 5/6 cases; long-fiber SMF-28 shows breakdown at z=0.20m**

## Performance

- **Duration:** 14 min
- **Started:** 2026-04-03T02:39:20Z
- **Completed:** 2026-04-03T02:53:00Z
- **Tasks:** 1 of 1
- **Files modified:** 19

## Accomplishments

- Created `scripts/propagation_z_resolved.jl` (921 lines) implementing the full z-resolved propagation pipeline: data loading, 12 forward propagations with 50 z-save points each, J(z) computation, 4 diagnostic figures, and findings markdown
- Ran 12 propagations (6 configs × 2 conditions: shaped/unshaped) in ~38 seconds total; confirmed J_z_shaped[end] matches stored J_after to within floating-point precision
- Discovered critical physics finding: shaped pulse prevents Raman onset entirely in 5 of 6 configs (J_z_shaped stays below 2×J(0) for all z), while the long-fiber SMF-28 5m case shows suppression breakdown at z=0.20m (4% of fiber length)
- Identified N_sol-dependent dynamics: low-N (1.3) has naturally weak Raman so shaped/unshaped differ by 45.7 dB; medium-N (2.6-3.6) shows the largest shaped/unshaped gap (64-68 dB); high-N (6.3) shows early Raman onset at z=0.010m for unshaped with shaped suppressing by 48.5 dB

## Task Commits

1. **Task 1: Z-resolved propagation script, 12 propagations, 4 figures, findings** - `966352e` (feat)

## Files Created/Modified

- `/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression/scripts/propagation_z_resolved.jl` - Z-resolved propagation script with PZ_ constants, pz_load_and_repropagate, pz_save_to_jld2, 4 figure functions, pz_write_findings, main execution block
- `results/raman/phase10/*_zsolved.jld2` (12 files) - Z-resolved propagation data: uω_z [50×Nt×1], ut_z [50×Nt×1], J_z [50], zsave [50], phi_opt, metadata
- `results/images/physics_10_01_raman_fraction_vs_z.png` (504 KB) - 2×3 grid: J(z) semilogy for all 6 configs, shaped vs unshaped with Raman onset markers
- `results/images/physics_10_02_spectral_evolution_comparison.png` (276 KB) - 2×2 spectral heatmaps for SMF-28 N=2.6 and HNLF N=3.6 (unshaped vs shaped)
- `results/images/physics_10_03_temporal_evolution_comparison.png` (281 KB) - 2×2 temporal heatmaps for same 2 representative configs
- `results/images/physics_10_04_nsol_regime_comparison.png` (436 KB) - 1×3 J(z) panel by N_sol regime (low/medium/high), solid=shaped dashed=unshaped
- `results/raman/PHASE10_ZRESOLVED_FINDINGS.md` - Per-config Raman onset table, N_sol regime analysis, long-fiber degradation analysis, preliminary hypothesis

## Decisions Made

- Used `β_order=3` in `setup_raman_problem` because fiber presets have 2 betas (β₂ + β₃) — the default `β_order=2` allows only 1 beta and throws `ArgumentError`
- Representative configs for evolution heatmaps: SMF-28 N=2.6 + HNLF N=3.6 (medium-N, best suppression cases, most informative)
- `@sprintf` with `* ` string concatenation is NOT a literal format string in Julia 1.12 — `macroexpand` called during docstring binding expands macros and fails; fix is to compute parts as variables first

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed β_order parameter missing from setup_raman_problem call**
- **Found during:** Task 1 (first test propagation)
- **Issue:** `setup_raman_problem` defaults to `β_order=2` which rejects fiber presets that have 2 betas (β₂+β₃); throws `ArgumentError: betas_user length must be ≤ β_order-1 (1); got 2`
- **Fix:** Added `β_order=3` to the `setup_raman_problem` call in `pz_load_and_repropagate`
- **Files modified:** `scripts/propagation_z_resolved.jl`
- **Committed in:** 966352e (Task 1 commit)

**2. [Rule 1 - Bug] Fixed @sprintf with string concatenation format**
- **Found during:** Task 1 (script include test)
- **Issue:** `@sprintf("..." * "...", args...)` fails during Julia 1.12 `macroexpand` when docstrings are processed by `DocStringExtensions` hook — first argument must be a literal string, not a runtime `*` expression
- **Fix:** Split the concatenated literal into a variable assignment and a single-literal `@sprintf` call
- **Files modified:** `scripts/propagation_z_resolved.jl`
- **Committed in:** 966352e (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs)
**Impact on plan:** Both fixes required for script to load and run. No scope creep.

## Issues Encountered

- `DocStringExtensions` is loaded transitively via `DifferentialEquations.jl` and hooks into Julia's `@doc` macro processing, causing `macroexpand` to be called on function bodies at docstring-bind time. This is a known Julia 1.12 compatibility issue. No workaround needed beyond using literal-only format strings in `@sprintf`.

## Known Stubs

None — all J(z) data is computed from real propagations; findings document is generated from actual simulation results.

## Next Phase Readiness

- All 12 JLD2 files in `results/raman/phase10/` ready for Phase 10.02 (phase ablation)
- `pz_load_and_repropagate` and `pz_save_to_jld2` functions reusable by Plan 02
- Key physics finding for Plan 02 planning: Raman onset in 5/6 configs is prevented by the shaped pulse (suggesting the ablation experiments should focus on what happens inside the Raman band in the 1 case that fails)

---
*Phase: 10-propagation-resolved-physics*
*Completed: 2026-04-03*

## Self-Check: PASSED
