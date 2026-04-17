# Burst VM coordination

This directory contains the mandatory coordination infrastructure for `fiber-raman-burst` after the 2026-04-17 kernel-lockup incident (7+ concurrent heavy Julia jobs starved the VM).

## What's here

- `run-heavy.sh` — **mandatory wrapper** for ALL heavy Julia runs on the burst VM. Acquires `/tmp/burst-heavy-lock`, launches the job in a named tmux session, releases the lock on exit even on crash. Enforces session-tag convention (`<Letter>-<name>`).
- `watchdog.sh` — runs continuously on the burst VM as a systemd `--user` service. Monitors load average and available memory; kills the youngest heavy Julia process if thresholds are crossed. Safety net against the Apr-17 scenario.
- `install.sh` — one-shot installer. Run from `claude-code-host` with `bash scripts/burst/install.sh`. Idempotent.

## How sessions should use this

**Do NOT launch Julia directly in a tmux.** Always go through the wrapper:

```bash
# On claude-code-host, to run a heavy job on the burst VM:
burst-ssh "cd fiber-raman-suppression && scripts/burst/run-heavy.sh E-sweep2 \
          'julia -t auto --project=. scripts/sweep_simple_run.jl'"
```

If another session is holding the lock, `run-heavy.sh` fails immediately by default with a message showing who is holding it. To wait instead, set `WAIT_TIMEOUT_SEC=<n>`:

```bash
burst-ssh "cd fiber-raman-suppression && WAIT_TIMEOUT_SEC=3600 \
          scripts/burst/run-heavy.sh F-longfiber-T5 \
          'julia -t auto --project=. scripts/longfiber_optimize_100m.jl'"
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
