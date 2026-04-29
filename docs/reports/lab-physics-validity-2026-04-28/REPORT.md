# Lab Physics Validity

Date: 2026-04-28

## Bottom line

The supported lab surface can demonstrate the single-mode phase-optimization
workflow and produce inspectable handoff artifacts. It does not, by itself,
validate every research claim in the repo.

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
