"""
Phase 29 Kernel Benchmarks — FFT, Kerr tullio, Raman tullio, forward RHS, adjoint RHS.

Emits `results/phase29/kernels.jld2` + `results/phase29/hw_profile.json`.

DOES NOT run the optimizer. DOES NOT modify src/. Intentionally overrides the Phase
15 FFTW-threads = 1 invariant LOCALLY for throughput measurement — the global Phase
15 invariant (FFTW.ESTIMATE + thread pin in src/) is untouched because this driver
does NOT call the determinism helper in scripts/determinism.jl and does NOT edit src/.

Structure:
  Block A — raw FFT throughput (MEASURE plans, thread sweep)
  Block B — Kerr tensor contraction (@tullio δKt[t,i,j] = γ[i,j,k,l]·(v·v + w·w))
  Block C — Raman frequency convolution (ESTIMATE plan, matches src/ pipeline)
  Block D — single forward-RHS step (disp_mmf! via get_p_disp_mmf)
  Block E — single adjoint-RHS step (adjoint_disp_mmf! via get_p_adjoint_disp_mmf)

For production numbers, run on the burst VM via:
  ~/bin/burst-run-heavy P29-kernels 'julia -t auto --project=. scripts/bench_kernels.jl'
per CLAUDE.md Rule P5. Running on claude-code-host is acceptable as a smoke test
at small thread counts but the reported throughput numbers become memo-grade only
after the burst-VM run.

This file is include-safe: the main body is guarded by
`abspath(PROGRAM_FILE) == @__FILE__`, so `report.jl` may `include()` it
without re-executing the benchmark.
"""

using Printf
using LinearAlgebra
using FFTW
using Logging
using Statistics
using Dates
using Random
using JLD2
using JSON3
ENV["MPLBACKEND"] = "Agg"
using MultiModeNoise
using MultiModeNoise: get_p_disp_mmf, disp_mmf!, get_p_adjoint_disp_mmf, adjoint_disp_mmf!
using Tullio

include(joinpath(@__DIR__, "..", "..", "..", "lib", "common.jl"))

if abspath(PROGRAM_FILE) == @__FILE__

# ─────────────────────────────────────────────────────────────────────────────
# Constants — P29K_ prefix per STATE.md "Script Constant Prefixes"
# ─────────────────────────────────────────────────────────────────────────────

const P29K_NT                = 2^13                   # SMF-28 canonical grid
const P29K_M                 = 1                      # single-mode (canonical)
const P29K_L_FIBER           = 2.0                    # SMF-28 canonical length [m]
const P29K_P_CONT            = 0.2                    # SMF-28 canonical power [W]
const P29K_N_FFT_PAIRS       = 100                    # FFT forward+inverse pairs per timed block
const P29K_N_TULLIO_REPS     = 200                    # tullio contraction repetitions per timed block
const P29K_N_RHS_REPS        = 500                    # single-RHS-step repetitions per timed block
const P29K_N_RUNS            = 5                      # median-of-N per configuration
const P29K_FFTW_THREAD_COUNTS = [1, 2, 4, 8, 16, 22]  # sweep for Block A (raw FFT)
const P29K_SEED              = 42

const P29K_OUTPUT_DIR        = joinpath(@__DIR__, "..", "..", "..", "..", "results", "phase29")
const P29K_KERNELS_JLD2      = joinpath(P29K_OUTPUT_DIR, "kernels.jld2")
const P29K_HW_PROFILE_JSON   = joinpath(P29K_OUTPUT_DIR, "hw_profile.json")

mkpath(P29K_OUTPUT_DIR)

# ─────────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────────

println("=" ^ 72)
println("  PHASE 29 KERNEL BENCHMARK — FFT-adjoint pipeline roofline audit")
println("=" ^ 72)
@printf("  Julia threads:       %d\n", Threads.nthreads())
@printf("  BLAS threads:        %d\n", BLAS.get_num_threads())
@printf("  FFTW threads (init): %d\n", FFTW.get_num_threads())
@printf("  Grid size Nt:        %d (2^%d)\n", P29K_NT, Int(log2(P29K_NT)))
@printf("  Canonical run:       SMF-28, L=%.1f m, P=%.3f W, M=%d\n",
        P29K_L_FIBER, P29K_P_CONT, P29K_M)
