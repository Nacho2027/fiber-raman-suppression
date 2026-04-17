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

echo "=== Step 1: install scripts into ~/bin (branch-independent) on $RMT ==="
# We keep the canonical source in scripts/burst/ on main, but deploy the
# executables to ~/bin so they survive when a session checks out a branch
# that doesn't contain scripts/burst/.
gcloud compute ssh --zone="$ZONE" --project="$PROJECT" "$RMT" --command='
    set -e
    mkdir -p ~/bin
    cd fiber-raman-suppression
    # Fetch latest main; pull the scripts via "git show" so we do not require
    # the checkout to be on main.
    git fetch origin main --quiet
    git show origin/main:scripts/burst/run-heavy.sh > ~/bin/burst-run-heavy
    git show origin/main:scripts/burst/watchdog.sh > ~/bin/burst-watchdog
    chmod +x ~/bin/burst-run-heavy ~/bin/burst-watchdog
    ls -la ~/bin/burst-run-heavy ~/bin/burst-watchdog
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
ExecStart=%h/bin/burst-watchdog
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
