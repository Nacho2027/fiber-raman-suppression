"""
Thin sweep expansion layer for front-layer experiment configs.

This is deliberately an expansion/validation surface first. It lets a
researcher define a small parameter sweep around a validated base experiment
without editing optimizer internals or duplicating many TOML files by hand.
"""

if !(@isdefined _EXPERIMENT_SWEEP_JL_LOADED)
const _EXPERIMENT_SWEEP_JL_LOADED = true

using TOML
using Printf
using Dates
using JSON3

include(joinpath(@__DIR__, "experiment_spec.jl"))

const EXPERIMENT_SWEEP_CONFIG_DIR = normpath(joinpath(@__DIR__, "..", "..", "configs", "experiment_sweeps"))

function _approved_experiment_sweep_ids(dir::AbstractString)
    isdir(dir) || return String[]
    ids = String[]
    for entry in readdir(dir)
        endswith(entry, ".toml") || continue
        push!(ids, replace(entry, ".toml" => ""))
    end
    sort!(ids)
    return ids
end

approved_experiment_sweep_config_ids() = _approved_experiment_sweep_ids(EXPERIMENT_SWEEP_CONFIG_DIR)

function resolve_experiment_sweep_config_path(spec::AbstractString)
    if isfile(spec)
        return abspath(spec)
    end

    filename = endswith(spec, ".toml") ? spec : string(spec, ".toml")
    candidate = joinpath(EXPERIMENT_SWEEP_CONFIG_DIR, filename)
    isfile(candidate) && return candidate

    available = join(approved_experiment_sweep_config_ids(), ", ")
    throw(ArgumentError(
        "could not resolve experiment sweep config `$spec` under `$EXPERIMENT_SWEEP_CONFIG_DIR`; available ids: [$available]"))
end

function load_experiment_sweep_spec(spec::AbstractString)
    path = resolve_experiment_sweep_config_path(spec)
    parsed = TOML.parsefile(path)
    sweep = parsed["sweep"]
    execution = get(parsed, "execution", Dict{String,Any}())

    return (
        id = String(parsed["id"]),
        description = String(get(parsed, "description", parsed["id"])),
        maturity = lowercase(String(get(parsed, "maturity", "experimental"))),
        config_path = path,
        base_experiment = String(parsed["base_experiment"]),
        output_root = String(get(parsed, "output_root", joinpath("results", "raman", "sweeps"))),
        output_tag = String(get(parsed, "output_tag", parsed["id"])),
        sweep = (
            parameter = String(sweep["parameter"]),
            values = Tuple(sweep["values"]),
            labels = Tuple(String.(get(sweep, "labels", String[]))),
        ),
        execution = (
            mode = _normalize_symbol(get(execution, "mode", "dry_run")),
            require_validate_all = Bool(get(execution, "require_validate_all", true)),
        ),
    )
end

function _case_label(sweep_spec, idx::Int)
    if !isempty(sweep_spec.sweep.labels)
        length(sweep_spec.sweep.labels) == length(sweep_spec.sweep.values) || throw(ArgumentError(
            "sweep labels length must match values length"))
        return sweep_spec.sweep.labels[idx]
    end
    return "case_" * lpad(string(idx), 3, '0')
end

function _override_nested(nt::NamedTuple, field::Symbol, value)
    haskey(nt, field) || throw(ArgumentError("cannot override missing field `$(field)`"))
    return (; nt..., field => value)
end

