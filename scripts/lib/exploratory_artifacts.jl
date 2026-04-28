"""
Generic exploratory artifacts for front-layer research runs.

These artifacts are intentionally modest. They give a researcher a consistent
first look at novel objectives or variables without replacing explicit
physics-specific diagnostics.
"""

if !(@isdefined _EXPLORATORY_ARTIFACTS_JL_LOADED)
const _EXPLORATORY_ARTIFACTS_JL_LOADED = true

using FFTW
using JLD2
using JSON3
using PyPlot
using Statistics

include(joinpath(@__DIR__, "common.jl"))

if !(@isdefined C_NM_THZ)
const C_NM_THZ = 299792.458
end

function _explore_get(object, name::Symbol, default=nothing)
    if object isa AbstractDict
        if haskey(object, String(name))
            return object[String(name)]
        elseif haskey(object, name)
            return object[name]
        end
        return default
    end
    return hasproperty(object, name) ? getproperty(object, name) : default
end

function _explore_sim_get(sim, key::String, default)
    if sim isa AbstractDict
        haskey(sim, key) && return sim[key]
        sym = Symbol(key)
        haskey(sim, sym) && return sim[sym]
    end
    return default
end

function _explore_tag(save_prefix::AbstractString)
    return basename(String(save_prefix))
end

function _explore_saved_payload(result_bundle)
    artifact_path = _explore_get(result_bundle, :artifact_path, nothing)
    artifact_path === nothing && return nothing
    isfile(String(artifact_path)) || return nothing
    try
        return JLD2.load(String(artifact_path))
    catch
        return nothing
    end
end

function _explore_phase(result_bundle)
    outcome = _explore_get(result_bundle, :outcome, nothing)
    result = _explore_get(result_bundle, :result, nothing)
    saved = _explore_saved_payload(result_bundle)
    phi = outcome === nothing ? _explore_get(result, :phi_opt, nothing) : _explore_get(outcome, :φ_opt, nothing)
    phi === nothing && outcome !== nothing && (phi = _explore_get(outcome, :phi_opt, nothing))
    phi === nothing && (phi = _explore_get(saved, :phi_opt, nothing))
    phi === nothing && return nothing
    return Array{Float64}(phi)
end

function _explore_amplitude(result_bundle)
    outcome = _explore_get(result_bundle, :outcome, nothing)
    saved = _explore_saved_payload(result_bundle)
    outcome === nothing && return nothing
    amplitude = _explore_get(outcome, :A_opt, nothing)
    amplitude === nothing && (amplitude = _explore_get(saved, :A_opt, nothing))
    amplitude === nothing && return nothing
    alpha = Float64(_explore_get(_explore_get(outcome, :diagnostics, Dict()), :alpha, 1.0))
    return alpha .* Array{Float64}(amplitude)
end

function _explore_shaped_input(result_bundle)
    uω0 = Array{ComplexF64}(_explore_get(result_bundle, :uω0))
    phi = _explore_phase(result_bundle)
    shaped = phi === nothing ? copy(uω0) : @. uω0 * cis(phi)
    amplitude = _explore_amplitude(result_bundle)
    amplitude === nothing || (shaped = shaped .* amplitude)
    return shaped
end

function _explore_trace(result_bundle)
    result = _explore_get(result_bundle, :result, nothing)
    outcome = _explore_get(result_bundle, :outcome, nothing)
    saved = _explore_saved_payload(result_bundle)
    for source in (result, outcome, saved)
        source === nothing && continue
        for field in (:convergence_history, :J_history, :history, :f_trace)
            trace = _explore_get(source, field, nothing)
            trace === nothing && continue
            return Float64.(collect(trace))
        end
    end
    return Float64[]
end

function _explore_energy_window(
    power::AbstractVector{<:Real};
    low_quantile::Float64=0.001,
    high_quantile::Float64=0.999,
    margin_fraction::Float64=0.20,
)
    n = length(power)
    n == 0 && return (lo = 1, hi = 1, width = 1, source = :empty, time_range = :auto)
    total = sum(power)
    if !(isfinite(total) && total > 0)
        return (lo = 1, hi = n, width = n, source = :full_range, time_range = :auto)
    end

    cumulative = cumsum(Float64.(power)) ./ total
    lo = findfirst(x -> x >= low_quantile, cumulative)
    hi = findfirst(x -> x >= high_quantile, cumulative)
    lo === nothing && (lo = 1)
    hi === nothing && (hi = n)
    margin = max(2, round(Int, margin_fraction * max(1, hi - lo + 1)))
    lo = max(1, lo - margin)
    hi = min(n, hi + margin)
    return (lo = lo, hi = hi, width = hi - lo + 1, source = :energy_window, time_range = :auto)
