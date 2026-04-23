# Phase 22: Sharpness-Aware Cost Function Research

**Researched:** 2026-04-20  
**Domain:** Robust spectral-phase optimization for Raman suppression in nonlinear fiber optics  
**Confidence:** High on implementation feasibility; medium on which formulation will dominate empirically

## Summary

Phase 22 is implementable without touching shared files. The repo already has
all critical primitives:

- `scripts/sharpness_optimization.jl` for gauge-projected Hutchinson trace
  estimation and sharpness-regularized L-BFGS
- `scripts/hvp.jl` for finite-difference HVPs
- `scripts/hessian_eigspec.jl` for Arpack matrix-free eigenspectra
- `scripts/sweep_simple_param.jl` for the reduced `N_phi=57` cubic-basis
  parameterization
- `scripts/simple_profile_driver.jl` for the existing `sigma_3dB` Gaussian
  perturbation scan pattern
- `scripts/standard_images.jl` for mandatory four-image output

The literature supports testing exactly the three formulations requested, but
with one important caveat: SAM's perturbed-loss proxy is not equivalent to
"flat minimum" in general. GSAM explicitly shows that low perturbed loss can
still occur at sharp minima, so Phase 22 should treat SAM as one Pareto probe,
not as a privileged definition of robustness. That is consistent with the
project's current physics evidence: Phase 13 found indefinite Hessians at the
L-BFGS optima, so a signed trace or perturbed-loss proxy may behave
non-monotonically when positive and negative curvature coexist.

The recommended implementation is therefore:

1. Keep the optimization base loss on the current project default scale,
   `J_dB`, so the comparison answers "should sharpness replace the default
   cost?" rather than "can linear-J + robustness beat log-J?"
2. Define all three sharpness flavors in the **physical phase space** `phi`,
   even when the control variable is the reduced `N_phi=57` coefficient vector
   `c`. This keeps the downstream `sigma_3dB` metric comparable across both
   operating points.
3. Measure the Hessian spectrum post hoc on the physical loss `J` using the
   existing Phase 13 HVP machinery. For the reduced `N_phi=57` operating point,
   analyze the Hessian in control space so the curvature verdict refers to the
   space actually optimized.

## Standard Stack

- `Optim.jl` L-BFGS via the existing `optimize_spectral_phase` / sharpness
  wrapper pattern already used in Phase 14
- `FFTW.jl` with deterministic environment from `scripts/determinism.jl`
- `Arpack.jl` matrix-free eigenspectrum via the existing `HVPOperator` pattern
- `JLD2.jl` for run snapshots and post-hoc synthesis
- `PyPlot.jl` for the Pareto figure and any additional summary figures
- `Threads.@threads` over independent `(operating point, flavor, regularization)`
  runs, with `deepcopy(fiber)` per task

## Architecture Patterns

### 1. Lift control variables into physical phase space

For both operating points, write the optimizer in terms of a control vector
`x`, but evaluate robustness in the lifted phase `phi = A*x`:

- full-resolution canonical point: `A = I`, `x = phi`
- Pareto reduced point: `A = B`, where `B` is the cubic basis from
  `scripts/sweep_simple_param.jl`, `x = c in R^57`

This gives a uniform control-space gradient rule:

- compute `grad_phi`
- map back with `grad_x = A' * grad_phi`

That same pattern works for plain loss, SAM, Monte Carlo Gaussian averaging,
and the trace penalty.

### 2. Deterministic sample-average approximation

Both stochastic flavors must be deterministic inside one optimization run:

- Hutchinson trace: fixed Rademacher draws per run, reused at every objective
  call
- Monte Carlo Gaussian: fixed Gaussian noise bank per run, preferably with
  antithetic `(+eps, -eps)` pairs

This avoids noisy line-search failures and makes `Optim.LBFGS()` usable.

### 3. Reuse Phase 13 eigenspectrum machinery directly

Do not rebuild eigenspectrum code from scratch. Reuse:

- `fd_hvp` from `scripts/hvp.jl`
- `HVPOperator` pattern from `scripts/hessian_eigspec.jl`
- `Arpack.eigs(...; which=:LR/:SR)` for top and bottom wings

Only wrap these in session-owned `scripts/sharpness_*` entry points that save
results under the Phase 22 directory.

## Literature Notes

### SAM / ASAM / GSAM

- Foret et al. define SAM as a min-max problem over a norm-bounded
  neighborhood and implement it efficiently through a gradient-aligned
  perturbation step. Source: arXiv 2010.01412.
- Kwon et al. show the sharpness radius should be scale-aware; fixed-radius
  neighborhoods can be misleading under parameter rescaling. Source:
  PMLR 139 / ASAM.
- Zhuang et al. show that low perturbed loss does **not** guarantee flatness:
  both sharp and flat minima can have low perturbed loss, motivating a second
  geometry diagnostic. Source: arXiv 2203.08065 / GSAM.