@printf("  Median of N:         %d samples per configuration\n", P29K_N_RUNS)
@printf("  FFT thread sweep:    %s\n", string(P29K_FFTW_THREAD_COUNTS))
println("=" ^ 72)
flush(stdout)

# ─────────────────────────────────────────────────────────────────────────────
# Capture hardware profile BEFORE any benchmark block
# ─────────────────────────────────────────────────────────────────────────────

"""
    _git_commit() -> String

Best-effort current HEAD commit sha; returns "unknown" if git is unavailable.
Cited by the Phase 29 memo for reproducibility (STRIDE threat T-29-04).
"""
function _git_commit()
    try
        return strip(read(`git -C $(dirname(@__DIR__)) rev-parse HEAD`, String))
    catch
        return "unknown"
    end
end

hw_profile = Dict(
    "timestamp"            => string(now()),
    "hostname"             => gethostname(),
    "julia_version"        => string(VERSION),
    "julia_threads"        => Threads.nthreads(),
    "blas_threads"         => BLAS.get_num_threads(),
    "fftw_threads_default" => FFTW.get_num_threads(),
    "cpu_info"             => string(Sys.cpu_info()[1].model),
    "cpu_count"            => Sys.CPU_THREADS,
    "total_memory_gb"      => Sys.total_memory() / 2^30,
    "os"                   => string(Sys.KERNEL),
    "git_commit"           => _git_commit(),
    "phase29_version"      => "1.0.0",
)
open(P29K_HW_PROFILE_JSON, "w") do io
    JSON3.pretty(io, hw_profile)
end
@info "hw_profile written" path=P29K_HW_PROFILE_JSON

# ─────────────────────────────────────────────────────────────────────────────
# Setup (the ONLY ODE-touching data dict used here; no optimizer)
# ─────────────────────────────────────────────────────────────────────────────

Random.seed!(P29K_SEED)
println("\nSetting up Raman problem (SMF-28 canonical)...")
flush(stdout)
uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
    L_fiber=P29K_L_FIBER, P_cont=P29K_P_CONT, Nt=P29K_NT,
    fiber_preset=:SMF28, β_order=3, time_window=10.0)
Nt = sim["Nt"]; M = sim["M"]
@assert Nt == P29K_NT "setup returned Nt=$Nt, expected $P29K_NT"
@assert M == P29K_M "setup returned M=$M, expected $P29K_M (canonical single-mode)"
@printf("  Setup complete: Nt=%d, M=%d\n", Nt, M)
flush(stdout)

# JIT warmup — compile every kernel we will measure. Do not include in any timed block.
println("\nJIT warmup (forward RHS + adjoint RHS)...")
flush(stdout)
t_warm_start = time()
let p_warm_fwd = get_p_disp_mmf(sim["ωs"], sim["ω0"], fiber["Dω"], fiber["γ"],
                                fiber["hRω"], fiber["one_m_fR"], Nt, M, sim["attenuator"])
    ũω_warm = zeros(ComplexF64, Nt, M)
    dũω_warm = similar(ũω_warm)
    disp_mmf!(dũω_warm, ũω_warm, p_warm_fwd, 0.0)
end
let sol_fwd_warm = MultiModeNoise.solve_disp_mmf(uω0, fiber, sim)
    ũω_sol = sol_fwd_warm["ode_sol"]
    τω = fftshift(sim["ωs"] / sim["ω0"])
    p_warm_adj = get_p_adjoint_disp_mmf(ũω_sol, τω, fiber["Dω"], fiber["hRω"],
                                        fiber["γ"], fiber["one_m_fR"],
                                        1 - fiber["one_m_fR"], Nt, M)
    λ_warm = zeros(ComplexF64, Nt, M)
    dλ_warm = similar(λ_warm)
    adjoint_disp_mmf!(dλ_warm, λ_warm, p_warm_adj, 0.0)
end
t_warmup = time() - t_warm_start
@printf("  JIT warmup: %.1f s\n", t_warmup)
flush(stdout)

# ─────────────────────────────────────────────────────────────────────────────
# Median-of-N timer (copied verbatim from scripts/benchmark_threading.jl:81-89)
# ─────────────────────────────────────────────────────────────────────────────

function timed_median(f, n_runs)
    times = Float64[]
    for _ in 1:n_runs
        t0 = time()
        f()
        push!(times, time() - t0)
    end
    return median(times), times
end

# Results storage — one NamedTuple entry per kernel configuration.
results_table = Dict{String, NamedTuple}()

