#!/usr/bin/env bash
# scripts/cost_audit_spawn_direct.sh
# ────────────────────────────────────────────────────────────────────────────
# Custom ephemeral-VM spawner for Session H. Works around the two issues that
# made burst-spawn-temp unusable for this phase:
#   1. Image age beats my latest commit (scripts/cost_audit_run_batch.sh
#      doesn't exist in the image).
#   2. git fetch/pull on the ephemeral VM fails silently (auth not preserved
#      in the machine image clone) → CMD never runs.
#
# Strategy: create VM, SCP the code tarball in, run via burst-run-heavy,
# SCP results out, destroy VM on exit.
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

PROJECT="${BURST_PROJECT:-riveralab}"
ZONE="${BURST_ZONE:-us-east5-a}"
MACHINE_IMAGE="${BURST_MACHINE_IMAGE:-fiber-raman-burst-template}"
MACHINE_TYPE="${BURST_MACHINE_TYPE:-c3d-standard-16}"
AUTO_SHUTDOWN_MINUTES="${BURST_AUTO_SHUTDOWN_MINUTES:-360}"

SESSION="H-auditF"
TIMESTAMP=$(date -u +%Y%m%dt%H%M%Sz)
VM_NAME="fiber-raman-temp-${SESSION,,}-${TIMESTAMP}"
VM_NAME="${VM_NAME:0:63}"

LOGROOT="/tmp/${SESSION}"
mkdir -p "$LOGROOT"
LOG="$LOGROOT/direct_spawn.log"
: > "$LOG"

log() { echo "[$(date -u +%H:%M:%SZ)] $*" | tee -a "$LOG"; }

destroy_vm() {
    log "destroying $VM_NAME"
    gcloud compute instances delete "$VM_NAME" \
        --zone="$ZONE" --project="$PROJECT" --quiet \
        >/dev/null 2>&1 || log "WARN: destroy failed"
}
trap destroy_vm EXIT INT TERM

# ── step 1: create VM from machine image ─────────────────────────────────────
log "creating ephemeral VM: $VM_NAME ($MACHINE_TYPE)"
gcloud compute instances create "$VM_NAME" \
    --source-machine-image="$MACHINE_IMAGE" \
    --machine-type="$MACHINE_TYPE" \
    --zone="$ZONE" \
    --project="$PROJECT" \
    --labels="purpose=ephemeral,session-tag=${SESSION,,},spawned-by=cost-audit-spawn-direct" \
    >/dev/null

# ── step 2: wait for SSH ─────────────────────────────────────────────────────
log "waiting for SSH"
tries=0
while (( tries < 30 )); do
    if gcloud compute ssh "$VM_NAME" \
        --zone="$ZONE" --project="$PROJECT" \
        --command='true' \
        --ssh-flag='-o ConnectTimeout=10' \
        --ssh-flag='-o StrictHostKeyChecking=no' \
        >/dev/null 2>&1; then
        log "SSH ready"
        break
    fi
    tries=$((tries + 1))
    sleep 10
done
if (( tries >= 30 )); then
    log "ERROR: SSH never became available"
    exit 1
fi

# ── step 3: safety-net auto-shutdown ─────────────────────────────────────────
log "scheduling ${AUTO_SHUTDOWN_MINUTES}-minute auto-shutdown"
gcloud compute ssh "$VM_NAME" \
    --zone="$ZONE" --project="$PROJECT" \
    --ssh-flag='-o StrictHostKeyChecking=no' \
    --command="sudo shutdown -h +${AUTO_SHUTDOWN_MINUTES}" \
    >/dev/null 2>&1 || log "WARN: auto-shutdown schedule failed (trap is primary)"

# ── step 4: scp source files ─────────────────────────────────────────────────
# Send only the files this session touched / needs, rooted at HOME on the VM.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo $PWD)"
log "packaging source files from $REPO_ROOT"

STAGE_DIR=$(mktemp -d)
# Mirror the directory layout the VM expects.
mkdir -p "$STAGE_DIR/fiber-raman-suppression/scripts"
mkdir -p "$STAGE_DIR/fiber-raman-suppression/test"

# Core files the batch touches (copy from the worktree we're in)
for f in \
    scripts/cost_audit_driver.jl \
    scripts/cost_audit_analyze.jl \
    scripts/cost_audit_noise_aware.jl \
    scripts/cost_audit_run_batch.sh \
    scripts/cost_audit_run_B_only.sh \
    scripts/cost_audit_run_BC.sh \
    scripts/standard_images.jl \
    scripts/visualization.jl \
    scripts/common.jl \
    scripts/raman_optimization.jl \
    scripts/sharpness_optimization.jl \
    scripts/determinism.jl \
    scripts/phase13_primitives.jl \
    scripts/phase13_hvp.jl \
    scripts/phase13_hessian_eigspec.jl \
    test/test_cost_audit_unit.jl \
    test/test_cost_audit_integration_A.jl \
    test/test_cost_audit_analyzer.jl \
    test/test_phase14_regression.jl \
    test/test_determinism.jl \
