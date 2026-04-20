# Phase 34 Context — Truncated-Newton Krylov preconditioning

**Gathered:** 2026-04-20  
**Status:** Complete  
**Mode:** Autonomous seed promotion / phase-definition only

## Locked Decisions

- This phase is matrix-free by default.
- HVP reuse from Phase 13 is mandatory.
- Preconditioning is part of the experiment design, not a deferred optional.
- Comparison baselines are L-BFGS and Phase 33's safeguarded second-order path.
