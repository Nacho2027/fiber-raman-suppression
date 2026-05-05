# Canonical Scripts

Maintained compatibility entry points.

Notebook and API work should start from `src/fiberlab/`. These scripts exist
for repeatable checks, old command workflows, and lab handoff automation.

Useful commands:

```bash
julia -t auto --project=. scripts/canonical/optimize_raman.jl --list
julia -t auto --project=. scripts/canonical/run_experiment.jl --list
julia -t auto --project=. scripts/canonical/run_sweep.jl --list
julia --project=. scripts/canonical/inspect_run.jl results/raman/<run_id>/
```

Keep wrappers thin. Put new user-facing behavior in `src/fiberlab/`; use
`scripts/lib/` only for transitional orchestration.