; do
    if [[ -f "$REPO_ROOT/$f" ]]; then
        cp "$REPO_ROOT/$f" "$STAGE_DIR/fiber-raman-suppression/$f"
    else
        log "WARN: missing source file $f (ok if baked in image)"
    fi
done

# Tarball for efficient transfer
TAR="$STAGE_DIR/payload.tgz"
tar czf "$TAR" -C "$STAGE_DIR" fiber-raman-suppression
log "tarball size: $(stat -c %s "$TAR") bytes"

# Transfer
log "scp-ing tarball"
if ! gcloud compute scp "$TAR" "$VM_NAME:/tmp/payload.tgz" \
        --zone="$ZONE" --project="$PROJECT" \
        --scp-flag='-o StrictHostKeyChecking=no' \
        >>"$LOG" 2>&1 ; then
    log "ERROR: scp failed"
    cat "$LOG" | tail -20
    exit 1
fi

# Extract on the VM (overwrites files in ~/fiber-raman-suppression)
log "extracting tarball on VM"
gcloud compute ssh "$VM_NAME" \
    --zone="$ZONE" --project="$PROJECT" \
    --ssh-flag='-o StrictHostKeyChecking=no' \
    --command="cd \$HOME && tar xzf /tmp/payload.tgz && chmod +x fiber-raman-suppression/scripts/cost_audit_run_batch.sh && ls -la fiber-raman-suppression/scripts/cost_audit_run_batch.sh fiber-raman-suppression/scripts/cost_audit_driver.jl" \
    2>&1 | tee -a "$LOG"

# ── step 5: run the batch via burst-run-heavy ────────────────────────────────
# The in-CMD git step is now a no-op / belt-and-suspenders. If it fails (auth
# issue) we fall through to the script, which is now definitely present.
INNER_CMD="cd ~/fiber-raman-suppression && bash scripts/cost_audit_run_final.sh"

log "running batch via burst-run-heavy H-audit"
# Skip the git-sync in the batch script by setting an env var the script honors.
# We allow this step to fail without tripping set -e (batch may error mid-run;
# we still want to pull any partial results back).
set +e
gcloud compute ssh "$VM_NAME" \
    --zone="$ZONE" --project="$PROJECT" \
    --ssh-flag='-o StrictHostKeyChecking=no' \
    --ssh-flag='-o ServerAliveInterval=60' \
    --ssh-flag='-o ServerAliveCountMax=10' \
    --command="cd fiber-raman-suppression && export PATH=\$HOME/.juliaup/bin:\$HOME/bin:\$PATH && COST_AUDIT_SKIP_GIT_SYNC=1 ~/bin/burst-run-heavy $SESSION '$INNER_CMD'" \
    2>&1 | tee -a "$LOG"
BATCH_RC=${PIPESTATUS[0]}
set -e
log "batch exit code: $BATCH_RC"

# ── step 6: collect results ──────────────────────────────────────────────────
log "pulling results tarball back"
set +e
gcloud compute ssh "$VM_NAME" \
    --zone="$ZONE" --project="$PROJECT" \
    --ssh-flag='-o StrictHostKeyChecking=no' \
    --command="cd \$HOME/fiber-raman-suppression && tar czf /tmp/results.tgz results/cost_audit results/burst-logs 2>/dev/null || true; ls -la /tmp/results.tgz 2>&1 || true" \
    2>&1 | tee -a "$LOG"

mkdir -p "$REPO_ROOT/results"
gcloud compute scp "$VM_NAME:/tmp/results.tgz" "$LOGROOT/results.tgz" \
    --zone="$ZONE" --project="$PROJECT" \
    --scp-flag='-o StrictHostKeyChecking=no' \
    2>&1 | tee -a "$LOG"
set -e

if [[ -f "$LOGROOT/results.tgz" ]]; then
    tar xzf "$LOGROOT/results.tgz" -C "$REPO_ROOT" 2>&1 | tee -a "$LOG"
    log "results extracted to $REPO_ROOT/results/cost_audit"
else
    log "WARN: no results tarball — batch likely errored before producing results"
fi

log "done (batch rc=$BATCH_RC)"
