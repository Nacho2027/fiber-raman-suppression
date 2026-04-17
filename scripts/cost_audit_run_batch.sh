#!/usr/bin/env bash
# scripts/cost_audit_run_batch.sh
# ────────────────────────────────────────────────────────────────────────────
# End-to-end batch script for Phase 16 Plan 16-02 on the burst VM (permanent
# or ephemeral via ~/bin/burst-spawn-temp H-audit ...).
#
# Invoked by burst-run-heavy — expects to already be in the repo root, on a
# host with Julia on PATH and the heavy-lock held.
#
# Stages (each fails fast via set -e):
#   1. Checkout sessions/H-cost, pull
#   2. Unit tests       (test_cost_audit_unit.jl)
#   3. Integration test (test_cost_audit_integration_A.jl)
#   4. Regression gates (test_phase14_regression.jl, test_determinism.jl)
#   5. 12-run batch     (cost_audit_driver.jl::run_all)
#   6. Analyzer         (cost_audit_analyze.jl)
#   7. Commit + push results back to sessions/H-cost
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

export GIT_AUTHOR_NAME="Ignacio Lizama (burst)"
export GIT_AUTHOR_EMAIL="ijl27@cornell.edu"
export GIT_COMMITTER_NAME="Ignacio Lizama (burst)"
export GIT_COMMITTER_EMAIL="ijl27@cornell.edu"

JULIA="julia -t auto --project=."

echo "== cost_audit_run_batch.sh :: $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
echo "== hostname: $(hostname)"
echo "== PATH: $PATH"

# Stage 1 — sync to sessions/H-cost (skip when files are scp'd directly)
if [[ "${COST_AUDIT_SKIP_GIT_SYNC:-0}" == "1" ]]; then
    echo "== [1/7] git sync skipped (COST_AUDIT_SKIP_GIT_SYNC=1, files delivered via scp)"
else
    echo "== [1/7] git checkout sessions/H-cost"
    git fetch origin
    git checkout sessions/H-cost
    git pull origin sessions/H-cost
fi

# Stage 2 — unit tests
echo "== [2/7] unit tests"
$JULIA test/test_cost_audit_unit.jl

# Stage 3 — integration test (4 variants, config A, Nt=1024)
echo "== [3/7] integration test"
$JULIA test/test_cost_audit_integration_A.jl

# Stage 4 — regressions
echo "== [4/7] Phase 14 + Phase 15 regressions"
$JULIA test/test_phase14_regression.jl
$JULIA test/test_determinism.jl

# Stage 5 — 12-run batch
echo "== [5/7] 12-run cost-audit batch (4 variants x 3 configs)"
$JULIA scripts/cost_audit_driver.jl

# Stage 6 — analyzer (CSVs + 4 figures + standard-image existence asserted by
#                      test_cost_audit_analyzer.jl)
echo "== [6/7] analyzer"
$JULIA scripts/cost_audit_analyze.jl
$JULIA test/test_cost_audit_analyzer.jl

# Stage 7 — publish results
# When run via cost_audit_spawn_direct.sh on an ephemeral VM, results are
# pulled back via scp (no git auth on the ephemeral). The caller will commit
# locally and push. When run on the permanent burst, commit + push directly.
if [[ "${COST_AUDIT_SKIP_GIT_SYNC:-0}" == "1" ]]; then
    echo "== [7/7] skipping git commit/push (spawner will collect results via scp)"
    du -sh results/cost_audit 2>/dev/null || true
else
    echo "== [7/7] commit + push results"
    git add results/cost_audit/ results/burst-logs/ 2>/dev/null || true
    if git diff --cached --quiet; then
        echo "no results changes to commit (unexpected, continuing)"
    else
        git commit -m "results(16-02): 12-run cost-audit batch + 48 standard images"
        git push origin sessions/H-cost
    fi
fi

echo "== cost_audit_run_batch.sh done :: $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
