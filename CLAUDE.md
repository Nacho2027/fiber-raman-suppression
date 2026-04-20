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

### Standard output images — mandatory for every optimization run

**Every optimization driver that produces a `phi_opt` MUST, before exiting, call `save_standard_set(...)` from `scripts/standard_images.jl`.** This produces the image set the research group expects:

1. `{tag}_phase_profile.png` — 6-panel before/after optimization comparison (wrapped + unwrapped + group delay × input/output)
2. `{tag}_evolution.png` — colorful spectral-evolution waterfall of the optimized field
3. `{tag}_phase_diagnostic.png` — wrapped/unwrapped/group-delay triplet of phi_opt alone
4. `{tag}_evolution_unshaped.png` — matching waterfall with phi ≡ 0 for comparison

Template:

```julia
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))

# ... setup_raman_problem, run optimizer, produce phi_opt ...

save_standard_set(phi_opt, uω0, fiber, sim,
    band_mask, Δf, raman_threshold;
    tag = "smf28_L2m_P0p2W",                    # filename prefix
    fiber_name = "SMF28", L_m = 2.0, P_W = 0.2, # metadata for captions
    output_dir = "results/raman/my_run/")
```

For runs that produced a `phi_opt` before this rule was in place, run `scripts/regenerate_standard_images.jl` (behind the heavy lock) to generate the standard set for every JLD2 under `results/raman/` that carries a phi_opt. Override the scan root via `REGEN_ROOT`.

Drivers that skip this step are incomplete. Do not mark work "done" without the standard images on disk.
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
- Used by: `simulate_disp_gain_mmf.jl`
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
- **Single live gain implementation**: `simulate_disp_gain_mmf.jl` is the gain-enabled propagation path currently used by the project. The stale placeholder `src/simulation/simulate_disp_gain_smf.jl` was removed in Phase 25 after it was confirmed to be dead code.
- **L-BFGS optimization**: Uses `Optim.jl` with L-BFGS for the spectral phase/amplitude optimization. The `only_fg!()` interface computes cost and gradient simultaneously (since both come from the same forward-adjoint pass).
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

**Strict mode is ON in this project.** `hooks.workflow_guard_strict: true` is set in `.planning/config.json`, so the `PreToolUse` guard at `~/.claude/hooks/gsd-workflow-guard.js` will **hard-deny** `Write`/`Edit` tool calls that target source files outside a GSD workflow context (no active `/gsd-*` skill and no Task subagent).

