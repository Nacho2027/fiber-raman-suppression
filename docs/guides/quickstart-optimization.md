# Quickstart: Optimization

Run the maintained SMF-28 optimization from the repo root:

```bash
make optimize
```

Equivalent direct command:

```bash
julia -t auto --project=. scripts/canonical/optimize_raman.jl
```

List named runs:

```bash
julia -t auto --project=. scripts/canonical/optimize_raman.jl --list
```

## Check the result

Find the newest result directory under `results/raman/`, then run:

```bash
julia --project=. scripts/canonical/inspect_run.jl results/raman/<run_id>/
```

Open the standard images and check that the plots render cleanly:

- `*_phase_profile.png`
- `*_evolution.png`
- `*_phase_diagnostic.png`
- `*_evolution_unshaped.png`

For handoff export:

```bash
julia --project=. scripts/canonical/export_run.jl results/raman/<run_id>/
```

## When not to use this

Do not use this path for large sweeps, MMF campaigns, or long-fiber runs on the
editing VM. Use the burst workflow for those.
