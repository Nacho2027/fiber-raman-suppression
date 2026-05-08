# Installation

Install Julia 1.12.x, then instantiate the project:

```bash
make install
```

Check the local environment:

```bash
make doctor
```

This is a Julia-first repo. There is no supported Python package or Python API.

## First Julia API Check

This check uses direct behavior objects:

```julia
using FiberLab

fiber = Fiber(preset = :SMF28_beta2_only, length_m = 1e-4, power_w = 1e-5, beta_order = 2)
grid = Grid(nt = 16, time_window_ps = 5.0, policy = :exact)
problem = fiber_problem(fiber; grid = grid, raman_threshold_thz = -0.25)

control = FullGridPhase(problem)
objective = raman_band_objective(problem; log_cost = false)
model = fiber_model(problem)
x0 = zeros(dimension(control))

check_adjoint_gradient(
    model,
    control,
    objective,
    x0;
    coordinate_indices = [2, 9],
)
```

## First Compatibility Commands

```bash
./fiberlab configs
./fiberlab plan research_engine_poc
./fiberlab run research_engine_poc
./fiberlab latest research_engine_poc
```

Large simulations should run on suitable compute with Julia threading enabled:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_poc
```
