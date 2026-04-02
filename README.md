# Fiber Raman Suppression

Adjoint-based spectral phase optimization for suppressing stimulated Raman scattering in optical fibers.

**Rivera Lab** | Cornell Applied & Engineering Physics | April 2026

## Overview

When ultrashort laser pulses propagate through optical fibers, Raman scattering transfers energy to longer wavelengths, degrading the pulse and adding quantum noise. This project optimizes the input spectral phase to minimize this energy transfer.

**Key result:** 37-78 dB Raman suppression across 24 fiber configurations (0.5-5 m length, two fiber types), verified with boundary checks and multi-start robustness analysis.

**Method:** Forward GNLSE simulation + backward adjoint solve gives exact gradients of the Raman cost in ~2 seconds. L-BFGS optimization converges in 20-60 iterations. A log-scale cost function (optimizing in dB) was the critical innovation, improving suppression by 20-28 dB over linear-scale optimization.

## Results at a glance

| Fiber | Best suppression | Worst | Configurations |
|-------|-----------------|-------|----------------|
| SMF-28 | **-78 dB** | -37 dB | 12 points (4 lengths x 3 powers) |
| HNLF | **-74 dB** | -51 dB | 12 points (4 lengths x 3 powers) |

See `results/RESULTS_SUMMARY.md` for a plain-language explanation, or `results/images/presentation/` for figures.

## Quick start

```bash
# Install dependencies (first time only)
julia --project -e 'using Pkg; Pkg.instantiate()'

# Run the main optimization (5 configs, ~5 min)
julia --project scripts/raman_optimization.jl

# Run the full parameter sweep (24 points, ~2-3 hours)
julia --project scripts/run_sweep.jl

# Generate reports and figures from sweep results
julia --project scripts/generate_sweep_reports.jl
julia --project scripts/generate_presentation_figures.jl
```

## Project structure

```
src/                          Core Julia package (MultiModeNoise.jl)
  simulation/                 GNLSE forward + adjoint solvers
  gain_simulation/            YDFA gain model
  analysis/                   Quantum noise variance decomposition
  helpers/                    Parameter setup, grid construction

scripts/                      Entry points and utilities
  raman_optimization.jl       Main optimization pipeline
  run_sweep.jl                L x P parameter sweep
  generate_sweep_reports.jl   Per-point reports from JLD2 data
  generate_presentation_figures.jl   Advisor-ready figures
  visualization.jl            Shared plotting functions
  common.jl                   Shared fiber presets and cost functions
  amplitude_optimization.jl   Amplitude shaping (alternative approach)
  benchmark_optimization.jl   Performance benchmarks

docs/                         Documentation
  companion_explainer.tex     Pedagogical math walkthrough (23 pages)
  companion_explainer.pdf     Compiled PDF
  verification_document.tex   Formal equation verification (32 pages)
  verification_document.pdf   Compiled PDF

results/
  RESULTS_SUMMARY.md          Plain-language results explanation
  raman/
    MATHEMATICAL_FORMULATION.md   Equations with code references
    sweeps/                   Sweep data, report cards, summaries
  images/
    presentation/             Advisor-ready figures

notebooks/                    Jupyter notebooks (interactive exploration)
test/                         Package tests
```

## Documentation

| Document | What it is | Pages |
|----------|-----------|-------|
| `results/RESULTS_SUMMARY.md` | Plain-language summary with glossary | - |
| `docs/companion_explainer.pdf` | First-principles math walkthrough (undergrad level) | 23 |
| `docs/verification_document.pdf` | Formal equation-by-equation code verification | 32 |
| `results/raman/MATHEMATICAL_FORMULATION.md` | Equations mapped to code line numbers | - |

## Key concepts

- **GNLSE**: Generalized Nonlinear Schrodinger Equation — the wave equation for light in a fiber
- **Adjoint method**: Compute gradients of the cost w.r.t. 8192 phase values in one backward simulation (instead of 16,384 forward simulations)
- **Soliton number (N)**: Ratio of nonlinear to dispersive effects. N=1 is a soliton. N>2 leads to fission.
- **Log-scale cost**: Optimizing 10*log10(J) instead of J keeps gradients O(1) as suppression deepens

## Requirements

- Julia >= 1.9.3 (recommended: 1.12.x)
- Python 3.x with Matplotlib (for PyPlot; auto-installed by Conda.jl)
- No GPU required

## Attribution

Built on Michael Horodynski's [MultiModeNoise.jl](https://github.com/michaelhorodynski/MultiModeNoise.jl) (shared September 2025). Extended with adjoint-based optimization, parameter sweeps, log-scale cost function, and comprehensive visualization.

## License

Research code — not yet published. Contact Rivera Lab for collaboration inquiries.
