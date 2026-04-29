# Canonical Scripts

Maintained command-line entry points.

Useful commands:

```bash
julia -t auto --project=. scripts/canonical/optimize_raman.jl --list
julia -t auto --project=. scripts/canonical/run_experiment.jl --list
julia -t auto --project=. scripts/canonical/run_sweep.jl --list
julia --project=. scripts/canonical/inspect_run.jl results/raman/<run_id>/
```

Keep wrappers thin. Put shared behavior in `scripts/lib/` or `src/`.
