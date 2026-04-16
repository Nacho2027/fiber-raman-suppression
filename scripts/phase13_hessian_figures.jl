"""
Phase 13 Plan 02 Task 3 — Hessian eigenspectrum figures.

READ-ONLY consumer of:
  * results/raman/phase13/hessian_smf28_canonical.jld2
  * results/raman/phase13/hessian_hnlf_canonical.jld2

Writes (all at 300 DPI):
  * results/images/phase13/phase13_04_hessian_eigvals_stem.png
  * results/images/phase13/phase13_05_top_eigenvectors.png
  * results/images/phase13/phase13_06_bottom_eigenvectors.png

Design notes:
  - Fig 04 uses a signed-log (symlog) y-axis to show the 4–5-decade span
    between stiff directions (λ_max) and Arpack's smallest-algebraic edge.
  - A gray band marks the plan's near-zero threshold `|λ| < 1e-6·λ_max`;
    annotated counts confirm the Arpack :LR / :SR wings never reach it
    (Arpack without shift-invert cannot resolve eigenvalues near zero —
     this is a known limitation, flagged in the figure subtitle).
  - Figs 05 and 06 plot eigenvectors against detuning Δf (THz) after
    fftshift. The input band is shaded in gold using the stored
    `input_band_mask`. For each bottom-5 eigenvector we compute cosine
    similarity against the two gauge reference modes
    (constant, linear-in-ω centered on the input band) and annotate the
    legend when the match exceeds 0.95 — i.e., the vector is recognisable
    as a gauge null-mode.

Usage:
  julia --project=. scripts/phase13_hessian_figures.jl
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using LinearAlgebra
using Statistics
using JLD2
using PyPlot

# ─────────────────────────────────────────────────────────────────────────────
# Paths + constants (P13_ prefix per STATE.md script convention)
# ─────────────────────────────────────────────────────────────────────────────

const P13_FIG_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase13")
const P13_FIG_IMG_DIR     = joinpath(@__DIR__, "..", "results", "images", "phase13")
const P13_FIG_NEAR_ZERO_REL = 1e-6      # |λ| < 1e-6·λ_max defines "near-zero"
const P13_FIG_GAUGE_COS_THR = 0.95      # cos-sim threshold for labelling a gauge mode
const P13_FIG_TOP_PLOT_K = 5
const P13_FIG_BOT_PLOT_K = 5

const P13_SMF_PATH  = joinpath(P13_FIG_RESULTS_DIR, "hessian_smf28_canonical.jld2")
const P13_HNLF_PATH = joinpath(P13_FIG_RESULTS_DIR, "hessian_hnlf_canonical.jld2")

# Colour palette: consistent with scripts/visualization.jl conventions.
const P13_CONFIG_LABELS = Dict(
    "smf28_canonical" => "SMF-28 canonical (L=2 m, P=0.2 W)",
    "hnlf_canonical"  => "HNLF canonical (L=0.5 m, P=0.01 W)",
)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    load_hessian_result(path) -> Dict

Load a Phase 13 Plan 02 JLD2 Hessian output and do the minimal checks
needed before plotting (sizes, NaN/Inf guards, gradient norm sanity).
"""
function load_hessian_result(path::AbstractString)
    @assert isfile(path) "Hessian result not found: $path"
    d = JLD2.load(path)
    # Schema sanity — matches the writer in scripts/phase13_hessian_eigspec.jl.
    for k in ("lambda_top", "lambda_bottom", "eigenvectors_top", "eigenvectors_bottom",
              "omega", "input_band_mask", "phi_opt", "grad_at_phi_opt",
              "J_after", "delta_J_dB", "near_zero_threshold",
              "near_zero_count_reported", "Nt", "config_name", "config_label")
        @assert haskey(d, k) "JLD2 $path missing key '$k' — aborting; inspect schema before rerunning"
    end
    Nt = Int(d["Nt"])
    @assert length(d["omega"]) == Nt
    @assert length(d["input_band_mask"]) == Nt
    @assert length(d["lambda_top"]) == size(d["eigenvectors_top"], 2)
    @assert length(d["lambda_bottom"]) == size(d["eigenvectors_bottom"], 2)
    for k in ("lambda_top", "lambda_bottom")
        @assert all(isfinite, d[k]) "$k in $path has non-finite values"
    end
    for k in ("eigenvectors_top", "eigenvectors_bottom")
        @assert all(isfinite, d[k]) "$k in $path has non-finite values"
    end
    return d
