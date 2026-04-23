# Archived Scripts

This directory is reserved for historical, phase-specific, or one-off scripts
that remain worth keeping for reproducibility, but should no longer compete with
the canonical or active research surfaces.

Current state:

- `phaseXX/` subdirectories hold organized copies of historical phase families.
- The top-level `scripts/phase*.jl` files remain the executable paths for now.
- This is intentional: many older phase scripts are tightly coupled to sibling
  files via `@__DIR__` and include-based composition, so moving the live entry
  points would be a behavior change.

Scripts moved here should have at least one of these properties:

- tied to a completed project phase
- superseded by a newer workflow
- useful mainly as a reproduction artifact
- benchmark or recovery glue with little day-to-day maintenance value

The goal is archival, not erasure. Delete only after a script is clearly dead,
duplicated, or its scientific value has been captured elsewhere.
