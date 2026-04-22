# Phase 29 — Kernel Inventory (Static Analysis)

**Produced:** 2026-04-21
**Scope:** Static accounting of the forward/adjoint inner-loop kernels that dominate
a single `cost_and_gradient` evaluation. FLOP counts are analytic; bytes are
working-set lower bounds (allocated work arrays from `get_p_disp_mmf` /
`get_p_adjoint_disp_mmf`). All numbers assume `ComplexF64` (16 B) unless stated.
`Nt` is the temporal grid size; `M` is the number of spatial modes. Production
configurations used here are `Nt ∈ {2^12, 2^13, 2^14}`, `M ∈ {1, 3, 6}`.

---

## 1. Scope and method

This inventory answers three questions:

1. **Where does time go in one `cost_and_gradient` call?** Enumerate every kernel
   invoked per ODE RHS evaluation (forward + adjoint), the FLOP cost per call,
   the resident working-set, and the per-step call multiplicity.
2. **Is each kernel compute-bound or memory-bound on our hardware?** Compute the
   arithmetic intensity `AI = flops / bytes_touched` and compare to machine
   balance `π / β` (peak flops per byte of DRAM bandwidth).
3. **What is the serial-fraction upper bound for multi-start / parallel
   gradient validation?** Distinguish embarrassingly parallel work (independent
   forward/adjoint solves) from per-RHS work that is already threaded inside
   FFTW / Tullio.

The kernels below trace the call graph of
`cost_and_gradient → solve_disp_mmf + solve_adjoint_disp_mmf`:

- `src/simulation/simulate_disp_mmf.jl::disp_mmf!` (forward RHS)
- `src/simulation/sensitivity_disp_mmf.jl::adjoint_disp_mmf!` (adjoint RHS)
- helpers `calc_δs!`, `calc_γ_a_b!`, `calc_λ_∂fR2c∂uc!`,
  `calc_λc_∂fR∂uc!`, `calc_λ_∂fKR1c∂uc!`, `calc_λc_∂fK∂uc!`.

---

## 2. Hardware balance (reference rooflines)

Two concrete machines carry this project. The balance point `AI* = π / β`
(flops/byte) separates compute-bound kernels (AI > AI*) from memory-bound
kernels (AI < AI*).

| Platform | π_peak (double, AVX-512) | β_peak (DRAM) | Balance AI* | Source |
|---|---|---|---|---|
| claude-code-host (`e2-standard-2`, 2 vCPU, Skylake family) | ~80 GFLOP/s (vector + FMA, all cores, ~2.5 GHz × 16 fps/cy × 2 cores) | ~20 GB/s (dual-channel DDR4, shared VM slice) | **~4 fps/B** | GCP e2 platform notes |
| fiber-raman-burst (`c3-highcpu-22`, 22 vCPU, Xeon Platinum 8481C / Sapphire Rapids) | ~700 GFLOP/s (AVX-512, 22 cores × 2.0 GHz × 16 fps/cy) | ~110 GB/s (scaled slice of 307 GB/s DDR5 socket) | **~6 fps/B** | Sapphire Rapids spec, DDR5-4800 |

**Notes:**
- AVX-512 all-core turbo on SPR is ≈ 2.0–2.47 GHz (no large frequency cliff vs.
  prior generations, but still below single-core 3.8 GHz).
- The c3-highcpu-22 slice does not dominate the socket; its DRAM bandwidth is
  ≈ `22/56 × 307 ≈ 121 GB/s` pessimistic, 110 GB/s sustained read.
- L2 cache = 2 MB / core (SPR), L3 shared = ~60 MB / socket.
- All Mac development is single-user; Mac figures would be ≈ 300–400 GB/s
  memory bandwidth, ~200 GFLOP/s peak, balance ~0.5 fps/B — but
  **Rule 1 of `CLAUDE.md` forbids running simulations on Mac / claude-code-host**;
  benchmarks MUST be executed on `fiber-raman-burst`.

---

## 3. Forward RHS (`disp_mmf!`) — per-step kernel census

A single call to `disp_mmf!` processes one ODE RHS evaluation. Tsit5 issues
6 stages per accepted step; production propagations take ~200–500 accepted
steps at `reltol=1e-8`, so **per forward solve ≈ 1200–3000 RHS calls**.

Let `NM = Nt·M`, `NMM = Nt·M²`, `M4 = M⁴` (tensor contractions).

