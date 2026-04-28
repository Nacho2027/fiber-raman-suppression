# Installation

[← docs index](../README.md) · [project README](../../README.md)

Install Julia, the pinned Julia package environment, and the optional
Python/Jupyter wrapper so you can run `make doctor` and `make optimize` from a
fresh clone.

## Requirements

| Tool | Version | Why |
|------|---------|-----|
| Julia | 1.12.6 pinned by `.julia-version` and `Manifest.toml` | Compiler + package manager. |
| Python | 3.10+ (`.python-version` records 3.11) | Local `.venv` for the notebook wrapper. PyPlot.jl may also bootstrap its own Python via Conda.jl. |
| Git | any recent version | Clone + pull updates. |
| `make` | GNU make ≥ 3.81 | Runs the convenience targets (`make install`, `make test`, …). |
| Docker | optional | Runs the reference Linux/headless environment from `Dockerfile`. |

No GPU required. Sweeps benefit from multicore but are not GPU-accelerated.

## First-time setup

```bash
git clone <repo-url>
cd fiber-raman-suppression
make install     # Julia instantiate + local .venv with fiber-research-engine
make doctor      # tool check + fast Julia tests + Python wrapper tests
```

If `make install` times out or errors, read the [Troubleshooting](#troubleshooting)
section below.

For Julia-only work, use `make install-julia` and `make test`. For notebooks or
Python orchestration, keep `make install-python` in the setup path so imports
work without `PYTHONPATH` hacks.

## Environment-specific notes

### macOS (Apple Silicon / Intel)

- Julia 1.12 via `juliaup` is the recommended install path. Avoid the
  system-provided Julia if it's older than 1.9.3.
- On first run, Conda.jl bootstraps a local Python environment with
  Matplotlib. The first `julia --project ...` invocation will be slow (~2 min)
  while it downloads binaries.
- The repo's Python helper is installed into `.venv` by `make install-python`;
  use `.venv/bin/python` or activate `.venv` for notebook-side imports.
- `ENV["MPLBACKEND"] = "Agg"` is set at the top of every entry-point script —
  if you run Julia interactively, set it yourself before `using PyPlot`.

### Linux (Debian / Ubuntu / Arch)

- Install Julia via `juliaup` or the official tarball. Distro packages are
  usually behind.
- Make sure `gcc`, `g++`, `libstdc++`, `fontconfig`, `python3-venv`, and
  `python3-pip` are present.
- On Debian/Ubuntu, the usual prerequisite install is:
  ```bash
  sudo apt install git make gcc g++ fontconfig python3 python3-venv python3-pip
  ```
- FFTW_jll / MKL_jll binaries are downloaded automatically; don't install
  system `libfftw3` separately.

### GCP VM (claude-code-host / fiber-raman-burst)

Both VMs have Julia 1.12 pre-installed.

```bash
# On either VM, first time only:
cd fiber-raman-suppression
make install

# Then, on the burst VM (fiber-raman-burst) for heavy runs:
julia -t auto --project=. scripts/canonical/run_sweep.jl smf28_hnlf_default
```

`claude-code-host` is small (4 vCPU, 16 GB); use it for editing and `make
test`. The burst VM is where `make sweep` and long-running optimizations
belong. See the burst-VM helper commands (`burst-start`, `burst-ssh`,
`burst-stop`) documented in the top-level `CLAUDE.md` and in
[quickstart-sweep.md](./quickstart-sweep.md).

## Container Option

Use the container when you want a clean Linux/headless reference environment
instead of depending on the host's Python, matplotlib, or system libraries:

```bash
make docker-build
make docker-test
```

See [container.md](./container.md) for the full workflow.

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

### Python import errors

Run:

```bash
make install-python
make test-python
```

The Python package is installed from `pyproject.toml` into `.venv`. You should
not need to set `PYTHONPATH=python` after installation.

### `make install-python` reports missing venv support

Install your platform's Python venv package and retry:

```bash
sudo apt install python3-venv python3-pip
make install-python
```

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
