# Lab Readiness

A lab-ready workflow is one another person can install, run, inspect, and export
without needing private context.

## Local gate

```bash
make lab-ready
```

This validates experiment configs, sweep configs, the export-smoke readiness
check, and the fast test tier.

## Artifact gate

```bash
make golden-smoke
```

This creates a real smoke result and verifies the export handoff path.

## Manual check

Before calling a run ready, inspect:

- standard images;
- `run_manifest.json`;
- trust or readiness report;
- export bundle, if the result is for lab handoff.

## Not lab-ready by default

- MMF planning configs;
- long-fiber planning configs;
- direct multivariable optimization;
- old phase directories under `docs/planning-history/`;
- generated result folders without inspected images.
