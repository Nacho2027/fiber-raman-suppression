"""
Export one saved run into an experiment-facing handoff bundle.

Usage:
    julia --project=. scripts/canonical/export_run.jl <run-dir-or-artifact> [output-dir]
"""

using Dates
using FFTW
using JSON3
using JLD2
using Printf
using Statistics
using MultiModeNoise

include(joinpath(@__DIR__, "..", "lib", "run_artifacts.jl"))

const EXPORT_SCHEMA_VERSION = "1.0"
const C_NM_THZ = 299792.458
const AMPLITUDE_HARDWARE_POLICY = "loss_only_normalized_to_max"

function _namedtuple_from_string_dict(payload)
    pairs = Pair{Symbol,Any}[Symbol(k) => v for (k, v) in payload]
    return (; pairs...)
end

function _multivar_slm_sidecar_path(artifact::AbstractString)
    endswith(artifact, "_result.jld2") || return nothing
    candidate = replace(artifact, "_result.jld2" => "_slm.json")
    return isfile(candidate) ? candidate : nothing
end

function _load_export_run(artifact::AbstractString)
    try
        return MultiModeNoise.load_run(artifact)
    catch err
        sidecar_path = _multivar_slm_sidecar_path(artifact)
        sidecar_path === nothing && rethrow()
        payload = JLD2.load(artifact)
        named = _namedtuple_from_string_dict(payload)
        sidecar = JSON3.read(read(sidecar_path, String))
        pairs = Pair{Symbol,Any}[name => getproperty(named, name) for name in propertynames(named)]
        push!(pairs, :sidecar => sidecar)
        return (; pairs...)
    end
end

function _manual_unwrap_export(phi::AbstractVector{<:Real})
    out = collect(Float64, phi)
    for i in 2:length(out)
        delta = out[i] - out[i - 1]
        if delta > π
            out[i:end] .-= 2π
        elseif delta < -π
            out[i:end] .+= 2π
        end
    end
    return out
end

function _group_delay_fs(phi_unwrapped::AbstractVector{<:Real}, dω_rad_per_ps::Real)
    n = length(phi_unwrapped)
    τ = zeros(Float64, n)
    if n == 1
        return τ
    end
    τ[1] = (phi_unwrapped[2] - phi_unwrapped[1]) / dω_rad_per_ps
    τ[end] = (phi_unwrapped[end] - phi_unwrapped[end - 1]) / dω_rad_per_ps
    for i in 2:(n - 1)
        τ[i] = (phi_unwrapped[i + 1] - phi_unwrapped[i - 1]) / (2dω_rad_per_ps)
    end
    return τ .* 1e3
end

function _phase_axes(loaded)
    Nt = Int(loaded.Nt)
    Δt_ps = Float64(loaded.sim_Dt)
    f0_THz = Float64(loaded.sim_omega0) / (2π)
    rel_f_THz = FFTW.fftfreq(Nt, 1 / Δt_ps)
    abs_f_THz = rel_f_THz .+ f0_THz
    λ_nm = similar(abs_f_THz)
    for i in eachindex(abs_f_THz)
        λ_nm[i] = abs(abs_f_THz[i]) > eps() ? C_NM_THZ / abs_f_THz[i] : Inf
    end
    dω = 2π / (Nt * Δt_ps)
    return rel_f_THz, abs_f_THz, λ_nm, dω
end

function _loaded_vector(loaded, field::Symbol, n::Integer)
    hasproperty(loaded, field) || return nothing
    values = collect(Float64, vec(getproperty(loaded, field)))
    length(values) == n || throw(ArgumentError(
        "export field `$field` has $(length(values)) entries, expected $n"))
    return values
end

function _write_amplitude_profile(output_dir::AbstractString,
                                  loaded,
                                  rel_f_THz,
                                  abs_f_THz,
                                  λ_nm)
    n = Int(loaded.Nt)
    amp = _loaded_vector(loaded, :amp_opt, n)
    if amp === nothing
        return nothing, Dict{String,Any}(
            "present" => false,
            "reason" => "source artifact has no amp_opt field",
        )
    end

    amp_max = maximum(amp)
    amp_min = minimum(amp)
    amp_max > 0 || throw(ArgumentError(
        "amp_opt cannot be exported with loss-only normalization because max amplitude is non-positive"))
    normalized = amp ./ amp_max

    amplitude_csv = joinpath(output_dir, "amplitude_profile.csv")
    open(amplitude_csv, "w") do io
        println(io, "index,frequency_offset_THz,absolute_frequency_THz,wavelength_nm,amplitude_multiplier,normalized_transmission_loss_only")
        for i in eachindex(amp)
            println(io, @sprintf("%d,%.12f,%.12f,%.12f,%.12f,%.12f",
                i,
                rel_f_THz[i],
                abs_f_THz[i],
                λ_nm[i],
                amp[i],
                normalized[i]))
        end
    end

    meta = Dict{String,Any}(
        "present" => true,
        "csv" => basename(amplitude_csv),
        "storage_key" => "amp_opt",
        "units" => "dimensionless multiplier",
        "hardware_policy" => AMPLITUDE_HARDWARE_POLICY,
        "policy_description" => "The simulated multiplier is normalized by its maximum value so a loss-only shaper receives transmission values in [0, 1]. The required global attenuation factor is recorded separately.",
        "global_attenuation_factor" => 1 / amp_max,
        "min_multiplier" => amp_min,
        "max_multiplier" => amp_max,
        "mean_multiplier" => mean(amp),
        "std_multiplier" => std(amp),
        "values_above_unity" => any(>(1.0), amp),
        "normalized_transmission_min" => minimum(normalized),
        "normalized_transmission_max" => maximum(normalized),
    )
    return amplitude_csv, meta
