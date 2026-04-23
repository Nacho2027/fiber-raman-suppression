# Phase 34 Bounded Rerun Status

This note records the post-fix bounded reruns performed after the Phase 34 `M`-wiring and gauge-safe PCG fixes.

It is intentionally narrow. The goal is to capture what the newly honest main-path reruns actually say before those results get blurred together with older caveated benchmark attempts.

## What changed before these reruns

Two plumbing issues were fixed before the reruns in this note:

- the trust-region outer loop now forwards the configured preconditioner `M` into `solve_subproblem`
- the PCG path now reprojects preconditioned residuals and directions into the gauge-complement subspace

That means these reruns are the first small comparisons in which the preconditioners are both:

- actually present in the main trust-region path
- compatible with the existing gauge-leak invariant

## Bounded rerun 1: small cold-start case

Case:

- fiber: SMF-28
- `L = 0.5 m`
- `P = 0.05 W`
- `Nt = 128`
- cold start

Compared variants:

- `:none`
- `:dispersion`
- `:dct_K16`

### Short-run result

With a short trust-region budget, all three could run honestly.

- `:none` gave the best final objective in the short run
- `:dispersion` was close to `:none` and cheaper in wall time
- `:dct` showed healthier accepted-step `rho` values but not a better final objective

### Slightly longer result

With a slightly longer budget, all three still converged to first-order saddles.

- `:none`: best final `J`
- `:dispersion`: nearly as good as `:none`, cheaper
- `:dct`: more accepted steps, but still worse final `J`

Interpretation:

- On the easy bounded case, preconditioning changes step behavior
- but only `:dispersion` looks practically competitive
- `:dct` improves acceptance statistics more than it improves the actual Raman objective

## Bounded rerun 2: harder cold-start case

Case:

- fiber: SMF-28
- `L = 1.0 m`
- `P = 0.1 W`
- `Nt = 256`
- cold start

Compared variants:

- `:none`
- `:dispersion`
- `:dct_K16`

Result:

- `:none`: `MAX_ITER`, no accepted steps
- `:dispersion`: same qualitative behavior as `:none`, but cheaper
- `:dct`: worse, with immediate trust-region collapse behavior

Interpretation:

- On the harder bounded cold-start case, none of the tested preconditioners rescue the local model
- this is evidence that preconditioning alone is not enough when the starting point is still too poor

## Bounded rerun 3: same-config warm start on the harder case

Target case:

- fiber: SMF-28
- `L = 1.0 m`
- `P = 0.1 W`
- `Nt = 256`

A same-config L-BFGS warm start was first computed on that target problem:

- target L-BFGS: `J ≈ 7.50e-6`

Then trust-region runs were launched from that warm start.

Result:

- `:none`: no accepted steps
- `:dispersion`: no accepted steps
- `:dct`: no accepted steps

Interpretation:

- A target-config L-BFGS warm start does not automatically give trust-region a usable local model
- being "good for L-BFGS" is not the same as being "good for trust-region Newton"

## Bounded rerun 4: continuation-style start on the harder case

Source case:

- fiber: SMF-28
- `L = 0.5 m`
- `P = 0.1 W`
- `Nt = 256`

The source problem was first solved with L-BFGS:

- source L-BFGS: `J ≈ 8.14e-8`

That source `phi` was then used as the initial point on the harder target problem:

- target: `L = 1.0 m`, `P = 0.1 W`, same `Nt = 256`

Result:

- `:none`: converged to a first-order saddle with accepted steps
- `:dispersion`: same qualitative behavior, with slightly better final `J` than `:none`
- `:dct`: failed to become competitive and accepted no steps

This was the first bounded rerun where preconditioned trust-region looked genuinely promising on the harder case.

## What these reruns say overall

The main lesson is:

- **path quality matters more than preconditioning alone**

More specifically:

- fixing the preconditioner plumbing was necessary
- fixing gauge safety was also necessary
- but once both fixes were in place, the harder-case results still depended much more on the starting point than on the preconditioner choice

Current ranking from these bounded reruns:

1. continuation-style start + `:dispersion` looks like the best near-term Phase 34 direction
2. continuation-style start + `:none` is a strong baseline
3. `:dct` is not earning its complexity on the tested bounded cases

## Recommended next step

Near-term Phase 34 work should focus on:

- `:none` vs `:dispersion`
- continuation-style starts, not same-config saddle starts
- bounded comparison runs that ask whether dispersion preconditioning improves either:
  - final `J`
  - convergence speed
  - or acceptance reliability

The bounded reruns do **not** support spending more near-term effort on the current DCT preconditioner path.
