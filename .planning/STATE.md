---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Verification & Discovery
status: Executing Phase 16
last_updated: "2026-04-17T03:52:20.728Z"
last_activity: 2026-04-17
progress:
  total_phases: 15
  completed_phases: 2
  total_plans: 11
  completed_plans: 17
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Physically correct simulation and optimization of Raman suppression, with every output plot clearly communicating the underlying physics.
**Current focus:** Phase 16 — Cost Function Head-to-Head Audit

## Current Position

Phase: 16 (Cost Function Head-to-Head Audit) — EXECUTING
Plan: 1 of 2
Phase 8 (Sweep Point Reporting) — COMPLETE
Phase 9 (Physics of Raman Suppression) — COMPLETE (2 plans, 15 figures, all hypotheses tested)
Next: Multimode (M>1) simulations for quantum noise analysis

## Phase Status

| Phase | Status | Plans | Notes |
|-------|--------|-------|-------|
| 4. Correctness Verification | Complete | 2/2 | 2026-03-25 |
| 5. Result Serialization | Complete | 1/1 | 2026-03-25 |
| 6. Cross-Run Comparison | Partial | 1/2 | Plan 02 (run_comparison.jl execution) not run |
| 6.1 Physics Insight | Partial | 1/2 | Plan 02 (Figs 5-8) not run |
| 7. Parameter Sweeps | Code complete | 2/3 | Plan 03 (execution + verification) pending re-run |
| 7.1 Grid Resolution Fix | Complete | 1/1 | Nt floor, max_iter, L=10m dropped |
| 8. Sweep Point Reporting | Complete | 1/1 | generate_sweep_reports.jl working; log-scale cost 20-28 dB improvement |

## Execution History

| Plan | Edits | Tasks | Files |
|------|-------|-------|-------|
| Phase 04 P01 | 3 | 1 | 2 |
| Phase 04 P02 | 35 | 2 | 2 |
| Phase 05 P01 | 12 | 2 | 3 |
| Phase 06 P01 | 8 | 2 | 1 |
| Phase 06 P02 | 15 | 1 | 1 |
| Phase 06.1 P01 | 4 | 2 | 5 |
| Phase 06.1 P02 | 2 | 1 (checkpoint) | 5 |
| Phase 07 P02 | 217 | 2 | 2 |
| Phase 07.1 P01 | — | 2 | 1 |
| Phase 08 P01 | — | — | 2 |

## Quick Tasks

| # | Description | Date | Commit |
|---|-------------|------|--------|
| 260331-gh0 | Fix SPM formula in recommended_time_window, max_iter 30→60, quality reporting | 2026-03-31 | 279d8ef |
| 260331-ph8 | Phase 8: Sweep point reporting (report cards, summaries, combined report) | 2026-03-31 | 00e5833 |
| 260415-u4s | Benchmark threading opportunities across simulation codebase | 2026-04-16 | d1c5bd9 |

## Critical Context for Future Agents

### Unit Conventions in JLD2

These are essential for any code that reconstructs simulation state from saved data:

- **sim_omega0**: stored in **rad/ps** (NOT rad/s). Convert to THz: `f0 = ω0 / (2π)`
- **sim_Dt**: stored in **picoseconds**. `fs = fftfreq(Nt, 1/Δt_ps)` gives THz.
- **P_cont_W**: average continuum power, NOT peak power. Peak: `P_peak = 0.881374 * P_cont / (fwhm_s * rep_rate)`
- **convergence_history**: stored in **dB** (converted post-optimization via lin_to_dB)
- **band_mask**: Boolean vector of length Nt, in FFT order (not fftshifted)

### Script Constant Prefixes

Julia `const` cannot be redefined in REPL. Each script uses a unique prefix to avoid collisions:

- `RC_` — run_comparison.jl
- `SW_` — run_sweep.jl
- `SR_` — generate_sweep_reports.jl

### Include Guards

Scripts use `if !(@isdefined _COMMON_JL_LOADED)` pattern. `using` statements must go OUTSIDE the guard block (macros need compile-time visibility).

### Burst Compute (Phase 13/14 heavy runs)

