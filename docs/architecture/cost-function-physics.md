# Cost Function and Physics

[← docs index](../README.md) · [project README](../../README.md)

This is the compact physics background for people working in this repo. It is
meant to explain what the optimizer is doing and why the current cost-function
choices exist, without requiring a full derivation on first read.

Longer references live in:

- [`../reference/companion_explainer.pdf`](../reference/companion_explainer.pdf)
- [`../reference/verification_document.pdf`](../reference/verification_document.pdf)
- [`../reference/physics_verification.pdf`](../reference/physics_verification.pdf)

## What we simulate: the GNLSE

The Generalized Nonlinear Schrödinger Equation governs the complex envelope of
the pulse as it propagates along the fiber axis z:

```
∂A/∂z = (linear dispersion) + (Kerr nonlinearity) + (Raman response)
```

The forward solver (`src/simulation/simulate_disp_mmf.jl`) integrates this in
the *interaction picture*, which separates fast linear dispersion from slow
nonlinear evolution. This lets the ODE solver take larger steps. Kerr is a
tensor contraction; Raman is a convolution with a memory kernel.

For the full derivation and numerical details see
[`../reference/companion_explainer.pdf`](../reference/companion_explainer.pdf).

## What we optimize: the cost J

The cost is the **fractional pulse energy in a Raman-shifted frequency band**
at fiber exit:

```
J(φ) = E_Raman(φ) / E_total(φ)
```

where `φ` is the input spectral phase and the Raman band is a ~13 THz wide
window on the long-wavelength side of the pump.

`J ∈ [0, 1]`. Smaller is better. We typically report `J_dB = 10 · log₁₀(J)`.

## Why log-scale cost (Key Decision — Phase 7/8)

Historically the optimizer received `J` (linear) and worked fine until
suppression got deep (say −30 dB). Below that, the gradient magnitude decayed
so quickly that L-BFGS's Hessian approximation corrupted and the line search
stalled.

The fix: let L-BFGS see `10·log₁₀(J)` directly. The gradient becomes
`10 / (J · ln 10) · ∇J`, which stays O(1) as J approaches zero. Result:
20–28 dB additional suppression across every sweep point. This is the
log-scale cost formulation referenced throughout the codebase.

Previous bug (Key Bug #1, fixed 2026-03-26): the optimizer was fed log J but
the gradient was linear-scale. Hybrid scale corrupted the Hessian. See
[`../planning-history/STATE.md`](../planning-history/STATE.md) "Key Bugs Fixed" #1.

## How we get gradients: the adjoint method

Autodiff would struggle with the in-place ODE solver. We instead derive the
adjoint equation by hand: a backward ODE whose terminal condition is seeded
from J's gradient at fiber exit, integrated back to z=0, where evaluating it
gives `∂J/∂φ` for every one of the 8192 phase values — in ONE backward pass.

Cost: one forward solve + one backward solve ≈ 2 forward-solve times per
gradient. Far cheaper than finite differences (which would need 8193 forward
solves).

Verification: `scripts/research/analysis/verification.jl` runs a Taylor-remainder test that
confirms the residual scales as O(ε²). Slopes of 2.01 / 2.07 / 2.09 were
recorded in Phase 4.

## Why spectral phase, not amplitude

Amplitude shaping discards energy; phase shaping does not. A lossless
spatial-light-modulator (SLM) can carve phase-only; amplitude shaping requires
either a loss-y amplitude SLM or a phase-to-amplitude conversion that itself
discards energy.

The `scripts/lib/amplitude_optimization.jl` entry point is provided as an A/B
comparison — phase-only is the default production path. See
[adding-an-optimization-variable.md](../guides/adding-an-optimization-variable.md)
for the framework view.

## Raman band definition

Raman gain in silica peaks around 13.2 THz below the pump with a ~10-15 THz
FWHM band. The cost-function mask (`band_mask`, constructed in
`scripts/lib/common.jl::setup_raman_problem`) is a boolean over `sim["fs"]`
selecting this region. `compute_noise_map`-level precision is not needed —
the mask merely has to enclose the Raman gain spectrum.

## Further reading

- [`../reference/companion_explainer.pdf`](../reference/companion_explainer.pdf) — longer mathematical walkthrough
- [`../reference/verification_document.pdf`](../reference/verification_document.pdf) — equation-by-equation code verification
- [`../reference/physics_verification.pdf`](../reference/physics_verification.pdf) — physics verification notes
- [`../../results/RESULTS_SUMMARY.md`](../../results/RESULTS_SUMMARY.md) — plain-language results summary
- `results/raman/MATHEMATICAL_FORMULATION.md` — equations keyed to code line numbers

## See also

- [interpreting-plots.md](../guides/interpreting-plots.md) — what the cost looks like
  graphically (convergence curve, spectral drop in the Raman band).
- [output-format.md](./output-format.md) — where `J_final_dB` lives in the
  saved metadata.
