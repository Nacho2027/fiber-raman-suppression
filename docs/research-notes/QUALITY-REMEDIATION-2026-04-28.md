# Research Note Quality Remediation

Evidence snapshot: 2026-04-28

## Retraction Of Prior Readiness Language

The prior documentation status overstated the quality of the research-note
series. The earlier checks verified compilation, PDF existence, rough contact
sheet rendering, citation reachability, and a small number of targeted equation
checks. Those checks are not sufficient to call the notes presentation-ready or
publication-ready.

The notes must be treated as **drafts under remediation** until each one passes
a true page-level audit.

## What Was Not Adequately Verified

- Whether every math section contains a complete derivation at an undergraduate
  explainability level.
- Whether methods sections contain enough detail to reproduce the exact result.
- Whether findings are complete, correctly scoped, and tied to artifacts.
- Whether every important figure is readable at page scale, not only visible in
  a low-resolution contact sheet.
- Whether plot labels, legends, insets, captions, and tables overlap or are
  malformed.
- Whether the figure choices have enough taste: strong control examples,
  paired phase diagnostic plus heat map, and no weak 500 mm hero examples.
- Whether every note can stand alone for presentation prep without agent-history
  context.

## New Quality Gate

A note cannot be marked ready until it passes all of the following:

1. Compile twice from source with no hard LaTeX errors, undefined references, or
   overfull boxes.
2. Render every page at readable resolution and inspect each page individually,
   not only as a contact sheet.
3. Record page-by-page defects in a QA table and fix them before promotion.
4. Confirm every major result has a control, optimized figure, phase diagnostic,
   heat map/evolution plot, and limitation statement where applicable.
5. Confirm math derivations include the actual scalar objective, variables,
   chain rules, regularizers, and optimizer surface used by the code path.
6. Confirm methods include enough command/config/artifact detail to reproduce
   the result or explicitly label the gap.
7. Confirm figure captions explain what the reader should learn from the image.
8. Confirm the note has a presentation capsule with what to say, what not to
   overclaim, and the best figure choices.

## Immediate Remediation Order

1. Audit and fix `02-reduced-basis-continuation` because it is central and the
   standard for future notes.
2. Audit and fix `06-long-fiber`, `08-multimode-baselines`, and
   `09-multi-parameter-optimization` because they contain recent result-heavy
   claims.
3. Audit and fix `01-baseline-raman-suppression` because it anchors the whole
   presentation story.
4. Audit methods-heavy notes `03`, `04`, `05`, `10`, and `11`.
5. Keep `12-long-fiber-reoptimization` provisional until its artifacts are
   freshly rerun or fully pinned.

## Current Status

No note should be described as final, perfect, paper-grade, or fully verified.
Use these PDFs as draft material only until the page-level remediation pass is
complete.
