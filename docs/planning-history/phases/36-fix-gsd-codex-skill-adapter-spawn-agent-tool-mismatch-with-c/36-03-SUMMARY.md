---
plan: 36-03
status: HALTED
verdict: harness_defect
control_run: non-compliant (confirmed, ≥3/7 FAIL)
patched_run: failed (6/7 FAIL — identical to control)
plan_04_status: BLOCKED — does NOT start per plan STOP rule
generated: 2026-04-21T02:45:00Z
---

# Plan 36-03 SUMMARY — Before/After Before-and-After Test

## Verdict

**HALTED.** Patched run failed the 7-criterion gate (6/7 FAIL, exit 1). Plan 36-04
does NOT start. However, root-cause analysis in `evidence/patched/FAIL.md` classifies
the failure as a **harness defect**, not an adapter defect — Codex ran in its default
read-only sandbox against a test project missing `.planning/STATE.md`, so `spawn_agent`
was never attempted in either direction. The Direction A adapter text installed correctly
(83/83 skills carry USER AUTHORIZATION NOTICE, 15/15 BLACKLIST skills carry STOP phrase).

## Side-by-Side 7-Criterion Table

| # | Criterion | Expected (patched) | Control | Patched | Δ |
|---|-----------|--------------------|---------|---------|---|
| 1 | spawn_agent invocations | ≥ 1 | **0** (FAIL) | **0** (FAIL) | none |
| 2 | Atomic per-plan commits | ≥ 2 | **0** (FAIL) | **0** (FAIL) | none |
| 3 | Rollup commits == 0 | 0 | 0 (PASS) | 0 (PASS) | none |
| 4 | manifest.json present | YES | **NO** (FAIL) | **NO** (FAIL) | none |
| 5 | check-phase-integrity.sh exit 0 | 0 | **1** (FAIL) | **1** (FAIL) | none |
| 6 | SUMMARY references ≥ 2 plan IDs | ≥ 2 | n/a (FAIL) | n/a (FAIL) | none |
| 7 | EXECUTION mentions subagent | ≥ 1 | n/a (FAIL) | n/a (FAIL) | none |

Both directions: 1 PASS / 6 FAIL. The patched run shows NO improvement over control —
not because the adapter failed, but because the harness never put Codex in a state
where the adapter could be exercised.

## Control Run Evidence (GSD 1.38.1 unpatched)

- Install: `npx --yes get-shit-done-cc@1.38.1 --codex --global` → successful, 81 skills installed
- W5 sanity: 0 skills carry NOTICE after install — confirmed (control adapter is live)
- Codex invocation: `codex exec --skip-git-repo-check -C /tmp/gsd-codex-adapter-test '$gsd-execute-phase 1'`
- codex_exit: 0 (command succeeded — but only dumped the workflow text inline, no execution)
- verify_control_failed.sh: PASS (`RESULT: control confirmed non-compliant`)

## Patched Run Evidence (forked adapter, `fix/codex-spawn-agent`)

- Install: `cd ~/src/gsd-fork && node bin/install.js --codex --global --no-sdk` → successful, 83 skills installed
- B2 sanity: 83 skills carry NOTICE after install — confirmed (patched adapter is live)
- Codex invocation: identical to control
- codex_exit: 0 (but codex explicitly refused to execute, see tail below)
- verify_patched_passed.sh: **FAIL** (exit 1, 6/7 criteria failed)

Codex's own refusal message (`evidence/patched/run.log` tail):
> Phase `1` is resolved correctly, but execution is blocked before Wave 1 can start.
> The hard blockers are:
> - `.planning/STATE.md` is missing, while the workflow expects phase-state writes during execution.
> - This session is mounted `read-only`, so I cannot create `A.txt`, `B.txt`, summaries, manifest/state files, or git commits.

## Harness Defects Identified (blocking re-run)

1. **`codex exec` invocation missing `--sandbox workspace-write`.** Codex defaults to
   read-only, which refuses all file/commit mutations before `spawn_agent` would fire.
   Affects both run_control.sh and run_patched.sh identically.
2. **`bootstrap_test_project.sh` does not seed `.planning/STATE.md`.** `gsd-execute-phase`
   performs `state.begin-phase` in its init step, which requires this file.

Both fixes are small (2-line and ~6-line edits respectively) and are documented with
diffs in `evidence/patched/FAIL.md`.

## Deviations from Plan

- Plan 36-03 Task 2 Step 1 (run_control.sh) terminated prematurely during a prior
  execution attempt — the agent was killed mid-codex-exec pipe. The control codex
  session had already completed (2004-line run.log is fully captured); the capture
  loop for the 7 criteria was re-run inline by the orchestrator (equivalent to the
  script's Step 6 block) to produce spawn_count.txt, git_log.txt, manifest_present.txt,
  integrity.txt, phasedir_listing.txt, NO_SUMMARY, NO_EXECUTION. No evidence fabricated.
- Post-install `manifest_present.txt` was initially written as `YES` due to a compgen
  edge case under zsh (not bash); re-computed via `ls … | grep -q .` and corrected to
  `NO` before verify was run.

## STOP

Per plan 36-03 Task 2 Step 4: Plan 36-04 does NOT start. Orchestrator returns to the
user for a revision decision — either authorize a follow-up plan to fix the harness
and re-run, or accept this halted state and rescope Plan 04.

## Commits

- `test(phase36-03): capture control + patched before/after evidence` (this plan's evidence commit)
- `fix(phase36-03): patched run FAILED — see evidence/patched/FAIL.md` (STOP marker commit)

## No Touches To

`.planning/STATE.md`, `.planning/ROADMAP.md`, `main` branch, any file outside
`.planning/phases/36-*/` or `/tmp/gsd-codex-adapter-test/`. Parallel-session Rules
P1/P2/P3 respected.
