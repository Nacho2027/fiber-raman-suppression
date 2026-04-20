---
id: 260420-iwc
slug: sync-phase22-artifacts
date: 2026-04-20
status: complete
commit: 7e9b965
---

# Quick Task 260420-iwc: Summary

## What happened

Mac was 1 commit ahead of origin/main (a one-line header comment in
`scripts/common.jl`) and 24 commits behind (overnight VM integration of
phases 21/23/24 plus ancillary fixes). Rebased the local commit onto
origin/main — zero conflicts because origin did not touch `scripts/common.jl`.

## Force-added (now tracked in git, pushed to origin/main)

Single commit `7e9b965 integrate(phase22): S-sharpness research artifacts +
26 flavor standard-image sets`, 110 files:

| Path | Count |
|------|-------|
| `.planning/phases/22-sharpness-research/22-01-PLAN.md` | 1 |
| `.planning/phases/22-sharpness-research/22-CONTEXT.md` | 1 |
| `.planning/phases/22-sharpness-research/22-RESEARCH.md` | 1 |
| `.planning/phases/22-sharpness-research/SUMMARY.md` | 1 |
| `.planning/phases/22-sharpness-research/UAT.md` | 1 |
| `.planning/phases/22-sharpness-research/REVIEWS.md` | 1 |
| `.planning/phases/22-sharpness-research/images/*.png` | 104 |

The 104 PNGs are the standard 4-image set (`phase_profile`, `evolution`,
`phase_diagnostic`, `evolution_unshaped`) × 26 optimizer flavors. The user
said "24 flavors"; actual is 26 — matches `canonical` + `pareto57` × (plain,
multiple SAM rhos, multiple MC sigmas, multiple trH lambdas). Close enough
to their estimate that this is not a discrepancy.

Files copied from `~/RiveraLab/raman-wt-sharpness/.planning/phases/22-sharpness-research/`
(the S-sharpness session worktree on branch `sessions/S-sharpness` at
`a6a9149`). Main repo now has them in the working tree and in git.

## Synced via rsync only (not force-added)

Everything else under `.planning/` that is not in git and wasn't explicitly
the S-sharpness target. Notable examples transferred by `sync-planning-to-vm`:

- `.planning/phases/19-physics-audit-2026-04-19/` — local phase dir from
  Saturday's audit; analogous to the tracked phase 20 but was never force-added
  by any integrator (see "Surprising" below).
- `.planning/quick/260415-u4s-*/`, `.planning/quick/260416-gcp-setup/` — quick
  tasks that predate the current tracking convention.
- `.planning/todos/pending/*`, `.planning/seeds/*` — working-state files by
  project policy.
- `.planning/notes/compute-infrastructure-decision.md`,
  `.planning/notes/parallel-session-prompts.md`,
  `.planning/notes/session-prompts-only.md`,
  `.planning/notes/multimode-optimization-scope.md`,
  `.planning/notes/gsd-hook-patch` — Mac-authored notes.
- `.planning/milestones/v1.0-ROADMAP.md`, `.planning/milestones/v1.0-REQUIREMENTS.md`,
  `.planning/MILESTONES.md`, `.planning/config.json` — milestone working state.
- `.planning/reports/20260405-session-report.md`,
  `.planning/research/advisor-meeting-questions.md`,
  `.planning/research/RIVERA_RESEARCH.md`.
- `~/.claude/projects/.../memory/` files (12 total).

## Surprising findings

1. **Phase 19 (`19-physics-audit-2026-04-19`) is only on Mac disk, never in
   git history on any branch.** It has the same three-file structure as the
   tracked phase 20 (`CONTEXT`, `PLAN`, `SUMMARY`). The overnight integrator
   tracked phase 20 but skipped phase 19. I intentionally did NOT force-add it
   in this task because the scope was Phase 22 and I want the user to confirm
   the policy decision before expanding. Flagging here so the user can decide
   whether to repeat this workflow for phase 19.
2. **Second Mac worktree `~/RiveraLab/raman-wt-matched`** (branch
   `sessions/M-matched100m` at `204489b`) exists and contains phase 20 +
   phase 23 — but phase 23 is already on origin/main via the overnight
   integration, so nothing to push from there.
3. **The S-sharpness worktree branch `sessions/S-sharpness` is at `a6a9149`
   and was never merged to main.** Per Rule P2 (branch-per-session), the user
   integrates session branches themselves. I did not push `sessions/S-sharpness`
   to origin — I only folded its `.planning/phases/22-sharpness-research/`
   artifacts into main. The session branch can now be safely deleted if the
   user is done with it; nothing else on that branch was unique to the Mac.
4. **Local `docs(common): add header comment`** rebased cleanly onto
   origin/main as `27c7704`, then got carried forward under `7e9b965`.
   Verified no conflict because `scripts/common.jl` was untouched in the
   overnight integration.
