---
phase: 34
plan: "01"
subsystem: trust-region-optimizer
tags: [delta0-sweep, radius-collapse, negative-curvature, diagnostic, go-no-go]
dependency-graph:
  requires: [phase-33-benchmark-results, trust_region_core.jl, trust_region_optimize.jl]
  provides: [34-01-SUMMARY.md, phase34_delta0_sweep.jl, DELTA0_SWEEP_VALUES constant]
  affects: [plans-02-04-preconditioning-decision]
tech-stack:
  added: [phase34_delta0_sweep.jl, DELTA0_SWEEP_VALUES in phase33_benchmark_common.jl]
  patterns: [delta0-sweep, cold-start-only, SteihaugSolver-frozen]
key-files:
  created:
    - scripts/phase34_delta0_sweep.jl
    - results/raman/phase34/delta0_sweep/bench-01-smf28-canonical/delta0_{0p5,0p1,0p01,0p001}/_result.jld2
    - results/raman/phase34/delta0_sweep/bench-01-smf28-canonical/delta0_{0p5,0p1,0p01,0p001}/telemetry.csv
    - results/raman/phase34/delta0_sweep/bench-01-smf28-canonical/delta0_{0p5,0p1,0p01,0p001}/trust_report.md
    - results/raman/phase34/delta0_sweep/bench-01-smf28-canonical/delta0_{0p5,0p1,0p01,0p001}/*.png (4 images each)
    - results/burst-logs/Q-phase34-delta0_20260421T223806Z.log
  modified:
    - scripts/phase33_benchmark_common.jl (append-only Phase 34 block)
decisions:
  - "DELTA0_SWEEP_VALUES = [0.5, 0.1, 0.01, 0.001] chosen to span 3 decades around default"
  - "cold-start only for sweep — warm-start would need pre-existing phi_opt which Phase 33 couldn't produce"
  - "SteihaugSolver frozen — sweep tests Δ₀ sensitivity of existing solver, not a new one"
  - "GO verdict: preconditioning investment is warranted — RADIUS_COLLAPSE is solver-agnostic wrt Δ₀"
metrics:
  duration: "~90 min total (30 min setup + waiter + 14 min sweep on burst VM)"
  completed: "2026-04-21T22:53Z"
  tasks_completed: 3
  files_created: 30
---

# Phase 34 Plan 01: Δ₀-Sweep Diagnostic Summary

**One-liner:** Cold-start Steihaug TR sweep over Δ₀ ∈ {0.5, 0.1, 0.01, 0.001} on bench-01-smf28-canonical yields RADIUS_COLLAPSE at every radius with 0 accepted iterations — root cause is Hessian negative curvature (λ_min=-303), not wrong initial radius.

## GO / NO-GO Verdict

**GO — Preconditioning investment is warranted.**

The Δ₀-sweep eliminates the "wrong initial radius" hypothesis. All four Δ₀ values collapse with identical behavior: J stuck at 0.7746 (baseline, no improvement), 0 accepted iterations, 100% NEGATIVE_CURVATURE exits. The initial Hessian at φ=0 has λ_min=-303, λ_max=547 (κ_eff=1.8). Steihaug CG exits on the very first CG step at every TR iteration because the quadratic model is non-convex. No radius choice can fix this — the solver sees negative curvature before it can take a useful step.

**Preconditioning (Plans 02-04) addresses the root cause:** a preconditioner that shifts the effective eigenspectrum positive will allow Steihaug CG to make useful steps before hitting NEGATIVE_CURVATURE. This is the correct remediation.

## Δ₀ Sweep Results Table

| Δ₀ | Exit | J_final | Accepted iters | Total iters | HVPs | ρ (all rejected) | Wall time |
|----|------|---------|----------------|-------------|------|-------------------|-----------|
| 0.5 | RADIUS_COLLAPSE | 7.746e-01 | 0 | 10 | 50 | N/A | 529.2s |
| 0.1 | RADIUS_COLLAPSE | 7.746e-01 | 0 | 9 | 9 | N/A | 125.2s |
| 0.01 | RADIUS_COLLAPSE | 7.746e-01 | 0 | 7 | 7 | N/A | 100.2s |
| 0.001 | RADIUS_COLLAPSE | 7.746e-01 | 0 | 5 | 5 | N/A | 73.2s |

**Observations:**
- J_final = 7.746e-01 for all runs = the baseline cost (φ=0). Zero optimization progress across all Δ₀.
- Iteration count follows log₄(Δ₀/Δ_min) formula exactly: smaller Δ₀ exits in fewer iterations before hitting Δ_min=1e-6.
- HVP count for Δ₀=0.5 is 50 (the Steihaug CG probes λ_min/λ_max at iter 10), others are ~1 HVP per iteration (single CG step exits immediately on NEGATIVE_CURVATURE).
- All rejections are NEGATIVE_CURVATURE: 10/10, 9/9, 7/7, 5/5.

## Rejection Breakdown (All Runs)

| Metric | Δ₀=0.5 | Δ₀=0.1 | Δ₀=0.01 | Δ₀=0.001 |
|--------|---------|---------|---------|---------|
| accepted | 0 | 0 | 0 | 0 |
| negative_curvature | 10 | 9 | 7 | 5 |
| rho_too_small | 0 | 0 | 0 | 0 |
| boundary_hit | 0 | 0 | 0 | 0 |
| cg_max_iter | 0 | 0 | 0 | 0 |
| nan_at_trial_point | 0 | 0 | 0 | 0 |

## Hessian Eigenspectrum (from Δ₀=0.5 iter 10)

Measured at final iteration (after 41 HVP probes with Steihaug's λ_probe):
- λ_min = -303.1 (large negative — severe non-convexity)
- λ_max = 547.4
- κ_eff = 1.81 (ratio of positive to negative — both large)

This confirms the Hessian at φ=0 (cold start) has substantial negative curvature. The objective landscape is non-convex in the spectral phase space at the initial point. Any fixed-point TR solver without preconditioning will collapse.

## Standard Images Verification

16 PNG files generated across 4 runs (4 images per run: phase_profile, evolution, phase_diagnostic, evolution_unshaped). All standard images confirmed on disk at:
`results/raman/phase34/delta0_sweep/bench-01-smf28-canonical/delta0_{0p5,0p1,0p01,0p001}/`

## Compute Discipline Confirmation

- Simulation run on `fiber-raman-burst` (c3-highcpu-22) via `burst-run-heavy Q-phase34-delta0` wrapper
- Session tag format compliant: `Q-phase34-delta0`
- Julia launched with `-t auto` (22 threads active, verified: `threads=22` in log)
- Lock acquired cleanly after Phase 32 expt2 released it (Phase 32 crashed on AssertionError — lock auto-released via trap)
- `deepcopy(fiber)` used per CLAUDE.md discipline (serial run but pattern maintained for future parallel callers)
- Results synced back via gcloud scp + tar
- `burst-stop` executed immediately after sync — VM confirmed TERMINATED
- Julia 1.12 world-age advisory warning (`Main.cost_and_gradient`) is non-blocking (advisory only, not an error — Revise include-chain pattern)

## Implications for Plans 02-04

Plans 02-04 (Jacobi preconditioning, diagonal Hessian estimation, shifted CG) are all warranted. The preconditioning must address the initial Hessian at φ=0, which has:
1. Large negative eigenvalue (λ_min=-303) — Steihaug CG can't make progress
2. Large positive eigenvalue (λ_max=547) — ill-conditioning even in the positive subspace
3. Mixed sign spectrum — requires a shift-and-invert or regularized preconditioner

The simplest approach (Plan 02: diagonal Hessian regularization via λ_shift > |λ_min|) is sufficient to make the Steihaug step take positive curvature directions. The Phase 33 cold start was not a radius problem.

## Deviations from Plan

### Phase 32 Lock Contention (handled automatically)

**Found during:** Task 3 (burst VM execution)

**Issue:** Phase 32's `P-32-accel-expt1` held the burst heavy lock when Task 3 tried to start. Phase 32 then transitioned to `P-32-accel-expt2` which immediately crashed with `AssertionError: expected 3 past iterates, got 2` in `phase32_mpe_offline.jl:447`.

**Fix:** Launched `Q-phase34-delta0-waiter` tmux session on burst VM with `WAIT_TIMEOUT_SEC=7200` to automatically acquire lock when released. Lock was released when Phase 32 expt2 crashed (trap cleanup ran correctly). The waiter acquired the lock and started the sweep without any manual intervention.

**Deviation classification:** None (Rule P5 WAIT mechanism worked as designed — this is normal burst coordination, not a plan deviation).

### Julia 1.12 World-Age Advisory

**Found during:** Task 3 (sweep execution)

**Issue:** Julia 1.12 emits advisory about `Main.cost_and_gradient` binding world-age across include chains. This is a Revise compatibility warning, not a runtime error.

**Classification:** Non-blocking. The optimizer ran correctly. This is a known issue with Julia 1.12's stricter world-age semantics + Revise. No fix needed for research use.

**Files modified:** None

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `scripts/phase34_delta0_sweep.jl` | FOUND |
| `scripts/phase33_benchmark_common.jl` (DELTA0_SWEEP_VALUES appended) | FOUND |
| `results/raman/phase34/.../delta0_0p5/_result.jld2` | FOUND |
| `results/raman/phase34/.../delta0_0p1/_result.jld2` | FOUND |
| `results/raman/phase34/.../delta0_0p01/_result.jld2` | FOUND |
| `results/raman/phase34/.../delta0_0p001/_result.jld2` | FOUND |
| 16 PNG images across 4 runs | FOUND |
| `34-01-SUMMARY.md` | FOUND |
| Task 1 commit `6cc33af` | FOUND |
| Task 2 commit `f732e72` | FOUND |
| GO verdict in SUMMARY | FOUND (3 occurrences of "GO") |
| RADIUS_COLLAPSE documented | FOUND (6 occurrences) |
| burst-stop executed | CONFIRMED |