function _override_experiment_parameter(spec, parameter::AbstractString, value)
    parts = split(parameter, ".")
    length(parts) == 2 || throw(ArgumentError(
        "sweep parameter `$parameter` must have shape section.field"))

    section = Symbol(parts[1])
    field = Symbol(parts[2])

    if section == :problem
        field in (:L_fiber, :P_cont, :Nt, :time_window) || throw(ArgumentError(
            "unsupported problem sweep field `$field`; supported: L_fiber, P_cont, Nt, time_window"))
        converted = field == :Nt ? Int(value) : Float64(value)
        return (; spec..., problem = _override_nested(spec.problem, field, converted))
    elseif section == :solver
        field == :max_iter || throw(ArgumentError(
            "unsupported solver sweep field `$field`; supported: max_iter"))
        return (; spec..., solver = _override_nested(spec.solver, field, Int(value)))
    elseif section == :objective
        field == :kind || throw(ArgumentError(
            "unsupported objective sweep field `$field`; supported: kind"))
        return (; spec..., objective = _override_nested(spec.objective, field, _normalize_symbol(value)))
    end

    throw(ArgumentError(
        "unsupported sweep section `$section`; supported sections: problem, solver, objective"))
end

function expand_experiment_sweep(sweep_spec)
    base = load_experiment_spec(sweep_spec.base_experiment)
    validate_experiment_spec(base)

    cases = []
    for (idx, value) in enumerate(sweep_spec.sweep.values)
        label = _case_label(sweep_spec, idx)
        case_spec = _override_experiment_parameter(base, sweep_spec.sweep.parameter, value)
        case_spec = (;
            case_spec...,
            id = string(sweep_spec.id, "__", label),
            description = string(sweep_spec.description, " [", sweep_spec.sweep.parameter, "=", value, "]"),
            output_root = sweep_spec.output_root,
            output_tag = string(sweep_spec.output_tag, "__", label),
        )
        validate_experiment_spec(case_spec)
        push!(cases, (
            label = label,
            value = value,
            spec = case_spec,
        ))
    end

    return (
        sweep_spec = sweep_spec,
        base_spec = base,
        cases = Tuple(cases),
    )
end

function experiment_sweep_output_dir(sweep_spec;
                                     timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"),
                                     create::Bool=true)
    dir = joinpath(sweep_spec.output_root, string(sweep_spec.output_tag, "_", timestamp))
    create && mkpath(dir)
    return dir
end

function experiment_sweep_output_directories(sweep_spec; require_summary::Bool=true)
    isdir(sweep_spec.output_root) || return String[]
    prefix = string(sweep_spec.output_tag, "_")
    dirs = String[]
    for entry in readdir(sweep_spec.output_root; join=true)
        isdir(entry) || continue
        startswith(basename(entry), prefix) || continue
        if require_summary && !isfile(joinpath(entry, "SWEEP_SUMMARY.md"))
            continue
        end
        push!(dirs, entry)
    end
    sort!(dirs; by=basename)
    return dirs
end

function latest_experiment_sweep_output_dir(sweep_spec; require_summary::Bool=true)
    dirs = experiment_sweep_output_directories(sweep_spec; require_summary=require_summary)
    isempty(dirs) && throw(ArgumentError(
        "no completed sweep outputs found for sweep `$(sweep_spec.id)` under `$(sweep_spec.output_root)`"))
    return last(dirs)
end

function render_experiment_sweep_plan(sweep_spec; io::Union{Nothing,IO}=nothing)
    expanded = expand_experiment_sweep(sweep_spec)
    lines = String[
        "Experiment sweep: $(sweep_spec.id)",
        "Description: $(sweep_spec.description)",
        "Base experiment: $(sweep_spec.base_experiment)",
        "Parameter: parameter=$(sweep_spec.sweep.parameter)",
        "Cases: $(length(expanded.cases))",
        "Execution mode: $(sweep_spec.execution.mode)",
        "No command in this plan launches optimization unless the sweep runner is called with --execute.",
    ]
    for case in expanded.cases
        push!(lines,
            "  $(case.label): value=$(case.value) mode=$(experiment_execution_mode(case.spec)) output_tag=$(case.spec.output_tag)")
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function validate_all_experiment_sweeps(; ids=approved_experiment_sweep_config_ids())
    reports = []
    for id in ids
        try
            sweep_spec = load_experiment_sweep_spec(id)
            expanded = expand_experiment_sweep(sweep_spec)
            push!(reports, (
                id = id,
                ok = true,
                cases = length(expanded.cases),
                base_experiment = sweep_spec.base_experiment,
                parameter = sweep_spec.sweep.parameter,
                error = "",
            ))
        catch err
            push!(reports, (
                id = id,
                ok = false,
                cases = 0,
                base_experiment = "",
                parameter = "",
                error = sprint(showerror, err),
            ))
        end
    end

    passed = count(report -> report.ok, reports)
    failed = length(reports) - passed
    return (
        complete = failed == 0,
        total = length(reports),
        passed = passed,
        failed = failed,
        reports = Tuple(reports),
    )
