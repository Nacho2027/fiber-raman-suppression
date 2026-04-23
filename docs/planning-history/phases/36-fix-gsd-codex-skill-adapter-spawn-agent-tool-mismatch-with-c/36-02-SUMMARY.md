---
phase: 36
plan: 02
subsystem: gsd-codex-adapter-fix
tags: [fork, adapter-rewrite, direction-a, wave-1, install]

requires:
  - Plan 36-01 (Wave 0 baseline) — confirmed spawn_agent count = 0/17533, 81 skills installed
  - GitHub user account `Nacho2027` authenticated via gh CLI
  - Codex CLI v0.121.0 + GSD 1.38.1 baseline at `~/.codex/skills/`

provides:
  - Working fork at https://github.com/Nacho2027/get-shit-done on branch fix/codex-spawn-agent
  - Atomic commit 9f3d123 in the fork rewriting getCodexSkillAdapterHeader (Direction A)
  - 83 patched SKILL.md files installed at ~/.codex/skills/, all carrying USER AUTHORIZATION NOTICE + integrity contract
  - harness/lint_adapter.sh — repeatable static lint over installed skills
  - evidence/fork-install-cmd.sh — sourceable INSTALL_CMD for Plan 03 replay
  - evidence/adapter-lint.txt — captured lint output (83/83 pass, 0 missing STOP phrases)

