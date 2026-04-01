---
quick_id: 260331-gh0
description: Fix sweep methodology — time window formula, max_iter, convergence reporting
date: 2026-03-31
status: complete
---

# Summary: Fix Sweep Methodology

## What Changed

### 1. Fixed SPM broadening formula (scripts/common.jl)

**Root cause:** `γ × P_peak × L` gives φ_NL (nonlinear phase in radians), NOT a frequency in rad/s. The code treated it as Δω, producing ~0 ps SPM contribution when it should produce tens of ps.

**Fix:** Added proper conversion: `δω_SPM = 0.86 × φ_NL / T0` where T0 = FWHM/1.763 (sech² half-duration). Added `pulse_fwhm` kwarg (default 185e-15 s) for backward compatibility.

**Impact on window sizes (SMF-28 examples):**
| Config | Before | After |
|--------|--------|-------|
| L=0.5m P=0.05W | 5 ps | 5 ps (unchanged — SPM negligible) |
| L=2.0m P=0.20W | 13 ps | ~27 ps |
| L=5.0m P=0.05W | 19 ps | ~48 ps |
| L=5.0m P=0.20W | 29 ps | ~202 ps |

### 2. Increased max_iter from 30 to 60 (scripts/run_sweep.jl)

Both `run_fiber_sweep()` and `run_multistart()` now use 60 iterations. Previous data showed some points still improving at iter 30; 60 gives sufficient headroom without making the sweep impractically slow.

### 3. Suppression-quality reporting (scripts/run_sweep.jl)

- Per-point logging now includes quality label: excellent (<-40 dB), good (<-30 dB), acceptable (<-20 dB), poor (>-20 dB)
- Summary output now shows suppression success rate alongside formal convergence count
- Previous analysis: 21/24 grid points achieved J < -30 dB despite only 4/24 formally converging — the old summary was misleading

## What Needs Re-running

The sweep must be re-run with `julia --project scripts/run_sweep.jl` to get results with the corrected window sizes. Previous results are invalid for points where SPM broadening was significant (L ≥ 2m or high power).

## Confidence

99%+ on the formula fix — dimensional analysis is unambiguous and the corrected formula explains all observed failure modes (54% drift at L=5m P=0.20W, 0.3% drift at L=0.5m P=0.05W).
