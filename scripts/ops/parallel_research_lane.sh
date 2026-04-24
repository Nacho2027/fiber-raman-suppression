#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
usage: parallel_research_lane.sh --lane NAME --target permanent|ephemeral \
    --tag X-name --cmd 'julia ...' --log-file PATH [--machine-type TYPE] [--dry-run]

Runs one research lane through the existing burst helpers while teeing local
output into a stable launcher log that Codex can poll.

Notes:
- `--target permanent` runs on `fiber-raman-burst` through remote
  `~/bin/burst-run-heavy`.
- `--target ephemeral` runs through local `~/bin/burst-spawn-temp`.
- By default this script refuses to launch from a dirty worktree because the
  remote jobs pull from `main`, not from local uncommitted changes.
  Override with `PARALLEL_ALLOW_DIRTY=1` only if that mismatch is intentional.
EOF
}

lane=""
target=""
tag=""
cmd=""
log_file=""
machine_type=""
dry_run=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lane) lane="${2:-}"; shift 2 ;;
        --target) target="${2:-}"; shift 2 ;;
        --tag) tag="${2:-}"; shift 2 ;;
        --cmd) cmd="${2:-}"; shift 2 ;;
        --log-file) log_file="${2:-}"; shift 2 ;;
        --machine-type) machine_type="${2:-}"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$lane" || -z "$target" || -z "$tag" || -z "$cmd" || -z "$log_file" ]]; then
    usage >&2
    exit 2
fi

if [[ "$target" != "permanent" && "$target" != "ephemeral" ]]; then
    echo "ERROR: target must be permanent or ephemeral" >&2
    exit 2
fi

if [[ ! "$tag" =~ ^[A-Za-z]-[A-Za-z0-9_-]+$ ]]; then
    echo "ERROR: tag must match <Letter>-<name>, got: $tag" >&2
    exit 2
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$(dirname "$log_file")"
log_file="$(cd "$(dirname "$log_file")" && pwd)/$(basename "$log_file")"

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(timestamp)] [$lane] $*" | tee -a "$log_file"; }

build_bootstrap_cmd() {
    local q_cmd
    local q_tag
    printf -v q_cmd "%q" "$cmd"
    printf -v q_tag "%q" "$tag"

    cat <<EOF
set -euo pipefail
RUN_DIR="\$HOME/research-runs/$q_tag"
mkdir -p "\$HOME/research-runs"
cd "\$HOME/fiber-raman-suppression"
git fetch origin --quiet
git worktree remove --force "\$RUN_DIR" >/dev/null 2>&1 || rm -rf "\$RUN_DIR"
git worktree prune >/dev/null 2>&1 || true
git worktree add --force --detach "\$RUN_DIR" origin/main
rm -rf "\$RUN_DIR/results"
ln -s "\$HOME/fiber-raman-suppression/results" "\$RUN_DIR/results"
cd "\$RUN_DIR"
julia --project=. -e "using Pkg; Pkg.instantiate()"
eval $q_cmd
EOF
}

ephemeral_pull_paths() {
    case "$lane" in
        longfiber)
            echo "results/burst-logs results/raman/phase16 results/images"
            ;;
        multivar|multiparameter)
            echo "results/burst-logs results/raman/multivar results/validation"
            ;;
        mmf|multimode)
            echo "results/burst-logs results/raman/mmf results/raman/phase36 results/images"
            ;;
        *)
            echo "results/burst-logs"
            ;;
    esac
}

if [[ "${PARALLEL_ALLOW_DIRTY:-0}" != "1" ]]; then
    if [[ -n "$(git -C "$project_dir" status --porcelain)" ]]; then
        echo "ERROR: refusing to launch $lane from a dirty worktree." >&2
        echo "Commit/push the needed code first, or set PARALLEL_ALLOW_DIRTY=1." >&2
        exit 3
    fi
fi

if [[ $dry_run -eq 1 ]]; then
    {
        echo "lane=$lane"
        echo "target=$target"
        echo "tag=$tag"
        echo "log_file=$log_file"
        [[ -n "$machine_type" ]] && echo "machine_type=$machine_type"
        echo "cmd=$cmd"
    } | tee -a "$log_file"
    exit 0
fi

log "launching target=$target tag=$tag"
log "command: $cmd"
bootstrap_cmd="$(build_bootstrap_cmd)"
log "remote runs from clean worktree: ~/research-runs/$tag"

cd "$project_dir"

if [[ "$target" == "permanent" ]]; then
    quoted_bootstrap=""
    printf -v quoted_bootstrap "%q" "$bootstrap_cmd"
    "$HOME/bin/burst-start" >/dev/null 2>&1 || true
    set +e
    "$HOME/bin/burst-ssh" "cd fiber-raman-suppression && ~/bin/burst-run-heavy $tag $quoted_bootstrap" \
        2>&1 | tee -a "$log_file"
    rc=${PIPESTATUS[0]}
    set -e
else
    set +e
    pull_paths="$(ephemeral_pull_paths)"
    if [[ -n "$machine_type" ]]; then
        BURST_PULL_PATHS="$pull_paths" \
        BURST_LOCAL_REPO="$project_dir" \
        BURST_MACHINE_TYPE="$machine_type" \
            ~/bin/burst-spawn-temp "$tag" "$bootstrap_cmd" 2>&1 | tee -a "$log_file"
    else
        BURST_PULL_PATHS="$pull_paths" \
        BURST_LOCAL_REPO="$project_dir" \
        ~/bin/burst-spawn-temp "$tag" "$bootstrap_cmd" 2>&1 | tee -a "$log_file"
    fi
    rc=${PIPESTATUS[0]}
    set -e
fi

log "finished rc=$rc"
exit "$rc"
