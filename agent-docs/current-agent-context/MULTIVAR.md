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
- Reference driver:
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
- 2026-04-26 equation audit fixed a missing amplitude derivative for the
  temporal-boundary regularizer. Any amplitude-enabled run with
  `λ_boundary > 0` that predates that fix should be regenerated before it is
  used as a final quantitative table.

## Current evidence boundary

The main issue is optimizer behavior and hardware readiness in the expanded
control space, not missing infrastructure.

At the canonical reference point (`SMF-28`, `L = 2 m`, `P = 0.30 W`), the accepted
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

A 2026-04-26 deterministic repeat reproduced those values to the displayed
precision. The amplitude profile used 8192 bins, with min `0.908455`, max
`1.090233`, mean `0.999560`, standard deviation `0.006874`, and unchanged stored
energy (`E_opt = E_ref`). Standard images for both phase-only and
amplitude-on-phase cases were visually inspected.

The 2026-04-26 amplitude-bound sweep then filled in two additional bounds:

- `δ = 0.05`: `J_after = -43.01 dB`, improvement `2.22 dB`, A range
  `[0.950, 1.050]`; useful but below the `3 dB` closure threshold
- `δ = 0.15`: `J_after = -45.94 dB`, improvement `5.15 dB`, A range
  `[0.855, 1.149]`
- `δ = 0.20`: `J_after = -46.82 dB`, improvement `6.02 dB`, A range
  `[0.805, 1.199]`

Interpretation: the amplitude-on-fixed-phase gain grows smoothly with allowed
amplitude freedom. Very small ±5% shaping is scientifically real but likely too
small to promote as a headline. ±10-20% shaping is the current useful range.

A four-point local neighborhood check around `L = 2 m`, `P = 0.30 W` then
showed that all nearby points improved, but not all crossed the `3 dB`
decision threshold:

- `L = 1.8 m`, `P = 0.30 W`: `3.17 dB` improvement
- `L = 2.2 m`, `P = 0.30 W`: `5.42 dB` improvement
- `L = 2.0 m`, `P = 0.27 W`: `2.30 dB` improvement
- `L = 2.0 m`, `P = 0.33 W`: `5.78 dB` improvement

Interpretation: broad joint phase+amplitude remains experimental/negative, but
fixed-phase amplitude refinement is now a reproducible and locally useful
candidate. Its margin is operating-point dependent, so it should be exposed as
an optional second-stage workflow rather than as a default lab optimizer. The
repo now has a neutral amplitude-aware export contract and round-trip
validation, but hardware readiness still needs a real shaper pixel grid,
calibration/transfer-function data, and lab-specific clipping or attenuation
policy.

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

1. rerun the full variable-combination ablation in
   `scripts/research/multivar/multivar_variable_ablation.jl` after the
   2026-04-26 boundary-amplitude gradient fix
2. implement a maintained two-stage workflow that exposes
   amplitude-on-phase as an optional refinement rather than a default
3. add hardware-constrained handling of relative amplitude values above unity
   once a real shaper model or measured transfer function is available
4. defer broad joint phase+amplitude tuning until a new physical or numerical
   hypothesis justifies it

Terminology note: the active `δ` jobs are amplitude-bound ablations, not the
full combinatorial multivar ablation. The full ablation should explicitly cover
single blocks and combinations of phase, amplitude, and scalar energy, including
fixed-phase staged cases.

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
- Repeatability and handoff review:
  `docs/status/multivar-amp-on-phase-repeatability-handoff-2026-04-26.md`
- Local robustness review:
  `docs/status/multivar-amp-on-phase-robustness-2026-04-26.md`
- Historical build/status summary:
  `docs/planning-history/phases/16-multivar-optimizer/16-01-SUMMARY.md`
