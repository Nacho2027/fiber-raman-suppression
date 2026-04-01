---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Verification & Discovery
status: Ready to execute
stopped_at: Documentation overhaul complete; sweep running; cleanup in progress
last_updated: "2026-03-26T18:00:00.000Z"
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 11
  completed_plans: 10
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Physically correct simulation and optimization of Raman suppression, with every output plot clearly communicating the underlying physics.
**Current focus:** Phase 07.1 — grid resolution fix (code done, sweep re-run pending)

## Current Position

Phase: 07.1 (grid-resolution-fix) — CODE COMPLETE, SWEEP RUNNING
Plan: 1 of 1 (sweep running in background)
Side work: Comprehensive documentation overhaul of src/ layer + codebase cleanup

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 4. Correctness Verification | - | - | - |
| 5. Result Serialization | - | - | - |
| 6. Cross-Run Comparison and Pattern Analysis | - | - | - |
| 7. Parameter Sweeps | - | - | - |

*Updated after each plan completion*
| Phase 04 P01 | 3 | 1 tasks | 2 files |
| Phase 04-correctness-verification P02 | 35 | 2 tasks | 2 files |
| Phase 05-result-serialization P01 | 12 | 2 tasks | 3 files |
| Phase 06-cross-run-comparison-and-pattern-analysis P01 | 8 | 2 tasks | 1 files |
| Phase 06-cross-run-comparison-and-pattern-analysis P02 | 15 | 1 tasks | 1 files |
| Phase 06.1-physics-insight P01 | 4 | 2 tasks | 5 files |
| Phase 06.1-physics-insight P02 | 2 | 1 tasks (checkpoint) | 5 files |
| Phase 07-parameter-sweeps P02 | 217 | 2 tasks | 2 files |
| Phase 07.1-grid-resolution-fix P01 | - | 2 tasks | 1 file |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1.0]: Use inferno as project colormap default
- [v1.0]: Mask-before-unwrap at -40 dB threshold for phase diagnostics
- [v1.0]: _energy_window over _auto_time_limits for temporal limits
- [v1.0]: Merged 2x2 evolution figure (3-file output per run)
- [v2.0 research]: JLD2.jl + JSON3.jl are the only new dependencies needed; DrWatson deferred as overkill at 5-run scale
- [v2.0 research]: Use small grids (Nt=2^7-2^8) for verification tests so suite completes in <60s
- [v2.0 research]: Canonical grid policy — all 5 runs must use same Nt and time_window, recorded in JLD2
- [Phase 04]: β_order=3 required for SMF28 preset (2 betas): setup_raman_problem enforces length(betas_user) ≤ β_order-1
- [Phase 04]: VERIF-04 uses atol=1e-12 (machine precision) because both J_func and J_direct paths use identical arithmetic
- [Phase 04]: verification.jl separate from test_optimization.jl — research-grade at Nt=2^14 vs fast CI at Nt=2^9
- [Phase 04-correctness-verification]: VERIF-02 FAILs by design: attenuator absorbs energy causing 2.7-49% photon number drift
- [Phase 04-correctness-verification]: sim['ωs'] is absolute freq (ω₀ included); photon number uses abs.(sim['ωs']) directly
- [Phase 04-correctness-verification]: VERIF-03 Taylor remainder at Nt=2^14: L=0.1m + epsilons=[1e0,1e-1,1e-2,1e-3]; slopes [2.01,2.07,2.09] confirm adjoint O(eps²)
- [Phase 05-result-serialization]: JLD2 + JSON3 for result persistence: JLD2 round-trips native Julia types; manifest.json at fixed path for Phase 6 discovery
- [Phase 05-result-serialization]: Manifest is append-safe (read/update-or-append/write) so sequential runs accumulate without overwriting
- [Phase 06]: P_cont_W in JLD2 is average continuum power, NOT peak power; compute_soliton_number takes peak power; run_comparison.jl (Plan 02) must compute P_peak = 0.881374 * P_cont / (fwhm_s * rep_rate)
- [Phase 06]: RC_ prefix for fiber constants in run_comparison.jl prevents const redefinition errors in Julia REPL sessions
- [Phase 06]: sim_Dt in JLD2 is picoseconds (sim[Δt] = time_window/Nt in ps); must multiply by 1e-12 before calling decompose_phase_polynomial which expects seconds
- [Phase 06.1-physics-insight]: Julia using statements must be placed outside include guard — macros need compile-time visibility; moved imports before if !(@isdefined) block
- [Phase 06.1-physics-insight]: normalize_phase zero-fills noise-floor bins (!signal_mask) to prevent random phase from distorting y-axis in overlays
- [Phase 06.1-physics-insight]: 98.9-99.9% non-polynomial residual fraction confirmed: optimizer uses complex high-order phase shaping, not GDD/TOD
- [Phase 07]: Sweep max_iter=30 (not 100) — convergence plots show plateau by iter 30. Sweep maps the landscape, doesn't need last-decimal precision. Re-run individual points at max_iter=100+ for publication-quality results.
- [Phase 07.1]: Nt floor = 2^13 (8192). nt_for_window() returns 1024-4096 which is too coarse for meaningful optimization. Low Nt = fewer spectral phase degrees of freedom = worse suppression.
- [Phase 07]: Two-pass visualization: sweep with do_plots=false (fast heatmaps), then full plots for ~6-8 interesting points identified from the heatmap. Avoids 96 PNGs that dilute attention.
- [CRITICAL — external fix 2026-03-26]: optimize_spectral_phase was returning lin_to_dB(J) to L-BFGS instead of linear J. This corrupted L-BFGS Hessian approximation and Wolfe line search (dB-scale objective paired with linear-scale gradient). Fixed by another agent in raman_optimization.jl line 191. f_abstol changed from 1e-6 (dB scale) to 1e-10 (linear scale). Convergence history now stored as linear values converted to dB post-optimization. ALL prior optimization results used the broken optimizer — phase profiles are valid but convergence behavior was degraded. Current sweep (running) uses old code. Must re-run sweep + production configs with fix.
- [Phase 06.1-physics-insight Plan02]: Fig 5 uses Option A (no re-propagation): J_before/J_after annotations from JLD2 scalars; input spectrum only (avoids ~2.5 min re-propagation)
- [Phase 06.1-physics-insight Plan02]: Group delay NaN-masks noise-floor bins (vs zero-fill used for phi_norm) — NaN causes matplotlib to break line rendering cleanly
- [Phase 06.1-physics-insight Plan02]: Global P_peak_global across all runs normalizes Fig 5 dB scale consistently
- [Phase 07-parameter-sweeps]: SW_ prefix for all constants in run_sweep.jl to prevent Julia const redefinition errors when script is re-included in REPL
- [Phase 07-parameter-sweeps]: N contour lines are vertical in L×P heatmap — N=sqrt(γP_peak T₀²/|β₂|) is independent of L (Research Pitfall 1)
- [Phase 07-parameter-sweeps]: safety_factor=3.0 when phi_NL>20 — higher-order effects undermine first-order SPM estimate for extreme sweep points
- [Phase 07.1]: SW_NT_FLOOR=2^13 (8192) minimum Nt in run_sweep.jl — nt_for_window() returns minimum for temporal resolution, sweep needs floor for optimization quality
- [Phase 07.1]: max_iter=30 for sweep/multistart (was 100) — convergence plateau by iteration 30-40 per Phase 6 evidence
- [Phase 07.1]: L=10m dropped from SMF-28 grid — 4x4=16 + 4x4=16 = 32 total sweep points
- [Documentation overhaul 2026-03-26]: All src/ functions documented with physics descriptions. Fixed: copy-paste adjoint docstring, "multimode" label on SMF files, "disperive" typo, stray println debug statements, misleading "silicon" comment (→ fused silica), duplicate FiniteDifferences import. CRLF→LF in 6 src files. Module docstring added. compute_noise_map_modem marked broken (empty @tullio, undefined vars).
- [Adjoint tolerance change 2026-03-26]: Changed Vern9/reltol=1e-10 → Tsit5/reltol=1e-8 in solve_adjoint_disp_mmf. All tests pass. Taylor remainder slopes: 2.00, 1.98 (perfect O(ε²)). Gradient FD agreement: 5/5 pass. Expected ~1.5-2x adjoint speedup.

