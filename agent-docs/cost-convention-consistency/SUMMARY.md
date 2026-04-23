# Summary

What changed:

- Added `raman_cost_surface_spec(...)` so the single-mode Raman objective is named explicitly in code.
- Added `validate_gradient_taylor(...)` so tests can catch objective/gradient mismatches that a pure ratio check can miss.
- `build_numerical_trust_report(...)` now accepts and emits an explicit surface spec.
- `build_oracle(...)` in `scripts/hvp.jl` now takes `log_cost`, `λ_gdd`, and `λ_boundary`, and records the exact HVP surface in metadata.
- `scripts/hessian_eigspec.jl` now logs and saves the objective surface used for curvature probes.
- Added human-facing convention doc: `docs/cost-convention.md`.
- Added `multivar_cost_surface_spec(...)` and persisted multivariable cost-surface metadata in saved results.
- Added `mmf_cost_surface_spec(...)` and fixed `scripts/mmf_raman_optimization.jl::cost_and_gradient_mmf` so regularizers are added before the optional log-cost transform.

Open boundary:

- The shared single-mode path, the multivariable path, and the MMF shared-phase path are now aligned. The MMF joint `(φ, c_m)` optimizer still needs the same audit before claiming repo-wide objective-surface unification.

Tests run:

- `julia -t auto --project=. test/test_phase27_numerics_regressions.jl`
- `julia -t auto --project=. test/test_hvp.jl`
- `julia -t auto --project=. test/test_phase28_trust_report.jl`
- `julia -t auto --project=. scripts/test_multivar_gradients.jl`
- `julia -t auto --project=. test/test_phase16_mmf.jl`
