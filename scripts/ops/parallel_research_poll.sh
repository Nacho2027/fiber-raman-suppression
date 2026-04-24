#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
usage: parallel_research_poll.sh --log-root PATH [--lines N]

Summarize the local launcher logs produced by `parallel_research_campaign.sh`.
This is the intended Codex polling surface: it stays local, stable, and does
not require attaching to tmux.
EOF
}

log_root=""
lines=20

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-root) log_root="${2:-}"; shift 2 ;;
        --lines) lines="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$log_root" ]]; then
    usage >&2
    exit 2
fi

if [[ ! -d "$log_root" ]]; then
    echo "ERROR: log root not found: $log_root" >&2
    exit 3
fi

echo "log_root=$log_root"
echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

if command -v ~/bin/burst-list-ephemerals >/dev/null 2>&1; then
    echo "ephemeral-vms:"
    ~/bin/burst-list-ephemerals || true
    echo ""
fi

for lane in mmf multivar longfiber; do
    log_file="$log_root/$lane.log"
    echo "===== $lane ====="
    if [[ -f "$log_file" ]]; then
        tail -n "$lines" "$log_file"
    else
        echo "(no log yet: $log_file)"
    fi
    echo ""
done
