# Multivariable Canonical Result: Negative At Current SMF-28 Point

Date: 2026-04-24

Run source: `V-multivar8` on ephemeral burst VM

Log: `results/burst-logs/V-multivar8_20260424T043923Z.log`

Output directory: `results/raman/multivar/smf28_L2m_P030W/`

## Question

Does the current multivariable phase+amplitude optimizer beat the maintained
phase-only optimizer at the canonical SMF-28 `L = 2 m`, `P = 0.30 W` research
point?

## Result

No. The latest accepted burst run completed successfully, produced the required
standard image sets, and returned a negative result:

| Case | Final objective | Improvement | Gap vs phase-only |
| --- | ---: | ---: | ---: |
| Phase-only | `-40.8 dB` | `-39.30 dB` | reference |
| Joint phase+amplitude, cold start | `-18.3 dB` | `-16.78 dB` | `+22.52 dB` worse |
| Joint phase+amplitude, warm start | `-31.2 dB` | `-29.72 dB` | `+9.58 dB` worse |

The demo success criterion was not met. The comparison plot also shows the
phase-only trace reaching a lower objective than either multivariable trace.

## Verification

- `V-multivar8` finished with `rc=0`.
- The returned bundle contains phase-only, cold-start joint, and warm-start
  joint JLD2/JSON artifacts.
- The comparison image `multivar_vs_phase_comparison.png` renders and shows the
  negative result.
- Standard images were visually inspected for phase-only, cold-start joint, and
  warm-start joint outputs:
  - `*_phase_profile.png`
  - `*_phase_diagnostic.png`
  - `*_evolution.png`
  - `*_evolution_unshaped.png`
- The returned plots were generated before the latest footer/legend cosmetic
  cleanup, so some metadata blocks overlap lower labels. That is cosmetic and
  does not change the numerical conclusion; future standard plots use the
  cleaned layout.

## Interpretation

The current phase+amplitude control surface should not be promoted to a
lab-facing default. At this canonical point, adding amplitude freedom makes the
optimizer worse, not better. Warm-starting from the phase-only optimum still
underperforms phase-only by about `9.6 dB`, and cold-start joint optimization is
much worse.

This does not prove that all multivariable controls are useless. It does show
that the current joint optimizer/configuration is not ready for lab dependence.

## Recommendation

Keep multivariable optimization under `scripts/research/multivar/` and label it
experimental in user-facing docs/configs. Do not expose it as a lab-ready
workflow.

If one more salvage pass is justified, make it narrow:

1. Run amplitude-only-on-top-of-fixed-phase as the next ablation.
2. Require at least `3 dB` improvement over phase-only before considering any
   broader multivariable path.
3. If amplitude-only does not beat phase-only, close the current multivar lane
   as low-value for the canonical SMF-28 point and defer future work until a new
   physical hypothesis justifies it.

