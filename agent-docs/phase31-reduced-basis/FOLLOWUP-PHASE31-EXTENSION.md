# Phase 31 Follow-Up — Continuation To Full-Grid

## Ranked Paths

| Path | Seed | Final J (dB) | Gain vs seed (dB) | σ_3dB | HNLF gap | +10% P gap | +5% β₂ gap | +5% FWHM gap |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| cubic128_full | cubic 128 | -67.60 | -0.00 | 0.072 | 21.50 | 6.11 | 0.08 | -0.73 |
| cubic32_full | cubic 32 | -67.16 | 6.39 | 0.070 | 22.31 | 7.93 | 1.64 | 2.52 |
| linear64_cubic128_full | linear 64 | -64.40 | 0.46 | 0.100 | 20.74 | 8.57 | -0.44 | 2.27 |
| linear64_full | linear 64 | -64.23 | 0.29 | 0.093 | 20.80 | 11.69 | 0.24 | 1.07 |
| full_zero | zero | -55.75 | NaN | 0.230 | 11.47 | 1.64 | 1.61 | -0.07 |

## Verdict

- Deepest path: `cubic128_full` at -67.60 dB.
- Best HNLF transfer: `full_zero` with gap 11.47 dB.
- Widest noise basin: `full_zero` with σ_3dB = 0.230 rad.

## Interpretation

- The follow-up asks whether reduced-basis continuation can survive a final full-grid polish or whether the full-grid step collapses back toward the zero-init basin.
- Paths are ranked primarily by final depth, then by smaller HNLF transfer gap, then by larger sigma_3dB.
- Use this file together with `results/raman/phase31/followup/path_comparison.jld2` and the standard-image set in `results/raman/phase31/followup/images/`.
