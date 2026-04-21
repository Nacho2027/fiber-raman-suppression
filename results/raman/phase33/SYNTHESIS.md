# Phase 33 Benchmark Synthesis

**Runs:** 9 (6 TR-executed, 3 SKIPPED_P8, 0 MISSING)
**Configs:** 3 (bench-01-smf28-canonical, bench-02-hnlf-phase21, bench-03-smf28-phase21)
**Start types:** 3 (cold, warm, perturbed)
**Generated:** 2026-04-21T14:42:40.050

> **Matrix provenance.** The original research plan proposed 4 configs × 3 start types = 12 runs. 
> Config `bench-04-pareto57-nphi57` was dropped 2026-04-21 because its per-row warm-start JLD2 was never synced 
> to the burst VM (see `scripts/phase33_benchmark_common.jl`). The remaining 3 configs × 3 start types = 9 slots 
> were executed on the ephemeral burst VM. The Phase-28 edge-fraction pre-flight trust gate (pitfall P8) then 
> aborted 3 of those 9 before the TR optimizer ran, so 6 slots produced `_result.jld2` artifacts and the other 
> 3 produced `trust_report.md` stubs only. These tables and figures render all 9 slots; SKIPPED_P8 rows carry 
> the measured edge fraction instead of optimizer metrics.

## Master Table

| config | start_type | exit_code | J_final | J_final_dB | iterations | hvps | grad_calls | λ_min | λ_max | wall_s |
|--------|------------|-----------|--------:|-----------:|-----------:|-----:|-----------:|------:|------:|-------:|
| bench-01-smf28-canonical | cold | RADIUS_COLLAPSE | 7.746e-01 | -1.11 | 10 | 50 | 1 | -3.031e+02 | 5.474e+02 | 528.6 |
| bench-01-smf28-canonical | warm | SKIPPED_P8 (edge_frac=7.876e-03) | — | — | — | — | — | — | — | — |
| bench-01-smf28-canonical | perturbed | SKIPPED_P8 (edge_frac=7.678e-03) | — | — | — | — | — | — | — | — |
| bench-02-hnlf-phase21 | cold | RADIUS_COLLAPSE | 1.011e-01 | -9.95 | 10 | 178 | 1 | -9.955e-04 | 1.848e-05 | 1064.2 |
| bench-02-hnlf-phase21 | warm | CONVERGED_1ST_ORDER_SADDLE | 2.148e-09 | -86.68 | 0 | 240 | 1 | -1.031e-06 | 7.062e-07 | 232.7 |
| bench-02-hnlf-phase21 | perturbed | CONVERGED_1ST_ORDER_SADDLE | 9.197e-08 | -70.36 | 0 | 139 | 1 | -1.041e-06 | 8.940e-07 | 135.0 |
| bench-03-smf28-phase21 | cold | RADIUS_COLLAPSE | 7.743e-01 | -1.11 | 10 | 95 | 1 | -1.892e-01 | 1.948e-02 | 1645.8 |
| bench-03-smf28-phase21 | warm | RADIUS_COLLAPSE | 2.185e-07 | -66.61 | 10 | 50 | 1 | -2.381e-05 | 1.886e-05 | 49.6 |
| bench-03-smf28-phase21 | perturbed | SKIPPED_P8 (edge_frac=1.215e-03) | — | — | — | — | — | — | — | — |

## Exit-Code Distribution

- `CONVERGED_1ST_ORDER_SADDLE`: 2
- `RADIUS_COLLAPSE`: 4
- `SKIPPED_P8`: 3

## Rejection Cause Summary (all runs combined)

| config | rho_too_small | negative_curvature | boundary_hit | cg_max_iter | nan_at_trial_point |
|--------|--------------:|-------------------:|-------------:|------------:|-------------------:|
| bench-01-smf28-canonical | 0 | 10 | 0 | 0 | 0 |
| bench-02-hnlf-phase21 | 0 | 10 | 0 | 0 | 2 |
| bench-03-smf28-phase21 | 0 | 20 | 0 | 0 | 0 |
| **TOTAL** | 0 | 40 | 0 | 0 | 2 |

## Per-Config Narrative

### bench-01-smf28-canonical
**Fiber:** SMF28, **L:** 2.0 m, **P:** 0.2 W, **Nt:** 8192, **time_window_ps:** 40.0
**Warm-start:** `results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2` — pre-audit canonical (bc_input_ok=false — baseline contrast)

- **cold**: exit=`RADIUS_COLLAPSE`, J=7.746e-01 (-1.11 dB), iters=10, HVPs=50, λ_min=-3.031e+02, λ_max=5.474e+02, wall=528.6s
    - no accepted iterations
