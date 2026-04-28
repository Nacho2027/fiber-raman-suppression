#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
usage: run_with_telemetry.sh --label LABEL --out-dir DIR [--sample-interval SEC] -- COMMAND [ARG...]

Runs COMMAND while recording lightweight compute telemetry:

- telemetry.json: command, host, thread/memory context, elapsed time, return code,
  sampled peak CPU%, sampled peak RSS, and /usr/bin/time fields when available.
- resource_samples.csv: timestamped process-group CPU/memory samples.
- time_verbose.txt: raw /usr/bin/time -v output when available.
- command.txt: exact command line.

This is for lab planning and run budgeting. It does not replace scientific
trust checks or artifact validation.
EOF
}

label=""
out_dir=""
sample_interval="${RUN_TELEMETRY_SAMPLE_INTERVAL:-30}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --label) label="${2:-}"; shift 2 ;;
        --out-dir) out_dir="${2:-}"; shift 2 ;;
        --sample-interval) sample_interval="${2:-}"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        --) shift; break ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$label" || -z "$out_dir" || $# -eq 0 ]]; then
    usage >&2
    exit 2
fi

mkdir -p "$out_dir"

telemetry_json="$out_dir/telemetry.json"
samples_csv="$out_dir/resource_samples.csv"
time_verbose="$out_dir/time_verbose.txt"
command_txt="$out_dir/command.txt"

json_escape() {
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

first_cpu_model() {
    if [[ -r /proc/cpuinfo ]]; then
        awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo
    else
        uname -m
    fi
}

mem_total_kb() {
    if [[ -r /proc/meminfo ]]; then
        awk '/MemTotal:/ {print $2; exit}' /proc/meminfo
    else
        echo ""
    fi
}

command_display="$(printf '%q ' "$@")"
printf '%s\n' "$command_display" > "$command_txt"

start_ns="$(date -u +%s%N)"
start_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
host="$(hostname 2>/dev/null || echo unknown)"
user_name="${USER:-$(id -un 2>/dev/null || echo unknown)}"
cwd="$(pwd)"
cpu_threads="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo "")"
cpu_model="$(first_cpu_model)"
memory_kb="$(mem_total_kb)"
julia_threads="${JULIA_NUM_THREADS:-${JULIA_NUM_THREADS_AUTO:-}}"

echo "timestamp_utc,elapsed_s,processes,cpu_percent_sum,mem_percent_sum,rss_kb_sum,vsz_kb_sum" > "$samples_csv"

time_cmd=()
if [[ -x /usr/bin/time ]]; then
    time_cmd=(/usr/bin/time -v -o "$time_verbose")
else
    : > "$time_verbose"
fi

run_pid=""
set +e
if command -v setsid >/dev/null 2>&1; then
    setsid --wait "${time_cmd[@]}" "$@" &
else
    "${time_cmd[@]}" "$@" &
fi
run_pid=$!
set -e

peak_sample_cpu="0"
peak_sample_rss_kb="0"
peak_sample_mem="0"

sample_once() {
    local now elapsed sample
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    elapsed="$(awk -v now="$(date -u +%s%N)" -v start="$start_ns" \
        'BEGIN {printf "%.3f", (now - start) / 1000000000}')"

    sample="$(ps -eo pgid=,pcpu=,pmem=,rss=,vsz= 2>/dev/null | awk -v pgid="$run_pid" '
        $1 == pgid {
            cpu += $2
            mem += $3
            rss += $4
            vsz += $5
            n += 1
        }
        END {
            if (n == 0) {
                printf "0,0,0,0,0"
            } else {
                printf "%d,%.3f,%.3f,%d,%d", n, cpu, mem, rss, vsz
            }
        }')"
    echo "$now,$elapsed,$sample" >> "$samples_csv"

    IFS=',' read -r processes cpu mem rss vsz <<< "$sample"
    if awk "BEGIN {exit !($cpu > $peak_sample_cpu)}"; then
        peak_sample_cpu="$cpu"
    fi
    if awk "BEGIN {exit !($mem > $peak_sample_mem)}"; then
        peak_sample_mem="$mem"
    fi
    if [[ "${rss:-0}" =~ ^[0-9]+$ && "$rss" -gt "$peak_sample_rss_kb" ]]; then
        peak_sample_rss_kb="$rss"
    fi
}

sample_once
while kill -0 "$run_pid" >/dev/null 2>&1; do
    sleep "$sample_interval" || true
    sample_once
done

set +e
wait "$run_pid"
rc=$?
set -e

end_ns="$(date -u +%s%N)"
end_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
elapsed_s="$(awk -v end="$end_ns" -v start="$start_ns" \
    'BEGIN {printf "%.3f", (end - start) / 1000000000}')"

time_user_s=""
time_system_s=""
time_cpu_percent=""
time_elapsed=""
time_max_rss_kb=""
if [[ -s "$time_verbose" ]]; then
    time_user_s="$(awk -F: '/User time/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' "$time_verbose")"
    time_system_s="$(awk -F: '/System time/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' "$time_verbose")"
    time_cpu_percent="$(awk -F: '/Percent of CPU/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' "$time_verbose")"
    time_elapsed="$(awk -F: '/Elapsed/ {sub(/^[^:]*:[ \t]*/, ""); print; exit}' "$time_verbose")"
    time_max_rss_kb="$(awk -F: '/Maximum resident set size/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' "$time_verbose")"
fi

cat > "$telemetry_json" <<EOF
{
  "schema": "fiber_run_telemetry_v1",
  "label": "$(json_escape "$label")",
  "command": "$(json_escape "$command_display")",
  "cwd": "$(json_escape "$cwd")",
  "hostname": "$(json_escape "$host")",
  "user": "$(json_escape "$user_name")",
  "started_at_utc": "$start_iso",
  "finished_at_utc": "$end_iso",
  "elapsed_s": $elapsed_s,
  "return_code": $rc,
  "cpu_model": "$(json_escape "$cpu_model")",
  "cpu_threads_online": "$(json_escape "$cpu_threads")",
  "mem_total_kb": "$(json_escape "$memory_kb")",
  "julia_num_threads": "$(json_escape "$julia_threads")",
  "sample_interval_s": "$(json_escape "$sample_interval")",
  "sampled_peak_cpu_percent_sum": $peak_sample_cpu,
  "sampled_peak_mem_percent_sum": $peak_sample_mem,
  "sampled_peak_rss_kb_sum": $peak_sample_rss_kb,
  "time_user_s": "$(json_escape "$time_user_s")",
  "time_system_s": "$(json_escape "$time_system_s")",
  "time_cpu_percent": "$(json_escape "$time_cpu_percent")",
  "time_elapsed": "$(json_escape "$time_elapsed")",
  "time_max_rss_kb": "$(json_escape "$time_max_rss_kb")",
  "samples_csv": "resource_samples.csv",
  "time_verbose": "time_verbose.txt",
  "command_file": "command.txt"
}
EOF

exit "$rc"
