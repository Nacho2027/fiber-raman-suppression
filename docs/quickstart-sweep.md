# Quickstart — Parameter Sweep

[← back to docs index](./README.md) · [project README](../README.md)

Goal: Produce a `J_final` heatmap over (L, P) for SMF-28 and HNLF. Expected
runtime: 2–3 hours on the burst VM.

## When to run a sweep

- You are mapping the operating-regime landscape (how does suppression vary
  with fiber length and pulse power?).
- You need multi-start statistics for one canonical config.
- You want the heatmaps for a lab meeting or paper draft.

**Do NOT run a sweep on `claude-code-host`** — it will take ~15–20 hours and
starve your editing session. Sweeps belong on the burst VM
(`fiber-raman-burst`). This is enforced by Rule 1 in the top-level
`CLAUDE.md` ("Running Simulations — Compute Discipline") and is not
negotiable: the always-on editing VM is not sized for compute.

## Step 1 — Start the burst VM

On `claude-code-host` (where you are presumably running Claude Code):

```bash
git status                 # confirm clean working tree
git push                   # burst VM pulls from git
burst-start                # ~30 s to boot
burst-status               # verify RUNNING
```

Helper scripts `burst-start`, `burst-ssh`, `burst-status`, and `burst-stop`
live in `~/bin/` on `claude-code-host` and wrap `gcloud compute` calls.

## Step 2 — Kick off the sweep in a detached tmux session

`make sweep` prints a 3-second warning banner and then runs the sweep in the
foreground. For a 2–3 h run we want detached tmux:

```bash
burst-ssh "cd fiber-raman-suppression && \
           git pull && \
           tmux new -d -s sweep 'make sweep > sweep_run.log 2>&1'"
```

Under the hood `make sweep` runs
`julia --project -t auto scripts/run_sweep.jl`. Launching via tmux keeps the
run alive across SSH disconnects.

## Step 3 — Monitor progress

```bash
burst-ssh "tail -f fiber-raman-suppression/sweep_run.log"
```

A healthy sweep prints one line per point (24 total):
`SMF28 L=2.0 P=0.2 → J_final_dB=-74.3 (42 iter, 12.3s)`.

## Step 4 — Pull results back, then STOP the burst VM

```bash
# On claude-code-host:
burst-ssh "cd fiber-raman-suppression && git add results/ && git commit -m 'sweep results' && git push"
git pull
burst-stop                 # $0.90/hr while running — do not skip this
```

If you forget `burst-stop`, the VM runs overnight at ~$22/day. Set a phone
reminder if you walk away mid-sweep.

## Step 5 — Generate report cards and heatmaps

```bash
make report
```

Produces:

- `results/raman/sweeps/<fiber>/<L>_<P>/report_card.png` — 4-panel summary per point.
- `results/raman/sweeps/<fiber>/<L>_<P>/report.md` — scalar metrics in YAML.
- `results/raman/sweeps/SWEEP_REPORT.md` — ranked table of all points.
- `results/images/presentation/*.png` — advisor-ready figures.

## Interpreting the heatmap

See [interpreting-plots.md](./interpreting-plots.md) for the visual
conventions (heatmap section). Key takeaway: look for a monotonic contour
pattern — `J_final` should smoothly decrease with larger L and larger P up to
a saturation boundary. Non-monotonic bright patches usually indicate a
non-converged or time-window-starved point; check the JSON sidecar's
`converged` field and the photon-number drift in the metadata. The full
schema is documented in [output-format.md](./output-format.md).

## Troubleshooting

- **Sweep died midway:** tmux session is still running (`tmux ls`) or crashed.
  Check `sweep_run.log`. Individual point failures are logged but don't abort
  the sweep — you can re-run the missing points by editing
  `scripts/run_sweep.jl` to skip completed points.
- **Photon number drift > 5% at high-power points:** the time window is too
  small. The SPM-aware `recommended_time_window` should handle this, but if
  you see the warning, increase the safety factor in `setup_raman_problem`.
- **Burst VM accidentally left running:** `burst-stop` is idempotent; just
  run it again.
- **`git pull` on burst fails with divergent history:** the burst VM has
  local commits that were not pushed. Resolve by pushing from burst first,
  then pulling on `claude-code-host`.
