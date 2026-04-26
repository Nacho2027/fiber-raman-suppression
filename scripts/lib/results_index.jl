"""
Lightweight read-only index for run artifacts and sweep summaries.

This is intentionally not a database. It scans output roots and renders a
compact table so lab users can find and compare completed runs/campaigns.
"""

if !(@isdefined _RESULTS_INDEX_JL_LOADED)
const _RESULTS_INDEX_JL_LOADED = true

using Printf
using JSON3
using TOML

include(joinpath(@__DIR__, "run_artifacts.jl"))

const INDEX_EXPORT_REQUIRED_FILES = (
    "phase_profile.csv",
    "metadata.json",
    "README.md",
    "source_run_config.toml",
)

function _index_float_cell(value)
    if value isa AbstractFloat
        isfinite(value) || return ""
        format = 0 < abs(value) < 0.01 ? "%.4g" : "%.2f"
        return Printf.format(Printf.Format(format), value)
    end
    return string(value)
end

function _csv_cell(value)
    text = if ismissing(value)
        ""
    elseif value isa AbstractFloat
        isfinite(value) ? string(value) : ""
    else
        string(value)
    end
    needs_quotes = any(ch -> ch in (',', '"', '\n', '\r'), text)
    escaped = replace(text, "\"" => "\"\"")
    return needs_quotes ? "\"$escaped\"" : escaped
end

function _nested_toml_value(data, keys::Tuple, default="")
    current = data
    for key in keys
        if current isa AbstractDict && haskey(current, String(key))
            current = current[String(key)]
        else
            return default
        end
    end
    return current
end

function _join_index_values(value)
    if ismissing(value) || isnothing(value)
        return ""
    elseif value isa AbstractVector
        return join(string.(value), ",")
    else
        return string(value)
    end
end

function _run_config_metadata(dir::AbstractString)
    path = joinpath(dir, "run_config.toml")
    if !isfile(path)
        return (
            config_id = "",
            regime = "",
            objective_kind = "",
            variables = "",
            solver_kind = "",
            run_config_path = "",
        )
    end

    try
        data = TOML.parsefile(path)
        return (
            config_id = _join_index_values(_nested_toml_value(data, (:id,))),
            regime = _join_index_values(_nested_toml_value(data, (:problem, :regime))),
            objective_kind = _join_index_values(_nested_toml_value(data, (:objective, :kind))),
            variables = _join_index_values(_nested_toml_value(data, (:controls, :variables))),
            solver_kind = _join_index_values(_nested_toml_value(data, (:solver, :kind))),
            run_config_path = abspath(path),
        )
    catch
        return (
            config_id = "",
            regime = "",
            objective_kind = "",
            variables = "",
            solver_kind = "",
            run_config_path = abspath(path),
        )
    end
end

function _sidecar_metadata(path::AbstractString)
    sidecar = replace(path, r"\.jld2$" => ".json")
    isfile(sidecar) || return (timestamp_utc = "", sidecar_path = "")
    try
        parsed = JSON3.read(read(sidecar, String))
        return (
            timestamp_utc = hasproperty(parsed, :timestamp_utc) ? string(parsed.timestamp_utc) : "",
            sidecar_path = abspath(sidecar),
        )
    catch
        return (timestamp_utc = "", sidecar_path = abspath(sidecar))
    end
end

function _trust_report_path(dir::AbstractString)
    isdir(dir) || return ""
    matches = sort(filter(name -> endswith(name, "_trust.md"), readdir(dir)))
    isempty(matches) && return ""
    return abspath(joinpath(dir, first(matches)))
end

function _export_handoff_complete(dir::AbstractString)
    export_dir = joinpath(dir, "export_handoff")
    isdir(export_dir) || return (complete = false, path = "")
    complete = all(name -> isfile(joinpath(export_dir, name)), INDEX_EXPORT_REQUIRED_FILES)
    return (complete = complete, path = complete ? abspath(export_dir) : "")
end

function _lab_readiness_status(; converged, standard_images_complete, trust_report_path, error="")
    blockers = String[]
    isempty(error) || push!(blockers, "artifact_error")
    converged === true || push!(blockers, "not_converged")
    standard_images_complete === true || push!(blockers, "missing_standard_images")
    isempty(trust_report_path) && push!(blockers, "missing_trust_report")
    return (
        lab_ready = isempty(blockers),
        readiness = isempty(blockers) ? "ready" : join(blockers, ","),
    )
