# Installation

Use this for a local checkout. Heavy sweeps still belong on the burst machine.

## Requirements

- Julia 1.12.x
- Python 3.10+
- `make`
- Git
- Docker, optional

## Install

```bash
make install
```

This runs `Pkg.instantiate()`, creates `.venv`, and installs the local Python
wrapper.

## Check the checkout

```bash
make doctor
```

`make doctor` runs the fast Julia test tier and Python CLI tests. It does not
run simulation-heavy tests.

## First real run

```bash
make optimize
```

The run writes into `results/raman/`. Inspect the standard images before using
the result in a meeting or report.

## Common failures

- Missing Julia: install Julia 1.12.x and make sure `julia` is on `PATH`.
- Missing Python venv support on Debian/Ubuntu: install `python3-venv` and
  `python3-pip`.
- PyPlot backend problems on headless Linux: use the Docker path or set an Agg
  backend before plotting.
- Slow or memory-heavy runs on the editing VM: stop and use the burst workflow.
