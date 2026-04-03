# Phase 10 Ablation Findings

**Generated:** 2026-04-02 20:47:40
**Canonical configs:** SMF-28 L=2m P=0.2W (multi-start) · HNLF L=1m P=0.01W (best suppression)
**Phase 9 context:** 84% of Raman suppression attributed to "configuration-specific nonlinear interference" — this phase asks which spectral frequencies of φ_opt carry that suppression.

---

## 1. Band Zeroing Results

Each of 10 equal-width sub-bands of the signal spectrum was individually zeroed using
a super-Gaussian window (order 6, 10% roll-off). Suppression loss = J_ablated - J_full in dB.

| Band | Center [THz] | Loss SMF-28 [dB] | Critical? | Loss HNLF [dB] | Critical? |
|------|-------------|-----------------|-----------|---------------|-----------|
|  1   |   -4.59     |   +3.63            | YES       |   +9.34         | YES       |
|  2   |   -3.57     |   +1.97            | no        |  +16.45         | YES       |
|  3   |   -2.55     |   +2.60            | no        |  +13.46         | YES       |
|  4   |   -1.53     |   +3.81            | YES       |  +18.28         | YES       |
|  5   |   -0.51     |   +1.98            | no        |  +27.68         | YES       |
|  6   |   +0.51     |   +7.12            | YES       |  +27.64         | YES       |
|  7   |   +1.53     |   +2.40            | no        |  +17.46         | YES       |
|  8   |   +2.55     |   +0.10            | no        |  +18.08         | YES       |
|  9   |   +3.57     |   -0.18            | no        |  +16.08         | YES       |
| 10   |   +4.59     |   -0.14            | no        |   +4.66         | YES       |
**Critical bands (>3 dB loss when zeroed):**
- SMF-28: bands 1, 4, 6
  Centers: -4.6, -1.5, 0.5 THz
- HNLF: bands 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
  Centers: -4.5, -3.5, -2.5, -1.5, -0.5, 0.5, 1.5, 2.5, 3.5, 4.5 THz

**Baselines:**
- SMF-28: φ_opt → -60.5 dB | Flat phase → -1.1 dB
- HNLF: φ_opt → -69.8 dB | Flat phase → -2.4 dB

---

## 2. Cumulative Ablation

Bands zeroed from spectral edges inward (outermost pair first, then next pair, etc.).
Reports the minimum number of central sub-bands needed to maintain suppression within 3 dB of full φ_opt.

| Step | Bands Remaining | J SMF-28 [dB] | J HNLF [dB] |
|------|----------------|--------------|------------|
| 0    | 10             |   -60.54      |   -69.79     |
| 1    |  8             |   -57.05      |   -61.51     |
| 2    |  6             |   -56.38      |   -50.07     |
| 3    |  4             |   -53.69      |   -48.43     |
| 4    |  2             |   -51.46      |   -47.11     |
| 5    |  0             |   -47.82      |   -38.74     |
**3 dB bandwidth requirement:**
- SMF-28: 10 sub-bands needed before 3 dB degradation
- HNLF: 10 sub-bands needed before 3 dB degradation

Full bandwidth is required for both configs — no spectral truncation is tolerated.

---

## 3. Scaling Robustness (3 dB Envelope)

Global scale factor α multiplied phi_opt. The 3 dB envelope spans scale factors where
suppression degrades by less than 3 dB relative to α=1.0.

- **SMF-28:** 3 dB envelope = [1.00, 1.00]
- **HNLF:** 3 dB envelope = [1.00, 1.00]

Scale factors tested: 0.00, 0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00

J at selected scales (SMF-28): -1.1, -40.4, -42.7, -43.9, -60.5, -46.6, -45.9, -45.7 dB
J at selected scales (HNLF): -2.4, -27.9, -31.7, -39.7, -69.8, -40.2, -40.8, -40.9 dB

---

## 4. Spectral Shift Sensitivity

phi_opt was translated by ±1, ±2, ±5 THz on the frequency grid using linear interpolation.
Shift sensitivity characterizes whether phi_opt is narrowly tuned to specific spectral features.

- **SMF-28:** 3 dB shift tolerance = [0.0, 0.0] THz
- **HNLF:** 3 dB shift tolerance = [0.0, 0.0] THz

J vs shift (SMF-28): -1.3, -22.2, -34.7, -60.5, -30.8, -24.3, -1.9 dB
J vs shift (HNLF): -7.9, -38.7, -46.1, -69.8, -38.4, -29.5, -5.2 dB

---

## 5. New Hypothesis: Mechanism Attribution

### H1: Phase suppression is spectrally distributed, not localized to a narrow pump-adjacent band

**Evidence:** If critical bands are scattered across the signal spectrum (not concentrated at DC or
pump frequency), this supports the conclusion that the optimizer exploits the full spectral phase
structure — consistent with the 84% non-polynomial phase finding from Phase 9.

**Falsified by:** A single band accounting for >10 dB of suppression while all others contribute <1 dB.

### H2: phi_opt is spectrally broad relative to the Raman detuning (13.2 THz)

**Prediction:** The spectral shift tolerance should be much narrower than 13.2 THz.
If phi_opt degrades by 3 dB with only 1-2 THz shift, the optimal phase encodes spectral
features on a sub-THz scale — finer than the Raman gain bandwidth.

**Implication:** The optimizer is exploiting interference at the spectral scale of the Raman
gain profile (few THz), not just the pump carrier.

### H3: Amplitude-sensitive nonlinear interference (not classical chirp management)

**Evidence from scaling:** If J_scaled degrades rapidly for α ≠ 1.0 (narrow 3 dB envelope),
the suppression depends on the precise amplitude of phase modulation — not just its spectral shape.
This is inconsistent with a simple chirp (GDD, TOD) interpretation, where scaling would shift
the soliton order but maintain qualitative behavior.

**Comparison with Phase 9:** Phase 9 found GDD + TOD explains only ~16% of the phase structure.
The remaining 84% must create precise amplitude-dependent interference — the scaling experiment
tests whether this interference is robust (broad envelope) or fragile (narrow envelope).

### H4: SMF-28 and HNLF exploit similar spectral regions despite different fiber parameters

**Test:** Compare critical_smf vs critical_hnlf — do the same sub-band indices appear?
If yes: the optimizer finds the same spectral strategy regardless of fiber nonlinearity γ and β₂.
If no: the mechanism is fiber-specific, consistent with the multi-start correlation = 0.109 finding
(different phi_opt profiles, each tuned to their specific fiber).

---

## 6. Comparison with Phase 9 Findings

| Phase 9 Finding | Ablation Evidence |
|----------------|-------------------|
| 84% non-polynomial phase structure | Band zeroing tells us which spectral regions this structure occupies |
| Multi-start correlation = 0.109 | Scaling robustness tells us how precisely the amplitude must be tuned |
| N_sol > 2 vs ≤ 2 clustering | SMF-28 (N≈2.6) vs HNLF (N≈3.6) band comparison probes fiber-type dependence |
| H5 (propagation diagnostics) deferred | Phase 10 Plan 01 addresses H5 directly via z-resolved snapshots |

---

## 7. Practical Implications for Pulse Shaping

- **3 dB scaling envelope:** Determines required precision of pulse shaper amplitude calibration.
- **3 dB shift tolerance:** Determines required carrier frequency stability of the shaped pulse.
- **Critical bands:** Guide which spectral regions require the highest phase resolution (most actuators).
