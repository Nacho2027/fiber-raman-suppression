# Phase 36: Fix GSD Codex Skill Adapter — Research

**Researched:** 2026-04-20
**Domain:** Agent-runtime skill adapter, Codex CLI v0.121.0 tool surface, GSD 1.38.1
**Confidence:** HIGH (reproduced locally, binary-inspected, upstream-verified)

## User Constraints (from CONTEXT.md)

### Locked Decisions
- All work in worktree `~/raman-wt-codex-adapter` on branch `sessions/codex-adapter-fix`.
- Adapter edits live in a fork of `gsd-build/get-shit-done` on `fix/codex-spawn-agent`. Fork NOT yet created — research only.
- Never push to `main`.
- File namespace owned: `.planning/phases/36-*/**`, `.planning/notes/codex-adapter-fix-*.md`, `.planning/sessions/codex-adapter-fix-status.md`, and the fork.
- Reproduce before fixing; audit Codex tool surface; catalogue affected skills; pick ONE of three fix directions with written rationale; test control + patched on throwaway project; file bug report FIRST (PR only after maintainer signal).

### Claude's Discretion
- Throwaway test project structure, RESEARCH.md format, fork branch naming, commit granularity in the fix branch.

### Deferred Ideas (OUT OF SCOPE)
- Physics/simulation edits in this research repo.
- Broader Codex adapter redesign beyond the tool-name mismatch.
- PR opening before `confirmed-bug` label applied.

---

## 1. Executive Summary

**Root cause is subtler than "tool does not exist."** The string `spawn_agent` is compiled into the Codex v0.121.0 native binary, the `multi_agent` feature flag is `stable` and `true` by default, and 33 `[agents.gsd-*]` entries are correctly wired in `~/.codex/config.toml`. The tool *is* exposed to the model — but Codex's built-in base-instructions contain:

> *"Only use `spawn_agent` if and only if the user explicitly asks for sub-agents, delegation, or parallel agent work. Requests for depth, thoroughness, research, investigation, or detailed codebase analysis do not count as permission to spawn."*

GSD's boilerplate `<codex_skill_adapter>` block (present verbatim in all 81 skills) tells the model "Task() → spawn_agent(agent_type=..., message=...)" but does NOT establish that the USER has explicitly authorized delegation. The model falls back to inline `exec_command`, producing silent protocol violations — no atomic per-plan commits, no `manifest.json`, hand-written `SUMMARY/EXECUTION`. **`spawn_agent` invocation count = 0 / 17,533 log rows.** The March PR #791 that added the mapping never verified runtime behavior.

**Recommended fix direction: A (sequential inline with enforced output contracts), with a per-skill `<codex_skill_adapter>` rewrite that (a) explicitly authorizes `spawn_agent` as the user-mandated protocol for orchestrator skills, (b) falls back to strict sequential `codex exec` child-spawning when `spawn_agent` still refuses, and (c) bakes the integrity contract (atomic commits, manifest, STOP on nested) into the skill instructions so even inline-fallback produces audit-compliant output.**

Evidence: binary strings, full sqlite log sweep, upstream CONTRIBUTING.md, and PR #791 body.

---

## 2. Reproduction Report

| Item | Observed |
|---|---|
| Host | Local Mac `/Users/ignaciojlizama` |
| Codex CLI version | `codex-cli 0.121.0` (canonical for this investigation) |
| Codex install path | `~/.nvm/versions/node/v22.3.0/lib/node_modules/@openai/codex` → native `codex-darwin-arm64/vendor/aarch64-apple-darwin/codex/codex` (Mach-O arm64) |
| GSD version installed for Codex | `1.38.1` (from `~/.codex/get-shit-done/VERSION`) |
| `~/.codex/logs_2.sqlite` total rows | **17,533** |
| `spawn_agent` invocation count | **0** (query: `COUNT(*) WHERE feedback_log_body LIKE '%tool_name="spawn_agent"%'`) |
| Tool invocations observed | `exec_command`, `apply_patch` (the only two tool_name values in all logs) |
| Skills installed (`~/.codex/skills/*/SKILL.md`) | **81** |
| Skills with `spawn_agent` reference in adapter | **81 / 81** (identical boilerplate block) |
| Agents registered in `~/.codex/config.toml` | **33** (verified: `[agents.gsd-*]` blocks with `config_file` pointing to `~/.codex/agents/gsd-*.toml`) |
| `multi_agent` feature flag state | `stable / true` (verified via `codex features list`) |
| `enable_fanout` feature flag | `under development / false` |

