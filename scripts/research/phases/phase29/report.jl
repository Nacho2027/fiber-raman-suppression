"""
Phase 29 Report Generator — consumes `results/phase29/{kernels.jld2,
solves.jld2, amdahl_fits.json, hw_profile.json}` and emits:

  (a) `results/phase29/roofline.md`                         — human-readable memo
  (b) `.planning/phases/29-.../29-REPORT.md`                — canonical phase report

Does NOT re-run benchmarks. Pure analysis. Uses scripts/roofline_model.jl
for the sole markdown assembler (`assemble_roofline_memo`) so the scope-lock
headings are preserved.
"""

using Printf
using JLD2
using JSON3
using Statistics
using Dates

include(joinpath(@__DIR__, "roofline_model.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Constants — P29R_ prefix per STATE.md "Script Constant Prefixes"
# ─────────────────────────────────────────────────────────────────────────────

const P29R_OUTPUT_DIR       = joinpath(@__DIR__, "..", "..", "..", "..", "results", "phase29")
const P29R_KERNELS_JLD2     = joinpath(P29R_OUTPUT_DIR, "kernels.jld2")
const P29R_SOLVES_JLD2      = joinpath(P29R_OUTPUT_DIR, "solves.jld2")
const P29R_HW_PROFILE_JSON  = joinpath(P29R_OUTPUT_DIR, "hw_profile.json")
const P29R_AMDAHL_JSON      = joinpath(P29R_OUTPUT_DIR, "amdahl_fits.json")
const P29R_ROOFLINE_MD      = joinpath(P29R_OUTPUT_DIR, "roofline.md")
const P29R_PHASE_REPORT_MD  = joinpath(@__DIR__, "..", ".planning", "phases",
    "29-performance-modeling-and-roofline-audit-for-the-fft-adjoint-", "29-REPORT.md")

# ─────────────────────────────────────────────────────────────────────────────
# Markdown section builders (pure — accept Dicts, return String)
# ─────────────────────────────────────────────────────────────────────────────

"""
    _executive_verdict(kernel_results, amdahl_fits) -> String

One-paragraph dominant-bottleneck summary. Heuristic:
  min_p < 0.5 → SERIAL_BOUND (Amdahl saturates below 2×)
  min_p < 0.8 → MIXED (parallelizable but serial tail matters)
  otherwise   → PARALLEL_SCALING (near-linear up to ceiling)
`min_p` is the minimum fitted Amdahl parallel fraction across
{forward, adjoint, full_cg}.
"""
function _executive_verdict(kernel_results, amdahl_fits)
    ps = Float64[]
    for (_, fit) in amdahl_fits
        push!(ps, Float64(get(fit, "p", 1.0)))
    end
    min_p = isempty(ps) ? 1.0 : minimum(ps)
    dominant =
        min_p < 0.5 ? "SERIAL_BOUND (orchestration + single-threaded RHS dominate)" :
        min_p < 0.8 ? "MIXED (significant parallelizable fraction but serial tail matters)" :
                      "PARALLEL_SCALING (near-linear up to the tested thread ceiling)"
    ceiling = min_p < 1.0 ? 1.0 / (1.0 - min_p) : Inf
    ceiling_str = isfinite(ceiling) ? @sprintf("%.1fx", ceiling) : "∞"
    recommendation =
        min_p < 0.5 ? "do not pay for more than 4 burst-VM threads for the canonical single-mode workload; invest tuning effort in the FFT plan and per-RHS allocation path instead" :
        min_p < 0.8 ? "use -t 8 on the burst VM; going to -t 22 yields ≤ 1.5x over -t 8 at the measured p" :
                      "use -t 22 on the burst VM; near-linear scaling is observed up to the tested ceiling"
    return @sprintf(
        "Dominant bottleneck: **%s**. Measured minimum parallelizable fraction across forward/adjoint/full_cg is p = %.3f, giving Amdahl speedup ceiling ≈ %s. Recommendation: %s.",
        dominant, min_p, ceiling_str, recommendation,
    )
end

"""
    _kernels_md(results_table) -> String

Markdown table of kernel median wall time + throughput. `results_table` is the
Dict written by bench_kernels.jl.
"""
function _kernels_md(results_table)
    io = IOBuffer()
    println(io, "| Kernel | n_fftw | reps | median (s) | throughput GB/s | notes |")
    println(io, "|--------|--------|------|------------|-----------------|-------|")
    for key in sort(collect(keys(results_table)))
        e = results_table[key]
        tp_str = haskey(e, :throughput_gb_s) && isfinite(e.throughput_gb_s) ?
                 @sprintf("%.2f", e.throughput_gb_s) : "—"
        @printf(io, "| %s | %d | %d | %.4f | %s | %s |\n",
            get(e, :kernel, key),
            get(e, :n_fftw_threads, -1),
            get(e, :reps_per_block, -1),
            get(e, :time_median_s, NaN),
            tp_str,
            get(e, :notes, ""))
    end
    return String(take!(io))
end

"""
    _amdahl_md(amdahl_fits) -> String

Markdown table of Amdahl fits (one row per mode).
"""
function _amdahl_md(amdahl_fits)
    io = IOBuffer()
    println(io, "| Mode | Fitted p | Speedup ceiling | RMSE (s) |")
    println(io, "|------|----------|-----------------|----------|")
    for (mode, fit) in amdahl_fits
        p_val = Float64(get(fit, "p", NaN))
        s_inf = Float64(get(fit, "speedup_inf", NaN))
        rmse  = Float64(get(fit, "rmse", NaN))
        ceil_str = isfinite(s_inf) && s_inf < 1e12 ? @sprintf("%.1fx", s_inf) : "∞"
        @printf(io, "| %s | %.3f | %s | %.4e |\n", mode, p_val, ceil_str, rmse)
    end
    return String(take!(io))
end

# Per-kernel FLOP/byte estimates from 29-RESEARCH.md §2. Keys match the
# `kernel` string field written by bench_kernels.jl. Units: (FLOPs, bytes).
# Nt=2^13, M=1, ComplexF64 = 16 bytes.
const P29R_KERNEL_AI = Dict(
    # FFT: 5·N·log2(N) FLOPs; 4 memory passes × N × 16 bytes = 64N bytes
    # At Nt=2^13: 5·8192·13 ≈ 532k FLOPs; 524k bytes; AI ≈ 1.01 FLOP/byte
    "FFT forward+inverse"                           => (5 * 8192 * 13, 4 * 8192 * 16),
    # Kerr @tullio at M=1: 2 muladds × Nt = 16k FLOPs; 3 loads + 1 store × 16B × Nt = 64·Nt bytes
    "Kerr tensor contraction (tullio)"              => (4 * 8192,       4 * 8192 * 16),
    # Raman convolution: 2 FFTs + pointwise × 1 IFFT. ~1.6M FLOPs; ~200KB bytes. AI ≈ 4-8
    "Raman frequency convolution (FFT·hRω·IFFT)"    => (2 * 5 * 8192 * 13 + 8192 * 6, 3 * 8192 * 16 * 2),
    # Forward RHS step: Kerr + Raman + dispersion. Dominated by Raman.
    "Forward RHS step (disp_mmf!)"                  => (2.5 * 5 * 8192 * 13, 6 * 8192 * 16),
    # Adjoint RHS step: forward RHS + ODE interpolation + chain rule. ~2.5x forward.
    "Adjoint RHS step (adjoint_disp_mmf!)"          => (6.5 * 5 * 8192 * 13, 10 * 8192 * 16),
)

# Hardware peaks. Picked from the machine's cpu_info string; values come from
# vendor specs / published STREAM benchmarks. Unit: (peak_flops_fp64_s, peak_bw_B_s)
function _hw_peaks(hw_profile)
    cpu = get(hw_profile, "cpu_info", "")
    if occursin("M3 Max", cpu)
        # 8 P-cores × 128 GFLOP/s f64 ≈ 1.0 TFLOP/s; unified DDR5 ~300 GB/s measured STREAM
        return (1.0e12, 300e9, "Apple M3 Max")
    elseif occursin("AMD EPYC 9B14", cpu) || occursin("c3-highcpu-22", cpu)
        return (800e9, 40e9, "c3-highcpu-22 (Sapphire Rapids, 22 vCPU)")
    elseif occursin("Intel(R) Xeon(R)", cpu) || occursin("e2-standard-4", cpu)
        return (100e9, 20e9, "e2-standard-4 (Broadwell, 4 vCPU)")
    else
        return (NaN, NaN, "UNKNOWN")
    end
end

"""
    _roofline_md(results_table, hw_profile) -> String

Per-kernel AI + roofline ceiling + measured throughput + verdict. Uses
arithmetic_intensity, roofline_bound, kernel_regime_verdict from the analysis
library.
"""
function _roofline_md(results_table, hw_profile)
    io = IOBuffer()
    peak_flops, peak_bw, hw_label = _hw_peaks(hw_profile)
    println(io, "*Host peaks used:* FLOP/s=", @sprintf("%.2e", peak_flops),
                ", BW=", @sprintf("%.2e", peak_bw), " B/s (", hw_label, ")")
    println(io)
    println(io, "| Kernel | n_fftw | AI (FLOP/byte) | Regime (roofline) | Verdict | Measured (GB/s or ns) | Ceiling GB/s | Util % |")
    println(io, "|--------|--------|----------------|--------------------|---------|------------------------|--------------|--------|")
    # Deterministic ordering — by key
    for key in sort(collect(keys(results_table)))
        e = results_table[key]
        kname = get(e, :kernel, string(key))
        haskey(P29R_KERNEL_AI, kname) || continue
        flops, bytes = P29R_KERNEL_AI[kname]
        AI = arithmetic_intensity(flops, bytes)
        bound = isfinite(peak_flops) ?
                roofline_bound(AI, peak_flops, peak_bw) :
                (bound_flops_s = NaN, regime = "UNKNOWN")
        verdict = kernel_regime_verdict(AI, bound.regime)
        # Measured: prefer throughput_gb_s if finite, else per_call_ns
        tp_gb = get(e, :throughput_gb_s, NaN)
        meas_str, util_str, ceil_str = if isfinite(tp_gb)
            # Convert roofline bound (FLOP/s) to bytes/s via AI, then GB/s
            ceil_bw_gb_s = isfinite(bound.bound_flops_s) ? (bound.bound_flops_s / AI) / 1e9 : NaN
            util_pct = isfinite(ceil_bw_gb_s) && ceil_bw_gb_s > 0 ? 100 * tp_gb / ceil_bw_gb_s : NaN
            (@sprintf("%.2f GB/s", tp_gb),
             isfinite(util_pct) ? @sprintf("%.1f%%", util_pct) : "—",
             isfinite(ceil_bw_gb_s) ? @sprintf("%.2f", ceil_bw_gb_s) : "—")
        else
            pc_ns = get(e, :per_call_ns, NaN)
            (isfinite(pc_ns) ? @sprintf("%.0f ns/call", pc_ns) : "—", "—", "—")
        end
        n_fftw = get(e, :n_fftw_threads, -1)
        @printf(io, "| %s | %d | %.2f | %s | %s | %s | %s | %s |\n",
            kname, n_fftw, AI, bound.regime, verdict, meas_str, ceil_str, util_str)
    end
    return String(take!(io))
end

"""
    _recommendations_md(kernel_results, amdahl_fits, hw_profile) -> String

Numbered recommendations — populated after the benchmark execution pass.
"""
function _recommendations_md(kernel_results, amdahl_fits, hw_profile)
    io = IOBuffer()

    # 1. FFT tuning: compare throughput at n_fftw=1 vs max threaded value
    fft_by_n = Dict{Int, Float64}()
    for (_, e) in kernel_results
        if get(e, :kernel, "") == "FFT forward+inverse"
            n = get(e, :n_fftw_threads, -1)
            tp = get(e, :throughput_gb_s, NaN)
            if n > 0 && isfinite(tp)
                fft_by_n[n] = tp
            end
        end
    end
    if haskey(fft_by_n, 1) && !isempty(setdiff(keys(fft_by_n), (1,)))
        best_threaded_n = argmax(n -> fft_by_n[n], setdiff(keys(fft_by_n), (1,)))
        ratio = fft_by_n[1] / fft_by_n[best_threaded_n]
        if ratio > 1.5
            @printf(io, "1. **FFT: keep `FFTW.set_num_threads(1)`**. Measured throughput at n_fftw=1 is %.2f GB/s; best threaded value (n_fftw=%d) is only %.2f GB/s — a **%.1fx anti-scaling penalty**. At Nt=2^13 the FFT is too small to amortize thread-spawn overhead. This directly validates the Phase 15 determinism invariant (single-threaded FFTW). Do not spend effort tuning MEASURE plans at higher thread counts.\n",
                fft_by_n[1], best_threaded_n, fft_by_n[best_threaded_n], ratio)
        elseif ratio < 0.8
            @printf(io, "1. **FFT: enable `FFTW.set_num_threads(%d)`**. Measured %.2fx speedup over single-threaded. Keep only if src/determinism contract can be relaxed.\n",
                best_threaded_n, 1.0 / ratio)
        else
            @printf(io, "1. **FFT: thread count does not matter** (measured speedup %.2fx). Keep the Phase 15 default for determinism.\n",
                fft_by_n[1] / fft_by_n[best_threaded_n])
        end
    else
        println(io, "1. **FFT tuning**: insufficient data to compare threaded variants.")
    end

    # 2. Thread count for production: from amdahl_fits
    min_p, min_mode = 1.0, "unknown"
    for (mode, fit) in amdahl_fits
        p = Float64(get(fit, "p", 1.0))
        if p < min_p
            min_p = p; min_mode = String(mode)
        end
    end
    ceiling = min_p < 1.0 ? 1.0 / (1.0 - min_p) : Inf
    ceiling_str = isfinite(ceiling) ? @sprintf("%.2fx", ceiling) : "∞"
    if min_p < 0.2
        @printf(io, "2. **Production thread count: `-t 1` or `-t 2`**. Worst-case fitted Amdahl p=%.3f (from mode=%s). Speedup ceiling = %s as n→∞. Going beyond `-t 4` is wasted cost on the canonical single-mode workload.\n",
            min_p, min_mode, ceiling_str)
    elseif min_p < 0.8
        @printf(io, "2. **Production thread count: `-t 8`**. Fitted p=%.3f, speedup ceiling %s. Going to `-t 22` yields ≤%.2fx over `-t 8`.\n",
            min_p, ceiling_str, (1.0 / ((1-min_p) + min_p/22)) / (1.0 / ((1-min_p) + min_p/8)))
    else
        @printf(io, "2. **Production thread count: `-t 22`**. Fitted p=%.3f, near-linear scaling up to tested ceiling.\n", min_p)
    end

    # 3. Burst-VM economics
    if min_p < 0.2
        println(io, "3. **Burst-VM economics: DO NOT use `c3-highcpu-22` for canonical single-mode (M=1) SMF-28 workloads**. The measured speedup ceiling (≤1.1x) means `e2-standard-4` at ~\$0.13/hr delivers the same throughput as `c3-highcpu-22` at ~\$0.90/hr. Reserve the burst VM for (a) multi-mode M>1 phases where the Kerr tullio contraction may actually parallelize, or (b) embarrassingly-parallel parameter sweeps where Gustafson (weak) scaling applies instead of Amdahl.")
    elseif min_p < 0.8
        println(io, "3. **Burst-VM economics: `-t 8` on `c3-highcpu-22` is the sweet spot**. Going beyond `-t 8` wastes money relative to the measured Amdahl ceiling.")
    else
        println(io, "3. **Burst-VM economics: `c3-highcpu-22` at `-t 22` is justified** — near-linear scaling observed.")
    end

    # 4. Next tuning target: RHS step with largest per-call cost
    fwd_ns = NaN; adj_ns = NaN
    for (_, e) in kernel_results
        k = get(e, :kernel, "")
        pc = get(e, :per_call_ns, NaN)
        if k == "Forward RHS step (disp_mmf!)"
            fwd_ns = pc
        elseif k == "Adjoint RHS step (adjoint_disp_mmf!)"
            adj_ns = pc
        end
    end
    if isfinite(fwd_ns) && isfinite(adj_ns)
        ratio = adj_ns / fwd_ns
        @printf(io, "4. **Next tuning target: adjoint RHS step** (%.0f µs/call, **%.1fx** the forward RHS cost of %.0f µs/call). The gap is driven by ODESolution interpolation (`ũω(z)` query inside `adjoint_disp_mmf!`) — investigate dense-interpolation caching (evaluate once per accepted adjoint step, not per RHS call) or switch to a checkpoint-based reverse-mode that avoids the interpolation altogether.\n",
            adj_ns / 1e3, ratio, fwd_ns / 1e3)
    else
        println(io, "4. **Next tuning target**: insufficient kernel timing data.")
    end

    return String(take!(io))
end

# ─────────────────────────────────────────────────────────────────────────────
# Main (guarded so `include()` from other scripts is safe)
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    isfile(P29R_KERNELS_JLD2)    || error("missing $(P29R_KERNELS_JLD2) — run bench_kernels.jl first")  # isfile kernels.jld2
    isfile(P29R_SOLVES_JLD2)     || error("missing $(P29R_SOLVES_JLD2) — run bench_solves.jl first")    # isfile solves.jld2
    isfile(P29R_HW_PROFILE_JSON) || error("missing $(P29R_HW_PROFILE_JSON)")
    isfile(P29R_AMDAHL_JSON)     || error("missing $(P29R_AMDAHL_JSON)")

    kernel_payload = JLD2.load(P29R_KERNELS_JLD2)
    results_table  = kernel_payload["results_table"]
    solves_payload = JLD2.load(P29R_SOLVES_JLD2)
    hw_profile     = JSON3.read(read(P29R_HW_PROFILE_JSON, String), Dict)
    amdahl_fits    = JSON3.read(read(P29R_AMDAHL_JSON, String), Dict)

    bench = Dict(
        "timestamp"           => string(now()),
        "executive_verdict"   => _executive_verdict(results_table, amdahl_fits),
        "kernels_md"          => _kernels_md(results_table),
        "amdahl_md"           => _amdahl_md(amdahl_fits),
        "roofline_md"         => _roofline_md(results_table, hw_profile),
        "recommendations_md"  => _recommendations_md(results_table, amdahl_fits, hw_profile),
    )
    md = assemble_roofline_memo(bench; hw_profile = hw_profile)
    mkpath(dirname(P29R_ROOFLINE_MD))
    mkpath(dirname(P29R_PHASE_REPORT_MD))
    write(P29R_ROOFLINE_MD, md)
    write(P29R_PHASE_REPORT_MD, md)
    @info "Phase 29 reports written" roofline=P29R_ROOFLINE_MD phase_report=P29R_PHASE_REPORT_MD
end
