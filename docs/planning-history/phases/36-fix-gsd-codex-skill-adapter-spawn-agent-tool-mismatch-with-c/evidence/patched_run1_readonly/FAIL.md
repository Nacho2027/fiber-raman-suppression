---
plan: 36-03
status: failed
verdict: harness_defect
generated: 2026-04-21T02:45:00Z
---

# Patched Run FAIL — Harness Defect, Adapter Behavior Indeterminate

## Verdict

`verify_patched_passed.sh` exits 1 (6/7 criteria FAIL, identical failure surface to the control run). However, the run.log reveals this is a **harness defect** — the patched adapter was read by Codex but could not be exercised because the `codex exec` invocation ran in Codex's default read-only sandbox against a test project missing `.planning/STATE.md`. No spawn_agent invocation was ever attempted.

Plan 04 MUST NOT start until the harness is corrected and a re-run either proves compliance (A) or proves a genuine adapter defect (B).

## Per-Criterion Table

| # | Criterion | Expected | Observed | Source |
|---|-----------|----------|----------|--------|
| 1 | spawn_agent invocations | ≥ 1 | 0 | `evidence/patched/spawn_count.txt` |
| 2 | Atomic per-plan commits | ≥ 2 | 0 | `evidence/patched/git_log.txt` (only `chore: seed test project`) |
| 3 | Rollup commits | 0 | 0 | `evidence/patched/git_log.txt` (vacuous pass) |
| 4 | manifest.json present | YES | NO | `evidence/patched/manifest_present.txt` |
| 5 | check-phase-integrity.sh exit | 0 | 1 (`phase dir not found for phase 1`) | `evidence/patched/integrity.txt` |
| 6 | SUMMARY references ≥2 plan IDs | ≥ 2 | n/a (`NO_SUMMARY`) | `evidence/patched/NO_SUMMARY` |
| 7 | EXECUTION mentions subagent | ≥ 1 | n/a (`NO_EXECUTION`) | `evidence/patched/NO_EXECUTION` |

Result: **1 PASS, 6 FAIL**, identical to control.

## Root-Cause Analysis

`evidence/patched/run.log` (tail) shows Codex read the patched skill and explicitly refused to execute because:

> - `.planning/STATE.md` is missing, while the workflow expects phase-state writes during execution.
> - This session is mounted `read-only`, so I cannot create `A.txt`, `B.txt`, summaries, manifest/state files, or git commits.

Two independent harness defects:

1. **Read-only sandbox.** The literal command from RESEARCH §9 —
   `codex exec --skip-git-repo-check -C /tmp/gsd-codex-adapter-test '$gsd-execute-phase 1'` —
   does not pass `--sandbox workspace-write` (or `--dangerously-bypass-approvals-and-sandbox`),
   so Codex defaults to read-only and refuses file/commit mutations before it would ever reach
   `spawn_agent`. This affects **both** the control and patched runs equally, which is why the
   failure tables are identical.

2. **Missing `.planning/STATE.md` seed.** `harness/bootstrap_test_project.sh` creates
   `ROADMAP.md`, `01-CONTEXT.md`, and the two PLAN files, but does **not** create `STATE.md`.
   `gsd-execute-phase` performs a `state.begin-phase` write in its init step; without the file,
   the skill aborts before Wave 1.

Both defects are in the Plan 01 / Plan 03 harness code, not in the Direction A adapter. The
adapter text was loaded verbatim into `~/.codex/skills/gsd-execute-phase/SKILL.md` (Plan 02
evidence: 83/83 skills carry `USER AUTHORIZATION NOTICE`, 15/15 installed blacklist skills carry
the STOP phrase).

## What We Can and Cannot Conclude

**Can conclude:**
- The patched skill content is correctly installed (USER AUTHORIZATION NOTICE literal, STOP
  phrase literal, and all 5 lint checks pass — see `evidence/adapter-lint.txt`).
- Codex reads the adapter block (`run.log` shows Codex quoting Section C text while explaining
  its refusal).

**Cannot conclude** (pending harness fix + re-run):
- Whether Codex would actually invoke `spawn_agent` under the patched adapter in a writable
  sandbox. The current evidence is consistent with either:
  - (A) Patched adapter works — Codex would invoke spawn_agent once sandbox/STATE issues are
    resolved, and the 7-criterion table would flip to all-PASS.
  - (B) Patched adapter is insufficient — even with a writable sandbox Codex would still fall
    back to inline text dumping (the symptom from Plan 01's baseline).

Direction A cannot be either validated or rejected without a corrected harness.

## Required Harness Corrections Before Re-Run

Edit `harness/run_control.sh` and `harness/run_patched.sh`:
```diff
-codex exec --skip-git-repo-check -C /tmp/gsd-codex-adapter-test '$gsd-execute-phase 1'
+codex exec --skip-git-repo-check --sandbox workspace-write \
+           -C /tmp/gsd-codex-adapter-test '$gsd-execute-phase 1'
```

Edit `harness/bootstrap_test_project.sh` to seed `.planning/STATE.md`:
```bash
cat > .planning/STATE.md <<'SMD'
---
status: planning
phase: 01
---
# State
- Phase 01 pending execution.
SMD
```

Re-run both scripts; re-run both verify_*.sh; re-evaluate.

## STOP

Per plan 36-03 Step 4: Plan 04 does NOT start. This phase halts until the user either
(a) authorizes the harness correction + re-run in a follow-up plan, or (b) accepts this
as the final verdict and re-scopes Plan 04 (e.g., "file a meta-bug: Codex skill adapter
has multiple defects, demonstrated by the failed harness run that revealed both sandbox
and STATE.md issues").
