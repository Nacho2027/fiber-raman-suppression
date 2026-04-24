"""
Threading/Parallelism Benchmark for Fiber Raman Suppression

Benchmarks all threading opportunities in the codebase:
A. FFTW internal threading (independent of Julia threads)
B. Tullio/LoopVectorization threading (requires Julia -t N)
C. Multi-start optimization parallelism (Threads.@threads)
D. Embarrassingly parallel forward solves (Threads.@threads)

Run:
  julia -t 1 --project=. scripts/benchmark_threading.jl   # FFTW only
  julia -t 8 --project=. scripts/benchmark_threading.jl   # full benchmark

Does NOT change Nt, ODE tolerances, or solver choice.
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

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "raman_optimization.jl"))

if abspath(PROGRAM_FILE) == @__FILE__

# ─────────────────────────────────────────────────────────────────────────────
# Constants (BT_ prefix to avoid include guard collisions)
# ─────────────────────────────────────────────────────────────────────────────

const BT_NT = 2^13                    # grid size for benchmarks
const BT_L_FIBER = 1.0                # fiber length [m]
const BT_P_CONT = 0.05               # continuum power [W]
const BT_N_FFT_PAIRS = 100           # FFT forward+inverse pairs for FFTW benchmark
const BT_N_RUNS = 3                   # repetitions per benchmark (take median)
const BT_N_STARTS = 4                 # multi-start optimization starts
const BT_MAX_ITER = 10                # L-BFGS iterations per start
const BT_N_PARALLEL_SOLVES = 4        # independent forward solves for benchmark D
const BT_FFTW_THREAD_COUNTS = [1, 2, 4, 8]

# ─────────────────────────────────────────────────────────────────────────────
# 0. Setup
# ─────────────────────────────────────────────────────────────────────────────

println("=" ^ 70)
println("  THREADING BENCHMARK — Fiber Raman Suppression")
println("=" ^ 70)
@printf("  Julia threads:  %d\n", Threads.nthreads())
@printf("  BLAS threads:   %d\n", BLAS.get_num_threads())
@printf("  Grid size Nt:   %d (2^%d)\n", BT_NT, Int(log2(BT_NT)))
@printf("  Fiber:          L=%.1fm, P=%.3fW (SMF-28)\n", BT_L_FIBER, BT_P_CONT)
println("=" ^ 70)
println()

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
flush(stdout)

# Helper: median of n timed runs
function timed_median(f, n_runs)
    times = Float64[]
    for _ in 1:n_runs
        t0 = time()
        f()
        push!(times, time() - t0)
    end
    return median(times), times
end

# Results storage for summary table
results_table = Dict{String, NamedTuple}()

# ─────────────────────────────────────────────────────────────────────────────
# A. FFTW Threading Benchmark
# ─────────────────────────────────────────────────────────────────────────────

println("=" ^ 70)
println("  BENCHMARK A: FFTW Internal Threading")
println("  (FFTW threads are independent of Julia threads)")
println("=" ^ 70)
flush(stdout)

# A1: Raw FFT throughput
println("\n  A1. Raw FFT throughput ($BT_N_FFT_PAIRS forward+inverse pairs)...")
flush(stdout)

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

fft_baseline = fft_times[1]
println("\n  FFT Speedup Summary:")
for n_fftw in BT_FFTW_THREAD_COUNTS
    spd = fft_baseline / fft_times[n_fftw]
    @printf("    %d threads: %.2fx\n", n_fftw, spd)
end
flush(stdout)

# A2: Full cost_and_gradient with different FFTW thread counts
println("\n  A2. Full cost_and_gradient with FFTW threading...")
flush(stdout)

cg_fftw_times = Dict{Int, Float64}()
φ_test = 0.1 .* randn(Nt, M)

for n_fftw in BT_FFTW_THREAD_COUNTS
    FFTW.set_num_threads(n_fftw)

    # Need fresh fiber setup because FFTW plans are baked into the p-tuple
    # inside solve_disp_mmf. The plans are created at problem setup time
    # with whatever FFTW thread count is active.
    uω0_a, fiber_a, sim_a, band_mask_a, _, _ = setup_raman_problem(;
        L_fiber=BT_L_FIBER, P_cont=BT_P_CONT, Nt=BT_NT,
        fiber_preset=:SMF28, β_order=3, time_window=10.0)

    # Warmup with this FFTW config
    cost_and_gradient(φ_test, uω0_a, fiber_a, sim_a, band_mask_a)

    med_t, _ = timed_median(BT_N_RUNS) do
        cost_and_gradient(φ_test, uω0_a, fiber_a, sim_a, band_mask_a)
    end
    cg_fftw_times[n_fftw] = med_t
    @printf("    FFTW threads=%d: cost_and_gradient = %.3f s\n", n_fftw, med_t)
    flush(stdout)
end

cg_fftw_baseline = cg_fftw_times[1]
println("\n  cost_and_gradient Speedup (FFTW threads):")
for n_fftw in BT_FFTW_THREAD_COUNTS
    spd = cg_fftw_baseline / cg_fftw_times[n_fftw]
    @printf("    %d threads: %.2fx (%.3f s)\n", n_fftw, spd, cg_fftw_times[n_fftw])
end
flush(stdout)

# Record best FFTW result
best_fftw_threads = argmin(n -> cg_fftw_times[n], BT_FFTW_THREAD_COUNTS)
best_fftw_speedup = cg_fftw_baseline / cg_fftw_times[best_fftw_threads]
results_table["A. FFTW threading"] = (
    t_1thread = cg_fftw_baseline,
    t_nthread = cg_fftw_times[best_fftw_threads],
    speedup = best_fftw_speedup,
    n_threads = best_fftw_threads,
    notes = "FFTW.set_num_threads() — free, no code changes"
)

# Reset FFTW to 1 thread for remaining benchmarks (isolate effects)
FFTW.set_num_threads(1)

# ─────────────────────────────────────────────────────────────────────────────
# B. Tullio/LoopVectorization Threading Benchmark
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 70)
println("  BENCHMARK B: Tullio/LoopVectorization Threading")
println("  (Requires Julia started with -t N)")
println("=" ^ 70)
flush(stdout)

julia_threads = Threads.nthreads()

# B1: Isolated Tullio contractions
println("\n  B1. Isolated Tullio tensor contractions (Nt=$Nt, M=$M)...")
flush(stdout)

# Create test tensors matching the shapes used in disp_mmf!
γ_test = randn(M, M, M, M)
v_test = randn(Nt, M)
w_test = randn(Nt, M)
δKt_test = zeros(Nt, M, M)

# Warmup
@tullio δKt_test[t, i, j] = γ_test[i, j, k, l] * (v_test[t, k] * v_test[t, l] + w_test[t, k] * w_test[t, l])

n_tullio_reps = 1000
med_tullio, _ = timed_median(BT_N_RUNS) do
    for _ in 1:n_tullio_reps
        @tullio δKt_test[t, i, j] = γ_test[i, j, k, l] * (v_test[t, k] * v_test[t, l] + w_test[t, k] * w_test[t, l])
    end
end
@printf("    Tullio Kerr contraction (threads=%d): %.4f s (%d reps)\n", julia_threads, med_tullio, n_tullio_reps)
flush(stdout)

if julia_threads == 1
    println("    NOTE: Julia started with 1 thread. Tullio threading requires -t N.")
    println("    Run with `julia -t 8 --project=. scripts/benchmark_threading.jl` to test.")
    results_table["B. Tullio threading"] = (
        t_1thread = med_tullio,
        t_nthread = med_tullio,
        speedup = 1.0,
        n_threads = 1,
        notes = "Single thread only — run with -t N to test"
    )
else
    @printf("    Tullio is using %d Julia threads for loop parallelism.\n", julia_threads)
    @printf("    For M=1, tensor contractions collapse to scalar ops over Nt=%d points.\n", Nt)
    @printf("    Meaningful speedup expected only for M>1 (multimode fibers).\n")
    results_table["B. Tullio threading"] = (
        t_1thread = med_tullio,  # We cannot easily turn off Tullio threading at runtime
        t_nthread = med_tullio,
        speedup = 1.0,  # Cannot measure 1-thread baseline without restarting Julia
        n_threads = julia_threads,
        notes = "M=1: trivial contraction. Speedup at M>1."
    )
end
flush(stdout)

# B2: Full cost_and_gradient with Julia threads (Tullio will use them internally)
println("\n  B2. Full cost_and_gradient with Tullio threading (threads=$julia_threads)...")
flush(stdout)

# Re-setup with FFTW threads=1 so we isolate Tullio effect
FFTW.set_num_threads(1)
uω0_b, fiber_b, sim_b, band_mask_b, _, _ = setup_raman_problem(;
    L_fiber=BT_L_FIBER, P_cont=BT_P_CONT, Nt=BT_NT,
    fiber_preset=:SMF28, β_order=3, time_window=10.0)

# Warmup
cost_and_gradient(φ_test, uω0_b, fiber_b, sim_b, band_mask_b)

med_cg_tullio, _ = timed_median(BT_N_RUNS) do
    cost_and_gradient(φ_test, uω0_b, fiber_b, sim_b, band_mask_b)
end
@printf("    cost_and_gradient (FFTW=1, Julia threads=%d): %.3f s\n", julia_threads, med_cg_tullio)
flush(stdout)

# ─────────────────────────────────────────────────────────────────────────────
# C. Multi-Start Optimization Parallelism
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 70)
println("  BENCHMARK C: Multi-Start Optimization Parallelism")
@printf("  (%d starts, %d L-BFGS iterations each)\n", BT_N_STARTS, BT_MAX_ITER)
println("=" ^ 70)
flush(stdout)

# Re-setup fresh
FFTW.set_num_threads(1)
uω0_c, fiber_c, sim_c, band_mask_c, _, _ = setup_raman_problem(;
    L_fiber=BT_L_FIBER, P_cont=BT_P_CONT, Nt=BT_NT,
    fiber_preset=:SMF28, β_order=3, time_window=10.0)

# Generate random initial phases (deterministic seeds for reproducibility)
φ0_starts = [0.1 .* randn(Nt, M) for _ in 1:BT_N_STARTS]
φ0_starts[1] = zeros(Nt, M)  # first start is always zero

# Warmup: one short optimization
optimize_spectral_phase(uω0_c, deepcopy(fiber_c), sim_c, band_mask_c;
    max_iter=2)

# C1: Sequential
println("\n  C1. Sequential multi-start...")
flush(stdout)

med_seq, _ = timed_median(BT_N_RUNS) do
    for i in 1:BT_N_STARTS
        fiber_local = deepcopy(fiber_c)
        optimize_spectral_phase(uω0_c, fiber_local, sim_c, band_mask_c;
            φ0=φ0_starts[i], max_iter=BT_MAX_ITER)
    end
end
@printf("    Sequential (%d starts): %.3f s\n", BT_N_STARTS, med_seq)
flush(stdout)

# C2: Threaded (only if nthreads > 1)
if julia_threads > 1
    println("\n  C2. Threaded multi-start (Threads.@threads)...")
    flush(stdout)

    med_par, _ = timed_median(BT_N_RUNS) do
        Threads.@threads for i in 1:BT_N_STARTS
            fiber_local = deepcopy(fiber_c)
            optimize_spectral_phase(copy(uω0_c), fiber_local, sim_c, band_mask_c;
                φ0=φ0_starts[i], max_iter=BT_MAX_ITER)
        end
    end
    @printf("    Threaded (%d starts, %d threads): %.3f s\n", BT_N_STARTS, julia_threads, med_par)

    ms_speedup = med_seq / med_par
    @printf("    Speedup: %.2fx\n", ms_speedup)
    flush(stdout)

    results_table["C. Multi-start optim"] = (
        t_1thread = med_seq,
        t_nthread = med_par,
        speedup = ms_speedup,
        n_threads = julia_threads,
        notes = "Threads.@threads + deepcopy(fiber)"
    )
else
    println("\n  C2. SKIPPED — need -t N for threaded multi-start")
    results_table["C. Multi-start optim"] = (
        t_1thread = med_seq,
        t_nthread = med_seq,
        speedup = 1.0,
        n_threads = 1,
        notes = "Run with -t N to test parallel multi-start"
    )
end
flush(stdout)

# ─────────────────────────────────────────────────────────────────────────────
# D. Embarrassingly Parallel Forward Solves
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 70)
println("  BENCHMARK D: Embarrassingly Parallel Forward Solves")
@printf("  (%d independent cost_and_gradient calls with random phases)\n", BT_N_PARALLEL_SOLVES)
println("=" ^ 70)
flush(stdout)

# Re-setup fresh
FFTW.set_num_threads(1)
uω0_d, fiber_d, sim_d, band_mask_d, _, _ = setup_raman_problem(;
    L_fiber=BT_L_FIBER, P_cont=BT_P_CONT, Nt=BT_NT,
    fiber_preset=:SMF28, β_order=3, time_window=10.0)

φ_randoms = [0.1 .* randn(Nt, M) for _ in 1:BT_N_PARALLEL_SOLVES]

# D1: Sequential
println("\n  D1. Sequential forward solves...")
flush(stdout)

med_seq_d, _ = timed_median(BT_N_RUNS) do
    for i in 1:BT_N_PARALLEL_SOLVES
        fiber_local = deepcopy(fiber_d)
        cost_and_gradient(φ_randoms[i], uω0_d, fiber_local, sim_d, band_mask_d)
    end
end
@printf("    Sequential (%d solves): %.3f s\n", BT_N_PARALLEL_SOLVES, med_seq_d)
flush(stdout)

# D2: Threaded
if julia_threads > 1
    println("\n  D2. Threaded forward solves...")
    flush(stdout)

    med_par_d, _ = timed_median(BT_N_RUNS) do
        Threads.@threads for i in 1:BT_N_PARALLEL_SOLVES
            fiber_local = deepcopy(fiber_d)
            cost_and_gradient(φ_randoms[i], copy(uω0_d), fiber_local, sim_d, band_mask_d)
        end
    end
    @printf("    Threaded (%d solves, %d threads): %.3f s\n", BT_N_PARALLEL_SOLVES, julia_threads, med_par_d)

    par_speedup = med_seq_d / med_par_d
    @printf("    Speedup: %.2fx\n", par_speedup)
    flush(stdout)

    results_table["D. Parallel fwd solves"] = (
        t_1thread = med_seq_d,
        t_nthread = med_par_d,
        speedup = par_speedup,
        n_threads = julia_threads,
        notes = "Threads.@threads + deepcopy(fiber)"
    )
else
    println("\n  D2. SKIPPED — need -t N for threaded forward solves")
    results_table["D. Parallel fwd solves"] = (
        t_1thread = med_seq_d,
        t_nthread = med_seq_d,
        speedup = 1.0,
        n_threads = 1,
        notes = "Run with -t N to test parallel forward solves"
    )
end
flush(stdout)

# ─────────────────────────────────────────────────────────────────────────────
# Summary Table
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 70)
println("  SUMMARY: Threading Opportunities")
println("=" ^ 70)
println()

# Box-drawing summary table (codebase convention)
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
println()

# Recommendations
println("─── Recommendations ───────────────────────────────────────────────────")
if haskey(results_table, "A. FFTW threading")
    local ra = results_table["A. FFTW threading"]
    if ra.speedup > 1.1
        @printf("  FFTW: Set FFTW.set_num_threads(%d) for %.0f%% speedup on forward-adjoint.\n",
            ra.n_threads, (ra.speedup - 1) * 100)
    else
        println("  FFTW: Negligible benefit at Nt=$BT_NT (FFT of $(BT_NT) points is too fast for thread overhead).")
    end
end

if julia_threads > 1
    if haskey(results_table, "C. Multi-start optim")
        local rc = results_table["C. Multi-start optim"]
        if rc.speedup > 1.3
            @printf("  Multi-start: %.1fx speedup with %d threads — use Threads.@threads for multi-start.\n",
                rc.speedup, rc.n_threads)
        else
            println("  Multi-start: Limited speedup — ODE solver may have thread contention.")
        end
    end
    if haskey(results_table, "D. Parallel fwd solves")
        local rd = results_table["D. Parallel fwd solves"]
        if rd.speedup > 1.3
            @printf("  Parallel solves: %.1fx speedup — good for parameter sweeps and gradient validation.\n",
                rd.speedup)
        else
            println("  Parallel solves: Limited speedup — check thread contention in ODE solver.")
        end
    end
else
    println("  Run with `julia -t 8 --project=. scripts/benchmark_threading.jl` to test Julia-thread parallelism.")
end

println("  Tullio: At M=1 (single-mode), tensor contractions are trivial. Expect")
println("          meaningful speedup only for M>1 multimode fibers.")
println("───────────────────────────────────────────────────────────────────────")
println()
@printf("Benchmark complete. Julia threads=%d, BLAS threads=%d\n", Threads.nthreads(), BLAS.get_num_threads())
flush(stdout)

end # if main script
