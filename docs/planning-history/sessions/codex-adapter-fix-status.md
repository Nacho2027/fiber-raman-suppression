---
session: codex-adapter-fix
branch: sessions/codex-adapter-fix
worktree: /Users/ignaciojlizama/raman-wt-codex-adapter
phase: 36
status: HALTED — Direction A insufficient, Direction B required (new phase)
last_updated: 2026-04-21T04:00:00Z
---

# Session Status — codex-adapter-fix

## Goal (original)

Fix the symptom documented in CLAUDE.md Codex Runtime Constraints: when running
`$gsd-execute-phase`, `$gsd-plan-phase`, etc. from Codex CLI, `spawn_agent` is
never invoked (sqlite count 0). Sub-agents `gsd-planner`, `gsd-executor`,
`gsd-verifier` silently degrade to inline single-agent execution, producing
commit bombs, missing manifests, and the Phase-28-style integrity damage.

## State as of halt

- 4 phase-36 plans executed. Plan 36-04 (upstream filing) intentionally not started.
- Patched vs control harness retest (after sandbox + verify-script fixes):
  - Control (GSD 1.38.1 unpatched): 1/7 criteria pass.
  - Patched (Direction A fork): 6/7 criteria pass.
  - Unresolvable under Direction A: criterion 1 (`spawn_agent invocations ≥ 1` — still 0).
- **Original problem is NOT fixed** — sub-agents still do not spawn. Direction A
  only makes the inline-execution failure mode audit-compliant (atomic per-plan
  commits, manifest.json, EXECUTION.md, phase-wide SUMMARY.md). Useful, but a
  partial mitigation, not a fix.

## Root cause identified (see 36-HANDOFF.md)

Direction A patches only the SKILL.md adapter header (~50 lines). It does NOT
touch the workflow files referenced by skills. The installed workflow file
`~/.codex/get-shit-done/workflows/execute-phase.md` still contains 9 literal
`Task(subagent_type="X", prompt="Y")` calls (Claude syntax) and 0
`spawn_agent(...)` calls. Codex has no `Task()` tool, so when it loads the
workflow it degrades to inline execution. The `USER AUTHORIZATION NOTICE`
patched into the adapter header addresses Codex's spawn gate, but gives it
no imperative spawn calls to run — so the gate is moot.

## Direction B — what the next phase must do

Extend the fork's installer (`~/src/gsd-fork/bin/install.js`) to also rewrite
workflow files for the Codex target. Substitutions in every
`~/.codex/get-shit-done/workflows/*.md`:

| Claude syntax | Codex translation |
|---------------|-------------------|
| `Task(subagent_type="X", prompt="Y")` | `spawn_agent(agent_type="X", message="Y")` |
| `Task(model="...")` | omit (per-role `.toml` in `~/.codex/agents/` already sets model) |
| `isolation="worktree"` | omit (Codex sandbox provides isolation) |
| Multiple parallel `Task(...)` calls | `spawn_agent` + `wait(ids)` + `close_agent(id)` pattern |

Regression gate: `harness/run_patched.sh` followed by `harness/verify_patched_passed.sh`
must show `evidence/patched/spawn_count.txt` ≥ 1 AND exit 0 (all 7 criteria PASS,
not just 6).

## Files / fork / branch state

- This worktree: `/Users/ignaciojlizama/raman-wt-codex-adapter`, branch
  `sessions/codex-adapter-fix`, 6 commits ahead of origin.
  - `a9ec6ee chore(phase36-01): add wave-0 harness + baseline evidence`
  - `783d589 docs(phase36-01): add plan summary (wave-0 harness + baseline)`
  - `7b4a7a6 chore(phase36-02): install patched fork adapter (Task 3's install) + lint 81 skills`
  - `4d2b77b test(phase36-03): capture control + patched before/after evidence`
  - `b3ae3a0 fix(phase36-03): patched run FAILED — see evidence/patched/FAIL.md`
  - `eb9bf3b fix(phase36-03-retry): harness corrections before re-run`
  - `29b45ef test(phase36-03-retry): full sandbox bypass + verify-script defect fixes`
  - `ba06678 docs(phase36): handoff — Direction A insufficient, root cause identified`
- Fork clone: `~/src/gsd-fork/`, branch `fix/codex-spawn-agent`, commit `9f3d123`.
  - **UNPUSHED** to upstream (`github.com/Nacho2027/get-shit-done` fork exists but
    the branch hasn't been pushed). DO NOT push or open a PR until Direction B
    ships in the same branch.
- Patched Codex adapter: currently installed in `~/.codex/skills/`
  (83 skills carry `USER AUTHORIZATION NOTICE`, 15/15 BLACKLIST skills carry the
  STOP phrase). Leave installed — integrity-contract benefits persist even
  without Direction B. Revert if desired via
  `npx --yes get-shit-done-cc@1.38.1 --codex --global`.
- Throwaway test project: `/tmp/gsd-codex-adapter-test/` (git repo, last
  `chore: seed test project`). Recreated by `harness/bootstrap_test_project.sh`
  on every run, safe to delete.

## Reusable harness (do not re-invent in Direction B)

All under `.planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/`:

- `reproduce.sh` — prints spawn_agent sqlite count, Codex version, skill count, STOP condition
- `capture_tools.sh` — dumps Codex native binary tool surface
- `bootstrap_test_project.sh` — creates the 2-plan throwaway test project at /tmp
- `run_control.sh` — reinstall 1.38.1 + post-install sanity + run codex exec + capture 7 criteria
- `run_patched.sh` — source fork-install-cmd.sh + sanity + run codex exec + capture
- `verify_control_failed.sh` — emit 7-row PASS/FAIL, gate on ≥3 FAILs
- `verify_patched_passed.sh` — emit 7-row PASS/FAIL, gate on 0 FAILs
- `lint_adapter.sh` — grep audit of installed skills against the adapter block literals

Evidence tree (`.planning/phases/36-*/evidence/`):
- `reproduction.txt`, `codex_tools.txt` — Plan 01 baseline
- `fork-url.txt`, `fork-install-cmd.sh`, `fork-install-log.txt`, `adapter-lint.txt` — Plan 02
- `control_run1/`, `control_run2/`, `control/` — iterated control runs
- `patched_run1_readonly/`, `patched/` — iterated patched runs (including FAIL.md diagnosis from run 1)

## Recommended next commands (from clear / fresh session)

```bash
cd /Users/ignaciojlizama/raman-wt-codex-adapter

# read the handoff first
cat .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-HANDOFF.md

# add the follow-up phase and route it through full GSD discipline
/gsd-add-phase
/gsd-research-phase 37     # (or whatever number /gsd-add-phase returns)
/gsd-discuss-phase 37
/gsd-plan-phase 37
/gsd-execute-phase 37

# then optionally finish plan 36-04 OR file upstream manually as one combined PR
/gsd-execute-phase 36 --gaps-only
```

## Parallel-session hygiene

- No touches to `.planning/STATE.md` or `.planning/ROADMAP.md` during this session.
- No pushes to `main` in either this repo or the fork.
- All work fenced to `sessions/codex-adapter-fix` branch + `~/src/gsd-fork/` external clone.
- Session-status file written here per Rule P3 (append-only; user aggregates at integration checkpoints).
