# Research Engine UX

The CLI should make the safe path easy and the risky path explicit.

## Lanes

- `run`: supported or conservative execution.
- `explore`: experimental execution with blockers and compute warnings visible.
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

A command should never make an experimental path look more supported than it is.
Print the status, blockers, compute expectation, and artifact plan before work
starts.
