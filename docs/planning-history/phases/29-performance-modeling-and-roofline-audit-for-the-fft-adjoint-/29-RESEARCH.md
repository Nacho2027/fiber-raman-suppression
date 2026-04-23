# Phase 29 Research — Performance modeling and roofline audit

**Scope:** Turn the forward/adjoint FFT pipeline into a measurable, modelable
system. Before tuning or buying more compute, we must know: which kernels are
memory-bound, which are compute-bound, where the Amdahl serial fraction lives,
and what `-t N` on `fiber-raman-burst` actually buys for this workload.

This research document locks in the kernel taxonomy, the FLOP/byte model, the
roofline derivation for the two project machines, the Amdahl/Gustafson theory
with the exact fitting equations, the linkage to prior phase findings, the
inventory of existing benchmark harnesses, the concrete forward-only call path
needed by Task 2A of `29-01-PLAN.md`, and the open-question list.

Target depth: enough that the plan's benchmark drivers, the pure analysis
module, and the final memo can all cite this file for every number they
compute, without having to re-derive anything.

---

## 1. Canonical configuration (fixed across Phase 29)

All FLOP/byte estimates and all measurements in this phase assume:

- `Nt = 2^13 = 8192` (SMF-28 canonical, see CLAUDE.md "Standard output images")
- `M = 1` (single-mode — GRIN multi-mode M≥6 is out of scope per CONTEXT.md)
- `L_fiber = 2.0 m`, `P_cont = 0.2 W`, `β_order = 3`, `fR = 0.18` (SMF-28 preset)
- `time_window = 10 ps`, `pulse_fwhm = 185 fs`, `pulse_rep_rate = 80.5 MHz`
- Seed 42 (deterministic)
- ComplexF64 throughout (16 bytes per element)
- `FFTW.ESTIMATE` plans in `src/` (Phase 15 invariant); MEASURE plans allowed
  locally only in kernel benches to expose hardware peak, never in production

`sizeof(ComplexF64) = 16` bytes. `sizeof(Float64) = 8` bytes. These constants
are reused throughout.

---

## 2. Kernel taxonomy and FLOP/byte estimates

Every FLOP/byte count below is "useful arithmetic" — counting one FMA as 2
FLOPs, one complex multiply as 6 FLOPs (4 real mul + 2 add) unless noted. Byte
counts are minimum traffic (one read + one write per element touched per pass),
assuming L1/L2 misses on the (Nt, M, M)=(8192, 1, 1) arrays that exceed typical
L1 sizes (≥ 128 KiB of data; e2-standard-4 L1d is 32 KiB).

### Kernel A — Raw FFT forward+inverse on (Nt, M) = (8192, 1)

Source of plan allocation: `src/simulation/simulate_disp_mmf.jl:84-85`.
Local MEASURE plan in the kernel bench: separate — not production.

- **Size:** Nt × M = 8192 complex doubles = 128 KiB per array (2× for scratch)
- **FLOPs (Cooley-Tukey):** 5·Nt·log₂(Nt) = 5·8192·13 ≈ 5.32e5 FLOPs per FFT.
  Forward + inverse ≈ 1.06e6 FLOPs per pair.
- **Bytes touched:** one full in-place read + write per pass = 2·16·Nt =
  2.62e5 B per FFT, ≈ 5.24e5 B per pair.
- **Arithmetic intensity:** AI_fft ≈ 1.06e6 / 5.24e5 ≈ **2.0 FLOP/byte**.
- Classic result: 1-D FFT on L2-resident data is right at the ridge — whether
  it is memory-bound or compute-bound depends entirely on the ridge point of
  the host (see §3). On e2-standard-4 it is memory-bound; on c3-highcpu-22 it
  is very close to the ridge.
- **Implementation line in production (do not edit):**
  `fft_plan_M! * uω` at `src/simulation/simulate_disp_mmf.jl:33`.

### Kernel B — Kerr tensor contraction (@tullio)

