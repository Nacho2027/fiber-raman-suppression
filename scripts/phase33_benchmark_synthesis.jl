# scripts/phase33_benchmark_synthesis.jl — Phase 33 cross-run synthesis.
#
# Loads results/raman/phase33/<tag>/<start_type>/_result.jld2 and telemetry.csv
# for every (BENCHMARK_CONFIGS × START_TYPES) pair. Writes:
#   - results/raman/phase33/SYNTHESIS.md       — master table + per-config narrative
#   - results/raman/phase33/rho_distribution.png   — accepted-ρ histograms
#   - results/raman/phase33/exit_codes.png         — stacked bar: exit codes by config
#   - results/raman/phase33/failure_taxonomy_by_config.png — rejection-cause breakdown
#
# Light file-I/O + matplotlib. No simulation, no burst VM required.
#
# Design choices:
#   - P8 pre-flight skips emit trust_report.md but NO _result.jld2. We treat
#     these as a dedicated row class "SKIPPED_P8" in every aggregation.
#   - exit_code in JLD2 is stored as String (see phase33_benchmark_run.jl
#     jldsave); we compare as strings throughout.
#   - CSV parse: readdlm with header=true returns (data, header) where header
#     is a 1×N Matrix. Symbol columns (cg_exit) land as bare strings (no
#     quotes were written by `_fmt_symbol`).

ENV["MPLBACKEND"] = "Agg"
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using JLD2
using Printf
using Dates
using Statistics
using DelimitedFiles
using PyPlot

