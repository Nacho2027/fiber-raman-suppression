# S02: Result Serialization

**Goal:** Add structured result serialization to every optimization run in raman_optimization.
**Demo:** Add structured result serialization to every optimization run in raman_optimization.

## Must-Haves


## Tasks

- [x] **T01: 05-result-serialization 01** `est:12min`
  - Add structured result serialization to every optimization run in raman_optimization.jl.

Purpose: Phase 6 (cross-run comparison) and Phase 7 (parameter sweeps) need to load run results without re-running simulations. This phase adds JLD2 binary files per run and a JSON manifest that indexes all runs.

Output: Modified raman_optimization.jl that saves `{save_prefix}_result.jld2` per run and updates `results/raman/manifest.json` after each run. Updated Project.toml with JLD2 and JSON3 dependencies.

## Files Likely Touched

- `Project.toml`
- `scripts/raman_optimization.jl`
