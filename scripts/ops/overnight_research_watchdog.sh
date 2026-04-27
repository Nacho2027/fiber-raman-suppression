#!/usr/bin/env bash

set -euo pipefail

PROJECT="${BURST_PROJECT:-riveralab}"
ZONE="${BURST_ZONE:-us-east5-a}"
REPO="${FIBER_REPO:-/home/ignaciojlizama/fiber-raman-suppression}"
DATE_TAG="${OVERNIGHT_DATE_TAG:-20260427}"
LOG_DIR="$REPO/results/burst-logs/overnight/$DATE_TAG"
LOG_FILE="$LOG_DIR/watchdog.log"
PATH="$HOME/bin:$HOME/.juliaup/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

mkdir -p "$LOG_DIR"
cd "$REPO"

log() {
    printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG_FILE"
}

has_tmux() {
    tmux has-session -t "$1" >/dev/null 2>&1
}

active_instance_names() {
    gcloud compute instances list \
        --project="$PROJECT" \
        --filter='name~fiber-raman AND status:(RUNNING OR STAGING OR PROVISIONING)' \
        --format='value(name)' 2>/dev/null || true
}

vm_exists() {
    local pattern="$1"
    active_instance_names | grep -E "$pattern" >/dev/null 2>&1
}

raw_ssh_vm() {
    local vm="$1"
    shift
    local ip
    ip=$(gcloud compute instances describe "$vm" \
        --project="$PROJECT" --zone="$ZONE" \
        --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || true)
    [[ -n "$ip" ]] || return 1
    ssh -i "$HOME/.ssh/google_compute_engine" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        "ignaciojlizama@$ip" "$@"
}

