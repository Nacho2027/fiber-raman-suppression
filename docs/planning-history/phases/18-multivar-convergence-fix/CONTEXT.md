# Phase 18 — Multivariable Joint-Space Convergence Fix

**Opened:** 2026-04-19 (integration of Session A / Phase 16 multivar)
**Status:** Open follow-up. Infra landed via merge(A); physics is incomplete.

## Background

Session A built a joint `{φ(ω), A(ω), E_in}` L-BFGS optimizer (`scripts/multivar_optimization.jl`, `scripts/multivar_demo.jl`, plus unit + gradient tests) parallel to the phase-only path. The infrastructure is sound: the gradient tests pass, the objective evaluation is consistent with the forward/adjoint stack, and the standard-images hook is wired.

**The physics does not converge.** On SMF-28 L=2m P=0.30W:

| Initialization | Final J (dB) |
|---|---|
| Phase-only (warm-start baseline) | -55.42 |
| Joint-space cold start | **-16.78** |

L-BFGS in joint space halts far from any meaningful optimum. Full writeup: `.planning/phases/16-multivar-optimizer/16-01-SUMMARY.md` §Follow-ups.

## Why this matters

Joint {φ, A, E} should *at worst* equal phase-only (the phase-only solution is a feasible point in the joint search space). A 38-dB gap means the joint-space problem has pathological scaling, a preconditioning issue, or a step-control issue — not a lack of good minima.

## Candidate fixes (from Session A's recommendations, roughly in order of effort)

1. **Amplitude-only warm-start.** Run amplitude-only first (phase frozen at zero), then unfreeze phase. Cheapest path; confirms the amplitude sub-problem is well-posed.
2. **Two-stage freeze-φ-then-unfreeze.** Start from the phase-only optimum, freeze φ, optimize amplitude alone, then jointly refine. Close to #1 but starts from better initial J.
3. **Diagonal Hessian preconditioner.** L-BFGS's implicit Hessian estimate is poorly-scaled across variable types (phase radians vs amplitude fractions vs total energy Joules). A cheap diagonal precond (e.g., use Phase 13's Hessian-diagonal estimate) should fix most of it.
4. **Trust-region Newton.** If #1–#3 don't fix it, the joint problem likely has indefinite curvature L-BFGS can't handle — use Newton with trust-region (Phase 13 already found indefinite Hessians at canonical optima).

## Definition of done

- Joint-space cold start reaches within 1 dB of phase-only warm-start on SMF-28 L=2m P=0.30W.
- At least one test point where joint beats phase-only by ≥ 3 dB (demonstrating the extra design freedom actually helps).
- Standard-images set produced for both.

## Inputs

- Session A's infra: `scripts/multivar_optimization.jl`, `scripts/multivar_demo.jl`.
- Session A's SUMMARY: `.planning/phases/16-multivar-optimizer/16-01-SUMMARY.md`.
- Phase 13 Hessian-diagonal tooling (for option 3).

## Not in scope

- Redesigning the cost function. Stick with the current log-dB cost (validated by Session H).
- Multi-mode. Session C's scaffolding is separate.