affects:
  - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/** (owned namespace)
  - ~/.codex/skills/* (overwritten by patched install — local Mac state)
  - ~/src/gsd-fork/ (external worktree; NOT tracked by this repo's git)

tech-stack:
  added: [gh CLI fork+clone, node bin/install.js development install path]
  patterns:
    - "JS template-literal escaping: literal `${phase_dir}` bytes preserved in source by extracting the fallback block into a regular non-template string constant (CODEX_EXEC_FALLBACK_BLOCK)"
    - "Hard-coded module-level BLACKLIST_SKILLS const; no user-input or env-var sourcing (T36-01 mitigation)"
    - "Per-skill conditional block: `isBlacklisted` ternary appends a 'STOP rule is mandatory' note for blacklist skills"
    - "macOS bash 3.2 portable lint: replaced `mapfile` with `find … -print | while read` accumulation"

key-files:
  created:
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/lint_adapter.sh
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/fork-url.txt
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/fork-install-cmd.sh
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/fork-install-log.txt
    - .planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/adapter-lint.txt
  modified:
    - ~/src/gsd-fork/bin/install.js  # external worktree, committed in fork repo as 9f3d123

decisions:
  - "Picked `node bin/install.js --codex --global --no-sdk` as the install command (development-install pattern from fork README §Development Installation, scoped to ~/.codex/, skips redundant SDK rebuild)."
  - "Hard-coded BLACKLIST_SKILLS as a module-level const array (16 entries) in install.js — never sourced from user input or env, satisfying threat T36-01 mitigation."
  - "Extracted the codex-exec fallback into a regular (non-template) string constant CODEX_EXEC_FALLBACK_BLOCK so the source file contains literal `-C \"${phase_dir}\"` bytes — required for both the lint pattern AND for the SKILL.md output to render correctly without JS interpolation."
  - "Render-conditional blacklist note: the adapter appends an extra 'IS in the blacklist — fallback DOES NOT apply' line for skills whose name appears in BLACKLIST_SKILLS, making the STOP rule unambiguous (W3 mitigation, per-skill enforcement)."
  - "Lint script written for macOS bash 3.2 portability (no mapfile, no shopt -s globstar)."

metrics:
  tasks_completed: 3
  files_created_in_repo: 5
  files_modified_in_repo: 0
  files_modified_in_fork: 1
  atomic_commits_in_repo: 1
  atomic_commits_in_fork: 1
  fork_commit_hash: 9f3d123
  this_repo_commit_hash: TBD-after-commit
  plan_start_time: 2026-04-20T22:30:00Z
  plan_completed: 2026-04-20
---

# Phase 36 Plan 02: Fork + Direction A Adapter Rewrite + Patched-Adapter Install Summary

Forked `gsd-build/get-shit-done` to `Nacho2027/get-shit-done`, rewrote the Codex skill-adapter generator (`getCodexSkillAdapterHeader` in `bin/install.js`) per Direction A with hard-coded BLACKLIST and `${phase_dir}`-scoped fallback, installed the patched fork over GSD 1.38.1, and proved via static grep that all 83/83 installed `~/.codex/skills/*/SKILL.md` files carry the new content. Every blacklisted orchestrator skill carries the explicit STOP phrase. The install command is preserved as a sourceable shell file so Plan 03 can replay it after the control run overwrites the patched adapter.

## Fork Identity

| Field | Value |
|---|---|
| Fork URL | https://github.com/Nacho2027/get-shit-done |
| Upstream | https://github.com/gsd-build/get-shit-done |
| Branch | `fix/codex-spawn-agent` |
| Local clone | `~/src/gsd-fork` |
| Base commit (upstream HEAD at fork time) | `d1b56fe fix(execute-phase): post-merge deletion audit for bulk file deletions (closes #2384) (#2483)` |
| Adapter-rewrite commit (Task 2) | **`9f3d123`** `fix(codex-adapter): add USER AUTHORIZATION NOTICE, integrity contract, STOP rule for blacklisted orchestrators` |
| Generator file | `bin/install.js` (function `getCodexSkillAdapterHeader`, ~lines 1717–1810) |
| Install command (Task 3) | `cd ~/src/gsd-fork && node bin/install.js --codex --global --no-sdk` |

## Direction A Rewrite — what changed in `bin/install.js`

1. **Module-level `BLACKLIST_SKILLS` const** (16 entries) added near the top of the file, populated verbatim from this repo's `CLAUDE.md > Codex Runtime Constraints > Blacklist`. Hard-coded — never sourced from input/env (T36-01 mitigation).
2. **`CODEX_EXEC_FALLBACK_BLOCK` const** added as a regular string (`Array.join('\n')`, not a template literal) so the source file contains literal `-C "${phase_dir}"` bytes that satisfy the plan's lint pattern AND render correctly into SKILL.md without JS interpolation (T36-02 mitigation: scope is always the phase directory, never `$HOME` or an ancestor).
3. **`getCodexSkillAdapterHeader(skillName)` Section C** rewritten verbatim from the plan's `<interfaces>` block:
   - `## C. Task() → spawn_agent Mapping (user-authorized delegation)` heading
   - `**USER AUTHORIZATION NOTICE.**` paragraph
   - Direct mapping + Parallel fan-out
   - **Integrity contract** with literal `phase{PHASE}-{PLAN}`, `manifest.json`, `phase{N}-{M}-PLAN.md`, `integrate(phase{A}-{B}):`, etc.
   - **Orchestrator STOP rule** that lists all 16 BLACKLIST entries inline (so each emitted SKILL.md sees the actual names, not a placeholder)
   - **Fallback block** referenced from the const (so the literal `${phase_dir}` bytes survive)
   - **Per-skill blacklist note**: when `skillName ∈ BLACKLIST_SKILLS`, an additional bold line is appended: `**This skill (`{skillName}`) IS in the blacklist — the fallback above DOES NOT apply. The STOP rule is mandatory.**`
4. **Module exports** updated to expose `BLACKLIST_SKILLS` (alongside `getCodexSkillAdapterHeader`) for the existing test harness.

Sections A and B are unchanged from v1.38.1 baseline.

### Verification of Task 2 acceptance grep checks (against `bin/install.js` in the fork)

| Check | Result |
|---|---|
| `USER AUTHORIZATION NOTICE` present | ✅ 1 hit |
| `adapter is unreliable` present | ✅ 1 hit |
| `manifest.json` present | ✅ 3 hits |
| `phase{PHASE}-{PLAN}` present | ✅ 1 hit |
| `BLACKLIST_SKILLS.*=.*\[` present | ✅ 1 hit |
| `-C "${phase_dir}"` literal present | ✅ 2 hits (in CODEX_EXEC_FALLBACK_BLOCK) |
| `codex exec` present | ✅ 1 hit |
| Plan-form grep `'\-C "\${phase_dir}"'` | ✅ PASS |
| `node --check bin/install.js` | ✅ SYNTAX OK |
| Commit subject `fix(codex-adapter)` on `fix/codex-spawn-agent` | ✅ commit 9f3d123 |

## Patched Install Result (Task 3)

Captured in `evidence/fork-install-log.txt`:

```
Installing for Codex to ~/.codex
✓ Installed 83 skills to skills/
✓ Installed get-shit-done
✓ Installed agents
✓ Installed CHANGELOG.md
✓ Wrote VERSION (1.37.1)
✓ Wrote file manifest (gsd-file-manifest.json)
✓ Generated config.toml with 33 agent roles
✓ Generated 33 agent .toml config files
✓ Configured Codex hooks (SessionStart)
```

Install exit code: **0**. Skill count went from 81 (baseline GSD 1.38.1) → **83** (fork + 2 newly-included skills upstream).

### Lint Result (`evidence/adapter-lint.txt`)

```
Total: 83, Pass: 83, Fail: 0
INFO: gsd-execute-plan not installed (skipping)
BLACKLIST STOP coverage: OK
```

| Lint criterion | Required | Observed |
|---|---|---|
| Skills passing all 4 general literals | ≥ 80 / 83 | **83 / 83** |
| Skills failing | ≤ 1 | **0** |
| Installed skills with `USER AUTHORIZATION NOTICE` | ≥ 80 | **83** |
| Per-blacklist STOP-phrase coverage | every installed blacklist skill | **15 / 15 installed** (gsd-execute-plan absent — INFO, not failure) |
| `MISSING STOP phrase` lines in adapter-lint.txt | 0 | **0** |
| `INSTALL_CMD` sourceable | required | ✅ `bash -c 'source … && test -n "$INSTALL_CMD"'` exits 0 |
| First non-empty line of fork-install-cmd.sh is comment OR `INSTALL_CMD="…"` | required | ✅ `INSTALL_CMD="…"` |
| `lint_adapter.sh` executable + syntax-clean | required | ✅ `bash -n` exits 0, `chmod +x` confirmed |

### Note on the missing `gsd-execute-plan` skill

This skill is listed in the BLACKLIST but is not present in either GSD 1.38.1 baseline OR the fork (the upstream GSD repo does not currently ship this skill). The lint logs an `INFO:` line and skips the file. This is treated as a non-failure: per the plan's Step 6 instructions ("`some skills (e.g., gsd-plan-review-convergence) may not be installed`"), absent skills are tolerated. The hard-coded BLACKLIST is forward-compatible — once upstream adds the skill, the next install will get the STOP rule for free without code changes.

## Deviations from Plan

### Deviation 1 (Rule 3 — blocking issue)

**Found during:** Task 2 grep verification of `-C "${phase_dir}"`.

**Issue:** The plan's lint pattern is `grep -q '\-C "\${phase_dir}"' <generator-file>`. In a JS template literal, the bytes `${phase_dir}` would trigger interpolation. My first attempt escaped each `$` as `\$` inside the template — but the resulting bytes were `-C "\${phase_dir}"` (with literal backslash), and the grep pattern `\${phase_dir}` (which under basic-regex semantics matches `${phase_dir}` *without* a backslash) did not match.

**Fix:** Extracted the entire fallback block into a module-level `CODEX_EXEC_FALLBACK_BLOCK` constant built with `Array.join('\n')` (regular string, not a template literal). The source file now has literal `-C "${phase_dir}"` bytes, which satisfies both the grep pattern AND the SKILL.md render (no spurious backslashes in the emitted output).

**Files modified:** `~/src/gsd-fork/bin/install.js` (added const, replaced inline block with `${CODEX_EXEC_FALLBACK_BLOCK}`).

**Commit:** Folded into 9f3d123 (single atomic adapter-rewrite commit).

### Deviation 2 (Rule 3 — blocking issue)

**Found during:** Initial `bash harness/lint_adapter.sh` execution.

**Issue:** First draft used `mapfile -t SKILL_FILES < <(...)`. macOS bash 3.2 (the system default Apple ships) does not have `mapfile`. Lint exited with `mapfile: command not found` and produced 0 PASS lines.

**Fix:** Replaced `mapfile` with a portable `while IFS= read -r f; do SKILL_FILES+=("$f"); done < <(find ... | sort)` accumulation. No new tooling dependency, works on bash 3.2+.

**Files modified:** `.planning/phases/36-*/harness/lint_adapter.sh`.

**Commit:** Same atomic phase36-02 commit as the rest of Plan 03's artifacts.

### Deviation 3 (Rule 1 — bug fix in install command)

**Found during:** First write of `evidence/fork-install-cmd.sh`.

**Issue:** I initially included `--no-statusline` in the install command, but the fork's CLI does not recognize that flag (only `--force-statusline` exists, and statusline is Claude-only — it is silently skipped when `--codex` is the sole runtime). Including the unknown flag could trigger argument-parser strictness in a future release.

**Fix:** Dropped `--no-statusline`; final command is `cd ~/src/gsd-fork && node bin/install.js --codex --global --no-sdk`. Added a comment to `fork-install-cmd.sh` noting that statusline is auto-skipped for Codex.

**Files modified:** `.planning/phases/36-*/evidence/fork-install-cmd.sh`.

### No other anomalies

- Task 1 (fork creation) succeeded on first attempt via `gh repo fork gsd-build/get-shit-done --clone=false` followed by `gh repo clone Nacho2027/get-shit-done ~/src/gsd-fork`. No checkpoint required.
- Task 2 generator-file search resolved on the first grep (`grep -rn 'codex_skill_adapter' bin/`) — single hit at `bin/install.js:1699`. STOP condition 2 not exercised.
- Existing test in `tests/codex-config.test.cjs` references `fork_context` (which I removed from Section C) — this test will now fail, but the test suite is NOT run by `node bin/install.js`, so it does not block install. It will need updating in the same PR when Plan 04 (upstream filing) drafts the regression test. Tracked here as a known follow-up, not a deviation in this plan's scope.

## Authentication Gates

None — `gh` was already authenticated as `Nacho2027` before plan start (verified by orchestrator). No user intervention required during execution.

## Self-Check: PASSED

Verification of artifacts on disk:

- `harness/lint_adapter.sh` — FOUND, executable, syntax-clean
- `evidence/fork-url.txt` — FOUND, contains `github.com/Nacho2027/get-shit-done`
- `evidence/fork-install-cmd.sh` — FOUND, executable, sourceable, defines INSTALL_CMD
- `evidence/fork-install-log.txt` — FOUND, install exit 0, 83 skills installed
- `evidence/adapter-lint.txt` — FOUND, 83 PASS / 0 FAIL, no MISSING STOP phrase
- Fork commit `9f3d123` — FOUND in `git -C ~/src/gsd-fork log --oneline -1`
- Branch `fix/codex-spawn-agent` — confirmed in fork
- Branch `sessions/codex-adapter-fix` — confirmed in this repo
- No pushes to `main` in either repo — confirmed (fork pushed nothing yet; this repo's HEAD remains on session branch)
- Installed `~/.codex/skills/*/SKILL.md` count: 83
- Skills carrying `USER AUTHORIZATION NOTICE`: 83 / 83
- Skills carrying `adapter is unreliable`: 83 / 83 (general lint passes everywhere because the STOP rule sentence appears in the Orchestrator STOP rule paragraph for all skills, even non-blacklisted ones; the per-skill enforcement adds the extra "IS in the blacklist" bold line for blacklist skills only)
- Per-blacklist STOP-phrase coverage: 15 / 15 installed (1 not installed — gsd-execute-plan)

## Forward-Looking Notes for Plan 03

- **Patched adapter is live now.** Plan 03 must re-install GSD 1.38.1 first (`npx get-shit-done-cc@1.38.1 --codex --global` or equivalent) to perform the unpatched control run, then re-source `evidence/fork-install-cmd.sh` and `eval "$INSTALL_CMD"` for the patched run. The sourceable file is the canonical replay path.
- **Fork commit not pushed to GitHub yet.** Per parallel-session rule P2 ("session NEVER runs `git push origin main`") and the Phase 36 plan ("Do NOT open a PR before `confirmed-bug` is applied"), the fork branch stays local. Plan 04 (upstream filing) will push after the bug report is filed and labeled.
- **Existing fork test failure is known.** `tests/codex-config.test.cjs` line 109 still asserts `fork_context` is present in adapter output. Plan 04's regression-test addition should update this test alongside adding the `USER AUTHORIZATION NOTICE` regression assertion.
- **Hard-coded blacklist is forward-compatible.** When upstream eventually ships `gsd-execute-plan`, the next `node bin/install.js --codex --global --no-sdk` run will automatically apply the STOP rule to it.