# ─────────────────────────────────────────────────────────────────────────────
# Block A — Raw FFT throughput (MEASURE plans, FFTW-thread sweep)
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 72)
println("  BLOCK A — Raw FFT throughput  [MEASURE plans, FFTW sweep]")
println("=" ^ 72)
flush(stdout)

# bytes_per_pair = 2 × Nt × M × 16 bytes (ComplexF64 = 16 B; forward + inverse
# both stream the array once). This is the minimum data volume moved per pair.
const BYTES_PER_FFT_PAIR = 2 * P29K_NT * P29K_M * 16  # bytes

data_fft_base = randn(ComplexF64, Nt, M)
fft_times = Dict{Int, Float64}()

for n_fftw in P29K_FFTW_THREAD_COUNTS
    FFTW.set_num_threads(n_fftw)
    plan_f = plan_fft!(copy(data_fft_base), 1; flags=FFTW.MEASURE)
    plan_i = plan_ifft!(copy(data_fft_base), 1; flags=FFTW.MEASURE)
    buf = copy(data_fft_base)
    # warmup under this plan
    plan_f * buf
    plan_i * buf
    med_t, runs = timed_median(P29K_N_RUNS) do
        for _ in 1:P29K_N_FFT_PAIRS
            plan_f * buf
            plan_i * buf
        end
    end
    fft_times[n_fftw] = med_t
    gbps = (BYTES_PER_FFT_PAIR * P29K_N_FFT_PAIRS) / (1e9 * med_t)
    key = @sprintf("A_fft_n%d", n_fftw)
    results_table[key] = (
        kernel           = "FFT forward+inverse",
        nt               = P29K_NT,
        m                = P29K_M,
        n_fftw_threads   = n_fftw,
        reps_per_block   = P29K_N_FFT_PAIRS,
        time_median_s    = med_t,
        time_runs        = runs,
        throughput_gb_s  = gbps,
        plan_flags       = "MEASURE",
        notes            = "local MEASURE plans; not the ESTIMATE plans used in src/",
    )
    @printf("  FFTW threads=%2d: %.4f s (%.2f GB/s)\n", n_fftw, med_t, gbps)
    flush(stdout)
end

# Reset FFTW to 1 for the remaining blocks so they isolate compute-bound vs
# FFTW-thread-bound behavior.
FFTW.set_num_threads(1)

# ─────────────────────────────────────────────────────────────────────────────
# Block B — Kerr tensor contraction (@tullio)
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 72)
println("  BLOCK B — Kerr tensor contraction  [@tullio over γ[i,j,k,l]]")
println("=" ^ 72)
flush(stdout)

# Mirrors src/simulation/simulate_disp_mmf.jl:39
#   @tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])
# At M=1 this is a scalar op but Tullio threading overhead is still present —
# measure anyway so the memo can document "tullio overhead at M=1 is X ns/call".
let
    γ = fiber["γ"]
    v = randn(Nt, M)
    w = randn(Nt, M)
    δKt_B = zeros(Nt, M, M)
    # warmup
    @tullio δKt_B[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])
    med_t, runs = timed_median(P29K_N_RUNS) do
        for _ in 1:P29K_N_TULLIO_REPS
            @tullio δKt_B[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])
        end
    end
    ops_per_sec = P29K_N_TULLIO_REPS / med_t
    results_table["B_kerr_tullio"] = (
        kernel           = "Kerr tensor contraction (tullio)",
        nt               = P29K_NT,
        m                = P29K_M,
        n_fftw_threads   = FFTW.get_num_threads(),
        reps_per_block   = P29K_N_TULLIO_REPS,
        time_median_s    = med_t,
        time_runs        = runs,
        throughput_gb_s  = NaN,  # not a memory-bandwidth kernel
        ops_per_sec      = ops_per_sec,
        plan_flags       = "N/A",
        notes            = "@tullio δKt[t,i,j] = γ[i,j,k,l]*(v_k*v_l + w_k*w_l); M=1 at canonical config",
    )
    @printf("  Kerr tullio: %.4f s over %d reps (%.2e reps/s)\n",
            med_t, P29K_N_TULLIO_REPS, ops_per_sec)
    flush(stdout)
end

# ─────────────────────────────────────────────────────────────────────────────
# Block C — Raman frequency convolution (ESTIMATE plan; matches src/)
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 72)
println("  BLOCK C — Raman frequency convolution  [ESTIMATE plan, src/-matching]")
println("=" ^ 72)
flush(stdout)