### Pending Todos

- Phase 4 start: Empirically calibrate photon number conservation tolerance on one real SMF-28 L=1m run before setting hard assertion threshold
- Phase 4 start: Inspect `results/raman/MATHEMATICAL_FORMULATION.md` for verification test case specifications
- Phase 5 start: Find exact location in raman_optimization.jl where `push!(cost_history, ...)` should be added to the callback
- Phase 7 CRITICAL: `recommended_time_window()` has NO power dependence — only accounts for linear dispersive walk-off. SPM broadening at high power pushes energy into the attenuator, causing 38-49% photon number loss for high-P/long-L configs. The function MUST be extended with a power-aware correction OR sweeps must use generous fixed windows (safety_factor=4-5x) with Nt scaled to maintain resolution. Without this fix, high-P sweep points will have artificially low Raman cost J because attenuator absorbs energy before it reaches the Raman band.
- Phase 7 start: Run `recommended_time_window()` for extreme sweep points (L=0.5m/high-P and L=5m/low-P) to verify a single fixed time_window covers all sweep points
- AFTER CURRENT SWEEP: Re-run full sweep with dB/linear fix (raman_optimization.jl line 191). Current sweep = baseline with broken optimizer. Compare old vs new convergence rates — the improvement itself is a publishable result.
- AFTER CURRENT SWEEP: Re-run 5 production configs (run_comparison.jl) with fix — Phase 6 JLD2 files have dB convergence history, new runs will have linear. Update plot_convergence_overlay to handle both or regenerate all.
- AFTER CURRENT SWEEP: Re-run Phase 6.1 physics_insight.jl — phase profiles (phi_opt) may change significantly with correct optimizer. The 99% non-polynomial residual finding needs re-verification.

