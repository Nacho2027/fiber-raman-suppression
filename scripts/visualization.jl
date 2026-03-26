"""
Publication-quality visualization for supercontinuum generation and
nonlinear fiber optics simulations.

Standard plot types following Dudley et al. (2006, Rev. Mod. Phys.):
  1. Spectral evolution: wavelength [nm] vs propagation distance, power [dB] color
  2. Temporal evolution: time [ps] vs propagation distance, power [dB] color
  3. Combined two-panel evolution figure
  4. Spectrogram (STFT): time [ps] vs wavelength [nm], intensity [dB] color
  5. Optimization result comparison (before/after)
  6. Boundary condition diagnostic
  7. Optimization convergence

Cross-run comparison functions (Phase 6):
  - compute_soliton_number: N = sqrt(γ·P₀·T₀²/|β₂|) for sech² pulses
  - decompose_phase_polynomial: GDD/TOD polynomial decomposition of phi_opt
  - plot_cross_run_summary_table: matplotlib table PNG of all run metrics
  - plot_convergence_overlay: J vs iteration overlay for all runs (dB scale)
  - plot_spectral_overlay: optimized output spectra per fiber type

Requires: PyPlot, FFTW, LinearAlgebra, MultiModeNoise (for meshgrid, lin_to_dB, solve_disp_mmf)

Include guard: safe to include multiple times.
"""

if !(@isdefined _VISUALIZATION_JL_LOADED)
const _VISUALIZATION_JL_LOADED = true

using PyPlot
using FFTW
using Statistics
using Printf
using Logging
using LinearAlgebra: norm

# ─────────────────────────────────────────────────────────────────────────────
# 0. Global formatting — publication defaults
# ─────────────────────────────────────────────────────────────────────────────

const _rc = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
_rc["font.size"]          = 10
_rc["axes.labelsize"]     = 12
_rc["axes.titlesize"]     = 13
_rc["xtick.labelsize"]    = 10
_rc["ytick.labelsize"]    = 10
_rc["legend.fontsize"]    = 10
_rc["figure.dpi"]         = 150
_rc["savefig.dpi"]        = 300
_rc["savefig.bbox"]       = "tight"
_rc["axes.grid"]          = true
_rc["grid.alpha"]         = 0.3

# Physical constants
const C_NM_THZ = 299792.458  # speed of light in nm·THz

# Okabe-Ito color scheme for colorblind-safe plots
const COLOR_INPUT  = "#0072B2"  # blue
const COLOR_OUTPUT = "#D55E00"  # vermillion
const COLOR_RAMAN  = "#CC79A7"  # reddish purple
const COLOR_REF    = "#000000"  # black

# 5-run comparison palette (Okabe-Ito extended, colorblind-safe) — per D-03
const COLORS_5_RUNS = [
    "#0072B2",   # blue       — Run 1
    "#E69F00",   # orange     — Run 2
    "#009E73",   # green      — Run 3
    "#CC79A7",   # pink       — Run 4
    "#56B4E9",   # sky blue   — Run 5
]

# ─────────────────────────────────────────────────────────────────────────────
# 1. Phase wrapping utilities
# ─────────────────────────────────────────────────────────────────────────────

"""Wrap phase to [0, 2π] for display."""
wrap_phase(φ) = mod.(φ, 2π)

"""Set π-labeled y-ticks on the given axis for phase plots."""
function set_phase_yticks!(ax)
    ax.set_yticks([0, π/2, π, 3π/2, 2π])
    ax.set_yticklabels(["0", "π/2", "π", "3π/2", "2π"])
    ax.set_ylim(0, 2π)
    ax.set_ylabel("Phase [rad]")
end

# ─────────────────────────────────────────────────────────────────────────────
# 2. Helper: auto length unit and frequency→wavelength
# ─────────────────────────────────────────────────────────────────────────────

"""Select display unit for propagation length."""
function _length_display(zsave, length_unit)
    if length_unit == :auto
        length_unit = maximum(zsave) < 1.0 ? :mm : :m
    end
    z_display = length_unit == :mm ? zsave .* 1e3 : zsave
    z_label = length_unit == :mm ? "Length [mm]" : "Length [m]"
    return z_display, z_label
end

"""
Convert FFT-order frequency grid to fftshifted wavelength in nm.
Returns (λ_nm, sort_idx) where sort_idx sorts λ ascending.
Only includes positive frequencies (λ > 0).
"""
function _freq_to_wavelength(sim)
    f0 = sim["f0"]  # center frequency in THz
    Nt = sim["Nt"]
    Δt = sim["Δt"]
    # Absolute frequencies in fftshifted order
    f_shifted = f0 .+ fftshift(fftfreq(Nt, 1 / Δt))
    # Only keep positive frequencies for wavelength conversion
    pos_mask = f_shifted .> 0
    λ_nm = C_NM_THZ ./ f_shifted[pos_mask]
    # Sort by wavelength (ascending) for proper plotting
    sort_idx = sortperm(λ_nm)
    return λ_nm[sort_idx], pos_mask, sort_idx
end

"""Auto-center time axis around the pulse peak, returning (t_min, t_max) in ps."""
function _auto_time_limits(P_t, ts_ps; padding_factor=3.0)
    peak_idx = argmax(P_t)
    peak_t = ts_ps[peak_idx]
    # Estimate FWHM
    half_max = P_t[peak_idx] / 2
    above = findall(P_t .>= half_max)
    if length(above) > 1
        fwhm = ts_ps[above[end]] - ts_ps[above[1]]
    else
        fwhm = (ts_ps[end] - ts_ps[1]) / 10
    end
    margin = max(fwhm * padding_factor, 0.5)
    return (peak_t - margin, peak_t + margin)
end

"""
Energy-based time window: find the smallest interval containing `energy_fraction`
of total energy. More robust than FWHM for dispersed pulses at long fiber lengths.
"""
function _energy_window(P_t, ts_ps; energy_fraction=0.999, min_padding_ps=0.2)
    E_total = sum(P_t)
    if E_total ≈ 0
        return (ts_ps[1], ts_ps[end])
    end
    E_cum = cumsum(P_t) ./ E_total
    tail = (1 - energy_fraction) / 2
    i_lo = something(findfirst(E_cum .>= tail), 1)
    i_hi = something(findfirst(E_cum .>= 1 - tail), length(ts_ps))
    return (ts_ps[i_lo] - min_padding_ps, ts_ps[i_hi] + min_padding_ps)
end

# ─────────────────────────────────────────────────────────────────────────────
# 2b. Phase analysis: unwrap, group delay, GDD, instantaneous frequency
# ─────────────────────────────────────────────────────────────────────────────

"""
    _manual_unwrap(φ)

Unwrap a 1D phase vector by removing jumps > π between consecutive samples.
"""
function _manual_unwrap(φ)
    out = copy(float.(φ))
    for i in 2:length(out)
        d = out[i] - out[i-1]
        if abs(d) > π
            out[i:end] .-= 2π * round(d / (2π))
        end
    end
    return out
end

"""
    _central_diff(y, dx)

First derivative via central finite differences with forward/backward at boundaries.
"""
function _central_diff(y, dx)
    N = length(y)
    dy = similar(y)
    dy[1] = (y[2] - y[1]) / dx
    dy[N] = (y[N] - y[N-1]) / dx
    for i in 2:N-1
        dy[i] = (y[i+1] - y[i-1]) / (2dx)
    end
    return dy
end

"""
    _second_central_diff(y, dx)

Second derivative via central finite differences. Boundary values set to NaN.
"""
function _second_central_diff(y, dx)
    N = length(y)
    d2y = similar(y)
    d2y[1] = d2y[N] = NaN
    for i in 2:N-1
        d2y[i] = (y[i+1] - 2y[i] + y[i-1]) / dx^2
    end
    return d2y
end

"""
    _spectral_omega_step(sim)

Return the angular frequency step dω [rad/ps] for the fftshifted grid.
"""
function _spectral_omega_step(sim)
    Δf_grid = fftshift(fftfreq(sim["Nt"], 1 / sim["Δt"]))
    return 2π * (Δf_grid[2] - Δf_grid[1])
end

"""
    _apply_dB_mask(data, power_spectrum; threshold_dB=-30)

Return a copy of `data` with NaN where `power_spectrum` is below `threshold_dB`
relative to peak. Works on any 1D arrays of matching length.
"""
function _apply_dB_mask(data, power_spectrum; threshold_dB=-30)
    P_peak = maximum(power_spectrum)
    dB = 10 .* log10.(power_spectrum ./ P_peak .+ 1e-30)
    masked = copy(float.(data))
    masked[dB .≤ threshold_dB] .= NaN
    return masked
end

"""
    _spectral_signal_xlim(P_spec_fftshifted, lambda_nm_fftshifted;
                           threshold_dB=-40.0, padding_nm=80.0)

Compute wavelength xlim containing all spectral content above threshold_dB
relative to peak. Returns (lambda_lo, lambda_hi) in nm.
Both inputs must be co-indexed in fftshifted order.
Negative-frequency ghost wavelengths (λ < 0 from FFT artifacts) are filtered out.
"""
function _spectral_signal_xlim(P_spec_fftshifted, lambda_nm_fftshifted;
                                threshold_dB=-40.0, padding_nm=80.0)
    P_peak = maximum(P_spec_fftshifted)
    dB = 10 .* log10.(P_spec_fftshifted ./ P_peak .+ 1e-30)
    above = findall(dB .> threshold_dB)
    isempty(above) && return (lambda_nm_fftshifted[1], lambda_nm_fftshifted[end])
    lambda_signal = lambda_nm_fftshifted[above]
    # Filter out negative-frequency ghost wavelengths (negative lambda from FFT)
    lambda_pos = filter(>(0), lambda_signal)
    isempty(lambda_pos) && return (lambda_nm_fftshifted[1], lambda_nm_fftshifted[end])
    return (minimum(lambda_pos) - padding_nm, maximum(lambda_pos) + padding_nm)
