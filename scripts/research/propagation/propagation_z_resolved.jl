"""
Z-Resolved Propagation Diagnostics — Phase 10.1

Runs z-resolved forward propagations for 6 representative configurations
(3 SMF-28 + 3 HNLF) spanning the soliton number range N_sol = 1.3 to 6.3.
Each configuration is propagated twice: once with flat phase (unshaped) and
once with phi_opt loaded from the Phase 7/8 sweep JLD2 files (shaped).

Raman band energy fraction J(z) is computed at 50 z-points along the fiber,
revealing WHERE Raman energy builds up inside the fiber and how the optimizer's
spectral phase delays or prevents this buildup.

Figures produced (all -> results/images/):
  01. physics_10_01_raman_fraction_vs_z.png   — J(z) shaped vs unshaped, all 6 configs
  02. physics_10_02_spectral_evolution_comparison.png — Spectral heatmaps, 2 configs
  03. physics_10_03_temporal_evolution_comparison.png — Temporal heatmaps, 2 configs
  04. physics_10_04_nsol_regime_comparison.png — J(z) by N_sol regime

Data saved to results/raman/phase10/ (12 JLD2 files, 6 configs x 2 conditions).

Written findings saved to results/raman/PHASE10_ZRESOLVED_FINDINGS.md.

Anti-patterns to avoid:
  - Always pass Nt=Int(data["Nt"]) and time_window=Float64(data["time_window_ps"])
    to setup_raman_problem — never rely on auto-sizing with stored data
  - Use deepcopy(fiber) before setting fiber["zsave"] — do not mutate original
  - Index z-slices as sol["uω_z"][i, :, :] (2D, explicit M) — never sol["uω_z"][i, :]
  - phi_opt and uω0 are in FFT order — no fftshift before applying exp.(1im .* phi_opt)
"""

try using Revise catch end
using Printf
using LinearAlgebra
using FFTW
using Logging
using Statistics
using Dates
ENV["MPLBACKEND"] = "Agg"
using PyPlot
using JLD2