Source: `src/simulation/simulate_disp_mmf.jl:39-41`.

```julia
@tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])
@tullio αK[t, i]     = δKt[t, i, j] * v[t, j]
@tullio βK[t, i]     = δKt[t, i, j] * w[t, j]
```

At M = 1 the inner loops collapse to scalar ops per t, but Tullio still pays
threading + bounds-check overhead per t. Counts PER t-slice (of which there
are Nt):

- `δKt = γ · (v·v + w·w)`: 1 mul + 1 mul + 1 add + 1 mul = **4 real FLOPs**
  at M=1. Reads `γ (1 elt), v, w`; writes `δKt (1 elt)`. ≈ 5 Float64 elts
  traffic = 40 B.
- `αK`, `βK`: 1 mul each; ≈ 3 elts traffic each = 24 B.
- Per t-slice: ~6 FLOPs, ~88 B → AI_kerr,M1 ≈ **0.07 FLOP/byte** — strongly
  memory-bound at M=1.
- Total over Nt: 6·Nt ≈ 5e4 FLOPs, 7.2e5 B — total AI still ~0.07.
- This kernel is **why M=1 measurements under-represent the tullio cost**:
  Tullio's actual FLOP/byte grows as M² (tensor becomes genuinely dense). At
  M=1 we are measuring threading overhead + bounds-check, not arithmetic.

### Kernel C — Raman frequency convolution on (Nt, M, M)

Source: `src/simulation/simulate_disp_mmf.jl:47-53`.

```julia
fft_plan_MM! * δKt_cplx       # FFT size (Nt, 1, 1) at M=1
@. hRω_δRω = hRω * δKt_cplx   # pointwise complex multiply
ifft_plan_MM! * hRω_δRω       # IFFT
fftshift!(hR_conv_δR, hRω_δRω, 1)
```

Per call at M=1:
- FFT + IFFT: as Kernel A, ≈ 1.06e6 FLOPs, 5.24e5 B traffic.
- Pointwise `hRω * δKt_cplx`: Nt complex mul = 6·Nt = 4.92e4 FLOPs, 3·16·Nt =
  3.93e5 B traffic (read hRω + δKt_cplx, write δKt_cplx).
- Fftshift: 0 FLOPs, 2·16·Nt = 2.62e5 B traffic.
- **Per call:** ≈ 1.11e6 FLOPs, 1.18e6 B → AI_raman ≈ **0.94 FLOP/byte** —
  memory-bound on both machines.

### Kernel D — Single forward-RHS step (`disp_mmf!`)

Source: `src/simulation/simulate_disp_mmf.jl:25-61`. One call does:
- 2 phase updates (`exp_D_p`, `exp_D_m`): 2·Nt·M complex `cis` each. `cis` is
  ~20 FLOPs. ≈ 8·10⁵ FLOPs, 2·2·16·Nt = 5.24e5 B traffic.
- 1 lab-frame multiply (`uω = exp_D_p * ũω`): Nt·M complex mul = 6·Nt ≈
  5e4 FLOPs, 3·16·Nt = 3.93e5 B.
- 1 forward FFT (Kernel A leg): 5.32e5 FLOPs, 2.62e5 B.
- 1 attenuator multiply: Nt complex mul × 2 vectors = 1e5 FLOPs, ~6·16·Nt B.
- real/imag split: 0 FLOPs arithmetically, 4·16·Nt = 5.24e5 B.
- Kerr tullio block (Kernel B scaled): ~6·Nt FLOPs, ~7e5 B at M=1.
- Raman block (Kernel C + a small `fftshift` of size Nt): 1.11e6 FLOPs, 1.18e6 B.
- Self-steepening multiply + IFFT + interaction-picture conversion:
  ≈ 6·Nt + 5.32e5 + 6·Nt FLOPs, several Nt×16 B traffic.

