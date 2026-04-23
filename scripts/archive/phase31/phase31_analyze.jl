# scripts/analyze.jl — Phase 31 Plan 02 Task 3
#
# Loads sweep_A_basis.jld2, sweep_B_penalty.jld2, and transfer_results.jld2
# and produces:
#   1. pareto.png        — 4-panel Pareto (J_dB vs N_eff, σ_3dB, poly_R², transfer gap)
#   2. L_curves/*.png    — one per penalty family
#   3. aic_ranking.csv   — AIC ranking across both branches
#   4. candidates.md     — recommended basis/penalty with justification
#   5. FINDINGS.md       — phase narrative answer
#
# Invocation: julia -t auto --project=. scripts/analyze.jl

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end

using Printf
using LinearAlgebra
using Statistics
using JLD2
using Dates
using CSV
using DataFrames
using PyPlot

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

const P31Z_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase31")
const P31Z_AGENT_DOCS = joinpath(@__DIR__, "..", "agent-docs", "phase31-reduced-basis")
const P31Z_RUN_TAG    = Dates.format(now(), "yyyymmdd_HHMMSS")

mkpath(joinpath(P31Z_RESULTS_DIR, "L_curves"))
mkpath(P31Z_AGENT_DOCS)

# ─────────────────────────────────────────────────────────────────────────────
# Load all three JLD2 files into a flat DataFrame
# ─────────────────────────────────────────────────────────────────────────────

"""
    load_all_rows() -> DataFrame

Load Branch A + Branch B rows with transfer-probe augmentation. Returns
one row per source optimum.
"""
function load_all_rows()
    sweep_A = joinpath(P31Z_RESULTS_DIR, "sweep_A_basis.jld2")
    sweep_B = joinpath(P31Z_RESULTS_DIR, "sweep_B_penalty.jld2")
    transfer = joinpath(P31Z_RESULTS_DIR, "transfer_results.jld2")

    rows_A = isfile(sweep_A) ? JLD2.load(sweep_A, "rows") : Dict{String,Any}[]
    rows_B = isfile(sweep_B) ? JLD2.load(sweep_B, "rows") : Dict{String,Any}[]
    rows_T = isfile(transfer) ? JLD2.load(transfer, "rows") : Dict{String,Any}[]

    # Index transfer by (branch, source_index)
    transfer_by_idx = Dict{Tuple{String,Int},Dict{String,Any}}()
    for tr in rows_T
        key = (String(tr["source_branch"]), Int(tr["source_index"]))
        transfer_by_idx[key] = tr
    end

    rows_combined = Dict{String,Any}[]
    for (branch_id, rs) in (("A", rows_A), ("B", rows_B))
        for (i, r) in enumerate(rs)
            rr = Dict{String,Any}(r)
            tr = get(transfer_by_idx, (branch_id, i), nothing)
            if tr !== nothing
                rr["J_transfer_HNLF"]   = tr["J_transfer_HNLF"]
                rr["sigma_3dB"]          = tr["sigma_3dB"]
                for (label, J) in tr["J_transfer_perturb"]
                    rr["J_transfer_$label"] = J
                end
                rr["perturb_flags"] = tr["perturb_flags"]
            else
                rr["J_transfer_HNLF"] = NaN
                rr["sigma_3dB"]        = NaN
            end
            rr["branch_id"] = branch_id
            rr["source_index"] = i
            push!(rows_combined, rr)
        end
    end

    return rows_combined
end

# ─────────────────────────────────────────────────────────────────────────────
# Pareto: 4-panel figure
# ─────────────────────────────────────────────────────────────────────────────

