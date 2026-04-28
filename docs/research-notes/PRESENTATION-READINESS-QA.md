# Presentation Readiness QA

Evidence snapshot: 2026-04-28

This is the practical presentation gate for the research-note series. A note is
presentation-ready only if an undergrad researcher can use the PDF to explain
the motivation, math, algorithm, result, figures, limitations, and reproduction
path without digging through planning logs.

## Readiness Retraction

The status matrix below is no longer authoritative. The previous checks were
too shallow: they covered compilation, PDF existence, rough contact sheets, and
some citation/equation checks, but not full page-level quality, math depth,
methods completeness, or figure readability. Treat every note as **draft under
remediation** until it passes the stricter gate in
[`QUALITY-REMEDIATION-2026-04-28.md`](QUALITY-REMEDIATION-2026-04-28.md).

## Status Matrix

| Note | Presentation status | Best use in deck | Current caveat |
|---|---|---|---|
| `01-baseline-raman-suppression` | ready | Main physical before/after and project vocabulary | Not a global-optimality claim. |
| `02-reduced-basis-continuation` | ready | Basis linear algebra, basin access, continuation | Deepest profiles remain fiber-specific and narrow. |
| `03-sharpness-robustness` | ready | Robustness-depth tradeoff | Use tradeoff charts, not weak short-fiber before/after images. |
| `04-trust-region-newton` | ready as methods/result context | Saddle geometry and why naive Newton is brittle | Not a new winning optimizer. |
| `05-cost-numerics-trust` | ready as methods backbone | Objective, gauge, diagnostics, trust gates | Some heavyweight audit cells remain incomplete. |
| `06-long-fiber` | ready with caveat | 100--200 m single-mode long-fiber milestones | Achieved deep values, not converged optima. |
| `07-simple-profiles-transferability` | ready | Simple vs deep vs transferable distinction | Do not call the simple profile universally best. |
| `08-multimode-baselines` | ready with caveat | Qualified GRIN-50 MMF simulation and trust-gate story | Not a generic experimental MMF claim; grid refinement remains compute-gated. |
| `09-multi-parameter-optimization` | ready with caveat | Staged amplitude refinement and negative broad-joint result | Not lab-default until amplitude calibration/convergence close. |
| `10-recovery-validation` | ready | Honest-grid recovery and retired-claim discipline | Publication claims still need exact saved-artifact provenance. |
| `11-performance-appendix` | ready as support section | How the research was run efficiently and reproducibly | Benchmark numbers are hardware/configuration-specific. |
| `12-long-fiber-reoptimization` | ready as provisional strategy | Warm-start/reoptimization strategy for long fibers | Not a converged global $100$ m optimum. |

## Main Slide Backbone

Use these notes, in this order, for a coherent presentation:

1. `01` for the physical problem, cost, baseline optimizer, and standard images.
2. `02` for reduced-basis basin access and the linear algebra of `phi = Bc`.
3. `07` for simple profiles and the taste distinction between explainable,
   transferable, robust, and deepest.
4. `03` for robustness-depth tradeoffs.
5. `10` for recovery and honest validation.
6. `09` for multivariable staged refinement.
7. `06` for completed long-fiber 100--200 m milestones.
8. `12` for long-fiber warm-start strategy.
9. `08` for qualified MMF simulation results.
10. `11` for compute and AI-enabled research operations as support.
11. `05` either before results as a trust contract or near the end as the
   verification backbone.

## Taste Rules

- Do not lead the physics story with 500 mm cases unless the unoptimized control
  visibly shows Raman growth.
- Do not show a phase diagnostic without the corresponding propagation heat map
  unless the note is explicitly a methods/compute appendix.
- Do not present a deepest-number result without its limitation sentence.
- Present `06` and `08` with their caveat sentence on the same slide as the
  result: long-fiber is not converged, and MMF is not a generic lab claim.
- Prefer a smaller number of strong figures over exhaustive run tables.

## QA Actions Completed

- Added `Presentation Capsule` sections to the polished presentation-relevant
  notes that were missing them.
- Promoted `09` to a polished staged-refinement note with real figures,
  compiled PDF, rendered-page inspection, and passing multivariable smoke tests.
- Added the multivariable result to the presentation building-block map.
- Promoted `06` and `08` after replacing scaffold/placeholder content with
  real figures, math, caveats, and reproduction capsules.
- Ran a full-series PDF audit on 2026-04-28: all twelve numbered PDFs exist,
  rendered to contact sheets, and passed visual inspection for broken pages,
  missing figure blocks, and obvious table overflow.
- Scanned extracted PDF text for stale placeholders, internal milestone labels,
  and private workflow language. The numbered PDFs passed this scan.
- Checked LaTeX logs for the numbered notes. No hard errors, undefined
  references, or overfull boxes were found; only minor underfull line-breaking
  messages remain in `06` and `08`.

## Remaining Work

- Revisit `06-long-fiber` only if a converged long-fiber optimum or cleaner
  lab-ready phase profile appears.
- Revisit `08-multimode-baselines` after the MMF grid-refinement, launch
  sensitivity, and random-coupling gates close.
- Do a final saved-artifact provenance pass before using the notes for a paper
  or formal lab handout.
- Keep `12-long-fiber-reoptimization` provisional until a fresh rerun confirms
  the warm-start/reoptimization artifacts and the compiled PDF is visually
  checked again.

The current full-series audit record is
[`SERIES-PRESENTATION-AUDIT-2026-04-28.md`](SERIES-PRESENTATION-AUDIT-2026-04-28.md).