# Mirrors src/simulation/simulate_disp_mmf.jl:47-49
#   fft_plan_MM! * δKt_cplx
#   @. hRω_δRω = hRω * δKt_cplx
#   ifft_plan_MM! * hRω_δRω
# Uses ESTIMATE plan to match the production pipeline (Phase 15 invariant).
let
    hRω = fiber["hRω"]                            # shape (Nt,) or (Nt, M, M) — use as broadcast
    @assert size(hRω, 1) == Nt "hRω first dim ≠ Nt"
    arr = randn(ComplexF64, Nt, M, M)
    fft_plan_MM! = plan_fft!(copy(arr), 1; flags=FFTW.ESTIMATE)
    ifft_plan_MM! = plan_ifft!(copy(arr), 1; flags=FFTW.ESTIMATE)
    buf = copy(arr)
    # warmup
    fft_plan_MM! * buf
    @. buf = hRω * buf
    ifft_plan_MM! * buf
    med_t, runs = timed_median(P29K_N_RUNS) do
        for _ in 1:P29K_N_TULLIO_REPS
            fft_plan_MM! * buf
            @. buf = hRω * buf
            ifft_plan_MM! * buf
        end
    end
    # Bytes moved per rep: roughly 3 passes over (Nt × M × M) ComplexF64.
    bytes_per_rep = 3 * Nt * M * M * 16
    gbps = (bytes_per_rep * P29K_N_TULLIO_REPS) / (1e9 * med_t)
    results_table["C_raman_convolution"] = (
        kernel           = "Raman frequency convolution (FFT·hRω·IFFT)",
        nt               = P29K_NT,
        m                = P29K_M,
        n_fftw_threads   = FFTW.get_num_threads(),
        reps_per_block   = P29K_N_TULLIO_REPS,
        time_median_s    = med_t,
        time_runs        = runs,
        throughput_gb_s  = gbps,
        plan_flags       = "ESTIMATE",
        notes            = "ESTIMATE plan matches src/; counts 3 passes over (Nt,M,M) ComplexF64",
    )
    @printf("  Raman conv: %.4f s over %d reps (≈ %.2f GB/s at 3·Nt·M² streams)\n",
            med_t, P29K_N_TULLIO_REPS, gbps)
    flush(stdout)
end

# ─────────────────────────────────────────────────────────────────────────────
# Block D — Single forward-RHS step (disp_mmf!)
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 72)
println("  BLOCK D — Single forward-RHS step  [disp_mmf! via get_p_disp_mmf]")
println("=" ^ 72)
flush(stdout)

let
    p_fwd = get_p_disp_mmf(sim["ωs"], sim["ω0"], fiber["Dω"], fiber["γ"],
                           fiber["hRω"], fiber["one_m_fR"], Nt, M, sim["attenuator"])
    ũω = (randn(ComplexF64, Nt, M) .* 1e-3)
    dũω = similar(ũω)
    # warmup
    disp_mmf!(dũω, ũω, p_fwd, 0.0)
    med_t, runs = timed_median(P29K_N_RUNS) do
        for _ in 1:P29K_N_RHS_REPS
            disp_mmf!(dũω, ũω, p_fwd, 0.0)
        end
    end
    per_call_ns = (med_t / P29K_N_RHS_REPS) * 1e9
    results_table["D_forward_rhs"] = (
        kernel           = "Forward RHS step (disp_mmf!)",
        nt               = P29K_NT,
        m                = P29K_M,
        n_fftw_threads   = FFTW.get_num_threads(),
        reps_per_block   = P29K_N_RHS_REPS,
        time_median_s    = med_t,
        time_runs        = runs,
        throughput_gb_s  = NaN,
        per_call_ns      = per_call_ns,
        plan_flags       = "ESTIMATE (src-canonical)",
        notes            = "disp_mmf! includes Kerr tullio + Raman convolution + self-steep + lab/interaction transforms",
    )
    @printf("  Forward RHS: %.4f s / %d reps = %.2f µs/call\n",
            med_t, P29K_N_RHS_REPS, per_call_ns / 1e3)
    flush(stdout)
end

# ─────────────────────────────────────────────────────────────────────────────
# Block E — Single adjoint-RHS step (adjoint_disp_mmf!)
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 72)
println("  BLOCK E — Single adjoint-RHS step  [adjoint_disp_mmf!]")
println("=" ^ 72)
flush(stdout)

