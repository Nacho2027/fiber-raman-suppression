# ═══════════════════════════════════════════════════════════════════════════════
# Session G — A/B + robustness figures + FINDINGS
# ═══════════════════════════════════════════════════════════════════════════════
#
# Consumes sharp_ab_slim/ab_results.jld2 and sharp_ab_slim/robustness.jld2;
# writes 3 figures + FINDINGS.md under results/raman/sharp_ab_slim/.

ENV["MPLBACKEND"] = "Agg"

using LinearAlgebra, Statistics, Printf, JLD2
using PyPlot

if !(@isdefined _SHARP_AB_FIGURES_LOADED)

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))

const _SHARP_AB_FIGURES_LOADED = true
const SAF_OUT_DIR  = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "sharp_ab_slim")
const SAF_IMG_DIR  = joinpath(@__DIR__, "..", "..", "..", "results", "images", "sharp_ab_slim")
const SAF_COLORS   = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd"]

function fig_J_vs_lambda(ab)
    lambdas = ab["lambdas"]
    Js      = [r.J_final_dB for r in ab["results"]]
    iters   = [r.iterations for r in ab["results"]]
    fig, ax = subplots(figsize=(6,4))
    # x-axis: index (because λ=0 breaks log); label with λ values
    x = 1:length(lambdas)
    ax.plot(x, Js, "o-", color=SAF_COLORS[1], markersize=8, linewidth=2)
    for (i, J) in enumerate(Js)
        ax.annotate(@sprintf("%.1f dB\n%d iter", J, iters[i]),
                     (i, J), textcoords="offset points",
                     xytext=(0, 12), ha="center", fontsize=9)
    end
    ax.set_xticks(x)
    ax.set_xticklabels([string(λ) for λ in lambdas])
    ax.set_xlabel("λ_sharp")
    ax.set_ylabel("J_final (dB)")
    ax.set_title("A/B final J vs λ_sharp (SMF-28 canonical)")
    ax.grid(true, alpha=0.3)
    tight_layout()
    path = joinpath(SAF_IMG_DIR, "sharp_ab_01_J_vs_lambda.png")
    savefig(path, dpi=300)
    close(fig)
    return path
end

function fig_robustness(ab, rob)
    lambdas  = rob["lambdas"]
    sigmas   = rob["sigmas"]
    mean_J   = rob["mean_J"]     # [lambda, sigma]
    std_J    = rob["std_J"]
    J_base   = rob["J_base_per_lambda"]
    σ3       = rob["sigma_3dB_per_lambda"]

    fig, ax = subplots(figsize=(6.5, 4.5))
    for (li, λ) in enumerate(lambdas)
        ΔJ = mean_J[li, :] .- J_base[li]
        std = std_J[li, :]
        σ3dB_str = isinf(σ3[li]) ? ">0.2" : @sprintf("%.3f", σ3[li])
        label = @sprintf("λ=%s, σ_3dB=%s", string(λ), σ3dB_str)
        ax.errorbar(sigmas, ΔJ, yerr=std, fmt="o-",
                     color=SAF_COLORS[li], label=label,
                     markersize=7, linewidth=2, capsize=4)
    end
    ax.axhline(3.0, color="gray", linestyle="--", alpha=0.6, label="3 dB threshold")
    ax.set_xlabel("σ (rad, Gaussian phase perturbation)")
    ax.set_ylabel("mean ΔJ = J(φ+σn) − J(φ_opt)  [dB]")
    ax.set_title("Basin width: sharp vs vanilla (SMF-28 canonical)")
    ax.grid(true, alpha=0.3)
    ax.legend(loc="upper left", fontsize=9)
    tight_layout()
    path = joinpath(SAF_IMG_DIR, "sharp_ab_02_robustness_curves.png")
    savefig(path, dpi=300)
    close(fig)
    return path
end

function fig_phase_profiles(ab)
    results = ab["results"]
    lambdas = ab["lambdas"]

    # Reconstruct ω from config for axis.
    cfg_kwargs = ab["config"].kwargs
    # Just use sample index for x-axis (no need to rebuild full problem;
    # ω_rad/ps is uniform-spaced).
    Nt = length(results[1].phi_opt)
    ω = collect(1:Nt)

    fig, ax = subplots(figsize=(8, 4))
    for (li, r) in enumerate(results)
        φ = r.phi_opt .- mean(r.phi_opt)  # remove gauge offset for display
        ax.plot(ω, φ, linewidth=1.2,
                 color=SAF_COLORS[li],
                 label=@sprintf("λ=%s (J=%.2f dB)",
                                string(lambdas[li]), r.J_final_dB))
    end
    ax.set_xlabel("ω index")
    ax.set_ylabel("φ(ω) − mean (rad)")
    ax.set_title("Gauge-offset-removed φ_opt per λ_sharp")
    ax.grid(true, alpha=0.3)
    ax.legend(loc="upper right", fontsize=9)
    tight_layout()
    path = joinpath(SAF_IMG_DIR, "sharp_ab_03_phase_profiles.png")
    savefig(path, dpi=300)
    close(fig)
    return path
end

