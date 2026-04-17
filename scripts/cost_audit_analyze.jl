# scripts/cost_audit_analyze.jl
# ═══════════════════════════════════════════════════════════════════════════════
# Phase 16 Plan 01 — Cost-function audit analyzer
# ═══════════════════════════════════════════════════════════════════════════════
# CLI: julia -t auto --project=. scripts/cost_audit_analyze.jl
# Reads results/cost_audit/<cfg>/*_result.jld2 → writes CSVs + 4 PNGs @ 300 DPI.
# ═══════════════════════════════════════════════════════════════════════════════

ENV["MPLBACKEND"] = "Agg"

using JLD2, CSV, DataFrames, Statistics, Printf
using PyPlot

include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

# Column schema — MUST match test_cost_audit_analyzer.jl::csv_schema exactly (D-16).
const CA_CSV_COLS = ["variant", "final_J_linear", "final_J_dB", "delta_J_dB",
    "iterations", "iter_to_90pct", "wall_s", "lambda_max", "cond_proxy",
    "robust_sigma_0.01_mean_dB", "robust_sigma_0.01_max_dB",
    "robust_sigma_0.05_mean_dB", "robust_sigma_0.05_max_dB",
    "robust_sigma_0.1_mean_dB",  "robust_sigma_0.1_max_dB",
    "robust_sigma_0.2_mean_dB",  "robust_sigma_0.2_max_dB"]

const CA_CONFIG_TAGS = ["A", "B", "C"]
const CA_VARIANT_NAMES = ["linear", "log_dB", "sharp", "curvature"]
const CA_VARIANT_COLORS = Dict("linear"    => "#1f77b4",
                                "log_dB"    => "#ff7f0e",
                                "sharp"     => "#2ca02c",
                                "curvature" => "#d62728")
const CA_SIGMAS_FLT = [0.01, 0.05, 0.1, 0.2]

function _load_run(jld2_path::AbstractString)
    d = JLD2.load(jld2_path)
    robust = d["robust"]
    row = Dict{String, Any}(
        "variant"        => d["variant"],
        "final_J_linear" => d["J_final"],
        "final_J_dB"     => d["J_final_dB"],
        "delta_J_dB"     => d["delta_J_dB"],
        "iterations"     => d["iterations"],
        "iter_to_90pct"  => d["iter_to_90pct"],
        "wall_s"         => d["wall_s"],
        "lambda_max"     => d["lambda_max"],
        "cond_proxy"     => d["cond_proxy"],
    )
    for σ in CA_SIGMAS_FLT
        row["robust_sigma_$(σ)_mean_dB"] =
            get(robust, Symbol("robust_sigma_$(σ)_mean_dB"), NaN)
        row["robust_sigma_$(σ)_max_dB"] =
            get(robust, Symbol("robust_sigma_$(σ)_max_dB"),  NaN)
    end
    return row, d
end

function _write_summary(cfg_tag::String, rows::Vector{Dict{String,Any}}, results_root)
    df = DataFrame()
    for col in CA_CSV_COLS
        df[!, col] = [get(r, col, missing) for r in rows]
    end
    out = joinpath(results_root, cfg_tag, "summary.csv")
    isdir(dirname(out)) || mkpath(dirname(out))
    CSV.write(out, df)
    @info "wrote $out"
    return out
end

function _write_summary_all(all_rows::Vector{<:NamedTuple}, results_root)
    # I-10: column name is `variant` (not D-17's literal `cost`). Driver/analyzer
    # vocabulary uses `variant` consistently (run_one(variant, ...), CA_VARIANTS).
    df = DataFrame(config=String[], variant=String[], metric=String[],
                   value=Float64[], dnf=Bool[])
    for nt in all_rows
        dnf = get(nt.run, "dnf", false)
        for (metric, value) in nt.metrics
            push!(df, (nt.config, nt.variant, metric, Float64(value), dnf))
        end
    end
    out = joinpath(results_root, "summary_all.csv")
    CSV.write(out, df)
    @info "wrote $out"
    return out
end

