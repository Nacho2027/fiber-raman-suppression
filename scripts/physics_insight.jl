"""
Physics Insight Visualization — Phase 6.1

Reveals what the L-BFGS optimizer is doing to suppress Raman scattering by
visualizing optimized spectral phase (phi_opt) across all 5 runs from multiple
angles. This is DISCOVERY — figures expose structure, not confirm narratives.

Figures produced (all → results/images/):
  1. insight_01_phi_overlay_freq.png     — phi_opt overlay in frequency domain (5 runs)
  2. insight_02_phi_overlay_lambda.png   — phi_opt overlay in wavelength domain (5 runs)
  3. insight_03_phi_detail_panels.png    — per-run detail panels with GDD+TOD polynomial overlay
  4. insight_04_correlation_scatter.png  — N / L / P vs delta_dB correlation scatter
  5. insight_05_raman_band_before_after.png — input spectra per run with J annotations
  6. insight_06_group_delay_overlay.png  — group delay d_phi/d_omega overlay (ps vs THz)
  7. insight_07_residual_overlay.png     — polynomial fit residual (99% unexplained structure)
  8. insight_08_phase_raman_zoom.png     — phase zoom into [-20, -8] THz near Raman offset

Data source: results/raman/manifest.json + per-run JLD2 files.

Phase normalization (D-02): global offset and linear group delay removed before
any multi-run overlay, so physically similar solutions are visually comparable.

Include guard: safe to include multiple times.
"""

try using Revise catch end
using Printf
using LinearAlgebra
using FFTW
using Logging
using Dates
ENV["MPLBACKEND"] = "Agg"  # Non-interactive backend for headless execution
using PyPlot
using JLD2
using JSON3

include("common.jl")
include("visualization.jl")

if !(@isdefined _PHYSICS_INSIGHT_JL_LOADED)
const _PHYSICS_INSIGHT_JL_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# Section 1: Helper functions
# ─────────────────────────────────────────────────────────────────────────────

"""
    normalize_phase(phi_raw_fftorder, uomega0_fftorder, sim_Dt_ps, Nt)

Remove global phase offset and linear group delay from a spectral phase vector.

Operates in fftshifted coordinates: the signal mask is built on the fftshifted
power spectrum, and the returned phi_norm is also fftshifted for direct plotting.

# Arguments
- `phi_raw_fftorder`: 1D vector of length Nt, raw phase in FFT order
- `uomega0_fftorder`: 1D complex vector of length Nt, input field in FFT order
- `sim_Dt_ps`:        Float64, simulation time step [ps]
- `Nt`:              Int, number of frequency grid points

# Returns
NamedTuple:
- `phi_norm`:    Float64 vector (Nt,), fftshifted, normalized phase (zero offset + zero slope)
- `df_THz`:      Float64 vector (Nt,), fftshifted frequency offset from carrier [THz]
- `signal_mask`: Bool vector (Nt,), true where power > -40 dB (fftshifted)
"""
function normalize_phase(phi_raw_fftorder, uomega0_fftorder, sim_Dt_ps, Nt)
    # --- Build -40 dB signal mask on fftshifted power spectrum ---
    spec_power = abs2.(fftshift(uomega0_fftorder))
    P_peak = maximum(spec_power)
    dB_vals = 10.0 .* log10.(spec_power ./ P_peak .+ 1e-30)
    signal_mask = dB_vals .> -40.0

    # --- Frequency offset grid in THz (fftshifted) ---
    # sim_Dt_ps is in picoseconds → fftfreq returns THz directly
    df_THz = fftshift(fftfreq(Nt, 1.0 / sim_Dt_ps))  # THz

    # --- fftshift the raw phase ---
    phi_shifted = fftshift(phi_raw_fftorder)

    # --- Extract signal-band phase and frequency ---
    phi_signal  = phi_shifted[signal_mask]
    df_signal   = df_THz[signal_mask]

    # Convert frequency offset to angular frequency [rad/THz]
    omega_signal = 2π .* df_signal  # rad/THz

    # --- Fit a + b·ω (global offset + linear group delay) ---
    A = hcat(ones(length(omega_signal)), omega_signal)
    coeffs = A \ phi_signal

    # --- Subtract linear trend from the full (fftshifted) phase array ---
    omega_full = 2π .* df_THz  # rad/THz
    phi_norm = phi_shifted .- (coeffs[1] .+ coeffs[2] .* omega_full)

    # --- Zero noise-floor bins for clean display (avoid random phase contamination) ---
    phi_norm[.!signal_mask] .= 0.0

    return (phi_norm=phi_norm, df_THz=df_THz, signal_mask=signal_mask)
