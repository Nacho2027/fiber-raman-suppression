# Quickstart — Run Your First Optimization

[← back to docs index](./README.md) · [project README](../README.md)

Goal: From a fresh clone, produce your first Raman-suppression result in under
15 minutes. If you've already run `make install`, this should take 5–8
minutes of wall-clock and maybe 5 minutes of reading.

## Prerequisite

```bash
make install    # one-time; see docs/installation.md if this fails
```

See [installation.md](./installation.md) for environment setup and
troubleshooting.

## Step 1 — Sanity check: run the fast tests (<30 s)

```bash
make test
```

This runs the fast-tier regression suite: SPM time-window formula, output-
format round trip, determinism helper. Zero simulation calls. If this fails,
stop and debug before going further — something is broken in your install.

## Step 2 — Run the canonical SMF-28 optimization (~5 min)

```bash
make optimize
```

Under the hood this runs `julia --project -t auto scripts/canonical/optimize_raman.jl`.
You will see L-BFGS iterations printed every few seconds. Expected output:

- ~30 L-BFGS iterations.
- Final `J` in dB somewhere between −60 and −78 dB.
- Wall time ~5 minutes on a 4-core laptop, ~2 minutes on the burst VM.

The first invocation of the session includes Julia precompilation (~90 s) —
that's normal. Subsequent runs start within a few seconds.

## Step 3 — Inspect the results

Results land under `results/raman/<run_id>/`:

```
results/raman/smf28_L2.0m_P0.2W_<timestamp>/
├── _result.jld2                    # binary payload (phi_opt, uω0, uωf, history)
├── _result.json                    # scalar metadata sidecar (grep-able)
├── {tag}_phase_profile.png         # 6-panel before/after (mandatory standard image)
├── {tag}_evolution.png             # spectral-evolution waterfall (mandatory)
├── {tag}_phase_diagnostic.png      # wrapped/unwrapped/group-delay triplet (mandatory)
├── {tag}_evolution_unshaped.png    # phi ≡ 0 waterfall for comparison (mandatory)
├── spectral.png                    # input vs output spectrum on dB axes
├── phase.png                       # 3-view phase diagnostic
└── evolution.png                   # 2x2 evolution comparison
```

The four `{tag}_*.png` files are the research group's **standard image
set** — every driver that produces a `phi_opt` must generate them via
`save_standard_set(...)` from `scripts/lib/standard_images.jl` (Project-rule
in `CLAUDE.md`). A run without the standard set is not considered
complete. If you are writing a new driver, the end of it must look like:

```julia
include(joinpath(@__DIR__, "standard_images.jl"))
save_standard_set(phi_opt, uω0, fiber, sim,
                  band_mask, Δf, raman_threshold;
                  tag        = "smf28_L2m_P0p2W",
                  fiber_name = "SMF28", L_m = 2.0, P_W = 0.2,
                  output_dir = "results/raman/my_run/")
```

To backfill the standard images for older JLD2 runs, use
`scripts/canonical/regenerate_standard_images.jl` on the burst VM — see
[quickstart-sweep.md](./quickstart-sweep.md#step-5--generate-report-cards-heatmaps-and-standard-images).

Quick scalar peek:

```bash
jq '{J_final_dB, n_iter, converged}' results/raman/smf28_*/_result.json
```

Or in Julia:

```julia
using MultiModeNoise: load_run
loaded = load_run("results/raman/smf28_L2.0m_P0.2W_<timestamp>/_result.jld2")
@show loaded.metadata["J_final_dB"]
@show loaded.metadata["n_iter"]
```

For the full JLD2 + JSON schema, see [output-format.md](./output-format.md).

## Step 4 — Interpret the plots

Open `spectral.png`:
- Blue curve = input spectrum.
- Orange / vermillion curve = output spectrum after fiber propagation.
- Shaded band = Raman gain region (~13 THz wide).
- You want the orange curve to DROP inside the shaded band. A 30+ dB drop is
  good; 50+ dB is excellent.

For the full plot anatomy tour see
[interpreting-plots.md](./interpreting-plots.md).

## Step 5 — What to read next

- Want to understand *why* the optimizer works?
  → [cost-function-physics.md](./cost-function-physics.md).
- Want to run a parameter sweep?
  → [quickstart-sweep.md](./quickstart-sweep.md).
- Want to extend to a new fiber?
  → [adding-a-fiber-preset.md](./adding-a-fiber-preset.md).
- Want the field-by-field JLD2+JSON reference?
  → [output-format.md](./output-format.md).

## Troubleshooting

- **`make optimize` hangs after 10 minutes with no output:**
  The first run includes Julia precompilation (~90 s). If it's still silent
  after 3 minutes, something is wrong. Run `julia --project -t auto scripts/canonical/optimize_raman.jl`
  directly to see the error.
- **Final J in dB is -3 to -5 (no suppression):**
  The optimizer is barely iterating. Check `max_iter` at the top of
  `scripts/lib/raman_optimization.jl`. The default is 30; setting it to 5 would
  reproduce this symptom.
- **Plots are blank:**
  Check `ENV["MPLBACKEND"]` is set to `"Agg"` before `using PyPlot`.
  Every entry-point script does this; interactive REPL usage does not.
- **`jq: command not found`:**
  `jq` is not a project dependency; install it via your package manager
  (`brew install jq`, `apt install jq`, …) or read the `_result.json` file
  directly.
