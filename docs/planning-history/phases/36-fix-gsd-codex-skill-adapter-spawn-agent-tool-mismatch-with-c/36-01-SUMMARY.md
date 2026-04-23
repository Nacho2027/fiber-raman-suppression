---
phase: 36
plan: 01
subsystem: gsd-codex-adapter-investigation
tags: [reproduction, tool-inventory, wave-0, baseline-evidence]
wave: 0

requires:
  - Codex CLI v0.121.0 installed at primary nvm path
  - ~/.codex/logs_*.sqlite present with query-able rows
  - ~/.codex/skills/*/SKILL.md present (GSD 1.38.1 installed)

provides:
  - harness/reproduce.sh — baseline reproducer for the spawn_agent=0 symptom
  - harness/capture_tools.sh — Codex v0.121.0 tool-surface extractor
  - harness/bootstrap_test_project.sh — throwaway 2-plan test scaffolder (unexecuted; Plan 03 consumes)
  - evidence/reproduction.txt — captured baseline state on this machine
  - evidence/codex_tools.txt — captured tool-name inventory

affects:
  - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/** (owned namespace)

tech-stack:
  added: [sqlite3 CLI, strings, file, codex CLI subcommands]
  patterns:
    - "drain-the-pipe grep (avoid grep -q under set -o pipefail with multi-MB streams)"
    - "word-boundary substring probe loop for packed-strings tool names"

key-files:
  created:
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/reproduce.sh
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/capture_tools.sh
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/bootstrap_test_project.sh
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/reproduction.txt
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/codex_tools.txt
  modified: []

decisions:
  - "Tool-name detection uses word-boundary substring probes, not anchored whole-line regex. Mach-O strings dumps pack short identifiers into multi-MB concatenated blobs where `^name$` never matches but `(^|\\W)name(\\W|$)` does."
  - "Pipes draining via `> /dev/null` instead of `grep -q` whenever set -o pipefail is combined with a multi-MB stream; grep -q's early-exit behavior turns the upstream printf into a SIGPIPE victim and pipefail rejects the whole pipeline."
  - "Harness STOP condition 1 encoded in reproduce.sh: exit 3 on spawn_agent count > 0 so Plan 02 onward cannot silently patch based on stale research."

metrics:
  tasks_completed: 2
  files_created: 5
  files_modified: 0
  atomic_commits: 1
  commit_hash: a9ec6ee
  plan_start_time: 2026-04-21T02:00:00Z
  plan_completed: 2026-04-21
---

# Phase 36 Plan 01: Wave-0 Harness + Baseline Evidence Summary

Wave-0 reproduction + inventory harness shipped. The spawn_agent=0 symptom is reproduced from live `~/.codex/logs_*.sqlite`, the Codex v0.121.0 tool surface is captured from the installed Mach-O arm64 binary, and the throwaway 2-plan test-project scaffold is written (but unexecuted — Plan 03 owns execution).

## Observed Baseline State

| Measurement | Value | Source |
|---|---|---|
| Host | `/Users/ignaciojlizama/raman-wt-codex-adapter` (sessions/codex-adapter-fix worktree) | `uname` / cwd |
| Codex CLI version | `codex-cli 0.121.0` | `codex --version` |
| GSD installed for Codex | `1.38.1` | `~/.codex/get-shit-done/VERSION` |
| Codex native binary | `~/.nvm/versions/node/v22.3.0/.../codex-darwin-arm64/vendor/aarch64-apple-darwin/codex/codex` (Mach-O 64-bit arm64) | `file` |
| Skills installed | **81** | `ls ~/.codex/skills/*/SKILL.md` |
| Skills referencing `spawn_agent` | **81 / 81** | `grep -l spawn_agent ~/.codex/skills/*/SKILL.md` |
| `logs_2.sqlite` size on disk | ≈17,533 rows | prior research §2 (rows not re-counted here) |
| **spawn_agent invocation count** | **0** | sqlite3 COUNT LIKE `tool_name="spawn_agent"` |
| tool_name values ever observed in logs | only `apply_patch`, `exec_command` | sqlite3 SELECT + extraction |
| `multi_agent` feature flag | `stable / true` | `codex features list` |
| `multi_agent_v2` feature flag | `under development / false` | `codex features list` |

The 0-invocation spawn_agent result exactly reproduces RESEARCH §2. The symptom is live and reproducible on this machine. No STOP condition fired — `reproduce.sh` exited 0 (count = 0 matches research's assumption).

## Codex v0.121.0 Tool Surface (from binary `strings`)

All 14 candidate tool names surfaced in the native binary:

```
apply_patch
close_agent
exec_command
followup_task
list_agents
request_user_input
resume_agent
send_input
send_message
spawn_agent
spawn_agents_on_csv
update_plan
wait
web_search_request
```

This confirms RESEARCH §3 and the Direction-A diagnosis: `spawn_agent` **exists** in the binary as a dispatchable tool. The problem is not "tool missing" — it's the base-instruction gate in the model's prompt ("Only use `spawn_agent` if and only if the user explicitly asks for sub-agents…"). With 0 / 17,533 invocations and 81 / 81 skills referencing it, the model is uniformly refusing to use the tool.

## Anomalies / Deviations

### Deviation 1 (Rule 1 — bug fix in capture_tools.sh)

**Found during:** Task 2 initial run.

**Issue:** My first draft of `capture_tools.sh` used `strings "$BIN" | grep -E '^(spawn_agent|exec_command|...)$'` to extract tool names. On the Mach-O arm64 binary, `strings` packs many short identifiers into multi-KB concatenated blobs (e.g. `hide_spawn_agent_metadatamulti_agent_v2data did not match any variant...`), so only `apply_patch` and `wait` happened to appear as standalone printable-run boundaries. The acceptance criterion required `grep -cE '^(exec_command|spawn_agent|apply_patch)$' ... >= 3` and was returning 1.

**Fix:** Replaced the anchored whole-line regex with a per-candidate word-boundary substring probe:

```bash
for tool in spawn_agent ... ; do
    if printf '%s\n' "$TOOL_DUMP" | grep -E "(^|[^A-Za-z0-9_])${tool}([^A-Za-z0-9_]|$)" > /dev/null; then
        echo "$tool"
    fi
done | sort -u
```

Each found name is emitted on its own line, so the downstream whole-line grep sees what it expects.

### Deviation 2 (Rule 3 — blocking issue)

**Found during:** Task 2 debug of the fix from Deviation 1.

**Issue:** The for-loop was emitting zero output despite standalone-bash tests showing the substring matches. Root cause: `set -o pipefail` + `printf "%s\n" "$TOOL_DUMP"` on a ~5.9 MB dump + `grep -q "pattern"`. `grep -q` exits at first match, which closes the pipe, which sends SIGPIPE to `printf`, which pipefail reports as a pipeline failure — so `if grep -q ...` evaluates to false even though grep itself matched.

**Fix:** Replaced `grep -q ...` with `grep ... > /dev/null` so grep drains the whole stream instead of exiting early. Documented the reason inline in capture_tools.sh.

### No other anomalies

- `reproduce.sh` exit code 0 — STOP condition NOT triggered (count = 0 as research assumed).
- `capture_tools.sh` exit code 0 — binary resolved at the primary nvm path; fallback `find` not exercised.
- `bootstrap_test_project.sh` NOT executed per plan instructions — Plan 03 will consume.

## Artifacts

| Path | Purpose | Size |
|---|---|---|
| `harness/reproduce.sh` | Baseline reproducer with STOP-condition-1 | 99 lines |
| `harness/capture_tools.sh` | Codex tool-surface extractor | 88 lines |
| `harness/bootstrap_test_project.sh` | Throwaway 2-plan test scaffolder | 100 lines |
| `evidence/reproduction.txt` | Captured baseline | 27 lines |
| `evidence/codex_tools.txt` | Captured tool inventory + CLI help + feature flags | 165 lines |

## Commit

`a9ec6ee chore(phase36-01): add wave-0 harness + baseline evidence` — single atomic commit on `sessions/codex-adapter-fix`. No push to main, no touch of any shared namespace.

## Acceptance / Verification

All Task 1 ACs: 8/8 pass. All Task 2 ACs: 9/9 pass. Plan-level verification:

- `test -d .../harness` — pass
- `ls .../harness/ | wc -l` — 3 (expected 3)
- `ls .../evidence/ | wc -l` — 2 (expected ≥ 2)
- `bash -n` all three scripts — pass
- `git log --oneline | grep 'chore(phase36-01)'` — `a9ec6ee`
- Branch `sessions/codex-adapter-fix` (not main) — confirmed

## Forward-Looking Notes for Plan 02+

- The 14-tool inventory in `evidence/codex_tools.txt` confirms Direction A is correct: the fork's adapter rewrite should target `spawn_agent` (exists, gated by prompt). Directions B and C remain fallbacks.
- `reproduce.sh` can be re-run before Plan 02 final acceptance to prove the spawn_agent count is still 0 after a fresh unpatched Codex session (i.e., the symptom is stable, not already drifting).
- `bootstrap_test_project.sh` is ready for Plan 03 — `bash harness/bootstrap_test_project.sh` creates the scaffold as a single idempotent step (`rm -rf` on re-run).

## Self-Check: PASSED

Verification (files exist + commit hash):

- `harness/reproduce.sh` — FOUND
- `harness/capture_tools.sh` — FOUND
- `harness/bootstrap_test_project.sh` — FOUND
- `evidence/reproduction.txt` — FOUND
- `evidence/codex_tools.txt` — FOUND
- Commit `a9ec6ee` — FOUND in `git log --oneline -3`
- Branch `sessions/codex-adapter-fix` — confirmed
- 0 deletions in `a9ec6ee` — confirmed via `git show --stat`
