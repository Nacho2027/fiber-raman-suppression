#!/usr/bin/env bash
# run_control.sh — Phase 36 Plan 03 control-run orchestrator.
#
# Reinstalls GSD 1.38.1 (the unpatched baseline), runs a post-install sanity
# check (W5 — aborts if any installed skill still carries the patched
# USER AUTHORIZATION NOTICE), bootstraps the throwaway test project, then
# invokes `codex exec '$gsd-execute-phase 1'` against it. Captures all 7
# RESEARCH §9 evidence artefacts under evidence/control/.
#
# Usage:
#   bash harness/run_control.sh

set -euo pipefail

WORKTREE="$(cd "$(dirname "$0")/../../../.." && pwd)"
EVIDENCE="$WORKTREE/.planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/control"

mkdir -p "$EVIDENCE"

echo "=== Phase 36 Plan 03 — CONTROL RUN (GSD 1.38.1 unpatched) ==="
echo "WORKTREE: $WORKTREE"
echo "EVIDENCE: $EVIDENCE"

# Step 1 — Reinstall GSD 1.38.1 (unpatched baseline)
echo "--- Reinstalling GSD 1.38.1 for Codex ---"
npx --yes get-shit-done-cc@1.38.1 --codex --global 2>&1 | tee "$EVIDENCE/install.log"

# Step 2 — W5 post-install sanity check: 0 skills should carry the NOTICE.
# Note: grep -l exits 1 if no matches; use `|| true` to tolerate that under set -o pipefail.
notice_count="$( { grep -l 'USER AUTHORIZATION NOTICE' ~/.codex/skills/*/SKILL.md 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [ "$notice_count" -ne 0 ]; then
  echo "ABORT: 1.38.1 install did NOT replace patched adapter ($notice_count skills still carry NOTICE) — control evidence would be fabricated" \
    | tee "$EVIDENCE/ABORTED.txt" >&2
  exit 2
fi
echo "SANITY: 0 skills carry NOTICE after 1.38.1 install — control adapter is live" >> "$EVIDENCE/install.log"

# Step 3 — Bootstrap throwaway test project (idempotent: rm -rf inside).
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

# Criterion 1: spawn_agent invocation count (sum across all logs_*.sqlite databases).
spawn_total=0
for db in ~/.codex/logs_*.sqlite; do
  [ -f "$db" ] || continue
  count=$(sqlite3 "$db" "SELECT COUNT(*) FROM logs WHERE feedback_log_body LIKE '%tool_name=\"spawn_agent\"%' AND ts > ${FIVE_MIN_AGO}000;" 2>/dev/null || echo 0)
  spawn_total=$((spawn_total + count))
done
echo "$spawn_total" > "$EVIDENCE/spawn_count.txt"

# Criterion 2/3: git log of the test project.
( cd /tmp/gsd-codex-adapter-test && git log --oneline ) > "$EVIDENCE/git_log.txt" 2>&1 || true

# Criterion 4: phase-dir listing + manifest.json presence.
ls /tmp/gsd-codex-adapter-test/.planning/phases/01-*/ > "$EVIDENCE/phasedir_listing.txt" 2>&1 || true
if compgen -G "/tmp/gsd-codex-adapter-test/.planning/phases/01-*/manifest.json" > /dev/null; then
  echo YES > "$EVIDENCE/manifest_present.txt"
else
  echo NO > "$EVIDENCE/manifest_present.txt"
fi

# Criterion 6/7: copy SUMMARY/EXECUTION files for grepping.
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

# Criterion 5: check-phase-integrity.sh exit (against the test project's phase 1).
(
  cd /tmp/gsd-codex-adapter-test
  # Pass "01" to match the test project's phase dir prefix (01-two-plan-phase).
  bash "$WORKTREE/scripts/check-phase-integrity.sh" 01
  echo "EXIT: $?"
) > "$EVIDENCE/integrity.txt" 2>&1 || true

# Step 7 — One-line summary.
echo "=== CONTROL RUN COMPLETE ==="
echo "spawn_count=$(cat "$EVIDENCE/spawn_count.txt"), manifest=$(cat "$EVIDENCE/manifest_present.txt"), codex_exit=$codex_exit"
