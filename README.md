# FiberLab

Julia-first FiberLab API for adjoint-based inverse design in nonlinear
fiber-optic systems.

The active user-facing model is a composable adjoint problem. Researchers pass
physics problems, controls, objectives, and models directly: controls decode
optimizer coordinates, objectives return a scalar cost and terminal adjoint
seed, and models provide the physical adjoint gradient.

```julia
using FiberLab

fiber = Fiber(preset = :SMF28, length_m = 2.0, power_w = 0.2)
grid = Grid(nt = 1024, time_window_ps = 12.0, policy = :exact)
problem = fiber_problem(fiber; grid = grid, raman_threshold_thz = -13.2)

control = controls(
    phase_control(problem; basis = polynomial_basis(problem, 0:3), bounds = (-3.0, 3.0)),
    amplitude_control(problem; bounds = (0.8, 1.2)),
    energy_control(),
)
objective = raman_band_objective(problem)

result = solve(problem, control, objective; max_iter = 4)
metrics(result)
report = standard_report(problem, result; output_dir = "results/demo", tag = "demo")
display_report(report)  # shows PNGs inline in notebooks
```

Symbolic objects such as `Control(variables = (:phase,))` and
`Objective(kind = :raman_band)` are compatibility and reproducibility helpers.
They are not the conceptual center of the API. New user-facing work should be
expressed as fibers, pulses, grids, controls, objectives, adjoint contracts,
solvers, results, and figures.

The inherited low-level propagation code remains in `src/` as the physics
backend. New work should start from the FiberLab concepts: fibers, pulses,
grids, controls, objectives, solvers, experiments, and artifacts.

FiberLab also has an experimental OSA comparison seam for sealed single-mode
forward results. It applies the wavelength Jacobian and an explicit Gaussian
RBW observation model, then produces a hashed shape-only report. See the
[notebook guide](docs/guides/notebook-api.md#osa-spectrum-comparison) for the
strict limits; synthetic tests do not yet establish compatibility with a real
Rivera Lab export.

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
| `examples/` | Runnable Julia notebooks for Raman, multivariable, multimode, and reduced-basis workflows |
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
