---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Verification & Discovery
status: Awaiting checkpoint
stopped_at: "06.1-02-PLAN.md Task 2 (human-verify: all 8 physics insight figures)"
last_updated: "2026-03-26T03:53:34Z"
progress:
  total_phases: 5
  completed_phases: 3
  total_plans: 7
  completed_plans: 6
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Physically correct simulation and optimization of Raman suppression, with every output plot clearly communicating the underlying physics.
**Current focus:** Phase 06.1 — physics-insight

## Current Position

Phase: 06.1 (physics-insight) — EXECUTING
Plan: 2 of 2

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
- [Phase 06.1-physics-insight Plan02]: Fig 5 uses Option A (no re-propagation): J_before/J_after annotations from JLD2 scalars; input spectrum only (avoids ~2.5 min re-propagation)
- [Phase 06.1-physics-insight Plan02]: Group delay NaN-masks noise-floor bins (vs zero-fill used for phi_norm) — NaN causes matplotlib to break line rendering cleanly
- [Phase 06.1-physics-insight Plan02]: Global P_peak_global across all runs normalizes Fig 5 dB scale consistently

### Pending Todos

- Phase 4 start: Empirically calibrate photon number conservation tolerance on one real SMF-28 L=1m run before setting hard assertion threshold
- Phase 4 start: Inspect `results/raman/MATHEMATICAL_FORMULATION.md` for verification test case specifications
- Phase 5 start: Find exact location in raman_optimization.jl where `push!(cost_history, ...)` should be added to the callback
- Phase 7 CRITICAL: `recommended_time_window()` has NO power dependence — only accounts for linear dispersive walk-off. SPM broadening at high power pushes energy into the attenuator, causing 38-49% photon number loss for high-P/long-L configs. The function MUST be extended with a power-aware correction OR sweeps must use generous fixed windows (safety_factor=4-5x) with Nt scaled to maintain resolution. Without this fix, high-P sweep points will have artificially low Raman cost J because attenuator absorbs energy before it reaches the Raman band.
- Phase 7 start: Run `recommended_time_window()` for extreme sweep points (L=0.5m/high-P and L=5m/low-P) to verify a single fixed time_window covers all sweep points

### Roadmap Evolution

- Phase 6.1 inserted after Phase 6: Physics Insight — visualize optimizer strategy (φ_opt overlays, N vs ΔdB correlation, polynomial fit residual visualization) (URGENT)
  - Motivation: Phase 6 produced infrastructure (summary table, convergence overlay, spectral overlays) but no physics insight. Phase decomposition showed 99% residual — optimizer uses complex non-polynomial phase structure. Need to understand and visualize what the optimizer is actually doing.

### Blockers/Concerns

- [v1.0 flag]: _manual_unwrap behavior on arrays with leading/trailing zeros needs verification
- [v1.0 flag]: Validate 60 dB vs 40 dB evolution floor against real run data
- [v2.0 risk]: Phase 4 is a strict gate — if a physics bug is found, Phases 5-7 must wait for the fix before proceeding
- [Phase 4 finding — CRITICAL for Phase 7]: recommended_time_window() is power-blind. Photon number drift: 2.7% (low-P) → 49% (long fiber). High-power sweep points will produce misleading J values unless time_window is sized for nonlinear broadening, not just linear walk-off. See verification report results/raman/validation/verification_20260325_173537.md for quantitative evidence.

## Session Continuity

Last session: 2026-03-26T03:53:34Z
Stopped at: "06.1-02-PLAN.md checkpoint:human-verify (Task 2 of 2) — all 8 insight PNGs generated, awaiting visual approval"
Resume file: None
