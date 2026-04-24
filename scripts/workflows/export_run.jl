"""
Export one saved run into an experiment-facing handoff bundle.

Usage:
    julia --project=. scripts/canonical/export_run.jl <run-dir-or-artifact> [output-dir]
"""

using Dates
using FFTW
using JSON3
using Printf
using MultiModeNoise

include(joinpath(@__DIR__, "..", "lib", "run_artifacts.jl"))

const EXPORT_SCHEMA_VERSION = "1.0"
const C_NM_THZ = 299792.458

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

function export_run_bundle(input_path::AbstractString, output_dir::AbstractString)
    artifact = resolve_run_artifact_path(input_path)
    loaded = MultiModeNoise.load_run(artifact)
    mkpath(output_dir)

    phi = vec(Float64.(loaded.phi_opt))
    phi_unwrapped = _manual_unwrap_export(phi)
    rel_f_THz, abs_f_THz, λ_nm, dω = _phase_axes(loaded)
    τ_fs = _group_delay_fs(phi_unwrapped, dω)

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
        println(io, "- `metadata.json` — provenance and scalar summary")
        if isfile(source_config)
            println(io, "- `source_run_config.toml` — approved run config copied from the source bundle")
        end
    end

    return (
        source_artifact = artifact,
        output_dir = output_dir,
        phase_csv = phase_csv,
        metadata_json = metadata_json,
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