end

function _csv_numeric_column(path::AbstractString, column::AbstractString)
    lines = readlines(path)
    isempty(lines) && throw(ArgumentError("empty CSV: $path"))
    header = split(first(lines), ",")
    idx = findfirst(==(column), header)
    idx === nothing && throw(ArgumentError("CSV `$path` has no `$column` column"))
    values = Float64[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ",")
        length(fields) >= idx || throw(ArgumentError("short CSV row in `$path`: $line"))
        push!(values, parse(Float64, fields[idx]))
    end
    return values
end

function _roundtrip_validation_report(output_dir::AbstractString,
                                      export_meta::Dict{String,Any})
    missing = String[]
    checks = String[]

    phase_csv = joinpath(output_dir, String(export_meta["phase_csv"]))
    push!(checks, "phase_csv_exists")
    isfile(phase_csv) || push!(missing, phase_csv)
    phase_rows = isfile(phase_csv) ? max(length(readlines(phase_csv)) - 1, 0) : 0

    amplitude_meta = export_meta["amplitude"]
    amplitude_rows = 0
    normalized_min = nothing
    normalized_max = nothing
    max_roundtrip_error = nothing
    if Bool(amplitude_meta["present"])
        amplitude_csv = joinpath(output_dir, String(amplitude_meta["csv"]))
        push!(checks, "amplitude_csv_exists")
        isfile(amplitude_csv) || push!(missing, amplitude_csv)
        if isfile(amplitude_csv)
            amp = _csv_numeric_column(amplitude_csv, "amplitude_multiplier")
            normalized = _csv_numeric_column(amplitude_csv, "normalized_transmission_loss_only")
            amplitude_rows = length(amp)
            if length(normalized) != amplitude_rows
                push!(missing, string(amplitude_csv, " normalized row count"))
            elseif !isempty(amp)
                attenuation = Float64(amplitude_meta["global_attenuation_factor"])
                reconstructed = normalized ./ attenuation
                max_roundtrip_error = maximum(abs.(reconstructed .- amp))
                normalized_min = minimum(normalized)
                normalized_max = maximum(normalized)
                if normalized_min < -1e-12 || normalized_max > 1.0 + 1e-12
                    push!(missing, string(amplitude_csv, " normalized transmission bounds"))
                end
                if max_roundtrip_error > 1e-9
                    push!(missing, string(amplitude_csv, " amplitude roundtrip tolerance"))
                end
            end
        end
    end

    return Dict{String,Any}(
        "complete" => isempty(missing),
        "generated_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
        "checks" => checks,
        "missing_or_invalid" => missing,
        "phase_rows" => phase_rows,
        "amplitude_rows" => amplitude_rows,
        "amplitude_present" => Bool(amplitude_meta["present"]),
        "hardware_policy" => Bool(amplitude_meta["present"]) ? amplitude_meta["hardware_policy"] : nothing,
        "normalized_transmission_min" => normalized_min,
        "normalized_transmission_max" => normalized_max,
        "max_amplitude_roundtrip_error" => max_roundtrip_error,
    )
end

