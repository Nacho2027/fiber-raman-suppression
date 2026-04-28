# Phase 30 Status

This note is the short human-facing status of Phase 30.

## What Phase 30 was trying to answer

Phase 30 turned continuation from an informal warm-start habit into an explicit numerical method with:

- a declared ladder
- predictor/corrector structure
- failure detectors
- per-step trust reporting
- a required cold-start comparison

The flagship reference run was a long-fiber SMF-28 ladder at `L = 1 -> 10 -> 100 m`.

## Current status

**Methodology implemented, flagship evidence incomplete.**

The continuation scaffold exists in:

- `scripts/research/analysis/continuation.jl`
- `scripts/research/phases/phase30/reference_run.jl`

The first heavy run was attempted on `2026-04-21`, but the empirical head-to-head did not complete.

## What actually happened

From the Phase 30 planning-history result note:

- the cold-start arm ran step 1 at `L = 1 m` to about `-38.07 dB`
- the cold-start arm degraded badly at `L = 10 m`, reaching only about `-1.17 dB`
- the run then died during the `L = 100 m` step when grid auto-sizing pushed to `Nt = 8,388,608`
- the continuation arm never started

So Phase 30 did **not** produce the intended cold-start vs continuation comparison on the flagship regime.

## What we learned anyway

Even though the run failed, it still taught two useful things.

### 1. The continuation machinery itself is real

This phase is not blocked on missing API work. The repo has an explicit continuation framework with detectors and trust hooks, rather than scattered ad hoc warm starts.

### 2. The first flagship regime was infrastructure-bad, not just numerically hard

The long-fiber SMF-28 reference run exposed a practical issue:

- `setup_raman_problem` auto-sizing is physically reasonable
- but it makes the selected `100 m` regime too expensive for this reference-run shape

So the first blocked item is not "does continuation exist?" It is "can the reference run be executed in a bounded regime or with an explicit grid cap?"

## Recommended interpretation

Future sessions should read Phase 30 as:

- **successful as methodology scaffolding**
- **incomplete as empirical evidence**

Do not cite Phase 30 as proving continuation beats cold start on the long-fiber benchmark. It does not.

## What should happen next

The next honest Phase 30 follow-up is one of:

1. Re-run the reference case with an explicit `Nt` / time-window cap appropriate for methodology comparison.
2. Re-scope the ladder to a hard but bounded regime where both arms can complete.

Until then, Phase 30 should be treated as "framework landed, benchmark inconclusive."

## Source

- Primary status artifact: `docs/planning-history/phases/30-continuation-and-homotopy-schedules-for-hard-raman-regimes/30-RESULTS.md`