### F-1 Interaction-picture phase factors
```julia
@. exp_D_p = cis(Dω * z)        # Nt·M complex
@. exp_D_m = cis(-Dω * z)       # Nt·M complex
```
- FLOPs ≈ `2·NM × (sincos + mul)` ≈ `40·NM` (cis costs ~20 fps).
- Bytes ≈ `3·NM·16` read Dω + write exp_D_p, exp_D_m (48 B / element).
- **AI ≈ 0.83 fps/B → memory-bound on both hosts.**

### F-2 Lift to lab frame + M FFT
```julia
@. uω = exp_D_p * ũω             # complex mul, NM
fft_plan_M! * uω                 # M 1-D FFTs of length Nt
```
- `uω = exp_D_p * ũω`: 6 fps/elt × NM = `6·NM` fps, `48·NM` B → AI 0.13 fps/B (**memory-bound**).
- 1-D complex-to-complex FFT size Nt: ≈ `5·Nt·log₂(Nt)` fps; `M` such FFTs in one batched plan.
  - `M·5·Nt·log₂(Nt)` fps.
  - Working set per FFT: `Nt × 16 B = 128 KB` at `Nt=2^13` → **L2-resident** (SPR
    L2 = 2 MB / core).
  - AI (in-cache, single pass): `5 log₂ Nt · Nt` fps / `2·Nt·16 B` = `log₂ Nt · 5 / 32` = ~2 fps/B at Nt=2^13 → **balanced, mildly memory-bound**.
  - ESTIMATE vs MEASURE: FFTW docs report ESTIMATE plans are often
    2–4× slower than MEASURE / PATIENT for sizes where radix choice matters
    (size 1024 complex: ~60 μs ESTIMATE vs 9 μs PATIENT). **Our project pins
    ESTIMATE for determinism** (`phase27-REPORT.md` line 303–304); the
    roofline memo must quantify the ESTIMATE tax, not assume it away.

### F-3 Attenuator + split to real/imag
```julia
@. ut = attenuator * uω          # complex·real, NM
@. v = real(ut)                  # NM real
@. w = imag(ut)                  # NM real
```
- FLOPs ≈ `2·NM` (complex·real mul); bytes ≈ `4·NM·16 = 64·NM` including ut read + v,w writes.
- **AI ≈ 0.03 fps/B → strongly memory-bound.**

### F-4 Kerr contraction δ_K (critical kernel)
```julia
@tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])
@tullio αK[t, i] = δKt[t, i, j] * v[t, j]
@tullio βK[t, i] = δKt[t, i, j] * w[t, j]
```
- δKt inner loop: `Σ_{kl}` for each `(t,i,j)` → `2·M²` fps per element × NMM elements
  → **`2·Nt·M⁴ + 2·Nt·M²·M²` ≈ `4·Nt·M⁴` fps** per δKt build (dominant term at M≥3).
- αK/βK contraction: `2·Nt·M·M = 2·NMM` fps each → `4·NMM` fps.
- Working set: γ (M⁴×8 B) fits L1 for M≤6 (8 KB at M=6); δKt (Nt·M²·8 B) = 300 KB
  at `Nt=2^13, M=6` → L2-resident.
- AI: `4·Nt·M⁴ / (Nt·M²·8·2 passes)` = `M²/4` fps/B. **At M=1: AI=0.25 (memory); at M=3: AI=2.25; at M=6: AI=9** → **compute-bound at M≥3 on our hosts**.
- Tullio + LoopVectorization on contiguous real arrays benchmarks at ~OpenBLAS
  speed (Tullio README). AVX-512 vectorizes the t-axis efficiently.
- **This is the single hottest kernel in the forward RHS at M=6.**

### F-5 Raman convolution (M² FFTs)
```julia
@. δKt_cplx = ComplexF64(δKt, 0.0)
fft_plan_MM! * δKt_cplx
@. hRω_δRω = hRω * δKt_cplx
ifft_plan_MM! * hRω_δRω
fftshift!(hR_conv_δR, hRω_δRω, 1)
@. δRt = real(hR_conv_δR)
```
- Real→complex cast: `NMM` stores of 16 B → pure memory (AI ≈ 0).
- FFT + IFFT on `(Nt, M, M)` along dim 1: `2·M²` FFTs of length Nt.
  - FLOPs: `2·M²·5·Nt·log₂(Nt)` = `10·M²·Nt·log₂ Nt` fps.
  - Working set: `Nt·M²·16 B` = 2.3 MB at Nt=2^13 M=6 → **spills to L3** (60 MB socket shared; the 22-vCPU slice sees ~24 MB).
  - AI ≈ `log₂ Nt × 5 / (2 passes × 32)` ≈ 1 fps/B out-of-cache → **memory-bound in L3**.