include("common.jl")
include("visualization.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Include guard + constants (PZ_ prefix per D-15)
# ─────────────────────────────────────────────────────────────────────────────

if !(@isdefined _PZ_SCRIPT_LOADED)
const _PZ_SCRIPT_LOADED = true

const PZ_N_ZSAVE = 50                               # D-01: 50 z-save points
const PZ_RESULTS_DIR = joinpath("results", "raman", "phase10")
const PZ_FIGURE_DIR  = joinpath("results", "images")

# Fiber betas lookup (betas field is empty in sweep JLD2 files; recover by fiber name)
const PZ_FIBER_BETAS = Dict(
    "SMF-28" => [-2.17e-26, 1.2e-40],
    "HNLF"   => [-0.5e-26, 1.0e-40],
)
const PZ_REP_RATE    = 80.5e6
const PZ_SECH2_FACTOR = 0.881374

# ─────────────────────────────────────────────────────────────────────────────
# 6 representative configurations spanning N_sol 1.3 to 6.3
# Selected to cover: low N (good suppression), medium N (good suppression),
# long-fiber degraded case (SMF-28 5m — reveals where suppression breaks down),
# HNLF across three N regimes.
# ─────────────────────────────────────────────────────────────────────────────

const PZ_CONFIGS = [
    # SMF-28 (3): low N, medium N, long-fiber degraded
    (fiber_dir="smf28", config="L0.5m_P0.05W",  label="SMF-28 N=1.3",        preset=:SMF28, fiber_type="SMF-28"),
    (fiber_dir="smf28", config="L0.5m_P0.2W",   label="SMF-28 N=2.6",        preset=:SMF28, fiber_type="SMF-28"),
    (fiber_dir="smf28", config="L5m_P0.2W",     label="SMF-28 N=2.6 (5m)",   preset=:SMF28, fiber_type="SMF-28"),
    # HNLF (3): low N, medium N, high N
    (fiber_dir="hnlf",  config="L1m_P0.005W",   label="HNLF N=2.6",          preset=:HNLF,  fiber_type="HNLF"),
    (fiber_dir="hnlf",  config="L1m_P0.01W",    label="HNLF N=3.6",          preset=:HNLF,  fiber_type="HNLF"),
    (fiber_dir="hnlf",  config="L0.5m_P0.03W",  label="HNLF N=6.3",          preset=:HNLF,  fiber_type="HNLF"),
]

# ─────────────────────────────────────────────────────────────────────────────
# Helper: compute soliton number from JLD2 metadata
# ─────────────────────────────────────────────────────────────────────────────

"""
    pz_soliton_number(data, preset) -> Float64

Compute soliton number N = sqrt(γ P_peak T0² / |β₂|) from JLD2 metadata.
Betas are looked up from PZ_FIBER_BETAS if the stored field is empty.
"""
function pz_soliton_number(data, preset_sym)
    P_cont  = Float64(data["P_cont_W"])
    fwhm_fs = Float64(data["fwhm_fs"])
    fwhm_s  = fwhm_fs * 1e-15
    P_peak  = PZ_SECH2_FACTOR * P_cont / (fwhm_s * PZ_REP_RATE)
    T0      = fwhm_s / 1.7627  # sech² pulse width parameter

    fiber_preset = FIBER_PRESETS[preset_sym]
    gamma  = fiber_preset.gamma
    beta2  = fiber_preset.betas[1]
    return sqrt(gamma * P_peak * T0^2 / abs(beta2))
end

# ─────────────────────────────────────────────────────────────────────────────
# Core function: load phi_opt, re-propagate with z-saves, compute J(z)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pz_load_and_repropagate(fiber_dir, config_name, preset; n_zsave=PZ_N_ZSAVE)

Load phi_opt from a sweep JLD2 file, reconstruct the identical simulation grid,
and run two forward propagations (shaped and unshaped) with 50 z-save points.
Returns a named tuple with all results needed for plotting and saving.

CRITICAL: Nt and time_window are loaded from JLD2 to ensure the reconstructed
grid matches exactly. Never rely on auto-sizing when loading stored phase data.
"""
function pz_load_and_repropagate(fiber_dir, config_name, preset; n_zsave=PZ_N_ZSAVE)
    jld2_path = joinpath("results", "raman", "sweeps", fiber_dir, config_name, "opt_result.jld2")
    @assert isfile(jld2_path) "JLD2 not found: $jld2_path"

    data = JLD2.load(jld2_path)

    phi_opt     = vec(data["phi_opt"])
    L           = Float64(data["L_m"])
    P_cont      = Float64(data["P_cont_W"])
    Nt          = Int(data["Nt"])
    time_window = Float64(data["time_window_ps"])
    fiber_name  = String(data["fiber_name"])
    J_before    = Float64(data["J_before"])
    J_after     = Float64(data["J_after"])
    fwhm_fs     = Float64(data["fwhm_fs"])

    @info @sprintf("Loading %s/%s: Nt=%d, time_window=%.1fps, L=%.1fm, P=%.3fW",
        fiber_dir, config_name, Nt, time_window, L, P_cont)

    # Reconstruct EXACT same grid (critical: must match stored Nt and time_window).
    # β_order=3 required because fiber presets have 2 betas (β₂ + β₃);
    # β_order=2 only allows 1 beta and throws ArgumentError.
    uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
        L_fiber=L, P_cont=P_cont, Nt=Nt, time_window=time_window,
        β_order=3, fiber_preset=preset
    )

    # Verify grid consistency with stored phi_opt
    @assert length(phi_opt) == size(uω0, 1) "Grid mismatch: phi_opt length $(length(phi_opt)) vs Nt=$(size(uω0,1))"

    # Z-save points: 50 evenly-spaced positions from 0 to L
    zsave_vec = collect(LinRange(0, fiber["L"], n_zsave))

    # --- Shaped propagation (apply phi_opt, phi in FFT order) ---
    fiber_shaped = deepcopy(fiber)
    fiber_shaped["zsave"] = zsave_vec

    uω0_shaped = uω0 .* exp.(1im .* phi_opt)  # phi_opt in FFT order — no fftshift

    @info @sprintf("Propagating SHAPED: %s/%s (Nt=%d, L=%.1fm)", fiber_dir, config_name, Nt, L)
    sol_shaped = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_shaped, sim)

    # --- Unshaped propagation (flat phase = original uω0) ---
    fiber_unshaped = deepcopy(fiber)
    fiber_unshaped["zsave"] = zsave_vec

    @info @sprintf("Propagating UNSHAPED: %s/%s (Nt=%d, L=%.1fm)", fiber_dir, config_name, Nt, L)
    sol_unshaped = MultiModeNoise.solve_disp_mmf(uω0, fiber_unshaped, sim)

    # --- J(z) at each z-slice (D-02) ---
    # Index as sol["uω_z"][i, :, :] — explicit 2D slice with M dimension
    J_z_shaped   = Float64[spectral_band_cost(sol_shaped["uω_z"][i, :, :],   band_mask)[1] for i in 1:n_zsave]
    J_z_unshaped = Float64[spectral_band_cost(sol_unshaped["uω_z"][i, :, :], band_mask)[1] for i in 1:n_zsave]

    return (
        sol_shaped   = sol_shaped,
        sol_unshaped = sol_unshaped,
        J_z_shaped   = J_z_shaped,
        J_z_unshaped = J_z_unshaped,
        zsave        = zsave_vec,
        fiber_shaped = fiber_shaped,
        fiber_unshaped = fiber_unshaped,
        sim          = sim,
        band_mask    = band_mask,
        phi_opt      = phi_opt,
        uω0          = uω0,
        L            = L,
        P_cont       = P_cont,
        Nt           = Nt,
        fwhm_fs      = fwhm_fs,
        fiber_name   = fiber_name,
        J_before     = J_before,
        J_after      = J_after,
        data         = data,
        time_window  = time_window,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Helper: save propagation result pair to JLD2 (D-14)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pz_save_to_jld2(result, fiber_dir, config_name)

Save shaped and unshaped z-resolved propagation results to JLD2 files in
PZ_RESULTS_DIR. Each file contains:
  - uω_z [Nz × Nt × M]: frequency-domain field at all z-save points
  - ut_z [Nz × Nt × M]: time-domain field at all z-save points
  - J_z  [Nz]: Raman band energy fraction at each z-save point
  - zsave, phi_opt, L_m, P_cont_W, fiber_name, Nt, sim_Dt, band_mask

Saves immediately after computation to allow large arrays to be released.
"""
function pz_save_to_jld2(result, fiber_dir, config_name)
    pairs = [
        ("shaped",   result.sol_shaped,   result.J_z_shaped),
        ("unshaped", result.sol_unshaped, result.J_z_unshaped),
    ]
    for (suffix, sol, J_z) in pairs
        fname = "$(fiber_dir)_$(config_name)_$(suffix)_zsolved.jld2"
        fpath = joinpath(PZ_RESULTS_DIR, fname)
        JLD2.jldsave(fpath;
            uω_z      = sol["uω_z"],
            ut_z      = sol["ut_z"],
            J_z       = J_z,
            zsave     = result.zsave,
            phi_opt   = result.phi_opt,
            L_m       = result.L,
            P_cont_W  = result.P_cont,
            fiber_name= result.fiber_name,
            Nt        = result.Nt,
            sim_Dt    = result.sim["Δt"],
            band_mask = result.band_mask,
            J_before  = result.J_before,
            J_after   = result.J_after,
            fwhm_fs   = result.fwhm_fs,
        )
        @info "Saved $fpath"
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Analysis helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    pz_raman_onset_z(J_z, zsave; factor=2.0) -> Float64 or NaN

Find z-position where J(z) first exceeds factor × J(z=0).
Returns NaN if onset was not reached within the fiber.
"""
function pz_raman_onset_z(J_z, zsave; factor=2.0)
    J0 = J_z[1]
    idx = findfirst(J_z .>= factor * J0)
    isnothing(idx) ? NaN : zsave[idx]
end

"""
    pz_critical_z_shaped(J_z_shaped, J_z_unshaped, zsave) -> Float64 or NaN

For the shaped case, find z-position where J_shaped starts rising significantly
(exceeds the midpoint between J_shaped[1] and J_unshaped[end]).
Returns NaN if no significant rise was found.
"""
function pz_critical_z_shaped(J_z_shaped, J_z_unshaped, zsave)
    threshold = J_z_shaped[1] + 0.1 * (J_z_unshaped[end] - J_z_shaped[1])
    threshold = max(threshold, 2 * J_z_shaped[1])  # at least 2x initial
    idx = findfirst(J_z_shaped .>= threshold)
    isnothing(idx) ? NaN : zsave[idx]
end

end  # include guard

# ─────────────────────────────────────────────────────────────────────────────
# 1. Figure: Raman fraction vs z (physics_10_01)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pz_fig_raman_fraction(all_results, configs)

Figure 10_01: 2×3 subplot grid (rows: SMF-28, HNLF; columns: 3 configs each).
Each panel: semilogy J(z) for shaped (blue) and unshaped (vermillion) vs z [m].
Annotates Raman onset z-position with a vertical dashed line.
"""
function pz_fig_raman_fraction(all_results, configs)
    fig, axes = subplots(2, 3, figsize=(14, 8))
    fig.suptitle("Raman band energy evolution along fiber", fontsize=14, fontweight="bold")

    smf_configs = [c for c in configs if c.fiber_type == "SMF-28"]
    hnlf_configs = [c for c in configs if c.fiber_type == "HNLF"]

    rows = [smf_configs, hnlf_configs]
    row_labels = ["SMF-28", "HNLF"]

    for (row_idx, (row_cfgs, row_label)) in enumerate(zip(rows, row_labels))
        for (col_idx, cfg) in enumerate(row_cfgs)
            ax = axes[row_idx, col_idx]
            result = all_results[cfg.config]

            zsave = result.zsave
            J_s = result.J_z_shaped
            J_u = result.J_z_unshaped

            # Clamp to avoid log(0)
            J_s_plot = max.(J_s, 1e-15)
            J_u_plot = max.(J_u, 1e-15)

            ax.semilogy(zsave, J_u_plot, color=COLOR_OUTPUT, linewidth=2.0,
                label="Unshaped", zorder=3)
            ax.semilogy(zsave, J_s_plot, color=COLOR_INPUT, linewidth=2.0,
                label="Shaped", zorder=4)

            # Raman onset line for unshaped
            z_onset_u = pz_raman_onset_z(J_u, zsave)
            if !isnan(z_onset_u)
                ax.axvline(x=z_onset_u, color=COLOR_OUTPUT, ls="--", alpha=0.7,
                    linewidth=1.2, label=@sprintf("Onset z=%.2fm", z_onset_u))
            end

            # Raman onset line for shaped
            z_onset_s = pz_raman_onset_z(J_s, zsave)
            if !isnan(z_onset_s)
                ax.axvline(x=z_onset_s, color=COLOR_INPUT, ls="--", alpha=0.7,
                    linewidth=1.2, label=@sprintf("Onset z=%.2fm", z_onset_s))
            end

            # Panel annotation
            J_before_dB = round(10*log10(max(result.J_before, 1e-15)), digits=1)
            J_after_dB  = round(10*log10(max(result.J_after,  1e-15)), digits=1)
            J_end_shaped_dB   = round(10*log10(max(J_s[end], 1e-15)), digits=1)
            J_end_unshaped_dB = round(10*log10(max(J_u[end], 1e-15)), digits=1)

            title_str = cfg.label
            ax.set_title(title_str, fontsize=10, fontweight="bold")

            # Compact annotation box in upper right
            ann_text = @sprintf("J₀=%.0fdB\nShaped: %.0fdB\nUnshaped: %.0fdB",
                J_before_dB, J_end_shaped_dB, J_end_unshaped_dB)
            ax.text(0.97, 0.97, ann_text, transform=ax.transAxes,
                fontsize=7.5, va="top", ha="right",
                bbox=Dict("boxstyle"=>"round,pad=0.3", "fc"=>"white", "alpha"=>0.8))

            ax.set_xlabel("z [m]", fontsize=10)
            ax.set_ylabel("J(z) = E_Raman/E_total", fontsize=9)
            ax.grid(true, alpha=0.3)

            # Row label on left column only
            if col_idx == 1
                ax.set_ylabel(@sprintf("%s\nJ(z) = E_Raman/E_total", row_label), fontsize=9)
            end

            # Legend on first panel only
            if row_idx == 1 && col_idx == 1
                ax.legend(fontsize=8, loc="lower right")
            end
        end
    end

    fig.tight_layout()
    fpath = joinpath(PZ_FIGURE_DIR, "physics_10_01_raman_fraction_vs_z.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info "Saved $fpath"
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# 2. Figure: Spectral evolution comparison (physics_10_02)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pz_fig_spectral_evolution(all_results, rep_configs)

Figure 10_02: 2×2 grid — 2 representative configs (1 SMF-28 + 1 HNLF), comparing
shaped vs unshaped spectral evolution. Left column: unshaped; right column: shaped.
"""
function pz_fig_spectral_evolution(all_results, rep_configs)
    fig, axes = subplots(2, 2, figsize=(12, 10))
    fig.suptitle("Spectral evolution: shaped vs unshaped", fontsize=14, fontweight="bold")

    col_titles = ["Unshaped", "Shaped"]
    for (row_idx, cfg) in enumerate(rep_configs)
        result = all_results[cfg.config]

        for (col_idx, (sol, fiber)) in enumerate([
            (result.sol_unshaped, result.fiber_unshaped),
            (result.sol_shaped,   result.fiber_shaped),
        ])
            ax = axes[row_idx, col_idx]
            _, _, im = plot_spectral_evolution(sol, result.sim, fiber;
                mode_idx=1, dB_range=40.0, ax=ax, fig=fig)

            title = @sprintf("%s — %s", col_titles[col_idx], cfg.label)
            ax.set_title(title, fontsize=10, fontweight="bold")

            if row_idx == 2
                # Add colorbar below bottom row panels
                cb = fig.colorbar(im, ax=ax, orientation="horizontal",
                    fraction=0.05, pad=0.15)
                cb.set_label("Power [dB]", fontsize=9)
            end
        end
    end

    fig.tight_layout()
    fpath = joinpath(PZ_FIGURE_DIR, "physics_10_02_spectral_evolution_comparison.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info "Saved $fpath"
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. Figure: Temporal evolution comparison (physics_10_03)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pz_fig_temporal_evolution(all_results, rep_configs)

Figure 10_03: 2×2 grid — 2 representative configs, comparing shaped vs unshaped
temporal evolution. Left column: unshaped; right column: shaped.
"""
function pz_fig_temporal_evolution(all_results, rep_configs)
    fig, axes = subplots(2, 2, figsize=(12, 10))
    fig.suptitle("Temporal evolution: shaped vs unshaped", fontsize=14, fontweight="bold")

    col_titles = ["Unshaped", "Shaped"]
    for (row_idx, cfg) in enumerate(rep_configs)
        result = all_results[cfg.config]

        for (col_idx, (sol, fiber)) in enumerate([
            (result.sol_unshaped, result.fiber_unshaped),
            (result.sol_shaped,   result.fiber_shaped),
        ])
            ax = axes[row_idx, col_idx]
            _, _, im = plot_temporal_evolution(sol, result.sim, fiber;
                mode_idx=1, dB_range=40.0, ax=ax, fig=fig)

            title = @sprintf("%s — %s", col_titles[col_idx], cfg.label)
            ax.set_title(title, fontsize=10, fontweight="bold")

            if row_idx == 2
                cb = fig.colorbar(im, ax=ax, orientation="horizontal",
                    fraction=0.05, pad=0.15)
                cb.set_label("Power [dB]", fontsize=9)
            end
        end
    end

    fig.tight_layout()
    fpath = joinpath(PZ_FIGURE_DIR, "physics_10_03_temporal_evolution_comparison.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info "Saved $fpath"
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# 4. Figure: N_sol regime comparison (physics_10_04)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pz_fig_nsol_regime(all_results, configs, nsol_values)

Figure 10_04: 1×3 subplot grid bucketing configs by N_sol regime.
Each panel overlays J(z) for all configs in that bucket (both fibers).
Shaped: solid lines; unshaped: dashed lines.
"""
function pz_fig_nsol_regime(all_results, configs, nsol_values)
    # Bucket by N_sol: low (~1.3), medium (~2.6), high (~3.6-6.3)
    # Thresholds: N <= 2.0 → low, 2.0 < N <= 3.0 → medium, N > 3.0 → high
    buckets = [
        (label="Low N_sol (N ≤ 2.0)",   filter=N -> N <= 2.0,          xlim_note=""),
        (label="Medium N_sol (2.0 < N ≤ 3.0)", filter=N -> 2.0 < N <= 3.0, xlim_note=""),
        (label="High N_sol (N > 3.0)",   filter=N -> N > 3.0,           xlim_note=""),
    ]

    # SMF-28 colors: blue tones; HNLF colors: red tones
    smf_colors = ["#0072B2", "#56B4E9", "#003F7F"]  # dark blue, sky blue, navy
    hnlf_colors = ["#D55E00", "#CC79A7", "#8B0000"]  # vermillion, pink, dark red
    smf_ci = [1]; hnlf_ci = [1]

    fig, axes = subplots(1, 3, figsize=(15, 5))
    fig.suptitle("Raman evolution by soliton number regime", fontsize=14, fontweight="bold")

    for (panel_idx, bucket) in enumerate(buckets)
        ax = axes[panel_idx]
        bucket_has_data = false

        smf_ci[1] = 1
        hnlf_ci[1] = 1

        for (cfg, N_sol) in zip(configs, nsol_values)
            bucket.filter(N_sol) || continue
            bucket_has_data = true
            result = all_results[cfg.config]
            zsave = result.zsave

            J_s = max.(result.J_z_shaped,   1e-15)
            J_u = max.(result.J_z_unshaped, 1e-15)

            if cfg.fiber_type == "SMF-28"
                color = smf_colors[min(smf_ci[1], length(smf_colors))]
                smf_ci[1] += 1
            else
                color = hnlf_colors[min(hnlf_ci[1], length(hnlf_colors))]
                hnlf_ci[1] += 1
            end

            lbl_u = @sprintf("%s unshaped", cfg.label)
            lbl_s = @sprintf("%s shaped",   cfg.label)
            ax.semilogy(zsave, J_u, color=color, linestyle="--",
                linewidth=1.8, alpha=0.85, label=lbl_u)
            ax.semilogy(zsave, J_s, color=color, linestyle="-",
                linewidth=2.0, alpha=1.0, label=lbl_s)
        end

        ax.set_title(bucket.label, fontsize=11, fontweight="bold")
        ax.set_xlabel("z [m]", fontsize=10)
        ax.set_ylabel("J(z) = E_Raman/E_total", fontsize=9)
        ax.grid(true, alpha=0.3)
        if bucket_has_data
            ax.legend(fontsize=7.5, loc="upper left", ncol=1)
        end
    end

    # Add unified legend note
    fig.text(0.5, 0.01,
        "Solid lines: shaped (phi_opt applied) — Dashed lines: unshaped (flat phase)\n" *
        "Blue tones: SMF-28 — Red/pink tones: HNLF",
        ha="center", fontsize=9, style="italic")

    fig.tight_layout(rect=[0, 0.06, 1, 1])
    fpath = joinpath(PZ_FIGURE_DIR, "physics_10_04_nsol_regime_comparison.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info "Saved $fpath"
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# 5. Findings document
# ─────────────────────────────────────────────────────────────────────────────

"""
    pz_write_findings(all_results, configs, nsol_values)

Write PHASE10_ZRESOLVED_FINDINGS.md to results/raman/ with:
  - Per-config table: Raman onset z, critical z, J_before, J_after
  - N_sol regime observations
  - Preliminary hypothesis from z-resolved observations
"""
function pz_write_findings(all_results, configs, nsol_values)
    fpath = joinpath("results", "raman", "PHASE10_ZRESOLVED_FINDINGS.md")

    lines = String[]

    push!(lines, "# Phase 10 Z-Resolved Propagation Findings\n")
    push!(lines, "**Date:** $(Dates.format(now(), "yyyy-mm-dd"))")
    push!(lines, "**Script:** `scripts/propagation_z_resolved.jl`")
    push!(lines, "**Data:** 12 JLD2 files in `results/raman/phase10/`\n")
    push!(lines, "---\n")

    push!(lines, "## 1. Abstract\n")
    push!(lines, "Phase 9 found that 84% of Raman suppression arises from " *
        "\"configuration-specific nonlinear interference\" — effects that require " *
        "propagation-resolved diagnostics to understand. This phase runs z-resolved " *
        "forward propagations for 6 representative configurations (3 SMF-28 + 3 HNLF) " *
        "spanning soliton numbers N_sol = 1.3 to 6.3, with 50 z-save points per fiber. " *
        "Each configuration was propagated with flat phase (unshaped) and with phi_opt " *
        "(shaped) to reveal WHERE Raman energy builds up and how the optimizer's phase " *
        "delays or prevents this buildup.\n")

    push!(lines, "## 2. Per-Configuration Results\n")

    # Table header
    push!(lines, "| Configuration | N_sol | J₀ (dB) | J_after shaped (dB) | J_end unshaped (dB) | Onset z unshaped (m) | Onset z shaped (m) | Suppression gain (dB) |")
    push!(lines, "|--------------|-------|---------|---------------------|---------------------|----------------------|---------------------|----------------------|")

    for (cfg, N_sol) in zip(configs, nsol_values)
        result = all_results[cfg.config]
        J0_dB    = round(10*log10(max(result.J_before, 1e-15)), digits=1)
        Js_dB    = round(10*log10(max(result.J_z_shaped[end],   1e-15)), digits=1)
        Ju_dB    = round(10*log10(max(result.J_z_unshaped[end], 1e-15)), digits=1)

        z_onset_u = pz_raman_onset_z(result.J_z_unshaped, result.zsave)
        z_onset_s = pz_raman_onset_z(result.J_z_shaped,   result.zsave)

        z_onset_u_str = isnan(z_onset_u) ? "> L" : @sprintf("%.3f", z_onset_u)
        z_onset_s_str = isnan(z_onset_s) ? "> L" : @sprintf("%.3f", z_onset_s)

        supp_gain = round(Ju_dB - Js_dB, digits=1)

        push!(lines, @sprintf("| %s | %.1f | %.1f | %.1f | %.1f | %s | %s | %.1f |",
            cfg.label, N_sol, J0_dB, Js_dB, Ju_dB,
            z_onset_u_str, z_onset_s_str, supp_gain))
    end
    push!(lines, "")

    push!(lines, "## 3. Raman Onset Analysis\n")
    push!(lines, "\"Raman onset\" is defined as the z-position where J(z) first exceeds " *
        "2× its initial value J(z=0). A value of '> L' means onset was not reached " *
        "within the fiber length.\n")

    for (cfg, N_sol) in zip(configs, nsol_values)
        result = all_results[cfg.config]
        z_onset_u = pz_raman_onset_z(result.J_z_unshaped, result.zsave)
        z_onset_s = pz_raman_onset_z(result.J_z_shaped,   result.zsave)

        push!(lines, @sprintf("### %s (N_sol = %.1f, L = %.1fm)", cfg.label, N_sol, result.L))

        if isnan(z_onset_u)
            push!(lines, "- **Unshaped:** Raman onset not reached within fiber (low initial J or short fiber).")
        else
            push!(lines, @sprintf("- **Unshaped:** Raman onset at z = %.3f m (%.1f%% of fiber length)",
                z_onset_u, 100*z_onset_u/result.L))
        end
        if isnan(z_onset_s)
            push!(lines, "- **Shaped:** Raman onset not reached within fiber (effective suppression).")
        else
            push!(lines, @sprintf("- **Shaped:** Raman onset at z = %.3f m (%.1f%% of fiber length)",
                z_onset_s, 100*z_onset_s/result.L))
        end

        # Special analysis for the long-fiber degraded case
        if cfg.config == "L5m_P0.2W"
            J_s = result.J_z_shaped
            z_crit = pz_critical_z_shaped(J_s, result.J_z_unshaped, result.zsave)
            if !isnan(z_crit)
                push!(lines, @sprintf("- **Critical z (shaped):** J_shaped starts rising significantly at z = %.2f m.", z_crit))
                push!(lines, "  This is the 'breakdown point' where the shaped pulse's Raman suppression starts to fail.")
            end
        end
        push!(lines, "")
    end

    push!(lines, "## 4. N_sol Regime Observations\n")

    push!(lines, "### Low N_sol (N ≤ 2.0)\n")
    low_N_cfgs = [(cfg, N) for (cfg, N) in zip(configs, nsol_values) if N <= 2.0]
    for (cfg, N) in low_N_cfgs
        result = all_results[cfg.config]
        Js_dB = round(10*log10(max(result.J_z_shaped[end],   1e-15)), digits=1)
        Ju_dB = round(10*log10(max(result.J_z_unshaped[end], 1e-15)), digits=1)
        push!(lines, @sprintf("- **%s** (N=%.1f): shaped=%.0fdB, unshaped=%.0fdB",
            cfg.label, N, Js_dB, Ju_dB))
    end
    push!(lines, "\nIn the low-N regime, Raman scattering is inherently weak " *
        "(the unshaped pulse may not accumulate significant Raman energy). " *
        "The optimizer still finds phases that suppress residual Raman, " *
        "but the absolute gains are limited by the weak nonlinearity.\n")

    push!(lines, "### Medium N_sol (2.0 < N ≤ 3.0)\n")
    med_N_cfgs = [(cfg, N) for (cfg, N) in zip(configs, nsol_values) if 2.0 < N <= 3.0]
    for (cfg, N) in med_N_cfgs
        result = all_results[cfg.config]
        Js_dB = round(10*log10(max(result.J_z_shaped[end],   1e-15)), digits=1)
        Ju_dB = round(10*log10(max(result.J_z_unshaped[end], 1e-15)), digits=1)
        push!(lines, @sprintf("- **%s** (N=%.1f): shaped=%.0fdB, unshaped=%.0fdB",
            cfg.label, N, Js_dB, Ju_dB))
    end
    push!(lines, "\nThe medium-N regime (around the N=2 soliton fission threshold) " *
        "is where the optimizer typically achieves its highest suppression ratios. " *
        "Z-resolved data reveals whether Raman energy is suppressed early (z-dependent " *
        "prevention) or late (redistribution at the fiber end).\n")

    push!(lines, "### High N_sol (N > 3.0)\n")
    high_N_cfgs = [(cfg, N) for (cfg, N) in zip(configs, nsol_values) if N > 3.0]
    for (cfg, N) in high_N_cfgs
        result = all_results[cfg.config]
        Js_dB = round(10*log10(max(result.J_z_shaped[end],   1e-15)), digits=1)
        Ju_dB = round(10*log10(max(result.J_z_unshaped[end], 1e-15)), digits=1)
        push!(lines, @sprintf("- **%s** (N=%.1f): shaped=%.0fdB, unshaped=%.0fdB",
            cfg.label, N, Js_dB, Ju_dB))
    end
    push!(lines, "\nIn the high-N regime, soliton fission occurs early in the fiber, " *
        "and the Raman self-frequency shift (SSFS) can dominate. The optimizer must " *
        "reshape the pulse to prevent the sub-pulses from accumulating sufficient " *
        "nonlinear phase for SSFS to set in.\n")

    push!(lines, "## 5. Long-Fiber Degradation: SMF-28 5m\n")
    push!(lines, "The SMF-28 L5m_P0.2W configuration achieves only -36.8 dB shaped " *
        "vs -77.6 dB for the same N_sol at L=0.5m — a 40 dB degradation at longer " *
        "fiber length. Z-resolved data answers: at what z does suppression break down?\n")

    if haskey(all_results, "L5m_P0.2W")
        result = all_results["L5m_P0.2W"]
        J_s = result.J_z_shaped
        z_crit = pz_critical_z_shaped(J_s, result.J_z_unshaped, result.zsave)
        if !isnan(z_crit)
            push!(lines, @sprintf("**Critical z (breakdown point):** z = %.2f m out of %.1f m total.",
                z_crit, result.L))
            J_min_dB = 10*log10(max(minimum(J_s), 1e-15))
            J_end_dB = 10*log10(max(J_s[end], 1e-15))
            push!(lines, @sprintf("Beyond this point, the shaped pulse's Raman fraction grows from ~%.1f dB to ~%.1f dB.\n",
                J_min_dB, J_end_dB))
        else
            push!(lines, "No clear critical z detected — shaped J(z) remains relatively flat.\n")
        end
    end

    push!(lines, "## 6. Preliminary Hypothesis\n")
    push!(lines, "Based on the z-resolved observations:\n")
    push!(lines, "1. **Delayed onset hypothesis:** The optimal spectral phase delays " *
        "the z-position of Raman energy accumulation rather than preventing it entirely. " *
        "This is consistent with temporal pulse stretching (16% of suppression from peak " *
        "power reduction, found in Phase 9) creating a longer nonlinear interaction region " *
        "before Raman becomes significant.\n")
    push!(lines, "2. **Redistribution hypothesis:** The optimizer may redistribute " *
        "Raman energy back into the pump band near the fiber end. If J_shaped(z) " *
        "rises in the middle of the fiber but falls before the end, this would indicate " *
        "a coherent energy transfer mechanism that cannot be seen from input/output analysis alone.\n")
    push!(lines, "3. **Regime separation:** The N_sol > 2 vs N_sol ≤ 2 boundary (best " *
        "clustering variable from Phase 9) should appear as a qualitative change in z-dynamics: " *
        "above the threshold, the J(z) curve is more complex (possible non-monotonic evolution); " *
        "below it, the curve may be nearly monotonic.\n")

    push!(lines, "---\n")
    push!(lines, "*Generated by Phase 10 z-resolved propagation pipeline. " *
        "Data: results/raman/phase10/. Script: scripts/propagation_z_resolved.jl.*\n")

    open(fpath, "w") do io
        for line in lines
            println(io, line)
        end
    end
    @info "Saved $fpath"
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# Main execution block
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__

    @info "========================================================================"
    @info " Phase 10.1: Z-Resolved Propagation Diagnostics"
    @info "========================================================================"

    mkpath(PZ_RESULTS_DIR)
    mkpath(PZ_FIGURE_DIR)

    # ─────────────────────────────────────────────────────────────────────────
    # Section 1: Run all 6 × 2 propagations
    # ─────────────────────────────────────────────────────────────────────────

    @info "Section 1: Running 12 z-resolved propagations (6 configs × 2 conditions)"

    all_results = Dict{String, Any}()
    nsol_values = Float64[]

    for cfg in PZ_CONFIGS
        @info @sprintf("━━━ Config: %s ━━━", cfg.label)

        result = pz_load_and_repropagate(cfg.fiber_dir, cfg.config, cfg.preset;
            n_zsave=PZ_N_ZSAVE)

        N_sol = pz_soliton_number(result.data, cfg.preset)
        push!(nsol_values, N_sol)

        @info @sprintf("  N_sol = %.2f, J_before = %.1f dB, J_after = %.1f dB",
            N_sol,
            10*log10(max(result.J_before, 1e-15)),
            10*log10(max(result.J_after,  1e-15)))
        @info @sprintf("  J_z_shaped[end]   = %.1f dB",
            10*log10(max(result.J_z_shaped[end],   1e-15)))
        @info @sprintf("  J_z_unshaped[end] = %.1f dB",
            10*log10(max(result.J_z_unshaped[end], 1e-15)))

        # Save JLD2 immediately to release large array memory
        pz_save_to_jld2(result, cfg.fiber_dir, cfg.config)

        all_results[cfg.config] = result
    end

    @info @sprintf("All 12 propagations complete. JLD2 files: %s",
        PZ_RESULTS_DIR)

    # ─────────────────────────────────────────────────────────────────────────
    # Section 2: Generate figures
    # ─────────────────────────────────────────────────────────────────────────

    @info "Section 2: Generating 4 diagnostic figures"

    # Figure 1: Raman fraction vs z (all 6 configs)
    @info "  Figure 10_01: Raman fraction vs z"
    pz_fig_raman_fraction(all_results, PZ_CONFIGS)

    # Representative configs for evolution heatmaps:
    # SMF-28 N=2.6 (index 2) + HNLF N=3.6 (index 5) — medium-N, good suppression
    rep_configs = [PZ_CONFIGS[2], PZ_CONFIGS[5]]

    # Figure 2: Spectral evolution comparison
    @info "  Figure 10_02: Spectral evolution comparison"
    pz_fig_spectral_evolution(all_results, rep_configs)

    # Figure 3: Temporal evolution comparison
    @info "  Figure 10_03: Temporal evolution comparison"
    pz_fig_temporal_evolution(all_results, rep_configs)

    # Figure 4: N_sol regime comparison
    @info "  Figure 10_04: N_sol regime comparison"
    pz_fig_nsol_regime(all_results, PZ_CONFIGS, nsol_values)

    # ─────────────────────────────────────────────────────────────────────────
    # Section 3: Write findings document
    # ─────────────────────────────────────────────────────────────────────────

    @info "Section 3: Writing findings document"
    pz_write_findings(all_results, PZ_CONFIGS, nsol_values)

    # ─────────────────────────────────────────────────────────────────────────
    # Run summary
    # ─────────────────────────────────────────────────────────────────────────

    n_jld2 = length(filter(f -> endswith(f, ".jld2"), readdir(PZ_RESULTS_DIR)))

    println()
    println("┌─────────────────────────────────────────────────────────────────┐")
    println("│  Phase 10.1 Z-Resolved Propagation Complete                    │")
    println("├─────────────────────────────────────────────────────────────────┤")
    println(@sprintf("│  JLD2 files:  %2d  (in %s)", n_jld2, PZ_RESULTS_DIR))
    println("│  Figures:      4  (physics_10_01 through physics_10_04)        │")
    println("│  Findings:         results/raman/PHASE10_ZRESOLVED_FINDINGS.md │")
    println("└─────────────────────────────────────────────────────────────────┘")

end  # if abspath(PROGRAM_FILE) == @__FILE__
