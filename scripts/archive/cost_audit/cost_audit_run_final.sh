#!/usr/bin/env bash
# scripts/cost_audit_run_final.sh
# ────────────────────────────────────────────────────────────────────────────
# Final recovery run. :sharp variant hung 1h 51m on B/sharp at L=5m
# (Hutchinson-sampled forward solves too expensive in this regime) and
# got killed. For the remaining budget we skip :sharp and run the fast
# variants for everything that doesn't yet have a JLD2:
#
#   - B/curvature                    (1 run, expected ~30 min)
#   - C/linear, log_dB, curvature    (3 runs, ~30-60 min each)
#
# Hessian is skipped for this batch (CA_SKIP_HESSIAN=1) because the
# existing Config A runs used nev=32 and any partial-fidelity Hessian
# from B/C would not be comparable. The decision doc will note that
# Hessian metrics are Config-A-only.
#
# Honors COST_AUDIT_SKIP_GIT_SYNC=1.
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

export GIT_AUTHOR_NAME="Ignacio Lizama (burst)"
export GIT_AUTHOR_EMAIL="ijl27@cornell.edu"
export CA_NEV=8
export CA_ARPACK_TOL=1e-3
export CA_SKIP_HESSIAN=1

JULIA="julia -t auto --project=."

echo "== cost_audit_run_final.sh :: $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
echo "== CA_SKIP_HESSIAN=$CA_SKIP_HESSIAN"

if [[ "${COST_AUDIT_SKIP_GIT_SYNC:-0}" != "1" ]]; then
    git fetch origin
    git checkout sessions/H-cost
    git pull origin sessions/H-cost
fi

# Run the fast variants; :sharp skipped because it hung on B/sharp for
# ~2h before being killed (Hutchinson FD at L=5m P=0.2W too slow).
$JULIA -e '
include("scripts/cost_audit_driver.jl")
runs = [
    (:curvature, :B),
    (:linear,    :C),
    (:log_dB,    :C),
    (:curvature, :C),
]
for (v, cfg) in runs
    @info "━━━ run $cfg/$v ━━━"
    try
        run_one(v, cfg; max_iter=100, Nt=8192, save=true,
                results_root=CA_RESULTS_ROOT)
    catch e
        @error "$cfg/$v FAILED" exception=(e, catch_backtrace())
    end
end
'

echo "== done $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
