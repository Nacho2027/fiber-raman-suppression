# Installation

[← back to docs index](./README.md) · [project README](../README.md)

Install Julia and the project's dependencies so you can run `make test` and
`make optimize` from a fresh clone.

## Requirements

| Tool | Version | Why |
|------|---------|-----|
| Julia | ≥ 1.9.3 (recommended 1.12.x, Manifest pinned to 1.12.4) | Compiler + package manager. |
| Python | 3.x with Matplotlib | PyPlot.jl calls matplotlib via PyCall. Auto-installed by Conda.jl on first run if you don't pre-install. |
| Git | any recent version | Clone + pull updates. |
| `make` | GNU make ≥ 3.81 | Runs the convenience targets (`make install`, `make test`, …). |

No GPU required. Sweeps benefit from multicore but are not GPU-accelerated.

## First-time setup

```bash
git clone <repo-url>
cd fiber-raman-suppression
make install     # runs `julia --project -e 'using Pkg; Pkg.instantiate()'`
make test        # fast tier (≤30 s) — should exit 0
```

If `make install` times out or errors, read the [Troubleshooting](#troubleshooting)
section below.

## Environment-specific notes

### macOS (Apple Silicon / Intel)

- Julia 1.12 via `juliaup` is the recommended install path. Avoid the
  system-provided Julia if it's older than 1.9.3.
- On first run, Conda.jl bootstraps a local Python environment with
  Matplotlib. The first `julia --project ...` invocation will be slow (~2 min)
  while it downloads binaries.
- `ENV["MPLBACKEND"] = "Agg"` is set at the top of every entry-point script —
  if you run Julia interactively, set it yourself before `using PyPlot`.

### Linux (Debian / Ubuntu / Arch)

- Install Julia via `juliaup` or the official tarball. Distro packages are
  usually behind.
- Make sure `gcc`, `libstdc++`, and `fontconfig` are present (needed by
  Matplotlib).
- FFTW_jll / MKL_jll binaries are downloaded automatically; don't install
  system `libfftw3` separately.

### GCP VM (claude-code-host / fiber-raman-burst)

Both VMs have Julia 1.12 pre-installed.

```bash
# On either VM, first time only:
cd fiber-raman-suppression
make install

# Then, on the burst VM (fiber-raman-burst) for heavy runs:
julia -t auto --project=. scripts/canonical/run_sweep.jl
```

`claude-code-host` is small (4 vCPU, 16 GB); use it for editing and `make
test`. The burst VM is where `make sweep` and long-running optimizations
belong. See the burst-VM helper commands (`burst-start`, `burst-ssh`,
`burst-stop`) documented in the top-level `CLAUDE.md` and in
[quickstart-sweep.md](./quickstart-sweep.md).

## Determinism note

The project uses `scripts/lib/determinism.jl` to pin FFTW planning to `ESTIMATE`
(not `MEASURE`) so that two runs from the same seed produce bit-identical
output. All entry-point scripts include this helper automatically. If you
run Julia interactively and need reproducibility, `include` it before any
FFT-touching code runs.

## Troubleshooting

### `Pkg.instantiate()` hangs or errors

- Check `~/.julia/logs/` for errors.
- If a specific package fails: `julia --project -e 'using Pkg; Pkg.build("<Name>")'`.
- For PyCall/PyPlot errors:
  ```bash
  julia --project -e 'ENV["PYTHON"]=""; using Pkg; Pkg.build("PyCall")'
  ```
  forces a rebuild using Conda.jl's own Python.

### `MPLBACKEND` / matplotlib display errors

Make sure you set `ENV["MPLBACKEND"] = "Agg"` BEFORE `using PyPlot`, or run
scripts as-is (they set it themselves).

### FFTW plan errors or non-deterministic output

If you see run-to-run variability in saved arrays, confirm
`scripts/lib/determinism.jl` was loaded — every entry-point script does this
automatically. The Phase 15 fix requires `FFTW.ESTIMATE` for bit-identity.

## Next steps

1. Finished install: go to [quickstart-optimization.md](./quickstart-optimization.md).
2. Want to run a sweep: go to [quickstart-sweep.md](./quickstart-sweep.md).
