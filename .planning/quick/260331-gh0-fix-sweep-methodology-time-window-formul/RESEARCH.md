# Research: Time Window Formula Fix

## The Bug

In `scripts/common.jl:202`, the SPM broadening estimate is:
```julia
Δω_SPM = gamma * P_peak * L_fiber           # "nonlinear phase bandwidth [rad/s]"
spm_ps = beta2 * L_fiber * Δω_SPM * 1e12    # "resulting temporal spread [ps]"
```

**The comment says `[rad/s]` but the quantity is dimensionless.** `γ × P0 × L` = φ_NL, the nonlinear phase in radians. It is NOT a frequency. To get spectral broadening in rad/s, you must divide by the pulse duration.

## Correct Physics (Agrawal, Ch. 4)

For a sech² pulse, SPM creates an instantaneous frequency chirp. The maximum frequency deviation is:

```
δω_max ≈ 0.86 × φ_NL / T0
```

where:
- φ_NL = γ × P0 × L_eff (nonlinear phase, radians)
- T0 = T_FWHM / 1.763 (sech² half-duration)
- 0.86 is the shape factor for sech² (max slope of |sech(τ)|²)
- L_eff = L for lossless fiber (our case: short lengths, no attenuation)

This SPM-broadened spectrum then disperses temporally via GVD:

```
T_SPM = |β₂| × L × δω_max
      = |β₂| × L × 0.86 × γ × P0 × L / T0
```

## Numerical Verification

### SMF-28 L=5m P_peak=11838W (the worst failure: J=-1.2 dB, 54% drift)

Parameters: γ=1.1e-3, β₂=2.17e-26, T0=185e-15/1.763=1.049e-13 s

- φ_NL = 1.1e-3 × 11838 × 5 = 65.1 rad
- δω_max = 0.86 × 65.1 / 1.049e-13 = 5.34e14 rad/s (84.9 THz)
- T_SPM = 2.17e-26 × 5 × 5.34e14 = 5.79e-11 s = **57.9 ps**
- Raman walk-off = 2.17e-26 × 5 × 8.17e13 × 1e12 = 8.86 ps
- Total = 57.9 + 8.86 + 0.5 = 67.3 ps → × safety 3.0 = **202 ps**

Current formula gives: **29 ps** (SPM contribution: ~0 ps)

This explains the 54% photon drift — the window is 7x too small.

### SMF-28 L=5m P=0.05W (P_peak=2959W, 51.7% drift)

- φ_NL = 1.1e-3 × 2959 × 5 = 16.3 rad
- δω_max = 0.86 × 16.3 / 1.049e-13 = 1.34e14 rad/s
- T_SPM = 2.17e-26 × 5 × 1.34e14 = 1.45e-11 = **14.5 ps**
- Raman walk-off = 8.86 ps
- Total = 14.5 + 8.86 + 0.5 = 23.9 ps → × 2.0 = **48 ps**

Current: **19 ps**. Should be 48 ps — explains the 51.7% drift.

### HNLF L=5m P=0.03W (P_peak=1774W, J=-4.5 dB, 26.6% drift)

Parameters: γ=10e-3, β₂=0.5e-26, T0=1.049e-13 s

- φ_NL = 10e-3 × 1774 × 5 = 88.7 rad
- δω_max = 0.86 × 88.7 / 1.049e-13 = 7.27e14 rad/s
- T_SPM = 0.5e-26 × 5 × 7.27e14 = 1.82e-11 = **18.2 ps**
- Raman walk-off = 0.5e-26 × 5 × 8.17e13 × 1e12 = 2.04 ps
- Total = 18.2 + 2.04 + 0.5 = 20.7 ps → × 3.0 = **63 ps**

Current: **8 ps**. Should be 63 ps — explains the catastrophic failure.

### SMF-28 L=0.5m P=0.05W (P_peak=2959W, SUCCESS: J=-57.9 dB)

- φ_NL = 1.1e-3 × 2959 × 0.5 = 1.63 rad
- δω_max = 0.86 × 1.63 / 1.049e-13 = 1.34e13 rad/s
- T_SPM = 2.17e-26 × 0.5 × 1.34e13 = 1.45e-13 = **0.00015 ps** (negligible)
- Raman walk-off = 0.89 ps
- Total = 0 + 0.89 + 0.5 = 1.39 ps → × 2.0 = 3 ps → clamped to **5 ps**

Current: **5 ps**. Correct! SPM is negligible at low φ_NL, confirming the formula works for low-power/short-fiber cases.

## Implementation

### Fix 1: Correct the SPM broadening formula

The function needs a `pulse_fwhm` parameter (in seconds) to convert φ_NL to actual spectral broadening:

```julia
function recommended_time_window(L_fiber; safety_factor=2.0, beta2=20e-27,
                                  gamma=0.0, P_peak=0.0,
                                  pulse_fwhm=185e-15)
    # ... existing walk-off calculation ...

    spm_ps = 0.0
    if gamma > 0 && P_peak > 0
        T0 = pulse_fwhm / 1.763              # sech² half-duration [s]
        phi_NL = gamma * P_peak * L_fiber     # nonlinear phase [rad]
        delta_omega = 0.86 * phi_NL / T0      # SPM spectral broadening [rad/s]
        spm_ps = beta2 * L_fiber * delta_omega * 1e12   # GVD temporal spread [ps]
    end
end
```

### Fix 2: Increase max_iter to 60

30 is too conservative. Data shows convergence at 6-20 iters for well-conditioned problems, but some points need 40-50. 60 gives headroom without making the sweep impractically slow with the larger Nt values from the window fix.

### Fix 3: Suppression-quality reporting

Current summary only reports convergence count (misleading). Add:
- J_after threshold classification: excellent (<-40 dB), good (<-30 dB), acceptable (<-20 dB), poor (>-20 dB)
- Suppression success rate in summary output

## Window Size vs Nt Impact

With the corrected formula, some points will need much larger windows:
- 48 ps → Nt = ceil(48/0.0105) = 4572 → 8192 (at floor, OK)
- 63 ps → Nt = ceil(63/0.0105) = 6000 → 8192 (at floor, OK)
- 202 ps → Nt = ceil(202/0.0105) = 19238 → **32768** (4x current!)

The L=5m P=0.20W point will need Nt=32768, making each iteration ~4x slower. At 60 iterations, that's a significant time investment but necessary for correct physics.

## Confidence Level

**99%+ confident** this is the correct fix. The dimensional analysis is unambiguous: γ×P×L gives radians, not rad/s. The corrected formula reproduces the observed failure modes (large drift at high φ_NL, no drift at low φ_NL) and gives physically reasonable window sizes.