- `hRω_δRω = hRω * δKt_cplx`: 6 fps × NMM fps, 48·NMM B → AI 0.13 (memory).
- `fftshift!`: pure data shuffle, 0 fps, `2·NMM·16 B` traffic.
- **Per-step FFT count:** M scalar-plan FFTs (F-2) + 2·M² MM-plan FFTs (F-5)
  + 1 inverse M FFT (F-6) = `M + 2M² + 1`. At M=6: **79 FFTs per RHS call**.

### F-6 Combine + final IFFT + self-steepening
```julia
@tullio αR[t, i] = δRt[t, i, j] * v[t, j]
@tullio βR[t, i] = δRt[t, i, j] * w[t, j]
@. ηKt = αK + 1im*βK; @. ηKt *= one_m_fR
@. ηRt = αR + 1im*βR
@. ηt = ηKt + ηRt
ifft_plan_M! * ηt
ηt .*= selfsteep
@. dũω = 1im * exp_D_m * ηt
```
- αR/βR: `4·NMM` fps, L2-resident (same as δKt footprint).
- Broadcasts: each `NM` complex elements with AI ≈ 0.1 fps/B → memory-bound.
- IFFT (size-Nt, M batched): same as F-2, L2-resident.

### F-7 Per-step totals (forward)
Sum of the above for one `disp_mmf!` call:

| Term | FLOPs (order) | Bytes touched (order) | Regime |
|---|---|---|---|
| Kerr δ_K+αK+βK (F-4) | `4·Nt·M⁴ + 4·Nt·M²` | `~4·Nt·M²·8` | compute-bound at M≥3 |
| M FFTs (F-2, F-6) | `10·M·Nt·log₂ Nt` | `~4·Nt·M·16` | balanced at Nt=2^13 |
| M² FFTs (F-5) | `10·M²·Nt·log₂ Nt` | `~4·Nt·M²·16` | memory-bound (L3) |
| Broadcasts (F-1, F-3, F-6) | `~10·Nt·M` | `~50·Nt·M` | memory-bound |

At `Nt=2^13, M=6, log₂Nt=13`:
- Kerr: `4·8192·1296 = 42.5 MFLOPs` **(dominant)**
- MM FFT: `10·36·8192·13 = 38 MFLOPs`
- M FFT + inverse: `10·6·8192·13 = 6.4 MFLOPs`
- Broadcasts: `~0.5 MFLOPs`
- **Per-RHS ≈ 90 MFLOPs; per-solve (1200 calls) ≈ 108 GFLOPs.**

At `M=1` the Kerr term collapses to `4·Nt`, the FFTs dominate, and the solve is
FFT-bound throughout.

---

## 4. Adjoint RHS (`adjoint_disp_mmf!`) — per-step kernel census

The adjoint RHS is structurally heavier than the forward:
- It needs the forward solution sampled via `ũω(z)` (Tsit5 4th-order interpolant).
- It computes **two** Kerr operators (δ₁ and δ₂) via `calc_δs!`.
- It invokes **two** Raman adjoint paths (`calc_λ_∂fR2c∂uc!`,
  `calc_λc_∂fR∂uc!`), each doing its own `calc_γ_a_b!` (two γ-contractions)
  plus a pair of MM-plan FFTs.

### A-1 Forward interpolant + phase factors + adjoint transforms
- `ũω_z .= ũω(z)` — Tsit5 interpolant eval: `~12·NM` fps (cubic Hermite per ω bin).
- Two `cis(±Dω z)` builds: same as F-1.
- `λω = exp_D_p * λ̃ω`, conjugates, 1 M FFT, 1 M IFFT: same accounting as F-2.

### A-2 `calc_δs!` — two Kerr operator tensors (δ₁ real, δ₂ complex)
```julia
@tullio abs2_u_z_re[t, i, j] = v[t,i]*v[t,j] + w[t,i]*w[t,j]   # 3·NMM
@tullio sq_u_z_re[t, i, j]   = v[t,i]*v[t,j] - w[t,i]*w[t,j]   # 3·NMM
@tullio sq_u_z_im[t, i, j]   = 2*v[t,i]*w[t,j]                  # 2·NMM
@tullio δ_1_[t,i,j]   = abs2_u_z_re[t,k,l] * γ[l,k,i,j]         # 2·Nt·M⁴
@tullio δ_2_re[t,i,j] = sq_u_z_re[t,k,l]   * γ[l,k,i,j]         # 2·Nt·M⁴
@tullio δ_2_im[t,i,j] = sq_u_z_im[t,k,l]   * γ[l,k,i,j]         # 2·Nt·M⁴
```
- **3 full γ-contractions** → `6·Nt·M⁴` fps.
- Working-set identical to F-4; same AI scaling.
- **Adjoint does ≈ 3× the Kerr-tensor work of the forward per RHS call.**

