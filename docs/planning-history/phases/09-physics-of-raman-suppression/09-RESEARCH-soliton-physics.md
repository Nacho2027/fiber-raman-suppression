# Phase 9: Physics of Raman Suppression - Soliton Dynamics Research

**Researched:** 2026-04-02
**Domain:** Nonlinear fiber optics -- soliton dynamics, intrapulse Raman scattering, spectral phase shaping
**Confidence:** MEDIUM-HIGH (established physics; novel application to optimization interpretation)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Research-grounded explanations only. Everything must be backed by literature or rigorous analysis of the data. No hand-waving.
- **D-02:** Universal vs arbitrary is the central question. The phase must deliver a clear answer: Do optimal phases have predictable structure from fiber parameters, or is each solution an arbitrary point in a high-dimensional landscape?
- **D-03:** Build on existing Phase 6.1 infrastructure. Phase 6.1 Plan 01 built data loading, phase normalization, and Figures 1-4. Plan 02 (Figures 5-8) was executed but awaits human verification gate closure. Phase 9 should complete that work and extend with deeper analysis.
- **D-04:** Analyze ALL 24 sweep points + 10 multi-start runs.
- **D-05:** Physical basis decomposition is required. Project phi_opt onto interpretable physical components (polynomial chirp: GDD, TOD, FOD; sinusoidal modulation) and report explained variance.
- **D-06:** Output should be paper-quality.

### Claude's Discretion
- Choice of clustering/similarity metrics for phi_opt comparison
- Whether to include PCA/SVD analysis of the phase profiles
- Which literature to cite and how deep to go
- Figure layout and panel arrangement
- Whether polynomial projection uses weighted or unweighted least squares

### Deferred Ideas (OUT OF SCOPE)
- Multimode (M>1) extension
- Quantum noise computation on top of classical solution
</user_constraints>

## Summary

This research document establishes the theoretical physics framework for interpreting why the L-BFGS optimizer's spectral phase profiles suppress Raman scattering by 37-78 dB across 24 fiber configurations. The analysis identifies five distinct physical mechanisms through which spectral phase shaping can suppress intrapulse Raman energy transfer, and for each mechanism derives testable predictions that can be checked against the existing sweep data.

The central finding from the literature is that spectral phase shaping affects Raman scattering through a hierarchy of mechanisms operating at different scales: (1) peak power reduction via temporal pulse stretching (the GDD/chirp mechanism), (2) delay or prevention of soliton formation and fission (the effective-N mechanism), (3) disruption of the intrapulse Raman gain bandwidth overlap (the spectral reshaping mechanism), (4) redirection of nonlinear energy into dispersive waves rather than the Raman band (the phase-matching mechanism), and (5) destructive interference in the Raman gain integral via rapid phase oscillations (the coherent control mechanism). The key insight from Phase 6.1 -- that 98.9-99.9% of the optimized phase is NOT explained by polynomial (GDD/TOD) structure -- strongly suggests that the optimizer is exploiting mechanisms (3)-(5), which require high-order spectral phase structure that goes far beyond simple pulse stretching.

**Primary recommendation:** Decompose phi_opt into physical components -- polynomial (GDD, TOD, FOD) plus oscillatory residual -- and correlate the component strengths with fiber parameters (N_sol, L/L_D, L/L_NL, L/L_fiss) to determine which mechanisms dominate and whether the phase structure is predictable from characteristic length scales.

---

## A. Soliton Self-Frequency Shift (SSFS)

### A.1 The Gordon Formula

The soliton self-frequency shift was discovered experimentally by Mitschke & Mollenauer (1986) and explained theoretically by Gordon (1986). For a fundamental soliton propagating in a fiber with intrapulse Raman scattering, the center frequency shifts continuously toward lower frequencies (red-shift) at a rate:

```
d(Omega_p)/dz = -8 |beta_2| T_R / (15 T_0^4)
```

where:
- `beta_2` = group velocity dispersion [s^2/m]
- `T_R` ~ 3 fs = Raman response time for silica at 1.5 um (Agrawal, Ch. 5)
- `T_0` = soliton half-duration (related to FWHM by T_0 = FWHM / 1.763 for sech^2)

**The critical T_0^(-4) scaling** means SSFS is extremely sensitive to pulse duration. A factor of 2 reduction in T_0 increases the SSFS rate by a factor of 16.

**Confidence:** HIGH -- Gordon (1986), Agrawal "Nonlinear Fiber Optics" Ch. 5, confirmed by extensive experimental literature.

