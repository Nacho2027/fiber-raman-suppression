# SMF Gain-Noise: Nonlinear Fiber Optics Simulation & Optimization

## What This Is

A Julia simulation platform for nonlinear fiber optics — specifically Raman suppression optimization via spectral phase and amplitude shaping in single-mode fibers. Includes forward+adjoint pulse propagation, L-BFGS optimization, and publication-quality visualization. For internal research group use (RiveraLab).

## Core Value

Physically correct simulation and optimization of Raman suppression, with every output plot clearly communicating the underlying physics.

## Requirements

### Validated

- ✓ Forward pulse propagation (Kerr + Raman nonlinearity, interaction picture) — existing
- ✓ Adjoint-method gradient computation for spectral phase optimization — existing
- ✓ L-BFGS optimization via Optim.jl — existing
- ✓ Spectral comparison (input vs output, dB scale, wavelength axis) — existing
- ✓ Temporal pulse shape comparison (before/after optimization) — existing
- ✓ Spectral and temporal evolution heatmaps along fiber length — existing
- ✓ Raman band shading covers correct ~13 THz gain band — v1.0
- ✓ Consistent Okabe-Ito color identity (input=blue, output=vermillion) — v1.0
- ✓ 3x2 phase diagnostic with mask-before-unwrap, all 5 phase views — v1.0
- ✓ Global P_ref normalization across Before/After comparison columns — v1.0
- ✓ Shared axis limits for Before/After panels — v1.0
- ✓ Spectral auto-zoom to signal-bearing region — v1.0
- ✓ Metadata annotation on every figure (fiber type, L, P, lambda0, FWHM) — v1.0
- ✓ Merged 2x2 evolution comparison (3-file output per run) — v1.0
- ✓ Forward solver correctness: soliton N=1 shape preserved to 1.1% at Nt=2^14 — v2.0 Phase 4
- ✓ Adjoint gradient exactness: Taylor remainder slopes [2.01, 2.07, 2.09] confirm O(ε²) — v2.0 Phase 4
- ✓ Cost function mask correctness: spectral_band_cost matches direct integration exactly — v2.0 Phase 4
- ✓ Photon number conservation measured across all 5 configs (attenuator drift documented) — v2.0 Phase 4
- ✓ Per-run JLD2 result files with 18 fields (phi_opt, uω0, convergence history, metadata) — v2.0 Phase 5
- ✓ Append-safe manifest.json indexing all runs with scalar summaries — v2.0 Phase 5
- ✓ Optim.jl convergence trace captured via store_trace=true — v2.0 Phase 5

### Active

#### Current Milestone: v2.0 Verification & Discovery

**Goal:** Verify that the raman_optimization pipeline is physically correct, then systematically explore parameter space and identify non-trivial patterns across optimization runs.

**Target features:**
- Correctness verification of raman_optimization.jl against published NLSE/Raman theory
- Cross-run comparison infrastructure (overlay phase profiles, costs, convergence)
- Pattern detection across fiber types and optimization configs
- Parameter space exploration (fiber lengths, peak powers beyond current presets)
- Automated summary/amalgamation plots after all runs complete

### Out of Scope

- Interactive/web-based plots — static PNG/PDF output sufficient for research group
- Notebook-specific plotting — focus on scripts/visualization.jl pipeline
- GPU acceleration — CPU-only computation sufficient for current grid sizes

## Context

- **Stack**: Julia 1.12 + DifferentialEquations.jl + FFTW.jl + Optim.jl + PyPlot (matplotlib)
- **Visualization**: `scripts/visualization.jl` (~1800 lines), fully overhauled in v1.0
- **Optimization scripts**: `scripts/raman_optimization.jl` (5 run configs), `scripts/amplitude_optimization.jl`
- **Documentation**: All `src/` functions fully documented with physics descriptions (2026-03-26). Core simulation layer (GMMNLSE, adjoint, fibers, gain) has comprehensive docstrings.
- **Runs**: Multiple fiber configs (SMF-28, HNLF) x (lengths, powers). Results to `results/raman/`
- **Shipped v1.0**: Visualization overhaul — 3 phases, 6 plans, all plotting functions refactored
- **Known minor gaps from v1.0**: jet→inferno colormap swap, grid on pcolormesh, evolution floor not yet applied
- **v2.0 Phase 4 finding**: Super-Gaussian attenuator causes 2.7-49% photon number drift — not a solver bug, but indicates time window may be undersized for high-power/long-fiber configs. Relevant for Phase 7 sweeps.

## Constraints

