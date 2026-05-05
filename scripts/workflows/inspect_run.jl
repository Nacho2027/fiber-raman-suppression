"""
Inspect one saved run bundle and print a concise human-readable summary.

Usage:
    julia --project=. scripts/canonical/inspect_run.jl <run-dir-or-artifact>
"""

using Printf
using FiberLab

include(joinpath(@__DIR__, "..", "lib", "run_artifacts.jl"))

const INSPECT_EXPORT_REQUIRED_FILES = (
    phase_csv = "phase_profile.csv",
    metadata_json = "metadata.json",
    readme = "README.md",
    source_config = "source_run_config.toml",
)

const INSPECT_PHASE_CSV_REQUIRED_COLUMNS = (
    "index",
    "frequency_offset_THz",
    "absolute_frequency_THz",
    "wavelength_nm",
    "phase_wrapped_rad",
    "phase_unwrapped_rad",
    "group_delay_fs",
)

function _push_phase_csv_error!(errors::Vector{String}, message::AbstractString)
    length(errors) < 12 && push!(errors, String(message))
    return errors
end

function validate_phase_profile_csv(path::AbstractString)
    errors = String[]
    isfile(path) || return (
        path = String(path),
        exists = false,
        valid = false,
        row_count = 0,
        columns = String[],
        errors = ("missing_phase_profile_csv",),
    )

    lines = readlines(path)
    if isempty(lines)
        return (
            path = String(path),
            exists = true,
            valid = false,
            row_count = 0,
            columns = String[],
            errors = ("missing_header",),
        )
    end

    header = split(strip(first(lines)), ",")
    missing_columns = setdiff(collect(INSPECT_PHASE_CSV_REQUIRED_COLUMNS), header)
    isempty(missing_columns) || _push_phase_csv_error!(
        errors,
        string("missing_columns:", join(missing_columns, "|")),
    )
    length(lines) > 1 || _push_phase_csv_error!(errors, "missing_data_rows")

    column_index = Dict(name => idx for (idx, name) in pairs(header))
    row_count = 0
    isempty(missing_columns) || return (
        path = String(path),
        exists = true,
        valid = false,
        row_count = row_count,
        columns = header,
        errors = Tuple(errors),
    )

    numeric_columns = setdiff(collect(INSPECT_PHASE_CSV_REQUIRED_COLUMNS), ["index"])
    for (line_number, line) in enumerate(lines[2:end])
        row_label = line_number + 1
        fields = split(line, ","; keepempty=true)
        if length(fields) != length(header)
            _push_phase_csv_error!(
                errors,
                "row_$(row_label)_field_count_$(length(fields))_expected_$(length(header))",
            )
            continue
        end

        row_count += 1
        index_value = tryparse(Int, strip(fields[column_index["index"]]))
        if index_value === nothing
            _push_phase_csv_error!(errors, "row_$(row_label)_invalid_index")
        elseif index_value != row_count
            _push_phase_csv_error!(
                errors,
                "row_$(row_label)_index_$(index_value)_expected_$(row_count)",
            )
        end

        for column in numeric_columns
            value = tryparse(Float64, strip(fields[column_index[column]]))
            if value === nothing || !isfinite(value)
                _push_phase_csv_error!(errors, "row_$(row_label)_invalid_$(column)")
                continue
            end
            if column in ("absolute_frequency_THz", "wavelength_nm") && value <= 0
                _push_phase_csv_error!(errors, "row_$(row_label)_nonpositive_$(column)")
            end
        end
    end

    return (
        path = String(path),
        exists = true,
        valid = isempty(errors),
        row_count = row_count,
        columns = header,
        errors = Tuple(errors),
    )
end

function export_handoff_status(run_dir::AbstractString)
    export_dir = joinpath(run_dir, "export_handoff")
    paths = Dict{Symbol,String}()
    missing = String[]

    for (key, filename) in pairs(INSPECT_EXPORT_REQUIRED_FILES)
        path = joinpath(export_dir, filename)
        paths[key] = path
        isfile(path) || push!(missing, filename)
    end

    phase_csv_validation = validate_phase_profile_csv(paths[:phase_csv])
    files_complete = isdir(export_dir) && isempty(missing)

    return (
        dir = export_dir,
        phase_csv = paths[:phase_csv],
        metadata_json = paths[:metadata_json],
        readme = paths[:readme],
        source_config = paths[:source_config],
        present = sort!([filename for filename in values(INSPECT_EXPORT_REQUIRED_FILES)
                         if isfile(joinpath(export_dir, filename))]),
        missing = sort!(missing),
        files_complete = files_complete,
        phase_csv_valid = phase_csv_validation.valid,
        phase_csv_rows = phase_csv_validation.row_count,
        phase_csv_errors = phase_csv_validation.errors,
        complete = files_complete && phase_csv_validation.valid,
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
        println(io, "Export phase CSV rows: ", summary.export_handoff.phase_csv_rows)
    elseif isdir(summary.export_handoff.dir)
        println(io, "Export handoff missing: ", join(summary.export_handoff.missing, ", "))
        if !summary.export_handoff.phase_csv_valid
            println(io, "Export phase CSV invalid: ", join(summary.export_handoff.phase_csv_errors, ", "))
        end
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
