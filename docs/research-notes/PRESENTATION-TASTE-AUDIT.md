# Presentation Taste Audit

Evidence snapshot: 2026-04-27

This file records the current presentation-quality concern: several notes are
technically useful but not always pedagogically tasteful. The goal is to make
the eventual presentation understandable to an undergraduate presenter and a
mixed lab audience, not just complete for future agents.

## Direct Answer

No, the current PDFs are not yet sufficient by themselves for an undergraduate
who barely understands the whole project to present everything comfortably.
They are strong reference documents, but a presentation needs a tighter
narrative, fewer examples, better figure selection, and explicit speaker notes.

The notes are moving in the right direction, but they still need a
presentation-first pass:

- choose the most visually persuasive examples;
- downgrade technically useful but visually weak examples;
- add one-minute explanations for each main idea;
- add "what to say out loud" bullets;
- add "what not to overclaim" warnings;
- avoid showing a run just because it is historically important.

## The 500 mm Problem

The short 500 mm / 0.5 m runs are often useful for numerics, recovery, or
robustness studies because they are cheaper and can reach extremely low Raman
fractions. But they are often bad presentation examples for the basic
before/after story because there may not be much visible Raman growth in the
unoptimized control. If the control barely has Raman transfer, the visual
before/after does not teach the audience why the optimization matters.

Presentation rule:

- Use 500 mm cases for methods, diagnostics, recovery, and robustness only when
  the note explicitly says why that operating point was chosen.
- Do not use 500 mm cases as the main "look, Raman was suppressed" slide unless
  the unoptimized control visibly shows the problem.
- For the main physical motivation, prefer a case with visible unoptimized
  Raman transfer and a clear optimized/control contrast.

## Better Figure Taste Rules

A slide-ready example should satisfy most of these:

- The control image visibly shows the problem.
- The optimized image visibly changes the propagation, not only the final dB
  number.
- The phase diagnostic is paired with the corresponding heat map.
- The caption explains the claim in one sentence.
- The axes and labels are readable from a slide.
- The figure supports one idea, not five.
- The example is not chosen only because it has the deepest dB value.
- The note says whether the result is established, provisional, or only a
  diagnostic case.

## Recommended Slide-First Examples

Use these before reaching for short-fiber diagnostic cases:

| Story | Preferred example | Why |
|---|---|---|
| Basic Raman suppression | `01` canonical 2 m SMF-28 control vs optimized pair | Clearer physical before/after than 500 mm weak-Raman cases. |
| Reduced-basis idea | `02` basis diagram plus cubic reduced diagnostic/evolution pair | Teaches the linear-algebra idea and shows a real result. |
| Simple vs deep vs transferable | `07` depth-transfer tradeoff plus simple/deep paired pages | Best conceptual story for a lab audience. |
| Robustness | `03` robustness-depth tradeoff, not a 500 mm before/after page | The point is the tradeoff, not dramatic Raman growth. |
| Trust/numerics | `05` objective pipeline and trust checklist | This is a methods slide, not a physics-result slide. |
| Saddle/recovery | `10` recovery workflow and saddle spectrum | The point is validation and landscape geometry. |
| Long-fiber warm starts | `12` 100 m no-shaping control and optimized pair | Visually stronger for explaining long-fiber relevance. |
| AI usage | AI-assisted workflow note diagrams | Use as a separate methods/reflection section. |

## Examples To Downgrade

These are not bad results, but they should not be first-choice presentation
figures:

- 500 mm short-fiber optimized runs as the main before/after Raman story.
- Any result table with more than about five rows on a slide.
- Any phase diagnostic shown without its corresponding heat map.
- Any stale placeholder figure from before the MMF and multivariable quality
  passes; use the accepted MMF trust-gate ladder and the polished multivariable
  two-stage amplitude-refinement figures instead.
- Any figure whose lesson requires a long explanation of internal history.
- Any "deepest ever" result if it is fragile, non-converged, or missing
  provenance.

## Required Pedagogy Pass

Each polished note should eventually add a short `Presentation Capsule` section:

- `Slide takeaway`: one sentence.
- `Best figure`: exact figure filename(s).
- `What to say`: three simple bullets.
- `What not to overclaim`: one warning.
- `If asked`: one short answer to the likely audience question.

The current `PRESENTATION-BUILDING-BLOCKS.md` is a start, but those capsules
should be copied into the PDFs themselves during the next polish pass.

## Undergrad Presenter Rule

A note is not presentation-ready until the presenter can answer these questions
without rereading code:

- What is the problem?
- What did we change?
- What did the control do?
- What did the optimized result do?
- What does the figure show?
- Why should anyone believe it?
- What is the limitation?

If any of those answers requires agent-history context, the note needs more
pedagogy.
