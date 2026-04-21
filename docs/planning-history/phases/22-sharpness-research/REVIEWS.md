# Phase 22 Review

## Findings

### No blocking findings remain after the smoke-cycle fixes

The current implementation passed a full smoke cycle covering:

- full-resolution canonical baseline
- reduced-basis Pareto baseline
- one full-resolution `tr(H)` run
- one reduced-basis `MC` run
- post-hoc `sigma_3dB`
- post-hoc Hessian eigenspectrum
- serial `save_standard_set(...)`
- summary/pareto generation

### Fixed during review: saved Pareto seed loader used the wrong JLD2 key type

`results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2` stores
`record["config"]` as `Dict{Symbol,Any}`, not `Dict{String,Any}`. The first
smoke failure was a row-lookup miss caused by string-key access. The loader in
`scripts/sharpness_phase22_lib.jl::_load_pareto_seed()` now reads symbol keys.

### Fixed during review: low-resolution Hessian path should be dense, not Arpack

The second smoke failure was an Arpack/HVPOperator mismatch on the 57-dimensional
control space. That was unnecessary complexity: Phase 13 already ships the
small-N exact Hessian builder `build_full_hessian_small(...)`. The library now
uses:

- dense exact Hessian for `N <= 1024`
- Arpack only for the full-resolution case

This is both more robust and cheaper for the Pareto point.

### Fixed during review: full-resolution Arpack wing extraction needed a retry path

The canonical `tr(H)` smoke run initially hit Arpack non-convergence at the
requested wing size. The production path now retries with:

- reduced `nev`
- larger `maxiter`
- looser `tol`

That keeps the record alive instead of failing the whole task.

## Residual Risks

- The full production sweep may still see slow or partially converged
  eigenspectra on some full-resolution runs. That is acceptable because the
  runner snapshots per-task results and records failures without aborting the
  batch.
- Smoke-mode baseline depths are intentionally under-optimized (`max_iter=8`)
  and should not be interpreted physically.
- `save_standard_set(...)` emits a recurring `pcolormesh` monotonic-coordinate
  warning from existing plotting code. It does not block image generation and
  is outside the Phase 22 namespace.

## Verdict

No blocking implementation defects remain after the smoke-cycle fixes. The
production sweep can proceed.
