# T01: 03-structure-annotation-and-final-assembly 01

**Slice:** S03 — **Milestone:** M001

## Description

Add metadata annotation helper, expand J cost annotation, and create merged 2x2 evolution comparison function in visualization.jl.

Purpose: Implements the core visualization functions needed for Phase 3 -- the metadata block that makes every figure self-documenting (META-01), the expanded J before/after annotation on comparison figures (META-02), the merged evolution figure with column titles and fiber length (META-03, ORG-01). These functions are created here; the optimization script call-site wiring happens in Plan 02.

Output: Updated visualization.jl with _add_metadata_block!, plot_merged_evolution, and metadata keyword support on plot_optimization_result_v2, plot_amplitude_result_v2, and plot_phase_diagnostic. Updated smoke tests.

## Must-Haves

- [ ] "_add_metadata_block! places a visible parameter annotation at bottom-left of any figure"
- [ ] "plot_optimization_result_v2 shows J_before, J_after, and delta-J on the After spectral panel"
- [ ] "plot_merged_evolution renders a 2x2 grid (temporal/spectral x optimized/unshaped) with shared colorbar"
- [ ] "plot_merged_evolution includes fiber length in suptitle and column titles identifying optimized vs unshaped"
- [ ] "All three top-level plotting functions accept metadata keyword and call _add_metadata_block! when provided"

## Files

- `scripts/visualization.jl`
- `scripts/test_visualization_smoke.jl`
