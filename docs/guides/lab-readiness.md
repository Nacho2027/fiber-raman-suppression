# Lab Readiness

A lab-ready run is one another person can install, run, inspect, and export
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

## Handoff Checklist

For the shortest new-user path, start with
`first-lab-user-walkthrough.md`. Before handoff:

- run `make lab-ready`;
- run `make golden-smoke`;
- inspect the four standard images;
- record the smoke run directory;
- state which lanes are supported, experimental, or planning-only.

## Current Research Closure State

The checked handoff run is single-mode phase-only Raman suppression.
Staged `amp_on_phase` remains an experimental refinement. MMF is a qualified
simulation candidate after the high-resolution validation, but it is not a
routine local workflow. Long-fiber and broad multivariable workflows remain
experimental or planning-only.

## Not lab-ready by default

- MMF planning configs;
- long-fiber planning configs;
- direct multivariable optimization;
- old phase directories under `docs/planning-history/`;
- generated result folders without inspected images.
