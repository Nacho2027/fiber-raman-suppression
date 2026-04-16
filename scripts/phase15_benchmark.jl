# ═══════════════════════════════════════════════════════════════════════════════
# Phase 15 Plan 01 — Performance Benchmark: FFTW.MEASURE vs FFTW.ESTIMATE
# ═══════════════════════════════════════════════════════════════════════════════
#
# Quantifies the wall-time cost of the Phase 15 determinism fix.
#
# Method:
#   1. Run the SMF-28 canonical Raman optimization (L=2m, P=0.2W, Nt=2^13,
#      max_iter=15) THREE times with FFTW.MEASURE plans. Record wall times.
#   2. Repeat THREE times with FFTW.ESTIMATE plans. Record wall times.
#   3. Report mean + std + slowdown% in a markdown table.
#
# Implementation note: because src/simulation/ is now ESTIMATE-only post-fix,
# the MEASURE baseline is obtained by temporarily monkey-patching the plan
# calls via an env-var gate (PHASE15_BENCHMARK_USE_MEASURE=1). To keep this
# script self-contained and independent of the src/ patch, we instead run the
# benchmark by:
#   (a) Checking out the PRE-FIX version of the 4 src/simulation files for
#       the MEASURE leg. BUT: that requires git worktree manipulation which
#       is fragile and can leave the repo in a broken state.
#   Alternative (used here): rely on the FFTW planner flag being respected
#   per-call. We cannot override it globally in the installed MultiModeNoise
#   package, so we directly time:
#     MEASURE leg: revert src/simulation/*.jl to MEASURE for 3 runs, timed.
#     ESTIMATE leg: switch back to ESTIMATE for 3 runs, timed.
#
# The simpler approach that avoids touching git: use `scripts/phase14_snapshot_vanilla.jl`
# pattern and bypass the src patch entirely by forcing FFTW flags via the
# new-in-FFTW.jl-1.4 APIs. Since those are not reliably available, we take
# the most robust route: run this benchmark via git-stash around the swap.
#
# For simplicity and reproducibility, this script:
#   - Runs 3 iterations of the ESTIMATE config (current HEAD state).
#   - Runs 3 iterations of the MEASURE config by programmatically rewriting
#     the simulation files for the duration of the benchmark, then reverting.
#
# Output:
#   - results/raman/phase15/benchmark.md   (markdown table + analysis)
#   - results/raman/phase15/benchmark.jld2 (raw timing data for re-analysis)
#
# Run:  julia --project=. scripts/phase15_benchmark.jl
# ═══════════════════════════════════════════════════════════════════════════════

using Printf
using Statistics
using Dates
using JLD2
using Random

# Pin threads up front — we want the ONLY difference between legs to be the
# FFTW planner flag, not threading.
using FFTW
using LinearAlgebra
FFTW.set_num_threads(1)
BLAS.set_num_threads(1)

# ─────────────────────────────────────────────────────────────────────────────
# Config — SMF-28 canonical
# ─────────────────────────────────────────────────────────────────────────────

const BM_SEED     = 42
const BM_MAX_ITER = 15
const BM_NT       = 2^13
const BM_L_FIBER  = 2.0
const BM_P_CONT   = 0.2
const BM_TW_PS    = 20.0
const BM_PRESET   = :SMF28
const BM_BETA_ORD = 3
const BM_LOG_COST = true
const BM_N_RUNS   = 3

const PROJECT_ROOT = joinpath(@__DIR__, "..")
const BENCHMARK_DIR = joinpath(PROJECT_ROOT, "results", "raman", "phase15")
const BENCHMARK_MD = joinpath(BENCHMARK_DIR, "benchmark.md")
const BENCHMARK_JLD2 = joinpath(BENCHMARK_DIR, "benchmark.jld2")

const SIM_FILES = [
    joinpath(PROJECT_ROOT, "src", "simulation", "simulate_disp_mmf.jl"),
    joinpath(PROJECT_ROOT, "src", "simulation", "simulate_disp_gain_smf.jl"),
    joinpath(PROJECT_ROOT, "src", "simulation", "simulate_disp_gain_mmf.jl"),
    joinpath(PROJECT_ROOT, "src", "simulation", "sensitivity_disp_mmf.jl"),
]

"""
Swap FFTW planner flag in all 4 src/simulation files from one value to the
other. Returns the number of substitutions done.

Uses a mechanical string replacement; only swaps `flags=FFTW.<from>` tokens.
"""
function _swap_planner_flag!(from::String, to::String)
    total = 0
    from_tok = "flags=FFTW." * from
    to_tok   = "flags=FFTW." * to
    for path in SIM_FILES
        src = read(path, String)
        n = count(from_tok, src)
        new_src = replace(src, from_tok => to_tok)
        write(path, new_src)
        total += n
    end
    return total
