#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
usage: parallel_research_campaign.sh [--dry-run]

Launch three local tmux windows, one per research lane, each backed by the
appropriate burst helper. Codex can then poll the local launcher logs or use
tmux capture-pane on the created session.

Environment overrides:
  CAMPAIGN_ID              explicit campaign id
  TMUX_SESSION             explicit tmux session name
  LOG_ROOT                 local log root

  MMF_TARGET               permanent|ephemeral   (default permanent)
  MMF_TAG                  default M-mmfdeep
  MMF_MACHINE_TYPE         only used for ephemeral targets
  MMF_CMD                  command to run

  MULTIVAR_TARGET          default ephemeral
  MULTIVAR_TAG             default V-multivar
  MULTIVAR_MACHINE_TYPE    default c3-highcpu-8
  MULTIVAR_CMD             command to run

  LONGFIBER_TARGET         default ephemeral
  LONGFIBER_TAG            default L-longfiber
  LONGFIBER_MACHINE_TYPE   default c3-highcpu-8
  LONGFIBER_CMD            command to run

Important:
- Parallel permanent+ephemeral campaigns require enough regional C3 quota.
- With the main c3-highcpu-22 burst VM plus two c3-highcpu-8 ephemerals,
  request at least 48 C3 CPUs, preferably 64.
EOF
}

dry_run=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
campaign_id="${CAMPAIGN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
tmux_session="${TMUX_SESSION:-research-parallel-$campaign_id}"
log_root="${LOG_ROOT:-$project_dir/results/burst-logs/parallel/$campaign_id}"
mkdir -p "$log_root"

mmf_target="${MMF_TARGET:-permanent}"
mmf_tag="${MMF_TAG:-M-mmfdeep}"
mmf_machine_type="${MMF_MACHINE_TYPE:-}"
mmf_cmd="${MMF_CMD:-julia -t auto --project=. scripts/research/mmf/baseline.jl}"

multivar_target="${MULTIVAR_TARGET:-ephemeral}"
multivar_tag="${MULTIVAR_TAG:-V-multivar}"
multivar_machine_type="${MULTIVAR_MACHINE_TYPE:-c3-highcpu-8}"
multivar_cmd="${MULTIVAR_CMD:-julia -t auto --project=. scripts/research/multivar/multivar_demo.jl}"

longfiber_target="${LONGFIBER_TARGET:-ephemeral}"
longfiber_tag="${LONGFIBER_TAG:-L-longfiber}"
longfiber_machine_type="${LONGFIBER_MACHINE_TYPE:-c3-highcpu-8}"
longfiber_cmd="${LONGFIBER_CMD:-LF100_MODE=fresh LF100_MAX_ITER=25 julia -t auto --project=. scripts/research/longfiber/longfiber_optimize_100m.jl}"

lane_script="$project_dir/scripts/ops/parallel_research_lane.sh"

mk_lane_cmd() {
    local lane="$1"
    local target="$2"
    local tag="$3"
    local machine_type="$4"
    local cmd="$5"
    local log_file="$6"

    local args=(
        "$lane_script"
        --lane "$lane"
        --target "$target"
        --tag "$tag"
        --cmd "$cmd"
        --log-file "$log_file"
    )
    if [[ -n "$machine_type" ]]; then
        args+=(--machine-type "$machine_type")
    fi
    if [[ $dry_run -eq 1 ]]; then
        args+=(--dry-run)
    fi
    printf '%q ' "${args[@]}"
}

mmf_log="$log_root/mmf.log"
multivar_log="$log_root/multivar.log"
longfiber_log="$log_root/longfiber.log"

mmf_lane_cmd="$(mk_lane_cmd mmf "$mmf_target" "$mmf_tag" "$mmf_machine_type" "$mmf_cmd" "$mmf_log")"
multivar_lane_cmd="$(mk_lane_cmd multivar "$multivar_target" "$multivar_tag" "$multivar_machine_type" "$multivar_cmd" "$multivar_log")"
longfiber_lane_cmd="$(mk_lane_cmd longfiber "$longfiber_target" "$longfiber_tag" "$longfiber_machine_type" "$longfiber_cmd" "$longfiber_log")"

mk_tmux_cmd() {
    local cmd="$1"
    printf 'PARALLEL_ALLOW_DIRTY=%q bash -lc %q' "${PARALLEL_ALLOW_DIRTY:-0}" "$cmd"
}

notes_cmd="cat <<\"TXT\"
Parallel research campaign: $campaign_id

Local logs:
- $mmf_log
- $multivar_log
- $longfiber_log

Poll with:
  scripts/ops/parallel_research_poll.sh --log-root $log_root

Or inspect panes with:
  tmux capture-pane -pt $tmux_session:mmf
  tmux capture-pane -pt $tmux_session:multivar
  tmux capture-pane -pt $tmux_session:longfiber
TXT
exec bash"

cat <<EOF
campaign_id=$campaign_id
tmux_session=$tmux_session
log_root=$log_root
mmf_log=$mmf_log
multivar_log=$multivar_log
longfiber_log=$longfiber_log
EOF

if [[ $dry_run -eq 1 ]]; then
    echo "mmf_cmd=$mmf_lane_cmd"
    echo "multivar_cmd=$multivar_lane_cmd"
    echo "longfiber_cmd=$longfiber_lane_cmd"
    exit 0
fi

if tmux has-session -t "$tmux_session" 2>/dev/null; then
    echo "ERROR: tmux session already exists: $tmux_session" >&2
    exit 4
fi

tmux new-session -d -s "$tmux_session" -n notes "bash -lc $(printf %q "$notes_cmd")"
tmux new-window -t "$tmux_session" -n mmf "$(mk_tmux_cmd "$mmf_lane_cmd")"
tmux new-window -t "$tmux_session" -n multivar "$(mk_tmux_cmd "$multivar_lane_cmd")"
tmux new-window -t "$tmux_session" -n longfiber "$(mk_tmux_cmd "$longfiber_lane_cmd")"
tmux select-window -t "$tmux_session:mmf"

echo "tmux session launched: $tmux_session"
echo "attach with: tmux attach -t $tmux_session"
