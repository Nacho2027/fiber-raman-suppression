---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Verification & Discovery
status: Ready to execute
stopped_at: Completed 04-01-PLAN.md
last_updated: "2026-03-25T21:12:33.921Z"
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 2
  completed_plans: 1
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Physically correct simulation and optimization of Raman suppression, with every output plot clearly communicating the underlying physics.
**Current focus:** Phase 04 — correctness-verification

## Current Position

Phase: 04 (correctness-verification) — EXECUTING
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

### Pending Todos

- Phase 4 start: Empirically calibrate photon number conservation tolerance on one real SMF-28 L=1m run before setting hard assertion threshold
- Phase 4 start: Inspect `results/raman/MATHEMATICAL_FORMULATION.md` for verification test case specifications
- Phase 5 start: Find exact location in raman_optimization.jl where `push!(cost_history, ...)` should be added to the callback
- Phase 7 start: Run `recommended_time_window()` for extreme sweep points (L=0.5m/high-P and L=5m/low-P) to verify a single fixed time_window covers all sweep points

### Blockers/Concerns

- [v1.0 flag]: _manual_unwrap behavior on arrays with leading/trailing zeros needs verification
- [v1.0 flag]: Validate 60 dB vs 40 dB evolution floor against real run data
- [v2.0 risk]: Phase 4 is a strict gate — if a physics bug is found, Phases 5-7 must wait for the fix before proceeding

## Session Continuity

Last session: 2026-03-25T21:12:33.918Z
Stopped at: Completed 04-01-PLAN.md
Resume file: None
