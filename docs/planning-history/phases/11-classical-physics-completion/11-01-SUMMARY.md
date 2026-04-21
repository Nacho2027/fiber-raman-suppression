---
phase: 11-classical-physics-completion
plan: "01"
subsystem: physics-analysis
tags:
  - raman-suppression
  - multi-start
  - z-dynamics
  - spectral-divergence
  - hypothesis-testing
dependency_graph:
  requires:
    - "10-01 z-resolved JLD2 files (results/raman/phase10/*_zsolved.jld2)"
    - "10-02 ablation/perturbation JLD2 files (results/raman/phase10/ablation_*.jld2, perturbation_*.jld2)"
    - "Phase 7/8 sweep multi-start JLD2 files (results/raman/sweeps/multistart/start_*/opt_result.jld2)"
  provides:
    - "20 multi-start JLD2 files: results/raman/phase11/multistart_start_XX_{shaped,unshaped}_zsolved.jld2"
    - "6 spectral divergence JLD2 files: results/raman/phase11/spectral_divergence_*.jld2"
    - "Trajectory analysis JLD2: results/raman/phase11/multistart_trajectory_analysis.jld2"
    - "5 figures: physics_11_01 through physics_11_05"
    - "physics_completion.jl analysis script for Phase 11 Plan 02 synthesis"
  affects:
    - "11-02 synthesis plan (all JLD2 data available)"
tech_stack:
  added: []
  patterns:
    - "PC_ constant prefix with include guard"
    - "Absolute paths via dirname(dirname(abspath(@__FILE__))) pattern"
    - "JLD2.jldsave for immediate per-propagation saves"
    - "Statistics.cor on column matrix for Pearson correlation"
key_files:
  created:
    - scripts/physics_completion.jl
    - results/raman/phase11/multistart_start_01_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_01_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_start_02_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_02_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_start_03_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_03_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_start_04_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_04_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_start_05_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_05_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_start_06_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_06_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_start_07_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_07_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_start_08_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_08_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_start_09_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_09_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_start_10_shaped_zsolved.jld2
    - results/raman/phase11/multistart_start_10_unshaped_zsolved.jld2
    - results/raman/phase11/multistart_trajectory_analysis.jld2
    - results/raman/phase11/spectral_divergence_smf28_L0.5m_P0.05W.jld2
    - results/raman/phase11/spectral_divergence_smf28_L0.5m_P0.2W.jld2
    - results/raman/phase11/spectral_divergence_smf28_L5m_P0.2W.jld2
    - results/raman/phase11/spectral_divergence_hnlf_L1m_P0.005W.jld2
    - results/raman/phase11/spectral_divergence_hnlf_L1m_P0.01W.jld2
    - results/raman/phase11/spectral_divergence_hnlf_L0.5m_P0.03W.jld2
    - results/images/physics_11_01_multistart_jz_overlay.png
    - results/images/physics_11_02_jz_cluster_comparison.png
    - results/images/physics_11_03_spectral_divergence_heatmaps.png
    - results/images/physics_11_04_h1_critical_bands_comparison.png
    - results/images/physics_11_05_h2_shift_scale_characterization.png
decisions:
  - "PC_ prefix for all script constants, absolute paths via _PC_PROJECT_ROOT"
  - "β_order=3 (Unicode kwarg) confirmed as required for FIBER_PRESETS with 2 betas"
  - "Parabolic fit to ±1 THz central window gives 0.329 THz 3dB tolerance for both fibers"
  - "Cluster A/B assigned by sorting final J(z=L) values (top 5 suppressors vs bottom 5)"
  - "Spectral divergence restricted to ±15 THz display window to show signal region only"
metrics:
  duration: "9m44s"
  completed: "2026-04-03T05:38:17Z"
  tasks_completed: 1
  tasks_total: 1
  files_created: 32
  deviations: 2
---

# Phase 11 Plan 01: Multi-Start Z-Dynamics and Spectral Divergence Summary

**One-liner:** Multi-start J(z) trajectories show higher phase-space correlation (0.621) than phi_opt structural similarity (0.091), confirming fiber physics dominates z-dynamics; spectral divergence emerges at z<0.03m for 5/6 configs; H1 overlap 30%; H2 tolerance 0.329 THz (2.5% of Raman bandwidth).

## What Was Built

`scripts/physics_completion.jl` — a complete analysis script (PC_ prefix, include guard, absolute paths) that:

1. **Section A — Multi-start z-propagation**: Re-propagated all 10 multi-start phi_opt profiles (SMF-28 L=2m P=0.2W, Nt=8192) with 50 z-save points each. Also propagated each with flat phase (unshaped baseline). Saved 20 JLD2 files immediately after each propagation pair.

2. **Consistency check**: All 10 flat-phase propagations produced identical J(z) to machine precision (max deviation = 0.00e+00). This validates that the simulation is deterministic.

