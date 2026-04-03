---
phase: 10-propagation-resolved-physics
plan: 02
subsystem: phase-ablation
tags: [ablation, perturbation, robustness, band-zeroing, spectral-shift, JLD2]
completed: "2026-04-03"
duration_minutes: 9

dependency_graph:
  requires:
    - "results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2 (canonical SMF-28 phi_opt)"
    - "results/raman/sweeps/hnlf/L1m_P0.01W/opt_result.jld2 (canonical HNLF phi_opt)"
    - "scripts/common.jl (setup_raman_problem, spectral_band_cost)"
    - "src/simulation/simulate_disp_mmf.jl (solve_disp_mmf)"
  provides:
    - "results/raman/phase10/ablation_smf28_canonical.jld2"
    - "results/raman/phase10/ablation_hnlf_canonical.jld2"
    - "results/raman/phase10/perturbation_smf28_canonical.jld2"
    - "results/raman/phase10/perturbation_hnlf_canonical.jld2"
    - "results/images/physics_10_05 through physics_10_09 (5 figures)"
    - "results/raman/PHASE10_ABLATION_FINDINGS.md"
  affects:
    - "Phase 9 interpretation: confirms distributed suppression mechanism"

tech_stack:
  added: []
  patterns:
    - "Super-Gaussian band-zeroing window (order 6, 10% roll-off) on fftshifted axis + ifftshift to FFT order"
    - "pab_ constant prefix to avoid REPL collision with PA_ (phase_analysis.jl)"
    - "Absolute path construction via dirname(dirname(abspath(@__FILE__))) for script portability"
    - "β_order=3 required when using FIBER_PRESETS with 2 beta coefficients (β₂ + β₃)"

key_files:
  created:
    - scripts/phase_ablation.jl
    - results/raman/phase10/ablation_smf28_canonical.jld2
    - results/raman/phase10/ablation_hnlf_canonical.jld2
    - results/raman/phase10/perturbation_smf28_canonical.jld2
    - results/raman/phase10/perturbation_hnlf_canonical.jld2
    - results/images/physics_10_05_ablation_band_zeroing.png
    - results/images/physics_10_06_ablation_cumulative.png
    - results/images/physics_10_07_scaling_robustness.png
    - results/images/physics_10_08_spectral_shift_robustness.png
    - results/images/physics_10_09_ablation_summary.png
    - results/raman/PHASE10_ABLATION_FINDINGS.md
  modified: []

decisions:
  - "β_order=3 in pab_load_config: setup_raman_problem default β_order=2 rejects presets with 2 beta coefficients. The sweep scripts used β_order=3 — matching this is required for grid consistency."
  - "Absolute paths via _PAB_PROJECT_ROOT: script portability across include() and direct julia execution contexts"

metrics:
  duration_minutes: 9
  completed_date: "2026-04-03"
  tasks_completed: 1
  tasks_total: 1
  files_created: 11
  propagations_run: ~64
---

# Phase 10 Plan 02: Phase Ablation & Perturbation Summary

**One-liner:** Band zeroing (10 sub-bands, super-Gaussian windowing) + scaling + shift perturbations on SMF-28 and HNLF canonical configs, revealing that phi_opt suppression is spectrally distributed, amplitude-sensitive, and exquisitely spectrally aligned (sub-THz shift tolerance).

## What Was Built

`scripts/phase_ablation.jl` runs 4 experiments on 2 canonical configurations
(SMF-28 L2m_P0.2W and HNLF L1m_P0.01W) selected from the Phase 9 analysis:

1. **Band zeroing** (Experiment 1): Divide signal band into 10 equal-width sub-bands, zero one at a time using super-Gaussian window (order 6, 10% roll-off), propagate, measure suppression loss.

2. **Cumulative ablation** (Experiment 2): Zero bands from spectral edges inward, track suppression as bandwidth is progressively truncated.

3. **Global scaling** (Experiment 3): Multiply phi_opt by [0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0], propagate each.

4. **Spectral shift** (Experiment 4): Translate phi_opt by [-5, -2, -1, 0, 1, 2, 5] THz using linear interpolation with zero extrapolation.

Total: ~64 propagations (no optimization, no z-saves — fast mode).

## Key Results

### Band Zeroing (Figure physics_10_05)

**SMF-28 (J_full = -60.5 dB, J_flat = -1.1 dB):**
- Critical bands (>3 dB loss when zeroed): bands 1, 4, 6 at -4.6, -1.5, +0.5 THz
- Band 6 (+0.5 THz) is the most critical: 7.1 dB loss when zeroed
- Bands 8–10 (blue edge) contribute negligibly (< 0.2 dB loss)
- Suppression is NOT uniformly distributed — some bands matter much more

**HNLF (J_full = -69.8 dB, J_flat = -2.4 dB):**
- ALL 10 bands are critical (every band contributes >3 dB when zeroed)
- Bands 5 and 6 (straddling 0 THz) are most critical: 27.7 dB loss each
- Even the outermost bands (1 and 10) contribute 9.3 and 4.7 dB
- Suppression is far more sensitive and distributed than SMF-28

### Cumulative Ablation (Figure physics_10_06)

Both configs require full bandwidth — the very first ablation step (zeroing outermost 2 bands) already causes:
- SMF-28: -60.5 → -57.0 dB (3.5 dB degradation, just crossing the 3 dB threshold)
- HNLF: -69.8 → -61.5 dB (8.3 dB degradation with only 2 bands zeroed)

