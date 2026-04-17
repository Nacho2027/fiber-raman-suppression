#!/usr/bin/env bash
#
# Session F Phase 16 — burst VM launcher
#
# Sequences the four simulation tasks on the burst VM with proper heavy-lock
# discipline. Designed to be launched under tmux on the burst VM and left
# to run overnight; always ends with `burst-stop` so the VM bills $0 after.
#
# Task sequence:
#   T4 - L=100m forward solves (light, can share VM with other work)
#   T3 - L=50m validation (holds heavy lock briefly, ~15 min)
#   T5 - L=100m L-BFGS optimization + checkpoint resume demo (holds heavy
#        lock, 2-8 h wall clock)
#   T6 - L=100m validation + phi a2 fit + FINDINGS.md (moderate, ~30 min)
#
# Usage (from claude-code-host): launch via `burst-ssh tmux new -d -s F-queue ...`
# Usage (on burst VM directly): bash scripts/longfiber_burst_launcher.sh
#
# Lock protocol (per CLAUDE.md Rule P5 and D-F-06):
#   - Poll /tmp/burst-heavy-lock every 5 min for up to 12 h before giving up
#   - Touch /tmp/burst-heavy-lock before each heavy task, rm after
#   - If any task exits non-zero, continue to next (don't abort the queue)
#   - Always run `burst-stop` in the final cleanup trap

set -uo pipefail  # -e deliberately omitted; we want to finish cleanup even on failure

# Ensure julia is on PATH (juliaup install dir); non-interactive bash on the
# burst VM does not source .bashrc by default.
export PATH="$HOME/.juliaup/bin:$PATH"

# Use a dedicated Session F worktree when present — isolates us from other
# sessions that do `git checkout` on the main burst VM repo. Created via
# `git worktree add /home/ignaciojlizama/raman-wt-F sessions/F-longfiber`.
if [[ -d "$HOME/raman-wt-F/.git" ]] || [[ -f "$HOME/raman-wt-F/.git" ]]; then
    PHASE_DIR="$HOME/raman-wt-F"
else
    PHASE_DIR="$HOME/fiber-raman-suppression"
fi
RESULTS_DIR="$PHASE_DIR/results/raman/phase16"
LOG_DIR="$RESULTS_DIR/logs"
LOCK_FILE="/tmp/burst-heavy-lock"
LOCK_TIMEOUT_S=$((12 * 3600))    # 12 hours
LOCK_POLL_S=300                  # 5 min
STATE_FILE="$LOG_DIR/queue_state.txt"

mkdir -p "$LOG_DIR"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] $*" | tee -a "$LOG_DIR/queue.log"; }

cleanup() {
    local rc=$?
    log "cleanup triggered (exit $rc)"
    # Release heavy lock only if we own it (tagged with our PID)
    if [[ -f "$LOCK_FILE" ]] && grep -q "session=F queue_pid=$$" "$LOCK_FILE" 2>/dev/null; then
        rm -f "$LOCK_FILE"
        log "heavy lock released"
    fi
    # Stop the VM ONLY if no other tmux sessions with active julia work remain.
    # This prevents us from killing Session E / Phase 14 / etc.
    local other_tmux
    other_tmux=$(tmux ls 2>/dev/null | grep -v "^F-queue:" | wc -l)
    local running_julia
    running_julia=$(pgrep -af julia 2>/dev/null | grep -v "$$" | grep -cv "bash -c" || echo 0)
    log "shutdown check: other_tmux=$other_tmux running_julia=$running_julia"
    if (( other_tmux == 0 )) && (( running_julia == 0 )); then
        log "no other work detected — self-stopping burst VM"
        if command -v gcloud >/dev/null 2>&1; then
            gcloud compute instances stop fiber-raman-burst --zone=us-east5-a --project=riveralab --quiet 2>&1 | tee -a "$LOG_DIR/queue.log" || true
        else
            log "gcloud not found — skipping self-stop"
        fi
    else
        log "other work still running — NOT self-stopping VM (caller should burst-stop from claude-code-host when safe)"
    fi
    log "queue finished with rc=$rc"
}
trap cleanup EXIT

