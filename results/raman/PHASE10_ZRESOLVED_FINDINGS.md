# Phase 10 Z-Resolved Propagation Findings

**Date:** 2026-04-02
**Script:** `scripts/propagation_z_resolved.jl`
**Data:** 12 JLD2 files in `results/raman/phase10/`

---

## 1. Abstract

Phase 9 found that 84% of Raman suppression arises from "configuration-specific nonlinear interference" — effects that require propagation-resolved diagnostics to understand. This phase runs z-resolved forward propagations for 6 representative configurations (3 SMF-28 + 3 HNLF) spanning soliton numbers N_sol = 1.3 to 6.3, with 50 z-save points per fiber. Each configuration was propagated with flat phase (unshaped) and with phi_opt (shaped) to reveal WHERE Raman energy builds up and how the optimizer's phase delays or prevents this buildup.

## 2. Per-Configuration Results

| Configuration | N_sol | J₀ (dB) | J_after shaped (dB) | J_end unshaped (dB) | Onset z unshaped (m) | Onset z shaped (m) | Suppression gain (dB) |
|--------------|-------|---------|---------------------|---------------------|----------------------|---------------------|----------------------|
| SMF-28 N=1.3 | 1.3 | -31.9 | -77.6 | -31.9 | 0.082 | > L | 45.7 |
| SMF-28 N=2.6 | 2.6 | -3.8 | -71.4 | -3.8 | 0.020 | > L | 67.6 |
| SMF-28 N=2.6 (5m) | 2.6 | -1.1 | -36.8 | -1.1 | 0.102 | 0.204 | 35.7 |
| HNLF N=2.6 | 2.6 | -9.3 | -73.8 | -9.3 | 0.061 | > L | 64.5 |
| HNLF N=3.6 | 3.6 | -2.4 | -69.8 | -2.4 | 0.041 | > L | 67.4 |
| HNLF N=6.3 | 6.3 | -2.5 | -51.0 | -2.5 | 0.010 | > L | 48.5 |

## 3. Raman Onset Analysis

"Raman onset" is defined as the z-position where J(z) first exceeds 2× its initial value J(z=0). A value of '> L' means onset was not reached within the fiber length.

### SMF-28 N=1.3 (N_sol = 1.3, L = 0.5m)
- **Unshaped:** Raman onset at z = 0.082 m (16.3% of fiber length)
- **Shaped:** Raman onset not reached within fiber (effective suppression).

### SMF-28 N=2.6 (N_sol = 2.6, L = 0.5m)
- **Unshaped:** Raman onset at z = 0.020 m (4.1% of fiber length)
- **Shaped:** Raman onset not reached within fiber (effective suppression).

### SMF-28 N=2.6 (5m) (N_sol = 2.6, L = 5.0m)
- **Unshaped:** Raman onset at z = 0.102 m (2.0% of fiber length)
- **Shaped:** Raman onset at z = 0.204 m (4.1% of fiber length)

### HNLF N=2.6 (N_sol = 2.6, L = 1.0m)
- **Unshaped:** Raman onset at z = 0.061 m (6.1% of fiber length)
- **Shaped:** Raman onset not reached within fiber (effective suppression).

### HNLF N=3.6 (N_sol = 3.6, L = 1.0m)
- **Unshaped:** Raman onset at z = 0.041 m (4.1% of fiber length)
- **Shaped:** Raman onset not reached within fiber (effective suppression).

### HNLF N=6.3 (N_sol = 6.3, L = 0.5m)
- **Unshaped:** Raman onset at z = 0.010 m (2.0% of fiber length)
- **Shaped:** Raman onset not reached within fiber (effective suppression).

## 4. N_sol Regime Observations

### Low N_sol (N ≤ 2.0)

- **SMF-28 N=1.3** (N=1.3): shaped=-78dB, unshaped=-32dB

In the low-N regime, Raman scattering is inherently weak (the unshaped pulse may not accumulate significant Raman energy). The optimizer still finds phases that suppress residual Raman, but the absolute gains are limited by the weak nonlinearity.

### Medium N_sol (2.0 < N ≤ 3.0)

- **SMF-28 N=2.6** (N=2.6): shaped=-71dB, unshaped=-4dB
- **SMF-28 N=2.6 (5m)** (N=2.6): shaped=-37dB, unshaped=-1dB
- **HNLF N=2.6** (N=2.6): shaped=-74dB, unshaped=-9dB

The medium-N regime (around the N=2 soliton fission threshold) is where the optimizer typically achieves its highest suppression ratios. Z-resolved data reveals whether Raman energy is suppressed early (z-dependent prevention) or late (redistribution at the fiber end).

### High N_sol (N > 3.0)

- **HNLF N=3.6** (N=3.6): shaped=-70dB, unshaped=-2dB
- **HNLF N=6.3** (N=6.3): shaped=-51dB, unshaped=-2dB

In the high-N regime, soliton fission occurs early in the fiber, and the Raman self-frequency shift (SSFS) can dominate. The optimizer must reshape the pulse to prevent the sub-pulses from accumulating sufficient nonlinear phase for SSFS to set in.

## 5. Long-Fiber Degradation: SMF-28 5m

The SMF-28 L5m_P0.2W configuration achieves only -36.8 dB shaped vs -77.6 dB for the same N_sol at L=0.5m — a 40 dB degradation at longer fiber length. Z-resolved data answers: at what z does suppression break down?

No clear critical z detected — shaped J(z) remains relatively flat.

## 6. Preliminary Hypothesis

Based on the z-resolved observations:

1. **Delayed onset hypothesis:** The optimal spectral phase delays the z-position of Raman energy accumulation rather than preventing it entirely. This is consistent with temporal pulse stretching (16% of suppression from peak power reduction, found in Phase 9) creating a longer nonlinear interaction region before Raman becomes significant.

2. **Redistribution hypothesis:** The optimizer may redistribute Raman energy back into the pump band near the fiber end. If J_shaped(z) rises in the middle of the fiber but falls before the end, this would indicate a coherent energy transfer mechanism that cannot be seen from input/output analysis alone.

3. **Regime separation:** The N_sol > 2 vs N_sol ≤ 2 boundary (best clustering variable from Phase 9) should appear as a qualitative change in z-dynamics: above the threshold, the J(z) curve is more complex (possible non-monotonic evolution); below it, the curve may be nearly monotonic.

---

*Generated by Phase 10 z-resolved propagation pipeline. Data: results/raman/phase10/. Script: scripts/propagation_z_resolved.jl.*