end

"""
    add_caption!(fig, caption; fontsize=9, y=0.01)

Add a small-text caption to the bottom of the figure.
Useful for annotating figure source, run tag, or brief methodology notes.
"""
function add_caption!(fig, caption; fontsize=9, y=0.01)
    fig.text(0.5, y, caption; ha="center", va="bottom",
             fontsize=fontsize, color="dimgray",
             transform=fig.transFigure)
end

"""
    _add_metadata_block!(fig, metadata; fontsize=8, x=0.01, y=0.01)

Add a metadata annotation block to the bottom-left corner of a figure.
`metadata` is a NamedTuple with fields: fiber_name, L_m, P_cont_W, lambda0_nm, fwhm_fs.
"""
function _add_metadata_block!(fig, metadata; fontsize=8, x=0.01, y=0.01)
    lines = [
        @sprintf("Fiber: %s  L = %.1f m", metadata.fiber_name, metadata.L_m),
        @sprintf("P0 = %.0f mW  lambda0 = %.0f nm  FWHM = %.0f fs",
            metadata.P_cont_W * 1000, metadata.lambda0_nm, metadata.fwhm_fs),
    ]
    fig.text(x, y, join(lines, "\n");
        ha="left", va="bottom", fontsize=fontsize,
        color="dimgray", transform=fig.transFigure,
        bbox=Dict("boxstyle" => "round,pad=0.2", "facecolor" => "white",
                  "alpha" => 0.7, "edgecolor" => "lightgray"))
end

"""
    compute_group_delay(φ_shifted, sim)

Compute group delay τ(ω) = dφ/dω in fs from fftshifted spectral phase.
Δω is in rad/ps, so dφ/dω is in ps; multiply by 1e3 to get fs.
"""
function compute_group_delay(φ_shifted, sim)
    dω = _spectral_omega_step(sim)
    φ_unwrapped = _manual_unwrap(φ_shifted)
    return _central_diff(φ_unwrapped, dω) .* 1e3
end

"""
    compute_gdd(φ, sim)

Compute GDD = d²φ/dω² in fs² from fftshifted spectral phase.
Δω is in rad/ps, so d²φ/dω² is in ps²; multiply by 1e6 to get fs².
"""
function compute_gdd(φ, sim)
    dω = _spectral_omega_step(sim)
    φ_unwrapped = _manual_unwrap(φ)
    return _second_central_diff(φ_unwrapped, dω) .* 1e6
end

"""
    compute_instantaneous_frequency(ut, sim)

Compute instantaneous frequency offset Δf(t) in THz from a complex time-domain
field vector. Extracts temporal phase, unwraps, and differentiates.
dφ/dt in rad/ps divided by 2π gives THz.
"""
function compute_instantaneous_frequency(ut, sim)
    dt_ps = (sim["ts"][2] - sim["ts"][1]) * 1e12
    φ_unwrapped = _manual_unwrap(angle.(ut))
    return _central_diff(φ_unwrapped, dt_ps) ./ (2π)
end

"""
    plot_phase_diagnostic(φ, uω0_base, sim; save_path=nothing)

Standalone 3×2 phase diagnostic figure:
  (1,1): Wrapped spectral phase φ(ω) [0, 2π] with π-ticks
  (1,2): Unwrapped spectral phase φ(ω) [rad]
  (2,1): Group delay τ(ω) [fs]
  (2,2): GDD [fs²] with percentile-clipped y-axis
  (3,1): Instantaneous frequency [THz offset] vs time
  (3,2): (empty)

Phase is masked to -40 dB BEFORE unwrapping (BUG-03 fix). All spectral
quantities are NaN-masked for display where power < -30 dB relative to peak.
Spectral xlim auto-zooms to signal-bearing region (AXIS-02).
"""
function plot_phase_diagnostic(φ, uω0_base, sim; save_path=nothing, metadata=nothing)
    f0 = sim["f0"]
    ts_ps = sim["ts"] .* 1e12
    dω = _spectral_omega_step(sim)

    λ_nm, pos_mask, sort_idx = _freq_to_wavelength(sim)

    # Spectral power for masking (fftshifted, positive-freq, wavelength-sorted)
    spec_pos = abs2.(fftshift(uω0_base[:, 1]))[pos_mask][sort_idx]

    # --- BUG-03 fix: mask phase BEFORE unwrapping ---
    φ_shifted = fftshift(φ[:, 1])
    spec_power_full = abs2.(fftshift(uω0_base[:, 1]))
    P_peak = maximum(spec_power_full)
    dB_full = 10 .* log10.(spec_power_full ./ P_peak .+ 1e-30)
    signal_mask = dB_full .> -40.0  # true where signal is present

    # Zero phase at noise-floor bins before unwrapping
    # Use 0.0, not NaN — _manual_unwrap requires finite input values
    φ_premask = copy(φ_shifted)
    φ_premask[.!signal_mask] .= 0.0

    # Unwrap the pre-masked phase
    φ_unwrapped_full = _manual_unwrap(φ_premask)

    # Extract positive-frequency, wavelength-sorted slices
    φ_unwrapped = φ_unwrapped_full[pos_mask][sort_idx]
    τ_pos = (_central_diff(φ_unwrapped_full, dω) .* 1e3)[pos_mask][sort_idx]
    gdd_pos = (_second_central_diff(φ_unwrapped_full, dω) .* 1e6)[pos_mask][sort_idx]

    # Wrapped phase (computed from original unmasked phase for display fidelity)
    φ_wrapped = wrap_phase(φ_shifted[pos_mask][sort_idx])

    # Instantaneous frequency from shaped temporal field
    ut_shaped = ifft(uω0_base .* cis.(φ), 1)
    Δf_inst = compute_instantaneous_frequency(ut_shaped[:, 1], sim)

    λ_raman_onset = C_NM_THZ / (f0 - 13.2)  # 13.2 THz: silica Raman Stokes shift

    # Apply -30 dB NaN mask for DISPLAY only (after all derivative computations)
    φ_wrapped_display = _apply_dB_mask(φ_wrapped, spec_pos)
    φ_masked = _apply_dB_mask(φ_unwrapped, spec_pos)
    τ_masked = _apply_dB_mask(τ_pos, spec_pos)
    gdd_masked = _apply_dB_mask(gdd_pos, spec_pos)

    # --- AXIS-02: auto-zoom to signal-bearing region ---
    spec_xlim = _spectral_signal_xlim(spec_pos, λ_nm)

    # --- PHASE-02: 3x2 layout with all 5 phase views ---
    fig, axs = subplots(3, 2, figsize=(12, 12))
    λ0_nm = C_NM_THZ / f0

    # Panel (1,1): Wrapped phase with pi-ticks (PHASE-04)
    axs[1, 1].plot(λ_nm, φ_wrapped_display, color=COLOR_REF, linewidth=0.8)
    axs[1, 1].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--", alpha=0.6, label="Raman onset")
    axs[1, 1].set_xlabel("Wavelength [nm]")
    axs[1, 1].set_title("Wrapped phase φ(ω)")
    set_phase_yticks!(axs[1, 1])
    axs[1, 1].set_xlim(spec_xlim...)
    axs[1, 1].legend(fontsize=8)

    # Remaining spectral panels: (row, col, data, ylabel, title)
    spectral_panels = [
        (1, 2, φ_masked,   "Spectral phase [rad]", "Unwrapped spectral phase φ(ω)"),
        (2, 1, τ_masked,   "Group delay [fs]",     "Group delay τ(ω)"),
        (2, 2, gdd_masked, "GDD [fs²]",            "Group delay dispersion"),
    ]
    for (r, c, data, ylabel, title) in spectral_panels
        axs[r, c].plot(λ_nm, data, color=COLOR_REF, linewidth=0.8)
        axs[r, c].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--", alpha=0.6, label="Raman onset")
        axs[r, c].set_xlabel("Wavelength [nm]")
        axs[r, c].set_ylabel(ylabel)
        axs[r, c].set_title(title)
        axs[r, c].set_xlim(spec_xlim...)
        axs[r, c].legend(fontsize=8)
    end

    # --- PHASE-03: GDD percentile clipping ---
    gdd_valid = filter(isfinite, gdd_masked)
    if length(gdd_valid) > 10
        gdd_lo = quantile(gdd_valid, 0.02)
        gdd_hi = quantile(gdd_valid, 0.98)
        # 5% headroom, minimum ±100 fs² to avoid degenerate zero range
        margin = max(abs(gdd_hi - gdd_lo) * 0.05, 100.0)
        axs[2, 2].set_ylim(gdd_lo - margin, gdd_hi + margin)
    end

    # Panel (3,1): Instantaneous frequency (time domain)
    axs[3, 1].plot(ts_ps, Δf_inst, color=COLOR_REF, linewidth=0.8)
    axs[3, 1].set_xlabel("Time [ps]")
    axs[3, 1].set_ylabel("Δf [THz]")
    axs[3, 1].set_title("Instantaneous frequency offset")
    t_lims = _auto_time_limits(abs2.(ut_shaped[:, 1]), ts_ps; padding_factor=4.0)
    axs[3, 1].set_xlim(t_lims...)

    # Panel (3,2): empty — hide
    axs[3, 2].set_visible(false)

    fig.tight_layout()

    if !isnothing(metadata)
        _add_metadata_block!(fig, metadata)
    end

    if !isnothing(save_path)
        savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved phase diagnostic to $save_path"
    end

    return fig, axs
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. Spectral evolution (wavelength domain)
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_spectral_evolution(sol, sim, fiber; kwargs...)