- **Tech stack**: Julia + PyPlot (matplotlib). No new visualization dependencies.
- **Output format**: PNG at 300 DPI for archival.
- **Performance**: Plotting should not add significant overhead to optimization runs.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Inferno colormap default | Black noise floor matches physics (dark = no signal) | ✓ Good |
| Mask-before-unwrap for phase | Prevents noise propagation into valid phase data | ✓ Good |
| Two-pass Before/After rendering | Global P_ref ensures dB values are directly comparable | ✓ Good |
| Merged 2x2 evolution figure | Single figure replaces two separate PNGs, enables side-by-side comparison | ✓ Good |
| _energy_window over _auto_time_limits | More robust for dispersed/amplitude-shaped pulses | ✓ Good |
| GDD percentile clipping (2nd-98th) | Prevents outlier spikes from dominating axis | ✓ Good |
| recommended_time_window() is power-blind | Phase 4 VERIF-02 showed 2.7-49% attenuator absorption; function uses linear walk-off only, no SPM broadening term. Must fix before Phase 7 sweeps. | ⚠️ Revisit |
| sim["ωs"] already includes ω₀ carrier offset | Photon number formula uses abs.(sim["ωs"]) directly, NOT abs.(ωs .+ ω₀). Verified in Phase 4. | ✓ Good |
| Sweep uses max_iter=30, not 100 | Phase 6 convergence plots show all runs plateau by iteration 30. Sweep maps the landscape (which (L,P) gives -30 vs -40 dB) — doesn't need last-decimal precision. To get exact optimal suppression at a specific point, re-run that point with max_iter=100+. | ✓ Good |
| Sweep Nt floor = 2^13 (8192) | nt_for_window() returns Nt=1024-4096 which is too coarse — production runs use 8192-16384. Low Nt gives the optimizer fewer spectral phase knobs. Phase 7.1 added SW_NT_FLOOR = 2^13. | ✓ Good |
| Sweep do_plots=false, then targeted visuals | Generating 96 PNGs (3 per point × 32) wastes attention. Sweep produces heatmaps first, then full plots for ~6-8 interesting points (best/worst suppression, convergence boundary). Two-pass: coarse map then focused inspection. | ✓ Good |
| **dB/linear mismatch in optimize_spectral_phase** | L-BFGS received lin_to_dB(J) as objective but linear gradient from adjoint. Corrupted Hessian approximation and Wolfe line search. Explains 95% non-convergence in production runs. Fixed by external agent 2026-03-26: returns linear J, f_abstol→1e-10, convergence history converted to dB post-optimization. ALL prior results used broken optimizer — must re-run sweep + production configs. | ⚠️ Revisit |
| **Adjoint tolerance: Vern9/1e-10 → Tsit5/1e-8** | Forward solve uses Tsit5 with 4th-order interpolant. Adjoint queries this interpolant, so its accuracy is bottlenecked regardless of adjoint solver order. L-BFGS needs ~1e-4 relative gradient accuracy, not 1e-10. Switching gives ~1.5-2x speedup on adjoint solve. Taylor remainder slopes 2.00/1.98 confirm gradient still exact. All 22+ tests pass. | ✓ Good |
| **Documentation overhaul of src/ layer** | All simulation, sensitivity, gain, analysis functions fully documented with physics descriptions, argument lists, and math formulations. Removed debug prints, fixed misleading comments, standardized line endings. | ✓ Good |
| **[Phase 8] Post-hoc sweep report generation** | `generate_sweep_reports.jl` reads JLD2 files and produces per-point report cards (4-panel PNG + markdown) plus ranked summary tables. No re-running optimization. | ✓ Good |
| **[Phase 7/8 CRITICAL] Log-scale cost function** | `10*log10(J)` with gradient scaling `10/(J*ln10)`. L-BFGS now works in dB space natively, improving suppression 20-28 dB across all sweep points. Resolves the dB/linear mismatch from 2026-03-26. | ✓ Good |
| **[Phase 7/8] Raman response overflow fix** | `exp(-t/tau2)` overflows for `t<0` when `time_window > 45ps`. Fixed by clamping to `max(t,0)` in Raman response construction. | ✓ Good |
| **[Phase 7/8] Auto-sizing time_window and Nt** | `setup_raman_problem`/`setup_amplitude_problem` auto-expand time_window and Nt when caller value is too small for dispersive walk-off + SPM broadening. Prevents silent attenuator absorption. | ✓ Good |
| **[Phase 7/8] lambda_boundary reduced 10.0 to 1.0** | With correct time windows, heavy boundary penalty fights the optimizer. Reduced from 10.0 to 1.0. | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-31 after Phase 8 completion and sweep analysis*