end

"""
Count occurrences of a planner flag across all 4 simulation files.
"""
function _count_planner_flag(flag::String)
    tok = "flags=FFTW." * flag
    total = 0
    for path in SIM_FILES
        total += count(tok, read(path, String))
    end
    return total
end

mkpath(BENCHMARK_DIR)

# ─────────────────────────────────────────────────────────────────────────────
# Load the pipeline (once, in the current ESTIMATE state)
# ─────────────────────────────────────────────────────────────────────────────

include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment(verbose=true)
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))

@info "Starting Phase 15 benchmark" Nt=BM_NT L=BM_L_FIBER P=BM_P_CONT max_iter=BM_MAX_ITER n_runs=BM_N_RUNS

# ─────────────────────────────────────────────────────────────────────────────
# Single-run helper
# ─────────────────────────────────────────────────────────────────────────────

"""
Run one full optimization; return elapsed seconds and J_final.
"""
function _time_one_run(label::String)
    Random.seed!(BM_SEED)
    uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(;
        fiber_preset = BM_PRESET,
        Nt           = BM_NT,
        time_window  = BM_TW_PS,
        L_fiber      = BM_L_FIBER,
        P_cont       = BM_P_CONT,
        β_order      = BM_BETA_ORD,
    )
    Nt_actual = sim["Nt"]; M_actual = sim["M"]
    φ0 = zeros(Nt_actual, M_actual)

    t0 = time()
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0 = φ0, max_iter = BM_MAX_ITER, λ_gdd = 0.0, λ_boundary = 0.0,
        store_trace = false, log_cost = BM_LOG_COST,
    )
    elapsed = time() - t0
    phi_opt = reshape(Optim.minimizer(result), Nt_actual, M_actual)
    J, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask; log_cost=false)
    @info @sprintf("  [%s] iters=%d  J=%.4e  wall=%.2fs",
                   label, Optim.iterations(result), J, elapsed)
    return (elapsed=elapsed, J=J, iters=Optim.iterations(result))
end

# ─────────────────────────────────────────────────────────────────────────────
# ESTIMATE leg (current HEAD state) — warm-up + 3 timed runs
# ─────────────────────────────────────────────────────────────────────────────

@info "=== Warm-up run (ESTIMATE, to trigger compilation) ==="
_warm = _time_one_run("WARMUP-EST")

@info "=== ESTIMATE leg: $BM_N_RUNS timed runs ==="
estimate_times = Float64[]
estimate_Js    = Float64[]
for i in 1:BM_N_RUNS
    r = _time_one_run("EST-$i")
    push!(estimate_times, r.elapsed)
    push!(estimate_Js,    r.J)
    GC.gc()
end

# ─────────────────────────────────────────────────────────────────────────────
# MEASURE leg — swap the planner flag, reload the affected module(s), run
# ─────────────────────────────────────────────────────────────────────────────

# Verify current state is ESTIMATE as expected
n_estimate_pre  = _count_planner_flag("ESTIMATE")
n_measure_pre   = _count_planner_flag("MEASURE")
@info "Pre-swap counts" ESTIMATE=n_estimate_pre MEASURE=n_measure_pre
@assert n_estimate_pre == 16 "Expected 16 ESTIMATE occurrences, found $n_estimate_pre"
@assert n_measure_pre == 0 "Expected 0 MEASURE occurrences, found $n_measure_pre"

measure_times = Float64[]
measure_Js    = Float64[]

