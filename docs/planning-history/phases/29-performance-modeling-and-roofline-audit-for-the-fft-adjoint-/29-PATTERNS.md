# Phase 29: Performance modeling and roofline audit — Pattern Map

**Mapped:** 2026-04-21
**Files analyzed:** 5 new + 2 planning artifacts (7 total)
**Analogs found:** 5 / 5 new code files have strong analogs in-tree

---

## File Classification

Phase 29 does NOT modify `src/` at all — it is a measurement + modeling
pass. All new code lives under `scripts/` and emits artifacts under
`results/phase29/`. All edits to `.planning/` are phase-scoped.

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/phase29_bench_kernels.jl` | benchmark driver (kernel-level: FFT, Kerr tullio, Raman tullio, single RHS step) | batch / measure-then-report | `scripts/benchmark_threading.jl` | exact (same role, same flow) |
| `scripts/phase29_bench_solves.jl` | benchmark driver (forward solve, adjoint solve, full cost_and_gradient) | subprocess-isolated batch | `scripts/phase15_benchmark.jl` | exact |
| `scripts/phase29_roofline_model.jl` | analysis/modeling (arithmetic intensity, roofline, Amdahl fits) | transform: raw timings → modeled bottlenecks | `scripts/phase13_primitives.jl` (library-style analysis module) | role-match |
| `scripts/phase29_report.jl` | report generator (markdown memo from timing JSON/JLD2) | transform: metrics → markdown | `scripts/phase15_benchmark.jl` (md generation section) + `scripts/numerical_trust.jl` (report assembly) | role-match |
| `test/test_phase29_roofline.jl` | unit/regression test for the model helpers | test | `test/test_phase28_trust_report.jl` | exact |
| `.planning/phases/29-.../29-01-PLAN.md` | plan doc | phase-scoped | `.planning/phases/28-.../28-01-PLAN.md` | exact |
| `.planning/phases/29-.../29-REPORT.md` | final memo (roofline + Amdahl verdict) | phase-scoped | `.planning/phases/27-.../27-REPORT.md` | exact |

Notes:
- No `src/` edits. `benchmark_threading.jl` already touches `setup_raman_problem` read-only; Phase 29 follows that discipline.
- The "modeling" file (`phase29_roofline_model.jl`) is pure analysis on timing data — no physics, no ODE calls. It is the one file with no exact analog because the repo has no prior roofline code; use `phase13_primitives.jl` for the **module shape** (include guard, constants, pure functions, docstrings with `# Arguments / # Returns`) and the Phase-27 report for the **domain language** (roofline, Amdahl, Gustafson, memory-bound / compute-bound).

---

## Pattern Assignments

### `scripts/phase29_bench_kernels.jl` (benchmark driver, kernel-level)

**Analog:** `scripts/benchmark_threading.jl`

**Header + imports pattern** (`benchmark_threading.jl:1-28`):

```julia
"""
Threading/Parallelism Benchmark for Fiber Raman Suppression
...
Run:
  julia -t 1 --project=. scripts/benchmark_threading.jl   # FFTW only
  julia -t 8 --project=. scripts/benchmark_threading.jl   # full benchmark
"""

using Printf
using LinearAlgebra
using FFTW
using Logging
using Statistics
ENV["MPLBACKEND"] = "Agg"
using MultiModeNoise
using Optim
using Tullio

include("common.jl")
include("raman_optimization.jl")

if abspath(PROGRAM_FILE) == @__FILE__
    # ... main body ...
end # if main script
```

Copy verbatim — replace the first docstring with Phase 29's kernel-benchmark
scope. Keep the `abspath(PROGRAM_FILE) == @__FILE__` guard so the file can be
`include`d by `phase29_report.jl` without re-running.

**Constant-prefix convention** (`benchmark_threading.jl:32-44`, STATE.md
"Script Constant Prefixes" rule):