end

function render_experiment_sweep_validation_report(report; io::IO=stdout)
    println(io, "Experiment sweep validation: complete=$(report.complete) passed=$(report.passed) failed=$(report.failed) total=$(report.total)")
    for item in report.reports
        if item.ok
            println(io,
                "  [ok] ",
                item.id,
                "  base=", item.base_experiment,
                "  parameter=", item.parameter,
                "  cases=", item.cases)
        else
            println(io, "  [fail] ", item.id, "  ", item.error)
        end
    end
    return nothing
end

function _sweep_cell(value)
    if isnothing(value) || ismissing(value)
        return ""
    else
        return string(value)
    end
end

function _sweep_metric_cell(value)
    if isnothing(value) || ismissing(value) || value == ""
        return ""
    elseif value isa AbstractFloat
        return isfinite(value) ? Printf.format(Printf.Format("%.2f"), value) : ""
    else
        return string(value)
    end
end

function _sweep_summary_field(result, field::Symbol)
    if result.summary === nothing
        return ""
    end
    return hasproperty(result.summary, field) ? getproperty(result.summary, field) : ""
end

function _sweep_result_field(result, field::Symbol)
    return hasproperty(result, field) ? getproperty(result, field) : ""
end

function _sweep_json_value(value)
    if isnothing(value) || ismissing(value) || value == ""
        return nothing
    elseif value isa Symbol
        return string(value)
    else
        return value
    end
end

function _csv_cell(value)
    text = if isnothing(value) || ismissing(value)
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

function _sweep_summary_row(result)
    status = string(result.status)
    artifact_or_error = status == "complete" ?
        String(result.artifact_path) :
        (hasproperty(result, :error) ? String(result.error) : "")
    return Dict{String,Any}(
        "case" => String(result.label),
        "value" => result.value,
        "status" => status,
        "artifact_status" => _sweep_json_value(_sweep_result_field(result, :artifact_status)),
        "trust_report_status" => _sweep_json_value(_sweep_result_field(result, :trust_report_status)),
        "standard_images_status" => _sweep_json_value(_sweep_result_field(result, :standard_images_status)),
        "J_before_dB" => _sweep_json_value(_sweep_summary_field(result, :J_before_dB)),
        "J_after_dB" => _sweep_json_value(_sweep_summary_field(result, :J_after_dB)),
        "delta_J_dB" => _sweep_json_value(_sweep_summary_field(result, :delta_J_dB)),
        "quality" => _sweep_json_value(_sweep_summary_field(result, :quality)),
        "converged" => _sweep_json_value(_sweep_summary_field(result, :converged)),
        "iterations" => _sweep_json_value(_sweep_summary_field(result, :iterations)),
        "output_dir" => _sweep_json_value(_sweep_result_field(result, :output_dir)),
        "artifact_path" => _sweep_json_value(_sweep_result_field(result, :artifact_path)),
        "artifact_or_error" => artifact_or_error,
        "error" => status == "complete" ? nothing : _sweep_json_value(artifact_or_error),
    )
end

