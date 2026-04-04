---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Verification & Discovery
status: Ready to execute
stopped_at: "Completed 12-01-PLAN.md: long-fiber propagation reach, phi_opt interpolation, 3 diagnostic figures"
last_updated: "2026-04-04T20:56:54.571Z"
progress:
  total_phases: 11
  completed_phases: 8
  total_plans: 19
  completed_plans: 17
  percent: 89
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Physically correct simulation and optimization of Raman suppression, with every output plot clearly communicating the underlying physics.
**Current focus:** Phase 12 — suppression-reach

## Current Position

Phase: 12 (suppression-reach) — EXECUTING
Plan: 2 of 2
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

### Resolved Issues

- [RESOLVED 2026-03-31] recommended_time_window() SPM formula: δω = 0.86 × φ_NL / T0
- [RESOLVED 2026-03-31] Raman response overflow for large time windows (clamp to max(t,0))
- [RESOLVED 2026-03-31] dB/linear mismatch fully resolved with log-scale cost function
- [RESOLVED 2026-03-26] Adjoint tolerance: Vern9/1e-10 → Tsit5/1e-8 (O(ε²) verified)

### Open Concerns

- compute_noise_map_modem in src/analysis/analysis.jl is broken (empty @tullio, undefined vars) — marked abandoned, do not call
- README.md at project root is stale (references MMF squeezing, not Raman suppression)

## Session Continuity

Last session: 2026-04-04T20:56:54.564Z
Stopped at: Completed 12-01-PLAN.md: long-fiber propagation reach, phi_opt interpolation, 3 diagnostic figures
Next action: Multimode (M>1) simulations for quantum noise analysis; optionally re-run sweep with fixed aggregate JLD2
