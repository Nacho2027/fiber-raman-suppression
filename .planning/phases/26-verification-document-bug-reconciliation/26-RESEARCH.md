# Phase 26 Research

**Phase:** 26 — Verification document bug reconciliation
**Date:** 2026-04-20
**Mode:** implementation

## Standard Stack

- Use local code search as the primary source of truth.
- Patch only `docs/verification_document.tex` plus minimal planning metadata.
- Verify by comparing the updated prose against current code paths and canonical Phase 21/23/25 findings.

## Architecture Patterns

- If a bug claim is still real in code, keep it as an open issue and seed it.
- If a bug claim is obsolete or misstated, fix the document rather than leaving historical drift in place.
- Distinguish single-mode phase-only behavior from amplitude or multivariable optimizer behavior; do not collapse those paths into one description.

## Don't Hand-Roll

- Do not claim `Issue 2` is fixed without changing the adjoint implementation.
- Do not claim TOD is a phase-only penalty term when it is only used diagnostically.
- Do not rewrite scientific findings that are already aligned with Phase 21/23 unless grep shows an overclaim still present.

## Common Pitfalls

- The verification document mixes historical bug history with current-state claims.
- A statement can be true for the single-mode phase-only path and false for the amplitude or multivariable paths.
- Historical numbers like `-54.77 dB` and `-71.4 dB` need status qualifiers, not blanket deletion.
