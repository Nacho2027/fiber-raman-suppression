# Multivar Amplitude-On-Phase Result: Positive Canonical Ablation

Date: 2026-04-24

Run source: `V-ampphase1` on ephemeral burst VM

Launcher log: `results/burst-logs/parallel/20260424T033354Z/amp-on-phase1.log`

Heavy log: `results/burst-logs/V-ampphase1_20260424T055207Z.log`

Output directory: `results/raman/multivar/amp_on_phase_20260424T055752Z/`

## Question

Given the maintained phase-only optimum at the canonical SMF-28 `L = 2 m`,
`P = 0.30 W` point, can amplitude-only shaping on top of the fixed phase improve
the physics objective by at least `3 dB`?

## Result

Yes. The focused ablation completed successfully and passed the threshold:

| Case | Final physics objective | Gap vs phase-only | Iterations | Amplitude range |
| --- | ---: | ---: | ---: | ---: |
| Phase-only reference | `-40.79 dB` | reference | `24` | `[1.000, 1.000]` |
| Amplitude on fixed phase | `-44.34 dB` | `-3.55 dB` better | `9` | `[0.908, 1.090]` |

The amplitude adjustment is modest, bounded by the configured `delta_bound =
0.10`, and improves the physics objective by `3.55 dB`.

## Verification

- `V-ampphase1` finished with `rc=0`.
- The ephemeral VM copied the modified result archive back and destroyed itself.
- The phase-only reference produced its trust report, JLD2/JSON artifacts, and
  full standard image set.
- The amplitude-on-phase result produced JLD2/JSON artifacts and the full
  standard image set.
- Standard images were visually inspected for both cases:
  `*_phase_profile.png`, `*_phase_diagnostic.png`, `*_evolution.png`, and
  `*_evolution_unshaped.png`.
- The generated summary has one bookkeeping issue: the committed script has
  been fixed to report the phase-only iteration count correctly in future runs.
  The run log shows the actual phase-only count was `24`.

## Interpretation

This changes the multivar conclusion. The broad joint phase+amplitude optimizer
should still stay experimental because cold and warm joint runs underperformed
phase-only. However, fixed-phase amplitude shaping is now a real candidate for
post-research validation.

This should not be promoted directly to lab default yet. The margin is just over
the `3 dB` decision threshold, and amplitude shaping introduces hardware-facing
questions that phase-only workflows avoid: calibration, clipping, insertion
loss, dynamic range, and whether the bounded amplitude profile maps cleanly to
the available SLM or pulse-shaper controls.

## Recommendation

Keep the joint optimizer out of lab-facing workflows. Keep the amplitude-on-phase
candidate alive as the only multivar path worth advancing.

Before lab rollout, validate amplitude-on-phase with:

1. A deterministic rerun with the same canonical config and explicit seed or
   recorded initialization assumptions.
2. A hardware-constrained export review of the amplitude profile.
3. A small local parameter check around `P = 0.30 W` and `L = 2 m` to ensure the
   gain is not a single-point artifact.
4. A notebook/API design that exposes this as an optional second-stage
   refinement, not as the default optimizer.