function export_run_bundle(input_path::AbstractString, output_dir::AbstractString)
    artifact = resolve_run_artifact_path(input_path)
    loaded = _load_export_run(artifact)
    mkpath(output_dir)

    phi = vec(Float64.(loaded.phi_opt))
    phi_unwrapped = _manual_unwrap_export(phi)
    rel_f_THz, abs_f_THz, λ_nm, dω = _phase_axes(loaded)
    τ_fs = _group_delay_fs(phi_unwrapped, dω)
    amplitude_csv, amplitude_meta = _write_amplitude_profile(
        output_dir,
        loaded,
        rel_f_THz,
        abs_f_THz,
        λ_nm,
    )

    phase_csv = joinpath(output_dir, "phase_profile.csv")
    open(phase_csv, "w") do io
        println(io, "index,frequency_offset_THz,absolute_frequency_THz,wavelength_nm,phase_wrapped_rad,phase_unwrapped_rad,group_delay_fs")
        for i in eachindex(phi)
            println(io, @sprintf("%d,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f",
                i,
                rel_f_THz[i],
                abs_f_THz[i],
                λ_nm[i],
                phi[i],
                phi_unwrapped[i],
                τ_fs[i]))
        end
    end

    source_dir = dirname(artifact)
    export_meta = Dict(
        "export_schema_version" => EXPORT_SCHEMA_VERSION,
        "generated_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
        "source_artifact" => artifact,
        "source_dir" => source_dir,
        "fiber_name" => getproperty(loaded, :fiber_name),
        "L_m" => getproperty(loaded, :L_m),
        "P_cont_W" => getproperty(loaded, :P_cont_W),
        "Nt" => Int(loaded.Nt),
        "time_window_ps" => Float64(loaded.time_window_ps),
        "converged" => getproperty(loaded, :converged),
        "iterations" => getproperty(loaded, :iterations),
        "J_initial_dB" => MultiModeNoise.lin_to_dB(getproperty(loaded, :J_before)),
        "J_final_dB" => MultiModeNoise.lin_to_dB(getproperty(loaded, :J_after)),
        "sidecar" => Dict{String,Any}(String(k) => v for (k, v) in pairs(loaded.sidecar)),
        "phase_csv" => basename(phase_csv),
        "amplitude" => amplitude_meta,
        "roundtrip_validation_json" => "roundtrip_validation.json",
    )

    metadata_json = joinpath(output_dir, "metadata.json")
    open(metadata_json, "w") do io
        JSON3.pretty(io, export_meta)
    end

    source_config = joinpath(source_dir, "run_config.toml")
    if isfile(source_config)
        cp(source_config, joinpath(output_dir, "source_run_config.toml"); force=true)
    end

    readme_path = joinpath(output_dir, "README.md")
    open(readme_path, "w") do io
        println(io, "# Experimental Handoff Bundle")
        println(io)
        println(io, "- Source artifact: `", artifact, "`")
        println(io, "- Fiber: `", loaded.fiber_name, "`")
        println(io, "- L: `", loaded.L_m, " m`")
        println(io, "- P: `", loaded.P_cont_W, " W`")
        println(io, "- Final objective: `", @sprintf("%.2f dB", MultiModeNoise.lin_to_dB(loaded.J_after)), "`")
        println(io, "- Converged: `", loaded.converged, "` in `", loaded.iterations, "` iterations")
        println(io)
        println(io, "Files:")
        println(io, "- `phase_profile.csv` — wavelength/frequency grid with wrapped phase, unwrapped phase, and group delay")
        if amplitude_csv !== nothing
            println(io, "- `amplitude_profile.csv` — simulation amplitude multiplier and loss-only normalized transmission")
            println(io, "- Amplitude hardware policy: `", AMPLITUDE_HARDWARE_POLICY, "`")
            println(io, "- Global attenuation factor for loss-only normalization: `",
                @sprintf("%.12f", amplitude_meta["global_attenuation_factor"]), "`")
        end
        println(io, "- `metadata.json` — provenance and scalar summary")
        println(io, "- `roundtrip_validation.json` — export reload and shape/bounds validation")
        if isfile(source_config)
            println(io, "- `source_run_config.toml` — approved run config copied from the source bundle")
        end
    end

    roundtrip_json = joinpath(output_dir, "roundtrip_validation.json")
    roundtrip_report = _roundtrip_validation_report(output_dir, export_meta)
    open(roundtrip_json, "w") do io
        JSON3.pretty(io, roundtrip_report)
    end

    return (
        source_artifact = artifact,
        output_dir = output_dir,
        phase_csv = phase_csv,
        amplitude_csv = amplitude_csv,
        metadata_json = metadata_json,
        roundtrip_json = roundtrip_json,
        readme = readme_path,
    )
end

function export_run_main(args=ARGS)
    if !(length(args) in (1, 2))
        error("usage: scripts/canonical/export_run.jl <run-dir-or-artifact> [output-dir]")
    end

    artifact = resolve_run_artifact_path(args[1])
    default_dir = joinpath(dirname(artifact), "export_handoff")
    output_dir = length(args) == 2 ? args[2] : default_dir
    exported = export_run_bundle(artifact, output_dir)
    @info "Exported handoff bundle" output_dir=exported.output_dir source=exported.source_artifact
    return exported
end

if abspath(PROGRAM_FILE) == @__FILE__
    export_run_main(ARGS)
end
