# Repo Diet

Temporary cleanup note for the May 4, 2026 agent-first refactor. Remove or
collapse this file when the cleanup is complete.

## Goal

Make the active repository Julia-first, small enough for agents to navigate,
and clear about supported entry points.

## Non-Negotiables

- Recovery exists before deletion:
  `/Users/ignaciojlizama/RiveraLab/fiber-raman-recovery-20260504-1254`.
- Do not delete important raw results without inventorying or vaulting them.
- Python is not a supported API surface unless the user explicitly requests it.
- Preserve Julia core code, checked configs, canonical CLI entry points, and
  tests for supported behavior.
- Prefer deleting, moving, or condensing stale docs/scripts/artifacts over
  preserving active-context clutter.

## Current Spine

- CLI: `./fiberlab` and maintained Julia entry points.
- Core: `src/`.
- Orchestration: `scripts/lib/`.
- Thin wrappers: `scripts/canonical/`.
- Configs: `configs/experiments/` for supported experiments.
- Results: generated evidence, not source.

## Checkpoints

- Created external recovery bundle and `recovery/pre-repo-diet-20260504`.
- Rewrote `AGENTS.md` as a Julia-first short operating contract.
- Moved raw `results/`, old `notebooks/`, historical planning, bulky docs,
  old agent topics, Python package/tests, and old research scripts/tests to the
  external archive.
- Replaced the Python `fiberlab` launcher with a Bash router to Julia commands.
- Promoted `scripts/lib/numerical_trust.jl` because maintained optimization
  code depends on it.
- Verified `make docs-check`, `./fiberlab configs`, `./fiberlab plan
  research_engine_poc`, and `make test`.
