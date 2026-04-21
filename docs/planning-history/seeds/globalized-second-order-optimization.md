# Seed: Globalized second-order optimization for Raman suppression

**Planted:** 2026-04-20  
**Source:** Phase 25 numerical-analysis audit

## Why this deserves a phase

The repo is already moving toward Hessian-aware and sharpness-aware work, but
CS 4220's optimization/globalization material makes the missing piece clear:
future second-order methods must be safeguarded.

Raw local Newton-style updates are not enough. The real phase is:
- choose a second-order search direction,
- globalize it,
- and benchmark basin robustness honestly.

## Scope

- Implement a safeguarded second-order optimizer path parallel to existing
  L-BFGS, not replacing it.
- Use backtracking or trust-region logic for step acceptance.
- Benchmark sensitivity to initialization and scaling.
- Report when the method fails gracefully rather than drifting into
  untrustworthy "best achieved" behavior.

## Dependencies

- Best done after the conditioning/backward-error framework seed
- Should build on existing HVP infrastructure rather than dense Hessians

## Success condition

The method is only successful if it improves robustness or interpretability
under honest trust metrics, not merely if it occasionally reaches a lower dB.
