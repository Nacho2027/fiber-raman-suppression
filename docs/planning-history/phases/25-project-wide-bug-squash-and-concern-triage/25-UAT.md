---
status: complete
phase: 25-project-wide-bug-squash-and-concern-triage
started: 2026-04-20T00:00:00Z
updated: 2026-04-20T00:00:00Z
source:
  - 25-SUMMARY.md
---

## Current Test

number: 3
name: Fast-tier verification
expected: |
  `julia --project=. test/tier_fast.jl` passes after the environment is instantiated.
awaiting: none

## Tests

### 1. Invalid pulse form is rejected
expected: Unsupported pulse-shape input throws `ArgumentError` instead of constructing an undefined pulse.
result: passed

### 2. Dead gain placeholder removed cleanly
expected: The deleted `simulate_disp_gain_smf.jl` file is no longer referenced by live code paths that need to execute.
result: passed

### 3. Fast-tier verification
expected: `julia --project=. test/tier_fast.jl` passes after dependency instantiation.
result: passed

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0

## Gaps

None in this phase's acceptance scope. Structural hazards were deferred to seeds.