end

function _sweep_summary_title(path::AbstractString)
    try
        for line in eachline(path)
            if startswith(line, "# ")
                return strip(replace(line, "# Experiment Sweep Summary:" => ""))
            end
        end
    catch
    end
    return basename(dirname(path))
end

function _safe_run_index_row(path::AbstractString)
    try
        summary = canonical_run_summary(path)
        images = standard_image_set_status(path)
        meta = _run_config_metadata(summary.artifact_dir)
        sidecar = _sidecar_metadata(String(summary.artifact))
        trust_report_path = _trust_report_path(summary.artifact_dir)
        export_handoff = _export_handoff_complete(summary.artifact_dir)
        readiness = _lab_readiness_status(
            converged=summary.converged,
            standard_images_complete=images.complete,
            trust_report_path=trust_report_path,
        )
        return (
            kind = :run,
            id = basename(dirname(summary.artifact)),
            config_id = meta.config_id,
            regime = meta.regime,
            objective_kind = meta.objective_kind,
            variables = meta.variables,
            solver_kind = meta.solver_kind,
            timestamp_utc = sidecar.timestamp_utc,
            fiber = summary.fiber_name,
            L_m = summary.L_m,
            P_cont_W = summary.P_cont_W,
            J_before_dB = summary.J_before_dB,
            J_after_dB = summary.J_after_dB,
            delta_J_dB = summary.delta_J_dB,
            quality = summary.quality,
            converged = summary.converged,
            iterations = summary.iterations,
            standard_images_complete = images.complete,
            trust_report_present = !isempty(trust_report_path),
            export_handoff_complete = export_handoff.complete,
            lab_ready = readiness.lab_ready,
            readiness = readiness.readiness,
            trust_report_path = trust_report_path,
            run_config_path = meta.run_config_path,
            sidecar_path = sidecar.sidecar_path,
            export_handoff_path = export_handoff.path,
            path = String(summary.artifact),
            error = "",
        )
    catch err
        error = sprint(showerror, err)
        readiness = _lab_readiness_status(
            converged=missing,
            standard_images_complete=false,
            trust_report_path="",
            error=error,
        )
        return (
            kind = :run,
            id = basename(dirname(path)),
            config_id = "",
            regime = "",
            objective_kind = "",
            variables = "",
            solver_kind = "",
            timestamp_utc = "",
            fiber = "",
            L_m = NaN,
            P_cont_W = NaN,
            J_before_dB = NaN,
            J_after_dB = NaN,
            delta_J_dB = NaN,
            quality = "ERROR",
            converged = missing,
            iterations = missing,
            standard_images_complete = false,
            trust_report_present = false,
            export_handoff_complete = false,
            lab_ready = readiness.lab_ready,
            readiness = readiness.readiness,
            trust_report_path = "",
            run_config_path = "",
            sidecar_path = "",
            export_handoff_path = "",
            path = abspath(path),
            error = error,
        )
    end
end

function _sweep_index_row(path::AbstractString)
    return (
        kind = :sweep,
        id = _sweep_summary_title(path),
        config_id = "",
        regime = "",
        objective_kind = "",
        variables = "",
        solver_kind = "",
        timestamp_utc = "",
        fiber = "",
        L_m = NaN,
        P_cont_W = NaN,
        J_before_dB = NaN,
        J_after_dB = NaN,
        delta_J_dB = NaN,
        quality = "",
        converged = missing,
        iterations = missing,
        standard_images_complete = missing,
        trust_report_present = missing,
        export_handoff_complete = missing,
        lab_ready = missing,
        readiness = "",
        trust_report_path = "",
        run_config_path = "",
        sidecar_path = "",
        export_handoff_path = "",
        path = abspath(path),
        error = "",
    )
end

function _walk_files(root::AbstractString)
    isdir(root) || return String[]
    files = String[]
    for (dir, _, names) in walkdir(root)
        for name in names
            push!(files, joinpath(dir, name))
        end
    end
    sort!(files)
    return files
end

