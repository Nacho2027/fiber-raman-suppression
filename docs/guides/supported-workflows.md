# Supported Workflows

The supported surface is Julia-only. The preferred mental model is the
FiberLab API; the current execution path still lowers experiments into
checked configs.

## Notebook API

```julia
using FiberLab

fiber = Fiber(regime = :single_mode, preset = :SMF28, length_m = 2.0, power_w = 0.2)
experiment = Experiment(fiber, Control(variables = (:phase,)), Objective(kind = :raman_band))

summarize(experiment)
```

See [Notebook API Quickstart](notebook-api.md) for the current bridge from API
objects to runnable configs.

## Experiment Configs

Configs are the maintained compatibility path for reproducible runs:

```bash
./fiberlab configs
./fiberlab plan research_engine_poc
./fiberlab run research_engine_poc
./fiberlab latest research_engine_poc
```

Equivalent direct Julia commands:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --list
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run research_engine_poc
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_poc
```

## Lab Handoff Smoke

```bash
make docs-check
make lab-ready
make golden-smoke
```

Use these as permanent gates:

- `make docs-check`: verifies the short agent/human documentation maps and
  catches broken documentation structure.
- `make lab-ready`: validates all maintained configs, front-layer behavior, and
  fast regression tests without producing a long-lived science result.
- `make golden-smoke`: runs one real supported smoke experiment and verifies
  the artifact bundle, standard images, and export handoff.

`make golden-smoke` writes generated output under `results/raman/smoke/`. That
output is ignored by git and should be pruned after verification unless a run is
intentionally promoted into human-facing docs:

```bash
SMOKE_KEEP=0 make prune-smoke
```

## Experimental Work

Do not add new research drivers under `scripts/`. Promote reusable logic into
`src/fiberlab/` or an extension contract, then record lane status in
[Research Verdicts](../research-verdicts.md).