The always-on `claude-code-host` (this machine) is `e2-standard-2` (2 vCPU, 8 GB). For anything computationally heavy — multi-start optimization, full Hessian eigendecomposition, parameter sweeps — use the burst VM `fiber-raman-burst` (c3-highcpu-22, 22 vCPU, 44 GB, AVX-512). Helpers installed on PATH:

- `burst-start` — start the burst VM (~30 s boot). Billing begins.
- `burst-ssh [cmd]` — SSH into burst; with an argument runs that command and returns
- `burst-stop` — stop the burst VM. **CRITICAL** — always stop when done to avoid $0.90/hour burn
- `burst-status` — check current state

Workflow:

1. Commit + push on claude-code-host: `git push`
2. `burst-start && burst-ssh 'cd ~/fiber-raman-suppression && git pull && julia --threads=22 scripts/<thing>.jl'`
3. `burst-ssh 'cd ~/fiber-raman-suppression && git add results/ && git commit -m "results" && git push'`
4. `git pull` on claude-code-host
5. `burst-stop`

Always use `--threads=22` (or `JULIA_NUM_THREADS=22`) on the burst VM. Benchmark showed parallel forward+adjoint solves give 3.55× at 8 threads — scales further on 22. Embarrassingly-parallel patterns (Hessian columns, multi-start) benefit most.

Light tests / unit tests / plan validation: run directly on this machine — no need for burst.

See `.planning/notes/compute-infrastructure-decision.md` and `.planning/todos/pending/provision-gcp-vm.md` for full details.

### Critical Directive — Do Not Break Original Optimizer Path (Phase 14)

When implementing Phase 14 (Sharpness-Aware / Hessian-in-Cost optimization), the existing `spectral_band_cost` and `optimize_spectral_phase` entry points **MUST remain fully functional and untouched**. The user's explicit directive: "the original cost function and that type of method should be kept separate and the hessian one should be a new one so we can use them both." Phase 14 adds a NEW parallel path (`spectral_band_cost_sharp`, `optimize_spectral_phase_sharp`) — it does not replace or modify the existing one. Regression tests confirming the original path is unchanged are a Phase 14 success criterion.

### Deterministic Numerical Environment (Phase 15)

All optimization entry-point scripts now call `ensure_deterministic_environment()` at top (from `scripts/determinism.jl`). This pins `FFTW.set_num_threads(1)` and `BLAS.set_num_threads(1)`, and the 18 `plan_fft`/`plan_ifft` call sites across `src/simulation/*.jl` were switched from `flags=FFTW.MEASURE` to `flags=FFTW.ESTIMATE` (commit 1caa08d). Consequence: identical seed → bit-identical `phi_opt`, `J_final`, and `ftrace`, both within a single process and across fresh Julia subprocesses. Verified by:

- `test/test_determinism.jl` — asserts `maximum(abs(phi_opt_a - phi_opt_b)) == 0.0` (same-process)
- `scripts/phase15_benchmark.jl` — 3 fresh subprocesses produced `max-min(J_final) = 0.0` on ESTIMATE (cross-process bit-identity); MEASURE leg reproduces the Phase 13 bug as a control (max-min = 1.055e-13)

Performance cost: **+21.4%** wall time on SMF-28 canonical (L=2m, P=0.2W, Nt=8192, max_iter=30) — well within the +30% acceptance budget. See `results/raman/phase15/benchmark.md` for the full table.

If an individual script needs max speed at the cost of reproducibility, it can call `ensure_deterministic_environment(force=true)` with custom flags, OR swap the 18 `FFTW.ESTIMATE` tokens back to `FFTW.MEASURE` in `src/simulation/*.jl`. Both are discouraged for research runs — the +21% cost buys exact reproducibility, which is usually the higher-value tradeoff.

Entry-point scripts wired: `raman_optimization.jl`, `amplitude_optimization.jl`, `run_sweep.jl`, `run_comparison.jl`, `generate_sweep_reports.jl`, `sharpness_optimization.jl`. All have exactly 2 added lines (include + call). `scripts/common.jl` was NOT modified (kept pure-utility, per Phase 15 CONTEXT directive).

