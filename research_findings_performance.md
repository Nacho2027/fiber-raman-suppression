# M3 Max Performance Research Findings

**System**: Apple M3 Max (12P + 4E cores), ARM64 (aarch64-apple-darwin)
**Codebase**: MultiModeNoise.jl — GNLSE solver with adjoint-based optimization
**Date**: 2026-03-11

---

## 1. Solver Architecture Analysis

### 1.1 Forward Solver (`disp_mmf!` / `disp_gain_smf!`)

The solver uses **DifferentialEquations.jl** with the **Tsit5()** integrator (Tsitouras 5th-order explicit Runge-Kutta) and `reltol=1e-5`, which is an adaptive-step ODE solver. The RHS function is written in the **interaction picture** to separate fast linear dispersion from slow nonlinear dynamics.

**Per RHS evaluation (each internal Tsit5 substep):**

| Operation | Type | Arrays | Size (Nt=8192, M=1) |
|-----------|------|--------|---------------------|
| `exp(±iDω·z)` | Elementwise complex exp | 2 × (Nt,M) | 2 × 64 KB |
| Forward FFT (`fft_plan_M!`) | In-place FFT, dim 1 | (Nt,M) | 64 KB |
| `@tullio δKt[t,i,j] = γ[i,j,k,l] * (v·v + w·w)` | 4-index tensor contraction | (Nt,M,M) | For M=1: trivial |
| `@tullio αK, βK` contractions | Matrix-vector | (Nt,M) each | 128 KB total |
| Raman convolution: FFT → multiply hRω → IFFT → fftshift | 2 FFTs on (Nt,M,M) + 1 IFFT | (Nt,M,M) | For M=1: 64 KB each |
| `@tullio αR, βR` contractions | Matrix-vector | (Nt,M) each | 128 KB total |
| Inverse FFT (`ifft_plan_M!`) | In-place IFFT, dim 1 | (Nt,M) | 64 KB |
| Self-steepening multiply | Elementwise | (Nt,M) | 64 KB |

**Total per RHS evaluation**: ~6 FFTs (for M=1: 2 on size Nt, 4 on size Nt — actually 2 on (Nt,M,M) which for M=1 are trivially Nt), plus multiple Tullio tensor contractions, plus 2 complex exponentials.

**Complexity per step**: O(6 · Nt·log(Nt)) for FFTs + O(Nt·M⁴) for Tullio contractions.

For M=1 (single-mode, which is what the optimization scripts use), the Tullio contractions reduce to simple elementwise multiplies, so the dominant cost is **6 FFTs of size 8192** plus **2 complex exponentials of size 8192** per RHS eval.

Tsit5 requires **6 RHS evaluations per accepted step** (7 stages, first-same-as-last). With adaptive stepping at `reltol=1e-5`, a typical 1-meter fiber propagation likely takes ~50–200 ODE steps, meaning **300–1200 RHS evaluations** per forward solve.

### 1.2 Adjoint Solver (`adjoint_disp_mmf!`)

The adjoint solver uses **Vern9()** (9th-order Verner method) with **fixed step size** `dt=1e-3` and `adaptive=false`.

**Critical issue**: For L=5m fiber, this means **5000 fixed steps**, each requiring 16 RHS evaluations (Vern9 has 16 stages). That's **80,000 RHS evaluations** for a single adjoint solve — potentially 50–100× more work than the adaptive forward solve.

The adjoint RHS (`adjoint_disp_mmf!`) is more expensive per evaluation than the forward RHS:
- 6+ FFTs per evaluation (similar to forward)
- Additional tensor contractions: `calc_γ_a_b!` involves 4-index contractions
- 4 separate gradient contribution functions, each with FFTs and tensor ops
- Interpolation of forward solution via `ũω(z)` at each step

**Total per adjoint RHS evaluation**: ~12–16 FFTs + multiple 4-index tensor contractions.

### 1.3 Per L-BFGS Iteration Breakdown

| Component | FFT calls (est.) | ODE steps | Wall time contribution |
|-----------|------------------|-----------|----------------------|
| Forward solve (Tsit5, adaptive) | ~600–7200 | 100–1200 | ~20% |
| Adjoint solve (Vern9, fixed dt=1e-3) | ~640,000–1,280,000 | 5000/L_m | **~70–80%** |
| Cost + gradient chain rule | ~2 | 1 | <1% |
| `deepcopy(fiber)` per iteration | 0 | 0 | ~1–2% |

