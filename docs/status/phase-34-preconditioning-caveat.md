# Phase 34 Preconditioning Status And Caveat

This note records the current interpretation status for Phase 34 preconditioning work.

## Current status

The original `M`-wiring caveat has now been addressed:

- `optimize_spectral_phase_tr` forwards `M` into `solve_subproblem`
- the Phase 34 benchmark driver passes its built preconditioner through that path
- regression coverage now checks that the outer loop actually uses `M`

So current PCG runs are no longer suffering from the earlier "preconditioner silently dropped" problem.

## The new short version

The important caveat has changed.

The current issue is no longer missing wiring. It is that preconditioning must respect the gauge-projected subspace used by the trust-region outer loop.

That problem has also been partially addressed:

- the PCG path now reprojects preconditioned residuals, directions, and the final step back into the gauge-complement

This removed the immediate `GAUGE_LEAK` failures that appeared as soon as real preconditioners were admitted into the main path.

## Why this matters

The Phase 34 story now has two stages:

1. before the wiring fix, full benchmark comparisons could not be trusted because nominal preconditioners might still behave like the identity case
2. after the wiring fix and gauge-safe projection fix, the preconditioners are finally being tested honestly on the main path

That is a real research transition: the comparisons are now more meaningful, but they still need to be interpreted as early bounded-case evidence rather than final Phase 34 verdicts.

## What is confirmed

The old gap was visible in the code path:

- `scripts/research/trust_region/trust_region_optimize.jl` calls:
  `solve_subproblem(solver, g, H_op, Δ; M=M, proj=_proj)`
- `scripts/research/trust_region/trust_region_pcg.jl` expects:
  `solve_subproblem(...; M=nothing, proj=identity, ...)`

The current bounded reruns through the real outer loop show:

- `:none` remains a strong baseline on final objective
- `:dispersion` is close to `:none` on final objective and cheaper in wall time on the small test
- `:dct` gives healthier and more consistent accepted-step `ρ` values, but did not beat `:none` on final objective in the small bounded tests

## What is still useful despite the caveat

The caveat does **not** erase Phase 34. It sharpens it.

Useful results that still stand:

- the `Δ0` sweep showed cold-start collapse is not just a bad initial radius choice
- the PCG smoke result indicated the conditioning hypothesis was plausible before the main-path fix
- the post-fix bounded reruns now show that preconditioners can run honestly on the main path without immediate `GAUGE_LEAK`
- the remaining question is no longer "does the preconditioner enter the solver?" but "does better step acceptance become better final Raman suppression?"

## Recommended interpretation

Treat current Phase 34 evidence in two buckets.

### Bucket 1: reliable

- radius-collapse diagnosis from the `Δ0` sweep
- the claim that curvature conditioning is the next real question
- smoke-level evidence that direct-wired preconditioning can improve acceptance behavior
- bounded main-path evidence that gauge-safe `:dispersion` and `:dct` runs are now genuinely distinct from `:none`

### Bucket 2: provisional

- any claim that preconditioning already improves the scientifically relevant final Raman objective in the regimes that matter most

Those claims still need a harder bounded comparison and then a larger benchmark pass.

## What should happen next

Before drawing stronger scientific conclusions from Phase 34 benchmarks, the right next steps are:

1. compare `:none`, `:dispersion`, and `:dct` on a slightly harder but still bounded cold-start case
2. decide whether Phase 34 should optimize for final objective, convergence speed, or cold-start recovery
3. only then rerun a broader benchmark slice

Until then, the correct reading is:

- the **preconditioning hypothesis remains alive**
- the **wiring problem is fixed**
- the **current remaining question is effectiveness, not plumbing**

## Sources

- `scripts/research/trust_region/trust_region_optimize.jl`
- `scripts/research/trust_region/trust_region_pcg.jl`
- `results/raman/phase34/pcg_smoke/smoke.jld2`