Full bandwidth is non-negotiable for HNLF. SMF-28 is marginally more tolerant of edge truncation.

### Scaling Robustness (Figure physics_10_07)

The 3 dB envelope is a single point (scale=1.0 exactly) for both configs:
- SMF-28: α=0.75 → -43.9 dB (+16.6 dB degradation from optimal)
- HNLF: α=0.75 → -39.7 dB (+30.1 dB degradation from optimal)
- SMF-28: α=1.25 → -46.6 dB (+13.9 dB degradation)
- HNLF: α=1.25 → -40.2 dB (+29.6 dB degradation)

The optimum is sharply peaked at α=1.0. Any deviation by ±25% in amplitude degrades HNLF by ~30 dB.

### Spectral Shift Sensitivity (Figure physics_10_08)

phi_opt degrades catastrophically with even 1 THz shift:
- SMF-28: Δf=1 THz → -34.7 dB (25.8 dB degradation); Δf=2 THz → -22.2 dB (38.3 dB)
- HNLF: Δf=1 THz → -46.1 dB (23.7 dB degradation); Δf=2 THz → -38.7 dB (31.1 dB)
- At Δf=±5 THz, both configs return nearly to flat-phase suppression levels

The 3 dB shift tolerance is sub-0-THz for both (only at Δf=0 exactly does suppression stay within 3 dB). phi_opt encodes spectral features at scales finer than the Raman gain bandwidth.

## New Hypotheses (from Findings Document)

**H1: Suppression is spectrally distributed, not localized**
HNLF requires all 10 bands — no "magic frequency" carries the suppression alone. For SMF-28, band 6 (+0.5 THz) dominates but bands 1 and 4 also contribute. This directly explains why polynomial phase (GDD, TOD) fails: it cannot zero multiple isolated spectral regions simultaneously.

**H2: phi_opt encodes sub-THz spectral structure**
The sub-1-THz shift tolerance means the optimizer is exploiting interference at spectral scales finer than the Raman gain bandwidth (~13.2 THz FWHM). The optimum phase is not a slowly-varying chirp but a fine spectral structure.

**H3: Amplitude-sensitive nonlinear interference**
The ultra-narrow scaling envelope (any ±25% deviation causes >13 dB degradation) confirms the suppression depends on precise phase amplitude, not just spectral shape. This rules out simple pulse compression or soliton order tuning as the mechanism.

**H4: SMF-28 and HNLF exploit different spectral regions**
SMF-28 critical bands cluster at -4.6, -1.5, +0.5 THz. HNLF is uniformly sensitive across all bands. The mechanisms are fiber-specific, consistent with Phase 9's multi-start correlation of 0.109.

## Comparison with Phase 9

| Phase 9 Finding | Ablation Evidence |
|----------------|-------------------|
| 84% non-polynomial phase structure | Confirmed: suppression is distributed and non-local in frequency |
| Multi-start correlation = 0.109 | Confirmed: SMF-28 vs HNLF critical bands differ significantly |
| N_sol > 2 vs ≤ 2 clustering | Both ablation configs are N>2; consistent regime |
| H5 (z-resolved diagnostics deferred) | Phase 10 Plan 01 addresses via propagation_z_resolved.jl |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] β_order=3 required for FIBER_PRESETS with 2 beta coefficients**
- **Found during:** Task 1 — first propagation attempt
- **Issue:** `setup_raman_problem` defaults to `β_order=2`, but `:SMF28` and `:HNLF` presets have `betas=[-β₂, β₃]` (2 values). `get_disp_fiber_params_user_defined` enforces `length(betas_user) ≤ β_order - 1`, throwing `ArgumentError`.
- **Fix:** Added `β_order=3` explicitly in `pab_load_config`. This matches the sweep scripts (`run_sweep.jl` line 205: `β_order = 3`).
- **Files modified:** scripts/phase_ablation.jl
- **Commit:** 2385e1e

**2. [Rule 3 - Blocking] Relative include paths failed when running with `julia -e`**
- **Found during:** Initial parse test
- **Issue:** `include("scripts/common.jl")` after `cd(...)` doubled the path to `scripts/scripts/common.jl`.
- **Fix:** Replaced with `_PAB_PROJECT_ROOT = dirname(dirname(abspath(@__FILE__)))` and absolute `joinpath` calls throughout.
- **Files modified:** scripts/phase_ablation.jl
- **Commit:** 2385e1e (same commit)

## Known Stubs

None. All 4 experiments execute real propagations and write real data. No placeholder values.

## Self-Check: PASSED

All required files exist and commit 2385e1e is in git log:
- scripts/phase_ablation.jl: FOUND
- results/raman/phase10/ablation_smf28_canonical.jld2: FOUND
- results/raman/phase10/ablation_hnlf_canonical.jld2: FOUND
- results/raman/phase10/perturbation_smf28_canonical.jld2: FOUND
- results/raman/phase10/perturbation_hnlf_canonical.jld2: FOUND
- results/images/physics_10_05_ablation_band_zeroing.png: FOUND (192 KB)
- results/images/physics_10_06_ablation_cumulative.png: FOUND (228 KB)
- results/images/physics_10_07_scaling_robustness.png: FOUND (291 KB)
- results/images/physics_10_08_spectral_shift_robustness.png: FOUND (273 KB)
- results/images/physics_10_09_ablation_summary.png: FOUND (615 KB)
- results/raman/PHASE10_ABLATION_FINDINGS.md: FOUND
- Commit 2385e1e: FOUND
