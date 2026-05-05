# Numerics Notes

This file distills what remains agent-relevant from the April 20 numerics audit and same-day follow-up fixes.

Source artifacts were archived outside the active repo during the repo diet.

## Issues that were identified and then fixed

The following were surfaced by the independent numerics audit and then fixed immediately after:

- boundary checking now measures pre-attenuator edge fraction rather than only post-absorber residue
- `cost_and_gradient(...; log_cost=true)` now applies the optional dB transform after the full regularized scalar objective is assembled, so the returned gradient matches the scalar objective seen by the optimizer
- `chirp_sensitivity` now returns linear `J`, so plotting converts to dB exactly once

Regression coverage for these fixes now lives in the fast Julia tier.

## Findings still worth keeping in active context

### Be explicit about objective scale

- The codebase contains both linear-cost and dB-cost paths.
- Historical bugs came from mixing those implicitly.
- Future agents should treat `log_cost=true` vs `log_cost=false` as an interface choice that must be documented whenever costs, gradients, HVPs, trust metrics, or diagnostics are compared.

### Hessian tooling is not automatically the optimizer Hessian

- The Phase 13 matrix-free Hessian tooling was historically pointed at the linear physics cost.
- That makes it useful, but not automatically the curvature of every regularized dB-scale optimizer objective.
- Any future Newton, trust-region, or curvature-based work should state explicitly which scalar objective its HVP oracle represents.

### Very low-signal regimes still deserve caution

- The audit flagged solver-tolerance sensitivity and mixed-unit conditioning concerns in deep-suppression regimes.
- Those were not the same-day bugfix targets, and they remain reasonable places to be skeptical when interpreting extreme `-60 dB` / `-80 dB` style results.

### Mixed units remain a codebase smell

- `sim` carries a hybrid of ps, s, THz, and rad/ps conventions.
- This is survivable, but it remains a conditioning and readability hazard for future numerics work.

### Reduced-basis extension remains high leverage

- The audit correctly highlighted that reduced-basis machinery already exists on the amplitude side.
- For future agent work, "reduced basis for phase" should be treated as an extension of existing machinery, not a greenfield idea.

## Practical agent rule

When making numerics claims, prefer one of these buckets:

- fixed and regression-covered
- known open concern
- not re-verified in this pass

That avoids repeating the exact failure mode the second-opinion audit was created to catch.