**The adjoint solver dominates runtime.** Its fixed step size is the single largest performance bottleneck.

### 1.4 Full Optimization Pipeline Breakdown

The `raman_optimization.jl` script runs 3 optimization runs (L=1m, L=2m, L=5m) with 15–20 L-BFGS iterations each, plus gradient validation, chirp sensitivity, and visualization. The L=5m run alone has 5000 adjoint steps × 16 stages × 20 iterations = **1.6M adjoint RHS evaluations**.

---

## 2. Quick Wins (implement in <1 hour, no algorithm changes)

### 2a. Check ARM64 vs Rosetta (Priority: CRITICAL, Expected: 0–3× if currently Rosetta)

**How to check:**
```julia
using InteractiveUtils
versioninfo()
```

- **Native ARM64**: shows `macOS (arm64-apple-darwin...)`
- **Rosetta2**: shows `macOS (x86_64-apple-darwin...)` — this means 2–3× penalty

If running under Rosetta, download the native ARM64 Julia installer from julialang.org.

### 2b. FFTW Planning Flags (Priority: HIGH, Expected: 1.5–2× on FFT-bound portions)

**Current code** in `get_p_disp_mmf` and `get_p_disp_gain_smf`:
```julia
fft_plan_M! = plan_fft!(zeros(ComplexF64, Nt, M), 1)
```

This uses the default `FFTW.ESTIMATE` flag, which picks a generic algorithm without benchmarking.

**Recommended change:**
```julia
fft_plan_M! = plan_fft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.MEASURE)
```

For Nt=8192, `FFTW.MEASURE` benchmarks real transforms and selects the fastest. This adds ~1–2 seconds of one-time planning cost but can yield **1.5–2× speedup per FFT call**. Since there are millions of FFT calls across the full suite, this is high-value.

Even better, use **FFTW wisdom caching** to amortize planning cost:
```julia
# At start of script:
wisdom_file = "fftw_wisdom_Nt$(Nt).dat"
if isfile(wisdom_file)
    FFTW.import_wisdom(wisdom_file)
end

# Create plans (will reuse wisdom if available)
fft_plan_M! = plan_fft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.PATIENT)

# After planning, save for future runs:
FFTW.export_wisdom(wisdom_file)
```

**Note on FFTW threading**: For Nt=8192, multithreaded FFTW is **counterproductive** — threading overhead exceeds gains at this moderate size. Keep FFTW single-threaded (`FFTW.set_num_threads(1)`).

### 2c. Replace `exp(1im * ...)` with `cis(...)` in Solver RHS (Priority: MEDIUM, Expected: 1.2–1.5× on exp calls)

**Current code** in `disp_mmf!`:
```julia
@. exp_D_p = exp(1im * Dω * z)
@. exp_D_m = exp(-1im * Dω * z)
```

`exp(1im * x)` computes a full complex exponential (costly). `cis(x) = cos(x) + i·sin(x)` is ~2× faster for purely imaginary arguments.

**Change to:**
```julia
@. exp_D_p = cis(Dω * z)
@. exp_D_m = cis(-Dω * z)
```

This appears in `disp_mmf!`, `disp_gain_smf!`, `adjoint_disp_mmf!`, and all helper functions. The optimization scripts already use `cis()` at the outer level, but the hot inner loops in MultiModeNoise.jl still use `exp()`.

### 2d. Pre-compute `exp_D` at Fixed z Values for Adjoint (Priority: MEDIUM, Expected: 1.1–1.3×)

The adjoint solver uses fixed `dt=1e-3`, so `z` values are known in advance. Instead of computing `exp(1im * Dω * z)` at every RHS evaluation (16 times per step), precompute the values for each z-step and index into them. This eliminates ~80,000 unnecessary `cis()` calls per L-BFGS iteration for L=5m.

### 2e. Set `JULIA_NUM_THREADS=12` (Priority: LOW for current code, but enables future parallelism)

M3 Max has 12 Performance cores + 4 Efficiency cores. The asymmetric design means E-cores can cause scheduling jitter. Set:
```bash
export JULIA_NUM_THREADS=12
```

This primarily helps Tullio's multithreaded contractions (which are already threaded via LoopVectorization). For M=1, the contractions are trivial, so the impact is minimal. For M>1 (multimode), this becomes important.

---

## 3. Medium-Effort Optimizations (1–4 hours)

