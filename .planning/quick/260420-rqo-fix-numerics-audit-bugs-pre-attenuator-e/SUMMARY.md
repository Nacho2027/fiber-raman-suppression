---
status: complete
completed_at: 2026-04-20T20:18:00Z
---

Completed bugfix quick task for the Phase 27 numerics audit.

Implemented:
- `scripts/common.jl`: `check_boundary_conditions` now reconstructs the pre-attenuator temporal field before computing edge energy fraction.
- `scripts/raman_optimization.jl`: regularization terms are accumulated in linear space and the optional dB transform is applied to the full objective at the end, so the returned gradient matches the scalar objective.
- `scripts/raman_optimization.jl`: `chirp_sensitivity` now evaluates linear `J`, which `plot_chirp_sensitivity` can safely convert to dB once.
- `test/test_phase27_numerics_regressions.jl`: dedicated regressions for pre-attenuator edge accounting, regularized log-cost gradient consistency, and chirp-sensitivity plotting.
- `test/tier_slow.jl`: includes the new Phase 27 regression file.

Verification:
- `julia --project=. test/test_phase27_numerics_regressions.jl`
  Result: pass (7/7 tests)
