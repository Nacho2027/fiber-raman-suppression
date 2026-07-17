# Experiment Configs

TOML files here are read by `./fiberlab` and
`scripts/canonical/run_experiment.jl`.

## Commands

```bash
./fiberlab configs
./fiberlab plan research_engine_poc
./fiberlab validate
```

Validation covers both listed runnable configs and the checked templates under
`templates/`.

Supported configs should run through the normal `run` lane. Experimental or
planning configs should be used through `explore` or dry-run inspection until
their gates are closed.

Do not add a config that names an objective or variable not implemented in code.
