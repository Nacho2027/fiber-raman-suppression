# ═══════════════════════════════════════════════════════════════════════════════
# Phase 15 Plan 01 — Performance Benchmark: FFTW.MEASURE vs FFTW.ESTIMATE
# ═══════════════════════════════════════════════════════════════════════════════
#
# Quantifies the wall-time cost of the Phase 15 determinism fix.
#
# Method (subprocess-isolated — fresh Julia process per run):
#   1. ESTIMATE leg: 1 warm-up run + 3 timed runs, each in its own subprocess.
#      Source code is already at `flags=FFTW.ESTIMATE` (HEAD state post-Phase-15).
#   2. MEASURE leg: swap the 16 occurrences of `flags=FFTW.ESTIMATE` in the 4
#      `src/simulation/*.jl` files back to `flags=FFTW.MEASURE`. Run 1 warm-up +
#      3 timed runs, each in a fresh subprocess (so compiled methods reflect the
#      MEASURE source). Then REVERT — always, in a `finally` block.
#
# Why subprocess isolation matters:
#   - A single Julia process caches compiled methods. Switching FFTW.MEASURE →
#     ESTIMATE mid-process would leave compiled code that targets the old plan.
#   - Fresh subprocesses guarantee each timed run pays the same (already-paid)
#     precompile cost and uses the source as currently checked out on disk.
#   - Each leg's first subprocess is a WARM-UP (discarded) so the 3 timed runs
#     represent steady-state wall clock.
#
# Timing scope: ONLY the inner `optimize_spectral_phase` call — Julia startup,
# precompilation, and problem setup are all excluded. See
# scripts/benchmark_run.jl for how the worker enforces this.
#
# Config: SMF-28 canonical (L=2m, P=0.2W, Nt=8192, max_iter=30) — production-grade
# so the measured wall time reflects real research-run cost.
#
# Output:
#   - results/raman/phase15/benchmark.md   (markdown table + analysis)
#   - results/raman/phase15/benchmark.jld2 (raw timing data for re-analysis)
#
# Run:  julia --project=. scripts/benchmark.jl
# ═══════════════════════════════════════════════════════════════════════════════

using Printf
using Statistics
using Dates
using JLD2
using JSON3

# ─────────────────────────────────────────────────────────────────────────────
# Paths and constants
# ─────────────────────────────────────────────────────────────────────────────

const PROJECT_ROOT   = abspath(joinpath(@__DIR__, ".."))
const WORKER_SCRIPT  = joinpath(@__DIR__, "benchmark_run.jl")
const BENCHMARK_DIR  = joinpath(PROJECT_ROOT, "results", "raman", "phase15")
const BENCHMARK_MD   = joinpath(BENCHMARK_DIR, "benchmark.md")
const BENCHMARK_JLD2 = joinpath(BENCHMARK_DIR, "benchmark.jld2")

const SIM_FILES = [
    joinpath(PROJECT_ROOT, "src", "simulation", "simulate_disp_mmf.jl"),
    joinpath(PROJECT_ROOT, "src", "simulation", "simulate_disp_gain_mmf.jl"),
    joinpath(PROJECT_ROOT, "src", "simulation", "sensitivity_disp_mmf.jl"),
]

const N_RUNS = 3                   # timed runs per leg
# Total `flags=FFTW.X` sites across the 3 live simulation files. The dead
# `simulate_disp_gain_smf.jl` placeholder path was removed in Phase 25, so the
# benchmark only swaps flags in code that is still part of the project.
const EXPECTED_FLAG_COUNT = 14

mkpath(BENCHMARK_DIR)

# ─────────────────────────────────────────────────────────────────────────────
# Planner-flag swap helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    _swap_planner_flag!(from, to) -> Int

Mechanically replace `flags=FFTW.<from>` with `flags=FFTW.<to>` in every file in
`SIM_FILES`. Returns total substitutions performed.
"""
function _swap_planner_flag!(from::String, to::String)
    total = 0
    from_tok = "flags=FFTW." * from
    to_tok   = "flags=FFTW." * to
    for path in SIM_FILES
        src = read(path, String)
        n = count(from_tok, src)
        if n > 0
            new_src = replace(src, from_tok => to_tok)
            write(path, new_src)
            total += n
        end
    end
    return total
end

"""
    _count_planner_flag(flag) -> Int

Count occurrences of `flags=FFTW.<flag>` across all files in `SIM_FILES`.
"""
function _count_planner_flag(flag::String)
    tok = "flags=FFTW." * flag
    total = 0
    for path in SIM_FILES
        total += count(tok, read(path, String))
    end
    return total
end

# ─────────────────────────────────────────────────────────────────────────────
# Subprocess runner
# ─────────────────────────────────────────────────────────────────────────────

"""
    _run_one_subprocess(mode, tag) -> NamedTuple

Spawn a fresh `julia --project=<root> scripts/benchmark_run.jl <mode> <tag>`
subprocess and parse its `BENCH_JSON:` line. Raises if the sentinel is missing.

