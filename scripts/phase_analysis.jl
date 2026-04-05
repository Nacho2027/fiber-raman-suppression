"""
Phase Decomposition & Cross-Sweep Structural Analysis — Phase 9.1

Decomposes all 34 optimized spectral phase profiles (24 sweep + 10 multi-start)
onto a physical basis (polynomial chirp up to 6th order + residual PSD), quantifies
structural similarity across fiber parameters, and determines whether optimal phases
cluster by physical regime or are uncorrelated.

Figures produced (all -> results/images/):
  01. physics_09_01_explained_variance_vs_order.png — Explained variance vs polynomial order (H1)
  02. physics_09_02_gdd_tod_vs_params.png           — GDD/TOD vs fiber parameters
  03. physics_09_03_residual_psd_waterfall.png       — Residual PSD waterfall (H2)
  04. physics_09_04_phi_overlay_all_sweep.png        — Normalized phi overlay all 24 sweep
  05. physics_09_05_decomposition_detail.png         — Best/worst polynomial decomposition
  06. physics_09_06_correlation_matrix.png           — Pairwise correlation matrix (H4)
  07. physics_09_07_similarity_by_grouping.png       — Similarity by physical grouping
  08. physics_09_08_multistart_overlay.png           — Multi-start overlay (H6)
  09. physics_09_09_phase_by_regime.png              — Phase colored by physical regime
  10. physics_09_10_coefficient_scaling.png          — Polynomial coefficient scaling

Data sources:
  - 24 sweep points: results/raman/sweeps/{smf28,hnlf}/L*_P*/opt_result.jld2
  - 10 multi-start:  results/raman/sweeps/multistart/start_*/opt_result.jld2

Include guard: safe to include multiple times.
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
using Interpolations

include("common.jl")
include("visualization.jl")
include("physics_insight.jl")

if !(@isdefined _PHASE_ANALYSIS_JL_LOADED)
const _PHASE_ANALYSIS_JL_LOADED = true

# Fiber betas lookup (betas field is empty in JLD2; recover from fiber name)
const PA_FIBER_BETAS = Dict(
    "SMF-28" => [-2.17e-26, 1.2e-40],
    "HNLF"   => [-0.5e-26, 1.0e-40],
)

const PA_REP_RATE = 80.5e6
const PA_SECH2_FACTOR = 0.881374

"""
    pa_peak_power(P_cont_W, fwhm_fs)

Peak power for sech^2 pulse from continuum power and FWHM in fs.
"""
function pa_peak_power(P_cont_W, fwhm_fs)
    fwhm_s = fwhm_fs * 1e-15
    return PA_SECH2_FACTOR * P_cont_W / (fwhm_s * PA_REP_RATE)
end

"""
    pa_extended_poly_fit(omega_sig, phi_detrended, max_ord)

