# S03: Cross Run Comparison And Pattern Analysis

**Goal:** Add all cross-run comparison and pattern analysis visualization functions to `scripts/visualization.jl`.
**Demo:** Cross-run comparison and pattern analysis visualization functions added to `scripts/visualization.jl`.

## Must-Haves


## Tasks

- [x] **T01: 06-cross-run-comparison-and-pattern-analysis 01**
  - Add all cross-run comparison and pattern analysis visualization functions to `scripts/visualization.jl`.

Purpose: Provide the function library that `run_comparison.jl` (Plan 02) will call. Separating function definitions from orchestration follows the established codebase pattern where visualization.jl holds all plotting functions and scripts call them.

Output: 5 new functions appended to visualization.jl before the include guard `end`, ready for Plan 02 to import and call.
- [x] **T02: 06-cross-run-comparison-and-pattern-analysis 02**
  - Create `scripts/run_comparison.jl` that re-runs all 5 optimization configs to generate JLD2 files, then loads results and produces 4 comparison figures (summary table, convergence overlay, 2 spectral overlays) plus phase decomposition analysis and soliton number annotations.

Purpose: This is the Phase 6 entry point per D-01. It produces the cross-run comparison artifacts that make all 5 optimization runs interpretable side-by-side for lab meetings and advisor reviews.

Output: 1 new script file + 4 PNG figures in results/images/ + updated manifest.json with soliton numbers.

## Files Likely Touched

- `scripts/visualization.jl`
- `scripts/run_comparison.jl`