```julia
const BT_NT = 2^13                    # grid size for benchmarks
const BT_L_FIBER = 1.0                # fiber length [m]
const BT_P_CONT = 0.05                # continuum power [W]
const BT_N_FFT_PAIRS = 100            # FFT forward+inverse pairs for FFTW benchmark
const BT_N_RUNS = 3                   # repetitions per benchmark (take median)
const BT_FFTW_THREAD_COUNTS = [1, 2, 4, 8]
```

Use `P29K_` prefix (Phase 29 Kernel) for this file's constants:
`P29K_NT`, `P29K_N_FFT_PAIRS`, `P29K_N_RUNS`, `P29K_JULIA_THREAD_COUNTS`,
`P29K_FFTW_THREAD_COUNTS`.

**Setup + JIT-warmup pattern** (`benchmark_threading.jl:60-78`):

```julia
# Setup problem once — reuse across all benchmarks
println("Setting up Raman optimization problem...")
flush(stdout)
uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
    L_fiber=BT_L_FIBER, P_cont=BT_P_CONT, Nt=BT_NT,
    fiber_preset=:SMF28, β_order=3, time_window=10.0)
Nt = sim["Nt"]; M = sim["M"]
@printf("  Setup complete: Nt=%d, M=%d\n\n", Nt, M)
flush(stdout)

# JIT warmup: run one cost_and_gradient to compile everything
println("JIT warmup (first cost_and_gradient call)...")
flush(stdout)
φ_warmup = zeros(Nt, M)
t_warmup_start = time()
cost_and_gradient(φ_warmup, uω0, fiber, sim, band_mask)
t_warmup = time() - t_warmup_start
@printf("  JIT warmup took %.1f s\n\n", t_warmup)
```

Copy exactly. The rule "warmup then measure" is what makes all timing numbers
steady-state rather than precompile-dominated.

**Median-of-N timer** (`benchmark_threading.jl:80-89`):

```julia
function timed_median(f, n_runs)
    times = Float64[]
    for _ in 1:n_runs
        t0 = time()
        f()
        push!(times, time() - t0)
    end
    return median(times), times
end
```

Copy as-is. This is the project's convention for microbenchmarks and is
already used in Phase 15 benchmarks. Do NOT switch to `BenchmarkTools.@btime`
— the rest of the codebase uses `time()` + median.

**Per-kernel measurement loop** (`benchmark_threading.jl:111-131`):

```julia
fft_times = Dict{Int, Float64}()
data_fft = randn(ComplexF64, Nt, M)

for n_fftw in BT_FFTW_THREAD_COUNTS
    FFTW.set_num_threads(n_fftw)
    # Create fresh plans with FFTW.MEASURE for this thread count
    plan_f = plan_fft!(copy(data_fft), 1; flags=FFTW.MEASURE)
    plan_i = plan_ifft!(copy(data_fft), 1; flags=FFTW.MEASURE)

    buf = copy(data_fft)
    # Warmup
    plan_f * buf
    plan_i * buf

    med_t, _ = timed_median(BT_N_RUNS) do
        for _ in 1:BT_N_FFT_PAIRS
            plan_f * buf
            plan_i * buf
        end
    end
    fft_times[n_fftw] = med_t
    @printf("    FFTW threads=%d: %.4f s (%d FFT pairs)\n", n_fftw, med_t, BT_N_FFT_PAIRS)
    flush(stdout)
end
```

Phase 29 kernels to benchmark, each as an isolated loop like this:
1. Raw FFT throughput — already written above, reuse directly.
2. Kerr contraction — copy from `benchmark_threading.jl:207-223` (`@tullio`
   block over `γ[i,j,k,l] · (v·v + w·w)`).
3. Raman frequency-convolution (multiply + IFFT on `(Nt, M, M)`).
4. Single `disp_mmf!` call — call through `get_p_disp_mmf` to hit the real
   ODE RHS path.
