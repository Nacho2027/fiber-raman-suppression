# Phase 32 Status

This note is the short human-facing status of Phase 32.

## What Phase 32 was trying to answer

Phase 32 asked a narrow question:

Can acceleration save expensive solves **without** weakening trust, when compared against explicit continuation rather than against cold start?

The main candidates were:

- Richardson extrapolation on refinement ladders
- polynomial warm-start prediction
- offline MPE / RRE combinations of previous converged solutions

## Current status

**Partially executed, with one clear negative result and no final phase verdict yet.**

The phase has real implementation artifacts:

- `scripts/research/phases/phase32/richardson_audit.jl`
- `scripts/research/phases/phase32/demo.jl`
- `scripts/research/phases/phase32/mpe_offline.jl`

and partial results under `results/phase32/`.

## What has actually run

### Experiment 0: Richardson applicability audit

This experiment **did run**.

The saved result in `results/phase32/richardson_audit.jld2` says:

- `p_fit = -0.00054`
- `R² = 0.405`
- verdict = `NOT_APPLICABLE`

Interpretation:

- the measured `J(Nt)` data did not follow a clean `C + A * Nt^{-p}` convergence law
- Richardson extrapolation is not trustworthy here

This is a real result, not a placeholder. It is a good example of the Phase 32 rule that "not worth it" can still be a successful outcome.

### Experiment 1: polynomial warm-start on the `L = 1 -> 10 -> 100 m` ladder

This experiment is only **partially present** on disk.

Saved artifacts show:

- `results_cold.jld2`
- `results_naive.jld2`
- trust markdown for cold and naive steps

But there is no matching completed accel-arm bundle in the checked results tree.

The partial numbers on disk are:

- cold arm: `-34.58 dB`, then `-26.17 dB`, status `["ok", "broken"]`
- naive arm: `-34.58 dB`, then `-27.63 dB`, status `["ok", "broken"]`

So at minimum:

- the run did not finish all three arms cleanly
- the intended polynomial-acceleration comparison is not yet complete
- no honest Experiment 1 verdict should be claimed from the current tree

### Experiment 2: offline MPE / RRE polish

The driver exists, but the corresponding result tree is not present in the checked artifacts here.

So this should be treated as **not yet evidenced** in the current workspace snapshot.

## What we can say now

Phase 32 has already delivered one useful conclusion:

- **Richardson is not a viable acceleration path for this problem in its audited form.**

What it has **not** delivered yet is a full phase-level answer about whether polynomial prediction or offline MPE / RRE are worth keeping.

## Recommended interpretation

Future sessions should treat Phase 32 as:

- **one completed negative result** on Richardson
- **partial evidence only** on polynomial warm starts
- **no final verdict yet** on the overall acceleration agenda

Do not describe Phase 32 as fully executed until the accel arm and offline MPE / RRE results are either completed or explicitly closed out as abandoned.

## What should happen next

The cleanest follow-up is:

1. Write down whether Experiment 1 was interrupted, failed, or intentionally stopped.
2. Either finish the accel-arm comparison or explicitly close it as incomplete.
3. Do the same for Experiment 2.

Until that happens, the reliable takeaway is simply:

- Richardson: no
- polynomial / MPE / RRE: still unresolved in practice

## Sources

- `results/phase32/richardson_audit.jld2`
- `results/phase32/expt1_polywarmstart_L100m/results_cold.jld2`
- `results/phase32/expt1_polywarmstart_L100m/results_naive.jld2`
- `docs/planning-history/phases/32-extrapolation-and-acceleration-for-parameter-studies-and-con/32-RESULTS.md`