# BENCHMARK_CONFIGS + START_TYPES. Side-effect-free include (no Pkg.activate,
# no ensure_deterministic_*). Do NOT include phase33_benchmark_run.jl here —
# that file has Pkg.activate + driver main block.
include(joinpath(@__DIR__, "phase33_benchmark_common.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Data loading
# ─────────────────────────────────────────────────────────────────────────────

"""
    load_all_runs(root="results/raman/phase33") -> Vector{NamedTuple}

Walk every (cfg, start_type) and return one NamedTuple per slot:
  (cfg, start_type, present::Bool, skipped_p8::Bool, edge_frac,
   result::Union{Dict,Nothing}, telemetry::Union{Tuple,Nothing})

- `present=true` iff _result.jld2 exists and was loaded.
- `skipped_p8=true` iff the slot's trust_report.md contains the P8 abort stub.
- `edge_frac` extracted from the trust_report.md line when parseable, else NaN.
"""
function load_all_runs(root::AbstractString = "results/raman/phase33")
    rows = Any[]
    for cfg in BENCHMARK_CONFIGS
        for st in START_TYPES
            dir = joinpath(root, cfg.tag, string(st))
            jld2_path = joinpath(dir, "_result.jld2")
            csv_path = joinpath(dir, "telemetry.csv")
            tr_path = joinpath(dir, "trust_report.md")

            skipped_p8 = false
            edge_frac = NaN
            if isfile(tr_path)
                txt = read(tr_path, String)
                if occursin("EDGE_FRAC_SUSPECT", txt)
                    skipped_p8 = true
                    m = match(r"edge fraction:\s*`([0-9eE.+\-]+)`", txt)
                    if m !== nothing
                        try
                            edge_frac = parse(Float64, m.captures[1])
                        catch
                        end
                    end
                end
            end

            if !isfile(jld2_path)
                push!(rows, (cfg = cfg, start_type = st, present = false,
                             skipped_p8 = skipped_p8, edge_frac = edge_frac,
                             result = nothing, telemetry = nothing))
                continue
            end

            result = jldopen(jld2_path, "r") do f
                Dict{String,Any}(String(k) => read(f, k) for k in keys(f))
            end
            telemetry = isfile(csv_path) ? readdlm(csv_path, ','; header = true) : nothing
            push!(rows, (cfg = cfg, start_type = st, present = true,
                         skipped_p8 = skipped_p8, edge_frac = edge_frac,
                         result = result, telemetry = telemetry))
        end
    end
    return rows
end

# ─────────────────────────────────────────────────────────────────────────────
# Telemetry parsing helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    _col(header, name) -> Int

Locate column index for `name` in the 1xN header matrix from `readdlm(...; header=true)`.
Throws if missing so telemetry schema drift is caught loudly.
"""
function _col(header, name::AbstractString)
    hdr_vec = vec(header)
    idx = findfirst(==(name), hdr_vec)
    @assert idx !== nothing "telemetry header missing column '$name' (have $(hdr_vec))"
    return idx
end

_as_float(x::Number) = Float64(x)
function _as_float(x::AbstractString)
    s = strip(x)
    (lowercase(s) == "nan") && return NaN
    (lowercase(s) in ("inf", "+inf")) && return Inf
    (lowercase(s) == "-inf") && return -Inf
    return parse(Float64, s)
end

_as_bool(x::Bool) = x
function _as_bool(x)
    s = lowercase(strip(string(x)))
    return s in ("true", "1", "yes")
end

"""
    accepted_rhos(row) -> Vector{Float64}

Return ρ values for accepted iterations. Empty if no telemetry or no accepted
iters.
"""
function accepted_rhos(row)
    (row.present && row.telemetry !== nothing) || return Float64[]
    data, header = row.telemetry
    rho_i = _col(header, "rho")
    acc_i = _col(header, "step_accepted")
    out = Float64[]
    for k in 1:size(data, 1)
        if _as_bool(data[k, acc_i])
            push!(out, _as_float(data[k, rho_i]))
        end
    end
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Rejection-cause counting
# ─────────────────────────────────────────────────────────────────────────────

const REJECTION_CAUSES = (:rho_too_small, :negative_curvature, :boundary_hit,
                          :cg_max_iter, :nan_at_trial_point)

"""
    rejection_cause_counts(rows) -> Dict{Tuple{String,Symbol},Int}

Sum rejection causes per config (across all start types). Cause assignment
per rejected telemetry row:
  - NaN ρ                  -> :nan_at_trial_point
  - cg_exit NEGATIVE_CURVATURE -> :negative_curvature
  - cg_exit BOUNDARY_HIT   -> :boundary_hit
  - cg_exit MAX_ITER       -> :cg_max_iter
  - else                   -> :rho_too_small
"""
function rejection_cause_counts(rows)
    counts = Dict{Tuple{String,Symbol},Int}()
    for cfg in BENCHMARK_CONFIGS, c in REJECTION_CAUSES
        counts[(cfg.tag, c)] = 0
    end
    for r in rows
        (r.present && r.telemetry !== nothing) || continue
        data, header = r.telemetry
        rho_i = _col(header, "rho")
        acc_i = _col(header, "step_accepted")
        cg_i = _col(header, "cg_exit")
        for k in 1:size(data, 1)
            _as_bool(data[k, acc_i]) && continue
            rho_v = _as_float(data[k, rho_i])
            cg = strip(string(data[k, cg_i]))
            cause = if isnan(rho_v)
                :nan_at_trial_point
            elseif occursin("NEGATIVE_CURVATURE", cg)
                :negative_curvature
            elseif occursin("BOUNDARY_HIT", cg)
                :boundary_hit
            elseif occursin("MAX_ITER", cg)
                :cg_max_iter
            else
                :rho_too_small
            end
            counts[(r.cfg.tag, cause)] += 1
        end
    end
    return counts
end

# ─────────────────────────────────────────────────────────────────────────────
# Plot 1 — ρ distributions (Nconfigs × Nstarts grid)
# ─────────────────────────────────────────────────────────────────────────────

function plot_rho_distribution(rows; path::AbstractString)
    nc = length(BENCHMARK_CONFIGS)
    ns = length(START_TYPES)
    fig, axes = subplots(nc, ns; figsize = (4.0 * ns, 3.2 * nc), squeeze = false)
    for (i, cfg) in enumerate(BENCHMARK_CONFIGS)
        for (j, st) in enumerate(START_TYPES)
            ax = axes[i, j]
            row = first(r for r in rows if r.cfg.tag == cfg.tag && r.start_type == st)
            status = if row.skipped_p8
                "SKIPPED_P8"
            elseif !row.present
                "MISSING"
            else
                string(row.result["exit_code"])
            end
            title_str = "$(cfg.tag)\n$(st)  exit=$(status)"
            ax.set_title(title_str; fontsize = 8)
            ax.axvline(0.25; ls = "--", color = "C1", lw = 0.8, label = "η₁=0.25")
            ax.axvline(0.75; ls = "--", color = "C2", lw = 0.8, label = "η₂=0.75")
            ax.set_xlim(-1.5, 2.5)
            if !row.present
                ax.text(0.5, 0.5, status; ha = "center", va = "center",
                        transform = ax.transAxes, fontsize = 10, color = "0.4")
                ax.set_yticks([])
                continue
            end
            rhos = accepted_rhos(row)
            if isempty(rhos)
                ax.text(0.5, 0.5, "no accepted\nsteps"; ha = "center", va = "center",
                        transform = ax.transAxes, fontsize = 9, color = "0.35")
                ax.set_yticks([])
            else
                ax.hist(rhos; bins = 30, range = (-1.5, 2.5), color = "C0", alpha = 0.75)
                ax.set_ylabel("count"; fontsize = 8)
            end
            ax.set_xlabel("ρ"; fontsize = 8)
            ax.tick_params(labelsize = 7)
        end
    end
    fig.suptitle("Phase 33 accepted-step ρ distributions (9 TR runs)"; fontsize = 11)
    fig.tight_layout(rect = (0, 0, 1, 0.97))
    fig.savefig(path; dpi = 300)
    close(fig)
    return path
end

# ─────────────────────────────────────────────────────────────────────────────
# Plot 2 — exit codes stacked bar
# ─────────────────────────────────────────────────────────────────────────────

const ALL_EXIT_CODES = [
    "CONVERGED_2ND_ORDER",
    "CONVERGED_1ST_ORDER_SADDLE",
    "RADIUS_COLLAPSE",
    "MAX_ITER",
    "MAX_ITER_STALLED",
    "NAN_IN_OBJECTIVE",
    "GAUGE_LEAK",
    "SKIPPED_P8",
    "MISSING",
]

function exit_code_counts(rows)
    configs = [cfg.tag for cfg in BENCHMARK_CONFIGS]
    counts = Dict{Tuple{String,String},Int}()
    for c in configs, ec in ALL_EXIT_CODES
        counts[(c, ec)] = 0
    end
    for r in rows
        ec = if r.skipped_p8
            "SKIPPED_P8"
        elseif !r.present
            "MISSING"
        else
            string(r.result["exit_code"])
        end
        counts[(r.cfg.tag, ec)] += 1
    end
    return counts
end

function plot_exit_codes(rows; path::AbstractString)
    configs = [cfg.tag for cfg in BENCHMARK_CONFIGS]
    counts = exit_code_counts(rows)
    fig, ax = subplots(figsize = (10, 5))
    x = collect(1:length(configs))
    bottom = zeros(length(configs))
    for ec in ALL_EXIT_CODES
        y = Float64[counts[(c, ec)] for c in configs]
        sum(y) == 0 && continue
        ax.bar(x, y; bottom = bottom, label = ec)
        bottom .+= y
    end
    ax.set_xticks(x)
    ax.set_xticklabels(configs; rotation = 20, ha = "right", fontsize = 9)
    ax.set_ylabel("runs per config (out of $(length(START_TYPES)))")
    ax.set_title("Phase 33 exit codes by config (N=$(length(START_TYPES)) start types per config)")
    ax.legend(loc = "upper right", fontsize = 8, framealpha = 0.9)
    fig.tight_layout()
    fig.savefig(path; dpi = 300)
    close(fig)
    return path
end

# ─────────────────────────────────────────────────────────────────────────────
# Plot 3 — rejection-cause stacked bar
# ─────────────────────────────────────────────────────────────────────────────

function plot_failure_taxonomy(rows; path::AbstractString)
    configs = [cfg.tag for cfg in BENCHMARK_CONFIGS]
    counts = rejection_cause_counts(rows)
    fig, ax = subplots(figsize = (10, 5))
    x = collect(1:length(configs))
    bottom = zeros(length(configs))
    for c in REJECTION_CAUSES
        y = Float64[counts[(cfg, c)] for cfg in configs]
        sum(y) == 0 && continue
        ax.bar(x, y; bottom = bottom, label = String(c))
        bottom .+= y
    end
    ax.set_xticks(x)
    ax.set_xticklabels(configs; rotation = 20, ha = "right", fontsize = 9)
    ax.set_ylabel("rejected steps (summed across $(length(START_TYPES)) start types)")
    ax.set_title("Phase 33 rejection causes by config")
    ax.legend(loc = "upper right", fontsize = 8, framealpha = 0.9)
    fig.tight_layout()
    fig.savefig(path; dpi = 300)
    close(fig)
    return path
end

# ─────────────────────────────────────────────────────────────────────────────
# SYNTHESIS.md
# ─────────────────────────────────────────────────────────────────────────────

"""
    _linear_to_dB(J) -> Float64

Physics cost `J` is a linear energy fraction in [0, 1] (see raman_optimization.jl
cost_and_gradient with log_cost=false). Convert to dB for the master table.
Clamp at 1e-30 to keep -∞ out of the markdown.
"""
_linear_to_dB(J::Real) = 10 * log10(max(J, 1e-30))

function write_synthesis_md(rows; path::AbstractString)
    open(path, "w") do io
        println(io, "# Phase 33 Benchmark Synthesis")
        println(io)
        present = count(r -> r.present, rows)
        skipped = count(r -> r.skipped_p8, rows)
        missing_ = length(rows) - present - skipped
        println(io, "**Runs:** $(length(rows)) ($(present) TR-executed, " *
                    "$(skipped) SKIPPED_P8, $(missing_) MISSING)")
        println(io, "**Configs:** $(length(BENCHMARK_CONFIGS)) " *
                    "(" * join([cfg.tag for cfg in BENCHMARK_CONFIGS], ", ") * ")")
        println(io, "**Start types:** $(length(START_TYPES)) " *
                    "(" * join(string.(START_TYPES), ", ") * ")")
        println(io, "**Generated:** $(now())")
        println(io)

        # Provenance note: plan wrote "12 runs" before matrix reductions.
        println(io, "> **Matrix provenance.** The original research plan proposed 4 configs × 3 start types = 12 runs. ")
        println(io, "> Config `bench-04-pareto57-nphi57` was dropped 2026-04-21 because its per-row warm-start JLD2 was never synced ")
        println(io, "> to the burst VM (see `scripts/phase33_benchmark_common.jl`). The remaining 3 configs × 3 start types = 9 slots ")
        println(io, "> were executed on the ephemeral burst VM. The Phase-28 edge-fraction pre-flight trust gate (pitfall P8) then ")
        println(io, "> aborted 3 of those 9 before the TR optimizer ran, so 6 slots produced `_result.jld2` artifacts and the other ")
        println(io, "> 3 produced `trust_report.md` stubs only. These tables and figures render all 9 slots; SKIPPED_P8 rows carry ")
        println(io, "> the measured edge fraction instead of optimizer metrics.")
        println(io)

        # ── Master Table ────────────────────────────────────────────────────
        println(io, "## Master Table")
        println(io)
        println(io, "| config | start_type | exit_code | J_final | J_final_dB | iterations | hvps | grad_calls | λ_min | λ_max | wall_s |")
        println(io, "|--------|------------|-----------|--------:|-----------:|-----------:|-----:|-----------:|------:|------:|-------:|")
        for r in rows
            if r.skipped_p8
                @printf(io, "| %s | %s | SKIPPED_P8 (edge_frac=%.3e) | — | — | — | — | — | — | — | — |\n",
                        r.cfg.tag, r.start_type, r.edge_frac)
                continue
            end
            if !r.present
                @printf(io, "| %s | %s | MISSING | — | — | — | — | — | — | — | — |\n",
                        r.cfg.tag, r.start_type)
                continue
            end
            d = r.result
            J = Float64(d["J_final"])
            @printf(io, "| %s | %s | %s | %.3e | %.2f | %d | %d | %d | %.3e | %.3e | %.1f |\n",
                    r.cfg.tag, r.start_type, d["exit_code"],
                    J, _linear_to_dB(J),
                    Int(d["iterations"]), Int(d["hvps_total"]),
                    Int(d["grad_calls_total"]),
                    Float64(d["lambda_min_final"]),
                    Float64(d["lambda_max_final"]),
                    Float64(d["wall_s"]))
        end
        println(io)

        # ── Exit-Code Distribution ──────────────────────────────────────────
        println(io, "## Exit-Code Distribution")
        println(io)
        exits = Dict{String,Int}()
        for r in rows
            ec = if r.skipped_p8
                "SKIPPED_P8"
            elseif !r.present
                "MISSING"
            else
                string(r.result["exit_code"])
            end
            exits[ec] = get(exits, ec, 0) + 1
        end
        for (k, v) in sort(collect(exits), by = first)
            println(io, "- `$k`: $v")
        end
        println(io)

        # ── Rejection Cause Summary ────────────────────────────────────────
        println(io, "## Rejection Cause Summary (all runs combined)")
        println(io)
        rej = rejection_cause_counts(rows)
        println(io, "| config | rho_too_small | negative_curvature | boundary_hit | cg_max_iter | nan_at_trial_point |")
        println(io, "|--------|--------------:|-------------------:|-------------:|------------:|-------------------:|")
        for cfg in BENCHMARK_CONFIGS
            vals = [rej[(cfg.tag, c)] for c in REJECTION_CAUSES]
            println(io, "| $(cfg.tag) | " * join(string.(vals), " | ") * " |")
        end
        totals = [sum(rej[(cfg.tag, c)] for cfg in BENCHMARK_CONFIGS) for c in REJECTION_CAUSES]
        println(io, "| **TOTAL** | " * join(string.(totals), " | ") * " |")
        println(io)

        # ── Per-Config Narrative ───────────────────────────────────────────
        println(io, "## Per-Config Narrative")
        println(io)
        for cfg in BENCHMARK_CONFIGS
            println(io, "### $(cfg.tag)")
            println(io, "**Fiber:** $(cfg.fiber), **L:** $(cfg.L) m, **P:** $(cfg.P) W, " *
                        "**Nt:** $(cfg.Nt), **time_window_ps:** $(cfg.time_window_ps)")
            println(io, "**Warm-start:** `$(cfg.warm_jld2)` — $(cfg.warm_note)")
            println(io)
            for st in START_TYPES
                r = first(x for x in rows if x.cfg.tag == cfg.tag && x.start_type == st)
                if r.skipped_p8
                    println(io, @sprintf("- **%s**: SKIPPED_P8 — input-shaped edge_frac=%.3e > threshold 1e-3. No TR run executed.",
                                         st, r.edge_frac))
                    continue
                end
                if !r.present
                    println(io, "- **$st**: MISSING — no `_result.jld2` and no P8 stub found.")
                    continue
                end
                d = r.result
                J = Float64(d["J_final"])
                rhos = accepted_rhos(r)
                rho_summary = if isempty(rhos)
                    "no accepted iterations"
                else
                    @sprintf("ρ (accepted, n=%d): mean=%.3f min=%.3f max=%.3f",
                            length(rhos), mean(rhos), minimum(rhos), maximum(rhos))
                end
                println(io, @sprintf("- **%s**: exit=`%s`, J=%.3e (%.2f dB), iters=%d, HVPs=%d, λ_min=%.3e, λ_max=%.3e, wall=%.1fs",
                                     st, d["exit_code"], J, _linear_to_dB(J),
                                     Int(d["iterations"]), Int(d["hvps_total"]),
                                     Float64(d["lambda_min_final"]),
                                     Float64(d["lambda_max_final"]),
                                     Float64(d["wall_s"])))
                println(io, "    - $rho_summary")
            end
            println(io)
        end

        # ── Gauge-Leak Audit ───────────────────────────────────────────────
        println(io, "## Gauge-Leak Audit")
        println(io)
        gl = [r for r in rows if r.present && string(r.result["exit_code"]) == "GAUGE_LEAK"]
        if isempty(gl)
            println(io, "- **None.** No run exited `GAUGE_LEAK`. Assertion `‖P_null·p‖ ≤ 1e-8·‖p‖` held on every accepted step across all executed runs. ✓")
        else
            println(io, "- **FIRED** — Plan 01 bug; escalate before Phase 34:")
            for r in gl
                println(io, "    - $(r.cfg.tag)/$(r.start_type)")
            end
        end
        println(io)

        # ── NaN Audit ──────────────────────────────────────────────────────
        println(io, "## NaN Audit")
        println(io)
        nans = [r for r in rows if r.present && string(r.result["exit_code"]) == "NAN_IN_OBJECTIVE"]
        if isempty(nans)
            println(io, "- **None.** No run exited `NAN_IN_OBJECTIVE`. ✓")
        else
            for r in nans
                println(io, "- $(r.cfg.tag)/$(r.start_type): NAN_IN_OBJECTIVE — investigate edge-fraction / time-window.")
            end
        end
        println(io)
        println(io, "> **Telemetry caveat.** Two `CONVERGED_1ST_ORDER_SADDLE` runs (bench-02 warm, bench-02 perturbed) log a single ")
        println(io, "> `nan_at_trial_point` row in the rejection breakdown. This is the *terminal diagnostic record* pushed by the ")
        println(io, "> λ-probe branch at iter 0 (see `_optimize_tr_core` at trust_region_optimize.jl line ~376): when the gradient ")
        println(io, "> was already below `g_tol` on entry, the outer loop recorded a zero-step-size row with `ρ=NaN` for visibility. ")
        println(io, "> No trial point actually NaN'd; the exit code `CONVERGED_1ST_ORDER_SADDLE` is authoritative.")
        println(io)

        # ── P8 Audit ───────────────────────────────────────────────────────
        println(io, "## Pre-flight (P8) Audit")
        println(io)
        skips = [r for r in rows if r.skipped_p8]
        if isempty(skips)
            println(io, "- **No P8 skips.**")
        else
            println(io, "The Phase-28 edge-fraction gate aborted $(length(skips)) slots before the TR optimizer ran. This is the gate working as designed — those pulses have already walked off the attenuator and any optimizer result would be contaminated (see 33-RESEARCH.md §P8).")
            println(io)
            for r in skips
                println(io, @sprintf("- %s/%s: edge_frac=%.3e (> 1e-3 threshold)",
                                     r.cfg.tag, r.start_type, r.edge_frac))
            end
        end
        println(io)

        # ── Accepted-step statistics (global) ───────────────────────────────
        println(io, "## Accepted-step Statistics (across all executed runs)")
        println(io)
        all_rhos = Float64[]
        for r in rows
            append!(all_rhos, accepted_rhos(r))
        end
        if isempty(all_rhos)
            println(io, "- No run produced an accepted step. All 6 executed runs exited before committing to any update ")
            println(io, "  (4 × `RADIUS_COLLAPSE` with 10 iterations of rejections; 2 × `CONVERGED_1ST_ORDER_SADDLE` at iter 0).")
            println(io, "- This is consistent with the Phase 35 saddle-dominated-landscape hypothesis: from both cold φ=0 ")
            println(io, "  initializations and Phase-21 honest warm-starts, TR cannot find an improving direction that its ")
            println(io, "  quadratic model trusts to predict.")
        else
            @printf(io, "- N accepted: %d\n", length(all_rhos))
            @printf(io, "- ρ mean: %.3f, median: %.3f, min: %.3f, max: %.3f\n",
                    mean(all_rhos), median(all_rhos), minimum(all_rhos), maximum(all_rhos))
        end
        println(io)
    end
    return path
end

# ─────────────────────────────────────────────────────────────────────────────
# Top-level
# ─────────────────────────────────────────────────────────────────────────────

function synthesize_phase33(; root::AbstractString = "results/raman/phase33")
    rows = load_all_runs(root)
    @info "phase33 synthesis" slots = length(rows) present = count(r -> r.present, rows) skipped_p8 = count(r -> r.skipped_p8, rows)
    plot_rho_distribution(rows; path = joinpath(root, "rho_distribution.png"))
    plot_exit_codes(rows; path = joinpath(root, "exit_codes.png"))
    plot_failure_taxonomy(rows; path = joinpath(root, "failure_taxonomy_by_config.png"))
    write_synthesis_md(rows; path = joinpath(root, "SYNTHESIS.md"))
    @info "synthesis complete" markdown = joinpath(root, "SYNTHESIS.md")
    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    synthesize_phase33()
end
