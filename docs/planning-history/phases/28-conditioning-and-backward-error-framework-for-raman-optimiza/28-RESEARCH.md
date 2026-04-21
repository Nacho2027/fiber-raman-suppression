# Phase 28 Research — Conditioning and backward-error framework

## Why this phase comes first

Phase 27's strongest conclusion was that future optimizer comparisons are weak
until the repo has a standing numerical trust contract. The numerics audit's
two follow-up bugs reinforced that point: the project can still produce
plausible-looking results while measuring the wrong surface or silently hiding
boundary loss.

## Required deliverables

- A trust-report schema attached to every serious optimization run
- A conditioning/scaling memo for phase, amplitude, and mixed-variable
  optimization paths
- Forward / backward / mixed error conventions for the project
- Standard pass/fail thresholds for determinism, edge fraction, energy drift,
  and gradient validation

## Recommended implementation order

1. Define the report schema and thresholds.
2. Add a read-only reporter utility that can evaluate existing JLD2 results.
3. Wire the utility into active run scripts.
4. Promote the report into a required acceptance gate for later phases.
