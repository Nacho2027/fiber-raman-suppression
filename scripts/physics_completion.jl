"""
Classical Physics Completion — Phase 11.01

Ties together all outstanding questions from Phase 10 with three analysis tasks:

  A. Multi-start z-dynamics: Re-propagate all 10 multi-start phi_opt profiles
     (SMF-28 L=2m P=0.2W) with 50 z-save points each. Baseline (flat phase)
     propagated once for consistency check. Reveals whether structurally different
     solutions (mean phi_opt correlation 0.109) produce similar or divergent J(z).

  B. Spectral divergence: For each of the 6 Phase 10 configs, compute D(z,f)
     = S_shaped/S_unshaped in dB at each z-slice. Find z-position where any
     frequency bin first exceeds 3 dB divergence. Visualized as 2x3 heatmap grid.

  C. Hypothesis formalization (H1, H2):
     H1 — spectrally distributed suppression: compare critical bands between
          SMF-28 and HNLF (Phase 10 ablation data).
     H2 — sub-THz spectral features: quantify 3 dB tolerance width from Phase 10
          shift perturbation data via parabolic fit. Compare with Raman bandwidth.

Figures produced (all -> results/images/):
  physics_11_01_multistart_jz_overlay.png         — 10 J(z) trajectories, clustered
  physics_11_02_jz_cluster_comparison.png          — J(z) vs phi_opt correlation matrices
  physics_11_03_spectral_divergence_heatmaps.png   — 6-panel D(z,f) heatmaps
  physics_11_04_h1_critical_bands_comparison.png   — SMF-28 vs HNLF per-band bar charts
  physics_11_05_h2_shift_scale_characterization.png — shift sensitivity + parabolic fit

Data saved to results/raman/phase11/ (20 multi-start JLD2 + 6 spectral divergence + 1 trajectory).

Anti-patterns to avoid:
  - Always pass β_order=3 (Unicode keyword) to setup_raman_problem
  - Always deepcopy(fiber) before setting fiber["zsave"]
  - JLD2 key for z-resolved fields is "uω_z" (Unicode), not "uomega_z"
  - phi_opt and uomega0 are in FFT order — no fftshift before applying exp.(1im .* phi_opt)
  - fftshift for DISPLAY only (plotting frequency axes)
  - sim_Dt is in picoseconds: fftfreq(Nt, 1/Dt_ps) gives THz
  - No @sprintf with * string concatenation (fails in Julia 1.12 at macro expansion)
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

# ─────────────────────────────────────────────────────────────────────────────
# Includes — use absolute paths to avoid cwd sensitivity
# ─────────────────────────────────────────────────────────────────────────────

const _PC_SCRIPT_DIR   = dirname(abspath(@__FILE__))
const _PC_PROJECT_ROOT = dirname(_PC_SCRIPT_DIR)  # scripts/ → project root

include(joinpath(_PC_SCRIPT_DIR, "common.jl"))
include(joinpath(_PC_SCRIPT_DIR, "visualization.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Include guard + constants (PC_ prefix)
# ─────────────────────────────────────────────────────────────────────────────

if !(@isdefined _PC_SCRIPT_LOADED)
const _PC_SCRIPT_LOADED = true

const PC_N_ZSAVE      = 50
const PC_RESULTS_DIR  = joinpath(_PC_PROJECT_ROOT, "results", "raman", "phase11")
const PC_FIGURE_DIR   = joinpath(_PC_PROJECT_ROOT, "results", "images")
const PC_PHASE10_DIR  = joinpath(_PC_PROJECT_ROOT, "results", "raman", "phase10")
const PC_MULTISTART_DIR = joinpath(_PC_PROJECT_ROOT, "results", "raman", "sweeps", "multistart")

# 6 Phase 10 configs that have paired shaped/unshaped JLD2 files
const PC_PHASE10_TAGS = [
    "smf28_L0.5m_P0.05W",
    "smf28_L0.5m_P0.2W",
    "smf28_L5m_P0.2W",
    "hnlf_L1m_P0.005W",
    "hnlf_L1m_P0.01W",
    "hnlf_L0.5m_P0.03W",
]

# Human-readable labels for 6 configs (parallel to PC_PHASE10_TAGS)
const PC_PHASE10_LABELS = [
    "SMF-28  L=0.5m  P=0.05W",
    "SMF-28  L=0.5m  P=0.2W",
    "SMF-28  L=5m    P=0.2W",
    "HNLF    L=1m    P=0.005W",
    "HNLF    L=1m    P=0.01W",
    "HNLF    L=0.5m  P=0.03W",
]

# Raman gain bandwidth (THz) — from Phase 9 research
const PC_RAMAN_BW_THZ = 13.2

# ─────────────────────────────────────────────────────────────────────────────
# A. Multi-start z-propagation helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    pc_load_multistart_and_propagate(start_idx; n_zsave=PC_N_ZSAVE)

Load phi_opt for multi-start index `start_idx` (1–10), reconstruct the exact
simulation grid, and propagate both shaped and unshaped pulses with `n_zsave`
z-save points. Saves both propagation results immediately to phase11 JLD2 files.

All 10 starts use identical fiber/pulse parameters (SMF-28, L=2m, P=0.2W,
Nt=8192, time_window=40ps) — verified from stored JLD2 metadata.

# Returns
NamedTuple: (J_z_shaped, J_z_flat, zsave, phi_opt, start_idx, sim, Nt)
"""
function pc_load_multistart_and_propagate(start_idx::Int; n_zsave::Int=PC_N_ZSAVE)
    # PRECONDITIONS
    @assert 1 <= start_idx <= 10 "start_idx must be 1..10, got $start_idx"

    jld2_path = joinpath(PC_MULTISTART_DIR,
        "start_$(lpad(string(start_idx), 2, '0'))",
        "opt_result.jld2")
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

    @info @sprintf("PC start_%02d: L=%.1fm, P=%.2fW, Nt=%d, tw=%.0fps, J_after=%.1fdB",
        start_idx, L, P_cont, Nt, time_window, 10*log10(max(J_after, 1e-20)))

    # Reconstruct grid — beta_order=3 required for fiber presets with 2 betas (β₂+β₃)
    uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
        L_fiber=L, P_cont=P_cont, Nt=Nt, time_window=time_window,
        β_order=3, fiber_preset=:SMF28
    )

    @assert length(phi_opt) == size(uω0, 1) "Grid mismatch: phi_opt=$(length(phi_opt)) vs Nt=$(size(uω0,1))"

    zsave_vec = collect(LinRange(0.0, L, n_zsave))

    # --- Shaped propagation ---
    fiber_shaped = deepcopy(fiber)
    fiber_shaped["zsave"] = zsave_vec
    uω0_shaped = uω0 .* exp.(1im .* phi_opt)  # FFT order — no fftshift
    @info @sprintf("  Propagating SHAPED start_%02d ...", start_idx)
    sol_shaped = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_shaped, sim)
    J_z_shaped = Float64[spectral_band_cost(sol_shaped["uω_z"][i, :, :], band_mask)[1] for i in 1:n_zsave]

    # --- Flat (unshaped) propagation ---
    fiber_flat = deepcopy(fiber)
    fiber_flat["zsave"] = zsave_vec
    @info @sprintf("  Propagating FLAT (unshaped) start_%02d ...", start_idx)
    sol_flat = MultiModeNoise.solve_disp_mmf(uω0, fiber_flat, sim)
    J_z_flat = Float64[spectral_band_cost(sol_flat["uω_z"][i, :, :], band_mask)[1] for i in 1:n_zsave]

    # --- Save immediately (shaped and unshaped) ---
    for (suffix, sol, Jz) in [
        ("shaped",   sol_shaped, J_z_shaped),
        ("unshaped", sol_flat,   J_z_flat),
    ]
        fname = joinpath(PC_RESULTS_DIR,
            "multistart_start_$(lpad(string(start_idx), 2, '0'))_$(suffix)_zsolved.jld2")
        JLD2.jldsave(fname;
            uω_z      = sol["uω_z"],
            ut_z      = sol["ut_z"],
            J_z       = Jz,
            zsave     = zsave_vec,
            phi_opt   = phi_opt,
            Nt        = Nt,
            L_m       = L,
            P_cont_W  = P_cont,
            fiber_name= fiber_name,
            sim_Dt    = sim["Δt"],
            band_mask = band_mask,
            J_before  = J_before,
            J_after   = J_after,
            start_idx = start_idx,
        )
        @info @sprintf("  Saved %s", fname)
    end

    # POSTCONDITIONS
    @assert length(J_z_shaped) == n_zsave "J_z_shaped length mismatch"
    @assert length(J_z_flat)   == n_zsave "J_z_flat length mismatch"
    @assert all(isfinite.(J_z_shaped)) "Non-finite values in J_z_shaped"
    @assert all(isfinite.(J_z_flat))   "Non-finite values in J_z_flat"

    return (
        J_z_shaped = J_z_shaped,
        J_z_flat   = J_z_flat,
        zsave      = zsave_vec,
        phi_opt    = phi_opt,
        start_idx  = start_idx,
        sim        = sim,
        Nt         = Nt,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# B. J(z) trajectory clustering
# ─────────────────────────────────────────────────────────────────────────────

"""
    pc_cluster_jz_trajectories(all_results) -> NamedTuple

Compute 10x10 pairwise Pearson correlation matrices for:
  - J(z) trajectories in dB space
  - phi_opt profiles (normalized to zero mean, unit norm)

Saves to multistart_trajectory_analysis.jld2.

# Returns
NamedTuple: (jz_corr_matrix, phi_corr_matrix, all_jz_shaped_dB, zsave, J_final_dB)
"""
function pc_cluster_jz_trajectories(all_results)
    n = length(all_results)
    @assert n == 10 "Expected 10 results, got $n"

    # Convert J(z) trajectories to dB
    all_jz_dB = [10.0 .* log10.(max.(r.J_z_shaped, 1e-20)) for r in all_results]
    zsave_ref  = all_results[1].zsave

    # 10x10 Pearson correlation matrix for J(z) trajectories
    jz_matrix = hcat(all_jz_dB...)  # (50, 10)
    jz_corr   = cor(jz_matrix)      # (10, 10), Statistics.cor on columns

    # 10x10 correlation matrix for phi_opt profiles
    phi_opts = [r.phi_opt for r in all_results]
    # Normalize each phi_opt: subtract mean, divide by norm
    phi_norm = [phi .- mean(phi) for phi in phi_opts]
    phi_norm = [p ./ (norm(p) + 1e-30) for p in phi_norm]

    phi_corr = zeros(Float64, n, n)
    for i in 1:n
        for j in 1:n
            phi_corr[i, j] = dot(phi_norm[i], phi_norm[j])
        end
    end

    J_final_dB = [10.0 * log10(max(r.J_z_shaped[end], 1e-20)) for r in all_results]

    # Save
    fpath = joinpath(PC_RESULTS_DIR, "multistart_trajectory_analysis.jld2")
    JLD2.jldsave(fpath;
        jz_corr_matrix    = jz_corr,
        phi_corr_matrix   = phi_corr,
        all_jz_shaped_dB  = all_jz_dB,
        zsave             = zsave_ref,
        J_final_dB        = J_final_dB,
    )
    @info @sprintf("Saved trajectory analysis: %s", fpath)

    return (
        jz_corr_matrix   = jz_corr,
        phi_corr_matrix  = phi_corr,
        all_jz_shaped_dB = all_jz_dB,
        zsave            = zsave_ref,
        J_final_dB       = J_final_dB,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# C. Spectral divergence analysis
# ─────────────────────────────────────────────────────────────────────────────

"""
    pc_spectral_divergence(fiber_tag) -> NamedTuple

Load shaped and unshaped z-resolved JLD2 files from Phase 10, compute the
spectral difference D(z,f) = 10*log10(S_shaped/S_unshaped) at each z-slice,
and identify where D first exceeds ±3 dB at any frequency.

# Arguments
- `fiber_tag`: one of PC_PHASE10_TAGS (e.g. "smf28_L0.5m_P0.2W")

# Returns
NamedTuple: (D_z_f, fs_THz, zsave, z_diverge_3dB, fiber_tag)
"""
function pc_spectral_divergence(fiber_tag::String)
    shaped_path   = joinpath(PC_PHASE10_DIR, "$(fiber_tag)_shaped_zsolved.jld2")
    unshaped_path = joinpath(PC_PHASE10_DIR, "$(fiber_tag)_unshaped_zsolved.jld2")
    @assert isfile(shaped_path)   "Shaped JLD2 not found: $shaped_path"
    @assert isfile(unshaped_path) "Unshaped JLD2 not found: $unshaped_path"

    d_s = JLD2.load(shaped_path)
    d_u = JLD2.load(unshaped_path)

    Nt     = Int(d_s["Nt"])
    Dt_ps  = Float64(d_s["sim_Dt"])   # picoseconds
    zsave  = vec(d_s["zsave"])
    n_zsave = length(zsave)

    # Frequency axis in THz (fftshifted for display)
    fs_THz = fftshift(fftfreq(Nt, 1.0 / Dt_ps))   # THz = 1/ps

    # Spectral power difference at each z-slice
    D_z_f = zeros(Float64, n_zsave, Nt)
    for i in 1:n_zsave
        S_s = fftshift(abs2.(d_s["uω_z"][i, :, 1]))
        S_u = fftshift(abs2.(d_u["uω_z"][i, :, 1]))
        D_z_f[i, :] = 10.0 .* log10.((S_s .+ 1e-30) ./ (S_u .+ 1e-30))
    end

    # Find 3 dB divergence z-position (first z where any freq bin exceeds 3 dB)
    z_diverge_3dB = NaN
    for i in 1:n_zsave
        if maximum(abs.(D_z_f[i, :])) >= 3.0
            z_diverge_3dB = zsave[i]
            break
        end
    end

    # Save
    fpath = joinpath(PC_RESULTS_DIR, "spectral_divergence_$(fiber_tag).jld2")
    JLD2.jldsave(fpath;
        D_z_f        = D_z_f,
        fs_THz       = fs_THz,
        zsave        = zsave,
        z_diverge_3dB = z_diverge_3dB,
        fiber_tag    = fiber_tag,
    )
    @info @sprintf("Spectral divergence %s: z_3dB=%.3fm  ->  %s",
        fiber_tag, isnan(z_diverge_3dB) ? -1.0 : z_diverge_3dB, fpath)

    return (
        D_z_f         = D_z_f,
        fs_THz        = fs_THz,
        zsave         = zsave,
        z_diverge_3dB = z_diverge_3dB,
        fiber_tag     = fiber_tag,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 01: Multi-start J(z) overlay
# ─────────────────────────────────────────────────────────────────────────────

"""
    pc_figure_01_multistart_jz_overlay(all_results, J_z_flat_ref)

Plot 10 J(z) trajectories (shaped) on a shared semilogy axis, color-coded by
cluster assignment (warm = Cluster A, cool = Cluster B). The common flat-phase
J(z) reference is overlaid as a dashed black line.
"""
function pc_figure_01_multistart_jz_overlay(all_results, J_z_flat_ref)
    fig, ax = subplots(1, 1, figsize=(9, 6))

    # Cluster A (starts with higher final suppression) — warm colors
    # Cluster B (starts with lower final suppression) — cool colors
    # Assign clusters by sorting final J values: top 5 = Cluster A
    J_final = [r.J_z_shaped[end] for r in all_results]
    sorted_idx = sortperm(J_final)  # ascending J = better suppression first
    cluster_A = sorted_idx[1:5]     # 5 best suppressors
    cluster_B = sorted_idx[6:10]    # 5 worse suppressors

    warm_colors = ["#d62728", "#ff7f0e", "#bcbd22", "#e377c2", "#8c564b"]
    cool_colors = ["#1f77b4", "#17becf", "#2ca02c", "#9467bd", "#7f7f7f"]

    wa, wb = 0, 0
    for (k, r) in enumerate(all_results)
        zsave_m = r.zsave
        Jz_dB   = 10.0 .* log10.(max.(r.J_z_shaped, 1e-20))
        if k in cluster_A
            wa += 1
            clr = warm_colors[wa]
            lbl = "Start $(r.start_idx) (A)"
        else
            wb += 1
            clr = cool_colors[wb]
            lbl = "Start $(r.start_idx) (B)"
        end
        ax.plot(zsave_m, Jz_dB, color=clr, linewidth=1.8, label=lbl, alpha=0.85)
    end

    # Flat reference
    Jflat_dB = 10.0 .* log10.(max.(J_z_flat_ref, 1e-20))
    ax.plot(all_results[1].zsave, Jflat_dB,
        color="black", linewidth=2.0, linestyle="--", label="Unshaped (ref)", zorder=10)

    ax.set_xlabel("Propagation distance z (m)", fontsize=12)
    ax.set_ylabel("Raman band fraction J (dB)", fontsize=12)
    ax.set_title("Multi-Start J(z) Trajectories — SMF-28 L=2m P=0.2W (N≈2.6)", fontsize=13)
    ax.legend(loc="upper right", fontsize=7, ncol=2, framealpha=0.8)
    ax.grid(true, alpha=0.3)
    fig.tight_layout()

    fpath = joinpath(PC_FIGURE_DIR, "physics_11_01_multistart_jz_overlay.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved $fpath"
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 02: J(z) vs phi_opt correlation matrix comparison
# ─────────────────────────────────────────────────────────────────────────────

"""
    pc_figure_02_jz_cluster_comparison(traj_analysis)

Side-by-side heatmaps of the 10x10 J(z) trajectory correlation matrix and the
10x10 phi_opt structural similarity matrix. Divergence between the two reveals
whether phase-space proximity translates to z-dynamics proximity.
"""
function pc_figure_02_jz_cluster_comparison(traj_analysis)
    fig, axes = subplots(1, 2, figsize=(13, 5))
    cmap = "RdBu_r"
    vmin, vmax = -1.0, 1.0
    ticks = 1:10

    for (ax, mat, ttl) in [
        (axes[1], traj_analysis.jz_corr_matrix,  "J(z) Trajectory Correlation"),
        (axes[2], traj_analysis.phi_corr_matrix,  "phi_opt Structural Similarity"),
    ]
        im = ax.imshow(mat, cmap=cmap, vmin=vmin, vmax=vmax, aspect="equal")
        colorbar(im, ax=ax, label="Pearson r", shrink=0.8)
        ax.set_xticks(0:9); ax.set_xticklabels(ticks, fontsize=8)
        ax.set_yticks(0:9); ax.set_yticklabels(ticks, fontsize=8)
        ax.set_xlabel("Start index", fontsize=10)
        ax.set_ylabel("Start index", fontsize=10)
        ax.set_title(ttl, fontsize=11)

        # Annotate each cell with the correlation value
        for i in 1:10
            for j in 1:10
                val = mat[i, j]
                txt_clr = abs(val) > 0.5 ? "white" : "black"
                ax.text(j-1, i-1, @sprintf("%.2f", val),
                    ha="center", va="center", fontsize=5, color=txt_clr)
            end
        end
    end

    fig.suptitle("J(z) Trajectory vs phi_opt Structural Similarity (N=10 multi-start, SMF-28)",
        fontsize=12, y=1.02)
    fig.tight_layout()

    fpath = joinpath(PC_FIGURE_DIR, "physics_11_02_jz_cluster_comparison.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved $fpath"
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 03: Spectral divergence heatmaps (2x3 grid)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pc_figure_03_spectral_divergence_heatmaps(all_divergence)

2x3 panel grid of D(z,f) = S_shaped/S_unshaped in dB for all 6 Phase 10 configs.
Top row: 3 SMF-28 configs. Bottom row: 3 HNLF configs.
Horizontal dashed line marks the 3 dB divergence z-position.
"""
function pc_figure_03_spectral_divergence_heatmaps(all_divergence)
    fig, axes = subplots(2, 3, figsize=(15, 8))

    for (k, div) in enumerate(all_divergence)
        row = (k <= 3) ? 1 : 2
        col = mod1(k, 3)
        ax  = axes[row, col]

        # Frequency mask: restrict to ±15 THz to show signal bandwidth
        f_mask = abs.(div.fs_THz) .<= 15.0
        fs_plot = div.fs_THz[f_mask]
        D_plot  = div.D_z_f[:, f_mask]

        # pcolormesh: z on y-axis, frequency on x-axis
        pcm = ax.pcolormesh(fs_plot, div.zsave, D_plot,
            cmap="RdBu_r", vmin=-20.0, vmax=20.0, shading="auto")
        colorbar(pcm, ax=ax, label="dB", shrink=0.8)

        # Mark 3 dB divergence position
        z3 = div.z_diverge_3dB
        if !isnan(z3)
            ax.axhline(y=z3, color="black", linewidth=1.5, linestyle="--",
                label=@sprintf("z₃dB=%.3fm", z3))
            ax.legend(loc="upper left", fontsize=7, framealpha=0.8)
        else
            ax.text(0.05, 0.95, "z₃dB: not reached", transform=ax.transAxes,
                fontsize=7, va="top", ha="left",
                bbox=Dict("boxstyle"=>"round", "facecolor"=>"white", "alpha"=>0.7))
        end

        ax.set_xlabel("Frequency (THz)", fontsize=9)
        ax.set_ylabel("z (m)", fontsize=9)
        ax.set_title(PC_PHASE10_LABELS[k], fontsize=9)
    end

    fig.suptitle("Spectral Divergence D(z,f) = S_shaped/S_unshaped (dB) — All 6 Phase 10 Configs",
        fontsize=12)
    fig.tight_layout()

    fpath = joinpath(PC_FIGURE_DIR, "physics_11_03_spectral_divergence_heatmaps.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved $fpath"
end

# ─────────────────────────────────────────────────────────────────────────────
# H1 formalization: critical bands comparison (Figure 04)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pc_h1_critical_bands_comparison()

Load Phase 10 ablation data for SMF-28 and HNLF canonical configs.
Compare per-band suppression loss: bands where zeroing degrades J by >3 dB
relative to full phi_opt. Compute overlap fraction between fibers.
"""
function pc_h1_critical_bands_comparison()
    smf_data  = JLD2.load(joinpath(PC_PHASE10_DIR, "ablation_smf28_canonical.jld2"))
    hnlf_data = JLD2.load(joinpath(PC_PHASE10_DIR, "ablation_hnlf_canonical.jld2"))

    J_full_smf  = Float64(smf_data["J_full"])
    J_full_hnlf = Float64(hnlf_data["J_full"])
    bz_smf      = Float64.(smf_data["band_zeroing_J"])   # J when each band zeroed
    bz_hnlf     = Float64.(hnlf_data["band_zeroing_J"])
    n_bands     = length(bz_smf)

    # Suppression loss = 10*log10(J_zeroed/J_full) — positive dB = degradation
    loss_smf  = 10.0 .* log10.(max.(bz_smf,  1e-30) ./ max(J_full_smf,  1e-30))
    loss_hnlf = 10.0 .* log10.(max.(bz_hnlf, 1e-30) ./ max(J_full_hnlf, 1e-30))

    threshold_dB = 3.0
    critical_smf  = loss_smf  .>= threshold_dB
    critical_hnlf = loss_hnlf .>= threshold_dB
    critical_both = critical_smf .& critical_hnlf

    overlap_frac = sum(critical_both) / n_bands
    @info @sprintf("H1 verdict: %d/%d bands critical in SMF-28, %d/%d in HNLF, overlap=%d/%d (%.0f%%)",
        sum(critical_smf), n_bands,
        sum(critical_hnlf), n_bands,
        sum(critical_both), n_bands,
        100*overlap_frac)

    # Figure 04
    pc_figure_04_h1_critical_bands(loss_smf, loss_hnlf, critical_smf, critical_hnlf, critical_both,
        n_bands, threshold_dB, overlap_frac)

    return (loss_smf=loss_smf, loss_hnlf=loss_hnlf, overlap_frac=overlap_frac,
        critical_smf=critical_smf, critical_hnlf=critical_hnlf)
end

"""
    pc_figure_04_h1_critical_bands(...)

Bar charts of per-band suppression loss for SMF-28 (left) and HNLF (right).
Bands critical in both fibers are highlighted in red. 3 dB threshold marked.
"""
function pc_figure_04_h1_critical_bands(loss_smf, loss_hnlf, critical_smf, critical_hnlf,
                                         critical_both, n_bands, threshold_dB, overlap_frac)
    fig, axes = subplots(1, 2, figsize=(12, 5))
    band_indices = 1:n_bands

    for (ax, loss, critical, title_str) in [
        (axes[1], loss_smf,  critical_smf,  "SMF-28  L=2m  P=0.2W"),
        (axes[2], loss_hnlf, critical_hnlf, "HNLF  L=1m  P=0.01W"),
    ]
        colors = [critical_both[i] ? "#d62728" :   # red: critical in both
                  critical[i]      ? "#ff7f0e" :   # orange: critical in this fiber only
                                     "#1f77b4"     # blue: non-critical
                  for i in band_indices]
        ax.bar(band_indices, loss, color=colors, edgecolor="black", linewidth=0.5)
        ax.axhline(y=threshold_dB, color="black", linewidth=1.5, linestyle="--",
            label="3 dB threshold")

        ax.set_xlabel("Spectral sub-band index", fontsize=11)
        ax.set_ylabel("Suppression loss (dB)", fontsize=11)
        ax.set_title(title_str, fontsize=11)
        ax.set_xticks(band_indices)
        ax.grid(true, axis="y", alpha=0.3)
        ax.legend(fontsize=9)

        # Annotate which bands are critical
        for i in band_indices
            if critical[i]
                ax.text(i, loss[i] + 0.5, @sprintf("%.0fdB", loss[i]),
                    ha="center", va="bottom", fontsize=7)
            end
        end
    end

    # Shared annotation about overlap
    fig.suptitle(@sprintf(
        "H1: Spectrally Distributed Suppression — Overlap: %d/%d bands critical in both fibers (%.0f%%)",
        sum(critical_both), n_bands, 100*overlap_frac),
        fontsize=11)

    # Color legend via PyPlot mpatches
    mpatches = PyPlot.matplotlib.patches
    patch_both  = mpatches.Patch(color="#d62728", label="Critical in both")
    patch_one   = mpatches.Patch(color="#ff7f0e", label="Critical in this fiber only")
    patch_none  = mpatches.Patch(color="#1f77b4", label="Non-critical")
    fig.legend(handles=[patch_both, patch_one, patch_none], loc="lower center",
        ncol=3, fontsize=9, bbox_to_anchor=(0.5, -0.04))

    fig.tight_layout(rect=[0, 0.04, 1, 0.95])

    fpath = joinpath(PC_FIGURE_DIR, "physics_11_04_h1_critical_bands_comparison.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved $fpath"
end

# ─────────────────────────────────────────────────────────────────────────────
# H2 formalization: sub-THz shift tolerance (Figure 05)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pc_h2_shift_scale_characterization()

Load Phase 10 shift perturbation data for SMF-28 and HNLF.
Fit a parabola J(Δf) = J₀ + a*Δf² to the 3 central shift points (±1, 0 THz).
Estimate 3 dB tolerance as sqrt(3/a) THz. Compare with Raman bandwidth.
"""
function pc_h2_shift_scale_characterization()
    smf_data  = JLD2.load(joinpath(PC_PHASE10_DIR, "perturbation_smf28_canonical.jld2"))
    hnlf_data = JLD2.load(joinpath(PC_PHASE10_DIR, "perturbation_hnlf_canonical.jld2"))

    shift_THz = Float64.(smf_data["shift_THz"])   # [-5,-2,-1,0,1,2,5]

    # shift_J: J values at each shift (linear scale)
    shift_J_smf  = Float64.(smf_data["shift_J"])
    shift_J_hnlf = Float64.(hnlf_data["shift_J"])

    # Convert to dB
    J_full_smf  = Float64(smf_data["J_full"])
    J_full_hnlf = Float64(hnlf_data["J_full"])
    shift_dB_smf  = 10.0 .* log10.(max.(shift_J_smf,  1e-30) ./ max(J_full_smf,  1e-30))
    shift_dB_hnlf = 10.0 .* log10.(max.(shift_J_hnlf, 1e-30) ./ max(J_full_hnlf, 1e-30))

    # Parabolic fit to 3 central points (Δf = -1, 0, 1 THz)
    central_mask = abs.(shift_THz) .<= 1.0
    df_central   = shift_THz[central_mask]
    function fit_parabola(dB_arr)
        dB_central = dB_arr[central_mask]
        # Fit J_dB = a2*df^2 + a1*df + a0 via least-squares (3 points, 3 unknowns)
        A = hcat(df_central.^2, df_central, ones(length(df_central)))
        coeffs = A \ dB_central   # [a2, a1, a0]
        # 3 dB tolerance: solve |a2|*tol^2 = 3 => tol = sqrt(3/|a2|)
        a2 = coeffs[1]
        tol = abs(a2) > 1e-10 ? sqrt(3.0 / abs(a2)) : Inf
        return coeffs, tol
    end

    coeffs_smf,  tol_smf  = fit_parabola(shift_dB_smf)
    coeffs_hnlf, tol_hnlf = fit_parabola(shift_dB_hnlf)

    @info @sprintf("H2 SMF-28:  3dB tolerance = %.3f THz  (Raman BW = %.1f THz, ratio = %.3f)",
        tol_smf, PC_RAMAN_BW_THZ, tol_smf / PC_RAMAN_BW_THZ)
    @info @sprintf("H2 HNLF:    3dB tolerance = %.3f THz  (Raman BW = %.1f THz, ratio = %.3f)",
        tol_hnlf, PC_RAMAN_BW_THZ, tol_hnlf / PC_RAMAN_BW_THZ)

    pc_figure_05_h2_shift_characterization(shift_THz, shift_dB_smf, shift_dB_hnlf,
        coeffs_smf, coeffs_hnlf, tol_smf, tol_hnlf)

    return (
        shift_THz    = shift_THz,
        shift_dB_smf = shift_dB_smf,
        shift_dB_hnlf= shift_dB_hnlf,
        tol_smf      = tol_smf,
        tol_hnlf     = tol_hnlf,
        coeffs_smf   = coeffs_smf,
        coeffs_hnlf  = coeffs_hnlf,
    )
end

"""
    pc_figure_05_h2_shift_characterization(...)

Left panel: J_shift (dB above optimum) vs spectral shift for SMF-28 and HNLF,
with parabolic fits. Vertical shaded bands show 3 dB tolerance for each fiber.
Right panel: bar chart comparing 3 dB tolerance vs Raman bandwidth.
"""
function pc_figure_05_h2_shift_characterization(shift_THz, dB_smf, dB_hnlf,
                                                  coeffs_smf, coeffs_hnlf, tol_smf, tol_hnlf)
    fig, axes = subplots(1, 2, figsize=(13, 5))

    # Left panel: shift sensitivity curves
    ax = axes[1]
    df_fine = range(-3.0, 3.0, length=200)

    # Parabolic model curves
    fit_smf  = coeffs_smf[1]  .* df_fine.^2 .+ coeffs_smf[2]  .* df_fine .+ coeffs_smf[3]
    fit_hnlf = coeffs_hnlf[1] .* df_fine.^2 .+ coeffs_hnlf[2] .* df_fine .+ coeffs_hnlf[3]

    ax.plot(shift_THz, dB_smf,  "o-", color="#1f77b4", linewidth=2, markersize=7, label="SMF-28 (data)")
    ax.plot(shift_THz, dB_hnlf, "s-", color="#d62728", linewidth=2, markersize=7, label="HNLF (data)")
    ax.plot(df_fine, fit_smf,  "--", color="#1f77b4", linewidth=1.5, alpha=0.7, label="SMF-28 (parabolic fit)")
    ax.plot(df_fine, fit_hnlf, "--", color="#d62728", linewidth=1.5, alpha=0.7, label="HNLF (parabolic fit)")

    # Shade 3 dB tolerance bands
    ax.axvspan(-tol_smf, tol_smf, alpha=0.12, color="#1f77b4",
        label=@sprintf("SMF-28 tol = ±%.2f THz", tol_smf))
    ax.axvspan(-tol_hnlf, tol_hnlf, alpha=0.12, color="#d62728",
        label=@sprintf("HNLF tol = ±%.2f THz", tol_hnlf))
    ax.axhline(y=-3.0, color="black", linestyle=":", linewidth=1.5, label="-3 dB level")

    ax.set_xlabel("Spectral shift Δf (THz)", fontsize=11)
    ax.set_ylabel("Suppression change from optimum (dB)", fontsize=11)
    ax.set_title("H2: Spectral Shift Sensitivity", fontsize=11)
    ax.legend(fontsize=7, loc="lower center")
    ax.grid(true, alpha=0.3)
    ax.set_xlim(-5.5, 5.5)

    # Right panel: bar comparison
    ax2 = axes[2]
    labels = ["SMF-28\n3dB tol", "HNLF\n3dB tol", "Raman\nBW (13.2 THz)"]
    values = [tol_smf, tol_hnlf, PC_RAMAN_BW_THZ]
    colors = ["#1f77b4", "#d62728", "#2ca02c"]
    bars = ax2.bar(labels, values, color=colors, edgecolor="black", linewidth=0.5)
    for (bar, val) in zip(bars, values)
        ax2.text(bar.get_x() + bar.get_width()/2, val + 0.1,
            @sprintf("%.2f THz", val), ha="center", va="bottom", fontsize=9)
    end
    ax2.set_ylabel("Frequency (THz)", fontsize=11)
    ax2.set_title("3 dB Tolerance vs Raman Bandwidth", fontsize=11)
    ax2.grid(true, axis="y", alpha=0.3)

    fig.suptitle("H2: Sub-THz Spectral Feature Scale — phi_opt has sub-0.5 THz relevant structure",
        fontsize=11)
    fig.tight_layout()

    fpath = joinpath(PC_FIGURE_DIR, "physics_11_05_h2_shift_scale_characterization.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved $fpath"
end

end  # include guard

# ─────────────────────────────────────────────────────────────────────────────
# Main execution block
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    t_start = time()

    mkpath(PC_RESULTS_DIR)
    mkpath(PC_FIGURE_DIR)

    @info "┌──────────────────────────────────────────────────────────────────────┐"
    @info "│  Phase 11.01 — Classical Physics Completion                          │"
    @info "│  Multi-start z-dynamics, spectral divergence, H1/H2 formalization   │"
    @info "└──────────────────────────────────────────────────────────────────────┘"

    # ── A. Multi-start z-propagation (10 starts × 2 conditions) ──────────────
    @info ""
    @info "=== Section A: Multi-start z-propagation (10 starts) ==="
    all_results = Vector{Any}(undef, 10)
    for idx in 1:10
        all_results[idx] = pc_load_multistart_and_propagate(idx; n_zsave=PC_N_ZSAVE)
    end

    # Consistency check: all 10 flat propagations must be identical
    @info ""
    @info "=== Consistency check: flat propagations must agree to < 1e-10 ==="
    J_flat_ref = all_results[1].J_z_flat
    max_flat_dev = 0.0
    for i in 2:10
        dev = maximum(abs.(all_results[i].J_z_flat .- J_flat_ref))
        global max_flat_dev = max(max_flat_dev, dev)
        @info @sprintf("  start_%02d flat deviation: max|ΔJ| = %.3e", i, dev)
    end
    @info @sprintf("  Global max flat deviation: %.3e (threshold: 1e-10)", max_flat_dev)
    if max_flat_dev > 1e-10
        @warn @sprintf("Flat propagation consistency check FAILED: max dev = %.3e", max_flat_dev)
    else
        @info "Flat propagation consistency check PASSED."
    end

    # ── B. J(z) trajectory clustering ────────────────────────────────────────
    @info ""
    @info "=== Section B: J(z) trajectory clustering ==="
    traj_analysis = pc_cluster_jz_trajectories(all_results)

    # ── C. Spectral divergence (6 Phase 10 configs) ──────────────────────────
    @info ""
    @info "=== Section C: Spectral divergence for 6 Phase 10 configs ==="
    all_divergence = [pc_spectral_divergence(tag) for tag in PC_PHASE10_TAGS]

    # ── D. Figures 01–03 ─────────────────────────────────────────────────────
    @info ""
    @info "=== Section D: Generating figures 01–03 ==="
    pc_figure_01_multistart_jz_overlay(all_results, J_flat_ref)
    pc_figure_02_jz_cluster_comparison(traj_analysis)
    pc_figure_03_spectral_divergence_heatmaps(all_divergence)

    # ── E. H1 formalization (Figure 04) ──────────────────────────────────────
    @info ""
    @info "=== Section E: H1 formalization ==="
    h1_result = pc_h1_critical_bands_comparison()

    # ── F. H2 formalization (Figure 05) ──────────────────────────────────────
    @info ""
    @info "=== Section F: H2 formalization ==="
    h2_result = pc_h2_shift_scale_characterization()

    # ── Summary table ─────────────────────────────────────────────────────────
    elapsed = time() - t_start
    @info ""
    @info "┌─────────────────────────────────────────────────────────────────────┐"
    @info "│  Phase 11.01 — Summary                                              │"
    @info "├─────────────────────────────────────────────────────────────────────┤"
    @info @sprintf("│  Wall time: %.1f s                                               │", elapsed)
    @info @sprintf("│  Flat propagation max deviation: %.2e (threshold 1e-10)         │", max_flat_dev)

    J_final_dB = traj_analysis.J_final_dB
    @info @sprintf("│  J(z=L) range: %.1f to %.1f dB (10 starts)                      │",
        minimum(J_final_dB), maximum(J_final_dB))
    @info @sprintf("│  J(z) mean corr (off-diag): %.3f                                 │",
        mean([traj_analysis.jz_corr_matrix[i,j] for i in 1:10 for j in 1:10 if i != j]))
    @info @sprintf("│  phi_opt mean corr (off-diag): %.3f                              │",
        mean([traj_analysis.phi_corr_matrix[i,j] for i in 1:10 for j in 1:10 if i != j]))

    @info "│  Spectral divergence 3dB z-positions:                               │"
    for (div, lbl) in zip(all_divergence, PC_PHASE10_LABELS)
        zstr = isnan(div.z_diverge_3dB) ? "not reached" : @sprintf("%.4f m", div.z_diverge_3dB)
        @info @sprintf("│    %-35s z_3dB = %s", lbl, zstr)
    end

    @info @sprintf("│  H1: SMF-28 critical bands = %d/10, HNLF = %d/10, overlap = %d/10 (%.0f%%)│",
        sum(h1_result.critical_smf), sum(h1_result.critical_hnlf),
        sum(h1_result.critical_smf .& h1_result.critical_hnlf),
        100 * h1_result.overlap_frac)
    @info @sprintf("│  H2: SMF-28 tol = %.3f THz, HNLF tol = %.3f THz (Raman BW = %.1f THz) │",
        h2_result.tol_smf, h2_result.tol_hnlf, PC_RAMAN_BW_THZ)

    @info "│                                                                     │"
    @info "│  Figures saved:                                                     │"
    for fig_name in [
        "physics_11_01_multistart_jz_overlay.png",
        "physics_11_02_jz_cluster_comparison.png",
        "physics_11_03_spectral_divergence_heatmaps.png",
        "physics_11_04_h1_critical_bands_comparison.png",
        "physics_11_05_h2_shift_scale_characterization.png",
    ]
        @info @sprintf("│    results/images/%s", fig_name)
    end
    @info "└─────────────────────────────────────────────────────────────────────┘"
end
