# Lab-Readiness Transition Plan

## Goal

Implement the first narrow lab-facing productization pass around the proposal:

- make the canonical single-run wrapper truthful
- add an approved config/spec layer for single runs and sweeps
- add saved-run inspect/export workflows
- update docs to describe the supported surface honestly
- add fast-tier regression coverage for that user-facing surface

## Approach

1. Audit the current maintained interface, research-state docs, and active
   agent context.
2. Separate stable surfaces from research-only surfaces.
3. Fix the canonical wrapper mismatch by moving the public path onto a real
   approved run config.
4. Add inspection/export helpers around the existing saved bundle.
5. Update docs and tests so the supported surface is discoverable and guarded.

## Intended output files

- approved configs under `configs/`
- new canonical/workflow entry points for optimize/inspect/export
- updated docs in `README.md`, `docs/README.md`, and guide docs
- fast-tier regression coverage in `test/`
- updated `agent-docs/lab-readiness-transition/{CONTEXT,PLAN,SUMMARY}.md`

## Implementation scope rule

This pass is planning-first. Avoid broad code changes unless a very small
wrapper or docs/link fix is clearly safe and materially improves trust.
