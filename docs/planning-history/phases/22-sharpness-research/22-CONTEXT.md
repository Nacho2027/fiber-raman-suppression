# Phase 22: Sharpness-Aware Cost Function Research — Context

**Gathered:** 2026-04-20  
**Status:** Ready for execution  
**Mode:** Autonomous (`--auto` equivalent)

<domain>
## Phase Boundary

Implement and compare three sharpness-aware objectives for Raman-suppression
phase optimization:

- SAM worst-case
- Hessian-trace penalty via Hutchinson HVP
- Monte Carlo Gaussian robust objective

Run each flavor on two operating points:

1. SMF-28 canonical full-resolution point: `L = 0.5 m`, `P = 0.05 W`
2. Pareto reduced-basis point: `SMF-28`, `L = 0.25 m`, `P = 0.10 W`,
   `N_phi = 57`, cubic basis

For every resulting `phi_opt`, save the mandatory standard image set under:

`.planning/phases/22-sharpness-research/images/`

Output a Phase 22 `SUMMARY.md` with:

- one Pareto plot overlaying all flavors (`J_dB` vs `sigma_3dB`)
- one Hessian-indefiniteness table vs regularization
- one 3-5 sentence verdict suitable for direct quoting by Session D
</domain>

<decisions>
## Locked Decisions

### Session namespace and file ownership

- New code lives only under `scripts/sharpness_*`.
- New planning artifacts live only under `.planning/phases/22-sharpness-research/`.
- Shared files remain read-only.

### Base optimization scale

- Use `log_cost=true` for the optimization base loss across all flavors.
- Report the physical outcome post hoc as plain `J_dB`, recomputed from
  `log_cost=false` and converted to dB.

Rationale: the question is whether a sharpness-aware objective should replace
the current project default, and the current default is the log-dB optimizer.

### Common control-space abstraction

- Optimize over a control vector `x`.
- Lift to physical phase with `phi = A*x`.
- Canonical point: `A = I`, `x = phi`.
- Pareto point: `A = B_cubic`, `x = c in R^57`.
- Always define perturbations and robustness in the lifted physical phase.

### Operating-point definitions

#### OP-A: SMF-28 canonical full-resolution

- `fiber_preset = :SMF28`
- `L_fiber = 0.5`
- `P_cont = 0.05`
- `Nt = 2^13`
- `time_window = 10.0`
- `beta_order = 3`
- use the Phase 17 baseline physics parameters:
  - `gamma_user = 1.1e-3`
  - `betas_user = [-2.17e-26, 1.2e-40]`
  - `fR = 0.18`
  - `pulse_fwhm = 185e-15`
  - `pulse_rep_rate = 80.5e6`

Warm start from `results/raman/phase17/baseline.jld2`.

#### OP-B: Pareto reduced-basis point

- `fiber_preset = :SMF28`
- `L_fiber = 0.25`
- `P_cont = 0.10`
- `Nt = 2^14`
- `time_window = 10.0`
- `beta_order = 3`
- reduced basis from `scripts/sweep_simple_param.jl`:
  - `N_phi = 57`
  - `kind = :cubic`

Warm start from the corresponding row in
`results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2`.

### Baseline anchor

- Include one `plain` baseline per operating point in the final synthesis.
- Do not re-optimize the baseline unless the saved warm-start artifact is
  missing or invalid; reuse prior `phi_opt` / `c_opt`, then recompute
  `J_dB`, `sigma_3dB`, eigenspectrum, and standard images in the Phase 22
  output directory.

### Flavor definitions

#### Flavor A: SAM worst-case

- Objective proxy: `L_sam(x) = J_dB(phi + rho * d_hat)`
- `d_hat` is the gauge-projected physical-phase gradient direction,
  normalized in physical phase space
- Gradient rule: standard SAM approximation, i.e. use the gradient evaluated
  at the perturbed phase and map it back to control space; do not
  differentiate through `d_hat`

Regularization sweep:

