# Multi-Parameter Optimization Status

This note captures the durable, agent-relevant status of the codebase's
multi-parameter optimization path.

## Current status

Multi-parameter optimization exists, but it is still an experimental research
path rather than a converged production workflow.

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

## What remains unresolved

The main unresolved issue is optimizer behavior in the joint search space, not
missing infrastructure.

At the canonical demo point (`SMF-28`, `L = 2 m`, `P = 0.30 W`), the recorded
results were approximately:

- phase-only: `ΔJ ≈ -55 dB`
- multivar cold start: `ΔJ ≈ -17 dB`
- multivar warm start: `ΔJ ≈ -24 dB`

Interpretation: the joint path runs, but it has not yet matched or exceeded the
canonical phase-only baseline at the reference configuration.

## Practical rule for future agents

Treat the multivar path as:

- a valid research scaffold
- a usable objective/gradient implementation for further optimizer work
- a source of prior artifacts worth validating against

Do **not** treat it as:

- the repository's canonical optimization workflow
- a proven improvement over phase-only shaping
- a finished general framework for adding arbitrary optimization variables

## Highest-value next steps

The open follow-up work is consistently:

1. amplitude-only warm start
2. two-stage optimization with phase frozen first, then unfrozen
3. better cross-block preconditioning or diagonal Hessian scaling
4. extending later trust-region / second-order ideas to the joint problem

## Artifact caveat

`scripts/research/multivar/multivar_demo.jl` now calls `save_standard_set(...)`,
but the current synced workspace snapshot only shows the multivar JLD2 payloads
under `results/raman/multivar/smf28_L2m_P030W/`.

If expected PNGs are missing, treat that as an artifact-sync or retention issue,
not as evidence that the code never supported standard image generation.

## Pointers

- Historical build/status summary:
  `docs/planning-history/phases/16-multivar-optimizer/16-01-SUMMARY.md`
- Open convergence follow-up:
  `docs/planning-history/phases/18-multivar-convergence-fix/CONTEXT.md`