end

function _explore_axis(sim, n::Int)
    Δt = Float64(_explore_sim_get(sim, "Δt", 1.0))
    centered = collect(0:(n - 1)) .- floor((n - 1) / 2)
    return centered .* Δt
end

function _explore_wavelength_axis(sim, n::Int)
    f0 = Float64(_explore_sim_get(sim, "f0", NaN))
    Δt = Float64(_explore_sim_get(sim, "Δt", NaN))
    if !(isfinite(f0) && isfinite(Δt) && Δt > 0)
        return collect(1:n), "Frequency bin"
    end
    f_shifted = f0 .+ fftshift(FFTW.fftfreq(n, 1 / Δt))
    if any(f -> !(isfinite(f) && f > 0), f_shifted)
        return collect(1:n), "Frequency bin"
    end
    return C_NM_THZ ./ f_shifted, "Wavelength [nm]"
end

function _explore_spectral_db(field)
    spectrum = abs2.(fftshift(field[:, 1]))
    ref = max(maximum(spectrum), eps())
    return 10 .* log10.(spectrum ./ ref .+ 1e-30)
end

function _explore_temporal_power(field)
    return abs2.(ifft(field[:, 1]))
end

function _explore_plot_contract(spec)
    if hasproperty(spec, :plots)
        return spec.plots
    end
    return (
        temporal_pulse = (
            time_range = :auto,
            normalize = false,
            energy_low = 0.001,
            energy_high = 0.999,
            margin_fraction = 0.20,
        ),
        spectrum = (
            dynamic_range_dB = 70.0,
        ),
    )
end

function _explore_temporal_zoom(spec, sim, power::AbstractVector{<:Real})
    plots = _explore_plot_contract(spec)
    temporal = plots.temporal_pulse
    n = length(power)
    if temporal.time_range !== :auto
        t_axis = _explore_axis(sim, n)
        lo_t, hi_t = temporal.time_range
        indices = findall(t -> lo_t <= t <= hi_t, t_axis)
        if !isempty(indices)
            lo = first(indices)
            hi = last(indices)
            return (
                lo = lo,
                hi = hi,
                width = hi - lo + 1,
                source = :config_time_range,
                time_range = (Float64(lo_t), Float64(hi_t)),
            )
        end
    end
    return _explore_energy_window(
        power;
        low_quantile = Float64(temporal.energy_low),
        high_quantile = Float64(temporal.energy_high),
        margin_fraction = Float64(temporal.margin_fraction),
    )
end

function _explore_normalized_power(power::AbstractVector{<:Real}, normalize::Bool)
    values = Float64.(power)
    normalize || return values
    ref = maximum(values)
    isfinite(ref) && ref > 0 || return values
    return values ./ ref
end

function _explore_variable_summary(spec, result_bundle)
    phi = _explore_phase(result_bundle)
    amplitude = _explore_amplitude(result_bundle)
    outcome = _explore_get(result_bundle, :outcome, nothing)

    summary = Dict{String,Any}()
    if phi !== nothing
        summary["phase"] = Dict{String,Any}(
            "min_rad" => Float64(minimum(phi)),
            "max_rad" => Float64(maximum(phi)),
            "rms_rad" => Float64(sqrt(mean(abs2, phi))),
        )
    end
    if amplitude !== nothing
        summary["amplitude"] = Dict{String,Any}(
            "min" => Float64(minimum(amplitude)),
            "max" => Float64(maximum(amplitude)),
            "mean" => Float64(mean(amplitude)),
        )
    end
    if outcome !== nothing
        gain_tilt = _explore_get(outcome, :gain_tilt_opt, nothing)
        gain_tilt === nothing || (summary["gain_tilt"] = Dict{String,Any}("value" => Float64(gain_tilt)))
        E_ref = _explore_get(outcome, :E_ref, nothing)
        E_opt = _explore_get(outcome, :E_opt, nothing)
        if E_ref !== nothing && E_opt !== nothing
            summary["energy"] = Dict{String,Any}(
                "E_ref" => Float64(E_ref),
                "E_opt" => Float64(E_opt),
                "E_opt_over_E_ref" => Float64(E_opt) / max(Float64(E_ref), eps()),
            )
        end
    end
    summary["declared_variables"] = [String(v) for v in spec.controls.variables]
    return summary
