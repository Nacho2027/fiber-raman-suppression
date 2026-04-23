"""
Session E — Pareto analysis + candidate handoff

Reads the JLD2 files produced by `scripts/research/sweep_simple/sweep_simple_run.jl`, computes the
Pareto front on (J_dB, N_eff), and emits:

  - results/raman/phase_sweep_simple/pareto.png
  - results/raman/phase_sweep_simple/sweep1_Nphi_curve.png
  - results/raman/phase_sweep_simple/candidates.md

The candidates.md file is the handoff artifact for Session D.

Usage
=====
  julia --project=. scripts/research/sweep_simple/sweep_simple_analyze.jl
"""

ENV["MPLBACKEND"] = "Agg"

using JLD2
using Printf
using Statistics
using Logging
using PyPlot
using Dates

const LR_RESULTS_DIR = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase_sweep_simple")

# ─────────────────────────────────────────────────────────────────────────────
# Pareto utilities
# ─────────────────────────────────────────────────────────────────────────────

"""
    pareto_front(points) -> Vector{Int}

Returns indices of non-dominated points. Each point is a 2-tuple (x, y) where
both lower x and lower y are better (minimization on both axes).
"""
function pareto_front(points::Vector{<:NTuple{2,<:Real}})
    n = length(points)
    dominated = falses(n)
    for i in 1:n
        xi, yi = points[i]
        for j in 1:n
            i == j && continue
            xj, yj = points[j]
            if xj ≤ xi && yj ≤ yi && (xj < xi || yj < yi)
                dominated[i] = true
                break
            end
        end
    end
    return findall(.!dominated)
end

# ─────────────────────────────────────────────────────────────────────────────
# Sweep 1 plot
# ─────────────────────────────────────────────────────────────────────────────

function plot_sweep1()
    path = joinpath(LR_RESULTS_DIR, "sweep1_Nphi.jld2")
    isfile(path) || (@warn "Sweep 1 file missing"; return nothing)
    data = JLD2.load(path)
    results = data["results"]
    # Sort by N_phi ascending
    sort!(results, by = r -> r["N_phi"])
    N_phis = [r["N_phi"] for r in results]
    J_dBs  = [r["J_final"] for r in results]
    iters  = [r["iterations"] for r in results]

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.semilogx(N_phis, J_dBs, "o-", lw=2, ms=9, color="#1f77b4")
    for (xi, yi, it) in zip(N_phis, J_dBs, iters)
        ax.annotate(@sprintf("%d it", it), (xi, yi),
                    textcoords="offset points", xytext=(6, 6), fontsize=8)
    end
    ax.set_xlabel("N_φ (optimization dim)", fontsize=12)
    ax.set_ylabel("J  (dB, Raman-band fractional energy)", fontsize=12)
    ax.set_title("Sweep 1 — suppression vs phase resolution", fontsize=13)
    ax.grid(true, which="both", alpha=0.3)
    fig.tight_layout()
    out = joinpath(LR_RESULTS_DIR, "sweep1_Nphi_curve.png")
    fig.savefig(out, dpi=300)
    plt.close(fig)
    @info "wrote $out"
    return results
end

# ─────────────────────────────────────────────────────────────────────────────
# Sweep 2: Pareto + candidate list
# ─────────────────────────────────────────────────────────────────────────────