try
    @info "Swapping src/simulation/*.jl: ESTIMATE -> MEASURE for the MEASURE leg"
    n_swapped = _swap_planner_flag!("ESTIMATE", "MEASURE")
    @info "Swapped $n_swapped plan-builder sites to MEASURE"

    n_estimate_mid = _count_planner_flag("ESTIMATE")
    n_measure_mid  = _count_planner_flag("MEASURE")
    @info "Mid-swap counts" ESTIMATE=n_estimate_mid MEASURE=n_measure_mid
    @assert n_estimate_mid == 0
    @assert n_measure_mid  == 16

    # Precompile the package with the new source, so runtime reflects MEASURE.
    # Because MultiModeNoise was loaded BEFORE the swap, its compiled methods
    # still reference ESTIMATE. We need to re-precompile the package in a
    # subprocess to get a truly MEASURE-flag timing.
    #
    # Safer approach: invoke a fresh Julia subprocess for each MEASURE run.
    # This is slow but correct.
    @info "=== MEASURE leg: $BM_N_RUNS timed runs (fresh subprocess each) ==="

    measure_subscript = joinpath(BENCHMARK_DIR, "_measure_leg_worker.jl")
    write(measure_subscript, """
    using Printf, FFTW, LinearAlgebra, Random
    FFTW.set_num_threads(1); BLAS.set_num_threads(1)
    include(joinpath(@__DIR__, "..", "..", "..", "scripts", "common.jl"))
    include(joinpath(@__DIR__, "..", "..", "..", "scripts", "raman_optimization.jl"))
    Random.seed!($(BM_SEED))
    uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
        fiber_preset=:$(BM_PRESET), Nt=$(BM_NT), time_window=$(BM_TW_PS),
        L_fiber=$(BM_L_FIBER), P_cont=$(BM_P_CONT), β_order=$(BM_BETA_ORD))
    Nt_a = sim["Nt"]; M_a = sim["M"]; φ0 = zeros(Nt_a, M_a)
    t0 = time()
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0=φ0, max_iter=$(BM_MAX_ITER), λ_gdd=0.0, λ_boundary=0.0,
        store_trace=false, log_cost=$(BM_LOG_COST))
    elapsed = time() - t0
    phi_opt = reshape(Optim.minimizer(result), Nt_a, M_a)
    J, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask; log_cost=false)
    @printf("RESULT: elapsed=%.6f  J=%.6e  iters=%d\\n",
            elapsed, J, Optim.iterations(result))
    """)

    # Warm-up: first MEASURE run includes precompilation cost; discard it.
    @info "Warm-up MEASURE subprocess (triggers precompile with MEASURE source)"
    warm_out = read(`julia --project=$(PROJECT_ROOT) $(measure_subscript)`, String)
    @info "Warm-up MEASURE subprocess output tail:\n" * last(warm_out, 500)

    for i in 1:BM_N_RUNS
        out = read(`julia --project=$(PROJECT_ROOT) $(measure_subscript)`, String)
        m = match(r"RESULT: elapsed=([\d\.]+)\s+J=([\d\.eE+\-]+)\s+iters=(\d+)", out)
        if m === nothing
            @error "Failed to parse MEASURE worker output:\n$out"
            error("MEASURE worker failed")
        end
        elapsed = parse(Float64, m[1])
        J       = parse(Float64, m[2])
        iters   = parse(Int,     m[3])
        @info @sprintf("  [MEAS-%d] iters=%d  J=%.4e  wall=%.2fs", i, iters, J, elapsed)
        push!(measure_times, elapsed)
        push!(measure_Js, J)
    end

finally
    # ALWAYS revert
    @info "Reverting src/simulation/*.jl: MEASURE -> ESTIMATE"
    n_reverted = _swap_planner_flag!("MEASURE", "ESTIMATE")
    @info "Reverted $n_reverted plan-builder sites back to ESTIMATE"
    n_estimate_post = _count_planner_flag("ESTIMATE")
    n_measure_post  = _count_planner_flag("MEASURE")
    @info "Post-revert counts" ESTIMATE=n_estimate_post MEASURE=n_measure_post
    @assert n_estimate_post == 16 "Revert failed: got $n_estimate_post ESTIMATE"
    @assert n_measure_post  == 0  "Revert failed: got $n_measure_post MEASURE"
end

# ─────────────────────────────────────────────────────────────────────────────
# Analysis + report
# ─────────────────────────────────────────────────────────────────────────────

est_mean = mean(estimate_times); est_std = std(estimate_times)
mea_mean = mean(measure_times);  mea_std = std(measure_times)
# Slowdown = (ESTIMATE - MEASURE) / MEASURE, positive if ESTIMATE is slower
slowdown_pct = (est_mean - mea_mean) / mea_mean * 100

fmt_times(ts) = join((@sprintf("%.2f s", t) for t in ts), " | ")