end

"""
    run_label(run)

Return a short descriptive label for a run dict (for plot legends).
"""
function run_label(run)
    nc_tag = run["converged"] ? "" : " (nc)"
    return @sprintf("%s L=%.0fm P=%.2fW N=%.1f%s",
        run["fiber_name"], Float64(run["L_m"]), Float64(run["P_cont_W"]),
        Float64(run["soliton_number_N"]), nc_tag)
end

"""
    build_lambda_axis_nm(df_THz, lambda0_nm)

Build the wavelength axis [nm] from a frequency offset grid [THz] and carrier wavelength.

Positive frequencies only (avoids FFT artifacts at negative frequency bins).

# Arguments
- `df_THz`:     Float64 vector, frequency offset from carrier [THz] (fftshifted)
- `lambda0_nm`: Float64, carrier wavelength [nm]

# Returns
NamedTuple:
- `lambda_nm`:  Float64 vector, wavelengths [nm] for positive-frequency bins
- `pos_mask`:   Bool vector (same length as df_THz), true for positive frequencies
"""
function build_lambda_axis_nm(df_THz, lambda0_nm)
    f0_THz = C_NM_THZ / lambda0_nm
    f_abs = f0_THz .+ df_THz          # absolute frequency [THz]
    pos_mask = f_abs .> 0
    lambda_nm = C_NM_THZ ./ f_abs[pos_mask]
    return (lambda_nm=lambda_nm, pos_mask=pos_mask)
end

end  # if !(@isdefined _PHYSICS_INSIGHT_JL_LOADED)

# ─────────────────────────────────────────────────────────────────────────────
# Main execution block (only runs when executed directly, not when included)
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__

# ─────────────────────────────────────────────────────────────────────────────
# Section 2: Data loading from manifest.json + JLD2
# ─────────────────────────────────────────────────────────────────────────────

@info "═══ Physics Insight — Phase 6.1 ═══"
@info "▶ Loading results from manifest.json"

manifest_path = joinpath("results", "raman", "manifest.json")
@assert isfile(manifest_path) "manifest.json not found at $manifest_path"

manifest_raw = JSON3.read(read(manifest_path, String), Vector{Dict{String,Any}})

all_runs = Dict{String,Any}[]
for entry in manifest_raw
    jld2_path = entry["result_file"]
    if !isfile(jld2_path)
        @warn "Missing JLD2 file, skipping manifest entry" path=jld2_path
        continue
    end
    jld2_data = JLD2.load(jld2_path)
    # Merge manifest scalars with JLD2 arrays/fields
    merged = merge(Dict{String,Any}(entry), Dict{String,Any}(jld2_data))
    push!(all_runs, merged)
end
@info "Loaded $(length(all_runs)) runs from manifest"

# Normalize phi_opt and uomega0 shapes; run phase normalization and decomposition
for (i, run) in enumerate(all_runs)
    Nt_run = Int(run["Nt"])
    sim_Dt_ps = Float64(run["sim_Dt"])

    # Normalize array shapes: JLD2 may store as (Nt, 1) or (Nt,)
    phi_opt  = vec(run["phi_opt"])
    uomega0  = vec(run["uomega0"])

    # Phase normalization (fftshifted, removes offset + linear group delay)
    norm_result = normalize_phase(phi_opt, uomega0, sim_Dt_ps, Nt_run)
    run["phi_norm"]    = norm_result.phi_norm
    run["df_THz"]      = norm_result.df_THz
    run["signal_mask"] = norm_result.signal_mask

    # Polynomial decomposition (GDD + TOD)
    # decompose_phase_polynomial expects 2D (Nt, 1) and sim_Dt in SECONDS
    sim_Dt_s = sim_Dt_ps * 1e-12
    decomp = decompose_phase_polynomial(
        reshape(phi_opt, :, 1),
        reshape(uomega0, :, 1),
        sim_Dt_s, Nt_run
    )
    run["decomp"] = decomp

    @info @sprintf("  Run %d: %s L=%.0fm P=%.2fW | GDD=%.1f fs² TOD=%.1f fs³ residual=%.1f%%",
        i, run["fiber_name"], Float64(run["L_m"]), Float64(run["P_cont_W"]),
        decomp.gdd_fs2, decomp.tod_fs3, decomp.residual_fraction * 100)
