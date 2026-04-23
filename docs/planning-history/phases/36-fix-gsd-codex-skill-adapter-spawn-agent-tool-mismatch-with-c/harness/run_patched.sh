#!/usr/bin/env bash
# run_patched.sh — Phase 36 Plan 03 patched-run orchestrator.
#
# Re-installs the patched fork DETERMINISTICALLY by sourcing the Plan 02
# evidence/fork-install-cmd.sh artifact (B2 mitigation), then runs a
# post-install sanity check that ≥80 installed skills carry the patched
# USER AUTHORIZATION NOTICE (aborts otherwise). Bootstraps the throwaway
# test project, then invokes `codex exec '$gsd-execute-phase 1'` against
# it. Captures all 7 RESEARCH §9 evidence artefacts under evidence/patched/.
#
# Usage:
#   bash harness/run_patched.sh

set -euo pipefail

WORKTREE="$(cd "$(dirname "$0")/../../../.." && pwd)"
EVIDENCE="$WORKTREE/.planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/patched"

mkdir -p "$EVIDENCE"

echo "=== Phase 36 Plan 03 — PATCHED RUN (forked adapter) ==="
echo "WORKTREE: $WORKTREE"
echo "EVIDENCE: $EVIDENCE"

# Step 1 — B2: Re-install patched adapter via the sourceable artifact.
INSTALL_FILE="$WORKTREE/.planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/fork-install-cmd.sh"
test -s "$INSTALL_FILE" || { echo "ABORT: $INSTALL_FILE missing or empty — run Plan 02 Task 3 first" >&2; exit 2; }
# shellcheck disable=SC1090
# Deterministic recovery: source .planning/phases/36-*/evidence/fork-install-cmd.sh
source "$INSTALL_FILE"
test -n "${INSTALL_CMD:-}" || { echo "ABORT: INSTALL_CMD not defined after sourcing $INSTALL_FILE" >&2; exit 2; }

echo "--- Re-installing patched fork: $INSTALL_CMD ---"
eval "$INSTALL_CMD" 2>&1 | tee "$EVIDENCE/install.log"

# Step 2 — Post-install sanity: ≥80 skills must carry NOTICE.
# Note: grep -l exits 1 if no matches; tolerate under set -o pipefail.
notice_count="$( { grep -l 'USER AUTHORIZATION NOTICE' ~/.codex/skills/*/SKILL.md 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [ "$notice_count" -lt 80 ]; then
  echo "ABORT: patched adapter did not install to ≥80 skills (only $notice_count) — cannot claim patched run" \
    | tee "$EVIDENCE/ABORTED.txt" >&2
  exit 2
fi
echo "SANITY: $notice_count skills carry NOTICE after patched re-install" >> "$EVIDENCE/install.log"

# Step 3 — Bootstrap throwaway test project (idempotent).
bash "$WORKTREE/.planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/bootstrap_test_project.sh"

# Step 4 — Record window + version.
FIVE_MIN_AGO=$(($(date +%s) - 60))
{
  echo "START: $(date -u +%FT%TZ)"
  echo "FIVE_MIN_AGO_EPOCH: $FIVE_MIN_AGO"
  echo "codex --version:"
  codex --version
  echo "GSD VERSION:"
  cat ~/.codex/get-shit-done/VERSION
} > "$EVIDENCE/window.txt"

# Step 5 — Invoke `codex exec`.
echo "--- Invoking codex exec ---"
set +e
codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox \
           -C /tmp/gsd-codex-adapter-test '$gsd-execute-phase 1' 2>&1 | tee "$EVIDENCE/run.log"
codex_exit=${PIPESTATUS[0]}
set -e
echo "CODEX_EXIT: $codex_exit" >> "$EVIDENCE/run.log"

# Step 6 — Capture the 7 criteria.
echo "--- Capturing evidence ---"

# Criterion 1: spawn_agent invocation count.
spawn_total=0
for db in ~/.codex/logs_*.sqlite; do
  [ -f "$db" ] || continue
  count=$(sqlite3 "$db" "SELECT COUNT(*) FROM logs WHERE feedback_log_body LIKE '%tool_name=\"spawn_agent\"%' AND ts > ${FIVE_MIN_AGO}000;" 2>/dev/null || echo 0)
  spawn_total=$((spawn_total + count))
done
echo "$spawn_total" > "$EVIDENCE/spawn_count.txt"

# Criterion 2/3: git log.
( cd /tmp/gsd-codex-adapter-test && git log --oneline ) > "$EVIDENCE/git_log.txt" 2>&1 || true

# Criterion 4: phase-dir listing + manifest.json presence.
ls /tmp/gsd-codex-adapter-test/.planning/phases/01-*/ > "$EVIDENCE/phasedir_listing.txt" 2>&1 || true
if compgen -G "/tmp/gsd-codex-adapter-test/.planning/phases/01-*/manifest.json" > /dev/null; then
  echo YES > "$EVIDENCE/manifest_present.txt"
else
  echo NO > "$EVIDENCE/manifest_present.txt"
fi

# Criterion 6/7: copy SUMMARY/EXECUTION files.
if compgen -G "/tmp/gsd-codex-adapter-test/.planning/phases/01-*/*SUMMARY.md" > /dev/null; then
  cp /tmp/gsd-codex-adapter-test/.planning/phases/01-*/*SUMMARY.md "$EVIDENCE/" 2>/dev/null || true
else
  echo "NO SUMMARY" > "$EVIDENCE/NO_SUMMARY"
fi
if compgen -G "/tmp/gsd-codex-adapter-test/.planning/phases/01-*/*EXECUTION.md" > /dev/null; then
  cp /tmp/gsd-codex-adapter-test/.planning/phases/01-*/*EXECUTION.md "$EVIDENCE/" 2>/dev/null || true
else
  echo "NO EXECUTION" > "$EVIDENCE/NO_EXECUTION"
fi

# Criterion 5: check-phase-integrity.sh exit.
(
  cd /tmp/gsd-codex-adapter-test
  # Pass "01" to match the test project's phase dir prefix (01-two-plan-phase).
  bash "$WORKTREE/scripts/check-phase-integrity.sh" 01
  echo "EXIT: $?"
) > "$EVIDENCE/integrity.txt" 2>&1 || true

# Step 7 — One-line summary.
echo "=== PATCHED RUN COMPLETE ==="
echo "spawn_count=$(cat "$EVIDENCE/spawn_count.txt"), manifest=$(cat "$EVIDENCE/manifest_present.txt"), codex_exit=$codex_exit"
