# Research Notes

This directory holds the outward-facing mini LaTeX research-note series for
the Raman-suppression project. The goal is not one giant report. Each note is a
small companion document for one research direction, with enough math,
implementation detail, results, figures, and limitations to support lab
discussion and future paper writing.

Shared LaTeX files live in `_shared/`. Per-note source, compiled PDF, local
figures, and sidecar tables live in each numbered note directory.

## Recommended Reading Order

1. `01-baseline-raman-suppression` — start here for the physical objective,
   adjoint/L-BFGS baseline, trust gates, and standard image vocabulary.
2. `02-reduced-basis-continuation` — explains the main basin-access result and
   the linear algebra of `phi = Bc`.
3. `03-sharpness-robustness` — separates suppression depth from robustness and
   explains why sharpness penalties are useful knobs, not a new default.
4. `04-trust-region-newton` — explains the second-order/trust-region attempts
   and why saddle geometry matters.
5. `09-multi-parameter-optimization` — explains the negative broad-joint result
   and the positive amplitude-on-fixed-phase refinement lane.
6. `05-cost-numerics-trust` — methods backbone for cost conventions, gauge
   projection, numerical trust checks, and standard-image requirements.
7. `11-performance-appendix` — explains adjoint cost, threading evidence, and
   compute strategy for running the research program efficiently.
8. `06-long-fiber` — explains completed 100--200 m single-mode long-fiber
   milestones and why they are achieved values, not converged optima.
9. `12-long-fiber-reoptimization` — explains the warm-start strategy where a
   short-fiber mask is transferred and re-optimized on a long-fiber target.
10. `07-simple-profiles-transferability` — explains simple masks,
   transferability, and the tradeoff between clean profiles and deep native
   suppression.
11. `08-multimode-baselines` — explains the qualified GRIN-50 MMF simulation
   result and the boundary-diagnostic correction.
12. `10-recovery-validation` — explains honest-grid recovery, retired claims,
   and saddle/negative-curvature follow-up.

## Quality Status Warning

The earlier readiness language for this series was too broad. These PDFs should
be treated as drafts under remediation until they pass a true page-level audit
for math completeness, methods completeness, figure readability, result
provenance, and presentation usefulness.

See
[`QUALITY-REMEDIATION-2026-04-28.md`](QUALITY-REMEDIATION-2026-04-28.md).

## Draft Notes With Existing PDFs

These notes have compiled PDFs and local figure bundles. That is not the same
as being fully presentation-ready or publication-ready.

| Note | Status | PDF |
|---|---|---|
| Baseline Raman Suppression and Core Optimization Surface | established reference workflow | [`01-baseline-raman-suppression.pdf`](01-baseline-raman-suppression/01-baseline-raman-suppression.pdf) |
| Reduced-Basis Continuation for Raman Suppression | established core claim; open portability questions | [`02-reduced-basis-continuation.pdf`](02-reduced-basis-continuation/02-reduced-basis-continuation.pdf) |
| Sharpness, Robustness Penalties, and Hessian Geometry | established tradeoff; not a default replacement | [`03-sharpness-robustness.pdf`](03-sharpness-robustness/03-sharpness-robustness.pdf) |
| Trust-Region Newton Methods in a Saddle-Dominated Raman Landscape | compiled outward-facing note | [`04-trust-region-newton.pdf`](04-trust-region-newton/04-trust-region-newton.pdf) |
| Cost Audit, Numerics Coherence, and Trust Diagnostics | production-ready methodology note; audit matrix incomplete | [`05-cost-numerics-trust.pdf`](05-cost-numerics-trust/05-cost-numerics-trust.pdf) |
| Long-Fiber Single-Mode Raman Suppression | completed 100--200 m milestone; not converged optima | [`06-long-fiber.pdf`](06-long-fiber/06-long-fiber.pdf) |
| Simple Profiles, Universality, and Transferability | compiled outward-facing note | [`07-simple-profiles-transferability.pdf`](07-simple-profiles-transferability/07-simple-profiles-transferability.pdf) |
| Multimode Raman Baselines and Cost Choice | qualified idealized GRIN-50 simulation result | [`08-multimode-baselines.pdf`](08-multimode-baselines/08-multimode-baselines.pdf) |
| Multi-Parameter Optimization Beyond Phase-Only Shaping | established simulated refinement result; not a lab-default workflow | [`09-multi-parameter-optimization.pdf`](09-multi-parameter-optimization/09-multi-parameter-optimization.pdf) |
| Recovery, Honest Grids, and Saddle Diagnostics | established with scoped limits | [`10-recovery-validation.pdf`](10-recovery-validation/10-recovery-validation.pdf) |
| Performance Model and Compute Strategy | established for canonical single-mode compute planning | [`11-performance-appendix.pdf`](11-performance-appendix/11-performance-appendix.pdf) |

