# M002: Verification & Discovery

## Vision
A Julia simulation platform for nonlinear fiber optics — specifically Raman suppression optimization via spectral phase and amplitude shaping in single-mode fibers.

## Slice Overview
| ID | Slice | Risk | Depends | Done | After this |
|----|-------|------|---------|------|------------|
| S01 | Correctness Verification | medium | — | ✅ | Create the `scripts/verification.jl` standalone verification suite. |
| S02 | Result Serialization | medium | S01 | ✅ | Add structured result serialization to every optimization run in raman_optimization.jl. |
| S03 | S03 | medium | — | ✅ | Add all cross-run comparison and pattern analysis visualization functions to `scripts/visualization.jl`. |
| S04 | Parameter Sweeps | medium | S03 | ⬜ | Fix the power-blind time window function and add sweep-mode support to run_optimization(), establishing the foundation for the parameter sweep phase. |
