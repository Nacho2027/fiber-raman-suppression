# Agent Operating Rules

This is a Julia-first nonlinear fiber optics simulation project focused on
Raman suppression, optimization, and visualization. Keep the active repo small,
legible, and easy for agents to navigate.

`AGENTS.md` is the canonical short contract for agents. Keep it short and
operational.

## Project Spine

- Primary implementation language: Julia.
- Product-facing code starts in `src/fiberlab/`: fibers, pulses, grids,
  controls, objectives, solvers, experiments, and artifacts.
- Low-level propagation and inherited physics backend code stays under `src/`.
- Checked TOML configs in `configs/experiments/` serialize experiments for
  reproducibility; they are not the conceptual API.
- Experimental controls and objectives live under `lab_extensions/`.
- `scripts/lib/` is transitional orchestration glue, not the product center.
- `scripts/canonical/` and `./fiberlab` are maintained compatibility entry
  points and readiness tools.
- Python is not a supported API surface unless the user explicitly asks for it.
- Ignored local folders such as `.venv/`, `.claude/`,
  `.pytest_cache/`, and `.bg-shell/` are not repo structure. Do not inspect or
  summarize them unless the task is explicitly about local tooling.
- Treat one-off notebooks, old phase scripts, generated outputs, and historical
  planning as non-canonical unless a current doc says otherwise.

## Agent Context Diet

- Prefer deleting, moving, or condensing obsolete docs, scripts, and generated
  artifacts over preserving stale context in the active tree.
- Do not create new long-lived agent-doc folders by default.
- If cleanup needs a breadcrumb, use one short temporary note and remove or
  collapse it when done.
- Do not add a new script when a config, small canonical wrapper, or reusable
  Julia function can express the workflow.
- Promote stable user-facing behavior toward `src/fiberlab/`; keep
  `scripts/lib/` for orchestration and transitional workflow glue.
- Keep human docs in `docs/`; keep agent-only operational notes in
  `agent-docs/`.
- Use `llms.txt`, `README.md`, and the smallest relevant doc map before
  recursively reading large documentation trees.

## Safety

- Delete obsolete files when a refactor or feature removal makes them
  irrelevant.
- Never delete files just to silence a test, lint, type, import, or runtime
  error. Stop and ask if deletion is only a workaround.
- Never edit `.env` or other environment variable files.
- Do not revert or delete work you did not author unless the user explicitly
  asks or all active agents agree.
- Moving, renaming, and restoring files is allowed when it preserves intent and
  improves structure.
- Never run destructive git operations such as `git reset --hard`,
  `git checkout --`, or broad `git restore` unless the user gives explicit
  written approval in the current thread.
- If a git operation leaves you unsure about another agent's in-flight work,
  stop and coordinate instead of deleting or reverting.

## Git

- Work on `main` unless the user asks otherwise.
- Start substantial sessions by checking local state:

```bash
git status
```

- Do not reflexively `git pull` at session start; inspect and reconcile commit
  history only when needed.
- Before committing or pushing, run:

```bash
git fetch origin
git status
```

- Keep commits atomic. Commit only files you touched and list paths explicitly.
- Quote git paths containing brackets, parentheses, or shell metacharacters.
- When rebasing, avoid opening editors by using `GIT_EDITOR=:` and
  `GIT_SEQUENCE_EDITOR=:` or an equivalent no-editor option.
- Never amend commits without explicit written approval.
- Avoid simultaneous edits to the same path across machines or agents.

## Research Before Coding

- Grep the repo before changing code. Read the files you touch and the files
  they call into.
- Check official docs or known pitfalls when a change depends on external
  behavior.
- Prefer test-driven development for non-trivial code changes. If red-first TDD
  is not practical, still add or update the relevant regression test before
  closing the work.
- Run the relevant tests before calling non-trivial work done.
- Public or reused code should have clear docstrings. Tricky numerics should
  document assumptions and invariants.

## Compute Rules

- No cloud provider or remote host is assumed to exist.
- Use local machines for validation and small smoke runs. Inspect
  `./fiberlab compute-plan SPEC` before high-resource work.
- Run long-fiber, multimode, or large-grid jobs only on a workstation, cluster,
  or cloud node with sufficient memory/time, and acknowledge them explicitly
  with the supported `--heavy-ok` path.
- Always launch Julia with threading enabled for simulation work:
  `julia -t auto --project=. ...`
- Copy result bundles back deliberately and stop any metered compute resource
  when the job finishes.

## Results And Outputs

- Do not treat `results/` as source code.
- Do not recursively inspect `results/` by default; use manifests, summaries,
  or targeted paths.
- Preserve important raw results by inventorying or moving them to a results
  vault before deleting from the active repo.
- Commit only durable, intentionally chosen summaries, fixtures, or figures.
- Generated PNGs, run logs, and routine JLD2 outputs should stay out of git
  unless deliberately curated.
- Any optimization driver that produces `phi_opt` must save the standard image
  set before exiting.
- Do not treat PNG existence as sufficient verification. For a single run,
  visually inspect the standard image set before calling it complete.

## When In Doubt

- Choose the smallest supported Julia path.
- Prefer one canonical doc update over adding another document.
- Ask before making an irreversible cleanup decision that could destroy unique
  scientific evidence or another agent's active work.
