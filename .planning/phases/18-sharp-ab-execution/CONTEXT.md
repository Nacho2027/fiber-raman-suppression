# Phase 18 — Sharpness A/B Execution (Session G follow-up)

**Opened:** 2026-04-19 (integration of Session G).
**Status:** Code committed on `main`; execution pending on the burst VM.

## Background

Session G prepared three slim drivers for the Phase 14 sharpness-aware-vs-vanilla A/B comparison. The agent hit Opus-4.7-side issues mid-Phase 16 and never launched the runs. See `BIG_WARNING.md` in this directory.

## Scope

Run the existing drivers. No code changes expected unless the compile-check surfaces a stale-API issue.

## Task list

1. Compile-check all 3 scripts against current main. If any reference `compute_noise_map_modem` or any other archived symbol, patch to use `src/_archived/analysis_modem.jl` (or remove the reference).
2. Verify `scripts/sharp_ab_slim.jl` calls `save_standard_set(...)` at the end. If not, wire it following the template in `scripts/standard_images.jl`.
3. Launch 3 burst-VM runs in sequence via `~/bin/burst-run-heavy` (see BIG_WARNING.md for exact commands).
4. Produce `results/raman/phase14-sharp-ab/FINDINGS.md` with the A/B verdict.

## Definition of done

- 3 JLD2s + standard-images set for each.
- FINDINGS.md states: does sharpness-aware beat vanilla on post-quantization robustness? By how many dB?
- σ_3dB (perturbation tolerance) compared head-to-head.

## Depends on

- Phase 14 baseline on main (already present).
- Phase 17 σ_3dB methodology from Session D (already merged).