end

# Ensure results/images directory exists
mkpath("results/images")

# ─────────────────────────────────────────────────────────────────────────────
# Section 3: Figure 1 — phi_opt overlay in frequency domain (D-02)
# ─────────────────────────────────────────────────────────────────────────────

@info "▶ Generating Figure 1: phi_opt overlay (frequency domain)"

fig1, ax1 = subplots(1, 1; figsize=(12, 6))

for (i, run) in enumerate(all_runs)
    mask = run["signal_mask"]
    df   = run["df_THz"]
    phi  = run["phi_norm"]
    ax1.plot(df[mask], phi[mask];
             color=COLORS_5_RUNS[i], lw=1.5, label=run_label(run))
end

# Shade Raman band: ~-30 THz to -13.2 THz (red-shifted side)
ax1.axvspan(-30.0, -13.2; alpha=0.08, color=COLOR_RAMAN, label="Raman band")
ax1.axvline(-13.2; color=COLOR_RAMAN, lw=0.8, ls="--")
ax1.axvline(-30.0; color=COLOR_RAMAN, lw=0.8, ls="--")

ax1.set_xlabel("Frequency offset from carrier (THz)")
ax1.set_ylabel("Normalized phase (rad)")
ax1.set_title("Optimized spectral phase — all 5 runs")
ax1.legend(loc="upper left", fontsize=8)
ax1.axhline(0; color="black", lw=0.5, ls=":")

add_caption!(fig1, "Global phase offset and linear group delay removed before overlay (D-02)")
fig1.tight_layout(rect=[0, 0.04, 1, 1])
fig1.savefig("results/images/insight_01_phi_overlay_freq.png"; dpi=300, bbox_inches="tight")
close(fig1)
@info "  Saved → results/images/insight_01_phi_overlay_freq.png"

# ─────────────────────────────────────────────────────────────────────────────
# Section 4: Figure 2 — phi_opt overlay in wavelength domain (D-02)
# ─────────────────────────────────────────────────────────────────────────────

@info "▶ Generating Figure 2: phi_opt overlay (wavelength domain)"

fig2, ax2 = subplots(1, 1; figsize=(12, 6))

for (i, run) in enumerate(all_runs)
    lambda0_nm = Float64(run["lambda0_nm"])
    df_THz     = run["df_THz"]
    phi_norm   = run["phi_norm"]
    sig_mask   = run["signal_mask"]

    lam = build_lambda_axis_nm(df_THz, lambda0_nm)
    pos_mask = lam.pos_mask

    # Intersect positive-frequency mask with signal mask for plotting
    combined = pos_mask .& sig_mask

    ax2.plot(lam.lambda_nm[sig_mask[pos_mask]], phi_norm[combined];
             color=COLORS_5_RUNS[i], lw=1.5, label=run_label(run))
end

# Shade Raman wavelength region
# Carrier at 1550 nm; -13.2 THz offset → higher wavelength
# f_raman_lo = C_NM_THZ/1550 - 30.0 THz, f_raman_hi = C_NM_THZ/1550 - 13.2 THz
f0_THz = C_NM_THZ / 1550.0
lambda_raman_lo = C_NM_THZ / (f0_THz - 30.0)   # farther from carrier (longer λ)
lambda_raman_hi = C_NM_THZ / (f0_THz - 13.2)   # closer to carrier (shorter λ)
ax2.axvspan(lambda_raman_hi, lambda_raman_lo; alpha=0.08, color=COLOR_RAMAN, label="Raman band")
ax2.axvline(lambda_raman_hi; color=COLOR_RAMAN, lw=0.8, ls="--")
ax2.axvline(lambda_raman_lo; color=COLOR_RAMAN, lw=0.8, ls="--")