5. Single `adjoint_disp_mmf!` call — call through `get_p_adjoint_disp_mmf`.

**NOTE on Phase 15 over Phase 29 contradiction — critical:**
Phase 15 (`src/simulation/*.jl`) hard-codes `flags=FFTW.ESTIMATE` for
determinism. `benchmark_threading.jl:114` uses `FFTW.MEASURE` for its own
plans because it's measuring FFT throughput, not running the production
pipeline. Phase 29 kernel-level FFT microbenchmarks SHOULD use
`FFTW.MEASURE` locally (to expose hardware peak) AND also report
`FFTW.ESTIMATE` throughput so the memo can quote the real-pipeline number.
Do NOT edit `src/simulation/*.jl` to do this; create local plans for the
kernel bench.

**Results-table write-back** (`benchmark_threading.jl:180-186`):

```julia
results_table["A. FFTW threading"] = (
    t_1thread = cg_fftw_baseline,
    t_nthread = cg_fftw_times[best_fftw_threads],
    speedup = best_fftw_speedup,
    n_threads = best_fftw_threads,
    notes = "FFTW.set_num_threads() — free, no code changes"
)
```

Same `NamedTuple` shape for all kernels, keyed by kernel name. Makes the
summary table trivial to render later.

**Summary table format** (`benchmark_threading.jl:420-430`, box-drawing
convention):

```julia
println("╔══════════════════════════════╦══════════════╦══════════════╦═══════════╦═══════════════════════════════════════════════╗")
println("║        Opportunity           ║  1-thread [s]║  N-thread [s]║  Speedup  ║  Notes                                        ║")
println("╠══════════════════════════════╬══════════════╬══════════════╬═══════════╬═══════════════════════════════════════════════╣")
for key in ["A. FFTW threading", "B. Tullio threading", "C. Multi-start optim", "D. Parallel fwd solves"]
    if haskey(results_table, key)
        local entry = results_table[key]
        @printf("║ %-28s ║ %10.3f   ║ %10.3f   ║ %7.2fx  ║  %-45s ║\n",
            key, entry.t_1thread, entry.t_nthread, entry.speedup, entry.notes)
    end
end
println("╚══════════════════════════════╩══════════════╩══════════════╩═══════════╩═══════════════════════════════════════════════╝")
```

This is the project-wide convention for terminal summary tables (also used in
`benchmark_optimization.jl:98-100`). Mandatory — don't switch to DataFrames
or Markdown-only output.

**Data persistence pattern** (`phase15_benchmark.jl:47-51, 65`):

```julia
const BENCHMARK_DIR  = joinpath(PROJECT_ROOT, "results", "raman", "phase15")
const BENCHMARK_MD   = joinpath(BENCHMARK_DIR, "benchmark.md")
const BENCHMARK_JLD2 = joinpath(BENCHMARK_DIR, "benchmark.jld2")
mkpath(BENCHMARK_DIR)
```

For Phase 29: `results/phase29/` with `kernels.jld2`, `solves.jld2`,
`roofline.md`. Use JLD2 for raw numbers (so the report can re-analyse
without re-running the bench), markdown for human-readable memo.

---

### `scripts/phase29_bench_solves.jl` (benchmark driver, subprocess-isolated)

**Analog:** `scripts/phase15_benchmark.jl`

**Why a separate driver:** full forward+adjoint solves are expensive and
need subprocess isolation for clean steady-state numbers (Phase 15 already
learned this — compiled method caching and FFT planning state leak across
calls in a single process).

**Subprocess runner pattern** (`phase15_benchmark.jl:120-147`):

