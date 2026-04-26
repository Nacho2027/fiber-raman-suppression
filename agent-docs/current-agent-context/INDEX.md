# Current Agent Context

This directory contains the small subset of former `.planning/` material that is still useful to future agents as active context.

## Why this exists

The old GSD workflow stored a mix of:

- historical planning artifacts
- one-off workflow glue
- durable technical findings
- operational runbooks

Only the durable technical and operational findings belong in the new system as active agent context. Everything else has been preserved under `docs/planning-history/`.

## Contents

- `METHODOLOGY.md` — durable sweep/windowing and threading findings that still affect how agents should run experiments
- `NUMERICS.md` — numerics audit findings that still matter after the April 20 fixes
- `LONGFIBER.md` — maintainer-style assessment of what the repo can currently support for 50–100 m single-mode work versus what is still experimental
- `MULTIVAR.md` — current status of the joint phase/amplitude/energy optimization path and the open convergence gap
- `PERFORMANCE.md` — static roofline/kernel conclusions from Phase 29 that still matter when reasoning about optimization runtime
- `INFRASTRUCTURE.md` — current remote compute setup and what parts of the old setup notes remain operationally useful
- `PLANNING-MIGRATION.md` — disposition of every remaining `.planning/` artifact migrated in this pass
- `../equation-verification/SUMMARY.md` — current audit of analytic gradients,
  finite-difference fallbacks, and equation-level verification gaps

## Scope rule

If a fact is still actionable for future implementation or analysis, it belongs here.

If it is mainly historical, GSD-specific, or a record of a one-time integration step, it belongs in `docs/planning-history/`.
