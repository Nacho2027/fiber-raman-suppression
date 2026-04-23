#!/usr/bin/env bash
# scripts/cost_audit_run_B_only.sh
# ────────────────────────────────────────────────────────────────────────────
# Recovery batch: re-run Config B's 4 variants after widening its
# time_window to 150 ps (was 45 ps, which triggered Nt auto-grow and tripped
# the strict_nt guard). Same contract as cost_audit_run_batch.sh but
# iterates only :B.
#
# Honors COST_AUDIT_SKIP_GIT_SYNC=1 (set by the spawner when files arrive
# via scp rather than git pull).
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

export GIT_AUTHOR_NAME="Ignacio Lizama (burst)"
export GIT_AUTHOR_EMAIL="ijl27@cornell.edu"
export GIT_COMMITTER_NAME="Ignacio Lizama (burst)"
export GIT_COMMITTER_EMAIL="ijl27@cornell.edu"

JULIA="julia -t auto --project=."

echo "== cost_audit_run_B_only.sh :: $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
echo "== hostname: $(hostname)"

if [[ "${COST_AUDIT_SKIP_GIT_SYNC:-0}" == "1" ]]; then
    echo "== git sync skipped"
else
    git fetch origin
    git checkout sessions/H-cost
    git pull origin sessions/H-cost
fi

echo "== Re-running Config B (4 variants) with widened time_window"
$JULIA -e '
include("scripts/cost_audit_driver.jl")
for v in [:linear, :log_dB, :sharp, :curvature]
    @info "━━━ re-run B/$v ━━━"
    try
        run_one(v, :B; max_iter=100, Nt=8192, save=true,
                results_root=CA_RESULTS_ROOT)
    catch e
        @error "B/$v FAILED" exception=(e, catch_backtrace())
    end
end
'

echo "== done $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