function build_results_index(roots::Vector{<:AbstractString}=["results/raman"])
    rows = []
    seen = Set{String}()
    for root in roots
        for path in _walk_files(root)
            if endswith(path, "_result.jld2")
                apath = abspath(path)
                apath in seen && continue
                push!(seen, apath)
                push!(rows, _safe_run_index_row(path))
            elseif basename(path) == "SWEEP_SUMMARY.md"
                apath = abspath(path)
                apath in seen && continue
                push!(seen, apath)
                push!(rows, _sweep_index_row(path))
            end
        end
    end

    sort!(rows; by = row -> (string(row.kind), row.id, row.path))
    return (
        roots = Tuple(String.(roots)),
        total = length(rows),
        rows = Tuple(rows),
    )
end

function _row_contains(row, needle::AbstractString)
    query = lowercase(needle)
    fields = (
        string(row.kind),
        row.id,
        row.config_id,
        row.regime,
        row.objective_kind,
        row.variables,
        row.solver_kind,
        row.timestamp_utc,
        row.fiber,
        row.quality,
        row.readiness,
        row.trust_report_path,
        row.run_config_path,
        row.sidecar_path,
        row.export_handoff_path,
        row.path,
        row.error,
    )
    return any(field -> occursin(query, lowercase(String(field))), fields)
end

function filter_results_index(
    index;
    kind::Union{Nothing,Symbol}=nothing,
    config_id::Union{Nothing,AbstractString}=nothing,
    regime::Union{Nothing,AbstractString}=nothing,
    objective::Union{Nothing,AbstractString}=nothing,
    solver::Union{Nothing,AbstractString}=nothing,
    fiber::Union{Nothing,AbstractString}=nothing,
    complete_images::Bool=false,
    lab_ready::Bool=false,
    export_ready::Bool=false,
    contains::Union{Nothing,AbstractString}=nothing,
)
    rows = collect(index.rows)
    if !isnothing(kind)
        rows = filter(row -> row.kind == kind, rows)
    end
    if !isnothing(config_id)
        rows = filter(row -> lowercase(row.config_id) == lowercase(String(config_id)), rows)
    end
    if !isnothing(regime)
        rows = filter(row -> lowercase(row.regime) == lowercase(String(regime)), rows)
    end
    if !isnothing(objective)
        rows = filter(row -> lowercase(row.objective_kind) == lowercase(String(objective)), rows)
    end
    if !isnothing(solver)
        rows = filter(row -> lowercase(row.solver_kind) == lowercase(String(solver)), rows)
    end
    if !isnothing(fiber)
        rows = filter(row -> lowercase(row.fiber) == lowercase(String(fiber)), rows)
    end
    if complete_images
        rows = filter(row -> row.standard_images_complete === true, rows)
    end
    if lab_ready
        rows = filter(row -> row.lab_ready === true, rows)
    end
    if export_ready
        rows = filter(row -> row.export_handoff_complete === true, rows)
    end
    if !isnothing(contains) && !isempty(contains)
        rows = filter(row -> _row_contains(row, contains), rows)
    end
    return (
        roots = index.roots,
        total = length(rows),
        rows = Tuple(rows),
    )
end

