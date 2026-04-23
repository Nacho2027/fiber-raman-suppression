# Repo Navigation Guide

This document answers four recurring maintenance questions:

1. Where should I start reading?
2. Which layer is authoritative for a given kind of change?
3. Where should new code live?
4. Which areas are stable infrastructure versus intentionally local research?

It is a navigation map, not a full architecture spec.

## First Orientation

If you are new to the repo, read in this order:

1. [`../../README.md`](../../README.md) for the project overview and maintained workflow surface.
2. [`../../scripts/README.md`](../../scripts/README.md) for the script-layer directory map.
3. [`output-format.md`](./output-format.md) if you will read or write run artifacts.
4. [`../../agent-docs/current-agent-context/INDEX.md`](../../agent-docs/current-agent-context/INDEX.md) before deep numerics, methodology, or infrastructure work.

## Boundary Map

### `src/`

This is the package layer. Put code here when it is stable, reusable, and not
specific to one script family.

Examples:

- forward / adjoint simulation kernels
- reusable optimization primitives
- canonical result payload and manifest I/O in `src/io/results.jl`

Do not put experiment orchestration here just because it is large.

### `scripts/lib/`

This is the shared script-library layer.

Use it for code that is reused across maintained scripts but is still too
workflow-shaped or include-oriented to promote into `src/` cleanly.

Examples:

- single-mode setup construction in `scripts/lib/common.jl`
- canonical Raman optimization orchestration in `scripts/lib/raman_optimization.jl`
- plotting helpers in `scripts/lib/visualization.jl`

Rule of thumb:

- If the code is shared by multiple scripts and still reads like workflow glue,
  `scripts/lib/` is usually right.
- If the code is a stable reusable abstraction with little script-local
  behavior, prefer `src/`.

### `scripts/canonical/`

This is the supported CLI surface.

Files here should be thin wrappers that point to maintained workflows. New
users, docs, and the `Makefile` should mostly refer to this layer.

Examples:

- `optimize_raman.jl`
- `run_sweep.jl`
- `generate_reports.jl`

Avoid placing heavy implementation logic here.

### `scripts/workflows/`

This layer contains maintained workflow implementations behind canonical entry
points.

Use it when the logic is:

- part of the supported workflow surface
- larger than a wrapper
- still orchestration-heavy rather than package-grade infrastructure

Examples:

- sweep report generation
- cross-run comparison workflows
- standard-image regeneration workflows

### `scripts/research/`

This layer is for active but not-yet-canonical research work.

These scripts should remain readable as experiment definitions and study-local
orchestration. Do not force them into a generic framework unless the same
pattern is clearly reused and maintained.

Typical contents:

- continuation or trust-region studies
- multimode or long-fiber investigations
- methodology audits
- study-local analysis pipelines

### `scripts/archive/`

Historical or reproducibility-oriented material that should not compete with the
maintained surfaces.

If a future maintainer asks whether to extend an archived file, the default
answer should usually be no.

## Authoritative Paths

These are the current maintained authorities for common changes.

### Single-mode problem setup

- Authoritative shared setup path: `scripts/lib/common.jl`
- Exact-grid reconstruction path: `setup_raman_problem_exact(...)` in the same file

If you need to rebuild a saved single-mode problem, do not reimplement the
fiber/sim/grid assembly locally.

### Canonical single-mode optimization entrypoint

- Shared maintained implementation: `scripts/lib/raman_optimization.jl`
- Public CLI wrapper: `scripts/canonical/optimize_raman.jl`

### Canonical results and manifest I/O

- Authoritative maintained layer: `src/io/results.jl`

If you need to change canonical run serialization, loading, or manifest update
behavior, start there.

### Standard-image generation

- Shared image helper: `scripts/lib/standard_images.jl`
- Canonical regeneration workflow: `scripts/workflows/regenerate_standard_images.jl`

Any workflow that produces a `phi_opt` should call the shared standard-image
helper rather than open-coding its own image set.

## Include Discipline

Relative includes are allowed here, but they should be disciplined.

Preferred pattern:

- canonical and workflow scripts explicitly include shared code from `../lib`
- research scripts explicitly include local siblings only when the boundary is
  truly study-local
- avoid hidden function-local includes
- avoid order-sensitive rebinding patterns across included files

Warning signs:

- a script only works because another included script happens to define names
  as a side effect
- same-directory includes obscure whether a dependency is shared infrastructure
  or research-local glue
- a script needs to be included in a particular order to keep `main()` or
  global constants from colliding

## Where New Code Should Go

### Add a new fiber, cost term, optimizer primitive, payload helper, or reusable utility

Start by asking whether the behavior is stable and reusable across workflows.

- If yes, prefer `src/`
- If not yet, but shared by multiple maintained scripts, use `scripts/lib/`

### Add a supported end-user workflow

- put the implementation in `scripts/workflows/`
- add a thin wrapper in `scripts/canonical/`
- point docs and `Makefile` at the wrapper

### Add a one-off or still-moving experiment

- put it in the appropriate `scripts/research/<area>/`
- keep it readable as an experiment definition
- only extract shared helpers if repeated active use justifies it

### Retire or preserve historical material

- move it to `scripts/archive/`
- keep only enough documentation to explain why it is archived

## Intentionally Local Areas

These areas are allowed to remain more study-local than the canonical path:

- long-fiber setup and regeneration adapters
- MMF-specific setup/orchestration
- phase-specific research manifests when they encode study-local provenance

Do not normalize these automatically just because they look different.

## Current Navigation Risks

The repo is clearer than before, but these areas still need extra care:

- some maintained research analysis and propagation scripts still use
  same-directory include chains
- `scripts/lib/` remains a transition layer, so some boundaries are still more
  conventional than enforced
- research-local manifest formats are intentionally heterogeneous

When in doubt, prefer editing the canonical authority listed above or document
why a local exception is justified.
