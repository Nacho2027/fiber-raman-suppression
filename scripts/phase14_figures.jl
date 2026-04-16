# ═══════════════════════════════════════════════════════════════════════════════
# Phase 14 Plan 02 — Figures
# ═══════════════════════════════════════════════════════════════════════════════
#
# Render the 3 decision figures for Phase 14 Plan 02 at 300 DPI.
#
#   phase14_01_ab_J_vs_lambda.png
#       One subplot per config; J_final_dB (vertical) vs log10(lambda_sharp).
#       λ=0 marker ("vanilla") drawn as a horizontal dashed line + annotated.
#
#   phase14_02_robustness_curves.png
#       One subplot per config; mean Δ J_dB (vertical) vs σ (linear x-axis).
#       Curve per lambda_sharp; error bars = std-dev across trials.
#
#   phase14_03_phase_profiles_ab.png
#       One subplot per config; φ(ω) overlays of {vanilla, λ=0.1, λ=1, λ=10}
#       after gauge-fix (from scripts/phase13_primitives.jl :: gauge_fix).
#       Input band highlighted.
#
# Data sources:
#   results/raman/phase14/ab_results.jld2         (from phase14_ab_comparison.jl)
#   results/raman/phase14/robustness_results.jld2 (from phase14_robustness_test.jl)
#
# Figures written to: results/images/phase14/
# ═══════════════════════════════════════════════════════════════════════════════

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using LinearAlgebra
using Statistics
using FFTW
using JLD2
using PyPlot

# We only need gauge_fix + omega_vector + input_band_mask for phase profiles.
include(joinpath(@__DIR__, "phase13_primitives.jl"))

const P14FG_VERSION = "1.0.0"
const P14FG_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase14")
const P14FG_IMG_DIR = joinpath(@__DIR__, "..", "results", "images", "phase14")
const P14FG_SMOKE = any(a -> a == "--smoke", ARGS)

# Canonical display order (by config_id). Matches A/B script ordering.
const P14FG_CONFIG_ORDER = P14FG_SMOKE ?
    ["smf28_canonical_smoke"] :
    ["smf28_canonical", "hnlf_canonical", "smf28_longfiber"]

# Colors per lambda_sharp value — consistent across figures.
function lambda_color(λ::Real)
    if λ == 0.0
        return "black"
    elseif λ ≈ 0.01
        return "#1f77b4"
    elseif λ ≈ 0.1
        return "#2ca02c"
    elseif λ ≈ 1.0
        return "#d62728"
    elseif λ ≈ 10.0
        return "#ff7f0e"
    elseif λ ≈ 100.0
        return "#9467bd"
    else
        return "gray"
    end
end

lambda_label(λ::Real) = λ == 0.0 ? "vanilla (λ=0)" : @sprintf("λ=%g", λ)

# ─────────────────────────────────────────────────────────────────────────────
# Load inputs
# ─────────────────────────────────────────────────────────────────────────────

function load_inputs()
    ab_path = joinpath(P14FG_RESULTS_DIR, P14FG_SMOKE ? "ab_results_smoke.jld2" : "ab_results.jld2")
    rb_path = joinpath(P14FG_RESULTS_DIR, P14FG_SMOKE ? "robustness_results_smoke.jld2" : "robustness_results.jld2")
    @assert isfile(ab_path) "A/B results not found: $ab_path"
    @assert isfile(rb_path) "Robustness results not found: $rb_path"
    ab = JLD2.load(ab_path)
    rb = JLD2.load(rb_path)
    return ab, rb, ab_path, rb_path
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 1: J_final_dB vs lambda_sharp
# ─────────────────────────────────────────────────────────────────────────────

