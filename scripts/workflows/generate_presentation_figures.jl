"""
Build the advisor-ready presentation figures from existing run / sweep artifacts.

Collates the 6–10 plots the lab uses in group meetings and paper drafts: best-
suppression spectra, convergence overlays, heatmaps, phase decomposition. Reads
from `results/raman/` and writes into `results/images/presentation/`.

# Run
    julia --project=. scripts/generate_presentation_figures.jl

# Inputs
- Existing JLD2 payloads under `results/raman/` (per-run and sweeps).
- `scripts/lib/visualization.jl` plotting helpers.

# Outputs
- `results/images/presentation/*.png` — presentation-quality figures at 300 DPI.

# Runtime
~3–6 minutes. Pure plotting, no simulation.

# Docs
Docs: docs/guides/interpreting-plots.md
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Printf, JLD2, FFTW, LinearAlgebra

include(joinpath(@__DIR__, "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "lib", "visualization.jl"))

const OUT_DIR = joinpath("results", "images", "presentation")
mkpath(OUT_DIR)

# ─────────────────────────────────────────────────────────────────────────────
# Load all per-point data
# ─────────────────────────────────────────────────────────────────────────────

function load_all_sweep_points()
    points = []
    for (fiber_key, fiber_label) in [("smf28", "SMF-28"), ("hnlf", "HNLF")]
        dir = joinpath("results", "raman", "sweeps", fiber_key)
        isdir(dir) || continue
        for d in sort(readdir(dir))
            jld2 = joinpath(dir, d, "opt_result.jld2")
            isfile(jld2) || continue
            data = load(jld2)
            J_after = data["J_after"]
            J_dB = 10 * log10(max(J_after, 1e-30))
            push!(points, (
                fiber = fiber_label,
                fiber_key = fiber_key,
                L = data["L_m"],
                P = data["P_cont_W"],
                J_before = data["J_before"],
                J_after = J_after,
                J_before_dB = 10 * log10(max(data["J_before"], 1e-30)),
                J_after_dB = J_dB,
                delta_dB = J_dB - 10 * log10(max(data["J_before"], 1e-30)),
                converged = data["converged"],
                iterations = data["iterations"],
                Nt = data["Nt"],
                gamma = data["gamma"],
                bc_in = data["bc_input_frac"],
            ))
        end
    end
    return points
end

# Compute soliton number
function N_sol(gamma, P_cont, beta2; fwhm=185e-15, rep_rate=80.5e6)
    P_peak = 0.881374 * P_cont / (fwhm * rep_rate)
    T0 = fwhm / 1.763
    return sqrt(gamma * P_peak * T0^2 / abs(beta2))
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 1: Side-by-side heatmaps
# ─────────────────────────────────────────────────────────────────────────────

function plot_heatmaps(points)
    fig, (ax1, ax2) = subplots(1, 2, figsize=(14, 5.5))

    for (ax, fiber_key, fiber_label, beta2) in [
        (ax1, "smf28", "SMF-28", 2.6e-26),
        (ax2, "hnlf", "HNLF", 1.1e-26)]

        pts = filter(p -> p.fiber_key == fiber_key, points)
        L_vals = sort(unique([p.L for p in pts]))
        P_vals = sort(unique([p.P for p in pts]))

        J_grid = fill(NaN, length(L_vals), length(P_vals))
        conv_grid = fill(false, length(L_vals), length(P_vals))

        for p in pts
            i = findfirst(==(p.L), L_vals)
            j = findfirst(==(p.P), P_vals)
            J_grid[i, j] = p.J_after_dB
            conv_grid[i, j] = p.converged
        end

        im = ax.pcolormesh(P_vals, L_vals, J_grid, cmap="inferno",
            shading="nearest", vmin=-80, vmax=-30)

        # Annotate each cell with dB value
        for (i, L) in enumerate(L_vals), (j, P) in enumerate(P_vals)
            J_dB = J_grid[i, j]
            isnan(J_dB) && continue
            color = J_dB < -55 ? "white" : "black"
            marker = conv_grid[i, j] ? "" : " *"
            ax.text(P, L, @sprintf("%.0f%s", J_dB, marker),
                ha="center", va="center", fontsize=9, fontweight="bold", color=color)
        end

        cb = fig.colorbar(im, ax=ax, label="J_final [dB]", shrink=0.9)
        ax.set_xlabel("Average power P [W]")
        ax.set_ylabel("Fiber length L [m]")
        ax.set_title("$(fiber_label): Raman suppression [dB]", fontsize=13)

        # Add N contours
        N_vals_to_show = fiber_key == "smf28" ? [1.5, 2.0, 3.0] : [3.0, 5.0, 8.0]
        for N_target in N_vals_to_show
            P_line = range(minimum(P_vals) * 0.8, maximum(P_vals) * 1.2, length=50)
            # N is independent of L, so just check if any L has this N
            for P_check in P_vals
                N_check = N_sol(pts[1].gamma, P_check, beta2)
                if abs(N_check - N_target) / N_target < 0.3
                    ax.axvline(x=P_check, color="white", ls="--", alpha=0.4, linewidth=0.8)
                    ax.text(P_check, maximum(L_vals) * 1.02, @sprintf("N=%.1f", N_check),
                        ha="center", va="bottom", fontsize=7, color="gray")
                end
            end
        end
    end

    fig.suptitle("Raman Suppression: L × P Parameter Sweep  (* = not formally converged)",
        fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.94])

    path = joinpath(OUT_DIR, "fig1_heatmaps.png")
    savefig(path, dpi=300, bbox_inches="tight")
    @info "Saved $path"
    close(fig)
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 2: N_sol vs J scatter
# ─────────────────────────────────────────────────────────────────────────────

function plot_nsol_vs_J(points)
    fig, ax = subplots(figsize=(8, 5.5))

    betas = Dict("smf28" => 2.6e-26, "hnlf" => 1.1e-26)
    colors = Dict("SMF-28" => "#0072B2", "HNLF" => "#D55E00")
    markers = Dict("SMF-28" => "o", "HNLF" => "s")

    for fiber_label in ["SMF-28", "HNLF"]
        pts = filter(p -> p.fiber == fiber_label, points)
        beta2 = betas[pts[1].fiber_key]

        Ns = [N_sol(p.gamma, p.P, beta2) for p in pts]
        Js = [p.J_after_dB for p in pts]
        Ls = [p.L for p in pts]

        # Color by fiber length
        scatter = ax.scatter(Ns, Js, c=Ls, cmap="viridis",
            marker=markers[fiber_label], s=80, edgecolors="black", linewidth=0.5,
            label=fiber_label, vmin=0.5, vmax=5.0, zorder=3)
    end

    cb = fig.colorbar(ax.collections[1], ax=ax, label="Fiber length L [m]")
    ax.set_xlabel("Soliton number N", fontsize=12)
    ax.set_ylabel("Raman suppression J_after [dB]", fontsize=12)
    ax.set_title("Suppression vs. soliton number (color = fiber length)", fontsize=13)
    ax.legend(fontsize=11)
    ax.grid(true, alpha=0.3)
    ax.set_xlim(0.5, 7)
    ax.set_ylim(-85, -30)

    path = joinpath(OUT_DIR, "fig2_nsol_vs_J.png")
    savefig(path, dpi=300, bbox_inches="tight")
    @info "Saved $path"
    close(fig)
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 3: Before/after comparison (old linear vs new log cost)
# ─────────────────────────────────────────────────────────────────────────────

function plot_before_after()
    # Hardcoded comparison data from the two sweep runs
    configs = [
        "L=0.5m\nP=0.05W", "L=0.5m\nP=0.10W", "L=0.5m\nP=0.20W",
        "L=1m\nP=0.05W", "L=1m\nP=0.10W", "L=1m\nP=0.20W",
        "L=2m\nP=0.05W", "L=2m\nP=0.10W", "L=2m\nP=0.20W",
        "L=5m\nP=0.05W", "L=5m\nP=0.10W", "L=5m\nP=0.20W",
    ]

    # Old results (linear cost, March 31)
    old_J = [-57.9, -49.6, -42.7, -52.4, -41.6, -36.6, -45.1, -37.6, -35.1, NaN, NaN, NaN]
    # New results (log cost, April 1)
    new_J = [-77.6, -65.8, -71.4, -63.4, -57.0, -64.4, -64.7, -51.9, -60.5, -45.0, -52.8, -36.8]

    fig, ax = subplots(figsize=(14, 6))
    x = 1:length(configs)
    width = 0.35

    bars_old = ax.bar(x .- width/2, [isnan(j) ? 0 : abs(j) for j in old_J], width,
        label="Linear cost (old)", color="#D55E00", alpha=0.8, edgecolor="black", linewidth=0.5)
    bars_new = ax.bar(x .+ width/2, abs.(new_J), width,
        label="Log-scale cost (new)", color="#0072B2", alpha=0.8, edgecolor="black", linewidth=0.5)

    # Mark crashed points
    for (i, j) in enumerate(old_J)
        if isnan(j)
            ax.text(i - width/2, 2, "CRASH", ha="center", va="bottom",
                fontsize=7, color="red", fontweight="bold", rotation=90)
        end
    end

    # Annotate improvement
    for i in 1:length(configs)
        if !isnan(old_J[i])
            delta = new_J[i] - old_J[i]
            ax.annotate(@sprintf("%+.0f", delta),
                xy=(i + width/2, abs(new_J[i]) + 1),
                ha="center", va="bottom", fontsize=7, color="#009E73", fontweight="bold")
        end
    end

    ax.set_ylabel("|Raman suppression| [dB]", fontsize=12)
    ax.set_title("SMF-28: Impact of log-scale cost function on Raman suppression", fontsize=13, fontweight="bold")
    ax.set_xticks(x)
    ax.set_xticklabels(configs, fontsize=8)
    ax.legend(fontsize=11, loc="upper right")
    ax.set_ylim(0, 85)
    ax.grid(axis="y", alpha=0.3)
    ax.invert_yaxis()  # more negative = better suppression = taller bar

    # Actually, let's not invert — show as positive magnitude
    ax.set_ylim(0, 85)

    path = joinpath(OUT_DIR, "fig3_linear_vs_log_cost.png")
    savefig(path, dpi=300, bbox_inches="tight")
    @info "Saved $path"
    close(fig)
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 4: Multistart comparison
# ─────────────────────────────────────────────────────────────────────────────

function plot_multistart_comparison()
    # Old multistart (linear cost)
    old_sigma = [0.0, 0.1, 0.1, 0.1, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0]
    old_J = [-35.1, -17.9, -15.5, -15.4, -14.8, -15.2, -14.0, -7.8, -7.7, -6.9]
    old_conv = [false, false, false, false, false, false, false, false, false, false]

    # New multistart (log cost) — from JLD2
    ms_data = load("results/raman/sweeps/multistart_L2m_P030W.jld2")
    ms = ms_data["ms_results"]
    new_sigma = [r.sigma for r in ms]
    new_J = [r.J_final < 0 ? r.J_final : 10*log10(max(r.J_final, 1e-30)) for r in ms]
    new_conv = [r.converged for r in ms]

    fig, (ax1, ax2) = subplots(1, 2, figsize=(13, 5), sharey=true)

    # Old
    colors_old = [c ? "#009E73" : "#D55E00" for c in old_conv]
    ax1.scatter(old_sigma .+ randn(10) .* 0.02, old_J, c=colors_old, s=100,
        edgecolors="black", linewidth=0.8, zorder=3)
    ax1.axhline(y=-30, color="gray", ls="--", alpha=0.5, label="-30 dB threshold")
    ax1.set_xlabel("Initial phase sigma [rad]", fontsize=11)
    ax1.set_ylabel("J_final [dB]", fontsize=11)
    ax1.set_title("Linear cost (old)\n0/10 converged, spread = 28.6 dB", fontsize=11)
    ax1.set_xlim(-0.1, 1.2)
    ax1.grid(true, alpha=0.3)
    ax1.legend(fontsize=9)

    # New
    colors_new = [c ? "#009E73" : "#D55E00" for c in new_conv]
    ax2.scatter(new_sigma .+ randn(10) .* 0.02, new_J, c=colors_new, s=100,
        edgecolors="black", linewidth=0.8, zorder=3)
    ax2.axhline(y=-30, color="gray", ls="--", alpha=0.5, label="-30 dB threshold")
    ax2.set_xlabel("Initial phase sigma [rad]", fontsize=11)
    ax2.set_title("Log-scale cost (new)\n10/10 converged, spread = 10.9 dB", fontsize=11)
    ax2.set_xlim(-0.1, 1.2)
    ax2.grid(true, alpha=0.3)
    ax2.legend(fontsize=9)

    fig.suptitle("Multi-start robustness: SMF-28, L=2m, P=0.20W (N ≈ 2.6)",
        fontsize=13, fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.92])

    # Legend for convergence colors
    from_mpl = PyPlot.matplotlib.patches
    green_patch = from_mpl.Patch(color="#009E73", label="Converged")
    red_patch = from_mpl.Patch(color="#D55E00", label="Not converged")
    fig.legend(handles=[green_patch, red_patch], loc="lower center", ncol=2, fontsize=10)

    path = joinpath(OUT_DIR, "fig4_multistart_comparison.png")
    savefig(path, dpi=300, bbox_inches="tight")
    @info "Saved $path"
    close(fig)
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 5: Summary table as figure
# ─────────────────────────────────────────────────────────────────────────────

function plot_summary_table(points)
    # Sort by J_after_dB (best first)
    sorted = sort(points, by=p -> p.J_after_dB)

    fig, ax = subplots(figsize=(12, 7))
    ax.set_axis_off()

    headers = ["Rank", "Fiber", "L [m]", "P [W]", "J_before [dB]", "J_after [dB]", "ΔJ [dB]", "Converged"]
    col_widths = [0.06, 0.10, 0.08, 0.10, 0.14, 0.14, 0.12, 0.12]

    # Header row
    for (j, h) in enumerate(headers)
        x = sum(col_widths[1:j-1]) + col_widths[j]/2 + 0.05
        ax.text(x, 0.96, h, ha="center", va="center", fontsize=10,
            fontweight="bold", transform=ax.transAxes)
    end

    # Data rows
    n_show = min(24, length(sorted))
    for i in 1:n_show
        p = sorted[i]
        y = 0.96 - i * 0.035
        row = [
            string(i),
            p.fiber,
            @sprintf("%.1f", p.L),
            @sprintf("%.3f", p.P),
            @sprintf("%.1f", p.J_before_dB),
            @sprintf("%.1f", p.J_after_dB),
            @sprintf("%.1f", p.delta_dB),
            p.converged ? "Yes" : "No",
        ]
        bg_color = p.J_after_dB < -60 ? "#d4edda" : p.J_after_dB < -50 ? "#fff3cd" : "#f8f9fa"
        for (j, val) in enumerate(row)
            x = sum(col_widths[1:j-1]) + col_widths[j]/2 + 0.05
            ax.text(x, y, val, ha="center", va="center", fontsize=8.5,
                transform=ax.transAxes,
                bbox=Dict("boxstyle" => "round,pad=0.15", "facecolor" => bg_color, "alpha" => 0.5))
        end
    end

    ax.set_title("All 24 sweep points ranked by Raman suppression (green = excellent, yellow = good)",
        fontsize=12, fontweight="bold", pad=20)

    path = joinpath(OUT_DIR, "fig5_summary_table.png")
    savefig(path, dpi=300, bbox_inches="tight")
    @info "Saved $path"
    close(fig)
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

function generate_presentation_figures_main()
    @info "Loading sweep data..."
    points = load_all_sweep_points()
    @info "Loaded $(length(points)) points"

    @info "Generating Figure 1: Heatmaps..."
    plot_heatmaps(points)

    @info "Generating Figure 2: N_sol vs J scatter..."
    plot_nsol_vs_J(points)

    @info "Generating Figure 3: Linear vs log cost comparison..."
    plot_before_after()

    @info "Generating Figure 4: Multistart comparison..."
    plot_multistart_comparison()

    @info "Generating Figure 5: Summary table..."
    plot_summary_table(points)

    @info "All presentation figures saved to $OUT_DIR"
end

main() = generate_presentation_figures_main()

if abspath(PROGRAM_FILE) == @__FILE__
    generate_presentation_figures_main()
end
