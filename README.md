# Fiber Raman Suppression

Simulation and optimization code for suppressing Raman-shifted spectral energy
in nonlinear fiber propagation.

The maintained path is single-mode spectral-phase optimization. Other work in
this repo is useful research history, but it is not the first workflow to hand
to a new lab user.

## Start

```bash
make install
make doctor
make optimize
```

That installs the Julia environment, installs the local Python wrapper, runs
fast checks, and launches the reference SMF-28 optimization.

For the local lab handoff smoke:

```bash
make lab-ready
make golden-smoke
```

For a clean Linux reference environment:

```bash
make docker-build
make docker-test
```

## What is supported

| Area | Status | Read |
|---|---|---|
| Single-mode phase optimization | Maintained workflow | [supported workflows](docs/guides/supported-workflows.md) |
| Config-driven experiments | Maintained front layer, narrow supported surface | [configurable experiments](docs/guides/configurable-experiments.md) |
| Staged `amp_on_phase` refinement | Experimental, useful after a phase solution | [amp-on-phase guide](docs/guides/amp-on-phase-refinement.md) |
| Long-fiber 200 m result | Completed result, not optimizer-converged | [status note](docs/status/longfiber-200m-closure-2026-04-28.md) |
| Multimode fiber work | Qualified simulation candidate | [MMF report](docs/reports/mmf-raman-readiness-2026-04-28/REPORT.md) |
| Newton and preconditioning | Deferred research direction | [research notes](docs/research-notes/README.md) |

The shortest project-state summary is
[docs/reports/research-closure-2026-04-28/REPORT.md](docs/reports/research-closure-2026-04-28/REPORT.md).

## Common commands

```bash
./fiberlab configs
./fiberlab plan research_engine_poc
./fiberlab run research_engine_poc
./fiberlab latest research_engine_poc
./fiberlab ready latest research_engine_poc
```

Use `./fiberlab explore ...` for explicitly experimental configs:

```bash
./fiberlab explore list
./fiberlab explore plan research_engine_gain_tilt_smoke
./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke
./fiberlab explore compare results/raman --top 10
```

Use Julia entry points directly when you need the lower-level script surface:

```bash
julia -t auto --project=. scripts/canonical/optimize_raman.jl --list
julia -t auto --project=. scripts/canonical/run_experiment.jl --list
julia -t auto --project=. scripts/canonical/run_sweep.jl --list
```

## Where things live

```text
src/         Julia package code
configs/     approved run, sweep, and SLM profile specs
scripts/     command-line entry points and research drivers
docs/        human-facing guides, reports, architecture notes, and status notes
agent-docs/  agent continuity notes, not user docs
test/        Julia and Python regression tests
results/     generated run artifacts; do not commit wholesale
notebooks/   scratch analysis and inspection
```

Start with [docs/README.md](docs/README.md) when you need a document map.

## Results

Canonical runs write JLD2 payloads, JSON sidecars, and standard PNGs under
`results/`. A run that produces `phi_opt` is not complete until the standard
image set exists and has been inspected.

The saved-result schema is described in
[docs/architecture/output-format.md](docs/architecture/output-format.md).

## Environment

- Julia 1.12.x is the pinned development/runtime line.
- Python 3.10+ is used for the local `fiberlab` wrapper and tests.
- Docker is optional.
- Heavy sweeps belong on the burst machine, launched through the project burst
  wrapper, not from the small editing host.

## Attribution

This repo builds on Michael Horodynski's
[MultiModeNoise.jl](https://github.com/michaelhorodynski/MultiModeNoise.jl).

MIT license. See [LICENSE](LICENSE).
