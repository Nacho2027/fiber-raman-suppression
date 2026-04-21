# Phase 9: Physics of Raman Suppression - Unified Research

**Synthesized:** 2026-04-02
**Sources:** 09-RESEARCH-literature.md, 09-RESEARCH-soliton-physics.md, codebase analysis (2 agents)
**Confidence:** MEDIUM-HIGH

---

## Executive Summary

The L-BFGS optimizer achieves 37-78 dB Raman suppression across 24 (L,P) configurations via spectral phase shaping. Literature research identifies **five candidate mechanisms**, but three key observations from existing data narrow the field:

1. **99% non-polynomial phase** (Phase 6.1) — rules out simple GDD/chirp as dominant mechanism
2. **Weak N-dependence** (sweep Section 3.5) — rules out SSFS/fission-focused mechanisms
3. **Deep suppression at L/L_fiss >> 10** — rules out fission delay as primary mechanism

**Leading hypothesis: Coherent Raman interference** — the optimizer engineers high-order spectral phase that creates temporal intensity modulations destructively interfering with the Raman response integral at 13 THz detuning. This is analogous to CARS spectroscopy pulse shaping (Silberberg/Dantus groups).

**Novelty claim:** No prior work combines adjoint-based gradient optimization of input spectral phase with Raman suppression as cost functional. Closest: Tzang et al. Nature Photon. 2018 (spatial wavefront, genetic algorithm), Takeoka et al. Opt. Lett. 2001 (spectral phase for squeezing).

---

## Five Candidate Mechanisms

### 1. Peak Power Reduction via GDD (CPA analogy)
- GDD stretches pulse → lower peak power → reduced Raman gain
- **Prediction:** GDD explains most phi_opt variance
- **Status: RULED OUT** — GDD+TOD explains only 0.1-1.1% of variance. Simple stretching gives ~20 dB max; we observe 78 dB.

### 2. Soliton Fission Delay via Chirp
- Pre-chirp delays soliton compression/fission beyond fiber end
- **Prediction:** GDD scales as L_fiber/L_D, suppression degrades steeply with N
- **Status: RULED OUT as primary** — L_fiber > L_fiss for nearly all configs (fission already occurred). Deep suppression at L/L_fiss >> 10.

### 3. Effective N Reduction
- GDD does NOT change N (invariant under phase-only shaping in NLSE)
- Chirp delays when soliton dynamics manifest, but doesn't change N
- **Status: PARTIALLY RELEVANT** — may contribute but cannot explain 99% non-polynomial phase

### 4. Dispersive Wave Energy Redirection
- Spectral phase controls DW emission efficiency/frequency
- SMF-28 ZDW offset ~ 28.8 THz blue-shifted — DW goes to blue, away from Raman band
- **Status: PLAUSIBLE secondary mechanism** — needs verification via output spectrum analysis

### 5. Coherent Raman Interference (LEADING HYPOTHESIS)
- High-order spectral phase → temporal intensity modulations → destructive interference with Raman response h_R(t) at 13 THz
- Consistent with: 99% non-polynomial phase, weak N-dependence, deep suppression at all L/L_fiss
- Analogous to CARS pulse shaping for vibrational mode control
- **Status: STRONGEST hypothesis** — needs direct testing via residual spectrum analysis and Raman overlap integral

---

## Seven Testable Hypotheses (H1-H7)

| # | Test | What It Reveals | Method |
|---|------|-----------------|--------|
| H1 | Polynomial basis decomposition (GDD→FOD) | Whether any polynomial order explains phi_opt | Weighted least squares, report explained variance vs order |
| H2 | PSD of phi_opt residual | Whether residual has structure at 13 THz Raman detuning | FFT of residual after polynomial subtraction |
| H3 | Temporal intensity profile | Peak power reduction + temporal structure timescale | IFFT of phase-shaped field, compare shaped vs unshaped |
| H4 | Cross-sweep clustering | Universal vs arbitrary (D-02 central question) | Similarity metrics on normalized phi_opt; cluster by N, L/L_D |
| H5 | Propagation diagnostics | Where Raman energy appears/is prevented along z | Re-propagate with intermediate z snapshots |
| H6 | Multi-start phase comparison | Landscape structure (unique solution vs many optima) | Compare 10 multi-start phi_opt profiles at N=2.6 |
| H7 | Raman response overlap integral | Direct confirmation of coherent control mechanism | Compute G_R = integral{h_R(Omega) * S_intensity(Omega) dOmega} |