function _plot_convergence(results_root, all_runs)
    fig, axes = PyPlot.subplots(1, 3, figsize=(15, 4), dpi=300)
    for (i, cfg_tag) in enumerate(CA_CONFIG_TAGS)
        ax = axes[i]
        for variant in CA_VARIANT_NAMES
            key = (cfg_tag, variant)
            haskey(all_runs, key) || continue
            trace = get(all_runs[key], "f_trace_linear", Float64[])
            isempty(trace) && continue
            trace_dB = [10*log10(max(v, 1e-15)) for v in trace]
            ax.plot(0:length(trace_dB)-1, trace_dB, label=variant,
                    color=CA_VARIANT_COLORS[variant], linewidth=1.5)
        end
        ax.set_xlabel("L-BFGS iteration"); ax.set_ylabel("J (dB)")
        ax.set_title("Config $cfg_tag"); ax.grid(true, alpha=0.3)
        i == 1 && ax.legend(fontsize=8, loc="upper right")
    end
    PyPlot.tight_layout()
    out = joinpath(results_root, "fig1_convergence.png")
    PyPlot.savefig(out, dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    @info "wrote $out ($(filesize(out)) bytes)"
    return out
end

function _plot_robustness(results_root, all_runs)
    fig, axes = PyPlot.subplots(1, 3, figsize=(15, 4), dpi=300)
    for (i, cfg_tag) in enumerate(CA_CONFIG_TAGS)
        ax = axes[i]
        for variant in CA_VARIANT_NAMES
            key = (cfg_tag, variant)
            haskey(all_runs, key) || continue
            robust = all_runs[key]["robust"]
            means = [get(robust, Symbol("robust_sigma_$(σ)_mean_dB"), NaN)
                     for σ in CA_SIGMAS_FLT]
            ax.plot(CA_SIGMAS_FLT, means, marker="o", label=variant,
                    color=CA_VARIANT_COLORS[variant], linewidth=1.5)
        end
        ax.set_xscale("log"); ax.set_yscale("symlog")
        ax.set_xlabel("σ (rad)"); ax.set_ylabel("mean ΔJ (dB)")
        ax.set_title("Config $cfg_tag — robustness"); ax.grid(true, alpha=0.3)
        i == 1 && ax.legend(fontsize=8)
    end
    PyPlot.tight_layout()
    out = joinpath(results_root, "fig2_robustness.png")
    PyPlot.savefig(out, dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    @info "wrote $out ($(filesize(out)) bytes)"
    return out
end

function _plot_eigenspectra(results_root, all_runs)
    fig, axes = PyPlot.subplots(1, 3, figsize=(15, 4), dpi=300)
    for (i, cfg_tag) in enumerate(CA_CONFIG_TAGS)
        ax = axes[i]
        for variant in CA_VARIANT_NAMES
            key = (cfg_tag, variant)
            haskey(all_runs, key) || continue
            λ = all_runs[key]["lambda_top"]
            (isempty(λ) || all(isnan, λ)) && continue
            ax.plot(1:length(λ), log10.(abs.(λ)), marker="o",
                    label=variant, color=CA_VARIANT_COLORS[variant],
                    linewidth=1.5)
        end
        ax.set_xlabel("Eigenvalue index (top-32)"); ax.set_ylabel("log₁₀ |λ|")
        ax.set_title("Config $cfg_tag — Hessian top-32"); ax.grid(true, alpha=0.3)
        i == 1 && ax.legend(fontsize=8)
    end
    PyPlot.tight_layout()
    out = joinpath(results_root, "fig3_eigenspectra.png")
    PyPlot.savefig(out, dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    @info "wrote $out ($(filesize(out)) bytes)"
    return out
end

function _plot_winner_heatmap(results_root, all_runs)
    metrics_spec = [
        ("final_J_dB",                :lower_is_better),
        ("iter_to_90pct",             :lower_is_better),
        ("wall_s",                    :lower_is_better),
        ("lambda_max",                :lower_is_better),
        ("cond_proxy",                :lower_is_better),
        ("robust_sigma_0.1_mean_dB",  :lower_is_better),
        ("robust_sigma_0.1_max_dB",   :lower_is_better),
        ("converged",                 :higher_is_better),
    ]
    n_cols = length(CA_CONFIG_TAGS) * length(metrics_spec)
    mat = fill(NaN, length(CA_VARIANT_NAMES), n_cols)
    col_labels = String[]
    c = 1
    for cfg_tag in CA_CONFIG_TAGS
        for (m, dir) in metrics_spec
            vals = Float64[]
            for variant in CA_VARIANT_NAMES
                key = (cfg_tag, variant)
                v_raw = if haskey(all_runs, key)
                    if m == "converged"
                        all_runs[key]["converged"] ? 1.0 : 0.0
                    elseif startswith(m, "robust_")
                        Float64(get(all_runs[key]["robust"], Symbol(m), NaN))
                    else
                        v = get(all_runs[key], m, NaN)
                        v isa Bool ? Float64(v) : Float64(v)
                    end
                else
                    NaN
                end
                push!(vals, v_raw)
            end
            # rank 1..4 (ties share adjacent ranks)
            ranks = if dir == :lower_is_better
                ip = sortperm(vals)
                r = zeros(Int, length(vals))
                for (k, ii) in enumerate(ip); r[ii] = k; end
                r
            else
                ip = sortperm(vals, rev=true)
                r = zeros(Int, length(vals))
                for (k, ii) in enumerate(ip); r[ii] = k; end
                r
            end
            mat[:, c] .= ranks
            push!(col_labels, "$cfg_tag/$m"); c += 1
        end
    end
    fig, ax = PyPlot.subplots(figsize=(max(12, 0.5*n_cols), 3.5), dpi=300)
    im = ax.imshow(mat, aspect="auto", cmap="viridis_r", vmin=1, vmax=4)
    ax.set_yticks(0:length(CA_VARIANT_NAMES)-1)
    ax.set_yticklabels(CA_VARIANT_NAMES)
    ax.set_xticks(0:n_cols-1)
    ax.set_xticklabels(col_labels, rotation=75, ha="right", fontsize=7)
    PyPlot.colorbar(im, ax=ax, label="rank (1=best)")
    ax.set_title("Winner heatmap — per-metric rank across variants")
    PyPlot.tight_layout()
    out = joinpath(results_root, "fig4_winner_heatmap.png")
    PyPlot.savefig(out, dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    @info "wrote $out ($(filesize(out)) bytes)"
    return out
end

"""
    analyze_all(; results_root=...) -> Nothing

Read every `<results_root>/<cfg>/<variant>_result.jld2`, write
per-config `summary.csv`, `summary_all.csv`, and 4 PNGs.
"""
function analyze_all(; results_root::AbstractString =
                     joinpath(@__DIR__, "..", "results", "cost_audit"))
    isdir(results_root) || error("results_root does not exist: $results_root")
    all_runs = Dict{Tuple{String,String}, Dict{String,Any}}()
    for cfg_tag in CA_CONFIG_TAGS
        dir = joinpath(results_root, cfg_tag)
        isdir(dir) || (@warn "missing config dir $dir"; continue)
        rows = Dict{String,Any}[]
        for variant in CA_VARIANT_NAMES
            path = joinpath(dir, "$(variant)_result.jld2")
            if !isfile(path)
                @warn "missing $path"; continue
            end
            row, d = _load_run(path)
            push!(rows, row)
            all_runs[(cfg_tag, variant)] = d
        end
        isempty(rows) || _write_summary(cfg_tag, rows, results_root)
    end

    # Long-format summary_all.csv
    long_rows = NamedTuple[]
    for ((cfg_tag, variant), d) in all_runs
        metrics = Dict{String,Any}()
        for m in ("final_J_linear", "final_J_dB", "delta_J_dB", "iterations",
                  "iter_to_90pct", "wall_s", "lambda_max", "cond_proxy")
            src = m == "final_J_linear" ? "J_final" : m
            v = get(d, src, NaN)
            metrics[m] = Float64(v)
        end
        for σ in CA_SIGMAS_FLT
            metrics["robust_sigma_$(σ)_mean_dB"] =
                Float64(get(d["robust"], Symbol("robust_sigma_$(σ)_mean_dB"), NaN))
            metrics["robust_sigma_$(σ)_max_dB"] =
                Float64(get(d["robust"], Symbol("robust_sigma_$(σ)_max_dB"), NaN))
        end
        metrics["converged"] = d["converged"] ? 1.0 : 0.0
        push!(long_rows, (config=cfg_tag, variant=variant,
                          run=d, metrics=metrics))
    end
    _write_summary_all(long_rows, results_root)

    # Figures
    _plot_convergence(results_root, all_runs)
    _plot_robustness(results_root, all_runs)
    _plot_eigenspectra(results_root, all_runs)
    _plot_winner_heatmap(results_root, all_runs)

    for i in 1:4
        name = ("convergence", "robustness", "eigenspectra", "winner_heatmap")[i]
        p = joinpath(results_root, "fig$(i)_$(name).png")
        isfile(p) && filesize(p) > 20_000 ||
            @warn "Figure $p missing or undersized (got $(isfile(p) ? filesize(p) : 0) bytes)"
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    analyze_all()
end
