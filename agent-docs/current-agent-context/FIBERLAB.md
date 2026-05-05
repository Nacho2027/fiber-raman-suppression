# FiberLab API

The active product direction is the FiberLab API for fiber-optic optimization.

Start API-facing work from `src/fiberlab/` and the exported concepts:
`Fiber`, `Pulse`, `Grid`, `Control`, `Objective`, `Solver`, `Experiment`, and
`ArtifactPolicy`.

Treat older `scripts/lib/` runner code as transitional implementation. Do not
make that directory the conceptual center of new work. Configs in
`configs/experiments/` serialize experiments for reproducibility; they are a
bridge, not the primary API.