function figure_1_ab_J_vs_lambda(ab)
    configs = [cid for cid in P14FG_CONFIG_ORDER if cid in ab["config_id"]]
    n_cfg = length(configs)
    fig, axes = subplots(1, n_cfg, figsize=(4.5 * n_cfg, 4), sharey=true)
    axes_vec = n_cfg == 1 ? [axes] : axes

    for (idx, cfg_id) in enumerate(configs)
        ax = axes_vec[idx]
        sel = (ab["config_id"] .== cfg_id) .& (.!ab["failed"])
        λs = ab["lambda_sharp"][sel]
        Js = ab["J_final_dB"][sel]
        saddle = ab["saddle_flag"][sel]
        label = first(ab["config_label"][sel])

        # Sort by lambda so the line connects nicely.
        order = sortperm(λs)
        λs = λs[order]
        Js = Js[order]
        saddle = saddle[order]

        # Vanilla (λ=0) separator: plot as a horizontal dashed line + single marker.
        idx_van = findfirst(isequal(0.0), λs)
        if idx_van !== nothing
            ax.axhline(Js[idx_van], color="black", linestyle="--", linewidth=1.2,
                        alpha=0.5, label="vanilla reference")
            ax.plot([0.001], [Js[idx_van]], color="black", marker="s", markersize=8,
                     linestyle="None", label="vanilla (plotted at λ=0.001)")
        end

        # Positive-lambda points on log x-axis.
        pos_mask = λs .> 0
        λp = λs[pos_mask]
        Jp = Js[pos_mask]
        sadp = saddle[pos_mask]
        ax.plot(λp, Jp, color="#1f77b4", marker="o", linestyle="-", linewidth=1.6,
                 markersize=7, label="sharp optimizer")

        # Saddle flag annotation: open circle marker where saddle_flag=true.
        sad_idx = findall(sadp)
        if !isempty(sad_idx)
            ax.plot(λp[sad_idx], Jp[sad_idx], color="red", marker="o", markersize=12,
                     markerfacecolor="none", markeredgewidth=2.0, linestyle="None",
                     label="saddle flag")
        end

        ax.set_xscale("log")
        ax.set_xlabel(L"\lambda_{\mathrm{sharp}}")
        if idx == 1
            ax.set_ylabel(L"J_{\mathrm{final}}\;[\mathrm{dB}]")
        end
        ax.set_title(label, fontsize=10)
        ax.grid(true, which="both", alpha=0.3)
        ax.legend(loc="best", fontsize=8, framealpha=0.85)
    end

    fig.suptitle("Phase 14 — A/B tradeoff: J_final vs λ_sharp", fontsize=11, y=1.01)
    fig.tight_layout()

    out = joinpath(P14FG_IMG_DIR, "phase14_01_ab_J_vs_lambda.png")
    fig.savefig(out, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Fig 1 written" path=out
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 2: robustness curves
# ─────────────────────────────────────────────────────────────────────────────

function figure_2_robustness_curves(ab, rb)
    configs = [cid for cid in P14FG_CONFIG_ORDER if cid in ab["config_id"]]
    n_cfg = length(configs)
    sigmas = rb["sigmas"]::Vector{Float64}
    mean_dJ = rb["mean_delta_J_dB"]::Matrix{Float64}
    std_dJ  = rb["std_delta_J_dB"]::Matrix{Float64}
    cell_cfg = rb["cell_config_id"]::Vector{String}
    cell_λ   = rb["cell_lambda_sharp"]::Vector{Float64}
    cell_failed = rb["cell_failed"]::Vector{Bool}

    fig, axes = subplots(1, n_cfg, figsize=(4.5 * n_cfg, 4), sharey=true)
    axes_vec = n_cfg == 1 ? [axes] : axes

    for (idx, cfg_id) in enumerate(configs)
        ax = axes_vec[idx]
        sel_idx = findall((cell_cfg .== cfg_id) .& (.!cell_failed))
        λs_local = cell_λ[sel_idx]
        order = sortperm(λs_local)
        sel_idx = sel_idx[order]
        λs_local = cell_λ[sel_idx]
        cfg_label = first(ab["config_label"][(ab["config_id"] .== cfg_id) .& (.!ab["failed"])])

        for (i_row, λ) in zip(sel_idx, λs_local)
            means = mean_dJ[i_row, :]
            stds  = std_dJ[i_row, :]
            ax.errorbar(sigmas, means, yerr=stds,
                         color=lambda_color(λ), marker="o", linewidth=1.6,
                         capsize=3, label=lambda_label(λ))
        end
        ax.set_xlabel(L"\sigma\;[\mathrm{rad}]")
        if idx == 1
            ax.set_ylabel(L"\mathrm{mean}\; \Delta J\;[\mathrm{dB}]")
        end
        ax.set_title(cfg_label, fontsize=10)
        ax.grid(true, alpha=0.3)
        ax.legend(loc="best", fontsize=7, framealpha=0.85, ncol=2)
    end

    fig.suptitle("Phase 14 — Robustness: ⟨ΔJ⟩ vs σ, curves per λ_sharp", fontsize=11, y=1.01)
    fig.tight_layout()
    out = joinpath(P14FG_IMG_DIR, "phase14_02_robustness_curves.png")
    fig.savefig(out, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Fig 2 written" path=out
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 3: phi(omega) overlays — gauge-fixed phase profiles
# ─────────────────────────────────────────────────────────────────────────────

function figure_3_phase_profiles(ab)
    configs = [cid for cid in P14FG_CONFIG_ORDER if cid in ab["config_id"]]
    n_cfg = length(configs)
    fig, axes = subplots(n_cfg, 1, figsize=(8, 3 * n_cfg), sharex=false)
    axes_vec = n_cfg == 1 ? [axes] : axes

    # Pick which lambdas to overlay (+ vanilla).
    λ_display = [0.0, 0.1, 1.0, 10.0]

    # We need omega + input_band_mask per config — rebuild via setup_raman_problem.
    # The Config registry mirrors what ab_results saved but we need to re-run setup.
    registry = Dict(
        "smf28_canonical" =>
            (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2,
             Nt = 2^13, time_window = 40.0, β_order = 3),
        "hnlf_canonical" =>
            (fiber_preset = :HNLF, L_fiber = 0.5, P_cont = 5e-3,
             Nt = 2^13, time_window = 5.0, β_order = 3),
        "smf28_longfiber" =>
            (fiber_preset = :SMF28, L_fiber = 5.0, P_cont = 0.2,
             Nt = 2^13, time_window = 100.0, β_order = 3),
        "smf28_canonical_smoke" =>
            (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2,
             Nt = 2^8, time_window = 10.0, β_order = 3),
    )

    for (idx, cfg_id) in enumerate(configs)
        ax = axes_vec[idx]
        kwargs = registry[cfg_id]
        uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(; kwargs...)
        Nt = sim["Nt"]
        # omega offsets in rad/ps — for gauge_fix
        omega = omega_vector(sim["ω0"], sim["Δt"], Nt)
        input_mask = input_band_mask(uω0)
        # Δf_plot in THz, fftshifted for plot legibility.
        Δf_fft = fftfreq(Nt, 1 / sim["Δt"])
        Δf_plot = fftshift(Δf_fft)

        cfg_label = first(ab["config_label"][(ab["config_id"] .== cfg_id) .& (.!ab["failed"])])

        # Highlight input band (use fftshift so it aligns with Δf_plot).
        input_mask_shifted = fftshift(input_mask)
        # Find contiguous true intervals of input_mask_shifted and shade them.
        in_band = findall(input_mask_shifted)
        if !isempty(in_band)
            f_min = minimum(Δf_plot[in_band])
            f_max = maximum(Δf_plot[in_band])
            ax.axvspan(f_min, f_max, color="lightsteelblue", alpha=0.3, label="input band")
        end

        # Overlay phi(omega) for each lambda_display value.
        for λ in λ_display
            matches = (ab["config_id"] .== cfg_id) .& (ab["lambda_sharp"] .== λ) .& (.!ab["failed"])
            if !any(matches)
                continue
            end
            i = findfirst(matches)
            phi_opt = ab["phi_opt"][i]
            phi_vec = vec(phi_opt)
            # Gauge-fix over the INPUT band (same convention as Phase 13 primitives).
            phi_fixed, _ = gauge_fix(phi_vec, input_mask, omega)
            phi_shift = fftshift(phi_fixed)
            ax.plot(Δf_plot, phi_shift,
                     color=lambda_color(λ), linewidth=1.4, alpha=0.9,
                     label=lambda_label(λ))
        end

        ax.set_xlabel(L"\Delta f\;[\mathrm{THz}]")
        ax.set_ylabel(L"\varphi(\omega)\;[\mathrm{rad}]")
        ax.set_title(cfg_label, fontsize=10)
        ax.grid(true, alpha=0.3)
        ax.legend(loc="best", fontsize=8, framealpha=0.85, ncol=2)

        # Zoom x-axis to the interesting region near the input band plus some
        # margin on each side.
        if !isempty(in_band)
            f_min = minimum(Δf_plot[in_band])
            f_max = maximum(Δf_plot[in_band])
            span = f_max - f_min
            ax.set_xlim(f_min - 0.5 * span, f_max + 0.5 * span)
        end
    end

    fig.suptitle("Phase 14 — Gauge-fixed φ_opt(ω) overlays", fontsize=11, y=1.01)
    fig.tight_layout()
    out = joinpath(P14FG_IMG_DIR, "phase14_03_phase_profiles_ab.png")
    fig.savefig(out, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Fig 3 written" path=out
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

function main()
    mkpath(P14FG_IMG_DIR)
    ab, rb, ab_path, rb_path = load_inputs()
    @info "Loaded inputs" ab_path=ab_path rb_path=rb_path smoke=P14FG_SMOKE

    f1 = figure_1_ab_J_vs_lambda(ab)
    f2 = figure_2_robustness_curves(ab, rb)
    f3 = figure_3_phase_profiles(ab)
    @info "All 3 figures written" f1=f1 f2=f2 f3=f3
    return (f1, f2, f3)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
