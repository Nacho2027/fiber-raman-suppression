#!/usr/bin/env bash
# watchdog.sh — run continuously on fiber-raman-burst. If load average or memory
# cross safety thresholds, kill the youngest heavy Julia process and log the
# event. Prevents the Apr-17 kernel-lockup scenario where 7+ concurrent heavy
# Julia jobs exhausted the VM.
#
# Intended to be installed via install.sh as a systemd --user service. Can also
# be run manually:
#
#   nohup scripts/burst/watchdog.sh > ~/watchdog.log 2>&1 &

set -euo pipefail

# Thresholds (tunable via env)
LOAD_MAX="${LOAD_MAX:-35}"          # 1-min load average; 22-core VM, alert >35
MEM_FREE_GB_MIN="${MEM_FREE_GB_MIN:-4}"
CHECK_INTERVAL_SEC="${CHECK_INTERVAL_SEC:-30}"
LOG="${LOG:-$HOME/watchdog.log}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG" ; }

# Find the youngest julia process with >1GB RSS (pid order: newest last)
youngest_heavy_julia() {
    ps -eo pid,etimes,rss,comm --sort=-etimes \
        | awk '$4 == "julia" && $3 > 1048576 { print $1 }' \
        | tail -1
}

heavy_julia_count() {
    ps -eo pid,rss,comm | awk '$2 > 1048576 && $3 == "julia"' | wc -l
}

kill_rogue() {
    local pid="$1"
    local reason="$2"
    local info
    info=$(ps -o pid,etime,rss,cmd -p "$pid" 2>/dev/null | tail -1 || echo "<gone>")
    log "KILLING pid=$pid  reason=$reason"
    log "  process: $info"
    # SIGTERM first, SIGKILL after 10s grace
    kill -TERM "$pid" 2>/dev/null || true
    sleep 10
    if kill -0 "$pid" 2>/dev/null; then
        log "  SIGTERM didn't work; SIGKILL"
        kill -KILL "$pid" 2>/dev/null || true
    fi
}

log "watchdog started  LOAD_MAX=$LOAD_MAX  MEM_FREE_GB_MIN=$MEM_FREE_GB_MIN  interval=${CHECK_INTERVAL_SEC}s"

while true; do
    # 1-minute load average
    load=$(awk '{print $1}' /proc/loadavg)
    # Available memory in GB
    mem_free_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    mem_free_gb=$(awk -v kb="$mem_free_kb" 'BEGIN { printf "%.2f", kb/1024/1024 }')

    n_heavy=$(heavy_julia_count)

    # Trigger if either threshold is exceeded AND we have at least 2 heavy julias
    # (killing the only heavy job when load is high might just be a slow run)
    trigger=""
    if awk -v load="$load" -v max="$LOAD_MAX" 'BEGIN { exit !(load+0 > max+0) }'; then
        trigger="load=$load > $LOAD_MAX"
    fi
    if awk -v free="$mem_free_gb" -v min="$MEM_FREE_GB_MIN" 'BEGIN { exit !(free+0 < min+0) }'; then
        trigger="${trigger}${trigger:+; }mem=${mem_free_gb}GB < ${MEM_FREE_GB_MIN}GB"
    fi

    if [[ -n "$trigger" ]] && (( n_heavy >= 2 )); then
        log "THRESHOLD EXCEEDED: $trigger  heavy_julia=$n_heavy"
        victim=$(youngest_heavy_julia)
        if [[ -n "$victim" ]]; then
            kill_rogue "$victim" "$trigger"
        else
            log "  no heavy julia to kill?"
        fi
    fi

    sleep "$CHECK_INTERVAL_SEC"
done