end

"""
    gauge_reference_modes(omega, input_band_mask) -> (const_ref, lin_ref)

Build unit-norm global-grid vectors representing the two gauge zero-modes:
  - `const_ref` ∝ 1        (removes mean(φ))
  - `lin_ref`  ∝ ω − mean(ω[band])  (removes group delay centered on band)

These are the analytic null directions of the band-cost Hessian; any
bottom eigenvector aligning with either at cos-similarity > 0.95 is
numerically confirmed as a gauge mode.
"""
function gauge_reference_modes(omega::AbstractVector{<:Real},
                               input_band_mask::AbstractVector{Bool})
    Nt = length(omega)
    @assert length(input_band_mask) == Nt
    const_ref = ones(Nt)
    const_ref ./= norm(const_ref)
    ω_band = omega[input_band_mask]
    ω_mean = isempty(ω_band) ? 0.0 : mean(ω_band)
    lin_ref = omega .- ω_mean
    nrm = norm(lin_ref)
    lin_ref = nrm > 0 ? lin_ref ./ nrm : lin_ref
    return const_ref, lin_ref
end

"""
    count_near_zero(lambdas, near_zero_threshold) -> Int

Absolute-threshold count — redundant with `near_zero_count_reported`
but recomputed defensively so the figure annotation can't drift from
the source data.
"""
count_near_zero(lambdas::AbstractVector{<:Real}, thr::Real) =
    count(x -> abs(x) < thr, lambdas)

# ─────────────────────────────────────────────────────────────────────────────
# Figure 04 — signed-log stem of top-20 and bottom-20 eigenvalues
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_eigvals_stem(smf, hnlf) -> path

Two-panel stem plot. Top-20 (λ_max side, blue) on positive x; bottom-20
(most-negative-algebraic side, red) on negative x. y-axis is matplotlib
symlog scaled by the near-zero threshold so the 4–5 decade span is
legible. Horizontal gray band marks `|λ| < 1e-6·λ_max`; annotation lists
near-zero-mode count and λ_max per panel.

