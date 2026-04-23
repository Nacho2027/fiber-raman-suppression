# Branch Reconciliation Plan

1. Inventory worktrees and branch refs, including `origin/*`.
2. Compare every non-`main` branch against `main` for unique commits and durable tracked artifacts.
3. Inspect linked worktrees for clean/dirty state plus candidate materials in `docs/`, `agent-docs/`, `.planning/`, and curated `results/` locations.
4. Recover only missing durable artifacts into `main`.
5. Remove auxiliary worktrees.
6. Delete non-`main` local branches.
7. Delete non-`main` remote branches.
8. Record reconciliation details and final state.