```julia
function _run_one_subprocess(mode::AbstractString, tag::AbstractString)
    cmd = `julia --project=$(PROJECT_ROOT) $(WORKER_SCRIPT) $(mode) $(tag)`
    @info "  spawn: $(mode) ($(tag))"
    t0_wall = time()
    out = read(cmd, String)
    wall_total = time() - t0_wall
    m = match(r"BENCH_JSON:\s*(\{.*\})", out)
    if m === nothing
        @error "Subprocess produced no BENCH_JSON line" mode tag
        println(stderr, "----- SUBPROCESS OUTPUT -----")
        println(stderr, out)
        println(stderr, "----- END OUTPUT -----")
        error("benchmark worker failed (mode=$mode tag=$tag)")
    end
    payload = JSON3.read(m[1])
    elapsed = Float64(payload["elapsed_s"])
    J       = Float64(payload["J"])
    # ...
    return (elapsed_s=elapsed, J=J, ...)
end
```

Copy wholesale. Phase 29's `mode` argument becomes the kernel-or-solve tag
(`"forward"`, `"adjoint"`, `"full_cg"`, `"multi_start_4"`), and the worker
file (`scripts/_phase29_bench_solves_run.jl` — analog to
`_phase15_benchmark_run.jl`) prints `BENCH_JSON: {...}` with
`elapsed_s / J / iters / Nt / M / julia_threads / fftw_threads`.

**Warmup-then-measure, N fresh subprocesses** (`phase15_benchmark.jl:167-177`):

```julia
@info "=== ESTIMATE leg: 1 warm-up + $N_RUNS timed runs (fresh subprocess each) ==="
_warm_est = _run_one_subprocess("estimate", "WARMUP")
estimate_times = Float64[]
for i in 1:N_RUNS
    r = _run_one_subprocess("estimate", "RUN-$i")
    push!(estimate_times, r.elapsed_s)
    # ...
end
```

Same structure for Phase 29 — per thread-count leg: 1 warmup + N timed
subprocesses. The serial-fraction measurement NEEDS fresh subprocesses
because precompile + first-call overhead confounds Amdahl-style fits
badly.

**Git-tree safety pattern** (`phase15_benchmark.jl:187-219`, `try / finally`
swap + revert): NOT needed for Phase 29 — we are not patching source. The
phase explicitly says "we model kernels before tuning them" (CONTEXT.md).
Keep the `try / finally` only if you end up doing before/after FFTW thread
comparisons that require setting env vars per subprocess — the wrapper
should still revert env to a known state.

**Constants** — use `P29S_` prefix:

```julia
const P29S_NT = 2^13
const P29S_L_FIBER = 2.0       # SMF-28 canonical (see CLAUDE.md standard run)
const P29S_P_CONT = 0.2
const P29S_N_RUNS = 3
const P29S_THREAD_COUNTS = [1, 2, 4, 8, 16, 22]  # 22 = burst VM ceiling
```

---

### `scripts/phase29_roofline_model.jl` (analysis library)

**Analog:** `scripts/phase13_primitives.jl` (for module shape) +
`scripts/numerical_trust.jl` (for verdict/threshold language)

**Module shape** (`phase13_primitives.jl:1-53`):

```julia
# ═══════════════════════════════════════════════════════════════════════════════
# Phase 29 Roofline Model — arithmetic intensity, bandwidth, Amdahl/Gustafson
# ═══════════════════════════════════════════════════════════════════════════════
#
# READ-ONLY consumer of timing JLD2 artifacts produced by
# scripts/phase29_bench_kernels.jl and scripts/phase29_bench_solves.jl.
# This module DOES NOT run simulations. All it does is turn timings into
# modeled bottlenecks (memory-bound vs compute-bound, serial fraction,
# speedup ceiling).
#
# Constants use the P29M_ prefix (Phase 29 Modeling).
#
# Library API:
#   arithmetic_intensity(flops, bytes)                       -> Float64 (FLOP/byte)
#   roofline_bound(AI, peak_flops, peak_bw)                  -> NamedTuple (bound, regime)
#   fit_amdahl(n_threads, times; method=:least_squares)      -> NamedTuple (p, speedup_inf, rmse)
#   fit_gustafson(n_threads, times_fixed_work_per_thread)    -> NamedTuple (s, speedup_n)
#   kernel_regime_verdict(AI, bound_regime)                  -> String
#   assemble_roofline_memo(bench_data; hw_profile)           -> String (markdown)
#
# All functions are pure and allocate their outputs. They do not mutate inputs.
# ═══════════════════════════════════════════════════════════════════════════════

using LinearAlgebra
using Statistics
using Printf

if !(@isdefined _PHASE29_ROOFLINE_LOADED)

const _PHASE29_ROOFLINE_LOADED = true
const P29M_VERSION = "1.0.0"
const P29M_MEMORY_BOUND_AI_THRESHOLD = 1.0   # FLOP/byte below which kernel is memory-bound
# ... etc
```

