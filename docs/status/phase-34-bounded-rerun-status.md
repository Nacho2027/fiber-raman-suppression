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

## Focused follow-up: `:none` vs `:dispersion` on continuation-style starts

After the broader bounded reruns, the comparison was narrowed to the two variants that still looked plausible:

- `:none`
- `:dispersion`

### Pair A: `L = 0.5 m -> 1.0 m`, `P = 0.1 W`, `Nt = 256`

Result:

- `:none`: `J ≈ 1.29e-6`, accepted 4 steps, converged to a first-order saddle
- `:dispersion`: `J ≈ 1.18e-6`, accepted 4 steps, converged to a first-order saddle

Interpretation:

- This confirms the earlier bounded rerun: on the easier continuation-style transfer, `:dispersion` is slightly better than `:none` while preserving the same qualitative behavior.

### Pair B: `L = 1.0 m -> 2.0 m`, `P = 0.1 W`

This pair required explicit cross-grid interpolation because the target problem auto-sized from `Nt = 256` to `Nt = 2048`.

Result:

- `:none`: `J ≈ 1.18e-1`, accepted 4 steps, `MAX_ITER`
- `:dispersion`: `J ≈ 1.14e-1`, accepted 5 steps, `MAX_ITER`

Interpretation:

- Even on the harder auto-sized transfer, the continuation-style start remains viable
- `:dispersion` again beats `:none`, both in final objective and in accepted-step count
- the margin is still moderate, but it is now consistent across the bounded continuation-style tests that have been run

## Short continuation ladder benchmark

To test whether the small bounded `:dispersion` advantage compounds across steps, a short continuation ladder was run with:

- base solve at `L = 0.5 m` using L-BFGS
- trust-region continuation steps at `L = 1.0 m` and `L = 2.0 m`
- fixed `P = 0.1 W`
- requested `Nt = 256`
- requested `time_window = 10 ps`
- variants: `:none` and `:dispersion`

Each variant carried its own previous-rung trust-region solution forward to the next rung.

### Ladder result

Base rung:

- `L = 0.5 m` L-BFGS: `J ≈ 8.14e-8`

First trust-region rung:

- `:none`, `0.5 -> 1.0 m`: `J ≈ 1.29e-6`, accepted 4, rejected 2
- `:dispersion`, `0.5 -> 1.0 m`: `J ≈ 1.18e-6`, accepted 4, rejected 2

Second trust-region rung:

- `:none`, `1.0 -> 2.0 m`: `J ≈ 5.17e-6`, accepted 3, rejected 7
- `:dispersion`, `1.0 -> 2.0 m`: `J ≈ 3.90e-6`, accepted 5, rejected 5

Interpretation:

- the small `:dispersion` advantage survives the stepwise ladder
- on the harder `1.0 -> 2.0 m` rung, that advantage becomes more meaningful
- this is the clearest bounded evidence so far that the useful Phase 34 branch is:
  continuation-style path + trust-region + `:dispersion`

This still does **not** show that preconditioning replaces continuation. It shows the opposite:

- once continuation has already supplied a viable path, `:dispersion` can improve the local second-order step sequence
- without that path, preconditioning alone still does not rescue poor cold starts

### Visible follow-up note

One one-off runner used during this investigation printed absurdly large source/target time-window values. That was a **status-line unit-conversion bug only**, not a simulation bug:

- in this code path, `sim["time_window"]` is already stored in picoseconds
- multiplying by `1e12` again only corrupted the printed summary line
- the interpolation and optimization logic were otherwise consistent

This should be cleaned up in any future ad hoc analysis snippets, but it did not invalidate the comparison results above.

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

## Cross-power validation and success metric

After the first short ladder at `P = 0.1 W`, the same bounded ladder was rerun at nearby powers `P = 0.08, 0.10, 0.12 W` to test whether the apparent `:dispersion` advantage was stable.

The explicit success metric for this validation is:

- **primary metric:** final `J` on the hardest rung (`1.0 -> 2.0 m`)

Secondary metrics are still useful, but only as support:

- accepted-step count on the hardest rung
- accepted-step `rho`
- HVP count as a bounded cost proxy

This matters because accepted steps alone can look healthier without actually improving the Raman objective.

### What the power validation showed

Hardest-rung result summary:

