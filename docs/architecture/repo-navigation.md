# Repo Navigation

Use this before moving code.

## Main directories

| Path | Purpose |
|---|---|
| `src/` | reusable Julia package code |
| `scripts/lib/` | shared implementation for scripts |
| `scripts/canonical/` | maintained CLI wrappers |
| `scripts/workflows/` | workflow bodies called by wrappers |
| `scripts/research/` | active research drivers outside the supported surface |
| `configs/` | run, sweep, experiment, and SLM specs |
| `docs/` | human-facing docs |
| `agent-docs/` | agent continuity notes |
| `results/` | generated artifacts |

## Where to edit

- physics or reusable numerics: `src/`;
- supported command behavior: `scripts/lib/` plus a thin wrapper in
  `scripts/canonical/`;
- one-off research driver: `scripts/research/<topic>/`;
- approved run settings: `configs/`;
- user-facing behavior changes: the matching file under `docs/`.

Do not promote notebook code by linking to it. Move reusable logic into `src/`
or `scripts/lib/` first.
