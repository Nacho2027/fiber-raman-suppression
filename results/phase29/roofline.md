# Phase 29 Report — Performance Modeling and Roofline Audit

**Generated:** 2026-04-21T09:32:45.947
**Host:** IJL-MacBook-Pro.local  |  CPU: Apple M3 Max  |  Julia threads launched: 12  |  git: c34ac614fbcb95009567927b7a8c97e9e3d26be7

## Executive Verdict

Dominant bottleneck: **SERIAL_BOUND (orchestration + single-threaded RHS dominate)**. Measured minimum parallelizable fraction across forward/adjoint/full_cg is p = 0.000, giving Amdahl speedup ceiling ≈ 1.0x. Recommendation: do not pay for more than 4 burst-VM threads for the canonical single-mode workload; invest tuning effort in the FFT plan and per-RHS allocation path instead.

## Kernel Timings

| Kernel | n_fftw | reps | median (s) | throughput GB/s | notes |
|--------|--------|------|------------|-----------------|-------|
| FFT forward+inverse | 1 | 100 | 0.0050 | 5.21 | local MEASURE plans; not the ESTIMATE plans used in src/ |
| FFT forward+inverse | 16 | 100 | 0.0989 | 0.27 | local MEASURE plans; not the ESTIMATE plans used in src/ |
| FFT forward+inverse | 2 | 100 | 0.0822 | 0.32 | local MEASURE plans; not the ESTIMATE plans used in src/ |
| FFT forward+inverse | 22 | 100 | 0.0989 | 0.26 | local MEASURE plans; not the ESTIMATE plans used in src/ |
| FFT forward+inverse | 4 | 100 | 0.0905 | 0.29 | local MEASURE plans; not the ESTIMATE plans used in src/ |
| FFT forward+inverse | 8 | 100 | 0.0864 | 0.30 | local MEASURE plans; not the ESTIMATE plans used in src/ |
| Kerr tensor contraction (tullio) | 1 | 200 | 0.0048 | — | @tullio δKt[t,i,j] = γ[i,j,k,l]*(v_k*v_l + w_k*w_l); M=1 at canonical config |
| Raman frequency convolution (FFT·hRω·IFFT) | 1 | 200 | 0.0125 | 6.31 | ESTIMATE plan matches src/; counts 3 passes over (Nt,M,M) ComplexF64 |
| Forward RHS step (disp_mmf!) | 1 | 500 | 0.1440 | — | disp_mmf! includes Kerr tullio + Raman convolution + self-steep + lab/interaction transforms |
| Adjoint RHS step (adjoint_disp_mmf!) | 1 | 500 | 0.4724 | — | adjoint_disp_mmf! queries ũω(z) via ODESolution interpolation; z=L/2 |


## Amdahl Fits

| Mode | Fitted p | Speedup ceiling | RMSE (s) |
|------|----------|-----------------|----------|
| forward | 0.000 | 1.0x | 5.5079e-02 |
| full_cg | 0.050 | 1.1x | 3.9368e-02 |
| adjoint | 0.000 | 1.0x | 3.1968e-02 |


## Roofline Regimes

*Host peaks used:* FLOP/s=1.00e+12, BW=3.00e+11 B/s (Apple M3 Max)

| Kernel | n_fftw | AI (FLOP/byte) | Regime (roofline) | Verdict | Measured (GB/s or ns) | Ceiling GB/s | Util % |
|--------|--------|----------------|--------------------|---------|------------------------|--------------|--------|
| FFT forward+inverse | 1 | 1.02 | MEMORY_BOUND | MEMORY_BOUND | 5.21 GB/s | 300.00 | 1.7% |
| FFT forward+inverse | 16 | 1.02 | MEMORY_BOUND | MEMORY_BOUND | 0.27 GB/s | 300.00 | 0.1% |
| FFT forward+inverse | 2 | 1.02 | MEMORY_BOUND | MEMORY_BOUND | 0.32 GB/s | 300.00 | 0.1% |
| FFT forward+inverse | 22 | 1.02 | MEMORY_BOUND | MEMORY_BOUND | 0.26 GB/s | 300.00 | 0.1% |
| FFT forward+inverse | 4 | 1.02 | MEMORY_BOUND | MEMORY_BOUND | 0.29 GB/s | 300.00 | 0.1% |
| FFT forward+inverse | 8 | 1.02 | MEMORY_BOUND | MEMORY_BOUND | 0.30 GB/s | 300.00 | 0.1% |
| Kerr tensor contraction (tullio) | 1 | 0.06 | MEMORY_BOUND | MEMORY_BOUND | — | — | — |
| Raman frequency convolution (FFT·hRω·IFFT) | 1 | 1.42 | MEMORY_BOUND | MEMORY_BOUND | 6.31 GB/s | 300.00 | 2.1% |
| Forward RHS step (disp_mmf!) | 1 | 1.69 | MEMORY_BOUND | MEMORY_BOUND | 288004 ns/call | — | — |
| Adjoint RHS step (adjoint_disp_mmf!) | 1 | 2.64 | MEMORY_BOUND | MEMORY_BOUND | 944702 ns/call | — | — |


## Recommendations

1. **FFT: keep `FFTW.set_num_threads(1)`**. Measured throughput at n_fftw=1 is 5.21 GB/s; best threaded value (n_fftw=2) is only 0.32 GB/s — a **16.3x anti-scaling penalty**. At Nt=2^13 the FFT is too small to amortize thread-spawn overhead. This directly validates the Phase 15 determinism invariant (single-threaded FFTW). Do not spend effort tuning MEASURE plans at higher thread counts.
2. **Production thread count: `-t 1` or `-t 2`**. Worst-case fitted Amdahl p=0.000 (from mode=forward). Speedup ceiling = 1.00x as n→∞. Going beyond `-t 4` is wasted cost on the canonical single-mode workload.
3. **Burst-VM economics: DO NOT use `c3-highcpu-22` for canonical single-mode (M=1) SMF-28 workloads**. The measured speedup ceiling (≤1.1x) means `e2-standard-4` at ~$0.13/hr delivers the same throughput as `c3-highcpu-22` at ~$0.90/hr. Reserve the burst VM for (a) multi-mode M>1 phases where the Kerr tullio contraction may actually parallelize, or (b) embarrassingly-parallel parameter sweeps where Gustafson (weak) scaling applies instead of Amdahl.
4. **Next tuning target: adjoint RHS step** (945 µs/call, **3.3x** the forward RHS cost of 288 µs/call). The gap is driven by ODESolution interpolation (`ũω(z)` query inside `adjoint_disp_mmf!`) — investigate dense-interpolation caching (evaluate once per accepted adjoint step, not per RHS call) or switch to a checkpoint-based reverse-mode that avoids the interpolation altogether.

