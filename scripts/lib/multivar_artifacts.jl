"""
Variable-specific artifact writers for front-layer multivariable runs.

These are thin post-run helpers. They do not change the optimization; they make
the artifact hooks advertised by `artifact_plan.jl` real for the current
phase/amplitude/energy surface.
"""

if !(@isdefined _MULTIVAR_ARTIFACTS_JL_LOADED)
const _MULTIVAR_ARTIFACTS_JL_LOADED = true

using FFTW
using JSON3
using Printf
using Statistics
using PyPlot

include(joinpath(@__DIR__, "common.jl"))

function _multivar_artifact_tag(save_prefix::AbstractString)
    return basename(String(save_prefix))
end

function _multivar_shaped_input(result_bundle)
    outcome = result_bundle.outcome
    alpha = Float64(get(outcome.diagnostics, :alpha, sqrt(outcome.E_opt / outcome.E_ref)))
    return @. alpha * outcome.A_opt * cis(outcome.φ_opt) * result_bundle.uω0
end

function _time_power(field)
    return abs2.(ifft(field, 1))
end

function _peak_power(field)
    return Float64(maximum(_time_power(field)))
end

function _safe_ratio(num, den)
    den == 0 ? NaN : Float64(num / den)
end

function _write_json(path::AbstractString, payload)
    open(path, "w") do io
        JSON3.pretty(io, payload)
    end
    return path
end

function _wavelength_axis_nm(sim)
    Nt = sim["Nt"]
    f0 = sim["f0"]
    Δt = sim["Δt"]
    f_shifted = f0 .+ fftshift(FFTW.fftfreq(Nt, 1 / Δt))
    return C_NM_THZ ./ f_shifted
end

function _spectral_db(field)
    spectrum = abs2.(fftshift(field[:, 1]))
    ref = max(maximum(spectrum), eps())
    return 10 .* log10.(spectrum ./ ref .+ 1e-30)
end

