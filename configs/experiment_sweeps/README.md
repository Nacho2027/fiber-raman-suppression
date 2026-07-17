# Experiment Sweeps

Sweep specs expand one experiment across parameter values.

```bash
./fiberlab sweep list
./fiberlab sweep plan smf28_power_micro_sweep
./fiberlab sweep validate
./fiberlab sweep latest smf28_power_micro_sweep
./fiberlab sweep run smf28_power_micro_sweep
```

Only supported sweeps whose expanded cases are also supported can execute;
experimental sweeps remain plan-only and fail closed at `sweep run`. Run large
sweeps on a suitable workstation or cluster. Keep routine outputs out of git.
