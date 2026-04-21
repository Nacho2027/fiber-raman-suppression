# Architecture

**Analysis Date:** 2026-04-19

## Pattern Overview

**Overall:** Forward–adjoint gradient optimization over a nonlinear-fiber ODE, split across a thin typed core (`src/MultiModeNoise.jl`) and a large pool of prefix-scoped driver scripts in `scripts/` that own the optimizer loops, cost-function variants, and result I/O.

**Key Characteristics:**

- **Interaction-picture GMMNLSE.** Forward dynamics encoded as `disp_mmf!` / `adjoint_disp_mmf!` (in `src/simulation/simulate_disp_mmf.jl` and `src/simulation/sensitivity_disp_mmf.jl`) — the linear dispersion operator `Dω` is factored out analytically, so only the slow nonlinear part is integrated by the ODE solver. This is the *single* physics core — all drivers delegate here.
- **Hand-derived adjoint method.** `adjoint_disp_mmf!` integrates the transpose-conjugate Jacobian backward from z=L to 0, using the stored forward `ODESolution` as a continuous interpolant at each step (`ũω_z .= ũω(z)` in `sensitivity_disp_mmf.jl:50`). Exact gradients — no automatic differentiation.
- **Preallocated tuple-packed ODE state.** `get_p_disp_mmf` / `get_p_adjoint_disp_mmf` pack ~20 working arrays + FFTW plans into one `Tuple`, destructured on entry to `disp_mmf!` (`simulate_disp_mmf.jl:26`). Zero allocations per ODE step.
- **Dict-based parameters, not structs.** `sim::Dict{String,Any}` (grid) and `fiber::Dict{String,Any}` (material/geometry) are passed through every layer. Only `YDFAParams` (gain model) is a typed struct.
- **Include-based composition for scripts.** No submodule namespaces — `common.jl`, `visualization.jl`, `standard_images.jl`, `determinism.jl` are `include()`'d via manual include guards (`_COMMON_JL_LOADED`, `_MMF_SETUP_JL_LOADED`, etc.). Allows prefix-scoped driver ownership without touching shared files.
- **Mandatory post-run image contract.** Every driver that produces a `phi_opt` MUST call `save_standard_set(...)` from `scripts/standard_images.jl` (4 PNGs per run). Enforced by `CLAUDE.md` and compliance scan.
- **Deterministic numerics baseline.** `scripts/determinism.jl::ensure_deterministic_environment()` pins FFTW planner to `:ESTIMATE`, loads FFTW wisdom from `results/raman/phase14/fftw_wisdom.txt`, fixes BLAS threads. Called at the top of every serious driver.
- **Parallel-session workflow.** Scripts carry a topic prefix (`multivar_*`, `mmf_*`, `longfiber_*`, `sweep_simple_*`, `cost_audit_*`, `sharp_ab_*`, `phase13_*`, `phase14_*`, `phase15_*`) reflecting which concurrent Claude Code session owns them. Shared physics files (`src/simulation/*`, `scripts/common.jl`, `scripts/visualization.jl`) are strictly read-only outside coordinated merges.

## Layers

**Physics core (forward + adjoint):**
- Purpose: Nonlinear pulse propagation and adjoint sensitivity in SMF and GRIN MMF.
- Location: `src/simulation/`
- Contains:
  - `simulate_disp_mmf.jl` — forward RHS `disp_mmf!`, `get_p_disp_mmf`, `solve_disp_mmf`
  - `sensitivity_disp_mmf.jl` — adjoint RHS `adjoint_disp_mmf!`, `solve_adjoint_disp_mmf`, `calc_δs!`
  - `simulate_disp_gain_mmf.jl` — gain-enabled propagation path with `compute_gain` dispatch
  - `simulate_mmf.jl` — fiber-mode-only solver (no dispersion; Session C reference)
  - `fibers.jl` — GRIN dielectric profile, finite-difference Helmholtz eigensolver, overlap tensor `γ[i,j,k,l]`
- Depends on: `DifferentialEquations.jl` (Tsit5, Vern9), `FFTW.jl` (preplanned MEASURE), `Tullio.jl` + `LoopVectorization`, `Arpack.jl`, `SparseArrays`, `FiniteDifferences`, `LinearAlgebra`
- Used by: every driver script, notebooks, tests

