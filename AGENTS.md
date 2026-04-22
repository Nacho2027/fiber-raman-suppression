# Codex Operating Rules

This is a Julia + Python nonlinear fiber optics simulation project focused on Raman suppression, optimization, and visualization work.

`AGENTS.md` is the canonical short operational contract for agents. `CLAUDE.md` is the longer human/reference manual.

## Core Rules

- Keep agent docs and human docs separate. Put internal work notes in `agent-docs/<topic>/CONTEXT.md`, `agent-docs/<topic>/PLAN.md`, and `agent-docs/<topic>/SUMMARY.md`. Put human-facing docs and reports in `docs/`.
- Read `agent-docs/current-agent-context/` before deep numerics, methodology, or infrastructure work.
- Research before coding. Grep the repo, read the files you touch and the files they call into, then check official docs and known pitfalls when the change depends on external behavior.
- Test heavily. Add or update tests for every non-trivial change, and do not call work done until the relevant tests have been run.

## Git And Sync

- All sessions work on `main` and push to `main`.
- Start with:

```bash
git status
git fetch origin
git pull --ff-only origin main
```

- If your push is rejected, run:

```bash
git fetch origin
git rebase origin/main
git push origin main
```

- The Mac and `claude-code-host` working trees are kept in sync by Syncthing.
- `.git` is not synced. Syncthing is for live file movement; git is for history and GitHub pushes.
- Syncthing does not solve simultaneous edits. Avoid overlapping edits to the same file path, or you will get `.sync-conflict-*` files.

## Compute Rules

- Heavy simulation work belongs on `fiber-raman-burst`, not on `claude-code-host`.
- `claude-code-host` is for editing, orchestration, dependency operations, and inspection only.
- The Mac and `claude-code-host` sync via Syncthing. `fiber-raman-burst` is not part of that sync mesh.
- Stage code to burst explicitly with `rsync`, run through `~/bin/burst-run-heavy`, then pull `results/` back explicitly with `rsync`.
- Never bypass the heavy-job wrapper for substantial Julia runs on burst.
- Always launch Julia with threading enabled for simulation work: `julia -t auto --project=. ...`
- Always stop the burst VM when done.

## Output Rules

- Every optimization driver that produces a `phi_opt` must call `save_standard_set(...)` from `scripts/standard_images.jl` before exiting.
- The expected standard image set is:
  - `{tag}_phase_profile.png`
  - `{tag}_evolution.png`
  - `{tag}_phase_diagnostic.png`
  - `{tag}_evolution_unshaped.png`
- Work that produces `phi_opt` but does not leave the standard images on disk is incomplete.

## Results Rules

- Do not treat `results/` as normal source code.
- Syncthing moves `results/` between the Mac and `claude-code-host`.
- Burst results come back via explicit `rsync`, then Syncthing carries them to the Mac.
- Commit only durable, intentionally chosen summaries or fixtures. Do not reflexively commit the whole `results/` tree.

## When In Doubt

- Use `CLAUDE.md` for the full project conventions, architecture notes, multi-machine workflow, and compute-discipline details.