Surprise: the adapter is installed *correctly*. The agent TOMLs exist, `config.toml` wires them, and the feature flag is on. The failure mode is *prompt-level refusal*, not a missing tool. This reframes the fix: it is about persuading the model to actually emit `spawn_agent`, not about replacing the tool name.

---

## 3. Codex CLI v0.121.0 Tool Inventory

Extracted from the native binary strings and confirmed against `codex --help` subcommands.

### Tools callable by the agent model (from binary)
| Tool | Status | Notes |
|---|---|---|
| `exec_command` | Active (heavily used) | Shell execution with sandbox |
| `apply_patch` | Active | Edit files via freeform patch |
| `spawn_agent` | **Exists, heavily disincentivized** | Binary contains dispatch code + base-instruction gate |
| `spawn_agents_on_csv` | Exists (homogeneous batch) | Official Codex subagent API per developers.openai.com/codex/subagents |
| `wait` | Exists (multi_agents handler) | Waits on spawned agent IDs |
| `close_agent` | Exists (multi_agents handler) | Cleanup |
| `send_input` / `send_message` | Exists (multi_agents handler) | Mid-run messaging |
| `resume_agent`, `followup_task`, `list_agents` | Exist under `multi_agents_v2` | Gated by `multi_agent_v2` (under development, false) |
| `update_plan` | Active | Plan-tracking tool |
| `request_user_input` | Active | User questions (GSD's `AskUserQuestion` maps here) |
| `web_search_request` | Active | Web search |

### CLI subcommands (from `codex --help`)
| Subcommand | Relevance |
|---|---|
| `codex exec [PROMPT]` | **Highly relevant for Direction C**: `-C <DIR>`, `--skip-git-repo-check`, `--json`, `--output-schema <FILE>`, `--output-last-message <FILE>`, `--ephemeral`, `--sandbox <mode>`, `-m <model>` |
| `codex mcp-server` | Start Codex itself as MCP server (stdio) |
| `codex resume --last` | Resume session |
| `codex features {list,enable,disable}` | Feature-flag management |

### Divergence from docs
- developers.openai.com/codex/subagents documents ONLY `spawn_agents_on_csv`. The binary implements `spawn_agent` (heterogeneous, single-spawn, full multi_agents handler suite) **and** `spawn_agents_on_csv` but publicly documents only the latter. This is why upstream issue #860 (independent port attempt) concluded the API was missing: the docs are incomplete.
- `spawn_agent`'s model-facing description says "Spawns an agent to work on the specified task … the agent will have canonical task name `/root/task1/task_3`" — confirming heterogeneous, nestable, single-spawn semantics.

---

## 4. Affected GSD Skills Inventory

All 81 skills share the same `<codex_skill_adapter>` boilerplate (verified by grep + visual diff on `gsd-manager`, `gsd-plan-phase`, `gsd-execute-phase`, `gsd-autonomous`). Severity below reflects the blast radius of a silent-inline fallback.

| Skill | Adapter pattern | Severity | Why |
|---|---|---|---|
| `gsd-plan-phase` | single spawn (planner) + parallel fan-out (researchers) | **Critical** | Missing plan-check ⇒ bad plans merged |
| `gsd-execute-phase` | single spawn (executor) + sequential spawn (verifier) + commit protocol | **Critical** | Source of Phase 28 commit-bomb |
| `gsd-autonomous` | chained orchestrator (plan → execute → verify → review) | **Critical** | Worst-case: seven phases rolled up |
| `gsd-plan-review-convergence` | nested orchestrator (plan-checker + revision loop) | **Critical** | Present in install? Not found locally — user should verify after next GSD install |
| `gsd-verify-work` | single spawn (verifier) | High | Silent inline = bogus verification |
| `gsd-code-review` / `gsd-code-review-fix` | single spawn (reviewer) + per-finding fixers | High | Silent inline = fake review |
| `gsd-audit-{fix,milestone,uat}` | single spawn (auditor) | High | Same as above |
| `gsd-ship`, `gsd-review`, `gsd-debug` | mixed | High | Protocol-dependent |
| `gsd-ingest-docs`, `gsd-new-milestone`, `gsd-new-project` | nested orchestrator | Medium | Planning scaffolds only |
| All other skills (≈ 60) | single spawn or none | Low | Mostly single-agent work, low protocol fan-out |

**CLAUDE.md blacklist (this repo) already lists the critical / high rows** — the blacklist is a correct workaround but does not fix the tool. The adapter rewrite must preserve the blacklist's spirit: skills that orchestrate MUST fail loud, not silently.

---

## 5. Fix Direction Comparison

Scoring 1–5 (5 = best).

| Direction | Feasibility | Fidelity | Risk | Upstream-acceptability | Total |
|---|---|---|---|---|---|
| **A. Sequential inline with enforced contracts + explicit `spawn_agent` authorization** | 5 | 4 | 3 | 5 | **17** |
| **B. Replace with `spawn_agents_on_csv`** | 3 | 2 | 4 | 3 | 12 |
| **C. Shell out via `codex exec`** | 4 | 5 | 2 | 2 | 13 |

### Direction A — chosen

The real bug is not a missing tool but a prompt-level gate. The fix is to:
1. **Rewrite the adapter's Section C** to establish, unambiguously, that the user has opted into delegation by invoking a GSD orchestrator skill. Language: *"Invoking a GSD orchestrator skill (`$gsd-plan-phase`, `$gsd-execute-phase`, `$gsd-autonomous`, `$gsd-verify-work`) constitutes explicit user authorization to delegate via `spawn_agent`. Skills listed as orchestrators in the GSD blacklist MUST spawn named subagents; refusing to spawn is a protocol violation."*
2. **Bake the integrity contract into the adapter** so even if the model still falls back to inline execution (e.g., a model variant trained with stricter gating), it produces audit-compliant output: atomic per-plan commits (`{type}(phase{N}-{M}): ...`), `manifest.json` with plan IDs and commit SHAs, no cross-phase rollup commits. Use the `scripts/check-phase-integrity.sh` spec as the contract.
3. **Add a STOP directive** for nested orchestrators: if a skill is in the blacklist and `spawn_agent` still refuses, the skill must emit the exact phrase from CLAUDE.md ("This task requires the `[name]` skill, which depends on named subagent orchestration. Codex's adapter is unreliable for this. Please re-run in Claude Code.") and terminate — no fabricated artifacts.
4. **Optional Direction C fallback wrapped in A**: for orchestrators, the adapter may additionally list `codex exec -C <dir> --skip-git-repo-check --json --output-last-message <file> --ephemeral "<scoped prompt>"` as a shell-level fallback when `spawn_agent` refuses. This is heterogeneous by construction (each `codex exec` is a fresh session with its own agent role via `-p <profile>`). Cons: double token cost, child has no access to parent memory.

### Why not B
`spawn_agents_on_csv` is homogeneous — the worker prompt is templated once and applied to each CSV row. GSD orchestrators are heterogeneous (planner + plan-checker + researcher + executor + verifier are distinct agent types with distinct toolsets). Forcing CSV mode collapses those roles into one prompt, destroying GSD's audit trail and agent-role separation.

### Why not C alone
`codex exec` is a full process-level shell-out: every child spawns a fresh Codex session, losing the parent's conversation context, memory, and approval state. Token cost is ~2× (parent + child both boot the session instructions). It is useful as a FALLBACK when `spawn_agent` refuses, but as the primary mechanism it changes the execution model too radically for upstream to accept as a targeted bug fix.

---

## 6. Draft Replacement `<codex_skill_adapter>` Block (Direction A)

Concrete skeleton — the planner will refine placeholders.

```markdown
<codex_skill_adapter>
## A. Skill Invocation
- This skill is invoked by mentioning `${SKILL_NAME}`.
- Treat all user text after `${SKILL_NAME}` as `{{GSD_ARGS}}`.
- If no arguments are present, treat `{{GSD_ARGS}}` as empty.

## B. AskUserQuestion → request_user_input Mapping
[unchanged from v1.38.1]

## C. Task() → spawn_agent Mapping (user-authorized delegation)

**USER AUTHORIZATION NOTICE.** Invocation of this GSD skill constitutes an
explicit request by the user for sub-agent delegation. The `spawn_agent` tool's
usage gate ("only when the user explicitly asks for sub-agents") is SATISFIED
for every `Task(...)` call in this skill's workflow. Do not second-guess this
authorization.

Direct mapping:
- `Task(subagent_type="X", prompt="Y")` → `spawn_agent(agent_type="X", message="Y")`
- `Task(model="...")` → omit (per-role config applies)

Parallel fan-out:
- Spawn N agents → collect IDs → `wait(ids)` until all complete → `close_agent(id)` for each

Integrity contract (ENFORCED EVEN IF SPAWN IS REFUSED):
- Every plan must receive its own commit: subject `{type}(phase{PHASE}-{PLAN}): {desc}`
  (types: feat|fix|docs|chore|test|refactor|style|perf). NO rollup commits.
- Phase dir must contain `manifest.json` listing `plan_id → commit_sha` pairs.
- `SUMMARY.md` must reference specific plan IDs (`phase{N}-{M}-PLAN.md`).
- `EXECUTION.md` must reference `spawn_agent` or `Skill(gsd-...)` calls — not
  hand-written prose.
- NO commit subjects matching `integrate(phase{A}-{B}):` (rollups) or
  `integrate(phase{A}+{B}):`.

Orchestrator STOP rule (for ${BLACKLIST_SKILLS}):
- If `spawn_agent` is refused by the runtime for any reason, emit:
  > "This task requires the `${SKILL_NAME}` skill, which depends on named
  > subagent orchestration. Codex's adapter is unreliable for this. Please
  > re-run in Claude Code."
  and HALT. Do NOT fabricate SUMMARY.md, EXECUTION.md, or manifest.json.

Fallback (optional, when allowed by skill):
- If `spawn_agent` is refused and this skill is NOT in `${BLACKLIST_SKILLS}`,
  shell out via `exec_command`:
  `codex exec -C "${phase_dir}" --skip-git-repo-check --json \
   --output-last-message "${phase_dir}/agent_out.json" --ephemeral \
   -p "${agent_type}" "${prompt}"`
  and parse `agent_out.json` as the agent result.

Result parsing:
- Look for markers: `CHECKPOINT`, `PLAN COMPLETE`, `SUMMARY`, `VERIFICATION PASSED`.
- After each agent returns, `close_agent(id)`.
</codex_skill_adapter>
```

The planner must split the generator `bin/lib/convertClaudeAgentToCodexAgent.*` (or wherever GSD emits this block — to be located in the fork) so that orchestrator skills receive the STOP rule with `${BLACKLIST_SKILLS}` populated from the CLAUDE.md Codex Runtime Constraints list.

---

## 7. Upstream Status

| Item | Finding |
|---|---|
| CONTRIBUTING.md rule | Bug flow: file issue → wait for `confirmed-bug` label → write regression test → open PR with Fix template. `approved-feature` gates feature PRs specifically. |
| Existing issue covering this specific mismatch | **None.** Searched `spawn_agent`, `codex adapter`, `codex inline`. Related but non-overlapping: #860 (parity gaps — closed), #863 (approval stuck — closed), #2256 (model_overrides — closed `confirmed-bug`). |
| PR #791 (the introducer) | Merged 2026-02-28 by @trek-e. Test plan verified installer emits the adapter but did NOT verify runtime tool invocation. This is where the silent failure mode slipped through. |
| CHANGELOG up through v1.38.1 (published 2026-04-19) | No mention of adapter changes, tool-name fixes, or spawn_agent behavior. v1.38.1 is a non-related hotfix. |
| Release cadence | Shipping every 2–7 days; v1.39.x could land mid-investigation. Planner should add a "re-check CHANGELOG before filing" step. |

**Go/no-go:** GO to file a bug report after the patched-adapter test produces compliant output. Do NOT open a PR until maintainer applies `confirmed-bug`. The issue body should include: sqlite reproducer (this file's Section 2), binary-extracted base-instruction text ("Only use spawn_agent if and only if…"), skill-inventory table (Section 4), before/after test evidence (Section 9), and the Direction A rationale.

---

## 8. Open Questions for Planning

1. **Where exactly is the adapter generator in the fork?** Phase 36 needs to edit either a template file or a TS/JS generator (likely `bin/lib/convertClaudeAgentToCodexAgent.*` per PR #791). Planner must open the fork and grep before writing tasks.
2. **Does `codex exec` inherit the parent's ChatGPT auth and approval policy?** If the child needs `codex login` independently, the Direction-A fallback path adds setup friction. Needs a 2-minute empirical check during plan execution.
3. **Should the STOP rule be per-skill metadata (new frontmatter field `orchestrator: true`) or a static list in the adapter?** Static list is simpler; frontmatter is more maintainable. User preference needed.
4. **Does the fix need to cover OpenCode too?** Issue #2256 groups OpenCode with Codex; the adapter may be emitted identically. Out of scope for this phase unless the user says otherwise.
5. **Regression test shape upstream requires.** A shell-based test that invokes the installer, greps the emitted adapter for "USER AUTHORIZATION NOTICE", and asserts the STOP rule for blacklisted skills is likely the minimum. A full end-to-end test requires a Codex session, which GSD's CI may not have.

---

## 9. Validation Architecture

### Test framework
| Property | Value |
|---|---|
| Harness | Bash + sqlite3 + git (no new deps) |
| Throwaway project | `/tmp/gsd-codex-adapter-test/` — empty git repo, `.planning/` scaffold, `ROADMAP.md` listing one phase with two trivial plans (each plan: "create file `X.txt` with content `Y`") |
| Control | v1.38.1 adapter (unpatched), Codex session invoking `$gsd-execute-phase` |
| Patched | Fork with Direction A adapter installed locally via `npm install -g file:$FORK_PATH` or the fork's `bin/install.js` |
| Codex version | pinned to v0.121.0 (documented at run time) |
| Evidence capture | tool-call sqlite query, `git log` of resulting commits, `ls` of phase dir, content of SUMMARY/EXECUTION |

### Before/after test protocol

```bash
# --- Setup ---
mkdir -p /tmp/gsd-codex-adapter-test && cd /tmp/gsd-codex-adapter-test
git init -q && mkdir -p .planning/phases/01-two-plan-phase
# populate ROADMAP.md, 01-CONTEXT.md, 01-01-PLAN.md, 01-02-PLAN.md
git add -A && git commit -q -m "chore: seed test project"

# --- Control (baseline unpatched) ---
# install GSD 1.38.1 for Codex (if not already)
codex exec --skip-git-repo-check -C /tmp/gsd-codex-adapter-test \
  '$gsd-execute-phase 1' 2>&1 | tee /tmp/control_run.log
# capture evidence
sqlite3 ~/.codex/logs_2.sqlite \
  "SELECT COUNT(*) FROM logs WHERE feedback_log_body LIKE '%tool_name=\"spawn_agent\"%' AND ts > $(date +%s -d '5 min ago')000" \
  > /tmp/control_spawn_count.txt
git log --oneline > /tmp/control_commits.txt
ls .planning/phases/01-*/ > /tmp/control_phasedir.txt
bash "$RESEARCH_REPO/scripts/check-phase-integrity.sh" 1 > /tmp/control_integrity.txt 2>&1

# --- Patched (fork with Direction A) ---
cd $FORK_PATH && npm install -g .
cd /tmp/gsd-codex-adapter-test && git reset --hard HEAD
codex exec --skip-git-repo-check -C /tmp/gsd-codex-adapter-test \
  '$gsd-execute-phase 1' 2>&1 | tee /tmp/patched_run.log
# capture same evidence as control into /tmp/patched_*.txt
```

### Compliant output criteria (patched run must satisfy ALL)

| Criterion | Measurement | Pass |
|---|---|---|
| `spawn_agent` invocations | sqlite COUNT during the 5-min window | ≥ 1 |
| Atomic per-plan commits | `git log --oneline | grep -cE '\(phase1-[0-9]+\):'` | ≥ 2 |
| Rollup commits | `git log | grep -c 'integrate(phase1-'` | 0 |
| `manifest.json` present | `test -f .planning/phases/01-*/manifest.json` | TRUE |
| `check-phase-integrity.sh 1` exit code | script exits | 0 |
| SUMMARY references plan IDs | grep `01-0[0-9]-PLAN\.md` in SUMMARY | ≥ 2 hits |
| EXECUTION mentions subagent | grep `spawn_agent\|Skill(\|Task(` | ≥ 1 hit |

### Non-compliant (control run expected to match)

- `spawn_agent` count = 0, rollup commit present or single commit for both plans, no `manifest.json`, `check-phase-integrity.sh` exit 1, SUMMARY/EXECUTION hand-written prose.

### STOP gates
- Patched run fails criteria → return to planning for one revision round.
- Two revision rounds fail → escalate to user; do NOT file upstream.

---

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|---|---|---|
| A1 | `gsd-plan-review-convergence` is a real skill in the blacklist (CLAUDE.md lists it but not found in `~/.codex/skills/`) | §4 | Low — verify on next `npx get-shit-done-cc@latest install` |
| A2 | `codex exec -p <profile>` accepts an agent name as profile identifier | §5 fallback | Medium — needs 2-min empirical check; may require `-c agents.X.enabled=true` override |
| A3 | The adapter generator lives in `bin/lib/convertClaudeAgentToCodexAgent.*` | §8 Q1 | Low — grep of the fork resolves in minutes |
| A4 | Codex's base-instruction gate applies uniformly across all `gpt-5.x-codex` models | §5 | Medium — binary showed the instruction under every model's `base_instructions`; confirmed across variants |
| A5 | Throwaway test project's `$gsd-execute-phase` invocation will exercise the full orchestrator path (not fall through to `$gsd-fast`) | §9 | Low — the skill dispatches based on the `$` prefix literal |

All other claims are VERIFIED (binary strings, sqlite query, github api, webfetch) or CITED (developers.openai.com/codex/subagents, upstream issue bodies).

---

## Sources

### Primary (HIGH)
- Codex native binary: `~/.nvm/versions/node/v22.3.0/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/codex/codex` (strings analysis)
- `~/.codex/logs_2.sqlite` (17,533 rows, queried 2026-04-20)
- `~/.codex/config.toml`, `~/.codex/agents/*.toml`, `~/.codex/skills/*/SKILL.md` (81 skills)
- `~/.codex/get-shit-done/VERSION` → `1.38.1`
- `codex --help`, `codex exec --help`, `codex features list`

### Secondary (HIGH, CITED)
- developers.openai.com/codex/subagents — `spawn_agents_on_csv` API
- github.com/gsd-build/get-shit-done/pull/791 — introduction of the mapping
- github.com/gsd-build/get-shit-done/blob/main/CONTRIBUTING.md — bug-report workflow, `confirmed-bug` label gate
- github.com/gsd-build/get-shit-done — issues #860, #863, #2256, #1983 (all checked; none overlap)
- github.com/gsd-build/get-shit-done/releases — v1.37 through v1.38.1 CHANGELOG

### Tertiary
- Local repo `scripts/check-phase-integrity.sh` — integrity contract spec
- Local repo `CLAUDE.md` "Codex Runtime Constraints" — the in-project workaround (blacklist) that this fix must preserve

---

## Metadata

- Standard stack: HIGH — directly inspected live installation
- Architecture: HIGH — adapter pattern identical across 81/81 skills, binary dispatch confirmed
- Pitfalls: HIGH — base-instruction gate is exact root cause, reproduced

**Research date:** 2026-04-20
**Valid until:** 2026-05-04 (14 days; Codex ships weekly, v1.39.x could change adapter shape)

## RESEARCH COMPLETE
