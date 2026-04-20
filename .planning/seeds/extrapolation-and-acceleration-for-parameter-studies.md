# Seed: Extrapolation and acceleration for parameter studies and continuation

**Planted:** 2026-04-20  
**Source:** Phase 25 NMDS pass

## Why this deserves a phase

This project repeatedly computes structured families of related solves:
- sweep grids,
- long-fiber transfers,
- basis-size studies,
- and continuation-like warm-start chains.

The `nmds` extrapolation/acceleration material suggests a different lever from
"better outer optimizer": accelerate sequences of related solves or iterates.

## Scope

- Identify one or two study families where sequence acceleration is plausible
- Compare naive warm-start chains against accelerated variants
- Measure whether acceleration reduces the number of expensive fully optimized
  points needed for a trustworthy study

## Candidate targets

- `N_phi` continuation or basis-size ladders
- parameter sweeps in `L,P`
- regularization-strength schedules

## Success condition

This phase is only worth promoting if acceleration reduces expensive solve count
without weakening numerical trust. If it only adds complexity to save trivial
runtime, the correct verdict is "not worth it."
