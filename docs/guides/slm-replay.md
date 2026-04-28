# Device-Agnostic SLM Replay

[<- docs index](../README.md) | [lab readiness](./lab-readiness.md)

SLM replay is the bridge between an ideal optimized simulation phase and the
phase a real pixelated pulse shaper can represent.

The supported abstraction is intentionally vendor-neutral:

```text
saved run artifact
    -> generic SLM replay profile
    -> replayed simulation-axis phase
    -> optional forward replay evaluation
    -> later vendor-specific export adapter
```

Do not treat a neutral replay bundle as a vendor-ready SLM file. It is the
common replay contract that vendor adapters should consume.

## Replay Profiles

Profiles live under `configs/slm_profiles/`. The first generic profiles are:

- `generic_128px_phase`
- `generic_256px_phase`

Each TOML profile records:

- active spectral window in THz
- number of effective SLM pixels
- interpolation rule
- outside-active-band policy
- phase wrapping convention
- bit depth and quantization
- calibration file references, if available
- replay acceptance threshold in dB

When real lab calibration exists, add a new profile rather than editing the
generic examples in place.

## Command

Create a replay bundle without running propagation:

```bash
julia -t auto --project=. scripts/canonical/replay_slm_mask.jl \
  results/raman/<run_dir>/ generic_128px_phase
```

Run a forward replay evaluation as well:

```bash
julia -t auto --project=. scripts/canonical/replay_slm_mask.jl \
  results/raman/<run_dir>/ generic_128px_phase --evaluate
```

`--evaluate` reconstructs the loaded phase on the simulation grid and runs a
single forward propagation. Use the same compute discipline as any other
substantial simulation.

## Bundle Contents

The bundle directory contains:

- `phase_profile_replayed.csv` - ideal and replayed phase on the simulation axis
- `pixel_phase_profile.csv` - sampled and loaded phase on the generic pixel axis
- `slm_replay_metadata.json` - profile metadata, source artifact, and optional
  ideal-vs-replayed suppression comparison

If `--evaluate` was used, the metadata includes the replayed Raman objective and
whether replay loss stayed below the profile threshold.

## Lab-Ready Interpretation

A mask is not SLM-lab-ready just because the ideal optimizer result is good.
For lab-facing claims, use the replayed mask:

1. Generate the replay bundle.
2. Run forward replay evaluation.
3. Check replay loss.
4. Inspect the replayed phase and pixel phase.
5. Only then convert the replay bundle into a vendor-specific file.

For first experiments, compare flat phase, a simple polynomial/chirp profile,
and the best replay-surviving optimized profile.
