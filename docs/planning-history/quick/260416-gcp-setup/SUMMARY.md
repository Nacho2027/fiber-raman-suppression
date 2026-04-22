---
phase: quick
plan: 260416-gcp-setup
status: awaiting-user-action
subsystem: infrastructure
tags: [gcp, vm, claude-code, remote-dev]
completed: "2026-04-16T15:45:00Z"
blocker: "User must authenticate Claude Code via browser OAuth on the VM (one-time)"
---

# Quick Task: Autonomous GCP Setup — claude-code-host + fiber-raman-burst

## Infrastructure state

| Resource | ID / IP | Spec | Zone | Status |
|---|---|---|---|---|
| claude-code-host | `instance-20260416-150007` / `34.152.124.66` | e2-standard-2, 2 vCPU, 8 GB RAM, Debian 12 | us-east5-a | **RUNNING** (always-on) |
| fiber-raman-burst | `fiber-raman-burst` / `34.186.245.123` | c3-highcpu-22, 22 vCPU, 44 GB RAM, Debian 12 | us-east5-a | **STOPPED** (no billing) |
| Firewall rule: `allow-mosh` | UDP 60000–61000 from 0.0.0.0/0 | — | global | **ACTIVE** |

Note: user created claude-code-host with Debian 12 (not Ubuntu 22.04 as originally specified in the todo). Setup adapted accordingly. AMD C3D not available in us-east5-a, so burst uses C3 (Intel Sapphire Rapids) — equivalent for this workload.

## What was installed autonomously

### On claude-code-host (34.152.124.66)
- [x] apt packages: tmux, git, build-essential, curl, rsync, mosh, python3-matplotlib, python3-numpy, ca-certificates
- [x] juliaup + Julia 1.12.6
- [x] Node.js 20.20.2 + npm 10.8.2
- [x] Claude Code CLI 2.1.111 (NOT YET AUTHENTICATED — user action required)
- [x] gcloud CLI 565.0.0 (on the VM)
- [x] Repo cloned: `~/fiber-raman-suppression` from `github.com/Nacho2027/fiber-raman-suppression.git`
- [x] `.planning/` rsync'd from local Mac (since `.planning/` is gitignored — current files not tracked in git)
- [x] Pkg.instantiate + Pkg.precompile in progress (background, ~10 min)
- [x] Helper scripts at `~/bin/`: `burst-start`, `burst-stop`, `burst-ssh`, `burst-status`
- [x] `~/bin/` added to PATH in `.bashrc`
- [x] VM service account scopes widened to `cloud-platform` (enables helper scripts to control burst VM from within claude-code-host)

### On fiber-raman-burst (stopped, 34.186.245.123 when running)
- [x] apt packages: same set as claude-code-host
- [x] juliaup + Julia 1.12.6
- [x] Repo cloned: `~/fiber-raman-suppression`
- [x] Pkg.instantiate + Pkg.precompile **COMPLETE** (364 dependencies precompiled in 228 s, MultiModeNoise included)
- [x] VM stopped after precompile (billing paused)

### On local Mac
- [x] SSH key auto-generated at `~/.ssh/google_compute_engine` (by gcloud on first SSH)
- [x] `~/bin/sync-planning-to-vm` — rsync local `.planning/` → claude-code-host
- [x] `~/bin/sync-planning-from-vm` — rsync claude-code-host `.planning/` → local
- [x] `~/bin/` added to PATH in `.zshrc`

## USER ACTION REQUIRED (the only thing I literally could not do)

**Authenticate Claude Code on claude-code-host** — this is a one-time browser OAuth and requires you to click links / paste codes.

```bash
# From your Mac:
mosh ignaciojlizama@34.152.124.66
# OR if mosh is flaky: ssh -i ~/.ssh/google_compute_engine ignaciojlizama@34.152.124.66

# On the VM:
tmux new -s main       # start a persistent session
claude login           # follow the browser OAuth flow — paste URL into your local browser
                       # log in with ijl27@cornell.edu
# Once authenticated:
claude                 # starts Claude Code
```

Detach from tmux with `Ctrl-b d` — session (and Claude Code) keeps running. Reattach later with `mosh ignaciojlizama@34.152.124.66` → `tmux attach -t main`.

## Daily workflow (now that setup is done)

**Normal editing/dev day:**
```bash
# From Mac:
mosh ignaciojlizama@34.152.124.66
tmux attach -t main    # or: tmux new -s main if first time
# Claude Code is running inside tmux. Edit, commit, push.
```

**When you need to run a heavy Newton job:**
```bash
# On claude-code-host (inside Claude Code or plain shell):
cd ~/fiber-raman-suppression
git add . && git commit -m "wip: ready for burst run" && git push

burst-start                                           # ~30 s
burst-ssh "cd fiber-raman-suppression && git pull && \
           tmux new -d -s run 'julia -t 22 --project=. scripts/your_script.jl > run.log 2>&1'"

# Monitor:
burst-ssh "tail -f fiber-raman-suppression/run.log"

# When done:
rsync -az -e "gcloud compute ssh --zone=us-east5-a --project=riveralab --" \
      fiber-raman-burst:~/fiber-raman-suppression/results/ \
      ~/fiber-raman-suppression/results/
burst-stop
```

**When .planning/ changes on your Mac and you want it on the VM:**
```bash
# From Mac:
sync-planning-to-vm
```

**When Claude Code on the VM edits .planning/ and you want it on your Mac:**
```bash
# From Mac:
sync-planning-from-vm
```

## Cost check

- claude-code-host (e2-standard-2) always-on: ~$0.084/hr × 672 hrs = **~$56 for the sprint**
- fiber-raman-burst (c3-highcpu-22) currently stopped → $0/day while stopped; pay ~$0.90/hr only when started
- Projected total: claude-code-host $56 + burst (~260 hrs across sprint) $234 + disks/egress ~$5 = **~$295 / $300** free trial budget

## Critical warning: budget alert

**⚠ Before walking away from this, set up the budget alert in the GCP console.**

Billing → Budgets & alerts → Create budget:
- Amount: $300
- Alert thresholds: 50%, 80%, 95%
- Email: `ijl27@cornell.edu`

I couldn't do this via gcloud CLI without additional API enablement. Takes 2 minutes in the console. Prevents surprise charges when the free trial is close to exhaustion.

## Verification checklist

Run these from your Mac to confirm everything works:

```bash
# 1. SSH to claude-code-host
mosh ignaciojlizama@34.152.124.66

# 2. On the VM, verify tooling
julia --version                    # should show 1.12.6
gcloud compute instances list       # should show both VMs
burst-status                        # should show TERMINATED (= stopped)

# 3. Test burst VM control
burst-start                         # takes ~30 s
burst-status                        # should show RUNNING
burst-ssh "julia --version"         # should show 1.12.6 on burst VM
burst-stop                          # wait for it to actually stop
burst-status                        # should show TERMINATED again

# 4. Claude Code auth (user action)
claude login                        # browser OAuth
```

## Files touched

- `.planning/quick/260416-gcp-setup/SUMMARY.md` (this file)
- Local `~/bin/sync-planning-to-vm`, `~/bin/sync-planning-from-vm` (helper scripts on Mac)

No repo source code modified. No git commits on the codebase.
