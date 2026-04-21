---
phase: 29-performance-modeling-and-roofline-audit-for-the-fft-adjoint-
verified: 2026-04-21T13:50:00Z
status: passed
score: 7/7 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: passed
  previous_score: 7/7
  gaps_closed: []
  gaps_remaining: []
  regressions: []
  notes: |
    Previous pass was a SCOPE-LOCK acceptance — apparatus present, numeric
    execution deferred to a burst-VM pass. This re-verification confirms the
    local Mac execution pass (commit 53decda) now produces the full numeric
    artifact set. Three real bugs were found and fixed during execution
    (missing MultiModeNoise import, ODESolution broadcasting, JSON3-NaN).
    Report stubs for Roofline Regimes + Recommendations are now fully
    populated from measured data. All requirements now backed by numbers,
    not just apparatus.
---

# Phase 29: Performance Modeling and Roofline Audit Verification Report

**Phase Goal:** Turn the performance-modeling seed into an execution-ready benchmark phase with explicit kernels, bottleneck hypotheses, measurement protocol, and decision criteria for when tuning or more hardware is actually worth it.

**Verified:** 2026-04-21T13:50:00Z
**Status:** passed
**Re-verification:** Yes — post local-execution pass (commit 53decda)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every performance kernel (FFT, Kerr tullio, Raman tullio, forward RHS, adjoint RHS) has a reproducible median-of-N wall-time measurement at Nt=8192, M=1 | VERIFIED | `results/phase29/kernels.jld2` `results_table` contains 10 entries (A_fft × 6 FFTW thread counts + B_kerr_tullio + C_raman_conv + D_forward_rhs + E_adjoint_rhs). Each entry is a NamedTuple with `time_median_s`, `time_runs` (5 samples), `reps_per_block`, `throughput_gb_s`, `plan_flags`. Sample: `B_kerr_tullio.time_median_s = 0.004751`, 5 runs in `time_runs`. Canonical config `nt=8192, m=1, p_cont_w=0.2, l_fiber_m=2.0, seed=42`. |
| 2 | Each measured kernel has a modeled arithmetic intensity (FLOP/byte) and is labeled MEMORY_BOUND / COMPUTE_BOUND / SERIAL_BOUND against a captured hardware roofline | VERIFIED | `29-REPORT.md` lines 35–50 "Roofline Regimes" table populated with real AI values: FFT=1.02, Kerr=0.06, Raman=1.42, Forward-RHS=1.69, Adjoint-RHS=2.64. All classified MEMORY_BOUND. Ceiling 300 GB/s (Apple M3 Max). Utilization column ranges 0.1–2.1%. Not a stub — arithmetic per kernel uses `assemble_roofline_memo` from `phase29_roofline_model.jl`. |
| 3 | Forward-solve, adjoint-solve, and full cost_and_gradient wall times are measured across Julia thread counts {1,2,4,8,16,22} in fresh subprocesses and fit to an Amdahl model | VERIFIED | `results/phase29/solves.jld2` `solves` dict has 18 keys (3 modes × 6 thread counts), each a Vector{Float64} of 3 timed runs. `amdahl_fits.json` gives p=0.000 (forward), p=0.000 (adjoint), p=0.0496 (full_cg); RMSE 5.5e-2 / 3.2e-2 / 3.9e-2. `solve_bench.log` shows 72 fresh-subprocess spawns (`┌ Info: spawn` lines) with WARMUP + RUN-1/2/3 tags per (mode, n_threads). |
| 4 | The final `29-REPORT.md` opens with an Executive Verdict naming the dominant bottleneck and a one-line recommendation | VERIFIED | `29-REPORT.md` line 6–8: `## Executive Verdict` names "SERIAL_BOUND (orchestration + single-threaded RHS dominate)", cites measured p=0.000, recommends `"do not pay for more than 4 burst-VM threads… invest tuning effort in the FFT plan and per-RHS allocation path"`. No longer deferred. |
| 5 | The Phase 15 deterministic invariant (FFTW.ESTIMATE + FFTW/BLAS threads=1) is preserved for all src/ code | VERIFIED | `git diff HEAD~1 HEAD -- src/` empty for the bugfix commit (53decda) and for the phase-29 run commits. `julia --project=. test/test_determinism.jl` exits 0 with **7/7 passing in 26.9s**; log shows `max(|Δφ|) = 0.000e+00 rad (must be 0.0)`. Phase 29 drivers vary FFTW state locally only in Block A. |
| 6 | Every pure analysis function in `phase29_roofline_model.jl` has a unit test with a canned numeric answer | VERIFIED | `julia --project=. test/test_phase29_roofline.jl` exits 0 with **43/43 passing in 0.6s**. Covers `arithmetic_intensity`, `roofline_bound`, `fit_amdahl` (synthetic p=0.9 recovery to atol=1e-10), `fit_gustafson`, `kernel_regime_verdict`, `assemble_roofline_memo`. |
| 7 | The report recommends concrete tuning targets (which kernels are worth tuning, where -t 22 genuinely helps) | VERIFIED | `29-REPORT.md` lines 53–58 "Recommendations" now **populated from measured data** (no longer TODO): (1) keep FFTW.set_num_threads(1) — 16.3x anti-scaling at n_fftw≥2; (2) production `-t 1` or `-t 2`, speedup ceiling 1.00x; (3) DO NOT use c3-highcpu-22 for canonical M=1 SMF-28 (speedup ≤1.1x); (4) next tuning target = adjoint RHS, 3.3x forward (945 vs 288 µs), cause = ODESolution interpolation. |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `scripts/phase29_bench_kernels.jl` | VERIFIED | 458 lines (was 457, +1 line for `using MultiModeNoise:` import added in 53decda). Canonical config hardcoded. Parse-clean. |
| `scripts/phase29_bench_solves.jl` | VERIFIED | 154 lines (was 149, +5 for NaN/null coercion added in 53decda). P29S_THREAD_COUNTS covers full {1,2,4,8,16,22} ladder. |
| `scripts/_phase29_bench_solves_run.jl` | VERIFIED | 151 lines (was 139, +12 for broadcasting fix + NaN→nothing JSON coercion). Three distinct call paths (forward / adjoint / full_cg) intact. |
| `scripts/phase29_roofline_model.jl` | VERIFIED | 219 lines, unchanged. 6 exported functions all tested. |
| `scripts/phase29_report.jl` | VERIFIED | 328 lines (was 172, +156 for populated Roofline Regimes + Recommendations builders). Consumes kernels.jld2 + solves.jld2 + hw_profile.json + amdahl_fits.json. |
| `test/test_phase29_roofline.jl` | VERIFIED | 104 lines, 43/43 tests passing. |
| `results/phase29/.gitkeep` | VERIFIED | Present as directory anchor. |
| `results/phase29/kernels.jld2` | VERIFIED (NEW) | 27 KB, 10-entry `results_table` plus `hw_profile`, `fftw_thread_sweep`, canonical-config keys. |
| `results/phase29/solves.jld2` | VERIFIED (NEW) | 12 KB, 18-key `solves` dict (3 modes × 6 threads × 3 runs). |
| `results/phase29/amdahl_fits.json` | VERIFIED (NEW) | 1381 bytes, three mode blocks with `p`, `speedup_inf`, `rmse`, `n_threads[]`, `median_s[]`. |
| `results/phase29/hw_profile.json` | VERIFIED (NEW) | Apple M3 Max, 12 cores, 48 GB, git=c34ac61, FFTW=1. |
| `results/phase29/roofline.md` | VERIFIED (NEW) | 60 lines, mirror of 29-REPORT.md content. |
| `results/phase29/kernel_bench.log` | VERIFIED (NEW) | 71 lines capturing Block A–E timings. |
| `results/phase29/solve_bench.log` | VERIFIED (NEW) | ~420 lines capturing 72 subprocess spawns + Amdahl fit lines. |
| `.planning/phases/29-.../29-REPORT.md` | VERIFIED | 60 lines, fully populated — Executive Verdict names bottleneck, Kernel Timings table, Amdahl Fits, Roofline Regimes, 4 Recommendations. No TODO stubs remain. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| phase29_bench_kernels.jl | setup_raman_problem | include+call | WIRED | Kernel log shows "Setup complete: Nt=8192, M=1" |
| phase29_bench_kernels.jl | get_p_disp_mmf / get_p_adjoint_disp_mmf | MultiModeNoise import | WIRED | Explicit import added in 53decda; Block D (`288 µs/call`) + Block E (`945 µs/call`) executed |
| phase29_bench_solves.jl | _phase29_bench_solves_run.jl | subprocess | WIRED | solve_bench.log shows 72 `┌ Info: spawn` entries with mode/tag/n_threads |
| phase29_report.jl | phase29_roofline_model.jl | include + assemble_roofline_memo | WIRED | Report sections populated with real AI / ceiling / regime outputs |
| phase29_report.jl | kernels.jld2 / solves.jld2 / amdahl_fits.json / hw_profile.json | JLD2.load / JSON3 | WIRED | All four files consumed and cited in generated report |
| test_phase29_roofline.jl | phase29_roofline_model.jl | include | WIRED | 43/43 tests |

