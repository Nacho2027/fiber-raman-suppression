"""
Run lab-readiness gates for configs and completed run bundles.

Usage:
    julia -t auto --project=. scripts/canonical/lab_ready.jl --config SPEC
    julia -t auto --project=. scripts/canonical/lab_ready.jl --run RUN_DIR_OR_ARTIFACT
    julia -t auto --project=. scripts/canonical/lab_ready.jl --latest SPEC

Options:
    --require-export       Require a complete export_handoff bundle for run gates.
    --help                 Show this message.
"""

include(joinpath(@__DIR__, "..", "lib", "experiment_spec.jl"))
include(joinpath(@__DIR__, "inspect_run.jl"))

function _lab_ready_usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/lab_ready.jl --config SPEC
    julia -t auto --project=. scripts/canonical/lab_ready.jl --run RUN_DIR_OR_ARTIFACT
    julia -t auto --project=. scripts/canonical/lab_ready.jl --latest SPEC

Options:
    --require-export       Require a complete export_handoff bundle for run gates.
    --help                 Show this message.
"""
end

function parse_lab_ready_args(args)
    isempty(args) && error(_lab_ready_usage())

    mode = nothing
    target = nothing
    require_export = false

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            return (help = true,)
        elseif arg == "--require-export"
            require_export = true
        elseif arg in ("--config", "--run", "--latest")
            isnothing(mode) || error("choose only one lab-ready mode: --config, --run, or --latest")
            i += 1
            i <= length(args) || error("$arg requires a value")
            mode = Symbol(arg[3:end])
            target = args[i]
        else
            error("unknown lab_ready option: $arg")
        end
        i += 1
    end

    isnothing(mode) && error("choose one lab-ready mode: --config, --run, or --latest")
    return (
        help = false,
        mode = mode,
        target = target,
        require_export = require_export,
    )
end

function _push_blocker!(blockers, condition::Bool, label::AbstractString)
    condition || push!(blockers, String(label))
    return blockers
end

function _lab_ready_config_report(spec)
    blockers = String[]
    validation_error = ""
    mode = :unknown

    try
        validate_experiment_spec(spec)
        mode = experiment_execution_mode(spec)
    catch err
        validation_error = sprint(showerror, err)
        push!(blockers, "config_validation_failed")
    end

    objective_extensions = validate_objective_extension_contracts()
    variable_extensions = validate_variable_extension_contracts()
    objective_extensions.invalid == 0 || push!(blockers, "invalid_objective_extensions")
    variable_extensions.invalid == 0 || push!(blockers, "invalid_variable_extensions")

    if isempty(validation_error)
        mode in (:phase_only, :multivar) || push!(blockers, "planning_only_execution_mode")
        spec.verification.artifact_validation || push!(blockers, "artifact_validation_disabled")
        spec.verification.block_on_failed_checks || push!(blockers, "failed_checks_do_not_block")
        if experiment_export_requested(spec) && mode != :phase_only
            push!(blockers, "export_requested_for_unsupported_mode")
        end
    end

    return (
        kind = :config,
        target = spec.id,
        config_path = spec.config_path,
        mode = mode,
        maturity = spec.maturity,
        regime = spec.problem.regime,
        variables = spec.controls.variables,
        objective = spec.objective.kind,
        solver = spec.solver.kind,
        export_requested = isempty(validation_error) ? experiment_export_requested(spec) : false,
        objective_extension_invalid = objective_extensions.invalid,
        variable_extension_invalid = variable_extensions.invalid,
        valid = isempty(validation_error),
        validation_error = validation_error,
        blockers = Tuple(blockers),
        pass = isempty(blockers),
    )
end

function lab_ready_config_report(spec::AbstractString)
    return _lab_ready_config_report(load_experiment_spec(spec))
end

function _sidecar_for_artifact(path::AbstractString)
    if endswith(path, ".jld2")
        json_path = replace(path, r"\.jld2$" => ".json")
        isfile(json_path) && return json_path
        prefix = _artifact_result_prefix(path)
        slm_path = string(prefix, "_slm.json")
        isfile(slm_path) && return slm_path
        return json_path
    end
    endswith(path, ".json") && return path
    return string(path, ".json")
end

function _lab_ready_run_spec(run_config)
    ismissing(run_config) && return nothing
    try
        return load_experiment_spec(String(run_config))
    catch
        return nothing
    end
end

function _lab_ready_trust_required(spec)
    isnothing(spec) && return true
    return any(request -> request.hook == :trust_report, experiment_artifact_plan(spec).hooks)
end

function _lab_ready_extra_artifacts(spec, artifact_path::AbstractString)
    isnothing(spec) && return (
        complete = true,
        checked = String[],
        missing = String[],
        paths = Dict{Symbol,Tuple{Vararg{String}}}(),
        hooks = Symbol[],
    )
    return extra_artifact_hook_file_status(spec, _artifact_result_prefix(artifact_path))
end

function lab_ready_run_report(path::AbstractString; require_export::Bool=false)
    blockers = String[]
    summary = inspect_run_summary(path)
    sidecar_path = _sidecar_for_artifact(String(summary.artifact))
    run_spec = _lab_ready_run_spec(summary.run_config)
    trust_required = _lab_ready_trust_required(run_spec)
    extra_artifacts = _lab_ready_extra_artifacts(run_spec, String(summary.artifact))

    _push_blocker!(blockers, isfile(String(summary.artifact)), "missing_result_artifact")
    _push_blocker!(blockers, isfile(sidecar_path), "missing_json_sidecar")
    _push_blocker!(blockers, !ismissing(summary.run_config), "missing_run_config")
    _push_blocker!(blockers, !trust_required || !isempty(summary.trust_reports), "missing_trust_report")
    _push_blocker!(blockers, summary.standard_images.complete, "missing_standard_images")
    _push_blocker!(blockers, extra_artifacts.complete, "missing_variable_artifacts")
    _push_blocker!(blockers, summary.converged === true, "not_converged")
    _push_blocker!(blockers, isfinite(Float64(summary.J_after_dB)), "missing_objective_metric")
    if require_export
        if !summary.export_handoff.files_complete
            push!(blockers, "missing_export_handoff")
        elseif !summary.export_handoff.phase_csv_valid
            push!(blockers, "invalid_export_phase_csv")
        end
    end

    return (
        kind = :run,
        target = path,
        artifact = String(summary.artifact),
        artifact_dir = String(summary.artifact_dir),
        sidecar_path = sidecar_path,
        run_config = summary.run_config,
        trust_reports = Tuple(summary.trust_reports),
        trust_report_required = trust_required,
        standard_images_complete = summary.standard_images.complete,
        standard_images_missing = Tuple(summary.standard_images.missing),
        variable_artifacts_complete = extra_artifacts.complete,
        variable_artifact_hooks = Tuple(extra_artifacts.hooks),
        variable_artifact_paths = Tuple(extra_artifacts.checked),
        variable_artifacts_missing = Tuple(extra_artifacts.missing),
        export_handoff_complete = summary.export_handoff.complete,
        export_handoff_files_complete = summary.export_handoff.files_complete,
        export_handoff_dir = summary.export_handoff.dir,
        export_phase_csv_valid = summary.export_handoff.phase_csv_valid,
        export_phase_csv_rows = summary.export_handoff.phase_csv_rows,
        export_phase_csv_errors = Tuple(summary.export_handoff.phase_csv_errors),
        converged = summary.converged,
        quality = summary.quality,
        J_after_dB = summary.J_after_dB,
        delta_J_dB = summary.delta_J_dB,
        blockers = Tuple(blockers),
        pass = isempty(blockers),
    )
end

function lab_ready_latest_report(spec::AbstractString; require_export::Bool=false)
    loaded = load_experiment_spec(spec)
    validate_experiment_spec(loaded)
    latest_dir = _lab_ready_latest_output_dir(loaded)
    run_report = lab_ready_run_report(latest_dir; require_export=require_export)
    return (; run_report..., kind = :latest, target = spec, latest_dir = latest_dir)
end

function _lab_ready_experiment_output_dirs(spec; require_artifact::Bool=true)
    isdir(spec.output_root) || return String[]
    prefix = string(spec.output_tag, "_")
    dirs = String[]
    for entry in readdir(spec.output_root; join=true)
        isdir(entry) || continue
        startswith(basename(entry), prefix) || continue
        if require_artifact
            try
                resolve_run_artifact_path(entry)
            catch
                continue
            end
        end
        push!(dirs, entry)
    end
    sort!(dirs; by=basename)
    return dirs
end

function _lab_ready_latest_output_dir(spec; require_artifact::Bool=true)
    dirs = _lab_ready_experiment_output_dirs(spec; require_artifact=require_artifact)
    isempty(dirs) && throw(ArgumentError(
        "no completed runs found for experiment `$(spec.id)` under `$(spec.output_root)`"))
    return last(dirs)
end

function _status_word(report)
    return report.pass ? "PASS" : "FAIL"
end

function render_lab_ready_report(report; io::IO=stdout)
    println(io, "# Lab Readiness Gate")
    println(io)
    println(io, "- Scope: `", report.kind, "`")
    println(io, "- Target: `", report.target, "`")
    println(io, "- Status: `", _status_word(report), "`")
    println(io, "- Blockers: `", isempty(report.blockers) ? "none" : join(report.blockers, ","), "`")

    if report.kind == :config
        println(io, "- Config path: `", report.config_path, "`")
        println(io, "- Execution mode: `", report.mode, "`")
        println(io, "- Maturity: `", report.maturity, "`")
        println(io, "- Regime: `", report.regime, "`")
        println(io, "- Variables: `", join(string.(report.variables), ","), "`")
        println(io, "- Objective: `", report.objective, "`")
        println(io, "- Solver: `", report.solver, "`")
        println(io, "- Export requested: `", report.export_requested, "`")
        println(io, "- Invalid objective extensions: `", report.objective_extension_invalid, "`")
        println(io, "- Invalid variable extensions: `", report.variable_extension_invalid, "`")
        if !isempty(report.validation_error)
            println(io, "- Validation error: `", report.validation_error, "`")
        end
    else
        if hasproperty(report, :latest_dir)
            println(io, "- Latest dir: `", report.latest_dir, "`")
        end
        println(io, "- Artifact: `", report.artifact, "`")
        println(io, "- Sidecar: `", report.sidecar_path, "`")
        println(io, "- Run config: `", ismissing(report.run_config) ? "missing" : report.run_config, "`")
        println(io, "- Trust report required: `", report.trust_report_required, "`")
        println(io, "- Trust reports: `", isempty(report.trust_reports) ? "none" : join(report.trust_reports, ","), "`")
        println(io, "- Standard images complete: `", report.standard_images_complete, "`")
        if !isempty(report.standard_images_missing)
            println(io, "- Standard images missing: `", join(report.standard_images_missing, ","), "`")
        end
        println(io, "- Variable artifacts complete: `", report.variable_artifacts_complete, "`")
        if !isempty(report.variable_artifact_hooks)
            println(io, "- Variable artifact hooks: `", join(string.(report.variable_artifact_hooks), ","), "`")
        end
        if !isempty(report.variable_artifacts_missing)
            println(io, "- Variable artifacts missing: `", join(report.variable_artifacts_missing, ","), "`")
        end
        println(io, "- Export handoff complete: `", report.export_handoff_complete, "`")
        println(io, "- Export phase CSV valid: `", report.export_phase_csv_valid, "`")
        println(io, "- Export phase CSV rows: `", report.export_phase_csv_rows, "`")
        if !isempty(report.export_phase_csv_errors)
            println(io, "- Export phase CSV errors: `", join(report.export_phase_csv_errors, ","), "`")
        end
        println(io, "- Converged: `", report.converged, "`")
        println(io, "- Quality: `", report.quality, "`")
        println(io, "- J_after_dB: `", report.J_after_dB, "`")
        println(io, "- Delta_J_dB: `", report.delta_J_dB, "`")
    end
    return nothing
end

function lab_ready_main(args=ARGS)
    parsed = parse_lab_ready_args(String.(args))
    if parsed.help
        println(_lab_ready_usage())
        return nothing
    end

    report = if parsed.mode == :config
        lab_ready_config_report(parsed.target)
    elseif parsed.mode == :run
        lab_ready_run_report(parsed.target; require_export=parsed.require_export)
    elseif parsed.mode == :latest
        lab_ready_latest_report(parsed.target; require_export=parsed.require_export)
    else
        error("unknown lab-ready mode: $(parsed.mode)")
    end

    render_lab_ready_report(report)
    report.pass || error("lab-readiness gate failed: $(join(report.blockers, ", "))")
    return report
end

if abspath(PROGRAM_FILE) == @__FILE__
    lab_ready_main(ARGS)
end
