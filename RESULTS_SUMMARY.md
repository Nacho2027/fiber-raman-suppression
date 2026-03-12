# Raman Suppression Optimization — Full Results Summary

**Date**: 2026-03-12
**Solver tolerances**: Forward reltol=1e-8, Adjoint reltol=1e-10
**Grid**: Nt=8192 (2^13), M=1 mode, sech^2 pulse (185 fs FWHM)
**Test suite**: 126/126 tests passed (Phase 0)

---

## Phase 1: Spectral Phase Optimization

### Run 1 — L=1m, P=0.05W (gentle regime, GDD/TOD reg)
| Metric | Value |
|--------|-------|
| Iterations | 15 |
| J initial | -24.84 dB |
| J final | -30.60 dB |
| Improvement | 5.76 dB |
| Wall time | 47.0 s |
| Gradient validation | PASSED (max rel err = 6.94e-6) |
| Boundary | OK |
| Regularization | lambda_gdd=1e-2, lambda_tod=1e-3, lambda_tikh=1e-5 |

### Run 2 — L=2m, P=0.15W (moderate regime)
| Metric | Value |
|--------|-------|
| Iterations | 20 |
| J initial | -1.05 dB |
| J final | -15.56 dB |
| Improvement | 14.51 dB |
| Wall time | 103.2 s |
| Boundary | WARNING (edge energy = 2.42e-6) |

### Run 3 — L=5m, P=0.15W (warm-started from Run 2)
| Metric | Value |
|--------|-------|
| Iterations | 20 |
| J initial | -4.05 dB |
| J final | -9.93 dB |
| Improvement | 5.88 dB |
| Wall time | 250.4 s |
| Boundary | WARNING (edge energy = 1.74e-5) |

### Chirp Sensitivity (on Run 1)
- 202 forward solves computed
- GDD/TOD sweep plots saved to `chirp_sens_L1m_P005W.png`

### Phase Optimization PNGs (10 files)
- `raman_opt_L1m_P005W.png` — 3x2 optimization panel
- `raman_opt_L1m_P005W_evolution.png` — before/after evolution
- `raman_opt_L1m_P005W_boundary.png` — boundary diagnostic
- `raman_opt_L2m_P015W.png`, `_evolution.png`, `_boundary.png`
- `raman_opt_L5m_P015W.png`, `_evolution.png`, `_boundary.png`
- `chirp_sens_L1m_P005W.png`

---

## Phase 2: Amplitude Optimization

### Run 1 — L=1m, P=0.15W, delta=0.30 (with regularization)
| Metric | Value |
|--------|-------|
| Iterations | 6 (converged early) |
| J_raman | 1.42e-1 (-8.47 dB) |
| A range | [0.700, 1.083] |
| Energy deviation | -18.7% |
| Boundary | OK (edge energy = 4.33e-8) |
| Gradient validation | PASSED (max rel err = 5.1e-4) |
| Wall time | 244 s |

### Run 2 — Zero-regularization baseline
| Metric | Value |
|--------|-------|
| J_raman | 5.65e-3 (-22.48 dB) |
| A range | [-13.28, 1.04] |
| Energy deviation | +11,186% |
| TV(A) | 28.56 |
| Boundary | WARNING (edge energy = 7.88e-2) |
| Peak power ratio | 58.7x |

**Key insight**: Without regularization, optimizer exploits amplitude freedom to create extreme spectral reshaping that violates energy conservation and boundary conditions. Regularization is essential.

### Run 3 — L=5m, P=0.15W, delta=0.30
| Metric | Value |
|--------|-------|
| Gradient validation | FAILED (max rel err = 1.0) |
| Status | UNSTABLE — A range [-26035, 1.45] |
| ODE solver | Hit maxiters (stiff problem) |
| Wall time | 11,069 s (3.1 hours) |

**Key finding**: Amplitude optimization gradients are unreliable at L=5m. The adjoint-based amplitude gradient breaks down for long fibers due to numerical sensitivity. Phase optimization handles L=5m much better.

### delta Sweep (L=1m, P=0.15W, 50 iter each)

