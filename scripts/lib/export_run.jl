"""
Export one saved run into an experiment-facing handoff bundle.

Usage:
    julia --project=. scripts/canonical/export_run.jl <run-dir-or-artifact> [output-dir]
"""

using Dates
using Printf

if !(@isdefined _EXPORT_RUN_JL_LOADED)
const _EXPORT_RUN_JL_LOADED = true

using FFTW
using JSON3
using JLD2
using Statistics
using FiberLab

include(joinpath(@__DIR__, "run_artifacts.jl"))
include(joinpath(@__DIR__, "export_integrity.jl"))

const EXPORT_SCHEMA_VERSION = "2.0"
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
        return FiberLab.load_run(artifact)
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

function _loaded_export_value(loaded, key::Symbol, default=nothing)
    hasproperty(loaded, key) && return getproperty(loaded, key)
    return default
end

function _sidecar_export_value(loaded, key::AbstractString, default=nothing)
    sidecar = _loaded_export_value(loaded, :sidecar)
    sidecar === nothing && return default
    return _export_value(sidecar, key, default)
end

function _source_trust_report_path(loaded, source_dir::AbstractString)
    reported = _loaded_export_value(loaded, :trust_report_md)
    if reported !== nothing
        candidate = joinpath(source_dir, basename(String(reported)))
        isfile(candidate) && return candidate
    end
    candidates = sort(filter(readdir(source_dir; join=true)) do path
        name = lowercase(basename(path))
        isfile(path) && occursin("trust", name) &&
            lowercase(splitext(name)[2]) in (".md", ".json")
    end)
    return isempty(candidates) ? nothing : first(candidates)
end

function _copy_export_provenance(output_dir::AbstractString,
                                 loaded,
                                 source_dir::AbstractString)
    copied = Dict{String,Any}()
    integrity = Dict{String,Any}()

    source_config = joinpath(source_dir, "run_config.toml")
    source_manifest = joinpath(source_dir, "run_manifest.json")
    sources = (
        "source_config" => (isfile(source_config) ? source_config : nothing),
        "source_trust_report" => _source_trust_report_path(loaded, source_dir),
        "source_run_manifest" => (isfile(source_manifest) ? source_manifest : nothing),
    )

    for (label, source) in sources
        source === nothing && continue
        extension = splitext(source)[2]
        destination_name = label == "source_config" ? "source_run_config.toml" :
            label == "source_trust_report" ? string("source_trust_report", extension) :
            "source_run_manifest.json"
        destination = joinpath(output_dir, destination_name)
        source_sha256 = export_file_sha256(source)
        cp(source, destination; force=true)
        export_file_sha256(destination) == source_sha256 || throw(ArgumentError(
            "copied provenance digest mismatch for `$label`"))
        copied[label] = destination_name
        integrity[label] = export_integrity_entry(output_dir, destination)
    end
    return copied, integrity
end

function _source_manifest_scalars(source_dir::AbstractString)
    path = joinpath(source_dir, "run_manifest.json")
    isfile(path) || return (
        config_id = nothing,
        run_context = nothing,
        run_command = nothing,
        git_commit = nothing,
    )
    manifest = try
        JSON3.read(read(path, String))
    catch
        return (
            config_id = nothing,
            run_context = nothing,
            run_command = nothing,
            git_commit = nothing,
        )
    end
    config = _export_value(manifest, "config", Dict{String,Any}())
    git = _export_value(manifest, "git", Dict{String,Any}())
    return (
        config_id = _export_value(config, "id"),
        run_context = _export_value(manifest, "run_context"),
        run_command = _export_value(manifest, "command"),
        git_commit = _export_value(git, "head", _export_value(git, "commit")),
    )
end

function _source_trust_verdict(loaded)
    report = _loaded_export_value(loaded, :trust_report)
    report === nothing && return nothing
    verdict = _export_value(report, "overall_verdict")
    verdict !== nothing && return String(verdict)
    passed = _export_value(report, "pass")
    return passed === nothing ? nothing : (Bool(passed) ? "PASS" : "FAIL")
end

