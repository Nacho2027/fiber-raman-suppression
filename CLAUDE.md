<!-- GSD:project-start source:PROJECT.md -->
## Project

**Visualization Overhaul: SMF Gain-Noise Plotting**

A comprehensive fix of all plotting and visualization in the smf-gain-noise project (MultiModeNoise.jl). The goal is to produce clean, readable, physically informative plots for nonlinear fiber optics simulations — specifically Raman suppression optimization via spectral phase and amplitude shaping. Plots are for internal research group use (lab meetings, advisor reviews).

**Core Value:** Every plot must clearly communicate the underlying physics so that a reader can understand what happened during propagation and optimization without needing the filename or external context.

### Constraints

- **Tech stack**: Must stay in Julia + PyPlot (matplotlib). No new visualization dependencies.
- **Backward compatibility**: Keep the same function signatures where possible, or provide clear migration.
- **Output format**: PNG at 300 DPI for archival, must look good at both screen and print resolution.
- **Performance**: Plotting should not add significant overhead to optimization runs.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages & Versions
- Julia >= 1.9.3 (declared in `Project.toml` [compat]); Manifest resolved with Julia 1.12.4
- Python (called via PyCall/PyPlot for Matplotlib plotting)
## Runtime
- Julia runtime (REPL, scripts, or Jupyter notebooks via IJulia)
- Python runtime required for PyPlot/Matplotlib backend (via PyCall JLL bridge)
- Julia built-in Pkg manager
- Lockfile: `Manifest.toml` present (machine-generated, pinned to Julia 1.12.4)
- Project definition: `Project.toml` (package name: `MultiModeNoise`, version `1.0.0-DEV`)
## Frameworks
- DifferentialEquations.jl — ODE solving (Tsit5, Vern9 methods) for pulse propagation
- FFTW.jl — Fast Fourier Transforms for frequency-domain computations
- Tullio.jl — Einstein summation notation for tensor contractions (mode overlap, nonlinear coupling)
- Optim.jl v1.13.3+ — L-BFGS optimization for spectral phase/amplitude shaping
- PyPlot.jl — Matplotlib wrapper for publication-quality figures (uses `Agg` backend for headless execution)
- Revise.jl — hot-reload during development (optional, wrapped in `try...catch`)
## Core Dependencies
| Package | Version (compat) | Purpose |
|---------|-------------------|---------|
| DifferentialEquations | (unversioned) | Full ODE/SDE solver suite; uses `Tsit5()` and `Vern9()` |
| FFTW | (unversioned) | FFT/IFFT with pre-planned in-place transforms (`FFTW.MEASURE`) |
| Tullio | (unversioned) | Einstein summation for 4D mode-overlap tensors `@tullio` |
| Optim | 1.13.3 | L-BFGS optimizer for spectral phase optimization |
| Arpack | (unversioned) | Sparse eigenvalue solver (`eigs`) for fiber mode computation |
| SparseArrays | (stdlib) | Sparse matrix construction for finite-difference eigenvalue problem |
| LinearAlgebra | (stdlib) | BLAS/LAPACK routines, `norm()`, matrix operations |
| LoopVectorization | (unversioned) | SIMD acceleration (used alongside Tullio) |
| NPZ | (unversioned) | Read/write NumPy `.npz` files (fiber parameter caching, cross-section data) |
| Interpolations | 0.16.2 | 1D linear interpolation for Yb cross-section spectra |
| FiniteDifferences | (unversioned) | Finite-difference stencils for beta-coefficient computation |
| PyPlot | (unversioned) | Matplotlib plotting via PyCall |
| CSV | 0.10.15 | CSV file I/O for experimental data |
| DataFrames | 1.8.1 | Tabular data handling (used in `data/plotFvsP.jl`) |
| Dates | 1.11.0 (stdlib) | Timestamp generation for run tags |
## Dev / Script Dependencies
| Package | Purpose | Used in |
|---------|---------|---------|
| Revise | Hot-reload during interactive dev | `scripts/raman_optimization.jl`, `scripts/amplitude_optimization.jl` |
| Statistics | `mean()` for spectral flatness penalty | `scripts/visualization.jl`, `scripts/amplitude_optimization.jl` |
| Printf | Formatted output and logging | All scripts |
| Logging | `@info`, `@warn`, `@debug` macros | All scripts |
## Configuration
- `ENV["MPLBACKEND"] = "Agg"` set in scripts for headless Matplotlib rendering
- No `.env` files; no environment variables required
- No secrets or API keys
- `Project.toml` — Julia package manifest with UUID `b336628f-8386-4303-a33d-f2bdce4c2a6e`
- `Manifest.toml` — full dependency lock (commit-tracked)
- No Makefile or build script; use Julia Pkg manager directly
## Build & Run
# or: julia test/runtests.jl
## Platform Requirements
- Julia >= 1.9.3 (recommended: 1.12.x as per Manifest)
- Python 3.x with Matplotlib (for PyPlot; installed automatically by Conda.jl if needed)
- FFTW system library (provided by FFTW_jll, MKL_jll auto-downloaded)
- OpenBLAS or MKL for linear algebra (provided by JLL packages)
- No GPU required (CPU-only computation; Tullio has optional CUDA extension but unused)
- Designed for local workstation or HPC node execution
- No containerization or deployment configuration
- Memory-intensive for large grids: `Nt=2^14, M>1` allocates ~GB-scale arrays
- Single-threaded by default; `Threads.@threads` used in benchmark parallel gradient validation
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Conventions
- Use `snake_case` for all functions: `cost_and_gradient`, `spectral_band_cost`, `setup_raman_problem`
- In-place mutating functions use `!` suffix per Julia convention: `disp_mmf!`, `adjoint_disp_mmf!`, `compute_gain!`, `calc_δs!`
- Private/internal helpers use `_` prefix: `_apply_fiber_preset`, `_manual_unwrap`, `_central_diff`, `_auto_time_limits`, `_energy_window`, `_freq_to_wavelength`, `_length_display`
- ODE right-hand-side functions follow pattern `{physics_model}!`: `disp_mmf!`, `disp_gain_smf!`, `mmf_u_mu_nu!`
- Parameter constructors follow `get_p_{model}`: `get_p_disp_mmf`, `get_p_adjoint_disp_mmf`, `get_p_disp_gain_smf`
- Setup functions are prefixed by optimization type: `setup_raman_problem`, `setup_amplitude_problem`
- Physics variables use Unicode symbols matching their mathematical notation: `λ0`, `ω0`, `β2`, `γ`, `φ`, `ũω`, `λ̃ω`, `Δt`, `Δf`
- Greek letters for physical quantities: `σ` (sigma), `τ` (tau), `ε` (epsilon), `ηt` (eta-temporal), `δKt` (delta-Kerr-temporal)
- Subscripts in variable names use domain-specific physics notation: `uωf` (field in frequency at fiber end), `ut0` (field in time at z=0), `hRω` (Raman response in frequency)
- Preallocated buffers use descriptive physics names: `exp_D_p`, `exp_D_m`, `hRω_δRω`, `hR_conv_δR`
- Counters and sizes: `Nt` (number of temporal grid points), `M` (number of spatial modes), `Nt_φ` (phase grid size)
- Source module files: `snake_case.jl` — `simulate_disp_mmf.jl`, `sensitivity_disp_mmf.jl`
- Script files: `snake_case.jl` — `raman_optimization.jl`, `benchmark_optimization.jl`
- Test files: `test_` prefix — `test_optimization.jl`, `test_visualization_smoke.jl`
- Shared library: `common.jl` in `scripts/`
- Module-level constants use `UPPER_SNAKE_CASE`: `FIBER_PRESETS`, `C_NM_THZ`, `COLOR_INPUT`, `COLOR_OUTPUT`, `COLOR_RAMAN`, `COLOR_REF`
- Script-level constants: `SMF28_GAMMA`, `SMF28_BETAS`, `HNLF_GAMMA`, `HNLF_BETAS`, `RUN_TAG`
- Include guard constants: `_COMMON_JL_LOADED`, `_VISUALIZATION_JL_LOADED`
- `PascalCase` for struct names: `YDFAParams` in `src/gain_simulation/gain.jl`
- Use `@kwdef mutable struct` for parameter containers with sensible defaults
## Code Style
- No formatter or linter is configured. No `.editorconfig`, `.JuliaFormatter.toml`, or equivalent exists.
- Indentation: 4 spaces consistently across all files
- Line length: no enforced limit; long lines (100-150 chars) are common, especially for parameter tuples and `@sprintf` calls
- Semicolons separate multiple short assignments on one line: `Nt = sim["Nt"]; M = sim["M"]`
- Use `@.` macro for vectorized operations: `@. uω = exp_D_p * ũω`
- Use `@tullio` for tensor contractions (Einstein summation): `@tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])`
- Prefer `cis(x)` over `exp(im * x)` for phase rotations (documented as avoiding exp overhead)
- Use `# ─────────────────────────────────────────────────────────────────────────────` (em-dash lines) between logical sections in scripts
- Section headers follow pattern: `# N. Section Title` with numbered sections in scripts
- Run summaries use box-drawing characters: `┌──┐`, `├──┤`, `│`, `└──┘`
- Benchmark tables use double-line box drawing: `╔═══╦═══╗`, `║`, `╚═══╩═══╝`
## Common Patterns
- Files meant for multiple inclusion use an include guard:
- Used in: `scripts/common.jl`, `scripts/visualization.jl`
- Functions use `@assert` for both preconditions and postconditions:
- Comments `# PRECONDITIONS` and `# POSTCONDITIONS` explicitly mark contract sections
- Simulation parameters stored in `Dict{String, Any}`:
- Used for: `sim` (simulation params), `fiber` (fiber params), `sol` (solution results)
- String keys throughout: `sim["Nt"]`, `fiber["Dω"]`, `fiber["L"]`
- ODE parameter tuples preallocate all working arrays to avoid GC pressure:
- Setup and run functions use extensive keyword arguments with defaults:
- Scripts that should not execute when `include`d use:
- Named tuples for fiber parameter sets in `scripts/common.jl`:
- `try using Revise catch end` at the top of scripts for optional hot-reloading
## Error Handling
- `@assert` for design-by-contract validation of function inputs and outputs (preconditions/postconditions)
- `throw(ArgumentError(...))` for user-facing validation in core library code (e.g., `src/helpers/helpers.jl`)
- `@warn` for recoverable conditions (e.g., time window too small):
- No try/catch blocks in numerical code — errors propagate to the caller
- No custom exception types are defined
## Documentation Style
- Multi-line `"""..."""` at top of each script file describing purpose and contents:
- Julia-style `"""..."""` docstrings above functions, using `# Arguments`, `# Returns`, `# Example` sections:
- `uωf`: Output field in frequency domain, shape (Nt, M).
- `band_mask`: Boolean vector of length Nt, true for frequencies in the band.
- `J`: Scalar cost = E_band / E_total in [0, 1].
- `dJ`: Gradient w.r.t. conj(uωf), adjoint terminal condition lambda(L).
- Physics comments explain the mathematical operation: `# Chain rule: dJ/dphi(omega) = 2 * Re(lambda_0*(omega) * i * u_0(omega))`
- Units always stated in comments: `# W^-1 m^-1`, `# s^2/m`, `# THz`
- `# --- Section Title ---` for subsections within functions
- Some older code (`src/simulation/`) has incomplete docstrings with empty argument descriptions
- `scripts/test_optimization.jl` contains a detailed TDD cycle log at the top documenting RED/GREEN/REFACTOR iterations:
## Import Organization
## Logging
- `@info` for run summaries, progress messages, and major milestones
- `@debug` for detailed diagnostics (iteration counts, parameter values, gradient norms) — only visible with `JULIA_DEBUG=all`
- `@warn` for non-fatal but concerning conditions (small time window, boundary energy too high)
- `@sprintf` used within logging macros for formatted output
- Older code in `src/` uses `println()` and `flush(stdout)` — the scripts layer uses `Logging` properly
- Run summaries use box-drawing characters for visual distinction
## SI Units Convention
- Wavelength: meters (e.g., `1550e-9`)
- Time: seconds for physics (e.g., `pulse_fwhm = 185e-15`), picoseconds for simulation grids
- Frequency: THz for spectral grids, Hz for repetition rates
- Power: Watts
- Dispersion: `s^2/m` for beta_2, `s^3/m` for beta_3
- Nonlinearity: `W^-1 m^-1`
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Overview
## Pattern Overview
- Julia package structure with `Project.toml` / `Manifest.toml` managing dependencies
- Core physics encoded as in-place ODE right-hand-side functions (`!` convention)
- Forward-adjoint optimization pattern: forward propagation + backward adjoint for gradient-based optimization
- Dictionary-based parameter passing (`sim::Dict`, `fiber::Dict`) rather than typed structs
- Pre-allocated work arrays packed into tuples to avoid GC pressure during ODE solving
- Scripts use `include()` chains with manual include guards (`_COMMON_JL_LOADED`)
## Core Concepts
- **Interaction picture**: ODEs are written in the interaction picture, separating fast linear (dispersive) dynamics from slow nonlinear dynamics. The `exp_D_p`/`exp_D_m` phase factors transform between lab frame and interaction frame.
- **Kerr + Raman nonlinearity**: The nonlinear response splits into instantaneous Kerr (tensor contraction `gamma[i,j,k,l]`) and delayed Raman (convolution with `hRω`). Both contribute to `dũω`.
- **Self-steepening**: Frequency-dependent scaling (`ωs/ω0`) applied to the nonlinear term.
- **Adjoint method**: Backward propagation of the adjoint field `λ` to compute gradients of a cost functional w.r.t. input spectral phase, enabling efficient gradient-based optimization.
- **Spectral band cost**: The optimization objective is the fractional energy in a Raman-shifted frequency band: `J = E_band / E_total`.
- **GRIN fiber modes**: For multimode fibers, spatial modes are computed from a graded-index (GRIN) refractive index profile using a finite-difference eigenvalue solver.
- **YDFA gain model**: Ytterbium-doped fiber amplifier gain computed from rate equations using absorption/emission cross-section data from NPZ files.
## Layers
- Purpose: ODE-based pulse propagation through fibers
- Location: `src/simulation/`
- Contains: Forward propagation RHS functions, adjoint RHS, ODE solvers, initial state generators
- Depends on: `DifferentialEquations.jl`, `FFTW.jl`, `Tullio.jl`, `LinearAlgebra`
- Used by: Scripts layer, notebooks
- Purpose: Build fiber parameter dictionaries from physical specifications
- Location: `src/simulation/fibers.jl` (GRIN mode solver), `src/helpers/helpers.jl` (user-defined SMF params)
- Contains: GRIN profile builder, eigenmode solver (`Arpack` sparse eigensolver), overlap tensor computation, simulation parameter setup (`get_disp_sim_params`)
- Depends on: `Arpack`, `SparseArrays`, `FiniteDifferences`, `NPZ`, `FFTW`
- Used by: All propagation solvers via `fiber` and `sim` dictionaries
- Purpose: YDFA spectral gain from Yb3+ rate equations
- Location: `src/gain_simulation/gain.jl`
- Contains: `YDFAParams` struct, cross-section interpolation from NPZ data, gain computation
- Depends on: `NPZ`, `Interpolations`
- Used by: `simulate_disp_gain_smf.jl` and `simulate_disp_gain_mmf.jl`
- Purpose: Quantum noise map computation
- Location: `src/analysis/analysis.jl`, `src/analysis/plotting.jl`
- Contains: Noise variance decomposition (shot noise, excess noise, derivative terms) via `Tullio` tensor contractions
- Used by: Notebooks for noise figure analysis
- Purpose: Raman suppression via spectral shaping
- Location: `scripts/raman_optimization.jl`, `scripts/amplitude_optimization.jl`
- Contains: Cost functions, adjoint gradient computation, L-BFGS optimization, regularization
- Depends on: `MultiModeNoise` module, `Optim.jl`, `scripts/common.jl`
- Used by: Direct execution or `scripts/run_benchmarks.jl`
- Purpose: Fiber presets, problem setup, shared cost/utility functions
- Location: `scripts/common.jl`
- Contains: `FIBER_PRESETS` dictionary, `setup_raman_problem`, `setup_amplitude_problem`, `spectral_band_cost`, `check_boundary_conditions`, `recommended_time_window`
- Used by: All optimization and benchmark scripts
- Purpose: Publication-quality plots for fiber optics simulations
- Location: `scripts/visualization.jl`
- Contains: Spectral/temporal evolution plots, optimization comparison, phase diagnostics, spectrogram
- Depends on: `PyPlot`, `FFTW`, `MultiModeNoise`
- Used by: Optimization scripts for result visualization
## Data Flow
- Simulation state is held in two Dict objects: `sim` (grid/physical constants) and `fiber` (material/geometry parameters)
- ODE state is a complex matrix `ũω` of shape `(Nt, M)` in the interaction picture
- Work arrays are pre-allocated in tuples (`p` parameter) to avoid allocations during ODE integration
## Key Abstractions
| Abstraction | Location | Purpose |
|-------------|----------|---------|
| `sim` Dict | `src/helpers/helpers.jl` :: `get_disp_sim_params()` | Simulation grid parameters: `Nt`, `Δt`, `ts`, `fs`, `ωs`, `ω0`, `attenuator`, `ε`, `β_order` |
| `fiber` Dict | `src/helpers/helpers.jl` :: `get_disp_fiber_params_user_defined()` | Fiber parameters: `Dω` (dispersion operator), `γ` (nonlinear tensor), `hRω` (Raman response), `L` (length), `one_m_fR`, `zsave` |
| `p` tuple (forward) | `src/simulation/simulate_disp_mmf.jl` :: `get_p_disp_mmf()` | Pre-allocated work arrays + FFT plans for the forward ODE RHS |
| `p` tuple (adjoint) | `src/simulation/sensitivity_disp_mmf.jl` :: `get_p_adjoint_disp_mmf()` | Pre-allocated work arrays + FFT plans for the adjoint ODE RHS |
| `YDFAParams` struct | `src/gain_simulation/gain.jl` | Typed parameter container for Yb-doped fiber amplifier (only typed struct in the codebase) |
| `FIBER_PRESETS` Dict | `scripts/common.jl` | Named fiber parameter presets (SMF28, HNLF variants) |
| `band_mask` Bool vector | `scripts/common.jl` :: `setup_raman_problem()` | Boolean mask selecting Raman-shifted frequency bins for cost computation |
## Entry Points
- Location: `src/MultiModeNoise.jl`
- Triggers: `using MultiModeNoise` in scripts/notebooks
- Responsibilities: Loads all submodules via `include()`, exports everything into `MultiModeNoise` namespace
- Location: `scripts/raman_optimization.jl`
- Triggers: `julia scripts/raman_optimization.jl` (uses `abspath(PROGRAM_FILE) == @__FILE__` guard)
- Responsibilities: Runs 5 predefined optimization configurations across SMF-28 and HNLF fibers, generates comparison plots and chirp sensitivity analysis
- Location: `scripts/amplitude_optimization.jl`
- Triggers: `julia scripts/amplitude_optimization.jl` (same guard pattern)
- Responsibilities: Runs spectral amplitude optimization with multiple regularization strategies
- Location: `scripts/run_benchmarks.jl`
- Triggers: `julia scripts/run_benchmarks.jl`
- Responsibilities: Grid size benchmarks, time window analysis, continuation methods, multi-start optimization, parallel gradient validation
- Location: `scripts/test_optimization.jl`
- Triggers: `julia scripts/test_optimization.jl`
- Responsibilities: Unit tests, contract violation tests, property-based tests, integration tests for the optimization pipeline
- Location: `test/runtests.jl`
- Triggers: `julia -e 'using Pkg; Pkg.test("MultiModeNoise")'`
- Responsibilities: Minimal smoke test (module loads successfully)
- Location: `notebooks/*.ipynb`
- Triggers: Manual execution in Jupyter
- Responsibilities: Interactive exploration of MMF squeezing, EDFA/YDFA gain, supercontinuum generation
## Module Relationships
```
```
## Error Handling
- Preconditions on function entry: `@assert ispow2(Nt)`, `@assert L_fiber > 0`, `@assert all(isfinite, φ)`
- Postconditions on results: `@assert 0 <= J <= 1`, `@assert all(isfinite, ∂J_∂φ)`
- `@warn` for soft violations: time window too small for dispersive walk-off
- `throw(ArgumentError(...))` for hard parameter validation in `get_disp_fiber_params_user_defined()`
- No try/catch error recovery in the simulation layer -- failures propagate as exceptions
## Design Decisions
- **Dict-based parameters over structs**: `sim` and `fiber` are plain `Dict{String, Any}` rather than typed structs. This allows flexible key addition (e.g., `fiber["zsave"]` is mutated by optimization code) but sacrifices type safety.
- **Pre-allocated tuple packing**: All ODE work arrays are packed into a single large tuple `p` to avoid allocations during integration. This is a performance-critical pattern for `DifferentialEquations.jl`.
- **Include-based composition (scripts)**: Scripts use `include()` with manual include guards rather than proper module imports. This is a pragmatic choice for research code but creates fragile dependency chains.
- **Interaction picture formulation**: Separating linear dispersion from nonlinear effects allows the ODE solver to use larger step sizes, critical for performance with large `Nt` grids.
- **Adjoint method for gradients**: Rather than automatic differentiation (which would struggle with the ODE solver), the codebase implements a hand-derived adjoint equation for gradient computation. This is exact and efficient but requires maintaining a separate adjoint ODE.
- **Two gain implementations**: `simulate_disp_gain_smf.jl` appears twice (one in `src/simulation/`, one standalone). The version in `src/simulation/` uses a `compute_gain!` placeholder; the standalone has the full YDFA model dispatching on `YDFAParams`.
- **L-BFGS optimization**: Uses `Optim.jl` with L-BFGS for the spectral phase/amplitude optimization. The `only_fg!()` interface computes cost and gradient simultaneously (since both come from the same forward-adjoint pass).
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