ax2.set_xlabel("Wavelength (nm)")
ax2.set_ylabel("Normalized phase (rad)")
ax2.set_title("Optimized spectral phase — wavelength domain")
ax2.legend(loc="upper left", fontsize=8)
ax2.axhline(0; color="black", lw=0.5, ls=":")

add_caption!(fig2, "Wavelength axis reconstructed from sim_Dt per run; Raman band at ~1650–1800 nm")
fig2.tight_layout(rect=[0, 0.04, 1, 1])
fig2.savefig("results/images/insight_02_phi_overlay_lambda.png"; dpi=300, bbox_inches="tight")
close(fig2)
@info "  Saved → results/images/insight_02_phi_overlay_lambda.png"

# ─────────────────────────────────────────────────────────────────────────────
# Section 5: Figure 3 — per-run detail panels with GDD+TOD polynomial overlay (D-04)
# ─────────────────────────────────────────────────────────────────────────────

@info "▶ Generating Figure 3: per-run detail panels with polynomial overlay"

n_runs = length(all_runs)
fig3, axes3 = subplots(n_runs, 1; figsize=(14, 3.5 * n_runs))

# Ensure axes3 is always indexable as an array
if n_runs == 1
    axes3 = [axes3]
end

for (i, run) in enumerate(all_runs)
    ax = axes3[i]
    Nt_run    = Int(run["Nt"])
    sim_Dt_ps = Float64(run["sim_Dt"])
    sim_Dt_s  = sim_Dt_ps * 1e-12
    mask      = run["signal_mask"]
    df_THz    = run["df_THz"]
    phi_norm  = run["phi_norm"]
    decomp    = run["decomp"]

    # Reconstruct the GDD+TOD polynomial on the full fftshifted omega grid
    # omega in rad/s; phi_poly is the polynomial fit to the DETRENDED phase
    omega_rad_s = 2π .* df_THz .* 1e12  # THz → rad/s
    gdd_s2  = decomp.gdd_fs2 * 1e-30    # fs² → s²
    tod_s3  = decomp.tod_fs3 * 1e-45    # fs³ → s³
    phi_poly = gdd_s2 .* omega_rad_s.^2 ./ 2.0 .+ tod_s3 .* omega_rad_s.^3 ./ 6.0

    # Plot normalized phase (solid) and polynomial fit (dashed)
    ax.plot(df_THz[mask], phi_norm[mask];
            color=COLORS_5_RUNS[i], lw=1.5, label="phi_norm")
    ax.plot(df_THz[mask], phi_poly[mask];
            color="#E69F00", lw=1.2, ls="--", label="GDD+TOD fit")

    # Shade Raman band
    ax.axvspan(-30.0, -13.2; alpha=0.10, color=COLOR_RAMAN)
    ax.axvline(-13.2; color=COLOR_RAMAN, lw=0.8, ls="--")
    ax.axhline(0; color="black", lw=0.5, ls=":")

    panel_title = run_label(run) * @sprintf(
        " | GDD=%.0f fs² | TOD=%.0f fs³ | residual: %.1f%%",
        decomp.gdd_fs2, decomp.tod_fs3, decomp.residual_fraction * 100)
    ax.set_title(panel_title; fontsize=10)
    ax.set_ylabel("Phase (rad)")

    if i == n_runs
        ax.set_xlabel("Frequency offset from carrier (THz)")
    end

    ax.legend(loc="upper left", fontsize=8)
end

fig3.suptitle("Per-run optimized phase with GDD+TOD polynomial overlay"; fontsize=13, y=1.01)
fig3.tight_layout(h_pad=2.5)
fig3.savefig("results/images/insight_03_phi_detail_panels.png"; dpi=300, bbox_inches="tight")
close(fig3)
@info "  Saved → results/images/insight_03_phi_detail_panels.png"

# ─────────────────────────────────────────────────────────────────────────────
# Section 6: Figure 4 — correlation scatter: N / L / P vs delta_dB (D-03)
# ─────────────────────────────────────────────────────────────────────────────

@info "▶ Generating Figure 4: correlation scatter (N, L, P vs delta_dB)"

fig4, axes4 = subplots(1, 3; figsize=(15, 5))