**Aggregate per RHS call:** roughly **3–4 × 10⁶ FLOPs** against **~5 × 10⁶ B**
of traffic at M=1 → **AI_rhs ≈ 0.6–0.8 FLOP/byte** — memory-bound. The FFTs
dominate both counts, which is the point: the solver is not compute-bound, it
is FFT-bandwidth-bound.

ODE solver overhead (Tsit5 Butcher tableau stages) adds ~5 RHS calls per
accepted step. The solver itself is ~100 step accepts for L = 2 m at reltol =
1e-8, so a full forward solve is ~500 RHS calls = **~1.5–2 × 10⁹ FLOPs**.

### Kernel E — Single adjoint-RHS step (`adjoint_disp_mmf!`)

Source: `src/simulation/sensitivity_disp_mmf.jl:32-79`. The adjoint RHS calls
four helper functions, each of which performs 1–2 FFTs plus tullio
contractions. Structurally, per call:
- 4 phase/lab-frame multiplies (like forward): ~3·10⁵ FLOPs, ~10⁶ B.
- 1 forward FFT + 1 inverse FFT of `λt`: ~1.06e6 FLOPs, ~5.24e5 B.
- Continuous interpolation into forward solution `ũω(z)`: 1 interpolant
  evaluation (Tsit5 4th-order), ~Nt·4 scalar evals ≈ 3.28e4 FLOPs.
- `calc_δs!`: 3 tullio contractions over (Nt, M, M) × (M, M, M, M). At M=1,
  cheap (~3·Nt mul per block).
- 1 Raman convolution (Kernel C again): 1.11e6 FLOPs, 1.18e6 B.
- 4 helper blocks (`calc_λ_∂fKR1c∂uc!`, `calc_λc_∂fK∂uc!`,
  `calc_λ_∂fR2c∂uc!`, `calc_λc_∂fR∂uc!`): each does 1–3 FFTs + 1–2 tullios.
  Aggregate ~3·(1 FFT) + 2·(1 conv) ≈ 5·10⁶ FLOPs, ~5·10⁶ B.

**Aggregate per adjoint RHS:** **~8 × 10⁶ FLOPs**, **~10⁷ B** traffic →
AI_adj ≈ **0.7–0.8 FLOP/byte** — also memory-bound, ~2–3× the forward RHS
in total work. The adjoint solve does roughly the same number of accepted
steps as the forward (reltol=1e-8, Tsit5), so a full adjoint is ~500 RHS
calls = ~4 × 10⁹ FLOPs.

**Bottom line:** every benchmark kernel sits comfortably below AI ≈ 2. All
production kernels are memory-bound; only the raw (MEASURE-plan, L1-resident)
FFT sits near the ridge.

---

## 3. Roofline derivation for both machines

### Hardware specs

