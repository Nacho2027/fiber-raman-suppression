# Configurable Front-Layer Plan

## Goal

Produce a maintainer-grade proposal for a configurable scientific front layer
that makes common variable/objective/regime swaps possible without deep code
surgery.

## Approach

1. Audit the current canonical config surface and the regime-specific setup
   paths.
2. Identify the minimum contracts needed above the existing physics kernels.
3. Write a human-facing architecture proposal under `docs/architecture/`.
4. Add one thin TOML schema sketch showing the recommended config shape.
5. Record the repo-specific reasoning in agent notes.

## Scope rule

This pass is intentionally thin:

- no broad implementation refactor
- no hidden framework build-out
- no attempt to stabilize unfinished research lanes beyond honest front-layer
  boundaries

## Output files

- `docs/architecture/configurable-front-layer.md`
- `configs/experiments/research_engine_poc.toml`
- `agent-docs/configurable-front-layer/{CONTEXT,PLAN,SUMMARY}.md`