Returns (elapsed_s, J, iters, Nt, M, startup_s) — startup_s is the full
wall-time of the subprocess (Julia startup + precompile + setup + optimize),
useful for sanity-checking the fraction that was the optimize call itself.
"""
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
    iters   = Int(payload["iters"])
    Nt_a    = Int(payload["Nt"])
    M_a     = Int(payload["M"])
    @info @sprintf(
        "  [%s/%s] optimize=%.2fs  total_subproc=%.2fs  iters=%d  J=%.4e",
        mode, tag, elapsed, wall_total, iters, J,
    )
    return (elapsed_s=elapsed, J=J, iters=iters, Nt=Nt_a, M=M_a,
            subproc_wall_s=wall_total)
end

# ─────────────────────────────────────────────────────────────────────────────
# Sanity-check HEAD state: must be ESTIMATE post-Phase-15
# ─────────────────────────────────────────────────────────────────────────────

n_estimate_head = _count_planner_flag("ESTIMATE")
n_measure_head  = _count_planner_flag("MEASURE")
@info "HEAD planner-flag counts" ESTIMATE=n_estimate_head MEASURE=n_measure_head
@assert n_estimate_head == EXPECTED_FLAG_COUNT (
    "Expected $EXPECTED_FLAG_COUNT ESTIMATE occurrences at HEAD, found $n_estimate_head"
)
@assert n_measure_head == 0 (
    "Expected 0 MEASURE occurrences at HEAD, found $n_measure_head"
)

# ─────────────────────────────────────────────────────────────────────────────
# ESTIMATE leg — HEAD state, no src/ modification needed
# ─────────────────────────────────────────────────────────────────────────────

@info "=== ESTIMATE leg: 1 warm-up + $N_RUNS timed runs (fresh subprocess each) ==="
_warm_est = _run_one_subprocess("estimate", "WARMUP")
estimate_times = Float64[]
estimate_Js    = Float64[]
estimate_iters = Int[]
for i in 1:N_RUNS
    r = _run_one_subprocess("estimate", "RUN-$i")
    push!(estimate_times, r.elapsed_s)
    push!(estimate_Js,    r.J)
    push!(estimate_iters, r.iters)
end

# ─────────────────────────────────────────────────────────────────────────────
# MEASURE leg — swap src/simulation/* back to FFTW.MEASURE, run, ALWAYS revert
# ─────────────────────────────────────────────────────────────────────────────

measure_times = Float64[]
measure_Js    = Float64[]
measure_iters = Int[]

try
    @info "Swapping src/simulation/*.jl: ESTIMATE -> MEASURE for the MEASURE leg"
    n_swapped = _swap_planner_flag!("ESTIMATE", "MEASURE")
    @info "Swapped $n_swapped plan-builder sites to MEASURE"

    n_mid_est = _count_planner_flag("ESTIMATE")
    n_mid_mea = _count_planner_flag("MEASURE")
    @assert n_mid_est == 0 "post-swap ESTIMATE count=$n_mid_est, expected 0"
    @assert n_mid_mea == EXPECTED_FLAG_COUNT (
        "post-swap MEASURE count=$n_mid_mea, expected $EXPECTED_FLAG_COUNT"
    )

    @info "=== MEASURE leg: 1 warm-up + $N_RUNS timed runs (fresh subprocess each) ==="
    _warm_mea = _run_one_subprocess("measure", "WARMUP")
    for i in 1:N_RUNS
        r = _run_one_subprocess("measure", "RUN-$i")
        push!(measure_times, r.elapsed_s)
        push!(measure_Js,    r.J)
        push!(measure_iters, r.iters)
    end

finally
    @info "Reverting src/simulation/*.jl: MEASURE -> ESTIMATE"
    n_reverted = _swap_planner_flag!("MEASURE", "ESTIMATE")
    @info "Reverted $n_reverted plan-builder sites back to ESTIMATE"
    n_post_est = _count_planner_flag("ESTIMATE")
    n_post_mea = _count_planner_flag("MEASURE")
    @assert n_post_est == EXPECTED_FLAG_COUNT (
        "revert failed: ESTIMATE count=$n_post_est"
    )
    @assert n_post_mea == 0 "revert failed: MEASURE count=$n_post_mea"
    @info "HEAD state restored (ESTIMATE=$n_post_est, MEASURE=$n_post_mea)"
end

# ─────────────────────────────────────────────────────────────────────────────
# Analysis + report
# ─────────────────────────────────────────────────────────────────────────────

est_mean = mean(estimate_times); est_std = std(estimate_times)
mea_mean = mean(measure_times);  mea_std = std(measure_times)
slowdown_pct = (est_mean - mea_mean) / mea_mean * 100

fmt_row(ts) = join((@sprintf("%.2f s", t) for t in ts), " | ")

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
| FFTW.MEASURE  | $(fmt_row(measure_times)) | $(@sprintf("%.2f s", mea_mean)) | ±$(@sprintf("%.2f s", mea_std)) | baseline |
| FFTW.ESTIMATE | $(fmt_row(estimate_times)) | $(@sprintf("%.2f s", est_mean)) | ±$(@sprintf("%.2f s", est_std)) | $(@sprintf("%+.1f%%", slowdown_pct)) |

## J Final Consistency

| Mode          | J_final (run 1) | J_final (run 2) | J_final (run 3) | max-min |
|---------------|-----------------|-----------------|-----------------|---------|
| FFTW.MEASURE  | $(@sprintf("%.6e", measure_Js[1])) | $(@sprintf("%.6e", measure_Js[2])) | $(@sprintf("%.6e", measure_Js[3])) | $(@sprintf("%.3e", maximum(measure_Js)-minimum(measure_Js))) |
| FFTW.ESTIMATE | $(@sprintf("%.6e", estimate_Js[1])) | $(@sprintf("%.6e", estimate_Js[2])) | $(@sprintf("%.6e", estimate_Js[3])) | $(@sprintf("%.3e", maximum(estimate_Js)-minimum(estimate_Js))) |

**Empirical cross-process determinism:** if ESTIMATE `max-min` is 0.0, multiple
independent Julia processes converged to bit-identical L-BFGS minima — the
strongest possible reproducibility signal. MEASURE `max-min` > 0.0 shows the
original bug (different processes pick different FFT algorithms → different
numerics → compounded divergence through L-BFGS iterations).

## Iteration Counts

| Mode          | Run 1 iters | Run 2 iters | Run 3 iters |
|---------------|-------------|-------------|-------------|
| FFTW.MEASURE  | $(measure_iters[1]) | $(measure_iters[2]) | $(measure_iters[3]) |
| FFTW.ESTIMATE | $(estimate_iters[1]) | $(estimate_iters[2]) | $(estimate_iters[3]) |

## Interpretation

- **Measured slowdown: $(@sprintf("%+.1f%%", slowdown_pct))**. This is the wall-time cost of the
  Phase 15 deterministic-environment guarantee on the canonical SMF-28 config.
- FFTW.ESTIMATE uses a heuristic (no timed microbenchmarks) for plan selection,
  so the chosen algorithm may not always be the fastest variant — but it IS
  always the same variant across runs, which eliminates the plan-selection
  non-determinism observed in Phase 13 Plan 01.
- **Plan-15 acceptance threshold:** +30% slowdown. At $(@sprintf("%+.1f%%", slowdown_pct)), the
  cost $(abs(slowdown_pct) <= 30 ? "is within budget" : "EXCEEDS the budget and triggers the FFTW.PATIENT wisdom-file escalation discussed in the plan Deviations section") — the deterministic fix $(abs(slowdown_pct) <= 30 ? "stays" : "should be revisited").

## Method

Each timed run is a fresh `julia --project=.` subprocess spawned from the driver
(`scripts/benchmark.jl`) invoking the worker
(`scripts/benchmark_run.jl`). The worker:

1. Pins `FFTW.set_num_threads(1)` and `BLAS.set_num_threads(1)`.
2. Includes the pipeline (`scripts/common.jl` + `scripts/raman_optimization.jl`),
   which triggers precompilation of any stale methods.
3. Sets up the Raman problem (NOT timed).
4. Calls `optimize_spectral_phase` — this, and ONLY this, is timed via `time()`.
5. Prints a single `BENCH_JSON: {...}` line the driver parses.

A warm-up subprocess per leg is discarded so the 3 timed runs reflect the
steady-state optimizer cost, not first-run precompile overhead.

The MEASURE leg is produced by mechanically swapping `flags=FFTW.ESTIMATE` →
`flags=FFTW.MEASURE` in the 4 `src/simulation/*.jl` files ($(EXPECTED_FLAG_COUNT) sites total),
running the leg, then reverting in a `finally` block. The git working tree is
guaranteed clean at exit.

## Raw data

See `results/raman/phase15/benchmark.jld2` — full per-run timings and metadata.
"""

open(BENCHMARK_MD, "w") do io
    write(io, md)
end

jldsave(BENCHMARK_JLD2;
    config = Dict(
        "Nt" => 8192, "L_fiber" => 2.0, "P_cont" => 0.2,
        "max_iter" => 30, "time_window" => 20.0,
        "preset" => "SMF28", "beta_order" => 3, "log_cost" => true,
        "seed" => 42, "n_runs" => N_RUNS,
    ),
    estimate_times = estimate_times,
    estimate_Js    = estimate_Js,
    estimate_iters = estimate_iters,
    measure_times  = measure_times,
    measure_Js     = measure_Js,
    measure_iters  = measure_iters,
    est_mean = est_mean, est_std = est_std,
    mea_mean = mea_mean, mea_std = mea_std,
    slowdown_pct = slowdown_pct,
    created_at = string(now()),
)

@info "Benchmark complete" BENCHMARK_MD BENCHMARK_JLD2
@info @sprintf("MEASURE  leg: mean %.2f s  std %.2f s", mea_mean, mea_std)
@info @sprintf("ESTIMATE leg: mean %.2f s  std %.2f s", est_mean, est_std)
@info @sprintf("Slowdown:     %+.1f%%", slowdown_pct)
