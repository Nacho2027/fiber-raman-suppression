# T01: 05-result-serialization 01

**Slice:** S02 — **Milestone:** M002

## Description

Add structured result serialization to every optimization run in raman_optimization.jl.

Purpose: Phase 6 (cross-run comparison) and Phase 7 (parameter sweeps) need to load run results without re-running simulations. This phase adds JLD2 binary files per run and a JSON manifest that indexes all runs.

Output: Modified raman_optimization.jl that saves `{save_prefix}_result.jld2` per run and updates `results/raman/manifest.json` after each run. Updated Project.toml with JLD2 and JSON3 dependencies.

## Must-Haves

- [ ] "After running raman_optimization.jl, each of the 5 run directories contains a _result.jld2 file with fiber params, J_before, J_after, convergence history, and wall time"
- [ ] "A top-level results/raman/manifest.json exists and lists all 5 runs with their scalar summaries in a format readable by jq or any JSON parser"
- [ ] "The serialization adds no new positional arguments or breaking changes to run_optimization() — the existing call sites still work unchanged"

## Files

- `Project.toml`
- `scripts/raman_optimization.jl`