- `rho in {0.01, 0.025, 0.05, 0.10}` rad

#### Flavor B: Hessian-trace penalty

- Objective: `L_tr(x) = J_dB(phi) + lambda_tr * tr_hat(H(phi))`
- Reuse the existing Hutchinson machinery from
  `scripts/sharpness_optimization.jl`
- Use fixed Rademacher probes per run
- Use `K = 4` probes in production, `K = 2` only in smoke tests

Regularization sweep:

- `lambda_tr in {1e-4, 3e-4, 1e-3, 3e-3}`

#### Flavor C: Monte Carlo Gaussian robust objective

- Objective: `L_mc(x) = mean_k J_dB(phi + eps_k)`
- `eps_k ~ N(0, sigma_mc^2 I)` in physical phase space
- Use a fixed antithetic noise bank per run for determinism
- Use `K = 4` perturbations in production as two antithetic pairs

Regularization sweep:

- `sigma_mc in {0.01, 0.025, 0.05, 0.075}` rad

### Metrics

For every baseline/flavor/regularization/operating-point record:

- `J_dB_plain`
- optimization wall time
- optimizer iterations and convergence flag
- `sigma_3dB` from the Phase 17-style median 3 dB crossing
- Hessian eigenspectrum:
  - top 20 algebraic eigenvalues
  - bottom 20 algebraic eigenvalues
  - `lambda_max`
  - `lambda_min`
  - `|lambda_min| / lambda_max`
  - `indefinite = lambda_min < 0 < lambda_max`

### sigma_3dB protocol

- Use the Phase 17 perturbation structure: Gaussian phase perturbations,
  median `Delta J_dB` curve, linear interpolation to the 3 dB crossing.
- Production sigma grid:
  - `{0.01, 0.025, 0.05, 0.075, 0.10, 0.15, 0.20}`
- Trials per sigma: `12`

### Standard images

Every baseline and every optimized run with a `phi_opt` must call
`save_standard_set(...)`.

Tag convention:

- `smf28_canonical_plain`
- `smf28_canonical_sam_rho1e-2`
- `smf28_canonical_trH_lambda1e-3`
- `smf28_canonical_mc_sigma2p5e-2`
- `smf28_pareto57_plain`
- ...

All image sets go under:

`.planning/phases/22-sharpness-research/images/`

### Runtime budget / prioritization

- Full target matrix:
  - 2 baselines
  - 3 flavors x 4 regularization values x 2 operating points = 24 runs
  - total = 26 records
- If runtime becomes tight:
  - keep all four `tr(H)` values
  - keep all four `MC` values
  - reduce `SAM` to three values `{0.01, 0.05, 0.10}`

### Compute discipline

- Run locally on the Mac with `julia -t 8 --project=.`
- Use `Threads.@threads` over independent tasks
- Use `deepcopy(fiber)` inside each threaded task
- Do **not** increase FFTW thread count above 1
</decisions>

<canonical_refs>
## Canonical References

- `results/PHYSICS_AUDIT_2026-04-19.md`
- `results/raman/phase13/FINDINGS.md`
- `results/raman/phase17/SUMMARY.md`
- `scripts/sharpness_optimization.jl`
- `scripts/phase13_hvp.jl`
- `scripts/phase13_hessian_eigspec.jl`
- `scripts/sweep_simple_param.jl`
- `results/raman/phase_sweep_simple/candidates.md`
- `results/raman/phase17/baseline.jld2`
- `results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2`
</canonical_refs>

<success_criteria>
## Success Criteria

- All 26 intended records produce a result bundle or an explicit failure record.
- Every available `phi_opt` has a full standard-image set on disk.
- The final Pareto plot overlays baseline + all three flavors for both
  operating points.
- The final summary states plainly whether sharpness should become the new
  default cost, remain optional, or be rejected.
- If flat optima remain indefinite, that is reported as the headline result,
  not buried as an implementation caveat.
</success_criteria>
