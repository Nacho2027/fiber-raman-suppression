# Experiment Sweeps

This directory defines thin parameter sweeps over front-layer experiment
configs. A sweep chooses one safe parameter path, a list of values, and a base
experiment config from `configs/experiments/`.

The sweep layer is intended for novel parameter-space questions without
duplicating many TOML files by hand. The current example is Raman-focused
because that is the first implemented objective family, but the sweep contract
is intended for broader fiber-optic optimization campaigns as additional
objective families are promoted.

List approved experiment sweeps:

```bash
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --list
```

Validate every approved experiment sweep without launching compute:

```bash
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --validate-all
```

Dry-run one sweep:

```bash
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --dry-run smf28_power_micro_sweep
```

Execute a sweep only when every expanded case is local-safe and supported:

```bash
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --execute smf28_power_micro_sweep
```

Execution writes a timestamped sweep directory under `output_root`, copies the
sweep config, and writes `SWEEP_SUMMARY.md`.

The current sweep layer supports these parameter paths:

- `problem.L_fiber`
- `problem.P_cont`
- `problem.Nt`
- `problem.time_window`
- `solver.max_iter`
- `objective.kind`

Each expanded case is validated through the same experiment-spec contract before
it is eligible for execution.
