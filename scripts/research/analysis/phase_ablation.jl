"""
Phase Ablation & Perturbation Experiments — Phase 10.02

Conducts spectral phase ablation experiments and perturbation robustness studies
on 2 canonical configurations:
  - SMF-28 L2m_P0.2W  (N≈2.57, J_after ≈ -60 dB, multi-start config)
  - HNLF   L1m_P0.01W (N≈3.61, J_after ≈ -67 dB, best HNLF suppression)

Experiments performed:
  1. Band zeroing: divide signal band into 10 sub-bands, zero one at a time
  2. Cumulative ablation: zero bands from edges inward, track suppression vs bandwidth
  3. Global scaling: multiply phi_opt by [0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
  4. Spectral shift: translate phi_opt by ±1, ±2, ±5 THz on frequency grid

Figures produced (all → results/images/):
  physics_10_05_ablation_band_zeroing.png     — bar chart of suppression loss per sub-band
  physics_10_06_ablation_cumulative.png       — J vs remaining bandwidth (cumulative ablation)
  physics_10_07_scaling_robustness.png        — J vs phi_opt scale factor with 3 dB envelope
  physics_10_08_spectral_shift_robustness.png — J vs spectral shift (THz) for both configs
  physics_10_09_ablation_summary.png          — multi-panel summary comparing SMF-28 vs HNLF

Data files saved (results/raman/phase10/):
  ablation_smf28_canonical.jld2    — band zeroing + cumulative ablation for SMF-28
  ablation_hnlf_canonical.jld2     — band zeroing + cumulative ablation for HNLF
  perturbation_smf28_canonical.jld2 — scaling + shift perturbation for SMF-28
  perturbation_hnlf_canonical.jld2  — scaling + shift perturbation for HNLF

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

# Include common utilities — path relative to this script's directory
const _PAB_SCRIPT_DIR   = dirname(abspath(@__FILE__))
const _PAB_PROJECT_ROOT = dirname(_PAB_SCRIPT_DIR)  # scripts/ → project root
include(joinpath(_PAB_SCRIPT_DIR, "common.jl"))
include(joinpath(_PAB_SCRIPT_DIR, "visualization.jl"))

if !(@isdefined _PAB_SCRIPT_LOADED)
const _PAB_SCRIPT_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# 1. Constants
# ─────────────────────────────────────────────────────────────────────────────

const PAB_RESULTS_DIR  = joinpath(_PAB_PROJECT_ROOT, "results", "raman", "phase10")
const PAB_FIGURE_DIR   = joinpath(_PAB_PROJECT_ROOT, "results", "images")
const PAB_N_BANDS      = 10                                               # D-07: 10 sub-bands
const PAB_SG_ORDER     = 6                                                # D-08: super-Gaussian order 6
const PAB_SG_WIDTH_FRAC = 0.1                                             # D-08: 10% of bandwidth for roll-off
const PAB_SCALE_FACTORS = [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]  # D-10
const PAB_SHIFT_THZ     = [-5.0, -2.0, -1.0, 0.0, 1.0, 2.0, 5.0]       # D-11

const PAB_FIBER_BETAS = Dict(
    "SMF-28" => [-2.17e-26, 1.2e-40],
    "HNLF"   => [-0.5e-26,  1.0e-40],
)

# Canonical ablation configurations (D-05)
const PAB_CONFIGS = [
    (fiber_dir="smf28", config="L2m_P0.2W",  label="SMF-28 N=2.6 (multi-start)", preset=:SMF28),
    (fiber_dir="hnlf",  config="L1m_P0.01W", label="HNLF N=3.6 (best)",          preset=:HNLF),
]

# ─────────────────────────────────────────────────────────────────────────────
# 2. Helper: Load canonical config from JLD2 and reconstruct initial state
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_load_config(fiber_dir, config_name, preset) -> NamedTuple

Load phi_opt and reconstruct the initial simulation state from a sweep JLD2 file.
Always passes stored Nt and time_window_ps to setup_raman_problem to avoid grid mismatch.

# Returns
NamedTuple with fields:
  uω0, fiber, sim, band_mask, phi_opt, Δf, L, P_cont, Nt,
  fiber_name, J_before, J_after
"""
function pab_load_config(fiber_dir, config_name, preset)
    jld2_path = joinpath(_PAB_PROJECT_ROOT, "results", "raman", "sweeps", fiber_dir, config_name, "opt_result.jld2")
    @assert isfile(jld2_path) "JLD2 not found: $jld2_path"
    data = JLD2.load(jld2_path)

    phi_opt     = vec(data["phi_opt"])
    L           = Float64(data["L_m"])
    P_cont      = Float64(data["P_cont_W"])
    Nt          = Int(data["Nt"])
    time_window = Float64(data["time_window_ps"])

    # Reconstruct with stored Nt and time_window to match original grid.
    # β_order=3 matches the sweep scripts (common.jl default is 2 but presets have 2 betas).
    uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
        L_fiber=L, P_cont=P_cont, Nt=Nt, time_window=time_window,
        β_order=3, fiber_preset=preset
    )

    @assert length(phi_opt) == size(uω0, 1) "Grid mismatch: phi_opt=$(length(phi_opt)) vs Nt=$(size(uω0,1))"

    return (
        uω0       = uω0,
        fiber     = fiber,
        sim       = sim,
        band_mask = band_mask,
        phi_opt   = phi_opt,
        Δf        = Δf,
        L         = L,
        P_cont    = P_cont,
        Nt        = Nt,
        fiber_name = data["fiber_name"],
        J_before   = Float64(data["J_before"]),
        J_after    = Float64(data["J_after"]),
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. Helper: Propagate with a given phi and return J at fiber end (no zsave)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_propagate_and_cost(uω0, phi, fiber, sim, band_mask) -> Float64

Propagate with phi applied to uω0, return scalar J = E_band/E_total at fiber end.
Uses no zsave for speed (only z=L output needed for ablation/perturbation sweeps).
"""
function pab_propagate_and_cost(uω0, phi, fiber, sim, band_mask)
    # Apply phase in FFT order (phi_opt and uω0 are both in FFT order — no fftshift)
    uω0_mod = uω0 .* cis.(phi)

    # deepcopy to avoid mutating the shared fiber dict across calls
    fiber_prop = deepcopy(fiber)
    # fiber["zsave"] is already nothing from setup_raman_problem; verify
    @assert isnothing(fiber_prop["zsave"]) "Expected fiber[zsave]=nothing for fast propagation"

    sol = MultiModeNoise.solve_disp_mmf(uω0_mod, fiber_prop, sim)

    # Recover lab-frame field at z=L from interaction picture:
    # u(ω,L) = exp(iD(ω)L) · ũ(ω,L)  [simulate_disp_mmf.jl line 192]
    uωf = cis.(fiber["Dω"] * fiber["L"]) .* sol["ode_sol"](fiber["L"])

    J, _ = spectral_band_cost(uωf, band_mask)
    return J
end

# ─────────────────────────────────────────────────────────────────────────────
# 4. Helper: Build smooth band-zeroing window (D-07, D-08)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_make_ablation_window(fs_fftshifted, band_lo, band_hi; sg_order, sg_width_frac) -> Vector

Build a smooth zeroing window on the fftshifted frequency axis.
The window is 1 everywhere except in [band_lo, band_hi], where it transitions to 0
via a super-Gaussian roll-off (order sg_order) at both edges.

# Arguments
- `fs_fftshifted`: frequency axis in THz, fftshifted (monotonically increasing)
- `band_lo`, `band_hi`: band edges in THz
- `sg_order`: super-Gaussian order (default 6) — higher = sharper transition
- `sg_width_frac`: roll-off width as fraction of band width (default 0.1 = 10%)

# Returns
Window vector in fftshifted order. Apply `ifftshift` before multiplying phi_opt.
"""
function pab_make_ablation_window(fs_fftshifted, band_lo, band_hi;
                                   sg_order::Int=PAB_SG_ORDER,
                                   sg_width_frac::Float64=PAB_SG_WIDTH_FRAC)
    window = ones(Float64, length(fs_fftshifted))
    band_width = band_hi - band_lo
    sg_sigma = max(sg_width_frac * band_width, 1e-6)  # guard against zero-width band
    for (i, f) in enumerate(fs_fftshifted)
        if band_lo <= f <= band_hi
            dist_lo = f - band_lo
            dist_hi = band_hi - f
            margin  = min(dist_lo, dist_hi)
            # 1 - super-Gaussian: ramps from 1 at edges to 0 at center of zeroed band
            window[i] = 1.0 - exp(-(margin / sg_sigma)^sg_order)
        end
    end
    return window
end

# ─────────────────────────────────────────────────────────────────────────────
# 5. Helper: Frequency-shift phi_opt by delta_f THz (D-11)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_shift_phase_spectrum(phi_opt, sim, delta_f_THz) -> Vector

Translate phi_opt by delta_f THz on the frequency grid using linear interpolation
with zero extrapolation (shift moves content, edges become zero).

# Arguments
- `phi_opt`: phase vector in FFT order, length Nt
- `sim`: simulation dict (used for Δt to build frequency axis)
- `delta_f_THz`: spectral shift in THz (positive = shift to higher frequencies)

# Returns
Shifted phase in FFT order.
"""
function pab_shift_phase_spectrum(phi_opt, sim, delta_f_THz)
    Nt = length(phi_opt)
    # fftshifted frequency axis in THz
    fs_shifted = fftshift(fftfreq(Nt, 1/sim["Δt"]))  # THz
    # phi_opt in fftshifted order for interpolation
    phi_on_shifted_axis = fftshift(phi_opt)
    # Interpolate: query at fs_shifted - delta_f (shifts content by +delta_f)
    itp = LinearInterpolation(fs_shifted, phi_on_shifted_axis, extrapolation_bc=0.0)
    phi_new_shifted = itp.(fs_shifted .- delta_f_THz)
    # Return to FFT order
    return ifftshift(phi_new_shifted)
end

# ─────────────────────────────────────────────────────────────────────────────
# 6. Experiment 1: Band zeroing (D-07, D-08)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_band_zeroing(cfg; n_bands=PAB_N_BANDS) -> (band_zeroing_J, sub_band_edges, J_full, J_flat)

For the given loaded config, zero phi_opt in each of n_bands equal-width sub-bands
using super-Gaussian windowing. Propagate each ablated phi and record J.

# Returns
- `band_zeroing_J`: Vector of J values for each band zeroed (length n_bands)
- `sub_band_edges`: Vector of (band_lo, band_hi, band_center) NamedTuples
- `J_full`: J with full phi_opt applied
- `J_flat`: J with flat (zero) phase (baseline)
"""
function pab_band_zeroing(cfg; n_bands::Int=PAB_N_BANDS)
    uω0 = cfg.uω0; fiber = cfg.fiber; sim = cfg.sim
    band_mask = cfg.band_mask; phi_opt = cfg.phi_opt

    Nt = length(phi_opt)
    # fftshifted frequency axis (THz) for band construction
    fs_fftshifted = fftshift(fftfreq(Nt, 1/sim["Δt"]))  # THz

    # --- Define signal band from spectrum ---
    # Find spectral extent of the input pulse (where |uω0|² > -40 dB of peak)
    S_input = abs2.(vec(fftshift(uω0)))   # power spectrum, fftshifted
    S_peak  = maximum(S_input)
    sig_mask_shifted = S_input .> S_peak * 1e-4  # -40 dB threshold
    sig_freqs = fs_fftshifted[sig_mask_shifted]
    sig_lo = minimum(sig_freqs)
    sig_hi = maximum(sig_freqs)

    @info @sprintf("Signal band: [%.2f, %.2f] THz (%.2f THz wide)", sig_lo, sig_hi, sig_hi - sig_lo)

    # Divide signal band into n_bands equal-width sub-bands
    sub_bandwidth = (sig_hi - sig_lo) / n_bands
    sub_band_edges = [(
        band_lo    = sig_lo + (k-1) * sub_bandwidth,
        band_hi    = sig_lo + k * sub_bandwidth,
        band_center = sig_lo + (k - 0.5) * sub_bandwidth,
    ) for k in 1:n_bands]

    # --- Baselines ---
    @info "Computing J_full (full phi_opt)"
    J_full = pab_propagate_and_cost(uω0, phi_opt, fiber, sim, band_mask)

    @info "Computing J_flat (zero phase)"
    J_flat = pab_propagate_and_cost(uω0, zeros(Nt), fiber, sim, band_mask)

    @info @sprintf("Baselines: J_full=%.4e (%.1f dB), J_flat=%.4e (%.1f dB)",
        J_full, 10*log10(max(J_full,1e-15)), J_flat, 10*log10(max(J_flat,1e-15)))

    # --- Band zeroing: zero one sub-band at a time ---
    band_zeroing_J = zeros(Float64, n_bands)
    for (k, sb) in enumerate(sub_band_edges)
        # Build smooth zeroing window in fftshifted order
        window_shifted = pab_make_ablation_window(fs_fftshifted, sb.band_lo, sb.band_hi)
        # Convert to FFT order before multiplying phi_opt
        window_fft  = ifftshift(window_shifted)
        phi_ablated = phi_opt .* window_fft
        J_ablated   = pab_propagate_and_cost(uω0, phi_ablated, fiber, sim, band_mask)
        band_zeroing_J[k] = J_ablated
        @info @sprintf("  Band %2d [%.1f–%.1f THz]: J_ablated=%.4e (%.1f dB, Δ=%.2f dB)",
            k, sb.band_lo, sb.band_hi, J_ablated,
            10*log10(max(J_ablated,1e-15)),
            10*log10(max(J_ablated,1e-15)) - 10*log10(max(J_full,1e-15)))
    end

    return band_zeroing_J, sub_band_edges, J_full, J_flat
end

# ─────────────────────────────────────────────────────────────────────────────
# 7. Experiment 2: Cumulative ablation (D-09)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_cumulative_ablation(cfg, sub_band_edges, J_full) -> (cumulative_J, n_remaining)

Zero bands from edges inward (bands 1,10,2,9,...) progressively and track J.
Returns J for each step, where step k has zeroed the k outermost pairs.

# Returns
- `cumulative_J`: J at each ablation step (length n_bands/2 + 1 with final step = all zeroed)
- `n_remaining`: number of sub-bands remaining at each step
- `bandwidth_remaining_THz`: approximate remaining bandwidth at each step
"""
function pab_cumulative_ablation(cfg, sub_band_edges, J_full)
    uω0 = cfg.uω0; fiber = cfg.fiber; sim = cfg.sim
    band_mask = cfg.band_mask; phi_opt = cfg.phi_opt

    n_bands = length(sub_band_edges)
    Nt = length(phi_opt)
    fs_fftshifted = fftshift(fftfreq(Nt, 1/sim["Δt"]))  # THz

    # Order: zero from edges inward — band 1, band n_bands, band 2, band n_bands-1, ...
    # Build sequence of (lo_idx, hi_idx) pairs to zero progressively
    lo_indices = collect(1:div(n_bands, 2))
    hi_indices = collect(n_bands:-1:(n_bands - div(n_bands,2) + 1))
    edge_pairs = collect(zip(lo_indices, hi_indices))

    # n_ablation_steps = number of unique pairs + 1 (include all-zeroed final step)
    # For n_bands=10: 5 pairs + 1 baseline = 6 points
    # Steps: 0 bands zeroed (=J_full), 2 zeroed (1+10), 4 zeroed (1+10+2+9), etc.
    n_steps = length(edge_pairs) + 1
    cumulative_J = zeros(Float64, n_steps)
    n_remaining  = zeros(Int, n_steps)
    bandwidth_remaining_THz = zeros(Float64, n_steps)

    total_bandwidth = sub_band_edges[end].band_hi - sub_band_edges[1].band_lo

    # Step 0: no bands zeroed (full phi_opt)
    cumulative_J[1]              = J_full
    n_remaining[1]               = n_bands
    bandwidth_remaining_THz[1]   = total_bandwidth

    # Accumulate zeroing window from edges inward
    cumulative_window_shifted = ones(Float64, length(fs_fftshifted))

    for (step, (lo_idx, hi_idx)) in enumerate(edge_pairs)
        # Zero both the lo and hi edge bands
        for band_idx in [lo_idx, hi_idx]
            sb = sub_band_edges[band_idx]
            edge_window = pab_make_ablation_window(fs_fftshifted, sb.band_lo, sb.band_hi)
            cumulative_window_shifted .= cumulative_window_shifted .* edge_window
        end

        # Apply cumulative window (converted to FFT order)
        window_fft  = ifftshift(cumulative_window_shifted)
        phi_ablated = phi_opt .* window_fft

        J_cum = pab_propagate_and_cost(uω0, phi_ablated, fiber, sim, band_mask)
        n_kept = n_bands - 2 * step  # bands not zeroed: total - 2 edge pairs zeroed
        # Remaining bandwidth: inner bands only
        remaining_bw = (n_kept > 0) ?
            (sub_band_edges[n_bands - step].band_hi - sub_band_edges[step + 1].band_lo) :
            0.0

        cumulative_J[step + 1]            = J_cum
        n_remaining[step + 1]             = max(n_kept, 0)
        bandwidth_remaining_THz[step + 1] = max(remaining_bw, 0.0)

        @info @sprintf("  Cumulative step %d: %d bands zeroed, %d remaining, J=%.4e (%.1f dB)",
            step, 2*step, max(n_kept,0), J_cum, 10*log10(max(J_cum,1e-15)))
    end

    return cumulative_J, n_remaining, bandwidth_remaining_THz
end

# ─────────────────────────────────────────────────────────────────────────────
# 8. Experiment 3: Global scaling (D-10)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_scaling_sweep(cfg) -> Vector{Float64}

Multiply phi_opt by each factor in PAB_SCALE_FACTORS and propagate.
Returns J values for each scale factor.
"""
function pab_scaling_sweep(cfg)
    uω0 = cfg.uω0; fiber = cfg.fiber; sim = cfg.sim
    band_mask = cfg.band_mask; phi_opt = cfg.phi_opt

    scale_J = zeros(Float64, length(PAB_SCALE_FACTORS))
    for (k, α) in enumerate(PAB_SCALE_FACTORS)
        phi_scaled = α .* phi_opt
        J_scaled   = pab_propagate_and_cost(uω0, phi_scaled, fiber, sim, band_mask)
        scale_J[k] = J_scaled
        @info @sprintf("  Scale=%.2f: J=%.4e (%.1f dB)", α, J_scaled, 10*log10(max(J_scaled,1e-15)))
    end
    return scale_J
end

# ─────────────────────────────────────────────────────────────────────────────
# 9. Experiment 4: Spectral shift (D-11)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_shift_sweep(cfg) -> Vector{Float64}

Translate phi_opt by each offset in PAB_SHIFT_THZ and propagate.
Returns J values for each spectral shift.
"""
function pab_shift_sweep(cfg)
    uω0 = cfg.uω0; fiber = cfg.fiber; sim = cfg.sim
    band_mask = cfg.band_mask; phi_opt = cfg.phi_opt; sim_ref = sim

    shift_J = zeros(Float64, length(PAB_SHIFT_THZ))
    for (k, δf) in enumerate(PAB_SHIFT_THZ)
        phi_shifted = pab_shift_phase_spectrum(phi_opt, sim_ref, δf)
        J_shifted   = pab_propagate_and_cost(uω0, phi_shifted, fiber, sim, band_mask)
        shift_J[k]  = J_shifted
        @info @sprintf("  Shift=%.1f THz: J=%.4e (%.1f dB)", δf, J_shifted, 10*log10(max(J_shifted,1e-15)))
    end
    return shift_J
end

# ─────────────────────────────────────────────────────────────────────────────
# 10. Figures
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_plot_band_zeroing(results_smf28, results_hnlf)

Figure 10_05: Bar chart of suppression loss when each sub-band is zeroed.
Two panels: left=SMF-28, right=HNLF.
"""
function pab_plot_band_zeroing(results_smf28, results_hnlf)
    fig, axes = subplots(1, 2, figsize=(14, 5))

    for (ax, res, title_str) in [
            (axes[1], results_smf28, "SMF-28 L=2m, P=0.2W"),
            (axes[2], results_hnlf,  "HNLF L=1m, P=0.01W"),
        ]

        band_zeroing_J = res[:band_zeroing_J]
        sub_band_edges = res[:sub_band_edges]
        J_full         = res[:J_full]
        J_flat         = res[:J_flat]
        n_bands        = length(band_zeroing_J)

        # Suppression loss: how much worse is J when this band is zeroed vs full phi_opt?
        loss_dB = [10*log10(max(band_zeroing_J[k], 1e-15)) - 10*log10(max(J_full, 1e-15))
                   for k in 1:n_bands]
        band_centers = [sb.band_center for sb in sub_band_edges]

        # Color bars by frequency position (viridis colormap)
        cmap = get_cmap("viridis")
        fc_min, fc_max = minimum(band_centers), maximum(band_centers)

        for k in 1:n_bands
            norm_fc = (band_centers[k] - fc_min) / (fc_max - fc_min + 1e-10)
            color   = cmap(norm_fc)
            ax.bar(k, loss_dB[k], color=color, edgecolor="k", linewidth=0.5, zorder=2)
        end

        # 3 dB threshold line
        ax.axhline(3.0, color="firebrick", linestyle="--", linewidth=1.5,
                   label="3 dB threshold", zorder=3)

        # Annotate baselines
        J_full_dB = 10*log10(max(J_full, 1e-15))
        J_flat_dB = 10*log10(max(J_flat, 1e-15))
        ax.text(0.98, 0.97, @sprintf("φ_opt: %.1f dB\nFlat: %.1f dB", J_full_dB, J_flat_dB),
                transform=ax.transAxes, ha="right", va="top", fontsize=9,
                bbox=Dict("boxstyle"=>"round,pad=0.3", "facecolor"=>"white", "alpha"=>0.8))

        # x-axis tick labels: band center frequency in THz
        ax.set_xticks(1:n_bands)
        ax.set_xticklabels([@sprintf("%.1f", bc) for bc in band_centers], rotation=45, ha="right", fontsize=8)
        ax.set_xlabel("Band center frequency [THz]")
        ax.set_ylabel("Suppression loss when band zeroed [dB]")
        ax.set_title(title_str)
        ax.legend(fontsize=9)
        ax.grid(true, axis="y", alpha=0.3, zorder=1)
    end

    fig.suptitle("Raman suppression sensitivity to frequency-band zeroing", fontsize=13, fontweight="bold")
    fig.tight_layout()
    savepath = joinpath(PAB_FIGURE_DIR, "physics_10_05_ablation_band_zeroing.png")
    fig.savefig(savepath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved: $savepath"
end

"""
    pab_plot_cumulative(results_smf28, results_hnlf)

Figure 10_06: Cumulative ablation — J vs number of remaining sub-bands.
"""
function pab_plot_cumulative(results_smf28, results_hnlf)
    fig, axes = subplots(1, 2, figsize=(14, 5))

    for (ax, res, title_str) in [
            (axes[1], results_smf28, "SMF-28 L=2m, P=0.2W"),
            (axes[2], results_hnlf,  "HNLF L=1m, P=0.01W"),
        ]

        cumulative_J  = res[:cumulative_J]
        n_remaining   = res[:n_remaining]
        bw_remaining  = res[:bandwidth_remaining_THz]
        J_full        = res[:J_full]
        J_flat        = res[:J_flat]

        J_dB = [10*log10(max(J, 1e-15)) for J in cumulative_J]
        J_full_dB = 10*log10(max(J_full, 1e-15))
        J_flat_dB = 10*log10(max(J_flat, 1e-15))

        ax.plot(n_remaining, J_dB, "o-", color=COLOR_INPUT, linewidth=2,
                markersize=6, markerfacecolor="white", markeredgewidth=2, zorder=3)

        # Mark full phi_opt at n_remaining = max
        ax.scatter([n_remaining[1]], [J_full_dB], color=COLOR_INPUT, s=80, zorder=4,
                   label=@sprintf("Full φ_opt: %.1f dB", J_full_dB))

        # Flat phase baseline
        ax.axhline(J_flat_dB, color=COLOR_OUTPUT, linestyle="--", linewidth=1.5,
                   label=@sprintf("Flat phase: %.1f dB", J_flat_dB))

        ax.set_xlabel("Sub-bands remaining (out of $(n_remaining[1]))")
        ax.set_ylabel("Raman suppression J [dB]")
        ax.set_title(title_str)
        ax.legend(fontsize=9)
        ax.grid(true, alpha=0.3)
        ax.invert_xaxis()  # show truncation from right (edges removed first)

        # Secondary x-axis: approximate remaining bandwidth
        valid_bw = bw_remaining[n_remaining .> 0]
        valid_nr = n_remaining[n_remaining .> 0]
        if !isempty(valid_bw)
            ax2 = ax.twiny()
            ax2.set_xlim(ax.get_xlim())
            ax2.set_xticks(valid_nr)
            ax2.set_xticklabels([@sprintf("%.1f", bw) for bw in valid_bw],
                                 rotation=45, ha="left", fontsize=8)
            ax2.set_xlabel("Remaining bandwidth [THz]", fontsize=9)
        end
    end

    fig.suptitle("Suppression vs. remaining phase bandwidth", fontsize=13, fontweight="bold")
    fig.tight_layout()
    savepath = joinpath(PAB_FIGURE_DIR, "physics_10_06_ablation_cumulative.png")
    fig.savefig(savepath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved: $savepath"
end

"""
    pab_plot_scaling(results_smf28, results_hnlf)

Figure 10_07: Global scaling robustness — J vs phi_opt scale factor with 3 dB envelope.
"""
function pab_plot_scaling(results_smf28, results_hnlf)
    fig, axes = subplots(1, 2, figsize=(14, 5))

    for (ax, res, title_str) in [
            (axes[1], results_smf28, "SMF-28 L=2m, P=0.2W"),
            (axes[2], results_hnlf,  "HNLF L=1m, P=0.01W"),
        ]

        scale_J   = res[:scale_J]
        J_full    = res[:J_full]
        J_flat    = res[:J_flat]
        factors   = PAB_SCALE_FACTORS

        scale_J_dB  = [10*log10(max(J, 1e-15)) for J in scale_J]
        J_full_dB   = 10*log10(max(J_full, 1e-15))
        J_flat_dB   = 10*log10(max(J_flat, 1e-15))

        # Find the 3 dB envelope: where scale_J_dB < J_full_dB + 3
        threshold_dB = J_full_dB + 3.0
        in_3dB = scale_J_dB .<= threshold_dB

        # Shade the 3 dB envelope region
        if any(in_3dB)
            lo_factor = minimum(factors[in_3dB])
            hi_factor = maximum(factors[in_3dB])
            ax.axvspan(lo_factor, hi_factor, alpha=0.15, color="steelblue",
                       label=@sprintf("3 dB envelope [%.2f–%.2f]", lo_factor, hi_factor))
        end

        ax.plot(factors, scale_J_dB, "o-", color=COLOR_INPUT, linewidth=2,
                markersize=6, markerfacecolor="white", markeredgewidth=2, zorder=3)

        # Mark optimal (scale=1.0)
        idx1 = findfirst(==(1.0), factors)
        if !isnothing(idx1)
            ax.scatter([1.0], [scale_J_dB[idx1]], color=COLOR_INPUT, s=100,
                       zorder=4, label=@sprintf("Scale=1.0: %.1f dB", scale_J_dB[idx1]))
        end

        # 3 dB line
        ax.axhline(threshold_dB, color="firebrick", linestyle="--", linewidth=1.5,
                   label=@sprintf("+3 dB from optimal (%.1f dB)", threshold_dB))

        # Flat baseline
        ax.axhline(J_flat_dB, color=COLOR_OUTPUT, linestyle=":", linewidth=1.5,
                   label=@sprintf("Flat phase: %.1f dB", J_flat_dB))

        ax.set_xlabel("φ_opt scale factor α")
        ax.set_ylabel("Raman suppression J [dB]")
        ax.set_title(title_str)
        ax.legend(fontsize=8)
        ax.grid(true, alpha=0.3)
    end

    fig.suptitle("Scaling robustness of optimal phase", fontsize=13, fontweight="bold")
    fig.tight_layout()
    savepath = joinpath(PAB_FIGURE_DIR, "physics_10_07_scaling_robustness.png")
    fig.savefig(savepath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved: $savepath"
end

"""
    pab_plot_shift(results_smf28, results_hnlf)

Figure 10_08: Spectral shift sensitivity — J vs spectral shift (THz).
"""
function pab_plot_shift(results_smf28, results_hnlf)
    fig, axes = subplots(1, 2, figsize=(14, 5))

    for (ax, res, title_str) in [
            (axes[1], results_smf28, "SMF-28 L=2m, P=0.2W"),
            (axes[2], results_hnlf,  "HNLF L=1m, P=0.01W"),
        ]

        shift_J   = res[:shift_J]
        J_full    = res[:J_full]
        J_flat    = res[:J_flat]
        shifts    = PAB_SHIFT_THZ

        shift_J_dB = [10*log10(max(J, 1e-15)) for J in shift_J]
        J_full_dB  = 10*log10(max(J_full, 1e-15))
        J_flat_dB  = 10*log10(max(J_flat, 1e-15))

        # 3 dB envelope around 0-shift minimum
        threshold_dB = J_full_dB + 3.0
        in_3dB = shift_J_dB .<= threshold_dB
        if any(in_3dB)
            lo_shift = minimum(shifts[in_3dB])
            hi_shift = maximum(shifts[in_3dB])
            ax.axvspan(lo_shift, hi_shift, alpha=0.15, color="steelblue",
                       label=@sprintf("3 dB envelope [%.1f–%.1f THz]", lo_shift, hi_shift))
        end

        ax.plot(shifts, shift_J_dB, "o-", color=COLOR_INPUT, linewidth=2,
                markersize=6, markerfacecolor="white", markeredgewidth=2, zorder=3)

        # Mark zero shift
        idx0 = findfirst(==(0.0), shifts)
        if !isnothing(idx0)
            ax.scatter([0.0], [shift_J_dB[idx0]], color=COLOR_INPUT, s=100, zorder=4,
                       label=@sprintf("Δf=0: %.1f dB", shift_J_dB[idx0]))
        end

        ax.axhline(J_flat_dB, color=COLOR_OUTPUT, linestyle="--", linewidth=1.5,
                   label=@sprintf("Flat phase: %.1f dB", J_flat_dB))

        ax.set_xlabel("Spectral shift Δf [THz]")
        ax.set_ylabel("Raman suppression J [dB]")
        ax.set_title(title_str)
        ax.legend(fontsize=9)
        ax.grid(true, alpha=0.3)
    end

    fig.suptitle("Spectral shift sensitivity of optimal phase", fontsize=13, fontweight="bold")
    fig.tight_layout()
    savepath = joinpath(PAB_FIGURE_DIR, "physics_10_08_spectral_shift_robustness.png")
    fig.savefig(savepath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved: $savepath"
end

"""
    pab_plot_summary(results_smf28, results_hnlf)

Figure 10_09: 2x2 multi-panel ablation summary overlaying SMF-28 vs HNLF.
"""
function pab_plot_summary(results_smf28, results_hnlf)
    fig, axes = subplots(2, 2, figsize=(14, 10))

    color_smf = COLOR_INPUT    # blue for SMF-28
    color_hnlf = COLOR_OUTPUT  # vermillion for HNLF

    # ── Panel (1,1): Band zeroing — normalized to each config's J_full ──
    ax = axes[1, 1]
    for (res, color, lbl) in [
            (results_smf28, color_smf,  "SMF-28"),
            (results_hnlf,  color_hnlf, "HNLF"),
        ]
        bz_J   = res[:band_zeroing_J]
        J_full = res[:J_full]
        sbe    = res[:sub_band_edges]
        n      = length(bz_J)
        # Suppression loss normalized to J_full (degradation in dB)
        loss_dB = [10*log10(max(bz_J[k], 1e-15)) - 10*log10(max(J_full, 1e-15)) for k in 1:n]
        ax.plot(1:n, loss_dB, "o-", color=color, linewidth=1.5, markersize=5, label=lbl)
    end
    ax.axhline(3.0, color="firebrick", linestyle="--", linewidth=1.2, label="3 dB threshold")
    ax.set_xlabel("Sub-band index")
    ax.set_ylabel("Suppression loss [dB]")
    ax.set_title("(a) Band zeroing sensitivity")
    ax.legend(fontsize=9)
    ax.grid(true, alpha=0.3)

    # ── Panel (1,2): Cumulative ablation ──
    ax = axes[1, 2]
    for (res, color, lbl) in [
            (results_smf28, color_smf,  "SMF-28"),
            (results_hnlf,  color_hnlf, "HNLF"),
        ]
        cum_J  = res[:cumulative_J]
        nr     = res[:n_remaining]
        J_full = res[:J_full]
        J_dB   = [10*log10(max(J, 1e-15)) for J in cum_J]
        ax.plot(nr, J_dB, "o-", color=color, linewidth=1.5, markersize=5, label=lbl)
    end
    ax.set_xlabel("Sub-bands remaining")
    ax.set_ylabel("Raman suppression J [dB]")
    ax.set_title("(b) Cumulative ablation (edges inward)")
    ax.legend(fontsize=9)
    ax.grid(true, alpha=0.3)
    ax.invert_xaxis()

    # ── Panel (2,1): Scaling robustness ──
    ax = axes[2, 1]
    for (res, color, lbl) in [
            (results_smf28, color_smf,  "SMF-28"),
            (results_hnlf,  color_hnlf, "HNLF"),
        ]
        sc_J    = res[:scale_J]
        J_full  = res[:J_full]
        sc_dB   = [10*log10(max(J, 1e-15)) for J in sc_J]
        ax.plot(PAB_SCALE_FACTORS, sc_dB, "o-", color=color, linewidth=1.5, markersize=5, label=lbl)
    end
    ax.axvline(1.0, color="gray", linestyle=":", linewidth=1.2)
    ax.set_xlabel("Scale factor α")
    ax.set_ylabel("Raman suppression J [dB]")
    ax.set_title("(c) Global scaling robustness")
    ax.legend(fontsize=9)
    ax.grid(true, alpha=0.3)

    # ── Panel (2,2): Spectral shift sensitivity ──
    ax = axes[2, 2]
    for (res, color, lbl) in [
            (results_smf28, color_smf,  "SMF-28"),
            (results_hnlf,  color_hnlf, "HNLF"),
        ]
        sh_J    = res[:shift_J]
        sh_dB   = [10*log10(max(J, 1e-15)) for J in sh_J]
        ax.plot(PAB_SHIFT_THZ, sh_dB, "o-", color=color, linewidth=1.5, markersize=5, label=lbl)
    end
    ax.axvline(0.0, color="gray", linestyle=":", linewidth=1.2)
    ax.set_xlabel("Spectral shift Δf [THz]")
    ax.set_ylabel("Raman suppression J [dB]")
    ax.set_title("(d) Spectral shift sensitivity")
    ax.legend(fontsize=9)
    ax.grid(true, alpha=0.3)

    fig.suptitle("Phase ablation summary: SMF-28 vs HNLF", fontsize=14, fontweight="bold")
    fig.tight_layout()
    savepath = joinpath(PAB_FIGURE_DIR, "physics_10_09_ablation_summary.png")
    fig.savefig(savepath, dpi=300, bbox_inches="tight")
    close(fig)
    @info "Saved: $savepath"
end

# ─────────────────────────────────────────────────────────────────────────────
# 11. Write findings document
# ─────────────────────────────────────────────────────────────────────────────

"""
    pab_write_findings(results_smf28, results_hnlf, output_path)

Write PHASE10_ABLATION_FINDINGS.md summarizing critical bands, robustness envelope,
and new hypotheses derived from the ablation/perturbation experiments.
"""
function pab_write_findings(results_smf28, results_hnlf, output_path)
    smf = results_smf28
    hnlf = results_hnlf

    # Extract key values
    bz_smf   = smf[:band_zeroing_J]; bz_hnlf = hnlf[:band_zeroing_J]
    sbe_smf  = smf[:sub_band_edges]; sbe_hnlf = hnlf[:sub_band_edges]
    J_full_smf = smf[:J_full];       J_full_hnlf = hnlf[:J_full]
    J_flat_smf = smf[:J_flat];       J_flat_hnlf = hnlf[:J_flat]
    cum_smf  = smf[:cumulative_J];   cum_hnlf = hnlf[:cumulative_J]
    nr_smf   = smf[:n_remaining];    nr_hnlf  = hnlf[:n_remaining]
    sc_smf   = smf[:scale_J];        sc_hnlf  = hnlf[:scale_J]
    sh_smf   = smf[:shift_J];        sh_hnlf  = hnlf[:shift_J]

    n_bands = length(bz_smf)

    # Suppression loss per band (dB)
    loss_smf = [10*log10(max(bz_smf[k],1e-15)) - 10*log10(max(J_full_smf,1e-15)) for k in 1:n_bands]
    loss_hnlf = [10*log10(max(bz_hnlf[k],1e-15)) - 10*log10(max(J_full_hnlf,1e-15)) for k in 1:n_bands]

    # Critical bands: those with > 3 dB loss when zeroed
    critical_smf  = findall(>(3.0), loss_smf)
    critical_hnlf = findall(>(3.0), loss_hnlf)

    # Scaling: 3 dB range
    threshold_smf  = 10*log10(max(J_full_smf,1e-15)) + 3.0
    threshold_hnlf = 10*log10(max(J_full_hnlf,1e-15)) + 3.0
    sc_dB_smf  = [10*log10(max(J,1e-15)) for J in sc_smf]
    sc_dB_hnlf = [10*log10(max(J,1e-15)) for J in sc_hnlf]
    in3_smf    = PAB_SCALE_FACTORS[sc_dB_smf .<= threshold_smf]
    in3_hnlf   = PAB_SCALE_FACTORS[sc_dB_hnlf .<= threshold_hnlf]

    # Shift: 3 dB range
    sh_dB_smf  = [10*log10(max(J,1e-15)) for J in sh_smf]
    sh_dB_hnlf = [10*log10(max(J,1e-15)) for J in sh_hnlf]
    in3sh_smf  = PAB_SHIFT_THZ[sh_dB_smf .<= threshold_smf]
    in3sh_hnlf = PAB_SHIFT_THZ[sh_dB_hnlf .<= threshold_hnlf]

    # Cumulative: how many bands needed before 3 dB degradation?
    cum_dB_smf  = [10*log10(max(J,1e-15)) for J in cum_smf]
    cum_dB_hnlf = [10*log10(max(J,1e-15)) for J in cum_hnlf]
    J_full_dB_smf  = 10*log10(max(J_full_smf,1e-15))
    J_full_dB_hnlf = 10*log10(max(J_full_hnlf,1e-15))
    cum_3dB_smf  = findfirst(>(J_full_dB_smf + 3.0), cum_dB_smf)
    cum_3dB_hnlf = findfirst(>(J_full_dB_hnlf + 3.0), cum_dB_hnlf)
    bands_before_3dB_smf  = isnothing(cum_3dB_smf)  ? nr_smf[1]  : nr_smf[cum_3dB_smf - 1]
    bands_before_3dB_hnlf = isnothing(cum_3dB_hnlf) ? nr_hnlf[1] : nr_hnlf[cum_3dB_hnlf - 1]

    open(output_path, "w") do io
        write(io, """# Phase 10 Ablation Findings

**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))
**Canonical configs:** SMF-28 L=2m P=0.2W (multi-start) · HNLF L=1m P=0.01W (best suppression)
**Phase 9 context:** 84% of Raman suppression attributed to "configuration-specific nonlinear interference" — this phase asks which spectral frequencies of φ_opt carry that suppression.

---

## 1. Band Zeroing Results

Each of 10 equal-width sub-bands of the signal spectrum was individually zeroed using
a super-Gaussian window (order 6, 10% roll-off). Suppression loss = J_ablated - J_full in dB.

| Band | Center [THz] | Loss SMF-28 [dB] | Critical? | Loss HNLF [dB] | Critical? |
|------|-------------|-----------------|-----------|---------------|-----------|
""")
        for k in 1:n_bands
            smf_crit  = loss_smf[k] > 3.0 ? "YES" : "no"
            hnlf_crit = loss_hnlf[k] > 3.0 ? "YES" : "no"
            write(io, @sprintf("| %2d   | %+7.2f     | %+7.2f            | %-9s | %+7.2f         | %-9s |\n",
                k, sbe_smf[k].band_center, loss_smf[k], smf_crit, loss_hnlf[k], hnlf_crit))
        end

        write(io, """
**Critical bands (>3 dB loss when zeroed):**
- SMF-28: bands $(isempty(critical_smf) ? "none" : join(critical_smf, ", "))
  $(isempty(critical_smf) ? "(suppression distributed; no single band dominates)" : @sprintf("Centers: %s THz", join([@sprintf("%.1f", sbe_smf[k].band_center) for k in critical_smf], ", ")))
- HNLF: bands $(isempty(critical_hnlf) ? "none" : join(critical_hnlf, ", "))
  $(isempty(critical_hnlf) ? "(suppression distributed; no single band dominates)" : @sprintf("Centers: %s THz", join([@sprintf("%.1f", sbe_hnlf[k].band_center) for k in critical_hnlf], ", ")))

**Baselines:**
- SMF-28: φ_opt → $(round(J_full_dB_smf, digits=1)) dB | Flat phase → $(round(10*log10(max(J_flat_smf,1e-15)), digits=1)) dB
- HNLF: φ_opt → $(round(J_full_dB_hnlf, digits=1)) dB | Flat phase → $(round(10*log10(max(J_flat_hnlf,1e-15)), digits=1)) dB

---

## 2. Cumulative Ablation

Bands zeroed from spectral edges inward (outermost pair first, then next pair, etc.).
Reports the minimum number of central sub-bands needed to maintain suppression within 3 dB of full φ_opt.

| Step | Bands Remaining | J SMF-28 [dB] | J HNLF [dB] |
|------|----------------|--------------|------------|
""")
        for i in 1:min(length(cum_smf), length(cum_hnlf))
            write(io, @sprintf("| %d    | %2d             | %+8.2f      | %+8.2f     |\n",
                i-1, nr_smf[i], cum_dB_smf[i], cum_dB_hnlf[i]))
        end

        write(io, """
**3 dB bandwidth requirement:**
- SMF-28: $(bands_before_3dB_smf) sub-bands needed before 3 dB degradation
- HNLF: $(bands_before_3dB_hnlf) sub-bands needed before 3 dB degradation

$(bands_before_3dB_smf == n_bands && bands_before_3dB_hnlf == n_bands ?
  "Full bandwidth is required for both configs — no spectral truncation is tolerated." :
  "Partial bandwidth is sufficient — the edges of φ_opt contribute less than the central region.")

---

## 3. Scaling Robustness (3 dB Envelope)

Global scale factor α multiplied phi_opt. The 3 dB envelope spans scale factors where
suppression degrades by less than 3 dB relative to α=1.0.

- **SMF-28:** 3 dB envelope = $(isempty(in3_smf) ? "none — very narrow" : @sprintf("[%.2f, %.2f]", minimum(in3_smf), maximum(in3_smf)))
- **HNLF:** 3 dB envelope = $(isempty(in3_hnlf) ? "none — very narrow" : @sprintf("[%.2f, %.2f]", minimum(in3_hnlf), maximum(in3_hnlf)))

Scale factors tested: $(join([@sprintf("%.2f", f) for f in PAB_SCALE_FACTORS], ", "))

J at selected scales (SMF-28): $(join([@sprintf("%.1f", dB) for dB in sc_dB_smf], ", ")) dB
J at selected scales (HNLF): $(join([@sprintf("%.1f", dB) for dB in sc_dB_hnlf], ", ")) dB

---

## 4. Spectral Shift Sensitivity

phi_opt was translated by ±1, ±2, ±5 THz on the frequency grid using linear interpolation.
Shift sensitivity characterizes whether phi_opt is narrowly tuned to specific spectral features.

- **SMF-28:** 3 dB shift tolerance = $(isempty(in3sh_smf) ? "< ±1 THz (very sensitive)" : @sprintf("[%.1f, %.1f] THz", minimum(in3sh_smf), maximum(in3sh_smf)))
- **HNLF:** 3 dB shift tolerance = $(isempty(in3sh_hnlf) ? "< ±1 THz (very sensitive)" : @sprintf("[%.1f, %.1f] THz", minimum(in3sh_hnlf), maximum(in3sh_hnlf)))

J vs shift (SMF-28): $(join([@sprintf("%.1f", dB) for dB in sh_dB_smf], ", ")) dB
J vs shift (HNLF): $(join([@sprintf("%.1f", dB) for dB in sh_dB_hnlf], ", ")) dB

---

## 5. New Hypothesis: Mechanism Attribution

### H1: Phase suppression is spectrally distributed, not localized to a narrow pump-adjacent band

**Evidence:** If critical bands are scattered across the signal spectrum (not concentrated at DC or
pump frequency), this supports the conclusion that the optimizer exploits the full spectral phase
structure — consistent with the 84% non-polynomial phase finding from Phase 9.

**Falsified by:** A single band accounting for >10 dB of suppression while all others contribute <1 dB.

### H2: phi_opt is spectrally broad relative to the Raman detuning (13.2 THz)

**Prediction:** The spectral shift tolerance should be much narrower than 13.2 THz.
If phi_opt degrades by 3 dB with only 1-2 THz shift, the optimal phase encodes spectral
features on a sub-THz scale — finer than the Raman gain bandwidth.

**Implication:** The optimizer is exploiting interference at the spectral scale of the Raman
gain profile (few THz), not just the pump carrier.

### H3: Amplitude-sensitive nonlinear interference (not classical chirp management)

**Evidence from scaling:** If J_scaled degrades rapidly for α ≠ 1.0 (narrow 3 dB envelope),
the suppression depends on the precise amplitude of phase modulation — not just its spectral shape.
This is inconsistent with a simple chirp (GDD, TOD) interpretation, where scaling would shift
the soliton order but maintain qualitative behavior.

**Comparison with Phase 9:** Phase 9 found GDD + TOD explains only ~16% of the phase structure.
The remaining 84% must create precise amplitude-dependent interference — the scaling experiment
tests whether this interference is robust (broad envelope) or fragile (narrow envelope).

### H4: SMF-28 and HNLF exploit similar spectral regions despite different fiber parameters

**Test:** Compare critical_smf vs critical_hnlf — do the same sub-band indices appear?
If yes: the optimizer finds the same spectral strategy regardless of fiber nonlinearity γ and β₂.
If no: the mechanism is fiber-specific, consistent with the multi-start correlation = 0.109 finding
(different phi_opt profiles, each tuned to their specific fiber).

---

## 6. Comparison with Phase 9 Findings

| Phase 9 Finding | Ablation Evidence |
|----------------|-------------------|
| 84% non-polynomial phase structure | Band zeroing tells us which spectral regions this structure occupies |
| Multi-start correlation = 0.109 | Scaling robustness tells us how precisely the amplitude must be tuned |
| N_sol > 2 vs ≤ 2 clustering | SMF-28 (N≈2.6) vs HNLF (N≈3.6) band comparison probes fiber-type dependence |
| H5 (propagation diagnostics) deferred | Phase 10 Plan 01 addresses H5 directly via z-resolved snapshots |

---

## 7. Practical Implications for Pulse Shaping

- **3 dB scaling envelope:** Determines required precision of pulse shaper amplitude calibration.
- **3 dB shift tolerance:** Determines required carrier frequency stability of the shaped pulse.
- **Critical bands:** Guide which spectral regions require the highest phase resolution (most actuators).
""")
    end
    @info "Saved findings: $output_path"
end

end  # !(@isdefined _PAB_SCRIPT_LOADED)

# ─────────────────────────────────────────────────────────────────────────────
# Main execution block
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    mkpath(PAB_RESULTS_DIR)
    mkpath(PAB_FIGURE_DIR)

    @info "=" ^ 70
    @info "Phase 10 Plan 02: Phase Ablation & Perturbation Experiments"
    @info "Configs: $(length(PAB_CONFIGS)) canonical configurations"
    @info "Experiments: band zeroing ($(PAB_N_BANDS) bands) + cumulative + scaling ($(length(PAB_SCALE_FACTORS)) factors) + shift ($(length(PAB_SHIFT_THZ)) offsets)"
    @info "=" ^ 70

    results_all = Dict{String, Dict{Symbol, Any}}()

    for cfg_spec in PAB_CONFIGS
        @info ""
        @info "─" ^ 60
        @info "Config: $(cfg_spec.label)  [$(cfg_spec.fiber_dir)/$(cfg_spec.config)]"
        @info "─" ^ 60

        cfg = pab_load_config(cfg_spec.fiber_dir, cfg_spec.config, cfg_spec.preset)
        @info @sprintf("Loaded: Nt=%d, time_window=%.1f ps, L=%.1f m, P=%.4f W, J_after=%.4e",
            cfg.Nt, cfg.sim["Nt"] > 0 ? Float64(cfg.sim["Nt"]) * cfg.sim["Δt"] : 0.0,
            cfg.L, cfg.P_cont, cfg.J_after)

        # ── Experiment 1: Band zeroing ──
        @info ""
        @info "Experiment 1: Band zeroing ($(PAB_N_BANDS) sub-bands)"
        band_zeroing_J, sub_band_edges, J_full, J_flat = pab_band_zeroing(cfg)

        # ── Experiment 2: Cumulative ablation ──
        @info ""
        @info "Experiment 2: Cumulative ablation (edges inward)"
        cumulative_J, n_remaining, bandwidth_remaining = pab_cumulative_ablation(
            cfg, sub_band_edges, J_full)

        # ── Experiment 3: Global scaling ──
        @info ""
        @info "Experiment 3: Global scaling sweep"
        scale_J = pab_scaling_sweep(cfg)

        # ── Experiment 4: Spectral shift ──
        @info ""
        @info "Experiment 4: Spectral shift sweep"
        shift_J = pab_shift_sweep(cfg)

        # Collect results
        res = Dict{Symbol, Any}(
            :band_zeroing_J         => band_zeroing_J,
            :sub_band_edges         => sub_band_edges,
            :J_full                 => J_full,
            :J_flat                 => J_flat,
            :cumulative_J           => cumulative_J,
            :n_remaining            => n_remaining,
            :bandwidth_remaining_THz => bandwidth_remaining,
            :scale_J                => scale_J,
            :shift_J                => shift_J,
            :config                 => cfg_spec.config,
            :fiber_name             => cfg.fiber_name,
        )
        results_all[cfg_spec.fiber_dir] = res

        # ── Save JLD2 for this config ──
        if cfg_spec.fiber_dir == "smf28"
            ablation_path    = joinpath(PAB_RESULTS_DIR, "ablation_smf28_canonical.jld2")
            perturbation_path = joinpath(PAB_RESULTS_DIR, "perturbation_smf28_canonical.jld2")
        else
            ablation_path    = joinpath(PAB_RESULTS_DIR, "ablation_hnlf_canonical.jld2")
            perturbation_path = joinpath(PAB_RESULTS_DIR, "perturbation_hnlf_canonical.jld2")
        end

        # Band zeroing + cumulative
        JLD2.save(ablation_path,
            "band_zeroing_J",   band_zeroing_J,
            "cumulative_J",     cumulative_J,
            "n_remaining",      n_remaining,
            "sub_bands",        [(lo=sb.band_lo, hi=sb.band_hi, center=sb.band_center) for sb in sub_band_edges],
            "bandwidth_remaining_THz", bandwidth_remaining,
            "J_full",           J_full,
            "J_flat",           J_flat,
            "config",           cfg_spec.config,
            "fiber_name",       cfg.fiber_name,
            "n_bands",          PAB_N_BANDS,
        )
        @info "Saved ablation data: $ablation_path"

        # Scaling + shift perturbation
        JLD2.save(perturbation_path,
            "scale_factors",    PAB_SCALE_FACTORS,
            "scale_J",          scale_J,
            "shift_THz",        PAB_SHIFT_THZ,
            "shift_J",          shift_J,
            "J_full",           J_full,
            "J_flat",           J_flat,
            "config",           cfg_spec.config,
            "fiber_name",       cfg.fiber_name,
        )
        @info "Saved perturbation data: $perturbation_path"
    end

    # ── Generate figures ──
    @info ""
    @info "Generating figures..."
    res_smf28 = results_all["smf28"]
    res_hnlf  = results_all["hnlf"]

    @info "Figure 10_05: Band zeroing bar chart"
    pab_plot_band_zeroing(res_smf28, res_hnlf)

    @info "Figure 10_06: Cumulative ablation"
    pab_plot_cumulative(res_smf28, res_hnlf)

    @info "Figure 10_07: Scaling robustness"
    pab_plot_scaling(res_smf28, res_hnlf)

    @info "Figure 10_08: Spectral shift sensitivity"
    pab_plot_shift(res_smf28, res_hnlf)

    @info "Figure 10_09: Ablation summary"
    pab_plot_summary(res_smf28, res_hnlf)

    # ── Write findings document ──
    findings_path = joinpath(_PAB_PROJECT_ROOT, "results", "raman", "PHASE10_ABLATION_FINDINGS.md")
    @info "Writing findings document: $findings_path"
    pab_write_findings(res_smf28, res_hnlf, findings_path)

    @info ""
    @info "=" ^ 70
    @info "Phase ablation experiments complete."
    @info "JLD2 files: $(joinpath(PAB_RESULTS_DIR))"
    @info "Figures: $(PAB_FIGURE_DIR)"
    @info "Findings: $findings_path"
    @info "=" ^ 70
end
