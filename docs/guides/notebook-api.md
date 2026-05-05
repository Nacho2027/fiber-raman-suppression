# Notebook API Quickstart

The notebook-facing layer starts with FiberLab objects:

```julia
using FiberLab

fiber = Fiber(
    regime = :single_mode,
    preset = :SMF28,
    length_m = 2.0,
    power_w = 0.2,
)

experiment = Experiment(
    fiber,
    Control(variables = (:phase,)),
    Objective(kind = :raman_band);
    id = "smf28_phase_notebook",
    solver = Solver(max_iter = 30),
)

summarize(experiment)
```

During the migration, the FiberLab API can lower an `Experiment` into the
current TOML-backed execution format:

```julia
path = write_experiment_config(
    "configs/experiments/smf28_phase_notebook.toml",
    experiment,
)
```

Then run through the maintained execution gate:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl smf28_phase_notebook
```

The intended direction is for notebooks to call execution functions directly.
Until that migration is complete, configs are the compatibility bridge between
the high-level API and the existing runner.