launch_multivar_sequence() {
    if has_tmux overnight-multivar-seq4 || vm_exists 'fiber-raman-temp-v-mv'; then
        return 0
    fi

    log "restarting multivar sequential supervisor"
    tmux new-session -d -s overnight-multivar-seq4 "
        cd '$REPO' &&
        for case_tag in \
            energy_on_phase:V-mvengoph4 \
            amp_on_phase:V-mvampoph4 \
            amp_energy_on_phase:V-mvampeoph4 \
            phase_energy_cold:V-mvpheng4 \
            phase_amp_energy_warm:V-mvphampe4 \
            amp_energy_unshaped:V-mvampeun4
        do
            case=\${case_tag%%:*}
            tag=\${case_tag##*:}
            result_dir=\"results/raman/multivar/variable_ablation_overnight_\${case}_20260427\"
            if [[ -f \"\$result_dir/\${case}_result.jld2\" ]]; then
                echo \"[\$(date -u +%FT%TZ)] skipping completed \$case\" | tee -a '$LOG_DIR/multivar-seq4.log'
                continue
            fi
            while gcloud compute instances list --project='$PROJECT' --filter='name~fiber-raman-temp-v-mv AND status:(RUNNING OR STAGING OR PROVISIONING)' --format='value(name)' | grep -q .; do
                echo \"[\$(date -u +%FT%TZ)] waiting for active multivar ephemeral before \$case\" | tee -a '$LOG_DIR/multivar-seq4.log'
                sleep 300
            done
            echo \"[\$(date -u +%FT%TZ)] launching \$case as \$tag\" | tee -a '$LOG_DIR/multivar-seq4.log'
            BURST_AUTO_SHUTDOWN_HOURS=16 BURST_SYNC_RETRIES=10 BURST_SYNC_RETRY_SLEEP=90 PARALLEL_ALLOW_DIRTY=1 \
                scripts/ops/parallel_research_lane.sh \
                    --lane multivar \
                    --target ephemeral \
                    --tag \"\$tag\" \
                    --machine-type c3-highcpu-8 \
                    --cmd \"MV_ABLATION_TAG=overnight_\${case}_20260427 MV_ABLATION_CASES=\${case} MV_ABLATION_PHASE_ITER=35 MV_ABLATION_MV_ITER=50 MV_ABLATION_ENERGY_ITER=25 julia -t auto --project=. scripts/research/multivar/multivar_variable_ablation.jl\" \
                    --log-file \"'$LOG_DIR'/multivar-\${case}.log\" || true
            sleep 180
        done
    "
}

launch_longfiber_if_missing() {
    if has_tmux overnight-longfiber-hc8 || vm_exists 'fiber-raman-temp-l-200mhc8'; then
        return 0
    fi
    if [[ -f results/raman/phase16/200m_overngt_opt_full_result.jld2 ]]; then
        return 0
    fi

    log "restarting long-fiber 200m supervisor"
    tmux new-session -d -s overnight-longfiber-hc8 "
        cd '$REPO' &&
        BURST_AUTO_SHUTDOWN_HOURS=16 BURST_SYNC_RETRIES=10 BURST_SYNC_RETRY_SLEEP=90 PARALLEL_ALLOW_DIRTY=1 \
            scripts/ops/parallel_research_lane.sh \
                --lane longfiber \
                --target ephemeral \
                --tag L-200mhc8 \
                --machine-type c3-highcpu-8 \
                --cmd 'LF100_MODE=fresh LF100_L=200 LF100_NT=65536 LF100_TIME_WIN=320 LF100_RUN_LABEL=200m_overngt LF100_MAX_ITER=15 julia -t auto --project=. scripts/research/longfiber/longfiber_optimize_100m.jl' \
                --log-file '$LOG_DIR/longfiber-200mhc8.log'
    "
}

launch_mmf_if_missing() {
    if has_tmux overnight-mmf; then
        return 0
    fi
    if [[ -f results/raman/phase36_window_validation/mmf_window_validation_summary.md ]]; then
        return 0
    fi

    log "restarting MMF window-validation supervisor"
    tmux new-session -d -s overnight-mmf "
        cd '$REPO' &&
        PARALLEL_ALLOW_DIRTY=1 scripts/ops/parallel_research_lane.sh \
            --lane mmf \
            --target permanent \
            --tag M-mmfwin3 \
            --cmd 'MMF_VALIDATION_CASES=threshold,aggressive MMF_VALIDATION_MAX_ITER=8 MMF_VALIDATION_THRESHOLD_TW=96 MMF_VALIDATION_THRESHOLD_NT=8192 MMF_VALIDATION_AGGRESSIVE_TW=160 MMF_VALIDATION_AGGRESSIVE_NT=16384 julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl' \
            --log-file '$LOG_DIR/mmf-window-validation3.log'
    "
}

log "watchdog tick"
log "instances: $(active_instance_names | tr '\n' ' ')"
log "tmux: $(tmux ls 2>/dev/null | grep -E 'overnight|M-mmfwin3|L-200|V-mv' | tr '\n' ' ' || true)"

if vm_exists 'fiber-raman-temp-l-200mhc8'; then
    lf_vm=$(active_instance_names | grep 'fiber-raman-temp-l-200mhc8' | head -n1)
    raw_ssh_vm "$lf_vm" "cd ~/fiber-raman-suppression && ps -eo pid,etime,pcpu,pmem,cmd | grep -E 'L-200mhc8|longfiber|julia' | grep -v grep | head -n 8" \
        >> "$LOG_FILE" 2>&1 || log "WARN: longfiber VM SSH poll failed"
fi

if vm_exists 'fiber-raman-temp-v-mv'; then
    mv_vm=$(active_instance_names | grep 'fiber-raman-temp-v-mv' | head -n1)
    raw_ssh_vm "$mv_vm" "cd ~/fiber-raman-suppression && ps -eo pid,etime,pcpu,pmem,cmd | grep -E 'V-mv|multivar|julia' | grep -v grep | head -n 8" \
        >> "$LOG_FILE" 2>&1 || log "WARN: multivar VM SSH poll failed"
fi

launch_mmf_if_missing
launch_longfiber_if_missing
launch_multivar_sequence

log "watchdog done"
