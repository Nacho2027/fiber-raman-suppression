#!/usr/bin/env bash
# phase33_diag.sh — diagnostic runner on ephemeral VM that captures environment
# state and the first ~2 minutes of the benchmark so we can debug the 30-second
# crash without losing the log.

set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"

DIAG_LOG=/tmp/phase33_diag.log
: > "${DIAG_LOG}"

{
    echo "=== phase33_diag start $(date -Is) ==="
    echo "=== pwd / whoami ==="
    pwd; whoami; hostname
    echo "=== julia version ==="
    julia --version 2>&1 || echo "julia not on PATH; checking ~/.juliaup"
    ls -la ~/.juliaup/bin/ 2>&1 | head -5
    echo "=== git status ==="
    git rev-parse HEAD 2>&1
    git log -1 --oneline 2>&1
    echo "=== BENCHMARK_CONFIGS load ==="
    julia --project=. -e 'include("scripts/phase33_benchmark_common.jl"); for cfg in BENCHMARK_CONFIGS; println(cfg.tag, " warm=", cfg.warm_jld2, " exists=", isfile(cfg.warm_jld2)); end' 2>&1 | head -40
    echo "=== warm jld2 sanity (ls) ==="
    ls -la results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2 \
           results/raman/phase21/phase13/hnlf_reanchor.jld2 \
           results/raman/phase21/phase13/smf28_reanchor.jld2 2>&1
    echo "=== try driver load (no main) ==="
    timeout 120 julia --project=. -e 'include("scripts/phase33_benchmark_run.jl"); @info "driver loaded"' 2>&1 | head -80
    echo "=== disk free ==="
    df -h ~/fiber-raman-suppression 2>&1 | tail -3
    echo "=== git config for push ==="
    git config --get user.email 2>&1
    git config --get remote.origin.url 2>&1
    echo "=== DONE ==="
} >> "${DIAG_LOG}" 2>&1

# Push the diag log via the same git-as-data-channel pattern
cp "${DIAG_LOG}" results/raman/phase33_diag.log 2>/dev/null || mkdir -p results/raman && cp "${DIAG_LOG}" results/raman/phase33_diag.log

git config user.email "${GIT_AUTHOR_EMAIL:-ijl27@cornell.edu}" || true
git config user.name  "${GIT_AUTHOR_NAME:-Ignacio Lizama (ephemeral diag)}" || true
git fetch origin main --quiet || true
git pull --rebase origin main 2>&1 | tail -3 || true
git add -f results/raman/phase33_diag.log
git commit -m "chore(phase33): ephemeral diagnostic log" || true
for i in 1 2 3; do
    if git push origin main 2>&1 | tee /tmp/p33_diag_push.log; then
        echo "[diag] push ok"
        break
    fi
    git fetch origin main --quiet
    git rebase origin/main 2>&1 | tail -5 || { git rebase --abort 2>/dev/null || true; break; }
done
echo "[phase33-diag] done"
exit 0
