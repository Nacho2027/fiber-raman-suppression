"""
Lightweight read-only index for run artifacts and sweep summaries.

This is intentionally not a database. It scans output roots and renders a
compact table so lab users can find and compare completed runs/campaigns.
"""

if !(@isdefined _RESULTS_INDEX_JL_LOADED)
const _RESULTS_INDEX_JL_LOADED = true

using JSON3
using SHA
using TOML

include(joinpath(@__DIR__, "run_artifacts.jl"))
include(joinpath(@__DIR__, "experiment_spec.jl"))
include(joinpath(@__DIR__, "export_integrity.jl"))
include(joinpath(@__DIR__, "numerical_trust.jl"))
include(joinpath(@__DIR__, "results_index_rendering.jl"))

const INDEX_EXPORT_REQUIRED_FILES = (
    "phase_profile.csv",
    "metadata.json",
    "README.md",
    "source_run_config.toml",
    "roundtrip_validation.json",
)

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

_missing_comparison_metadata(reason) = (
    objective_cost_scale = "",
    comparison_signature = "",
    comparison_blocker = String(reason),
)

function _run_config_comparison_metadata(data)
    problem = get(data, "problem", nothing)
    objective = get(data, "objective", nothing)
    problem isa AbstractDict || return _missing_comparison_metadata(
        "run_config.toml is missing [problem]")
    objective isa AbstractDict || return _missing_comparison_metadata(
        "run_config.toml is missing [objective]")
    isempty(strip(_join_index_values(get(objective, "kind", "")))) &&
        return _missing_comparison_metadata(
            "run_config.toml is missing objective.kind")
    log_cost = get(objective, "log_cost", missing)
    log_cost isa Bool || return _missing_comparison_metadata(
        "run_config.toml is missing Boolean objective.log_cost")
    payload = sprint(io -> TOML.print(io,
        Dict("problem" => problem, "objective" => objective); sorted=true))
    return (
        objective_cost_scale = log_cost ? "log10_db" : "linear",
        comparison_signature = bytes2hex(SHA.sha256(payload)),
        comparison_blocker = "",
    )
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
            _missing_comparison_metadata("missing run_config.toml")...,
        )
    end

    try
        data = TOML.parsefile(path)
        comparison = _run_config_comparison_metadata(data)
        return (
            config_id = _join_index_values(_nested_toml_value(data, (:id,))),
            regime = _join_index_values(_nested_toml_value(data, (:problem, :regime))),
            objective_kind = _join_index_values(_nested_toml_value(data, (:objective, :kind))),
            variables = _join_index_values(_nested_toml_value(data, (:controls, :variables))),
            solver_kind = _join_index_values(_nested_toml_value(data, (:solver, :kind))),
            run_config_path = abspath(path),
            comparison...,
        )
    catch err
        return (
            config_id = "",
            regime = "",
            objective_kind = "",
            variables = "",
            solver_kind = "",
            run_config_path = abspath(path),
            _missing_comparison_metadata(string(
                "invalid run_config.toml: ", sprint(showerror, err)))...,
        )
    end
end

function _artifact_save_prefix(path::AbstractString)
    text = String(path)
    for suffix in ("_result.jld2", "_result.json")
        if endswith(text, suffix)
            return text[1:(lastindex(text) - lastindex(suffix))]
        end
    end
    root, _ = splitext(text)
    return root
end

