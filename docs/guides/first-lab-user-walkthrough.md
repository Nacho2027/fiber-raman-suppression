# First Lab User Walkthrough

Shortest path for a new user.

## 1. Install

```bash
make install
make doctor
make lab-ready
```

## 2. See available configs

```bash
./fiberlab configs
./fiberlab plan research_engine_poc
```

## 3. Run the supported baseline

```bash
./fiberlab run research_engine_poc
./fiberlab latest research_engine_poc
./fiberlab ready latest research_engine_poc
```

## 4. Run the handoff smoke

```bash
make golden-smoke
```

## 5. Inspect output

Open the standard images under the newest result directory. If the images look
blank, cropped, or inconsistent with the reported metric, do not use the result
until the issue is understood.

The neutral handoff bundle is under `export_handoff/` in the generated run
directory.

## 6. Notebook Pattern

Notebook work should read committed interfaces and generated artifacts:

- run a supported config from the shell;
- read `opt_result.json` for metrics;
- read `export_handoff/phase_profile.csv` for a neutral phase profile;
- embed the standard PNGs for visual review.

## 7. Next reading

- [supported workflows](supported-workflows.md)
- [configurable experiments](configurable-experiments.md)
- [interpreting plots](interpreting-plots.md)
- [output format](../architecture/output-format.md)