x_getters = [
    run -> Float64(run["soliton_number_N"]),
    run -> Float64(run["L_m"]),
    run -> Float64(run["P_cont_W"]),
]
x_labels = ["Soliton number N", "Fiber length L (m)", "Continuum power P (W)"]
panel_titles = ["(a)", "(b)", "(c)"]

for (j, (getter, xlabel, ptitle)) in enumerate(zip(x_getters, x_labels, panel_titles))
    ax = axes4[j]

    for (i, run) in enumerate(all_runs)
        x_val = getter(run)
        y_val = Float64(run["delta_J_dB"])

        # Marker shape: circle for SMF-28, triangle for HNLF
        marker = run["fiber_name"] == "SMF-28" ? "o" : "^"

        # Fill: filled for converged, open (hollow) for not converged
        fc = run["converged"] ? COLORS_5_RUNS[i] : "none"
        ec = COLORS_5_RUNS[i]

        ax.scatter([x_val], [y_val];
                   marker=marker, s=150,
                   facecolors=fc, edgecolors=ec, linewidths=2.0,
                   zorder=3)
    end

    ax.set_xlabel(xlabel; fontsize=11)
    ax.set_ylabel("Raman suppression ΔdB"; fontsize=11)
    ax.set_title(ptitle; fontsize=12)
    ax.axhline(0; color="black", lw=0.5, ls=":")
end

# Shared legend below all subplots showing marker meanings
legend_handles = [
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="gray", markersize=10, label="SMF-28"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="^", color="w",
        markerfacecolor="gray", markersize=10, label="HNLF"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="gray", markersize=10, label="Converged"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="none", markeredgecolor="gray",
        markeredgewidth=2, markersize=10, label="Not converged"),
]
fig4.legend(handles=legend_handles;
            loc="lower center", ncol=4, fontsize=9,
            bbox_to_anchor=(0.5, -0.08))

add_caption!(fig4, "Color by run index (consistent with Figs 1-3). No trend lines — only 5 data points.")
fig4.suptitle("Raman suppression vs run parameters"; fontsize=13)
fig4.tight_layout(rect=[0, 0.06, 1, 1])
fig4.savefig("results/images/insight_04_correlation_scatter.png"; dpi=300, bbox_inches="tight")
close(fig4)
@info "  Saved → results/images/insight_04_correlation_scatter.png"

# ─────────────────────────────────────────────────────────────────────────────
# Section 7: Figure 5 — Before/After Raman Band Comparison (D-04 item 5)
# Option A: input spectrum + J annotation (no re-propagation required)
# ─────────────────────────────────────────────────────────────────────────────

@info "▶ Generating Figure 5: input spectra with Raman band + J annotations (Option A)"

n_runs5 = length(all_runs)
fig5, axes5 = subplots(n_runs5, 1; figsize=(14, 4.0 * n_runs5))
if n_runs5 == 1
    axes5 = [axes5]
end

# Global P_peak across all runs for consistent dB normalization
P_peak_global = maximum(maximum(abs2.(fftshift(vec(run["uomega0"])))) for run in all_runs)

