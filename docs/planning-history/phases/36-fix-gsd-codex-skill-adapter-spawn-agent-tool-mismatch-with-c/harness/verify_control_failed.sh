#!/usr/bin/env bash
# verify_control_failed.sh — emit the FULL 7-row PASS/FAIL table for the
# control run and gate on ≥3 of 7 FAILed (i.e., the unpatched adapter is
# confirmed non-compliant).
#
# Exit codes:
#   0 — control confirmed non-compliant (≥3 fails)
#   1 — control unexpectedly passed too many criteria — investigate

set -euo pipefail

WORKTREE="$(cd "$(dirname "$0")/../../../.." && pwd)"
E="$WORKTREE/.planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/control"

fails=0
passes=0

check() {  # $1=label, $2=condition-string (eval'd)
  if eval "$2" >/dev/null 2>&1; then
    echo "PASS: $1"
    passes=$((passes + 1))
  else
    echo "FAIL: $1"
    fails=$((fails + 1))
  fi
}

# Criterion 1: spawn_agent invocations ≥ 1 (control: expected to FAIL → count 0).
check "spawn_agent invocations >= 1" \
  "spawn=\$(cat '$E/spawn_count.txt' 2>/dev/null | tr -d ' '); test -n \"\$spawn\" && test \"\$spawn\" -ge 1"

# Criterion 2: ≥2 atomic per-plan commits (control: expected to FAIL → rollup).
check "Atomic per-plan commits >= 2" \
  "test \"\$(grep -cE '\\(phase0*1-[0-9]+\\):' '$E/git_log.txt' 2>/dev/null)\" -ge 2"

# Criterion 3: zero rollup commits (control: expected to FAIL → typically one rollup).
check "Rollup commits == 0" \
  "test \"\$(grep -cE 'integrate\\(phase0*1-' '$E/git_log.txt' 2>/dev/null || true)\" -eq 0"

# Criterion 4: manifest.json present (control: expected FAIL).
check "manifest.json present" \
  "grep -q YES '$E/manifest_present.txt' 2>/dev/null"

# Criterion 5: check-phase-integrity.sh exit 0 (control: expected FAIL).
check "check-phase-integrity.sh exit 0" \
  "grep -q 'EXIT: 0' '$E/integrity.txt' 2>/dev/null"

# Criterion 6: SUMMARY references ≥2 plan IDs. Aggregate across all SUMMARY files
# (phase-wide SUMMARY.md + any 01-0X-SUMMARY.md) because Codex may emit either form.
check "SUMMARY references >=2 plan IDs" \
  "matches=0; for s in '$E'/SUMMARY.md '$E'/*SUMMARY.md; do [ -f \"\$s\" ] || continue; n=\$(grep -cE '0*1-0*[0-9]+-?PLAN\\.md|phase0*1-0*[0-9]+' \"\$s\" 2>/dev/null); matches=\$((matches + n)); done; test \"\$matches\" -ge 2"

# Criterion 7: EXECUTION mentions subagent tool.
check "EXECUTION mentions subagent" \
  "exec=\$(ls '$E'/*EXECUTION.md 2>/dev/null | head -1); test -n \"\$exec\" && test \"\$(grep -cE 'spawn_agent|Skill\\(|Task\\(' \"\$exec\")\" -ge 1"

echo "Total: 7, Pass: $passes, Fail: $fails"

# Control is confirmed non-compliant iff ≥3 of 7 FAILED.
# Fewer fails → control unexpectedly passed → SUSPICIOUS (another session patched the adapter?).
if [ "$fails" -ge 3 ]; then
  echo "RESULT: control confirmed non-compliant (>=3 of 7 failed)"
  exit 0
else
  echo "RESULT: control unexpectedly PASSED too many criteria ($fails failures < 3) — investigate"
  exit 1
fi