### 3a. Make the Adjoint Solver Adaptive (Priority: CRITICAL, Expected: 5–50× on adjoint)

**This is the single most impactful change.**

The adjoint solver currently uses:
```julia
solve(prob, Vern9(), dt=1e-3, adaptive=false, saveat=(0, fiber["L"]))
```

For L=5m, this forces 5000 steps regardless of dynamics. The forward solver (Tsit5 with adaptive stepping) typically needs only ~100–200 steps for the same propagation.

**Change to:**
```julia
solve(prob, Vern9(), reltol=1e-6, saveat=(0, fiber["L"]))
```

Or even use a lower-order method with adaptive stepping:
```julia
solve(prob, Tsit5(), reltol=1e-5, saveat=(0, fiber["L"]))
```

**Expected impact**: Reduce adjoint solve from 5000 steps to ~100–500 steps, a **10–50× reduction** in the dominant cost component. This alone could bring the L=5m run from hours to minutes.

**Risk**: The adjoint dynamics may have stiff regions that require small steps. Test gradient accuracy before/after the change using the existing `validate_gradient` function.

### 3b. Eliminate `deepcopy(fiber)` in Cost Function (Priority: MEDIUM, Expected: 1.05–1.1×)

Both `cost_and_gradient` and `cost_and_gradient_amplitude` call:
```julia
fiber_local = deepcopy(fiber)
fiber_local["zsave"] = nothing
```

This creates a deep copy of the fiber Dict (including all arrays) every L-BFGS iteration. Since the only mutation is `zsave`, pass `zsave=nothing` directly or use a separate parameter:

```julia
# Pre-set once before optimization loop:
fiber["zsave"] = nothing
# Then pass fiber directly — no deepcopy needed
```

### 3c. Multi-Resolution Optimization (Priority: HIGH, Expected: 2–4× on early iterations)

The setup defaults to Nt=2^13 (8192) for all iterations. But early L-BFGS iterations don't need full resolution — they're exploring the landscape broadly.

**Strategy:**
1. Run first 5 iterations at Nt=2^10 (1024) — 8× less work per FFT
2. Interpolate the optimized phase to Nt=2^11 (2048), run 5 more iterations
3. Refine to Nt=2^13 for final 5 iterations

The `benchmark_grid_sizes` function already exists in `benchmark_optimization.jl` to validate this approach. For L=1m, Nt=2^10 may produce cost values within 10% of the Nt=2^13 reference.

**Expected speedup**: Early iterations are ~8–64× faster, reducing total time by ~2–4×.

### 3d. Early Termination (Priority: MEDIUM, Expected: 1.2–1.5×)

The L-BFGS optimizer uses `f_abstol=1e-6` but the cost is reported in **dB** (via `lin_to_dB`). A change of 1e-6 dB is negligible — the optimizer is running far more iterations than needed.

Consider adding a relative tolerance or stopping when `|ΔJ/J| < 0.01` (1% improvement). This could save 30–50% of iterations in later optimization phases.

### 3e. AppleAccelerate.jl Integration (Priority: LOW for M=1, HIGH for M>1)

For single-mode (M=1) simulations, BLAS operations are minimal — the dominant cost is FFTs and elementwise operations. AppleAccelerate.jl's BLAS acceleration won't help much.

However, for multimode (M>1) future work, AppleAccelerate provides:
- 6–14× faster GEMM (matrix multiply)
- 2–4× faster factorizations
- Access to Apple's proprietary matrix acceleration hardware (AMX)

**Installation:**
```julia
using Pkg; Pkg.add("AppleAccelerate")
using AppleAccelerate  # Automatically overrides BLAS
```

### 3f. Avoid Redundant `fftshift` / `ifftshift` (Priority: LOW, Expected: 1.05×)

The Raman convolution in the RHS does:
```julia
fftshift!(hR_conv_δR, hRω_δRω, 1)
@. δRt = real(hR_conv_δR)
```

The `fftshift!` creates a copy. If `hRω` is stored in the shifted convention from the start, this shift can be eliminated from the hot inner loop.

---

## 4. Major Optimizations (1–2 days)

### 4a. Solver Algorithm Upgrade: RK4IP (Expected: 2–5× from fewer steps)

The current approach uses DifferentialEquations.jl's generic ODE solvers (Tsit5, Vern9) applied to the interaction-picture RHS. This works, but specialized GNLSE solvers are significantly faster.

