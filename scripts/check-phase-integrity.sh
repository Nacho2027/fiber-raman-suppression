#!/usr/bin/env bash
# check-phase-integrity.sh — verify GSD execution protocol compliance
# for a given phase.
#
# Detects the violation pattern observed after Codex-on-VM executed
# Phase 28 on 2026-04-20 without proper subagent orchestration:
#   - commit-bombed 7 phases in one `integrate(phase28-34)` commit
#   - no manifest.json in the phase dir
#   - no atomic per-plan commits
#
# Usage:
#   bash scripts/check-phase-integrity.sh <phase-number>
#
# Example:
#   bash scripts/check-phase-integrity.sh 28
#
# Exit codes:
#   0  all checks pass
#   1  one or more checks failed
#   2  usage error

set -euo pipefail

PHASE="${1:-}"
if [ -z "$PHASE" ]; then
    echo "usage: $0 <phase-number>" >&2
    exit 2
fi

PHASE_DIR=$(find .planning/phases -maxdepth 1 -type d -name "${PHASE}-*" 2>/dev/null | head -1)
if [ -z "$PHASE_DIR" ] || [ ! -d "$PHASE_DIR" ]; then
    echo "ERR: phase dir not found for phase $PHASE in .planning/phases/" >&2
    exit 1
fi

echo "=== phase dir: $PHASE_DIR ==="
FAIL=0

# --- Check 1: manifest.json exists ---
if [ -f "$PHASE_DIR/manifest.json" ]; then
    echo "[PASS] manifest.json exists"
else
    echo "[FAIL] manifest.json missing — phase likely not executed via gsd-execute-phase"
    FAIL=$((FAIL+1))
fi

# --- Check 2: per-plan atomic commits ---
PLAN_COUNT=$(find "$PHASE_DIR" -maxdepth 1 -name "${PHASE}-[0-9]*-PLAN.md" 2>/dev/null | wc -l | tr -d ' ')
PLAN_COMMITS=$(git log --all --format="%s" 2>/dev/null \
    | grep -cE "^(feat|fix|docs|chore|test|refactor|style|perf)\(phase${PHASE}-[0-9]+\):" \
    || true)

if [ "$PLAN_COUNT" -eq 0 ]; then
    echo "[WARN] no plan files found in $PHASE_DIR — phase not planned yet (skip commit check)"
elif [ "$PLAN_COMMITS" -ge "$PLAN_COUNT" ]; then
    echo "[PASS] $PLAN_COMMITS atomic per-plan commits found (>= $PLAN_COUNT plans)"
else
    echo "[FAIL] only $PLAN_COMMITS atomic per-plan commits found (expected >= $PLAN_COUNT for $PLAN_COUNT plans)"
    FAIL=$((FAIL+1))
fi

# --- Check 3: no rollup commits spanning multiple phases ---
ROLLUP=$(git log --all --format="%h %s" 2>/dev/null \
    | grep -E "integrate\(phase[0-9]+-[0-9]+\)|integrate\(phase[0-9]+ ?[+,-] ?[0-9]+\)" \
    | head -5 \
    || true)
if [ -n "$ROLLUP" ]; then
    echo "[FAIL] rollup commits detected spanning multiple phases:"
    echo "$ROLLUP" | sed 's/^/        /'
    FAIL=$((FAIL+1))
else
    echo "[PASS] no multi-phase rollup commits in history"
fi

# --- Check 4: SUMMARY references specific plan IDs (not hand-waving) ---
SUMMARY="$PHASE_DIR/${PHASE}-SUMMARY.md"
if [ -f "$SUMMARY" ]; then
    if grep -qE "${PHASE}-[0-9]+-PLAN\.md|plan[- ]?${PHASE}-[0-9]+|Plan ${PHASE}-[0-9]+" "$SUMMARY"; then
        echo "[PASS] SUMMARY.md references specific plan IDs"
    else
        echo "[WARN] SUMMARY.md does not reference specific plan IDs — may be hand-written"
    fi
fi

# --- Check 5: EXECUTION.md mentions gsd-executor or skill invocation ---
EXEC="$PHASE_DIR/${PHASE}-EXECUTION.md"
if [ -f "$EXEC" ]; then
    if grep -qEi "gsd-executor|spawn_agent|Skill\(gsd-|Task\(subagent_type" "$EXEC"; then
        echo "[PASS] EXECUTION.md references subagent/skill invocation"
    else
        echo "[WARN] EXECUTION.md does not reference subagent or skill invocation — may be hand-written by Codex in inline mode"
    fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "OK — phase $PHASE appears to have been executed with GSD discipline."
    exit 0
else
    echo "NOT OK — phase $PHASE has $FAIL integrity violation(s) above."
    echo "Recommendation: re-execute via Claude Code \`/gsd-execute-phase $PHASE\`."
    exit 1
fi