### A-3 `calc_γ_a_b!` — general complex γ-contraction (invoked 2× per RHS)
```julia
@tullio a_b_re[t,i,j] = a_re*b_re - a_im*b_im     # 3·NMM
@tullio a_b_im[t,i,j] = a_re*b_im + a_im*b_re     # 3·NMM
@tullio γ_a_b_re[t,i,j] = a_b_re[t,l,k] * γ[l,k,i,j]   # 2·Nt·M⁴
@tullio γ_a_b_im[t,i,j] = a_b_im[t,l,k] * γ[l,k,i,j]   # 2·Nt·M⁴
```
- Per invocation: `4·Nt·M⁴` fps (+ `6·NMM` setup).
- Invoked in both `calc_λ_∂fR2c∂uc!` and `calc_λc_∂fR∂uc!` → `8·Nt·M⁴` fps per RHS.

### A-4 Raman adjoint: 4 MM-plan FFTs per path × 2 paths = 8 MM FFTs
```julia
fft_plan_MM! * γ_λt_utc
@. γ_λt_utc *= hωc * σ                 # 8·NMM + 8·NMM fps; 48·NMM B
fft_plan_MM! * γ_λt_utc                 # !! forward twice — wastes an IFFT?
@tullio γ_λt_ut_ut[t,i] = γ_λt_utc[t,i,j] * ifft_uω[t,j]
fft_plan_M! * γ_λt_ut_ut                # extra M FFT
```
- `calc_λ_∂fR2c∂uc!`: 2 MM FFTs (both forward), 1 M FFT.
- `calc_λc_∂fR∂uc!`: 1 IFFT + 1 FFT MM, 1 IFFT M.
- Plus 1 MM FFT and 1 MM IFFT in the main body for δ₁ convolution.
- **Total MM FFT count per adjoint RHS ≈ 6** (forward had `2·M²` of the same
  plan, e.g. 72 at M=6 — wait, that's MM-plan FFTs of shape `(Nt, M, M)` which
  is one FFTW call that does M² length-Nt FFTs). Counting **FFTW plan calls**:
  forward = 4 MM calls + 2 M calls = 6; adjoint ≈ 8 MM calls + 4 M calls = 12.
- **Adjoint FFT work ≈ 2× forward FFT work.**

### A-5 Adjoint per-step totals
Summing:

| Term | FLOPs (order) | Relative to forward |
|---|---|---|
| Kerr γ-contractions (A-2, A-3) | `(6 + 8)·Nt·M⁴` | ~3.5× forward Kerr |
| MM FFTs (A-4) | `~8·M²·5·Nt·log₂Nt` | ~2× forward MM FFT |
| M FFTs + phases | similar to forward | ~1.5× |

At `Nt=2^13, M=6`: **per-RHS ≈ 250 MFLOPs** (vs ~90 MFLOPs forward). At M=1 the
Kerr/γ terms collapse and adjoint ≈ 2× forward due to extra FFTs only.

Production adjoint solves run the same number of accepted steps as forward
(they share tolerances and the forward trajectory), giving **cost(gradient) ≈
3–4 × cost(forward)** at M=6 — consistent with `reltol=1e-8` + `saveat=(0,L)`
observed in `solve_adjoint_disp_mmf`.

---

## 5. Parallelism surfaces

| Level | Mechanism | Scope | Scaling ceiling |
|---|---|---|---|
| L1: SIMD | AVX-512 via FFTW / Tullio `@avx` | Per-kernel inner loop | Bounded by vector lanes (8 doubles) |
| L2: Tullio threading | Polyester spawn, inner-loop tiling | Tensor contractions along `t`-axis | `Nt / tile_size`; near-linear to core count at `Nt ≥ 4096` |
| L3: FFTW threading | FFTW internal threads | Per FFT plan | At `Nt=2^13` FFTW threading **hurts** (per `phase27-REPORT.md` and `benchmark_threading.jl` data); keep `FFTW.set_num_threads(1)` |
| L4: `Threads.@threads` over solves | Multi-start L-BFGS, parallel gradient checks | Independent forward-adjoint pairs | Amdahl ceiling = `1 / (serial_frac)` — measured 2.13× at 4 threads for multi-start, 3.55× at 8 threads for parallel forward solves (`benchmark_threading.jl` results file) |
| L5: Process-level (burst-VM) | `burst-run-heavy` + tmux | Independent sweeps (e.g., grid in `(L, P)`) | Limited by VM-wide lock + watchdog (one heavy job at a time by policy) |

