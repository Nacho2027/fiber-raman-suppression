#!/usr/bin/env bash
# phase33_benchmark_run_with_push.sh — run Phase 33 benchmark on an ephemeral
# burst VM, then push results to main so claude-code-host can git pull them
# before the ephemeral VM auto-destroys.
#
# Invoked via: ~/bin/burst-spawn-temp A-p33 'bash scripts/phase33_benchmark_run_with_push.sh'

set -uo pipefail

cd "$(dirname "$0")/.."
REPO="$PWD"
TS=$(date -u +%Y%m%dT%H%M%SZ)

echo "[phase33-push-runner] starting at ${TS}"
echo "[phase33-push-runner] threads=$(nproc) pwd=${REPO}"

# ── 1. Run the benchmark ────────────────────────────────────────────────
julia -t auto --project=. scripts/phase33_benchmark_run.jl
JL_EXIT=$?
echo "[phase33-push-runner] julia exit=${JL_EXIT}"

# ── 2. Commit + push results even on partial failure ────────────────────
# Allow partial results to be captured rather than lost with the VM.
git config user.email "${GIT_AUTHOR_EMAIL:-ijl27@cornell.edu}" || true
git config user.name  "${GIT_AUTHOR_NAME:-Ignacio Lizama (ephemeral)}" || true

# Pull latest to minimize push conflicts with parallel sessions.
git fetch origin main --quiet || true
git pull --ff-only origin main 2>&1 | tail -5 || echo "[phase33-push-runner] WARN ff-pull failed; attempting rebase"
git pull --rebase origin main 2>&1 | tail -5 || echo "[phase33-push-runner] WARN rebase pull failed"

# Force-add JLD2 / PNG / CSV / MD artifacts + log (these are .gitignore'd).
git add -f "results/raman/phase33/" 2>/dev/null || true
git add -f "results/burst-logs/P-phase33-tr_"*.log 2>/dev/null || true

if git diff --cached --quiet; then
    echo "[phase33-push-runner] no results to commit (phase33 tree empty?)"
else
    MSG="chore(phase33): benchmark sweep results (ephemeral, julia exit=${JL_EXIT})"
    git commit -m "${MSG}"
    # Retry push up to 3 times with rebase-on-conflict.
    for i in 1 2 3; do
        if git push origin main 2>&1 | tee /tmp/p33_push.log; then
            echo "[phase33-push-runner] push succeeded on attempt ${i}"
            break
        fi
        echo "[phase33-push-runner] push attempt ${i} failed; rebasing and retrying"
        git fetch origin main --quiet
        git rebase origin/main 2>&1 | tail -10 || {
            echo "[phase33-push-runner] rebase conflict; aborting"
            git rebase --abort 2>/dev/null || true
            break
        }
    done
fi

echo "[phase33-push-runner] done; ephemeral VM will now be destroyed by spawn-temp trap"
exit 0
