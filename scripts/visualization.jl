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

Requires: PyPlot, FFTW, MultiModeNoise (for meshgrid, lin_to_dB, solve_disp_mmf)

Include guard: safe to include multiple times.
"""

if !(@isdefined _VISUALIZATION_JL_LOADED)
const _VISUALIZATION_JL_LOADED = true

using PyPlot
using FFTW
using Statistics
using Printf
using Logging

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

Standalone 2×2 phase diagnostic figure:
  (1,1): Unwrapped spectral phase φ(ω) [rad] vs wavelength
  (1,2): Group delay τ(ω) [fs] vs wavelength
  (2,1): GDD [fs²] vs wavelength
  (2,2): Instantaneous frequency [THz offset] vs time

All spectral quantities are masked where power < -30 dB relative to peak.
"""
function plot_phase_diagnostic(φ, uω0_base, sim; save_path=nothing)
    f0 = sim["f0"]
    ts_ps = sim["ts"] .* 1e12
    dω = _spectral_omega_step(sim)

    λ_nm, pos_mask, sort_idx = _freq_to_wavelength(sim)

    # Spectral power for masking (fftshifted, positive-freq, wavelength-sorted)
    spec_pos = abs2.(fftshift(uω0_base[:, 1]))[pos_mask][sort_idx]

    # Unwrap once on the full fftshifted grid, then derive group delay and GDD
    φ_shifted = fftshift(φ[:, 1])
    φ_unwrapped_full = _manual_unwrap(φ_shifted)

    φ_unwrapped = φ_unwrapped_full[pos_mask][sort_idx]
    τ_pos = (_central_diff(φ_unwrapped_full, dω) .* 1e3)[pos_mask][sort_idx]
    gdd_pos = (_second_central_diff(φ_unwrapped_full, dω) .* 1e6)[pos_mask][sort_idx]

    # Instantaneous frequency from shaped temporal field
    ut_shaped = ifft(uω0_base .* cis.(φ), 1)
    Δf_inst = compute_instantaneous_frequency(ut_shaped[:, 1], sim)

    λ_raman_onset = C_NM_THZ / (f0 - 13.2)  # 13.2 THz: silica Raman Stokes shift

    # Apply -30dB mask to spectral quantities
    φ_masked = _apply_dB_mask(φ_unwrapped, spec_pos)
    τ_masked = _apply_dB_mask(τ_pos, spec_pos)
    gdd_masked = _apply_dB_mask(gdd_pos, spec_pos)

    fig, axs = subplots(2, 2, figsize=(12, 9))
    λ0_nm = C_NM_THZ / f0

    # Spectral panel config: (row, col, data, ylabel, title)
    spectral_panels = [
        (1, 1, φ_masked,   "Spectral phase [rad]", "Unwrapped spectral phase φ(ω)"),
        (1, 2, τ_masked,   "Group delay [fs]",     "Group delay τ(ω)"),
        (2, 1, gdd_masked, "GDD [fs²]",            "Group delay dispersion"),
    ]
    for (r, c, data, ylabel, title) in spectral_panels
        axs[r, c].plot(λ_nm, data, color=COLOR_REF, linewidth=0.8)
        axs[r, c].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--", alpha=0.6, label="Raman onset")
        axs[r, c].set_xlabel("Wavelength [nm]")
        axs[r, c].set_ylabel(ylabel)
        axs[r, c].set_title(title)
        axs[r, c].set_xlim(λ0_nm - 300, λ0_nm + 500)
        axs[r, c].legend(fontsize=8)
    end

    axs[2, 2].plot(ts_ps, Δf_inst, color=COLOR_REF, linewidth=0.8)
    axs[2, 2].set_xlabel("Time [ps]")
    axs[2, 2].set_ylabel("Δf [THz]")
    axs[2, 2].set_title("Instantaneous frequency offset")
    t_lims = _auto_time_limits(abs2.(ut_shaped[:, 1]), ts_ps; padding_factor=4.0)
    axs[2, 2].set_xlim(t_lims...)

    fig.tight_layout()

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
        # Default: center ± sensible range based on center wavelength
        ax.set_xlim(λ0_nm - 400, λ0_nm + 700)
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
        λ0_nm = C_NM_THZ / f0
        ax.set_ylim(λ0_nm - 400, λ0_nm + 700)
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
        λ0_nm = C_NM_THZ / f0
        ax.set_xlim(λ0_nm - 400, λ0_nm + 700)
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
    figsize=(12, 12), save_path=nothing)

    ts_ps = sim["ts"] .* 1e12
    Nt = sim["Nt"]
    f0 = sim["f0"]
    Δt = sim["Δt"]

    # Wavelength grid (fftshifted)
    f_shifted = f0 .+ fftshift(fftfreq(Nt, 1 / Δt))
    λ_nm = C_NM_THZ ./ f_shifted
    λ0_nm = C_NM_THZ / f0

    # Raman band in wavelength
    Δf_shifted = fftshift(fftfreq(Nt, 1 / Δt))
    raman_half_bw_thz = 2.5  # ±2.5 THz window around gain peak (~10 THz FWHM silica Raman)
    raman_λ_idx = abs.(Δf_shifted .- raman_threshold) .< raman_half_bw_thz

    fig, axs = subplots(3, 2, figsize=figsize)

    J_values = Float64[]  # track J per column for ΔJ annotation

    for (col, (φ, label)) in enumerate([(φ_before, "Before"), (φ_after, "After")])
        uω0_shaped = @. uω0_base * cis(φ)

        fiber_plot = deepcopy(fiber)
        fiber_plot["zsave"] = [0.0, fiber["L"]]
        sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_plot, sim)
        uωf = sol["uω_z"][end, :, :]
        utf = sol["ut_z"][end, :, :]
        ut_in = fft(uω0_shaped, 1)

        # ── Row 1: Spectra (wavelength, dB) ──
        spec_out = abs2.(fftshift(uωf[:, 1]))
        spec_in = abs2.(fftshift(uω0_shaped[:, 1]))
        P_ref = max(maximum(spec_in), maximum(spec_out))
        spec_in_dB = 10 .* log10.(spec_in ./ P_ref .+ 1e-30)
        spec_out_dB = 10 .* log10.(spec_out ./ P_ref .+ 1e-30)

        axs[1, col].plot(λ_nm, spec_out_dB, color=COLOR_OUTPUT, label="Output", alpha=0.8, linewidth=1.0)
        axs[1, col].plot(λ_nm, spec_in_dB, color=COLOR_INPUT, ls="--", label="Input", alpha=0.7, linewidth=1.5)

        # Set xlim before adding line markers for correct clipping
        axs[1, col].set_xlim(λ0_nm - 300, λ0_nm + 500)
        axs[1, col].set_ylim(-60, 3)

        # Raman onset line: axvline at Stokes onset wavelength
        λ_raman_onset = C_NM_THZ / (f0 + raman_threshold)
        axs[1, col].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--",
            alpha=0.7, linewidth=1.0, label="Raman onset")

        axs[1, col].set_xlabel("Wavelength [nm]")
        axs[1, col].set_ylabel("Power [dB]")
        axs[1, col].set_title("$label optimization")
        axs[1, col].legend(fontsize=8)
        axs[1, col].ticklabel_format(useOffset=false, style="plain", axis="x")

        J_val = sum(abs2.(uωf) .* band_mask) / sum(abs2.(uωf))
        push!(J_values, J_val)
        axs[1, col].annotate(@sprintf("J = %.4f (%.1f dB)", J_val, MultiModeNoise.lin_to_dB(J_val)),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 2: Temporal pulse shape ──
        P_in = abs2.(ut_in[:, 1])
        P_out = abs2.(utf[:, 1])

        axs[2, col].plot(ts_ps, P_out, color=COLOR_OUTPUT, label="Output", alpha=0.8, linewidth=1.0)
        axs[2, col].plot(ts_ps, P_in, color=COLOR_INPUT, ls="--", label="Input", alpha=0.7, linewidth=1.5)
        axs[2, col].set_xlabel("Time [ps]")
        axs[2, col].set_ylabel("Power [W]")
        axs[2, col].set_title("Temporal pulse shape")
        axs[2, col].legend(fontsize=8)

        # Energy-window auto-ranging (robust for dispersed pulses at long L)
        t_lims_in = _energy_window(P_in, ts_ps)
        t_lims_out = _energy_window(P_out, ts_ps)
        t_lims = (min(t_lims_in[1], t_lims_out[1]), max(t_lims_in[2], t_lims_out[2]))
        axs[2, col].set_xlim(t_lims...)

        # Zoom inset when pulse is very dispersed (full_range / FWHM > 20)
        half_max_out = maximum(P_out) / 2
        above_out = findall(P_out .>= half_max_out)
        fwhm_out = length(above_out) > 1 ? ts_ps[above_out[end]] - ts_ps[above_out[1]] : 1.0
        full_range = t_lims[2] - t_lims[1]
        if full_range / max(fwhm_out, 0.01) > 20
            inset = axs[2, col].inset_axes([0.55, 0.45, 0.40, 0.48])
            inset.plot(ts_ps, P_out, color=COLOR_OUTPUT, linewidth=0.8)
            inset.plot(ts_ps, P_in, color=COLOR_INPUT, ls="--", linewidth=0.8, alpha=0.7)
            peak_idx_in = argmax(P_in)
            t_peak = ts_ps[peak_idx_in]
            inset.set_xlim(t_peak - 3fwhm_out, t_peak + 3fwhm_out)
            inset.tick_params(labelsize=7)
            inset.set_title("Zoom", fontsize=8)
        end

        peak_in = maximum(P_in)
        peak_out = maximum(P_out)
        axs[2, col].annotate(@sprintf("Peak in: %.0f W\nPeak out: %.0f W", peak_in, peak_out),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=9,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 3: Group delay τ(ω) [fs] ──
        # Group delay is the most human-readable phase view: it shows
        # how much each wavelength is delayed/advanced in time.
        τ_fs = compute_group_delay(fftshift(φ[:, 1]), sim)
        spec_power = abs2.(fftshift(uω0_shaped[:, 1]))
        τ_display = _apply_dB_mask(τ_fs, spec_power)

        axs[3, col].plot(λ_nm, τ_display, color=COLOR_REF, linewidth=0.8)
        axs[3, col].set_xlabel("Wavelength [nm]")
        axs[3, col].set_ylabel("Group delay [fs]")
        axs[3, col].set_xlim(λ0_nm - 300, λ0_nm + 500)
        axs[3, col].set_title("Group delay τ(ω)")
        axs[3, col].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--", alpha=0.5, linewidth=0.8)
        axs[3, col].ticklabel_format(useOffset=false, style="plain", axis="x")
    end

    # ΔJ = J_after - J_before annotation on the "After" spectral panel
    if length(J_values) == 2
        ΔJ = J_values[2] - J_values[1]
        ΔJ_dB = MultiModeNoise.lin_to_dB(J_values[2]) - MultiModeNoise.lin_to_dB(J_values[1])
        axs[1, 2].annotate(@sprintf("ΔJ = %.4f (%.1f dB improvement)", ΔJ, -ΔJ_dB),
            xy=(0.05, 0.85), xycoords="axes fraction", va="top", fontsize=9,
            color=ΔJ < 0 ? "darkgreen" : "darkred",
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))
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
    figsize=(12, 14), save_path=nothing)

    ts_ps = sim["ts"] .* 1e12
    Nt = sim["Nt"]
    f0 = sim["f0"]
    Δt = sim["Δt"]

    f_shifted = f0 .+ fftshift(fftfreq(Nt, 1 / Δt))
    λ_nm = C_NM_THZ ./ f_shifted
    λ0_nm = C_NM_THZ / f0

    Δf_shifted = fftshift(fftfreq(Nt, 1 / Δt))
    raman_half_bw_thz = 2.5  # ±2.5 THz window around gain peak (~10 THz FWHM silica Raman)
    raman_λ_idx = abs.(Δf_shifted .- raman_threshold) .< raman_half_bw_thz

    fig, axs = subplots(3, 2, figsize=figsize)

    for (col, (A, label)) in enumerate([(A_before, "Before"), (A_after, "After")])
        uω0_shaped = uω0_base .* A

        fiber_plot = deepcopy(fiber)
        fiber_plot["zsave"] = [0.0, fiber["L"]]
        sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_plot, sim)
        uωf = sol["uω_z"][end, :, :]
        utf = sol["ut_z"][end, :, :]
        ut_in = fft(uω0_shaped, 1)

        # ── Row 1: Spectra (wavelength, dB) ──
        spec_out = abs2.(fftshift(uωf[:, 1]))
        spec_in = abs2.(fftshift(uω0_shaped[:, 1]))
        P_ref = max(maximum(spec_in), maximum(spec_out))
        spec_in_dB = 10 .* log10.(spec_in ./ P_ref .+ 1e-30)
        spec_out_dB = 10 .* log10.(spec_out ./ P_ref .+ 1e-30)

        axs[1, col].plot(λ_nm, spec_in_dB, color=COLOR_INPUT, label="Input", alpha=0.7, linewidth=1.0)
        axs[1, col].plot(λ_nm, spec_out_dB, color=COLOR_OUTPUT, label="Output", alpha=0.8, linewidth=1.0)

        # Raman onset line: axvline at Stokes onset wavelength
        λ_raman_onset_amp = C_NM_THZ / (f0 + raman_threshold)
        axs[1, col].axvline(x=λ_raman_onset_amp, color=COLOR_RAMAN, ls="--",
            alpha=0.7, linewidth=1.0, label="Raman onset")

        axs[1, col].set_xlabel("Wavelength [nm]")
        axs[1, col].set_ylabel("Power [dB]")
        axs[1, col].set_title("$label optimization")
        axs[1, col].legend(fontsize=8)
        axs[1, col].set_xlim(λ0_nm - 300, λ0_nm + 500)
        axs[1, col].set_ylim(-60, 3)
        axs[1, col].ticklabel_format(useOffset=false, style="plain", axis="x")

        J_val = sum(abs2.(uωf) .* band_mask) / sum(abs2.(uωf))
        axs[1, col].annotate(@sprintf("J = %.4f (%.1f dB)", J_val, MultiModeNoise.lin_to_dB(J_val)),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 2: Temporal pulse shape ──
        P_in = abs2.(ut_in[:, 1])
        P_out = abs2.(utf[:, 1])

        axs[2, col].plot(ts_ps, P_in, color=COLOR_INPUT, label="Input", alpha=0.7, linewidth=1.0)
        axs[2, col].plot(ts_ps, P_out, color=COLOR_OUTPUT, label="Output", alpha=0.8, linewidth=1.0)
        axs[2, col].set_xlabel("Time [ps]")
        axs[2, col].set_ylabel("Power [W]")
        axs[2, col].set_title("Temporal pulse shape")
        axs[2, col].legend(fontsize=8)

        P_combined = max.(P_in, P_out)
        t_lims = _auto_time_limits(P_combined, ts_ps; padding_factor=4.0)
        axs[2, col].set_xlim(t_lims...)

        peak_in = maximum(P_in)
        peak_out = maximum(P_out)
        axs[2, col].annotate(@sprintf("Peak in: %.1f W\nPeak out: %.1f W", peak_in, peak_out),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=9,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 3: Amplitude profile A(ω) on wavelength axis ──
        A_shifted = fftshift(A[:, 1])
        axs[3, col].plot(λ_nm, A_shifted, "k-", linewidth=1.2)
        axs[3, col].axhline(y=1.0, color="gray", ls="--", alpha=0.5, label="A = 1")
        axs[3, col].set_xlabel("Wavelength [nm]")
        axs[3, col].set_ylabel("Amplitude A(ω)")
        axs[3, col].set_xlim(λ0_nm - 300, λ0_nm + 500)
        axs[3, col].legend(fontsize=8)
        axs[3, col].set_title("Amplitude profile")
        axs[3, col].ticklabel_format(useOffset=false, style="plain", axis="x")

        A_min, A_max = extrema(A[:, 1])
        axs[3, col].annotate(@sprintf("A ∈ [%.3f, %.3f]", A_min, A_max),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # Box constraint check: amplitude must stay in [0, 1]
        # Mark INVALID if box constraints violated (amplitude < 0 or > 1)
        if A_min < -1e-6 || A_max > 1.0 + 1e-6
            # INVALID watermark: box constraints violated
            for r in 1:3
                axs[r, col].text(0.5, 0.5, "INVALID",
                    transform=axs[r, col].transAxes,
                    fontsize=18, color="red", alpha=0.4,
                    ha="center", va="center", rotation=30,
                    fontweight="bold",
                    bbox=Dict("boxstyle" => "round", "facecolor" => "white", "alpha" => 0.2))
            end
            @warn "plot_amplitude_result_v2: column $col has box constraints violated (A ∈ [$A_min, $A_max])"
        end
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

end # include guard (_VISUALIZATION_JL_LOADED)