Copy pattern: banner block, READ-ONLY note, API list in header, include
guard, module-prefixed constants. Include guard is MANDATORY (project
convention per CLAUDE.md "Common Patterns").

**Thresholds + verdicts pattern** (`numerical_trust.jl:4-37`):

```julia
const TRUST_THRESHOLDS = (
    energy_drift_pass = 1e-4,
    energy_drift_marginal = 1e-3,
    # ...
)

const _TRUST_RANK = Dict("PASS" => 0, "MARGINAL" => 1, "SUSPECT" => 2, "NOT_RUN" => 3)

function trust_verdict(value::Real, pass::Real, marginal::Real)
    !isfinite(value) && return "NOT_RUN"
    value <= pass && return "PASS"
    value <= marginal && return "MARGINAL"
    return "SUSPECT"
end
```

For Phase 29 the verdicts are regime labels ("MEMORY_BOUND", "COMPUTE_BOUND",
"SERIAL_BOUND", "AMDAHL_SATURATED"). Use the same **shape** — named-tuple
of thresholds, ranked verdict function — so the report generator reads like
the trust report already in the codebase.

**Docstring style** (`phase13_primitives.jl:59-80`):

```julia
"""
    omega_vector(sim_omega0, sim_Dt, Nt)

Build the per-bin **angular-frequency offset** vector (rad/ps) in FFT order
from the scalar ω₀ and Δt stored inside the existing JLD2 files.

The convention in this codebase (see STATE.md Unit Conventions) is:
- `sim_omega0` stored in rad/ps (carrier ω₀)
- `sim_Dt` stored in picoseconds
- spectral arrays in FFT order (not fftshifted)

...
"""
function omega_vector(sim_omega0::Real, sim_Dt::Real, Nt::Integer)
    @assert sim_Dt > 0 "sim_Dt must be positive, got $sim_Dt"
    @assert Nt > 0 && ispow2(Nt) "Nt must be a positive power of 2, got $Nt"
    # ...
end
```

Mandatory for every public helper: Julia `"""..."""` docstring, stated
units, `@assert` preconditions at entry. Especially important here because
the modeling functions take raw numbers that MUST be in consistent units
(FLOPS/s, bytes/s, seconds — not mixed).

---

### `scripts/phase29_report.jl` (report generator)

**Analog:** `scripts/phase15_benchmark.jl` (markdown assembly section,
`:229-298`) + `scripts/numerical_trust.jl` (report Dict assembly, `:105-180`)

**Markdown template pattern** (`phase15_benchmark.jl:231-299`):

```julia
md = """
# Phase 15 Plan 01 — Performance Benchmark: FFTW.MEASURE vs FFTW.ESTIMATE

**Generated:** $(now())
**Config:** SMF-28 canonical, L=2.0 m, P=0.2 W, Nt=8192, max_iter=30, seed=42
**Thread pins:** FFTW threads = 1, BLAS threads = 1
**Runs per leg:** $(N_RUNS) timed, each in a fresh Julia subprocess (1 warm-up per leg discarded)
**Timing scope:** only `optimize_spectral_phase` wall time (excludes Julia startup, precompile, setup)

## Wall-time Summary

| Mode          | Run 1 | Run 2 | Run 3 | Mean     | Std      | Slowdown vs MEASURE |
|---------------|-------|-------|-------|----------|----------|---------------------|
| FFTW.MEASURE  | $(fmt_row(measure_times)) | $(@sprintf("%.2f s", mea_mean)) | ...
| FFTW.ESTIMATE | $(fmt_row(estimate_times)) | $(@sprintf("%.2f s", est_mean)) | ...

## J Final Consistency
...
"""
write(BENCHMARK_MD, md)
```