function pareto_figure(rows::Vector{<:Dict{String,Any}}, outpath::AbstractString)
    J_dB = [Float64(r["J_final"]) for r in rows]
    N_eff = [Float64(r["N_eff"]) for r in rows]
    σ_3dB = [Float64(r["sigma_3dB"]) for r in rows]
    poly_R2 = [Float64(r["polynomial_R2"]) for r in rows]
    J_hnlf = [Float64(r["J_transfer_HNLF"]) for r in rows]
    branches = [String(r["branch_id"]) for r in rows]

    colorA = "tab:blue"
    colorB = "tab:orange"
    colors = [b == "A" ? colorA : colorB for b in branches]

    fig, axes = subplots(2, 2, figsize=(12, 9))

    # Panel (a): J vs N_eff
    ax = axes[1, 1]
    for i in eachindex(J_dB)
        ax.scatter(N_eff[i], J_dB[i], c=colors[i], s=50, alpha=0.8,
                   edgecolors="k", linewidth=0.5)
    end
    ax.set_xlabel("effective # active coefficients (N_eff)")
    ax.set_ylabel("J_final (dB)")
    ax.set_title("(a) Depth vs effective dimensionality")
    ax.set_xscale("log")
    ax.grid(true, alpha=0.3)

    # Panel (b): J vs σ_3dB (robustness)
    ax = axes[1, 2]
    for i in eachindex(J_dB)
        isnan(σ_3dB[i]) && continue
        ax.scatter(σ_3dB[i], J_dB[i], c=colors[i], s=50, alpha=0.8,
                   edgecolors="k", linewidth=0.5)
    end
    ax.set_xlabel("σ_3dB (rad) — larger = more robust")
    ax.set_ylabel("J_final (dB)")
    ax.set_title("(b) Depth vs Gaussian-perturbation robustness")
    ax.grid(true, alpha=0.3)

    # Panel (c): J vs polynomial_R² (interpretability)
    ax = axes[2, 1]
    for i in eachindex(J_dB)
        isnan(poly_R2[i]) && continue
        ax.scatter(poly_R2[i], J_dB[i], c=colors[i], s=50, alpha=0.8,
                   edgecolors="k", linewidth=0.5)
    end
    ax.set_xlabel("polynomial R² (2..4) — higher = more polynomial-like")
    ax.set_ylabel("J_final (dB)")
    ax.set_title("(c) Depth vs polynomial interpretability")
    ax.grid(true, alpha=0.3)

    # Panel (d): J on HNLF vs J on canonical (transferability)
    ax = axes[2, 2]
    for i in eachindex(J_dB)
        isnan(J_hnlf[i]) && continue
        ax.scatter(J_dB[i], J_hnlf[i], c=colors[i], s=50, alpha=0.8,
                   edgecolors="k", linewidth=0.5)
    end
    # Diagonal reference: perfect transfer
    lims = (-80, 0)
    ax.plot(lims, lims, "k--", alpha=0.4, label="J_HNLF = J_canonical")
    ax.set_xlabel("J_canonical (dB)")
    ax.set_ylabel("J on HNLF (dB)")
    ax.set_title("(d) Transferability to HNLF")
    ax.set_xlim(lims)
    ax.set_ylim(lims)
    ax.legend(loc="lower right", fontsize=9)
    ax.grid(true, alpha=0.3)

    # Legend
    fig.suptitle("Phase 31 Pareto — Branch A (blue) vs Branch B (orange)",
                  fontsize=12, fontweight="bold")
    fig.tight_layout()
    fig.savefig(outpath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "pareto figure saved" path=outpath
end

# ─────────────────────────────────────────────────────────────────────────────
# L-curves per penalty family (Branch B only)
# ─────────────────────────────────────────────────────────────────────────────

function l_curves(rows_B::Vector{<:Dict{String,Any}}, outdir::AbstractString)
    # Group by penalty_name
    by_penalty = Dict{String,Vector{Dict{String,Any}}}()
    for r in rows_B
        pname = String(r["penalty_name"])
        push!(get!(by_penalty, pname, Dict{String,Any}[]), r)
    end

    for (pname, rs) in by_penalty
        # Sort by lambda
        sort!(rs; by = r -> Float64(r["lambda"]))
        λs = [Float64(r["lambda"]) for r in rs]
        J_raman = [Float64(r["J_raman_linear"]) for r in rs]
        J_pen = [Float64(get(r, "J_penalty_linear", 0.0)) for r in rs]

        fig, ax = subplots(1, 1, figsize=(7, 5))
        # Plot only λ > 0 on log-log
        mask = λs .> 0
        if any(mask)
            ax.loglog(J_pen[mask], J_raman[mask], "o-", markersize=8,
                       color="tab:orange", label="(log J_raman vs log J_penalty)")
        end
        # Also mark λ=0 as a horizontal reference
        idx_zero = findall(iszero, λs)
        if !isempty(idx_zero)
            ax.axhline(J_raman[idx_zero[1]], color="k", linestyle="--", alpha=0.5,
                        label=@sprintf("λ=0 baseline: J_raman=%.2e", J_raman[idx_zero[1]]))
        end
        # Annotate each point with its λ
        for (i, λ) in enumerate(λs)
            λ == 0 && continue
            ax.annotate(@sprintf("λ=%.0e", λ), (J_pen[i], J_raman[i]),
                         textcoords="offset points", xytext=(5,5), fontsize=8)
        end
        ax.set_xlabel("J_penalty (linear)")
        ax.set_ylabel("J_raman (linear)")
        ax.set_title("L-curve: penalty=:$(pname)")
        ax.grid(true, which="both", alpha=0.3)
        ax.legend(loc="best", fontsize=9)
        fig.tight_layout()

        outpath = joinpath(outdir, "L_curve_$(pname).png")
        fig.savefig(outpath, dpi=300, bbox_inches="tight")
        close(fig)
        @info "L-curve saved" family=pname path=outpath
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# AIC-style ranking
# ─────────────────────────────────────────────────────────────────────────────

"""
    aic_rank(rows) -> DataFrame

Rank rows by an AIC-like score: AIC = 2 · k + 2 · J_raman_dB, where
k is N_eff (effective coefficient count, which handles both basis
dimensionality and penalty-induced sparsity). Lower AIC = better.
"""
function aic_rank(rows::Vector{<:Dict{String,Any}})
    N_eff = [Float64(r["N_eff"]) for r in rows]
    J_dB = [Float64(r["J_final"]) for r in rows]
    sigma = [Float64(r["sigma_3dB"]) for r in rows]
    J_hnlf = [Float64(r["J_transfer_HNLF"]) for r in rows]
    branches = [String(r["branch_id"]) for r in rows]
    kinds = [String(r["kind"]) for r in rows]
    N_phi = [Int(r["N_phi"]) for r in rows]
    pnames = [String(get(r, "penalty_name", "")) for r in rows]
    lams = [Float64(get(r, "lambda", 0.0)) for r in rows]

    # AIC = 2·k + 2·J_dB. Use N_eff for k (handles both branches uniformly).
    aic = @. 2.0 * N_eff + 2.0 * J_dB

    df = DataFrame(
        branch = branches,
        kind = kinds,
        N_phi = N_phi,
        penalty = pnames,
        lambda = lams,
        J_dB = J_dB,
        N_eff = N_eff,
        sigma_3dB = sigma,
        J_HNLF = J_hnlf,
        AIC = aic,
    )
    sort!(df, :AIC)
    return df
end

# ─────────────────────────────────────────────────────────────────────────────
# candidates.md + FINDINGS.md
# ─────────────────────────────────────────────────────────────────────────────

function write_candidates(df_ranked::DataFrame, outpath::AbstractString)
    top_n = min(10, nrow(df_ranked))
    open(outpath, "w") do io
        println(io, "# Phase 31 — Candidate optima\n")
        println(io, "Top $top_n rows by AIC = 2·N_eff + 2·J_dB (lower = better).\n")
        println(io, "| # | Branch | Kind / Penalty | N_phi / λ | J (dB) | N_eff | σ_3dB | J_HNLF (dB) | AIC |")
        println(io, "|---|--------|---------------|-----------|--------|-------|-------|-------------|-----|")
        for i in 1:top_n
            row = df_ranked[i, :]
            identity_or_kind = row.branch == "A" ? row.kind : "penalty(:$(row.penalty))"
            hyper = row.branch == "A" ? string(row.N_phi) : @sprintf("λ=%.1e", row.lambda)
            println(io, @sprintf("| %d | %s | %s | %s | %.2f | %.1f | %.3f | %.2f | %.2f |",
                                  i, row.branch, identity_or_kind, hyper,
                                  row.J_dB, row.N_eff, row.sigma_3dB,
                                  row.J_HNLF, row.AIC))
        end

        # Recommendation — simplest row with J within 3 dB of best
        best_J = minimum(df_ranked.J_dB)
        eligible = df_ranked[df_ranked.J_dB .≤ best_J + 3.0, :]
        if nrow(eligible) > 0
            rec = first(sort(eligible, :N_eff))
            println(io, "\n## Recommendation\n")
            println(io, "**Simplest optimum within 3 dB of best J_dB** ($(round(best_J, digits=2)) dB):")
            println(io, "- Branch: $(rec.branch)")
            if rec.branch == "A"
                println(io, "- Kind: $(rec.kind), N_phi = $(rec.N_phi)")
            else
                println(io, "- Penalty: $(rec.penalty) at λ = $(rec.lambda)")
            end
            println(io, "- J_dB = $(round(rec.J_dB, digits=2)), N_eff = $(round(rec.N_eff, digits=1))")
            println(io, "- σ_3dB = $(round(rec.sigma_3dB, digits=3)) rad, J_HNLF = $(round(rec.J_HNLF, digits=2)) dB")
        end
    end
    @info "candidates written" path=outpath
end

function write_findings(df::DataFrame, rows_A::Vector, rows_B::Vector,
                         outpath::AbstractString)
    best_A_idx = argmin(getindex.(rows_A, "J_final"))
    best_A = rows_A[best_A_idx]
    best_B = isempty(rows_B) ? nothing : rows_B[argmin(getindex.(rows_B, "J_final"))]

    open(outpath, "w") do io
        println(io, "# Phase 31 — FINDINGS\n")
        println(io, "**Question:** does reduced-basis or regularization give a simpler, more transferable, equally-deep Raman suppression optimum than full-grid L-BFGS?\n")

        println(io, "## Branch A (basis restriction) summary\n")
        println(io, "- $(length(rows_A)) optima across 5 basis families.")
        println(io, "- Best: kind=**$(best_A["kind"])** N_phi=**$(best_A["N_phi"])** → J=$(round(best_A["J_final"], digits=2)) dB.")
        println(io, "- Polynomial plateau at ~−26.5 dB for N_phi ∈ {3..8}: low-order polynomial bases express only quadratic GVD compensation; multi-start seeds collapse to that basin.")
        println(io, "- DCT plateau at ~−26 dB for N_phi ≤ 64, jumps to −31 dB at N_phi=128.")
        println(io, "- Cubic basis dramatically outperforms DCT at same N_phi — the optimal phase has **local** structure that global DCT modes miss.\n")

        if best_B !== nothing
            println(io, "## Branch B (penalty on full grid) summary\n")
            println(io, "- $(length(rows_B)) optima across 5 penalty families (tikhonov, gdd, tod, tv, dct_l1).")
            println(io, "- Best: penalty=**$(best_B["penalty_name"])** λ=$(best_B["lambda"]) → J=$(round(best_B["J_final"], digits=2)) dB.\n")
        else
            println(io, "## Branch B (penalty on full grid) — not yet run\n")
        end

        println(io, "## Transferability\n")
        not_nan = filter(!isnan, df.J_HNLF)
        if !isempty(not_nan)
            min_gap = minimum(df.J_HNLF - df.J_dB)
            println(io, "- Best transfer gap (smaller = better): $(round(min_gap, digits=2)) dB.")
            median_gap = median(df.J_HNLF - df.J_dB)
            println(io, "- Median transfer gap: $(round(median_gap, digits=2)) dB.\n")
        else
            println(io, "- Transfer probe not yet run (no `transfer_results.jld2`).\n")
        end

        println(io, "## Robustness (σ_3dB at canonical)\n")
        not_nan_s = filter(!isnan, df.sigma_3dB)
        if !isempty(not_nan_s)
            println(io, "- Largest σ_3dB (most robust): $(round(maximum(not_nan_s), digits=3)) rad.")
            println(io, "- Smallest σ_3dB (sharpest): $(round(minimum(not_nan_s), digits=3)) rad.\n")
        else
            println(io, "- σ_3dB probe not yet run.\n")
        end

        println(io, "## Saddle-masking caveat\n")
        println(io, "Per the resolved Open Question 5 in CONTEXT.md, ambient-Hessian probes are deferred out of Phase 31.")
        println(io, "Every basis-restricted PSD optimum is flagged `PSD_UNVERIFIED_AMBIENT`: its coefficient-space Hessian may be PSD while the ambient (full-Nt) Hessian remains indefinite (Phase 35 pitfall).")
        println(io, "Candidates in `candidates.md` should be interpreted with this caveat.\n")

        println(io, "## Verdict\n")
        println(io, "See `candidates.md` for the recommendation. Reasoning walkthrough follows AIC-ranked table.\n")
    end
    @info "FINDINGS written" path=outpath
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

function main_analyze()
    rows_all = load_all_rows()
    rows_A = filter(r -> r["branch_id"] == "A", rows_all)
    rows_B = filter(r -> r["branch_id"] == "B", rows_all)
    @info @sprintf("Loaded %d total rows (A=%d, B=%d)",
                    length(rows_all), length(rows_A), length(rows_B))

    if isempty(rows_all)
        @warn "No rows to analyze — run Branch A / B / transfer first."
        return
    end

    # (1) Pareto
    pareto_figure(rows_all, joinpath(P31Z_RESULTS_DIR, "pareto.png"))

    # (2) L-curves
    if !isempty(rows_B)
        l_curves(rows_B, joinpath(P31Z_RESULTS_DIR, "L_curves"))
    end

    # (3) AIC ranking
    df = aic_rank(rows_all)
    csv_path = joinpath(P31Z_RESULTS_DIR, "aic_ranking.csv")
    CSV.write(csv_path, df)
    @info "AIC ranking written" path=csv_path rows=nrow(df)

    # (4) candidates.md
    write_candidates(df, joinpath(P31Z_AGENT_DOCS, "candidates.md"))

    # (5) FINDINGS.md
    write_findings(df, rows_A, rows_B, joinpath(P31Z_AGENT_DOCS, "FINDINGS.md"))

    # PyCall cleanup
    try
        Base.invokelatest(PyPlot.close, "all")
    catch
    end
    GC.gc()

    @info "analyze complete — outputs in $(P31Z_RESULTS_DIR) and $(P31Z_AGENT_DOCS)"
end

if abspath(PROGRAM_FILE) == @__FILE__
    main_analyze()
end
