# ═══════════════════════════════════════════════════════════════════════════════
# Phase 17 Plan 01 — Simple Phase Profile Stability Study — Synthesis
# ═══════════════════════════════════════════════════════════════════════════════
#
#   julia --project=. scripts/simple_profile_synthesis.jl
#
# Consumes (from results/raman/phase17/):
#   baseline.jld2, perturbation.jld2, transferability.jld2, simplicity.jld2
#
# Emits:
#   results/images/phase17/phase17_01_perturbation_curve.png
#   results/images/phase17/phase17_02_transferability_table.png
#   results/images/phase17/phase17_03_simplicity_vs_suppression.png
#   results/images/phase17/phase17_04_synthesis.png
#   results/raman/phase17/SUMMARY.md
#   .planning/notes/simple-profile-handoff-to-E.md
#
# Each figure is PNG at 300 DPI; SUMMARY.md follows the Phase 13 template.
# ═══════════════════════════════════════════════════════════════════════════════

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using Statistics
using FFTW
using JLD2
using Dates
using PyPlot

# ─────────────────────────────────────────────────────────────────────────────
# Constants (SPS_ = Simple Profile Synthesis)
# ─────────────────────────────────────────────────────────────────────────────

const SPS_VERSION = "1.0.0"
const SPS_IMAGE_DIR   = joinpath(@__DIR__, "..", "results", "images", "phase17")
const SPS_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase17")
const SPS_NOTES_DIR   = joinpath(@__DIR__, "..", ".planning", "notes")
const SPS_DPI = 300

# Verdict thresholds from D-simple-decisions §8.
const SPS_SIGMA_FLAT_MIN    = 0.2
const SPS_SIGMA_SHARP_MAX   = 0.05
const SPS_TRANSFER_DB_TOL   = 3.0
const SPS_TRANSFER_OK_COUNT = 3     # of 5 non-baseline SMF-28 transfer points

# ─────────────────────────────────────────────────────────────────────────────
# Loading helpers
# ─────────────────────────────────────────────────────────────────────────────

function _safe_load(path::AbstractString)
    isfile(path) || return nothing
    try
        return JLD2.load(path)
    catch e
        @warn "Could not load JLD2" path=path exception=e
        return nothing
    end
end

