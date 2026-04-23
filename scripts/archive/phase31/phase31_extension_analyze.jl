#!/usr/bin/env julia
# scripts/extension_analyze.jl — summarize Phase 31 follow-up paths

using Printf
using JLD2

const P31XA_RESULTS = joinpath(@__DIR__, "..", "results", "raman", "phase31", "followup")
const P31XA_DOCS    = joinpath(@__DIR__, "..", "agent-docs", "phase31-reduced-basis")

function p31xa_path_table_row(row::Dict{String,Any})
    seed = row["seed_meta"]
    Jp = row["J_transfer_perturb"]
    return (
        path_name = String(row["path_name"]),
        seed_kind = String(seed["seed_kind"]),
        seed_N_phi = Int(seed["seed_N_phi"]),
        seed_J_dB = Float64(seed["seed_J_final"]),
        final_J_dB = Float64(row["final_J_dB"]),
        gain_dB = isnan(Float64(seed["seed_J_final"])) ? NaN :
            Float64(seed["seed_J_final"]) - Float64(row["final_J_dB"]),
        sigma_3dB = Float64(row["sigma_3dB"]),
        hnlf_gap = Float64(row["J_transfer_HNLF"]) - Float64(row["final_J_dB"]),
        power_gap = get(Jp, "P_10pct", NaN) - Float64(row["final_J_dB"]),
        beta2_gap = get(Jp, "beta2_5pct", NaN) - Float64(row["final_J_dB"]),
        fwhm_gap = get(Jp, "fwhm_5pct", NaN) - Float64(row["final_J_dB"]),
        converged = Bool(row["final_converged"]),
        final_iters = Int(row["final_iterations"]),
    )
end

function p31xa_rank(rows)
    scored = p31xa_path_table_row.(rows)
    return sort(scored, by = x -> (x.final_J_dB, x.hnlf_gap, -x.sigma_3dB))
end

function p31xa_write_summary(rows)
    ranked = p31xa_rank(rows)
    best_depth = ranked[1]
    best_transfer = sort(ranked, by = x -> (x.hnlf_gap, x.final_J_dB))[1]
    best_robust = sort(ranked, by = x -> (-x.sigma_3dB, x.final_J_dB))[1]

    summary_path = joinpath(P31XA_DOCS, "FOLLOWUP-PHASE31-EXTENSION.md")
    open(summary_path, "w") do io
        println(io, "# Phase 31 Follow-Up — Continuation To Full-Grid")
        println(io)
        println(io, "## Ranked Paths")
        println(io)
        println(io, "| Path | Seed | Final J (dB) | Gain vs seed (dB) | σ_3dB | HNLF gap | +10% P gap | +5% β₂ gap | +5% FWHM gap |")
        println(io, "|---|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in ranked
            seed_label = r.seed_kind == "zero" ? "zero" : @sprintf("%s %d", r.seed_kind, r.seed_N_phi)
            println(io, @sprintf("| %s | %s | %.2f | %.2f | %.3f | %.2f | %.2f | %.2f | %.2f |",
                                 r.path_name, seed_label, r.final_J_dB, r.gain_dB,
                                 r.sigma_3dB, r.hnlf_gap, r.power_gap, r.beta2_gap, r.fwhm_gap))
        end
        println(io)
        println(io, "## Verdict")
        println(io)
        println(io, @sprintf("- Deepest path: `%s` at %.2f dB.", best_depth.path_name, best_depth.final_J_dB))
        println(io, @sprintf("- Best HNLF transfer: `%s` with gap %.2f dB.", best_transfer.path_name, best_transfer.hnlf_gap))
        println(io, @sprintf("- Widest noise basin: `%s` with σ_3dB = %.3f rad.", best_robust.path_name, best_robust.sigma_3dB))
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io, "- The follow-up asks whether reduced-basis continuation can survive a final full-grid polish or whether the full-grid step collapses back toward the zero-init basin.")
        println(io, "- Paths are ranked primarily by final depth, then by smaller HNLF transfer gap, then by larger sigma_3dB.")
        println(io, "- Use this file together with `results/raman/phase31/followup/path_comparison.jld2` and the standard-image set in `results/raman/phase31/followup/images/`.")
    end
    return summary_path, ranked
end

function main()
    path = joinpath(P31XA_RESULTS, "path_comparison.jld2")
    rows = JLD2.load(path, "rows")
    summary_path, ranked = p31xa_write_summary(rows)
    println("wrote ", summary_path)
    for r in ranked
        println(@sprintf("%-24s final=%7.2f dB  hnlf_gap=%6.2f dB  sigma=%5.3f",
                         r.path_name, r.final_J_dB, r.hnlf_gap, r.sigma_3dB))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