---

## Key Scaling Laws

| Quantity | Formula | Our Values |
|----------|---------|------------|
| Soliton number | N = sqrt(gamma * P_peak * T_0^2 / \|beta_2\|) | 1.3 — 6.3 |
| Dispersion length | L_D = T_0^2 / \|beta_2\| | 0.51 m (SMF-28), 1.14 m (HNLF) |
| Fission length | L_fiss = L_D / N | 0.18 — 0.44 m |
| SSFS rate | d(Omega)/dz ~ \|beta_2\| T_R / T_0^4 | ~0.046 THz/m (fundamental, SMF-28) |
| Walk-off length | L_W = T_0 / (\|beta_2\| * Omega_R) | ~0.058 m (SMF-28) |

---

## Existing Infrastructure (Reuse)

### Already Built (physics_insight.jl + visualization.jl)
- `normalize_phase()` — removes offset + linear group delay, -40 dB mask
- `decompose_phase_polynomial()` — GDD/TOD projection, residual fraction
- `compute_soliton_number()` — N from fiber params
- `_central_diff()` — for group delay d(phi)/d(omega)
- `build_lambda_axis_nm()` — frequency→wavelength conversion
- 8 insight figures (01-08) already coded in physics_insight.jl
- Data loading pattern: manifest.json + JLD2 merge

### JLD2 Fields Available Per Sweep Point
phi_opt (Nt,1), uomega0 (Nt,1), band_mask (Nt,), convergence_history, sim_Dt [ps], sim_omega0 [rad/ps], betas, gamma, fwhm_fs, fiber_name, L_m, P_cont_W, J_before, J_after, converged, iterations, Nt, time_window_ps

### Known Bug
SWEEP_REPORT.md shows 0/12 converged (NaN) because generate_sweep_reports.jl reads from aggregate JLD2 grids which may be stale. Individual per-point report.md files are correct.

---

## Key References

| # | Citation | Relevance |
|---|----------|-----------|
| 1 | Agrawal, Nonlinear Fiber Optics 6th ed. (2019) | GNLSE, Raman physics, soliton theory |
| 2 | Dudley, Genty, Coen, Rev. Mod. Phys. 78 (2006) | Soliton fission, SCG, L_fiss |
| 3 | Gordon, Opt. Lett. 11, 662 (1986) | SSFS theory, T_0^-4 scaling |
| 4 | Smith, Appl. Opt. 11, 2489 (1972) | SRS critical power formula |
| 5 | Blow & Wood, IEEE JQE 25, 2665 (1989) | GNLSE Raman response h_R(t) |
| 6 | Turke et al., Appl. Phys. B 83, 37 (2006) | Chirp-controlled soliton fission |
| 7 | Kormokar et al., Opt. Lett. 50, 2117 (2025) | Pre-chirp SSFS optimization |
| 8 | Maghrabi et al., Opt. Lett. 44, 3940 (2019) | Adjoint sensitivity for NLSE |
| 9 | Tzang et al., Nature Photon. 12, 368 (2018) | Wavefront shaping for SRS control |
| 10 | Takeoka et al., Opt. Lett. 26, 1592 (2001) | Spectral phase optimization for squeezing |
| 11 | Uddin, Rivera et al., Nature Photon. (2025) | Noise-immune quantum correlations |
| 12 | Sloan, Rivera et al., arXiv:2509.03482 (2025) | Spatiotemporal quantum noise control |

---

## Recommendations for Planning

### Plan 1: Phase Decomposition & Cross-Sweep Analysis (H1, H2, H4)
- Load all 24 sweep phi_opt + 10 multi-start phi_opt
- Extended polynomial decomposition (up to order 6)
- Residual PSD analysis (test for 13 THz feature)
- Cross-sweep similarity/clustering by physical parameters
- ~8-10 new figures

### Plan 2: Physical Mechanism Attribution (H3, H5, H6, H7)
- Temporal intensity profiles (shaped vs unshaped)
- Raman overlap integral computation
- Multi-start structural comparison
- Propagation diagnostics (if feasible without re-running — may use existing JLD2)
- ~6-8 new figures

### Plan 3: Synthesis & Paper Section (if warranted)
- Compile findings into coherent narrative
- Determine universal vs arbitrary answer
- Write paper-quality methods/results text
