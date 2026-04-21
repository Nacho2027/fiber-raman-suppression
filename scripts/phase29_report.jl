"""
Phase 29 Report Generator — consumes `results/phase29/{kernels.jld2,
solves.jld2, amdahl_fits.json, hw_profile.json}` and emits:

  (a) `results/phase29/roofline.md`                         — human-readable memo
  (b) `.planning/phases/29-.../29-REPORT.md`                — canonical phase report

Does NOT re-run benchmarks. Pure analysis. Uses scripts/phase29_roofline_model.jl
for the sole markdown assembler (`assemble_roofline_memo`) so the scope-lock
headings are preserved.
"""

using Printf
using JLD2
using JSON3
using Statistics
using Dates

include(joinpath(@__DIR__, "phase29_roofline_model.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Constants — P29R_ prefix per STATE.md "Script Constant Prefixes"
# ─────────────────────────────────────────────────────────────────────────────

const P29R_OUTPUT_DIR       = joinpath(@__DIR__, "..", "results", "phase29")
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
Dict written by phase29_bench_kernels.jl.
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

"""
    _roofline_md(results_table, hw_profile) -> String

Per-kernel arithmetic-intensity table (populated by the analysis pass). At
scope-lock time this is a stub; the numbers are filled after the burst-VM run.
"""
function _roofline_md(results_table, hw_profile)
    io = IOBuffer()
    println(io, "| Kernel | AI (FLOP/byte) | Regime | Measured throughput | Ceiling | Utilization |")
    println(io, "|--------|----------------|--------|----------------------|---------|-------------|")
    println(io, "<!-- Populated by analysis pass in phase29_report.jl main body -->")
    return String(take!(io))
end

"""
    _recommendations_md(kernel_results, amdahl_fits, hw_profile) -> String

Numbered recommendations — populated after the benchmark execution pass.
"""
function _recommendations_md(kernel_results, amdahl_fits, hw_profile)
    io = IOBuffer()
    println(io, "1. **FFT tuning effort**: <populated based on measured MEASURE vs ESTIMATE delta>")
    println(io, "2. **Thread count for production**: <populated based on fit_amdahl verdict>")
    println(io, "3. **Burst-VM economics**: <populated — cost/benefit of c3-highcpu-22 given measured scaling>")
    println(io, "4. **Next tuning target**: <kernel with worst roofline utilization, not lowest wall time>")
    return String(take!(io))
end

# ─────────────────────────────────────────────────────────────────────────────
# Main (guarded so `include()` from other scripts is safe)
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    isfile(P29R_KERNELS_JLD2)    || error("missing $(P29R_KERNELS_JLD2) — run phase29_bench_kernels.jl first")  # isfile kernels.jld2
    isfile(P29R_SOLVES_JLD2)     || error("missing $(P29R_SOLVES_JLD2) — run phase29_bench_solves.jl first")    # isfile solves.jld2
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
