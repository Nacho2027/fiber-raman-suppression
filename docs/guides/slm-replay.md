# SLM Replay

Export a saved phase mask into a device-neutral replay bundle.

## Export a run

```bash
julia --project=. scripts/canonical/export_run.jl results/raman/<run_id>/
```

## Replay with a profile

```bash
julia -t auto --project=. scripts/canonical/replay_slm_mask.jl   --run results/raman/<run_id>/   --profile configs/slm_profiles/generic_256px_phase.toml
```

The generic profiles are not vendor calibration files. Treat them as a clean
intermediate format until a real device profile exists.

## Check before lab use

- phase units and wrapping convention;
- pixel count and active aperture;
- wavelength and frequency-grid assumptions;
- whether amplitude effects are intentionally absent.
