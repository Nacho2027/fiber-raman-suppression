# Adding an Optimization Variable

[← back to docs index](./README.md) · [project README](../README.md)

> **Status — stub.** Session A (multi-variable optimization) owns the
> expansion of this doc. This file provides the framework-level scaffold so
> that Session A's work has a known destination. See Session A for the
> full guide when it lands.

## Current optimization variables

Today the pipeline optimizes two quantities, in separate scripts:

- **Spectral phase** — `scripts/raman_optimization.jl` (the canonical path).
- **Spectral amplitude** — `scripts/amplitude_optimization.jl` (A/B comparison path).

Both consume the same adjoint machinery under the hood. The difference is in
the `cost_and_gradient` wrapper that maps optimization variable → (J, ∇J).

Background on the physics rationale — why phase is the default and amplitude
is only an A/B check — is in
[cost-function-physics.md](./cost-function-physics.md#why-spectral-phase-not-amplitude).

## What "adding a variable" means

The framework supports any scalar-or-vector variable `x` that:

- maps deterministically to an input field perturbation `A_in = f(A_in_0, x)`;
- has a well-defined gradient `∂A_in/∂x` (so the chain rule through the adjoint
  works);
- is bounded or regularized enough to keep the optimizer from running away.

## Extension checklist (Session A to expand)

1. Define the variable's shape and physical meaning.
2. Write a `cost_and_gradient_<name>` function that:
   a. Maps `x` → `A_in`.
   b. Calls the forward+adjoint solve.
   c. Applies the chain rule to produce `∇_x J`.
3. Write a `optimize_<name>` wrapper matching the interface of
   `optimize_spectral_phase`.
4. Add tests mirroring `test/tier_slow.jl`'s Key Bug #1 regression and the
   Taylor-remainder gradient check.
5. Add a top-of-file docstring to the new entry-point script following the
   template in [quickstart-optimization.md](./quickstart-optimization.md).
6. Document the new variable's schema in [output-format.md](./output-format.md).

## See also

- [cost-function-physics.md](./cost-function-physics.md) — cost + adjoint math.
- [output-format.md](./output-format.md) — schema versioning for new fields.
- [adding-a-fiber-preset.md](./adding-a-fiber-preset.md) — sibling extension
  guide for fibers (more mature; use as a style reference).