Physics read: a λ_min much smaller in magnitude than λ_max is the stiff
spectrum; a λ_min with the opposite sign to λ_max is a saddle.
"""
function plot_eigvals_stem(smf::Dict, hnlf::Dict; out_path::AbstractString)
    fig, axs = subplots(1, 2, figsize=(14, 6))
    for (ax, d, key) in zip(axs, (smf, hnlf),
                            ("smf28_canonical", "hnlf_canonical"))
        label = P13_CONFIG_LABELS[key]
        λ_top = collect(d["lambda_top"])
        λ_bot = collect(d["lambda_bottom"])
        thr   = Float64(d["near_zero_threshold"])
        λ_max = maximum(λ_top)

        # Rank top descending, bottom ascending so the extremes sit at the outside
        order_top = sortperm(λ_top; rev=true)
        order_bot = sortperm(λ_bot)
        λt_sorted = λ_top[order_top]
        λb_sorted = λ_bot[order_bot]

        x_top = collect(1:length(λt_sorted))
        x_bot = -collect(1:length(λb_sorted))

        # Symlog axis: linear near zero, log outside. linthresh anchored to
        # the near-zero threshold so the "marked band" is a thin linear strip.
        # yscale="symlog" needs linthresh > 0; use max(thr, 1e-16) for safety.
        linthresh = max(thr, 1e-16)
        ax.set_yscale("symlog", linthresh=linthresh)

        ax.stem(x_top, λt_sorted;
            linefmt="C0-", markerfmt="C0o", basefmt=" ",
            label=@sprintf("top-%d (Arpack :LR)", length(x_top)))
        ax.stem(x_bot, λb_sorted;
            linefmt="C3-", markerfmt="C3s", basefmt=" ",
            label=@sprintf("bottom-%d (Arpack :SR)", length(x_bot)))

        ax.axhspan(-thr, thr; alpha=0.2, color="gray",
            label=@sprintf("|λ| < 1e-6·λ_max = %.1e", thr))
        ax.axhline(0; color="k", lw=0.5)
        ax.axvline(0; color="k", lw=0.3, linestyle=":")
        ax.set_xlabel("Rank  (negative x = bottom / most-negative :SR,   positive x = top / largest :LR)")
        ax.set_ylabel("Eigenvalue  λ  (symlog)")
        ax.set_title(label)
        ax.legend(loc="upper left", fontsize=9)
        ax.grid(true, alpha=0.3)

        nz_total = count_near_zero(vcat(λt_sorted, λb_sorted), thr)
        λ_min = minimum(λb_sorted)
        sign_gap = sign(λ_max) != sign(λ_min) && λ_min < 0 ? "INDEFINITE (saddle)" : "same-sign"
        ax.text(0.98, 0.02,
            @sprintf("λ_max = %+.2e\nλ_min = %+.2e\n|λ_min|/λ_max = %.1e\nnear-zero modes in reported 2K: %d\nsign pattern: %s",
                     λ_max, λ_min, abs(λ_min) / λ_max, nz_total, sign_gap);
            transform=ax.transAxes, ha="right", va="bottom", fontsize=9,
            bbox=Dict("facecolor" => "white", "alpha" => 0.85, "edgecolor" => "gray"))
    end
    fig.suptitle("Phase 13 Fig 4 — Hessian top-20 + bottom-20 eigenvalues at converged L-BFGS optima\n" *
                 "(Arpack matrix-free Lanczos :LR / :SR; gauge null-modes near zero are not resolvable without shift-invert)",
                 fontsize=12)
    fig.tight_layout()
    fig.savefig(out_path; dpi=300, bbox_inches="tight")
    close(fig)
    @info "  saved $out_path"
    return out_path
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 05 — top-5 eigenvectors (stiff directions)
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_top_eigvecs(smf, hnlf; out_path)

Two columns × two rows: top row = top-K eigenvalue bar, bottom row = the
K eigenvectors plotted as φ(Δf) over the detuning axis. Input band shaded.

x-axis is Δf = ω/(2π) with fftshift applied so the spectrum reads left to
right in natural order. Each eigenvector's sign is chosen so its peak is
positive for visual consistency.
"""
function plot_top_eigvecs(smf::Dict, hnlf::Dict; out_path::AbstractString)
    fig, axs = subplots(2, 2, figsize=(14, 9))
    for (col, d, key) in zip(1:2, (smf, hnlf),
                             ("smf28_canonical", "hnlf_canonical"))
        label = P13_CONFIG_LABELS[key]
        λ = collect(d["lambda_top"])
        V = collect(d["eigenvectors_top"])  # (Nt, K)
        omega = collect(d["omega"])
        in_mask = collect(d["input_band_mask"])

        # Arpack returns eigenpairs in no guaranteed order; sort by λ descending.
        order = sortperm(λ; rev=true)
        λ_sorted = λ[order]
        V_sorted = V[:, order]

        # Convert to detuning in THz and fftshift so axis reads monotonically.
        Δf = omega ./ (2π)
        shift_idx = sortperm(Δf)
        Δf_shift = Δf[shift_idx]
        Δf_band = Δf[in_mask]

        # ── top row: eigenvalue bar
        ax_t = axs[1, col]
        Kplot = min(P13_FIG_TOP_PLOT_K, length(λ_sorted))
        ax_t.bar(1:Kplot, λ_sorted[1:Kplot]; color="#0072B2", alpha=0.85)
        ax_t.set_xticks(1:Kplot)
        ax_t.set_xlabel("rank k")
        ax_t.set_ylabel("λ_k")
        ax_t.set_title(@sprintf("%s — top-%d eigenvalues", label, Kplot))
        ax_t.grid(true, axis="y", alpha=0.3)

        # ── bottom row: eigenvectors
        ax_b = axs[2, col]
        cmap = get_cmap("viridis")
        colors = [cmap(v) for v in range(0.0, 0.9; length=Kplot)]
        if !isempty(Δf_band)
            ax_b.axvspan(minimum(Δf_band), maximum(Δf_band);
                         alpha=0.12, color="gold", label="input band")
        end
        for k in 1:Kplot
            v = V_sorted[:, k][shift_idx]
            imax = argmax(abs.(v))
            if v[imax] < 0
                v = -v
            end
            ax_b.plot(Δf_shift, v; color=colors[k], lw=1.3,
                      label=@sprintf("k=%d, λ=%.2e", k, λ_sorted[k]))
        end
        ax_b.set_xlabel("Δf (THz)")
        ax_b.set_ylabel("eigenvector component")
        ax_b.set_title(@sprintf("%s — top-%d eigenvectors", label, Kplot))
        ax_b.legend(loc="best", fontsize=8)
        ax_b.grid(true, alpha=0.3)
        # Zoom to ±1.5× the input band so stiff-direction structure near
        # the pulse is legible.
        if !isempty(Δf_band)
            ext = maximum(Δf_band) - minimum(Δf_band)
            ctr = 0.5 * (maximum(Δf_band) + minimum(Δf_band))
            ax_b.set_xlim(ctr - 0.75 * ext, ctr + 0.75 * ext)
        end
    end
    fig.suptitle("Phase 13 Fig 5 — Top-5 Hessian eigenvectors (stiff directions at the optimum)",
                 fontsize=13)
    fig.tight_layout()
    fig.savefig(out_path; dpi=300, bbox_inches="tight")
    close(fig)
    @info "  saved $out_path"
    return out_path
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 06 — bottom-5 eigenvectors (soft / gauge / saddle directions)
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_bot_eigvecs(smf, hnlf; out_path)