function write_findings(ab, rob, fig_paths)
    lambdas = ab["lambdas"]
    results = ab["results"]
    σ3      = rob["sigma_3dB_per_lambda"]
    Js      = [r.J_final_dB for r in results]

    # Baseline (λ=0) reference
    i0 = findfirst(==(0.0), lambdas)
    J0 = Js[i0]; σ0 = σ3[i0]
    # Best non-vanilla by σ_3dB
    nonzero_idx = [i for i in 1:length(lambdas) if lambdas[i] > 0]
    best_σ_idx = nonzero_idx[argmax([σ3[i] for i in nonzero_idx])]
    σ_best = σ3[best_σ_idx]; λ_best = lambdas[best_σ_idx]; J_best = Js[best_σ_idx]
    ΔJ = J_best - J0
    Δσ_ratio = isinf(σ_best) ? Inf : σ_best / max(σ0, 1e-9)

    verdict = if σ_best == Inf
        "SHARPNESS_HELPS_DECISIVELY (λ>0 finds a basin flatter than the 0.2 rad perturbation scan)"
    elseif σ_best >= 2 * σ0 && ΔJ < 5
        @sprintf("SHARPNESS_HELPS (σ_3dB improved %.1fx at λ=%s; J_final dropped %.2f dB)",
                  Δσ_ratio, string(λ_best), -ΔJ)
    elseif σ_best >= 1.3 * σ0
        @sprintf("SHARPNESS_MARGINAL (σ_3dB improved %.1fx, J cost %.2f dB)",
                  Δσ_ratio, -ΔJ)
    else
        @sprintf("SHARPNESS_NO_OP (σ_3dB %.1fx, J cost %.2f dB — not worth it)",
                  Δσ_ratio, -ΔJ)
    end

    lines = String[]
    push!(lines, "---")
    push!(lines, "phase: sharp-ab-slim")
    push!(lines, "session: G-sharp-ab")
    push!(lines, "branch: sessions/G-sharp-ab")
    push!(lines, "created: 2026-04-17")
    push!(lines, "verdict: " * verdict)
    push!(lines, "---")
    push!(lines, "")
    push!(lines, "# Session G — Slim A/B FINDINGS")
    push!(lines, "")
    push!(lines, "## Headline verdict")
    push!(lines, "")
    push!(lines, "**" * verdict * "**")
    push!(lines, "")
    push!(lines, "## Quick numbers (SMF-28 canonical L=2 m P=0.2 W Nt=2^13 max_iter=20 N_s=4)")
    push!(lines, "")
    push!(lines, "| λ_sharp | J_final (dB) | iters | σ_3dB (rad) |")
    push!(lines, "|---|---|---|---|")
    for i in 1:length(lambdas)
        σstr = isinf(σ3[i]) ? ">0.2" : @sprintf("%.4f", σ3[i])
        push!(lines, @sprintf("| %s | %.3f | %d | %s |",
                               string(lambdas[i]), Js[i],
                               results[i].iterations, σstr))
    end
    push!(lines, "")
    push!(lines, "## Comparison to Session D Phase 17 (baseline reference)")
    push!(lines, "")
    push!(lines, "Session D's SHARP_LUCKY verdict on the simple-phase optimum gave σ_3dB = 0.025 rad.")
    push!(lines, @sprintf("This slim A/B's vanilla (λ=0) result: σ_3dB = %.4f rad, J = %.3f dB.", σ0, J0))
    push!(lines, "")
    push!(lines, "## Interpretation")
    push!(lines, "")
    if σ_best == Inf
        push!(lines, "Sharpness-aware optimization moves to a basin whose width exceeds the perturbation scan — clear win. Recommend elevating SO_DEFAULT_LAMBDA. Follow-up: confirm on HNLF and at a long-fiber point.")
    elseif Δσ_ratio >= 2
        push!(lines, @sprintf("Sharpness-aware cost at λ=%s widens σ_3dB from %.4f → %.4f rad (%.1fx). J_final cost is %+.2f dB — acceptable tradeoff for experimental robustness. Recommend making λ=%s the default.",
                               string(λ_best), σ0, σ_best, Δσ_ratio, -ΔJ, string(λ_best)))
    elseif Δσ_ratio >= 1.3
        push!(lines, @sprintf("Sharpness helps marginally (σ_3dB ratio %.1fx) at J cost of %.2f dB. Not clear-cut; probably not worth making default without a larger per-config study.",
                               Δσ_ratio, -ΔJ))
    else
        push!(lines, "Within the λ range tested ({" * join([string(l) for l in lambdas], ", ") * "}), sharpness penalty does not widen the basin meaningfully. Consistent with Phase 13's indefinite_hessian finding: L-BFGS terminates on saddle points where tr(H) Hutchinson estimator is noisy and may not reflect true curvature.")
    end
    push!(lines, "")
    push!(lines, "## Limitations")
    push!(lines, "")
    push!(lines, "- Single config only; HNLF and long-fiber regimes untested")
    push!(lines, "- max_iter reduced to 20 from the nominal 30; convergence not fully exhausted at each λ")
    push!(lines, "- N_s = 4 Hutchinson samples → elevated sharpness-estimator variance; σ_3dB interpretation benefits from larger N_s in a follow-up")
    push!(lines, "- Perturbation n is full-Nt Gaussian (not gauge-projected); small σ means gauge component is ≲2% of n, so effect is minor")
    push!(lines, "")
    push!(lines, "## Figures")
    push!(lines, "")
    for p in fig_paths
        push!(lines, "- `" * p * "`")
    end

    path = joinpath(SAF_OUT_DIR, "FINDINGS.md")
    write(path, join(lines, "\n") * "\n")
    @info "wrote $path"
    return path
end

function main()
    ab  = JLD2.load(joinpath(SAF_OUT_DIR, "ab_results.jld2"))
    rob = JLD2.load(joinpath(SAF_OUT_DIR, "robustness.jld2"))
    mkpath(SAF_IMG_DIR)
    fig_paths = [
        fig_J_vs_lambda(ab),
        fig_robustness(ab, rob),
        fig_phase_profiles(ab),
    ]
    @info "figures: $fig_paths"
    write_findings(ab, rob, fig_paths)
end

end  # include guard

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
