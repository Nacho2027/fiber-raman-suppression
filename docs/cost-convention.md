# Cost Convention

This file is the authoritative objective convention for shared Raman numerics.

## Canonical single-mode phase objective

`scripts/raman_optimization.jl::cost_and_gradient` defines the scalar objective as:

- linear surface:
  `J_surface = J_physics + λ_gdd * R_gdd(φ) + λ_boundary * R_boundary(φ)`
- log surface:
  `J_scalar = 10 * log10(J_surface)`

Rules:

- Regularizers are always added to the linear surface before any optional log transform.
- If `log_cost=true`, the returned gradient is the derivative of `10*log10(J_surface)`.
- If `log_cost=false`, the returned gradient is the derivative of `J_surface`.
- `R_boundary` is measured on the pre-attenuator temporal edge fraction of the shaped input pulse.

The helper `raman_cost_surface_spec(; log_cost, λ_gdd, λ_boundary, objective_label)` is the shared machine-readable spec for this contract. Trust reports and HVP metadata should carry that spec instead of reconstructing the meaning from ad hoc strings.

## Multivariable path

`scripts/multivar_optimization.jl::cost_and_gradient_multivar` now follows the same pattern:

- assemble the full linear surface from physics plus enabled regularizers
- apply `10*log10(...)` only after that full scalar is assembled when `cfg.log_cost=true`

The helper `multivar_cost_surface_spec(cfg; objective_label=...)` names that surface explicitly and is persisted in multivariable result payloads.

## MMF shared-phase path

`scripts/mmf_raman_optimization.jl::cost_and_gradient_mmf` now matches the same rule:

- linear surface:
  `J_mmf_variant + λ_gdd*R_gdd + λ_boundary*R_boundary`
- log surface:
  `10*log10(linear surface)`

Historically this path applied the log transform before the regularizers. That is now fixed. The helper `mmf_cost_surface_spec(; variant, log_cost, λ_gdd, λ_boundary, objective_label)` is the explicit contract for that path.

## HVP convention

`scripts/phase13_hvp.jl::build_oracle(config; log_cost, λ_gdd, λ_boundary)` differentiates the exact same scalar named by those arguments.

Defaults:

- `log_cost=false`
- `λ_gdd=0.0`
- `λ_boundary=0.0`

So the default HVP is the linear physics-only Hessian. That remains useful for trust-region and eigenspectrum work, but it is only comparable to optimizers or diagnostics that also use that same surface. If a study wants the regularized dB objective, it must request that surface explicitly when building the oracle.

## Safe comparisons after this cleanup

Safe now:

- optimizer objective vs reported trust-report surface, when they share the same `log_cost`, `λ_gdd`, and `λ_boundary`
- gradient finite-difference checks and Taylor-remainder checks against the scalar returned by `cost_and_gradient`
- HVP studies that quote the `build_oracle(...; log_cost, λ_gdd, λ_boundary)` surface they used
- chirp-sensitivity plots, because `chirp_sensitivity` now evaluates linear cost and `plot_chirp_sensitivity` applies the dB transform exactly once
- multivariable comparisons, if runs quote the persisted `cost_surface` block from the saved result
- MMF shared-phase comparisons, if runs quote the `variant`, `log_cost`, `λ_gdd`, and `λ_boundary` tuple explicitly

Still not automatically safe:

- comparing a default Phase 13/33/34 HVP result against a default L-BFGS run with `log_cost=true`
- extrapolating these claims to the MMF joint `(φ, c_m)` path without a separate audit

## Open items

- The MMF and multivariable objectives still have their own implementations; they should be audited against this contract before claiming full-project unification.
- The MMF joint `(φ, c_m)` optimizer still needs the same explicit-surface treatment if it is going to be used in honest method comparisons.
- Existing historical reports and eigenspectra remain labeled by the conventions they were run with; this change does not retroactively rewrite old artifacts.