### A.2 SSFS for Our Parameters

For a 185 fs sech^2 pulse:
- T_0 = 185e-15 / 1.763 = 104.9 fs

For SMF-28 (beta_2 = -2.17e-26 s^2/m):
```
d(Omega_p)/dz = -8 * 2.17e-26 * 3e-15 / (15 * (104.9e-15)^4)
              = -5.21e-40 / (15 * 1.21e-52)
              = -5.21e-40 / 1.82e-51
              = -2.86e11 rad/s per meter
              = -45.6 GHz/m
              = -0.046 THz/m
```

Over L = 1 m, this gives approximately 0.046 THz red-shift for a fundamental soliton. Over L = 5 m, approximately 0.23 THz. The Raman band starts at 5 THz detuning (our `raman_threshold = -5.0` THz), so SSFS alone does NOT directly shift the carrier into the Raman measurement band for fundamental solitons in our short fibers.

However, for higher-order solitons (N > 1), fission produces fundamental solitons with shorter durations (smaller T_0), dramatically increasing the SSFS rate for each ejected soliton.

### A.3 How Spectral Phase Suppresses SSFS

**Mechanism 1: Temporal stretching reduces peak power.**
Adding GDD stretches the pulse temporally. A chirped sech^2 pulse has effective duration T_eff = T_0 * sqrt(1 + C^2) where C is the chirp parameter. This reduces peak power by the same factor, lowering the effective soliton number:

```
N_eff^2 = gamma * P_eff * T_eff^2 / |beta_2|
```

But P_eff = P_0 / sqrt(1 + C^2) and T_eff = T_0 * sqrt(1 + C^2), so:

```
N_eff^2 = gamma * P_0 * T_0^2 / |beta_2| = N^2 (unchanged!)
```

**This is a critical subtlety:** for a transform-limited sech^2 pulse, adding pure GDD (linear chirp) does NOT change the soliton number N. The soliton number is set by the time-bandwidth product, which is invariant under linear chirp. This means simple GDD alone cannot prevent soliton formation -- the chirped pulse will compress back to its transform limit during propagation and form solitons.

**Mechanism 2: Chirp delays soliton formation.**
While N is invariant, the distance at which soliton formation occurs changes. A positively chirped pulse in the anomalous dispersion regime first compresses (as GVD acts to dechirp it) before soliton dynamics take over. If the compression distance exceeds the fiber length, no solitons form. The compression distance for a chirped Gaussian is approximately:

```
z_compress ~ |C| * L_D / (1 + C^2)   (maximum compression point)
```

For C >> 1, z_compress ~ L_D / |C|, which shrinks. But the key point is that during the compression stage, the pulse is NOT a soliton and does not experience SSFS.

**Prediction A1:** If SSFS suppression via chirp delay is the primary mechanism, we should see phi_opt producing positive chirp (anomalous GVD regime) proportional to L_fiber/L_D, sufficient to push the compression point beyond the fiber end.

**Prediction A2:** The SSFS mechanism should show strong N-dependence (since SSFS rate scales as T_0^-4, and shorter ejected solitons from higher N fission shift faster). But our sweep data shows WEAK N-dependence with log-cost optimizer (Section 3.5 of SWEEP_ANALYSIS). This suggests SSFS suppression is NOT the sole mechanism, or the optimizer found a mechanism that works independently of N.

### A.4 Relevance Assessment

**Likely relevance: MODERATE for low N (1.3-1.8), LOW for high N (3.6-6.3).**

For near-fundamental solitons (N ~ 1.3), the SSFS rate is modest and the Raman energy transfer can be managed by temporal reshaping. For high N, fission produces multiple solitons with very short durations, and each independently undergoes strong SSFS -- the optimizer would need to prevent ALL of them, which is much harder via a single input spectral phase.

---

## B. Soliton Fission and Spectral Phase

### B.1 Fission Length

Higher-order solitons (N > 1) undergo periodic compression-expansion cycles. In the presence of perturbations (Raman, TOD, noise), the N-soliton breaks apart into N fundamental solitons at the fission length:

```
L_fiss = L_D / N
```

where L_D = T_0^2 / |beta_2| is the dispersion length and N = sqrt(gamma * P_0 * T_0^2 / |beta_2|) is the soliton number.

Ref: Dudley, Genty & Coen, Rev. Mod. Phys. 78, 1135 (2006).

### B.2 Fission Length for Our Parameters

