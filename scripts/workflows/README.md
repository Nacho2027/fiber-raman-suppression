# Workflow Implementations

Implementation files for maintained workflows live here.

Prefer invoking commands through `scripts/canonical/`; canonical scripts are
the public-facing wrappers.

## Role

Use this directory for maintained orchestration that is:

- part of the supported workflow surface
- too large to leave in a thin wrapper
- still more workflow-specific than package infrastructure

Typical examples:

- sweep report generation
- presentation-figure generation
- result comparison workflows
- optional second-stage refinement workflows
- standard-image regeneration

## Boundary

- shared reusable helpers belong in `../lib/`
- stable package abstractions belong in `../../src/`
- exploratory or study-local workflows belong in `../research/`

Prefer explicit `../lib` includes over hidden sideways dependencies on sibling
workflow files.
