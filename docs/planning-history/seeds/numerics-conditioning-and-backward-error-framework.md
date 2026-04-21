# Seed: Conditioning and backward-error framework for Raman optimization

**Planted:** 2026-04-20  
**Source:** Phase 25 numerical-analysis audit

## Why this deserves a phase

This is the most foundational missing numerical layer in the repo.
Several high-impact issues already fixed by the project can be reinterpreted as
conditioning / trust failures:
- wrong grid but good-looking dB,
- nondeterministic FFT planning,
- objective/gradient scaling mismatch,
- weakly standardized stopping/reporting criteria.

The next step is to turn those lessons into a standing framework instead of
rediscovering them piecemeal.

## Scope

- Define a standard numerical trust report for optimization runs:
  determinism, edge fraction, energy drift, gradient-test status, and scaled
  stopping criteria.
- Audit current optimizer variables and objectives for conditioning/scaling.
- Propose dimensionless or physically scaled coordinates where appropriate.
- Define forward / backward / mixed error conventions for this project.

## Deliverables

- A reusable trust-report utility for future phases
- A conditioning/scaling memo with recommended variable transformations
- Updated run-report conventions for future numerical experiments

## Why now

This phase should come before any ambitious Newton / Hessian / multivariable
optimizer rollout. Otherwise, those later phases will be comparing methods on a
poorly scaled, weakly governed footing.