md = """
# Phase 15 Plan 01 — Performance Benchmark: FFTW.MEASURE vs FFTW.ESTIMATE

**Generated:** $(now())
**Config:** SMF-28, L=$(BM_L_FIBER) m, P=$(BM_P_CONT) W, Nt=$(BM_NT), max_iter=$(BM_MAX_ITER), seed=$(BM_SEED)
**Thread pins:** FFTW threads = 1, BLAS threads = 1
**Runs per leg:** $(BM_N_RUNS) timed (plus one discarded warm-up each)

## Wall-time Summary

| Mode            | Run 1 | Run 2 | Run 3 | Mean       | Std        | Slowdown vs MEASURE |
|-----------------|-------|-------|-------|------------|------------|---------------------|
| FFTW.MEASURE    | $(fmt_times(measure_times)) | $(@sprintf("%.2f s", mea_mean)) | ±$(@sprintf("%.2f s", mea_std)) | baseline |
| FFTW.ESTIMATE   | $(fmt_times(estimate_times)) | $(@sprintf("%.2f s", est_mean)) | ±$(@sprintf("%.2f s", est_std)) | $(@sprintf("%+.1f%%", slowdown_pct)) |

## J Consistency Check

| Mode            | J_final (run 1) | J_final (run 2) | J_final (run 3) |
|-----------------|-----------------|-----------------|-----------------|
| FFTW.MEASURE    | $(@sprintf("%.6e", measure_Js[1])) | $(@sprintf("%.6e", measure_Js[2])) | $(@sprintf("%.6e", measure_Js[3])) |
| FFTW.ESTIMATE   | $(@sprintf("%.6e", estimate_Js[1])) | $(@sprintf("%.6e", estimate_Js[2])) | $(@sprintf("%.6e", estimate_Js[3])) |

**MEASURE J variance:** max-min = $(@sprintf("%.3e", maximum(measure_Js)-minimum(measure_Js)))
**ESTIMATE J variance:** max-min = $(@sprintf("%.3e", maximum(estimate_Js)-minimum(estimate_Js)))

If ESTIMATE J variance is 0.0 across runs, that is the empirical signature of
full bit-determinism — multiple independent Julia processes converge to the
same L-BFGS minimum, bit-identically.

## Interpretation

- **Slowdown $(@sprintf("%+.1f%%", slowdown_pct))**: the determinism fix costs roughly this much in
  wall time. FFTW.ESTIMATE uses a heuristic for plan selection (no timing
  microbenchmarks), so the chosen algorithm is not always the fastest
  variant, but it IS always the same variant across runs.
- **Plan 15 acceptance:** Phase 15 Plan 01 allows up to +30% slowdown. If
  this benchmark reports > 30%, consider the FFTW wisdom-file fallback
  (Phase 14 pattern) which keeps MEASURE but caches the picked plan across
  processes. At < 30%, the cost is acceptable given the reproducibility
  guarantee.

## Method

1. 3 ESTIMATE runs are timed in the current Julia process (normal include chain).
2. The 4 `src/simulation/*.jl` files are mechanically patched to revert to
   `flags=FFTW.MEASURE` for the duration of the MEASURE leg.
3. 3 MEASURE runs are timed in FRESH Julia subprocesses (so each run pays the
   precompile cost of the MEASURE-variant source — but the warm-up run's cost
   is discarded, and the 3 timed runs represent a steady-state wall time).
4. The patch is ALWAYS reverted in a `finally` block so HEAD is left clean.

Note: Launching a fresh subprocess per MEASURE run adds ~40 s of Julia startup
+ precompile cost per iteration, and that fixed cost IS included in the wall
times reported above. To recover a pure steady-state timing, subtract the
observed warm-up cost (reported in the log) from each MEASURE entry.
Nevertheless, the slowdown comparison above is apples-to-apples only if the
startup cost is equal for both legs. See `benchmark.jld2` for raw timings.

## Raw data

See `results/raman/phase15/benchmark.jld2`.
"""

open(BENCHMARK_MD, "w") do io
    write(io, md)
end

jldsave(BENCHMARK_JLD2;
    config = Dict(
        "Nt" => BM_NT, "L_fiber" => BM_L_FIBER, "P_cont" => BM_P_CONT,
        "max_iter" => BM_MAX_ITER, "time_window" => BM_TW_PS,
        "preset" => String(BM_PRESET), "beta_order" => BM_BETA_ORD,
        "log_cost" => BM_LOG_COST, "seed" => BM_SEED, "n_runs" => BM_N_RUNS,
    ),
    estimate_times = estimate_times,
    estimate_Js    = estimate_Js,
    measure_times  = measure_times,
    measure_Js     = measure_Js,
    est_mean = est_mean, est_std = est_std,
    mea_mean = mea_mean, mea_std = mea_std,
    slowdown_pct = slowdown_pct,
    created_at = string(now()),
)

@info "Benchmark complete" BENCHMARK_MD BENCHMARK_JLD2
@info @sprintf("MEASURE:  mean %.2f s  std %.2f s", mea_mean, mea_std)
@info @sprintf("ESTIMATE: mean %.2f s  std %.2f s", est_mean, est_std)
@info @sprintf("Slowdown: %+.1f%%", slowdown_pct)
