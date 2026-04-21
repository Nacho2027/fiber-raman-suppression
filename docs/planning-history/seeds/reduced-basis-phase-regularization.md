# Seed: Reduced-basis and regularized phase parameterization

**Planted:** 2026-04-20  
**Source:** Phase 25 numerical-analysis audit

## Why this deserves a phase

The project already decomposes optimized phases onto low-order polynomial
components and repeatedly asks whether phase structure is universal or arbitrary.
That is exactly the kind of setting where CS 4220's regularization / factor
selection ideas become phase-sized work.

## Scope

- Compare full-grid phase optimization to reduced parameterizations:
  polynomial, band-limited, spline, or other basis-constrained models
- Measure explained variance, suppression depth, robustness, and transferability
- Compare penalty-based regularization to explicit basis restriction

## Hypothesis

Some regimes are over-parameterized today. A reduced-basis model may improve
conditioning, robustness, and interpretability even if it sacrifices a small
amount of best-case dB.

## Why this matters

This may yield more practical value than adding ever more sophisticated
optimizers to an overly flexible full-grid representation.