function _load_all()
    return (
        baseline = _safe_load(joinpath(SPS_RESULTS_DIR, "baseline.jld2")),
        pert     = _safe_load(joinpath(SPS_RESULTS_DIR, "perturbation.jld2")),
        transfer = _safe_load(joinpath(SPS_RESULTS_DIR, "transferability.jld2")),
        simpl    = _safe_load(joinpath(SPS_RESULTS_DIR, "simplicity.jld2")),
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 1 — Perturbation curve
# ─────────────────────────────────────────────────────────────────────────────

function fig_perturbation(pert::Dict, J_baseline_dB::Real)
    sigmas  = pert["sigmas"]::Vector{Float64}
    task_σ  = pert["task_sigma"]::Vector{Float64}
    task_ΔJ = pert["task_delta_J_dB"]::Vector{Float64}
    med     = pert["median_delta_J_dB"]::Vector{Float64}
    q25     = pert["q25_delta_J_dB"]::Vector{Float64}
    q75     = pert["q75_delta_J_dB"]::Vector{Float64}
    σ_3dB   = pert["sigma_3dB_interp"]::Float64
    N       = pert["n_samples"]::Int

    fig, ax = subplots(figsize=(8, 5))
    ax.scatter(task_σ, task_ΔJ; alpha=0.3, s=22, color="#4477AA", label=@sprintf("samples (N=%d/σ)", N))
    ax.plot(sigmas, med; color="#CC3311", linewidth=2.0, marker="o", label="median")
    ax.fill_between(sigmas, q25, q75; color="#CC3311", alpha=0.2, label="25–75 percentile")
    ax.axhline(3.0; color="k", linestyle=":", linewidth=1.0, alpha=0.7)
    if isfinite(σ_3dB)
        ax.axvline(σ_3dB; color="#228833", linestyle="--", linewidth=1.4,
            label=@sprintf("σ_3dB = %.3f rad", σ_3dB))
    end
    ax.set_xscale("log")
    ax.set_xlabel("Phase noise amplitude σ (rad)")
    ax.set_ylabel("ΔJ = J_perturbed − J_baseline (dB)")
    ax.set_title(@sprintf("Baseline optimum: Raman suppression vs phase noise\nJ_baseline = %.2f dB, N=%d samples per σ",
        J_baseline_dB, N))
    ax.grid(true, which="both", alpha=0.3)
    ax.legend(loc="upper left")

    out = joinpath(SPS_IMAGE_DIR, "phase17_01_perturbation_curve.png")
    tight_layout()
    savefig(out; dpi=SPS_DPI)
    close(fig)
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 2 — Transferability (heatmap + bar)
# ─────────────────────────────────────────────────────────────────────────────

function fig_transferability(transfer::Dict, J_baseline_dB::Real)
    fiber = transfer["fiber_name_arr"]::Vector{String}
    L     = transfer["L_m_arr"]::Vector{Float64}
    P     = transfer["P_cont_W_arr"]::Vector{Float64}
    Jev   = transfer["J_eval_dB_arr"]::Vector{Float64}
    Jwm   = transfer["J_warm_dB_arr"]::Vector{Float64}
    axis  = transfer["axis_arr"]::Vector{String}
    isb   = transfer["is_baseline_arr"]::Vector{Bool}
    n     = length(fiber)

    fig = figure(figsize=(14, 5.5))

    # ── Left: heatmap of SMF-28 (L × P) — sparse grid, most cells NaN ──
    ax1 = fig.add_subplot(1, 2, 1)
    Ls_axis = [0.25, 0.5, 1.0, 2.0, 5.0]
    Ps_axis = [0.02, 0.05, 0.1, 0.2]
    H = fill(NaN, length(Ps_axis), length(Ls_axis))
    for i in 1:n
        fiber[i] == "SMF-28" || continue
        li = findfirst(x -> isapprox(x, L[i]; atol=1e-6), Ls_axis)
        pi_ = findfirst(x -> isapprox(x, P[i]; atol=1e-6), Ps_axis)
        isnothing(li) && continue
        isnothing(pi_) && continue
        H[pi_, li] = Jev[i]
    end
    # Mask NaN
    im = ax1.imshow(H; aspect="auto", cmap="RdYlGn_r",
        vmin=-80, vmax=-30, origin="lower",
        extent=[-0.5, length(Ls_axis) - 0.5, -0.5, length(Ps_axis) - 0.5])
    ax1.set_xticks(0:length(Ls_axis) - 1)
    ax1.set_xticklabels([@sprintf("%.2f", L) for L in Ls_axis])
    ax1.set_yticks(0:length(Ps_axis) - 1)
    ax1.set_yticklabels([@sprintf("%.2f", P) for P in Ps_axis])
    ax1.set_xlabel("L (m)")
    ax1.set_ylabel("P_cont (W)")
    ax1.set_title("J_eval_dB — baseline φ_opt applied to SMF-28 grid")
    for pi_ in 1:length(Ps_axis), li in 1:length(Ls_axis)
        v = H[pi_, li]
        isnan(v) && continue
        ax1.text(li - 1, pi_ - 1, @sprintf("%.1f", v);
            ha="center", va="center",
            color=(v < -50 ? "white" : "black"), fontsize=9)
    end
    cbar = fig.colorbar(im, ax=ax1)
    cbar.set_label("J (dB)")

    # ── Right: grouped bar chart of J_eval vs J_warm per target ──
    ax2 = fig.add_subplot(1, 2, 2)
    labels = [@sprintf("%s\nL=%.2g P=%.3g", fiber[i], L[i], P[i]) for i in 1:n]
    x = collect(1:n)
    w = 0.38
    bars1 = ax2.bar(x .- w/2, Jev; width=w, label="J_eval (warm transfer)", color="#4477AA")
    bars2 = ax2.bar(x .+ w/2, Jwm; width=w, label="J_warm (reopt, 40 iter)", color="#CC6677")
    # Highlight baseline
    for i in 1:n
        if isb[i]
            bars1[i].set_edgecolor("black"); bars1[i].set_linewidth(1.8)
            bars2[i].set_edgecolor("black"); bars2[i].set_linewidth(1.8)
        end
    end
    ax2.axhline(J_baseline_dB; color="k", linestyle="--", linewidth=1.2,
        label=@sprintf("J_baseline = %.2f dB", J_baseline_dB))
    ax2.set_xticks(x)
    ax2.set_xticklabels(labels; rotation=45, ha="right", fontsize=8)
    ax2.set_ylabel("J (dB)")
    ax2.set_title("Transferability — baseline φ_opt → 11 targets")
    ax2.legend(loc="best")
    ax2.grid(true, axis="y", alpha=0.3)

    tight_layout()
    out = joinpath(SPS_IMAGE_DIR, "phase17_02_transferability_table.png")
    savefig(out; dpi=SPS_DPI)
    close(fig)
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 3 — Simplicity vs suppression
# ─────────────────────────────────────────────────────────────────────────────

function fig_simplicity(simpl::Dict)
    names  = simpl["names"]::Vector{String}
    Jarr   = simpl["J_after_dB"]::Vector{Float64}
    TVarr  = simpl["TV_arr"]::Vector{Float64}
    Earr   = simpl["entropy_arr"]::Vector{Float64}
    Starr  = simpl["stationary_arr"]
    winner = simpl["winner"]::String
    r_tv   = simpl["r_TV"]; r_ent = simpl["r_entropy"]; r_st = simpl["r_stationary"]

    fig, axs = subplots(1, 3; figsize=(14, 4.5))
    baseline_idx = 1   # convention in metrics script

    function _panel(ax, yarr, label, r, is_winner)
        for i in 1:length(Jarr)
            if i == baseline_idx
                ax.scatter(Jarr[i], yarr[i]; s=140, color="#CC3311", edgecolor="black", linewidth=1.5, zorder=3, label="baseline")
            else
                ax.scatter(Jarr[i], yarr[i]; s=55, color="#4477AA", zorder=2)
            end
        end
        ax.set_xlabel("J_after (dB)")
        ax.set_ylabel(label)
        title = @sprintf("%s — Pearson r = %.3f", label, r)
        if is_winner
            ax.set_title(title; fontweight="bold")
        else
            ax.set_title(title)
        end
        ax.grid(true, alpha=0.3)
    end

    _panel(axs[1], TVarr, "Total variation", r_tv, winner == "TV")
    _panel(axs[2], Earr,  "Spectral entropy", r_ent, winner == "entropy")
    _panel(axs[3], Float64.(Starr), "Stationary-point count", r_st, winner == "stationary")

    fig.suptitle(@sprintf("Simplicity vs suppression — winner: %s", winner); fontweight="bold")
    tight_layout()
    out = joinpath(SPS_IMAGE_DIR, "phase17_03_simplicity_vs_suppression.png")
    savefig(out; dpi=SPS_DPI)
    close(fig)
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 4 — Synthesis (2×2)
# ─────────────────────────────────────────────────────────────────────────────

function fig_synthesis(bl, pert, transfer, simpl, verdict::AbstractString)
    fig = figure(figsize=(14, 10))

    # Top-left: baseline phi_opt
    ax_tl = fig.add_subplot(2, 2, 1)
    Nt = bl["Nt"]::Int
    fs_THz = fftshift(bl["fftfreq_THz"]::Vector{Float64})
    phi_opt = bl["phi_opt"]::Matrix{Float64}
    phi_plot = fftshift(phi_opt[:, 1])
    ax_tl.plot(fs_THz, phi_plot; color="#4477AA", linewidth=1.3, label="φ_opt (raw)")
    if !isnothing(simpl)
        phi_gf_col = simpl["phi_gf_collection"]
        if length(phi_gf_col) >= 1
            phi_gf = fftshift(phi_gf_col[1])
            ax_tl.plot(fs_THz, phi_gf; color="#CC3311", linewidth=1.3, alpha=0.85, label="φ_opt (gauge-fixed)")
        end
    end
    ax_tl.set_xlabel("Frequency offset (THz)")
    ax_tl.set_ylabel("Phase (rad)")
    ax_tl.set_title(@sprintf("Baseline φ_opt — J = %.2f dB", bl["J_final_dB"]))
    ax_tl.legend()
    ax_tl.grid(true, alpha=0.3)

    # Top-right: perturbation curve (inline)
    ax_tr = fig.add_subplot(2, 2, 2)
    if !isnothing(pert)
        sigmas = pert["sigmas"]; med = pert["median_delta_J_dB"]
        q25 = pert["q25_delta_J_dB"]; q75 = pert["q75_delta_J_dB"]
        σ_3dB = pert["sigma_3dB_interp"]
        ax_tr.plot(sigmas, med; color="#CC3311", marker="o", linewidth=2.0, label="median ΔJ")
        ax_tr.fill_between(sigmas, q25, q75; color="#CC3311", alpha=0.2)
        ax_tr.axhline(3.0; color="k", linestyle=":", alpha=0.7)
        if isfinite(σ_3dB)
            ax_tr.axvline(σ_3dB; color="#228833", linestyle="--",
                label=@sprintf("σ_3dB = %.3f rad", σ_3dB))
        end
        ax_tr.set_xscale("log")
        ax_tr.set_xlabel("σ (rad)"); ax_tr.set_ylabel("ΔJ (dB)")
        ax_tr.set_title("Basin-width probe")
        ax_tr.legend()
        ax_tr.grid(true, which="both", alpha=0.3)
    else
        ax_tr.text(0.5, 0.5, "perturbation.jld2 missing"; transform=ax_tr.transAxes, ha="center")
    end

    # Bottom-left: transferability warm vs eval
    ax_bl = fig.add_subplot(2, 2, 3)
    if !isnothing(transfer)
        Jev = transfer["J_eval_dB_arr"]; Jwm = transfer["J_warm_dB_arr"]
        fiber = transfer["fiber_name_arr"]; L = transfer["L_m_arr"]; P = transfer["P_cont_W_arr"]
        n = length(Jev)
        x = 1:n
        labels = [@sprintf("%s\nL=%.2g/P=%.3g", fiber[i], L[i], P[i]) for i in 1:n]
        w = 0.38
        ax_bl.bar(collect(x) .- w/2, Jev; width=w, label="eval-only", color="#4477AA")
        ax_bl.bar(collect(x) .+ w/2, Jwm; width=w, label="warm reopt", color="#CC6677")
        ax_bl.axhline(bl["J_final_dB"]; color="k", linestyle="--", alpha=0.7, label="baseline")
        ax_bl.set_xticks(x); ax_bl.set_xticklabels(labels; rotation=45, ha="right", fontsize=7)
        ax_bl.set_ylabel("J (dB)"); ax_bl.set_title("Transferability across 11 targets")
        ax_bl.legend(fontsize=8); ax_bl.grid(true, axis="y", alpha=0.3)
    else
        ax_bl.text(0.5, 0.5, "transferability.jld2 missing"; transform=ax_bl.transAxes, ha="center")
    end

    # Bottom-right: simplicity winner
    ax_br = fig.add_subplot(2, 2, 4)
    if !isnothing(simpl) && simpl["n_optima"] > 1
        winner = simpl["winner"]::String
        Jarr = simpl["J_after_dB"]
        yarr = if winner == "TV"
            simpl["TV_arr"]
        elseif winner == "entropy"
            simpl["entropy_arr"]
        elseif winner == "stationary"
            Float64.(simpl["stationary_arr"])
        else
            simpl["TV_arr"]
        end
        r = simpl["best_r"]
        for i in 1:length(Jarr)
            if i == 1
                ax_br.scatter(Jarr[i], yarr[i]; s=140, color="#CC3311", edgecolor="black", linewidth=1.5, label="baseline")
            else
                ax_br.scatter(Jarr[i], yarr[i]; s=55, color="#4477AA")
            end
        end
        ax_br.set_xlabel("J_after (dB)")
        ax_br.set_ylabel(winner)
        ax_br.set_title(@sprintf("Winning simplicity metric: %s  (r=%.2f)", winner, r))
        ax_br.grid(true, alpha=0.3); ax_br.legend()
    else
        ax_br.text(0.5, 0.5, "simplicity.jld2 missing or inconclusive"; transform=ax_br.transAxes, ha="center")
    end

    fig.suptitle(@sprintf("Is the L=0.5m P=0.05W optimum special?   VERDICT: %s", verdict);
        fontsize=15, fontweight="bold")
    tight_layout(rect=[0, 0, 1, 0.96])
    out = joinpath(SPS_IMAGE_DIR, "phase17_04_synthesis.png")
    savefig(out; dpi=SPS_DPI)
    close(fig)
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Verdict logic (decisions §8)
# ─────────────────────────────────────────────────────────────────────────────

function decide_verdict(pert, transfer, simpl)
    # σ_3dB thresholds
    σ_3dB = isnothing(pert) ? NaN : pert["sigma_3dB_interp"]
    flat_σ  = isfinite(σ_3dB) && σ_3dB >= SPS_SIGMA_FLAT_MIN
    sharp_σ = isfinite(σ_3dB) && σ_3dB <= SPS_SIGMA_SHARP_MAX

    # Transferability: count non-baseline SMF-28 points where eval-only stays
    # within SPS_TRANSFER_DB_TOL dB of the warm reopt (proxy for "close to
    # cold-start J", the actual cold-start requirement in decisions §8).
    transfer_ok = false
    transfer_ok_count = 0
    transfer_total = 0
    if !isnothing(transfer)
        fiber = transfer["fiber_name_arr"]
        isb   = transfer["is_baseline_arr"]
        Jev   = transfer["J_eval_dB_arr"]
        Jwm   = transfer["J_warm_dB_arr"]
        for i in 1:length(Jev)
            fiber[i] == "SMF-28" || continue
            isb[i] && continue
            transfer_total += 1
            # warm is better/more negative; eval worse. Gap = Jev - Jwm (dB).
            gap = Jev[i] - Jwm[i]
            if gap <= SPS_TRANSFER_DB_TOL
                transfer_ok_count += 1
            end
        end
        transfer_ok = transfer_ok_count >= SPS_TRANSFER_OK_COUNT
    end

    # Simplicity: baseline should be the simplest (lowest winning metric value)
    simplicity_ok = false
    if !isnothing(simpl) && simpl["n_optima"] > 1
        winner = simpl["winner"]::String
        yarr = if winner == "TV"
            simpl["TV_arr"]
        elseif winner == "entropy"
            simpl["entropy_arr"]
        elseif winner == "stationary"
            Float64.(simpl["stationary_arr"])
        else
            Float64[]
        end
        if !isempty(yarr)
            simplicity_ok = yarr[1] == minimum(yarr)
        end
    end

    verdict = if flat_σ && transfer_ok && simplicity_ok
        "FLAT_ROBUST"
    elseif sharp_σ || !simplicity_ok
        "SHARP_LUCKY"
    else
        "INCONCLUSIVE"
    end

    return (verdict = verdict,
            sigma_3dB = σ_3dB,
            flat_σ = flat_σ, sharp_σ = sharp_σ,
            transfer_ok = transfer_ok,
            transfer_ok_count = transfer_ok_count,
            transfer_total = transfer_total,
            simplicity_ok = simplicity_ok)
end

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY.md
# ─────────────────────────────────────────────────────────────────────────────

function write_summary(bl, pert, transfer, simpl, verdict_info, fig_paths)
    out = joinpath(SPS_RESULTS_DIR, "SUMMARY.md")
    open(out, "w") do io
        println(io, "---")
        println(io, "phase: 16-simple-phase-profile-stability-study")
        println(io, "plan: \"01\"")
        println(io, "created: ", Dates.today())
        println(io, "verdict: ", verdict_info.verdict)
        println(io, "---")
        println(io)
        println(io, "# Phase 17 — Simple Phase Profile Stability Study")
        println(io)
        println(io, "## Headline Verdict")
        println(io)
        @printf(io, "**%s** — σ_3dB = %s rad, transferability %d/%d, simplicity baseline-simplest = %s.\n\n",
            verdict_info.verdict,
            isfinite(verdict_info.sigma_3dB) ? @sprintf("%.3f", verdict_info.sigma_3dB) : "not reached",
            verdict_info.transfer_ok_count, verdict_info.transfer_total,
            verdict_info.simplicity_ok ? "YES" : "NO")
        println(io, "## What Was Built")
        println(io)
        println(io, "1. `scripts/simple_profile_driver.jl` — baseline + perturbation + transferability stages")
        println(io, "2. `scripts/simple_profile_metrics.jl` — gauge-fixed TV, entropy, stationary-point metrics")
        println(io, "3. `scripts/simple_profile_synthesis.jl` — figures + this SUMMARY")
        println(io)
        println(io, "## Key Numbers")
        println(io)
        if !isnothing(bl)
            @printf(io, "- Baseline: J_final = %.3f dB (expected %.1f ± 1 dB) in %.2f s over %d iter\n",
                bl["J_final_dB"], bl["J_expected_dB"], bl["wall_s"], bl["iterations"])
            @printf(io, "- Nonlinear phase Φ_NL = %.2f rad, P_peak = %.1f W\n",
                bl["Phi_NL_rad"], bl["P_peak_W"])
        end
        if !isnothing(pert)
            @printf(io, "- Perturbation: %d σ × %d samples = %d tasks in %.1f s\n",
                length(pert["sigmas"]), pert["n_samples"],
                length(pert["task_sigma"]), pert["total_wall_s"])
            @printf(io, "- σ_3dB (interp) = %s rad\n",
                isfinite(verdict_info.sigma_3dB) ? @sprintf("%.3f", verdict_info.sigma_3dB) : "not reached")
        end
        if !isnothing(transfer)
            @printf(io, "- Transferability: %d targets evaluated in %.1f s\n",
                transfer["n_targets"], transfer["total_wall_s"])
        end
        if !isnothing(simpl)
            @printf(io, "- Simplicity winner: %s (r = %.3f, N = %d optima)\n",
                simpl["winner"], simpl["best_r"], simpl["n_optima"])
        end
        println(io)
        println(io, "## Figure Index")
        println(io)
        for p in fig_paths
            println(io, "- `", relpath(p, joinpath(@__DIR__, "..")), "`")
        end
        println(io)
        println(io, "## Data Index")
        println(io)
        for name in ["baseline.jld2", "perturbation.jld2", "transferability.jld2", "simplicity.jld2"]
            p = joinpath(SPS_RESULTS_DIR, name)
            mark = isfile(p) ? "✓" : "✗"
            println(io, "- [$mark] `results/raman/phase17/$name`")
        end
        println(io)
        println(io, "## Hypothesis Summary Table")
        println(io)
        println(io, "| Criterion | Threshold | Observed | Pass? |")
        println(io, "|---|---|---|---|")
        @printf(io, "| σ_3dB ≥ %.2f rad (FLAT) | ≥ %.2f | %s | %s |\n",
            SPS_SIGMA_FLAT_MIN, SPS_SIGMA_FLAT_MIN,
            isfinite(verdict_info.sigma_3dB) ? @sprintf("%.3f", verdict_info.sigma_3dB) : "NaN",
            verdict_info.flat_σ ? "YES" : "NO")
        @printf(io, "| σ_3dB ≤ %.2f rad (SHARP) | ≤ %.2f | %s | %s |\n",
            SPS_SIGMA_SHARP_MAX, SPS_SIGMA_SHARP_MAX,
            isfinite(verdict_info.sigma_3dB) ? @sprintf("%.3f", verdict_info.sigma_3dB) : "NaN",
            verdict_info.sharp_σ ? "YES" : "NO")
        @printf(io, "| SMF-28 transfer ≥ %d/%d ≤ %.0f dB gap | ≥ %d | %d/%d | %s |\n",
            SPS_TRANSFER_OK_COUNT, verdict_info.transfer_total, SPS_TRANSFER_DB_TOL,
            SPS_TRANSFER_OK_COUNT, verdict_info.transfer_ok_count, verdict_info.transfer_total,
            verdict_info.transfer_ok ? "YES" : "NO")
        @printf(io, "| Baseline = simplest of N=%d optima | YES | %s | %s |\n",
            isnothing(simpl) ? 0 : simpl["n_optima"],
            verdict_info.simplicity_ok ? "YES" : "NO",
            verdict_info.simplicity_ok ? "YES" : "NO")
        println(io)
        println(io, "## Hand-off to Session E")
        println(io)
        println(io, "See `.planning/notes/simple-profile-handoff-to-E.md`.")
        println(io)
    end
    @info "SUMMARY.md written" path=out
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Handoff note for Session E
# ─────────────────────────────────────────────────────────────────────────────

function write_handoff(verdict_info, simpl)
    mkpath(SPS_NOTES_DIR)
    out = joinpath(SPS_NOTES_DIR, "simple-profile-handoff-to-E.md")
    v = verdict_info.verdict
    winner = isnothing(simpl) ? "unknown" : simpl["winner"]
    open(out, "w") do io
        println(io, "---")
        println(io, "from: Session D")
        println(io, "to: Session E")
        println(io, "date: ", Dates.today())
        println(io, "verdict: ", v)
        println(io, "---")
        println(io)
        println(io, "# Handoff — Simple Phase Profile Stability Study → Session E")
        println(io)
        if v == "FLAT_ROBUST"
            println(io, "## Parameter ranges where the simple-phase property is preserved")
            println(io)
            println(io, "- Fiber: SMF-28 (γ=1.1e-3 W⁻¹m⁻¹, β₂=-2.17e-26 s²/m, β₃=1.2e-40 s³/m)")
            println(io, "- Length axis: L ∈ {0.25, 0.5, 1.0, 2.0, 5.0} m  — refine by eval-only ΔJ ≤ 3 dB")
            println(io, "- Power axis: P_cont ∈ {0.02, 0.05, 0.1, 0.2} W — refine likewise")
            println(io)
            println(io, "## Recommended simplicity metric")
            println(io)
            @printf(io, "- **%s** (highest |Pearson r| vs J_after in N=%d-point Session D comparison)\n",
                winner, isnothing(simpl) ? 0 : simpl["n_optima"])
            println(io)
            println(io, "## Seed script")
            println(io)
            println(io, "Session E can adapt `scripts/simple_profile_metrics.jl` for a dense sweep.")
            println(io, "The primitives live in `scripts/phase13_primitives.jl` (READ-ONLY): `gauge_fix`,")
            println(io, "`input_band_mask`, `omega_vector`. Metric helpers in `simple_profile_metrics.jl`:")
            println(io, "`compute_total_variation`, `compute_spectral_entropy`, `compute_stationary_points`.")
        else
            println(io, "## Negative-result handoff")
            println(io)
            if v == "SHARP_LUCKY"
                println(io, "The L=0.5m P=0.05W optimum is a **sharp** minimum — small phase perturbations")
                println(io, "degrade Raman suppression rapidly. Do NOT assume other low-Φ_NL points share")
                println(io, "the apparent-simplicity property.")
            else
                println(io, "Mixed signals — treat the simple-phase hypothesis as UNPROVEN. Session E should")
                println(io, "still run its sweep but plan for a high failure rate and surface any outliers.")
            end
            println(io)
            println(io, "## Observed numbers")
            println(io)
            @printf(io, "- σ_3dB = %s rad\n",
                isfinite(verdict_info.sigma_3dB) ? @sprintf("%.3f", verdict_info.sigma_3dB) : "not reached")
            @printf(io, "- Transfer points within %.0f dB of warm reopt: %d / %d\n",
                SPS_TRANSFER_DB_TOL, verdict_info.transfer_ok_count, verdict_info.transfer_total)
            @printf(io, "- Baseline simplest of comparators: %s\n", verdict_info.simplicity_ok ? "YES" : "NO")
        end
        println(io)
        println(io, "## Artefacts")
        println(io)
        println(io, "- `results/raman/phase17/baseline.jld2` — reference optimum + grid metadata")
        println(io, "- `results/raman/phase17/perturbation.jld2` — basin-width data (100 samples)")
        println(io, "- `results/raman/phase17/transferability.jld2` — 11-target transfer study")
        println(io, "- `results/raman/phase17/simplicity.jld2` — TV / entropy / stationary metrics")
        println(io, "- `results/images/phase17/phase17_04_synthesis.png` — 1-page summary figure")
    end
    @info "Handoff note written" path=out
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

function main()
    mkpath(SPS_IMAGE_DIR)
    mkpath(SPS_RESULTS_DIR)
    mkpath(SPS_NOTES_DIR)

    data = _load_all()
    @assert !isnothing(data.baseline) "baseline.jld2 missing — run driver --stage=baseline first"
    bl = data.baseline
    J_baseline_dB = bl["J_final_dB"]::Float64

    fig_paths = String[]

    if !isnothing(data.pert)
        push!(fig_paths, fig_perturbation(data.pert, J_baseline_dB))
    else
        @warn "perturbation.jld2 missing — Figure 1 skipped"
    end

    if !isnothing(data.transfer)
        push!(fig_paths, fig_transferability(data.transfer, J_baseline_dB))
    else
        @warn "transferability.jld2 missing — Figure 2 skipped"
    end

    if !isnothing(data.simpl)
        push!(fig_paths, fig_simplicity(data.simpl))
    else
        @warn "simplicity.jld2 missing — Figure 3 skipped"
    end

    verdict_info = decide_verdict(data.pert, data.transfer, data.simpl)
    @info "Verdict decided" verdict=verdict_info.verdict σ_3dB=verdict_info.sigma_3dB

    push!(fig_paths, fig_synthesis(bl, data.pert, data.transfer, data.simpl, verdict_info.verdict))

    write_summary(bl, data.pert, data.transfer, data.simpl, verdict_info, fig_paths)
    write_handoff(verdict_info, data.simpl)

    println(repeat("═", 72))
    println(@sprintf("  VERDICT: %s", verdict_info.verdict))
    println(repeat("═", 72))
    project_root = joinpath(@__DIR__, "..")
    for p in fig_paths
        println("  ", relpath(p, project_root))
    end
    println(repeat("═", 72))
    return verdict_info
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
