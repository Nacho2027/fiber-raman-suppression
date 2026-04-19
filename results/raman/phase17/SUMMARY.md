---
phase: 17-simple-phase-profile-stability-study
plan: "01"
session: D-simple
branch: sessions/D-simple
created: 2026-04-17
verdict: SHARP_LUCKY (primary) + SIMPLE_PHASE_IS_GOOD_WARM_START_INITIALIZER (secondary)
---

# Phase 17 — Simple Phase Profile Stability Study

## Headline Verdict

**SHARP_LUCKY** — σ_3dB = 0.025 rad. The visually simple phase sits on a *razor-sharp*
minimum: a 3-rad Gaussian perturbation below the 0.05-rad threshold already costs 7.9 dB
of suppression (median over 20 samples). The shaper calibration envelope typical of
an SLM (≥ 0.05 rad rms phase error) would immediately lose most of the -77 dB
advantage.

### Secondary finding — simple phase is a good *warm-start initializer*, not a *flat basin*

Eval-only transfer is catastrophic (0 / 7 SMF-28 targets retain J within 3 dB of
warm-reopt), but L-BFGS re-optimised from the baseline φ_opt on nearby configs reaches
`-70 … -82 dB in 6–40 iterations` — including HNLF at -79.5 dB (a fiber the baseline
was never computed for). Interpretation: the simple-phase profile lives in a *stable
manifold of many nearby basins*, so the simplicity is a useful **initialisation prior**
rather than a **generalisation property of one attractor**.

This reframes the "simplicity = physically meaningful structure" intuition: low-Φ_NL
attractors ARE simpler than high-Φ_NL ones (baseline: 7 stationary points vs. Phase 13
canonical's 16 — Pearson r = 0.94 stationary-count vs. J_dB across 4 optima), but
simplicity predicts neither basin width nor parameter transferability on its own.

## What Was Built

1. `scripts/simple_profile_driver.jl` — baseline + perturbation + transferability stages
2. `scripts/simple_profile_metrics.jl` — gauge-fixed TV, entropy, stationary-point metrics
3. `scripts/simple_profile_synthesis.jl` — figures + this SUMMARY

## Key Numbers

- Baseline: J_final = -76.862 dB (expected -77.6 ± 1 dB) in 25.02 s over 21 iter
- Nonlinear phase Φ_NL = 1.63 rad, P_peak = 2959.1 W
- Perturbation: 5 σ × 20 samples = 100 tasks in 45.2 s
- σ_3dB (interp) = 0.025 rad
- Transferability: 11 targets evaluated in 257.3 s
- Simplicity winner: stationary (r = 0.941, N = 4 optima)

## Figure Index

- `results/images/phase17/phase17_01_perturbation_curve.png`
- `results/images/phase17/phase17_02_transferability_table.png`
- `results/images/phase17/phase17_03_simplicity_vs_suppression.png`
- `results/images/phase17/phase17_04_synthesis.png`

## Data Index

- [✓] `results/raman/phase17/baseline.jld2`
- [✓] `results/raman/phase17/perturbation.jld2`
- [✓] `results/raman/phase17/transferability.jld2`
- [✓] `results/raman/phase17/simplicity.jld2`

## Hypothesis Summary Table

| Criterion | Threshold | Observed | Pass? |
|---|---|---|---|
| σ_3dB ≥ 0.20 rad (FLAT) | ≥ 0.20 | 0.025 | NO |
| σ_3dB ≤ 0.05 rad (SHARP) | ≤ 0.05 | 0.025 | YES |
| SMF-28 transfer ≥ 3/7 ≤ 3 dB gap | ≥ 3 | 0/7 | NO |
| Baseline = simplest of N=4 optima | YES | YES | YES |

## Hand-off to Session E

See `.planning/notes/simple-profile-handoff-to-E.md`.