3. **Section B — Trajectory clustering**: Computed 10×10 Pearson correlation matrices for both J(z) trajectories in dB space and phi_opt profiles (zero-mean, unit-norm normalized). Saved to `multistart_trajectory_analysis.jld2`.

4. **Section C — Spectral divergence**: For each of the 6 Phase 10 configs, computed D(z,f) = 10*log10(S_shaped / S_unshaped) at all 50 z-slices. Found z_3dB (first z where any frequency exceeds 3 dB divergence). Saved 6 JLD2 files.

5. **H1 formalization**: Loaded Phase 10 ablation data, computed per-band suppression loss, identified critical bands (>3 dB), and computed overlap fraction between SMF-28 and HNLF.

6. **H2 formalization**: Loaded Phase 10 shift perturbation data, fit a parabola to the ±1 THz central window, extracted 3 dB tolerance width.

7. **5 figures**: physics_11_01 through physics_11_05 at 300 DPI.

## Key Physics Findings

### Multi-Start Z-Dynamics

- **J(z=L) range**: -65.2 to -54.8 dB across 10 starts (10 dB spread despite identical fiber/pulse)
- **J(z) trajectory correlation (mean off-diagonal)**: 0.621
- **phi_opt structural similarity (mean off-diagonal)**: 0.091
- **Interpretation**: J(z) trajectories are significantly more correlated than the phi_opt profiles that generate them. Different phase structures converge to similar z-dynamics, suggesting fiber physics (not phase shape) dominates how J evolves. The suppression mechanism operates via the same physical channel regardless of the specific phi_opt solution found.

### Spectral Divergence

| Config | z_3dB (m) | z_3dB / L_fiber |
|--------|-----------|-----------------|
| SMF-28 L=0.5m P=0.05W | 0.0102 m | 2.0% |
| SMF-28 L=0.5m P=0.2W  | 0.0102 m | 2.0% |
| SMF-28 L=5m   P=0.2W  | 0.1020 m | 2.0% |
| HNLF   L=1m   P=0.005W| 0.0204 m | 2.0% |
| HNLF   L=1m   P=0.01W | 0.0204 m | 2.0% |
| HNLF   L=0.5m P=0.03W | 0.0102 m | 1.0% |

The spectral effect of the optimal phase appears in the first ~2% of fiber length across all configs. This confirms that the suppression mechanism works by modifying the spectrum very early in propagation.

### H1 Verdict: Spectrally Distributed Suppression

- SMF-28 critical bands (>3 dB loss when zeroed): 3/10
- HNLF critical bands: 10/10
- Overlap: 3/10 = 30%
- **Verdict confirmed**: HNLF requires all 10 spectral bands for suppression (fully distributed). SMF-28 uses a partial strategy (3 critical bands). The two fibers employ different spectral mechanisms.

### H2 Verdict: Sub-THz Spectral Feature Scale

- SMF-28 3 dB tolerance: 0.329 THz
- HNLF 3 dB tolerance: 0.330 THz
- Raman bandwidth: 13.2 THz
- Ratio: ~2.5% of Raman bandwidth
- **Verdict confirmed**: The optimal phase has ~40x finer spectral structure than the Raman gain bandwidth. This is sub-THz precision, consistent with constructive/destructive interference requirements in the nonlinear regime.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `for bar, val in zip(...)` — invalid Julia syntax**
- **Found during:** Task 1, first run attempt
- **Issue:** Julia requires `for (bar, val) in zip(...)` — missing parentheses caused ParseError
- **Fix:** Added parentheses around the destructuring target
- **Files modified:** scripts/physics_completion.jl
- **Commit:** d6a2e29

**2. [Rule 1 - Bug] `import PyPlot.matplotlib.patches as mpatches` — invalid Julia syntax**
- **Found during:** Task 1, first run attempt (would have failed at runtime)
- **Issue:** Julia does not support Python-style `import X as Y` syntax. Access via `PyPlot.matplotlib.patches` directly.
- **Fix:** Changed to `mpatches = PyPlot.matplotlib.patches` assignment
- **Files modified:** scripts/physics_completion.jl
- **Commit:** d6a2e29

**3. [Rule 1 - Bug] `beta_order=3` keyword rejected — Unicode kwarg required**
- **Found during:** Task 1, second run attempt
- **Issue:** `setup_raman_problem` uses `β_order` (Unicode beta), not `beta_order`. The docstring said "beta_order=3" but the actual API uses the Unicode symbol.
- **Fix:** Changed all occurrences to `β_order=3`
- **Files modified:** scripts/physics_completion.jl
- **Commit:** d6a2e29

All three bugs were auto-fixed inline before the successful run. The script completed in 28.5 seconds total wall time (dominated by the 10×2 = 20 forward propagations).

## Known Stubs

None. All data is wired from real propagations and Phase 10 JLD2 files. All 5 figures display actual computed physics.

## Self-Check: PASSED

All files verified to exist on disk. Task commit d6a2e29 confirmed in git log.
