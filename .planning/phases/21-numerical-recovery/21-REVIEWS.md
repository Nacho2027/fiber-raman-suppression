# Phase 21 Plan Review

**Date:** 2026-04-20  
**Reviewer:** Session I self-review (external CLI review not guaranteed in this environment)

## Findings

### 1. Highest-risk item is Sweep-1 grid choice

The original window formula already existed in the repo and still under-sized
the `L=2 m, P=0.2 W` family. The plan is only defensible because it does **not**
trust the formula alone; it explicitly validates the flat pulse and all stored
warm-start phases on the candidate grid before launching recovery optimizations.

### 2. Session F 100 m should not be re-optimized by default

The user's priority #2 is schema recovery and honest validation, not a new
long-fiber campaign. The plan correctly treats 100 m as a schema-normalization
task unless the stored phase is missing or inconsistent.

### 3. Phase 13 must report more than a new dB number

A re-anchor that only prints the new `J_dB` is weak. The plan correctly
requires a verdict on whether the original stationary point persisted on the
repaired grid.

### 4. MMF must remain opportunistic

Trying to force the MMF aggressive run before the first three buckets are done
would risk the overnight budget. Keeping it opportunistic is the right call.

## Verdict

Plan is acceptable for execution. The main operational risk is burst-runtime
debugging of the new recovery scripts, so the implementation should be pushed in
one clean chunk before the first VM job starts.
