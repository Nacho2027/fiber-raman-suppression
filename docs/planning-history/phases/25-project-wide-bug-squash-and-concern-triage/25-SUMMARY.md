---
phase: 25
status: complete
completed_at: 2026-04-20
---

# Phase 25 Summary

## What changed

- Added explicit `ArgumentError` validation for unsupported `pulse_form` values in the two live pulse constructors:
  - `src/simulation/simulate_disp_mmf.jl`
  - `src/simulation/simulate_disp_gain_mmf.jl`
- Deleted the dead placeholder file `src/simulation/simulate_disp_gain_smf.jl`.
- Updated `scripts/benchmark.jl` so its planner-flag swap only touches live simulation files and uses the correct flag-count assertion.
- Added fast-tier regression coverage for invalid pulse-form input.
- Corrected stale living docs that still described the deleted file as active code or misclassified helper scripts as missing-driver bugs.

## Verification

- Ran `julia --project=. -e 'using Pkg; Pkg.instantiate()'` because the fresh worktree did not yet have all Julia deps available.
- Ran `julia --project=. test/tier_fast.jl`
- Result: pass (`20/20` tests)

## Left unresolved

- `fiber["zsave"]` mutation remains a structural thread-safety hazard.
- `using PyPlot` at `src/MultiModeNoise.jl` load time still couples non-plotting code to matplotlib availability.
- CI automation remains absent.

## Seeds planted

- `.planning/seeds/thread-safe-fiber-params.md`
- `.planning/seeds/decouple-pyplot-from-core-module.md`
