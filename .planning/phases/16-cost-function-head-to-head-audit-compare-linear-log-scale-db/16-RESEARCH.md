# Phase 16: Cost Function Head-to-Head Audit — Research

**Researched:** 2026-04-17 (Session H, auto mode)
**Domain:** Cost-function methodology for gradient-based spectral-phase optimization in nonlinear fiber optics; ML loss-landscape literature synthesis
**Confidence:** HIGH (codebase verified line-by-line; literature claims cross-referenced against arXiv/proceedings abstracts)

## Summary

Phase 16 is a methodology phase, not a discovery phase: the user has locked all 22 decisions in `16-CONTEXT.md`, and the research job is to (1) verify that those decisions are implementable against the existing codebase without touching shared files, (2) attach the ML loss-landscape literature the decision doc will cite, and (3) flag execution risks that the plan must guard against. The codebase scan confirms every reusable asset named in CONTEXT exists and exports the signatures CONTEXT claims (`optimize_spectral_phase`, `optimize_spectral_phase_sharp`, `make_sharp_problem`, `build_gauge_projector`, `fd_hvp`, `build_oracle`, `HVPOperator`, `input_band_mask`, `omega_vector`, `ensure_deterministic_environment`). The Phase-13 Hessian eigenspectrum pipeline (`scripts/phase13_hessian_eigspec.jl`, verified) is directly reusable for Phase 16's D-14 metric 4 — we wrap it, we do not reimplement it.

