# Research Engine UX

The CLI should show what will run, where it will write files, and why a config
is blocked.

## Lanes

- `run`: supported or conservative execution.
- `explore`: experimental execution with blockers and compute warnings.
- `check`: inspection without running optimization.
- `ready`: readiness checks for configs or completed runs.
- `sweep`: planned parameter expansion and sweep status.

## Useful commands

```bash
./fiberlab configs
./fiberlab plan research_engine_poc
./fiberlab run research_engine_poc
./fiberlab explore plan research_engine_gain_tilt_smoke
./fiberlab check config research_engine_gain_tilt_smoke
./fiberlab explore compare results/raman --top 10
```

## UX rule

A command should print the status, blockers, compute expectation, and artifact
plan before work starts.
