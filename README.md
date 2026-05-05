# FiberLab

Julia-first FiberLab API for building, running, and inspecting nonlinear
fiber-optic optimization experiments.

The active user-facing model is:

```julia
using FiberLab

fiber = Fiber(regime = :single_mode, preset = :SMF28, length_m = 2.0, power_w = 0.2)
experiment = Experiment(fiber, Control(variables = (:phase,)), Objective(kind = :raman_band))
summarize(experiment)
```

The inherited low-level propagation code remains in `src/` as the physics
backend. New work should start from the FiberLab concepts: fibers, pulses,
grids, controls, objectives, solvers, experiments, and artifacts.

Python is not a supported API surface.

## Start

```bash
make install
make docs-check
make lab-ready
```

For the current compatibility execution path:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --list
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run research_engine_poc
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_poc
```

## Where Things Live

| Path | Purpose |
|---|---|
| `src/fiberlab/` | Notebook-facing FiberLab API |
| `src/simulation/`, `src/gain_simulation/`, `src/mmf_cost.jl` | Low-level physics backend |
| `configs/experiments/` | Serialized experiments for reproducible runs |
| `lab_extensions/` | Experimental controls and objectives |
| `scripts/canonical/` | Maintained compatibility entry points |
| `scripts/lib/` | Transitional runner/orchestration internals |
| `docs/` | Human-facing docs |
| `agent-docs/` | Minimal active agent context |
| `results/` | Generated artifacts; do not commit wholesale |

Start with [docs/README.md](docs/README.md) for the human doc map and
[llms.txt](llms.txt) for the compact agent source map.

## Archive Boundary

Old notebooks, raw result trees, cached fiber/data files, historical plans, and
superseded research drivers were moved out of the active repo:

```text
/Users/ignaciojlizama/RiveraLab/fiber-raman-results-vault/active-tree-archive-20260504/
```

Do not reintroduce archived code as active source. Promote reusable Julia logic
into the FiberLab API or the maintained backend first.