Fit polynomial orders 2..max_ord on NORMALIZED omega to avoid Vandermonde overflow.
Returns (coeffs_physical, explained_var, residual_vec).
coeffs_physical[k-1] has units rad*s^k for order k.
"""
function pa_extended_poly_fit(omega_sig, phi_detrended, max_ord)
    # Normalize omega to [-1, 1] to avoid catastrophic Vandermonde conditioning
    omega_lo = omega_sig[1]
    omega_hi = omega_sig[end]
    omega_range = omega_hi - omega_lo
    if abs(omega_range) < 1e-20
        return zeros(max_ord - 1), 0.0, phi_detrended
    end
    omega_norm = 2.0 .* (omega_sig .- omega_lo) ./ omega_range .- 1.0

    # Build Vandermonde on normalized omega with factorial normalization
    n_cols = max_ord - 1  # orders 2..max_ord
    A_norm = zeros(length(omega_norm), n_cols)
    for k in 2:max_ord
        A_norm[:, k-1] = omega_norm .^ k ./ factorial(k)
    end

    # QR solve for stability
    coeffs_norm = qr(A_norm) \ phi_detrended

    phi_fit = A_norm * coeffs_norm
    residual_vec = phi_detrended .- phi_fit
    var_total = dot(phi_detrended, phi_detrended)
    var_residual = dot(residual_vec, residual_vec)
    explained_var = var_total > 1e-30 ? 1.0 - var_residual / var_total : 0.0

    # Convert normalized coefficients back to physical (rad*s^k) units.
    # If omega_norm = 2*(omega - omega_lo)/R - 1, then d(omega_norm) = 2*d(omega)/R
    # so omega_norm^k = (2/R)^k * (omega - omega_lo - R/2)^k via binomial expansion.
    # However, for the explained variance and residual we already have the right values.
    # For physical coefficients, we refit on physical omega with a well-conditioned approach.
    # Since we only need coefficients for orders 2-6, and the physical omega is huge (rad/s ~1e15),
    # we store them as "normalized-basis" coefficients and convert for display only.
    #
    # For physical GDD/TOD etc, we use the chain rule:
    # c_phys_k = c_norm_k * (2/R)^k  where R = omega_range
    scale = 2.0 / omega_range
    coeffs_physical = zeros(n_cols)
    for j in 1:n_cols
        k = j + 1  # polynomial order
        coeffs_physical[j] = coeffs_norm[j] * scale^k
    end

    return coeffs_physical, explained_var, residual_vec
end

end  # include guard

# ===========================================================================
# Main execution
# ===========================================================================

if abspath(PROGRAM_FILE) == @__FILE__

@info "========================================================================"
@info " Phase 9.1: Phase Decomposition & Cross-Sweep Structural Analysis"
@info "========================================================================"

# ───────────────────────────────────────────────────────────────────────────
# Section 1: Data Loading
# ───────────────────────────────────────────────────────────────────────────

@info "Section 1: Loading all 34 opt_result.jld2 files"

PA_all_points = Dict{String,Any}[]

# Load sweep data
for (fiber_dir, fiber_preset) in [("smf28", "SMF-28"), ("hnlf", "HNLF")]
    sweep_base = joinpath("results", "raman", "sweeps", fiber_dir)
    for d in sort(readdir(sweep_base))
        d == "SWEEP_SUMMARY.md" && continue
        jld2_path = joinpath(sweep_base, d, "opt_result.jld2")
        isfile(jld2_path) || continue
        data = JLD2.load(jld2_path)
        point = Dict{String,Any}(data)
        point["is_multistart"] = false
        point["source_dir"] = "$fiber_dir/$d"

        # Look up betas from fiber name since JLD2 stores empty vector
        betas_phys = PA_FIBER_BETAS[fiber_preset]
        if isempty(point["betas"])
            point["betas"] = betas_phys
        end

        # Compute derived quantities
        fwhm_fs = Float64(point["fwhm_fs"])
        P_cont_W = Float64(point["P_cont_W"])
        P_peak = pa_peak_power(P_cont_W, fwhm_fs)
        point["P_peak_W"] = P_peak

        beta2 = point["betas"][1]
        T0_s = fwhm_fs * 1e-15 / (2.0 * acosh(sqrt(2.0)))
        N_sol = sqrt(max(Float64(point["gamma"]) * P_peak * T0_s^2 / abs(beta2), 0.0))
        L_D = T0_s^2 / abs(beta2)
        point["soliton_number_N"] = N_sol
        point["L_D"] = L_D
        point["L_fiss"] = N_sol > 0 ? L_D / N_sol : Inf

        # Phase normalization
        Nt_run = Int(point["Nt"])
        sim_Dt_ps = Float64(point["sim_Dt"])
        phi_opt = vec(point["phi_opt"])
        uomega0 = vec(point["uomega0"])
        norm_result = normalize_phase(phi_opt, uomega0, sim_Dt_ps, Nt_run)
        point["phi_norm"] = norm_result.phi_norm
        point["df_THz"] = norm_result.df_THz
        point["signal_mask"] = norm_result.signal_mask

        push!(PA_all_points, point)
    end
end

# Load multistart data
for d in sort(readdir(joinpath("results", "raman", "sweeps", "multistart")))
    jld2_path = joinpath("results", "raman", "sweeps", "multistart", d, "opt_result.jld2")
    isfile(jld2_path) || continue
    data = JLD2.load(jld2_path)
    point = Dict{String,Any}(data)
    point["is_multistart"] = true
    point["source_dir"] = "multistart/$d"

    fiber_name = point["fiber_name"]
    betas_phys = PA_FIBER_BETAS[fiber_name]
    if isempty(point["betas"])
        point["betas"] = betas_phys
    end

    fwhm_fs = Float64(point["fwhm_fs"])
    P_cont_W = Float64(point["P_cont_W"])
    P_peak = pa_peak_power(P_cont_W, fwhm_fs)
    point["P_peak_W"] = P_peak

    beta2 = point["betas"][1]
    T0_s = fwhm_fs * 1e-15 / (2.0 * acosh(sqrt(2.0)))
    N_sol = sqrt(max(Float64(point["gamma"]) * P_peak * T0_s^2 / abs(beta2), 0.0))
    L_D = T0_s^2 / abs(beta2)
    point["soliton_number_N"] = N_sol
    point["L_D"] = L_D
    point["L_fiss"] = N_sol > 0 ? L_D / N_sol : Inf

    Nt_run = Int(point["Nt"])
    sim_Dt_ps = Float64(point["sim_Dt"])
    phi_opt = vec(point["phi_opt"])
    uomega0 = vec(point["uomega0"])
    norm_result = normalize_phase(phi_opt, uomega0, sim_Dt_ps, Nt_run)
    point["phi_norm"] = norm_result.phi_norm
    point["df_THz"] = norm_result.df_THz
    point["signal_mask"] = norm_result.signal_mask

    push!(PA_all_points, point)
end

n_sweep = count(p -> !p["is_multistart"], PA_all_points)
n_multi = count(p -> p["is_multistart"], PA_all_points)
@info "Loaded $n_sweep sweep + $n_multi multi-start = $(length(PA_all_points)) total points"

# ───────────────────────────────────────────────────────────────────────────
# Section 2: Extended Polynomial Decomposition (H1)
# ───────────────────────────────────────────────────────────────────────────

@info "Section 2: Extended polynomial decomposition (orders 2-6)"

for point in PA_all_points
    Nt_run = Int(point["Nt"])
    sim_Dt_ps = Float64(point["sim_Dt"])
    sim_Dt_s = sim_Dt_ps * 1e-12

    phi_opt = vec(point["phi_opt"])
    uomega0 = vec(point["uomega0"])

    # Build omega grid in rad/s (fftshifted)
    omega_shifted = 2pi .* fftshift(fftfreq(Nt_run, 1.0 / sim_Dt_s))

    # Signal mask at -40 dB
    spec_power = abs2.(fftshift(uomega0))
    P_peak_spec = maximum(spec_power)
    dB_mask = 10.0 .* log10.(spec_power ./ P_peak_spec .+ 1e-30)
    sig_mask = dB_mask .> -40.0

    omega_sig = omega_shifted[sig_mask]
    phi_shifted = fftshift(phi_opt)
    phi_sig = phi_shifted[sig_mask]

    # Remove offset + linear term
    A_lin = hcat(ones(length(omega_sig)), omega_sig)
    coeffs_lin = A_lin \ phi_sig
    phi_detrended = phi_sig .- A_lin * coeffs_lin

    # Fit for orders 2 through 6
    explained_variances = Float64[]
    all_coeffs = Vector{Float64}[]
    all_residuals = Vector{Float64}[]

    for max_ord in 2:6
        coeffs_phys, ev, resid = pa_extended_poly_fit(omega_sig, phi_detrended, max_ord)
        push!(explained_variances, ev)
        push!(all_coeffs, coeffs_phys)
        push!(all_residuals, resid)
    end

    point["explained_variances"] = explained_variances  # [order2, order3, ..., order6]
    point["poly_coeffs"] = all_coeffs                    # coeffs at each max_order
    point["poly_residuals"] = all_residuals
    point["omega_sig"] = omega_sig
    point["phi_detrended"] = phi_detrended

    # Convert order-6 coefficients to display units
    # coeffs_physical[j] has units rad * (2/R)^(j+1) * (1/factorial(j+1))
    # For GDD: order 2 coefficient in s^2 -> fs^2 (*1e30)
    # For TOD: order 3 coefficient in s^3 -> fs^3 (*1e45)
    c6 = all_coeffs[5]  # max_ord=6 coefficients
    if length(c6) >= 1
        point["GDD_fs2"] = c6[1] * 1e30
    else
        point["GDD_fs2"] = 0.0
    end
    if length(c6) >= 2
        point["TOD_fs3"] = c6[2] * 1e45
    else
        point["TOD_fs3"] = 0.0
    end
    if length(c6) >= 3
        point["FOD_fs4"] = c6[3] * 1e60
    else
        point["FOD_fs4"] = 0.0
    end
    if length(c6) >= 4
        point["fifth_fs5"] = c6[4] * 1e75
    else
        point["fifth_fs5"] = 0.0
    end
end

# Print summary table
@info "Explained variance summary (fraction of detrended phase variance):"
println()
@printf("%-25s %6s %6s %6s %6s %6s %8s %10s\n",
    "Source", "Ord2", "Ord3", "Ord4", "Ord5", "Ord6", "N_sol", "delta_dB")
println("-"^95)
for p in PA_all_points
    ev = p["explained_variances"]
    @printf("%-25s %5.1f%% %5.1f%% %5.1f%% %5.1f%% %5.1f%% %7.1f %9.1f\n",
        p["source_dir"],
        ev[1]*100, ev[2]*100, ev[3]*100, ev[4]*100, ev[5]*100,
        p["soliton_number_N"], Float64(p["delta_J_dB"]))
end
println()

# ───────────────────────────────────────────────────────────────────────────
# Section 3: Residual PSD Analysis (H2)
# ───────────────────────────────────────────────────────────────────────────

@info "Section 3: Residual PSD analysis (testing 13 THz hypothesis)"

for point in PA_all_points
    resid_ord6 = point["poly_residuals"][5]  # order-6 residual
    omega_sig = point["omega_sig"]

    if length(resid_ord6) < 4
        point["psd_mod_freq_THz"] = Float64[]
        point["psd_dB"] = Float64[]
        continue
    end

    # Zero-pad for spectral resolution
    N_pad = nextpow(2, 4 * length(resid_ord6))
    padded = zeros(N_pad)
    padded[1:length(resid_ord6)] = resid_ord6

    # PSD of residual phase in "modulation frequency" space
    # Independent variable is omega (rad/s), conjugate is time delay (s)
    d_omega = omega_sig[2] - omega_sig[1]  # rad/s spacing
    psd_raw = abs2.(fft(padded))

    # Conjugate delay axis:
    # Julia fftfreq(N, fs) computes k*fs/N. We want k/(N*d_omega) in s/rad.
    # So pass fs = 1/d_omega: fftfreq(N, 1/d_omega) = k/(N*d_omega) [s/rad].
    # A phase oscillation at Delta_omega (rad/s) appears at tau = 1/Delta_omega [s/rad].
    # Physical delay: tau_phys = 2*pi * tau_srad [seconds].
    # Raman: Delta_omega = 2*pi*13e12 -> tau_srad = 1/(2*pi*13e12) -> tau_phys = 77 fs.
    tau_srad = fftfreq(N_pad, 1.0 / d_omega)  # s/rad
    mod_delay_fs = 2pi .* tau_srad .* 1e15     # femtoseconds

    # Take positive half only
    n_half = N_pad ÷ 2
    psd_half = psd_raw[1:n_half]
    delay_half = mod_delay_fs[1:n_half]

    # Normalize PSD to dB
    psd_max = maximum(psd_half[2:end])  # skip DC
    psd_dB = 10.0 .* log10.(psd_half ./ (psd_max + 1e-30) .+ 1e-30)

    point["psd_mod_delay_fs"] = delay_half
    point["psd_dB"] = psd_dB
end

# ───────────────────────────────────────────────────────────────────────────
# Section 4: Figures 01-05
# ───────────────────────────────────────────────────────────────────────────

mkpath("results/images")

# Separate sweep and multistart
sweep_points = filter(p -> !p["is_multistart"], PA_all_points)
multi_points = filter(p -> p["is_multistart"], PA_all_points)
smf_points = filter(p -> p["fiber_name"] == "SMF-28" && !p["is_multistart"], PA_all_points)
hnlf_points = filter(p -> p["fiber_name"] == "HNLF" && !p["is_multistart"], PA_all_points)

# --- Figure 09-01: Explained variance vs polynomial order ---
@info "Generating Figure 09-01: Explained variance vs polynomial order"

fig01, (ax01a, ax01b) = subplots(1, 2; figsize=(14, 6))

for (ax, points, title) in [(ax01a, smf_points, "SMF-28"), (ax01b, hnlf_points, "HNLF")]
    N_sols = [p["soliton_number_N"] for p in points]
    N_min, N_max = extrema(N_sols)
    cmap = PyPlot.cm.viridis

    for p in points
        ev = p["explained_variances"]
        N_norm = N_max > N_min ? (p["soliton_number_N"] - N_min) / (N_max - N_min) : 0.5
        color = cmap(N_norm)
        ax.plot(2:6, ev .* 100;
            color=color, lw=1.5, marker="o", ms=4,
            label=@sprintf("L=%.0fm P=%.2fW N=%.1f", Float64(p["L_m"]), Float64(p["P_cont_W"]), p["soliton_number_N"]))
    end

    ax.axhline(90; color="gray", ls="--", lw=0.8, alpha=0.5)
    ax.axhline(50; color="gray", ls=":", lw=0.8, alpha=0.5)
    ax.text(6.05, 90, "90%"; fontsize=8, color="gray", va="center")
    ax.text(6.05, 50, "50%"; fontsize=8, color="gray", va="center")

    ax.set_xlabel("Maximum polynomial order")
    ax.set_ylabel("Explained variance (%)")
    ax.set_title(title)
    ax.set_xlim(1.8, 6.2)
    ax.set_ylim(-5, 105)
    ax.set_xticks(2:6)
    ax.legend(fontsize=6, ncol=2, loc="upper left")
end

fig01.suptitle("Explained variance of phi_opt by polynomial order (H1)"; fontsize=14)
add_caption!(fig01, "Color: N_sol (viridis). Horizontal lines at 50% and 90% thresholds.")
fig01.tight_layout(rect=[0, 0.04, 1, 0.96])
fig01.savefig("results/images/physics_09_01_explained_variance_vs_order.png"; dpi=300, bbox_inches="tight")
close(fig01)
@info "  Saved -> results/images/physics_09_01_explained_variance_vs_order.png"


# --- Figure 09-02: GDD and TOD vs fiber parameters ---
@info "Generating Figure 09-02: GDD and TOD vs fiber parameters"

fig02, axes02 = subplots(2, 3; figsize=(16, 10))

param_getters = [
    p -> Float64(p["L_m"]),
    p -> Float64(p["P_cont_W"]),
    p -> p["soliton_number_N"],
]
param_labels = ["Fiber length L (m)", "Continuum power P (W)", "Soliton number N"]

for (col, (getter, xlabel)) in enumerate(zip(param_getters, param_labels))
    ax_gdd = axes02[1, col]
    ax_tod = axes02[2, col]

    for p in sweep_points
        x_val = getter(p)
        is_smf = p["fiber_name"] == "SMF-28"
        color = is_smf ? "#0072B2" : "#E69F00"
        marker = p["converged"] ? "o" : "s"
        fc = p["converged"] ? color : "none"

        ax_gdd.scatter([x_val], [p["GDD_fs2"]];
            color=color, marker=marker, s=60, facecolors=fc, edgecolors=color, linewidths=1.5, zorder=3)
        ax_tod.scatter([x_val], [p["TOD_fs3"]];
            color=color, marker=marker, s=60, facecolors=fc, edgecolors=color, linewidths=1.5, zorder=3)
    end

    ax_gdd.set_xlabel(xlabel)
    ax_gdd.set_ylabel("GDD (fs\u00B2)")
    ax_tod.set_xlabel(xlabel)
    ax_tod.set_ylabel("TOD (fs\u00B3)")

    if col == 1
        ax_gdd.set_title("(a) GDD vs L")
        ax_tod.set_title("(d) TOD vs L")
    elseif col == 2
        ax_gdd.set_title("(b) GDD vs P")
        ax_tod.set_title("(e) TOD vs P")
    else
        ax_gdd.set_title("(c) GDD vs N")
        ax_tod.set_title("(f) TOD vs N")
    end

    ax_gdd.axhline(0; color="black", lw=0.5, ls=":")
    ax_tod.axhline(0; color="black", lw=0.5, ls=":")
end

# Legend
from_legend = [
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="#0072B2", markersize=8, label="SMF-28"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="#E69F00", markersize=8, label="HNLF"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="gray", markersize=8, label="Converged"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="s", color="w",
        markerfacecolor="none", markeredgecolor="gray", markeredgewidth=1.5,
        markersize=8, label="Not converged"),
]
fig02.legend(handles=from_legend; loc="lower center", ncol=4, fontsize=9, bbox_to_anchor=(0.5, -0.02))

fig02.suptitle("GDD and TOD coefficients vs fiber parameters"; fontsize=14)
add_caption!(fig02, "Polynomial order 6 fit; coefficients from normalized-basis fitting.")
fig02.tight_layout(rect=[0, 0.04, 1, 0.96])
fig02.savefig("results/images/physics_09_02_gdd_tod_vs_params.png"; dpi=300, bbox_inches="tight")
close(fig02)
@info "  Saved -> results/images/physics_09_02_gdd_tod_vs_params.png"


# --- Figure 09-03: Residual PSD waterfall ---
@info "Generating Figure 09-03: Residual PSD waterfall"

fig03, ax03 = subplots(1, 1; figsize=(14, 10))

n_sweep_pts = length(sweep_points)
offset_step = 15.0  # dB offset between traces

cmap_03 = PyPlot.cm.tab20
for (i, p) in enumerate(sweep_points)
    delay_fs = p["psd_mod_delay_fs"]
    psd_dB = p["psd_dB"]

    if isempty(delay_fs)
        continue
    end

    # Plot only positive delay up to 500 fs
    valid = (delay_fs .> 0) .& (delay_fs .< 500)
    if !any(valid)
        continue
    end

    y_offset = (n_sweep_pts - i) * offset_step
    color = cmap_03(mod(i - 1, 20) / 20.0)
    label = @sprintf("%s L=%.0fm P=%.3fW", p["fiber_name"], Float64(p["L_m"]), Float64(p["P_cont_W"]))

    ax03.plot(delay_fs[valid], psd_dB[valid] .+ y_offset;
        color=color, lw=0.8, label=label)
end

# Mark 77 fs (Raman detuning: 1/13THz)
ax03.axvline(77.0; color=COLOR_RAMAN, lw=2.0, ls="--", label="77 fs (1/13 THz Raman)")

ax03.set_xlabel("Modulation delay (fs)")
ax03.set_ylabel("PSD (dB, offset for visibility)")
ax03.set_title("Residual PSD waterfall after order-6 polynomial subtraction (H2)")
ax03.legend(fontsize=6, ncol=2, loc="upper right")
ax03.set_xlim(0, 400)

add_caption!(fig03, "Vertical dashed: 77 fs = 1/(13 THz) Raman detuning period. Each trace offset by $(Int(offset_step)) dB.")
fig03.tight_layout(rect=[0, 0.04, 1, 1])
fig03.savefig("results/images/physics_09_03_residual_psd_waterfall.png"; dpi=300, bbox_inches="tight")
close(fig03)
@info "  Saved -> results/images/physics_09_03_residual_psd_waterfall.png"


# --- Figure 09-04: Normalized phi overlay all sweep ---
@info "Generating Figure 09-04: Normalized phi overlay (all 24 sweep points)"

fig04, (ax04a, ax04b) = subplots(1, 2; figsize=(16, 7))

# Color by L, linestyle by P
L_colors = Dict(0.5 => "#0072B2", 1.0 => "#E69F00", 2.0 => "#009E73", 5.0 => "#CC79A7")
P_styles_smf = Dict(0.05 => "-", 0.1 => "--", 0.2 => ":")
P_styles_hnlf = Dict(0.005 => "-", 0.01 => "--", 0.03 => ":")

for (ax, points, title, P_styles) in [
    (ax04a, smf_points, "SMF-28 (12 sweep points)", P_styles_smf),
    (ax04b, hnlf_points, "HNLF (12 sweep points)", P_styles_hnlf)]

    for p in points
        mask = p["signal_mask"]
        df = p["df_THz"]
        phi = p["phi_norm"]
        L_val = Float64(p["L_m"])
        P_val = Float64(p["P_cont_W"])

        color = get(L_colors, L_val, "black")
        ls = get(P_styles, P_val, "-")

        ax.plot(df[mask], phi[mask];
            color=color, ls=ls, lw=1.0,
            label=@sprintf("L=%.1fm P=%.3fW", L_val, P_val))
    end

    # Shade Raman band
    ax.axvspan(-30.0, -13.2; alpha=0.08, color=COLOR_RAMAN, label="Raman band")
    ax.axvline(-13.2; color=COLOR_RAMAN, lw=0.8, ls="--")
    ax.axhline(0; color="black", lw=0.5, ls=":")

    ax.set_xlabel("Frequency offset (THz)")
    ax.set_ylabel("Normalized phase (rad)")
    ax.set_title(title)
    ax.legend(fontsize=6, ncol=2, loc="upper left")
end

fig04.suptitle("Optimized spectral phase — all 24 sweep points (D-04)"; fontsize=14)
add_caption!(fig04, "Color: fiber length. Linestyle: power level. Offset/slope removed.")
fig04.tight_layout(rect=[0, 0.04, 1, 0.96])
fig04.savefig("results/images/physics_09_04_phi_overlay_all_sweep.png"; dpi=300, bbox_inches="tight")
close(fig04)
@info "  Saved -> results/images/physics_09_04_phi_overlay_all_sweep.png"


# --- Figure 09-05: Decomposition detail (best/worst) ---
@info "Generating Figure 09-05: Decomposition detail (best/worst explained variance)"

ev6_all = [(p["explained_variances"][5], i, p) for (i, p) in enumerate(sweep_points)]
sort!(ev6_all; by=x -> x[1])

# 2 lowest, 2 highest
worst_2 = ev6_all[1:min(2, length(ev6_all))]
best_2 = ev6_all[max(1, end-1):end]
detail_points = vcat(worst_2, best_2)

fig05, axes05 = subplots(2, 2; figsize=(16, 12))
axes05_flat = [axes05[1,1], axes05[1,2], axes05[2,1], axes05[2,2]]

for (panel_idx, (ev6, _, p)) in enumerate(detail_points)
    if panel_idx > 4 break end
    ax = axes05_flat[panel_idx]

    omega_sig = p["omega_sig"]
    phi_det = p["phi_detrended"]
    resid = p["poly_residuals"][5]

    # Reconstruct the order-6 fit
    phi_fit = phi_det .- resid

    # Convert omega to THz for display
    omega_THz = omega_sig ./ (2pi * 1e12)

    ax.plot(omega_THz, phi_det; color="#0072B2", lw=1.5, label="phi_detrended")
    ax.plot(omega_THz, phi_fit; color="#E69F00", lw=1.2, ls="--", label="Order-6 poly fit")
    ax.plot(omega_THz, resid; color="#009E73", lw=0.8, alpha=0.7, label="Residual")

    ax.axhline(0; color="black", lw=0.5, ls=":")
    ax.set_xlabel("Frequency offset (THz)")
    ax.set_ylabel("Phase (rad)")

    label_type = panel_idx <= 2 ? "WORST" : "BEST"
    ax.set_title(@sprintf("%s: %s (EV=%.1f%%)", label_type, p["source_dir"], ev6 * 100); fontsize=10)
    ax.legend(fontsize=8, loc="upper left")
end

fig05.suptitle("Extended polynomial decomposition detail (best/worst cases)"; fontsize=14)
add_caption!(fig05, "Top: lowest explained variance. Bottom: highest. Order-6 polynomial fit.")
fig05.tight_layout(rect=[0, 0.04, 1, 0.96])
fig05.savefig("results/images/physics_09_05_decomposition_detail.png"; dpi=300, bbox_inches="tight")
close(fig05)
@info "  Saved -> results/images/physics_09_05_decomposition_detail.png"


# ───────────────────────────────────────────────────────────────────────────
# Section 5: Phase Profile Similarity Matrix (H4)
# ───────────────────────────────────────────────────────────────────────────

@info "Section 5: Computing pairwise similarity matrix"

n_sw = length(sweep_points)

# Find common frequency range across all sweep points
all_df_min = maximum(minimum(p["df_THz"][p["signal_mask"]]) for p in sweep_points)
all_df_max = minimum(maximum(p["df_THz"][p["signal_mask"]]) for p in sweep_points)

# Common grid: use the coarsest resolution
all_dfs = [p["df_THz"][2] - p["df_THz"][1] for p in sweep_points]
df_step = maximum(all_dfs)
common_df = collect(range(all_df_min, all_df_max; step=df_step))

@info @sprintf("  Common frequency grid: %.1f to %.1f THz, %d points, step=%.4f THz",
    all_df_min, all_df_max, length(common_df), df_step)

# Interpolate all sweep profiles onto common grid
interp_profiles = Vector{Vector{Float64}}(undef, n_sw)
for (i, p) in enumerate(sweep_points)
    mask = p["signal_mask"]
    df_masked = p["df_THz"][mask]
    phi_masked = p["phi_norm"][mask]

    # Sort by frequency (should already be sorted for fftshifted data)
    sort_idx = sortperm(df_masked)
    df_sorted = df_masked[sort_idx]
    phi_sorted = phi_masked[sort_idx]

    # Ensure unique x values (remove duplicates)
    unique_mask = [true; diff(df_sorted) .> 0]
    df_unique = df_sorted[unique_mask]
    phi_unique = phi_sorted[unique_mask]

    if length(df_unique) < 2
        interp_profiles[i] = zeros(length(common_df))
        continue
    end

    itp = LinearInterpolation(df_unique, phi_unique; extrapolation_bc=0.0)
    interp_profiles[i] = itp.(common_df)
end

# Pairwise normalized cross-correlation
corr_matrix = zeros(n_sw, n_sw)
for i in 1:n_sw
    for j in 1:n_sw
        pi_prof = interp_profiles[i]
        pj_prof = interp_profiles[j]
        ni = norm(pi_prof)
        nj = norm(pj_prof)
        if ni > 1e-30 && nj > 1e-30
            corr_matrix[i, j] = dot(pi_prof, pj_prof) / (ni * nj)
        end
    end
end

# Cosine similarity of polynomial coefficient vectors
coeff_sim_matrix = zeros(n_sw, n_sw)
for i in 1:n_sw
    for j in 1:n_sw
        ci = sweep_points[i]["poly_coeffs"][5]  # order-6
        cj = sweep_points[j]["poly_coeffs"][5]
        ni = norm(ci)
        nj = norm(cj)
        if ni > 1e-30 && nj > 1e-30
            coeff_sim_matrix[i, j] = dot(ci, cj) / (ni * nj)
        end
    end
end

# ───────────────────────────────────────────────────────────────────────────
# Section 6: Clustering Analysis (H4)
# ───────────────────────────────────────────────────────────────────────────

@info "Section 6: Clustering analysis"

# Distance matrix
dist_matrix = 1.0 .- abs.(corr_matrix)

# Simple agglomerative clustering (average linkage)
# For 24 points this is trivial
function agglomerative_cluster(D)
    n = size(D, 1)
    clusters = [[i] for i in 1:n]
    merge_history = Tuple{Int,Int,Float64}[]
    active = collect(1:n)

    D_work = copy(D)
    for _ in 1:(n-1)
        # Find closest pair among active clusters
        best_dist = Inf
        best_i, best_j = 0, 0
        for ii in 1:length(active)
            for jj in (ii+1):length(active)
                ci, cj = active[ii], active[jj]
                # Average linkage
                d_avg = 0.0
                count = 0
                for a in clusters[ci]
                    for b in clusters[cj]
                        d_avg += D[a, b]
                        count += 1
                    end
                end
                d_avg /= count
                if d_avg < best_dist
                    best_dist = d_avg
                    best_i, best_j = ii, jj
                end
            end
        end

        ci, cj = active[best_i], active[best_j]
        push!(merge_history, (ci, cj, best_dist))

        # Merge into ci
        append!(clusters[ci], clusters[cj])
        deleteat!(active, best_j)
    end

    return merge_history, clusters
end

merge_hist, final_clusters = agglomerative_cluster(dist_matrix)

# Compute silhouette-like scores for predefined groupings
function mean_within_between(corr_mat, labels)
    unique_labels = unique(labels)
    if length(unique_labels) < 2
        return 0.0, 0.0  # can't compute
    end
    within_corrs = Float64[]
    between_corrs = Float64[]
    n = size(corr_mat, 1)
    for i in 1:n
        for j in (i+1):n
            if labels[i] == labels[j]
                push!(within_corrs, abs(corr_mat[i, j]))
            else
                push!(between_corrs, abs(corr_mat[i, j]))
            end
        end
    end
    mean_w = isempty(within_corrs) ? 0.0 : mean(within_corrs)
    mean_b = isempty(between_corrs) ? 0.0 : mean(between_corrs)
    return mean_w, mean_b
end

# Groupings
group_fiber = [p["fiber_name"] for p in sweep_points]
group_nsol = [p["soliton_number_N"] > 2.0 ? "high_N" : "low_N" for p in sweep_points]
group_L = [Float64(p["L_m"]) > 1.0 ? "long" : "short" for p in sweep_points]
group_P_str = String[]
for p in sweep_points
    P_val = Float64(p["P_cont_W"])
    # For SMF-28: low=0.05, mid=0.1, high=0.2
    # For HNLF: low=0.005, mid=0.01, high=0.03
    # Use median as threshold
    push!(group_P_str, P_val > median([Float64(pp["P_cont_W"]) for pp in sweep_points]) ? "high_P" : "low_P")
end

grouping_names = ["Fiber type", "N_sol > 2", "L > 1m", "Power"]
grouping_labels = [group_fiber, group_nsol, group_L, group_P_str]

grouping_results = Tuple{String,Float64,Float64}[]
for (name, labels) in zip(grouping_names, grouping_labels)
    w, b = mean_within_between(corr_matrix, labels)
    push!(grouping_results, (name, w, b))
    @info @sprintf("  Grouping %-15s: within=%.3f  between=%.3f  gap=%.3f", name, w, b, w - b)
end


# ───────────────────────────────────────────────────────────────────────────
# Section 7: Multi-Start Structural Comparison (H6)
# ───────────────────────────────────────────────────────────────────────────

@info "Section 7: Multi-start structural comparison"

n_ms = length(multi_points)

# Interpolate multistart profiles onto common grid
ms_df_min = maximum(minimum(p["df_THz"][p["signal_mask"]]) for p in multi_points)
ms_df_max = minimum(maximum(p["df_THz"][p["signal_mask"]]) for p in multi_points)
ms_dfs = [p["df_THz"][2] - p["df_THz"][1] for p in multi_points]
ms_df_step = maximum(ms_dfs)
ms_common_df = collect(range(ms_df_min, ms_df_max; step=ms_df_step))

ms_interp_profiles = Vector{Vector{Float64}}(undef, n_ms)
for (i, p) in enumerate(multi_points)
    mask = p["signal_mask"]
    df_masked = p["df_THz"][mask]
    phi_masked = p["phi_norm"][mask]
    sort_idx = sortperm(df_masked)
    df_sorted = df_masked[sort_idx]
    phi_sorted = phi_masked[sort_idx]
    unique_mask = [true; diff(df_sorted) .> 0]
    df_unique = df_sorted[unique_mask]
    phi_unique = phi_sorted[unique_mask]

    if length(df_unique) < 2
        ms_interp_profiles[i] = zeros(length(ms_common_df))
        continue
    end

    itp = LinearInterpolation(df_unique, phi_unique; extrapolation_bc=0.0)
    ms_interp_profiles[i] = itp.(ms_common_df)
end

# 10x10 correlation matrix
ms_corr = zeros(n_ms, n_ms)
for i in 1:n_ms
    for j in 1:n_ms
        ni = norm(ms_interp_profiles[i])
        nj = norm(ms_interp_profiles[j])
        if ni > 1e-30 && nj > 1e-30
            ms_corr[i, j] = dot(ms_interp_profiles[i], ms_interp_profiles[j]) / (ni * nj)
        end
    end
end

# Report
ms_off_diag = [ms_corr[i,j] for i in 1:n_ms for j in (i+1):n_ms]
ms_mean_corr = mean(ms_off_diag)
ms_min_corr = minimum(ms_off_diag)
@info @sprintf("  Multi-start pairwise correlation: mean=%.3f, min=%.3f", ms_mean_corr, ms_min_corr)

if ms_mean_corr > 0.9
    @info "  Multi-start verdict: SINGLE BASIN (all solutions structurally similar)"
elseif ms_mean_corr > 0.5
    @info "  Multi-start verdict: BROAD BASIN (moderate structural similarity)"
else
    @info "  Multi-start verdict: MULTIPLE BASINS (distinct solution families)"
end


# ───────────────────────────────────────────────────────────────────────────
# Section 8: Figures 06-10
# ───────────────────────────────────────────────────────────────────────────

# --- Figure 09-06: Pairwise correlation matrix heatmap ---
@info "Generating Figure 09-06: Pairwise correlation matrix heatmap"

fig06, ax06 = subplots(1, 1; figsize=(14, 12))

# Reorder by hierarchical clustering
# Build ordering from merge history
function get_cluster_order(merge_hist, n)
    # Simple: use the order from agglomerative clustering
    # Flatten the final cluster
    clusters = [[i] for i in 1:n]
    order_list = Int[]
    for (ci, cj, _) in merge_hist
        # Find which existing clusters contain ci and cj members
    end
    # Simpler: just use fiber-type then L ordering
    return nothing
end

# Order by fiber type, then L, then P
sort_order = sortperm(sweep_points; by=p -> (p["fiber_name"], Float64(p["L_m"]), Float64(p["P_cont_W"])))
corr_sorted = corr_matrix[sort_order, sort_order]

labels_sorted = [@sprintf("%s L=%.1f P=%.3f", p["fiber_name"], Float64(p["L_m"]), Float64(p["P_cont_W"])) for p in sweep_points[sort_order]]

im06 = ax06.imshow(corr_sorted; cmap="RdBu_r", vmin=-1, vmax=1, aspect="auto")
fig06.colorbar(im06; ax=ax06, label="Normalized cross-correlation")

ax06.set_xticks(0:(n_sw-1))
ax06.set_xticklabels(labels_sorted; rotation=90, fontsize=7)
ax06.set_yticks(0:(n_sw-1))
ax06.set_yticklabels(labels_sorted; fontsize=7)
ax06.set_title("Pairwise phi_opt correlation matrix (H4 key result)")

# Draw box around fiber-type blocks
# After sorting by fiber name (alphabetical: "HNLF" < "SMF-28"), HNLF comes first
local hnlf_count = count(i -> sweep_points[sort_order[i]]["fiber_name"] == "HNLF", 1:n_sw)
# Draw boxes
rect1 = PyPlot.matplotlib.patches.Rectangle((-0.5, -0.5), hnlf_count, hnlf_count;
    linewidth=2, edgecolor="black", facecolor="none")
rect2 = PyPlot.matplotlib.patches.Rectangle((hnlf_count - 0.5, hnlf_count - 0.5),
    n_sw - hnlf_count, n_sw - hnlf_count;
    linewidth=2, edgecolor="black", facecolor="none")
ax06.add_patch(rect1)
ax06.add_patch(rect2)

add_caption!(fig06, "Rows/columns sorted by fiber type, then L, then P. Black boxes: same-fiber blocks.")
fig06.tight_layout(rect=[0, 0.04, 1, 1])
fig06.savefig("results/images/physics_09_06_correlation_matrix.png"; dpi=300, bbox_inches="tight")
close(fig06)
@info "  Saved -> results/images/physics_09_06_correlation_matrix.png"


# --- Figure 09-07: Similarity by physical grouping ---
@info "Generating Figure 09-07: Similarity by physical grouping"

fig07, ax07 = subplots(1, 1; figsize=(10, 6))

names_07 = [g[1] for g in grouping_results]
within_07 = [g[2] for g in grouping_results]
between_07 = [g[3] for g in grouping_results]

x_pos = collect(1:length(names_07))
width = 0.35

bars_w = ax07.bar(x_pos .- width/2, within_07; width=width, color="#0072B2", label="Within-group |corr|")
bars_b = ax07.bar(x_pos .+ width/2, between_07; width=width, color="#E69F00", label="Between-group |corr|")

ax07.set_xticks(x_pos)
ax07.set_xticklabels(names_07; fontsize=10)
ax07.set_ylabel("Mean |correlation|")
ax07.set_title("Phase similarity by physical grouping (H4)")
ax07.legend()
ax07.set_ylim(0, 1)

# Annotate gap
for (i, (name, w, b)) in enumerate(grouping_results)
    gap = w - b
    ax07.text(i, max(w, b) + 0.03, @sprintf("gap=%.3f", gap);
        ha="center", fontsize=9, color="dimgray")
end

add_caption!(fig07, "Higher within-group vs between-group correlation means that grouping explains phi structure.")
fig07.tight_layout(rect=[0, 0.04, 1, 1])
fig07.savefig("results/images/physics_09_07_similarity_by_grouping.png"; dpi=300, bbox_inches="tight")
close(fig07)
@info "  Saved -> results/images/physics_09_07_similarity_by_grouping.png"


# --- Figure 09-08: Multi-start overlay ---
@info "Generating Figure 09-08: Multi-start overlay"

fig08 = figure(figsize=(14, 8))
ax08_main = fig08.add_axes([0.08, 0.12, 0.62, 0.80])
ax08_inset = fig08.add_axes([0.74, 0.45, 0.23, 0.45])

J_finals = [Float64(p["J_after"]) for p in multi_points]
J_min, J_max = extrema(J_finals)

cmap_08 = PyPlot.cm.RdYlGn_r  # red=worst, green=best
for (i, p) in enumerate(multi_points)
    mask = p["signal_mask"]
    df = p["df_THz"]
    phi = p["phi_norm"]
    J_val = Float64(p["J_after"])

    # Normalize J for color
    J_norm = J_max > J_min ? (J_val - J_min) / (J_max - J_min) : 0.5
    color = cmap_08(J_norm)

    J_dB = 10.0 * log10(J_val + 1e-30)
    ax08_main.plot(df[mask], phi[mask];
        color=color, lw=1.0,
        label=@sprintf("start_%02d J=%.1f dB", i, J_dB))
end

ax08_main.axvspan(-30.0, -13.2; alpha=0.08, color=COLOR_RAMAN, label="Raman band")
ax08_main.axvline(-13.2; color=COLOR_RAMAN, lw=0.8, ls="--")
ax08_main.axhline(0; color="black", lw=0.5, ls=":")
ax08_main.set_xlabel("Frequency offset (THz)")
ax08_main.set_ylabel("Normalized phase (rad)")
ax08_main.set_title("Multi-start phi_opt overlay (H6 key result)")
ax08_main.legend(fontsize=7, ncol=2, loc="upper left")

# Inset: 10x10 correlation matrix
im08 = ax08_inset.imshow(ms_corr; cmap="RdBu_r", vmin=-1, vmax=1, aspect="auto")
ax08_inset.set_title(@sprintf("Corr matrix (mean=%.2f)", ms_mean_corr); fontsize=9)
ax08_inset.set_xticks(0:9)
ax08_inset.set_yticks(0:9)
ax08_inset.tick_params(labelsize=7)
fig08.colorbar(im08; ax=ax08_inset, fraction=0.046, pad=0.04)

J_spread_dB = 10.0 * log10(J_max + 1e-30) - 10.0 * log10(J_min + 1e-30)
add_caption!(fig08, @sprintf("10 random-start optimizations at L=2m, P=0.20W SMF-28. Mean corr=%.2f, J spread=%.1f dB.", ms_mean_corr, J_spread_dB))
fig08.savefig("results/images/physics_09_08_multistart_overlay.png"; dpi=300, bbox_inches="tight")
close(fig08)
@info "  Saved -> results/images/physics_09_08_multistart_overlay.png"


# --- Figure 09-09: Phase profiles colored by physical regime ---
@info "Generating Figure 09-09: Phase profiles colored by regime"

fig09, axes09 = subplots(2, 2; figsize=(16, 12))

# (a) Colored by N_sol
ax09a = axes09[1, 1]
N_vals = [p["soliton_number_N"] for p in sweep_points]
N_min_all, N_max_all = extrema(N_vals)
cmap_09 = PyPlot.cm.viridis

for p in sweep_points
    mask = p["signal_mask"]
    df = p["df_THz"]
    phi = p["phi_norm"]
    N_norm = N_max_all > N_min_all ? (p["soliton_number_N"] - N_min_all) / (N_max_all - N_min_all) : 0.5
    ax09a.plot(df[mask], phi[mask]; color=cmap_09(N_norm), lw=0.8)
end
ax09a.set_title("(a) Colored by soliton number N")
ax09a.set_xlabel("Frequency offset (THz)")
ax09a.set_ylabel("Phase (rad)")
sm_a = PyPlot.cm.ScalarMappable(; cmap=cmap_09, norm=PyPlot.matplotlib.colors.Normalize(N_min_all, N_max_all))
sm_a.set_array([])
fig09.colorbar(sm_a; ax=ax09a, label="N_sol")

# (b) Colored by L_m
ax09b = axes09[1, 2]
L_vals = [Float64(p["L_m"]) for p in sweep_points]
L_min_all, L_max_all = extrema(L_vals)

for p in sweep_points
    mask = p["signal_mask"]
    df = p["df_THz"]
    phi = p["phi_norm"]
    L_norm = L_max_all > L_min_all ? (Float64(p["L_m"]) - L_min_all) / (L_max_all - L_min_all) : 0.5
    ax09b.plot(df[mask], phi[mask]; color=cmap_09(L_norm), lw=0.8)
end
ax09b.set_title("(b) Colored by fiber length L")
ax09b.set_xlabel("Frequency offset (THz)")
ax09b.set_ylabel("Phase (rad)")
sm_b = PyPlot.cm.ScalarMappable(; cmap=cmap_09, norm=PyPlot.matplotlib.colors.Normalize(L_min_all, L_max_all))
sm_b.set_array([])
fig09.colorbar(sm_b; ax=ax09b, label="L (m)")

# (c) Colored by suppression depth
ax09c = axes09[2, 1]
dJ_vals = [Float64(p["delta_J_dB"]) for p in sweep_points]
dJ_min, dJ_max = extrema(dJ_vals)

for p in sweep_points
    mask = p["signal_mask"]
    df = p["df_THz"]
    phi = p["phi_norm"]
    dJ_norm = dJ_max > dJ_min ? (Float64(p["delta_J_dB"]) - dJ_min) / (dJ_max - dJ_min) : 0.5
    ax09c.plot(df[mask], phi[mask]; color=cmap_09(dJ_norm), lw=0.8)
end
ax09c.set_title("(c) Colored by suppression depth")
ax09c.set_xlabel("Frequency offset (THz)")
ax09c.set_ylabel("Phase (rad)")
sm_c = PyPlot.cm.ScalarMappable(; cmap=cmap_09, norm=PyPlot.matplotlib.colors.Normalize(dJ_min, dJ_max))
sm_c.set_array([])
fig09.colorbar(sm_c; ax=ax09c, label="delta_J (dB)")

# (d) SMF-28 vs HNLF overlay
ax09d = axes09[2, 2]
for p in sweep_points
    mask = p["signal_mask"]
    df = p["df_THz"]
    phi = p["phi_norm"]
    color = p["fiber_name"] == "SMF-28" ? "#0072B2" : "#E69F00"
    ax09d.plot(df[mask], phi[mask]; color=color, lw=0.8, alpha=0.6)
end
ax09d.set_title("(d) SMF-28 (blue) vs HNLF (orange)")
ax09d.set_xlabel("Frequency offset (THz)")
ax09d.set_ylabel("Phase (rad)")
# Manual legend
handles_09d = [
    PyPlot.matplotlib.lines.Line2D([0], [0]; color="#0072B2", lw=2, label="SMF-28"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; color="#E69F00", lw=2, label="HNLF"),
]
ax09d.legend(handles=handles_09d; fontsize=9)

for ax in [ax09a, ax09b, ax09c, ax09d]
    ax.axhline(0; color="black", lw=0.5, ls=":")
    ax.axvspan(-30.0, -13.2; alpha=0.05, color=COLOR_RAMAN)
end

fig09.suptitle("Phase profiles colored by physical regime"; fontsize=14)
add_caption!(fig09, "All 24 sweep points. Raman band shaded. Does any coloring reveal ordering?")
fig09.tight_layout(rect=[0, 0.04, 1, 0.96])
fig09.savefig("results/images/physics_09_09_phase_by_regime.png"; dpi=300, bbox_inches="tight")
close(fig09)
@info "  Saved -> results/images/physics_09_09_phase_by_regime.png"


# --- Figure 09-10: Polynomial coefficient scaling ---
@info "Generating Figure 09-10: Polynomial coefficient scaling"

fig10, axes10 = subplots(2, 2; figsize=(14, 10))

# Compute L/L_D for all sweep points
LLD_vals = [Float64(p["L_m"]) / p["L_D"] for p in sweep_points]
N_vals_10 = [p["soliton_number_N"] for p in sweep_points]
GDD_vals = [p["GDD_fs2"] for p in sweep_points]
TOD_vals = [p["TOD_fs3"] for p in sweep_points]
FOD_vals = [p["FOD_fs4"] for p in sweep_points]
fifth_vals = [p["fifth_fs5"] for p in sweep_points]

# Helper: scatter + linear fit with R^2
function scatter_with_fit!(ax, x, y, xlabel, ylabel, title; colors=nothing)
    if colors === nothing
        colors_arr = [p["fiber_name"] == "SMF-28" ? "#0072B2" : "#E69F00" for p in sweep_points]
    else
        colors_arr = colors
    end

    for (xi, yi, ci) in zip(x, y, colors_arr)
        ax.scatter([xi], [yi]; color=ci, s=50, zorder=3)
    end

    # Linear fit
    if length(x) > 2
        x_vec = Float64.(x)
        y_vec = Float64.(y)
        A = hcat(ones(length(x_vec)), x_vec)
        coeffs = A \ y_vec
        y_fit = A * coeffs
        SS_res = sum((y_vec .- y_fit).^2)
        SS_tot = sum((y_vec .- mean(y_vec)).^2)
        R2 = SS_tot > 0 ? 1.0 - SS_res / SS_tot : 0.0

        x_line = range(minimum(x_vec), maximum(x_vec); length=50)
        y_line = coeffs[1] .+ coeffs[2] .* x_line
        ax.plot(x_line, y_line; color="gray", ls="--", lw=1.0)
        ax.text(0.95, 0.95, @sprintf("R\u00B2 = %.3f", R2);
            transform=ax.transAxes, ha="right", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))
    end

    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.axhline(0; color="black", lw=0.5, ls=":")
end

scatter_with_fit!(axes10[1,1], LLD_vals, GDD_vals, "L / L_D", "GDD (fs\u00B2)", "(a) GDD vs L/L_D")
scatter_with_fit!(axes10[1,2], LLD_vals, TOD_vals, "L / L_D", "TOD (fs\u00B3)", "(b) TOD vs L/L_D")
scatter_with_fit!(axes10[2,1], N_vals_10, FOD_vals, "Soliton number N", "FOD (fs\u2074)", "(c) FOD vs N_sol")
scatter_with_fit!(axes10[2,2], N_vals_10, fifth_vals, "Soliton number N", "5th order (fs\u2075)", "(d) 5th order vs N_sol")

fig10.suptitle("Polynomial coefficient scaling with fiber parameters"; fontsize=14)
from_legend_10 = [
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="#0072B2", markersize=8, label="SMF-28"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="#E69F00", markersize=8, label="HNLF"),
]
fig10.legend(handles=from_legend_10; loc="lower center", ncol=2, fontsize=9, bbox_to_anchor=(0.5, -0.02))
add_caption!(fig10, "Linear fit + R-squared. If any coefficient scales predictably, it provides an analytical prediction.")
fig10.tight_layout(rect=[0, 0.04, 1, 0.96])
fig10.savefig("results/images/physics_09_10_coefficient_scaling.png"; dpi=300, bbox_inches="tight")
close(fig10)
@info "  Saved -> results/images/physics_09_10_coefficient_scaling.png"


# ───────────────────────────────────────────────────────────────────────────
# Section 9: Summary Verdict
# ───────────────────────────────────────────────────────────────────────────

@info "Section 9: Summary and verdict"
println()

# Compute mean explained variance across all sweep points at each order
mean_ev = zeros(5)
for ord_idx in 1:5
    mean_ev[ord_idx] = mean(p["explained_variances"][ord_idx] for p in sweep_points)
end
max_ev = maximum(mean_ev)
best_order = argmax(mean_ev) + 1  # +1 because order starts at 2

println("="^70)
println("PHASE 9.1 SUMMARY")
println("="^70)
println()
@printf("Mean explained variance by polynomial order (24 sweep points):\n")
for (i, ord) in enumerate(2:6)
    @printf("  Order %d: %.1f%%\n", ord, mean_ev[i] * 100)
end
println()

# Grouping with best separation
best_group_idx = argmax([g[2] - g[3] for g in grouping_results])
best_group_name = grouping_results[best_group_idx][1]
best_gap = grouping_results[best_group_idx][2] - grouping_results[best_group_idx][3]

@printf("Best physical grouping: %s (within-between gap = %.3f)\n", best_group_name, best_gap)
@printf("Multi-start mean correlation: %.3f (min: %.3f)\n", ms_mean_corr, ms_min_corr)
println()

# Determine verdict
if max_ev > 0.5 && best_gap > 0.1
    verdict = "UNIVERSAL"
    reason = @sprintf("Polynomial basis explains >50%% variance (best: order %d at %.0f%%) AND grouping by %s shows significant structure (gap=%.3f).",
        best_order, max_ev * 100, best_group_name, best_gap)
elseif max_ev < 0.1 && best_gap < 0.05
    verdict = "ARBITRARY"
    reason = @sprintf("Polynomial basis explains <10%% variance at all orders AND no grouping shows meaningful structure (best gap=%.3f).",
        best_gap)
else
    verdict = "STRUCTURED BUT COMPLEX"
    reason = @sprintf("Polynomial order %d explains %.0f%% of variance. Grouping by %s shows gap=%.3f. Structure exists but exceeds polynomial basis.",
        best_order, max_ev * 100, best_group_name, best_gap)
end

println("VERDICT: $verdict")
println("Reason: $reason")
println()

if ms_mean_corr > 0.9
    println("Multi-start: SINGLE BASIN (all 10 starts converge to structurally similar solutions)")
elseif ms_mean_corr > 0.5
    println("Multi-start: BROAD BASIN (moderate similarity, some variation)")
else
    println("Multi-start: MULTIPLE BASINS (distinct solution families from different starts)")
end

println()
println("="^70)
println()

@info "Phase 9.1 figures complete. Continuing to Phase 9.2 temporal/Raman analysis..."

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 9.2: Physical Mechanism Attribution & Temporal Analysis
# ═══════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────
# Section 10: Temporal Intensity Computation (H3)
# ───────────────────────────────────────────────────────────────────────────

@info "Section 10: Computing temporal intensity profiles (H3)"

for point in PA_all_points
    Nt = Int(point["Nt"])
    uomega0 = vec(point["uomega0"])  # FFT-order complex field
    phi_opt = vec(point["phi_opt"])   # FFT-order phase

    # Unshaped: just IFFT the input field
    ut_unshaped = ifft(uomega0)
    I_unshaped = abs2.(ut_unshaped)

    # Shaped: apply phi_opt then IFFT
    ut_shaped = ifft(uomega0 .* cis.(phi_opt))
    I_shaped = abs2.(ut_shaped)

    # Time axis in ps (sim_Dt is in ps)
    sim_Dt_ps = Float64(point["sim_Dt"])
    t_ps = fftshift((0:Nt-1) .* sim_Dt_ps .- (Nt * sim_Dt_ps / 2))

    # fftshift intensities for plotting
    I_unshaped_shifted = fftshift(I_unshaped)
    I_shaped_shifted = fftshift(I_shaped)

    # Store
    point["I_unshaped"] = I_unshaped_shifted
    point["I_shaped"] = I_shaped_shifted
    point["t_ps"] = t_ps

    # Peak power ratio (computed on raw FFT-order data, shift-invariant)
    peak_unshaped = maximum(I_unshaped)
    peak_shaped = maximum(I_shaped)
    point["peak_power_ratio"] = peak_unshaped > 0 ? peak_shaped / peak_unshaped : 1.0

    # Temporal RMS width ratio
    t_fft = (0:Nt-1) .* sim_Dt_ps .- (Nt * sim_Dt_ps / 2)
    function _rms_width_local(I_t, t_grid)
        E = sum(I_t)
        E < 1e-30 && return 0.0
        t_mean = sum(t_grid .* I_t) / E
        t2_mean = sum(t_grid.^2 .* I_t) / E
        return sqrt(max(t2_mean - t_mean^2, 0.0))
    end
    rms_unshaped = _rms_width_local(I_unshaped, t_fft)
    rms_shaped = _rms_width_local(I_shaped, t_fft)
    point["temporal_rms_ratio"] = rms_unshaped > 0 ? rms_shaped / rms_unshaped : 1.0

    # Peak power reduction in dB
    point["peak_power_reduction_dB"] = 10.0 * log10(point["peak_power_ratio"] + 1e-30)
end

@info "  Temporal intensity computation complete for $(length(PA_all_points)) points"
mean_ppr = mean(p["peak_power_reduction_dB"] for p in PA_all_points)
mean_spread = mean(p["temporal_rms_ratio"] for p in PA_all_points)
@info @sprintf("  Mean peak power reduction: %.1f dB, Mean temporal spread: %.2fx", mean_ppr, mean_spread)


# ───────────────────────────────────────────────────────────────────────────
# Section 11: Raman Response Function and Overlap Integral (H7)
# ───────────────────────────────────────────────────────────────────────────

@info "Section 11: Raman response function and overlap integral (H7)"

# Raman parameters (silica, from helpers.jl)
const PA_FR = 0.18       # fractional Raman contribution
const PA_TAU1 = 12.2     # fs (oscillation period)
const PA_TAU2 = 32.0     # fs (decay time)

"""
    compute_raman_response_fft(Nt, sim_Dt_ps)