for (i, run) in enumerate(all_runs)
    ax = axes5[i]
    df_THz = run["df_THz"]

    # Input power spectrum in dB (relative to global peak)
    spec_power = abs2.(fftshift(vec(run["uomega0"])))
    spec_dB = 10.0 .* log10.(spec_power ./ P_peak_global .+ 1e-30)

    ax.plot(df_THz, spec_dB; color=COLOR_INPUT, lw=1.5, label="Input spectrum")

    # Shade Raman band region
    ax.axvspan(-30.0, -13.2; alpha=0.12, color=COLOR_RAMAN, label="Raman band")
    ax.axvline(-13.2; color=COLOR_RAMAN, lw=1.0, ls="--")

    # J annotations — convert to dB for display
    J_before = Float64(run["J_before"])
    J_after  = Float64(run["J_after"])
    J_before_dB = 10.0 * log10(J_before + 1e-30)
    J_after_dB  = 10.0 * log10(J_after  + 1e-30)
    delta_J_dB  = J_after_dB - J_before_dB

    ann_text = @sprintf("J_before = %.1f dB\nJ_after  = %.1f dB\nΔdB = %.1f dB",
                        J_before_dB, J_after_dB, delta_J_dB)
    ax.text(0.98, 0.95, ann_text;
            transform=ax.transAxes, ha="right", va="top", fontsize=9,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

    ax.set_title(run_label(run); fontsize=10)
    ax.set_ylabel("PSD (dB)")
    ax.set_ylim(-65, 5)
    ax.axhline(0; color="black", lw=0.5, ls=":")
    ax.legend(loc="upper left", fontsize=8)

    if i == n_runs5
        ax.set_xlabel("Frequency offset from carrier (THz)")
    end
end

add_caption!(fig5, "Input spectra with Raman band annotated. J values from optimization (no re-propagation).")
fig5.tight_layout(rect=[0, 0.04, 1, 1], h_pad=2.5)
fig5.savefig("results/images/insight_05_raman_band_before_after.png"; dpi=300, bbox_inches="tight")
close(fig5)
@info "  Saved → results/images/insight_05_raman_band_before_after.png"

# ─────────────────────────────────────────────────────────────────────────────
# Section 8: Figure 6 — Group Delay Overlay (D-04 item 6)
# Group delay = d_phi/d_omega; omega in rad/THz → group delay in ps
# ─────────────────────────────────────────────────────────────────────────────

@info "▶ Generating Figure 6: group delay overlay"

fig6, ax6 = subplots(1, 1; figsize=(12, 6))

for (i, run) in enumerate(all_runs)
    phi_norm    = run["phi_norm"]
    df_THz      = run["df_THz"]
    signal_mask = run["signal_mask"]

    # Angular frequency step in rad/THz
    dw = 2π * (df_THz[2] - df_THz[1])  # rad/THz

    # Group delay: d_phi/d_omega [rad / (rad/THz)] = THz^-1 = ps
    gd_ps = _central_diff(phi_norm, dw)

    # Apply signal mask — set noise-floor bins to NaN for clean display
    gd_ps_masked = copy(gd_ps)
    gd_ps_masked[.!signal_mask] .= NaN

    ax6.plot(df_THz, gd_ps_masked;
             color=COLORS_5_RUNS[i], lw=1.5, label=run_label(run))
end

ax6.axvspan(-30.0, -13.2; alpha=0.08, color=COLOR_RAMAN, label="Raman band")
ax6.axvline(-13.2; color=COLOR_RAMAN, lw=0.8, ls="--")
ax6.axhline(0; color="black", lw=0.5, ls=":")

ax6.set_xlabel("Frequency offset from carrier (THz)")
ax6.set_ylabel("Group delay (ps)")
ax6.set_title("Group delay d\u03C6/d\u03C9 — temporal reshaping by optimizer")
ax6.legend(loc="upper left", fontsize=8)

add_caption!(fig6, "Group delay shows how the optimizer redistributes pulse arrival time vs frequency.")
fig6.tight_layout(rect=[0, 0.04, 1, 1])
fig6.savefig("results/images/insight_06_group_delay_overlay.png"; dpi=300, bbox_inches="tight")
close(fig6)
@info "  Saved → results/images/insight_06_group_delay_overlay.png"

# ─────────────────────────────────────────────────────────────────────────────
# Section 9: Figure 7 — Polynomial Fit Residual Overlay (D-04 item 7)
# THE key figure: shows the 99% unexplained phase structure
# ─────────────────────────────────────────────────────────────────────────────

@info "▶ Generating Figure 7: polynomial fit residual overlay (key insight figure)"

fig7, ax7 = subplots(1, 1; figsize=(12, 6))

for (i, run) in enumerate(all_runs)
    phi_norm    = run["phi_norm"]
    df_THz      = run["df_THz"]
    signal_mask = run["signal_mask"]
    decomp      = run["decomp"]

    # Reconstruct the polynomial fit on the full fftshifted frequency grid
    omega_rad_s = 2π .* df_THz .* 1e12     # THz → rad/s
    gdd_s2 = decomp.gdd_fs2 * 1e-30        # fs² → s²
    tod_s3 = decomp.tod_fs3 * 1e-45        # fs³ → s³
    phi_poly = gdd_s2 .* omega_rad_s.^2 ./ 2.0 .+ tod_s3 .* omega_rad_s.^3 ./ 6.0

    # Residual: phi_norm minus polynomial fit
    residual = phi_norm .- phi_poly

    # Apply signal mask for clean display
    residual_masked = copy(residual)
    residual_masked[.!signal_mask] .= NaN

    label_str = run_label(run) * @sprintf(" (res %.1f%%)", decomp.residual_fraction * 100)
    ax7.plot(df_THz, residual_masked;
             color=COLORS_5_RUNS[i], lw=1.5, label=label_str)
end

ax7.axvspan(-30.0, -13.2; alpha=0.08, color=COLOR_RAMAN, label="Raman band")
ax7.axvline(-13.2; color=COLOR_RAMAN, lw=0.8, ls="--")
ax7.axhline(0; color="black", lw=0.5, ls=":")

ax7.set_xlabel("Frequency offset from carrier (THz)")
ax7.set_ylabel("Phase residual (rad)")
ax7.set_title("Polynomial fit residual — the unexplained phase structure")
ax7.legend(loc="upper left", fontsize=8)

add_caption!(fig7, "Residual after removing GDD+TOD fit. 98.9-99.9% of phase variance lives here.")
fig7.tight_layout(rect=[0, 0.04, 1, 1])
fig7.savefig("results/images/insight_07_residual_overlay.png"; dpi=300, bbox_inches="tight")
close(fig7)
@info "  Saved → results/images/insight_07_residual_overlay.png"

# ─────────────────────────────────────────────────────────────────────────────
# Section 10: Figure 8 — Phase Structure at Raman Offset Zoom (D-04 item 8)
# Zoom into [-20, -8] THz to reveal whether optimizer targets 13.2 THz specifically
# ─────────────────────────────────────────────────────────────────────────────

@info "▶ Generating Figure 8: phase structure near Raman band offset (zoom)"

fig8, ax8 = subplots(1, 1; figsize=(12, 6))

for (i, run) in enumerate(all_runs)
    phi_norm    = run["phi_norm"]
    df_THz      = run["df_THz"]
    signal_mask = run["signal_mask"]

    # Extract Raman-band frequency window
    zoom_mask = (-20.0 .< df_THz .< -8.0) .& signal_mask

    if any(zoom_mask)
        ax8.plot(df_THz[zoom_mask], phi_norm[zoom_mask];
                 color=COLORS_5_RUNS[i], lw=1.5, label=run_label(run))
    end
end

# Mark the 13.2 THz Raman peak
ax8.axvline(-13.2; color=COLOR_RAMAN, lw=1.5, ls="--", label="13.2 THz Raman peak")
ax8.axhline(0; color="black", lw=0.5, ls=":")

ax8.set_xlabel("Frequency offset from carrier (THz)")
ax8.set_ylabel("Normalized phase (rad)")
ax8.set_title("Phase structure near Raman band offset")
ax8.set_xlim(-20, -8)
ax8.legend(loc="upper left", fontsize=8)

add_caption!(fig8, "Zoom into [-20, -8] THz showing phase behavior at the 13.2 THz Raman shift.")
fig8.tight_layout(rect=[0, 0.04, 1, 1])
fig8.savefig("results/images/insight_08_phase_raman_zoom.png"; dpi=300, bbox_inches="tight")
close(fig8)
@info "  Saved → results/images/insight_08_phase_raman_zoom.png"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

@info """
┌──────────────────────────────────────────────────────────────────────────────
│ Physics Insight — Figure Generation Complete
├──────────────────────────────────────────────────────────────────────────────
│  Fig 1: results/images/insight_01_phi_overlay_freq.png
│  Fig 2: results/images/insight_02_phi_overlay_lambda.png
│  Fig 3: results/images/insight_03_phi_detail_panels.png
│  Fig 4: results/images/insight_04_correlation_scatter.png
│  Fig 5: results/images/insight_05_raman_band_before_after.png
│  Fig 6: results/images/insight_06_group_delay_overlay.png
│  Fig 7: results/images/insight_07_residual_overlay.png
│  Fig 8: results/images/insight_08_phase_raman_zoom.png
└──────────────────────────────────────────────────────────────────────────────
"""

end  # if abspath(PROGRAM_FILE) == @__FILE__
