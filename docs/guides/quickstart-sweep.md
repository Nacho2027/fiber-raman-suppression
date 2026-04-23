# Quickstart: Parameter Sweep

[← docs index](../README.md) · [project README](../../README.md)

Use this workflow when the task is to generate or refresh a maintained sweep on
the burst VM. The sweep is not a laptop workflow and should not be treated as a
casual extension of `make optimize`.

Mac and `claude-code-host` are assumed to be live-synced by Syncthing. Burst is
not. Stage code to burst explicitly and pull results back explicitly.

## When to run a sweep

- You are mapping the operating-regime landscape (how does suppression vary
  with fiber length and pulse power?).
- You need multi-start statistics for one canonical config.
- You want the heatmaps for a lab meeting or paper draft.

**Do NOT run a sweep on `claude-code-host`** — it will take ~15–20 hours and
starve your editing session. Sweeps belong on the burst VM
(`fiber-raman-burst`). The always-on editing VM is intentionally not where
these runs belong.

## Step 1 — Start the burst VM

On `claude-code-host` (where you are presumably running Claude Code):

```bash
git status                 # confirm clean working tree
syncthing cli show connections
burst-start                # ~30 s to boot
burst-status               # verify RUNNING
```

Helper scripts `burst-start`, `burst-ssh`, `burst-status`, and `burst-stop`
live in `~/bin/` on `claude-code-host` and wrap `gcloud compute` calls.

## Step 2 — Kick off the sweep through the heavy-lock wrapper

Heavy Julia jobs on the burst VM MUST go through `~/bin/burst-run-heavy`
(Rule P5 in `CLAUDE.md`). The wrapper acquires an exclusive heavy-job lock,
runs the job in tmux, releases the lock on exit (even on crash), and tees
output to `results/burst-logs/<tag>_<timestamp>.log`. Bare
`tmux new -d -s … 'julia …'` is DEPRECATED — it caused the 2026-04-17 VM
lockup (7+ concurrent heavy jobs) and is enforced-against by the watchdog.

```bash
# Session-B example. Replace B-sweep with your session tag.
# Tag format: ^[A-Za-z]-[A-Za-z0-9_-]+$
burst-ssh "~/bin/burst-status"                   # confirm lock is free
rsync -az --delete \
      --exclude='.git' --exclude='.DS_Store' --exclude='.stfolder' \
      ~/fiber-raman-suppression/ \
      -e "gcloud compute ssh --zone=us-east5-a --project=riveralab --" \
      fiber-raman-burst:~/fiber-raman-suppression/
burst-ssh "cd fiber-raman-suppression && \
           ~/bin/burst-run-heavy B-sweep 'julia -t auto --project=. scripts/canonical/run_sweep.jl'"
```

Under the hood the wrapper runs your command inside tmux session
`heavy-B-sweep` and keeps it alive across SSH disconnects. `make sweep`
from the Makefile is the local-foreground equivalent — do NOT invoke
`make sweep` via the wrapper (the sweep's `julia` call is the heavy
payload; `make` just wraps it).

If the lock is held, the wrapper prints the holder and exits. You have
three options:

1. **Wait for the lock** (good if the other job is close to done):
   ```bash
   WAIT_TIMEOUT_SEC=3600 burst-ssh "cd fiber-raman-suppression && \
       ~/bin/burst-run-heavy B-sweep 'julia -t auto --project=. scripts/canonical/run_sweep.jl'"
   ```

2. **Spawn an ephemeral second VM** (good if you can't wait, and for
   isolated reproducibility runs, quick experiments, or parallelizing a
   multi-config sweep without disturbing the primary VM). Run this from
   `claude-code-host`, NOT from inside the burst VM:
   ```bash
   ~/bin/burst-spawn-temp B-sweep2 'julia -t auto --project=. scripts/canonical/run_sweep.jl'
   ```
   The spawner creates a fresh VM from a machine image of
   `fiber-raman-burst`, runs your job, and destroys the VM on exit (the
   trap fires on success, Ctrl-C, and crash). There is also a 6-hour
   auto-shutdown scheduled on the VM itself as a safety net. Billing is
   ~$0.90/hr while running.

   **Soft cap:** try to keep the number of concurrent ephemerals to ~2.
   Check what's alive between work blocks:
   ```bash
   ~/bin/burst-list-ephemerals              # should be empty most of the time
   ~/bin/burst-list-ephemerals --destroy    # cleanup safety net
   ```