## Provisional Or Waiting Notes

These PDFs may compile, but they should not be treated as final outward-facing
handouts until their research lanes stabilize or they receive the same quality
pass as the notes above.

| Note | Current status | Why not final yet |
|---|---|---|
| `12-long-fiber-reoptimization` | provisional strategy note | Warm-start/reoptimization evidence is real through 200 m, but should be reframed as a milestone rather than a converged optimum. |

## Closure Classification

Use this table when deciding whether to improve notes or reopen science:

| Direction | Classification | Action |
|---|---|---|
| Single-mode phase | established | Polish and keep as baseline |
| Multi-parameter `amp_on_phase` | positive experimental result | Summarize; do not start a broader campaign during packaging |
| Direct joint multivariable | negative | Archive as cautionary result |
| Long-fiber 200 m | completed milestone | Summarize with non-convergence caveat |
| MMF | qualified but incomplete | Keep caveats; high-grid and launch sensitivity remain open |
| Newton/preconditioning | deferred | Keep note as methods/negative lesson, not production path |

## Quality Checklist

Before calling a note production-ready:

- Compile the note to PDF in its own directory.
- Render the PDF to images and visually inspect the pages.
- Include real result figures, not placeholders.
- Pair each representative phase diagnostic or phase profile with the
  corresponding evolution heat map on the same page when both exist.
- Include a no-optimization/no-shaping control page when the artifact exists.
- Explain the actual cost function and any regularizers, log transforms,
  projections, basis maps, or optimizer-coordinate changes.
- Add short `Intuition Check`, `TL;DR`, or interpretive blocks for dense math
  and method sections.
- Cite external sources for the physics, numerical method, optimizer, basis,
  continuation, or robustness method being used.
- Avoid internal milestone labels and private workflow language.
- Clean LaTeX build artifacts after verification unless a local workflow needs
  them.

See [`QUALITY-STANDARD.md`](QUALITY-STANDARD.md) for the full quality bar.
The current note-by-note verification gaps are tracked in
[`VERIFICATION-CLOSURE-MATRIX.md`](VERIFICATION-CLOSURE-MATRIX.md).
The provisional-note upgrade worksheets are tracked in
[`PROVISIONAL-UPGRADE-WORKSHEETS.md`](PROVISIONAL-UPGRADE-WORKSHEETS.md).
The code/result/figure traceability map is tracked in
[`TRACEABILITY-MAP.md`](TRACEABILITY-MAP.md).
The presentation-oriented coverage map is tracked in
[`PRESENTATION-BUILDING-BLOCKS.md`](PRESENTATION-BUILDING-BLOCKS.md).
The presentation-readiness QA gate is tracked in
[`PRESENTATION-READINESS-QA.md`](PRESENTATION-READINESS-QA.md).
The presentation taste audit is tracked in
[`PRESENTATION-TASTE-AUDIT.md`](PRESENTATION-TASTE-AUDIT.md).
The latest full-series visual/text audit is
[`SERIES-PRESENTATION-AUDIT-2026-04-28.md`](SERIES-PRESENTATION-AUDIT-2026-04-28.md).
The latest citation audit is
[`CITATION-AUDIT-2026-04-28.md`](CITATION-AUDIT-2026-04-28.md).
The latest artifact provenance ledger is
[`ARTIFACT-PROVENANCE-LEDGER-2026-04-28.md`](ARTIFACT-PROVENANCE-LEDGER-2026-04-28.md).
The latest equation/code closure record is
[`EQUATION-CODE-CLOSURE-2026-04-28.md`](EQUATION-CODE-CLOSURE-2026-04-28.md).
The current equation-level verification backbone is
[`../reference/current-equation-verification.pdf`](../reference/current-equation-verification.pdf).

## Maintenance Notes

The setup helper can refresh starter note directories and some generated
sidecar tables:

```bash
julia --project=. scripts/dev/setup_research_note_series.jl
```

Do not run that helper blindly over polished notes without checking the diff.
The polished PDFs in this directory were manually edited and visually verified.
