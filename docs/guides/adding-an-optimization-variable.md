# Adding an Optimization Variable

A new optimization variable is a code change, not just a new TOML key.

## Minimum work

- define the variable contract;
- map optimizer vectors to physical controls;
- add bounds or regularization;
- implement gradients or clearly mark the solver as derivative-free;
- add artifact output that lets a reader inspect the control;
- add tests for validation and dispatch;
- update the supported/experimental status.

## Scaffold

```bash
julia -t auto --project=. scripts/canonical/scaffold_variable.jl my_variable   --label "My variable"   --status planning
```

Then run:

```bash
./fiberlab variables --validate
```

Keep the variable experimental until representative runs and artifacts have
been checked.