### Key Bugs Fixed

1. **dB/linear mismatch (2026-03-26)**: `optimize_spectral_phase` fed `lin_to_dB(J)` to L-BFGS but gradient was linear-scale. Fixed: optimizer now receives linear J. All prior sweep results have degraded convergence.

2. **SPM time window formula (2026-03-31)**: `γ×P×L` gives φ_NL (radians), not Δω (rad/s). Fixed: `δω = 0.86 × φ_NL / T0`. High-power/long-fiber windows were 5-7x too small.

Both fixes require re-running the sweep to get valid results.

### Pending Actions

- [ ] Re-run sweep with fixed aggregate JLD2 (current sweep_results.jld2 may have stale entries)
- [ ] Multimode M>1 exploration — extend propagation to few-mode fibers for quantum noise analysis
- [ ] Re-run 5 production configs via run_comparison.jl (Phase 6 Plan 02)
- [ ] Re-run physics_insight.jl (Phase 6.1 Plan 02) — phase profiles may change with log-scale cost
- [ ] Compare old vs new convergence rates (dB/linear fix — publishable result)

### Accumulated Context — Key Decisions

- Log-scale cost `10*log10(J)` with gradient `10/(J*ln10)` gives 20-28 dB improvement across sweep
- Raman response `exp(-t/tau2)` overflows for `t<0` when `time_window > 45ps` — clamped to `max(t,0)`
- Auto-sizing time_window/Nt in setup functions prevents silent attenuator absorption
- lambda_boundary reduced 10.0 to 1.0 (correct time windows make heavy penalty counterproductive)
- Rivera Lab context: internal research group, plots for lab meetings/advisor reviews, exploratory physics discovery mindset
- [Phase 10]: beta_order=3 required for FIBER_PRESETS with 2 betas; sweep scripts confirmed this — must be explicit in pab_load_config
- [Phase 10]: Phase ablation shows phi_opt requires sub-THz spectral alignment and exact amplitude (±25% degrades HNLF by 30 dB); mechanism is amplitude-sensitive nonlinear interference across full spectral bandwidth
- [Phase 10-propagation-resolved-physics]: β_order=3 required in setup_raman_problem when using fiber presets with 2 betas (β₂+β₃)
- [Phase 10-propagation-resolved-physics]: @sprintf with string concatenation (* operator) fails in Julia 1.12 macroexpand at docstring-bind time — use single literal format strings only
- [Phase 10-propagation-resolved-physics]: Optimal phase prevents Raman onset entirely in 5 of 6 configs; long-fiber SMF-28 5m shows critical breakdown at z=0.20m (4% of fiber)
- [Phase 11-classical-physics-completion]: J(z) trajectories mean correlation 0.621 vs phi_opt structural similarity 0.091 — fiber physics dominates z-dynamics, not phase shape
- [Phase 11-classical-physics-completion]: Spectral divergence appears at ~2% of fiber length across all 6 configs; H1 overlap 30%; H2 tolerance 0.329 THz (2.5% of Raman BW)
- [Phase 11-classical-physics-completion]: H3 CONFIRMED: amplitude-sensitive nonlinear interference — 3dB envelope is single point at alpha=1.0; CPA model ruled out
- [Phase 11-classical-physics-completion]: Suppression horizon: L_50dB ≈ 3.33 m at P=0.2W for SMF-28; 5m degradation is landscape-limited, not resolution or convergence
- [Phase 12-suppression-reach]: Bypass setup_raman_problem auto-sizing via direct MultiModeNoise calls for L>=10m — the wrapper always overrides explicit Nt/tw at long distances
- [Phase 12-suppression-reach]: SMF-28 phi@2m maintains -57 dB Raman suppression at L=30m (15x opt horizon); HNLF reach collapses to <3 dB by z=15m — fiber-type-dependent suppression reach confirmed

### Roadmap Evolution