### Data-Flow Trace (Level 4)

| Artifact | Data Source | Produces Real Data | Status |
|----------|-------------|--------------------|--------|
| 29-REPORT.md Executive Verdict | phase29_report.jl → amdahl_fits.json (`p` values) | p=0.000/0.000/0.0496 (real fits from 18 subprocess runs × 3 samples) | FLOWING |
| 29-REPORT.md Kernel Timings table | kernels.jld2 results_table | 10 NamedTuples with time_median_s from 100–500 reps each | FLOWING |
| 29-REPORT.md Amdahl Fits | amdahl_fits.json | 3 mode blocks with non-trivial RMSE values | FLOWING |
| 29-REPORT.md Roofline Regimes | roofline_model.jl + kernels.jld2 + hw_profile.json | AI values 0.06–2.64, ceiling 300 GB/s keyed off Apple M3 Max | FLOWING |
| 29-REPORT.md Recommendations | Computed from measured data (16.3x anti-scaling; 3.3x adjoint/forward ratio) | Numeric ratios derived from kernel medians + Amdahl fits | FLOWING |

All user-visible report sections trace back to on-disk numeric artifacts; no hardcoded defaults or placeholder text.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase 29 unit tests pass | `julia --project=. test/test_phase29_roofline.jl` | `Phase 29 roofline model \| 43 43 0.6s` | PASS |
| Phase 15 determinism invariant preserved | `julia --project=. test/test_determinism.jl` | `7 7 26.9s`; max(\|Δφ\|)=0 | PASS |
| No src/ changes in 53decda bugfix commit | `git diff --name-only HEAD~1 HEAD \| grep ^src/` | empty (NO_SRC_CHANGES) | PASS |
| kernels.jld2 has real data | load + inspect results_table | 10-entry dict, 5-sample time_runs per entry | PASS |
| solves.jld2 has full thread ladder | load + inspect solves dict | 18 keys = 3 modes × 6 threads, 3 runs each | PASS |
| amdahl_fits.json well-formed | parse JSON | 3 modes each with p, rmse, speedup_inf, median_s[] | PASS |
| Report contains no TODO stubs | grep TODO/placeholder in 29-REPORT.md | no matches | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| NMDS-PERF-01 | 29-01 | Kernel-level median-of-N wall time at canonical config, persisted to kernels.jld2 + hw_profile.json | SATISFIED | `results/phase29/kernels.jld2` (27 KB) + `hw_profile.json` both present; 10 kernel entries with `time_median_s` over 5 runs at Nt=8192 M=1 seed=42. Report §Kernel Timings cites measured values. |
| NMDS-PERF-02 | 29-01 | Forward/adjoint/full_cg wall times across threads {1,2,4,8,16,22} in fresh subprocesses with 3 distinct quantities | SATISFIED | `solves.jld2` contains 18 distinct (mode, n_threads) keys with 3 samples each; `solve_bench.log` shows 72 fresh-subprocess spawns; three modes use three DISTINCT call paths (solve_disp_mmf, solve_adjoint_disp_mmf with pre-captured adjoint seed, cost_and_gradient). |
| NMDS-PERF-03 | 29-01 | Amdahl fits (p, speedup_inf, rmse) persisted to amdahl_fits.json | SATISFIED | `amdahl_fits.json` has three mode blocks: forward (p=0.000, speedup_inf=1.0, rmse=0.0551), adjoint (p=0.000, speedup_inf=1.0, rmse=0.0320), full_cg (p=0.0496, speedup_inf=1.052, rmse=0.0394). `fit_amdahl` unit-tested against synthetic p=0.9 to atol=1e-10. |
| NMDS-PERF-04 | 29-01 | Each kernel labeled MEMORY/COMPUTE/SERIAL_BOUND against captured hardware roofline; report opens with Executive Verdict + -t N recommendation | SATISFIED | Report §Roofline Regimes has 10 rows, all classified against Apple M3 Max peak (FLOP/s=1e12, BW=3e11 B/s). Executive Verdict names SERIAL_BOUND as dominant across orchestration and prescribes `-t 4` ceiling. |

