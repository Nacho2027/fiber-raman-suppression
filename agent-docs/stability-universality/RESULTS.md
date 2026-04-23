# Phase 31 Stability Probe Results

Generated: 2026-04-23T19:28:34 UTC

## Scope

This run evaluated locally available Phase 31 profiles, the regenerated Phase 17 baseline fixed mask, and a local Phase 16 long-fiber endpoint artifact.

Existing Phase 31 transfer and `sigma_3dB` metrics were reused from `results/raman/phase31/transfer_results.jld2` and `results/raman/phase31/followup/path_comparison.jld2`.
Forward perturbation probes used candidate-matched setups. Pixelation and smoothing were applied only on the active spectral band, leaving out-of-band phase untouched. Noise used `1` trials per sigma.

## Existing Transfer Metrics

| Candidate | Native J (dB) | sigma_3dB (rad) | HNLF gap (dB) | +5% FWHM gap | +10% P gap | +5% beta2 gap |
|---|---:|---:|---:|---:|---:|---:|
| `poly3_transferable` | -26.50 | NaN | 0.29 | -0.46 | 10.51 | -0.95 |
| `cubic32_reduced` | -60.77 | 0.143 | 16.51 | -0.60 | 1.08 | 0.45 |
| `cubic128_reduced` | -67.60 | 0.072 | 21.50 | -0.73 | 6.11 | 0.08 |
| `cubic32_fullgrid` | -67.16 | 0.070 | 22.31 | 2.52 | 7.93 | 1.64 |
| `zero_fullgrid` | -55.75 | 0.230 | 11.47 | -0.07 | 1.64 | 1.61 |
| `simple_phase17` | -76.86 | NaN | NaN | NaN | NaN | NaN |
| `longfiber100m_phase16` | -54.77 | NaN | NaN | NaN | NaN | NaN |

## Rankings

- Deepest native profile: `simple_phase17` at -76.86 dB.
- Best HNLF transfer gap: `poly3_transferable` at 0.29 dB.
- Widest finite measured noise basin: `zero_fullgrid` at 0.230 rad.
- No 3 dB crossover inside the existing sigma ladder: `poly3_transferable`, `simple_phase17`, `longfiber100m_phase16`.

## Forward Probe Highlights

- `poly3_transferable`: noise 0.05 rad mean gap 0.10 dB; active-band 128-pixel gap 0.00 dB; active-band 9-point smoothing gap 0.01 dB; wrapped SLM 128x10 gap 8.16 dB.
- `cubic32_reduced`: noise 0.05 rad mean gap 1.17 dB; active-band 128-pixel gap 44.07 dB; active-band 9-point smoothing gap 14.98 dB; wrapped SLM 128x10 gap 59.65 dB.
- `cubic128_reduced`: noise 0.05 rad mean gap 1.91 dB; active-band 128-pixel gap 51.04 dB; active-band 9-point smoothing gap 21.82 dB; wrapped SLM 128x10 gap 66.48 dB.
- `cubic32_fullgrid`: noise 0.05 rad mean gap 1.33 dB; active-band 128-pixel gap 50.51 dB; active-band 9-point smoothing gap 21.37 dB; wrapped SLM 128x10 gap 66.04 dB.
- `zero_fullgrid`: noise 0.05 rad mean gap 0.43 dB; active-band 128-pixel gap 39.08 dB; active-band 9-point smoothing gap 9.20 dB; wrapped SLM 128x10 gap 35.79 dB.
- `simple_phase17`: noise 0.05 rad mean gap 8.64 dB; active-band 128-pixel gap 38.96 dB; active-band 9-point smoothing gap 15.88 dB; wrapped SLM 128x10 gap 45.31 dB.
- `longfiber100m_phase16`: noise 0.05 rad mean gap 0.22 dB; active-band 128-pixel gap 54.05 dB; active-band 9-point smoothing gap -0.06 dB; wrapped SLM 128x10 gap 54.34 dB.

## Decision Table

| Role | Candidate | Reason |
|---|---|---|
| Simple publishable mask | `poly3_transferable` | best transfer and essentially no hardware sensitivity in this probe |
| Deep but fragile mask | `simple_phase17` | deepest native result, but very large noise and hardware losses |
| Deep canonical structured mask | `cubic128_reduced` | strong depth, but local and hardware-fragile |
| More robust deep-ish reference | `zero_fullgrid` | shallower, but widest finite noise basin among tested finite-sigma masks |
| Best simple surrogate family result | low-order fits are robust but shallow | the deep masks do not compress into a simple fixed mask without losing tens of dB |

## Interpretation

- `poly3_transferable` remains the simple-transfer baseline: shallow, but nearly unchanged on HNLF in existing metrics.
- Cubic continuation candidates are much deeper but have large HNLF gaps and narrow `sigma_3dB` values.
- `zero_fullgrid` is less deep but has the widest measured Phase 31 noise basin, matching the earlier depth/robustness tradeoff.
- The regenerated Phase 17 baseline now sits clearly in the 'deep but fragile' bucket.
- For `cubic128_reduced` and `cubic32_fullgrid`, fitted `GDD`, `GDD+TOD`, `GDD+TOD+FOD`, and `GDD+DCT4` surrogates are far more hardware-stable but collapse from about `-67 dB` native depth to about `-1 dB` to `-18 dB`. The deep branch is not captured by a small smooth family.
- For `simple_phase17`, the fitted smooth surrogates cluster near `-31.5 dB` and are extremely robust, which means the spectacular `-76.9 dB` mask depends on structure that the simple fits throw away.
- Phase 16 long-fiber endpoint artifact was available locally and entered the fixed-mask panel.
