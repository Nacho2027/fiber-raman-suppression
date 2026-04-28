# Joint Multivariable Canonical Result: Negative At Current SMF-28 Point

Date: 2026-04-24

Run source: `V-multivar8` on ephemeral burst VM

Log: `results/burst-logs/V-multivar8_20260424T043923Z.log`

Output directory: `results/raman/multivar/smf28_L2m_P030W/`

## Question

Does the current joint phase+amplitude optimizer beat the maintained phase-only
optimizer at the canonical SMF-28 `L = 2 m`, `P = 0.30 W` research point?

## Result

No. The latest accepted joint-optimizer burst run completed successfully,
produced the required standard image sets, and returned a negative result:

| Case | Final objective | Improvement | Gap vs phase-only |
| --- | ---: | ---: | ---: |
| Phase-only | `-40.8 dB` | `-39.30 dB` | reference |
| Joint phase+amplitude, cold start | `-18.3 dB` | `-16.78 dB` | `+22.52 dB` worse |
| Joint phase+amplitude, warm start | `-31.2 dB` | `-29.72 dB` | `+9.58 dB` worse |

The joint reference-run success criterion was not met. The comparison plot also shows
the phase-only trace reaching a lower objective than either joint
multivariable trace.

## Follow-Up Ablation

This result has been narrowed by a follow-up amplitude-on-fixed-phase ablation:

- Follow-up run: `V-ampphase1`
- Follow-up output:
  `results/raman/multivar/amp_on_phase_20260424T055752Z/`
- Follow-up status:
  `docs/status/multivar-amp-on-phase-positive-result-2026-04-24.md`

That ablation found that amplitude-only shaping on top of the fixed phase-only
optimum improved the physics objective from `-40.79 dB` to `-44.34 dB`, a
`3.55 dB` improvement. Therefore, the correct conclusion is not "all
multivariable control is low-value"; it is "cold/warm joint phase+amplitude is
not ready, while fixed-phase amplitude shaping is a real but still experimental
candidate."

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

The current joint phase+amplitude control surface should not be promoted to a
lab-facing default. At this canonical point, cold-start joint optimization is
much worse than phase-only, and warm-starting the joint optimizer from the
phase-only optimum still underperforms phase-only by about `9.6 dB`.

This does not prove that all multivariable controls are useless. The subsequent
amplitude-on-fixed-phase ablation now shows the opposite: one narrow
multivariable variant is promising enough to keep alive. It does show that the
current joint optimizer/configuration is not ready for lab dependence.

## Recommendation

Keep joint multivariable optimization under `scripts/research/multivar/` and
label it experimental in user-facing docs/configs. Do not expose the joint
optimizer as a lab-ready workflow.

The amplitude-only-on-fixed-phase salvage pass passed its `3 dB` threshold.
Next work should focus on validating that narrow candidate, not broad joint
optimizer tuning.
