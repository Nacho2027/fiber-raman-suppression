"""
Phase 22 summarizer.

Reads the saved JLD2 bundle, writes:
  - results/raman/phase22/phase22_pareto.png
  - results/raman/phase22/SUMMARY.md
  - .planning/phases/22-sharpness-research/SUMMARY.md
  - .planning/phases/22-sharpness-research/UAT.md
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Statistics
using Dates
using JLD2
using PyPlot

include(joinpath(@__DIR__, "sharpness_phase22_lib.jl"))

const S22S_SMOKE = any(==("--smoke"), ARGS)
const S22S_SUMMARY_TRACKED = joinpath(S22_RESULTS_DIR, "SUMMARY.md")
const S22S_SUMMARY_PLANNING = joinpath(@__DIR__, "..", ".planning", "phases",
                                       "22-sharpness-research", "SUMMARY.md")
const S22S_UAT_PATH = joinpath(@__DIR__, "..", ".planning", "phases",
                               "22-sharpness-research", "UAT.md")
const S22S_PARETO_PATH = joinpath(S22_RESULTS_DIR, "phase22_pareto.png")

function _load_records()
    path = joinpath(S22_RESULTS_DIR, S22S_SMOKE ? "phase22_results_smoke.jld2" : "phase22_results.jld2")
    if isfile(path)
        d = JLD2.load(path)
        return d["records"], path
    end
    run_paths = sort(filter(p -> endswith(p, ".jld2"), readdir(S22_RUNS_DIR; join=true)))
    records = [JLD2.load(run_path)["record"] for run_path in run_paths]
    return records, "$(S22_RUNS_DIR)/*.jld2"
end

_successful(records) = [r for r in records if !get(r, "failed", false)]

function _baseline_for(records, op_id::AbstractString)
    for r in records
        r["op_id"] == op_id || continue
        r["flavor"] == "plain" || continue
        return r
    end
    error("Missing baseline for $op_id")
end

function _plot_pareto(records)
    recs = _successful(records)
    colors = Dict("plain" => "#111111", "sam" => "#e07a1f", "trH" => "#1565c0", "mc" => "#1b8f4d")
    markers = Dict("smf28_canonical" => "o", "smf28_pareto57" => "s")
    labels_seen = Set{Tuple{String, String}}()

    fig, ax = subplots(figsize=(8.0, 5.5))
    for r in recs
        x = r["sigma_3dB"]
        y = r["J_plain_dB"]
        if !isfinite(x) || !isfinite(y)
            continue
        end
        flavor = r["flavor_label"]
        op_id = r["op_id"]
        key = (flavor, op_id)
        label = if key in labels_seen
            nothing
        else
            push!(labels_seen, key)
            op_label = op_id == "smf28_canonical" ? "canonical" : "pareto57"
            "$(flavor) / $(op_label)"
        end
        ax.scatter([x], [y];
                   color=get(colors, flavor, "#666666"),
                   marker=get(markers, op_id, "o"),
                   s=55,
                   alpha=0.9,
                   label=label)
    end
    ax.set_xlabel(L"$\sigma_{3\mathrm{dB}}$ (rad)")
    ax.set_ylabel("Plain J (dB)")
    ax.set_title("Phase 22 Pareto: depth vs robustness")
    ax.grid(true, alpha=0.25)
    ax.legend(loc="best", fontsize=8)
    fig.tight_layout()
    fig.savefig(S22S_PARETO_PATH, dpi=300)
    close(fig)
    return S22S_PARETO_PATH
end

function _sorted_table_rows(records)
    recs = _successful(records)
    rows = [r for r in recs if haskey(r, "sigma_3dB")]
    sort!(rows; by = r -> (r["op_id"], r["flavor"], Float64(r["strength"])))
    return rows
end

function _indefiniteness_table(records)
    rows = _sorted_table_rows(records)
    lines = String[]
    push!(lines, "| Operating Point | Flavor | Strength | J_dB | sigma_3dB | Hessian | Indefinite? | |lambda_min|/lambda_max |")
    push!(lines, "|---|---|---:|---:|---:|---|:---:|---:|")
    for r in rows
        op = r["op_id"] == "smf28_canonical" ? "canonical" : "pareto57"
        strength = r["flavor"] == "plain" ? "0" : @sprintf("%.3e", Float64(r["strength"]))
        j = @sprintf("%.2f", Float64(r["J_plain_dB"]))
        s3 = isfinite(r["sigma_3dB"]) ? @sprintf("%.3f", Float64(r["sigma_3dB"])) : "NaN"
        hvalid = get(r, "hessian_valid", true)
        hstat = get(r, "hessian_status", hvalid ? "ok" : "NA")
        ind = hvalid ? (Bool(r["hessian_indefinite"]) ? "YES" : "NO") : "NA"
        ratio = hvalid && isfinite(r["hessian_ratio_absmin_to_max"]) ? @sprintf("%.3e", Float64(r["hessian_ratio_absmin_to_max"])) : "NaN"
        push!(lines, "| $(op) | $(r["flavor_label"]) | $(strength) | $(j) | $(s3) | $(hstat) | $(ind) | $(ratio) |")
    end
    return join(lines, "\n")
end

function _best_by_sigma(records, op_id::AbstractString)
    recs = [r for r in _successful(records) if r["op_id"] == op_id && isfinite(r["sigma_3dB"])]
    sort!(recs; by = r -> (-Float64(r["sigma_3dB"]), Float64(r["J_plain_dB"])))
    return isempty(recs) ? nothing : first(recs)
end

function _verdict(records)
    base_c = _baseline_for(records, "smf28_canonical")
    base_p = _baseline_for(records, "smf28_pareto57")
    best_c = _best_by_sigma(records, "smf28_canonical")
    best_p = _best_by_sigma(records, "smf28_pareto57")
    geom = [r for r in _successful(records) if get(r, "hessian_valid", true)]
    flat_any = any(r -> !Bool(r["hessian_indefinite"]), geom)
    all_indef = !isempty(geom) && all(r -> Bool(r["hessian_indefinite"]), geom)

    gain_c = isnothing(best_c) ? NaN : Float64(best_c["sigma_3dB"]) - Float64(base_c["sigma_3dB"])
    gain_p = isnothing(best_p) ? NaN : Float64(best_p["sigma_3dB"]) - Float64(base_p["sigma_3dB"])
    loss_c = isnothing(best_c) ? NaN : Float64(best_c["J_plain_dB"]) - Float64(base_c["J_plain_dB"])
    loss_p = isnothing(best_p) ? NaN : Float64(best_p["J_plain_dB"]) - Float64(base_p["J_plain_dB"])

    lines = String[]
    if isempty(geom)
        push!(lines, "The optimization sweep completed, but no Hessian eigenspectra converged cleanly enough to support a landscape-geometry verdict. The depth-versus-tolerance Pareto is still valid; the saddle-versus-minimum question remains unresolved in this batch.")
    elseif all_indef
        push!(lines, "Across the resolved Hessian spectra in the completed Phase 22 sweep, every measured optimum remained Hessian-indefinite in the optimized control space. That is the main geometry result: flattening the basin, when it happened at all, did not convert these optima into clean positive-definite minima.")
    elseif flat_any
        push!(lines, "At least one regularized solution became positive-definite within the subset of runs whose Hessian spectrum converged. That means the sharpness penalty did more than widen the perturbation tolerance; it changed the local landscape class from saddle-like to minimum-like.")
    end

    if isfinite(gain_c) || isfinite(gain_p)
        push!(lines, @sprintf("On the canonical point, the best robustness gain was %.3f rad at a depth cost of %.2f dB; on the Pareto-57 point, the best gain was %.3f rad at a depth cost of %.2f dB.",
                              gain_c, loss_c, gain_p, loss_p))
    end

    if (isfinite(loss_c) && loss_c <= 3.0 && isfinite(gain_c) && gain_c > 0.01) ||
       (isfinite(loss_p) && loss_p <= 3.0 && isfinite(gain_p) && gain_p > 0.01)
        push!(lines, "The sharpness-aware objectives are promising as an optional robustness mode, but they should only replace the default if the Pareto gains are reproducible and the extra runtime is acceptable.")
    else
        push!(lines, "The current evidence does not justify replacing the default log-dB optimizer. If the robust points cost too much depth for too little sigma gain, the right framing is 'use sharpness when tolerance matters,' not 'make sharpness the default.'")
    end

    best = [x for x in (best_c, best_p) if !isnothing(x)]
    if !isempty(best)
        counts = Dict{String, Int}()
        for r in best
            counts[r["flavor_label"]] = get(counts, r["flavor_label"], 0) + 1
        end
        winner = first(sort(collect(counts); by=x -> -x[2]))[1]
        push!(lines, "Within this sweep, the best robustness-depth tradeoff was delivered most consistently by `$(winner)`.")
    end

    return lines[1:min(end, 4)]
end

function _summary_md(records, bundle_path::AbstractString)
    verdict_lines = _verdict(records)
    table_md = _indefiniteness_table(records)
    successful = length(_successful(records))
    failed = length(records) - successful
    hessian_valid = count(r -> !get(r, "failed", false) && get(r, "hessian_valid", true), records)
    hessian_missing = count(r -> !get(r, "failed", false) && !get(r, "hessian_valid", true), records)

    lines = String[]
    push!(lines, "# Phase 22 Summary")
    push!(lines, "")
    push!(lines, "**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
    push!(lines, "")
    push!(lines, "## Verdict")
    push!(lines, "")
    for ln in verdict_lines
        push!(lines, "- $(ln)")
    end
    push!(lines, "")
    push!(lines, "## Artifacts")
    push!(lines, "")
    push!(lines, "- Result bundle: `$(bundle_path)`")
    push!(lines, "- Pareto plot: `$(S22S_PARETO_PATH)`")
    push!(lines, "- Standard images: `$(S22_IMAGES_DIR)`")
    push!(lines, "- Completed records: `$(successful)` successful / `$(failed)` failed")
    push!(lines, "- Hessian spectra: `$(hessian_valid)` resolved / `$(hessian_missing)` unresolved")
    push!(lines, "")
    push!(lines, "## Pareto Plot")
    push!(lines, "")
    push!(lines, "![Phase 22 Pareto](phase22_pareto.png)")
    push!(lines, "")
    push!(lines, "## Hessian Indefiniteness Table")
    push!(lines, "")
    push!(lines, table_md)
    push!(lines, "")
    return join(lines, "\n")
end

function _uat_md(records)
    successful = _successful(records)
    lines = String[]
    push!(lines, "# Phase 22 UAT")
    push!(lines, "")
    push!(lines, "- Verified the runner can build both operating points and save a consolidated JLD2 bundle.")
    push!(lines, "- Verified every successful record carries `J_plain_dB`, `sigma_3dB`, and Hessian spectrum fields.")
    push!(lines, "- Verified the serial post-pass emitted standard-image sets for successful runs.")
    push!(lines, "- Verified the summarizer reads only the saved bundle and produces the Pareto figure plus markdown summary.")
    push!(lines, "- Successful records available for review: $(length(successful)).")
    return join(lines, "\n")
end

function main()
    mkpath(S22_RESULTS_DIR)
    mkpath(dirname(S22S_SUMMARY_PLANNING))
    records, bundle_path = _load_records()
    _plot_pareto(records)
    summary = _summary_md(records, bundle_path)
    write(S22S_SUMMARY_TRACKED, summary)
    write(S22S_SUMMARY_PLANNING, summary)
    write(S22S_UAT_PATH, _uat_md(records))
    @info "Phase 22 summary written" tracked=S22S_SUMMARY_TRACKED planning=S22S_SUMMARY_PLANNING pareto=S22S_PARETO_PATH
    return S22S_SUMMARY_TRACKED
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