**Parameter construction:**
- Purpose: Build `sim` and `fiber` dicts from physical specs (SI units).
- Location: `src/helpers/helpers.jl`, `src/simulation/fibers.jl`
- Contains:
  - `get_disp_sim_params(λ0, M, Nt, time_window, β_order)` — temporal/spectral grids, super-Gaussian attenuator window, quantum-noise constant `ε`
  - `get_disp_fiber_params(L, radius, core_NA, alpha, nx, sim, fname; ...)` — GRIN path (hits `build_GRIN` + eigensolver, NPZ cached)
  - `get_disp_fiber_params_user_defined(L, sim; gamma_user, betas_user, fR)` — SMF path (Taylor β expansion, bypasses GRIN)
  - `get_initial_state(u0_modes, P_cont, pulse_fwhm, rep_rate, pulse_shape, sim)` — sech² or Gaussian pulse
- Depends on: `Arpack`, `SparseArrays`, `FiniteDifferences`, `NPZ`, `FFTW`
- Used by: all `setup_*_problem` helpers

**Gain modeling (YDFA):**
- Purpose: Yb³⁺ rate-equation gain for SMF/MMF amplifier runs.
- Location: `src/gain_simulation/gain.jl` with companion data `Yb_absorption.npz`, `Yb_emission.npz`
- Contains: `YDFAParams` struct (only typed struct in the codebase), cross-section interpolation, `compute_gain!`
- Used by: `simulate_disp_gain_mmf.jl`, notebooks

**Quantum-noise analysis:**
- Purpose: Shot/excess/derivative noise decomposition via mode-overlap Tullio contractions.
- Location: `src/analysis/analysis.jl`, `src/analysis/plotting.jl`
- Used by: notebooks (`notebooks/mmf-spmode-squeezing_*.ipynb`, `notebooks/EDFA.ipynb`, etc.)

**SMF driver / shared scripts layer:**
- Purpose: Fiber presets, problem setup, spectral-band cost, plotting, standard-image contract, determinism.
- Location: `scripts/common.jl`, `scripts/visualization.jl`, `scripts/standard_images.jl`, `scripts/determinism.jl`
- Contains:
  - `FIBER_PRESETS` Dict (`:SMF28`, `:SMF28_beta2_only`, `:HNLF`, `:HNLF_zero_disp`)
  - `setup_raman_problem`, `setup_amplitude_problem`
  - `recommended_time_window` (dispersive walk-off + SPM correction), `nt_for_window`
  - `spectral_band_cost` — canonical `J = E_band/E_total` and its adjoint terminal condition
  - `check_boundary_conditions`
  - `save_standard_set` — mandatory 4-PNG post-run output
- Protected — edits require explicit user go-ahead (Rule P1 in `CLAUDE.md`).

**MMF driver layer (Session C — Phase 16/17):**
- Purpose: Multimode Raman suppression with shared spectral phase across M modes.
- Location: `scripts/mmf_*.jl` plus `src/mmf_cost.jl` (cost variants live in `src/` so MMF and SMF drivers can both import them).
- Contains:
  - `scripts/mmf_fiber_presets.jl` — `MMF_FIBER_PRESETS` (`:GRIN_50` M=6, `:STEP_9` M=4), `MMF_DEFAULT_MODE_WEIGHTS`
  - `scripts/mmf_setup.jl` — `setup_mmf_raman_problem`, NPZ-cached GRIN eigensolve
  - `scripts/mmf_raman_optimization.jl` — `cost_and_gradient_mmf`, L-BFGS driver (shared φ, fixed `c_m`)
  - `scripts/mmf_joint_optimization.jl` — Phase 17: joint φ + mode-coefficient optimization
  - `scripts/mmf_run_phase16_all.jl`, `mmf_run_phase16_aggressive.jl` — batch runners
  - `scripts/mmf_m1_limit_run.jl`, `mmf_smoke_test.jl`, `mmf_analyze_phase16.jl` — sanity + analysis
  - `src/mmf_cost.jl` — `mmf_cost_sum` (integrating detector), `mmf_cost_fundamental` (mode-selective), `mmf_cost_worst_mode` (log-sum-exp smooth-max)

**Multivariable optimizer layer (Session A — Phase 16/18):**
- Purpose: Jointly optimize any subset of {phase φ(ω), amplitude A(ω), energy E} through a single forward-adjoint pass.
- Location: `scripts/multivar_*.jl`
- Contains:
  - `scripts/multivar_optimization.jl` — `MVConfig`, `cost_and_gradient_multivar`, `optimize_spectral_multivariable`, `run_multivar_optimization`, `save_multivar_result`/`load_multivar_result`
  - `scripts/multivar_demo.jl` — end-to-end example and A/B plot
  - `scripts/test_multivar_gradients.jl`, `scripts/test_multivar_unit.jl` — finite-difference gradient checks
