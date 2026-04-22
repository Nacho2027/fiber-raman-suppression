# Codex Notes

This is a Julia + Python nonlinear fiber optics simulation project focused on Raman suppression and related optimization and visualization work.

- Keep agent docs and human docs separate. Put internal work notes in `agent-docs/<topic>/CONTEXT.md`, `agent-docs/<topic>/PLAN.md`, and `agent-docs/<topic>/SUMMARY.md`. Put human-facing docs and reports in `docs/`.
- Read `agent-docs/current-agent-context/` before deep numerics, methodology, or infrastructure work. That directory is the curated replacement for the old `.planning/` agent context.
- Research before coding. Grep the repo, read the files you touch and the files they call into, then check official docs and known pitfalls when the change depends on external behavior.
- Test heavily. Add or update tests for every non-trivial change, and do not call work done until the relevant tests have been run.
- All sessions work on `main` and push to `main`. Start with `git fetch origin && git pull --ff-only origin main`. If your push is rejected, run `git fetch origin && git rebase origin/main`, then push again. Do not create session branches unless the user explicitly asks for one.

Read `CLAUDE.md` for the full project conventions, architecture notes, multi-machine workflow, and compute-discipline rules for simulations.
