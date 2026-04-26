# Multivar Amplitude-On-Phase Local Robustness Check

Date: 2026-04-26

Run source: `V-ampphase-robust4` on ephemeral burst VM

Launcher log: `results/burst-logs/parallel/20260426T1955Z/amp-on-phase-robust4.log`

Heavy log: `results/burst-logs/V-ampphase-robust4_20260426T200843Z.log`

Output directories:
`results/raman/multivar/amp_on_phase_20260426T1955Z_robust_*`

## Question

Does the reproduced canonical amplitude-on-fixed-phase improvement persist in a
small neighborhood around `L = 2.0 m`, `P = 0.30 W`?

## Result

The result is positive but not uniformly above the `3 dB` decision threshold.
All four nearby points improved after amplitude shaping, but one lower-power
neighbor improved by only `2.30 dB`.

| Point | Phase-only | Amp-on-phase | Improvement | Iterations | A range | Verdict |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `L=1.8 m`, `P=0.30 W` | `-39.67 dB` | `-42.84 dB` | `3.17 dB` | `9` | `[0.902, 1.100]` | pass |
| `L=2.2 m`, `P=0.30 W` | `-37.93 dB` | `-43.34 dB` | `5.42 dB` | `13` | `[0.900, 1.100]` | pass |
| `L=2.0 m`, `P=0.27 W` | `-42.74 dB` | `-45.04 dB` | `2.30 dB` | `6` | `[0.909, 1.094]` | below threshold |
| `L=2.0 m`, `P=0.33 W` | `-43.73 dB` | `-49.51 dB` | `5.78 dB` | `10` | `[0.944, 1.073]` | pass |

Together with the repeated center point (`3.55 dB` improvement at `L=2.0 m`,
`P=0.30 W`), this supports the narrower conclusion that fixed-phase amplitude
refinement is a real local improvement mechanism. It does not support promoting
amplitude-on-phase to a default lab workflow with a hard `3 dB` guarantee across
nearby operating points.

## Verification

- The first ephemeral retry failed before compute due to C3 quota exhaustion.
- A permanent-burst retry was stopped before compute after its SSH launcher
  stalled without creating result directories.
- `V-ampphase-robust3` reached the VM but failed before compute due to nested
  shell quoting.
- `V-ampphase-robust4` completed with `rc=0`, copied results back, and
  destroyed the ephemeral VM.
- Each point produced the full standard image set for both the phase-only
  reference and amplitude-on-phase result.
- Representative visual inspection completed:
  - best gain case `L=2.0 m`, `P=0.33 W`: inspected
    `amp_on_phase_phase_profile.png` and `amp_on_phase_evolution.png`
  - threshold-fail case `L=2.0 m`, `P=0.27 W`: inspected
    `amp_on_phase_phase_profile.png`, `amp_on_phase_evolution.png`, and
    `amp_on_phase_phase_diagnostic.png`
  - length neighbors `L=1.8 m` and `L=2.2 m` at `P=0.30 W`: inspected
    `amp_on_phase_phase_profile.png`
- The inspected images were coherent and showed no malformed standard plots.

## Interpretation

The science direction is now clearer:

- Broad joint phase+amplitude optimization remains deferred.
- Fixed-phase amplitude shaping is reproducible and locally useful.
- The gain is operating-point dependent; the lower-power neighbor still
  improves, but does not meet the previous `3 dB` pass/fail threshold.
- Lab readiness should expose this only as an optional second-stage refinement
  with explicit result inspection, not as a guaranteed improvement path.

## Recommendation

Do not spend effort tuning broad joint multivariable optimization now. The
highest-value next step is to make the optional two-stage amplitude workflow
usable and honest:

1. keep phase-only as the canonical lab workflow
2. expose amplitude-on-phase as an experimental second-stage command/notebook
3. require export validation and visual inspection before handoff
4. report the achieved improvement per run instead of promising a fixed gain
5. defer hardware-specific calibration until a real shaper pixel grid and
   measured transfer function are available

## 2026-04-26 Workflow Follow-Up

The first maintained wrapper for this path is
`scripts/canonical/refine_amp_on_phase.jl`. It exposes dry-run planning,
parameterized `L`/`P`, amplitude bounds, iteration caps, and optional export
through the existing amplitude-aware handoff bundle.

This wrapper is intentionally documented as experimental and optional. It does
not change the default lab workflow, which remains phase-only optimization plus
inspection and export.
