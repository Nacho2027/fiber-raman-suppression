"""
Publication-quality visualization for supercontinuum generation and
nonlinear fiber optics simulations.

Standard plot types following Dudley et al. (2006, Rev. Mod. Phys.):
  1. Spectral evolution: wavelength [nm] vs propagation distance, power [dB] color
  2. Temporal evolution: time [ps] vs propagation distance, power [dB] color
  3. Combined two-panel evolution figure
  4. Optimization result comparison (before/after)

Requires: PyPlot, FFTW, LinearAlgebra, FiberLab (for meshgrid, lin_to_dB, solve_disp_mmf)

This package-owned implementation is safe to include multiple times.
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

const _PLOT_DEFAULTS_CONFIGURED = Ref(false)

function _ensure_plot_defaults!()
    _PLOT_DEFAULTS_CONFIGURED[] && return nothing
    rc = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
    for (key, value) in (
        "font.size" => 10,
        "axes.labelsize" => 12,
        "axes.titlesize" => 13,
        "xtick.labelsize" => 10,
        "ytick.labelsize" => 10,
        "legend.fontsize" => 10,
        "figure.dpi" => 150,
        "savefig.dpi" => 450,
        "savefig.bbox" => "tight",
        "axes.grid" => true,
        "grid.alpha" => 0.3,
    )
        rc[key] = value
    end
    _PLOT_DEFAULTS_CONFIGURED[] = true
    return nothing
end

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

Compute the angular frequency step Δω [rad/ps] from the fftshifted grid.
"""
function _spectral_omega_step(sim)
    Δf_grid = fftshift(fftfreq(sim["Nt"], 1 / sim["Δt"]))
    return 2π * (Δf_grid[2] - Δf_grid[1])
end

_raman_marker_wavelength_nm(f0_thz::Real, threshold_thz::Real) =
    C_NM_THZ / (Float64(f0_thz) + Float64(threshold_thz))

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
                           threshold_dB=-30.0, padding_nm=20.0)

Compute wavelength xlim containing all spectral content above threshold_dB
relative to peak. Returns (lambda_lo, lambda_hi) in nm.
Both inputs must be co-indexed in fftshifted order.
Negative-frequency ghost wavelengths (λ < 0 from FFT artifacts) are filtered out.

Uses a −30 dB signal threshold and 20 nm wavelength padding.
so narrow pulses (≲ 20 nm FWHM) are not plotted against a ±130 nm whitespace
envelope. Callers can still pass the old values explicitly.
"""
function _spectral_signal_xlim(P_spec_fftshifted, lambda_nm_fftshifted;
                                threshold_dB=-30.0, padding_nm=20.0)
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
        @sprintf("Fiber: %s  L = %s", metadata.fiber_name,
                 _format_length_m(metadata.L_m)),
        @sprintf("P0 = %.0f mW  lambda0 = %.0f nm  FWHM = %.0f fs",
            metadata.P_cont_W * 1000, metadata.lambda0_nm, metadata.fwhm_fs),
    ]
    fig.text(x, y, join(lines, "\n");
        ha="left", va="bottom", fontsize=fontsize,
        color="dimgray", transform=fig.transFigure,
        bbox=Dict("boxstyle" => "round,pad=0.2", "facecolor" => "white",
                  "alpha" => 0.7, "edgecolor" => "lightgray"))
end

function _tight_layout_with_optional_metadata!(fig, metadata; footer_y=0.006, bottom=0.045)
    if isnothing(metadata)
        fig.tight_layout()
    else
        fig.tight_layout(rect=(0.0, bottom, 1.0, 1.0))
        _add_metadata_block!(fig, metadata; y=footer_y)
    end
end

function _format_power_watts(P::Real)
    P_float = Float64(P)
    isfinite(P_float) || return "NaN W"
    P_abs = abs(P_float)
    if P_abs >= 1e3
        return @sprintf("%.3g kW", P_float / 1e3)
    elseif P_abs >= 1.0
        return @sprintf("%.3g W", P_float)
    elseif P_abs >= 1e-3
        return @sprintf("%.3g mW", P_float * 1e3)
    else
        return @sprintf("%.3g uW", P_float * 1e6)
    end
end

function _format_objective_value(value::Real)
    x = Float64(value)
    isfinite(x) || return "NaN"
    magnitude = abs(x)
    return 0 < magnitude < 1e-3 || magnitude >= 1e4 ?
        @sprintf("%.3e", x) : @sprintf("%.4f", x)
end

function _format_length_m(length_m::Real)
    value = Float64(length_m)
    value >= 1 && return @sprintf("%.3g m", value)
    value >= 1e-3 && return @sprintf("%.3g mm", value * 1e3)
    return @sprintf("%.3g µm", value * 1e6)
end

_format_delta_db(value::Real) = abs(value) < 0.05 ?
    @sprintf("%.3f dB", value) : @sprintf("%.1f dB", value)

function _objective_plot_label(kind::Symbol, supplied)
    builtin = Dict(
        :raman_band => "Raman-band leakage",
        :raman_peak => "Raman-band peak",
        :temporal_width => "Temporal width",
        :mmf_sum => "Mode-summed Raman leakage",
        :mmf_fundamental => "Fundamental-mode Raman leakage",
        :mmf_worst_mode => "Worst-mode Raman leakage",
    )
    haskey(builtin, kind) && return builtin[kind]
    return supplied === nothing ? replace(String(kind), "_" => " ") : String(supplied)
end

"""Compute group delay `dφ/dω` in fs from fft-shifted spectral phase."""
function compute_group_delay(φ_shifted, sim)
    dω = _spectral_omega_step(sim)
    φ_unwrapped = _manual_unwrap(φ_shifted)
    return _central_diff(φ_unwrapped, dω) .* 1e3
end

"""
    compute_instantaneous_frequency(ut, sim)

