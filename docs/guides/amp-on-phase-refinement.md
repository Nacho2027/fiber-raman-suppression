# Optional Amp-On-Phase Refinement

[docs index](../README.md) | [project README](../../README.md)

This workflow is an experimental second stage, not the default lab optimizer.
Use it only after a phase-only run is understood and after the standard images
are inspected.

## Why It Exists

The maintained phase-only workflow remains the canonical lab path. Recent
multivariable checks showed that bounded amplitude shaping on top of a fixed
phase solution is reproducible and locally useful, but the improvement is
operating-point dependent. In a four-point neighborhood around `L = 2.0 m`,
`P = 0.30 W`, all points improved, but one lower-power point improved by only
`2.30 dB`, below the prior `3 dB` decision threshold.

The right user-facing contract is therefore:

1. run or identify the phase-only baseline
2. run optional amp-on-phase refinement
3. inspect the standard images
4. export only if the achieved improvement and amplitude profile are acceptable

## Dry Run

```bash
julia -t auto --project=. scripts/canonical/refine_amp_on_phase.jl \
  --dry-run \
  --tag trial_L2p0_P0p30 \
  --L 2.0 \
  --P 0.30 \
  --export
```

The dry run prints the output directory, result artifact, and export location
without launching compute.

## Execute

Run substantial refinement jobs on burst, using the existing heavy-job wrapper.
The command below is the local command that the burst wrapper should run from a
clean `origin/main` worktree:

```bash
julia -t auto --project=. scripts/canonical/refine_amp_on_phase.jl \
  --tag trial_L2p0_P0p30 \
  --L 2.0 \
  --P 0.30 \
  --phase-iter 50 \
  --amp-iter 60 \
  --delta-bound 0.10 \
  --export
```

The result directory is:

```text
results/raman/multivar/amp_on_phase_<tag>/
```

## Required Closeout

Before using the result for lab handoff, check:

- `amp_on_phase_summary.md`
- `phase_only_reference_*` standard images
- `amp_on_phase_*` standard images
- `export_handoff/metadata.json`, if `--export` was used
- `export_handoff/amplitude_profile.csv`, if `amp_opt` is present
- `export_handoff/roundtrip_validation.json`

The export uses the neutral `loss_only_normalized_to_max` amplitude policy. It
does not replace lab-specific shaper calibration, pixel-grid interpolation, or
measured transfer-function validation.
