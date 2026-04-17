#!/usr/bin/env bash
# install.sh — install the burst VM coordination discipline on fiber-raman-burst.
# Run ONCE from claude-code-host: bash scripts/burst/install.sh
#
# Installs:
#   1. run-heavy.sh and watchdog.sh made executable inside the repo on burst VM
#   2. Systemd --user service that runs watchdog.sh continuously
#   3. ~/bin/burst-status helper that shows lock + tmux state
#
# Idempotent — safe to re-run.

set -euo pipefail

RMT=fiber-raman-burst
ZONE=us-east5-a
PROJECT=riveralab

echo "=== Step 1: make burst scripts executable on $RMT ==="
gcloud compute ssh --zone="$ZONE" --project="$PROJECT" "$RMT" --command='
    set -e
    cd fiber-raman-suppression
    chmod +x scripts/burst/run-heavy.sh scripts/burst/watchdog.sh scripts/burst/install.sh 2>/dev/null || true
    ls -la scripts/burst/
'

echo "=== Step 2: install watchdog as systemd --user service ==="
gcloud compute ssh --zone="$ZONE" --project="$PROJECT" "$RMT" --command='
    set -e
    mkdir -p ~/.config/systemd/user
    cat > ~/.config/systemd/user/raman-watchdog.service <<SERVICE
[Unit]
Description=Raman burst VM watchdog (load and memory safety net)
After=network.target

[Service]
Type=simple
ExecStart=%h/fiber-raman-suppression/scripts/burst/watchdog.sh
Restart=on-failure
RestartSec=30
StandardOutput=append:%h/watchdog.log
StandardError=append:%h/watchdog.log

[Install]
WantedBy=default.target
SERVICE
    systemctl --user daemon-reload
    systemctl --user enable raman-watchdog.service
    systemctl --user restart raman-watchdog.service
    sleep 2
    systemctl --user status raman-watchdog.service --no-pager | head -15
    # Make systemd user session persist across logout (ensures watchdog keeps running)
    sudo loginctl enable-linger "$(whoami)" 2>/dev/null || true
'

echo "=== Step 3: install ~/bin/burst-status and ~/bin/burst-run-heavy helpers on $RMT ==="
gcloud compute ssh --zone="$ZONE" --project="$PROJECT" "$RMT" --command='
    set -e
    mkdir -p ~/bin
    cat > ~/bin/burst-status <<"EOF"
#!/usr/bin/env bash
# On-VM status — lock holder + tmux sessions + watchdog state
LOCK=/tmp/burst-heavy-lock
echo "=== heavy lock ==="
if [[ -f "$LOCK" ]]; then
    cat "$LOCK"
    echo ""
    pid=$(grep -E "^pid=" "$LOCK" | cut -d= -f2)
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        echo "  (STALE — pid $pid is not running; lock will be cleared on next run)"
    fi
else
    echo "(no lock held)"
fi

echo ""
echo "=== tmux sessions ==="
tmux list-sessions 2>/dev/null || echo "(none)"

echo ""
echo "=== heavy julia processes (RSS > 1GB) ==="
ps -eo pid,etime,rss,cmd | awk "NR==1 || (\$3 > 1048576 && /julia/)"

echo ""
echo "=== load / mem ==="
uptime
free -h | head -2

echo ""
echo "=== watchdog ==="
systemctl --user is-active raman-watchdog.service 2>/dev/null || echo "(not running)"
tail -5 ~/watchdog.log 2>/dev/null || true
EOF
    chmod +x ~/bin/burst-status
    echo "installed ~/bin/burst-status"
'

echo ""
echo "=== Install complete. ==="
echo ""
echo "Verify with:  burst-ssh 'burst-status'"
