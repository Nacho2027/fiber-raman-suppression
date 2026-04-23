# Phase 36: Fix GSD Codex Skill Adapter — Context

**Gathered:** 2026-04-20
**Status:** Ready for planning
**Source:** User-authored session prompt (treated as PRD)

<domain>
## Phase Boundary

Investigate, patch, and file upstream a bug in GSD's Codex skill adapter. Codex's adapter
in every `get-shit-done/skills/*/SKILL.md` at the `<codex_skill_adapter>` section instructs
Codex to call `spawn_agent(agent_type="X", message="Y")` when translating Claude Code's
`Task(...)` calls — but Codex CLI v0.121.0 does not expose `spawn_agent` as a callable tool.
The result is silent inline fallback execution, which broke Phase 28 execution (single
`integrate(phase28-34)` commit spanning 7 phases, no manifest.json, no atomic per-plan
commits, hand-written SUMMARY/EXECUTION).

In scope for this phase:
1. Reproduce the tool-name mismatch on a fresh Codex install to verify the root cause.
2. Audit Codex CLI v0.121.0's actual callable tool surface.
3. Catalogue every GSD skill whose `<codex_skill_adapter>` block references `spawn_agent`.
4. Select one of three fix directions and draft the replacement adapter content.
5. Fork `gsd-build/get-shit-done`, implement the fix on a feature branch in that fork.
6. Run a control (unpatched) test and a patched test on a throwaway 2-plan phase; collect
   tool-call traces from `~/.codex/logs_*.sqlite`, git log, and phase manifest evidence.
7. If the patched adapter produces compliant output, file a bug report upstream with the
   evidence; do NOT open a PR until maintainer applies the `approved-feature` label.
8. Write `.planning/sessions/codex-adapter-fix-status.md` (≤500 words) summarizing root
   cause, fix, evidence, upstream status, and integration gotchas.

Out of scope:
- Touching anything in this research repo's source code (Julia, scripts, docs).
- Modifying the already-committed `scripts/check-phase-integrity.sh` or the Codex Runtime
  Constraints section of `CLAUDE.md`.
- Merging to `main` — all commits land on `sessions/codex-adapter-fix` for user integration.
</domain>

<decisions>
## Implementation Decisions (LOCKED)

### Git hygiene
- All phase work happens in worktree `~/raman-wt-codex-adapter` on branch
  `sessions/codex-adapter-fix`.
- Adapter modifications live in a GitHub fork of `gsd-build/get-shit-done` under the user's
  account, on a `fix/codex-spawn-agent` branch. The fork must be created before any code
  change; do NOT commit adapter edits to this research repo.
- NEVER push to `main` from this session. The user integrates at a checkpoint.

### File namespace (owned by this phase)
- `.planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/**`
- `.planning/notes/codex-adapter-fix-*.md`
- `.planning/sessions/codex-adapter-fix-status.md`
- The fork repo (outside this working tree)

Do NOT modify: `scripts/check-phase-integrity.sh`, the Codex Runtime Constraints section of
`CLAUDE.md`, or any file outside the namespace above.

### Research-first methodology
- **Reproduce before fixing.** The planner must include a reproduction step that runs a
  fresh Codex session against a trivial `$gsd-quick` task and queries
  `~/.codex/logs_*.sqlite` for `tool_name`. The reported 0-invocation count for
  `spawn_agent` must be reproduced on this machine before any adapter edits.
- **Audit Codex tool surface.** The planner must include a task that enumerates every
  tool Codex CLI v0.121.0 actually exposes (grep the installed npm package, `codex --help`
  subcommands, or a live Codex REPL session asking the model its tool list). The adapter
  fix must target a tool that genuinely exists in v0.121.0.
- **Catalogue affected skills.** The planner must produce an inventory of every
  `<codex_skill_adapter>` section across `get-shit-done/skills/*/SKILL.md` that references
  `spawn_agent`. Count and pattern (single spawn, parallel fan-out, chained plan-check).

### Fix direction options (one will be selected during planning, based on research)
1. Sequential inline with enforced output contracts (atomic per-plan commits, `manifest.json`,
   STOP directive on nested chains).
2. Replace `spawn_agent` with `spawn_agents_on_csv` for homogeneous batches (Codex's
   documented subagent API per developers.openai.com/codex/subagents).
3. Shell out via `codex exec` for heterogeneous workers (spawning a child Codex session with
   a fresh task scope).

The plan must pick ONE direction with written rationale, grounded in the research findings.

