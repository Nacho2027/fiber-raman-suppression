# Context

The repo was carrying forward an older parallel-session workflow that assumed:

- per-session git branches
- optional git worktrees per session
- user-led integration checkpoints

That no longer matches the desired operating model. The requested policy is simpler:

- all agents stay on `main`
- all agents push to `main`
- no routine `sessions/*` branch workflow

The active instructions need to say that explicitly so future agents do not recreate the old branch-heavy process.
