# Numerics Notes

This file distills what remains agent-relevant from the April 20 numerics audit and same-day follow-up fixes.

Source artifacts were archived outside the active repo during the repo diet.

## Issues that were identified and then fixed

The following were surfaced by the independent numerics audit and then fixed immediately after:

- boundary checking now measures raw edge energy on the periodic FFT time grid
- `cost_and_gradient(...; log_cost=true)` now applies the optional dB transform after the full regularized scalar objective is assembled, so the returned gradient matches the scalar objective seen by the optimizer

Regression coverage for these fixes now lives in the fast Julia tier.

## Findings still worth keeping in active context

### Be explicit about objective scale

- The codebase contains both linear-cost and dB-cost paths.
- Historical bugs came from mixing those implicitly.
- Future agents should treat `log_cost=true` vs `log_cost=false` as an interface choice that must be documented whenever costs, gradients, HVPs, trust metrics, or diagnostics are compared.

### Curvature tooling must name its objective

- A Hessian-vector product for the linear physics cost is not automatically
  the curvature of a regularized dB-scale optimizer objective.
- Any future Newton, trust-region, or curvature-based work should state explicitly which scalar objective its HVP oracle represents.

### Sampling and runtime are part of the physics contract

- Longer fibers and higher powers need larger temporal windows as spectral
  broadening grows. Route supported runs through the shared grid resolver;
  do not revive hand-sized campaign grids.
- Keep FFTW internal threading at one for current grids unless a new benchmark
  demonstrates a benefit. Parallelize independent experiments or sweep cases.
- Copy mutable fiber state per concurrent solve.
- In multimode runs, Kerr tensor contractions can dominate FFT work; state the
  mode count whenever making performance claims.

### Very low-signal regimes still deserve caution

- The audit flagged solver-tolerance sensitivity and mixed-unit conditioning concerns in deep-suppression regimes.
- Those were not the same-day bugfix targets, and they remain reasonable places to be skeptical when interpreting extreme `-60 dB` / `-80 dB` style results.

### Mixed units remain a codebase smell

- `sim` carries a hybrid of ps, s, THz, and rad/ps conventions.
- This is survivable, but it remains a conditioning and readability hazard for future numerics work.

### Reduced-basis extension remains high leverage

- Reduced spectral phase is a supported control map; extend that contract rather than creating a parallel optimizer.

## Practical agent rule

When making numerics claims, prefer one of these buckets:

- fixed and regression-covered
- known open concern
- not re-verified in this pass

That avoids repeating the exact failure mode the second-opinion audit was created to catch.