function _manual_unwrap_export(phi::AbstractVector{<:Real})
    wrapped = collect(Float64, phi)
    out = similar(wrapped)
    isempty(wrapped) && return out
    out[1] = wrapped[1]
    for i in 2:length(out)
        delta = wrapped[i] - wrapped[i - 1]
        delta -= 2π * round(delta / (2π))
        out[i] = out[i - 1] + delta
    end
    return out
end

function _phase_export_data(phi_storage::AbstractVector{<:Real})
    phase_centered = FFTW.fftshift(collect(Float64, phi_storage))
    phase_wrapped = angle.(cis.(phase_centered))
    return (
        wrapped = phase_wrapped,
        unwrapped = _manual_unwrap_export(phase_wrapped),
    )
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
    rel_f_THz = FFTW.fftshift(FFTW.fftfreq(Nt, 1 / Δt_ps))
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
    amp_storage = _loaded_vector(loaded, :amp_opt, n)
    if amp_storage === nothing
        return nothing, Dict{String,Any}(
            "present" => false,
            "reason" => "source artifact has no amp_opt field",
        )
    end
    amp = FFTW.fftshift(amp_storage)

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
                                      export_meta::Dict{String,Any};
                                      source_artifact=nothing)
    missing = String[]
    checks = String[]

    phase_csv = joinpath(output_dir, String(export_meta["phase_csv"]))
    push!(checks, "phase_csv_exists")
    isfile(phase_csv) || push!(missing, basename(phase_csv))
    phase_rows = isfile(phase_csv) ? max(length(readlines(phase_csv)) - 1, 0) : 0

    amplitude_meta = export_meta["amplitude"]
    amplitude_rows = 0
    normalized_min = nothing
    normalized_max = nothing
    max_roundtrip_error = nothing
    if Bool(amplitude_meta["present"])
        amplitude_csv = joinpath(output_dir, String(amplitude_meta["csv"]))
        push!(checks, "amplitude_csv_exists")
        isfile(amplitude_csv) || push!(missing, basename(amplitude_csv))
        if isfile(amplitude_csv)
            amp = _csv_numeric_column(amplitude_csv, "amplitude_multiplier")
            normalized = _csv_numeric_column(amplitude_csv, "normalized_transmission_loss_only")
            amplitude_rows = length(amp)
            if length(normalized) != amplitude_rows
                push!(missing, string(basename(amplitude_csv), ":normalized_row_count"))
            elseif !isempty(amp)
                attenuation = Float64(amplitude_meta["global_attenuation_factor"])
                reconstructed = normalized ./ attenuation
                max_roundtrip_error = maximum(abs.(reconstructed .- amp))
                normalized_min = minimum(normalized)
                normalized_max = maximum(normalized)
                if normalized_min < -1e-12 || normalized_max > 1.0 + 1e-12
                    push!(missing, string(basename(amplitude_csv), ":normalized_transmission_bounds"))
                end
                if max_roundtrip_error > 1e-9
                    push!(missing, string(basename(amplitude_csv), ":amplitude_roundtrip_tolerance"))
                end
            end
        end
    end

    integrity = validate_export_handoff_integrity(
        output_dir;
        source_artifact=source_artifact,
    )
    append!(missing, ["integrity:$error" for error in integrity.errors])

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
        "integrity_complete" => integrity.complete,
        "integrity_checked" => collect(integrity.checked),
        "source_artifact_checked" => integrity.source_artifact_checked,
    )
end