Adopt the same **triple-quoted-string + interpolation** approach with these
sections for Phase 29:
1. Header with config, hardware, timestamp.
2. Kernel wall-time table (FFT, Kerr, Raman, forward RHS, adjoint RHS).
3. Forward/adjoint full-solve table across thread counts.
4. Amdahl fit table (measured p, extrapolated speedup ceiling).
5. Roofline verdict per kernel (memory-bound / compute-bound / serial-bound).
6. Recommendations (mirror `benchmark_threading.jl:434-470` recommendation
   structure).

**Final-memo tone** — match `27-REPORT.md`:

```markdown
# Phase 27 Report — Numerical Analysis Audit and CS 4220 / NMDS Application Roadmap

## Executive Verdict

The CS 4220 material is highly relevant to this project, but not because the
repo is "missing advanced math" in general. The best applications are targeted:

1. **Conditioning and scaling** are the clearest open numerical problem.
...
```

Phase 29's `29-REPORT.md` should lead with an "Executive Verdict" paragraph
naming the dominant bottleneck (FFT bandwidth / serial orchestration / Tullio
contraction / ODE stepping overhead) and a single-line recommendation on
`-t N` and burst-VM usage. Then tables. Then per-kernel analysis. This
matches how Rivera Lab reads reports — verdict first, data second.

---

### `test/test_phase29_roofline.jl`

**Analog:** `test/test_phase28_trust_report.jl`

Covers the pure functions in `phase29_roofline_model.jl`:
- `arithmetic_intensity` returns correct FLOP/byte for known kernels.
- `fit_amdahl` recovers `p` exactly from synthetic `(1−p) + p/n` data.
- `roofline_bound` picks correct regime at known AI (below/above ridge).
- `assemble_roofline_memo` produces markdown with required section headers.

Pattern: `using Test; @testset ... end` blocks calling the pure functions
with canned numbers. No physics, no ODE, no subprocess — unit-test speed.

---

## Shared Patterns

### Determinism / thread pinning at script entry
**Source:** `scripts/determinism.jl` + `scripts/benchmark_threading.jl:189`
**Apply to:** All Phase 29 Julia scripts.

```julia
# At top of each driver, after includes:
FFTW.set_num_threads(1)        # default pin; override per-benchmark block
# Do NOT call ensure_deterministic_environment() in kernel benches that
# deliberately sweep FFTW threads — it pins to 1 permanently.
```

Phase 29 is the ONLY place in the repo that legitimately varies thread
counts. Document clearly at top of each file: "this script intentionally
overrides the Phase 15 FFTW-threads=1 invariant for benchmarking; it does
NOT use the optimized phi_opt for any downstream physics."

### Logging convention
**Source:** CLAUDE.md "Logging" rule + `benchmark_threading.jl:51-57`
**Apply to:** All Phase 29 drivers.

```julia
@info "Phase 29 kernel benchmark" Nt=P29K_NT M=M julia_threads=Threads.nthreads() fftw_threads=FFTW.get_num_threads()
# ...
@info @sprintf("  Kerr contraction: %.4f s (%d reps)", med_t, n_reps)
```

`@info` for run summaries, `@debug` for per-rep, `@warn` for anomalies. Use
`@sprintf` for formatting (project-wide).

