#!/usr/bin/env bash
# scripts/cost_audit_run_BC.sh
# ────────────────────────────────────────────────────────────────────────────
# Recovery batch: re-run Config B (with widened time_window=150 ps) and
# Config C using a fast-mode Hessian (nev=8, tol=1e-3) so the batch
# completes within the ephemeral VM's 6h auto-shutdown budget.
#
# Config A was already completed under the default (nev=32, tol=1e-6) in
# the first batch; we keep its results as-is.
#
# Config C's linear variant got stuck for 3+ hours on the first try at
# nev=32 (most likely in Arpack :LR at high-nonlinearity), so the recovery
# reduces eigenspectrum fidelity to finish in time.
#
# Honors COST_AUDIT_SKIP_GIT_SYNC=1.
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

export GIT_AUTHOR_NAME="Ignacio Lizama (burst)"
export GIT_AUTHOR_EMAIL="ijl27@cornell.edu"
export GIT_COMMITTER_NAME="Ignacio Lizama (burst)"
export GIT_COMMITTER_EMAIL="ijl27@cornell.edu"

# Fast-mode Hessian (recovery parameters)
export CA_NEV=8
export CA_ARPACK_TOL=1e-3
export CA_ARPACK_MAXITER=200

JULIA="julia -t auto --project=."

echo "== cost_audit_run_BC.sh :: $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
echo "== hostname: $(hostname)"
echo "== CA_NEV=$CA_NEV CA_ARPACK_TOL=$CA_ARPACK_TOL"

if [[ "${COST_AUDIT_SKIP_GIT_SYNC:-0}" == "1" ]]; then
    echo "== git sync skipped"
else
    git fetch origin
    git checkout sessions/H-cost
    git pull origin sessions/H-cost
fi

echo "== Re-running Config B + Config C (4 variants each) in fast-Hessian mode"
$JULIA -e '
include("scripts/cost_audit_driver.jl")
for cfg_tag in [:B, :C]
    for v in [:linear, :log_dB, :sharp, :curvature]
        @info "━━━ run $cfg_tag/$v ━━━"
        try
            run_one(v, cfg_tag; max_iter=100, Nt=8192, save=true,
                    results_root=CA_RESULTS_ROOT)
        catch e
            @error "$cfg_tag/$v FAILED" exception=(e, catch_backtrace())
        end
    end
end
'

echo "== done $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
