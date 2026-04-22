# Summary

The active workflow docs now reflect the simpler git policy:

- agents work on `main`
- agents push to `main`
- rejected pushes are resolved by rebasing on `origin/main`
- `sessions/*` branches are no longer the default parallel-session workflow

The historical branch-per-session material remains in `docs/planning-history/` as archive only.