### Roadmap Evolution

- Phase 6.1 inserted after Phase 6: Physics Insight — visualize optimizer strategy (φ_opt overlays, N vs ΔdB correlation, polynomial fit residual visualization) (URGENT)
  - Motivation: Phase 6 produced infrastructure (summary table, convergence overlay, spectral overlays) but no physics insight. Phase decomposition showed 99% residual — optimizer uses complex non-polynomial phase structure. Need to understand and visualize what the optimizer is actually doing.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260331-gh0 | Fix sweep methodology: time window formula, max_iter, convergence reporting | 2026-03-31 | pending | [260331-gh0](./quick/260331-gh0-fix-sweep-methodology-time-window-formul/) |

### Blockers/Concerns

- [v1.0 flag]: _manual_unwrap behavior on arrays with leading/trailing zeros needs verification
- [v1.0 flag]: Validate 60 dB vs 40 dB evolution floor against real run data
- [v2.0 risk]: Phase 4 is a strict gate — if a physics bug is found, Phases 5-7 must wait for the fix before proceeding
- [CRITICAL — 2026-03-26]: dB/linear mismatch fix invalidates all prior optimization results. Current sweep (running) uses old code. After sweep completes: (1) re-run sweep with fix as comparison, (2) re-run 5 production configs, (3) re-verify Phase 6.1 physics insight findings. The before/after comparison of convergence rates is itself scientifically interesting.
- [RESOLVED — 2026-03-31]: recommended_time_window() SPM formula fixed. Bug: γ×P×L gives φ_NL (radians), not Δω (rad/s). Fix: δω = 0.86 × φ_NL / T0 per Agrawal Ch. 4. SMF-28 L=5m P=0.20W window: 29 ps → ~202 ps. Sweep must be re-run.

## Session Continuity

Last session: 2026-03-31
Stopped at: Fixed sweep methodology (time window formula, max_iter, reporting)
Resume file: None
Next action: Re-run sweep with `julia --project scripts/run_sweep.jl` to get corrected results