function export_run_bundle(input_path::AbstractString, output_dir::AbstractString)
    artifact = resolve_run_artifact_path(input_path)
    loaded = _load_export_run(artifact)
    mkpath(output_dir)

    phi = _phase_export_data(vec(Float64.(loaded.phi_opt)))
    rel_f_THz, abs_f_THz, λ_nm, dω = _phase_axes(loaded)
    τ_fs = _group_delay_fs(phi.unwrapped, dω)
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
        for i in eachindex(phi.wrapped)
            println(io, @sprintf("%d,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f",
                i,
                rel_f_THz[i],
                abs_f_THz[i],
                λ_nm[i],
                phi.wrapped[i],
                phi.unwrapped[i],
                τ_fs[i]))
        end
    end

    source_dir = dirname(artifact)
    provenance, integrity = _copy_export_provenance(
        output_dir,
        loaded,
        source_dir,
    )
    integrity["phase_profile"] = export_integrity_entry(output_dir, phase_csv)
    if amplitude_csv !== nothing
        integrity["amplitude_profile"] = export_integrity_entry(output_dir, amplitude_csv)
    end
    manifest_scalars = _source_manifest_scalars(source_dir)
    source_artifact_sha256 = export_file_sha256(artifact)
    export_meta = Dict(
        "export_schema_version" => EXPORT_SCHEMA_VERSION,
        "generated_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
        "source_artifact" => basename(artifact),
        "source_artifact_included" => false,
        "source_artifact_sha256" => source_artifact_sha256,
        "source_result_schema" => _sidecar_export_value(loaded, "schema_version"),
        "source_timestamp_utc" => _sidecar_export_value(loaded, "timestamp_utc"),
        "source_git_sha" => _sidecar_export_value(loaded, "git_sha", manifest_scalars.git_commit),
        "config_id" => manifest_scalars.config_id,
        "run_context" => manifest_scalars.run_context,
        "run_command" => manifest_scalars.run_command,
        "trust_verdict" => _source_trust_verdict(loaded),
        "fiber_name" => getproperty(loaded, :fiber_name),
        "L_m" => getproperty(loaded, :L_m),
        "P_cont_W" => getproperty(loaded, :P_cont_W),
        "Nt" => Int(loaded.Nt),
        "time_window_ps" => Float64(loaded.time_window_ps),
        "converged" => getproperty(loaded, :converged),
        "iterations" => getproperty(loaded, :iterations),
        "J_initial_dB" => FiberLab.lin_to_dB(getproperty(loaded, :J_before)),
        "J_final_dB" => FiberLab.lin_to_dB(getproperty(loaded, :J_after)),
        "phase_csv" => basename(phase_csv),
        "amplitude" => amplitude_meta,
        "provenance" => provenance,
        "integrity" => integrity,
        "roundtrip_validation_json" => "roundtrip_validation.json",
    )

    metadata_json = joinpath(output_dir, "metadata.json")
    open(metadata_json, "w") do io
        JSON3.pretty(io, export_meta)
    end

    readme_path = joinpath(output_dir, "README.md")
    open(readme_path, "w") do io
        println(io, "# Experimental Handoff Bundle")
        println(io)
        println(io, "- Source artifact name: `", basename(artifact), "` (not included)")
        println(io, "- Source artifact SHA-256: `", source_artifact_sha256, "`")
        println(io, "- Fiber: `", loaded.fiber_name, "`")
        println(io, "- L: `", loaded.L_m, " m`")
        println(io, "- P: `", loaded.P_cont_W, " W`")
        println(io, "- Final objective: `", @sprintf("%.2f dB", FiberLab.lin_to_dB(loaded.J_after)), "`")
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
        if haskey(provenance, "source_config")
            println(io, "- `", provenance["source_config"], "` — copied run config")
        end
        if haskey(provenance, "source_trust_report")
            println(io, "- `", provenance["source_trust_report"], "` — copied trust report")
        end
        if haskey(provenance, "source_run_manifest")
            println(io, "- `", provenance["source_run_manifest"], "` — copied run manifest")
        end
        println(io, "- SHA-256 values for copied provenance and CSV files are recorded in `metadata.json`.")
    end

    roundtrip_json = joinpath(output_dir, "roundtrip_validation.json")
    roundtrip_report = _roundtrip_validation_report(
        output_dir,
        export_meta;
        source_artifact=artifact,
    )
    open(roundtrip_json, "w") do io
        JSON3.pretty(io, roundtrip_report)
    end
    Bool(roundtrip_report["complete"]) || throw(ArgumentError(
        "export handoff failed roundtrip/integrity validation: " *
        join(roundtrip_report["missing_or_invalid"], ", ")))

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

end # include guard
