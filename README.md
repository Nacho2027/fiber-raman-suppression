# Fiber Raman Suppression

Adjoint-based spectral phase optimization for suppressing stimulated Raman
scattering in optical fibers.

**Rivera Lab** | Cornell Applied & Engineering Physics

## What this is (90 seconds)

When ultrashort laser pulses propagate through optical fibers, stimulated Raman
scattering transfers energy to longer wavelengths, degrading the pulse and
adding quantum noise. This repository optimizes the input spectral phase to
suppress that energy transfer. Forward GNLSE simulation + backward adjoint solve
gives exact gradients in ~2 seconds; L-BFGS converges in 20–60 iterations.

New to the project? Start here:

1. `make install` — install Julia dependencies.
2. `make optimize` — run the canonical SMF-28 optimization (~5 min).
3. Read [`docs/README.md`](docs/README.md) for the full documentation suite.

## Results at a glance

| Fiber  | Best suppression | Worst | Configurations               |
|--------|------------------|-------|------------------------------|
| SMF-28 | **-78 dB**       | -37 dB | 12 points (4 lengths × 3 powers) |
| HNLF   | **-74 dB**       | -51 dB | 12 points (4 lengths × 3 powers) |

See [`results/RESULTS_SUMMARY.md`](results/RESULTS_SUMMARY.md) for a
plain-language explanation. After running `make report`, presentation-quality
figures land in `results/images/presentation/` — see
[`docs/interpreting-plots.md`](docs/interpreting-plots.md) for a field guide.

## Happy path

```bash
make install         # install Julia dependencies (one-time, ~2 min)
make test            # run the fast tier regression tests (~30 s)
make optimize        # run the canonical SMF-28 optimization (~5 min)
make report          # regenerate figures and report cards from existing JLD2
```

For the full parameter sweep (2–3 h, strongly recommended on the burst VM):

```bash
make sweep
```

Run `make` with no arguments to list every target.

## Where to go next

| I want to...                                     | Read                                                  |
|--------------------------------------------------|-------------------------------------------------------|
| Install and run my first optimization            | [`docs/quickstart-optimization.md`](docs/quickstart-optimization.md) |
| Launch a parameter sweep                         | [`docs/quickstart-sweep.md`](docs/quickstart-sweep.md) |
| Understand the output file format (JLD2 + JSON)  | [`docs/output-format.md`](docs/output-format.md)      |
| Interpret the plots                              | [`docs/interpreting-plots.md`](docs/interpreting-plots.md) |
| Understand the cost function / adjoint / physics | [`docs/cost-function-physics.md`](docs/cost-function-physics.md) and [`docs/companion_explainer.pdf`](docs/companion_explainer.pdf) |
| Extend with a new fiber preset                   | [`docs/adding-a-fiber-preset.md`](docs/adding-a-fiber-preset.md) |
| Extend with a new optimization variable          | [`docs/adding-an-optimization-variable.md`](docs/adding-an-optimization-variable.md) |
| Install troubleshooting                          | [`docs/installation.md`](docs/installation.md)        |
| Full doc index                                   | [`docs/README.md`](docs/README.md)                    |

## Project layout

```
src/                Core Julia package (MultiModeNoise.jl): GNLSE forward +
                    adjoint solvers, YDFA gain, mode solving
scripts/            Entry points: `raman_optimization.jl`, `run_sweep.jl`,
                    `generate_sweep_reports.jl`, `generate_presentation_figures.jl`,
                    `amplitude_optimization.jl`, `run_comparison.jl`,
                    `sharpness_optimization.jl`
docs/               Markdown how-tos + LaTeX pedagogy (companion_explainer.pdf,
                    verification_document.pdf, physics_verification.pdf)
test/               Tiered regression test suite (fast / slow / full)
results/            Run artifacts (JLD2 + JSON), figures, report cards
notebooks/          Research scratchpads (not handoff material)
Makefile            Convenience targets — see `make` with no arguments
```

## Requirements

- Julia ≥ 1.9.3 (recommended: 1.12.x). See [`docs/installation.md`](docs/installation.md).
- Python 3.x with Matplotlib (auto-installed by Conda.jl via PyPlot).
- No GPU required. Parameter sweeps benefit from a multicore burst VM.

## Attribution

Built on Michael Horodynski's
[MultiModeNoise.jl](https://github.com/michaelhorodynski/MultiModeNoise.jl)
(shared September 2025). Extended with adjoint-based optimization, parameter
sweeps, log-scale cost function, and comprehensive visualization.

## License

Research code — not yet published. Contact Rivera Lab for collaboration
inquiries.
