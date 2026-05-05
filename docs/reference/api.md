# Public API

The high-level FiberLab API is defined in `src/fiberlab/api.jl` and exported
from the Julia package.

## Core Types

- `Fiber`
- `Pulse`
- `Grid`
- `Control`
- `Objective`
- `Solver`
- `ArtifactPolicy`
- `Experiment`

## Core Functions

- `summarize(experiment)`
- `experiment_config_text(experiment)`
- `write_experiment_config(path, experiment)`

## Current Boundary

The API layer is intentionally small. It establishes the product vocabulary and
notebook-facing construction path. Existing execution still runs through the
validated experiment config and runner layer. Future work should move execution
behind these API objects instead of adding more script-first workflows.