function _write_multivar_amplitude_plot(path, result_bundle, shaped)
    λ_nm = _wavelength_axis_nm(result_bundle.sim)
    A_opt = result_bundle.outcome.A_opt

    fig, axs = subplots(2, 1, figsize=(10, 7), sharex=true)
    axs[1].plot(λ_nm, fftshift(A_opt[:, 1]), color="black", linewidth=1.3)
    axs[1].axhline(1.0, color="gray", linestyle="--", alpha=0.6)
    axs[1].set_ylabel("Amplitude mask")
    axs[1].set_title("Multivariable amplitude control")
    Amin, Amax = extrema(A_opt)
    axs[1].annotate(
        @sprintf("A in [%.3f, %.3f]", Amin, Amax),
        xy=(0.02, 0.92),
        xycoords="axes fraction",
        va="top",
        fontsize=9,
        bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
    )

    axs[2].plot(λ_nm, _spectral_db(result_bundle.uω0), label="unshaped input", alpha=0.8)
    axs[2].plot(λ_nm, _spectral_db(shaped), label="shaped input", alpha=0.8)
    axs[2].set_xlabel("Wavelength [nm]")
    axs[2].set_ylabel("Power [dB]")
    axs[2].set_ylim(-60, 3)
    axs[2].legend(fontsize=8)
    axs[2].ticklabel_format(useOffset=false, style="plain", axis="x")

    tight_layout()
    savefig(path; dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    return path
end

function _write_multivar_gain_tilt_plot(path, result_bundle, shaped)
    λ_nm = _wavelength_axis_nm(result_bundle.sim)
    A_opt = result_bundle.outcome.A_opt
    slope = Float64(get(result_bundle.outcome, :gain_tilt_opt, 0.0))

    fig, axs = subplots(2, 1, figsize=(10, 7), sharex=true)
    axs[1].plot(λ_nm, fftshift(A_opt[:, 1]), color="#1f4e5f", linewidth=1.4)
    axs[1].axhline(1.0, color="gray", linestyle="--", alpha=0.6)
    axs[1].set_ylabel("Transmission")
    axs[1].set_title("Gain-tilt control")
    Amin, Amax = extrema(A_opt)
    axs[1].annotate(
        @sprintf("slope=%.4f, A in [%.3f, %.3f]", slope, Amin, Amax),
        xy=(0.02, 0.92),
        xycoords="axes fraction",
        va="top",
        fontsize=9,
        bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
    )

    axs[2].plot(λ_nm, _spectral_db(result_bundle.uω0), label="unshaped input", alpha=0.8)
    axs[2].plot(λ_nm, _spectral_db(shaped), label="gain-tilted input", alpha=0.8)
    axs[2].set_xlabel("Wavelength [nm]")
    axs[2].set_ylabel("Power [dB]")
    axs[2].set_ylim(-60, 3)
    axs[2].legend(fontsize=8)
    axs[2].ticklabel_format(useOffset=false, style="plain", axis="x")

    tight_layout()
    savefig(path; dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    return path
end

function write_multivar_variable_artifacts(spec, result_bundle)
    output_dir = dirname(String(result_bundle.save_prefix))
    mkpath(output_dir)
    tag = _multivar_artifact_tag(result_bundle.save_prefix)
    outcome = result_bundle.outcome
    shaped = _multivar_shaped_input(result_bundle)

    paths = Dict{Symbol,String}()

    if :amplitude in spec.controls.variables
        amplitude_path = joinpath(output_dir, "$(tag)_amplitude_mask.png")
        _write_multivar_amplitude_plot(amplitude_path, result_bundle, shaped)
        paths[:amplitude_mask] = amplitude_path
        paths[:shaped_input_spectrum] = amplitude_path
    end

    if :gain_tilt in spec.controls.variables
        gain_tilt_path = joinpath(output_dir, "$(tag)_gain_tilt_profile.png")
        _write_multivar_gain_tilt_plot(gain_tilt_path, result_bundle, shaped)
        paths[:gain_tilt_profile] = gain_tilt_path
    end

    E_ref = Float64(outcome.E_ref)
    E_opt = Float64(outcome.E_opt)
    E_unshaped = Float64(sum(abs2, result_bundle.uω0))
    E_shaped = Float64(sum(abs2, shaped))

    if :amplitude in spec.controls.variables || :energy in spec.controls.variables || :gain_tilt in spec.controls.variables
        energy_path = joinpath(output_dir, "$(tag)_energy_metrics.json")
        energy_payload = Dict{String,Any}(
            "schema_version" => "multivar_energy_metrics_v1",
            "variables" => [String(v) for v in spec.controls.variables],
            "gain_tilt_opt" => Float64(get(outcome, :gain_tilt_opt, 0.0)),
            "E_ref" => E_ref,
            "E_opt" => E_opt,
            "E_unshaped_input" => E_unshaped,
            "E_shaped_input" => E_shaped,
            "energy_scale_alpha" => Float64(get(outcome.diagnostics, :alpha, sqrt(E_opt / E_ref))),
            "E_opt_over_E_ref" => _safe_ratio(E_opt, E_ref),
            "shaped_over_unshaped_input_energy" => _safe_ratio(E_shaped, E_unshaped),
            "amplitude_min" => Float64(minimum(outcome.A_opt)),
            "amplitude_max" => Float64(maximum(outcome.A_opt)),
            "amplitude_mean" => Float64(mean(outcome.A_opt)),
        )
        _write_json(energy_path, energy_payload)
        paths[:energy_throughput] = energy_path
        paths[:energy_scale] = energy_path
    end

    if :energy in spec.controls.variables
        pulse_path = joinpath(output_dir, "$(tag)_pulse_metrics.json")
        pulse_payload = Dict{String,Any}(
            "schema_version" => "multivar_pulse_metrics_v1",
            "variables" => [String(v) for v in spec.controls.variables],
            "peak_power_unshaped_input" => _peak_power(result_bundle.uω0),
            "peak_power_shaped_input" => _peak_power(shaped),
            "E_ref" => E_ref,
            "E_opt" => E_opt,
            "energy_scale_alpha" => Float64(get(outcome.diagnostics, :alpha, sqrt(E_opt / E_ref))),
        )
        _write_json(pulse_path, pulse_payload)
        paths[:peak_power] = pulse_path
    end

    return (
        complete = true,
        paths = paths,
    )
end

end # include guard