| Config | N | L_D [m] | L_fiss [m] | L_fiber [m] | L/L_fiss |
|--------|---|---------|------------|-------------|----------|
| SMF28 P=0.05W | 1.3 | 0.507 | 0.390 | 0.5-5.0 | 1.3-12.8 |
| SMF28 P=0.10W | 1.8 | 0.507 | 0.282 | 0.5-5.0 | 1.8-17.7 |
| SMF28 P=0.20W | 2.6 | 0.507 | 0.195 | 0.5-5.0 | 2.6-25.6 |
| HNLF P=0.005W | 2.6 | 1.14* | 0.438 | 0.5-5.0 | 1.1-11.4 |
| HNLF P=0.010W | 3.6 | 1.14* | 0.317 | 0.5-5.0 | 1.6-15.8 |
| HNLF P=0.030W | 6.3 | 1.14* | 0.181 | 0.5-5.0 | 2.8-27.6 |

(*HNLF L_D uses beta_2 = -0.5e-26 s^2/m from the HNLF preset in common.jl -- note: SWEEP_ANALYSIS header says beta_2 = -1.1e-26 which differs from the code preset of -0.5e-26; if -1.1e-26: L_D = 0.524 m)

**Key observation:** For nearly ALL configurations, L_fiber > L_fiss. This means soliton fission has already occurred in every sweep point. The optimizer cannot prevent fission in most configurations -- the fiber is simply too long. It must instead control what happens AFTER fission.

### B.3 Pre-Chirp Effect on Fission

Research on chirp-controlled soliton fission (Genty et al., Appl. Phys. B, 2006) demonstrated that input pulse chirp controls when and how fission occurs:

1. **Positive chirp (C > 0) in anomalous dispersion:** The pulse first compresses (GVD dechirps it), reaching maximum compression at z ~ L_D * |C| / (1 + C^2), THEN undergoes fission. This delays fission onset.

2. **Negative chirp (C < 0) in anomalous dispersion:** The pulse broadens initially, reducing peak power and potentially avoiding the fission threshold entirely for moderate N.

3. **Large chirp (|C| >> 1):** The pulse duration is so stretched that its peak power is below the soliton threshold for a significant propagation distance. Fission may occur much later or not at all if L_fiber < z_fission_effective.

**Prediction B1:** If fission delay is the dominant mechanism, then the GDD component of phi_opt should scale approximately as:

```
GDD_optimal ~ C_optimal * T_0^2   (units: s^2, or equivalently fs^2)
```

where C_optimal is large enough that z_compress > L_fiber. This gives:

```
|C_optimal| > L_fiber / L_D = L_fiber * |beta_2| / T_0^2
```

For SMF-28 L=1m: |C| > 1.0/0.507 = 2.0, giving GDD > 2.0 * (104.9e-15)^2 / 2 = 1.10e-26 s^2 = 11,000 fs^2.

**Prediction B2:** BUT -- Phase 6.1 showed that GDD+TOD explains only 0.1-1.1% of phi_opt variance. If fission delay via GDD were the primary mechanism, we would expect the polynomial component to dominate (>50% variance). It does not. This strongly suggests fission delay is NOT the primary suppression mechanism.

### B.4 Post-Fission Soliton Control

Since fission has already happened for most configurations, the more relevant question is: **How does phi_opt control the properties of the ejected fundamental solitons?**

After fission of an N-soliton, the ejected solitons have amplitudes:

```
A_k = (2N - 2k + 1) * A_1     for k = 1, ..., N
```

where A_1 is the fundamental soliton amplitude. The first ejected soliton (k=1) carries the most energy and has the shortest duration:

```
T_k = T_0 / (2N - 2k + 1)
```

The first soliton has T_1 = T_0 / (2N-1). For N=2.6, T_1 ~ T_0/4.2 = 25 fs, giving SSFS rate 4.2^4 = 311x larger than the original pulse.

**The input spectral phase cannot change the soliton number N** (invariant under phase-only shaping), but it CAN change:
- The temporal shape, controlling WHEN maximum compression occurs
- The spectral distribution of energy, potentially redirecting energy away from the Raman band
- The relative phases of frequency components, affecting nonlinear interference

---

## C. Four-Wave Mixing vs Raman Competition

### C.1 The FWM-Raman Bandwidth Budget

In the anomalous dispersion regime, the third-order nonlinearity chi^(3) drives both:
1. **Instantaneous Kerr (FWM):** parametric four-wave mixing, generating symmetric sidebands
2. **Delayed Raman:** stimulated Raman scattering, generating asymmetric (red-shifted) energy transfer

