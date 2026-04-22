---
title: Provision GCP split architecture (e2-standard-2 + c3-highcpu-22) + set up remote Julia/Claude Code environment
date: 2026-04-16
priority: high
context: First step of 4-week multimode (M=6) + Newton sprint. Blocks all downstream work. Uses GCP $300 free trial credit — zero out-of-pocket cost for the sprint.
---

# Provision GCP Split Architecture + Set Up Remote Environment

Blocks: multimode extension work, Newton optimizer implementation.
Expected time: **1 day**.
Target: always-on Claude Code on a small cheap VM + on-demand burst VM for heavy Newton runs, coordinated via gcloud CLI and synced via git.

## Architecture

```
Your Mac
   │ ssh/mosh
   ▼
┌──────────────────────────┐     gcloud start/stop     ┌─────────────────────────────┐
│ claude-code-host         │◄─────────────────────────►│ fiber-raman-burst           │
│ e2-standard-2            │                           │ c3-highcpu-22               │
│ 2 vCPU, 8 GB RAM         │   git push / pull         │ 22 vCPU, 44 GB RAM          │
│ ALWAYS-ON 24/7           │   rsync for results       │ STOPPED by default          │
│ Hosts Claude Code + tmux │                           │ Start on demand, stop after │
│ Light editing + dev      │                           │ run. Pay only active hours. │
│ ~$0.084/hr = ~$56/sprint │                           │ ~$0.90/hr = pay-as-you-run  │
└──────────────────────────┘                           └─────────────────────────────┘
```

**Division of responsibilities:**
- **claude-code-host** (always-on): SSH target from your Mac, hosts Claude Code in tmux, edits files, runs `gcloud` commands to control the burst VM, hosts lightweight Julia tests. 8 GB RAM leaves real headroom for Claude Code (Node runtime + large context windows easily use 1–2 GB).
- **fiber-raman-burst** (on-demand): where actual Newton / multimode compute runs. Started when you need it, stopped when you don't. 22 vCPU gives strong parallelism for Hessian column computation.

## Why split (vs single VM)

The single-VM option (`c3d-highcpu-16` always-on with stop/start discipline) was initially preferred. Replaced because:

- Stop/start kills "always-on Claude Code" — you have to manually restart every morning
- Running a 16-vCPU machine 24/7 is wasteful (Claude Code uses <1 vCPU)
- Split architecture lets you actually leave Claude Code running 24/7 for the cost of a cheap e2 instance, while paying for heavy compute only when you use it

Budget comparison (all within $300 free trial):

| Architecture | 24/7 always-on component | Burst compute | Total 4-week cost |
|---|---|---|---|
| Single c3d-highcpu-16, 14 hr/day | — | — | ~$255 |
| **Split: e2-standard-2 + c3-highcpu-22** | ~$56 | ~$234 (~260 hrs of burst) | **~$295** |
| Split: e2-medium + c3-highcpu-22 | ~$28 | ~$260 (~290 hrs of burst) | ~$293 |

260 hours of c3-highcpu-22 across 4 weeks ≈ 9 hrs/day of active heavy compute. Realistic and plenty.

## Budget math

$300 free trial ÷ 4 weeks = $75/week ≈ $10.70/day effective budget.

| Expense | Rate | Assumption | Cost |
|---|---|---|---|
| claude-code-host (e2-standard-2) 24/7 | $0.084/hr | 672 hours | **~$56** |
| fiber-raman-burst (c3-highcpu-22) active | $0.90/hr | ~260 hours across sprint | **~$234** |
| Boot disks (30 GB + 50 GB, balanced persistent) | ~$0.04/GB/month | 80 GB × 1 month | **~$3** |
| Network egress (typical small) | — | minimal | **~$2** |
| **Total** | | | **~$295 / $300** |

If you need more burst budget: downshift to **e2-medium** (4 GB RAM, ~$28 for the sprint) — frees up ~$28 for an extra ~31 burst hours. 4 GB is tight for Claude Code but usable.

## Steps

### Phase 1 — GCP account setup