- `P = 0.08 W`: `:none` won clearly on final `J` and accepted-step count
- `P = 0.10 W`: `:dispersion` won on final `J` and accepted-step count
- `P = 0.12 W`: both variants collapsed; `:dispersion` was only marginally better on final `J`

Interpretation:

- `:dispersion` improved the primary metric in `2/3` nearby power settings
- but the win is **not** universal
- the `0.08 W` case is a real counterexample and should not be hidden by averaging language

So the strongest defensible statement right now is:

- `:dispersion` is the right **default Phase 34 comparison branch**
- `:none` must remain the baseline
- the benefit appears regime-dependent rather than guaranteed

That is still a useful outcome. It means future work should test whether the `:dispersion` gain is strongest only in a middle continuation-stress band, rather than assuming it monotonically helps everywhere.

## Dense burst-side power sweep

To tighten that "middle band" hypothesis, the same bounded ladder was rerun on burst at:

- `P = 0.07, 0.08, 0.09, 0.10, 0.11, 0.12, 0.13 W`

using the same primary metric:

- hardest-rung final `J` on `1.0 -> 2.0 m`

### Dense-sweep result

Hardest-rung outcome by power:

- `0.07 W`: `:none` better
- `0.08 W`: `:none` better
- `0.09 W`: `:none` better
- `0.10 W`: `:dispersion` better
- `0.11 W`: `:dispersion` better
- `0.12 W`: `:dispersion` only marginally better, but both collapsed
- `0.13 W`: tie, with both collapsed

Interpretation:

- this is the clearest evidence so far of a **regime crossover**
- `:dispersion` is not broadly helpful at lower powers in this bounded continuation ladder
- `:dispersion` becomes competitive and then mildly better in the middle band around `0.10–0.11 W`
- above that, both methods run into collapse behavior, so the apparent `:dispersion` edge is no longer scientifically strong

The meaningful research update is therefore not:

- "`:dispersion` wins"

It is:

- "`:dispersion` seems most useful in a middle continuation-stress band, not at the easy low-power end and not in the hard collapse regime"

That is a more specific and more actionable claim than anything available before the burst sweep.

## Focused mid-band rerun at larger TR budget

The dense burst sweep still left one ambiguity:

- was the `0.10–0.11 W` advantage a real regime effect, or just a short-budget artifact?

To test that, the same bounded ladder was rerun only at:

- `P = 0.09, 0.10, 0.11 W`

but with a larger trust-region budget:

- `TR max_iter = 20`
- `PCG max_iter = 30`

### Longer-budget result

Hardest-rung outcome:

- `0.09 W`: `:none` still better
- `0.10 W`: `:dispersion` still better
- `0.11 W`: `:none` slightly better

Interpretation:

- the `0.10 W` win is **not** just a short-budget artifact
- the `0.11 W` advantage from the short-budget sweep does **not** survive the larger TR budget
- so the strongest current claim is narrower than "middle band 0.10–0.11 W"

The cleaner statement is:

- there is a **localized regime near `0.10 W`** where `:dispersion` genuinely helps
- outside that local window, `:none` is often as good or better

That is a real result. It means the interesting scientific question has changed again:

- not "is `:dispersion` better?"
- but "what changes around the `0.10 W` regime that makes dispersion preconditioning become useful there?"

## Final decision

This note was originally written as a live status document while the bounded reruns were still open.

That is no longer the right reading.

After the denser bounded validation and the longer-budget reruns, the correct project-level conclusion is:

- the branch is now closed as an active Raman-suppression research path

Why:

- `:dispersion` never became a broad or stable win
- the strongest signal was a localized bounded-case effect, not a transferable result
- continuation remained the main driver of success throughout
- `:dct` and the other alternatives did not justify more attention

So the bounded reruns should now be read as a closure record, not as a prompt for open-ended follow-up.

## What remains useful

The useful durable conclusions from these reruns are:

- the trust-region preconditioning path is now technically honest
- gauge-safe PCG handling is necessary
- continuation helps far more than preconditioning alone
- `:dispersion` was the only candidate that ever looked plausible, and even that case was too narrow to keep alive as a Raman-suppression branch

For the formal closure decision, see:

- [phase-34-dispersion-closure.md](./phase-34-dispersion-closure.md)
