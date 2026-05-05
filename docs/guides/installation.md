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

```julia
using MultiModeNoise

fiber = Fiber(regime = :single_mode, preset = :SMF28, length_m = 2.0, power_w = 0.2)
experiment = Experiment(fiber, Control(variables = (:phase,)), Objective(kind = :raman_band))
summarize(experiment)
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