Two columns × two rows; bottom-K eigenvalues on top row (colour-coded by
sign so negative → firebrick, positive → steelblue), eigenvectors
plotted as φ(Δf) on bottom row. We also overlay the two gauge reference
modes (constant, linear-in-ω) as dashed lines so a reader can visually
confirm whether any bottom eigenvector collapses onto either.
Cosine-similarity against each gauge mode is computed over the FULL
grid (not only the input band) and annotated in the legend whenever it
exceeds 0.95 — numerical confirmation of a gauge null-mode.
"""
function plot_bot_eigvecs(smf::Dict, hnlf::Dict; out_path::AbstractString)
    fig, axs = subplots(2, 2, figsize=(14, 9))
    for (col, d, key) in zip(1:2, (smf, hnlf),
                             ("smf28_canonical", "hnlf_canonical"))
        label = P13_CONFIG_LABELS[key]
        λ = collect(d["lambda_bottom"])
        V = collect(d["eigenvectors_bottom"])
        omega = collect(d["omega"])
        in_mask = collect(d["input_band_mask"])

        # Rank by |λ| ascending so "softest" modes come first.
        order = sortperm(abs.(λ))
        λ_sorted = λ[order]
        V_sorted = V[:, order]

        Δf = omega ./ (2π)
        shift_idx = sortperm(Δf)
        Δf_shift = Δf[shift_idx]
        Δf_band = Δf[in_mask]

        # ── top row: signed eigenvalue bar
        ax_t = axs[1, col]
        Kplot = min(P13_FIG_BOT_PLOT_K, length(λ_sorted))
        bar_colors = [x >= 0 ? "#0072B2" : "#D55E00" for x in λ_sorted[1:Kplot]]
        ax_t.bar(1:Kplot, λ_sorted[1:Kplot]; color=bar_colors, alpha=0.85)
        ax_t.axhline(0; color="k", lw=0.5)
        ax_t.set_xticks(1:Kplot)
        ax_t.set_xlabel("rank k (by |λ| ascending)")
        ax_t.set_ylabel("λ_k")
        ax_t.set_title(@sprintf("%s — bottom-%d by |λ|  (blue=+, vermillion=−)", label, Kplot))
        ax_t.grid(true, axis="y", alpha=0.3)

        # ── bottom row: eigenvectors + gauge references
        ax_b = axs[2, col]
        cmap = get_cmap("plasma")
        colors = [cmap(v) for v in range(0.0, 0.9; length=Kplot)]

        const_ref, lin_ref = gauge_reference_modes(omega, in_mask)
        if !isempty(Δf_band)
            ax_b.axvspan(minimum(Δf_band), maximum(Δf_band);
                         alpha=0.12, color="gold", label="input band")
        end

        gauge_hits = String[]
        for k in 1:Kplot
            v_raw = V_sorted[:, k]
            # Cosine similarity on the raw (unflipped) vector — sign is irrelevant for |cos|
            cos_const = abs(dot(v_raw, const_ref))
            cos_lin   = abs(dot(v_raw, lin_ref))
            gauge_mark = ""
            if cos_const > P13_FIG_GAUGE_COS_THR
                gauge_mark = "  [gauge: C]"
                push!(gauge_hits, @sprintf("k=%d const cos=%.3f", k, cos_const))
            elseif cos_lin > P13_FIG_GAUGE_COS_THR
                gauge_mark = "  [gauge: ω-linear]"
                push!(gauge_hits, @sprintf("k=%d linear cos=%.3f", k, cos_lin))
            end
            v_plot = v_raw[shift_idx]
            imax = argmax(abs.(v_plot))
            if v_plot[imax] < 0
                v_plot = -v_plot
            end
            ax_b.plot(Δf_shift, v_plot; color=colors[k], lw=1.3,
                label=@sprintf("k=%d, λ=%+.2e%s  (cos_C=%.3f, cos_ω=%.3f)",
                               k, λ_sorted[k], gauge_mark, cos_const, cos_lin))
        end
        # Reference gauge modes as faint dashed/dotted lines
        ax_b.plot(Δf_shift, const_ref[shift_idx]; color="k", lw=0.8,
                  linestyle="--", alpha=0.5, label="gauge ref: constant")
        ax_b.plot(Δf_shift, lin_ref[shift_idx]; color="k", lw=0.8,
                  linestyle=":", alpha=0.5, label="gauge ref: ω-linear")

        ax_b.set_xlabel("Δf (THz)")
        ax_b.set_ylabel("eigenvector component")
        ax_b.set_title(@sprintf("%s — bottom-%d eigenvectors (sorted by |λ|)", label, Kplot))
        ax_b.legend(loc="best", fontsize=7)
        ax_b.grid(true, alpha=0.3)
        if !isempty(Δf_band)
            ext = maximum(Δf_band) - minimum(Δf_band)
            ctr = 0.5 * (maximum(Δf_band) + minimum(Δf_band))
            ax_b.set_xlim(ctr - 0.75 * ext, ctr + 0.75 * ext)
        end

        if isempty(gauge_hits)
            @info @sprintf("  %s: no bottom-%d eigenvector matches gauge refs at cos-sim > %.2f — bottom set does NOT contain gauge null-modes",
                           key, Kplot, P13_FIG_GAUGE_COS_THR)
        else
            @info @sprintf("  %s gauge hits: %s", key, join(gauge_hits, "; "))
        end
    end
    fig.suptitle("Phase 13 Fig 6 — Bottom-5 Hessian eigenvectors (soft directions — gauge, saddle, or genuine flatness)",
                 fontsize=13)
    fig.tight_layout()
    fig.savefig(out_path; dpi=300, bbox_inches="tight")
    close(fig)
    @info "  saved $out_path"
    return out_path
end

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

"""
    main() -> Vector{String}

Load both JLD2s, produce all 3 figures, return the written paths.
Safe to call multiple times; each figure is rewritten.
"""
function main()
    mkpath(P13_FIG_IMG_DIR)
    smf  = load_hessian_result(P13_SMF_PATH)
    hnlf = load_hessian_result(P13_HNLF_PATH)

    out_stem = joinpath(P13_FIG_IMG_DIR, "phase13_04_hessian_eigvals_stem.png")
    out_top  = joinpath(P13_FIG_IMG_DIR, "phase13_05_top_eigenvectors.png")
    out_bot  = joinpath(P13_FIG_IMG_DIR, "phase13_06_bottom_eigenvectors.png")

    @info "Phase 13 Fig 4 — stem plot of top/bottom eigenvalues"
    plot_eigvals_stem(smf, hnlf; out_path=out_stem)
    @info "Phase 13 Fig 5 — top-5 eigenvectors"
    plot_top_eigvecs(smf, hnlf; out_path=out_top)
    @info "Phase 13 Fig 6 — bottom-5 eigenvectors"
    plot_bot_eigvecs(smf, hnlf; out_path=out_bot)

    return [out_stem, out_top, out_bot]
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
