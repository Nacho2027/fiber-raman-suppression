# Seed: Continuation and homotopy schedules for hard Raman regimes

**Planted:** 2026-04-20  
**Source:** Phase 25 numerical-analysis audit

## Why this deserves a phase

The project already relies heavily on warm starts across fiber length, power,
phase complexity, and long-fiber transfers. CS 4220 frames continuation as a
first-class numerical tactic, and this repo is a natural fit for it.

## Scope

- Define explicit continuation schedules over variables such as:
  `L`, `P`, `N_phi`, regularization strength, multimode complexity, or
  optimizer sharpness weight
- Add failure detection and trust checks along the continuation path
- Compare path-following results against cold-start optimization in hard regimes

## Potential payoff

- Larger basins of convergence
- More reproducible entry into difficult regimes
- Better understanding of when "solution transfer" is real versus accidental

## Dependencies

- Pairs naturally with globalization and conditioning work
- Can reuse existing sweep and warm-start infrastructure