### `deepcopy(fiber)` per-thread copy
**Source:** CLAUDE.md "Running Simulations — Rule 3" + `benchmark_optimization.jl:635,704`
**Apply to:** Any parallel benchmark loop in Phase 29.

```julia
Threads.@threads for i in 1:n_tasks
    fiber_local = deepcopy(fiber)      # MANDATORY per-thread copy
    cost_and_gradient(φ_randoms[i], uω0, fiber_local, sim, band_mask)
end
```

If Phase 29 exercises `Threads.@threads` to measure multi-start speedup,
this is non-negotiable. The `fiber` dict has mutable fields (`fiber["zsave"]`)
the ODE solver writes — sharing across threads races.

### Results directory layout
**Source:** `phase15_benchmark.jl:49-51`, STATE.md
**Apply to:** All Phase 29 artifacts.

```
results/phase29/
├── kernels.jld2         # raw kernel timings
├── solves.jld2          # raw forward/adjoint solve timings
├── roofline.md          # the memo (human-readable)
├── amdahl_fits.json     # per-kernel fits for re-analysis
└── hw_profile.json      # machine this was measured on (cpuinfo, meminfo)
```

**Hardware profile capture is new** — add a short helper that snapshots
`/proc/cpuinfo`, `/proc/meminfo` (on Linux / burst VM) or `sysctl -a
machdep.cpu` (Mac) into JSON. Without it the roofline numbers are
un-reproducible across machines.

### Burst-VM compute discipline
**Source:** CLAUDE.md "Running Simulations — Compute Discipline"
**Apply to:** All Phase 29 heavy runs.

- Kernel microbenchmarks at `Nt=8192, M=1` on `claude-code-host` are
  borderline; prefer burst VM to avoid Claude Code memory contention.
- Forward+adjoint full-solve benchmarks → burst VM always, through
  `~/bin/burst-run-heavy P29-roofline 'julia -t N --project=. scripts/phase29_bench_solves.jl'`.
- Thread-sweep studies (measuring scaling from `-t 1` to `-t 22`) need the
  22-core burst VM specifically (c3-highcpu-22).

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | | | All Phase 29 files have close analogs in-tree. |

The closest-to-no-analog case is `phase29_roofline_model.jl` — no prior
roofline code exists in the repo — but the module shape, constant
prefix, and verdict-threshold patterns from `phase13_primitives.jl` and
`numerical_trust.jl` cover the code-shape needs. The ONLY new knowledge
is domain (FLOP counts for each kernel, memory-traffic estimates, Amdahl
fitting) and that belongs in RESEARCH.md, not patterns.

---

## Metadata

**Analog search scope:**
- `/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression/scripts/**/*.jl`
- `/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression/src/**/*.jl`
- `/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression/test/**/*.jl`
- `/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression/.planning/phases/15-.../`
- `/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression/.planning/phases/27-.../`
- `/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression/.planning/phases/28-.../`

**Key analogs consulted (by path):**
- `scripts/benchmark_threading.jl` — kernel-level FFTW / Tullio / multi-start benchmark
- `scripts/benchmark_optimization.jl` — grid-size benchmarks, multi-start with `deepcopy(fiber)`
- `scripts/phase15_benchmark.jl` — subprocess-isolated timing driver + md generation
- `scripts/phase13_primitives.jl` — pure-function analysis module with include guard
- `scripts/numerical_trust.jl` — threshold/verdict/report assembly pattern
- `scripts/determinism.jl` — FFTW/BLAS thread-pinning convention
- `src/simulation/simulate_disp_mmf.jl` — forward RHS to benchmark
- `src/simulation/sensitivity_disp_mmf.jl` — adjoint RHS to benchmark
- `.planning/phases/27-.../27-REPORT.md` — report tone ("Executive Verdict" first)
- `.planning/phases/28-.../28-01-PLAN.md` — plan doc shape for phase definition mode

**Pattern extraction date:** 2026-04-21