For this project that means SAM is worth testing, but the verdict must be
driven by both `sigma_3dB` and the Hessian spectrum, not by SAM's own
objective value.

### Hutchinson Trace Estimation

- Hutchinson's original estimator is unbiased and uses Rademacher probes with a
  minimum-variance property among a standard class of probe choices. Source:
  Hutchinson 1989/1990, DOI 10.1080/03610918908812806.
- Hutch++ reduces variance and matrix-vector complexity dramatically for PSD
  matrices, but its cleanest guarantees are PSD-focused. Source: arXiv
  2010.09649.

Because Phase 13 found the local Hessian to be **indefinite**, plain
Hutchinson with fixed Rademacher probes is the safer baseline implementation
for Phase 22. If variance becomes a blocker, antithetic pairing and a larger
`K` are lower-risk than introducing Hutch++ mid-phase.

### Robust Optimization in Physics / Electromagnetics

- Nohadani et al. show that physics optimization under implementation error is
  naturally framed as a robustness problem, and discuss expected-value /
  variance-style objectives versus other robust objectives in a nonconvex
  electromagnetic design setting. Source: *Journal of Applied Physics* 101,
  074507 (2007).

That supports the engineering interpretation of the Monte Carlo Gaussian
objective: it is not just an ML import, it is a direct "expected performance
under perturbation" objective of the kind used in physical design problems.

## Don't Hand-Roll

- Do not modify `scripts/common.jl`, `scripts/raman_optimization.jl`,
  `scripts/sharpness_optimization.jl`, or `src/**`.
- Do not create a second HVP implementation; use `fd_hvp`.
- Do not create a second `sigma_3dB` methodology; reuse the Phase 17 median
  crossing logic.
- Do not add new plotting dependencies; stay in Julia + PyPlot + existing
  project helpers.

## Common Pitfalls

- `fiber["zsave"]` is mutated by the solver path. Any threaded outer loop must
  use `deepcopy(fiber)` per task.
- `FFTW.set_num_threads(n > 1)` should not be used here; the user explicitly
  prohibited that at `Nt = 2^13`.
- Stochastic objectives must use fixed sample banks per run or `LBFGS` will
  see a moving target.
- A signed Hessian trace can cancel positive and negative curvature at a saddle.
  That is a feature of the formulation, not a bug; Phase 22 should report it
  plainly if it happens.
- The reduced `N_phi=57` point should not be analyzed with the full-space
  Hessian as if it were an unconstrained optimum; the relevant spectrum is the
  control-space spectrum.

## Code Examples

### Physical-space lift

```julia
phi = reshape(A * x, Nt, 1)
J, grad_phi = cost_and_gradient(phi, uω0, fiber, sim, band_mask; log_cost=true)
grad_x = A' * vec(grad_phi)
```

### Deterministic MC Gaussian objective

```julia
J_sum = 0.0
g_sum = zeros(length(x))
for eps in fixed_noise_bank
    phi_eps = reshape(A * x, Nt, 1) .+ eps
    J, grad_phi = cost_and_gradient(phi_eps, uω0, fiber, sim, band_mask; log_cost=true)
    J_sum += J
    g_sum .+= A' * vec(grad_phi)
end
J_mc = J_sum / length(fixed_noise_bank)
g_mc = g_sum / length(fixed_noise_bank)
```

### Post-hoc Hessian eigenspectrum

```julia
grad_oracle = x -> control_space_grad(x, ctrl; log_cost=false)
H_op = HVPOperator(length(x_opt), grad_oracle, x_opt, 1e-4)
lambda_top, V_top = Arpack.eigs(H_op; nev=20, which=:LR)
lambda_bot, V_bot = Arpack.eigs(H_op; nev=20, which=:SR)
```

## Sources

- Foret et al., "Sharpness-Aware Minimization for Efficiently Improving
  Generalization" (2020): https://arxiv.org/abs/2010.01412
- Kwon et al., "ASAM: Adaptive Sharpness-Aware Minimization for Scale-Invariant
  Learning of Deep Neural Networks" (ICML 2021): https://proceedings.mlr.press/v139/kwon21b.html
- Zhuang et al., "Surrogate Gap Minimization Improves Sharpness-Aware Training"
  (2022): https://arxiv.org/abs/2203.08065
- Hutchinson, "A Stochastic Estimator of the Trace of the Influence Matrix for
  Laplacian Smoothing Splines" (1989/1990): https://doi.org/10.1080/03610918908812806
- Meyer et al., "Hutch++: Optimal Stochastic Trace Estimation" (2020):
  https://arxiv.org/abs/2010.09649
- Nohadani et al., "Robust Optimization in Electromagnetic Scattering Problems"
  (2007): https://www.mit.edu/~dbertsim/papers/Robust%20Optimization/Robust%20Optimization%20in%20Electromagnetic%20Scattering%20Problems.pdf