Build the Raman response h_R(t) on the FFT-order time grid and return its FFT.
Uses the Blow & Wood (1989) damped oscillator model for silica.
"""
function compute_raman_response_fft(Nt, sim_Dt_ps)
    # Time grid in fs, FFT order
    dt_fs = sim_Dt_ps * 1e3  # ps -> fs

    # Causal response: h_R(t) for t >= 0
    # In FFT order: indices 1..Nt/2 correspond to t=0..(Nt/2-1)*dt
    # indices Nt/2+1..Nt correspond to t=-(Nt/2)*dt..(-1)*dt
    h_R = zeros(Nt)
    prefactor = (PA_TAU1^2 + PA_TAU2^2) / (PA_TAU1 * PA_TAU2^2)
    half_Nt = Nt ÷ 2
    for i in 1:half_Nt
        t_i = (i - 1) * dt_fs  # fs, t >= 0
        h_R[i] = prefactor * exp(-t_i / PA_TAU2) * sin(t_i / PA_TAU1)
    end
    # indices half_Nt+1..Nt: t < 0, h_R = 0 (causal)

    # Normalize so that sum * dt = 1
    h_integral = sum(h_R) * dt_fs
    if abs(h_integral) > 1e-30
        h_R ./= h_integral
    end

    return h_R, fft(h_R)
end

"""
    raman_overlap_integral(I_t_fftorder, H_R_fft)

