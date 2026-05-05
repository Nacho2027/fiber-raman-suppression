# Extending And Troubleshooting

Use this when a supported config is not enough.

## Add A New Experiment

1. Start with the FiberLab concepts: `Fiber`, `Pulse`, `Grid`, `Control`,
   `Objective`, `Solver`, and `Experiment`.
2. If the experiment needs to be reproducible or batch-run, write it as a config
   under `configs/experiments/`.
3. Run `./fiberlab plan <config>` and `./fiberlab layout <config>`.
4. Run `./fiberlab artifacts <config>` to confirm expected outputs.
5. Add or update a focused test when behavior changes.

Do not add a one-off driver under `scripts/` for a normal experiment. The
maintained path is FiberLab API first, config bridge second, canonical wrapper
only when a compatibility command needs to be maintained.

## Add A New Variable Or Objective

Use extension contracts under `lab_extensions/` for experimental controls or
objectives. Promote stable behavior into `src/` once it is reused or required by
multiple workflows.

Validation commands:

```bash
./fiberlab variables --validate
./fiberlab objectives --validate
```

## Debug A Failed Run

1. Re-run the config as a dry run.
2. Check `run_manifest.json` and the result sidecar in the output directory.
3. Inspect the standard image set, not just file existence.
4. Check boundary fractions, conservation, convergence, and configured Raman
   band before trusting a numerical improvement.
5. For high-resource configs, reproduce on suitable compute with
   `julia -t auto --project=. ...`.

## Keep The Repo Small

- Put stable user-facing API in `src/fiberlab/`.
- Keep low-level propagation and numerics in the backend files under `src/`.
- Put transitional orchestration in `scripts/lib/`.
- Put thin commands in `scripts/canonical/`.
- Put human guidance in `docs/`.
- Keep agent notes temporary and short.
- Archive raw results, caches, and failed research drivers outside the active
  tree.
