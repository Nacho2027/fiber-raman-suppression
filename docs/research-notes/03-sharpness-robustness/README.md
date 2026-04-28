# Sharpness, Robustness Penalties, and Hessian Geometry

- status: `established tradeoff; not a default replacement`
- evidence snapshot: `2026-04-26`
- output: `03-sharpness-robustness.pdf`

## Purpose

Separate depth from robustness and show what the sharpness penalties did and did not buy.

## Main Evidence

- The completed sweep had `26` successful records and no failed records.
- Every resolved Hessian spectrum was indefinite in the optimized control space.
- Monte Carlo averaging gave the cheaper full-grid robustness improvement: about `+0.014 rad` tolerance for `3.85 dB` depth loss.
- The Hessian-trace penalty gave the largest tolerance gains: about `+0.058 rad` full-grid and `+0.066 rad` reduced-control, but with much larger depth cost.
- SAM did not produce a useful robustness Pareto improvement in this sweep.
- The plain log-cost objective remains the defensible default when maximum Raman suppression is the priority.

## Primary sources

- sharpness/robustness sweep summary in the synced Raman results tree
- historical Pareto summary figure in `docs/figures/`
- `scripts/research/sharpness/run.jl`
- `scripts/research/sharpness/summarize.jl`
- historical sharpness research summary under `docs/planning-history/`

## Figure Rule

Representative result pages pair the phase diagnostic with the corresponding
spectral-evolution heat map on the same page. The first paired page is the
no-optimization control.
