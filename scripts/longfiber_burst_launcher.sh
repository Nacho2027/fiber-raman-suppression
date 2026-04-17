#!/usr/bin/env bash
#
# Session F Phase 16 — burst VM launcher  (rewritten 2026-04-17)
#
# Delegates heavy Julia runs to the mandatory ~/bin/burst-run-heavy wrapper
# per new Rule P5 (2026-04-17). No more manual /tmp/burst-heavy-lock
# touching — the wrapper handles lock acquisition, tmux launch, and release.
#
# The wrapper also enforces:
#   - session-tag convention (F-<name>)
#   - single-heavy-at-a-time serialization
#   - output tee into results/burst-logs/<tag>_<ts>.log
#
# Task sequence (Session F Phase 16):
#   T4 - L=100m forward solves (light — no lock needed; runs directly)
#   T3 - L=50m validate (light L-BFGS — no lock)
#   T5 - L=100m L-BFGS (heavy — via burst-run-heavy F-T5)
#   T6 - L=100m validation (light)
#
# Usage — run from claude-code-host:
#
#   ~/bin/burst-run-heavy F-T5 \
#     'LF100_MODE=fresh LF100_MAX_ITER=25 julia -t auto --project=. \
#      scripts/longfiber_optimize_100m.jl'
#
# This script itself runs on the burst VM as the final orchestrator and
# assumes any necessary lock has ALREADY been acquired by whatever
# `~/bin/burst-run-heavy <tag>` invocation launched the tmux hosting it.
# Light tasks inside the queue run bare (no wrapper) since they are
# lock-exempt. T5 (the one true heavy) should be launched SEPARATELY via
# burst-run-heavy, not chained through this queue.

set -uo pipefail
export PATH="$HOME/.juliaup/bin:$PATH"

if [[ -d "$HOME/raman-wt-F/.git" ]] || [[ -f "$HOME/raman-wt-F/.git" ]]; then
    PHASE_DIR="$HOME/raman-wt-F"
else
    PHASE_DIR="$HOME/fiber-raman-suppression"
fi

RESULTS_DIR="$PHASE_DIR/results/raman/phase16"
LOG_DIR="$RESULTS_DIR/logs"
STATE_FILE="$LOG_DIR/queue_state.txt"

mkdir -p "$LOG_DIR"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] $*" | tee -a "$LOG_DIR/queue.log"; }

run_light() {
    local name="$1"
    local script="$2"
    shift 2
    local env_prefix="$*"

    log "===== TASK $name (script=$script, mode=light) ====="
    echo "task=$name status=started at=$(ts)" >> "$STATE_FILE"

    local logfile="$LOG_DIR/${name}.log"
    (
        cd "$PHASE_DIR" || exit 3
        # shellcheck disable=SC2086
        eval $env_prefix julia -t auto --project=. "$script" > "$logfile" 2>&1
    )
    local rc=$?
    log "[$name] exit $rc — log: $logfile"
    echo "task=$name status=done rc=$rc at=$(ts)" >> "$STATE_FILE"
    return $rc
}

log "=========================================="
log "Session F Phase 16 light-queue started"
log "queue_pid=$$  working dir=$PHASE_DIR"
log "=========================================="
log "NOTE: heavy L=100m optimization (T5) is NOT run by this script."
log "      Launch it from claude-code-host via:"
log "        burst-ssh \"cd fiber-raman-suppression && ~/bin/burst-run-heavy F-T5 \\"
log "            'LF100_MODE=fresh LF100_MAX_ITER=25 julia -t auto \\"
log "             --project=. scripts/longfiber_optimize_100m.jl'\""
log ""

( cd "$PHASE_DIR" && git fetch origin 2>&1 | tee -a "$LOG_DIR/queue.log" \
    && git pull --ff-only 2>&1 | tee -a "$LOG_DIR/queue.log" ) || {
    log "git pull failed — aborting"
    exit 4
}

# Light tasks: forward solves + 50 m validation. Neither monopolizes the VM.
run_light "T4-100m-forward" "scripts/longfiber_forward_100m.jl"
run_light "T3-50m-validate" "scripts/longfiber_validate_50m.jl"
run_light "T6-100m-validate" "scripts/longfiber_validate_100m.jl"

log "light queue complete. T5 must be launched separately via burst-run-heavy."