3. **Yield and switch tasks.** Sometimes the right move is not compute.

The full wrapper + spawner reference is in
[`scripts/burst/README.md`](../../scripts/burst/README.md).

## Step 3 — Monitor progress

The wrapper tees stdout+stderr to a timestamped log under
`results/burst-logs/`. Find the active log and tail it:

```bash
burst-ssh "ls -t fiber-raman-suppression/results/burst-logs/B-sweep_*.log | head -1"
burst-ssh "tail -f fiber-raman-suppression/results/burst-logs/B-sweep_<stamp>.log"
```

Or attach to the tmux session directly:

```bash
burst-ssh -t "tmux attach -t heavy-B-sweep"     # Ctrl-b d to detach
```

A healthy sweep prints one line per point (24 total):
`SMF28 L=2.0 P=0.2 → J_final_dB=-74.3 (42 iter, 12.3s)`.

## Step 4 — Pull results back, then STOP the burst VM

```bash
# On claude-code-host:
rsync -az -e "gcloud compute ssh --zone=us-east5-a --project=riveralab --" \
      fiber-raman-burst:~/fiber-raman-suppression/results/ \
      ~/fiber-raman-suppression/results/
burst-stop                 # $0.90/hr while running — do not skip this
```

The pulled `results/` tree then flows back to the Mac automatically via
Syncthing. Commit only the small durable summaries you actually want in git;
do not reflexively commit the whole `results/` tree.

If you forget `burst-stop`, the VM runs overnight at ~$22/day. Set a phone
reminder if you walk away mid-sweep.

## Step 5 — Generate report cards, heatmaps, and standard images

```bash
make report
```

Produces:

- `results/raman/sweeps/<fiber>/<L>_<P>/report_card.png` — 4-panel summary per point.
- `results/raman/sweeps/<fiber>/<L>_<P>/report.md` — scalar metrics in YAML.
- `results/raman/sweeps/SWEEP_REPORT.md` — ranked table of all points.
- `results/images/presentation/*.png` — regenerated presentation figures.

Every optimized `phi_opt` in the repo must also have the four-image
**standard set** (`{tag}_phase_profile.png`, `{tag}_evolution.png`,
`{tag}_phase_diagnostic.png`, `{tag}_evolution_unshaped.png`) per the
Project-level rule in `CLAUDE.md`. New drivers call
`save_standard_set(...)` from `scripts/lib/standard_images.jl` automatically
(see [quickstart-optimization.md](./quickstart-optimization.md)). For
sweep JLD2s produced before the rule landed, backfill via:

```bash
burst-ssh "cd fiber-raman-suppression && \
           ~/bin/burst-run-heavy R-stdimages \
           'julia -t auto --project=. scripts/canonical/regenerate_standard_images.jl'"
```

A sweep without the standard image set is NOT considered complete.

## Interpreting the heatmap

See [interpreting-plots.md](./interpreting-plots.md) for the visual
conventions (heatmap section). Key takeaway: look for a monotonic contour
pattern — `J_final` should smoothly decrease with larger L and larger P up to
a saturation boundary. Non-monotonic bright patches usually indicate a
non-converged or time-window-starved point; check the JSON sidecar's
`converged` field and the photon-number drift in the metadata. The full
schema is documented in [output-format.md](../architecture/output-format.md).

## Troubleshooting

- **Sweep died midway:** tmux session is still running (`tmux ls`) or crashed.
  Check `sweep_run.log`. Individual point failures are logged but don't abort
  the sweep — you can re-run the missing points by editing
  `scripts/canonical/run_sweep.jl` to skip completed points.
- **Photon number drift > 5% at high-power points:** the time window is too
  small. The SPM-aware `recommended_time_window` should handle this, but if
  you see the warning, increase the safety factor in `setup_raman_problem`.
- **Burst VM accidentally left running:** `burst-stop` is idempotent; just
  run it again.
- **Burst results came back but are not on the Mac yet:** verify Syncthing is
  healthy on the Mac and on `claude-code-host`, then wait for the initial scan
  or force a rescan from the Syncthing UI/CLI.