let
    # Produce a real forward ODESolution — the adjoint RHS needs to query
    # ũω(z) on every call. We run ONE forward solve (untimed) to obtain it.
    sol_fwd = MultiModeNoise.solve_disp_mmf(uω0, fiber, sim)
    ũω_sol  = sol_fwd["ode_sol"]
    τω = fftshift(sim["ωs"] / sim["ω0"])
    p_adj = get_p_adjoint_disp_mmf(ũω_sol, τω, fiber["Dω"], fiber["hRω"],
                                   fiber["γ"], fiber["one_m_fR"],
                                   1 - fiber["one_m_fR"], Nt, M)
    λ = (randn(ComplexF64, Nt, M) .* 1e-3)
    dλ = similar(λ)
    # warmup (mid-fiber z — both exp_D_p and exp_D_m are non-trivial)
    z_mid = fiber["L"] / 2
    adjoint_disp_mmf!(dλ, λ, p_adj, z_mid)
    med_t, runs = timed_median(P29K_N_RUNS) do
        for _ in 1:P29K_N_RHS_REPS
            adjoint_disp_mmf!(dλ, λ, p_adj, z_mid)
        end
    end
    per_call_ns = (med_t / P29K_N_RHS_REPS) * 1e9
    results_table["E_adjoint_rhs"] = (
        kernel           = "Adjoint RHS step (adjoint_disp_mmf!)",
        nt               = P29K_NT,
        m                = P29K_M,
        n_fftw_threads   = FFTW.get_num_threads(),
        reps_per_block   = P29K_N_RHS_REPS,
        time_median_s    = med_t,
        time_runs        = runs,
        throughput_gb_s  = NaN,
        per_call_ns      = per_call_ns,
        plan_flags       = "ESTIMATE (src-canonical)",
        notes            = "adjoint_disp_mmf! queries ũω(z) via ODESolution interpolation; z=L/2",
    )
    @printf("  Adjoint RHS: %.4f s / %d reps = %.2f µs/call\n",
            med_t, P29K_N_RHS_REPS, per_call_ns / 1e3)
    flush(stdout)
end

# ─────────────────────────────────────────────────────────────────────────────
# Box-drawing terminal summary (compare 1-thread vs best-thread FFT, others as is)
# ─────────────────────────────────────────────────────────────────────────────

println("\n" * "=" ^ 72)
println("  KERNEL SUMMARY")
println("=" ^ 72)
@printf("  %-42s  %10s  %14s\n", "Kernel", "median [s]", "regime-hint")
println("  " * "-" ^ 70)
for key in sort(collect(keys(results_table)))
    e = results_table[key]
    # Regime hint is crude at this stage — the real verdict comes from
    # roofline_model.jl after the memo is assembled.
    hint = startswith(key, "A_fft") ? "MEMORY_BOUND (FFT)" :
           key == "B_kerr_tullio"   ? "COMPUTE_BOUND (M=1 trivial)" :
           key == "C_raman_convolution" ? "MEMORY_BOUND (ESTIMATE FFT)" :
           key == "D_forward_rhs"   ? "MIXED (FFT + tullio)" :
           key == "E_adjoint_rhs"   ? "MIXED (FFT + tullio + interp)" : "UNKNOWN"
    @printf("  %-42s  %10.4f  %14s\n", e.kernel, e.time_median_s, hint)
end
println("=" ^ 72)
flush(stdout)

# ─────────────────────────────────────────────────────────────────────────────
# Persist
# ─────────────────────────────────────────────────────────────────────────────

jldsave(P29K_KERNELS_JLD2;
    results_table    = results_table,
    hw_profile       = hw_profile,
    fftw_thread_sweep = P29K_FFTW_THREAD_COUNTS,
    nt               = P29K_NT,
    m                = P29K_M,
    l_fiber_m        = P29K_L_FIBER,
    p_cont_w         = P29K_P_CONT,
    n_runs           = P29K_N_RUNS,
    seed             = P29K_SEED,
    phase29_version  = "1.0.0",
    timestamp        = string(now()))

@info "phase29_bench_kernels done" kernels=P29K_KERNELS_JLD2 hw=P29K_HW_PROFILE_JSON

end # abspath(PROGRAM_FILE) == @__FILE__