function analyze_sweep2()
    path = joinpath(LR_RESULTS_DIR, "sweep2_LP_fiber.jld2")
    isfile(path) || (@warn "Sweep 2 file missing"; return nothing)
    data = JLD2.load(path)
    results_all = data["results"]
    # Drop error rows
    results = filter(r -> !haskey(r, "error"), results_all)
    @info "Sweep 2: $(length(results)) successful rows (of $(length(results_all)))"

    # Helper: config dicts may use symbol or string keys
    _cg(cfg, k) = haskey(cfg, Symbol(k)) ? cfg[Symbol(k)] : get(cfg, k, missing)

    # Group by (fiber, L, P) to find best J per operating point
    best_J_by_config = Dict{Tuple{String,Float64,Float64}, Float64}()
    for r in results
        cfg = r["config"]
        key = (String(_cg(cfg, "fiber_preset")), Float64(_cg(cfg, "L_fiber")), Float64(_cg(cfg, "P_cont")))
        if !haskey(best_J_by_config, key) || r["J_final"] < best_J_by_config[key]
            best_J_by_config[key] = r["J_final"]
        end
    end

    points = [(Float64(r["J_final"]), Float64(r["N_eff"])) for r in results]
    nd_idx = pareto_front(points)
    @info "Pareto front: $(length(nd_idx)) non-dominated points"

    # --- Figure: Pareto scatter ---
    fibers = unique(String(_cg(r["config"], "fiber_preset")) for r in results)
    colormap = Dict(f => c for (f, c) in zip(fibers, ["#1f77b4", "#d62728", "#2ca02c", "#9467bd"]))

    fig, ax = plt.subplots(figsize=(8, 6))
    for r in results
        f = String(_cg(r["config"], "fiber_preset"))
        N_phi = r["N_phi"]
        m = N_phi == 16 ? "o" : "s"
        ax.scatter(r["J_final"], r["N_eff"], s=60, marker=m,
                   edgecolor="black", linewidth=0.5,
                   color=colormap[f], alpha=0.7)
    end
    # Pareto line
    pts_nd = sort([(results[i]["J_final"], results[i]["N_eff"]) for i in nd_idx])
    xs = [p[1] for p in pts_nd]; ys = [p[2] for p in pts_nd]
    ax.plot(xs, ys, "k--", lw=1.8, alpha=0.8, label="Pareto front")

    # Legend synthesis
    for (f, c) in pairs(colormap)
        ax.scatter([], [], color=c, label=f, edgecolor="black", linewidth=0.5)
    end
    ax.scatter([], [], marker="o", color="gray", label="N_φ = 16", edgecolor="black")
    ax.scatter([], [], marker="s", color="gray", label="N_φ = 64", edgecolor="black")
    ax.legend(loc="upper right", fontsize=9)
    ax.set_xlabel("J (dB) — suppression depth (lower = better)")
    ax.set_ylabel("N_eff — effective DCT bandwidth (lower = simpler)")
    ax.set_title("Sweep 2 — Pareto: suppression depth vs phase simplicity")
    ax.grid(true, alpha=0.3)
    fig.tight_layout()
    out = joinpath(LR_RESULTS_DIR, "pareto.png")
    fig.savefig(out, dpi=300)
    plt.close(fig)
    @info "wrote $out"

    return results, nd_idx
end

# ─────────────────────────────────────────────────────────────────────────────
# Candidate selection for Session D handoff
# ─────────────────────────────────────────────────────────────────────────────

"""
Select simple-profile candidates: Pareto-optimal points with J within 3 dB of
the best J at each (fiber, L, P) operating point. Ranks them by N_eff
(simpler first).
"""
function select_candidates(results, nd_idx)
    _cg(cfg, k) = haskey(cfg, Symbol(k)) ? cfg[Symbol(k)] : get(cfg, k, missing)

    # Best J per (fiber, L, P)
    best_J = Dict{Tuple{String,Float64,Float64}, Float64}()
    for r in results
        cfg = r["config"]
        key = (String(_cg(cfg, "fiber_preset")), Float64(_cg(cfg, "L_fiber")), Float64(_cg(cfg, "P_cont")))
        if !haskey(best_J, key) || r["J_final"] < best_J[key]
            best_J[key] = r["J_final"]
        end
    end

    candidates = []
    for i in nd_idx
        r = results[i]
        cfg = r["config"]
        key = (String(_cg(cfg, "fiber_preset")), Float64(_cg(cfg, "L_fiber")), Float64(_cg(cfg, "P_cont")))
        J_best = best_J[key]
        Δ = r["J_final"] - J_best
        if Δ ≤ 3.0     # within 3 dB of best at that operating point
            push!(candidates, (r, Δ))
        end
    end
    # Rank by N_eff (simplicity), tiebreak by J
    sort!(candidates, by = x -> (x[1]["N_eff"], x[1]["J_final"]))
    return candidates