function experiment_sweep_summary_payload(sweep_spec, results)
    rows = [_sweep_summary_row(result) for result in results]
    return Dict{String,Any}(
        "schema" => "experiment_sweep_summary_v1",
        "sweep_id" => String(sweep_spec.id),
        "description" => String(sweep_spec.description),
        "base_experiment" => String(sweep_spec.base_experiment),
        "parameter" => String(sweep_spec.sweep.parameter),
        "cases" => rows,
        "case_count" => length(rows),
        "complete" => count(row -> row["status"] == "complete", rows),
        "failed" => count(row -> row["status"] == "failed", rows),
        "skipped" => count(row -> row["status"] == "skipped", rows),
        "generated_by" => "scripts/canonical/run_experiment_sweep.jl",
    )
end

function render_experiment_sweep_summary_csv(sweep_spec, results)
    columns = (
        "case",
        "value",
        "status",
        "artifact_status",
        "trust_report_status",
        "standard_images_status",
        "J_before_dB",
        "J_after_dB",
        "delta_J_dB",
        "quality",
        "converged",
        "iterations",
        "output_dir",
        "artifact_path",
        "artifact_or_error",
        "error",
    )
    payload = experiment_sweep_summary_payload(sweep_spec, results)
    lines = [join(columns, ",")]
    for row in payload["cases"]
        push!(lines, join((_csv_cell(get(row, column, nothing)) for column in columns), ","))
    end
    return join(lines, "\n")
end

function write_experiment_sweep_summary_files(sweep_spec, results, sweep_dir::AbstractString)
    summary_md = render_experiment_sweep_summary(sweep_spec, results)
    summary_csv = render_experiment_sweep_summary_csv(sweep_spec, results)
    payload = experiment_sweep_summary_payload(sweep_spec, results)

    md_path = joinpath(sweep_dir, "SWEEP_SUMMARY.md")
    json_path = joinpath(sweep_dir, "SWEEP_SUMMARY.json")
    csv_path = joinpath(sweep_dir, "SWEEP_SUMMARY.csv")

    write(md_path, summary_md)
    open(json_path, "w") do io
        JSON3.pretty(io, payload)
    end
    write(csv_path, summary_csv)

    return (
        summary_path = md_path,
        summary_json_path = json_path,
        summary_csv_path = csv_path,
    )
end

function render_experiment_sweep_summary(sweep_spec, results)
    lines = String[
        "# Experiment Sweep Summary: $(sweep_spec.id)",
        "",
        "Description: $(sweep_spec.description)",
        "",
        "- Base experiment: `$(sweep_spec.base_experiment)`",
        "- Parameter: `$(sweep_spec.sweep.parameter)`",
        "- Cases: `$(length(results))`",
        "",
        "| Case | Value | Status | Artifact Status | Trust | Standard Images | J_before [dB] | J_after [dB] | ΔJ [dB] | Quality | Converged | Iterations | Artifact / Error |",
        "|---|---:|---|---|---|---|---:|---:|---:|---|---|---:|---|",
    ]

    for result in results
        status = string(result.status)
        artifact_or_error = status == "complete" ?
            String(result.artifact_path) :
            (hasproperty(result, :error) ? String(result.error) : "")
        cells = (
            result.label,
            _sweep_cell(result.value),
            status,
            _sweep_cell(_sweep_result_field(result, :artifact_status)),
            _sweep_cell(_sweep_result_field(result, :trust_report_status)),
            _sweep_cell(_sweep_result_field(result, :standard_images_status)),
            _sweep_metric_cell(_sweep_summary_field(result, :J_before_dB)),
            _sweep_metric_cell(_sweep_summary_field(result, :J_after_dB)),
            _sweep_metric_cell(_sweep_summary_field(result, :delta_J_dB)),
            _sweep_cell(_sweep_summary_field(result, :quality)),
            _sweep_cell(_sweep_summary_field(result, :converged)),
            _sweep_cell(_sweep_summary_field(result, :iterations)),
            artifact_or_error,
        )
        push!(lines, string("| ", join(cells, " | "), " |"))
    end

    push!(lines, "")
    push!(lines, "Generated by `scripts/canonical/run_experiment_sweep.jl`.")
    return join(lines, "\n")
end

end # include guard
