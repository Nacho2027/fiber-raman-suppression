#!/usr/bin/env bash
# run-heavy.sh — mandatory wrapper for ALL heavy Julia runs on fiber-raman-burst.
#
# Acquires /tmp/burst-heavy-lock, runs the command in a detached tmux session,
# and releases the lock when the command exits (even on crash via trap).
#
# Usage (on burst VM):
#   scripts/burst/run-heavy.sh <session-tag> <command>
#
# Usage (from claude-code-host):
#   burst-ssh "cd fiber-raman-suppression && scripts/burst/run-heavy.sh \
#              F-longfiber 'julia -t auto --project=. scripts/canonical/run_experiment.jl --heavy-ok smf28_longfiber_phase_poc'"
#
# session-tag convention: <Letter>-<short-name>, matching AGENTS.md Rule P6.
# Examples: A-multivar, E-sweep2, F-longfiber-T5, H-cost-audit, etc.
#
# The lock is a file /tmp/burst-heavy-lock containing:
#   session=<tag>
#   pid=<pid of the julia process>
#   tmux=<tmux session name>
#   started=<ISO timestamp>
#   cmd=<command>

set -euo pipefail

LOCK=/tmp/burst-heavy-lock
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-0}"   # 0 = fail immediately; >0 = wait

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <session-tag> <command...>" >&2
    echo "example: $0 E-sweep2 'julia -t auto --project=. scripts/sweep.jl'" >&2
    exit 2
fi

SESSION="$1"; shift
CMD="$*"

# Enforce session tag convention: Letter-rest
if [[ ! "$SESSION" =~ ^[A-Za-z]-[A-Za-z0-9_-]+$ ]]; then
    echo "ERROR: session tag '$SESSION' must match <Letter>-<name>" >&2
    echo "examples: A-multivar, E-sweep2, F-longfiber-T5" >&2
    exit 2
fi

check_stale_lock() {
    [[ -f "$LOCK" ]] || return 1
    # Parse the pid; if the process isn't running, lock is stale.
    local pid
    pid=$(grep -E '^pid=' "$LOCK" 2>/dev/null | cut -d= -f2)
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        echo "NOTE: clearing stale lock (pid $pid no longer running)" >&2
        rm -f "$LOCK"
        return 1
    fi
    return 0
}

acquire_lock() {
    local elapsed=0
    while true; do
        if ! check_stale_lock; then
            break
        fi
        # lock is held and pid is live
        if (( elapsed >= WAIT_TIMEOUT_SEC )); then
            echo "ERROR: burst-heavy-lock already held:" >&2
            cat "$LOCK" >&2
            echo "" >&2
            echo "Set WAIT_TIMEOUT_SEC=<seconds> to wait for lock release." >&2
            exit 1
        fi
        echo "waiting for heavy lock... (${elapsed}s / ${WAIT_TIMEOUT_SEC}s)" >&2
        sleep 30
        elapsed=$((elapsed + 30))
    done

    # Claim it
    cat > "$LOCK" <<EOF
session=$SESSION
pid=$$
tmux=$SESSION
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cmd=$CMD
EOF
    echo "acquired heavy lock for session=$SESSION" >&2
}

release_lock() {
    # Only release if WE are the holder (don't clobber someone else's lock)
    if [[ -f "$LOCK" ]]; then
        local holder
        holder=$(grep -E '^session=' "$LOCK" 2>/dev/null | cut -d= -f2)
        if [[ "$holder" == "$SESSION" ]]; then
            rm -f "$LOCK"
            echo "released heavy lock for session=$SESSION" >&2
        fi
    fi
}

trap release_lock EXIT INT TERM

acquire_lock

# Ensure Julia is on PATH even under tmux (juliaup installs to ~/.juliaup/bin)
export PATH="$HOME/.juliaup/bin:$PATH"

# Kill any previous tmux with our session name (cleanup from failed runs)
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Run in tmux, BUT stay attached from this shell so the trap fires on exit.
# We'll send the command to tmux and wait for it.
LOGDIR="$HOME/fiber-raman-suppression/results/burst-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/${SESSION}_$(date -u +%Y%m%dT%H%M%SZ).log"

echo "logfile: $LOGFILE" >&2
echo "tmux session: $SESSION" >&2
echo "command: $CMD" >&2

# Pipe output to logfile AND tmux buffer
tmux new -d -s "$SESSION" "$CMD 2>&1 | tee $LOGFILE; echo '--- job finished ---'"

# Wait for the tmux session to exit
while tmux has-session -t "$SESSION" 2>/dev/null; do
    sleep 15
done

echo "tmux session $SESSION ended; logfile: $LOGFILE" >&2
