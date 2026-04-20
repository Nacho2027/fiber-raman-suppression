# Seed: Decouple `PyPlot` from `src/MultiModeNoise.jl`

**Planted:** 2026-04-20 by Phase 25
**Trigger:** promote when import failures on headless machines or CI become load-bearing, or when a clean test/CI split is required.

## Problem

`src/MultiModeNoise.jl` still does `using PyPlot` at module load. That means any matplotlib/PyCall issue can break non-plotting workflows that only need the physics core.

## Why this is seed-sized, not bug-sized

- Plotting helpers are spread across `src/analysis/plotting.jl`, `scripts/visualization.jl`, and a large set of driver scripts.
- The safe refactor likely needs a dedicated compile-check pass over scripts and notebooks.

## Candidate directions

1. Move plotting imports behind script-level includes only.
2. Create a separate plotting/helper module for the script layer.
3. Add a CI smoke test that imports `MultiModeNoise` without any matplotlib backend configured.
