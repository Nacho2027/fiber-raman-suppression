"""
Inspect one saved run bundle and print a concise human-readable summary.

Usage:
    julia --project=. scripts/canonical/inspect_run.jl <run-dir-or-artifact>
"""

using Printf
using MultiModeNoise

include(joinpath(@__DIR__, "..", "lib", "run_artifacts.jl"))

const INSPECT_EXPORT_REQUIRED_FILES = (
    phase_csv = "phase_profile.csv",
    metadata_json = "metadata.json",
    readme = "README.md",
    source_config = "source_run_config.toml",
)

function export_handoff_status(run_dir::AbstractString)
    export_dir = joinpath(run_dir, "export_handoff")
    paths = Dict{Symbol,String}()
    missing = String[]

    for (key, filename) in pairs(INSPECT_EXPORT_REQUIRED_FILES)
        path = joinpath(export_dir, filename)
        paths[key] = path
        isfile(path) || push!(missing, filename)
    end

    return (
        dir = export_dir,
        phase_csv = paths[:phase_csv],
        metadata_json = paths[:metadata_json],
        readme = paths[:readme],
        source_config = paths[:source_config],
        present = sort!([filename for filename in values(INSPECT_EXPORT_REQUIRED_FILES)
                         if isfile(joinpath(export_dir, filename))]),
        missing = sort!(missing),
        complete = isdir(export_dir) && isempty(missing),
    )
end

function inspect_run_summary(path::AbstractString)
    artifact = resolve_run_artifact_path(path)
    summary = canonical_run_summary(artifact)
    images = standard_image_set_status(artifact)
    dir = dirname(artifact)
    trust_candidates = sort(filter(name -> endswith(name, "_trust.md"), readdir(dir)))
    run_config = joinpath(dir, "run_config.toml")

    return (;
        summary...,
        run_config = isfile(run_config) ? run_config : missing,
        trust_reports = [joinpath(dir, name) for name in trust_candidates],
        standard_images = images,
        export_handoff = export_handoff_status(dir),
    )
end

function render_run_summary(summary; io::IO=stdout)
    println(io, "Run artifact: ", summary.artifact)
    println(io, "Artifact dir: ", summary.artifact_dir)
    println(io, @sprintf("Config: fiber=%s  L=%s m  P=%s W",
        summary.fiber_name,
        string(summary.L_m),
        string(summary.P_cont_W)))
    println(io, @sprintf("Grid: Nt=%s  time_window_ps=%s",
        string(summary.Nt),
        string(summary.time_window_ps)))
    println(io, @sprintf("Objective: J_before=%s dB  J_after=%s dB  Δ=%s dB",
        string(summary.J_before_dB),
        string(summary.J_after_dB),
        string(summary.delta_J_dB)))
    println(io, @sprintf("Optimizer: converged=%s  iterations=%s  schema=%s",
        string(summary.converged),
        string(summary.iterations),
        summary.schema_version))
    println(io, "Run config: ", ismissing(summary.run_config) ? "none" : summary.run_config)
    println(io, "Trust reports: ", isempty(summary.trust_reports) ? "none" : join(summary.trust_reports, ", "))
    println(io, "Standard image set complete: ", summary.standard_images.complete)
    println(io, "Standard images present: ",
        isempty(summary.standard_images.present) ? "none" : join(summary.standard_images.present, ", "))
    if !isempty(summary.standard_images.missing)
        println(io, "Standard images missing: ", join(summary.standard_images.missing, ", "))
    end
    println(io, "Export handoff complete: ", summary.export_handoff.complete)
    if summary.export_handoff.complete
        println(io, "Export handoff dir: ", summary.export_handoff.dir)
        println(io, "Export phase CSV: ", summary.export_handoff.phase_csv)
    elseif isdir(summary.export_handoff.dir)
        println(io, "Export handoff missing: ", join(summary.export_handoff.missing, ", "))
    else
        println(io, "Export handoff: none")
    end
    return nothing
end

function inspect_run_main(args=ARGS)
    length(args) == 1 || error("usage: scripts/canonical/inspect_run.jl <run-dir-or-artifact>")
    summary = inspect_run_summary(args[1])
    render_run_summary(summary)
    return summary
end

if abspath(PROGRAM_FILE) == @__FILE__
    inspect_run_main(ARGS)
end