wait_for_heavy_lock() {
    local task_name="$1"
    local waited=0
    while [[ -f "$LOCK_FILE" ]]; do
        local holder
        holder=$(cat "$LOCK_FILE" 2>/dev/null | head -1 || echo "unknown")
        log "[$task_name] heavy lock held by: $holder  (waited ${waited}s)"
        if (( waited >= LOCK_TIMEOUT_S )); then
            log "[$task_name] TIMEOUT after ${LOCK_TIMEOUT_S}s waiting for heavy lock — skipping task"
            return 1
        fi
        sleep "$LOCK_POLL_S"
        waited=$((waited + LOCK_POLL_S))
    done
    # Acquire the lock atomically
    # Race-safe: O_CREAT|O_EXCL pattern via set -o noclobber
    ( set -o noclobber; echo "session=F queue_pid=$$ task=$task_name acquired=$(ts)" > "$LOCK_FILE" ) 2>/dev/null || {
        log "[$task_name] lock race lost, retry"
        sleep "$LOCK_POLL_S"
        return 2
    }
    log "[$task_name] heavy lock acquired"
    return 0
}

release_heavy_lock() {
    local task_name="$1"
    if [[ -f "$LOCK_FILE" ]] && grep -q "session=F queue_pid=$$" "$LOCK_FILE" 2>/dev/null; then
        rm -f "$LOCK_FILE"
        log "[$task_name] heavy lock released"
    fi
}

run_task() {
    local name="$1"
    local script="$2"
    local heavy="$3"   # "heavy" or "light"
    shift 3
    local env_prefix="$*"

    log "===== TASK $name (script=$script, mode=$heavy) ====="
    echo "task=$name status=started at=$(ts)" >> "$STATE_FILE"

    if [[ "$heavy" == "heavy" ]]; then
        while ! wait_for_heavy_lock "$name"; do
            [[ $? -eq 1 ]] && return 1  # timeout
            # else race lost, retry
        done
    fi

    local logfile="$LOG_DIR/${name}.log"
    log "[$name] running: $env_prefix julia -t auto --project=. $script"
    log "[$name] log → $logfile"

    (
        cd "$PHASE_DIR" || exit 3
        # shellcheck disable=SC2086
        eval $env_prefix julia -t auto --project=. "$script" > "$logfile" 2>&1
    )
    local rc=$?
    log "[$name] exit code: $rc"

    [[ "$heavy" == "heavy" ]] && release_heavy_lock "$name"

    echo "task=$name status=done rc=$rc at=$(ts)" >> "$STATE_FILE"
    return $rc
}

log "=========================================="
log "Session F Phase 16 burst launcher started"
log "queue_pid=$$"
log "working dir=$PHASE_DIR"
log "=========================================="

# Pull latest code
log "git pull"
( cd "$PHASE_DIR" && git fetch origin && git checkout sessions/F-longfiber 2>&1 | tee -a "$LOG_DIR/queue.log" && git pull --ff-only origin sessions/F-longfiber 2>&1 | tee -a "$LOG_DIR/queue.log" ) || {
    log "git pull failed — aborting"
    exit 4
}

# Confirm warm-start seed
if [[ ! -f "$PHASE_DIR/results/raman/sweeps/smf28/L2m_P0.05W/opt_result.jld2" ]]; then
    log "WARN warm-start seed not found — T3 and T5 will likely fail"
fi

# Task 4 first (LIGHT): L=100m forward solves — fast grid adequacy + per-solve timing
run_task "T4-100m-forward" "scripts/longfiber_forward_100m.jl" "light"
t4_rc=$?
log "T4 done (rc=$t4_rc)"

# Task 3 (LIGHT): L=50m stepping stone. Originally tagged heavy but empirically
# the L-BFGS completes in 5-15 min at Nt=16384 — below the CLAUDE.md Rule P5
# heavy threshold when the grid is this modest. Keep it light so it does not
# block behind multi-session sweep lock contention.
run_task "T3-50m-validate" "scripts/longfiber_validate_50m.jl" "light"
t3_rc=$?
log "T3 done (rc=$t3_rc)"

# Task 5 (VERY HEAVY): L=100m L-BFGS optimization with checkpoint-resume demo
run_task "T5-100m-optimize" "scripts/longfiber_optimize_100m.jl" "heavy" "LF100_MODE=resume_demo"
t5_rc=$?
log "T5 done (rc=$t5_rc)"

# Task 6 (MODERATE): validation + FINDINGS.md
run_task "T6-100m-validate" "scripts/longfiber_validate_100m.jl" "light"
t6_rc=$?
log "T6 done (rc=$t6_rc)"

log "final task return codes: T4=$t4_rc T3=$t3_rc T5=$t5_rc T6=$t6_rc"
log "queue completed at $(ts)"
# Cleanup trap runs burst-stop
