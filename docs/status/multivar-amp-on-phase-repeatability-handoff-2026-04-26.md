# Multivar Amplitude-On-Phase Repeatability And Handoff Review

Date: 2026-04-26

Run source: `V-ampphase-repeat2` on ephemeral burst VM

Launcher log: `results/burst-logs/parallel/20260426T1915Z/amp-on-phase-repeat2.log`

Heavy log: `results/burst-logs/V-ampphase-repeat2_20260426T191436Z.log`

Output directory:
`results/raman/multivar/amp_on_phase_20260426T1915Z_repeat2/`

## Question

Does the 2026-04-24 positive amplitude-on-fixed-phase result reproduce
deterministically enough to keep as a serious post-phase refinement candidate,
and is the resulting amplitude profile ready for lab handoff?

## Repeat Result

The repeat run reproduced the 2026-04-24 result to the displayed precision:

| Case | Final physics objective | Gap vs phase-only | Iterations | Amplitude range |
| --- | ---: | ---: | ---: | ---: |
| Phase-only reference | `-40.79 dB` | reference | `24` | `[1.000, 1.000]` |
| Amplitude on fixed phase | `-44.34 dB` | `-3.55 dB` better | `9` | `[0.908, 1.090]` |

The amplitude-on-phase result saved:

- `J_after = 4.358085790156e-05`
- `delta_J_dB = -3.546596464746`
- `iterations = 9`
- `converged = true`
- `E_opt = E_ref = 103.522487676`

The amplitude profile statistics were:

| Statistic | Value |
| --- | ---: |
| bins | `8192` |
| min | `0.908455` |
| max | `1.090233` |
| mean | `0.999560` |
| standard deviation | `0.006874` |
| 1st percentile | `0.974597` |
| 5th percentile | `0.999997` |
| median | `1.000000` |
| 95th percentile | `1.000000` |
| 99th percentile | `1.007608` |

Interpretation: most spectral bins remain effectively unchanged, with a sparse
bounded amplitude correction. Energy is unchanged in the stored result; this is
amplitude shaping on top of the fixed phase solution, not energy retuning.

## Verification

- The first launch attempt failed before science compute because the burst
  machine image was temporarily unavailable.
- `V-ampphase-repeat2` completed with `rc=0`.
- The ephemeral VM copied results back, released the heavy lock, and destroyed
  itself.
- The repeat was run from a clean `origin/main` worktree on the burst VM.
- The full standard image set was visually inspected for both cases:
  `phase_only_reference_phase_profile.png`,
  `phase_only_reference_phase_diagnostic.png`,
  `phase_only_reference_evolution.png`,
  `phase_only_reference_evolution_unshaped.png`,
  `amp_on_phase_phase_profile.png`,
  `amp_on_phase_phase_diagnostic.png`,
  `amp_on_phase_evolution.png`, and
  `amp_on_phase_evolution_unshaped.png`.
- The images were coherent and matched the expected interpretation: same fixed
  phase reference, bounded amplitude refinement, no malformed evolution plots.

## Hardware Handoff Review

This candidate is reproducible enough to keep alive, but it is not yet
lab-ready. The current result artifacts are research artifacts, not a complete
hardware handoff contract for an amplitude-capable shaper.

Before exposing this to the lab as anything more than an experimental second
stage, the repo needs an amplitude-aware export path that records:

- the frequency or wavelength grid used by the optimized amplitude profile
- the optimized phase on the same grid
- the dimensionless amplitude multiplier `A(omega)`
- interpolation rules from simulation grid to hardware pixel grid
- clipping behavior and minimum transmission floor
- insertion-loss normalization policy
- measured or assumed shaper transfer function
- provenance metadata linking the export to the JLD2/JSON run artifact
- a round-trip validation check that reloads the exported hardware payload and
  confirms it matches the simulated profile within stated tolerances

The bounded range `[0.908, 1.090]` is encouraging, but values above unity are
not automatically realizable on a loss-only amplitude shaper. A lab-facing
export must define whether the amplitude profile is normalized by global
attenuation, converted into a relative transmission mask, or rejected when it
cannot be represented by the available hardware.

## Decision

Advance fixed-phase amplitude shaping only as a validated research candidate.
Do not make it the default lab workflow yet.

Recommended sequencing:

1. Keep phase-only optimization as the canonical lab-ready path.
2. Add a documented amplitude export schema and validation fixture before any
   experimental handoff.
3. Run a small local robustness check around `L = 2 m`, `P = 0.30 W`.
4. Only then expose amplitude-on-phase as an optional second-stage notebook/API
   flow.
5. Continue to defer broad joint phase+amplitude optimization unless a new
   numerical or physical hypothesis justifies it.

## 2026-04-26 Export Follow-Up

The first amplitude-aware neutral export contract now exists in
`scripts/canonical/export_run.jl`. For artifacts with `amp_opt`, it writes
`amplitude_profile.csv`, records the `loss_only_normalized_to_max` hardware
policy in `metadata.json`, and writes `roundtrip_validation.json`.

The repeated artifact
`results/raman/multivar/amp_on_phase_20260426T1915Z_repeat2/amp_on_phase_result.jld2`
was exported to `/tmp/fiber_amp_export_check` as a verification run. The
round-trip report was complete over `8192` phase rows and `8192` amplitude rows,
with normalized transmission bounded by `[0.833266977342, 1.0]`.

This closes the first export-contract gap, but not the full lab-hardware gap:
the remaining work is calibration against the actual shaper pixel grid,
measured transfer function, and lab-specific clipping/attenuation policy.

## 2026-04-26 Robustness Follow-Up

A four-point local neighborhood check is documented in
`docs/status/multivar-amp-on-phase-robustness-2026-04-26.md`. All four nearby
points improved with amplitude-on-fixed-phase, but one lower-power point
improved by only `2.30 dB`, below the prior `3 dB` decision threshold.

Updated conclusion: amplitude-on-phase is reproducible and locally useful, but
its margin is operating-point dependent. It should become an optional
second-stage experimental workflow, not a default lab-ready optimizer.
