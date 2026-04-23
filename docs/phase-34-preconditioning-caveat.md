# Phase 34 Preconditioning Caveat

This note records the most important interpretation caveat for current Phase 34 results.

## The short version

Some early Phase 34 benchmark comparisons should **not** be read as true preconditioned benchmark evidence.

The reason is simple:

- `PreconditionedCGSolver` supports a preconditioner passed as `M`
- but the main trust-region outer loop currently calls `solve_subproblem(solver, g, H_op, Δ)` without forwarding `M`

So in that path, the configured solver can still run as if no preconditioner was supplied.

## Why this matters

If `M` is not forwarded, then a benchmark labeled with a preconditioner name may still behave like the identity / unpreconditioned case inside the actual subproblem solve.

That means:

- solver-type comparisons may be overstated
- negative results may say more about wiring than about the preconditioner idea itself
- apparent parity with Steihaug can be an artifact of bypass, not a scientific verdict

## What is confirmed

The gap is visible in the current code path:

- `scripts/trust_region_optimize.jl` calls:
  `solve_subproblem(solver, g, H_op, Δ)`
- `scripts/trust_region_pcg.jl` expects:
  `solve_subproblem(...; M=nothing, ...)`

So unless some caller-specific path injects `M` directly, the prebuilt preconditioner is bypassed.

This matches the project state note in `docs/planning-history/STATE.md`:

- "M-kwarg wiring gap: optimize_spectral_phase_tr does not forward preconditioner M kwarg into solve_subproblem"

## What is still useful despite the caveat

The caveat does **not** erase all of Phase 34.

Useful results that still stand:

- the `Δ0` sweep showed cold-start collapse is not just a bad initial radius choice
- the PCG smoke result indicates the conditioning hypothesis is plausible when the solver is direct-wired in a smoke setup

In particular, the smoke artifact in `results/raman/phase34/pcg_smoke/smoke.jld2` shows high `rho` values for multiple preconditioner choices on a small cold-start oracle. That supports the idea that preconditioning may help once the benchmark path is wired correctly.

## Recommended interpretation

Treat current Phase 34 evidence in two buckets.

### Bucket 1: reliable

- radius-collapse diagnosis from the `Δ0` sweep
- the claim that curvature conditioning is the next real question
- smoke-level evidence that direct-wired preconditioning can improve acceptance behavior

### Bucket 2: provisional

- any full benchmark comparison that depends on the main outer-loop path using the intended preconditioner

Those results are provisional until the `M` forwarding path is fixed and regression-tested.

## What should happen next

Before drawing stronger scientific conclusions from Phase 34 benchmarks:

1. forward `M` through the trust-region outer loop
2. add a regression test proving the configured preconditioner actually reaches `solve_subproblem`
3. rerun the smallest honest benchmark or smoke comparison

Until then, the correct reading is:

- the **preconditioning hypothesis remains alive**
- the **benchmark wiring is not yet strong enough** to treat all current Phase 34 comparisons as final

## Sources

- `docs/planning-history/STATE.md`
- `scripts/trust_region_optimize.jl`
- `scripts/trust_region_pcg.jl`
- `results/raman/phase34/pcg_smoke/smoke.jld2`