Compute instantaneous frequency offset Δf(t) in THz from a complex time-domain
field vector. Extracts temporal phase, unwraps, and differentiates.
The project convention is `u(t) ∝ exp(-iΩt)`, so `-dφ/dt / 2π` gives
the physical frequency offset in THz.
"""
function compute_instantaneous_frequency(ut, sim)
    dt_ps = (sim["ts"][2] - sim["ts"][1]) * 1e12
    φ_unwrapped = _manual_unwrap(angle.(ut))
    return -_central_diff(φ_unwrapped, dt_ps) ./ (2π)
end

"""
    plot_phase_diagnostic(φ, uω0_base, sim; save_path=nothing)

Standalone six-view phase diagnostic figure:
  (1,1): Wrapped spectral phase φ(ω) [0, 2π] with π-ticks
  (1,2): Unwrapped spectral phase φ(ω) [rad]
  (2,1): Group delay τ(ω) [fs]
  (2,2): GDD [fs²] with percentile-clipped y-axis
  (3,1): Instantaneous frequency [THz offset] vs time
  (3,2): spectral support used for phase masking

Phase is masked to -40 dB BEFORE unwrapping (BUG-03 fix). All spectral
quantities are NaN-masked for display where power < -30 dB relative to peak.
Spectral xlim auto-zooms to signal-bearing region (AXIS-02).
"""
function plot_phase_diagnostic(φ, uω0_base, sim; save_path=nothing, metadata=nothing,
    objective_kind::Symbol=:raman_band, raman_threshold_thz=nothing,
    mode_idx=:sum)
    _ensure_plot_defaults!()
    f0 = sim["f0"]
    ts_ps = sim["ts"] .* 1e12
    dω = _spectral_omega_step(sim)

    λ_nm, pos_mask, sort_idx = _freq_to_wavelength(sim)

    phase_trace = _phase_trace(φ, mode_idx)
    view_label = _mode_view_label(mode_idx, size(uω0_base, 2))

    # Spectral power for masking (fftshifted, positive-freq, wavelength-sorted)
    spec_power_full = vec(_modal_power(fftshift(uω0_base, 1), mode_idx))
    P_peak = maximum(spec_power_full)
    P_peak > 0 || throw(ArgumentError(
        "phase diagnostic view `$(view_label)` has zero spectral energy"))
    spec_pos = spec_power_full[pos_mask][sort_idx]

    # --- BUG-03 fix: mask phase BEFORE unwrapping ---
    φ_shifted = fftshift(phase_trace)
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
    phase_matrix = ndims(φ) == 1 ? reshape(φ, :, 1) : φ
    ut_shaped = fft(uω0_base .* cis.(phase_matrix), 1)
    temporal_power = vec(_modal_power(ut_shaped, mode_idx))
    Δf_inst = _apply_dB_mask(
        _modal_instantaneous_frequency(ut_shaped, sim, mode_idx), temporal_power)

    show_raman_marker = objective_kind in (:raman_band, :raman_peak) &&
        raman_threshold_thz !== nothing
    λ_raman_onset = show_raman_marker ?
        _raman_marker_wavelength_nm(f0, raman_threshold_thz) : NaN

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
    if show_raman_marker
        axs[1, 1].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--", alpha=0.6, label="Raman onset")
    end
    axs[1, 1].set_xlabel("Wavelength [nm]")
    axs[1, 1].set_title(_mode_view_title(
        "Wrapped phase φ(ω)", mode_idx, size(uω0_base, 2)))
    set_phase_yticks!(axs[1, 1])
    axs[1, 1].set_xlim(spec_xlim...)
    show_raman_marker && axs[1, 1].legend(fontsize=8)

    # Remaining spectral panels: (row, col, data, ylabel, title)
    spectral_panels = [
        (1, 2, φ_masked,   "Spectral phase [rad]", "Unwrapped spectral phase φ(ω)"),
        (2, 1, τ_masked,   "Group delay [fs]",     "Group delay τ(ω)"),
        (2, 2, gdd_masked, "GDD [fs²]",            "Group delay dispersion"),
    ]
    for (r, c, data, ylabel, title) in spectral_panels
        axs[r, c].plot(λ_nm, data, color=COLOR_REF, linewidth=0.8)
        if show_raman_marker
            axs[r, c].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--", alpha=0.6, label="Raman onset")
        end
        axs[r, c].set_xlabel("Wavelength [nm]")
        axs[r, c].set_ylabel(ylabel)
        axs[r, c].set_title(title)
        axs[r, c].set_xlim(spec_xlim...)
        show_raman_marker && axs[r, c].legend(fontsize=8)
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
    t_lims = _auto_time_limits(temporal_power, ts_ps; padding_factor=4.0)
    axs[3, 1].set_xlim(t_lims...)

    # Panel (3,2): spectral support makes the derivative masks auditable.
    support_dB = 10 .* log10.(spec_pos ./ maximum(spec_pos) .+ 1e-30)
    axs[3, 2].plot(λ_nm, support_dB, color=COLOR_INPUT, linewidth=1.0)
    axs[3, 2].axhline(-30.0, color="gray", ls="--", linewidth=0.8,
                      label="Display mask")
    if show_raman_marker
        axs[3, 2].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--",
                          alpha=0.6, label="Raman onset")
    end
    axs[3, 2].set_xlabel("Wavelength [nm]")
    axs[3, 2].set_ylabel("Relative power [dB]")
    axs[3, 2].set_title("Spectral support for phase views")
    axs[3, 2].set_xlim(spec_xlim...)
    axs[3, 2].set_ylim(-60, 3)
    axs[3, 2].legend(fontsize=8)

    _tight_layout_with_optional_metadata!(fig, metadata)

    if !isnothing(save_path)
        savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved phase diagnostic to $save_path"
    end

    return fig, axs
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. Spectral evolution (wavelength domain)
# ─────────────────────────────────────────────────────────────────────────────

"""Return modal power, either for one mode or summed incoherently over modes."""
function _modal_power(field, mode_idx)
    modal_axis = ndims(field)
    mode_count = size(field, modal_axis)
    if mode_idx == :sum
        return dropdims(sum(abs2, field; dims=modal_axis); dims=modal_axis)
    end
    mode_idx isa Integer || throw(ArgumentError(
        "mode_idx must be a mode number or :sum, got `$(mode_idx)`"))
    1 <= mode_idx <= mode_count || throw(ArgumentError(
        "mode_idx=$(mode_idx) is outside 1:$(mode_count)"))
    return abs2.(selectdim(field, modal_axis, mode_idx))
end

_mode_view_label(mode_idx, mode_count=nothing) = mode_idx == :sum ?
    (mode_count == 1 ? "single mode" : "all modes (summed power)") :
    "mode $(mode_idx)"

function _mode_view_title(title, mode_idx, mode_count)
    mode_count == 1 && return String(title)
    return "$(title) — $(_mode_view_label(mode_idx, mode_count))"
end

function _modal_instantaneous_frequency(field::AbstractMatrix, sim, mode_idx)
    mode_idx isa Integer && return compute_instantaneous_frequency(field[:, mode_idx], sim)
    mode_idx == :sum || throw(ArgumentError(
        "mode_idx must be a mode number or :sum, got `$(mode_idx)`"))
    power = abs2.(field)
    total_power = vec(sum(power; dims=2))
    weighted = zeros(Float64, size(field, 1))
    for mode in axes(field, 2)
        weighted .+= power[:, mode] .* compute_instantaneous_frequency(field[:, mode], sim)
    end
    active = total_power .> 0
    weighted[active] ./= total_power[active]
    return weighted
end

function _phase_trace(phase, mode_idx=:sum)
    ndims(phase) == 1 && return vec(phase)
    ndims(phase) == 2 || throw(ArgumentError("phase must be a vector or Nt×M matrix"))
    if mode_idx == :sum
        profile = vec(phase[:, 1])
        all(column -> column == profile, eachcol(phase)) || throw(ArgumentError(
            "mode_idx=:sum requires a phase shared across all modes"))
        return profile
    end
    mode_idx isa Integer || throw(ArgumentError(
        "mode_idx must be a mode number or :sum, got `$(mode_idx)`"))
    1 <= mode_idx <= size(phase, 2) || throw(ArgumentError(
        "mode_idx=$(mode_idx) is outside 1:$(size(phase, 2))"))
    return vec(phase[:, mode_idx])
end

"""
    plot_spectral_evolution(sol, sim, fiber; kwargs...)

