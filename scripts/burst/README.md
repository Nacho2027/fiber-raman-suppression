# Burst VM coordination

This directory contains the mandatory coordination infrastructure for `fiber-raman-burst` after the 2026-04-17 kernel-lockup incident (7+ concurrent heavy Julia jobs starved the VM).

## What's here

- `run-heavy.sh` — **mandatory wrapper** for ALL heavy Julia runs on the burst VM. Acquires `/tmp/burst-heavy-lock`, launches the job in a named tmux session, releases the lock on exit even on crash. Enforces session-tag convention (`<Letter>-<name>`).
- `watchdog.sh` — runs continuously on the burst VM as a systemd `--user` service. Monitors load average and available memory; kills the youngest heavy Julia process if thresholds are crossed. Safety net against the Apr-17 scenario.
- `install.sh` — one-shot installer. Run from `claude-code-host` with `bash scripts/burst/install.sh`. Idempotent.

## How sessions should use this

`install.sh` deploys the wrappers into `~/bin/` on the burst VM so they are **branch-independent** (they keep working no matter which branch a session has checked out).

**Do NOT launch Julia directly in a tmux.** Always go through the wrapper:

```bash
# On claude-code-host, to run a heavy job on the burst VM:
burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy E-sweep2 \
          'julia -t auto --project=. scripts/research/sweep_simple/sweep_simple_run.jl'"
```

If another session is holding the lock, `burst-run-heavy` fails immediately by default with a message showing who is holding it. To wait instead, set `WAIT_TIMEOUT_SEC=<n>`:

```bash
burst-ssh "cd fiber-raman-suppression && WAIT_TIMEOUT_SEC=3600 \
          ~/bin/burst-run-heavy F-longfiber-T5 \
          'julia -t auto --project=. scripts/research/longfiber/longfiber_optimize_100m.jl'"
```

## Session-tag convention

`<Letter>-<short-name>`. Enforced by the wrapper.

| Session | Example tags |
|---|---|
| A-multivar | `A-multivar`, `A-gradcheck`, `A-demo` |
| C-multimode | `C-smoke`, `C-M2-run` |
| D-simple | `D-transfer`, `D-perturb` |
| E-sweep | `E-sweep1`, `E-sweep2`, `E-sweep1b` |
| F-longfiber | `F-T3`, `F-T5`, `F-queue` |
| H-cost | `H-audit`, `H-Cr` |

## Status check

From `claude-code-host`:

```bash
burst-ssh "burst-status"
```

Shows: lock holder, live tmux sessions, heavy Julia processes (>1 GB RSS), load, memory, watchdog status.

## Watchdog thresholds

Defaults in `watchdog.sh` (override via env):

- `LOAD_MAX=35` — 1-min load average (22-core VM, so 35 ≈ 1.6× core count).
- `MEM_FREE_GB_MIN=4` — available memory floor.
- `CHECK_INTERVAL_SEC=30` — poll period.

Watchdog only kills when **at least 2 heavy Julia processes** are running AND a threshold is crossed. A single heavy job using all cores is fine.

## Log locations

- `~/watchdog.log` on burst VM
- `~/fiber-raman-suppression/results/burst-logs/<session>_<timestamp>.log` — per-run log from `run-heavy.sh`

## Light runs (≤ 4 cores, < 5 min)

Don't need the wrapper if they're truly light and the lock isn't held by a competing heavy job. Still use descriptive tmux names matching the convention:

```bash
burst-ssh "tmux new -d -s E-validate 'julia -t 4 --project=. scripts/e2e_check.jl'"
```

But if you're uncertain whether a job is "light," use `run-heavy.sh` — being blocked by the lock is much cheaper than freezing the VM.

## On-demand ephemeral second burst VM

When you want to run a heavy Julia job in parallel with whatever is currently on `fiber-raman-burst` (queued work, a parallel sweep, an isolated reproducibility run), use `~/bin/burst-spawn-temp` **on claude-code-host** (not on the burst VM).

```bash
~/bin/burst-spawn-temp <session-tag> '<command>'

# Example — run a parallel sweep while the main burst VM is busy:
~/bin/burst-spawn-temp B-parallel-sweep \
    'julia -t auto --project=. scripts/my_other_sweep.jl'
```

What it does:

1. Ensures a recent machine image of `fiber-raman-burst` exists (`fiber-raman-burst-template`). Creates one on first use or when the cached image is >48 h old. Takes ~2 min on cache miss; near-instant on hit.
2. Creates an ephemeral VM `fiber-raman-temp-<tag>-<timestamp>` from the machine image. Same size as the main burst VM (c3-highcpu-22 by default). VM boots with the whole working filesystem — Julia, repo, data, and `~/bin` scripts are pre-installed.
3. Runs your command via the same `burst-run-heavy` wrapper on the ephemeral VM (so lock and per-run-log conventions still apply locally).
4. **On exit — success, failure, or Ctrl-C — destroys the ephemeral VM** via a trap.
5. Safety net: before running the command, schedules `sudo shutdown -h +360` (6 hours) on the VM in case the trap never fires (claude-code-host network drop). Configurable via `BURST_AUTO_SHUTDOWN_HOURS`.

### Cost note

Ephemeral VMs bill at ~$0.90/hr while running. The trap is the primary cleanup; the 6-hour auto-shutdown is backup. If you suspect an orphan was left behind:

```bash
~/bin/burst-list-ephemerals           # list running ephemerals
~/bin/burst-list-ephemerals --destroy # destroy all of them
```

### Good uses

- Second heavy job while the main VM is busy.
- Parallelizing a multi-config sweep that would serialize to half a day on one VM.
- Isolated reproducibility runs with no noisy-neighbor risk.
- Quick experiments you don't want to queue behind a long-running job.

### Soft cap and cleanup

Keep the concurrent count of ephemerals at ~2 or fewer — each bills ~$0.90/hr, so a dozen simultaneous would burn through the project budget in a day. Run `burst-list-ephemerals` at the end of a work block and destroy any orphans. The trap + 6-hour auto-shutdown mean a one-off failure will not cost you overnight, but explicit cleanup is still the right habit.