Allow-list (always permitted, even outside GSD): `.planning/**`, `.gitignore`, `.env*`, `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `settings.json`.

When starting any edit on a tracked source file, route through:
- `/gsd-fast` — trivial one-shot edits, no planning overhead
- `/gsd-quick` — small fixes, doc updates, ad-hoc tasks with state tracking
- `/gsd-debug` — investigation and bug fixing
- `/gsd-execute-phase` — planned phase work

If the user explicitly says "bypass GSD for this one" (or similar), flip `hooks.workflow_guard_strict` to `false` in `.planning/config.json` for the duration of the task, then flip it back. Do NOT silently work around the block any other way.
<!-- GSD:workflow-end -->

## Codex Runtime Constraints

**Context:** On 2026-04-20 a Codex-on-VM session executing Phase 28 produced:
- A single `integrate(phase28-34)` commit spanning **7 phases**
- No `manifest.json` in `.planning/phases/28-*/`
- No atomic per-plan commits
- No visible `spawn_agent(gsd-executor, ...)` handoff

Codex's skill adapter translates Claude's `Task(...)` → `spawn_agent(...)`, but in practice it sometimes silently falls back to inline execution. Heavy orchestrators (`plan-phase`, `execute-phase`, `autonomous`) lose their plan-check / verifier / atomic-commit protocol when this happens, leaving the phase uninauditable.

### Whitelist — Codex MAY invoke these skills

Single-scope, inline-safe, no named subagents required:

- `$gsd-fast`, `$gsd-quick`, `$gsd-note`, `$gsd-add-todo`, `$gsd-add-backlog`
- `$gsd-progress`, `$gsd-stats`, `$gsd-check-todos`, `$gsd-help`, `$gsd-status`
- `$gsd-explore`, `$gsd-spike`, `$gsd-sketch`, `$gsd-plant-seed`
- `$gsd-research-phase` (standalone research only — DO NOT chain to plan or execute)

### Blacklist — Codex MUST NOT invoke these skills

Require subagent orchestration (`gsd-planner`, `gsd-phase-researcher`, `gsd-executor`, `gsd-plan-checker`, `gsd-verifier`, etc.):

- `$gsd-plan-phase`, `$gsd-execute-phase`, `$gsd-execute-plan`
- `$gsd-autonomous`, `$gsd-plan-review-convergence`
- `$gsd-verify-work`, `$gsd-review`, `$gsd-ship`, `$gsd-debug`
- `$gsd-audit-fix`, `$gsd-audit-milestone`, `$gsd-audit-uat`, `$gsd-code-review`
- `$gsd-ingest-docs`, `$gsd-new-milestone`, `$gsd-new-project`

If a Codex session determines it needs a blacklisted skill, it MUST stop and return this exact phrase:

> "This task requires the `[name]` skill, which depends on named subagent orchestration. Codex's adapter is unreliable for this. Please re-run in Claude Code."

**Do NOT** silently execute inline. **Do NOT** manually replicate the skill's workflow (no hand-writing `PHASE-SUMMARY.md`, no fabricating `manifest.json`, no batch-committing multiple plans). Return control to the user.

### Verification after any Codex session touching `.planning/phases/`

```bash
bash scripts/check-phase-integrity.sh <phase-number>
```

Exits 0 if protocol was followed, 1 if violations detected. Run before ending any Codex session that touched phase artifacts; run on any phase you suspect was commit-bombed.

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

## Parallel Session Operation Protocol

**This project runs up to 8 concurrent Claude Code sessions on multiple machines (Mac + claude-code-host + sometimes fiber-raman-burst). Silent conflicts would destroy hours of work. Every agent in every session MUST follow this protocol.**

### Rule P1: Session has an OWNED FILE NAMESPACE. Stay inside it.

When a session is launched with a prompt from `.planning/notes/parallel-session-prompts.md`, that prompt specifies the files it owns. The agent MUST NOT write to files outside its namespace. If the agent needs a change to a file outside its namespace (e.g., a utility in `scripts/common.jl`), it STOPS and escalates to the user — it does not silently edit shared code.

Session namespaces (see `.planning/notes/parallel-session-prompts.md` for exact ownership per session):

- New scripts: prefixed by session topic — `multivar_*.jl`, `mmf_*.jl`, `longfiber_*.jl`, `sweep_simple_*.jl`, `cost_audit_*.jl`, etc.
- New src modules: similarly prefixed and placed in `src/<session_topic>/`
- `.planning/phases/<N>-<session-topic>/` — entire phase dir owned by one session
- `.planning/notes/<session-topic>-*.md` — files prefixed by session topic
- `.planning/seeds/<session-topic>-*.md` — same

**Shared files — NEVER modify without an explicit user go-ahead:**
- `scripts/common.jl`, `scripts/visualization.jl`
- `src/simulation/*.jl`, `src/sensitivity_*.jl` (physics core)
- `Project.toml`, `Manifest.toml`
- `.gitignore`, `CLAUDE.md`, `README.md` (unless this is Session B's job)
- `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, `.planning/PROJECT.md`, `.planning/MILESTONES.md`

### Rule P2: Branch-per-session. Never push directly to `main`.

Each session works in a git worktree on its own branch:

```bash
# Set up ONCE at session start (on Mac or VM — each session in its own worktree):
git worktree add ../raman-wt-<session-name> sessions/<session-name>
cd ../raman-wt-<session-name>
# ... session work happens here ...

# Commits go to this branch:
git commit -m "..."
git push origin sessions/<session-name>
```

**The session NEVER runs `git push origin main`.** Only the user (or a single designated integrator session) merges session branches into main at coordination checkpoints. This eliminates the push race.

### Rule P3: Append-only edits to shared `.planning/` files

If a session MUST touch `STATE.md` / `ROADMAP.md` (e.g., to record a phase outcome), do so ONLY by appending a new row to an existing table — never by editing existing rows. Rebase-friendly.

Better yet: write to a session-specific status file:
- `.planning/sessions/<session-name>-status.md`

The user (or integrator session) aggregates these into the central STATE.md at checkpoints.

### Rule P4: Sync helpers are non-destructive

`sync-planning-to-vm` and `sync-planning-from-vm` use `rsync --update` (not `--delete`) and exclude git-tracked files (`STATE.md`, `ROADMAP.md`). This means:

- Files that exist on only one side are preserved
- If a file differs on both sides, the more recently modified version wins (per `--update`)
- `STATE.md` and `ROADMAP.md` go through git, not rsync — run `git pull` for those

Do NOT run sync-planning-* while another session is actively editing `.planning/` on either side. Coordinate at quiet points.

### Rule P5: Burst VM coordination — MANDATORY WRAPPER (post-2026-04-17)

**Context:** On 2026-04-17, 7+ concurrent heavy Julia processes on the 22-core burst VM caused a hard kernel lockup. The manual lock in the earlier version of this rule was not uniformly respected. The current rule uses an enforced wrapper (`~/bin/burst-run-heavy`) plus a watchdog (`~/bin/burst-watchdog` running as `raman-watchdog.service`). See `scripts/burst/README.md` for the full mechanism.

**All sessions MUST obey the following.**

**Heavy runs** (>8 cores, >5 min, any simulation): never launch directly. Use the wrapper:

```bash
burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy <SESSION-TAG> \
          'julia -t auto --project=. scripts/your_script.jl'"
```

The wrapper enforces session-tag format `^[A-Za-z]-[A-Za-z0-9_-]+$` (e.g., `A-multivar`, `E-sweep2`, `F-T5`, `H-audit`), acquires `/tmp/burst-heavy-lock` with stale-lock detection, launches the job in a named tmux, releases the lock on exit (even on crash via `trap`), and tees all stdout/stderr to `results/burst-logs/<tag>_<timestamp>.log`.

If another session holds the lock, `burst-run-heavy` fails immediately by default and prints the current holder. To wait instead, set `WAIT_TIMEOUT_SEC=<seconds>`:

```bash
burst-ssh "cd fiber-raman-suppression && WAIT_TIMEOUT_SEC=3600 \
          ~/bin/burst-run-heavy F-T5 'julia -t auto --project=. scripts/longfiber.jl'"
```

**Before any work on the burst VM, check state:**

```bash
burst-ssh "~/bin/burst-status"
# Shows: lock holder + pid + start time, tmux sessions, heavy Julia procs,
#        load, memory, watchdog service status.
```

**Light runs** (≤ 4 cores, quick validation): the wrapper is optional, but the `<Letter>-<name>` tmux naming convention is still mandatory so `burst-status` can attribute the work:

```bash
burst-ssh "tmux new -d -s E-validate 'julia -t 4 --project=. scripts/check.jl'"
```

**Watchdog:** `~/bin/burst-watchdog` (running as `systemctl --user status raman-watchdog.service`) kills the youngest heavy Julia if 1-min load > 35 OR available memory < 4 GB, AND ≥ 2 heavy Julia processes are active. Logs to `~/watchdog.log` on the VM. A single job at 100% CPU is fine — the watchdog only fires on contention.

**If in doubt, treat as heavy** — being blocked by the lock is much cheaper than freezing the VM.

**Pre-Apr-17 manual lock pattern (`touch /tmp/burst-heavy-lock`) is DEPRECATED.** Use the wrapper. Any session still using the old pattern is violating Rule P5.

**On-demand second burst VM:** when you want to run a heavy job in parallel with the one on the main burst VM, use `~/bin/burst-spawn-temp <tag> '<command>'` on claude-code-host. It creates an ephemeral VM from a machine image of `fiber-raman-burst`, runs the command, and destroys the VM on exit via a trap (plus a 6-hour auto-shutdown safety net). Use it freely — good cases include a queued heavy job while the main VM is busy, isolated reproducibility runs, and experiments that shouldn't disturb a long-running job. Guidelines: keep the concurrent count of ephemerals at ~2 or fewer (each bills ~$0.90/hr), and run `~/bin/burst-list-ephemerals` at the end of a work block to confirm nothing is orphaned (kill orphans with `--destroy`). Full docs in `scripts/burst/README.md`.

### Rule P6: Session host distribution

The `claude-code-host` VM (e2-standard-4, 16 GB RAM) can host ~3 concurrent Claude Code sessions before OOM. Distribute:

- **Run on Mac**: sessions doing heavy editing / lots of context / light compute (Sessions B docs, G synthesis, E sweep design, D perturbation study). Each in its own `~/raman-wt-<name>` worktree.
- **Run on claude-code-host**: sessions needing the burst VM frequently (Sessions A multivar, C multimode, F long-fiber, H cost-audit). The helper scripts (`burst-start`, `burst-ssh`, etc.) are only on `claude-code-host`.

Before launching a 4th session on claude-code-host, check `free -h` on the VM — if `available` is under 3 GB, don't add more.

### Rule P7: Integration checkpoints

Every 2–3 hours (or at natural breakpoints), the USER (not a session) does an integration pass:

```bash
# On Mac:
git fetch origin
git branch -r | grep sessions/     # see which session branches have new work
for branch in sessions/B-handoff sessions/D-simple ... ; do
  git log main..origin/$branch --oneline  # see what's in each
done

# Review → merge via PR pattern or local merge:
git checkout main
git merge origin/sessions/B-handoff --no-ff   # or just ff if clean
git push origin main
```

Sessions pull from main at the start of their next work block to incorporate the integrations.

## Running Simulations — Compute Discipline

**This project has dedicated compute infrastructure. Use it correctly. These rules apply to ALL agents (Claude Code, sub-agents, planners, executors) running Julia simulations in this project.**

### Rule 1: ALWAYS run simulations on the burst VM, never on `claude-code-host`

**This rule has NO exceptions.** Any Julia execution that does nonlinear fiber propagation — forward solve, adjoint solve, optimization iteration, sweep point, sanity check, unit test of the simulation code — goes on `fiber-raman-burst`.

`claude-code-host` is a small always-on VM (4 vCPU, 16 GB RAM) sized to host Claude Code, not to run compute. Even "small" sims on it will:
- OOM if another Claude Code session is active (each session uses 1–4 GB)
- Starve Claude Code of CPU, making the editing session unresponsive
- Make benchmark numbers unreproducible (noisy neighbor)

If you think your run is "small enough to skip the burst VM," use the burst VM anyway. The 30-second VM-start overhead is trivial compared to the time you save by not having to redo a noisy benchmark or recover a frozen session.

**The ONLY Julia work permitted on `claude-code-host`:**
- `julia --version` and similar single-command checks
- `Pkg.status()`, `Pkg.instantiate()`, dependency resolution
- REPL help / doc lookups (no simulation calls)
- Reading saved JLD2 results for inspection (loading data, not re-running)

Everything else → burst VM.

### How to use the burst VM (current pattern — post-2026-04-17)

From `claude-code-host` (helper scripts are in `~/bin/` on PATH):

```bash
# 1. Commit and push your code changes first (burst VM pulls from git).
git add <files> && git commit -m "..." && git push

# 2. Start the burst VM (~30 s to boot).
burst-start

# 3. Check the VM is free before you try to claim the lock.
burst-ssh "~/bin/burst-status"

# 4. Run the simulation through the MANDATORY heavy-lock wrapper (Rule P5).
#    Session tag must match ^[A-Za-z]-[A-Za-z0-9_-]+$ — e.g. E-sweep2.
burst-ssh "cd fiber-raman-suppression && git pull && \
           ~/bin/burst-run-heavy E-sweep2 \
           'julia -t auto --project=. scripts/your_script.jl'"

# 5. Monitor progress (per-run log path printed by the wrapper).
burst-ssh "tail -f fiber-raman-suppression/results/burst-logs/E-sweep2_*.log"

# 6. When done, pull results back to the claude-code-host checkout.
rsync -az -e "gcloud compute ssh --zone=us-east5-a --project=riveralab --" \
      fiber-raman-burst:~/fiber-raman-suppression/results/ \
      ~/fiber-raman-suppression/results/

# 7. ALWAYS STOP THE BURST VM WHEN DONE (~$0.90/hr while running).
burst-stop
```

The raw `tmux new -d -s run 'julia ...'` pattern from earlier versions of
this doc is DEPRECATED because it bypasses the heavy-lock and can
re-create the Apr-17 lockup scenario. Use `~/bin/burst-run-heavy` instead.

Helper scripts: `burst-start`, `burst-stop`, `burst-ssh`, `burst-status`.

### Rule 2: ALWAYS launch Julia with threading enabled

**The simulation core in `src/simulation/` is single-threaded by default — you must enable threading explicitly via the Julia launch flag.** Without it, you use 1 core out of 4 (or 22 on the burst VM).

```bash
julia -t auto --project=. <script>      # use all available threads (PREFERRED)
julia -t 22 --project=. <script>        # or explicit count for burst VM
```

**Never launch bare `julia` for simulation work.** Verify inside Julia with `Threads.nthreads()` (should return > 1).

Threading speedups observed (per `scripts/benchmark_threading.jl`, commit `d1c5bd9`):

- **Parallel forward solves: 3.55×** at 8 threads on M3 Max → expect ~10–15× on the 22-core burst VM
- **Multi-start optimization: 2.13×** at 8 threads
- **FFTW threading at Nt=2^13: counterproductive** — do NOT call `FFTW.set_num_threads(n > 1)` at this grid size; it's already worse
- **Tullio threading at M=1: no effect** (tensor contractions trivial) — becomes meaningful at `M > 1`

These numbers are only achieved if Julia is launched with `-t N`. Without the flag, all parallelism is dormant.

### Rule 3: ALWAYS stop the burst VM when simulations complete

The burst VM bills at ~$0.90/hr while running, $0 while stopped. Leaving it running overnight by accident costs ~$21. Over a weekend, ~$65. The 4-week project budget is $300 free trial — careless runtime eats it fast.

Before ending any session that touched the burst VM:

```bash
burst-status            # verify: TERMINATED means stopped
burst-stop              # if it shows RUNNING, stop it now
```

### When the `deepcopy(fiber)` pattern is required

Multi-threaded Julia code sharing the `fiber` dict across threads **will race** because `fiber["zsave"]` and other fields are mutated inside solvers. Any `Threads.@threads` loop over independent solves must do:

```julia
Threads.@threads for i in 1:n_tasks
    fiber_local = deepcopy(fiber)      # per-thread copy
    # ... use fiber_local, never the shared fiber
end
```

This pattern is already used in `scripts/benchmark_optimization.jl:635` for multi-start optimization and `scripts/benchmark_optimization.jl:704` for parallel gradient validation. Copy it when adding new parallel solve blocks (Newton Hessian, parameter sweeps, etc.).

### Summary — quick checklist before running any simulation

- [ ] Is this "non-trivial" per Rule 1? → YES: use burst VM. NO: may run on `claude-code-host`.
- [ ] Did I commit and push my code changes so the burst VM's `git pull` gets them?
- [ ] Am I launching Julia with `-t auto` (or `-t N`)?
- [ ] If adding new parallel loops: am I `deepcopy(fiber)` per thread?
- [ ] When done: have I run `burst-stop`?
<!-- GSD:multi-machine-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
