# Configurable Experiments

Experiment configs live under `configs/experiments/`. They are serialized
FiberLab experiments for reproducible runs and batch execution.

For new notebook work, start from `Experiment` objects first. Use configs when
the run needs to be shared, repeated, validated by `make lab-ready`, or staged
for lab compute.

Useful commands:

```bash
./fiberlab configs
./fiberlab capabilities
./fiberlab plan <config>
./fiberlab layout <config>
./fiberlab artifacts <config>
./fiberlab compute-plan <config>
./fiberlab run <config>
./fiberlab latest <config>
```

Validation:

```bash
./fiberlab validate
./fiberlab objectives --validate
./fiberlab variables --validate
```

Add new supported behavior through the FiberLab API, Julia extension
contracts, and tests. Do not add Python API code for maintained workflows.
