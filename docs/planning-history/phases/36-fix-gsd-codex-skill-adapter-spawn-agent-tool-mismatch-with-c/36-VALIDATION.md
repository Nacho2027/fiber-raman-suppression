---
phase: 36
slug: fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-20
---

# Phase 36 — Validation Strategy

> Per-phase validation contract for the GSD Codex adapter fix. Sourced from
> 36-RESEARCH.md §9 "Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + sqlite3 + git (no new deps) |
| **Config file** | none — throwaway test repo bootstrapped by Wave 0 |
| **Quick run command** | `bash .planning/phases/36-*/harness/run_control.sh` |
| **Full suite command** | `bash .planning/phases/36-*/harness/run_both.sh` (control + patched) |
| **Estimated runtime** | ~8 min per run (5 min for Codex session + evidence capture) |

---

## Sampling Rate

- **After every task commit in this phase:** Run `bash harness/lint_adapter.sh`
  (static grep checks on the fork's rewritten adapter block — no Codex session).
- **After every plan wave:** Run full before/after test protocol.
- **Before `/gsd-verify-work`:** Both control and patched runs must be captured
  on disk (logs, sqlite queries, git history snapshots, integrity-check exit
  codes) under `.planning/phases/36-*/evidence/`.
- **Max feedback latency:** 30s for static checks; full runs are offline.

---

## Per-Task Verification Map

(Filled by the planner. Columns reflect the evidence capture required by
RESEARCH §9's "Compliant output criteria" table.)

| Task ID | Plan | Wave | Source-of-truth | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-----------------|-----------------|-----------|-------------------|-------------|--------|
| 36-01-01 | 01 reproduce | 0 | RESEARCH §2 | symptom still present locally | integration | `bash harness/reproduce.sh > evidence/reproduction.txt` | ❌ W0 | ⬜ pending |
| 36-01-02 | 01 reproduce | 0 | RESEARCH §3 | Codex tool inventory captured | static | `bash harness/capture_tools.sh > evidence/codex_tools.txt` | ❌ W0 | ⬜ pending |
| 36-02-01 | 02 fork+patch | 1 | RESEARCH §6 | adapter block contains "USER AUTHORIZATION NOTICE" | static | `grep -l 'USER AUTHORIZATION NOTICE' $FORK/skills/**/SKILL.md` | ❌ W0 | ⬜ pending |
| 36-02-02 | 02 fork+patch | 1 | RESEARCH §6 | adapter contains atomic-commit clause | static | `grep -l 'phase{PHASE}-{PLAN}' $FORK/skills/**/SKILL.md` | ❌ W0 | ⬜ pending |
| 36-02-03 | 02 fork+patch | 1 | RESEARCH §6 | adapter contains STOP directive for blacklist | static | `grep -l 'adapter is unreliable' $FORK/skills/**/SKILL.md` | ❌ W0 | ⬜ pending |
| 36-03-01 | 03 test | 2 | RESEARCH §9 control | control run non-compliant, evidence captured | integration | `bash harness/run_control.sh && bash harness/verify_control_failed.sh` | ❌ W0 | ⬜ pending |
| 36-03-02 | 03 test | 2 | RESEARCH §9 patched | patched run compliant on all 7 criteria | integration | `bash harness/run_patched.sh && bash harness/verify_patched_passed.sh` | ❌ W0 | ⬜ pending |
| 36-04-01 | 04 upstream | 3 | RESEARCH §7 | bug report drafted, not yet filed | manual | `test -f .planning/phases/36-*/upstream/bug-report.md` | ❌ W0 | ⬜ pending |
| 36-04-02 | 04 upstream | 3 | RESEARCH §7 | bug report filed, issue URL recorded | manual | `grep -E 'https://github.com/gsd-build/get-shit-done/issues/[0-9]+' .planning/sessions/codex-adapter-fix-status.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Task IDs are the planner's provisional starting point; exact IDs are
determined during planning. The verification map must match final plan IDs.*

---

## Wave 0 Requirements

- [ ] `.planning/phases/36-*/harness/reproduce.sh` — runs the sqlite query
      from RESEARCH §2 against the live `~/.codex/logs_*.sqlite` and emits
      `spawn_agent` count + Codex version + skill count.
- [ ] `.planning/phases/36-*/harness/capture_tools.sh` — extracts tool-name
      inventory from the installed Codex binary (strings | grep for tool
      dispatch names).
- [ ] `.planning/phases/36-*/harness/bootstrap_test_project.sh` — creates
      `/tmp/gsd-codex-adapter-test/` with the 2-plan phase scaffold
      described in RESEARCH §9.
- [ ] `.planning/phases/36-*/harness/run_control.sh` — uses currently
      installed GSD 1.38.1 adapter; invokes `$gsd-execute-phase 1` via
      `codex exec`; captures sqlite/git/phase evidence under
      `evidence/control/`.
- [ ] `.planning/phases/36-*/harness/run_patched.sh` — installs fork via
      its `bin/install.js` (or `npm install -g file:$FORK_PATH`), runs the
      same `$gsd-execute-phase 1` invocation, captures evidence under
      `evidence/patched/`.
- [ ] `.planning/phases/36-*/harness/verify_control_failed.sh` and
      `verify_patched_passed.sh` — assertion scripts that check the 7
      criteria in RESEARCH §9's table; exit 0 when their expected state
      is met.
- [ ] `.planning/phases/36-*/harness/lint_adapter.sh` — static grep checks
      on the fork's rewritten `<codex_skill_adapter>` block.

---

## Manual-Only Verifications

| Behavior | Source | Why Manual | Test Instructions |
|----------|--------|------------|-------------------|
| Fork creation on GitHub | RESEARCH §7 | external service, one-time | Create fork of `gsd-build/get-shit-done` under user's account; record URL in evidence/fork-url.txt |
| Bug-report filing | RESEARCH §7 | external service, human-reviewed | Paste issue body (including §9 before/after evidence table) into gsd-build/get-shit-done issues; record issue number in sessions/codex-adapter-fix-status.md |
| `codex exec -p <profile>` auth verification (Open Q A2) | RESEARCH §8 | requires live Codex auth state | Invoke `codex exec -p gsd-planner --ephemeral -C /tmp --skip-git-repo-check 'print hello'`; record output to evidence/codex-exec-auth-check.txt |

---

## Validation Sign-Off

- [ ] All phase tasks have `<automated>` commands or declared Wave 0 dependencies.
- [ ] Sampling continuity: harness-backed verification at end of every plan.
- [ ] Wave 0 covers all throwaway-project scaffolding and assertion scripts.
- [ ] No watch-mode flags; all scripts are one-shot.
- [ ] Feedback latency < 30s for static checks; full runs captured offline.
- [ ] Control run documented as non-compliant (expected baseline).
- [ ] Patched run verified compliant on all 7 RESEARCH §9 criteria.
- [ ] `nyquist_compliant: true` set in frontmatter once planner + checker agree.

**Approval:** pending