### Testing requirements (BLOCKING before upstream filing)
- Patched adapter must be installed locally from the fork (install path determined from the
  fork's `bin/install.js` or equivalent).
- A throwaway test project with a 2-plan phase must be created.
- A fresh Codex session must invoke `$gsd-execute-phase` on that test project with the
  patched adapter active.
- Evidence collected for BOTH patched and control (unpatched) runs:
  - Tool-call trace from `~/.codex/logs_*.sqlite` showing what tools actually fired.
  - Git log of resulting commits (patched: must be 2 atomic per-plan commits; control:
    expected to be a single rollup).
  - Presence/absence of `manifest.json` in the phase directory.
  - Shape of `SUMMARY.md` and `EXECUTION.md` (skill-generated vs hand-written).
- Evidence goes into phase `VERIFICATION.md`.
- If the patched adapter does NOT produce compliant output, STOP and return to planning for
  a different direction. After 2 failed iterations, escalate to user.

### Upstream filing gate
- CONTRIBUTING.md of `gsd-build/get-shit-done` has TWO label gates (clarified during
  research in §7 of 36-RESEARCH.md — the original session prompt mentioned only
  `approved-feature`, but empirical fetch of live CONTRIBUTING.md found both):
  - **Bug PRs** require the `confirmed-bug` label before maintainers accept code.
  - **Feature PRs** require the `approved-feature` label before maintainers accept code.
  - Since this phase files a BUG, the operative gate is `confirmed-bug`.
- File a BUG REPORT (issue) first (not a PR) containing:
  - Reproduction (sqlite tool-call query returns 0 for `spawn_agent` on this Mac).
  - Root-cause text from the Codex binary base-instructions (the user-authorization gate).
  - Affected-skill inventory (RESEARCH §4).
  - Before/after test evidence (commit structure, manifest presence, tool-call trace).
  - Proposed fix direction A described in prose (no diffs yet).
  - Offer to open a PR once maintainer applies `confirmed-bug`.
- Do NOT open a PR before `confirmed-bug` is applied to the issue.
- At filing time, Plan 04 must curl the live CONTRIBUTING.md to confirm the label names
  have not changed; if they have, the plan records the actual label and updates the
  acceptance criteria rather than silently proceeding.

### Escape hatches (STOP conditions)
- `/gsd-plan-phase` or `/gsd-execute-phase` itself malfunctions on this machine → STOP,
  memo the user; this is the bug under investigation.
- Patched adapter fails to produce atomic commits after 2 iterations → STOP, escalate for
  a different direction.
- Upstream repo has changed significantly since 1.38.1 (e.g., 1.39.0 shipped and obsoleted
  this) → STOP, re-read the CHANGELOG before filing.
- NEVER file a bug report without test evidence in hand.

### Claude's discretion
- Choice of throwaway test project structure (empty repo with `.planning/` + a minimal
  ROADMAP entry; actual plan content can be trivial no-op file creations).
- Exact format of the phase's RESEARCH.md — free-form, covering the four research axes.
- Naming of the fork's feature branch (suggested `fix/codex-spawn-agent`).
- Commit granularity inside the fix branch, provided each commit is atomic and messages
  follow `type(scope): description`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### This repo (context only — do NOT modify the marked files)
- `CLAUDE.md` — sections "GSD Workflow Enforcement", "Codex Runtime Constraints", "Parallel
  Session Operation Protocol" (rules P1–P7). Already committed; source of truth for
  operating rules.
- `scripts/check-phase-integrity.sh` — already-committed audit script; do NOT modify.
  Provides the integrity checks the patched adapter must make pass.
- `.planning/notes/session-prompts-only.md` — multi-session operating principles.
- `.planning/phases/28-*/` — the commit-bombed phase whose artifacts motivate this fix.

### External (read before planning)
- `https://developers.openai.com/codex/subagents` — official Codex subagent docs.
  Documents `spawn_agents_on_csv` (batch homogeneous). Nothing about heterogeneous
  single-spawn.
- `github.com/openai/codex/issues/3898` — community thread confirming no heterogeneous
  single-spawn API in Codex CLI.
- `github.com/gsd-build/get-shit-done/pull/791` — the merged March PR that introduced the
  `spawn_agent` mapping. Investigate what tool it targeted.
- `github.com/gsd-build/get-shit-done/blob/main/CONTRIBUTING.md` — governs whether a PR or
  issue is appropriate first.
- `~/.codex/logs_2.sqlite` — local Codex telemetry; the reproduction query is
  `SELECT COUNT(*) FROM logs WHERE feedback_log_body LIKE '%tool_name="spawn_agent"%';`.

</canonical_refs>

<specifics>
## Specific Facts & Evidence

- Reproducer query:
  `sqlite3 ~/.codex/logs_2.sqlite "SELECT COUNT(*) FROM logs WHERE feedback_log_body LIKE '%tool_name=\"spawn_agent\"%';"`
  → returned 0 over 21+ MB of session history on the VM. Only `exec_command` was
  ever invoked (25 calls).
- Codex CLI version under test: **v0.121.0**.
- Reported upstream issues already searched: no existing coverage of the specific
  tool-name mismatch. Issue #863 is a different symptom (approval-stuck). Issue #2402
  fixes a runtime-aware gate, not the missing tool. Issue #860 assumed #791 worked.
- CONTRIBUTING guard: PRs are auto-closed unless labeled `approved-feature`. File an issue
  first.

</specifics>

<deferred>
## Deferred / Out of Scope

- Any physics or simulation changes in this research repo.
- Broader overhaul of the Codex adapter semantics (e.g., redesigning `<codex_skill_adapter>`
  block structure) — this phase only fixes the tool-name mismatch and the resulting
  protocol violations.
- Upstream PR opening — gated on maintainer response to the bug report.

</deferred>

---

*Phase: 36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c*
*Context gathered: 2026-04-20 via /gsd-plan-phase (PRD-equivalent from session prompt)*
