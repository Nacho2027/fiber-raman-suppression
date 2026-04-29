# Presentation Readiness QA

Checklist before turning research notes into slides. A note is
presentation-ready only if the PDF compiles, the rendered pages were inspected,
the main claim is stated with its caveat, and the note contains enough math,
method, figures, and reproduction detail to build slides without digging through
chat history.

## 2026-04-29 Series Gate

Status: usable for presentation building, with caveats explicitly preserved.

Checks completed:

- Recompiled all 12 note PDFs with `pdflatex`.
- Rendered all PDFs to PNG pages under `/tmp/research-note-final-audit`.
- Built contact sheets for all 162 rendered pages and visually inspected the
  full series for malformed figures, overlapping tables, and missing
  control/optimized visual comparisons.
- Scanned public note sources for stale internal labels, unfinished-marker
  language, failed high-grid language, and weak short-fiber hero framing.
- Scanned LaTeX logs for hard errors, overfull boxes, undefined references, and
  undefined citations.

No PDF-level blockers were found in the final gate.

## Note Status

| Note | Presentation role | Status | Main caveat to say out loud |
|---|---|---|---|
| `01-baseline-raman-suppression` | Opens the physics story and baseline before/after result. | Ready | Single-mode, phase-only, one canonical operating point. |
| `02-reduced-basis-continuation` | Best board-explanation note for basis ideas and continuation. | Ready | Reduced basis helps optimization, but is not automatically transferable. |
| `03-sharpness-robustness` | Explains why deepest suppression is not always best. | Ready | Robustness metrics are simulations around selected phase candidates. |
| `04-trust-region-newton` | Explains second-order methods and saddle diagnostics. | Ready | This is mostly a methods/diagnostics lane, not the headline physics result. |
| `05-cost-numerics-trust` | Explains objective consistency, numerics, and trust gates. | Ready | The point is audit discipline, not a new suppression record. |
| `06-long-fiber` | Shows long-fiber scaling and why the problem changes. | Ready with caveat | Long-fiber runs are checkpointed/constrained and not universal convergence claims. |
| `07-simple-profiles-transferability` | Shows simple profiles, universality limits, and transfer tradeoffs. | Ready | Simple profiles are interpretable but not always deepest. |
| `08-multimode-baselines` | Shows MMF result with accepted/rejected trust gate. | Ready with caveat | Accepted result is an idealized six-mode simulation, not generic MMF experiment proof. |
| `09-multi-parameter-optimization` | Shows staged multivariable success and broad joint-search failure. | Ready | The positive result is staged amplitude refinement, not arbitrary joint optimization. |
| `10-recovery-validation` | Explains recovery, checked grids, and retired claims. | Ready | Recovery validates or retires candidates; it is not itself a new optimizer. |
| `11-performance-appendix` | Supports compute strategy and why adjoints matter. | Ready as appendix | Use only if asked about runtime/engineering; do not make it a main physics section. |
| `12-long-fiber-reoptimization` | Short strategy note for warm-start reoptimization. | Ready as provisional lane | Useful strategy evidence, not a final performance benchmark. |

## Slide-Building Rule

For each topic, use one claim slide, one method/math slide, one visual result
slide, and one caveat slide. Do not show a figure unless the note gives you the
sentence that explains why the figure matters.
