"""
Phase 29 Solve-Level Benchmark — forward / adjoint / full cost_and_gradient wall
times across Julia thread counts {1, 2, 4, 8, 16, 22} in FRESH subprocesses.
Fits Amdahl (via scripts/phase29_roofline_model.jl). Persists
`results/phase29/solves.jld2` + `results/phase29/amdahl_fits.json`. Does NOT
modify src/.

For production runs execute via the MANDATORY heavy-lock wrapper per CLAUDE.md
Rule P5:

    ~/bin/burst-run-heavy P29-solves \\
        'julia -t 22 --project=. scripts/phase29_bench_solves.jl'

Running on `claude-code-host` is permitted for small thread counts (-t 1..4)
as a smoke test — but production Amdahl fits REQUIRE the burst VM's full 22-thread
ladder. Budget ≈ 25 min on c3-highcpu-22 (3 modes × 6 thread counts × (1 warmup
+ 3 timed) = 72 fresh subprocesses).

Each timed sample runs in a fresh `julia -t N` subprocess so the thread pool is
honored; subprocess-isolation also eliminates state leakage between samples
(Phase 15 pattern, scripts/phase15_benchmark.jl:120-147).
"""

using Printf
using JSON3
using JLD2
using Statistics
using Dates
using Logging

include(joinpath(@__DIR__, "phase29_roofline_model.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Constants — P29S_ prefix per STATE.md "Script Constant Prefixes"
# ─────────────────────────────────────────────────────────────────────────────

const P29S_NT             = 2^13
const P29S_L_FIBER        = 2.0     # SMF-28 canonical [m]
const P29S_P_CONT         = 0.2     # SMF-28 canonical [W]
const P29S_N_RUNS         = 3       # timed samples per (mode, n_threads); 1 warmup discarded
const P29S_THREAD_COUNTS  = [1, 2, 4, 8, 16, 22]      # burst-VM ceiling = 22
const P29S_MODES          = ["forward", "adjoint", "full_cg"]
const P29S_OUTPUT_DIR     = joinpath(@__DIR__, "..", "results", "phase29")
const P29S_SOLVES_JLD2    = joinpath(P29S_OUTPUT_DIR, "solves.jld2")
const P29S_AMDAHL_JSON    = joinpath(P29S_OUTPUT_DIR, "amdahl_fits.json")
const P29S_PROJECT_ROOT   = realpath(joinpath(@__DIR__, ".."))
const P29S_WORKER_SCRIPT  = joinpath(@__DIR__, "_phase29_bench_solves_run.jl")

mkpath(P29S_OUTPUT_DIR)

# ─────────────────────────────────────────────────────────────────────────────
# Subprocess dispatch (mirrors scripts/phase15_benchmark.jl::_run_one_subprocess)
# ─────────────────────────────────────────────────────────────────────────────

"""
    _run_one_subprocess(mode, tag, n_threads) -> NamedTuple

Spawns `julia -t n_threads --project=... _phase29_bench_solves_run.jl mode tag`,
reads its stdout, and extracts the single `BENCH_JSON: {...}` line. Any other
output on stdout/stderr is echoed to the parent's stderr on failure so debugging
is possible.
"""
function _run_one_subprocess(mode::AbstractString, tag::AbstractString, n_threads::Int)
    @assert mode in P29S_MODES "bad mode: $mode"
    @assert n_threads >= 1 "n_threads must be ≥ 1"
    cmd = `julia -t $(n_threads) --project=$(P29S_PROJECT_ROOT) $(P29S_WORKER_SCRIPT) $(mode) $(tag)`
    @info "  spawn" mode tag n_threads
    out = read(cmd, String)
    m = match(r"BENCH_JSON:\s*(\{.*\})", out)
    if m === nothing
        println(stderr, out)
        error("worker produced no BENCH_JSON (mode=$mode tag=$tag n_threads=$n_threads)")
    end
    payload = JSON3.read(m[1])
    return (elapsed_s     = Float64(payload["elapsed_s"]),
            J             = Float64(payload["J"]),
            iters         = Int(payload["iters"]),
            julia_threads = Int(payload["julia_threads"]),
            fftw_threads  = Int(payload["fftw_threads"]))
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__

    println("=" ^ 72)
    println("  PHASE 29 SOLVE BENCHMARK — subprocess-isolated thread scan")
    println("=" ^ 72)
    @printf("  Modes:          %s\n", join(P29S_MODES, ", "))
    @printf("  Thread counts:  %s\n", string(P29S_THREAD_COUNTS))
    @printf("  Samples/config: 1 warmup + %d timed (fresh Julia per sample)\n", P29S_N_RUNS)
    @printf("  Canonical:      SMF-28, L=%.1f m, P=%.3f W, Nt=%d\n",
            P29S_L_FIBER, P29S_P_CONT, P29S_NT)
    println("=" ^ 72)
    flush(stdout)

    # (mode, n_threads) -> Vector of timed seconds
    solves = Dict{Tuple{String,Int}, Vector{Float64}}()

    for mode in P29S_MODES
        for n in P29S_THREAD_COUNTS
            _ = _run_one_subprocess(mode, "WARMUP", n)
            times = Float64[]
            for i in 1:P29S_N_RUNS
                r = _run_one_subprocess(mode, "RUN-$i", n)
                push!(times, r.elapsed_s)
            end
            solves[(mode, n)] = times
            @info "  median" mode n median_s=median(times)
            flush(stdout)
        end
    end

    # ── Fit Amdahl per mode ────────────────────────────────────────────────
    fits = Dict{String, Any}()
    for mode in P29S_MODES
        ns = P29S_THREAD_COUNTS
        ts = [median(solves[(mode, n)]) for n in ns]
        f  = fit_amdahl(ns, ts)
        fits[mode] = Dict(
            "p"            => f.p,
            "speedup_inf"  => isfinite(f.speedup_inf) ? f.speedup_inf : 1e18,  # JSON-safe
            "rmse"         => f.rmse,
            "n_threads"    => collect(ns),
            "median_s"     => ts,
        )
        @info "  amdahl-fit" mode p=f.p speedup_inf=f.speedup_inf rmse=f.rmse
    end

    jldsave(P29S_SOLVES_JLD2;
        solves          = solves,
        thread_counts   = P29S_THREAD_COUNTS,
        modes           = P29S_MODES,
        nt              = P29S_NT,
        l_fiber_m       = P29S_L_FIBER,
        p_cont_w        = P29S_P_CONT,
        n_runs          = P29S_N_RUNS,
        phase29_version = "1.0.0",
        timestamp       = string(now()))

    open(P29S_AMDAHL_JSON, "w") do io
        JSON3.pretty(io, fits)
    end

    @info "phase29_bench_solves done" solves=P29S_SOLVES_JLD2 fits=P29S_AMDAHL_JSON

end # abspath(PROGRAM_FILE) == @__FILE__
