# Seed: Truncated-Newton / Krylov / preconditioning path

**Planted:** 2026-04-20  
**Source:** Phase 25 numerical-analysis audit

## Why this deserves a phase

This repo already has matrix-free Hessian-vector products and Lanczos-style
eigenspectrum analysis. That means a Krylov-based second-order path is a real
extension target, not a theoretical detour.

## Scope

- Build a truncated-Newton style solver using matrix-free HVPs
- Explore Krylov inner solves and practical preconditioning strategies
- Compare against L-BFGS on both quality and trust metrics
- Reuse existing HVP / eigenspectrum code paths wherever possible

## Key question

Can matrix-free curvature information improve convergence or robustness enough
to justify the added complexity once scaling and globalization are handled?

## Why not do this immediately

Without prior work on scaling and globalization, this phase would likely
produce misleading comparisons. It should follow, not precede, the numerical
governance work.