**State-of-the-art: RK4IP with embedded error estimation**

The RK4IP (Runge-Kutta 4th order in the Interaction Picture) method, originally by Hult (2007) and refined by Balac & Mahé (2013) with embedded error estimation (ERK4(3)-IP), is the gold standard:

- 4th-order global accuracy (vs. 5th-order for Tsit5, but with purpose-built step structure)
- Embedded 3rd-order method for local error estimation at negligible extra cost
- Adaptive step sizing based on **conservation quantity error** (photon number conservation)
- Typical step reduction: 2–5× fewer steps than generic RK methods for equivalent accuracy

**Key advantage**: RK4IP is specifically designed for `du/dz = L(u) + N(u)` split problems. It handles the linear operator analytically (via the interaction picture) rather than numerically, avoiding the stability issues that force generic solvers to take small steps.

**Implementation path**: Either implement RK4IP as a custom stepper in DifferentialEquations.jl, or use Luna.jl's solver (see 4c).

**References:**
- Hult, J. (2007) "A Fourth-Order Runge–Kutta in the Interaction Picture Method" — *J. Lightwave Technol.* 25, 3770–3775
- Balac, S. and Mahé, F. (2013) "Embedded Runge–Kutta scheme for step-size control in the interaction picture method" — *Comput. Phys. Commun.* 184(4), 1211–1219

### 4b. GPU via Metal.jl (Expected: Currently NOT recommended)

**Status**: Metal.jl is **NOT production-ready** for FFT-heavy workloads as of early 2026.

Key limitations:
- No functional complex-valued FFT support in Metal.jl
- Ongoing work on MLX wrapper for FFT, but incomplete
- Data transfer overhead (CPU↔GPU) may negate gains for Nt=8192
- Only NVIDIA CUDA has mature Julia GPU FFT support

**Recommendation**: Skip GPU acceleration for now. The CPU-based optimizations (especially fixing the adjoint solver) will provide larger gains with less risk. Revisit Metal.jl in 6–12 months.

For reference, NVIDIA GPU GNLSE solvers achieve 8–17× speedups, but this requires CUDA hardware.

### 4c. Use Luna.jl as the Forward Solver (Expected: 2–5× from optimized internals)

