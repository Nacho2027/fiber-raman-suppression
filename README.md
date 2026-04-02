# MultiModeNoise.jl — Nonlinear Fiber Optics Simulation and Raman Suppression

Julia package for simulating nonlinear pulse propagation in optical fibers with
adjoint-based optimization of spectral phase for Raman suppression.

Part of Rivera Lab (Cornell) research on quantum noise in multimode fibers.

Based on Michael Horodynski's multimode noise code
(https://github.com/michaelhorodynski/MultiModeNoise.jl.git), shared Sept. 2025.

## What this does

Simulates femtosecond pulse propagation through single-mode and multimode fibers
using the generalized nonlinear Schrodinger equation (GNLSE) in the interaction
picture. The forward-adjoint method computes exact gradients of a spectral band
cost function with respect to input spectral phase, enabling L-BFGS optimization
to suppress stimulated Raman scattering.

## Key scripts

| Script | Purpose |
|--------|---------|
| `scripts/raman_optimization.jl` | Main optimization pipeline: 5 fiber configs, chirp sensitivity |
| `scripts/run_sweep.jl` | L x P parameter sweep across SMF-28 and HNLF grids |
| `scripts/generate_sweep_reports.jl` | Post-hoc report generation from sweep JLD2 files |
| `scripts/run_comparison.jl` | Cross-run comparison: summary table, convergence overlay, spectral overlay |
| `scripts/benchmark_optimization.jl` | Grid size benchmarks, time window analysis, continuation methods |
| `scripts/amplitude_optimization.jl` | Spectral amplitude optimization (alternative to phase-only) |
| `scripts/visualization.jl` | Publication-quality plotting functions (shared by all scripts) |

## Quick start

```bash
# Activate the project environment and run the main optimization
julia --project scripts/raman_optimization.jl

# Run the parameter sweep
julia --project scripts/run_sweep.jl

# Generate sweep reports from existing JLD2 results
julia --project scripts/generate_sweep_reports.jl
```

## Requirements

- Julia >= 1.9.3 (recommended: 1.12.x)
- Python 3.x with Matplotlib (for PyPlot; installed automatically by Conda.jl if needed)
- No GPU required (CPU-only)

Dependencies are managed via `Project.toml` and `Manifest.toml`. On first run:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

## Project structure

```
src/                        Core library (MultiModeNoise module)
  simulation/               ODE-based pulse propagation (forward + adjoint)
  gain_simulation/          YDFA gain model
  analysis/                 Noise variance decomposition
  helpers/                  Simulation parameter setup
scripts/                    Optimization and analysis entry points
results/raman/              Optimization outputs (JLD2, plots, sweep data)
notebooks/                  Interactive exploration (MMF squeezing, EDFA/YDFA)
data/                       Experimental data and cross-section files
test/                       Package tests
```
