# Summary

## Completed

- Archived the requested historical planning material into `docs/planning-history/`.
- Removed `.planning/config.json`.
- Rewrote `CLAUDE.md` around a stock `docs/` workflow.
- Split active doc locations: `agent-docs/` for agent work notes, `docs/` for human-facing docs and reports.
- Replaced `AGENTS.md` with a short Codex-facing version of the new top-level rules.

## Notes

- The recent archived work was mostly about numerical trust reporting, performance modeling, and saddle-escape analysis.
- Active agent work should now use tracked `agent-docs/<topic>/` directories instead of `.planning/`.
- Human-facing docs and reports stay in `docs/`.

## Left in place on purpose

- `.planning/milestones/`, `.planning/quick/`, `.planning/reports/`, and `.planning/todos/` were left untouched because they were outside the explicitly requested archive set.
- `scripts/check-phase-integrity.sh`, `scripts/codex-gsd-bootstrap.sh`, and `scripts/codex-gsd-prompt.md` were left untouched because they are clearly GSD-related support artifacts, but not clearly within the requested "config files" deletion scope.