Plot spectral power evolution along fiber length.

Produces the standard wavelength-vs-length density plot (Dudley et al. 2006).
Color scale is normalized dB relative to global peak.
"""
function plot_spectral_evolution(sol, sim, fiber;
    mode_idx=1, dB_range=40.0,
    wavelength_limits=nothing,
    cmap="inferno", figsize=(8, 6),
    length_unit=:auto,
    ax=nothing, fig=nothing)

    uω_z = sol["uω_z"]  # [Nz × Nt × M]
    zsave = collect(fiber["zsave"])
    z_display, z_label = _length_display(zsave, length_unit)

    # Frequency → wavelength
    f0 = sim["f0"]
    Nt = sim["Nt"]
    Δt = sim["Δt"]
    f_shifted = f0 .+ fftshift(fftfreq(Nt, 1 / Δt))

    # Power in fftshifted order: [Nz × Nt]
    P = abs2.(fftshift(uω_z[:, :, mode_idx], 2))
    P_max = maximum(P)
    P_dB = 10 .* log10.(P ./ P_max .+ 1e-30)
    P_dB = clamp.(P_dB, -dB_range, 0)

    # Wavelength array (may contain negative freq → filter)
    λ_nm = C_NM_THZ ./ f_shifted

    # Build meshgrid
    ΛΛ, ZZ = MultiModeNoise.meshgrid(λ_nm, z_display)

    if isnothing(ax)
        fig, ax = subplots(figsize=figsize)
    end
    im = ax.pcolormesh(ΛΛ, ZZ, P_dB, shading="nearest", cmap=cmap,
        vmin=-dB_range, vmax=0)
    ax.grid(false)

    ax.set_xlabel("Wavelength [nm]")
    ax.set_ylabel(z_label)
    ax.set_title("Spectral evolution")

    # Mark pump wavelength and Raman onset
    # Silica Raman Stokes shift is ~13.2 THz (dominant peak at 440 cm^-1)
    f_raman = f0 - 13.2  # THz: Raman Stokes onset frequency
    λ0_nm = C_NM_THZ / f0
    λ_raman_nm = C_NM_THZ / f_raman
    ax.axvline(x=λ0_nm, color="white", ls="--", alpha=0.5, linewidth=0.8, label="Pump λ₀")
    ax.axvline(x=λ_raman_nm, color=COLOR_RAMAN, ls="--", alpha=0.7, linewidth=0.8, label="Raman onset")

    if !isnothing(wavelength_limits)
        ax.set_xlim(wavelength_limits...)
    else
        # AXIS-02: auto-zoom using the z=0 spectrum as signal-content reference.
        # The input spectrum defines the signal extent; propagation may broaden it
        # but the input provides a stable reference that doesn't depend on how much
        # the spectrum has spread (which would over-expand the zoom window).
        P0_spec = abs2.(fftshift(uω_z[1, :, mode_idx], 1))
        spec_xlim_evo = _spectral_signal_xlim(P0_spec, λ_nm)
        ax.set_xlim(spec_xlim_evo...)
    end

    return fig, ax, im
end

# ─────────────────────────────────────────────────────────────────────────────
# 4. Temporal evolution
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_temporal_evolution(sol, sim, fiber; kwargs...)

Plot temporal power evolution along fiber length.
Color scale in dB (default) or linear.
"""
function plot_temporal_evolution(sol, sim, fiber;
    mode_idx=1, dB_range=40.0,
    time_limits=nothing,
    cmap="inferno", figsize=(8, 6),
    length_unit=:auto, scale=:dB,
    ax=nothing, fig=nothing)

    ut_z = sol["ut_z"]  # [Nz × Nt × M]
    zsave = collect(fiber["zsave"])
    ts_ps = sim["ts"] .* 1e12
    z_display, z_label = _length_display(zsave, length_unit)

    P = abs2.(ut_z[:, :, mode_idx])

    if scale == :dB
        P_max = maximum(P)
        P_plot = 10 .* log10.(P ./ P_max .+ 1e-30)
        P_plot = clamp.(P_plot, -dB_range, 0)
        cb_label = "Power [dB]"
        vmin, vmax = -dB_range, 0.0
    else
        P_plot = P
        cb_label = "Power [W]"
        vmin, vmax = 0.0, maximum(P)
    end

    TT, ZZ = MultiModeNoise.meshgrid(ts_ps, z_display)

    if isnothing(ax)
        fig, ax = subplots(figsize=figsize)
    end
    im = ax.pcolormesh(TT, ZZ, P_plot, shading="nearest", cmap=cmap,
        vmin=vmin, vmax=vmax)
    ax.grid(false)

    ax.set_xlabel("Time [ps]")
    ax.set_ylabel(z_label)

    if !isnothing(time_limits)
        ax.set_xlim(time_limits...)
    else
        # Auto-center on pulse at z=0
        P0 = P[1, :]
        t_lims = _auto_time_limits(P0, ts_ps; padding_factor=5.0)
        ax.set_xlim(t_lims...)
    end

    return fig, ax, im
end

# ─────────────────────────────────────────────────────────────────────────────
# 5. Combined two-panel evolution (THE standard figure)
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_combined_evolution(sol, sim, fiber; kwargs...)

Two-panel figure matching the standard supercontinuum evolution visualization.
Top: temporal evolution. Bottom: spectral evolution. Shared colorbar.
"""
function plot_combined_evolution(sol, sim, fiber;
    mode_idx=1, dB_range=40.0,
    time_limits=nothing, wavelength_limits=nothing,
    cmap="inferno", figsize=(8, 10),
    length_unit=:auto, title=nothing)

    fig, axes = subplots(2, 1, figsize=figsize)

    # Top: temporal
    _, ax_t, im_t = plot_temporal_evolution(sol, sim, fiber;
        mode_idx=mode_idx, dB_range=dB_range, time_limits=time_limits,
        cmap=cmap, length_unit=length_unit, ax=axes[1], fig=fig)
    ax_t.set_title("Temporal evolution")

    # Bottom: spectral (note: plot_spectral_evolution now adds Raman/pump markers)
    _, ax_s, im_s = plot_spectral_evolution(sol, sim, fiber;
        mode_idx=mode_idx, dB_range=dB_range, wavelength_limits=wavelength_limits,
        cmap=cmap, length_unit=length_unit, ax=axes[2], fig=fig)
    ax_s.set_title("Spectral evolution")
    ax_s.legend(fontsize=7, loc="upper right")

    # Shared colorbar on the right
    fig.subplots_adjust(right=0.88)
    cbar_ax = fig.add_axes([0.90, 0.15, 0.025, 0.7])
    cb = fig.colorbar(im_s, cax=cbar_ax)
    cb.set_label("Power [dB]")

    if !isnothing(title)
        fig.suptitle(title, fontsize=14, y=0.98)
    end

    # Caption: key nonlinear effects observable in this figure
    # Soliton self-frequency shift (SSFS) appears as spectral red-drift at long propagation
    add_caption!(fig, "Spectral evolution — key effects: soliton self-frequency shift (SSFS), Raman Stokes emission")

    return fig, axes
end

# ─────────────────────────────────────────────────────────────────────────────
# 5b. Merged 2x2 evolution comparison (optimized vs unshaped)
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_merged_evolution(sol_opt, sol_unshaped, sim, fiber;
        dB_range=40.0, cmap="inferno", figsize=(14, 10),
        length_unit=:auto, metadata=nothing, save_path=nothing)

2x2 merged evolution figure: rows = temporal/spectral, columns = optimized/unshaped.
Shared colorbar on the right. Column titles identify which is optimized vs unshaped.
Fiber length displayed in suptitle (META-03). Metadata block if provided (META-01).

Returns (fig, axs) where axs is a 2x2 array.
"""
function plot_merged_evolution(sol_opt, sol_unshaped, sim, fiber;
    dB_range=40.0, cmap="inferno", figsize=(14, 10),
    length_unit=:auto, metadata=nothing, save_path=nothing)

    fig, axs = subplots(2, 2, figsize=figsize)

    # Column 1: Optimized
    _, _, im1 = plot_temporal_evolution(sol_opt, sim, fiber;
        dB_range=dB_range, cmap=cmap, length_unit=length_unit,
        ax=axs[1,1], fig=fig)
    axs[1,1].set_title("Optimized -- temporal")

    _, _, _ = plot_spectral_evolution(sol_opt, sim, fiber;
        dB_range=dB_range, cmap=cmap, length_unit=length_unit,
        ax=axs[2,1], fig=fig)
    axs[2,1].set_title("Optimized -- spectral")
    axs[2,1].legend(fontsize=7, loc="upper right")

    # Column 2: Unshaped
    _, _, _ = plot_temporal_evolution(sol_unshaped, sim, fiber;
        dB_range=dB_range, cmap=cmap, length_unit=length_unit,
        ax=axs[1,2], fig=fig)
    axs[1,2].set_title("Unshaped -- temporal")

    _, _, _ = plot_spectral_evolution(sol_unshaped, sim, fiber;
        dB_range=dB_range, cmap=cmap, length_unit=length_unit,
        ax=axs[2,2], fig=fig)
    axs[2,2].set_title("Unshaped -- spectral")
    axs[2,2].legend(fontsize=7, loc="upper right")

    # Shared colorbar on the right (same pattern as plot_combined_evolution)
    # Do NOT call tight_layout after add_axes — it displaces manually positioned axes (Pitfall 1)
    fig.subplots_adjust(right=0.88, top=0.93, bottom=0.06)
    cbar_ax = fig.add_axes([0.90, 0.15, 0.025, 0.7])
    cb = fig.colorbar(im1, cax=cbar_ax)
    cb.set_label("Power [dB]")

    # META-03: fiber length in suptitle
    L_val = fiber["L"]
    L_str = L_val >= 1.0 ? @sprintf("L = %.1f m", L_val) : @sprintf("L = %.0f cm", L_val * 100)
    fig.suptitle("Evolution comparison -- $L_str", fontsize=13, y=0.98)

    # META-01: metadata annotation block (bottom=0.06 in subplots_adjust reserves space for it)
    if !isnothing(metadata)
        _add_metadata_block!(fig, metadata)
    end

    if !isnothing(save_path)
        savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved merged evolution plot to $save_path"
    end

    return fig, axs
