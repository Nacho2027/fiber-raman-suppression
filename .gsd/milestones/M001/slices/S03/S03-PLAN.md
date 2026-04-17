# S03: Structure Annotation And Final Assembly

**Goal:** Add metadata annotation helper, expand J cost annotation, and create merged 2x2 evolution comparison function in visualization.
**Demo:** Add metadata annotation helper, expand J cost annotation, and create merged 2x2 evolution comparison function in visualization.

## Must-Haves


## Tasks

- [x] **T01: 03-structure-annotation-and-final-assembly 01**
  - Add metadata annotation helper, expand J cost annotation, and create merged 2x2 evolution comparison function in visualization.jl.

Purpose: Implements the core visualization functions needed for Phase 3 -- the metadata block that makes every figure self-documenting (META-01), the expanded J before/after annotation on comparison figures (META-02), the merged evolution figure with column titles and fiber length (META-03, ORG-01). These functions are created here; the optimization script call-site wiring happens in Plan 02.

Output: Updated visualization.jl with _add_metadata_block!, plot_merged_evolution, and metadata keyword support on plot_optimization_result_v2, plot_amplitude_result_v2, and plot_phase_diagnostic. Updated smoke tests.
- [x] **T02: 03-structure-annotation-and-final-assembly 02**
  - Wire metadata threading and merged evolution call sites in both optimization scripts.

Purpose: Connects the new visualization functions from Plan 01 (_add_metadata_block!, plot_merged_evolution) to the optimization scripts that produce figures. This completes ORG-02 (exactly 3 output files per run) and ensures every figure carries metadata annotations (META-01, META-03). Also fixes a broken call to the non-existent `plot_evolution_comparison` in amplitude_optimization.jl by replacing it with `plot_merged_evolution`.

Output: Updated raman_optimization.jl and amplitude_optimization.jl with metadata construction, metadata passing, and merged evolution calls.

## Files Likely Touched

- `scripts/visualization.jl`
- `scripts/test_visualization_smoke.jl`
- `scripts/raman_optimization.jl`
- `scripts/amplitude_optimization.jl`
