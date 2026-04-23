---
phase: 36
status: HALTED — Direction A insufficient; root cause identified
plan_04_status: NOT STARTED — pending follow-up phase
generated: 2026-04-21T03:30:00Z
---

# Phase 36 Handoff — Direction A Insufficient, Root Cause Identified

## State

- Plans 36-01, 36-02, 36-03 executed; 36-04 (upstream bug filing) NOT started.
- Patched-run final score: **6/7** of the RESEARCH §9 criteria (control: 1/7).
- Blocker on the 7th criterion (`spawn_agent invocations ≥ 1`): root cause identified.
- Fork: `github.com/Nacho2027/get-shit-done` branch `fix/codex-spawn-agent` (unpushed).

## Root cause discovered (post-Direction-A)

The Direction A fix patches the **adapter block at the top of each SKILL.md** (~50 lines).
It does NOT touch the workflow files referenced by skills (e.g.,
`~/.codex/get-shit-done/workflows/execute-phase.md`, ~1610 lines).

The installed Codex workflow file contains 9 literal `Task(subagent_type="X", prompt="Y")`
calls and 0 `spawn_agent(...)` calls — i.e., it is the unmodified Claude Code workflow.
Codex has no `Task()` tool, so when it loads the workflow it can either:
- (a) follow the workflow conceptually and degrade to inline execution (what currently
  happens), or
- (b) try to translate `Task(...)` → `spawn_agent(...)` per the SKILL.md adapter NOTICE
  (does not happen reliably — the NOTICE is descriptive, not imperative).

Direction A's USER AUTHORIZATION NOTICE addresses Codex's *gate* on `spawn_agent` but
does not give Codex *imperative* `spawn_agent(...)` calls to execute — so the gate is
moot.

## What Direction A DID achieve (still ship-worthy on its own)

When Codex degrades to inline execution under the patched adapter, it now also follows
the integrity contract baked into Section C of the adapter block. Result: phase
artifacts (manifest.json, EXECUTION.md, atomic `feat(phase01-01):` commits, phase-wide
SUMMARY.md) are produced even when sub-agents are not. The inline-execution failure
mode becomes auditable instead of silent. Plan 28's commit-bombing pattern would not
recur under this adapter.

## Direction B (proposed next phase)

The GSD installer should rewrite the Codex workflow files in addition to the SKILL.md
adapter blocks. Required substitutions in every `~/.codex/get-shit-done/workflows/*.md`:

| Claude syntax | Codex translation |
|---------------|-------------------|
| `Task(subagent_type="X", prompt="Y")` | `spawn_agent(agent_type="X", message="Y")` |
| `Task(model="...")` | (omit — per-role config in `~/.codex/agents/*.toml`) |
| `isolation="worktree"` | (omit — Codex sandbox provides isolation) |
| `Task(...)` followed by `Task(...)` in single message | sequential `spawn_agent`+`wait` pattern |

Plus the integrity contract from Section C, plus the orchestrator STOP rule for
blacklisted skills.

## Required follow-up — do not advance phase 36 to "complete" without this

A new phase (suggested: 36.1 inserted, or a new milestone phase 37) should:

1. **Research** (`/gsd-research-phase`) — confirm the workflow-translation hypothesis
   on this machine (literally edit the installed workflow to use `spawn_agent(...)`
   imperatives, re-run the test project, observe sqlite spawn_count delta). Survey
   what other workflows are similarly affected (e.g., `plan-phase.md`, `verify-work.md`,
   `discuss-phase.md`).
2. **Plan** (`/gsd-plan-phase`) — design the installer change and the test-project
   regression that proves it.
3. **Execute** — extend the fork's generator to also rewrite workflow files; commit
   on a new fork branch (e.g., `fix/codex-workflow-translation`); re-run the
   harness; flip criterion 1 from FAIL to PASS.
4. **Plan 04 from THIS phase** — file ONE upstream bug citing both halves
   (Direction A integrity contract + Direction B workflow translation) for a
   cohesive PR.

## Files / commits left in good order

- All phase 36 commits land on `sessions/codex-adapter-fix` (no `main` push).
- Fork branch `fix/codex-spawn-agent` exists with one commit `9f3d123`
  (`fix(codex-adapter): add USER AUTHORIZATION NOTICE, integrity contract, STOP
  rule for blacklisted orchestrators`). DO NOT push or open a PR upstream until
  Direction B ships in the same branch (or a new combined branch).
- Patched adapter is currently installed in `~/.codex/skills/`. Either leave it
  (it provides the integrity-contract benefits even without Direction B) or
  reinstall stock GSD 1.38.1 via `npx --yes get-shit-done-cc@1.38.1 --codex --global`.

## No-touches

`.planning/STATE.md`, `.planning/ROADMAP.md`, `main` branch, any file outside
`.planning/phases/36-*/` or `/tmp/gsd-codex-adapter-test/`. Parallel-session
Rules P1/P2/P3 respected throughout.