end

# ─────────────────────────────────────────────────────────────────────────────
# 6. Spectrogram (STFT)
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_spectrogram(ut, sim; kwargs...)

Compute and plot spectrogram using short-time Fourier transform.
Gate: Gaussian with specified FWHM.

# Arguments
- `ut`: temporal field vector (length Nt) — single mode, single z-position
- `sim`: simulation parameters dict
- `gate_fwhm_ps`: FWHM of Gaussian gate in ps (default 0.05)
- `domain`: `:wavelength` or `:frequency`
"""
function plot_spectrogram(ut, sim;
    gate_fwhm_ps=0.05, dB_range=40.0,
    domain=:wavelength,
    freq_limits=nothing, time_limits=nothing,
    cmap="inferno", figsize=(8, 6))

    Nt = length(ut)
    ts_ps = sim["ts"] .* 1e12
    dt = ts_ps[2] - ts_ps[1]

    # Gaussian gate
    σ = gate_fwhm_ps / (2 * sqrt(2 * log(2)))
    t_center = (ts_ps[1] + ts_ps[end]) / 2
    gate = exp.(-(ts_ps .- t_center).^2 ./ (2σ^2))

    # STFT: slide gate across time, take FFT at each position
    n_steps = min(Nt, 512)
    step_indices = round.(Int, range(1, Nt, length=n_steps))

    S = zeros(Nt, n_steps)
    for (j, center) in enumerate(step_indices)
        shifted_gate = circshift(gate, center - Nt ÷ 2)
        windowed = ut .* shifted_gate
        S[:, j] = abs2.(fft(windowed))
    end

    S_max = maximum(S)
    S_dB = 10 .* log10.(S ./ S_max .+ 1e-30)
    S_dB = clamp.(S_dB, -dB_range, 0)

    # Time axis
    t_axis = ts_ps[step_indices]

    # Frequency/wavelength axis
    f0 = sim["f0"]
    Δt_sim = sim["Δt"]
    if domain == :wavelength
        f_abs = f0 .+ fftshift(fftfreq(Nt, 1 / Δt_sim))
        y_axis = C_NM_THZ ./ f_abs
        S_plot = fftshift(S_dB, 1)
        y_label = "Wavelength [nm]"
    else
        y_axis = fftshift(fftfreq(Nt, 1 / Δt_sim))
        S_plot = fftshift(S_dB, 1)
        y_label = "Frequency offset [THz]"
    end

    fig, ax = subplots(figsize=figsize)
    im = ax.pcolormesh(t_axis, y_axis, S_plot, shading="nearest", cmap=cmap,
        vmin=-dB_range, vmax=0)
    ax.grid(false)
    fig.colorbar(im, ax=ax, label="Intensity [dB]")
    ax.set_xlabel("Time [ps]")
    ax.set_ylabel(y_label)
    ax.set_title("Spectrogram")

    if !isnothing(time_limits)
        ax.set_xlim(time_limits...)
    end
    if !isnothing(freq_limits)
        ax.set_ylim(freq_limits...)
    elseif domain == :wavelength
        # AXIS-02: auto-zoom using the spectral marginal (sum over time gates).
        # Summing over the time axis collapses the 2D spectrogram to a 1D spectral
        # envelope, which represents the total signal content at each wavelength.
        S_marginal = vec(sum(S, dims=2))  # sum over time gates → spectral marginal (FFT order)
        S_marginal_shifted = fftshift(S_marginal)
        spec_xlim_sg = _spectral_signal_xlim(S_marginal_shifted, y_axis)
        ax.set_ylim(spec_xlim_sg...)
    end

    fig.tight_layout()
    return fig, ax
end

# ─────────────────────────────────────────────────────────────────────────────
# 7. Input/output spectrum comparison (wavelength axis, dB scale)
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_spectrum_comparison(uω_in, uω_out, sim; kwargs...)

Plot input and output spectra on wavelength axis with dB scale.
`uω_in`, `uω_out` are in FFT order, shape (Nt,) or (Nt, M).
"""
function plot_spectrum_comparison(uω_in, uω_out, sim;
    mode_idx=1, dB_range=60.0,
    wavelength_limits=nothing,
    figsize=(8, 4), label_in="Input", label_out="Output",
    band_mask=nothing, raman_threshold=nothing)

    Nt = sim["Nt"]
    f0 = sim["f0"]
    Δt = sim["Δt"]

    # Absolute frequencies (fftshifted)
    f_shifted = f0 .+ fftshift(fftfreq(Nt, 1 / Δt))
    λ_nm = C_NM_THZ ./ f_shifted

    # Power spectral density (fftshifted)
    if ndims(uω_in) == 1
        P_in = abs2.(fftshift(uω_in))
        P_out = abs2.(fftshift(uω_out))
    else
        P_in = abs2.(fftshift(uω_in[:, mode_idx]))
        P_out = abs2.(fftshift(uω_out[:, mode_idx]))
    end

    # Normalize to global peak and convert to dB
    P_ref = max(maximum(P_in), maximum(P_out))
    P_in_dB = 10 .* log10.(P_in ./ P_ref .+ 1e-30)
    P_out_dB = 10 .* log10.(P_out ./ P_ref .+ 1e-30)

    fig, ax = subplots(figsize=figsize)
    ax.plot(λ_nm, P_in_dB, color=COLOR_INPUT, label=label_in, alpha=0.7, linewidth=1.2)
    ax.plot(λ_nm, P_out_dB, color=COLOR_OUTPUT, label=label_out, alpha=0.8, linewidth=1.2)

    # Raman onset marker: axvline at Stokes onset wavelength
    if !isnothing(raman_threshold)
        # Raman Stokes onset wavelength from threshold frequency offset
        f_raman_onset = f0 + raman_threshold  # THz
        λ_raman_onset_nm = C_NM_THZ / f_raman_onset
        ax.axvline(x=λ_raman_onset_nm, color=COLOR_RAMAN, ls="--",
            alpha=0.7, linewidth=1.0, label="Raman onset")
    end

    ax.set_xlabel("Wavelength [nm]")
    ax.set_ylabel("Power [dB]")
    ax.set_ylim(-dB_range, 3)
    ax.legend()
    ax.ticklabel_format(useOffset=false, style="plain", axis="x")

    if !isnothing(wavelength_limits)
        ax.set_xlim(wavelength_limits...)
    else
        # AXIS-02: auto-zoom using the union of input and output spectra.
        # The union ensures both the input peak and any broadened output signal
        # are visible within the display window.
        P_union = max.(P_in, P_out)
        spec_xlim_comp = _spectral_signal_xlim(P_union, λ_nm)
        ax.set_xlim(spec_xlim_comp...)
    end

    fig.tight_layout()
    return fig, ax
end

# ─────────────────────────────────────────────────────────────────────────────
# 8. Optimization result — publication quality (phase optimization)
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_optimization_result_v2(φ_before, φ_after, uω0_base, fiber, sim,
                                 band_mask, Δf, raman_threshold; kwargs...)

