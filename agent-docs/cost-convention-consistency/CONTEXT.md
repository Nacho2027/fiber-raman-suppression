# Context

Session date: 2026-04-22

Mission: clean up the shared objective/cost/HVP/trust consistency layer so future sharpness/Newton/optimizer comparisons are honest.

Files touched:

- `scripts/raman_optimization.jl`
- `scripts/numerical_trust.jl`
- `scripts/hvp.jl`
- `scripts/hessian_eigspec.jl`
- `test/test_phase27_numerics_regressions.jl`
- `test/test_hvp.jl`
- `test/test_phase28_trust_report.jl`
- `scripts/test_optimization.jl`
- `docs/cost-convention.md`
- `scripts/multivar_optimization.jl`
- `scripts/mmf_raman_optimization.jl`
- `scripts/test_multivar_gradients.jl`
- `test/test_phase16_mmf.jl`

Primary decision:

- For single-mode Raman phase optimization, the authoritative linear surface is
  `J_physics + λ_gdd*R_gdd + λ_boundary*R_boundary`.
- If `log_cost=true`, the scalar objective is `10*log10` of that full linear surface.
- HVP tooling is only comparable to an optimizer/diagnostic when it is built with the same `(log_cost, λ_gdd, λ_boundary)` tuple.
- The multivariable and MMF shared-phase paths now follow the same "assemble full linear surface first, then optionally apply `10*log10`" rule.