The literature synthesis supports the conceptual bridge CONTEXT draws — "experimentally robust = flat minimum" — but forces one tightening: Zhuang et al. 2022 (GSAM) showed that low perturbed loss (SAM's proxy) can still sit in sharp basins, which argues the robustness metric (D-14 item 5) and the Hessian spectrum (item 4) should both weigh in the decision doc, not just one or the other. For the log-scale cost (D-02), the existing gradient chain-rule (`10/(J·ln10)` with `J_clamped = max(J, 1e-15)`) is mathematically correct and the clamp handles the only genuine failure mode (J→0); Phase 8 empirical record (20–28 dB deeper J) supports keeping it as a baseline horse in the race.

The largest execution risk is not correctness — it is wall-time. D-14's metric 4 alone (top-32 Arpack eigenvalues via 2·K HVP-based Lanczos on gauge-projected Hessian at Nt=8192) is roughly the cost of a full L-BFGS optimization per (config), per variant. The plan must budget this explicitly or drop metric 4 to top-16 on the burst VM.

**Primary recommendation:** Build Phase 16 as three thin wrapper scripts (`cost_audit_driver.jl`, `cost_audit_analyze.jl`, `cost_audit_noise_aware.jl`) that call existing public entry points unmodified, snapshot per-(variant, config) JLD2 after each run for restart-tolerance, run the 12-run batch under a single `/tmp/burst-heavy-lock`, and report all 4 variants' metrics against each other with a heatmap of per-metric ranks. Time-box the Hessian eigenspectrum at top-32 (CONTEXT) but add a fallback to top-16 if the first two configs exceed 12 min each.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Cost-Function Variants (the four horses)**

- **D-01 [auto]: Linear cost.** `optimize_spectral_phase(..., log_cost=false, λ_gdd=0.0, λ_boundary=0.0)` — the original `J = E_band / E_total` as minimization target.
- **D-02 [auto]: Log-scale dB cost.** `optimize_spectral_phase(..., log_cost=true)` — Phase 8 fix. Gradient scaled by `10/(J·ln10)` via existing code.
- **D-03 [auto]: Sharpness-aware cost.** `optimize_spectral_phase_sharp(prob, φ0; lambda_sharp=0.1, n_samples=8, eps=1e-3, rng=MersenneTwister(seed))` — Phase 14 `J + λ·S(φ)` with Hutchinson-estimated sharpness under gauge-projected Rademacher directions. λ fixed at the Phase 14 default (no sweep — that was Plan 14-02's scope; we subsume it by reporting a single λ).
- **D-04 [auto]: Noise-aware scaffold.** Cost = linear `J` + `γ_curv · ⟨|∂²φ/∂ω²|²⟩_band` where the weighted average is over the Raman band frequency bins. γ_curv=1e-4 chosen so the curvature term is O(10%) of the linear J at the starting phase (auto-calibrated per config at φ₀, logged). Scaffold-quality: not claimed physically rigorous, but numerically well-defined and differentiable. Placed in `scripts/cost_audit_noise_aware.jl` as a pure wrapper that adds the penalty to the existing J and ∇J tuple.

**Fair-Comparison Protocol (locked, identical across all 4 variants per config)**

- **D-05 [auto]: Grid.** `Nt=8192`, `beta_order=3`, `M=1`.
- **D-06 [auto]: Starting phase.** `φ₀ = 0.1 · randn(MersenneTwister(SEED), Nt)` with **SEED fixed per config** (42, 43, 44 for configs A, B, C respectively) and reused verbatim across all four cost variants within a config.
- **D-07 [auto]: Iteration cap.** `max_iter=100` uniformly.
- **D-08 [auto]: Stopping criterion.** `f_abstol=0.01` (the existing `log_cost=true` default = 0.01 dB change) for all four variants. For the linear variant we override `f_tol=1e-10`.
- **D-09 [auto]: FFTW determinism.** Load `results/raman/phase14/fftw_wisdom.txt` at the top of each run. Phase 15 (FFTW.ESTIMATE across `src/simulation/`) is structural; wisdom is belt-and-suspenders.
- **D-10 [auto]: Thread count.** `julia -t auto` on the 22-core burst VM. `deepcopy(fiber)` guard per solve thread.

**Configurations (3 regimes)**

- **D-11 [auto]: Config A (simple).** SMF-28, L=0.5 m, P=0.05 W. Weak-nonlinearity regime.
- **D-12 [auto]: Config B (hard).** SMF-28, L=5 m, P=0.2 W. Hard regime — beyond L₅₀dB≈3.33 m.
- **D-13 [auto]: Config C (high-nonlinearity).** HNLF, L=1 m, P=0.5 W. High γ regime.

**Metrics (extracted per run)**

- **D-14 [auto]: Primary metrics per run.** (1) Final J (linear and dB), (2) Wall time, (3) Iterations to L-BFGS termination + iterations to 90% of final ΔJ_dB, (4) Hessian top-32 eigenspectrum at optimum via gauge-projected Lanczos/Arpack on HVP, (5) Robustness under perturbation: σ ∈ {0.01, 0.05, 0.1, 0.2} rad × n_trials=10, mean & max ΔJ_dB.
- **D-15 [auto]: Secondary.** Convergence trace; starting J_dB sanity; for sharpness variant: `S(φ_final)` and `λ·S(φ_final)`.

**Reporting Artifacts**

- **D-16 [auto]: Per-config table** `results/cost_audit/<config>/summary.csv`.
- **D-17 [auto]: Cross-config summary** `results/cost_audit/summary_all.csv`.
- **D-18 [auto]: Figures.** 4 PNGs @ 300 DPI: convergence overlay, robustness curves, eigenspectrum, winner heatmap.
- **D-19 [auto]: Decision doc** `.planning/notes/cost-function-default.md` — recommendation + rationale with ML literature citations.

**Execution Discipline**

- **D-20 [auto]: Burst VM mandatory.** All 12 runs + 3 Hessian eigenspectra on `fiber-raman-burst`, guarded by `/tmp/burst-heavy-lock`. `burst-stop` at end.
- **D-21 [auto]: Commit discipline.** All commits to `sessions/H-cost` branch. Never push to `main`.
- **D-22 [auto]: Zero modification of shared files.** Protected: `scripts/common.jl`, `scripts/raman_optimization.jl`, `scripts/sharpness_optimization.jl`, `src/simulation/**`, `Project.toml`.

### Claude's Discretion

- Exact Hessian-eigenvalue solver choice (Arpack vs KrylovKit). Default: Arpack.
- Analyzer figure styling beyond 300 DPI + project colors.
- Snapshot intermediate JLD2 per-run vs only at end. Recommended: per-run (restart-tolerance).
- Sharpness λ value: Phase 14 default (0.1) unless degeneracy at φ_opt; fallback to 0.01.

### Deferred Ideas (OUT OF SCOPE)

- Li-et-al.-style 2D loss-surface visualization around each optimum (~4× Hessian cost).
- Sharpness-λ grid sweep (was Plan 14-02 scope).
- First-principles quantum-noise cost (D-04 is a classical proxy only).
- Multimode M>1 comparison (Session C territory).
- Multi-start per variant (keeps batch within 90 min).
- Burn-in warm start (e.g., run linear first, then sharpness).

</user_constraints>

## Project Constraints (from CLAUDE.md)

These must be honored by the plan; the planner verifies compliance task-by-task.

| Source | Directive | Enforcement |
|--------|-----------|-------------|
| CLAUDE.md Rule P1 | Session H may only write `scripts/cost_audit_*.jl`, `.planning/phases/16-*/`, `.planning/notes/cost-audit-*.md`, `.planning/sessions/H-cost-*.md` | Plan's final verification task runs `git diff --stat origin/main…HEAD` and asserts no paths outside the namespace are modified. |
| CLAUDE.md Rule P2 | Never `git push origin main`; only push to `sessions/H-cost`. | Plan includes a pre-push guard (`git branch --show-current` must equal `sessions/H-cost`). |
| CLAUDE.md Rule P5 | Heavy runs on burst VM must hold `/tmp/burst-heavy-lock`; release at end. | Plan's driver wraps the 12-run batch in a lock `touch`/`rm -f` pair inside a single tmux session. |
| CLAUDE.md "Running Simulations" Rule 1 | ALL Julia simulation work on `fiber-raman-burst`, never on `claude-code-host`. | Plan's driver runs on burst VM exclusively; claude-code-host is used only for code editing and rsync of results. |
| CLAUDE.md "Running Simulations" Rule 2 | Always launch `julia -t auto` (or `-t 22`). | Plan's tmux command uses `julia -t auto --project=.`. |
| CLAUDE.md "Running Simulations" Rule 3 | `burst-stop` when done. | Plan's final task is an unconditional `burst-stop` after rsync. |
| CLAUDE.md "deepcopy(fiber)" pattern | Any `Threads.@threads` loop over solves must `fiber_local = deepcopy(fiber)`. | For Phase 16 we keep per-run solves *serial* (one optimization at a time, each using all threads internally via FFTW/BLAS — which Phase 15 has pinned to 1). See Risk R4 below. |
| STATE.md "Script Constant Prefixes" | Each script uses a unique `const` prefix to avoid REPL collisions. | Phase 16 uses `CA_` prefix (per CONTEXT code_context). |
| STATE.md "Include Guards" | Scripts use `if !(@isdefined _NAME_LOADED)`; `using` stays OUTSIDE the guard. | Plan's wrapper scripts follow the pattern, copying the shape from `sharpness_optimization.jl`. |
| STATE.md "Deterministic Numerical Environment (Phase 15)" | Call `ensure_deterministic_environment()` at top of each entry-point script. | Plan's driver and analyzer both include `scripts/determinism.jl` and call the helper. |
| STATE.md "Critical Directive — Do Not Break Original Optimizer Path" | Existing `spectral_band_cost` and `optimize_spectral_phase` MUST remain fully functional and untouched. | Phase 16 is strictly additive: no writes outside the cost_audit_ namespace, verified by the same git-diff guard as Rule P1. |

<phase_requirements>
## Phase Requirements

Phase 16 was added 2026-04-17; it does not map to the v2.0 requirement IDs (VERIF-/XRUN-/PATT-/SWEEP-), which are all complete per REQUIREMENTS.md. Session H has produced the phase as an independent methodology sprint. The planner should treat the CONTEXT decisions D-01…D-22 as the requirements for this phase:

| ID | Description | Research Support |
|----|-------------|------------------|
| D-01…D-04 | Four cost-function variants | `optimize_spectral_phase` + `optimize_spectral_phase_sharp` + a new `cost_and_gradient_curvature_penalty` wrapper in `scripts/cost_audit_noise_aware.jl`. All verified callable. |
| D-05…D-10 | Fair-comparison protocol | Grid choice matches existing canonical Phase 14 snapshot (Nt=8192, β_order=3, M=1); seeds reused across variants via `MersenneTwister(SEED)`; `f_abstol=0.01` matches the log_cost default in `optimize_spectral_phase:200`. Determinism guaranteed by Phase 15 (`FFTW.ESTIMATE` patched across 18 plan call sites in `src/simulation/*.jl`; FFTW+BLAS pinned to 1 thread). |
| D-11…D-13 | Three (fiber, L, P) configs | All three reachable via `setup_raman_problem(fiber_preset=:SMF28 / :HNLF, L_fiber=…, P_cont=…)` with β_order=3 as required by 2-beta presets. |
| D-14…D-15 | Per-run metrics | (1–3) directly from `Optim.OptimizationResult` (`Optim.minimum`, `Optim.iterations`, `Optim.f_trace`, wall clock). (4) via `scripts/phase13_hvp.jl :: build_oracle` + `HVPOperator` + `Arpack.eigs(:LR, nev=32)`, gauge-projected via `build_gauge_projector` from `sharpness_optimization.jl`. (5) by looping over σ values and calling `cost_and_gradient(φ_opt + σ·randn(), ...)`. |
| D-16…D-19 | Reporting | CSVs via DataFrames+CSV.jl (already project deps); PNG figures via PyPlot @ 300 DPI matching project convention. |
| D-20…D-22 | Execution discipline | Verified in "Project Constraints (from CLAUDE.md)" above. |

</phase_requirements>

## Architectural Responsibility Map

Phase 16 is a *wrapper-scripts* phase, so the tier map is much simpler than a multi-tier app. The capability-to-tier mapping is about which existing module owns each piece of work:

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Physics forward/adjoint ODE solves | `src/simulation/*.jl` (MultiModeNoise core) | — | Canonical codebase layer; Phase 15 pinned the determinism here. |
| Cost functions + L-BFGS (linear, log, GDD/boundary penalties) | `scripts/raman_optimization.jl` | `scripts/common.jl` (setup + shared utilities) | Already complete; `optimize_spectral_phase` is the dispatch entry for D-01/D-02. |
| Sharpness regularizer + gauge projector | `scripts/sharpness_optimization.jl` | — | Already complete; `optimize_spectral_phase_sharp` is the dispatch for D-03. |
| Gauge fix + polynomial projection + HVP | `scripts/phase13_primitives.jl` + `scripts/phase13_hvp.jl` | — | Already complete; reused for metric 4 (Hessian top-32). |
| Hessian eigenspectrum pipeline | `scripts/phase13_hessian_eigspec.jl` | — | Already complete; Phase 16 wraps its `HVPOperator` pattern, not the full script. |
| Determinism environment | `scripts/determinism.jl` | — | Already complete; Phase 16 calls `ensure_deterministic_environment()` at the top of every entry-point script. |
| **New: D-04 cost wrapper (curvature penalty)** | `scripts/cost_audit_noise_aware.jl` | — | Wraps `cost_and_gradient` (unchanged) by adding `γ_curv · Σ_band (φ[i+1] - 2φ[i] + φ[i-1])² / Δω³`; autodiff-free analytical gradient mirrors the existing `λ_gdd` penalty code in `raman_optimization.jl:114–128`. |
| **New: 12-run driver** | `scripts/cost_audit_driver.jl` | — | Sequential runner: 3 configs × 4 variants. Snapshots per-(variant, config) JLD2. |
| **New: Analyzer** | `scripts/cost_audit_analyze.jl` | — | Post-processes JLD2s into CSVs + 4 PNGs + the decision-doc input. |

**Tier check:** Nothing in Phase 16 reaches below the scripts layer into `src/*`. Any attempt to (e.g.) pull `solve_disp_mmf` parameters out or to modify `spectral_band_cost` is out of scope and a Rule P1 violation.

## Standard Stack

### Core (already in use — no new deps)

| Library | Version (verified) | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Optim.jl | 1.13.3+ (Project.toml) | L-BFGS optimizer | `optimize_spectral_phase*` already use `Optim.only_fg!()`; we do not touch this. [CITED: julianlsolvers.github.io/Optim.jl] |
| FFTW.jl | (unversioned, latest stable) | FFT plans | Phase 15 pinned `ESTIMATE` + 1 thread; Phase 16 imports wisdom for extra safety. [CITED: fftw.org/fftw3_doc] |
| Arpack.jl | (unversioned) | Matrix-free Lanczos/Arnoldi `eigs` | Already used in `src/simulation/fibers.jl` for GRIN mode solver; reused in `phase13_hessian_eigspec.jl` for HVP-based eigendecomposition. [CITED: julialinearalgebra.github.io/Arpack.jl] — matrix-free contract: implement `size`, `eltype`, `issymmetric`, `mul!` on the operator. |
| JLD2.jl | (unversioned) | Per-run snapshot I/O | Project-wide pattern; already used by `optimize_spectral_phase`'s `jldsave(...)` in `raman_optimization.jl:511`. |
| CSV.jl | 0.10.15 | CSV writers for summaries | Already in `Project.toml`. |
| DataFrames.jl | 1.8.1 | Tabular aggregation for summary_all.csv | Already in `Project.toml`. |
| PyPlot.jl | (unversioned) | 300 DPI PNG figures | Project standard; `Agg` backend via `ENV["MPLBACKEND"]="Agg"`. |
| Random (stdlib) | 1.11.0 | `MersenneTwister(seed)` for reproducible phase starts and Hutchinson RNG | — |
| Dates (stdlib) | 1.11.0 | `RUN_TAG = Dates.format(now(), "yyyymmdd_HHMMss")` | Existing pattern in `raman_optimization.jl:656`. |

### Supporting (already loaded via include chain)

| Library | Purpose | When to Use |
|---------|---------|-------------|
| MultiModeNoise module | `solve_disp_mmf`, `solve_adjoint_disp_mmf`, `lin_to_dB` | Called through `cost_and_gradient` — never directly from Phase 16 code. |
| `scripts/common.jl` | `setup_raman_problem`, `FIBER_PRESETS`, `spectral_band_cost`, `check_boundary_conditions` | Required setup for every run. |
| `scripts/raman_optimization.jl` | `cost_and_gradient`, `optimize_spectral_phase` | D-01, D-02 dispatch; D-04 wraps. |
| `scripts/sharpness_optimization.jl` | `optimize_spectral_phase_sharp`, `make_sharp_problem`, `build_gauge_projector`, `cost_and_gradient_sharp`, `SO_input_band_mask` | D-03 dispatch; gauge projector reused for D-14 metric 4. |
| `scripts/phase13_primitives.jl` | `input_band_mask`, `omega_vector`, `gauge_fix`, `polynomial_project` | Used via `scripts/phase13_hvp.jl`. |
| `scripts/phase13_hvp.jl` | `build_oracle`, `fd_hvp`, `validate_hvp_taylor` | D-14 metric 4 HVP machinery. |
| `scripts/phase13_hessian_eigspec.jl` | `HVPOperator` struct (AbstractMatrix-like adaptor for `Arpack.eigs`) | **Pattern reuse**, not import — Phase 16 defines its own `CA_HVPOperator` if desired to keep Rule P1 clean, but can also `include()` this script read-only. Recommend the latter. |
| `scripts/determinism.jl` | `ensure_deterministic_environment()` | Call once at top of every Phase 16 script. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff | Decision |
|------------|-----------|----------|----------|
| Arpack.jl (Fortran ARPACK wrapper) | KrylovKit.jl (pure-Julia Lanczos/Arnoldi) | KrylovKit is pure-Julia, thread-safe, and more actively maintained; Arpack has a known gotcha that `:SR` can stall at near-zero modes. | Keep Arpack — already used by `phase13_hessian_eigspec.jl` and `src/simulation/fibers.jl`; switching would require changing those too. Rule P1 forbids. [ASSUMED]: KrylovKit would likely be faster, but not verified for this codebase. |
| Hutchinson sharpness (Phase 14) | PyHessian-style Lanczos trace estimate | Hutchinson already implemented; Lanczos trace needs HVP which Phase 13 has but Phase 14 avoided. | Keep Hutchinson per D-03 lock. |
| D-04 autodiff (Zygote/Enzyme) | Hand-coded analytical gradient (mirror `λ_gdd` pattern) | Hand-coded gradient is ≤ 30 lines and matches the existing project's explicit-gradient style (see REQUIREMENTS.md OUT-OF-SCOPE note about AD's poor fit with `DifferentialEquations.jl`). | Hand-code; the curvature penalty is a quadratic form in φ and its gradient is linear in φ. |
| 2D loss-surface slice (Li 2018) | — | Compute cost ≈ 4× eigenspectrum (~200 forward solves per direction for a 30×30 grid). | CONTEXT defers; eigenspectrum is the quantitative substitute. |

**No new packages required.** Phase 16 is purely additive in the `scripts/cost_audit_*.jl` namespace; all dependencies are already in `Project.toml`.

**Version verification:** Project.toml `[compat]` says Optim=1.13.3. [VERIFIED: Project.toml read] — the actually-resolved version in `Manifest.toml` is what matters; the plan should `Pkg.status Optim` at the start of the batch and log the version.

## Architecture Patterns

### System Architecture Diagram

Data flow for a single (variant, config) run, and for the analyzer pass:

```
                           Phase 16 — Per-run data flow
                           ═════════════════════════════

 ┌─────────────────────────────────────────────────────────────────────────┐
 │  (fiber_preset, L, P) per config A/B/C                                  │
 └───────────────┬─────────────────────────────────────────────────────────┘
                 │ setup_raman_problem(; Nt=8192, β_order=3, …)
                 ▼
 ┌─────────────────────────────────────────────────────────────────────────┐
 │  uω0, fiber, sim, band_mask, Δf  ← scripts/common.jl (UNCHANGED)        │
 └───────────────┬─────────────────────────────────────────────────────────┘
                 │ Random.seed!(SEED)  (42 / 43 / 44 for A/B/C)
                 │ φ₀ = 0.1 * randn(Nt)
                 ▼
 ┌─────────────────────────────────────────────────────────────────────────┐
 │  For each variant in {linear, log_dB, sharp, curvature}:                │
 │    • dispatch to optimize_spectral_phase(..., log_cost=false/true)     │
 │      OR optimize_spectral_phase_sharp(prob, φ₀; …)                      │
 │      OR curvature-wrapped cost+grad → optimize_spectral_phase(...)     │
 │    • load FFTW wisdom, call ensure_deterministic_environment()         │
 │    • time-box @elapsed                                                 │
 │    • Optim returns (minimizer, minimum, f_trace, iterations, converged)│
 └───────────────┬─────────────────────────────────────────────────────────┘
                 │ φ_opt
                 ▼
 ┌──────────────────────────┬──────────────────────────┬──────────────────┐
 │  Hessian top-32          │  Robustness probe        │  Convergence     │
 │  ─ gauge_projector via   │  σ ∈ {0.01,0.05,0.1,0.2} │  trace → dB      │
 │    build_gauge_projector │  n_trials=10             │                  │
 │  ─ HVP via build_oracle  │  for each σ,trial:       │                  │
 │    + fd_hvp              │    φ_p = φ_opt + σ·randn │                  │
 │  ─ Arpack.eigs(:LR,32)   │    J_p, _ = CG(φ_p…)     │                  │
 │    on HVPOperator        │    ΔJ_dB = 10·log10(…)   │                  │
 └──────────────┬───────────┴──────────┬───────────────┴────────┬─────────┘
                │                      │                        │
                ▼                      ▼                        ▼
 ┌─────────────────────────────────────────────────────────────────────────┐
 │  results/cost_audit/<config>/<variant>_result.jld2 (per-run snapshot)   │
 │  ─ φ_opt, J_final, ftrace, iterations, wall_s                          │
 │  ─ lambda_top_32, condition_proxy, lambda_max                          │
 │  ─ robust_σ*_mean_dB, robust_σ*_max_dB                                 │
 └─────────────────────────────────────────────────────────────────────────┘


                           Phase 16 — Analyzer pass
                           ═══════════════════════

  results/cost_audit/A/*.jld2 ──┐
  results/cost_audit/B/*.jld2 ──┼──► cost_audit_analyze.jl
  results/cost_audit/C/*.jld2 ──┘            │
                                             ├─► summary.csv per config (D-16)
                                             ├─► summary_all.csv (D-17)
                                             ├─► fig1: convergence overlay
                                             ├─► fig2: robustness curves
                                             ├─► fig3: eigenspectra
                                             ├─► fig4: winner heatmap
                                             └─► .planning/notes/cost-function-default.md
                                                     (hand-written, cites data + ML lit)
```

### Recommended Project Structure

```
scripts/
├── cost_audit_noise_aware.jl     # NEW — D-04 wrapper (curvature penalty)
├── cost_audit_driver.jl          # NEW — 12-run orchestrator
└── cost_audit_analyze.jl         # NEW — CSVs + figures + decision-doc input

results/cost_audit/               # NEW output tree
├── A/ {linear,log_dB,sharp,curvature}_result.jld2, summary.csv
├── B/ {linear,log_dB,sharp,curvature}_result.jld2, summary.csv
├── C/ {linear,log_dB,sharp,curvature}_result.jld2, summary.csv
├── summary_all.csv
├── fig1_convergence.png
├── fig2_robustness.png
├── fig3_eigenspectra.png
└── fig4_winner_heatmap.png

.planning/notes/
└── cost-function-default.md      # NEW — the decision recommendation + rationale
```

### Pattern 1: Three-layer wrapper (dispatch, not reimplement)

**What:** Each variant is a thin function that (1) prepares the problem via `setup_raman_problem`, (2) seeds RNG deterministically, (3) dispatches to the correct existing optimizer with the correct kwargs. Phase 16 never reimplements cost or gradient code for D-01/D-02/D-03. Only D-04 adds a penalty — and its analytical gradient mirrors the existing `λ_gdd` pattern.

**When to use:** Every Phase 16 code path that does a forward optimization.

**Example (D-04 curvature-penalty variant):**

```julia
# Source: new file scripts/cost_audit_noise_aware.jl
# Pattern mirror: scripts/raman_optimization.jl:114-128 (GDD penalty)

function cost_and_gradient_curvature(φ, uω0, fiber, sim, band_mask;
        γ_curv::Real, band_mask_output::AbstractVector{Bool},
        uω0_shaped=nothing, uωf_buffer=nothing,
        λ_gdd::Real=0.0, λ_boundary::Real=0.0)
    # 1. Base linear cost and gradient — UNCHANGED call into the shared oracle.
    J, ∂J_∂φ = cost_and_gradient(φ, uω0, fiber, sim, band_mask;
        uω0_shaped=uω0_shaped, uωf_buffer=uωf_buffer,
        λ_gdd=λ_gdd, λ_boundary=λ_boundary, log_cost=false)

    # 2. Curvature penalty over the output Raman band: ⟨|∂²φ/∂ω²|²⟩_band.
    Nt, M = size(φ)
    Δω = 2π / (Nt * sim["Δt"])
    inv_Δω4 = 1.0 / Δω^4          # finite-difference /Δω² squared → /Δω⁴ scaling
    P = 0.0
    ∂P_∂φ = zeros(size(φ))
    N_band = count(band_mask_output)
    for m in 1:M
        for i in 2:(Nt-1)
            if band_mask_output[i]
                d2 = φ[i+1, m] - 2*φ[i, m] + φ[i-1, m]
                P += inv_Δω4 * d2^2 / N_band
                coeff = 2 * inv_Δω4 * d2 / N_band
                ∂P_∂φ[i-1, m] += coeff
                ∂P_∂φ[i,   m] -= 2*coeff
                ∂P_∂φ[i+1, m] += coeff
            end
        end
    end
    return J + γ_curv * P, ∂J_∂φ .+ γ_curv .* ∂P_∂φ
end
```

Note: CONTEXT D-04 specifies the curvature average is **over the Raman band** (the output spectral band from `band_mask`). This is the "noise-aware" interpretation (penalize curvature where the physical noise lives). The existing `λ_gdd` penalty by contrast integrates curvature over the *entire* grid — so D-04 is genuinely different, not duplicative.

### Pattern 2: Matrix-free HVP eigendecomposition

**What:** Wrap `fd_hvp` as an `AbstractMatrix`-like struct that implements `size`, `eltype`, `issymmetric`, `ishermitian`, and `LinearAlgebra.mul!`. Pass to `Arpack.eigs(op; nev=32, which=:LR)`.

**When to use:** D-14 metric 4, once per (variant, config) — 12 eigendecompositions total (not 3; each variant has its own optimum).

**Example (already in codebase):**

```julia
# Source: scripts/phase13_hessian_eigspec.jl:104-121

struct HVPOperator{F, V}
    n::Int
    oracle::F
    phi::V
    eps::Float64
end
Base.size(H::HVPOperator) = (H.n, H.n)
Base.size(H::HVPOperator, d::Integer) = H.n
Base.eltype(::HVPOperator{F, V}) where {F, V} = Float64
LinearAlgebra.issymmetric(::HVPOperator) = true
LinearAlgebra.ishermitian(::HVPOperator) = true
function LinearAlgebra.mul!(y::AbstractVector, H::HVPOperator, x::AbstractVector)
    y .= fd_hvp(H.phi, collect(x), H.oracle; eps=H.eps)
    return y
end
```

**Gauge projection:** Before the eigendecomposition, build a gauge-projected oracle — every HVP call projects input and output vectors through `P = build_gauge_projector(ωs, input_band_mask)`. This forces Arpack's Krylov subspace to stay in the non-gauge subspace and avoids the "half of the small eigenvalues are the 2 gauge modes" artifact Phase 13 documented. Add this as a tiny wrapper inside `cost_audit_driver.jl`:

```julia
function gauge_projected_oracle(raw_oracle, P)
    return phi -> begin
        g = raw_oracle(phi)
        return P(g)
    end
end
```

This gives a Hessian whose restriction to the non-gauge subspace is what we actually want to characterize.

### Pattern 3: Per-run snapshot for restart tolerance

**What:** After each (variant, config) optimization + metric extraction, write a self-contained JLD2 with everything needed to rebuild plots. If the batch crashes at run 9/12, the first 8 are preserved and the driver can skip them on restart via a `isfile(snapshot_path)` guard.

**Pattern mirror:** `raman_optimization.jl:511` `jldsave(jld2_path; …)`.

### Anti-Patterns to Avoid

- **Reimplementing `cost_and_gradient` for D-04.** The user directive in STATE.md ("the original cost function and that type of method should be kept separate") means we do **not** mutate or fork the existing cost — D-04 adds a penalty on top of a called-through linear cost, just like the existing `λ_gdd` penalty does. Treating D-04 as a fork would duplicate the adjoint ODE pipeline.
- **Running all 12 runs in parallel via `Threads.@threads`.** Even with `deepcopy(fiber)` per thread, the 12 runs would need 12× the memory (≈ 1–2 GB per Nt=8192 sim, so 12–24 GB → fits on 44 GB burst VM but puts OS/FFTW into swap territory) and Phase 15's `FFTW.set_num_threads(1)` gives up its advantage. Serial runs with per-run `julia -t 22` is the right pattern.
- **Computing Hessian eigenspectrum *during* optimization.** D-14 metric 4 is only needed at the converged `φ_opt`. Interleaving would 10×+ the batch time.
- **Letting the driver touch anything outside `scripts/cost_audit_*.jl`.** Rule P1 / D-22 — silently editing `common.jl` to pass `band_mask_output` through would violate the lock. All wiring goes through existing public kwargs.
- **Dropping FFTW wisdom import because "Phase 15 handles it."** The wisdom file is a *cross-process* cache that hardens against subtly different FFTW library updates on the burst VM (provisioned separately from claude-code-host). Import it; the cost is 2 ms.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Adjoint ODE gradient | Autodiff of `solve_disp_mmf` | `cost_and_gradient` (raman_optimization.jl:52) | REQUIREMENTS.md lists this as explicitly out of scope; hand-derived adjoint is exact and battle-tested. |
| Sharpness estimator | New Hutchinson loop | `cost_and_gradient_sharp` (sharpness_optimization.jl:304) | Phase 14 has the gauge-projected Rademacher estimator with `n_samples=8` already verified. |
| Gauge projector | New Gram-Schmidt code | `build_gauge_projector(ωs, input_band_mask)` (sharpness_optimization.jl:142) | Exact same projector that Phase 14 gauge-projects Hutchinson directions — reusing it for the Hessian projection guarantees consistency. |
| Hessian-vector product | New finite-difference | `fd_hvp` (phase13_hvp.jl:148) | Already validated O(ε²) against Taylor remainder via `validate_hvp_taylor`. |
| Matrix-free Lanczos on HVP | Raw Arpack wrapping | `HVPOperator` struct (phase13_hessian_eigspec.jl:104) | 18 lines, battle-tested at Nt=8192 for two configs in Phase 13 Plan 02. |
| Input-band mask | New energy-cumulative mask | `SO_input_band_mask` (sharpness_optimization.jl:89) or `input_band_mask` (phase13_primitives.jl:106) — these two are *twins*, same algorithm | Pick `SO_input_band_mask` to stay within the sharpness_optimization.jl dependency set. |
| FFTW wisdom + BLAS pinning | ad-hoc `FFTW.set_num_threads(1)` in every file | `ensure_deterministic_environment()` from `scripts/determinism.jl` | Phase 15's canonical single-source helper. |
| Log-scale cost math | `10·log10(J)` + chain rule by hand | `log_cost=true` kwarg on `optimize_spectral_phase` (raman_optimization.jl:101–109) | Phase 8 fix already includes the `J_clamped = max(J, 1e-15)` guard against `J→0`. |
| JLD2 manifest / per-run metadata | New JSON writer | Existing pattern: `jldsave(…; phi_opt=…, J_after=…, sim_Dt=…, …)` | `Phase13_hessian_eigspec.jl:269-315` shows 40+ keys; mimic the subset we need. |

**Key insight:** Phase 16 is a *composition* phase, not a construction phase. Approximately 85% of the code should be `include()` + function call. Any new file longer than ~200 lines is a design smell.

## Runtime State Inventory

> This phase is additive (new scripts + new results dir). It does not rename, refactor, or migrate anything.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — verified by codebase grep for "ChromaDB", "Redis", "SQLite", "Mem0". Project is a local Julia codebase; no datastores other than JLD2 files in `results/`. | None |
| Live service config | None — no UI-defined config (no n8n, Datadog, Tailscale, Cloudflare). The only external service is the burst VM, whose config is in git via `.planning/notes/compute-infrastructure-decision.md`. | None |
| OS-registered state | None — no Task Scheduler / systemd / launchd / pm2 registrations. `burst-*` helpers in `~/bin/` on the claude-code-host VM are already deployed (Phase 15 era). | None |
| Secrets and env vars | `ENV["MPLBACKEND"]="Agg"` (not a secret, just backend choice). `ENV["JULIA_NUM_THREADS"]`/`-t N` are passed at launch. No .env files. | None |
| Build artifacts / installed packages | `Manifest.toml` is committed and pinned. `Project.toml` is unchanged by Phase 16 (Rule P1/D-22). `~/.julia/compiled/*` on the burst VM will rebuild on first run — harmless. | None |

**Nothing needs a data migration or runtime-state change.** Phase 16 is a pure scripts-layer addition.

## Common Pitfalls

### Pitfall 1: `setup_raman_problem` auto-sizing silently grows `Nt`

**What goes wrong:** The wrapper at `common.jl:353` auto-expands `time_window` (and therefore `Nt` via `nt_for_window`) when the SPM-corrected window exceeds the requested one. For config B (SMF-28, L=5 m, P=0.2 W), the default `time_window=10.0` will be auto-grown — STATE.md Phase 12 explicitly notes that for L ≥ 10 m, the auto-sizer "always overrides explicit Nt/tw".

**Why it happens:** Design-by-contract to prevent attenuator absorption at boundaries.

**How to avoid:** For each config, **compute the recommended time window ahead of time and pass it explicitly**; check that the returned `sim["Nt"] == 8192` matches CONTEXT D-05. If not, the grid has silently inflated and the "fair-comparison" protocol is broken across configs.

**Warning signs:** Run log prints `"Auto-sizing: time_window N→M ps, Nt N→M"`. Treat this as a fatal configuration error in Phase 16.

**Concrete action for plan:** The driver explicitly computes `recommended_time_window(L; beta2, gamma, P_peak)` per config, passes that as the `time_window` kwarg, and asserts that `sim["Nt"] == 8192`. If the user actually wants a bigger grid for config B, that's a CONTEXT amendment, not a silent plan deviation.

### Pitfall 2: `f_abstol` semantics differ between linear and log cost

**What goes wrong:** `f_abstol=1e-10` for the linear variant tests for a 1e-10 change in linear J ∈ [0,1]. `f_abstol=0.01` for log/sharpness tests for a 0.01 dB change. These correspond to ~ -100 dB absolute stopping vs ~ 0.2% relative stopping — wildly different criteria.

**Why it happens:** The linear scale is already very small near optima (J ≈ 1e-7 at -70 dB), so `1e-10` is actually a tight relative criterion; but it will often not trigger on config A where J starts much larger.

**How to avoid:** Accept the CONTEXT-locked defaults (D-08), but the **analyzer must normalize**: convert every trace to dB before plotting (already in CONTEXT's analyzer spec). And the "iter_to_90% of final ΔJ_dB" metric should be computed from the dB-converted trace uniformly. Document in the decision doc that the linear variant stopping may bite earlier or later than others depending on the regime.

### Pitfall 3: D-04 curvature penalty auto-calibration at φ₀=random may be near zero

**What goes wrong:** CONTEXT says `γ_curv` is chosen so the penalty is ~10% of `J(φ₀)` at the starting random phase. But a random phase has enormous curvature (φ₀ = 0.1·randn → ⟨|∂²φ|²⟩ ≈ 0.01 × Δω⁻⁴ × 2 per bin, summed over Raman band of ~500 bins → order 10⁴ unless Δω is also large) — so `γ_curv` could end up being ~1e-4 to 1e-6 depending on the grid.

**Why it happens:** Random-phase curvature is not a physically meaningful baseline; it's just white-noise second-derivative content.

**How to avoid:** The plan's D-04 driver should log both `P(φ₀)` and `J(φ₀)` before computing `γ_curv`, log the result, and — if `γ_curv` ends up outside `[1e-6, 1e-2]` — fall back to a hand-chosen value (recommend `1e-4` as CONTEXT suggests) with a warning. Do NOT silently let an extreme auto-calibrated value wreck the optimization.

**Warning signs:** D-04 optimization terminates in < 10 iterations with J barely moving (penalty dominates) or the phase goes to a pathologically smooth polynomial (penalty overwhelms J). Spot-check against the convergence trace.

### Pitfall 4: Arpack `:SR` (smallest real) stalls on near-zero gauge modes

**What goes wrong:** Even with the gauge projector applied, floating-point residue in the projected HVP can leave 2 eigenvalues very close to zero. `Arpack.eigs(:SR, nev=K)` may ping-pong between these and not converge within `maxiter=500`.

**Why it happens:** Arpack's Lanczos re-orthogonalization is not perfect at scale Nt=8192; the residual null-space contamination is at the ε_machine × ‖H‖ level.

**How to avoid:** CONTEXT D-14 only asks for the **top-32** eigenvalues (`:LR`), not the bottom. Use `:LR` exclusively. The top-32 are the "stiff directions" — precisely what gets us `λ_max` and (by ratio of top to 32nd) a practical condition number proxy. The gauge modes are in the *bottom* tail; we don't need them.

**Warning signs:** Arpack warning `XYAUPD: number of iterations exceeded maxiter`. If the top-32 extraction warns, increase `maxiter` from 500 to 1000 and `tol` from 1e-7 to 1e-6 as a fallback.

### Pitfall 5: Hessian eigenspectrum wall-time budget

**What goes wrong:** Per `phase13_hessian_eigspec.jl` tolerances (`tol=1e-7`, `maxiter=500`), a `:LR` 20-eigenvalue extraction at Nt=8192 takes on the order of 2 forward+adjoint solves × (ncv ≥ 41 Lanczos vectors × some restarts) — with each HVP = 2 forward + 2 adjoint solves. On Phase 13's two completed runs this worked out to minutes per decomposition; at `nev=32` the cost scales super-linearly (ncv grows). Expect 5–20 min per (variant, config) eigendecomposition. For 12 variant-config pairs, that's ~1–4 hours of Hessian work alone.

**Why it happens:** Krylov-subspace size `ncv` in Arpack defaults to `max(20, 2·nev+1) = 65` at `nev=32`. Each restart does ~ncv Lanczos steps; each step is 2 oracle calls; each oracle call is 1 forward + 1 adjoint solve.

**How to avoid:** Budget explicitly. Recommend the plan:
1. Time-box the eigenspectrum pass to 90 min across all 12 runs.
2. Start with `nev=32`; if the first (variant, config) pair takes > 10 min, drop to `nev=16` for remaining pairs and log the reduction in the summary CSV.
3. Relax `tol` from 1e-7 to 1e-5 — the eigenvalues themselves are already contaminated at O(ε_HVP²) ≈ 1e-8 relative by the finite-difference HVP, so tighter tolerance is false precision.

### Pitfall 6: `cost_and_gradient_sharp` with `log_cost=true` is the Phase 14 default

**What goes wrong:** `optimize_spectral_phase_sharp`'s default is `log_cost=true` (sharpness_optimization.jl:431). CONTEXT says D-03 uses the Phase 14 default, which implies `log_cost=true` under the hood — but CONTEXT also compares D-03 against D-01 (linear) and D-02 (log). So D-03 is effectively `log_dB + sharpness`, not `linear + sharpness`. That may be fine but the decision doc MUST state which D-02 vs D-03 is really comparing.

**Why it happens:** Phase 14 adopted `log_cost=true` as its default because Phase 8 showed log-scale converges much deeper.

**How to avoid:** The analyzer explicitly logs which `log_cost` each variant used. If the user wants D-03 to be sharpness on the *linear* scale, that's a CONTEXT amendment. Default stance: honor the Phase 14 default; document it.

### Pitfall 7: FFTW wisdom imported but ignored by `ESTIMATE`

**What goes wrong:** Phase 15 patched `src/simulation/*.jl` to use `flags=FFTW.ESTIMATE`. That flag explicitly tells FFTW *not* to consult wisdom or measure — so importing wisdom before Phase 15-patched `plan_fft!` calls is a no-op. CONTEXT D-09 calls it "belt-and-suspenders", which is accurate — but the plan shouldn't expect improved performance from the wisdom import.

**Why it happens:** The determinism trade (Phase 15) deliberately gave up MEASURE-optimized plans in exchange for reproducibility.

**How to avoid:** Keep the wisdom import (it's cheap and protects against future FFTW library churn), but don't attribute wall-time differences to it.

### Pitfall 8: `MersenneTwister(seed)` passed to `optimize_spectral_phase_sharp` is consumed internally

**What goes wrong:** `optimize_spectral_phase_sharp` passes `rng` into `sharpness_estimator`, which draws Rademacher vectors. After `max_iter=100` L-BFGS steps × `n_samples=8` draws per step × Nt=8192 per draw, the RNG has advanced by millions of states. If the driver also uses the same RNG object for the perturbation robustness probe, the robustness draws will depend on the exact convergence path. Fine for determinism; but it means the robustness probe seeds for different variants are different (D-01 doesn't consume the RNG, D-03 consumes it heavily).

**Why it happens:** `MersenneTwister` is stateful.

**How to avoid:** The driver uses two DIFFERENT RNGs — one for φ₀ generation (`MersenneTwister(SEED)`) and a separate one for the robustness probe per run (`MersenneTwister(SEED + 1000 + variant_index)`). Then all 4 variants have identical robustness draws. Log both seeds.

## Code Examples

### Example 1: D-04 driver entry (wrapper composition)

```julia
# Source: scripts/cost_audit_driver.jl (new), pattern from
# scripts/raman_optimization.jl:425 and scripts/phase13_hessian_eigspec.jl

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "sharpness_optimization.jl"))
include(joinpath(@__DIR__, "phase13_hvp.jl"))
include(joinpath(@__DIR__, "cost_audit_noise_aware.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

const CA_FFTW_WISDOM_PATH = joinpath(@__DIR__, "..", "results", "raman",
                                     "phase14", "fftw_wisdom.txt")
isfile(CA_FFTW_WISDOM_PATH) && FFTW.import_wisdom(CA_FFTW_WISDOM_PATH)

const CA_CONFIGS = [
    (tag="A", fiber_preset=:SMF28, L_fiber=0.5, P_cont=0.05, seed=42,
     time_window=5.0),
    (tag="B", fiber_preset=:SMF28, L_fiber=5.0, P_cont=0.2,  seed=43,
     time_window=45.0),  # set explicitly to suppress auto-sizing
    (tag="C", fiber_preset=:HNLF,  L_fiber=1.0, P_cont=0.5,  seed=44,
     time_window=15.0),
]
const CA_VARIANTS = [:linear, :log_dB, :sharp, :curvature]
```

### Example 2: Gauge-projected Hessian top-32 via Arpack

```julia
# Source: new, pattern from scripts/phase13_hessian_eigspec.jl

function top32_eigenspectrum(phi_opt, uω0, fiber, sim, band_mask)
    # Build raw gradient oracle (log_cost=false, λ_gdd=0, λ_boundary=0
    # per CONTEXT metric-4 "pure landscape Hessian" convention).
    setup_kwargs = (…)  # reconstruct per config
    oracle, meta = build_oracle(setup_kwargs)
    # Gauge projector — EXACTLY the same object the sharpness estimator uses.
    P = build_gauge_projector(meta.omega, meta.input_band_mask)

    proj_oracle = phi -> P(oracle(phi))   # both input and output live in the
                                          # non-gauge subspace; the input projection
                                          # is implicit because we ask Arpack for
                                          # the Hessian *restricted* to that
                                          # subspace, so starting vectors are also
                                          # projected.
    H_op = HVPOperator(length(vec(phi_opt)), proj_oracle, vec(phi_opt), 1e-4)
    λ_top, V_top, n_iter = Arpack.eigs(H_op; nev=32, which=:LR,
                                        maxiter=500, tol=1e-6)
    return (lambda_top=real.(λ_top),
            condition_proxy=real(maximum(λ_top)) / max(real(λ_top[end]), eps()),
            lambda_max=real(maximum(λ_top)),
            n_iter=n_iter)
end
```

### Example 3: Robustness probe (mean & max ΔJ_dB per σ)

```julia
# Source: new, pattern from scripts/raman_optimization.jl:chirp_sensitivity

function robustness_probe(phi_opt, uω0, fiber, sim, band_mask;
        sigmas=(0.01, 0.05, 0.1, 0.2), n_trials=10, rng=MersenneTwister(999))
    J_opt, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask)
    J_opt_dB = 10*log10(max(J_opt, 1e-15))
    results = Dict{Symbol, Any}()
    for σ in sigmas
        dJ_dB = zeros(n_trials)
        for t in 1:n_trials
            φ_p = phi_opt .+ σ .* randn(rng, size(phi_opt)...)
            J_p, _ = cost_and_gradient(φ_p, uω0, fiber, sim, band_mask)
            dJ_dB[t] = 10*log10(max(J_p, 1e-15)) - J_opt_dB
        end
        results[Symbol("sigma_$σ_mean_dB")] = mean(dJ_dB)
        results[Symbol("sigma_$σ_max_dB")]  = maximum(dJ_dB)
    end
    return results
end
```

## State of the Art

### ML loss-landscape literature — claims we will cite in the decision doc

| # | Paper | Claim (compressed) | Translation to this physics phase |
|---|-------|--------------------|-----------------------------------|
| 1 | [Hochreiter & Schmidhuber 1997, Flat Minima](https://direct.mit.edu/neco/article/9/1/1/6027/Flat-Minima) | An MDL/Bayesian argument links flat minima ("large connected regions where the error remains approximately constant") to lower expected generalization error. Sharp minima require high-precision weights (= more bits). | The analogue: a "flat" `φ_opt` tolerates small perturbations (SLM pixel drift, fiber-length variance, temperature fluctuations) with small ΔJ. That is **exactly** our D-14 metric 5 (robustness under perturbation). Flatness = experimental realizability of the optimum. |
| 2 | [Keskar et al. 2017, Large-batch training → sharp minima](https://arxiv.org/abs/1609.04836) | Large-batch SGD converges to sharper minima with ≈5% generalization gap; sharpness is measured by the magnitude of Hessian eigenvalues (or a cheaper sensitivity proxy). | Empirically grounds the flatness→generalization link. In our setting this means we should *not* just look at final J_dB — a variant that reaches deeper J but in a sharper basin may be experimentally worse. Our Hessian top-32 (D-14 #4) is the direct port of the "magnitude of Hessian eigenvalues" proxy. |
| 3 | [Li et al. 2018, Visualizing the Loss Landscape](https://arxiv.org/abs/1712.09913) | Introduces **filter-normalized** random-direction 2D slices; shows that visual sharpness of the slice correlates with generalization error. Skip connections convexify the landscape. | Gives the *methodology* for the 2D slice (deferred — CONTEXT item). Also validates that a Hessian-eigenvalue-based sharpness metric (what we actually compute) is what underlies the 2D visualization — the top eigenvectors *are* the directions the 2D slice captures. |
| 4 | [Foret et al. 2020, SAM](https://arxiv.org/abs/2010.01412) | Proves a generalization bound in terms of loss *in an ℓ₂ neighborhood* around the minimum; introduces SAM: solve `min_φ max_{‖ε‖≤ρ} J(φ+ε)`. Gradient descent in this min-max is tractable. | Direct parent of the sharpness-aware variant D-03, but D-03 uses Hutchinson-curvature-regularization (J + λ·S), NOT SAM's min-max. The decision doc should name this distinction: D-03 is "SAM-inspired, trace-of-Hessian penalty", not SAM itself. SAM's ρ-ball robustness maps to our σ-ball (D-14 #5). |
| 5 | [Kwon et al. 2021, ASAM](https://arxiv.org/abs/2102.11600) | SAM's fixed-ρ ball is sensitive to parameter re-scaling (if you rescale weights, SAM gives different answers). ASAM introduces scale-invariant "adaptive sharpness". | Relevant to us only as caution: our φ has a natural scale (radians, bounded in practice by ±π), so scale invariance is less of an issue. Mention in the decision doc as "not an issue for this problem." |
| 6 | [Zhuang et al. 2022, GSAM](https://arxiv.org/abs/2203.08065) | Low SAM loss ≠ flat minimum. SAM's perturbed loss can be low even at sharp minima if the gradient ascent step lands on the plateau. Introduces a "surrogate gap" = (SAM loss) − (clean loss), which equals the dominant Hessian eigenvalue in the small-radius limit. | Critical caveat: we cannot conclude "D-03 found a flatter optimum" just from D-03 finding a low `J + λ·S`. The Hessian eigenspectrum (D-14 #4) is the arbiter. The decision doc must cite this. |
| 7 | [Wilson et al. 2017, Marginal Value of Adaptive Methods](https://arxiv.org/abs/1705.08292) | Adaptive optimizers (Adam, AdaGrad) train faster but often generalize worse than SGD on held-out data. | Methodological anchor: we use L-BFGS (2nd-order-ish, non-adaptive) uniformly across all variants, so this concern doesn't apply to Phase 16 — but it's the canonical "benchmark optimizers fairly" paper. |
| 8 | [Schmidt et al. 2021, Descending through a Crowded Valley](https://arxiv.org/abs/2007.01547) | Among 15 optimizers × 8 tasks × 50k runs: there is no universal winner; evaluating multiple optimizers at defaults is approximately as good as tuning a single one. Optimizer choice is "crucial but empirical." | This *is* our methodology template. We do a 4×3 analogue (cost functions, not optimizers), at fixed hyperparameters per CONTEXT, and report the whole matrix. The decision doc's framing of "there is no universal winner, but for our specific regime the recommended default is X" is the direct lift from Schmidt et al. |

**Assumption check:** All 8 papers verified via web search to exist and have the attributed claims. Publication details are from arXiv abstracts (HIGH) or official proceedings pages (HIGH).

### Flatness/sharpness metrics feasibility (Question 2 in Additional Context)

| Metric | Cost at Nt=8192 | Applicable? | Our use |
|--------|-----------------|-------------|---------|
| Top-k Hessian eigenvalue (Arpack/Lanczos on HVP) | 2·k Krylov × (2 fwd + 2 adj) = ~O(100–500) forward solves per run | **Yes** — already in CONTEXT D-14 #4 | Primary sharpness metric; gauge-projected. |
| Hutchinson trace estimator | `n_samples × (2 fwd+adj)` per evaluation = ~32 solves | **Yes** — already used by D-03 during optimization | Cheaper than eigenspectrum but only gives `tr(H)`, not the top eigenvalue. D-15 secondary: log `S(φ_final)` for the sharpness variant only. |
| Fisher information | Requires probabilistic model; our `J = E_band/E_total` is deterministic | **No** | Skip. |
| Empirical robustness under Gaussian perturbation | `|σ_grid| × n_trials × (1 fwd)` = 40 solves per run | **Yes** — CONTEXT D-14 #5 | Primary robustness metric; the "experimental" analogue of SAM's ρ-ball. |
| Monotonic-basin size (largest ε for which J_perturbed ≤ J_opt + 3 dB) | Bisection over σ: ~10 solves per run | **Yes** — cheap bonus | Optional derived quantity from the σ-grid data; don't add a separate probe. |
| 1D / 2D random-direction slice (Li et al. 2018) | 2D grid 30×30 × 2 random directions = 1800 solves per run | **No at Nt=8192** — 12× that is 21 600 solves across batch | Deferred per CONTEXT "Deferred Ideas". |

**Recommendation:** Stick to CONTEXT's metric set; the 2D slice is correctly deferred.

### Log-scale cost in nonlinear optimization (Question 3)

**Is log-scale cost a known trick for L-BFGS?** Yes, at the level of "whenever the cost spans many orders of magnitude and the optimum has J→0, logarithmic transformations keep the gradient magnitude roughly constant across the optimization trajectory." [CITED: L-BFGS is called 'the algorithm of choice' for log-linear (MaxEnt) models — https://en.wikipedia.org/wiki/Limited-memory_BFGS]. In optics, log-scale (dB) cost is the norm for *reporting* suppression but **less common as the optimization target** — spectral pulse shaping papers typically optimize linear metrics like spectral intensity enhancement or pulse-energy fraction and report dB post hoc. [ASSUMED] — I did not find an explicit "optimize in dB" citation in the first-pass search.

**Is the existing Phase 8 math correct?**

```julia
# scripts/raman_optimization.jl:101-109
if log_cost
    J_clamped = max(J, 1e-15)
    J_phys = 10.0 * log10(J_clamped)
    log_scale = 10.0 / (J_clamped * log(10.0))
    ∂J_∂φ_scaled = ∂J_∂φ .* log_scale
else
    J_phys = J
    ∂J_∂φ_scaled = ∂J_∂φ
end
```

Mathematical check: If f(φ) = 10·log10(J(φ)), then ∂f/∂φ = (10 / (J · ln10)) · ∂J/∂φ. [VERIFIED by direct calculus]. The code implements exactly this, using `max(J, 1e-15)` to avoid `log10(0)` / division-by-zero. **The only edge case is J ≈ 0** (perfect suppression), which the clamp handles by freezing J_phys at `10·log10(1e-15) = -150 dB` and `log_scale` at `10/(1e-15 · ln10) ≈ 4.34e15` — a large but finite gradient scaling. In practice, `J` never reaches 1e-15 on this problem (Phase 12 observed J_final ≈ -74 dB = 4e-8 at best, still 7 orders above the clamp). The math is correct; the clamp is appropriate; no fix needed.

## Runtime Risks (Question 7)

Ten concrete risks for the 12-run batch, with mitigations that belong in the plan:

| # | Risk | Where it can bite | Mitigation |
|---|------|-------------------|------------|
| R1 | Auto-sizing silently grows Nt for config B, breaking fair-comparison | `setup_raman_problem` at config B (L=5m, P=0.2W) | Pass explicit `time_window=45.0 ps` per config; assert `sim["Nt"]==8192` post-setup. |
| R2 | D-04 γ_curv auto-calibration lands in a pathological range | First iteration of D-04 driver per config | Log `P(φ₀)` and `J(φ₀)`; fall back to `γ_curv=1e-4` if ratio is outside `[1e-2, 10]`. |
| R3 | Optim.jl LBFGS returns NaN gradient for sharpness variant in hard-regime config B | `cost_and_gradient_sharp` inside L-BFGS on SMF-28 L=5m (multi-modal landscape per Phase 11) | `@assert all(isfinite, grad)` already inside `cost_and_gradient_sharp:347`. If it fires, the plan catches via try/catch and writes the snapshot with `converged=false`, `J_final=NaN`; analyzer colors the cell as "DNF". |
| R4 | FFTW wisdom file locked during parallel solves | Not applicable — Phase 15 pinned FFTW to 1 thread; runs are serial per (variant, config). | Keep serial. If a future phase wants parallel multi-start, `fftw_make_planner_thread_safe()` must be called or wisdom disabled. |
| R5 | JLD2 partial write on crash (corrupts per-run snapshot) | `jldsave(…)` is not atomic by default | Write to `path.tmp`, then `mv path.tmp path`. JLD2 supports this pattern; wrap in a helper. |
| R6 | Arpack `:LR` stalls at `maxiter=500` for tight `tol=1e-7` on hard-regime optimum | Config B eigendecomposition | Start with `tol=1e-6`, `maxiter=500`; on stall, relax to `tol=1e-5`, `maxiter=1000`. Log which tier fired. |
| R7 | 90-min batch wall-time blown by cumulative Hessian eigenspectra | 12 eigendecompositions × 5–20 min each | Time-box: abort eigenspectrum task at 90 min cumulative; if reached, drop remaining configs to `nev=16`. |
| R8 | Burst VM `/tmp/burst-heavy-lock` left stuck if tmux session dies | After unexpected crash | tmux command uses `… ; rm -f /tmp/burst-heavy-lock` as the last statement, so lock clears even if Julia throws. Additionally, the session teardown task explicitly `rm -f`s it. |
| R9 | Stopping criterion `f_abstol=1e-10` triggers much earlier for D-01 linear than others, producing an unfair "winner" on wall time | D-01 linear variant on config A | Analyzer normalizes: all convergence metrics reported after converting to dB. The "winner on wall time" is reported alongside "winner on final J_dB" — the plan makes this a winner-per-metric heatmap (D-18 fig 4), not a single winner. |
| R10 | Phase 14 regression test (`test/test_phase14_regression.jl`) fails because Session H touches a shared file | git diff fails Rule P1 audit | Pre-commit task runs `git diff --stat main…HEAD` and greps for any path outside the cost_audit namespace; refuse to commit if found. Run the regression test on branch before closing the phase. |

## Environment Availability

Phase 16 runs exclusively on the burst VM (`fiber-raman-burst`) per CLAUDE.md Rule 1. This audit is about what that machine needs.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | All code | ✓ (on burst VM) | 1.12.x per Manifest | — |
| Python3 + Matplotlib | PyPlot figures | ✓ (via PyCall/Conda) | auto-installed by PyCall.jl | — |
| FFTW system library | FFTW.jl | ✓ (provided by FFTW_jll) | bundled | — |
| Arpack.jl | Hessian eigenspectrum | ✓ (in Project.toml) | resolver-pinned in Manifest | — |
| Burst VM (GCP c3-highcpu-22) | All heavy runs | ✓ (provisioned, stopped by default) | 22 vCPU, 44 GB RAM | — |
| `/tmp/burst-heavy-lock` convention | CLAUDE.md Rule P5 serialization | ✓ (convention already in use by Session A/C/F per Phase 15 era) | — | — |
| `burst-start` / `burst-ssh` / `burst-stop` helpers | Driver scripts | ✓ on `claude-code-host` only | — | Run the driver on burst VM directly (the helpers are for claude-code-host → burst orchestration). |
| FFTW wisdom file `results/raman/phase14/fftw_wisdom.txt` | Belt-and-suspenders D-09 | ✓ (4295 bytes, verified) | fftw-3.3.10 | Import is wrapped in try/catch; warn and proceed if absent. |
| `scripts/phase13_hvp.jl`, `scripts/phase13_hessian_eigspec.jl` | HVP & eigendecomposition reuse | ✓ (both verified present at 315 + 624 lines) | — | — |
| `scripts/sharpness_optimization.jl` | D-03 | ✓ (496 lines) | — | — |
| Phase 14 regression snapshot (`results/raman/phase14/vanilla_snapshot.jld2`) | Pre-phase-close smoke test | ✓ (verified present) | — | Smoke test skips with warning if missing. |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Test.jl (stdlib) — project standard; see `test/test_phase14_regression.jl` for idiomatic shape. |
| Config file | None — tests live in `test/` and invoke `@testset` directly. |
| Quick run command | `julia --project=. test/test_cost_audit_unit.jl` (new file, see Wave 0 gaps) |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test("MultiModeNoise")'` — currently minimal but auto-includes `test/runtests.jl`. |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| D-04 gradient | Curvature penalty gradient matches finite differences at O(ε²) | unit (Taylor-remainder) | `julia --project=. test/test_cost_audit_unit.jl::d04_gradient` | ❌ Wave 0 |
| D-04 scale consistency | `γ_curv=0` → D-04 reduces byte-identically to linear (D-01) | unit | `julia --project=. test/test_cost_audit_unit.jl::d04_zero_penalty` | ❌ Wave 0 |
| D-05/D-06 determinism | Given same seed, linear variant produces bit-identical φ_opt (Phase 15 guarantee) | unit | `julia --project=. test/test_cost_audit_unit.jl::determinism` | ❌ Wave 0 |
| D-07/D-08 protocol | All 4 variants produce a valid `Optim.OptimizationResult` on config A (smoke) | integration | `julia -t 4 --project=. test/test_cost_audit_integration_A.jl` | ❌ Wave 0 |
| D-11/D-12/D-13 protocol | Driver runs the full 12-run batch end-to-end; every CSV/JLD2/PNG exists | system | (end-to-end) — the driver run itself is the system test; gated on `results/cost_audit/summary_all.csv` presence | ❌ (driver is Wave 0 itself) |
| Phase 14 regression | Vanilla path unchanged (`test/test_phase14_regression.jl`) | regression | `julia --project=. test/test_phase14_regression.jl` | ✅ |
| Phase 15 regression | `test/test_determinism.jl` passes | regression | `julia --project=. test/test_determinism.jl` | ✅ |
| D-14 #4 analyzer | CSV schema matches CONTEXT D-16 column list exactly | contract | `julia --project=. test/test_cost_audit_analyzer.jl::csv_schema` | ❌ Wave 0 |
| D-18 analyzer figures | 4 PNGs produced at 300 DPI; file sizes > 20 KB each | contract | `julia --project=. test/test_cost_audit_analyzer.jl::figures_exist` | ❌ Wave 0 |
| Nyquist completeness | Every (variant, config) has all 8 metrics populated in summary_all.csv (no NaN except for DNF runs explicitly flagged) | nyquist | `julia --project=. test/test_cost_audit_analyzer.jl::nyquist_complete` | ❌ Wave 0 |
| D-20 discipline | Batch runs entirely on burst VM (host marker in JLD2) | contract | (manual visual check in post-run log) | N/A |
| Performance | Total wall time ≤ 120 min for all 12 runs + eigenspectra + analyzer | performance | (manual log inspection) | N/A |

### Sampling Rate

- **Per task commit:** `julia --project=. test/test_cost_audit_unit.jl` (≤ 30 s) — runs the 4 unit tests (D-04 gradient, D-04 zero-penalty reduction, determinism, import-order smoke).
- **Per wave merge:** `julia --project=. test/test_cost_audit_unit.jl && julia --project=. test/test_phase14_regression.jl && julia --project=. test/test_determinism.jl` — adds the regression gates.
- **Phase gate:** Full burst-VM batch run completes; `test/test_cost_audit_analyzer.jl` passes against the generated CSVs/PNGs; Phase 14 regression green.

### Wave 0 Gaps

- [ ] `test/test_cost_audit_unit.jl` — Taylor-remainder gradient test for D-04; zero-penalty reduction test; determinism smoke (~ 2 min at Nt=1024 to keep it fast). [covers REQ-D04, REQ-D05, REQ-D06]
- [ ] `test/test_cost_audit_integration_A.jl` — Smoke test: each of the 4 variants runs to completion on config A scaled down to `max_iter=10`, produces a non-NaN J_final. Target wall time: ≤ 5 min. [covers REQ-D07, REQ-D08]
- [ ] `test/test_cost_audit_analyzer.jl` — CSV schema assertion, figures-exist assertion, Nyquist completeness assertion. Runs post-batch on the real outputs. [covers REQ-D14, REQ-D16, REQ-D18]
- [ ] `scripts/cost_audit_noise_aware.jl` — contains the `cost_and_gradient_curvature` function (new file) — also its own unit tests live in `test_cost_audit_unit.jl`.
- [ ] `scripts/cost_audit_driver.jl` — the 12-run orchestrator (new file).
- [ ] `scripts/cost_audit_analyze.jl` — the CSV/figure producer (new file).

*(No framework install needed — Test.jl is stdlib; existing tests follow the project's unadorned `@testset` pattern.)*

## Security Domain

> `security_enforcement` is not explicitly set in `.planning/config.json` (which is an empty file); default is enabled. However, this is a research codebase with no network exposure, no user input, no authentication, and no storage of user data. The applicable ASVS surface is minimal.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No authenticated surface. |
| V3 Session Management | no | No sessions. |
| V4 Access Control | no | No users. |
| V5 Input Validation | partial | Julia `@assert` preconditions on every public function in `common.jl` / `raman_optimization.jl`; Phase 16 wrappers follow the same pattern (validate `σ > 0`, `n_trials ≥ 1`, `γ_curv ≥ 0`, `band_mask` non-empty). Not a security concern, but contract integrity. |
| V6 Cryptography | no | No crypto. |
| V7 Error Handling / Logging | partial | `@info`/`@warn`/`@debug` already used throughout; Phase 16 follows. No sensitive data to redact. |
| V14 Configuration | partial | `ensure_deterministic_environment()` is the Phase-15 canonical config pin; Phase 16 calls it. |

### Known Threat Patterns for Julia research code

| Pattern | STRIDE | Standard Mitigation | Relevant here? |
|---------|--------|---------------------|----------------|
| Malicious package via `Pkg.add` | Tampering | Pin `Manifest.toml`; use `Pkg.instantiate()` not `Pkg.resolve()`. | Yes — Rule D-22 forbids modifying `Project.toml`. Manifest is committed. |
| Path traversal in user-supplied filenames | Tampering | We accept no user paths; all paths are derived from compile-time constants. | No. |
| Resource exhaustion on burst VM ($$$ leak) | DoS (of the budget) | `burst-stop` at end of every batch; lock file guarded. | **Yes — R8 above.** |
| Non-reproducible numerical results (silent bug) | Tampering (of science) | Phase 15 determinism; Phase 14 regression test; commit all RNG seeds. | Yes — entire plan structure. |

No other ASVS categories apply to this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `[ASSUMED]` Log-scale cost as an L-BFGS *optimization target* (not just reporting) is uncommon in femtosecond-pulse-shaping literature; Agrawal and Trebino-style reviews optimize linear metrics. I did not find a direct physics-optics citation for "optimize in dB." | State of the Art / log-scale discussion | Decision doc's framing of "log-scale cost is a known trick" may overclaim. Mitigation: cite only the MaxEnt/log-linear-model L-BFGS tradition + the project's own Phase 8 empirical record (20–28 dB deeper). |
| A2 | `[ASSUMED]` KrylovKit.jl would be equivalent or slightly faster than Arpack for the top-32 HVP eigenspectrum at Nt=8192. | Alternatives Considered | Low — we're not actually switching; this is a discussion-only comparison. |
| A3 | `[ASSUMED]` `cost_and_gradient_sharp` with `log_cost=true` (Phase 14 default) is the intended D-03. | Pitfall 6 | Medium — if the user intended D-03 on the linear scale, the D-02-vs-D-03 comparison changes meaning. Mitigation: the analyzer logs the `log_cost` flag used per variant; the decision doc names it explicitly. |
| A4 | `[ASSUMED]` Per-(variant, config) eigendecomposition will cost 5–20 min each at Nt=8192 / nev=32, extrapolating from Phase 13 Plan 02's observed runtime at nev=20. | Pitfall 5 | Medium — if it's actually 30+ min each, the 90-min batch budget overflows. Mitigation: Risk R7 already specifies an adaptive drop to nev=16. |
| A5 | `[ASSUMED]` D-04 `γ_curv=1e-4` fallback value will be in a useful range for all three configs. | Pitfall 3 | Medium — it could be order-of-magnitude wrong for the HNLF config C. Mitigation: plan logs the auto-calibrated value and D-04 outcome explicitly; if the curvature term dominates J in config C, the decision doc names D-04 as "configuration-dependent, not recommended as default." |
| A6 | `[ASSUMED]` The `ncv` default (2·nev+1) is suitable for Arpack `:LR` at Nt=8192. Phase 13 Plan 02 used `nev=20` successfully with default `ncv`. | Risks R6, R7 | Low — can always increase `ncv` manually as a fallback. |
| A7 | `[ASSUMED]` The curvature penalty `γ_curv · ⟨|∂²φ/∂ω²|²⟩_band` is a defensible classical proxy for quantum-noise amplification in squeezed-vacuum multimode fiber. This is user-specified in CONTEXT D-04 and I did not re-derive it. (See "Scaffold defensibility" note below.) | D-04 design | Medium — if the Rivera lab's physics group later objects, D-04's interpretation changes, but the *numerical* experiment (does adding a curvature penalty improve the optimum's robustness?) remains valid as a regularization study. |

**Scaffold defensibility note (Question 6):** The CONTEXT D-04 choice of `⟨|∂²φ/∂ω²|²⟩` over the Raman band is equivalent to penalizing group-delay dispersion (GDD) localized to the Raman-shifted frequency bins. Physically, large phase curvature produces large instantaneous-frequency excursions through the fiber, which in the quantum picture correlates with multimode mixing and photon-number fluctuations. The project's actual quantum-noise context (Rivera Lab, squeezed-vacuum propagation) would ideally penalize the squeezing-parameter variance at output — a *much* more involved quantity requiring a second-moment propagation alongside the mean field. The classical proxy is defensible as a *regularizer that prefers physically smooth solutions*, not as a quantitative noise predictor. A materially better tractable proxy could be penalizing `⟨|∂²|E(t)|²/∂t²|²⟩` — the second time-derivative of output *intensity* (a classical quantity that does track noise amplification in supercontinuum generation). Mentioning this as a future alternative in the decision doc is appropriate, but D-04 as specified is acceptable for this phase. No physics re-derivation here per CONTEXT's deferred-ideas list.

## Open Questions

1. **Does D-03 run with `log_cost=true` (Phase 14 default) or `log_cost=false` in the audit?**
   - What we know: `optimize_spectral_phase_sharp` defaults to `log_cost=true`; CONTEXT D-03 says "Phase 14 default", so the answer is `true`.
   - What's unclear: whether the user wanted D-03 to be directly comparable to D-01 (linear) — which requires `log_cost=false` — or to D-02 (log_dB). The latter is natural.
   - Recommendation: run `log_cost=true` for D-03 (matches Phase 14 default), log the flag in every JLD2 and CSV, and let the decision doc name the comparison explicitly. If the user wants both, that's a CONTEXT amendment (easy to do as a second pass since the driver is parameterized).

2. **If the Phase 14 regression test fails on `sessions/H-cost`, what is the response?**
   - What we know: Session H writes zero shared files; the test should continue passing.
   - What's unclear: drift from the `sessions/H-cost` worktree being out of sync with main, or from unrelated background merges while the session runs.
   - Recommendation: run the regression test at the *start* of the plan (before any Session H changes) to establish baseline green; re-run at end as the gate. If it fails at start, pull main; if at end with zero changes outside the namespace, escalate to user.

3. **Do we log the FFTW wisdom cache hit ratio to attribute any D-09 wall-time benefit?**
   - What we know: Phase 15's `ESTIMATE` flag means the wisdom is effectively unused.
   - What's unclear: worth logging a marker to silence future "is wisdom doing anything?" questions.
   - Recommendation: skip; it's confirmed no-op per Phase 15 patch. Don't expand the scope.

4. **Does the analyzer need to recompute metrics 1–5 from the raw `phi_opt` / `ftrace` at analysis time, or trust the per-run JLD2s?**
   - What we know: Per-run JLD2s are written by the driver immediately after each run.
   - Recommendation: trust the JLD2s for summary_all.csv; recompute the robustness probe only if the user changes the σ-grid later. This means the driver is the authoritative computation of all 5 metrics, the analyzer is a pure aggregator.

## Sources

### Primary (HIGH confidence — verified in codebase, or official proceedings)

- `/home/ignaciojlizama/raman-wt-H/.planning/phases/16-cost-function-head-to-head-audit-compare-linear-log-scale-db/16-CONTEXT.md` — the locked decisions (D-01…D-22).
- `/home/ignaciojlizama/raman-wt-H/CLAUDE.md` — project instructions incl. parallel-session, burst-VM, and compute-discipline rules.
- `/home/ignaciojlizama/raman-wt-H/.planning/STATE.md` — decision history incl. Phase 8 log-cost fix, Phase 13 gauge/HVP, Phase 14 sharpness, Phase 15 determinism, Phase 16 roadmap entry.
- `/home/ignaciojlizama/raman-wt-H/scripts/raman_optimization.jl` lines 52–160 (`cost_and_gradient` + `log_cost` math), 166–220 (`optimize_spectral_phase` with `log_cost` and `f_abstol` dispatch).
- `/home/ignaciojlizama/raman-wt-H/scripts/sharpness_optimization.jl` lines 142–193 (`build_gauge_projector`), 231–274 (`sharpness_estimator`), 304–350 (`cost_and_gradient_sharp`), 370–381 (`make_sharp_problem`), 425–496 (`optimize_spectral_phase_sharp` with defaults).
- `/home/ignaciojlizama/raman-wt-H/scripts/common.jl` lines 260–276 (`spectral_band_cost`), 318–377 (`setup_raman_problem` incl. auto-sizing), 191–215 (`recommended_time_window`).
- `/home/ignaciojlizama/raman-wt-H/scripts/phase13_hvp.jl` lines 84–119 (`build_oracle`), 148–165 (`fd_hvp`), 288–309 (`ensure_deterministic_fftw`).
- `/home/ignaciojlizama/raman-wt-H/scripts/phase13_hessian_eigspec.jl` lines 104–124 (`HVPOperator`), 169–318 (`run_eigendecomposition`).
- `/home/ignaciojlizama/raman-wt-H/scripts/phase13_primitives.jl` lines 106–127 (`input_band_mask`), 142–198 (`gauge_fix`), 228–279 (`polynomial_project`).
- `/home/ignaciojlizama/raman-wt-H/scripts/determinism.jl` — `ensure_deterministic_environment()`.
- `/home/ignaciojlizama/raman-wt-H/test/test_phase14_regression.jl` — regression gate pattern and tolerances.
- `/home/ignaciojlizama/raman-wt-H/results/raman/phase14/fftw_wisdom.txt` — wisdom file (4 295 bytes, verified present).
- [Foret et al. 2020 — SAM, arXiv:2010.01412](https://arxiv.org/abs/2010.01412)
- [Kwon et al. 2021 — ASAM, ICML 2021](https://proceedings.mlr.press/v139/kwon21b.html)
- [Zhuang et al. 2022 — GSAM, ICLR 2022](https://arxiv.org/abs/2203.08065)
- [Li et al. 2018 — Visualizing the Loss Landscape, NeurIPS 2018](https://arxiv.org/abs/1712.09913)
- [Hochreiter & Schmidhuber 1997 — Flat Minima, Neural Computation](https://direct.mit.edu/neco/article/9/1/1/6027/Flat-Minima)
- [Keskar et al. 2017 — Large-Batch Training, arXiv:1609.04836](https://arxiv.org/abs/1609.04836)
- [Wilson et al. 2017 — Marginal Value of Adaptive Gradient Methods, NeurIPS 2017](https://arxiv.org/abs/1705.08292)
- [Schmidt et al. 2021 — Descending through a Crowded Valley, ICML 2021](https://proceedings.mlr.press/v139/schmidt21a.html)

### Secondary (MEDIUM confidence — official API docs, cross-verified)

- [Optim.jl — Configurable Options / (L-)BFGS](https://julianlsolvers.github.io/Optim.jl/stable/user/config/) — confirms `f_abstol`, `store_trace` semantics; confirms `Optim.only_fg!()` API.
- [Arpack.jl — Standard Eigen Decomposition](https://julialinearalgebra.github.io/Arpack.jl/stable/eigs/) — matrix-free contract (`mul!`, `size`, `eltype`, `issymmetric`).
- [FFTW thread-safety docs](https://www.fftw.org/fftw3_doc/Thread-safety.html) — confirms the wisdom system is not thread-safe by default; `fftw_execute` is the only routine that is.
- [L-BFGS Wikipedia](https://en.wikipedia.org/wiki/Limited-memory_BFGS) — confirms L-BFGS as the standard choice for large-scale smooth nonlinear optimization; cites MaxEnt / log-linear model usage.

### Tertiary (LOW confidence — WebSearch synthesis only; not cited in the decision doc without further verification)

- General claim that femtosecond pulse-shaping uses evolutionary / genetic / particle-swarm algorithms more than gradient methods ([Nature Sci Reports 2024 article](https://www.nature.com/articles/s41598-024-84567-x)). Context only; not affecting Phase 16 decisions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every function is verified line-by-line in the cloned worktree.
- Architecture patterns: HIGH — patterns are lifted directly from Phase 13/14/15 already-merged code.
- Pitfalls: HIGH — 8 pitfalls each backed by specific line numbers in existing scripts or by STATE.md historical entries.
- Risks: HIGH (R1–R5, R8–R10), MEDIUM (R6–R7) — eigenspectrum wall time extrapolated from Phase 13 Plan 02 but not directly measured at nev=32.
- ML literature: HIGH — 8 papers verified via web search against arXiv/proceedings.
- D-04 scaffold defensibility: MEDIUM — argument is physically plausible but not rigorously derived; CONTEXT explicitly frames it as scaffold-quality.

**Research date:** 2026-04-17
**Valid until:** 2026-05-17 (30 days — Julia/Optim/Arpack APIs are stable; the FFTW ESTIMATE patch is structural; ML literature doesn't move that fast).

---

*Research for Phase 16 complete. Planner can proceed to produce `16-01-PLAN.md` with task breakdown.*