- Math: `.planning/notes/multivar-gradient-derivations.md`. Schema: `.planning/notes/multivar-output-schema.md`.

**Low-res phase sweep + Pareto (Session E — Phase 16):**
- Purpose: Parameterize φ in a low-dim cosine basis, sweep N_φ, L, P, fiber to build a Pareto front.
- Location: `scripts/sweep_simple_*.jl`
- Contains: `sweep_simple_param.jl` (cosine basis + mapping), `sweep_simple_run.jl` (sweep driver), `sweep_simple_analyze.jl`, `sweep_simple_visualize_candidates.jl`
- Outputs: `results/raman/phase_sweep_simple/{sweep1_Nphi,sweep2_LP_fiber}.jld2` + `pareto.png` + standard-image set per candidate.

**Simple-phase profile stability (Session D — Phase 17):**
- Purpose: Test robustness of low-rank `{linear chirp, quadratic, GDD sweep, ...}` phase families.
- Location: `scripts/simple_profile_driver.jl`, `simple_profile_metrics.jl`, `simple_profile_stdimages.jl`, `simple_profile_synthesis.jl`, `render_simple_phases.jl`.

**Long-fiber propagation (Session F — Phase 16):**
- Purpose: 50/100 m SMF runs with explicit (Nt, time_window) grid (not auto-sized).
- Location: `scripts/longfiber_*.jl`, `scripts/longfiber_burst_launcher.sh`.
- Contains: `longfiber_setup.jl` (grid table from research brief D-F-02), `longfiber_forward_100m.jl`, `longfiber_optimize_100m.jl`, `longfiber_checkpoint.jl` (mid-run resume), `longfiber_validate_{50m,100m,100m_fix}.jl`, `longfiber_regenerate_standard_images.jl`.

**Sharpness-aware optimizer (Sessions G / Phase 14):**
- Purpose: Hessian-trace regularization for flatter minima.
- Location: `scripts/sharpness_optimization.jl`, `scripts/sharp_ab_slim.jl` (Session G slim A/B), `sharp_ab_figures.jl`, `sharp_robustness_slim.jl`, `scripts/phase14_*.jl` (original Phase 14 family).

**Cost-function audit (Session H — Phase 16/18):**
- Purpose: 3 configs × 4 cost variants (linear, log_dB, sharp, curvature) with Hessian eigenspectra and robustness probes.
- Location: `scripts/cost_audit_driver.jl`, `cost_audit_analyze.jl`, `cost_audit_noise_aware.jl`, plus `cost_audit_run_*.sh` / `cost_audit_spawn_direct*.sh` burst launchers.

**Landscape diagnostics (Phase 13):**
- Purpose: Gauge-fixed Hessian eigenspectrum, polynomial parameterization, HVP.
- Location: `scripts/phase13_primitives.jl`, `phase13_hvp.jl`, `phase13_gauge_and_polynomial.jl`, `phase13_hessian_eigspec.jl`, `phase13_hessian_figures.jl`.

## Data Flow

**Per-driver forward–adjoint–optimize loop:**