Plot spectral power evolution along fiber length.

Produces the standard wavelength-vs-length density plot (Dudley et al. 2006).
Color scale is normalized dB relative to global peak.
"""
function plot_spectral_evolution(sol, sim, fiber;
    mode_idx=:sum, dB_range=40.0,
    wavelength_limits=nothing,
    cmap="inferno", figsize=(8, 6),
    length_unit=:auto,
    ax=nothing, fig=nothing,
    title="Spectral evolution",
    colorbar::Bool=true)
    _ensure_plot_defaults!()

    uω_z = sol["uω_z"]  # [Nz × Nt × M]
    zsave = collect(fiber["zsave"])
    z_display, z_label = _length_display(zsave, length_unit)

    # Frequency → wavelength
    f0 = sim["f0"]
    Nt = sim["Nt"]
    Δt = sim["Δt"]
    f_shifted = f0 .+ fftshift(fftfreq(Nt, 1 / Δt))

    # Power in fftshifted order: [Nz × Nt]. Multimode plots default to
    # incoherent total power so the required figure represents the full field.
    P = _modal_power(fftshift(uω_z, 2), mode_idx)
    P_max = maximum(P)
    P_dB = 10 .* log10.(P ./ P_max .+ 1e-30)
    P_dB = clamp.(P_dB, -dB_range, 0)

    # Wavelength array (may contain negative freq → filter)
    λ_nm = C_NM_THZ ./ f_shifted

    # Build meshgrid
    ΛΛ, ZZ = FiberLab.meshgrid(λ_nm, z_display)

    created_axes = isnothing(ax)
    if created_axes
        fig, ax = subplots(figsize=figsize)
    end
    im = ax.pcolormesh(ΛΛ, ZZ, P_dB, shading="gouraud", cmap=cmap,
        vmin=-dB_range, vmax=0)
    ax.grid(false)

    ax.set_xlabel("Wavelength [nm]")
    ax.set_ylabel(z_label)
    ax.set_title(title)

    # Mark pump wavelength and Raman onset
    # Silica Raman Stokes shift is ~13.2 THz (dominant peak at 440 cm^-1)
    f_raman = f0 - 13.2  # THz: Raman Stokes onset frequency
    λ0_nm = C_NM_THZ / f0
    λ_raman_nm = C_NM_THZ / f_raman
    ax.axvline(x=λ0_nm, color="white", ls="--", alpha=0.5, linewidth=0.8, label="Pump λ₀")
    ax.axvline(x=λ_raman_nm, color=COLOR_RAMAN, ls="--", alpha=0.7, linewidth=0.8, label="Raman onset")
    ax.legend(loc="upper right", fontsize=8)
    created_axes && colorbar && fig.colorbar(im, ax=ax, label="Relative power [dB]")

    if !isnothing(wavelength_limits)
        ax.set_xlim(wavelength_limits...)
    else
        # AXIS-02: auto-zoom using the z=0 spectrum as signal-content reference.
        # The input spectrum defines the signal extent; propagation may broaden it
        # but the input provides a stable reference that doesn't depend on how much
        # the spectrum has spread (which would over-expand the zoom window).
        P0_spec = vec(P[1, :])
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
    mode_idx=:sum, dB_range=40.0,
    time_limits=nothing,
    cmap="inferno", figsize=(8, 6),
    length_unit=:auto, scale=:dB,
    ax=nothing, fig=nothing)
    _ensure_plot_defaults!()

    ut_z = sol["ut_z"]  # [Nz × Nt × M]
    zsave = collect(fiber["zsave"])
    ts_ps = sim["ts"] .* 1e12
    z_display, z_label = _length_display(zsave, length_unit)

    P = _modal_power(ut_z, mode_idx)

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

    TT, ZZ = FiberLab.meshgrid(ts_ps, z_display)

    if isnothing(ax)
        fig, ax = subplots(figsize=figsize)
    end
    im = ax.pcolormesh(TT, ZZ, P_plot, shading="gouraud", cmap=cmap,
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
    mode_idx=:sum, dB_range=40.0,
    time_limits=nothing, wavelength_limits=nothing,
    cmap="inferno", figsize=(8, 10),
    length_unit=:auto, title=nothing)
    _ensure_plot_defaults!()

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
    dB_range=40.0, cmap="inferno", figsize=(16, 12),
    length_unit=:auto, metadata=nothing, save_path=nothing,
    mode_idx=:sum)
    _ensure_plot_defaults!()

    fig, axs = subplots(2, 2, figsize=figsize)

    # Column 1: Optimized
    _, _, im1 = plot_temporal_evolution(sol_opt, sim, fiber;
        dB_range=dB_range, cmap=cmap, length_unit=length_unit,
        ax=axs[1,1], fig=fig, mode_idx=mode_idx)
    axs[1,1].set_title("Optimized -- temporal")

    _, _, _ = plot_spectral_evolution(sol_opt, sim, fiber;
        dB_range=dB_range, cmap=cmap, length_unit=length_unit,
        ax=axs[2,1], fig=fig, mode_idx=mode_idx)
    axs[2,1].set_title("Optimized -- spectral")
    axs[2,1].legend(fontsize=7, loc="upper right")

    # Column 2: Unshaped
    _, _, _ = plot_temporal_evolution(sol_unshaped, sim, fiber;
        dB_range=dB_range, cmap=cmap, length_unit=length_unit,
        ax=axs[1,2], fig=fig, mode_idx=mode_idx)
    axs[1,2].set_title("Unshaped -- temporal")

    _, _, _ = plot_spectral_evolution(sol_unshaped, sim, fiber;
        dB_range=dB_range, cmap=cmap, length_unit=length_unit,
        ax=axs[2,2], fig=fig, mode_idx=mode_idx)
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
    L_str = "L = $(_format_length_m(L_val))"
    fig.suptitle("Evolution comparison -- $L_str", fontsize=13, y=0.98)

    # META-01: metadata annotation block (bottom=0.06 in subplots_adjust reserves space for it)
    if !isnothing(metadata)
        _add_metadata_block!(fig, metadata)
    end

    if !isnothing(save_path)
        savefig(save_path, dpi=450, bbox_inches="tight")
        @info "Saved merged evolution plot to $save_path"
    end

    return fig, axs
end


# ─────────────────────────────────────────────────────────────────────────────
# 7. Optimization result — publication quality (phase optimization)
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
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
    figsize=(12, 12), save_path=nothing, metadata=nothing,
    objective_kind::Symbol=:raman_band,
    uω0_after=nothing,
    objective_values=nothing,
    objective_scale::Symbol=:linear,
    objective_label=nothing,
    mode_idx=:sum)
    _ensure_plot_defaults!()

    ts_ps = sim["ts"] .* 1e12
    Nt = sim["Nt"]
    f0 = sim["f0"]
    Δt = sim["Δt"]

    # Wavelength grid (fftshifted)
    f_shifted = f0 .+ fftshift(fftfreq(Nt, 1 / Δt))
    λ_nm = C_NM_THZ ./ f_shifted
    λ0_nm = C_NM_THZ / f0

    show_raman_marker = objective_kind in (:raman_band, :raman_peak)
    λ_raman_onset = show_raman_marker ? C_NM_THZ / (f0 + raman_threshold) : NaN
    resolved_objective_label = _objective_plot_label(objective_kind, objective_label)
    after_input = uω0_after === nothing ? uω0_base : uω0_after
    size(after_input) == size(uω0_base) || throw(ArgumentError(
        "uω0_after shape $(size(after_input)) must match before-input shape $(size(uω0_base))"))
    objective_scale in (:linear, :db) || throw(ArgumentError(
        "objective_scale must be :linear or :db"))
    if objective_values !== nothing
        length(objective_values) == 2 || throw(ArgumentError(
            "objective_values must contain exactly (before, after)"))
        all(value -> value isa Real && isfinite(Float64(value)) &&
                (objective_scale == :db || value >= 0),
            objective_values) || throw(ArgumentError(
            "objective_values must be finite and linear values must be nonnegative"))
    end

    # ── Pass 1: simulate both columns and collect results ──
    # Pre-compute all fields so shared quantities can be derived globally.
    col_data = NamedTuple[]
    mode_views = mode_idx isa Tuple ? mode_idx : (mode_idx, mode_idx)
    length(mode_views) == 2 || throw(ArgumentError(
        "mode_idx tuple must contain exactly (before, after) views"))
    comparisons = ((φ_before, uω0_base, "Before", mode_views[1]),
                   (φ_after, after_input, "After", mode_views[2]))
    for (phi_col, input_col, label, mode_view) in comparisons
        uω0_shaped = @. input_col * cis(phi_col)
        fiber_plot = deepcopy(fiber)
        fiber_plot["zsave"] = [0.0, fiber["L"]]
        sol = FiberLab.solve_disp_mmf(uω0_shaped, fiber_plot, sim)
        uωf = sol["uω_z"][end, :, :]
        utf = sol["ut_z"][end, :, :]
        ut_in = fft(uω0_shaped, 1)
        push!(col_data, (
            uω0_shaped = uω0_shaped,
            uωf        = uωf,
            utf        = utf,
            ut_in      = ut_in,
            label      = label,
            spec_in    = vec(_modal_power(fftshift(uω0_shaped, 1), mode_view)),
            spec_out   = vec(_modal_power(fftshift(uωf, 1), mode_view)),
            P_in       = vec(_modal_power(ut_in, mode_view)),
            P_out      = vec(_modal_power(utf, mode_view)),
            phi_col    = phi_col,
            mode_view  = mode_view,
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

        if show_raman_marker
            axs[1, col].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--",
                alpha=0.7, linewidth=1.0, label="Raman onset")
        end

        axs[1, col].set_xlabel("Wavelength [nm]")
        axs[1, col].set_ylabel("Power [dB]")
        axs[1, col].set_title(_mode_view_title(
            "$(r.label) optimization", r.mode_view, size(r.uω0_shaped, 2)))
        axs[1, col].legend(fontsize=8, loc="upper right")
        axs[1, col].ticklabel_format(useOffset=false, style="plain", axis="x")

        J_val = if objective_values !== nothing
            Float64(objective_values[col])
        elseif objective_kind == :temporal_width
            FiberLab._field_temporal_width_cost(r.uωf, sim)[1]
        elseif objective_kind == :raman_peak
            FiberLab._field_spectral_peak_cost(r.uωf, band_mask)[1]
        else
            FiberLab._field_spectral_band_cost(r.uωf, band_mask)[1]
        end
        push!(J_values, J_val)
        objective_text = objective_scale == :db ?
            @sprintf("%s = %.2f dB", resolved_objective_label, J_val) :
            @sprintf("%s = %s (%.1f dB)", resolved_objective_label,
                _format_objective_value(J_val), FiberLab.lin_to_dB(J_val))
        if objective_values === nothing || col == 1
            axs[1, col].annotate(objective_text,
                xy=(0.04, 0.95), xycoords="axes fraction", va="top", fontsize=9,
                bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.85))
        end

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
        axs[2, col].annotate(@sprintf("Peak in: %s\nPeak out: %s",
                _format_power_watts(peak_in), _format_power_watts(peak_out)),
            xy=(0.05, 0.82), xycoords="axes fraction", va="top", fontsize=9,
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))

        # ── Row 3: Group delay τ(ω) [fs] ──
        # Group delay is the most human-readable phase view: it shows
        # how much each wavelength is delayed/advanced in time.
        τ_fs = compute_group_delay(fftshift(_phase_trace(r.phi_col, r.mode_view)), sim)
        spec_power = vec(_modal_power(fftshift(r.uω0_shaped, 1), r.mode_view))
        τ_display = _apply_dB_mask(τ_fs, spec_power)

        axs[3, col].plot(λ_nm, τ_display, color=COLOR_REF, linewidth=0.8)
        axs[3, col].set_xlabel("Wavelength [nm]")
        axs[3, col].set_ylabel("Group delay [fs]")
        # AXIS-02: auto-zoom spectral xlim (replaces fixed λ0 ± offset)
        axs[3, col].set_xlim(spec_xlim...)
        axs[3, col].set_title("Group delay τ(ω)")
        if show_raman_marker
            axs[3, col].axvline(x=λ_raman_onset, color=COLOR_RAMAN, ls="--", alpha=0.5, linewidth=0.8)
        end
        axs[3, col].ticklabel_format(useOffset=false, style="plain", axis="x")
    end

    # META-02: J_before, J_after, and Delta-J annotation on the "After" spectral panel
    if length(J_values) == 2
        J_before_dB = objective_scale == :db ? J_values[1] : FiberLab.lin_to_dB(J_values[1])
        J_after_dB = objective_scale == :db ? J_values[2] : FiberLab.lin_to_dB(J_values[2])
        ΔJ_dB = J_after_dB - J_before_dB
        axs[1, 2].annotate(
            @sprintf("%s\nBefore  %.1f dB\nAfter   %.1f dB\nΔ       %s",
                resolved_objective_label, J_before_dB, J_after_dB,
                _format_delta_db(ΔJ_dB)),
            xy=(0.04, 0.95), xycoords="axes fraction", va="top", fontsize=9,
            color=ΔJ_dB < 0 ? "darkgreen" : "darkred",
            bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.85))
    end

    _tight_layout_with_optional_metadata!(fig, metadata)

    if !isnothing(save_path)
        savefig(save_path, dpi=450, bbox_inches="tight")
        @info "Saved optimization result to $save_path"
    end

    return fig
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
    _ensure_plot_defaults!()

    fiber_evo = deepcopy(fiber)
    fiber_evo["zsave"] = collect(LinRange(0, fiber["L"], n_zsave))
    sol = FiberLab.solve_disp_mmf(uω0_shaped, fiber_evo, sim)

    fig, axes = plot_combined_evolution(sol, sim, fiber_evo;
        title=title, kwargs...)

    if !isnothing(save_path)
        savefig(save_path, dpi=300, bbox_inches="tight")
        @info "Saved evolution plot to $save_path"
    end

    return sol, fig, axes
end


end # include guard (_VISUALIZATION_JL_LOADED)
