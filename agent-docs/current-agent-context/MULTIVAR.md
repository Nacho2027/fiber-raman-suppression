# Multi-Parameter Optimization Status

This note captures the durable, agent-relevant status of the codebase's
multi-parameter optimization path.

## Current status

Multi-parameter optimization exists, but it is still an experimental research
path rather than a converged production workflow. The current best-supported
interpretation separates the broad joint optimizer from the narrower
amplitude-on-fixed-phase candidate.

The implementation can jointly optimize:

- spectral `:phase`
- spectral `:amplitude`
- input `:energy`

The implementation does **not** yet support `:mode_coeffs` end-to-end. That
symbol is present as a future extension point, but the current code strips it
with a warning.

## Where the code lives

- Core implementation:
  `scripts/research/multivar/multivar_optimization.jl`
- Demo driver:
  `scripts/research/multivar/multivar_demo.jl`
- Smoke tests:
  `scripts/dev/smoke/test_multivar_unit.jl`
  `scripts/dev/smoke/test_multivar_gradients.jl`

## What is verified

- The helper layer for packing/unpacking, block layout, scaling, and config
  defaults is covered by the lightweight unit test and passes locally.
- Historical burst-VM runs documented successful finite-difference vs adjoint
  gradient checks for the implemented variable blocks.
- The saved multivar artifacts are included in
  `scripts/validation/validate_results.jl`.

## Current evidence boundary

The main issue is optimizer behavior and hardware readiness in the expanded
control space, not missing infrastructure.

At the canonical demo point (`SMF-28`, `L = 2 m`, `P = 0.30 W`), the accepted
2026-04-24 joint-optimizer run showed:

- phase-only: `J_after = -40.8 dB`
- joint phase+amplitude, cold start: `J_after = -18.3 dB`
- joint phase+amplitude, warm start: `J_after = -31.2 dB`

Interpretation: the broad joint path runs, but it should not be promoted as a
lab-facing optimizer because it underperforms phase-only at the reference
configuration.

A focused follow-up ablation then tested amplitude-only shaping on top of the
fixed phase-only optimum:

- phase-only reference: `J_after = -40.79 dB`
- amplitude-on-fixed-phase: `J_after = -44.34 dB`
- improvement: `3.55 dB`
- amplitude range: `[0.908, 1.090]`

Interpretation: broad joint phase+amplitude remains experimental/negative, but
fixed-phase amplitude refinement is now a promising candidate that deserves
repeatability and hardware-export validation.

## Practical rule for future agents

Treat the multivar path as:

- a valid research scaffold
- a usable objective/gradient implementation for further optimizer work
- a source of prior artifacts worth validating against

Do **not** treat it as:

- the repository's canonical optimization workflow
- a proven improvement over phase-only shaping
- a finished general framework for adding arbitrary optimization variables
- hardware-ready amplitude shaping

## Highest-value next steps

The open follow-up work is now:

1. deterministic repeatability rerun of amplitude-on-fixed-phase
2. hardware-constrained export review for the bounded amplitude profile
3. small robustness check around the canonical `L = 2 m`, `P = 0.30 W` point
4. only after those pass, consider a two-stage workflow that exposes
   amplitude-on-phase as an optional refinement rather than a default
5. defer broad joint phase+amplitude tuning until a new physical or numerical
   hypothesis justifies it

## Artifact caveat

`scripts/research/multivar/multivar_demo.jl` now calls `save_standard_set(...)`,
but the current synced workspace snapshot only shows the multivar JLD2 payloads
under `results/raman/multivar/smf28_L2m_P030W/`.

If expected PNGs are missing, treat that as an artifact-sync or retention issue,
not as evidence that the code never supported standard image generation.

## Pointers

- Joint negative result:
  `docs/status/multivar-canonical-negative-result-2026-04-24.md`
- Positive amplitude-on-phase ablation:
  `docs/status/multivar-amp-on-phase-positive-result-2026-04-24.md`
- Historical build/status summary:
  `docs/planning-history/phases/16-multivar-optimizer/16-01-SUMMARY.md`