end

function _explore_format_number(value)
    value isa Real || return string(value)
    return string(round(Float64(value); sigdigits=4))
end

function _explore_variable_summary_lines(variable_summary)
    lines = String[]
    for (key, value) in sort!(collect(variable_summary); by = first)
        key == "declared_variables" && continue
        if value isa AbstractDict
            parts = String[]
            for (subkey, subvalue) in sort!(collect(value); by = first)
                push!(parts, string(subkey, "=", _explore_format_number(subvalue)))
            end
            push!(lines, string(key, ": ", join(parts, ", ")))
        else
            push!(lines, string(key, ": ", _explore_format_number(value)))
        end
    end
    return lines
end

function _explore_metric_summary(result_bundle)
    result = _explore_get(result_bundle, :result, nothing)
    outcome = _explore_get(result_bundle, :outcome, nothing)
    saved = _explore_saved_payload(result_bundle)

    metrics = Dict{String,Any}()
    for source in (outcome, result, saved)
        source === nothing && continue
        for field in (:J_before, :J_after, :J_after_lin, :ΔJ_dB, :delta_J_dB, :iterations)
            haskey(metrics, String(field)) && continue
            value = _explore_get(source, field, nothing)
            value === nothing && continue
            metrics[String(field)] = value isa Integer ? Int(value) : Float64(value)
        end
    end
    return metrics
end

function _write_exploratory_summary(path::AbstractString, spec, result_bundle, zoom)
    trace = _explore_trace(result_bundle)
    plots = _explore_plot_contract(spec)
    payload = Dict{String,Any}(
        "schema_version" => "exploratory_artifacts_v1",
        "config" => Dict{String,Any}(
            "id" => spec.id,
            "maturity" => spec.maturity,
        ),
        "problem" => Dict{String,Any}(
            "regime" => string(spec.problem.regime),
            "preset" => string(spec.problem.preset),
            "L_fiber" => spec.problem.L_fiber,
            "P_cont" => spec.problem.P_cont,
            "Nt" => spec.problem.Nt,
            "time_window" => spec.problem.time_window,
        ),
        "controls" => Dict{String,Any}(
            "variables" => [String(v) for v in spec.controls.variables],
            "parameterization" => string(spec.controls.parameterization),
        ),
        "objective" => Dict{String,Any}(
            "kind" => string(spec.objective.kind),
            "log_cost" => spec.objective.log_cost,
        ),
        "solver" => Dict{String,Any}(
            "kind" => string(spec.solver.kind),
            "max_iter" => spec.solver.max_iter,
        ),
        "metrics" => _explore_metric_summary(result_bundle),
        "trace" => Dict{String,Any}(
            "points" => length(trace),
            "first" => isempty(trace) ? nothing : first(trace),
            "last" => isempty(trace) ? nothing : last(trace),
        ),
        "variables" => _explore_variable_summary(spec, result_bundle),
        "zoom" => Dict{String,Any}(
            "time_window_start_index" => zoom.lo,
            "time_window_end_index" => zoom.hi,
            "time_window_samples" => zoom.width,
            "source" => String(zoom.source),
            "time_range" => zoom.time_range === :auto ? "auto" : [zoom.time_range[1], zoom.time_range[2]],
        ),
        "plots" => Dict{String,Any}(
            "temporal_pulse" => Dict{String,Any}(
                "time_range" => plots.temporal_pulse.time_range === :auto ? "auto" : [plots.temporal_pulse.time_range[1], plots.temporal_pulse.time_range[2]],
                "normalize" => plots.temporal_pulse.normalize,
                "energy_low" => plots.temporal_pulse.energy_low,
                "energy_high" => plots.temporal_pulse.energy_high,
                "margin_fraction" => plots.temporal_pulse.margin_fraction,
            ),
            "spectrum" => Dict{String,Any}(
                "dynamic_range_dB" => plots.spectrum.dynamic_range_dB,
            ),
        ),
    )
    open(path, "w") do io
        JSON3.pretty(io, payload)
    end
    return path
end