Compute Raman overlap integral in frequency domain.
G_R = sum(S_I .* |H_R|) where S_I = |FFT(|E(t)|^2)|^2.
"""
function raman_overlap_integral(I_t_fftorder, H_R_fft)
    S_I = abs2.(fft(I_t_fftorder))
    H_R_mag = abs.(H_R_fft)
    return sum(S_I .* H_R_mag)
end

for point in PA_all_points
    Nt = Int(point["Nt"])
    sim_Dt_ps = Float64(point["sim_Dt"])

    # Build Raman response on this point's grid
    h_R, H_R_fft = compute_raman_response_fft(Nt, sim_Dt_ps)

    # Get FFT-order intensities (un-shifted)
    uomega0 = vec(point["uomega0"])
    phi_opt = vec(point["phi_opt"])

    I_unshaped_fft = abs2.(ifft(uomega0))
    I_shaped_fft = abs2.(ifft(uomega0 .* cis.(phi_opt)))

    # Raman overlap integrals
    G_R_unshaped = raman_overlap_integral(I_unshaped_fft, H_R_fft)
    G_R_shaped = raman_overlap_integral(I_shaped_fft, H_R_fft)

    # Ratio in dB (shaped / unshaped -- negative means reduction)
    G_R_ratio = G_R_unshaped > 0 ? G_R_shaped / G_R_unshaped : 1.0
    G_R_ratio_dB = 10.0 * log10(G_R_ratio + 1e-30)

    point["G_R_unshaped"] = G_R_unshaped
    point["G_R_shaped"] = G_R_shaped
    point["G_R_ratio_dB"] = G_R_ratio_dB
end

@info "  Raman overlap computation complete"
for p in sweep_points
    @info @sprintf("    %s: G_R_ratio = %.1f dB, delta_J = %.1f dB",
        p["source_dir"], p["G_R_ratio_dB"], Float64(p["delta_J_dB"]))
end


# ───────────────────────────────────────────────────────────────────────────
# Section 12: Group Delay Profiles
# ───────────────────────────────────────────────────────────────────────────

@info "Section 12: Computing group delay profiles"

for point in PA_all_points
    phi_norm = point["phi_norm"]       # fftshifted, normalized
    df_THz = point["df_THz"]           # fftshifted
    sig_mask = point["signal_mask"]

    d_omega = 2pi * (df_THz[2] - df_THz[1])  # rad/THz
    gd_ps = _central_diff(phi_norm, d_omega)  # ps

    gd_masked = copy(gd_ps)
    gd_masked[.!sig_mask] .= NaN

    point["group_delay_ps"] = gd_masked
end

@info "  Group delay computation complete"


# ───────────────────────────────────────────────────────────────────────────
# Section 13: Figures 09-11 through 09-15
# ───────────────────────────────────────────────────────────────────────────

# --- Figure 09-11: Temporal intensity before/after ---
@info "Generating Figure 09-11: Temporal intensity comparison (H3)"

# Select 6 representative sweep points
function select_representative_points(sweep_pts)
    smf_pts = filter(p -> p["fiber_name"] == "SMF-28", sweep_pts)
    hnlf_pts = filter(p -> p["fiber_name"] == "HNLF", sweep_pts)

    reps = Dict{String,Any}[]

    if !isempty(smf_pts)
        push!(reps, smf_pts[argmin([p["soliton_number_N"] for p in smf_pts])])
        push!(reps, smf_pts[argmax([p["soliton_number_N"] for p in smf_pts])])
    end
    if !isempty(hnlf_pts)
        push!(reps, hnlf_pts[argmin([p["soliton_number_N"] for p in hnlf_pts])])
        push!(reps, hnlf_pts[argmax([p["soliton_number_N"] for p in hnlf_pts])])
    end

    all_by_L = sort(sweep_pts; by=p -> Float64(p["L_m"]))
    for candidate in [all_by_L[1], all_by_L[end]]
        if !(candidate in reps)
            push!(reps, candidate)
        end
    end

    for p in sweep_pts
        length(reps) >= 6 && break
        if !(p in reps)
            push!(reps, p)
        end
    end

    return reps[1:min(6, length(reps))]
end

rep_points = select_representative_points(sweep_points)

n_rep = length(rep_points)
n_rows_11 = (n_rep + 1) ÷ 2
fig11, axes11 = subplots(n_rows_11, 2; figsize=(16, 4 * n_rows_11))

for (idx, p) in enumerate(rep_points)
    row = (idx - 1) ÷ 2 + 1
    col = (idx - 1) % 2 + 1
    ax = n_rows_11 == 1 ? axes11[col] : axes11[row, col]

    t_ps_local = p["t_ps"]
    I_un = p["I_unshaped"]
    I_sh = p["I_shaped"]

    # Normalize to unshaped peak
    peak_un = maximum(I_un)
    if peak_un > 0
        I_un_norm = I_un ./ peak_un
        I_sh_norm = I_sh ./ peak_un
    else
        I_un_norm = I_un
        I_sh_norm = I_sh
    end

    ax.plot(t_ps_local, I_un_norm; color=COLOR_INPUT, lw=1.5, label="Unshaped", alpha=0.8)
    ax.plot(t_ps_local, I_sh_norm; color=COLOR_OUTPUT, lw=1.5, label="Shaped", alpha=0.8)

    # Auto-zoom to region with signal
    threshold_11 = 1e-4
    active_un = findall(I_un_norm .> threshold_11)
    active_sh = findall(I_sh_norm .> threshold_11)
    all_active = vcat(active_un, active_sh)
    if !isempty(all_active)
        t_lo = t_ps_local[minimum(all_active)]
        t_hi = t_ps_local[maximum(all_active)]
        margin = max((t_hi - t_lo) * 0.15, 0.1)
        ax.set_xlim(t_lo - margin, t_hi + margin)
    end

    ppr_dB_loc = p["peak_power_reduction_dB"]
    spread_loc = p["temporal_rms_ratio"]
    ann_11 = @sprintf("Peak: %.1f dB\nSpread: %.2fx", ppr_dB_loc, spread_loc)
    ax.text(0.97, 0.95, ann_11;
        transform=ax.transAxes, ha="right", va="top", fontsize=8,
        bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

    title_str = @sprintf("%s L=%.1fm P=%.3fW N=%.1f",
        p["fiber_name"], Float64(p["L_m"]), Float64(p["P_cont_W"]), p["soliton_number_N"])
    ax.set_title(title_str; fontsize=10)
    ax.set_ylabel("Normalized intensity")
    ax.set_xlabel("Time (ps)")
    ax.legend(fontsize=7, loc="upper left")
end

# Hide unused panels
if n_rep < n_rows_11 * 2
    for idx in (n_rep+1):(n_rows_11*2)
        row = (idx - 1) ÷ 2 + 1
        col = (idx - 1) % 2 + 1
        ax = n_rows_11 == 1 ? axes11[col] : axes11[row, col]
        ax.set_visible(false)
    end
end

fig11.suptitle("Temporal intensity before/after phase shaping (H3)"; fontsize=14)
add_caption!(fig11, "Blue: unshaped pulse. Red: shaped pulse. Both normalized to unshaped peak.")
fig11.tight_layout(rect=[0, 0.04, 1, 0.96])
fig11.savefig("results/images/physics_09_11_temporal_intensity_comparison.png"; dpi=300, bbox_inches="tight")
close(fig11)
@info "  Saved -> results/images/physics_09_11_temporal_intensity_comparison.png"


# --- Figure 09-12: Raman overlap correlation (THE key figure) ---
@info "Generating Figure 09-12: Raman overlap correlation (H7 key result)"

fig12, ax12 = subplots(1, 1; figsize=(10, 8))

G_R_vals = Float64[p["G_R_ratio_dB"] for p in sweep_points]
dJ_vals_12 = Float64[Float64(p["delta_J_dB"]) for p in sweep_points]

for p in sweep_points
    x_val = p["G_R_ratio_dB"]
    y_val = Float64(p["delta_J_dB"])
    is_smf = p["fiber_name"] == "SMF-28"
    color = is_smf ? "#0072B2" : "#E69F00"
    marker = is_smf ? "o" : "^"
    ax12.scatter([x_val], [y_val];
        color=color, marker=marker, s=120, zorder=3, edgecolors="black", linewidths=0.5)
end

# Linear fit with R^2 and Pearson r
R2_key = 0.0
pearson_r_key = 0.0
if length(G_R_vals) > 2
    A_fit = hcat(ones(length(G_R_vals)), G_R_vals)
    coeffs_fit = A_fit \ dJ_vals_12
    y_fit_12 = A_fit * coeffs_fit
    SS_res = sum((dJ_vals_12 .- y_fit_12).^2)
    SS_tot = sum((dJ_vals_12 .- mean(dJ_vals_12)).^2)
    R2_key = SS_tot > 0 ? 1.0 - SS_res / SS_tot : 0.0
    pearson_r_key = cor(G_R_vals, dJ_vals_12)

    x_line = range(minimum(G_R_vals) - 2, maximum(G_R_vals) + 2; length=50)
    y_line = coeffs_fit[1] .+ coeffs_fit[2] .* x_line
    ax12.plot(x_line, y_line; color="gray", ls="--", lw=1.5, alpha=0.7)

    ann_text = @sprintf("R\u00B2 = %.3f\nPearson r = %.3f\nSlope = %.2f", R2_key, pearson_r_key, coeffs_fit[2])
    ax12.text(0.05, 0.05, ann_text;
        transform=ax12.transAxes, ha="left", va="bottom", fontsize=12,
        bbox=Dict("boxstyle" => "round,pad=0.4", "facecolor" => "lightyellow", "alpha" => 0.9))
end

# 1:1 line for reference
lim_lo = min(minimum(G_R_vals), minimum(dJ_vals_12)) - 5
lim_hi = max(maximum(G_R_vals), maximum(dJ_vals_12)) + 5
ax12.plot([lim_lo, lim_hi], [lim_lo, lim_hi]; color="black", ls=":", lw=0.8, alpha=0.4, label="1:1 line")

handles_12 = [
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="#0072B2", markeredgecolor="black", markersize=10, label="SMF-28"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="^", color="w",
        markerfacecolor="#E69F00", markeredgecolor="black", markersize=10, label="HNLF"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; color="gray", ls="--", lw=1.5, label="Linear fit"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; color="black", ls=":", lw=0.8, label="1:1 line"),
]
ax12.legend(handles=handles_12; fontsize=10, loc="upper left")

ax12.set_xlabel("Raman overlap reduction G_R (dB)"; fontsize=12)
ax12.set_ylabel("Raman suppression delta_J (dB)"; fontsize=12)
ax12.set_title("Raman Overlap Integral vs Suppression Depth (H7 key result)"; fontsize=13)

add_caption!(fig12, "If R^2 > 0.7, coherent Raman interference is confirmed as the dominant suppression mechanism.")
fig12.tight_layout(rect=[0, 0.04, 1, 1])
fig12.savefig("results/images/physics_09_12_raman_overlap_correlation.png"; dpi=300, bbox_inches="tight")
close(fig12)
@info "  Saved -> results/images/physics_09_12_raman_overlap_correlation.png"


# --- Figure 09-13: Peak power reduction vs suppression ---
@info "Generating Figure 09-13: Peak power reduction vs suppression"

fig13, ax13 = subplots(1, 1; figsize=(10, 8))

ppr_vals = Float64[p["peak_power_reduction_dB"] for p in sweep_points]
dJ_vals_13 = Float64[Float64(p["delta_J_dB"]) for p in sweep_points]

for p in sweep_points
    x_val = p["peak_power_reduction_dB"]
    y_val = Float64(p["delta_J_dB"])
    is_smf = p["fiber_name"] == "SMF-28"
    color = is_smf ? "#0072B2" : "#E69F00"
    marker = is_smf ? "o" : "^"
    ax13.scatter([x_val], [y_val];
        color=color, marker=marker, s=120, zorder=3, edgecolors="black", linewidths=0.5)
end

R2_13 = 0.0
if length(ppr_vals) > 2
    A_fit13 = hcat(ones(length(ppr_vals)), ppr_vals)
    coeffs_fit13 = A_fit13 \ dJ_vals_13
    y_fit_13 = A_fit13 * coeffs_fit13
    SS_res13 = sum((dJ_vals_13 .- y_fit_13).^2)
    SS_tot13 = sum((dJ_vals_13 .- mean(dJ_vals_13)).^2)
    R2_13 = SS_tot13 > 0 ? 1.0 - SS_res13 / SS_tot13 : 0.0
    pearson_r13 = cor(ppr_vals, dJ_vals_13)

    x_line13 = range(minimum(ppr_vals) - 1, maximum(ppr_vals) + 1; length=50)
    y_line13 = coeffs_fit13[1] .+ coeffs_fit13[2] .* x_line13
    ax13.plot(x_line13, y_line13; color="gray", ls="--", lw=1.5, alpha=0.7)

    ann13 = @sprintf("R\u00B2 = %.3f\nPearson r = %.3f\nSlope = %.2f", R2_13, pearson_r13, coeffs_fit13[2])
    ax13.text(0.05, 0.05, ann13;
        transform=ax13.transAxes, ha="left", va="bottom", fontsize=12,
        bbox=Dict("boxstyle" => "round,pad=0.4", "facecolor" => "lightyellow", "alpha" => 0.9))
end

# 1:1 reference
lim_lo13 = min(minimum(ppr_vals), minimum(dJ_vals_13)) - 5
lim_hi13 = max(maximum(ppr_vals), maximum(dJ_vals_13)) + 5
ax13.plot([lim_lo13, lim_hi13], [lim_lo13, lim_hi13]; color="black", ls=":", lw=0.8, alpha=0.4)

handles_13 = [
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="o", color="w",
        markerfacecolor="#0072B2", markeredgecolor="black", markersize=10, label="SMF-28"),
    PyPlot.matplotlib.lines.Line2D([0], [0]; marker="^", color="w",
        markerfacecolor="#E69F00", markeredgecolor="black", markersize=10, label="HNLF"),
]
ax13.legend(handles=handles_13; fontsize=10, loc="upper left")

ax13.set_xlabel("Peak power reduction (dB)"; fontsize=12)
ax13.set_ylabel("Raman suppression delta_J (dB)"; fontsize=12)
ax13.set_title("Peak Power Reduction vs Suppression Depth"; fontsize=13)

add_caption!(fig13, "If slope ~1 and R^2 high, peak power reduction (CPA) fully explains suppression.")
fig13.tight_layout(rect=[0, 0.04, 1, 1])
fig13.savefig("results/images/physics_09_13_peak_power_vs_suppression.png"; dpi=300, bbox_inches="tight")
close(fig13)
@info "  Saved -> results/images/physics_09_13_peak_power_vs_suppression.png"


# --- Figure 09-14: Group delay profiles ---
@info "Generating Figure 09-14: Group delay profiles"

fig14, (ax14a, ax14b) = subplots(1, 2; figsize=(16, 7))

L_cmap = PyPlot.cm.viridis
L_all_sweep_14 = [Float64(p["L_m"]) for p in sweep_points]
L_min_14, L_max_14 = extrema(L_all_sweep_14)

for (ax, pts, title) in [(ax14a, smf_points, "(a) SMF-28 group delay"),
                          (ax14b, hnlf_points, "(b) HNLF group delay")]
    for p in pts
        df_THz_loc = p["df_THz"]
        gd = p["group_delay_ps"]
        L_val = Float64(p["L_m"])
        L_norm = L_max_14 > L_min_14 ? (L_val - L_min_14) / (L_max_14 - L_min_14) : 0.5
        color = L_cmap(L_norm)

        ax.plot(df_THz_loc, gd; color=color, lw=0.8,
            label=@sprintf("L=%.1fm P=%.3fW", L_val, Float64(p["P_cont_W"])))
    end

    ax.axvspan(-30.0, -13.2; alpha=0.08, color=COLOR_RAMAN, label="Raman band")
    ax.axvline(-13.2; color=COLOR_RAMAN, lw=0.8, ls="--")
    ax.axhline(0; color="black", lw=0.5, ls=":")

    ax.set_xlabel("Frequency offset (THz)")
    ax.set_ylabel("Group delay (ps)")
    ax.set_title(title)
    ax.legend(fontsize=6, ncol=2, loc="upper left")
end

sm_14 = PyPlot.cm.ScalarMappable(; cmap=L_cmap,
    norm=PyPlot.matplotlib.colors.Normalize(L_min_14, L_max_14))
sm_14.set_array([])
fig14.colorbar(sm_14; ax=[ax14a, ax14b], label="Fiber length L (m)", shrink=0.8)

fig14.suptitle("Group delay profiles -- temporal reshaping by optimizer"; fontsize=14)
add_caption!(fig14, "Group delay d_phi/d_omega shows how the optimizer redistributes pulse arrival time across the spectrum.")
fig14.tight_layout(rect=[0, 0.04, 1, 0.96])
fig14.savefig("results/images/physics_09_14_group_delay_profiles.png"; dpi=300, bbox_inches="tight")
close(fig14)
@info "  Saved -> results/images/physics_09_14_group_delay_profiles.png"


# --- Figure 09-15: Mechanism attribution summary ---
@info "Generating Figure 09-15: Mechanism attribution summary"

fig15, axes15 = subplots(2, 2; figsize=(16, 12))

# (a) Histogram: fraction of suppression explained by peak power reduction
ax15a = axes15[1, 1]
fraction_explained = Float64[]
for p in sweep_points
    dJ = Float64(p["delta_J_dB"])
    ppr_local = p["peak_power_reduction_dB"]
    if abs(dJ) > 0.1
        push!(fraction_explained, ppr_local / dJ)  # Both negative, ratio positive
    else
        push!(fraction_explained, 0.0)
    end
end

ax15a.hist(fraction_explained; bins=20, color="#0072B2", edgecolor="black", alpha=0.7)
ax15a.axvline(1.0; color="red", ls="--", lw=2, label="Full explanation (1.0)")
mean_frac = isempty(fraction_explained) ? 0.0 : mean(fraction_explained)
ax15a.axvline(mean_frac; color="green", ls="-", lw=2,
    label=@sprintf("Mean = %.2f", mean_frac))
ax15a.set_xlabel("Peak power fraction of suppression")
ax15a.set_ylabel("Count")
ax15a.set_title("(a) How much does peak power reduction explain?")
ax15a.legend(fontsize=9)

# (b) G_R_ratio_dB vs peak_power_reduction_dB scatter
ax15b = axes15[1, 2]
for p in sweep_points
    is_smf = p["fiber_name"] == "SMF-28"
    color = is_smf ? "#0072B2" : "#E69F00"
    marker = is_smf ? "o" : "^"
    ax15b.scatter([p["peak_power_reduction_dB"]], [p["G_R_ratio_dB"]];
        color=color, marker=marker, s=80, zorder=3, edgecolors="black", linewidths=0.5)
end
ax15b.set_xlabel("Peak power reduction (dB)")
ax15b.set_ylabel("Raman overlap reduction G_R (dB)")
ax15b.set_title("(b) Two mechanisms separated")
b_lo = min(minimum(ppr_vals), minimum(G_R_vals)) - 2
b_hi = max(maximum(ppr_vals), maximum(G_R_vals)) + 2
ax15b.plot([b_lo, b_hi], [b_lo, b_hi]; color="black", ls=":", lw=0.8, alpha=0.4, label="1:1")
ax15b.legend(fontsize=9)

# (c) Explained variance vs G_R correlation
ax15c = axes15[2, 1]
ev6_sweep = [p["explained_variances"][5] for p in sweep_points]
gr_sweep = [p["G_R_ratio_dB"] for p in sweep_points]

for (i, p) in enumerate(sweep_points)
    is_smf = p["fiber_name"] == "SMF-28"
    color = is_smf ? "#0072B2" : "#E69F00"
    marker = is_smf ? "o" : "^"
    ax15c.scatter([ev6_sweep[i] * 100], [gr_sweep[i]];
        color=color, marker=marker, s=80, zorder=3, edgecolors="black", linewidths=0.5)
end
ax15c.set_xlabel("Explained variance at order 6 (%)")
ax15c.set_ylabel("Raman overlap reduction G_R (dB)")
ax15c.set_title("(c) Frequency-domain vs time-domain analysis")

if length(ev6_sweep) > 2
    r_ev_gr = cor(ev6_sweep, gr_sweep)
    ax15c.text(0.95, 0.05, @sprintf("r = %.3f", r_ev_gr);
        transform=ax15c.transAxes, ha="right", va="bottom", fontsize=11,
        bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))
end

# (d) Summary verdict text panel
ax15d = axes15[2, 2]
ax15d.axis("off")

mean_ppr_sweep = mean(p["peak_power_reduction_dB"] for p in sweep_points)
mean_GR_sweep = mean(p["G_R_ratio_dB"] for p in sweep_points)

# Determine dominant mechanism
if R2_key > 0.7
    mechanism_verdict = "COHERENT RAMAN INTERFERENCE"
    mechanism_detail = "The optimizer reduces the Raman overlap integral\nby reshaping temporal intensity."
elseif R2_key > 0.3 && abs(mean_frac) < 0.3
    mechanism_verdict = "MIXED: Raman interference + other"
    mechanism_detail = "Both Raman overlap reduction and peak power\nreduction contribute to suppression."
elseif abs(mean_frac) > 0.7
    mechanism_verdict = "PEAK POWER REDUCTION (CPA)"
    mechanism_detail = "Simple pulse stretching reduces peak power\nand thereby Raman scattering."
else
    mechanism_verdict = "COMPLEX / MULTI-MECHANISM"
    mechanism_detail = "No single mechanism dominates.\nFurther propagation analysis needed."
end

verdict_text = """MECHANISM ATTRIBUTION VERDICT
========================================

