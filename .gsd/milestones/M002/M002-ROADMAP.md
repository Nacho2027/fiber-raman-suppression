# M002: Verification & Discovery

**Vision:** A Julia simulation platform for nonlinear fiber optics — specifically Raman suppression optimization via spectral phase and amplitude shaping in single-mode fibers.

## Success Criteria


## Slices

- [x] **S01: Correctness Verification** `risk:medium` `depends:[]`
  > After this: Create the `scripts/verification.jl` standalone verification suite.
- [x] **S02: Result Serialization** `risk:medium` `depends:[S01]`
  > After this: Add structured result serialization to every optimization run in raman_optimization.jl.
- [ ] **S03: Cross Run Comparison And Pattern Analysis** `risk:medium` `depends:[S02]`
  > After this: Add all cross-run comparison and pattern analysis visualization functions to `scripts/visualization.jl`.
- [ ] **S04: Parameter Sweeps** `risk:medium` `depends:[S03]`
  > After this: Fix the power-blind time window function and add sweep-mode support to run_optimization(), establishing the foundation for the parameter sweep phase.
