# Lab Physics Validity

Date: 2026-04-28

## Bottom line

The current lab-ready run demonstrates one thing: single-mode phase optimization
with inspectable output and a handoff bundle. It does not validate every
research claim in the repo.

## Valid for

- local installation and CLI health;
- config validation;
- single-mode phase smoke runs;
- standard-image generation;
- export-bundle generation;
- result and telemetry indexing.

## Not valid for

- broad MMF claims;
- long-fiber convergence claims;
- direct joint multivariable superiority;
- device-calibrated SLM performance;
- production readiness of Newton/preconditioning methods.

## Gate commands

```bash
make lab-ready
make golden-smoke
```

Use slow/full tests and burst runs when the claim depends on simulation scale,
parameter coverage, or heavy numerics.