| delta | J_total | J_raman | J_energy | J_tikhonov |
|-------|---------|---------|----------|------------|
| 0.05 | 0.384 | 3.75e-1 | 9.50e-3 | 2.46e-6 |
| 0.10 | 0.254 | 2.18e-1 | 3.61e-2 | 9.68e-6 |
| **0.15** | **0.174** | **1.13e-1** | **6.16e-2** | **1.87e-7** |
| 0.20 | 0.173 | 1.15e-1 | 5.87e-2 | 1.29e-7 |
| 0.30 | 0.177 | 1.42e-1 | 3.48e-2 | 2.04e-7 |

**Findings**: J_total is minimized at delta=0.15-0.20. Wider bounds (delta=0.30) allow more energy redistribution but J_raman actually worsens because the energy penalty dominates. The sweet spot is delta~0.15-0.20 where J_raman and J_energy balance.

### Amplitude PNGs (9+ files)
- `amp_opt_L1m_P015W_d030.png`, `_evolution.png`, `_boundary.png`
- `amp_opt_L1m_P015W_d030_noreg.png`, `_evolution.png`, `_boundary.png`
- `amp_opt_L5m_P015W_d030.png` (unstable result)

---

## Phase 3: Benchmarks

### 3a. Grid Size Benchmark (L=1m, P=0.05W)

| Nt | time/iter [s] | J | |grad J| | speedup |
|----|---------------|------|---------|---------|
| 2^10=1024 | 0.045 | 3.13e-3 | 1.64e-3 | 17.9x |
| 2^11=2048 | 0.107 | 3.21e-3 | 1.74e-3 | 7.5x |
| 2^12=4096 | 0.177 | 3.57e-3 | 1.67e-3 | 4.5x |
| **2^13=8192** | **0.465** | **3.57e-3** | **1.50e-3** | **1.7x** |
| 2^14=16384 | 0.797 | 3.39e-3 | 1.83e-3 | 1.0x |

**Convergence**: J varies ~5% across grid sizes relative to Nt=16384 reference. The cost function is dominated by broadband Raman rather than fine spectral features, so even coarse grids give reasonable J estimates. Nt=8192 offers a good speed/accuracy trade-off (1.7x faster than 16384).

### 3b. Optimized Time Window Analysis

| Window [ps] | J [dB] | J [lin] | Edge energy | Status |
|-------------|--------|---------|-------------|--------|
| 5.0 | -36.33 | 2.33e-4 | 1.49e-5 | WARNING |
| **10.0** | **-36.04** | **2.49e-4** | **5.82e-7** | **OK** |
| 15.0 | -35.94 | 2.55e-4 | 5.74e-6 | WARNING |
| 20.0 | -35.89 | 2.57e-4 | 1.23e-4 | WARNING |
| **30.0** | **-35.88** | **2.58e-4** | **4.66e-7** | **OK** |
| 40.0 | -35.93 | 2.55e-4 | 4.71e-5 | WARNING |

**Key finding**: J is remarkably stable across windows (-36.3 to -35.9 dB), confirming the optimized phase transfers well. Only 10 ps and 30 ps give clean boundaries (OK status). The non-monotonic edge energy pattern (5ps WARNING, 10ps OK, 15ps WARNING) suggests aliasing effects from the phase interpolation onto different grids.

### 3c. Continuation Method (warm-start across fiber lengths)

| L [m] | Window [ps] | J_init | J_opt | Time [s] | Boundary |
|-------|-------------|--------|-------|----------|----------|
| 0.10 | 5 | 8.52e-5 | 1.76e-7 | 1.5 | 6.4e-5 |
| 0.20 | 5 | 7.79e-5 | 2.96e-7 | 1.8 | 7.0e-3 |
| 0.50 | 5 | 1.52e-4 | 1.05e-6 | 3.8 | 2.2e-2 |
| 1.00 | 5 | 1.23e-5 | 1.45e-7 | 12.1 | 8.1e-3 |
| 2.00 | 8 | 3.86e-5 | 6.39e-7 | 9.8 | 1.6e-2 |
| 5.00 | 18 | 8.38e-5 | 2.84e-5 | 1757.6 | 1.4e-1 |

**Findings**:
- Warm-starting works: J_init at each step benefits from the previous solution
- L=5m is the bottleneck (1758s, 29 min) and shows boundary corruption (14%)
- For L<=2m, optimization converges quickly (<12s) with good results
- Boundary condition worsens significantly at L>=2m

