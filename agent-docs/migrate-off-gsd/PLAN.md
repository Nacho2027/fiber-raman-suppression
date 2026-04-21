# Plan

1. Archive the requested `.planning/` directories and top-level planning docs under `docs/planning-history/`, preserving the internal structure.
2. Remove the active GSD config file from `.planning/`.
3. Rewrite `CLAUDE.md` so it keeps the project, stack, conventions, architecture, machine workflow, session protocol, and compute-discipline rules, but removes GSD enforcement/runtime policy.
4. Separate active agent work docs from human-facing docs by using `agent-docs/` for internal notes and `docs/` for user-facing docs and reports.
5. Replace `AGENTS.md` with a short Codex-facing front page that mirrors the new top-level rules.
6. Record this migration in `agent-docs/migrate-off-gsd/` and commit the migration as a single atomic change.