These compete for the available nonlinear bandwidth. In the GNLSE as implemented in the codebase (simulate_disp_mmf.jl), the split is controlled by fR = 0.18:
- Kerr contribution: (1 - fR) = 0.82
- Raman contribution: fR = 0.18, convolved with h_R(omega) in frequency domain

### C.2 FWM Phase Matching

FWM requires phase matching. In the anomalous dispersion regime, the phase-mismatch for degenerate FWM with frequency detuning Omega from the pump is:

```
Delta_k = beta_2 * Omega^2 + 2 * gamma * P_0
```

Phase matching (Delta_k = 0) gives the parametric gain bands at:

```
Omega_PM = sqrt(-2 * gamma * P_0 / beta_2)
```

For SMF-28 at P=0.20W (P_peak ~ 13.4 kW):
```
Omega_PM = sqrt(2 * 0.0011 * 13400 / 2.17e-26)
         = sqrt(1.36e30)
         = 3.69e15 rad/s
         ~ 587 THz
```

This is vastly larger than the Raman shift (13.2 THz), meaning parametric FWM gain extends to enormous frequency offsets. However, the actual energy transfer depends on the spectral overlap of the field with these phase-matched frequencies.

### C.3 Spectral Phase and FWM Control

The input spectral phase phi(omega) directly affects which FWM pathways are phase-matched. By engineering phi(omega), the optimizer could:

1. **Enhance FWM into specific bands** that don't overlap with the Raman measurement window
2. **Create phase mismatch for Raman-band frequencies** specifically
3. **Redirect nonlinear energy into dispersive waves** rather than Raman Stokes

**Prediction C1:** If FWM redirection is the primary mechanism, we should see the output spectrum (with phi_opt) showing ENHANCED energy at specific non-Raman frequencies compared to the flat-phase case -- the energy that would have gone to Raman goes elsewhere via FWM instead.

**Confidence:** MEDIUM -- This mechanism is physically plausible but I found no specific literature on spectral phase optimization for FWM-vs-Raman steering.

---

## D. Temporal Pulse Reshaping Beyond GDD

### D.1 The Peak Power Reduction Limit

Simple GDD stretching reduces peak power by a factor of sqrt(1 + C^2). For our cost metric J = E_band / E_total, the Raman energy transfer scales approximately as:

```
J ~ g_R * P_peak * L_eff * exp(...)   (for spontaneous SRS onset)
```

The Raman threshold (Stolen & Johnson, 1972) is approximately:

```
P_threshold ~ 16 * A_eff / (g_R * L_eff)
```

For operation well above threshold (our regime), the Raman energy fraction scales roughly exponentially with g_R * P_peak * L_eff. A factor of 2 reduction in P_peak (C ~ 1.7, corresponding to ~3700 fs^2 GDD) would reduce J by many dB.

### D.2 But Our Results Exceed Simple GDD Predictions

The optimizer achieves 37-78 dB suppression. Simple peak power reduction via GDD would give:

For C = 10 (very large chirp), P_peak drops by factor sqrt(101) ~ 10, or 10 dB in P_peak. In the exponential Raman regime, this could give ~20-30 dB suppression. But:

1. We observe up to 78 dB suppression
2. The polynomial (GDD/TOD) content of phi_opt is only 0.1-1.1% of variance
3. The suppression is relatively N-independent (weak scaling)

This means **the dominant suppression mechanism is NOT simple peak power reduction** via GDD. The optimizer has found something more sophisticated.

### D.3 Sophisticated Temporal Reshaping Mechanisms

The 98.9-99.9% non-polynomial residual in phi_opt represents high-order spectral phase that creates complex temporal pulse shapes. These can:

1. **Create temporal pre-pulses and post-pulses:** Energy distributed into a train of sub-pulses, each below the Raman threshold individually, even though the total energy is unchanged.

2. **Create asymmetric temporal profiles:** A pulse with gradual leading edge and sharp trailing edge has different nonlinear dynamics than a symmetric sech^2. The Raman response (causal, h_R(t<0) = 0 as enforced in the codebase) means only the leading part of the pulse contributes to the delayed nonlinear response at any given point.

3. **Create rapid temporal oscillations:** If the temporal intensity oscillates on a timescale faster than the Raman response time (tau_1 ~ 12.2 fs, tau_2 ~ 32 fs for silica), the Raman convolution integral averages over these oscillations, reducing the effective Raman driving strength.