function _write_exploratory_overview(path::AbstractString, spec, result_bundle, zoom)
    uω0 = Array{ComplexF64}(_explore_get(result_bundle, :uω0))
    shaped = _explore_shaped_input(result_bundle)
    sim = _explore_get(result_bundle, :sim, Dict{String,Any}())
    n = size(uω0, 1)
    x_spec, x_spec_label = _explore_wavelength_axis(sim, n)

    unshaped_t = _explore_temporal_power(uω0)
    shaped_t = _explore_temporal_power(shaped)
    t_axis = _explore_axis(sim, n)
    trace = _explore_trace(result_bundle)
    variable_summary = _explore_variable_summary(spec, result_bundle)
    plots = _explore_plot_contract(spec)
    temporal_normalize = Bool(plots.temporal_pulse.normalize)

    fig, axs = subplots(2, 2, figsize=(12, 8))

    axs[1, 1].plot(x_spec, _explore_spectral_db(uω0), label="input", alpha=0.85)
    axs[1, 1].plot(x_spec, _explore_spectral_db(shaped), label="shaped", alpha=0.85)
    axs[1, 1].set_title("Spectrum")
    axs[1, 1].set_xlabel(x_spec_label)
    axs[1, 1].set_ylabel("Power [dB rel.]")
    axs[1, 1].set_ylim(-Float64(plots.spectrum.dynamic_range_dB), 5)
    axs[1, 1].legend(fontsize=8)
    axs[1, 1].ticklabel_format(useOffset=false, style="plain", axis="x")

    zoom_range = zoom.lo:zoom.hi
    axs[1, 2].plot(t_axis[zoom_range], _explore_normalized_power(unshaped_t[zoom_range], temporal_normalize), label="input", alpha=0.85)
    axs[1, 2].plot(t_axis[zoom_range], _explore_normalized_power(shaped_t[zoom_range], temporal_normalize), label="shaped", alpha=0.85)
    axs[1, 2].set_title("Temporal Pulse")
    axs[1, 2].set_xlabel("Time [simulation units]")
    axs[1, 2].set_ylabel(temporal_normalize ? "Power [norm.]" : "Power [arb.]")
    axs[1, 2].legend(fontsize=8)

    if isempty(trace)
        axs[2, 1].text(0.5, 0.5, "No objective trace stored", ha="center", va="center")
        axs[2, 1].set_axis_off()
    else
        axs[2, 1].plot(1:length(trace), trace, marker="o", linewidth=1.2, markersize=3)
        axs[2, 1].set_title("Objective Trace")
        axs[2, 1].set_xlabel("Stored trace index")
        axs[2, 1].set_ylabel("Objective")
        axs[2, 1].grid(alpha=0.25)
    end

    lines = String[
        "Config: $(spec.id)",
        "Objective: $(spec.objective.kind)",
        "Variables: $(join(string.(spec.controls.variables), ", "))",
    ]
    append!(lines, _explore_variable_summary_lines(variable_summary))
    axs[2, 2].text(0.02, 0.98, join(lines, "\n"), va="top", ha="left", fontsize=9,
        bbox=Dict("boxstyle" => "round,pad=0.4", "facecolor" => "white", "alpha" => 0.9))
    axs[2, 2].set_axis_off()

    fig.suptitle("Exploratory Run Overview", fontsize=13)
    tight_layout()
    savefig(path; dpi=250, bbox_inches="tight")
    PyPlot.close(fig)
    return path
end

function write_exploratory_artifacts(spec, result_bundle)
    hooks = exploratory_artifact_hooks(spec)
    isempty(hooks) && return (complete = true, paths = Dict{Symbol,String}())

    output_dir = dirname(String(result_bundle.save_prefix))
    mkpath(output_dir)
    tag = _explore_tag(result_bundle.save_prefix)
    shaped = _explore_shaped_input(result_bundle)
    shaped_t = _explore_temporal_power(shaped)
    sim = _explore_get(result_bundle, :sim, Dict{String,Any}())
    zoom = _explore_temporal_zoom(spec, sim, vec(shaped_t))

    paths = Dict{Symbol,String}()
    summary_path = joinpath(output_dir, "$(tag)_explore_summary.json")
    overview_path = joinpath(output_dir, "$(tag)_explore_overview.png")
    _write_exploratory_summary(summary_path, spec, result_bundle, zoom)
    _write_exploratory_overview(overview_path, spec, result_bundle, zoom)
    paths[:exploratory_summary] = summary_path
    paths[:exploratory_overview] = overview_path
    return (
        complete = all(isfile, values(paths)),
        paths = paths,
    )
end

end # include guard