## Multi-Machine Workflow

This project runs on **multiple machines** (local Mac + GCP claude-code-host + occasional bursts on fiber-raman-burst). The same repo is cloned on each machine. Without discipline, divergent commits on different machines produce merge conflicts.

### Session hygiene — always do these

**At the START of any Claude Code session (regardless of machine):**

```bash
git fetch origin
git status                        # check for divergence / uncommitted changes
git pull --ff-only origin main    # apply remote changes if local is behind
```

If `git pull --ff-only` fails (diverged histories), the other machine has committed work that isn't in this checkout. Do NOT proceed with edits before reconciling — merging or rebasing blindly after a long session can lose work. Surface it to the user for a decision.

**At the END of any session (or any logical stopping point):**

```bash
git status                        # confirm what's about to be committed
git add <specific files>          # prefer explicit over "git add -A"
git commit -m "<type>(<scope>): <description>"
git push origin main              # so the other machines can pull
```

### Gitignored state: `.planning/` and memory

The `.planning/` directory and `~/.claude/projects/.../memory/` files are **not** tracked in git. Changes there only propagate via the local sync helpers on the Mac:

- `sync-planning-to-vm` — Mac → VM (push planning + memory)
- `sync-planning-from-vm` — VM → Mac (pull planning + memory)

Run these explicitly whenever `.planning/` or memory has been edited on one side. After running `sync-planning-from-vm`, re-read any `.planning/` file you had open — the on-disk content may have changed.

### Machine inventory (as of 2026-04-16)

| Machine | Role | Always on? |
|---|---|---|
| Local Mac (`/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression`) | Primary editing, exploration, advisor context | Yes (whenever laptop is on) |
| `claude-code-host` (GCP e2-standard-4, 34.152.124.66) | Remote Claude Code sessions, long-running tasks | Yes, 24/7 |
| `fiber-raman-burst` (GCP c3-highcpu-22) | Heavy Newton / multimode runs | On-demand (stopped by default) |

See `.planning/todos/pending/provision-gcp-vm.md` and `.planning/notes/compute-infrastructure-decision.md` for the full setup and rationale.

### Common pitfalls

- **Forgetting to pull at session start** → diverged commits, merge conflicts later. Always fetch+pull first.
- **Forgetting to push at session end** → other machines can't see the work. Always push before closing out.
- **Editing `.planning/` on one machine without syncing** → stale state on the other. Run `sync-planning-{to,from}-vm` explicitly.
- **Multiple parallel Claude Code sessions editing the same files** → use git worktrees or enforce non-overlapping directory scope per session.
<!-- GSD:multi-machine-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
