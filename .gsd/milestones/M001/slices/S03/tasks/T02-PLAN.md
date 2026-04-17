# T02: 03-structure-annotation-and-final-assembly 02

**Slice:** S03 — **Milestone:** M001

## Description

Wire metadata threading and merged evolution call sites in both optimization scripts.

Purpose: Connects the new visualization functions from Plan 01 (_add_metadata_block!, plot_merged_evolution) to the optimization scripts that produce figures. This completes ORG-02 (exactly 3 output files per run) and ensures every figure carries metadata annotations (META-01, META-03). Also fixes a broken call to the non-existent `plot_evolution_comparison` in amplitude_optimization.jl by replacing it with `plot_merged_evolution`.

Output: Updated raman_optimization.jl and amplitude_optimization.jl with metadata construction, metadata passing, and merged evolution calls.

## Must-Haves

- [ ] "run_optimization in raman_optimization.jl constructs a metadata NamedTuple and passes it to all three plotting calls"
- [ ] "run_optimization produces exactly 3 output files: opt.png, opt_phase.png, opt_evolution.png (not 4)"
- [ ] "run_optimization calls plot_merged_evolution instead of two separate propagate_and_plot_evolution calls"
- [ ] "run_amplitude_optimization and run_amplitude_optimization_lowdim pass metadata to plotting calls"
- [ ] "amplitude_optimization.jl calls plot_merged_evolution (replacing broken plot_evolution_comparison calls)"

## Files

- `scripts/raman_optimization.jl`
- `scripts/amplitude_optimization.jl`
