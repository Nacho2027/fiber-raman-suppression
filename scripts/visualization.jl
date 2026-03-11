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

PyPlot.matplotlib.rcParams["font.size"] = 11
PyPlot.matplotlib.rcParams["axes.labelsize"] = 12
PyPlot.matplotlib.rcParams["axes.titlesize"] = 13
PyPlot.matplotlib.rcParams["xtick.labelsize"] = 10
PyPlot.matplotlib.rcParams["ytick.labelsize"] = 10
PyPlot.matplotlib.rcParams["legend.fontsize"] = 10
PyPlot.matplotlib.rcParams["figure.dpi"] = 150
PyPlot.matplotlib.rcParams["savefig.dpi"] = 300
PyPlot.matplotlib.rcParams["axes.grid"] = true
PyPlot.matplotlib.rcParams["grid.alpha"] = 0.3

# Physical constants
const C_NM_THZ = 299792.458  # speed of light in nm·THz

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
    cmap="jet", figsize=(8, 6),
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

    ax.set_xlabel("Wavelength [nm]")
    ax.set_ylabel(z_label)

    if !isnothing(wavelength_limits)
        ax.set_xlim(wavelength_limits...)
    else
        # Default: center ± sensible range based on center wavelength
        λ0_nm = C_NM_THZ / f0
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
    cmap="jet", figsize=(8, 6),
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
    cmap="jet", figsize=(8, 10),
    length_unit=:auto, title=nothing)

    fig, axes = subplots(2, 1, figsize=figsize)

    # Top: temporal
    _, ax_t, im_t = plot_temporal_evolution(sol, sim, fiber;
        mode_idx=mode_idx, dB_range=dB_range, time_limits=time_limits,
        cmap=cmap, length_unit=length_unit, ax=axes[1], fig=fig)
    ax_t.set_title("Temporal evolution")

    # Bottom: spectral
    _, ax_s, im_s = plot_spectral_evolution(sol, sim, fiber;
        mode_idx=mode_idx, dB_range=dB_range, wavelength_limits=wavelength_limits,
        cmap=cmap, length_unit=length_unit, ax=axes[2], fig=fig)
    ax_s.set_title("Spectral evolution")

    # Shared colorbar on the right
    fig.subplots_adjust(right=0.88)
    cbar_ax = fig.add_axes([0.90, 0.15, 0.025, 0.7])
    cb = fig.colorbar(im_s, cax=cbar_ax)
    cb.set_label("Power [dB]")

    if !isnothing(title)
        fig.suptitle(title, fontsize=14, y=0.98)
    end

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
    cmap="jet", figsize=(8, 6))

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
    ax.plot(λ_nm, P_in_dB, "b-", label=label_in, alpha=0.7, linewidth=1.2)
    ax.plot(λ_nm, P_out_dB, "r-", label=label_out, alpha=0.8, linewidth=1.2)

    # Raman band shading
    if !isnothing(raman_threshold)
        Δf_shifted = fftshift(fftfreq(Nt, 1 / Δt))
        raman_idx = Δf_shifted .< raman_threshold
        if any(raman_idx)
            λ_raman = λ_nm[raman_idx]
            ax.axvspan(minimum(λ_raman), maximum(λ_raman),
                alpha=0.12, color="red", label="Raman band")
        end
    end

    ax.set_xlabel("Wavelength [nm]")
    ax.set_ylabel("Power [dB]")
    ax.set_ylim(-dB_range, 3)
    ax.legend()

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
    raman_λ_idx = Δf_shifted .< raman_threshold

    fig, axs = subplots(3, 2, figsize=figsize)

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

        axs[1, col].plot(λ_nm, spec_in_dB, "b-", label="Input", alpha=0.7, linewidth=1.0)
        axs[1, col].plot(λ_nm, spec_out_dB, "r-", label="Output", alpha=0.8, linewidth=1.0)

        if any(raman_λ_idx)
            λ_raman = λ_nm[raman_λ_idx]
            axs[1, col].axvspan(minimum(λ_raman), maximum(λ_raman),
                alpha=0.12, color="red", label="Raman band")
        end

        axs[1, col].set_xlabel("Wavelength [nm]")
        axs[1, col].set_ylabel("Power [dB]")
        axs[1, col].set_title("$label optimization")
        axs[1, col].legend(fontsize=8)
        axs[1, col].set_xlim(λ0_nm - 300, λ0_nm + 500)
        axs[1, col].set_ylim(-60, 3)

        J_val = sum(abs2.(uωf) .* band_mask) / sum(abs2.(uωf))
        axs[1, col].annotate(@sprintf("J = %.4f (%.1f dB)", J_val, MultiModeNoise.lin_to_dB(J_val)),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 2: Temporal pulse shape ──
        P_in = abs2.(ut_in[:, 1])
        P_out = abs2.(utf[:, 1])

        axs[2, col].plot(ts_ps, P_in, "b-", label="Input", alpha=0.7, linewidth=1.0)
        axs[2, col].plot(ts_ps, P_out, "r-", label="Output", alpha=0.8, linewidth=1.0)
        axs[2, col].set_xlabel("Time [ps]")
        axs[2, col].set_ylabel("Power [W]")
        axs[2, col].set_title("Temporal pulse shape")
        axs[2, col].legend(fontsize=8)

        # Auto-center on pulse
        P_combined = max.(P_in, P_out)
        t_lims = _auto_time_limits(P_combined, ts_ps; padding_factor=4.0)
        axs[2, col].set_xlim(t_lims...)

        peak_in = maximum(P_in)
        peak_out = maximum(P_out)
        axs[2, col].annotate(@sprintf("Peak in: %.0f W\nPeak out: %.0f W", peak_in, peak_out),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=9,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 3: Spectral phase [0, 2π] ──
        φ_wrapped = wrap_phase(fftshift(φ[:, 1]))
        axs[3, col].plot(λ_nm, φ_wrapped, "k-", linewidth=0.8)
        axs[3, col].set_xlabel("Wavelength [nm]")
        set_phase_yticks!(axs[3, col])
        axs[3, col].set_xlim(λ0_nm - 300, λ0_nm + 500)
        axs[3, col].set_title("Spectral phase")
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
    raman_λ_idx = Δf_shifted .< raman_threshold

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

        axs[1, col].plot(λ_nm, spec_in_dB, "b-", label="Input", alpha=0.7, linewidth=1.0)
        axs[1, col].plot(λ_nm, spec_out_dB, "r-", label="Output", alpha=0.8, linewidth=1.0)

        if any(raman_λ_idx)
            λ_raman = λ_nm[raman_λ_idx]
            axs[1, col].axvspan(minimum(λ_raman), maximum(λ_raman),
                alpha=0.12, color="red", label="Raman band")
        end

        axs[1, col].set_xlabel("Wavelength [nm]")
        axs[1, col].set_ylabel("Power [dB]")
        axs[1, col].set_title("$label optimization")
        axs[1, col].legend(fontsize=8)
        axs[1, col].set_xlim(λ0_nm - 300, λ0_nm + 500)
        axs[1, col].set_ylim(-60, 3)

        J_val = sum(abs2.(uωf) .* band_mask) / sum(abs2.(uωf))
        axs[1, col].annotate(@sprintf("J = %.4f (%.1f dB)", J_val, MultiModeNoise.lin_to_dB(J_val)),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 2: Temporal pulse shape ──
        P_in = abs2.(ut_in[:, 1])
        P_out = abs2.(utf[:, 1])

        axs[2, col].plot(ts_ps, P_in, "b-", label="Input", alpha=0.7, linewidth=1.0)
        axs[2, col].plot(ts_ps, P_out, "r-", label="Output", alpha=0.8, linewidth=1.0)
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

        A_min, A_max = extrema(A[:, 1])
        axs[3, col].annotate(@sprintf("A ∈ [%.3f, %.3f]", A_min, A_max),
            xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))
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

    # Edge zones
    ax.axvspan(ts_ps[1], ts_ps[n_edge], alpha=0.2, color="red", label="Edge zone")
    ax.axvspan(ts_ps[end-n_edge+1], ts_ps[end], alpha=0.2, color="red")

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
