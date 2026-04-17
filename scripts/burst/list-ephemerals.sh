#!/usr/bin/env bash
# list-ephemerals.sh — list any ephemeral burst VMs that are currently
# running, and offer to destroy them. Safety net if burst-spawn-temp's
# trap failed to clean up.
#
# Usage:  ~/bin/burst-list-ephemerals           # list only
#         ~/bin/burst-list-ephemerals --destroy # destroy every one

set -euo pipefail

PROJECT="${BURST_PROJECT:-riveralab}"
ZONE="${BURST_ZONE:-us-east5-a}"

MODE="${1:-list}"

mapfile -t VMS < <(gcloud compute instances list \
    --project="$PROJECT" \
    --filter="labels.purpose=ephemeral AND zone:($ZONE)" \
    --format="value(name,status,creationTimestamp)" 2>/dev/null)

if [[ ${#VMS[@]} -eq 0 ]]; then
    echo "no ephemeral burst VMs found."
    exit 0
fi

echo "ephemeral burst VMs ($ZONE):"
printf '  %s\n' "${VMS[@]}"
echo ""

if [[ "$MODE" == "--destroy" ]]; then
    for entry in "${VMS[@]}"; do
        name=$(echo "$entry" | awk '{print $1}')
        echo "destroying $name..."
        gcloud compute instances delete "$name" \
            --zone="$ZONE" --project="$PROJECT" --quiet
    done
fi