**Prediction D1:** If sub-pulse creation is the mechanism, the temporal intensity profile of the optimized pulse should show multiple peaks separated by ~100+ fs gaps.

**Prediction D2:** If rapid oscillation averaging is the mechanism, the temporal intensity should show structure on the ~10-30 fs scale (comparable to Raman response time).

**Prediction D3:** The temporal shape should be analyzable via IFFT of the phase-shaped spectral field. Compare the temporal peak power of phi_opt-shaped pulse vs flat-phase pulse: if peak power reduction explains < 30 dB of the ~60 dB suppression, there must be an additional coherent mechanism.

---

## E. Dispersive Wave Emission and Phase Matching

### E.1 Soliton-Dispersive Wave Resonance

When a soliton propagates in a fiber with higher-order dispersion (beta_3 nonzero), it can shed energy into a linear dispersive wave at a frequency omega_DW determined by the phase-matching condition:

```
beta(omega_DW) = beta_s(omega_DW)
```

where beta_s is the soliton wavenumber:

```
beta_s(omega) = beta(omega_s) + beta_1(omega_s) * (omega - omega_s) + gamma * P_s / 2
```

and beta(omega) is the fiber's full dispersion curve. The resonant DW frequency is typically in the normal-dispersion regime (blue-shifted from the zero-dispersion wavelength).

Ref: Akhmediev & Karlsson, Phys. Rev. A 51, 2602 (1995).

### E.2 Spectral Phase Control of Dispersive Waves

Recent work (Conforti et al., Opt. Express 29, 12723, 2021; and Bose et al., Results in Physics 17, 103130, 2020) demonstrated that **quadratic spectral phase (GDD/chirp) directly controls the efficiency and frequency of dispersive wave emission.** Key findings:

1. The sign of the chirp determines whether DW efficiency is enhanced or suppressed
2. Positive chirp (in anomalous regime) can enhance DW emission while suppressing Raman energy transfer
3. The DW resonant frequency shifts with applied chirp, potentially moving it outside or inside the Raman measurement band
4. Higher-order spectral phase (cubic = TOD-like, quartic = FOD-like) creates multiple DW emission bands

**Prediction E1:** The optimizer may be steering energy into DW channels that fall OUTSIDE the Raman measurement band (< -5 THz from carrier). If so, the output spectrum with phi_opt should show DW peaks at specific frequencies predicted by the phase-matching condition.

### E.3 Phase Matching for Our Fiber Parameters

For SMF-28 with beta_2 = -2.17e-26, beta_3 = 1.2e-40, the zero-dispersion frequency offset is:

```
Omega_ZDW = -beta_2 / beta_3 = 2.17e-26 / 1.2e-40 = 1.81e14 rad/s ~ 28.8 THz
```

This is in the blue-shifted direction from the 1550 nm carrier, corresponding to wavelengths around 1300 nm. Dispersive waves emitted at this offset would be in the BLUE part of the spectrum, far from the RED-shifted Raman band.

**This means the dispersive wave channel is a natural energy "drain" that competes with Raman.** Energy steered into dispersive waves goes to the blue, not the red. The optimizer could exploit this by enhancing DW emission, which removes energy from the soliton (reducing SSFS) and deposits it in the blue (outside the Raman measurement band).

---

## F. Coherent Control via Phase Oscillations

### F.1 The Raman Convolution Integral

In the GNLSE, the Raman nonlinear term involves a convolution in the time domain:

```
N_Raman(t) = fR * u(t) * integral[h_R(t-t') * |u(t')|^2 dt']
```

where h_R(t) is the Raman response function (causal, with characteristic times tau_1 ~ 12.2 fs and tau_2 ~ 32 fs). In the frequency domain (as implemented in simulate_disp_mmf.jl lines 46-54), this becomes a multiplication:

```
N_Raman(omega) = fR * FT{ u(t) * IFFT[h_R(omega) * FT[|u(t)|^2]] }
```

### F.2 Coherent Cancellation Mechanism

If the spectral phase phi(omega) creates temporal intensity oscillations |u(t)|^2 with frequency content near the peak of h_R(omega) (around 13.2 THz), these oscillations can either:

1. **Constructively interfere** with the Raman response, enhancing energy transfer (this is what happens with a transform-limited pulse whose bandwidth spans 13 THz)
2. **Destructively interfere** with the Raman response, suppressing energy transfer (this is what a carefully designed phi(omega) could achieve)

This is the mechanism most consistent with the observation that 99% of phi_opt is non-polynomial. High-order spectral phase creates precisely the temporal intensity modulations needed to destructively interfere with the Raman gain.

