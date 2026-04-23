#!/usr/bin/env bash
# verify_patched_passed.sh — emit the FULL 7-row PASS/FAIL table for the
# patched run; require ALL 7 PASS. Exits non-zero on ANY failure → triggers
# Plan 03's STOP rule (FAIL.md + halt; do not advance to Plan 04).

set -euo pipefail

WORKTREE="$(cd "$(dirname "$0")/../../../.." && pwd)"
E="$WORKTREE/.planning/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/patched"

fails=0
passes=0

check() {
  if eval "$2" >/dev/null 2>&1; then
    echo "PASS: $1"
    passes=$((passes + 1))
  else
    echo "FAIL: $1"
    fails=$((fails + 1))
  fi
}

check "spawn_agent invocations >= 1" \
  "spawn=\$(cat '$E/spawn_count.txt' 2>/dev/null | tr -d ' '); test -n \"\$spawn\" && test \"\$spawn\" -ge 1"
check "Atomic per-plan commits >= 2" \
  "test \"\$(grep -cE '\\(phase0*1-[0-9]+\\):' '$E/git_log.txt' 2>/dev/null)\" -ge 2"
check "Rollup commits == 0" \
  "test \"\$(grep -cE 'integrate\\(phase0*1-' '$E/git_log.txt' 2>/dev/null || true)\" -eq 0"
check "manifest.json present" \
  "grep -q YES '$E/manifest_present.txt' 2>/dev/null"
check "check-phase-integrity.sh exit 0" \
  "grep -q 'EXIT: 0' '$E/integrity.txt' 2>/dev/null"
check "SUMMARY references >=2 plan IDs" \
  "matches=0; for s in '$E'/SUMMARY.md '$E'/*SUMMARY.md; do [ -f \"\$s\" ] || continue; n=\$(grep -cE '0*1-0*[0-9]+-?PLAN\\.md|phase0*1-0*[0-9]+' \"\$s\" 2>/dev/null); matches=\$((matches + n)); done; test \"\$matches\" -ge 2"
check "EXECUTION mentions subagent" \
  "exec=\$(ls '$E'/*EXECUTION.md 2>/dev/null | head -1); test -n \"\$exec\" && test \"\$(grep -cE 'spawn_agent|Skill\\(|Task\\(' \"\$exec\")\" -ge 1"

echo "Total: 7, Pass: $passes, Fail: $fails"
test "$fails" -eq 0