**Key asymmetry:** Tullio threading requires the outer loop to be the `t`-axis,
which is always `Nt` (8192 in production) — ample parallel work. FFTW internal
threading competes for the same cores and does not pay off at these sizes. The
benchmark harness must not conflate the two.

---

## 6. Memory hierarchy crossings (worst case per RHS)

At `Nt = 2^13, M = 6`:

| Array | Shape | Bytes | Location on SPR |
|---|---|---|---|
| Single-mode field `uω`, `ũω` | `(Nt, M)` complex | 786 KB | L2 (per-core 2 MB) |
| Kerr operator `δKt` | `(Nt, M, M)` real | 2.36 MB | L3 (per-socket 60 MB) |
| Kerr complex `δKt_cplx`, `hRω_δRω` | `(Nt, M, M)` complex | 4.72 MB | L3 |
| γ tensor | `(M⁴)` | 10 KB | L1 |
| Dω | `(Nt, M)` real | 393 KB | L2 |

At `Nt = 2^14, M = 6`: `(Nt, M, M)` complex = 9.4 MB → **L3 but large slice**,
first candidate for cache-blocking wins.

Implication: for the burst-VM 22-vCPU slice with ~24 MB of "effective" L3, the
`(Nt, M, M)` arrays are the capacity pressure; running the parallel-solve
harness with 4–8 threads each holding an independent copy crosses the L3
boundary and pushes working sets into DRAM. `deepcopy(fiber)` per thread
(documented in `CLAUDE.md`) already handles correctness; the performance
model must treat multi-start throughput as DRAM-bandwidth limited.

---

## 7. Benchmark matrix (derived from this inventory)

The execution plan (`29-02-PLAN.md`) ties timings back to the kernels above via
this matrix:

| Axis | Values | Rationale |
|---|---|---|
| `Nt` | `2^12, 2^13, 2^14` | Span L2-only → L3-only → DRAM-pressure |
| `M` | `1, 3, 6` | Kerr term scales as `M⁴`; at M=1 FFT dominates, at M=6 Kerr dominates |
| Threads | `1, 2, 4, 8, 16, 22` | Burst VM has 22 vCPU; scaling curve probes Amdahl serial fraction |
| Kernel isolation | `disp_mmf!`, `adjoint_disp_mmf!`, `calc_δs!`, `calc_γ_a_b!`, single `plan_fft!` call | Separate per-kernel roofline from whole-solve wall-clock |
| FFTW flags | `ESTIMATE` (production), `MEASURE` (reference) | Quantify determinism tax identified in Phase 27 |
| Metrics | Median wall-time, `@benchmark` allocations, BenchmarkTools samples=10, seconds=30 | Stable medians; allocations must be zero for ODE RHS |

All benchmarks run via `~/bin/burst-run-heavy E-roofline 'julia -t auto …'` per
Rule P5 (`CLAUDE.md` Parallel Session Protocol).

---

## 8. Sanity-check references in the codebase

- `scripts/benchmark_threading.jl` — existing threading benchmark; does A/B/C/D
  but not per-kernel roofline; its results feed this inventory.
- `scripts/benchmark_optimization.jl` — grid-size + multi-start benchmarks; its
  median timings anchor the Amdahl ceiling for L4 parallelism.
- `scripts/determinism.jl:75-76` — pins FFTW + BLAS threads to 1. Any roofline
  number quoted here assumes determinism mode unless explicitly flagged.

---

## 9. Open questions the execution pass must answer

1. **Is the forward solve Kerr-bound or FFT-bound at the production point
   `(Nt=2^13, M=6)`?** Static analysis says Kerr just barely wins in FLOP
   share; measurement must confirm.
2. **What fraction of runtime is the ESTIMATE→MEASURE gap?** If it is > 20 %
   we need a determinism-aware plan-caching layer.
3. **Where does multi-start Amdahl plateau?** If serial_frac measured is
   > 0.2, adding cores past 8 is wasted; if < 0.05, burst-spawn-temp for
   sweeps is justified.
4. **Is the adjoint in-place Tullio thread-safe under per-thread
   `deepcopy(fiber)`?** Correctness is established; perf under contention is
   not.
5. **Does `fftshift!` show up as a measurable cost?** At M=6 it moves ~5 MB —
   non-trivial DRAM traffic per step.