### F.3 Analogy to Coherent Control in Spectroscopy

This mechanism is directly analogous to coherent anti-Stokes Raman scattering (CARS) spectroscopy, where pulse shaping is routinely used to control which Raman transitions are excited or suppressed. The literature on CARS pulse shaping (Silberberg group, Dantus group) uses spectral phase masks to selectively excite or suppress specific vibrational modes.

**Prediction F1:** If coherent control is the mechanism, then the oscillatory content of the phi_opt residual (after removing polynomial terms) should show spectral features correlated with the Raman gain spectrum, specifically structure at detunings near +/- 13.2 THz from the carrier.

**Prediction F2:** The Fourier transform of the phi_opt residual (i.e., the temporal autocorrelation of the phase oscillations) should show peaks near the Raman response time scales (12-32 fs).

**Confidence:** MEDIUM -- This is the most speculative mechanism but also the most consistent with the Phase 6.1 finding that the optimizer uses complex non-polynomial phase.

---

## G. Analytical Scaling Laws

### G.1 Characteristic Length Scales

| Quantity | Symbol | Formula | Significance |
|----------|--------|---------|--------------|
| Dispersion length | L_D | T_0^2 / \|beta_2\| | Distance for dispersive broadening |
| Nonlinear length | L_NL | 1 / (gamma * P_peak) | Distance for 1 rad nonlinear phase |
| Soliton period | z_s | (pi/2) * L_D | Higher-order soliton recurrence |
| Fission length | L_fiss | L_D / N | Distance to soliton breakup |
| Walk-off length | L_W | T_0 / \|beta_2 * Omega_R\| | Raman walk-off (pump-Stokes temporal separation) |
| SSFS length | L_SSFS | 15 T_0^4 / (8 \|beta_2\| T_R) | Distance for 1-bandwidth SSFS shift |

### G.2 Regime Classification for Our Sweep Points

The ratio L_fiber / L_fiss determines the propagation regime:

- **L/L_fiss < 1:** Pre-fission. Soliton dynamics haven't started. Phase shaping can prevent fission entirely.
- **L/L_fiss ~ 1-3:** Early fission. Solitons are just forming. Phase shaping has maximum leverage.
- **L/L_fiss >> 3:** Post-fission. Multiple solitons propagating independently. Phase shaping must work through initial conditions.

From the table in Section B.2, nearly all configurations have L/L_fiss > 1, most have L/L_fiss > 2, and the L=5m points have L/L_fiss > 10. Yet suppression remains strong even at L/L_fiss >> 10 (e.g., HNLF L=5m P=0.010W: J_after = -65.3 dB with L/L_fiss ~ 15.8).

This is remarkable and argues against fission delay as the primary mechanism -- the optimizer achieves deep suppression even when fission has long since completed.

### G.3 Predicted Scaling of Optimal Phase

If the optimal phase structure were dominated by a single mechanism, we would expect specific scaling:

**If SSFS suppression (delay mechanism):**
- GDD component should scale as L_fiber / L_D (need larger chirp for longer fibers)
- Suppression should degrade steeply with N (more ejected solitons to control)

**If peak power reduction:**
- GDD component should scale as P_peak (need more stretching for higher power)
- Suppression should scale logarithmically with GDD

**If coherent Raman interference:**
- Phase oscillation amplitude should scale with fR * gamma * P_peak * L_fiber (stronger Raman drive needs stronger cancellation)
- Phase oscillation frequency content should peak near Raman detuning (13 THz)
- Suppression should be relatively N-independent (interference works on the Raman integral regardless of soliton structure)

**The sweep data is most consistent with the coherent interference mechanism (F)** because:
1. Suppression is weakly N-dependent (Section 3.5 of SWEEP_ANALYSIS)
2. Phase structure is 99% non-polynomial (Phase 6.1 finding)
3. Deep suppression (>50 dB) achieved even at L/L_fiss >> 10

---

## H. Testable Hypotheses for Phase 9 Analysis

### H1. Polynomial Basis Decomposition (addresses D-05)
Decompose each phi_opt into:
- GDD (phi_2): quadratic spectral phase
- TOD (phi_3): cubic spectral phase
- FOD (phi_4): quartic spectral phase
- Residual: phi_opt - polynomial fit

Report explained variance for each order. Phase 6.1 showed 0.1-1.1% for GDD+TOD; extending to FOD will determine if higher polynomial orders help.