end

function write_handoff(candidates)
    out_md = joinpath(LR_RESULTS_DIR, "candidates.md")
    handoff_note = joinpath(@__DIR__, "..", "..", "..", ".planning", "notes", "sweep-candidate-handoff.md")

    lines = String[]
    push!(lines, "# Session E — Simple-Profile Candidate Handoff")
    push!(lines, "")
    push!(lines, "**Generated:** $(now())")
    push!(lines, "**Source:** Sweep 2 results, low-resolution phase parameterization")
    push!(lines, "")
    push!(lines, "Each candidate is a non-dominated point on (J_dB, N_eff) whose J is within")
    push!(lines, "3 dB of the best J achieved at its (fiber, L, P) operating point. Sorted by")
    push!(lines, "N_eff (simpler first).")
    push!(lines, "")
    push!(lines, "| # | Fiber | L (m) | P (W) | N_φ | J (dB) | ΔJ (dB) | N_eff | TV | curv. |")
    push!(lines, "|---|-------|-------|-------|-----|--------|---------|-------|----|-------|")
    for (idx, (r, Δ)) in enumerate(candidates)
        cfg = r["config"]
        _cg(k) = haskey(cfg, Symbol(k)) ? cfg[Symbol(k)] : get(cfg, k, missing)
        fiber = String(_cg("fiber_preset"))
        L = Float64(_cg("L_fiber")); P = Float64(_cg("P_cont"))
        push!(lines, @sprintf("| %d | %s | %.2f | %.3f | %d | %.2f | %.2f | %.2f | %.2f | %.2e |",
                               idx, fiber, L, P, r["N_phi"], r["J_final"], Δ,
                               r["N_eff"], r["TV"], r["curvature"]))
    end
    push!(lines, "")
    push!(lines, "## Handoff notes")
    push!(lines, "")
    push!(lines, "- φ_opt profiles are stored in `results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2` as")
    push!(lines, "  `phi_opt` arrays (length Nt=$(2^14)). Use `JLD2.load(...)` and filter by `config`.")
    push!(lines, "- Simplicity metrics (`N_eff`, `TV`, `curvature`) were computed on the pulse bandwidth")
    push!(lines, "  mask; see `scripts/research/sweep_simple/sweep_simple_param.jl` for definitions.")
    push!(lines, "- Recommended Session D stability-test protocol: perturb φ by σ·n, n ~ N(0, I), σ in")
    push!(lines, "  {0.01, 0.05, 0.1, 0.2} rad; report mean and max ΔJ. 10 trials per σ.")
    push!(lines, "- For comparison, Session D should also test the corresponding full-resolution optima")
    push!(lines, "  (Nt-dim phase) at the same operating points so the robustness gap can be quantified.")
    push!(lines, "")

    open(out_md, "w") do io
        foreach(l -> println(io, l), lines)
    end
    @info "wrote $out_md"
    cp(out_md, handoff_note; force=true)
    @info "mirrored to $handoff_note"
    return out_md
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

function main()
    @info "Session E analysis — Pareto + handoff"
    plot_sweep1()
    s2 = analyze_sweep2()
    if s2 === nothing
        @warn "No Sweep 2 data; skipping candidate selection."
        return
    end
    results, nd_idx = s2
    candidates = select_candidates(results, nd_idx)
    @info "Selected $(length(candidates)) simple-profile candidates for Session D handoff"
    write_handoff(candidates)
    @info "Session E analysis complete."
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
