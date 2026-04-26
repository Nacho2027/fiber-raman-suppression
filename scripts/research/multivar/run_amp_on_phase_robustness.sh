#!/usr/bin/env bash

set -euo pipefail

# Small neighborhood check around the reproduced canonical
# L=2.0 m, P=0.30 W amplitude-on-phase result.
#
# Override MV_AMP_ROBUST_POINTS with entries of the form tag:L:P, separated by
# spaces. Example:
#   MV_AMP_ROBUST_POINTS="L1p9_P0p30:1.9:0.30 L2p0_P0p31:2.0:0.31" \
#     scripts/research/multivar/run_amp_on_phase_robustness.sh

POINTS="${MV_AMP_ROBUST_POINTS:-L1p8_P0p30:1.8:0.30 L2p2_P0p30:2.2:0.30 L2p0_P0p27:2.0:0.27 L2p0_P0p33:2.0:0.33}"
TAG_PREFIX="${MV_AMP_ROBUST_TAG_PREFIX:-$(date -u +%Y%m%dT%H%M%SZ)_robust}"
PHASE_ITER="${MV_AMP_PHASE_PHASE_ITER:-50}"
AMP_ITER="${MV_AMP_PHASE_AMP_ITER:-60}"

for spec in ${POINTS}; do
    IFS=: read -r tag L P <<< "${spec}"
    echo "=== amp-on-phase robustness ${tag} L=${L} P=${P} ==="
    MV_AMP_PHASE_TAG="${TAG_PREFIX}_${tag}" \
    MV_AMP_PHASE_L_FIBER="${L}" \
    MV_AMP_PHASE_P_CONT="${P}" \
    MV_AMP_PHASE_PHASE_ITER="${PHASE_ITER}" \
    MV_AMP_PHASE_AMP_ITER="${AMP_ITER}" \
        julia -t auto --project=. scripts/research/multivar/multivar_amp_on_phase_ablation.jl
done
