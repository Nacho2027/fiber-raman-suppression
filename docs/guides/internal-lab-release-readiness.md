# Internal Lab Release Readiness

Run this checklist before telling another Rivera Lab user to run the repo.

## Required

```bash
make install
make doctor
make lab-ready
make golden-smoke
```

Also open the smoke output images and confirm they render correctly.

## Handoff contents

Point the user to:

- `README.md`;
- `docs/guides/installation.md`;
- `docs/guides/supported-workflows.md`;
- `docs/guides/configurable-experiments.md`;
- `docs/guides/first-lab-user-walkthrough.md`.

## Say clearly

- The supported path is single-mode phase optimization.
- `amp_on_phase` is experimental refinement.
- MMF and long-fiber configs are not routine local workflows.
- Generated `results/` folders are not source files.