- Phase 9 added: Physics of Raman Suppression — understand universal vs arbitrary phase structure
- Phase 13 added (2026-04-16): Optimization Landscape Diagnostics — gauge-fixing, polynomial projection, Hessian eigenspectrum at L-BFGS optima; gates any Newton's method decision. See `.planning/notes/newton-vs-lbfgs-reframe.md` and `.planning/seeds/newton-method-implementation.md`.
- Phase 14 added (2026-04-16): Sharpness-Aware (Hessian-in-Cost) Optimization — new optimizer path `optimize_spectral_phase_sharp` parallel to existing L-BFGS; keeps original cost function unchanged; user directive is both paths must remain usable for A/B comparison.
- Phase 15 added (2026-04-16): Deterministic Numerical Environment — user-directed. Fixes FFTW.MEASURE plan-selection non-determinism found in Phase 13 Plan 01 (max|Δφ| = 1.04 rad between identical-seed runs). Pins FFTW planner to ESTIMATE, sets FFTW/BLAS thread counts to 1. Runs before Phase 14 Plan 02 so A/B comparison is reproducible.
- Phase 16 added (2026-04-17, Session H): Cost Function Head-to-Head Audit — systematic 4-variant × 3-config comparison (linear E_band/E_total, log-scale dB, sharpness-aware from Phase 14, noise-aware scaffold). Produces `.planning/notes/cost-function-default.md` recommending a project-wide default cost; prevents drift between parallel optimization paths. Owned namespace: `scripts/cost_audit_*.jl`, `.planning/phases/16-*/`, `.planning/notes/cost-audit-*.md`, `.planning/sessions/H-cost-*.md`. No modifications to existing optimizers — new wrappers only. 12 runs on burst VM.

### Resolved Issues

- [RESOLVED 2026-04-16] FFTW.MEASURE plan-selection non-determinism (max|Δφ| = 1.04 rad between identical-seed runs, found in Phase 13 Plan 01) — fixed in Phase 15 Plan 01 via `scripts/determinism.jl` (FFTW/BLAS thread pinning) + mechanical `flags=FFTW.MEASURE → flags=FFTW.ESTIMATE` patch across 18 sites in `src/simulation/*.jl`. Regression test `test/test_determinism.jl` asserts `maximum(abs(phi_opt_a - phi_opt_b)) == 0.0` (bit-identity). Also verified cross-process: 3 fresh Julia subprocesses converge to bit-identical `J_final` (benchmark max-min = 0.0). Performance cost: +21.4% wall time on SMF-28 canonical (see `results/raman/phase15/benchmark.md`).
- [RESOLVED 2026-03-31] recommended_time_window() SPM formula: δω = 0.86 × φ_NL / T0
- [RESOLVED 2026-03-31] Raman response overflow for large time windows (clamp to max(t,0))
- [RESOLVED 2026-03-31] dB/linear mismatch fully resolved with log-scale cost function
- [RESOLVED 2026-03-26] Adjoint tolerance: Vern9/1e-10 → Tsit5/1e-8 (O(ε²) verified)

### Open Concerns

- compute_noise_map_modem in src/analysis/analysis.jl is broken (empty @tullio, undefined vars) — marked abandoned, do not call
- README.md at project root is stale (references MMF squeezing, not Raman suppression)

## Session Continuity

Last session: 2026-04-17T02:40:00Z
Last activity: 2026-04-17
Next action: **URGENT** — a follow-up session must (1) check `burst-ssh "tail -100 fiber-raman-suppression/sweep_run.log"` for sweep completion, (2) rsync results back, (3) run `burst-stop` (burst VM is RUNNING at $0.90/hr), (4) update `07-03-SUMMARY.md` status IN_PROGRESS → COMPLETE with final counts. Then continue Phase 13/14/15 Newton/Hessian sprint.

## Active Background Jobs

- **Parameter sweep (Phase 07 Plan 03)** — `julia -t auto scripts/run_sweep.jl` on `fiber-raman-burst` in tmux session `sweep`, heavy lock held. Launched 2026-04-17T01:42Z. At last check: SMF-28 11/12 done + L5m_P0.2W in progress; HNLF 4/12 at L=1.0m P=0.005W in progress. Multi-start + aggregate saves + heatmap PNGs still pending. See `.planning/phases/07-parameter-sweeps/07-03-SUMMARY.md`.
