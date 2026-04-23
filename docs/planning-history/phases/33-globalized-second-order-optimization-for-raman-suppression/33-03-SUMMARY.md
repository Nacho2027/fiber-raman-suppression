---
phase: 33-globalized-second-order-optimization-for-raman-suppression
plan: 03
subsystem: optimization
tags: [synthesis, report, phase-33, trust-region, direction-solver-contract]
dependency-graph:
  requires: [scripts/benchmark_common.jl, results/raman/phase33/**, scripts/trust_region_core.jl]
  provides: [scripts/benchmark_synthesis.jl, results/raman/phase33/SYNTHESIS.md, results/raman/phase33/rho_distribution.png, results/raman/phase33/exit_codes.png, results/raman/phase33/failure_taxonomy_by_config.png, 33-REPORT.md]
  affects: []
tech-stack:
  added: []
  patterns: [cross-run-synthesis, stacked-bar-taxonomy, verbatim-code-contract-in-report]
key-files:
  created:
    - scripts/benchmark_synthesis.jl
    - results/raman/phase33/SYNTHESIS.md
    - results/raman/phase33/rho_distribution.png
    - results/raman/phase33/exit_codes.png
    - results/raman/phase33/failure_taxonomy_by_config.png
    - .planning/phases/33-globalized-second-order-optimization-for-raman-suppression/33-REPORT.md
  modified: []
decisions:
  - "Synthesis treats SKIPPED_P8 and MISSING as first-class exit-code classes in every aggregation (not silently dropped) so the P8 pre-flight gate's contribution is visible in the data"
  - "Master table reports J in both linear (raw physics cost) and dB (10*log10(max(J,1e-30))) for cross-phase comparison against Phase 21 baselines"
  - "Rejection-cause classification priority: NaN-rho > cg_exit keyword > rho_too_small fallback (matches rejection_breakdown from trust_region_telemetry.jl)"
  - "33-REPORT.md pastes TRExitCode/DirectionSolver/SubproblemResult/SteihaugSolver/solve_subproblem/update_radius verbatim from scripts/trust_region_core.jl so Phase 34 planner has a reproducible handoff contract without needing to re-read source"
  - "Honest reporting: report does NOT claim TR beat L-BFGS on dB (no accepted steps to claim it on). Comparison table is axes-based (exit-code taxonomy, saddle handling, gauge-null safety) per research non-goal"
metrics:
  duration: "~30 min wall clock (file I/O + matplotlib, no simulation)"
  completed-date: 2026-04-21
  tasks-completed: 2
  files-created: 6
---

# Phase 33 Plan 03: Synthesis + Final Report

## One-liner

Ingested 9-slot Phase 33 benchmark matrix, produced 3 synthesis PNGs + SYNTHESIS.md + final 33-REPORT.md with Phase 34 `DirectionSolver` handoff contract pasted verbatim — phase is now CLOSED with a locked interface for Phase 34 to subtype.

## Files created

| File | Lines | Purpose |
|---|---:|---|
| `scripts/benchmark_synthesis.jl` | 563 | Ingest 9 (cfg × start_type) slots, emit SYNTHESIS.md + 3 figures; handles SKIPPED_P8 + MISSING as first-class classes |
| `results/raman/phase33/SYNTHESIS.md` | 106 | Master table (9 rows), exit-code distribution, rejection-cause breakdown by config, per-config narrative, gauge-leak / NaN / P8 audits, accepted-step global statistics |
| `results/raman/phase33/rho_distribution.png` | 273 KB | 3×3 grid of accepted-ρ histograms (mostly "no accepted steps" — that's the finding) |
| `results/raman/phase33/exit_codes.png` | 174 KB | Stacked bar, 3 configs × {CONVERGED_1ST_ORDER_SADDLE, RADIUS_COLLAPSE, SKIPPED_P8} |
| `results/raman/phase33/failure_taxonomy_by_config.png` | 173 KB | Stacked bar, rejection causes per config (40 negative_curvature + 2 nan_at_trial_point totals) |
| `.planning/phases/33-.../33-REPORT.md` | 385 | Final deliverable — Verdict, What Was Built, What Was Found, Comparison vs L-BFGS (axes not dB), Pitfall Audit P1-P8, Phase 34 Handoff (verbatim code), Open Questions |

**Total new content: 1 Julia script + 5 result/report artifacts.** No shared-code edits.

## Exit-code distribution (from Master Table)

| Exit code | Count |
|---|---:|
| `CONVERGED_1ST_ORDER_SADDLE` | 2 |
| `RADIUS_COLLAPSE` | 4 |
| `SKIPPED_P8` | 3 |
| `CONVERGED_2ND_ORDER` | 0 |
| `MAX_ITER` / `MAX_ITER_STALLED` | 0 |
| `NAN_IN_OBJECTIVE` | 0 |
| `GAUGE_LEAK` | 0 |
| **Total** | **9** |

## Verdict (from 33-REPORT.md)

> Phase 33 delivered a safeguarded trust-region Newton optimizer (`optimize_spectral_phase_tr`) with Steihaug truncated-CG inner solve, gauge-projected HVP, 7-way typed exit-code taxonomy, Phase-28 trust-report extension, and a `DirectionSolver` abstract interface frozen for Phase 34. The optimizer ran end-to-end on the 9-slot benchmark matrix (3 configs × 3 start types) without a single silent failure. **Zero `GAUGE_LEAK`. Zero `NAN_IN_OBJECTIVE`. Zero `CONVERGED_2ND_ORDER`.** The Phase-35 saddle-rich landscape hypothesis is **CONFIRMED**: every warm-start that survived the trust gate landed at a point where `λ_min < -1e-6` and where no directional escape lowered J. The cold-start `RADIUS_COLLAPSE` results are honest pessimism — the quadratic model is not trustworthy from zero phase — which is exactly what the ρ test is built to diagnose.

## Deviations from Plan 03

**Matrix reduction** (documented in both SYNTHESIS.md and 33-REPORT.md):
- Plan wrote "12 runs" / "4 configs × 3 start types"; reality is 9 slots (3 × 3) after `bench-04-pareto57` was dropped in Plan 02 (per-row Pareto JLD2 never synced from Mac). Subsequent P8 pre-flight rejected 3 of those 9 slots (bench-01 warm + perturbed with edge_frac ≈ 7.7e-3, bench-03 perturbed with edge_frac ≈ 1.22e-3), leaving 6 executed TR runs.
- All reductions are honest gate actions, not bugs. Documented under "Matrix provenance" in SYNTHESIS.md and the Verdict / Pre-flight Audit sections of the report.

**No code regressions or rule-1-auto-fixes applied.** Synthesis ran clean on first execution after script creation.

## Deferred / not done

- No `log_cost=true` synthesis pass (research open question 1) — deferred because Wave 2 did not produce enough accepted-step data to characterize a healthy ρ distribution at `log_cost=false` baseline. Moved into Phase 34 or a Phase-28 follow-up.
- No Δ₀ sensitivity sweep — flagged as new open question 5 in 33-REPORT.md; explicitly recommended for Phase 34 before the preconditioner work.

## Phase 33 status

**COMPLETE.** Phase 34 is unblocked. The `DirectionSolver` / `SubproblemResult` / `SteihaugSolver` / `solve_subproblem` / `update_radius` contracts are pasted verbatim in 33-REPORT.md §Phase 34 Handoff — a Phase-34 planner can read that one file and have full interface reproduction without diving into `scripts/trust_region_core.jl`.

## Shared-file edit audit (Plans 01→02→03)

None.

- Plan 01: added `scripts/trust_region_core.jl`, `trust_region_telemetry.jl`, `trust_region_optimize.jl`, 2 test files. Zero modifications to `scripts/common.jl`, `raman_optimization.jl`, `phase13_*.jl`, `numerical_trust.jl`, `determinism.jl`, `standard_images.jl`, or `src/**`.
- Plan 02: added `scripts/benchmark_run.jl`, `scripts/benchmark_common.jl`. Zero modifications to any shared file.
- Plan 03: added `scripts/benchmark_synthesis.jl`, the 3 PNGs + SYNTHESIS.md + 33-REPORT.md. Zero modifications to any shared file.

Phase-33 namespace isolation held across all three waves. Rule P1 (per CLAUDE.md §Parallel Session Operation Protocol) was honored throughout.

## Self-Check: PASSED

- `scripts/benchmark_synthesis.jl` — FOUND (563 LOC)
- `results/raman/phase33/SYNTHESIS.md` — FOUND (106 LOC)
- `results/raman/phase33/rho_distribution.png` — FOUND (273 KB, 300 DPI)
- `results/raman/phase33/exit_codes.png` — FOUND (174 KB, 300 DPI)
- `results/raman/phase33/failure_taxonomy_by_config.png` — FOUND (173 KB, 300 DPI)
- `.planning/phases/33-.../33-REPORT.md` — FOUND (385 lines)
- Commit `1fe6a18` (Task 1) — FOUND in git log
- 33-REPORT.md heading count = 10 (>= 7 required)
- 33-REPORT.md P1-P8 disposition lines = 10 (>= 8 required)
- 33-REPORT.md line count = 385 (>= 200 required)
- Master table in SYNTHESIS.md contains all 9 slots — confirmed
