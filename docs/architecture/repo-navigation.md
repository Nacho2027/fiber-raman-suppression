# Repo Navigation

Read this before moving code.

## Canonical Surfaces

| Path | Purpose |
|---|---|
| `src/fiberlab/` | Notebook-facing FiberLab API and product vocabulary |
| `src/simulation/`, `src/gain_simulation/`, `src/mmf_cost.jl` | Low-level physics backend |
| `configs/experiments/` | Serialized experiments for reproducible runs |
| `lab_extensions/` | Experimental controls and objectives |
| `scripts/canonical/` | Maintained compatibility entry points |
| `scripts/lib/` | Transitional runner/orchestration internals |
| `./fiberlab` | Bash router to maintained Julia commands |
| `test/` | Regression tests for supported behavior |
| `docs/` | Human-facing docs |
| `agent-docs/` | Minimal active agent context |

## Non-Canonical Areas

| Path | Rule |
|---|---|
| `results/` | Generated evidence; use manifests or targeted paths |
| `.venv/`, `.claude/`, `.burst-sync/`, `.pytest_cache/` | Ignored local tooling; not repo structure |
| external cleanup vault | Historical source/results; inspect only for archaeology |

Python is not a supported API surface.

## Where To Edit

- Notebook-facing experiment concepts: `src/fiberlab/`.
- Physics or reusable numerics: the backend files under `src/`.
- Supported command behavior: prefer FiberLab API in `src/fiberlab/`; use
  `scripts/lib/` only for transitional orchestration; keep wrappers in
  `scripts/canonical/` thin.
- Experiment settings: `configs/experiments/`.
- Experimental objectives and controls: `lab_extensions/`.
- Research verdicts: [Research Verdicts](../research-verdicts.md).
- User-facing behavior changes: the relevant file under `docs/`.

Do not promote notebook code by linking to it. Move reusable logic into Julia
first.

## What Not To Add

- New long-lived phase scripts.
- New Python API code.
- New docs that duplicate an existing doc instead of replacing it.
- Generated results or cached fiber/data files in active source paths.
- New script-first APIs when a FiberLab object or extension contract would
  express the idea.