All 4 requirement IDs declared in PLAN frontmatter match REQUIREMENTS.md §v3.0 and ROADMAP.md. No orphaned requirements. Burst-VM-specific rooflines (e2-standard-4, c3-highcpu-22) are referenced in Recommendation #3; generating the full burst-VM capture is explicitly out-of-scope per the local-execution contract.

### Anti-Patterns Found

No blockers. Previous "intentional placeholder" text in 29-REPORT.md has been fully replaced with data-derived content. The report no longer contains `deferred` markers, `TODO`, or `will be populated` phrases. Grep for `TODO|FIXME|placeholder|deferred` in `29-REPORT.md` → zero matches.

### Human Verification Required

None. This is a measurement / modeling phase; all deliverables are numeric artifacts and markdown, not UX.

### Gaps Summary

No gaps. Phase 29 goal fully achieved:

1. **Execution-ready benchmark phase**: Five kernels × FFTW thread sweep + three solve modes × six Julia thread counts — all executed locally on Apple M3 Max with numeric results on disk.
2. **Explicit kernels**: Locked before execution (Blocks A–E); kernel log + JLD2 confirm all five measured.
3. **Bottleneck hypotheses**: Arithmetic intensity + roofline regime + Amdahl fits turn hypotheses into data-backed verdicts. All kernels empirically MEMORY_BOUND.
4. **Measurement protocol**: Canonical config, subprocess isolation, N=5 / N=3+1 sample counts, plan-flag discipline all encoded in drivers and executed as specified.
5. **Decision criteria**: Report §Recommendations gives four data-backed prescriptions (FFT stays single-threaded; production `-t 1..2`; skip c3-highcpu-22 for M=1; next tuning target = adjoint interpolation).

Phase 15 determinism invariant confirmed still holding (test passes with bit-identical φ). Local execution surfaced three real bugs that a scope-lock-only pass would have missed — these are now fixed and the bench is reproducible end-to-end.

Burst-VM execution (to cross-validate e2-standard-4 / c3-highcpu-22 rooflines) remains a legitimate follow-on but is explicitly descoped from this phase per CLAUDE.md cost discipline; the Mac-side numbers answer the goal's decision questions ("when is tuning / more hardware worth it") by themselves: the speedup ceiling ≤1.1x means paying for c3-highcpu-22 is unjustified for the canonical M=1 workload.

---

_Verified: 2026-04-21T13:50:00Z_
_Verifier: Claude (gsd-verifier)_
