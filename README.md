# FiberLab

Julia-first FiberLab API for adjoint-based inverse design in nonlinear
fiber-optic systems.

The active user-facing model is a composable adjoint problem. Researchers pass
physics problems, controls, objectives, and models directly: controls decode
optimizer coordinates, objectives return a scalar cost and terminal adjoint
seed, and models provide the physical adjoint gradient.

```julia
using FiberLab

fiber = Fiber(preset = :SMF28_beta2_only, length_m = 1e-4, power_w = 1e-5, beta_order = 2)
grid = Grid(nt = 16, time_window_ps = 5.0, policy = :exact)
problem = fiber_problem(fiber; grid = grid, raman_threshold_thz = -0.25)

control = FullGridPhase(problem)
objective = raman_band_objective(problem; log_cost = false)
model = fiber_model(problem)

x0 = zeros(dimension(control))
result = solve(problem, control, objective, x0; max_iter = 1)
metrics(result)
```

Symbolic objects such as `Control(variables = (:phase,))` and
`Objective(kind = :raman_band)` are compatibility and reproducibility helpers.
They are not the conceptual center of the API. New user-facing work should be
expressed as fibers, pulses, grids, controls, objectives, adjoint contracts,
solvers, results, and figures.

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
