# Exploratory Physics Workflow

Use this path for questions outside the supported lab surface.

## Pattern

1. Start with a config that only plans or smokes.
2. Inspect the compute and artifact plan.
3. Run locally only if the config is a true smoke.
4. Move heavy work to burst.
5. Pull results back and inspect standard or fallback artifacts.
6. Promote the result only after writing a short status note.

## Commands

```bash
./fiberlab explore list
./fiberlab explore plan <config_id>
./fiberlab check config <config_id>
./fiberlab explore run <config_id> --local-smoke
./fiberlab explore compare results/raman --top 10
```

For heavy paths, use `--heavy-ok --dry-run` locally to inspect the launch plan,
then run on the burst machine through the wrapper.

Exploration is allowed to be messy. The docs should not be.
