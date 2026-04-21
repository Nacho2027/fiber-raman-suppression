# Context

## Goal

Migrate the repo off the GSD planning workflow and onto a stock `docs/`-based workflow for Claude and Codex.

## Why this change

- The active workflow instructions still depended on `.planning/` and GSD-specific enforcement.
- Historical planning material was valuable context, but it should live as archived documentation rather than active workflow state.
- Future work needs a simpler convention: document in `docs/`, research before coding, and test before calling work complete.

## Historical context skimmed before migration

- Phase 28 introduced a canonical trust-report path for optimizer numerics and validation.
- Phase 29 built performance-modeling and roofline benchmarking infrastructure for FFT, adjoint, and end-to-end solve paths.
- Phase 35 concluded that the strongest Raman-suppression branch is saddle-dominated and recommended reduced-basis continuation plus globalized second-order methods.