function render_results_index(index; io::Union{Nothing,IO}=nothing)
    lines = String[
        "# Results Index",
        "",
        "- Roots: `$(join(index.roots, "`, `"))`",
        "- Entries: `$(index.total)`",
        "",
        "| Kind | ID | Config | Regime | Objective | Variables | Fiber | L [m] | P [W] | J_after [dB] | ΔJ [dB] | Quality | Lab Ready | Readiness | Std Images | Trust | Export | Path |",
        "|---|---|---|---|---|---|---|---:|---:|---:|---:|---|---|---|---|---|---|---|",
    ]

    for row in index.rows
        push!(lines, string(
            "| ", row.kind,
            " | ", row.id,
            " | ", row.config_id,
            " | ", row.regime,
            " | ", row.objective_kind,
            " | ", row.variables,
            " | ", row.fiber,
            " | ", _index_float_cell(row.L_m),
            " | ", _index_float_cell(row.P_cont_W),
            " | ", _index_float_cell(row.J_after_dB),
            " | ", _index_float_cell(row.delta_J_dB),
            " | ", row.quality,
            " | ", ismissing(row.lab_ready) ? "" : string(row.lab_ready),
            " | ", row.readiness,
            " | ", ismissing(row.standard_images_complete) ? "" : string(row.standard_images_complete),
            " | ", ismissing(row.trust_report_present) ? "" : string(row.trust_report_present),
            " | ", ismissing(row.export_handoff_complete) ? "" : string(row.export_handoff_complete),
            " | ", isempty(row.error) ? row.path : row.error,
            " |"))
    end

    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function render_results_index_csv(index; io::Union{Nothing,IO}=nothing)
    columns = (
        :kind,
        :id,
        :config_id,
        :regime,
        :objective_kind,
        :variables,
        :solver_kind,
        :timestamp_utc,
        :fiber,
        :L_m,
        :P_cont_W,
        :J_before_dB,
        :J_after_dB,
        :delta_J_dB,
        :quality,
        :converged,
        :iterations,
        :standard_images_complete,
        :trust_report_present,
        :export_handoff_complete,
        :lab_ready,
        :readiness,
        :trust_report_path,
        :run_config_path,
        :sidecar_path,
        :export_handoff_path,
        :path,
        :error,
    )
    lines = [join(string.(columns), ",")]
    for row in index.rows
        push!(lines, join((_csv_cell(getproperty(row, col)) for col in columns), ","))
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function compare_results_index(index; lab_ready_only::Bool=false,
                               export_ready_only::Bool=false,
                               top::Union{Nothing,Int}=nothing)
    rows = [row for row in index.rows if row.kind == :run]
    lab_ready_only && filter!(row -> row.lab_ready === true, rows)
    export_ready_only && filter!(row -> row.export_handoff_complete === true, rows)
    sort!(rows; by = row -> (
        row.lab_ready === true ? 0 : 1,
        row.converged === true ? 0 : 1,
        row.standard_images_complete === true ? 0 : 1,
        row.trust_report_present === true ? 0 : 1,
        isnan(row.J_after_dB) ? Inf : row.J_after_dB,
        row.id,
    ))
    if !isnothing(top) && top >= 0
        rows = rows[1:min(top, length(rows))]
    end
    return (
        roots = index.roots,
        total = length(rows),
        rows = Tuple(rows),
    )
end

function render_results_comparison(comparison; io::Union{Nothing,IO}=nothing)
    lines = String[
        "# Results Comparison",
        "",
        "- Roots: `$(join(comparison.roots, "`, `"))`",
        "- Runs: `$(comparison.total)`",
        "",
        "| Rank | Lab Ready | Readiness | Config | Objective | Variables | Fiber | L [m] | P [W] | J_after [dB] | ΔJ [dB] | Quality | Std Images | Trust | Export | Path |",
        "|---:|---|---|---|---|---|---|---:|---:|---:|---:|---|---|---|---|---|",
    ]
    for (rank, row) in enumerate(comparison.rows)
        push!(lines, string(
            "| ", rank,
            " | ", row.lab_ready,
            " | ", row.readiness,
            " | ", row.config_id,
            " | ", row.objective_kind,
            " | ", row.variables,
            " | ", row.fiber,
            " | ", _index_float_cell(row.L_m),
            " | ", _index_float_cell(row.P_cont_W),
            " | ", _index_float_cell(row.J_after_dB),
            " | ", _index_float_cell(row.delta_J_dB),
            " | ", row.quality,
            " | ", row.standard_images_complete,
            " | ", row.trust_report_present,
            " | ", row.export_handoff_complete,
            " | ", isempty(row.error) ? row.path : row.error,
            " |"))
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function render_results_comparison_csv(comparison; io::Union{Nothing,IO}=nothing)
    columns = (
        :rank,
        :lab_ready,
        :readiness,
        :config_id,
        :objective_kind,
        :variables,
        :fiber,
        :L_m,
        :P_cont_W,
        :J_after_dB,
        :delta_J_dB,
        :quality,
        :standard_images_complete,
        :trust_report_present,
        :export_handoff_complete,
        :path,
    )
    lines = [join(string.(columns), ",")]
    for (rank, row) in enumerate(comparison.rows)
        push!(lines, join((_csv_cell(col == :rank ? rank : getproperty(row, col)) for col in columns), ","))
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

end # include guard