**Test:** Plot explained variance vs polynomial order (2, 3, 4, 5, 6). Expect convergence to a small fraction (<5%) even at high order, confirming the optimizer uses intrinsically non-polynomial phase.

### H2. Oscillatory Residual Spectrum
Compute the power spectral density (PSD) of the phi_opt residual (after polynomial subtraction):

```
S_residual(f) = |FT{phi_residual(omega)}|^2
```

**Test:** Does S_residual show a peak near the Raman detuning (13.2 THz), or at the Raman response time scale (~30 THz corresponding to ~30 fs period)?

### H3. Temporal Intensity Analysis
For each sweep point, compute the temporal intensity |u(t)|^2 of the phase-shaped pulse:

```
u_shaped(t) = IFFT{ |u_0(omega)| * exp(i * phi_opt(omega)) }
```

**Test:** Compare peak power of shaped vs unshaped pulse. If peak power reduction accounts for < 30 dB of the total suppression, the remaining suppression must come from coherent mechanisms.

**Test:** Compute the autocorrelation of |u_shaped(t)|^2 and look for temporal structure on the Raman response time scale (10-50 fs).

### H4. Universal vs Arbitrary Phase Structure (addresses D-02)
For each pair of sweep points, compute a similarity metric between normalized phi_opt profiles (after Phase 6.1's normalization: remove offset + linear slope).

**Test:** Cluster the 24 phi_opt profiles by similarity. Do points with similar N_sol cluster together? Do points with similar L/L_D cluster? If universal structure exists, there should be clear clustering by physical parameters.

**Test:** Correlate the GDD component magnitude with L_fiber/L_D for each point. Correlate the oscillatory residual amplitude with gamma * P_peak * L_fiber.

### H5. Propagation Diagnostics
Re-propagate with phi_opt and record the spectral evolution at intermediate z positions.

**Test:** At what z does Raman energy first appear (for flat phase)? At what z does it appear (for phi_opt)? Is the onset simply delayed, or is it prevented entirely?

**Test:** Track the output spectrum's dispersive wave content. Is energy redirected to the blue (DW channel) when phi_opt is applied?

### H6. Multi-Start Phase Comparison
The 10 multi-start runs at N=2.6 (10.9 dB spread) found different local optima.

**Test:** Are the phase profiles at -60 dB qualitatively similar to each other but different from the -50 dB profiles? Or do all 10 look structurally different? This directly addresses whether there is a unique physical solution or a landscape of many solutions.

### H7. Raman Response Overlap
Compute the Raman gain weighted integral:

```
G_R = integral{ h_R(Omega) * S_intensity(Omega) dOmega }
```

where S_intensity is the power spectrum of |u(t)|^2 (the intensity fluctuation spectrum).

**Test:** Compare G_R for flat-phase vs phi_opt-shaped pulses. If the optimizer reduces this overlap integral, it directly confirms the coherent control mechanism.

---

## I. Mapping Mechanisms to Observed Results

### I.1 Key Observations to Explain

| Observation | Section | Implication |
|-------------|---------|-------------|
| 37-78 dB suppression | Sweep 2.1-2.2 | Far beyond simple peak power reduction (~10-20 dB max) |
| Weak N-dependence with log cost | Sweep 3.5 | Mechanism works regardless of soliton order |
| 99% non-polynomial phase | Phase 6.1 | Not simple GDD/TOD chirp |
| 10.9 dB multi-start spread | Sweep 2.3 | Multiple local optima exist but all are good |
| Works for both SMF-28 and HNLF | Sweep 2.1-2.2 | Mechanism generalizes across gamma values |
| More suppression at shorter L | Sweep trends | Consistent with fewer nonlinear lengths |
| Best: -78 dB at low N, short L | L=0.5m P=0.05W | Easiest case: near-linear propagation |

### I.2 Most Likely Mechanism Hierarchy

Based on the literature and consistency with observations:

1. **Primary: Coherent Raman interference (F)** -- The non-polynomial phase structure creates temporal intensity modulations that destructively interfere with the Raman response integral. This is N-independent and explains the 99% non-polynomial finding.

2. **Secondary: Dispersive wave redirection (E)** -- Some energy is steered into blue-shifted DW channels via phase-matching modification. This reduces the soliton energy available for Raman transfer.

3. **Tertiary: Peak power reduction (D)** -- The small polynomial component (~1%) provides a modest GDD that stretches the pulse slightly, contributing ~5-10 dB of the total suppression.

4. **Minimal: SSFS delay (A-B)** -- Relevant only for the short-fiber, low-N configurations where L/L_fiss < 2. Not the dominant mechanism.

---

## J. Essential Equations Reference

For convenient reference in the analysis scripts:

```julia
# Characteristic lengths
L_D = T0^2 / abs(beta2)                    # Dispersion length [m]
L_NL = 1.0 / (gamma * P_peak)              # Nonlinear length [m]
N_sol = sqrt(L_D / L_NL)                   # Soliton number
L_fiss = L_D / N_sol                        # Fission length [m]
z_s = pi/2 * L_D                           # Soliton period [m]

# SSFS rate (Gordon formula, fundamental soliton)
T_R = 3e-15                                 # Raman response time [s]
dOmega_dz = -8 * abs(beta2) * T_R / (15 * T0^4)  # [rad/s per m]

# Sech^2 pulse parameters
T0 = pulse_fwhm / 1.763                    # Half-duration [s]
P_peak = 0.881374 * P_cont / (pulse_fwhm * rep_rate)  # Peak power [W]

# Dispersive wave phase matching (linear approx)
Omega_ZDW = -beta2 / beta3                  # Zero-dispersion frequency offset [rad/s]

# Chirp parameter from GDD
C = 2 * GDD / T0^2                          # Dimensionless chirp parameter
```

---

## Sources

### Primary (HIGH confidence)
- Gordon, J.P., "Theory of the soliton self-frequency shift," Opt. Lett. 11, 662 (1986) -- SSFS T0^-4 scaling
- Mitschke & Mollenauer, "Discovery of the soliton self-frequency shift," Opt. Lett. 11, 659 (1986) -- SSFS discovery
- Dudley, Genty & Coen, "Supercontinuum generation in photonic crystal fiber," Rev. Mod. Phys. 78, 1135 (2006) -- Fission length L_fiss = L_D/N, comprehensive SCG review
- Agrawal, "Nonlinear Fiber Optics," Academic Press (6th ed., 2019) -- GNLSE, Raman response, soliton dynamics
- Akhmediev & Karlsson, Phys. Rev. A 51, 2602 (1995) -- DW phase-matching condition

### Secondary (MEDIUM confidence)
- [Genty et al., "Chirp-controlled soliton fission in tapered optical fibers," Appl. Phys. B, 2006](https://link.springer.com/article/10.1007/s00340-006-2138-9) -- Chirp control of fission dynamics
- [Conforti et al., "Manipulation of dispersive waves emission via quadratic spectral phase," Opt. Express 29, 12723 (2021)](https://opg.optica.org/oe/fulltext.cfm?uri=oe-29-8-12723&id=450003) -- Spectral phase control of DW emission
- [Bose et al., "Boosting dispersive wave emission via spectral phase shaping," Results in Physics 17, 103130 (2020)](https://www.sciencedirect.com/science/article/pii/S2211379720319690) -- DW control through cubic/quadratic spectral phase
- [Soliton Self-Frequency Shift: Experimental Demonstrations and Applications, PMC 2012](https://pmc.ncbi.nlm.nih.gov/articles/PMC3465838/) -- SSFS review with equations
- [In-amplifier soliton self-frequency shift optimization by pre-chirping, Opt. Lett. 50(7), 2025](https://opg.optica.org/ol/abstract.cfm?uri=ol-50-7-2117) -- Pre-chirp for SSFS control

### Tertiary (LOW confidence -- theoretical extrapolation)
- Coherent Raman interference mechanism (Section F) -- Extrapolated from CARS spectroscopy literature and GNLSE structure; not directly verified in optimization context
- FWM-Raman competition steering (Section C) -- Physically plausible, no direct literature on optimization for this purpose found

---

## Metadata

**Confidence breakdown:**
- SSFS physics (A): HIGH -- textbook-level, well-established equations
- Fission dynamics (B): HIGH -- well-established in SCG literature
- FWM-Raman competition (C): MEDIUM -- physics is known, application to optimization is novel
- Temporal reshaping (D): MEDIUM-HIGH -- basic mechanism well-known, quantitative predictions for 50+ dB suppression are novel
- Dispersive wave control (E): MEDIUM -- recent literature (2020-2021) directly relevant
- Coherent interference (F): MEDIUM -- strongest hypothesis for explaining our results, but least directly supported by existing literature
- Scaling laws (G): HIGH for individual formulas, MEDIUM for combined predictions

**Research date:** 2026-04-02
**Valid until:** Indefinite (established physics; specific predictions valid until tested against sweep data)