Dominant: $mechanism_verdict

$mechanism_detail

Key metrics:
  G_R vs delta_J: R^2 = $(@sprintf("%.3f", R2_key))
  Peak power fraction: $(@sprintf("%.2f", mean_frac))
  Mean peak reduction: $(@sprintf("%.1f dB", mean_ppr_sweep))
  Mean G_R reduction: $(@sprintf("%.1f dB", mean_GR_sweep))
"""

ax15d.text(0.05, 0.95, verdict_text;
    transform=ax15d.transAxes, ha="left", va="top", fontsize=11,
    family="monospace",
    bbox=Dict("boxstyle" => "round,pad=0.5", "facecolor" => "lightyellow", "alpha" => 0.9))

fig15.suptitle("Mechanism Attribution Summary"; fontsize=14)
add_caption!(fig15, "Combining temporal, spectral, and overlap analyses to determine dominant suppression mechanism.")
fig15.tight_layout(rect=[0, 0.04, 1, 0.96])
fig15.savefig("results/images/physics_09_15_mechanism_attribution.png"; dpi=300, bbox_inches="tight")
close(fig15)
@info "  Saved -> results/images/physics_09_15_mechanism_attribution.png"


# ───────────────────────────────────────────────────────────────────────────
# Section 14: Final Summary Print (All Hypothesis Verdicts)
# ───────────────────────────────────────────────────────────────────────────

@info "Section 14: Final summary"
println()

# Gather all statistics
mean_ev_final = zeros(5)
for ord_idx in 1:5
    mean_ev_final[ord_idx] = mean(p["explained_variances"][ord_idx] for p in sweep_points)
end
max_ev_final = maximum(mean_ev_final)
best_order_final = argmax(mean_ev_final) + 1

# Check 13 THz feature in residual PSD
has_13thz_feature = false
for p in sweep_points
    delay = p["psd_mod_delay_fs"]
    psd_loc = p["psd_dB"]
    if isempty(delay) || isempty(psd_loc)
        continue
    end
    target_mask = (delay .> 60) .& (delay .< 100)
    if any(target_mask)
        psd_target = psd_loc[target_mask]
        psd_elsewhere = psd_loc[(delay .> 10) .& (delay .< 300) .& .!target_mask]
        if !isempty(psd_elsewhere) && !isempty(psd_target)
            if maximum(psd_target) > mean(psd_elsewhere) + 3.0
                global has_13thz_feature = true
            end
        end
    end
end

# Check for sub-structure in temporal profiles
has_substructure = false
for p in sweep_points
    I_sh = p["I_shaped"]
    peak = maximum(I_sh)
    if peak > 0
        I_norm_loc = I_sh ./ peak
        n_peaks_loc = 0
        for i in 2:(length(I_norm_loc)-1)
            if I_norm_loc[i] > I_norm_loc[i-1] && I_norm_loc[i] > I_norm_loc[i+1] && I_norm_loc[i] > 0.05
                n_peaks_loc += 1
            end
        end
        if n_peaks_loc > 3
            global has_substructure = true
        end
    end
end

mean_gdd_ev = mean_ev_final[1] * 100
mean_gddtod_ev = mean_ev_final[2] * 100
mean_fod_ev = mean_ev_final[3] * 100

if length(G_R_vals) > 2
    r_raman = cor(G_R_vals, dJ_vals_12)
else
    r_raman = 0.0
end

if R2_key > 0.7
    h7_verdict = "CONFIRMED"
elseif R2_key > 0.3
    h7_verdict = "INCONCLUSIVE"
else
    h7_verdict = "REJECTED"
end

println("="^60)
println("PHASE 9: PHYSICS OF RAMAN SUPPRESSION -- FINAL SUMMARY")
println("="^60)
println()
@printf("1. POLYNOMIAL DECOMPOSITION (H1):\n")
@printf("   - Max explained variance at order %d: %.1f%% (mean across %d sweep points)\n",
    best_order_final, max_ev_final * 100, length(sweep_points))
@printf("   - GDD alone: %.1f%% | GDD+TOD: %.1f%% | Up to FOD: %.1f%%\n",
    mean_gdd_ev, mean_gddtod_ev, mean_fod_ev)
if max_ev_final > 0.5
    println("   - VERDICT: Polynomial chirp is SUFFICIENT (explains >50%)")
elseif max_ev_final > 0.1
    println("   - VERDICT: Polynomial chirp is PARTIAL (explains 10-50%)")
else
    println("   - VERDICT: Polynomial chirp is INSUFFICIENT (explains <10%)")
end
println()

@printf("2. RESIDUAL STRUCTURE (H2):\n")
@printf("   - 13 THz feature in residual PSD: %s\n", has_13thz_feature ? "PRESENT" : "ABSENT")
println("   - Residual is ", has_13thz_feature ? "STRUCTURED (features at Raman frequency)" : "appears noise-like or broadband")
println()

@printf("3. TEMPORAL RESHAPING (H3):\n")
@printf("   - Mean peak power reduction: %.1f dB\n", mean_ppr)
@printf("   - Mean temporal spread: %.2fx\n", mean_spread)
@printf("   - Sub-structure visible: %s\n", has_substructure ? "YES" : "NO")
println()

@printf("4. CROSS-SWEEP CLUSTERING (H4):\n")
best_group_idx_final = argmax([g[2] - g[3] for g in grouping_results])
@printf("   - Best grouping variable: %s\n", grouping_results[best_group_idx_final][1])
@printf("   - Mean within-group correlation: %.3f\n", grouping_results[best_group_idx_final][2])
@printf("   - Within-between gap: %.3f\n",
    grouping_results[best_group_idx_final][2] - grouping_results[best_group_idx_final][3])
println()

@printf("5. MULTI-START (H6):\n")
@printf("   - Mean pairwise correlation: %.3f\n", ms_mean_corr)
if ms_mean_corr > 0.9
    println("   - Solution landscape: SINGLE BASIN")
elseif ms_mean_corr > 0.5
    println("   - Solution landscape: BROAD BASIN")
else
    println("   - Solution landscape: MULTIPLE BASINS")
end
println()

@printf("6. RAMAN OVERLAP (H7):\n")
@printf("   - G_R reduction vs delta_J correlation: R^2 = %.3f\n", R2_key)
@printf("   - Coherent interference hypothesis: %s\n", h7_verdict)
println()

println("="^60)
println("CENTRAL QUESTION (D-02): UNIVERSAL vs ARBITRARY")
println("="^60)

println(verdict)
println()
println("Evidence: $reason")
println()
println("Mechanism: $mechanism_verdict")
println(mechanism_detail)
println("="^60)
println()

@info """
+----------------------------------------------------------------------+
| Phase 9: Full Analysis Complete (Plans 01 + 02)                       |
+----------------------------------------------------------------------+
|  Fig 01: physics_09_01_explained_variance_vs_order.png               |
|  Fig 02: physics_09_02_gdd_tod_vs_params.png                        |
|  Fig 03: physics_09_03_residual_psd_waterfall.png                   |
|  Fig 04: physics_09_04_phi_overlay_all_sweep.png                    |
|  Fig 05: physics_09_05_decomposition_detail.png                     |
|  Fig 06: physics_09_06_correlation_matrix.png                       |
|  Fig 07: physics_09_07_similarity_by_grouping.png                   |
|  Fig 08: physics_09_08_multistart_overlay.png                       |
|  Fig 09: physics_09_09_phase_by_regime.png                          |
|  Fig 10: physics_09_10_coefficient_scaling.png                      |
|  Fig 11: physics_09_11_temporal_intensity_comparison.png             |
|  Fig 12: physics_09_12_raman_overlap_correlation.png                |
|  Fig 13: physics_09_13_peak_power_vs_suppression.png                |
|  Fig 14: physics_09_14_group_delay_profiles.png                     |
|  Fig 15: physics_09_15_mechanism_attribution.png                    |
+----------------------------------------------------------------------+
"""

end  # if abspath(PROGRAM_FILE) == @__FILE__