| Host | CPU | Peak DP FLOP/s (per socket) | Sustained mem BW | Ridge AI (FLOP/byte) |
|------|-----|------------------------------|------------------|----------------------|
| `claude-code-host` (e2-standard-4) | Skylake @ ~2.2 GHz, 4 vCPU (2 physical), 16 GB DDR4 | 4 cores × 2 GHz × 16 DP FLOPs/cycle = ~1.3 × 10¹¹ FLOP/s  | DDR4 shared, STREAM copy ≈ 18–20 GB/s (Intel Xeon E2 series, cited in GCP docs + STREAM benchmarks at https://www.cs.virginia.edu/stream/) | ≈ 1.3e11 / 2e10 = **6.5 FLOP/byte** |
| `fiber-raman-burst` (c3-highcpu-22) | Sapphire Rapids, 22 vCPU (11 physical), DDR5 | 11 cores × 3 GHz × 16 DP FLOPs/cycle × AVX-512 = ~5.3 × 10¹¹ FLOP/s | DDR5 @ ~40 GB/s measured (Sapphire Rapids C3 series, STREAM copy) | ≈ 5.3e11 / 4e10 = **13 FLOP/byte** |

These ridge points are upper bounds — real FFTW at FFTW.MEASURE achieves
~30–50% of peak; Tullio at M=1 achieves much less because the inner loop is
memory-bound. **The entire production pipeline runs at AI < 1** (§2), so both
machines classify it as **MEMORY-BOUND**. The ridge comparison matters
primarily for interpreting the FFT microbench (the only kernel near the
ridge).

### Roofline verdict (predicted, to be measured)

- **FFT with MEASURE plan:** on e2 borderline memory-bound (AI 2 < ridge 6.5);
  on c3 strongly memory-bound (AI 2 < ridge 13). Both machines will spend
  well below peak FLOPS but should hit ≥ 50% of memory BW.
- **Kerr tullio at M=1:** memory-bound everywhere (AI ~0.07). Expect a
  measured throughput << both ridges; this kernel cost comes from threading
  overhead + bounds-check + allocator, not arithmetic.
- **Raman convolution:** memory-bound everywhere (AI ~0.94 < both ridges).
- **Forward RHS / Adjoint RHS:** memory-bound (AI ~0.7 < both ridges). The
  wall-clock difference between e2 and c3 will primarily reflect their
  respective DDR4 vs DDR5 bandwidth ratios, not FLOP peak.

### Citation

- STREAM benchmark reference for DDR4/DDR5 sustained bandwidth:
  https://www.cs.virginia.edu/stream/ref.html. Use STREAM_Copy as the
  memory-BW number; Triad overcounts by ~30% because it accumulates.
- Williams, Waterman, Patterson 2009 "Roofline: an insightful visual
  performance model for multicore architectures", *Comm. ACM* 52(4) 65–76 —
  the canonical roofline derivation.
- Cooley–Tukey FLOP count 5·N·log₂(N) from CLRS (Cormen et al., 3rd ed.,
  §30.3) and Press et al., *Numerical Recipes*, §12.2.

---

## 4. Amdahl and Gustafson theory, with fit equations

### Amdahl's Law (fixed total work)

If a fraction `p` of the wall time is perfectly parallelizable and `1−p` is
irremediably serial (FFTW planning, ODE solver orchestration, `cost_and_gradient`
glue code, Julia method dispatch, `@info` I/O), then on n threads:

$$T(n) = T(1) \cdot \left[(1-p) + \frac{p}{n}\right]$$

$$S(n) = \frac{T(1)}{T(n)} = \frac{1}{(1-p) + p/n}$$

Asymptotic speedup: $S(\infty) = 1/(1-p)$. For `p = 0.9`, ceiling = 10×. For
`p = 0.5`, ceiling = 2×. For `p = 0.2`, ceiling = 1.25× — more threads
cannot help.

**Fitting `p` from measurements.** Given timings `(n_i, T_i)` for
`i = 1, …, K`, let `x_i = 1/n_i`, `y_i = T_i / T(1) − 1`. Then

$$y_i = p \cdot (x_i - 1)$$

is linear in `p` with no intercept. Least-squares estimate:

$$\hat p = \frac{\sum_i (x_i - 1) \cdot y_i}{\sum_i (x_i - 1)^2}$$

Clamp to `[0, 1]`; the RMSE on predicted `T(n)` is the fit-quality metric.
This is the formula used in `fit_amdahl` in `scripts/roofline_model.jl`.

### Gustafson's Law (fixed work per thread)

If each thread keeps the same local workload and total problem scales with n,

$$S_{\text{Gustafson}}(n) = n - s \cdot (n - 1),$$

where `s` is the serial fraction. Gustafson is the right lens when the
workload grows (e.g., parameter sweeps: more threads → more sweep points in
the same wall time). It is NOT the right lens for a fixed-Nt solve — that's
Amdahl.

Phase 29 measures Amdahl for `forward`, `adjoint`, `full_cg` (fixed Nt, fixed
fiber), and exposes `fit_gustafson` for future sweep-style benchmarks.

### What the measured `p` means operationally

| Measured `p` | Interpretation | Compute-discipline decision |
|---|---|---|
| `p < 0.3` | Orchestration-dominated (Julia dispatch, ODE solver, FFTW planning overwhelm the parallelizable FFTs) | Stop at `-t 4` on burst; more threads waste $ |
| `0.3 ≤ p < 0.6` | Mixed; modest gains to `-t 8` | `-t 8` is the sweet spot |
| `0.6 ≤ p < 0.85` | FFTs + Tullio carry the wall time; significant scaling | `-t 16` worth the cost; beyond that diminishing returns |
| `p ≥ 0.85` | Nearly perfect scaling | `-t 22` (burst VM ceiling) justified |

---

## 5. Linkage to prior phases (explicit findings)

**Phase 13 — Optimization Landscape Diagnostics** (determinism primitives).
From `13-01-SUMMARY.md`:
> "Determinism baseline: FFTW.MEASURE non-determinism quantified (max|Δφ| = 1.04 rad, ΔJ = −1.83 dB)"

*Implication for Phase 29:* MEASURE plans are NOT safe for production runs —
they produce non-bit-identical solutions across invocations. The Phase 29
kernel bench uses MEASURE only on throwaway local arrays to probe hardware
ceiling; the solve bench uses the production ESTIMATE path (`get_p_disp_mmf`,
which hard-codes ESTIMATE at `src/simulation/simulate_disp_mmf.jl:84-87`).

**Phase 22 — Sharpness Research** (benchmark harness convention). From
`22-sharpness-research/SUMMARY.md`:
> "26 successful / 0 failed" Hessian spectra — the harness pattern (per-record JLD2 + `results/raman/phase22/phase22_results.jld2` bundle) is the template Phase 29 reuses under `results/phase29/{kernels,solves}.jld2`.

*Implication for Phase 29:* JLD2 bundle + JSON sidecar (`hw_profile.json`,
`amdahl_fits.json`) is the established pattern. Do not invent new formats.

**Phase 27 — Numerical Audit** (direct mandate for this phase). From
`27-REPORT.md` §E "Performance-modeling / roofline audit":
> "This repo is sufficiently FFT-heavy and burst-compute-aware that the missing modeling pass is worth doing" and "bottleneck decomposition of forward solve, adjoint solve, FFT plans, and Amdahl-style upper bounds on useful parallel speedup."

And from the second-opinion addendum (`27-REPORT.md:343`):
> "ESTIMATE plans (required for determinism) cost measurable FFT throughput vs MEASURE/PATIENT. The determinism seed and the performance-modeling seed do not reference each other; they should."

*Implication for Phase 29:* quantify the MEASURE-vs-ESTIMATE gap in the FFT
kernel bench. The memo must report both numbers explicitly so the lab can
see the "determinism tax."

**Phase 28 — Numerical Trust Framework**. From `28-SUMMARY.md`:
> "scripts/numerical_trust.jl defines the shared trust schema, thresholds, and markdown output."

*Implication for Phase 29:* the roofline library copies this pattern exactly
(`TRUST_THRESHOLDS` → `P29M_*_THRESHOLD`; `trust_verdict` → `kernel_regime_verdict`
returning `"MEMORY_BOUND"` / `"COMPUTE_BOUND"` / `"SERIAL_BOUND"`/
`"AMDAHL_SATURATED"`). The memo's overall-verdict line must read like the
trust report's verdict line.

**Phase 35 — Saddle-escape verdict** (what performance work is NOT for). From
`35-SUMMARY.md`:
> "Genuine minima do exist, but only after aggressive control-space restriction that destroys the competitive Raman-suppression depth. The high-performing branch remains saddle-dominated."

*Implication for Phase 29:* Phase 29 is orthogonal — it does NOT attempt to
find better minima, it models the cost of finding minima. Do not mix the two
narratives in the memo; performance work cannot solve the saddle problem.

---

## 6. Existing benchmark harnesses in this repo (do not duplicate)

- `scripts/benchmark_threading.jl` (269 lines) — measures (A) FFTW internal
  threads, (B) Tullio threading, (C) multi-start `cost_and_gradient` via
  `Threads.@threads`, (D) embarrassingly parallel forward solves. Uses
  `BT_` constant prefix, median-of-3, box-drawing summary table. This is the
  analog for `scripts/bench_kernels.jl`. See
  `benchmark_threading.jl:44` for `BT_FFTW_THREAD_COUNTS = [1,2,4,8]` — Phase
  29 extends to `[1,2,4,8,16,22]`.
- `scripts/benchmark.jl` (320+ lines) — subprocess-isolated FFTW
  MEASURE-vs-ESTIMATE comparison; introduced the `BENCH_JSON: {…}` regex
  contract + git-tree swap + revert. This is the analog for
  `scripts/bench_solves.jl` + `scripts/bench_solves_run.jl`.
- `scripts/benchmark_optimization.jl` — grid-size benchmarks + multi-start
  with `deepcopy(fiber)` per thread at `:635,704` (this is the canonical
  `deepcopy(fiber)` pattern the planner cites for any Phase 29 parallel
  loops — though the Phase 29 solve bench is subprocess-parallel, not
  thread-parallel, so deepcopy is not triggered).
- `scripts/run_benchmarks.jl` — driver that runs grid-size + time-window +
  continuation + multi-start + parallel gradient validation end-to-end;
  Phase 29 does NOT re-run this.
- `scripts/primitives.jl` — include-guarded pure-function module
  (`_PHASE13_PRIMITIVES_LOADED` pattern) with `@assert` preconditions. This
  is the module-shape analog for `scripts/roofline_model.jl`.
- `scripts/numerical_trust.jl` — threshold + ranked-verdict pattern; analog
  for the Phase 29 regime classifier.
- `scripts/determinism.jl` — `ensure_deterministic_environment()` pins FFTW
  + BLAS to 1 thread. Phase 29 drivers explicitly DO NOT call this (they
  sweep thread counts); document this in each driver header.

---

## 7. Forward-only vs adjoint-only vs full_cg call paths

This is the key content that unblocks Blocker 2 of the plan: the three modes
(`"forward"`, `"adjoint"`, `"full_cg"`) in `scripts/bench_solves_run.jl`
must measure distinct quantities. The current draft has all three calling
`cost_and_gradient(...)` — that makes the "subtract forward from full" trick
recover ≈ 0, because all three branches do identical work.

Below is the exact code pattern each branch must use, with file:line
citations so the worker can be written deterministically.

### 7.1 Forward-only solve (mode = "forward")

The forward-only path is `MultiModeNoise.solve_disp_mmf(uω0, fiber, sim)`
defined at `src/simulation/simulate_disp_mmf.jl:178-200`. It wraps:

```
p_fwd   = get_p_disp_mmf(sim["ωs"], sim["ω0"], fiber["Dω"], fiber["γ"],
                         fiber["hRω"], fiber["one_m_fR"], sim["Nt"],
                         sim["M"], sim["attenuator"])        # :179-180
prob_fwd = ODEProblem(disp_mmf!, uω0, (0, fiber["L"]), p_fwd) # :181
sol_fwd  = solve(prob_fwd, Tsit5(), reltol=1e-8)              # :184
```

Returned `sol_fwd["ode_sol"]` is an ODE `sol` callable as `sol(z)`. NO cost
calculation, NO adjoint. This is pure forward propagation cost.

**Concrete worker snippet for mode == "forward":**

```julia
# One-time setup (outside the timed block — already done above)
# uω0, fiber, sim, band_mask, _ = setup_raman_problem(...)
# φ   = zeros(Nt, M)
# uω0_shaped = @. uω0 * cis(φ)      # φ=0 → uω0_shaped == uω0, but mirror production path

# --- Timed block ---
t_start = time()
sol_fwd = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
elapsed_s = time() - t_start
ũω = sol_fwd["ode_sol"]                  # needed only if you want to validate;
                                          # DO NOT evaluate ũω(L) inside the timed block
J_val = NaN                               # no cost in forward-only mode
iters = Int(length(ũω.t))                 # number of accepted steps (Tsit5)
```

Warmup must call `solve_disp_mmf` once before the timed block so the JIT
compiles `disp_mmf!`, the FFTW plans are allocated, and method-table dispatch
is warm.

### 7.2 Adjoint-only solve (mode = "adjoint")

The adjoint path is `MultiModeNoise.solve_adjoint_disp_mmf(λωL, ũω, fiber, sim)`
at `src/simulation/sensitivity_disp_mmf.jl:294-304`. It requires:
- a forward solution object `ũω` (interpolable ODESolution, not just the
  terminal field — the adjoint RHS calls `ũω(z)` at each step);
- a terminal condition `λωL` = the gradient of the cost w.r.t. the output
  field, produced by `spectral_band_cost(uωf, band_mask)` at
  `scripts/common.jl:261-277`.

The right way to isolate adjoint cost is: run one forward solve OUTSIDE the
timed block, snapshot the ODESolution + terminal cost gradient, then run the
adjoint solve INSIDE the timed block.

**Concrete worker snippet for mode == "adjoint":**

```julia
# --- One-time setup for the adjoint snapshot (OUTSIDE the timed block) ---
sol_fwd      = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
ũω           = sol_fwd["ode_sol"]
L            = fiber["L"]
Dω           = fiber["Dω"]
uωf          = @. cis(Dω * L) * ũω(L)         # lab-frame terminal field
_, λωL       = spectral_band_cost(uωf, band_mask)   # adjoint terminal condition

# --- Timed block (adjoint only) ---
t_start = time()
sol_adj = MultiModeNoise.solve_adjoint_disp_mmf(λωL, ũω, fiber, sim)
elapsed_s = time() - t_start
λ0 = sol_adj(0)                                      # retrieve but don't time this
J_val = NaN
iters = Int(length(sol_adj.t))
```

The outer driver isolates adjoint-only cost by measuring `elapsed_s` here
directly (it is already pure adjoint — the forward runs OUTSIDE the timed
block). No post-hoc subtraction needed. **But** the outer driver can also
double-check by computing `(T_adjoint_mode) ≈ (T_full_cg) − (T_forward)` ±
measurement noise.

### 7.3 Full cost-and-gradient (mode = "full_cg")

Unchanged from the current draft — calls `cost_and_gradient(φ, uω0, fiber, sim, band_mask)`
from `scripts/raman_optimization.jl:73-178`, which does forward + terminal
cost + adjoint + chain rule + (optional) regularizers + log-dB conversion.

**Concrete worker snippet for mode == "full_cg":**

```julia
# --- Timed block ---
t_start = time()
J_val, grad = cost_and_gradient(φ, uω0, fiber, sim, band_mask)
elapsed_s = time() - t_start
iters = 1
```

### 7.4 Outer-driver consistency check

After the subprocess run, the outer driver computes:

```
T_forward_med = median(times for mode="forward")
T_adjoint_med = median(times for mode="adjoint")
T_full_cg_med = median(times for mode="full_cg")
residual      = T_full_cg_med - (T_forward_med + T_adjoint_med)
# residual should be small (cost + chain rule are ~0.1% of wall time at Nt=8192)
# if residual > 10% of T_full_cg → the three modes are NOT measuring distinct work
```

Write `residual` to `solves.jld2` as a consistency metric; the report flags
runs where residual > 10% as suspect.

---

## 8. Plan-flag strategy (ESTIMATE vs MEASURE vs PATIENT)

Per Phase 13 determinism finding and Phase 27 NMDS addendum, production MUST
use `FFTW.ESTIMATE`. The kernel benchmark deliberately builds LOCAL MEASURE
plans to expose hardware peak for comparison. PATIENT is excluded (plan time
is prohibitive and plan quality gain is marginal for single-thread Nt = 8192).

For Kernel A (raw FFT), report BOTH numbers in the memo:
- `AI_measured = (5·Nt·log₂Nt) / (bytes_per_pair × 2)` — compute AI from the
  plan's measured throughput (bytes/sec) × FFT FLOPs.
- `throughput_estimate_gb_s` vs `throughput_measure_gb_s` — ratio is the
  "determinism tax."

For Kernels B–E, use ESTIMATE only (via `get_p_disp_mmf` / `get_p_adjoint_disp_mmf`
which hard-code it). Any attempt to measure with MEASURE plans here would
require editing `src/`, which is out of scope for Phase 29.

---

## 9. Expected budget for the execution pass

Back-of-envelope for the plan's future execution pass on `fiber-raman-burst`:

- Kernel bench: 5 kernels × 6 thread counts (only for FFT) + 1 thread (for
  B–E) × 5 runs × ~200 reps × ~5 ms per kernel call ≈ 5–10 min wall.
- Solve bench: 3 modes × 6 thread counts × (1 warmup + 3 timed) = 72 fresh
  Julia subprocesses. Each subprocess: ~15 s JIT + ~5 s of actual solve
  work = ~20 s wall. Total: 72 × 20 s ≈ **24 min wall**, most of it JIT.
- Report generation: ~5 s pure CPU on `claude-code-host`.

Fits comfortably inside a single 1-hour burst-VM session (~$0.90).

---

## 10. Open Questions

Only one:

**OQ-1** — At M = 1, the Kerr tullio (Kernel B) may be so cheap (AI ≈ 0.07,
~6·Nt FLOPs) that its measurement is dominated by Tullio's threading
overhead rather than arithmetic. If the measured wall time is
indistinguishable from zero (< timing noise floor ~1 µs), the kernel bench
should report `"TRIVIAL_AT_M1"` and defer a real AI measurement to a future
MMF (M ≥ 6) performance phase. The pure-function library's
`kernel_regime_verdict` handles this by returning `"UNKNOWN"` when bytes = 0
or `fit_amdahl` RMSE is larger than the timings themselves.

*(All other measurement paths are unambiguous — forward solve, adjoint solve,
full_cg, raw FFT, Raman convolution all have single established call sites
in the codebase.)*

---

## Summary of commitments locked by this research document

1. **Five kernels only**: raw FFT, Kerr tullio, Raman convolution, forward
   RHS, adjoint RHS. Each with a stated FLOP count, byte count, and AI.
2. **Two machines, two ridges**: 6.5 FLOP/byte on e2, 13 FLOP/byte on c3.
   All production kernels below both ridges → memory-bound everywhere.
3. **Amdahl fit**: least-squares in `1/n` space, formula in §4, implemented
   in `scripts/roofline_model.jl :: fit_amdahl`.
4. **Three modes with distinct measurement paths**: forward-only via
   `solve_disp_mmf`, adjoint-only via `solve_adjoint_disp_mmf` with a
   pre-captured forward `ũω`, full_cg via `cost_and_gradient`. §7 has the
   concrete code snippets.
5. **Prior-phase linkage**: Phase 13 (determinism tax for MEASURE), Phase 22
   (JLD2 bundle convention), Phase 27 (explicit mandate for this phase +
   ESTIMATE-vs-MEASURE reporting requirement), Phase 28 (verdict pattern),
   Phase 35 (scope — performance work is orthogonal to saddle-escape).
6. **Existing benchmark harness inventory**: 6 scripts, each with its
   role locked (analog for a Phase 29 artifact, or explicit non-reuse).
7. **Open questions**: one (OQ-1, Kerr tullio at M=1 may be below timing
   noise floor).
