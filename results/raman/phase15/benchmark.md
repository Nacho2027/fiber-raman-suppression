# Phase 15 Plan 01 — Performance Benchmark: FFTW.MEASURE vs FFTW.ESTIMATE

**Generated:** 2026-04-16T22:39:46.334
**Config:** SMF-28 canonical, L=2.0 m, P=0.2 W, Nt=8192, max_iter=30, seed=42
**Thread pins:** FFTW threads = 1, BLAS threads = 1
**Runs per leg:** 3 timed, each in a fresh Julia subprocess (1 warm-up per leg discarded)
**Timing scope:** only `optimize_spectral_phase` wall time (excludes Julia startup, precompile, setup)

## Wall-time Summary

| Mode          | Run 1 | Run 2 | Run 3 | Mean     | Std      | Slowdown vs MEASURE |
|---------------|-------|-------|-------|----------|----------|---------------------|
| FFTW.MEASURE  | 112.73 s | 111.95 s | 112.01 s | 112.23 s | ±0.43 s | baseline |
| FFTW.ESTIMATE | 136.81 s | 136.44 s | 135.38 s | 136.21 s | ±0.74 s | +21.4% |

## J Final Consistency

| Mode          | J_final (run 1) | J_final (run 2) | J_final (run 3) | max-min |
|---------------|-----------------|-----------------|-----------------|---------|
| FFTW.MEASURE  | 1.705924e-06 | 1.705924e-06 | 1.705924e-06 | 1.055e-13 |
| FFTW.ESTIMATE | 1.705924e-06 | 1.705924e-06 | 1.705924e-06 | 0.000e+00 |

**Empirical cross-process determinism:** if ESTIMATE `max-min` is 0.0, multiple
independent Julia processes converged to bit-identical L-BFGS minima — the
strongest possible reproducibility signal. MEASURE `max-min` > 0.0 shows the
original bug (different processes pick different FFT algorithms → different
numerics → compounded divergence through L-BFGS iterations).

## Iteration Counts

| Mode          | Run 1 iters | Run 2 iters | Run 3 iters |
|---------------|-------------|-------------|-------------|
| FFTW.MEASURE  | 14 | 14 | 14 |
| FFTW.ESTIMATE | 14 | 14 | 14 |

## Interpretation

- **Measured slowdown: +21.4%**. This is the wall-time cost of the
  Phase 15 deterministic-environment guarantee on the canonical SMF-28 config.
- FFTW.ESTIMATE uses a heuristic (no timed microbenchmarks) for plan selection,
  so the chosen algorithm may not always be the fastest variant — but it IS
  always the same variant across runs, which eliminates the plan-selection
  non-determinism observed in Phase 13 Plan 01.
- **Plan-15 acceptance threshold:** +30% slowdown. At +21.4%, the
  cost is within budget — the deterministic fix stays.

## Method

Each timed run is a fresh `julia --project=.` subprocess spawned from the driver
(`scripts/phase15_benchmark.jl`) invoking the worker
(`scripts/_phase15_benchmark_run.jl`). The worker:

1. Pins `FFTW.set_num_threads(1)` and `BLAS.set_num_threads(1)`.
2. Includes the pipeline (`scripts/common.jl` + `scripts/raman_optimization.jl`),
   which triggers precompilation of any stale methods.
3. Sets up the Raman problem (NOT timed).
4. Calls `optimize_spectral_phase` — this, and ONLY this, is timed via `time()`.
5. Prints a single `BENCH_JSON: {...}` line the driver parses.

A warm-up subprocess per leg is discarded so the 3 timed runs reflect the
steady-state optimizer cost, not first-run precompile overhead.

The MEASURE leg is produced by mechanically swapping `flags=FFTW.ESTIMATE` →
`flags=FFTW.MEASURE` in the 4 `src/simulation/*.jl` files (18 sites total:
`simulate_disp_mmf.jl`=4, `simulate_disp_gain_smf.jl`=4, `simulate_disp_gain_mmf.jl`=4,
`sensitivity_disp_mmf.jl`=6), running the leg, then reverting in a `finally`
block. The git working tree is guaranteed clean at exit.

## Raw data

See `results/raman/phase15/benchmark.jld2` — full per-run timings and metadata.