**Luna.jl** (https://github.com/LupoLab/Luna.jl) is a mature Julia package for nonlinear pulse propagation:
- Supports GNLSE and UPPE formulations
- Optimized RK4IP implementation with adaptive stepping
- Built-in Raman response, self-steepening, shock terms
- Active maintenance, requires Julia 1.9+
- Extensive test suite and documentation

**Trade-offs:**
- Would require adapting the adjoint method to work with Luna's internal solver state
- May not support the specific multimode tensor coupling format used in MultiModeNoise
- The gain model (YDFA) would need to be integrated as a custom term

**Recommendation**: Evaluate Luna.jl for the forward-only solve first. If it's 2–5× faster, the adjoint could be reimplemented on top of it. Alternatively, extract Luna's RK4IP stepping logic and integrate it into MultiModeNoise.

### 4d. Checkpointing vs. Recomputation in Adjoint (Expected: varies)

**Current behavior**: The adjoint solver receives the forward solution `ũω` as an interpolation object and evaluates `ũω(z)` at each adjoint step. This means:
1. The forward solution is stored in memory (DifferentialEquations.jl's dense output)
2. Interpolation at arbitrary z is O(1) per point but has overhead
3. Memory usage scales with the number of forward solve timesteps

**Alternative**: Use checkpointing — store the forward solution at a small number of z-values and recompute between them during the adjoint pass. This trades compute for memory, which is useful if memory is the bottleneck. Given that the M3 Max has ample RAM, the current approach (store + interpolate) is likely fine.

---

## 5. Literature Findings

### GNLSE Solver Methods

| Method | Order | Steps (typical) | FFTs/step | Adaptive? | Reference |
|--------|-------|-----------------|-----------|-----------|-----------|
| Symmetric Split-Step (SSFM) | 2 | ~1000–10000 | 2 | Fixed | Agrawal (2019) |
| RK4IP | 4 | ~200–2000 | 4 | Optional | Hult (2007) |
| ERK4(3)-IP | 4(3) | ~100–500 | 4 | Yes (embedded) | Balac & Mahé (2013) |
| Tsit5 on IP-RHS (current) | 5(4) | ~100–1200 | 6 per stage × 6 stages | Yes | Tsitouras (2011) |
| Vern9 on IP-RHS (adjoint) | 9(8) | 5000 (fixed!) | 12–16 per stage × 16 stages | No (forced fixed) | Verner (2010) |

### Key Papers

1. **Hult (2007)**: "A Fourth-Order Runge–Kutta in the Interaction Picture Method for Simulating Supercontinuum Generation in Optical Fibers" — *J. Lightwave Technol.* 25(12), 3770–3775. Established RK4IP as gold standard.

2. **Balac & Mahé (2013)**: "Embedded Runge–Kutta scheme for step-size control in the interaction picture method" — *Comput. Phys. Commun.* 184(4), 1211–1219. Added embedded error estimation to RK4IP.

3. **Heidt (2009)**: "Efficient Adaptive Step Size Method for the Simulation of Supercontinuum Generation in Optical Fibers" — *J. Lightwave Technol.* 27(18), 3984–3991. Conservation quantity error method for step-size control.

4. **Brehler & Schirwon**: "A GPU-Accelerated Fourth-Order Runge–Kutta in the Interaction Picture Method for multimode fiber simulations" — GPU-accelerated RK4IP for multimode systems.

### Julia Ecosystem

- **Luna.jl** (LupoLab): Comprehensive pulse propagator, GNLSE + UPPE, mature, actively maintained
- **NonlinearSchrodinger.jl** (oashour): Algorithms up to 8th order, good for NLS studies
- **FiberNlse.jl**: Dedicated NLSE solver for fiber optics

---

## 6. Estimated Total Speedup

### Assumptions
- Baseline: Current code on M3 Max, full suite takes ~2–4 hours
- Adjoint solve is ~70–80% of total runtime
- M=1 (single mode) for optimization scripts

### Tier 1: Quick Wins Only (~1 hour effort)

| Change | Speedup | Confidence |
|--------|---------|------------|
| Verify native ARM64 (not Rosetta) | 1.0–3.0× | High (if currently Rosetta) |
| FFTW.MEASURE + wisdom caching | 1.3–1.8× on FFTs | High |
| `cis()` instead of `exp(1im·...)` | 1.1–1.3× on exp calls | High |
| FFTW single-threaded (confirm) | 1.0–1.1× | Medium |

**Combined quick wins: 1.5–2.5×** (conservative: 1.5×, optimistic: 2.5×)

### Tier 2: Quick + Medium Effort (~4–8 hours total)

| Change | Speedup | Confidence |
|--------|---------|------------|
| Quick wins (above) | 1.5–2.5× | High |
| **Adaptive adjoint solver** | **5–50× on adjoint** (→ 3–10× overall) | High |
| Eliminate deepcopy | 1.05× | High |
| Multi-resolution (early iters at low Nt) | 2–4× on early iterations | Medium |
| Early termination | 1.2–1.5× | Medium |

**Combined quick + medium: 5–15×** (conservative: 5×, optimistic: 15×)

The adaptive adjoint solver alone could bring the full suite from 2–4 hours to 15–45 minutes.

### Tier 3: All Optimizations (~2–3 days total)

| Change | Additional speedup | Confidence |
|--------|-------------------|------------|
| Quick + medium (above) | 5–15× | High |
| RK4IP solver upgrade | 1.5–3× additional | Medium |
| Luna.jl integration | 2–5× additional (replaces RK4IP) | Medium-Low |
| AppleAccelerate (for future M>1) | 1.0–1.2× (M=1) | Low for current code |
| GPU (Metal.jl) | Not recommended currently | N/A |

**All optimizations: 10–30×** (conservative: 10×, optimistic: 30×)

### Summary

| Tier | Effort | Expected Speedup | Full Suite Time |
|------|--------|-----------------|-----------------|
| Current baseline | — | 1× | 2–4 hours |
| Quick wins only | ~1 hour | 1.5–2.5× | 1–2.5 hours |
| Quick + medium | ~4–8 hours | **5–15×** | **10–45 minutes** |
| All optimizations | ~2–3 days | 10–30× | 5–20 minutes |

**Recommendation**: Focus on **Tier 2**, specifically making the adjoint solver adaptive (3a). This single change has the highest impact-to-effort ratio and is likely to achieve the 3–5× target alone. Combine with FFTW.MEASURE (2b) and `cis()` replacement (2c) for additional gains.