1. Driver calls `setup_raman_problem` (SMF) or `setup_mmf_raman_problem` (MMF) — returns `(uω0, fiber, sim, band_mask, Δf, raman_threshold, ...)`.
2. Shape input: `uω0_shaped = uω0 .* cis(φ)` (plus amplitude/energy scaling in multivar path).
3. Forward: `sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)` — Tsit5 integrates `disp_mmf!` from z=0 to z=L, storing the `ODESolution` as a continuous interpolant.
4. Extract `uωf = sol.u[end]` at z=L.
5. Cost: `(J, dJ) = spectral_band_cost(uωf, band_mask)` (SMF) or one of `mmf_cost_{sum,fundamental,worst_mode}` (MMF). `dJ = ∂J/∂conj(uωf)` is the adjoint terminal condition.
6. Adjoint: `λ0 = MultiModeNoise.solve_adjoint_disp_mmf(dJ, sol, fiber, sim)` — backward integrate `adjoint_disp_mmf!` from z=L to z=0, passing the forward solution interpolant.
7. Gradient chain rule: `∂J/∂φ = 2 · Re( λ(0) .* im .* uω0_shaped )` (phase path). Multivar path has per-variable chain rules for A and E.
8. Regularizers added outside adjoint: GDD penalty `λ_gdd · Σ(Δ²φ)²`, boundary leakage penalty, Tikhonov/TV/flat for amplitude.
9. L-BFGS (`Optim.jl`'s `only_fg!`) consumes `(J, grad)` tuple, updates φ.
10. On convergence: `save_standard_set(phi_opt, uω0, fiber, sim, band_mask, Δf, raman_threshold; tag, fiber_name, L_m, P_W, output_dir)` → 4 PNGs.
11. Persist `_result.jld2` + `_result.json` sidecar + append to `results/raman/manifest.json`.

**State management:**
- Simulation state during ODE integration: `ũω::Matrix{ComplexF64}(Nt, M)` in the interaction picture.
- Optimization state: flat `Vector{Float64}` of length `Nt` (phase-only), `2Nt` (multivar phase+amp), `2Nt+1` (phase+amp+energy).
- `fiber["zsave"]` is mutated by drivers that want intermediate snapshots — do `fiber_local = deepcopy(fiber)` inside `Threads.@threads` loops to avoid races (pattern in `scripts/benchmark_optimization.jl:635` and `:704`).

## Key Abstractions

**`sim::Dict{String,Any}`** (built by `get_disp_sim_params`):
- Purpose: temporal and spectral grids, physical constants.
- Keys: `"λ0"`, `"f0"`, `"ω0"`, `"M"`, `"Nt"`, `"time_window"`, `"Δt"`, `"ts"`, `"fs"`, `"ωs"`, `"attenuator"` (super-Gaussian order-30 window on 85% of time span), `"ε"` (vacuum-noise photon scale), `"β_order"`, `"c0"`, `"h"`.

**`fiber::Dict{String,Any}`** (built by `get_disp_fiber_params` or `get_disp_fiber_params_user_defined`):
- Purpose: dispersion operator, nonlinear tensor, Raman kernel, length, optional spatial modes.
- Keys: `"Dω"` (Nt×M dispersion phase per metre), `"γ"` (M×M×M×M overlap tensor or 1×1×1×1 for SMF), `"hRω"` (Raman response in ω), `"L"`, `"one_m_fR"`, `"zsave"` (override sample z's), `"ϕ"` (spatial modes, `nothing` for SMF), `"x"` (spatial grid, `nothing` for SMF), `"gain_parameters"`.

**Preallocated ODE tuple `p`:**
- Forward `p`: 24-element tuple from `get_p_disp_mmf` — `(selfsteep, Dω, γ, hRω, one_m_fR, attenuator, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_p, exp_D_m, uω, ut, v, w, δKt, δKt_cplx, αK, βK, ηKt, hRω_δRω, hR_conv_δR, δRt, αR, βR, ηRt, ηt)`.
- Adjoint `p`: nested tuple `(p_params, p_fft, p_prealloc, p_calc_δs, p_γ_a_b)` — destructured at top of `adjoint_disp_mmf!`.

**`band_mask::Vector{Bool}`:**
- Purpose: boolean selector on FFT-order frequency bins that count as Raman-shifted.
- Default: `Δf_fft .< raman_threshold` with `raman_threshold = -5.0 THz` (configurable).
- Used as terminal-condition weight in `spectral_band_cost`.

**`MVConfig` (multivar optimizer):**
- `@kwdef mutable struct` in `scripts/multivar_optimization.jl:78`.
- Fields: `variables::Tuple` (subset of `:phase, :amplitude, :energy`), `δ_bound`, `amp_param` (`:tanh` or `:fminbox`), per-var preconditioner scales `s_φ,s_A,s_E`, `log_cost`, regularizers `λ_gdd,λ_boundary,λ_energy,λ_tikhonov,λ_tv,λ_flat`.

**`YDFAParams`:**
- `@kwdef mutable struct` in `src/gain_simulation/gain.jl` — only typed struct in the core.

**Fiber preset NamedTuples:**
- SMF: `FIBER_PRESETS::Dict{Symbol,NamedTuple}` in `scripts/common.jl:47`.
- MMF: `MMF_FIBER_PRESETS::Dict{Symbol,NamedTuple}` in `scripts/mmf_fiber_presets.jl:46` with additional fields `radius, core_NA, alpha, M, nx, spatial_window, β_order, Δf_THz`.

## Entry Points

**Main SMF Raman driver:**
- Location: `scripts/raman_optimization.jl`
- Triggers: `julia -t auto --project=. scripts/raman_optimization.jl` (guarded by `abspath(PROGRAM_FILE) == @__FILE__`)
- Responsibilities: runs the 5 canonical SMF-28/HNLF configs, writes JLD2 + standard image set + manifest entry.

**MMF Raman driver:**
- Location: `scripts/mmf_raman_optimization.jl`
- Triggers: `julia -t auto --project=. scripts/mmf_raman_optimization.jl`
- Responsibilities: multimode phase-only optimization at M=6 (GRIN_50) or M=4 (STEP_9), dispatch on cost variant `:sum | :fundamental | :worst_mode`. Batch runners live in `mmf_run_phase16_{all,aggressive}.jl`.

**Multivar optimizer:**
- Location: `scripts/multivar_demo.jl` (single canonical config), `scripts/multivar_optimization.jl` (library + `run_multivar_optimization`)
- Responsibilities: joint {φ, A, E} optimization through a single forward-adjoint.

**Low-res phase sweep (Pareto hunter):**
- Location: `scripts/sweep_simple_run.jl [--sweep1|--sweep2|--both] [--dry-run]`
- Responsibilities: 64+ config Pareto sweep with 3-seed multi-start at coarsest N_φ.

**Simple-profile stability:**
- Location: `scripts/simple_profile_driver.jl`, `simple_profile_synthesis.jl`.

**Long-fiber 100 m:**
- Location: `scripts/longfiber_optimize_100m.jl` (heavy), `longfiber_checkpoint.jl` (resume), `longfiber_validate_100m.jl` (post-hoc). Launch via `scripts/longfiber_burst_launcher.sh`.

**Sharpness A/B:**
- Location: `scripts/sharp_ab_slim.jl` (Session G, 3 λ values, trimmed budget).

**Cost-function audit:**
- Location: `scripts/cost_audit_driver.jl` (3 configs × 4 variants = 12 runs; burst-VM-bound).

**Benchmarks & verification:**
- `scripts/benchmark_optimization.jl` — grid, time-window, continuation, multi-start, parallel-gradient suites.
- `scripts/benchmark_threading.jl` — thread scaling (see `.planning/quick/260415-u4s-benchmark-threading-*`).
- `scripts/verification.jl` — physics sanity checks.
- `scripts/run_benchmarks.jl`, `run_comparison.jl`, `run_sweep.jl` — legacy orchestrators.

**Tests:**
- `test/runtests.jl` — smoke test (module loads).
- `test/tier_{fast,slow,full}.jl` — tiered test harness.
- `test/test_{cost_audit_*,determinism,phase13_*,phase14_*,phase16_mmf}.jl` — topical.
- `scripts/test_{optimization,visualization_smoke,multivar_gradients,multivar_unit}.jl` — script-layer tests co-located with drivers.

**Notebooks (interactive):**
- Location: `notebooks/*.ipynb` — `EDFA`, `YDFA{,_modular}`, `MultiModeNoise_DispMMF_test`, `mmf-spmode-squeezing_{FvsP,dbk}`, `mmf_spmode_squeezing_f_vs_p_vs_spm`, `smf_{gain_YDFA,gain_linear,supercontinuum}`.

## Error Handling

**Strategy:** design-by-contract via `@assert`, hard `ArgumentError` for user-facing library inputs, `@warn` for soft violations, no try/catch in the numerical path (errors propagate to the caller).

**Patterns:**
- `@assert ispow2(Nt)`, `@assert L_fiber > 0`, `@assert all(isfinite, φ)` as preconditions at the top of every public function.
- Postconditions `@assert 0 ≤ J ≤ 1`, `@assert all(isfinite, dJ)` immediately before return in cost functions (e.g. `src/mmf_cost.jl:59`).
- `throw(ArgumentError("..."))` for hard parameter validation in `src/helpers/helpers.jl:171` (missing `gamma_user`/`betas_user`).
- `@warn` for recoverable drift (e.g. `multivar_optimization.jl:117` stripping `:mode_coeffs`; auto-widening `time_window` in `setup_raman_problem` logs `@info`).
- `try ... using Revise ... catch end` at the top of every dev-facing driver — optional hot-reload without failing headless runs.

## Cross-Cutting Concerns

**Determinism:**
- `scripts/determinism.jl::ensure_deterministic_environment()` — called at the top of every driver. Pins FFTW planner to `ESTIMATE`, loads wisdom from `results/raman/phase14/fftw_wisdom.txt`, sets `BLAS.set_num_threads(1)`.

**Logging:**
- `@info`/`@debug`/`@warn` from `Logging` stdlib. `@debug` visible with `JULIA_DEBUG=all`. Box-drawing banners for run summaries (`print_fiber_summary` in `common.jl:145`).

**Plotting contract:**
- `save_standard_set(...)` in `scripts/standard_images.jl` — 4 PNGs per run: `{tag}_phase_profile.png` (6-panel before/after), `{tag}_evolution.png` (optimized waterfall), `{tag}_phase_diagnostic.png` (wrapped/unwrapped/GD), `{tag}_evolution_unshaped.png` (φ≡0 comparison). MANDATORY per `CLAUDE.md`.
- Use `scripts/regenerate_standard_images.jl` (SMF) or `longfiber_regenerate_standard_images.jl` to backfill pre-contract runs.

**Threading / compute discipline:**
- All simulations run on `fiber-raman-burst` VM through `~/bin/burst-run-heavy <session-tag>` wrapper (heavy-lock `/tmp/burst-heavy-lock` + watchdog service). `claude-code-host` is reserved for editing only. See `CLAUDE.md` "Running Simulations" + `scripts/burst/README.md`.
- Julia always launched with `-t auto` or `-t N`. Never bare `julia` for simulation work.
- `Threads.@threads` loops MUST `deepcopy(fiber)` per iteration — shared `fiber["zsave"]` mutation is the known race.

**Result layout:**
- `results/raman/<run_or_phase>/` — JLD2 + JSON sidecar + PNGs + per-phase `FINDINGS.md`.
- `results/raman/manifest.json` — append-only index of canonical SMF runs.
- `results/burst-logs/<tag>_<timestamp>.log` — stdout/stderr tee from `burst-run-heavy`.
- `results/cost_audit/{A,B}/`, `results/raman/{phase13,phase14,phase15,phase16,phase17}/`, `results/raman/{multivar,phase_sweep_simple,hnlf,smf28,validation,research}/`.

## Design Decisions

- **Dict-based parameters over structs.** `sim` and `fiber` are plain Dicts so drivers can add keys (`"zsave"`, `"gain_parameters"`) without touching the core. The cost is type instability at Dict lookups, but this is outside the ODE hot path.
- **Hand-derived adjoint vs. autodiff.** `DifferentialEquations.jl`'s SciMLSensitivity paths were rejected — the explicit adjoint ODE matches the physics in closed form (no AD overhead, no dual-number proliferation through FFT plans and Tullio contractions).
- **Interaction picture.** The `exp(±iDω·z)` factors let the ODE solver take ~10× larger steps, critical at `Nt=2^13–2^14`.
- **Preallocated tuple packing.** A 24-slot `Tuple` passes cleanly into `DifferentialEquations.jl`'s parameter slot while being destructured with zero overhead.
- **L-BFGS with `only_fg!`.** Cost and gradient come from the *same* forward-adjoint pass — `Optim.jl`'s `only_fg!` interface consumes both, so the optimizer never asks for `f` without `g`.
- **Log-scale cost by default.** `log_cost::Bool=true` on phase and multivar optimizers — `J̃ = 10·log10(J)` with gradient scaled by `10/(J·ln10)`. Gives 20–28 dB improvement over linear cost (see user memory `project_dB_linear_fix.md`).
- **Shared φ across modes in MMF.** `scripts/mmf_raman_optimization.jl` broadcasts a single `φ::Vector{Float64}(Nt)` to the `(Nt,M)` field because a single pulse shaper is physically realizable. Joint `(φ, c_m)` optimization deferred to Phase 17 (`mmf_joint_optimization.jl`).
- **Topic-prefixed driver namespaces.** Enables up to 8 concurrent Claude Code sessions to edit new files in parallel without touching `src/simulation/*`, `scripts/common.jl`, or `scripts/visualization.jl` (Rule P1 in `CLAUDE.md`).
- **Include-guard composition.** Scripts use `if !(@isdefined _FOO_JL_LOADED)` guards so they can be safely `include()`'d from multiple drivers and tests.
- **Determinism over speed.** FFTW `ESTIMATE` is 2–3× slower than `MEASURE` but bit-identical across runs — critical for Hessian eigenspectra (Phase 13) and sharpness metrics (Phase 14).

---

*Architecture refresh: 2026-04-19*