- **warm**: SKIPPED_P8 — input-shaped edge_frac=7.876e-03 > threshold 1e-3. No TR run executed.
- **perturbed**: SKIPPED_P8 — input-shaped edge_frac=7.678e-03 > threshold 1e-3. No TR run executed.

### bench-02-hnlf-phase21
**Fiber:** HNLF, **L:** 0.5 m, **P:** 0.01 W, **Nt:** 65536, **time_window_ps:** 320.0
**Warm-start:** `results/raman/phase21/phase13/hnlf_reanchor.jld2` — Phase 21 honest HNLF, J=-86.68 dB, edge_frac=2.2e-4

- **cold**: exit=`RADIUS_COLLAPSE`, J=1.011e-01 (-9.95 dB), iters=10, HVPs=178, λ_min=-9.955e-04, λ_max=1.848e-05, wall=1064.2s
    - no accepted iterations
- **warm**: exit=`CONVERGED_1ST_ORDER_SADDLE`, J=2.148e-09 (-86.68 dB), iters=0, HVPs=240, λ_min=-1.031e-06, λ_max=7.062e-07, wall=232.7s
    - no accepted iterations
- **perturbed**: exit=`CONVERGED_1ST_ORDER_SADDLE`, J=9.197e-08 (-70.36 dB), iters=0, HVPs=139, λ_min=-1.041e-06, λ_max=8.940e-07, wall=135.0s
    - no accepted iterations

### bench-03-smf28-phase21
**Fiber:** SMF28, **L:** 2.0 m, **P:** 0.2 W, **Nt:** 16384, **time_window_ps:** 54.0
**Warm-start:** `results/raman/phase21/phase13/smf28_reanchor.jld2` — Phase 21 honest SMF-28, J=-66.61 dB, edge_frac=8.1e-4

- **cold**: exit=`RADIUS_COLLAPSE`, J=7.743e-01 (-1.11 dB), iters=10, HVPs=95, λ_min=-1.892e-01, λ_max=1.948e-02, wall=1645.8s
    - no accepted iterations
- **warm**: exit=`RADIUS_COLLAPSE`, J=2.185e-07 (-66.61 dB), iters=10, HVPs=50, λ_min=-2.381e-05, λ_max=1.886e-05, wall=49.6s
    - no accepted iterations
- **perturbed**: SKIPPED_P8 — input-shaped edge_frac=1.215e-03 > threshold 1e-3. No TR run executed.

## Gauge-Leak Audit

- **None.** No run exited `GAUGE_LEAK`. Assertion `‖P_null·p‖ ≤ 1e-8·‖p‖` held on every accepted step across all executed runs. ✓

## NaN Audit

- **None.** No run exited `NAN_IN_OBJECTIVE`. ✓

> **Telemetry caveat.** Two `CONVERGED_1ST_ORDER_SADDLE` runs (bench-02 warm, bench-02 perturbed) log a single 
> `nan_at_trial_point` row in the rejection breakdown. This is the *terminal diagnostic record* pushed by the 
> λ-probe branch at iter 0 (see `_optimize_tr_core` at trust_region_optimize.jl line ~376): when the gradient 
> was already below `g_tol` on entry, the outer loop recorded a zero-step-size row with `ρ=NaN` for visibility. 
> No trial point actually NaN'd; the exit code `CONVERGED_1ST_ORDER_SADDLE` is authoritative.

## Pre-flight (P8) Audit

The Phase-28 edge-fraction gate aborted 3 slots before the TR optimizer ran. This is the gate working as designed — those pulses have already walked off the attenuator and any optimizer result would be contaminated (see 33-RESEARCH.md §P8).

- bench-01-smf28-canonical/warm: edge_frac=7.876e-03 (> 1e-3 threshold)
- bench-01-smf28-canonical/perturbed: edge_frac=7.678e-03 (> 1e-3 threshold)
- bench-03-smf28-phase21/perturbed: edge_frac=1.215e-03 (> 1e-3 threshold)

## Accepted-step Statistics (across all executed runs)

- No run produced an accepted step. All 6 executed runs exited before committing to any update 
  (4 × `RADIUS_COLLAPSE` with 10 iterations of rejections; 2 × `CONVERGED_1ST_ORDER_SADDLE` at iter 0).
- This is consistent with the Phase 35 saddle-dominated-landscape hypothesis: from both cold φ=0 
  initializations and Phase-21 honest warm-starts, TR cannot find an improving direction that its 
  quadratic model trusts to predict.

