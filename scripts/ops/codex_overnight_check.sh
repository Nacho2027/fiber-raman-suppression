#!/usr/bin/env bash

set -euo pipefail

REPO="${FIBER_REPO:-/home/ignaciojlizama/fiber-raman-suppression}"
DATE_TAG="${OVERNIGHT_DATE_TAG:-20260427}"
CODEX_BIN="${CODEX_BIN:-/home/ignaciojlizama/.npm-global/bin/codex}"
PROMPT_FILE="$REPO/agent-docs/overnight-research-supervision/CODEX_WATCHDOG_PROMPT.md"
LOG_DIR="$REPO/results/burst-logs/overnight/$DATE_TAG"
RUN_LOG="$LOG_DIR/codex-watchdog.log"
LAST_MESSAGE="$LOG_DIR/codex-watchdog-last-message.md"
LOCK_FILE="$LOG_DIR/codex-watchdog.lock"
TIMEOUT="${CODEX_WATCHDOG_TIMEOUT:-25m}"
PATH="$HOME/bin:$HOME/.npm-global/bin:$HOME/.juliaup/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

mkdir -p "$LOG_DIR"
cd "$REPO"

log() {
    printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$RUN_LOG"
}

if [[ ! -x "$CODEX_BIN" ]]; then
    log "ERROR: Codex CLI is not executable at $CODEX_BIN"
    exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
    log "ERROR: missing prompt file $PROMPT_FILE"
    exit 1
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "another Codex watchdog is already running; skipping"
    exit 0
fi

log "Codex watchdog start"

if [[ "${CODEX_WATCHDOG_DRY_RUN:-0}" == "1" ]]; then
    log "dry run: would execute $CODEX_BIN exec --cd $REPO"
    exit 0
fi

set +e
timeout "$TIMEOUT" "$CODEX_BIN" exec \
    --cd "$REPO" \
    --dangerously-bypass-approvals-and-sandbox \
    --output-last-message "$LAST_MESSAGE" \
    - < "$PROMPT_FILE" >> "$RUN_LOG" 2>&1
status=$?
set -e

if [[ "$status" -eq 124 ]]; then
    log "WARN: Codex watchdog timed out after $TIMEOUT"
elif [[ "$status" -ne 0 ]]; then
    log "WARN: Codex watchdog exited with status $status"
else
    log "Codex watchdog complete"
fi

exit 0