1. **Sign up for GCP free trial**
   - Go to `console.cloud.google.com`
   - Sign in with personal or Cornell Google account
   - Click "Start free trial" → accept terms → add credit card (won't be charged within free tier)
   - Wait ~2 minutes for activation; $300 credit appears in Billing

2. **Create project**
   - Name: `fiber-raman`
   - Note the project ID (auto-generated)

3. **Enable Compute Engine API**
   - APIs & Services → Enable APIs → search "Compute Engine" → Enable
   - Takes ~60 seconds

4. **Set up billing alert (critical)**
   - Billing → Budgets & alerts → Create budget
   - Budget amount: $300
   - Alert thresholds: 50%, 80%, 95%
   - Email: `ijl27@cornell.edu`
   - Prevents surprise charges when the free trial is close to exhaustion

### Phase 2 — Create the always-on claude-code-host

5. **Create claude-code-host VM**
   - Compute Engine → VM instances → Create Instance
   - **Name:** `claude-code-host`
   - **Region:** `us-east1` (South Carolina — ~20 ms latency from Ithaca)
   - **Zone:** `us-east1-b`
   - **Machine configuration:**
     - Series: **E2**
     - Machine type: **e2-standard-2** (2 vCPU, 8 GB RAM)
   - **Boot disk:** Ubuntu 22.04 LTS, **30 GB**, Balanced persistent disk
   - **Identity and API access:** defaults
   - **Firewall:** Allow HTTP/HTTPS (optional)
   - **Advanced → Security → Manage SSH keys:** paste `~/.ssh/id_ed25519.pub` with username `ijl27`
   - Click **Create** → VM boots in ~1 minute

6. **Connect and install tooling on claude-code-host**
   ```bash
   ssh ijl27@<claude-code-host-ip>
   sudo apt update && sudo apt install -y mosh tmux build-essential git curl rsync python3-matplotlib
   ```

7. **Install gcloud CLI on claude-code-host** (so it can control the burst VM)
   ```bash
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   gcloud init
   # Authenticate with your Google account, pick the fiber-raman project
   ```

8. **Install Mosh firewall rule** (one-time, applies to both VMs)
   - GCP Console → VPC network → Firewall → Create firewall rule
   - Name: `allow-mosh`
   - Targets: All instances in the network
   - Source filter: your home/campus IP range (or `0.0.0.0/0` for convenience)
   - Protocols: UDP, ports `60000-61000`
   - On local Mac: `brew install mosh` if not installed
   - Test: `mosh ijl27@<claude-code-host-ip>`

9. **Install Claude Code on claude-code-host**
   - Follow official Claude Code install instructions
   - Authenticate with `ijl27@cornell.edu`
   - Test a minimal session (edit a file, run a command)
   - Start Claude Code inside a `tmux` session: `tmux new -s main` → run Claude Code → detach with `Ctrl-b d`

10. **Clone repo on claude-code-host**
    ```bash
    git clone <repo-url> ~/fiber-raman-suppression
    # Optional: install Julia here for light sanity checks
    # (skip if 8 GB is too tight — Julia plus Claude Code can coexist but with tight margins)
    curl -fsSL https://install.julialang.org | sh
    exec -l $SHELL
    juliaup add 1.12 && juliaup default 1.12
    cd ~/fiber-raman-suppression && julia --project=. -e 'using Pkg; Pkg.instantiate()'
    ```

### Phase 3 — Create the burst VM

11. **Create fiber-raman-burst VM**
    - Compute Engine → VM instances → Create Instance
    - **Name:** `fiber-raman-burst`
    - **Region / Zone:** `us-east1` / `us-east1-b` (same as claude-code-host — enables cheap VPC-internal traffic)
    - **Machine configuration:**
      - Series: **C3**
      - Machine type: **c3-highcpu-22** (22 vCPU, 44 GB RAM)
    - **Boot disk:** Ubuntu 22.04 LTS, **50 GB**, Balanced persistent disk
    - **Same SSH key** as claude-code-host
    - Click **Create** → VM boots in ~1 minute

12. **Install Julia stack on fiber-raman-burst**
    ```bash
    # From claude-code-host:
    gcloud compute ssh fiber-raman-burst --zone=us-east1-b

    # On the burst VM:
    sudo apt update && sudo apt install -y tmux build-essential git curl python3-matplotlib
    curl -fsSL https://install.julialang.org | sh
    exec -l $SHELL
    juliaup add 1.12 && juliaup default 1.12
    git clone <repo-url> ~/fiber-raman-suppression
    cd ~/fiber-raman-suppression
    julia -t 22 --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
    ```

13. **Stop the burst VM** (CRITICAL — stops billing until you start it again)
    ```bash
    # From claude-code-host or your Mac:
    gcloud compute instances stop fiber-raman-burst --zone=us-east1-b
    ```

14. **Install helper scripts on claude-code-host**
    Create `~/bin/burst-start`, `~/bin/burst-stop`, `~/bin/burst-ssh`:
    ```bash
    mkdir -p ~/bin
    cat > ~/bin/burst-start <<'EOF'
    #!/bin/bash
    gcloud compute instances start fiber-raman-burst --zone=us-east1-b
    EOF

    cat > ~/bin/burst-stop <<'EOF'
    #!/bin/bash
    gcloud compute instances stop fiber-raman-burst --zone=us-east1-b
    EOF

    cat > ~/bin/burst-ssh <<'EOF'
    #!/bin/bash
    gcloud compute ssh fiber-raman-burst --zone=us-east1-b -- "$@"
    EOF

    chmod +x ~/bin/burst-*
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    ```

### Phase 4 — Correctness + threading verification

15. **Baseline correctness check on burst VM**
    ```bash
    burst-start  # wait ~30 s for it to come up
    burst-ssh
    cd ~/fiber-raman-suppression
    julia -t 22 --project=. scripts/raman_optimization.jl
    # Compare output plot against known-good local M3 Max run (within ε)
    julia -t 22 --project=. scripts/test_optimization.jl  # all tests pass
    exit  # back to claude-code-host
    burst-stop
    ```

16. **Threading sanity check on burst VM**
    ```bash
    burst-start
    burst-ssh
    cd ~/fiber-raman-suppression
    julia -t 22 --project=. scripts/benchmark_threading.jl
    # Expect: similar ~3–4× on parallel forward solves vs M3 Max
    # At M>1 (if you test): Tullio threading should now show non-trivial speedup
    exit
    burst-stop
    ```

## Daily workflow once set up

**Normal day (editing, light work):**
1. From Mac: `mosh ijl27@<claude-code-host-ip>` → `tmux attach -t main`
2. Inside tmux: Claude Code is already running. Edit files, commit to git.

**When you need to run a heavy Newton job:**
```bash
# On claude-code-host:
cd ~/fiber-raman-suppression
git add . && git commit -m "wip: ready for burst run" && git push

burst-start                                               # ~30 s to boot
burst-ssh "cd fiber-raman-suppression && git pull && \
           tmux new -d -s run 'julia -t 22 --project=. scripts/your_newton_script.jl > run.log 2>&1'"

# Monitor:
burst-ssh "tail -f fiber-raman-suppression/run.log"

# When done, pull results back:
rsync -az -e "gcloud compute ssh --zone=us-east1-b --" \
      fiber-raman-burst:~/fiber-raman-suppression/results/ \
      ~/fiber-raman-suppression/results/
burst-stop
```

## Acceptance criteria

- [ ] GCP free trial activated, $300 credit showing in Billing
- [ ] Billing alert set at $250 (83% of free tier), 3 thresholds (50/80/95%), email to `ijl27@cornell.edu`
- [ ] `claude-code-host` (e2-standard-2, 8 GB RAM) running in `us-east1-b`, SSH + Mosh works from Mac
- [ ] `fiber-raman-burst` (c3-highcpu-22) exists and boots via `burst-start`, stops via `burst-stop`, confirmed STOPPED state
- [ ] Mosh UDP firewall rule in place, typing feels instant from Mac
- [ ] Claude Code installed on claude-code-host, authenticated, running in `tmux` session `main`
- [ ] `gcloud` CLI works on claude-code-host and can control the burst VM
- [ ] Burst VM has Julia 1.12 + Pkg.instantiated + precompiled
- [ ] `~/bin/burst-start`, `~/bin/burst-stop`, `~/bin/burst-ssh` scripts exist and on PATH
- [ ] Existing `raman_optimization.jl` on burst VM produces output plot matching M3 Max local run (within ε)
- [ ] `scripts/benchmark_threading.jl` runs on burst VM — results captured
- [ ] Quick M=6 correctness check run on burst VM (forward+adjoint only, no Newton) — confirms existing code paths work unchanged
- [ ] Cost dashboard shows claude-code-host burning ~$2/day, burst VM $0/day while stopped

## Out of scope

- Any multimode or Newton implementation work (belongs in the research phase, not this setup todo)
- CI/CD automation (not needed for a 4-week sprint)
- GPU setup (see compute-infrastructure-decision note for rationale)
- Shared persistent disk between the two VMs (git + rsync is simpler for this sprint)
- Persistent data beyond the boot disks (80 GB total is plenty; archive big outputs to git-LFS or GCS bucket if needed)

## Cost control playbook

- **Normal cadence:** claude-code-host 24/7 (~$0.084/hr = $2/day); fiber-raman-burst runs ~9 hrs/day average = ~$8/day. Total daily cost ~$10, aligns with $10.70/day budget.
- **If approaching budget cap mid-sprint:** leave claude-code-host on (it's cheap), reduce burst VM usage to targeted big runs only. Or downshift burst to c3-highcpu-8 (~$0.33/hr) when runs don't need all 22 cores.
- **If you need to burst harder for a specific run:** `gcloud compute instances set-machine-type fiber-raman-burst --zone=us-east1-b --machine-type=c3-highcpu-44` (requires VM stopped). Revert after the run. Confirms 44 vCPU × ~$1.80/hr burn rate before committing to long runs at that size.
- **When sprint ends:** delete BOTH VMs and BOTH boot disks. `gcloud compute instances delete claude-code-host fiber-raman-burst --zone=us-east1-b --delete-disks=all`. Prevents any post-trial charges.

---

## Why not the alternatives (final record)

**Single c3d-highcpu-16 with stop/start discipline:** Rejected — stop/start defeats "always-on Claude Code" goal, and 16 vCPU always-running wastes money since Claude Code uses <1 vCPU.

**Hetzner Cloud CCX (primary earlier choice):** All dedicated-vCPU sizes above 4 vCPU sold out at every Hetzner location as of 2026-04-16. Only CCX23 (4 vCPU, 16 GB) available — insufficient for Newton Hessian parallelism.

**Hetzner dedicated (AX102-U):** €269 one-time setup fee makes 4-week economics unattractive.

**NSF ACCESS Jetstream2:** User elected not to pursue (scope hesitation on existing MLAOD allocation). Strong future option for post-sprint work.

**AWS on-demand:** c7i.4xlarge ~$514/month is 2.3× the cost of GCP equivalents for similar parallelism.

**AWS spot:** Interruption risk undermines "always-on Claude Code" and reliable long runs.
