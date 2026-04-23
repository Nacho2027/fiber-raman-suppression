#!/usr/bin/env bash
# reproduce.sh — Phase 36 Wave 0 reproduction harness.
#
# Reproduces the spawn_agent=0 symptom on this machine by querying
# every ~/.codex/logs_*.sqlite for invocation counts of the
# spawn_agent tool. Also captures Codex CLI version, GSD version,
# and skill counts for context.
#
# Caller usage:
#     bash harness/reproduce.sh > evidence/reproduction.txt 2>&1
#
# STOP condition (encoded below):
#     If the total spawn_agent COUNT across all logs_*.sqlite > 0,
#     research's 0-invocation assumption is invalidated. The script
#     emits a STOP message to stderr and exits 3 so plan execution
#     halts before any adapter edits.

set -euo pipefail

echo "=== Phase 36 reproduction harness ==="
echo "Run timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

echo "--- Codex CLI version ---"
if command -v codex >/dev/null 2>&1; then
    codex --version 2>&1 || echo "codex --version exited non-zero"
else
    echo "codex CLI NOT ON PATH"
fi
echo

echo "--- GSD VERSION file ---"
if [ -f "$HOME/.codex/get-shit-done/VERSION" ]; then
    cat "$HOME/.codex/get-shit-done/VERSION"
else
    echo "VERSION file missing"
fi
echo

echo "--- Skill inventory ---"
SKILL_COUNT=0
if compgen -G "$HOME/.codex/skills/*/SKILL.md" >/dev/null; then
    SKILL_COUNT=$(ls "$HOME"/.codex/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
fi
echo "skills installed: ${SKILL_COUNT}"

SPAWN_REF_COUNT=0
if compgen -G "$HOME/.codex/skills/*/SKILL.md" >/dev/null; then
    SPAWN_REF_COUNT=$(grep -l 'spawn_agent' "$HOME"/.codex/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
fi
echo "skills referencing spawn_agent: ${SPAWN_REF_COUNT}"
echo

echo "--- spawn_agent invocation counts across all logs_*.sqlite ---"
TOTAL_SPAWN_COUNT=0
FIRST_DB=""
DB_FOUND=0
for db in "$HOME"/.codex/logs_*.sqlite; do
    [ -e "$db" ] || continue
    DB_FOUND=1
    [ -z "$FIRST_DB" ] && FIRST_DB="$db"
    # Literal pattern: tool_name="spawn_agent" — single-quoted so the shell
    # passes the backslash-escaped double quotes verbatim into sqlite3.
    COUNT=$(sqlite3 "$db" "SELECT COUNT(*) FROM logs WHERE feedback_log_body LIKE '%tool_name=\"spawn_agent\"%';" 2>/dev/null || echo "0")
    echo "  ${db}: ${COUNT}"
    TOTAL_SPAWN_COUNT=$((TOTAL_SPAWN_COUNT + COUNT))
done
if [ "$DB_FOUND" -eq 0 ]; then
    echo "  (no logs_*.sqlite files found under ~/.codex)"
fi
echo
echo "TOTAL spawn_agent invocations: ${TOTAL_SPAWN_COUNT}"
echo

echo "--- Distinct tool_name values ever observed in first db ---"
if [ -n "$FIRST_DB" ]; then
    sqlite3 "$FIRST_DB" "SELECT feedback_log_body FROM logs WHERE feedback_log_body LIKE '%tool_name=%' LIMIT 50;" 2>/dev/null \
        | grep -oE 'tool_name="[^"]+"' \
        | sort -u \
        || echo "(no tool_name=... rows matched in first 50)"
else
    echo "(no db available — skipping)"
fi
echo

echo "=== reproduction summary ==="
echo "spawn_agent_total=${TOTAL_SPAWN_COUNT}"
echo "skills_total=${SKILL_COUNT}"
echo "skills_with_spawn_ref=${SPAWN_REF_COUNT}"
echo

# STOP condition 1: research assumed spawn_agent count = 0.
# If the live count disagrees, halt — the research findings may be stale.
if [ "$TOTAL_SPAWN_COUNT" -gt 0 ]; then
    echo "STOP: spawn_agent count is ${TOTAL_SPAWN_COUNT}, research assumed 0. Research may be outdated — re-run /gsd-research-phase before patching." >&2
    exit 3
fi

echo "Reproduction complete. spawn_agent symptom (count=0) reproduced."
