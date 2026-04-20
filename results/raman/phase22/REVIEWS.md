# Phase 22 Review

## Findings

### No blocking findings remain after the full production run

The final Phase 22 pipeline completed the full 26-record sweep, emitted the
mandatory 104-image standard set, resolved Hessian spectra for all 26 records,
and produced the final Pareto summary and geometry table without manual patch-up.

### Fixed during review: Pareto seed loader needed `Symbol` keys, not `String` keys

`results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2` stores `record["config"]`
as `Dict{Symbol,Any}`. The original lookup silently missed the target
`N_phi = 57` row. `scripts/sharpness_phase22_lib.jl::_load_pareto_seed()` now
reads symbol keys and reliably recovers the Phase 17 seed.

### Fixed during review: low-resolution Hessians should use the exact dense Phase 13 path

The 57-dimensional operating point does not need Arpack. The final code routes
`N <= 1024` through `build_full_hessian_small(...)` from Phase 13 and reserves
Arpack for the full-resolution canonical control space only.

### Fixed during review: Hessian extraction must be isolated from the threaded optimization sweep

The critical production bug was not simple non-convergence; concurrent Arpack
post-processing could segfault Julia itself. The final design splits the phase
into:

- threaded optimization + `sigma_3dB` measurement + `save_standard_set(...)`
- isolated one-record-at-a-time Hessian postpass via `scripts/sharpness_phase22_hessian_one.jl`
- final bundle collection via `scripts/sharpness_phase22_collect.jl`

That is the change that made the 26-record production batch reliable.

## Residual Risks

- Full-resolution Hessian wings are still slow because they rely on Arpack over
  a finite-difference HVP operator. The isolation step makes this tolerable,
  but not cheap.
- `save_standard_set(...)` still emits the pre-existing Matplotlib
  `pcolormesh` monotonic-coordinate warning. It does not block image generation
  and is outside the Phase 22 write scope.
- The tracked markdown summary and Pareto plot are versioned, but the large
  JLD2 bundles and the 104 PNG standard images follow the project's existing
  results-artifact handling rather than normal source control.

## Verdict

No blocking implementation defects remain. The final Phase 22 result is
technically sound enough for D-docs to quote directly: the sweep ran to
completion, the geometry claim is supported by resolved Hessian spectra, and
the robustness recommendation is now based on the full two-operating-point
Pareto rather than smoke-mode behavior.