Publication-quality 3×2 optimization comparison for spectral phase optimization.
Row 1: Spectra (wavelength axis, dB scale)
Row 2: Temporal pulse shape (auto-centered, peak power annotation)
Row 3: Phase [0, 2π] wrapped with π-ticks
"""
function plot_optimization_result_v2(φ_before, φ_after, uω0_base, fiber, sim,
    band_mask, Δf, raman_threshold;
    figsize=(12, 12), save_path=nothing, metadata=nothing)

    ts_ps = sim["ts"] .* 1e12
    Nt = sim["Nt"]
    f0 = sim["f0"]
    Δt = sim["Δt"]

    # Wavelength grid (fftshifted)
    f_shifted = f0 .+ fftshift(fftfreq(Nt, 1 / Δt))
    λ_nm = C_NM_THZ ./ f_shifted
    λ0_nm = C_NM_THZ / f0

    # Raman onset wavelength
    λ_raman_onset = C_NM_THZ / (f0 + raman_threshold)

    # ── Pass 1: simulate both columns and collect results ──
    # Pre-compute all fields so shared quantities can be derived globally.
    col_data = NamedTuple[]
    for (phi_col, label) in [(φ_before, "Before"), (φ_after, "After")]
        uω0_shaped = @. uω0_base * cis(phi_col)
        fiber_plot = deepcopy(fiber)
        fiber_plot["zsave"] = [0.0, fiber["L"]]
        sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_plot, sim)
        uωf = sol["uω_z"][end, :, :]
        utf = sol["ut_z"][end, :, :]
        ut_in = fft(uω0_shaped, 1)
        push!(col_data, (
            uω0_shaped = uω0_shaped,
            uωf        = uωf,
            utf        = utf,
            ut_in      = ut_in,
            label      = label,
            spec_in    = abs2.(fftshift(uω0_shaped[:, 1])),
            spec_out   = abs2.(fftshift(uωf[:, 1])),
            P_in       = abs2.(ut_in[:, 1]),
            P_out      = abs2.(utf[:, 1]),
            phi_col    = phi_col,
        ))
    end

    # ── Pass 2: compute shared normalization and axis limits from ALL results ──

    # BUG-04: global P_ref — maximum across ALL spectra (both columns, input + output)
    # Without this, each column normalizes to its own peak, hiding the optimization improvement.
    P_ref_global = maximum(
        max(maximum(r.spec_in), maximum(r.spec_out))
        for r in col_data
    )

    # AXIS-01: shared temporal xlim — union of energy windows for all columns
    # If Before and After have different pulse widths, the wider window is used so
    # pulse compression appears as narrowing, not as axis rescaling.
    all_t_lims = [
        let t_in  = _energy_window(r.P_in,  ts_ps),
            t_out = _energy_window(r.P_out, ts_ps)
            (min(t_in[1], t_out[1]), max(t_in[2], t_out[2]))
        end
        for r in col_data
    ]
    t_lo_shared = minimum(t[1] for t in all_t_lims)
    t_hi_shared = maximum(t[2] for t in all_t_lims)

    # AXIS-01: shared temporal ylim — peak power range across all columns
    P_max_shared = maximum(max(maximum(r.P_in), maximum(r.P_out)) for r in col_data)

    # AXIS-02: shared spectral xlim — signal extent from the union of all spectra
    all_specs = vcat([r.spec_in for r in col_data], [r.spec_out for r in col_data])
    spec_union = maximum(hcat(all_specs...), dims=2)[:]
    spec_xlim = _spectral_signal_xlim(spec_union, λ_nm)

    # ── Pass 3: render using shared quantities ──
    fig, axs = subplots(3, 2, figsize=figsize)

    J_values = Float64[]  # track J per column for ΔJ annotation

    for (col, r) in enumerate(col_data)
        # ── Row 1: Spectra (wavelength, dB) ──
        # P_ref_global ensures both columns share the same dB reference — the dB
        # offset between Before and After columns now reflects the true improvement.
        spec_in_dB  = 10 .* log10.(r.spec_in  ./ P_ref_global .+ 1e-30)
        spec_out_dB = 10 .* log10.(r.spec_out ./ P_ref_global .+ 1e-30)

        axs[1, col].plot(λ_nm, spec_out_dB, color=COLOR_OUTPUT, label="Output", alpha=0.8, linewidth=1.0)
        axs[1, col].plot(λ_nm, spec_in_dB, color=COLOR_INPUT, ls="--", label="Input", alpha=0.7, linewidth=1.5)

        # AXIS-02: auto-zoom to signal-bearing region (replaces fixed λ0 ± offset)
        axs[1, col].set_xlim(spec_xlim...)
        axs[1, col].set_ylim(-60, 3)

        # Raman onset line
        axs[1, col].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--",
            alpha=0.7, linewidth=1.0, label="Raman onset")

        axs[1, col].set_xlabel("Wavelength [nm]")
        axs[1, col].set_ylabel("Power [dB]")
        axs[1, col].set_title("$(r.label) optimization")
        axs[1, col].legend(fontsize=8)
        axs[1, col].ticklabel_format(useOffset=false, style="plain", axis="x")

        J_val = sum(abs2.(r.uωf) .* band_mask) / sum(abs2.(r.uωf))
        push!(J_values, J_val)
        axs[1, col].annotate(@sprintf("J = %.4f (%.1f dB)", J_val, MultiModeNoise.lin_to_dB(J_val)),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 2: Temporal pulse shape ──
        axs[2, col].plot(ts_ps, r.P_out, color=COLOR_OUTPUT, label="Output", alpha=0.8, linewidth=1.0)
        axs[2, col].plot(ts_ps, r.P_in, color=COLOR_INPUT, ls="--", label="Input", alpha=0.7, linewidth=1.5)
        axs[2, col].set_xlabel("Time [ps]")
        axs[2, col].set_ylabel("Power [W]")
        axs[2, col].set_title("Temporal pulse shape")
        axs[2, col].legend(fontsize=8)

        # AXIS-01: apply shared xlim and ylim so pulse compression is visible as
        # narrowing rather than as axis rescaling across the two columns.
        axs[2, col].set_xlim(t_lo_shared, t_hi_shared)
        axs[2, col].set_ylim(0, P_max_shared * 1.05)

        # Zoom inset when pulse is very dispersed (full_range / FWHM > 20)
        half_max_out = maximum(r.P_out) / 2
        above_out = findall(r.P_out .>= half_max_out)
        fwhm_out = length(above_out) > 1 ? ts_ps[above_out[end]] - ts_ps[above_out[1]] : 1.0
        full_range = t_hi_shared - t_lo_shared
        if full_range / max(fwhm_out, 0.01) > 20
            inset = axs[2, col].inset_axes([0.55, 0.45, 0.40, 0.48])
            inset.plot(ts_ps, r.P_out, color=COLOR_OUTPUT, linewidth=0.8)
            inset.plot(ts_ps, r.P_in, color=COLOR_INPUT, ls="--", linewidth=0.8, alpha=0.7)
            peak_idx_in = argmax(r.P_in)
            t_peak = ts_ps[peak_idx_in]
            inset.set_xlim(t_peak - 3fwhm_out, t_peak + 3fwhm_out)
            inset.tick_params(labelsize=7)
            inset.set_title("Zoom", fontsize=8)
        end

        peak_in = maximum(r.P_in)
        peak_out = maximum(r.P_out)
        axs[2, col].annotate(@sprintf("Peak in: %.0f W\nPeak out: %.0f W", peak_in, peak_out),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=9,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 3: Group delay τ(ω) [fs] ──
        # Group delay is the most human-readable phase view: it shows
        # how much each wavelength is delayed/advanced in time.
        τ_fs = compute_group_delay(fftshift(r.phi_col[:, 1]), sim)
        spec_power = abs2.(fftshift(r.uω0_shaped[:, 1]))
        τ_display = _apply_dB_mask(τ_fs, spec_power)

        axs[3, col].plot(λ_nm, τ_display, color=COLOR_REF, linewidth=0.8)
        axs[3, col].set_xlabel("Wavelength [nm]")
        axs[3, col].set_ylabel("Group delay [fs]")
        # AXIS-02: auto-zoom spectral xlim (replaces fixed λ0 ± offset)
        axs[3, col].set_xlim(spec_xlim...)
        axs[3, col].set_title("Group delay τ(ω)")
        axs[3, col].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--", alpha=0.5, linewidth=0.8)
        axs[3, col].ticklabel_format(useOffset=false, style="plain", axis="x")
    end

    # META-02: J_before, J_after, and Delta-J annotation on the "After" spectral panel
    if length(J_values) == 2
        J_before_dB = MultiModeNoise.lin_to_dB(J_values[1])
        J_after_dB = MultiModeNoise.lin_to_dB(J_values[2])
        ΔJ_dB = J_after_dB - J_before_dB
        axs[1, 2].annotate(
            @sprintf("J_before = %.1f dB\nJ_after  = %.1f dB\nDelta-J  = %.1f dB", J_before_dB, J_after_dB, -ΔJ_dB),
            xy=(0.05, 0.85), xycoords="axes fraction", va="top", fontsize=9,
            color=ΔJ_dB < 0 ? "darkgreen" : "darkred",
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))
    end

    if !isnothing(metadata)
        _add_metadata_block!(fig, metadata)
    end

    fig.tight_layout()

    if !isnothing(save_path)
        savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved optimization result to $save_path"
    end

    return fig
end

# ─────────────────────────────────────────────────────────────────────────────
# 9. Optimization result — amplitude optimization (4×2 layout)
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_amplitude_result_v2(A_before, A_after, uω0_base, fiber, sim,
                              band_mask, Δf, raman_threshold; kwargs...)

Publication-quality 4×2 optimization comparison for amplitude optimization.
Row 1: Spectra (wavelength, dB)
Row 2: Temporal pulse shape (auto-centered)
Row 3: Amplitude profile A(ω) on wavelength axis
Row 4: (reserved for cost breakdown — shown if cost_breakdown provided)
"""
function plot_amplitude_result_v2(A_before, A_after, uω0_base, fiber, sim,
    band_mask, Δf, raman_threshold;
    figsize=(12, 14), save_path=nothing, metadata=nothing)

    ts_ps = sim["ts"] .* 1e12
    Nt = sim["Nt"]
    f0 = sim["f0"]
    Δt = sim["Δt"]

    f_shifted = f0 .+ fftshift(fftfreq(Nt, 1 / Δt))
    λ_nm = C_NM_THZ ./ f_shifted
    λ0_nm = C_NM_THZ / f0

    # Raman onset wavelength
    λ_raman_onset_amp = C_NM_THZ / (f0 + raman_threshold)

    # ── Pass 1: simulate both columns and collect results ──
    # Pre-compute all fields so shared quantities can be derived globally.
    col_data = NamedTuple[]
    for (A_col, label) in [(A_before, "Before"), (A_after, "After")]
        uω0_shaped = uω0_base .* A_col
        fiber_plot = deepcopy(fiber)
        fiber_plot["zsave"] = [0.0, fiber["L"]]
        sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_plot, sim)
        uωf = sol["uω_z"][end, :, :]
        utf = sol["ut_z"][end, :, :]
        ut_in = fft(uω0_shaped, 1)
        push!(col_data, (
            uω0_shaped = uω0_shaped,
            uωf        = uωf,
            utf        = utf,
            ut_in      = ut_in,
            label      = label,
            spec_in    = abs2.(fftshift(uω0_shaped[:, 1])),
            spec_out   = abs2.(fftshift(uωf[:, 1])),
            P_in       = abs2.(ut_in[:, 1]),
            P_out      = abs2.(utf[:, 1]),
            A_col      = A_col,
        ))
    end

    # ── Pass 2: compute shared normalization and axis limits from ALL results ──

    # BUG-04: global P_ref — maximum across ALL spectra (both columns, input + output)
    P_ref_global = maximum(
        max(maximum(r.spec_in), maximum(r.spec_out))
        for r in col_data
    )

    # AXIS-01: shared temporal xlim — union of energy windows for all columns
    # _energy_window is more robust than _auto_time_limits for dispersed amplitude-shaped pulses.
    all_t_lims = [
        let t_in  = _energy_window(r.P_in,  ts_ps),
            t_out = _energy_window(r.P_out, ts_ps)
            (min(t_in[1], t_out[1]), max(t_in[2], t_out[2]))
        end
        for r in col_data
    ]
    t_lo_shared = minimum(t[1] for t in all_t_lims)
    t_hi_shared = maximum(t[2] for t in all_t_lims)

    # AXIS-01: shared temporal ylim
    P_max_shared = maximum(max(maximum(r.P_in), maximum(r.P_out)) for r in col_data)

    # AXIS-02: shared spectral xlim — signal extent from the union of all spectra
    all_specs = vcat([r.spec_in for r in col_data], [r.spec_out for r in col_data])
    spec_union = maximum(hcat(all_specs...), dims=2)[:]
    spec_xlim = _spectral_signal_xlim(spec_union, λ_nm)

    # ── Pass 3: render using shared quantities ──
    fig, axs = subplots(3, 2, figsize=figsize)

    for (col, r) in enumerate(col_data)
        # ── Row 1: Spectra (wavelength, dB) ──
        # P_ref_global ensures both columns share the same dB reference.
        spec_in_dB  = 10 .* log10.(r.spec_in  ./ P_ref_global .+ 1e-30)
        spec_out_dB = 10 .* log10.(r.spec_out ./ P_ref_global .+ 1e-30)

        axs[1, col].plot(λ_nm, spec_in_dB, color=COLOR_INPUT, label="Input", alpha=0.7, linewidth=1.0)
        axs[1, col].plot(λ_nm, spec_out_dB, color=COLOR_OUTPUT, label="Output", alpha=0.8, linewidth=1.0)

        # Raman onset line
        axs[1, col].axvline(x=λ_raman_onset_amp, color=COLOR_RAMAN, ls="--",
            alpha=0.7, linewidth=1.0, label="Raman onset")

        axs[1, col].set_xlabel("Wavelength [nm]")
        axs[1, col].set_ylabel("Power [dB]")
        axs[1, col].set_title("$(r.label) optimization")
        axs[1, col].legend(fontsize=8)
        # AXIS-02: auto-zoom to signal-bearing region (replaces fixed λ0 ± offset)
        axs[1, col].set_xlim(spec_xlim...)
        axs[1, col].set_ylim(-60, 3)
        axs[1, col].ticklabel_format(useOffset=false, style="plain", axis="x")

        J_val = sum(abs2.(r.uωf) .* band_mask) / sum(abs2.(r.uωf))
        axs[1, col].annotate(@sprintf("J = %.4f (%.1f dB)", J_val, MultiModeNoise.lin_to_dB(J_val)),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 2: Temporal pulse shape ──
        axs[2, col].plot(ts_ps, r.P_in, color=COLOR_INPUT, label="Input", alpha=0.7, linewidth=1.0)
        axs[2, col].plot(ts_ps, r.P_out, color=COLOR_OUTPUT, label="Output", alpha=0.8, linewidth=1.0)
        axs[2, col].set_xlabel("Time [ps]")
        axs[2, col].set_ylabel("Power [W]")
        axs[2, col].set_title("Temporal pulse shape")
        axs[2, col].legend(fontsize=8)

        # AXIS-01: shared xlim and ylim so compression is visible as narrowing,
        # not as axis rescaling. _energy_window used instead of _auto_time_limits
        # for better robustness with amplitude-shaped (potentially dispersed) pulses.
        axs[2, col].set_xlim(t_lo_shared, t_hi_shared)
        axs[2, col].set_ylim(0, P_max_shared * 1.05)

        peak_in = maximum(r.P_in)
        peak_out = maximum(r.P_out)
        axs[2, col].annotate(@sprintf("Peak in: %.1f W\nPeak out: %.1f W", peak_in, peak_out),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=9,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 3: Amplitude profile A(ω) on wavelength axis ──
        A_shifted = fftshift(r.A_col[:, 1])
        axs[3, col].plot(λ_nm, A_shifted, "k-", linewidth=1.2)
        axs[3, col].axhline(y=1.0, color="gray", ls="--", alpha=0.5, label="A = 1")
        axs[3, col].set_xlabel("Wavelength [nm]")
        axs[3, col].set_ylabel("Amplitude A(ω)")
        # AXIS-02: auto-zoom to signal-bearing region (replaces fixed λ0 ± offset)
        axs[3, col].set_xlim(spec_xlim...)
        axs[3, col].legend(fontsize=8)
        axs[3, col].set_title("Amplitude profile")
        axs[3, col].ticklabel_format(useOffset=false, style="plain", axis="x")

        A_min, A_max = extrema(r.A_col[:, 1])
        axs[3, col].annotate(@sprintf("A ∈ [%.3f, %.3f]", A_min, A_max),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # Box constraint check: amplitude must stay in [0, 1]
        # Mark INVALID if box constraints violated (amplitude < 0 or > 1)
        if A_min < -1e-6 || A_max > 1.0 + 1e-6
            # INVALID watermark: box constraints violated
            for row in 1:3
                axs[row, col].text(0.5, 0.5, "INVALID",
                    transform=axs[row, col].transAxes,
                    fontsize=18, color="red", alpha=0.4,
                    ha="center", va="center", rotation=30,
                    fontweight="bold",
                    bbox=Dict("boxstyle" => "round", "facecolor" => "white", "alpha" => 0.2))
            end
            @warn "plot_amplitude_result_v2: column $col has box constraints violated (A ∈ [$A_min, $A_max])"
        end
    end

    # META-02: J before/after summary on the After spectral panel
    if length(col_data) == 2
        J_before_val = sum(abs2.(col_data[1].uωf) .* band_mask) / sum(abs2.(col_data[1].uωf))
        J_after_val = sum(abs2.(col_data[2].uωf) .* band_mask) / sum(abs2.(col_data[2].uωf))
        J_before_dB = MultiModeNoise.lin_to_dB(J_before_val)
        J_after_dB = MultiModeNoise.lin_to_dB(J_after_val)
        ΔJ_dB = J_after_dB - J_before_dB
        axs[1, 2].annotate(
            @sprintf("J_before = %.1f dB\nJ_after  = %.1f dB\nDelta-J  = %.1f dB", J_before_dB, J_after_dB, -ΔJ_dB),
            xy=(0.05, 0.85), xycoords="axes fraction", va="top", fontsize=9,
            color=ΔJ_dB < 0 ? "darkgreen" : "darkred",
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))
    end

    if !isnothing(metadata)
        _add_metadata_block!(fig, metadata)
    end

    fig.tight_layout()

    if !isnothing(save_path)
        savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved amplitude result to $save_path"
    end

    return fig
end

# ─────────────────────────────────────────────────────────────────────────────
# 10. Boundary condition diagnostic
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_boundary_diagnostic(sol, sim, fiber; mode_idx=1, edge_fraction=0.05)

Plot temporal field at output showing window edges.
Red zones indicate potential boundary corruption.
Green = OK (<1e-6), Yellow = warning (<1e-3), Red = danger (>1e-3).
"""
function plot_boundary_diagnostic(sol, sim, fiber; mode_idx=1, edge_fraction=0.05)
    ut_end = sol["ut_z"][end, :, mode_idx]
    ts_ps = sim["ts"] .* 1e12
    Nt = sim["Nt"]

    P = abs2.(ut_end)
    P_norm = P ./ maximum(P)

    n_edge = max(1, round(Int, Nt * edge_fraction))

    fig, ax = subplots(figsize=(10, 4))

    # Edge zone markers: fill_between to highlight dangerous edge regions
    ax.fill_betweenx([1e-30, 10.0], ts_ps[1], ts_ps[n_edge],
        alpha=0.2, color="red", label="Edge zone")
    ax.fill_betweenx([1e-30, 10.0], ts_ps[end-n_edge+1], ts_ps[end],
        alpha=0.2, color="red")

    # Power profile
    ax.semilogy(ts_ps, P_norm .+ 1e-30, "b-", linewidth=1.0)
    ax.set_xlabel("Time [ps]")
    ax.set_ylabel("Normalized power")
    ax.set_title("Boundary condition diagnostic (output, z = $(fiber["L"]) m)")

    # Energy fraction in edges
    E_total = sum(P)
    E_left = sum(P[1:n_edge])
    E_right = sum(P[end-n_edge+1:end])
    edge_frac = (E_left + E_right) / E_total

    if edge_frac < 1e-6
        status = "OK"
        color = "green"
    elseif edge_frac < 1e-3
        status = "WARNING"
        color = "orange"
    else
        status = "DANGER"
        color = "red"
    end

    ax.annotate(@sprintf("Edge energy: %.2e (%s)", edge_frac, status),
        xy=(0.02, 0.95), xycoords="axes fraction", va="top", fontsize=11,
        color=color, fontweight="bold",
        bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.9))

    ax.set_ylim(1e-15, 10)
    ax.legend()
    fig.tight_layout()
    return fig, ax
end

# ─────────────────────────────────────────────────────────────────────────────
# 11. Optimization convergence plot
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_convergence(costs; components=nothing, figsize=(8, 4))

Plot cost J vs iteration on log scale.
If `components` is a Dict of name => Vector, show component breakdown.
"""
function plot_convergence(costs; components=nothing, figsize=(8, 4))
    fig, ax = subplots(figsize=figsize)

    iters = 1:length(costs)
    ax.semilogy(iters, costs, "k-o", markersize=4, linewidth=1.5, label="J total")

    if !isnothing(components)
        colors = ["tab:blue", "tab:orange", "tab:green", "tab:red", "tab:purple"]
        for (i, (name, vals)) in enumerate(components)
            c = colors[mod1(i, length(colors))]
            ax.semilogy(1:length(vals), vals, "--", color=c, linewidth=1.0,
                label=name, alpha=0.8)
        end
    end

    ax.set_xlabel("Iteration")
    ax.set_ylabel("Cost J")
    ax.set_title("Optimization convergence")
    ax.legend()
    fig.tight_layout()
    return fig, ax
end

# ─────────────────────────────────────────────────────────────────────────────
# 12. Helper: run evolution propagation and plot
# ─────────────────────────────────────────────────────────────────────────────

"""
    propagate_and_plot_evolution(uω0_shaped, fiber, sim;
        n_zsave=101, title=nothing, save_path=nothing, kwargs...)

Forward-propagate with fine z-sampling and generate the combined evolution plot.
"""
function propagate_and_plot_evolution(uω0_shaped, fiber, sim;
    n_zsave=101, title=nothing, save_path=nothing, kwargs...)

    fiber_evo = deepcopy(fiber)
    fiber_evo["zsave"] = collect(LinRange(0, fiber["L"], n_zsave))
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_evo, sim)

    fig, axes = plot_combined_evolution(sol, sim, fiber_evo;
        title=title, kwargs...)

    if !isnothing(save_path)
        savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved evolution plot to $save_path"
    end

    return sol, fig, axes
end


# ─────────────────────────────────────────────────────────────────────────────
# 13. Cross-run comparison: soliton number, phase decomposition, summary table
# ─────────────────────────────────────────────────────────────────────────────

"""
    compute_soliton_number(gamma_Wm, P0_W, fwhm_fs, beta2_s2m) -> Float64

Compute the soliton number N for a pulse propagating in a fiber.

Formula: N = sqrt(γ · P₀ · T₀² / |β₂|)
where T₀ = FWHM / (2 · acosh(√2)) for sech² pulse assumption.
acosh(√2) ≈ 0.8814 — standard result for sech² FWHM-to-T₀ conversion.

# Arguments
- `gamma_Wm`:   Float64, nonlinear coefficient [W⁻¹ m⁻¹]
- `P0_W`:       Float64, peak power [W]
- `fwhm_fs`:    Float64, pulse FWHM [fs] — converted to seconds internally via × 1e-15
- `beta2_s2m`:  Float64, group-velocity dispersion β₂ [s²/m]

# Returns
Float64 soliton number N ≥ 0 (NaN-safe via max(N_sq, 0.0) before sqrt).

# Reference
Agrawal, "Nonlinear Fiber Optics", Chapter 5.
"""
function compute_soliton_number(gamma_Wm, P0_W, fwhm_fs, beta2_s2m)
    # T0 = FWHM / (2 * acosh(sqrt(2))) for sech^2 pulse
    # acosh(sqrt(2)) ≈ 0.8814
    T0_s = (fwhm_fs * 1e-15) / (2.0 * acosh(sqrt(2.0)))
    N_sq = gamma_Wm * P0_W * T0_s^2 / abs(beta2_s2m)
    return sqrt(max(N_sq, 0.0))
end

"""
    decompose_phase_polynomial(phi_opt, uomega0, sim_Dt, Nt) -> NamedTuple

Decompose an optimized spectral phase profile onto a GDD/TOD polynomial basis
in the signal-bearing spectral region, and report the residual fraction.

GDD (group delay dispersion) = d²φ/dω² [fs²] quantifies quadratic chirp.
TOD (third-order dispersion) = d³φ/dω³ [fs³] quantifies cubic chirp.
A small residual_fraction (<0.2) indicates the optimizer found a physically
interpretable polynomial chirp. A large residual suggests non-polynomial
phase structure worth investigating.

Algorithm:
1. Build signal-band mask at -40 dB spectral power threshold (matches BUG-03 convention).
2. Remove global offset and linear group-delay term (CRITICAL: L-BFGS finds the
   nearest minimum from zero-phase init, so different runs may differ by a constant
   or linear term even if the physics is the same).
3. Fit 2nd+3rd order polynomial (GDD/TOD basis) to detrended phase via least-squares.
4. Convert coefficients to fs² / fs³ and compute residual fraction.

# Arguments
- `phi_opt`:  Matrix{Float64} of shape (Nt, M) — optimal phase; uses mode 1 ([:, 1])
- `uomega0`:  Matrix{ComplexF64} of shape (Nt, M) — input field; used for signal mask
- `sim_Dt`:   Float64 — simulation time step Δt [s] (= sim["Δt"] × 1e-12)
- `Nt`:       Int — number of frequency grid points

# Returns
NamedTuple with fields:
- `gdd_fs2`:           Float64, GDD coefficient [fs²]
- `tod_fs3`:           Float64, TOD coefficient [fs³]
- `residual_fraction`: Float64, norm(residual) / norm(detrended_phase) ∈ [0, 1]
"""
function decompose_phase_polynomial(phi_opt, uomega0, sim_Dt, Nt)
    # --- Step 1: Build signal-band mask at -40 dB threshold ---
    spec_power = abs2.(fftshift(uomega0[:, 1]))
    P_peak = maximum(spec_power)
    dB = 10.0 .* log10.(spec_power ./ P_peak .+ 1e-30)
    signal_mask = dB .> -40.0

    # --- Step 2: Angular frequency grid (fftshifted), in rad/s ---
    # sim_Dt is Δt in seconds; fftfreq returns cycles/s → multiply by 2π for rad/s
    ω_shifted = 2π .* fftshift(fftfreq(Nt, 1.0 / sim_Dt))  # rad/s

    # --- Step 3: Extract signal-band phase ---
    phi_shifted = fftshift(phi_opt[:, 1])
    phi_signal  = phi_shifted[signal_mask]
    ω_signal    = ω_shifted[signal_mask]

    # --- Step 4: Remove global offset and linear group-delay term ---
    # Fit phi ≈ a0 + a1·ω (constant + group delay), then subtract
    A_linear      = hcat(ones(length(ω_signal)), ω_signal)
    coeffs_linear = A_linear \ phi_signal
    phi_detrended = phi_signal .- (coeffs_linear[1] .+ coeffs_linear[2] .* ω_signal)

    # --- Step 5: Fit 2nd+3rd order polynomial to detrended phase ---
    # phi_detrended ≈ β₂_eff · ω²/2 + β₃_eff · ω³/6
    # where β₂_eff = GDD [rad·s²] and β₃_eff = TOD [rad·s³]
    A_poly      = hcat(ω_signal.^2 ./ 2.0, ω_signal.^3 ./ 6.0)
    coeffs_poly = A_poly \ phi_detrended

    # --- Step 6: Convert to physical units ---
    # GDD: rad·s² → fs²:  1 s² = 1e30 fs²
    # TOD: rad·s³ → fs³:  1 s³ = 1e45 fs³
    gdd_fs2 = coeffs_poly[1] * 1e30
    tod_fs3 = coeffs_poly[2] * 1e45

    # --- Step 7: Residual fraction ---
    phi_poly_fit       = A_poly * coeffs_poly
    residual_fraction  = norm(phi_detrended .- phi_poly_fit) / (norm(phi_detrended) + 1e-30)

    return (gdd_fs2=gdd_fs2, tod_fs3=tod_fs3, residual_fraction=residual_fraction)
end

"""
    plot_cross_run_summary_table(runs; save_path=nothing) -> (fig, ax)

Render a presentation-ready PNG summary table of cross-run optimization results
via matplotlib `ax.table()`.

Columns: Fiber | L (m) | P (W) | J_before (dB) | J_after (dB) | ΔdB | Iter. | Time (s) | N

Each row corresponds to one optimization run. `runs` must be a Vector of Dicts
where each Dict contains the JLD2 fields plus `soliton_number_N` (pre-computed
by the caller via `compute_soliton_number`).

A footnote below the table warns that J values are not directly comparable across
runs with different grids (heterogeneous Nt / time_window — see Research Pitfall 2).

# Arguments
- `runs`:       Vector{Dict} — each Dict has keys from the JLD2 result file
                plus `soliton_number_N` (Float64)
- `save_path`:  String or nothing — if provided, saves to this path at 300 DPI

# Returns
`(fig, ax)` tuple (matplotlib figure and axes objects).
"""
function plot_cross_run_summary_table(runs; save_path=nothing)
    # --- Column headers ---
    columns = ["Fiber", "L (m)", "P (W)", "J_before (dB)", "J_after (dB)",
               "ΔdB", "Iter.", "Time (s)", "N"]

    # --- Build cell text from each run ---
    cell_text = Vector{Vector{String}}()
    for run in runs
        J_before_dB = 10.0 * log10(max(run["J_before"], 1e-30))
        J_after_dB  = 10.0 * log10(max(run["J_after"],  1e-30))
        row = [
            string(run["fiber_name"]),
            @sprintf("%.1f",  run["L_m"]),
            @sprintf("%.2f",  run["P_cont_W"]),
            @sprintf("%.1f",  J_before_dB),
            @sprintf("%.1f",  J_after_dB),
            @sprintf("%.1f",  run["delta_J_dB"]),
            string(run["iterations"]),
            @sprintf("%.1f",  run["wall_time_s"]),
            @sprintf("%.2f",  run["soliton_number_N"]),
        ]
        push!(cell_text, row)
    end

    # --- Create figure ---
    fig, ax = subplots(figsize=(14, 3))
    ax.axis("off")

    # --- Render table ---
    table = ax.table(cellText=cell_text, colLabels=columns,
                     loc="center", cellLoc="center")
    table.auto_set_font_size(false)
    table.set_fontsize(10)
    table.scale(1, 1.8)

    # --- Title and footnote ---
    fig.suptitle("Cross-Run Optimization Summary", fontsize=14,
                 fontweight="bold", y=0.95)
    fig.text(0.5, 0.02,
        "Note: J values use run-specific band masks (Nt/time_window vary across runs).",
        ha="center", fontsize=8, style="italic")

    # --- Save ---
    if !isnothing(save_path)
        fig.savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved summary table to $save_path"
    end

    return (fig, ax)
end

# ─────────────────────────────────────────────────────────────────────────────
# 14. Cross-run comparison: convergence overlay and spectral overlay
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_convergence_overlay(runs; save_path=nothing) -> (fig, ax)

Overlay J vs iteration for all optimization runs on a single figure.

Converts the stored linear J convergence history to dB for readability.
Each run is plotted with a distinct color from `COLORS_5_RUNS` (Okabe-Ito
extended palette, colorblind-safe). Labels show fiber type, length, and power
so the figure is self-contained for presentation.

# Arguments
- `runs`:      Vector{Dict} — each Dict must contain:
                 `convergence_history` (Vector{Float64}, linear J values),
                 `fiber_name`, `L_m`, `P_cont_W`
- `save_path`: String or nothing — if provided, saves to this path at 300 DPI

# Returns
`(fig, ax)` tuple.
"""
function plot_convergence_overlay(runs; save_path=nothing)
    fig, ax = subplots(figsize=(8, 5))

    for (i, run) in enumerate(runs)
        # Convergence history is already in dB — optimize_spectral_phase
        # returns lin_to_dB(J) to Optim.jl, so f_trace stores dB values
        J_dB  = run["convergence_history"]
        iters = 0:length(J_dB)-1
        label = "$(run["fiber_name"]) L=$(run["L_m"])m P=$(run["P_cont_W"])W"
        color = COLORS_5_RUNS[mod1(i, length(COLORS_5_RUNS))]
        ax.plot(iters, J_dB, color=color, label=label, lw=1.5)
    end

    ax.set_xlabel("Iteration")
    ax.set_ylabel("Raman band fraction J [dB]")
    ax.set_title("Convergence: All Optimization Runs")
    ax.legend(loc="best", fontsize=9)

    if !isnothing(save_path)
        fig.savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved convergence overlay to $save_path"
    end

    return (fig, ax)
end

"""
    plot_spectral_overlay(runs_fiber_group, fiber_type_label; save_path=nothing) -> (fig, ax)

Overlay optimized OUTPUT spectra for runs of the same fiber type on shared dB axes.

Each run's shaped input field is re-propagated through the reconstructed fiber to
obtain the optimized output spectrum. Spectra are normalized in dB relative to
their own peak (enabling cross-run shape comparison on a shared scale).

Each run uses its native frequency grid — no interpolation to a common grid.
The shared x-axis limits are set from the first run's signal extent (via
`_spectral_signal_xlim`) expanded by 50 nm on each side for context.