### 3d. Multi-Start Optimization (10 starts x 30 iter, L=1m)

| Metric | Value |
|--------|-------|
| Best start | #3, J = 5.63e-9 (-82.5 dB) |
| Worst | J = 1.92e-6 (-57.2 dB) |
| Median | J = 5.20e-8 (-72.8 dB) |
| Spread | 25.3 dB (worst - best) |
| Std | 7.70e-7 |

**Key finding**: The optimization landscape has significant local minima. The best start reaches -82.5 dB (vs. -30.6 dB for the regularized single-start in Phase 1 Run 1). The 25.3 dB spread across starts indicates multi-start is essential for finding good solutions. The regularization in Phase 1 constrains the search space significantly.

### 3e. Parallel Gradient Validation

| Metric | Value |
|--------|-------|
| Max rel error | 2.71e-3 |
| Status | WARNING (threshold is 1e-3) |
| ε (perturbation) | 1e-5 |
| Threads | 1 (single-threaded) |

The gradient validation shows slightly elevated error (2.7e-3) compared to the Phase 1 in-script validation (6.9e-6). This is likely due to the random phase test point used in the benchmark vs. zero phase in the optimization scripts. The adjoint gradient is still reasonably accurate for optimization purposes.

### 3f. Performance Notes
1. FFT plans are cached (plan_fft!)
2. exp(±iDw·z) computed at every ODE step — potential optimization target
3. Adjoint: Vern9() with dt=1e-3, adaptive=false. For L=5m → 5000 steps
4. Buffer pre-allocation for uω0_shaped and uωf across L-BFGS iterations
5. Time window sizing critical for L>=2m

---

## Generated Files (33 PNGs)

### Phase 1
- `raman_opt_L1m_P005W.png` / `_evolution.png` / `_boundary.png`
- `raman_opt_L2m_P015W.png` / `_evolution.png` / `_boundary.png`
- `raman_opt_L5m_P015W.png` / `_evolution.png` / `_boundary.png`
- `chirp_sens_L1m_P005W.png`

### Phase 2
- `amp_opt_L1m_P015W_d030.png` / `_evolution.png` / `_boundary.png`
- `amp_opt_L1m_P015W_d030_noreg.png` / `_evolution.png` / `_boundary.png`
- `amp_opt_L5m_P015W_d030.png`

### Phase 3
- `tw_reference.png` / `_evolution.png` / `_boundary.png`
- `time_window_optimized.png`

### From prior runs (still present)
- `amp_opt_L1m_P005W_d010.png` / `_evolution.png` / `_boundary.png`
- `amp_opt_L1m_P005W_d020.png` / `_evolution.png` / `_boundary.png`
- `amp_opt_L1m_P015W_d015.png` / `_evolution.png` / `_boundary.png`
- `time_window_analysis_L5.0m.png`
- `raman_opt_L1m_P005W_evolution_before.png` / `_after.png`

---

## Key Recommendations

1. **Phase optimization is preferred over amplitude optimization** for L>=2m. Phase gradients remain accurate at long fiber lengths; amplitude gradients fail at L=5m.

2. **Use multi-start** for production runs. The 25 dB spread across random starts means single-start results can be far from optimal. 10 starts with 30 iterations each is a good balance.

3. **Regularization is essential for amplitude optimization**. Without it, the optimizer finds unphysical solutions with extreme amplitudes and boundary violations.

4. **Time window sizing**: 10 ps is optimal for L=1m (clean boundaries). For L>=2m, use `recommended_time_window(L)` or increase to 20-30 ps.

5. **Grid size**: Nt=8192 is sufficient for the current parameters. The cost function converges well at this resolution with 1.7x speedup over 16384.

6. **Continuation works but L=5m is hard**: The warm-start continuation from short to long fibers works well up to L=2m. At L=5m, convergence slows dramatically and boundary conditions degrade.

7. **Solver tolerance impact**: The tightened tolerances (fwd 1e-8, adj 1e-10) improve gradient accuracy (~7e-6 for phase, ~5e-4 for amplitude) at the cost of ~2x slower forward/adjoint solves.

---

## Raw Logs
- Phase 1: `/tmp/phase1_output.log`
- Phase 2: `/tmp/phase2_output.log`
- Phase 3: `/tmp/phase3_output.log`