function _sidecar_metadata(path::AbstractString)
    sidecar = replace(path, r"\.jld2$" => ".json")
    slm_sidecar = string(_artifact_save_prefix(path), "_slm.json")
    if !isfile(sidecar) && isfile(slm_sidecar)
        sidecar = slm_sidecar
    end
    isfile(sidecar) || return (timestamp_utc = "", sidecar_path = "")
    try
        parsed = JSON3.read(read(sidecar, String))
        return (
            timestamp_utc = hasproperty(parsed, :timestamp_utc) ? string(parsed.timestamp_utc) :
                (hasproperty(parsed, :generated_at) ? string(parsed.generated_at) : ""),
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

function _export_handoff_complete(dir::AbstractString, source_artifact::AbstractString)
    export_dir = joinpath(dir, "export_handoff")
    isdir(export_dir) || return (complete = false, path = "")
    files_complete = all(
        name -> isfile(joinpath(export_dir, name)),
        INDEX_EXPORT_REQUIRED_FILES,
    )
    integrity = validate_export_handoff_integrity(
        export_dir; source_artifact=source_artifact)
    complete = files_complete && integrity.complete
    return (complete = complete, path = complete ? abspath(export_dir) : "")
end

function _missing_manifest_metadata(; present::Bool=false, path::AbstractString="")
    return (
        present = present,
        path = String(path),
        schema_version = "",
        run_context = "",
        command = "",
        compare_ready = missing,
        missing = "",
        artifacts_complete = missing,
        standard_images_complete = missing,
        variable_artifacts_complete = missing,
    )
end

function _manifest_bool(object, name::Symbol)
    hasproperty(object, name) || return missing
    value = getproperty(object, name)
    ismissing(value) && return missing
    isnothing(value) && return missing
    return Bool(value)
end

function _manifest_string(object, name::Symbol)
    hasproperty(object, name) || return ""
    value = getproperty(object, name)
    isnothing(value) && return ""
    ismissing(value) && return ""
    return string(value)
end

function _results_manifest_missing(items)
    return string.(collect(items))
end

function _run_manifest_metadata(dir::AbstractString)
    path = joinpath(dir, "run_manifest.json")
    isfile(path) || return _missing_manifest_metadata()
    manifest_path = abspath(path)

    try
        parsed = JSON3.read(read(path, String))
        execution = hasproperty(parsed, :execution) ? parsed.execution : nothing
        artifacts = hasproperty(parsed, :artifacts) ? parsed.artifacts : nothing
        missing_items = if execution !== nothing && hasproperty(execution, :missing)
            join(_results_manifest_missing(execution.missing), ",")
        else
            ""
        end

        return (
            present = true,
            path = manifest_path,
            schema_version = _manifest_string(parsed, :schema_version),
            run_context = _manifest_string(parsed, :run_context),
            command = _manifest_string(parsed, :command),
            compare_ready = execution === nothing ? missing : _manifest_bool(execution, :compare_ready),
            missing = missing_items,
            artifacts_complete = artifacts === nothing ? missing : _manifest_bool(artifacts, :complete),
            standard_images_complete = artifacts === nothing ? missing : _manifest_bool(artifacts, :standard_images_complete),
            variable_artifacts_complete = artifacts === nothing ? missing : _manifest_bool(artifacts, :variable_artifacts_complete),
        )
    catch err
        return (; _missing_manifest_metadata(present=true, path=manifest_path)...,
            missing = string("manifest_error:", sprint(showerror, err)))
    end
end

function _index_experiment_spec(run_config_path::AbstractString)
    isempty(run_config_path) && return nothing
    isfile(run_config_path) || return nothing
    try
        return load_experiment_spec(run_config_path)
    catch
        return nothing
    end
end

function _trust_report_required(index_spec)
    isnothing(index_spec) && return true
    return any(request -> request.hook == :trust_report, experiment_artifact_plan(index_spec).hooks)
end

function _index_extra_artifact_status(index_spec, artifact_path::AbstractString)
    if isnothing(index_spec)
        return (
            complete = true,
            hooks = "",
            paths = "",
            missing = "",
        )
    end

    status = extra_artifact_hook_file_status(index_spec, _artifact_save_prefix(artifact_path))
    return (
        complete = status.complete,
        hooks = join(string.(status.hooks), ","),
        paths = join(status.checked, ","),
        missing = join(status.missing, ","),
    )
end

function _lab_readiness_status(;
    converged,
    standard_images_complete,
    trust_report_path,
    trust_report_required::Bool=true,
    variable_artifacts_complete=true,
    index_spec=nothing,
    error="",
)
    blockers = String[]
    trust_paths = isempty(trust_report_path) ? String[] : [String(trust_report_path)]
    trust = trust_readiness(trust_paths; required=trust_report_required)
    isempty(error) || push!(blockers, "artifact_error")
    converged === true || push!(blockers, "not_converged")
    standard_images_complete === true || push!(blockers, "missing_standard_images")
    trust.pass || push!(blockers, trust.blocker)
    variable_artifacts_complete === false && push!(blockers, "missing_variable_artifacts")
    ismissing(variable_artifacts_complete) && push!(blockers, "unknown_variable_artifacts")
    if isnothing(index_spec)
        push!(blockers, "missing_or_invalid_run_config")
    else
        promotion = experiment_promotion_status(index_spec)
        promotion.stage == :lab_ready ||
            push!(blockers, "promotion_stage_$(promotion.stage)")
    end
    return (
        lab_ready = isempty(blockers),
        readiness = isempty(blockers) ? "ready" : join(blockers, ","),
        trust_verdict = trust.verdict,
        trust_pass = trust.pass,
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

function _markdown_cells(line::AbstractString)
    text = strip(line)
    startswith(text, "|") || return String[]
    endswith(text, "|") && (text = text[1:prevind(text, lastindex(text))])
    startswith(text, "|") && (text = text[nextind(text, firstindex(text)):end])
    return strip.(split(text, "|"))
end

function _safe_parse_float(text)
    value = strip(String(text))
    isempty(value) && return NaN
    try
        return parse(Float64, value)
    catch
        return NaN
    end
end

function _median_float(values)
    clean = sort([Float64(value) for value in values if isfinite(Float64(value))])
    isempty(clean) && return NaN
    n = length(clean)
    mid = div(n + 1, 2)
    return isodd(n) ? clean[mid] : (clean[mid] + clean[mid + 1]) / 2
end

function _sweep_summary_metrics(path::AbstractString)
    header = String[]
    rows = Vector{Vector{String}}()
    try
        lines = collect(eachline(path))
        for (idx, line) in enumerate(lines)
            cells = _markdown_cells(line)
            if "Case" in cells && "Status" in cells
                header = cells
                for rowline in lines[(idx + 2):end]
                    row = _markdown_cells(rowline)
                    isempty(row) && break
                    length(row) == length(header) || continue
                    push!(rows, row)
                end
                break
            end
        end
    catch err
        return (
            id = _sweep_summary_title(path),
            cases = 0,
            complete = 0,
            failed = 0,
            skipped = 0,
            best_case = "",
            best_J_after_dB = NaN,
            median_J_after_dB = NaN,
            path = abspath(path),
            error = sprint(showerror, err),
        )
    end

    isempty(header) && return (
        id = _sweep_summary_title(path),
        cases = 0,
        complete = 0,
        failed = 0,
        skipped = 0,
        best_case = "",
        best_J_after_dB = NaN,
        median_J_after_dB = NaN,
        path = abspath(path),
        error = "no sweep table found",
    )

    case_idx = findfirst(==("Case"), header)
    status_idx = findfirst(==("Status"), header)
    j_after_idx = findfirst(==("J_after [dB]"), header)

    statuses = lowercase.([row[status_idx] for row in rows])
    j_values = isnothing(j_after_idx) ? Float64[] : [_safe_parse_float(row[j_after_idx]) for row in rows]
    valid_pairs = [
        (case = row[case_idx], J_after_dB = _safe_parse_float(row[j_after_idx]))
        for row in rows
        if !isnothing(j_after_idx) && isfinite(_safe_parse_float(row[j_after_idx]))
    ]
    sort!(valid_pairs; by = row -> row.J_after_dB)
    best = isempty(valid_pairs) ? (case = "", J_after_dB = NaN) : first(valid_pairs)

    return (
        id = _sweep_summary_title(path),
        cases = length(rows),
        complete = count(==("complete"), statuses),
        failed = count(==("failed"), statuses),
        skipped = count(==("skipped"), statuses),
        best_case = best.case,
        best_J_after_dB = best.J_after_dB,
        median_J_after_dB = _median_float(j_values),
        path = abspath(path),
        error = "",
    )
end

function _safe_run_index_row(path::AbstractString)
    try
        summary = canonical_run_summary(path)
        images = standard_image_set_status(path)
        meta = _run_config_metadata(summary.artifact_dir)
        index_spec = _index_experiment_spec(meta.run_config_path)
        sidecar = _sidecar_metadata(String(summary.artifact))
        trust_report_path = _trust_report_path(summary.artifact_dir)
        extra_artifacts = _index_extra_artifact_status(index_spec, String(summary.artifact))
        export_handoff = _export_handoff_complete(
            summary.artifact_dir, String(summary.artifact))
        manifest = _run_manifest_metadata(summary.artifact_dir)
        readiness = _lab_readiness_status(
            converged=summary.converged,
            standard_images_complete=images.complete,
            trust_report_path=trust_report_path,
            trust_report_required=_trust_report_required(index_spec),
            variable_artifacts_complete=extra_artifacts.complete,
            index_spec=index_spec,
        )
        return (
            kind = :run,
            id = basename(dirname(summary.artifact)),
            config_id = meta.config_id,
            regime = meta.regime,
            objective_kind = meta.objective_kind,
            objective_cost_scale = meta.objective_cost_scale,
            variables = meta.variables,
            solver_kind = meta.solver_kind,
            comparison_signature = meta.comparison_signature,
            comparison_blocker = meta.comparison_blocker,
            timestamp_utc = sidecar.timestamp_utc,
            manifest_present = manifest.present,
            manifest_schema_version = manifest.schema_version,
            run_context = manifest.run_context,
            manifest_command = manifest.command,
            manifest_compare_ready = ismissing(manifest.compare_ready) ? missing :
                (manifest.compare_ready === true && readiness.lab_ready),
            manifest_missing = manifest.missing,
            manifest_path = manifest.path,
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
            trust_report_verdict = readiness.trust_verdict,
            trust_report_pass = readiness.trust_pass,
            variable_artifacts_complete = extra_artifacts.complete,
            variable_artifact_hooks = extra_artifacts.hooks,
            variable_artifact_paths = extra_artifacts.paths,
            variable_artifacts_missing = extra_artifacts.missing,
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
            objective_cost_scale = "",
            variables = "",
            solver_kind = "",
            comparison_signature = "",
            comparison_blocker = "run artifact could not be indexed",
            timestamp_utc = "",
            manifest_present = false,
            manifest_schema_version = "",
            run_context = "",
            manifest_command = "",
            manifest_compare_ready = missing,
            manifest_missing = "",
            manifest_path = "",
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
            trust_report_verdict = readiness.trust_verdict,
            trust_report_pass = readiness.trust_pass,
            variable_artifacts_complete = false,
            variable_artifact_hooks = "",
            variable_artifact_paths = "",
            variable_artifacts_missing = "",
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
        objective_cost_scale = "",
        variables = "",
        solver_kind = "",
        comparison_signature = "",
        comparison_blocker = "not a run artifact",
        timestamp_utc = "",
        manifest_present = false,
        manifest_schema_version = "",
        run_context = "",
        manifest_command = "",
        manifest_compare_ready = missing,
        manifest_missing = "",
        manifest_path = "",
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
        trust_report_verdict = missing,
        trust_report_pass = missing,
        variable_artifacts_complete = missing,
        variable_artifact_hooks = "",
        variable_artifact_paths = "",
        variable_artifacts_missing = "",
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
        row.objective_cost_scale,
        row.variables,
        row.solver_kind,
        row.comparison_signature,
        row.comparison_blocker,
        row.timestamp_utc,
        row.run_context,
        row.manifest_command,
        row.manifest_missing,
        row.manifest_path,
        row.fiber,
        row.quality,
        row.readiness,
        row.variable_artifact_hooks,
        row.variable_artifact_paths,
        row.variable_artifacts_missing,
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

function _require_comparable_results(rows)
    invalid = filter(rows) do row
        isempty(row.objective_kind) || isempty(row.objective_cost_scale) ||
        isempty(row.comparison_signature)
    end
    if !isempty(invalid)
        details = join((string(
            isempty(row.id) ? "<unnamed>" : row.id, " (",
            isempty(row.comparison_blocker) ?
                "missing objective/comparison identity" : row.comparison_blocker,
            ")",
        ) for row in invalid), ", ")
        throw(ArgumentError(
            "cannot rank results without complete requested-config comparison metadata: " *
            details * ". Use the inventory view without --compare, or filter to " *
            "runs with a complete copied run_config.toml."))
    end

    groups = Dict{Tuple{String,String,String},Vector{String}}()
    for row in rows
        key = (row.objective_kind, row.objective_cost_scale,
            row.comparison_signature)
        push!(get!(groups, key, String[]), row.id)
    end
    if length(groups) > 1
        summaries = [string(
            kind, "/", scale, "/", first(signature, min(12, length(signature))),
            " [", join(sort!(ids), ", "), "]",
        ) for ((kind, scale, signature), ids) in sort!(collect(groups); by=first)]
        throw(ArgumentError(
            "cannot rank runs with different requested configurations; --compare " *
            "requires one objective kind, optimization cost scale, and copied " *
            "[problem]/[objective] signature. This is not a resolved-physics identity. " *
            "Found: " * join(summaries, "; ") * ". Narrow the inventory " *
            "with --config-id, --objective, --fiber, or --contains before comparing."))
    end
    return isempty(groups) ? ("", "", "") : first(keys(groups))
end

function compare_results_index(index; lab_ready_only::Bool=false,
                               export_ready_only::Bool=false,
                               top::Union{Nothing,Int}=nothing)
    rows = [row for row in index.rows if row.kind == :run]
    lab_ready_only && filter!(row -> row.lab_ready === true, rows)
    export_ready_only && filter!(row -> row.export_handoff_complete === true, rows)
    identity = _require_comparable_results(rows)
    sort!(rows; by = row -> (
        row.lab_ready === true ? 0 : 1,
        row.converged === true ? 0 : 1,
        row.standard_images_complete === true ? 0 : 1,
        row.variable_artifacts_complete === true ? 0 : 1,
        row.trust_report_pass === true ? 0 : 1,
        isnan(row.J_after_dB) ? Inf : row.J_after_dB,
        row.id,
    ))
    if !isnothing(top) && top >= 0
        rows = rows[1:min(top, length(rows))]
    end
    return (
        roots = index.roots,
        total = length(rows),
        comparison_identity = isempty(rows) ? "" : string(
            identity[1], "/", identity[2], "/", first(identity[3], 12)),
        comparison_signature = isempty(rows) ? "" : identity[3],
        rows = Tuple(rows),
    )
end

function _json_property(object, name::Symbol, default=nothing)
    return hasproperty(object, name) ? getproperty(object, name) : default
end

function _sweep_summary_json_path(markdown_path::AbstractString)
    return joinpath(dirname(markdown_path), "SWEEP_SUMMARY.json")
end

function _sweep_summary_metrics_from_json(path::AbstractString)
    payload = JSON3.read(read(path, String))
    cases = collect(_json_property(payload, :cases, []))
    j_values = Float64[]
    valid = NamedTuple[]
    for case in cases
        j_after = _json_property(case, :J_after_dB, nothing)
        if !(j_after === nothing) && isfinite(Float64(j_after))
            push!(j_values, Float64(j_after))
            push!(valid, (
                case = string(_json_property(case, :case, "")),
                J_after_dB = Float64(j_after),
            ))
        end
    end
    sort!(valid; by = row -> row.J_after_dB)
    best = isempty(valid) ? (case = "", J_after_dB = NaN) : first(valid)
    return (
        id = string(_json_property(payload, :sweep_id, basename(dirname(path)))),
        cases = Int(_json_property(payload, :case_count, length(cases))),
        complete = Int(_json_property(payload, :complete, count(case -> string(_json_property(case, :status, "")) == "complete", cases))),
        failed = Int(_json_property(payload, :failed, count(case -> string(_json_property(case, :status, "")) == "failed", cases))),
        skipped = Int(_json_property(payload, :skipped, count(case -> string(_json_property(case, :status, "")) == "skipped", cases))),
        best_case = best.case,
        best_J_after_dB = best.J_after_dB,
        median_J_after_dB = _median_float(j_values),
        path = abspath(path),
        error = "",
    )
end

function _sweep_summary_metrics_prefer_sidecar(markdown_path::AbstractString)
    json_path = _sweep_summary_json_path(markdown_path)
    if isfile(json_path)
        try
            return _sweep_summary_metrics_from_json(json_path)
        catch err
            row = _sweep_summary_metrics(markdown_path)
            return (; row..., error = string("json sidecar failed; markdown fallback: ", sprint(showerror, err)))
        end
    end
    return _sweep_summary_metrics(markdown_path)
end

function compare_sweep_summaries(index; top::Union{Nothing,Int}=nothing)
    rows = [_sweep_summary_metrics_prefer_sidecar(row.path) for row in index.rows if row.kind == :sweep]
    sort!(rows; by = row -> (
        isnan(row.best_J_after_dB) ? Inf : row.best_J_after_dB,
        row.failed,
        row.skipped,
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

end # include guard
