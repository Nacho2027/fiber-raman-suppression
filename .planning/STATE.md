---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Verification & Discovery
status: In progress
stopped_at: Sweep analysis complete; next steps discussion pending
last_updated: "2026-03-31"
progress:
  total_phases: 8
  completed_phases: 6
  total_plans: 13
  completed_plans: 12
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Physically correct simulation and optimization of Raman suppression, with every output plot clearly communicating the underlying physics.
**Current focus:** Results complete. Next: multimode (M>1) simulations for quantum noise analysis.

## Current Position

Phase 8 (Sweep Point Reporting) — COMPLETE
Phase 7 / 07.1 (Parameter Sweeps) — CODE COMPLETE, sweep executed with log-scale cost
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

### Resolved Issues

- [RESOLVED 2026-03-31] recommended_time_window() SPM formula: δω = 0.86 × φ_NL / T0
- [RESOLVED 2026-03-31] Raman response overflow for large time windows (clamp to max(t,0))
- [RESOLVED 2026-03-31] dB/linear mismatch fully resolved with log-scale cost function
- [RESOLVED 2026-03-26] Adjoint tolerance: Vern9/1e-10 → Tsit5/1e-8 (O(ε²) verified)

### Open Concerns

- compute_noise_map_modem in src/analysis/analysis.jl is broken (empty @tullio, undefined vars) — marked abandoned, do not call
- README.md at project root is stale (references MMF squeezing, not Raman suppression)

## Session Continuity

Last session: 2026-03-31
Stopped at: Sweep analysis complete, next steps discussion pending
Next action: Multimode (M>1) simulations for quantum noise analysis; optionally re-run sweep with fixed aggregate JLD2