# Arguments
- `runs_fiber_group`: Vector{Dict} for runs of ONE fiber type (e.g., all SMF-28
                      or all HNLF). Each Dict contains JLD2 fields:
                      `uomega0`, `phi_opt`, `L_m`, `P_cont_W`, `gamma`, `betas`,
                      `Nt`, `time_window_ps`, `lambda0_nm`, `delta_J_dB`, plus
                      `sim_Dt` and `sim_omega0`.
- `fiber_type_label`: String for the figure title (e.g., "SMF-28" or "HNLF")
- `save_path`:        String or nothing — if provided, saves to this path at 300 DPI

# Returns
`(fig, ax)` tuple.
"""
function plot_spectral_overlay(runs_fiber_group, fiber_type_label; save_path=nothing)
    fig, ax = subplots(figsize=(10, 6))

    xlim_min = nothing
    xlim_max = nothing

    for (i, run) in enumerate(runs_fiber_group)
        Nt           = run["Nt"]
        time_win_ps  = run["time_window_ps"]
        lambda0_nm   = run["lambda0_nm"]
        lambda0_m    = lambda0_nm * 1e-9
        gamma        = run["gamma"]
        betas        = run["betas"]
        L_m          = run["L_m"]

        # --- Reconstruct sim and fiber from JLD2 scalars ---
        # beta_order=3 per Phase 4 decision; M=1 for SMF
        sim_r = MultiModeNoise.get_disp_sim_params(lambda0_m, 1, Nt, time_win_ps, 3)

        # Fallback for empty betas (Pitfall 5): use fiber-name-specific defaults
        betas_use = if isempty(betas)
            run["fiber_name"] == "SMF-28" ? [-2.17e-26, 1.2e-40] : [-0.5e-26, 1.0e-40]
        else
            betas
        end

        fiber_r = MultiModeNoise.get_disp_fiber_params_user_defined(
            L_m, sim_r; gamma_user=gamma, betas_user=betas_use)
        fiber_r["zsave"] = [0.0, L_m]

        # --- Apply optimal phase and propagate ---
        uomega0_shaped = @. run["uomega0"] * cis(run["phi_opt"])
        sol = MultiModeNoise.solve_disp_mmf(uomega0_shaped, fiber_r, sim_r)
        uomega_out = sol["uω_z"][end, :, :]

        # --- Compute output power spectrum (fftshifted) ---
        spec_out = abs2.(fftshift(uomega_out[:, 1]))

        # --- Wavelength grid for this run ---
        # sim_r["f0"] is center frequency in THz; sim_r["Δt"] is time step in ps
        f0_THz    = sim_r["f0"]
        Dt_ps     = sim_r["Δt"]
        f_shifted = f0_THz .+ fftshift(fftfreq(Nt, 1.0 / Dt_ps))  # THz
        lambda_nm = C_NM_THZ ./ f_shifted                           # nm

        # --- dB spectrum normalized to peak ---
        dB = 10.0 .* log10.(spec_out ./ maximum(spec_out) .+ 1e-30)

        # --- Determine shared x-limits from first run ---
        if i == 1
            # Use existing helper; pass fftshifted spectrum and wavelength grid
            (lmin, lmax) = _spectral_signal_xlim(spec_out, lambda_nm; threshold_dB=-40.0)
            xlim_min = lmin - 50.0
            xlim_max = lmax + 50.0
        end

        label = "L=$(L_m)m P=$(run["P_cont_W"])W ($(round(run["delta_J_dB"], digits=1)) dB)"
        color = COLORS_5_RUNS[mod1(i, length(COLORS_5_RUNS))]
        ax.plot(lambda_nm, dB, color=color, label=label, lw=1.2)
    end

    # --- Axis formatting ---
    if !isnothing(xlim_min) && !isnothing(xlim_max)
        ax.set_xlim(xlim_min, xlim_max)
    end
    ax.set_ylim(-60, 5)
    ax.set_xlabel("Wavelength [nm]")
    ax.set_ylabel("Spectral power [dB]")
    ax.set_title("Optimized Output Spectra: $fiber_type_label")
    ax.legend(loc="best", fontsize=9)

    if !isnothing(save_path)
        fig.savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved spectral overlay to $save_path"
    end

    return (fig, ax)
end

end # include guard (_VISUALIZATION_JL_LOADED)
