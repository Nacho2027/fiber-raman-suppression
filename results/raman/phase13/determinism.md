# Phase 13 Determinism Check

Generated: 2026-04-16 18:37:05

## Config
- Fiber preset: :SMF28
- P_cont: 0.2 W
- L_fiber: 2.0 m
- Nt: 8192
- time_window: 40 ps
- β_order: 3
- Optimiser: L-BFGS (log-cost) with f_abstol = 0.01 dB
- max_iter: 30

## Environment
- Random.seed!(42) set before each run
- FFTW.set_num_threads(1), BLAS.set_num_threads(1)
- seed=42, max_iter=30, FFTW threads=1, BLAS threads=1, Nt=8192

## Result

- Identical (==): **false**
- max(|phi_a - phi_b|): **1.041031187437095** rad
- J_a: 1.874085306742435e-7    (-67.27 dB)
- J_b: 2.854090037759967e-7    (-65.45 dB)
- J_a / J_b: -1.83 dB

## Verdict

**determinism: FAIL**

## Interpretation

Two runs with identical Random.seed!(42) produce phi_opt differing by up to 1.041 rad and final J differing by -1.83 dB.

**Root cause (suspected):** FFTW plans are built with `FFTW.MEASURE` in src/simulation/simulate_disp_mmf.jl and src/simulation/sensitivity_disp_mmf.jl. MEASURE runs timing microbenchmarks to select the fastest algorithm per plan and the choice is timing-noise-dependent, even on a single thread. Different plans produce bit-different FFT outputs because of floating-point associativity in the reduction order, and L-BFGS amplifies these into different final phi_opt.

**Evidence it is not RNG:** `Random.seed!(42)` is set before each call and neither `optimize_spectral_phase` nor the ODE integrators sample any random numbers.

**Implication for Phase 13 and 14:** Any Hessian-eigendecomposition or sharpness-aware comparison that re-runs an optimization must either (a) replace `FFTW.MEASURE` with `FFTW.ESTIMATE` (deterministic plan choice, possibly slower) or (b) cache the plan via `plan_fft(...; flags=FFTW.WISDOM_ONLY)` after building once, or (c) report a tolerance threshold rather than bit-identity. The existing production pipeline should not be changed; this is a DIAGNOSTIC observation.

This is NOT a bug. It is a known FFTW MEASURE-mode non-determinism that the project has been tolerating unknowingly.

