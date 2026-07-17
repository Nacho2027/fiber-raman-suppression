"""
Validate and inspect front-layer experiment sweeps.

Usage:
    julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --list
    julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --validate-all
    julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --dry-run [sweep]
    julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --execute sweep
    julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --latest [sweep]

This command defaults to planning. Execution is explicit and currently limited
to locally supported front-layer experiment modes.
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end

include(joinpath(@__DIR__, "..", "lib", "experiment_sweep.jl"))
include(joinpath(@__DIR__, "..", "lib", "experiment_runner.jl"))

function _sweep_case_execution_allowed(case)
    mode = experiment_execution_mode(case.spec)
    return mode in (:phase_only, :multivar)
end

function _sweep_case_artifact_status(run_bundle)
    if !hasproperty(run_bundle, :artifact_validation)
        return (
            artifact_status = "not_run",
            trust_report_status = "unknown",
            standard_images_status = "unknown",
        )
    end

    report = run_bundle.artifact_validation
    trust_status = if run_bundle.spec.artifacts.write_trust_report
        isfile(report.trust_report_path) ? "present" : "missing"
    else
        "not_required"
    end
    return (
        artifact_status = report.complete ? "complete" : "incomplete",
        trust_report_status = trust_status,
        standard_images_status = report.standard_images.complete ? "complete" : "incomplete",
    )
end

function experiment_sweep_execution_status(results)
    complete = count(result -> result.status == :complete, results)
    failed = count(result -> result.status == :failed, results)
    skipped = count(result -> result.status == :skipped, results)
    return (
        pass = failed == 0 && skipped == 0,
        total = length(results),
        complete = complete,
        failed = failed,
        skipped = skipped,
    )
end

function execute_experiment_sweep(sweep_spec;
                                  timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"))
    expanded = expand_experiment_sweep(sweep_spec)
    sweep_spec.maturity == "supported" || throw(ArgumentError(
        "experimental sweep `$(sweep_spec.id)` is planning-only; promote it before execution"))
    experimental_cases = [case.label for case in expanded.cases
                          if case.spec.maturity != "supported"]
    isempty(experimental_cases) || throw(ArgumentError(
        "sweep `$(sweep_spec.id)` contains experimental cases and is planning-only: " *
        join(experimental_cases, ", ")))
    sweep_dir = experiment_sweep_output_dir(sweep_spec; timestamp=timestamp)
    cp(sweep_spec.config_path, joinpath(sweep_dir, "sweep_config.toml"); force=true)

    results = []
    for case in expanded.cases
        if !_sweep_case_execution_allowed(case)
            push!(results, (
                label = case.label,
                value = case.value,
                status = :skipped,
                output_dir = "",
                artifact_path = "",
                summary = nothing,
                error = "execution mode $(experiment_execution_mode(case.spec)) is planning-only for sweeps",
            ))
            continue
        end

        try
            run_bundle = run_supported_experiment(
                case.spec;
                timestamp=timestamp,
                run_context=:sweep,
                run_command="./fiberlab sweep run $(sweep_spec.id)",
            )
            summary = canonical_run_summary(run_bundle.artifact_path)
            artifact_status = _sweep_case_artifact_status(run_bundle)
            push!(results, (;
                label = case.label,
                value = case.value,
                status = :complete,
                output_dir = run_bundle.output_dir,
                artifact_path = run_bundle.artifact_path,
                summary = summary,
                artifact_status...,
            ))
        catch err
            push!(results, (
                label = case.label,
                value = case.value,
                status = :failed,
                output_dir = "",
                artifact_path = "",
                summary = nothing,
                error = sprint(showerror, err),
            ))
        end
    end

    summary_files = write_experiment_sweep_summary_files(sweep_spec, Tuple(results), sweep_dir)
    status = experiment_sweep_execution_status(results)
    return (
        sweep_spec = sweep_spec,
        output_dir = sweep_dir,
        summary_path = summary_files.summary_path,
        summary_json_path = summary_files.summary_json_path,
        summary_csv_path = summary_files.summary_csv_path,
        results = Tuple(results),
        status = status,
    )
end

function _print_available_experiment_sweeps()
    println("Front-layer experiment sweeps:")
    for id in approved_experiment_sweep_config_ids()
        spec = load_experiment_sweep_spec(id)
        println("  ", spec.id, "  —  ", spec.description, "  [", spec.maturity, "]")
    end
end

function _load_or_default_sweep(args)
    ids = approved_experiment_sweep_config_ids()
    isempty(ids) && throw(ArgumentError("no approved experiment sweep configs found"))
    return isempty(args) ? first(ids) : args[1]
end

function run_experiment_sweep_main(args=ARGS)
    if isempty(args) || args[1] == "--dry-run"
        length(args) in (0, 1, 2) || error("usage: scripts/canonical/run_experiment_sweep.jl --dry-run [sweep]")
        spec_name = isempty(args) ? _load_or_default_sweep(String[]) : _load_or_default_sweep(args[2:end])
        sweep_spec = load_experiment_sweep_spec(spec_name)
        println(render_experiment_sweep_plan(sweep_spec))
        return sweep_spec
    end

    if args[1] == "--list"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment_sweep.jl --list")
        _print_available_experiment_sweeps()
        return nothing
    end

    if args[1] == "--validate-all"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment_sweep.jl --validate-all")
        report = validate_all_experiment_sweeps()
        render_experiment_sweep_validation_report(report)
        report.complete || error("one or more experiment sweeps failed validation")
        return report
    end

    if args[1] == "--execute"
        length(args) == 2 || error("usage: scripts/canonical/run_experiment_sweep.jl --execute sweep")
        spec_name = _load_or_default_sweep(args[2:end])
        sweep_spec = load_experiment_sweep_spec(spec_name)
        result = execute_experiment_sweep(sweep_spec)
        println(result.status.pass ? "Experiment sweep complete" : "Experiment sweep incomplete")
        println("Cases: complete=$(result.status.complete) failed=$(result.status.failed) skipped=$(result.status.skipped) total=$(result.status.total)")
        println("Output directory: ", result.output_dir)
        println("Summary: ", result.summary_path)
        println("Summary JSON: ", result.summary_json_path)
        println("Summary CSV: ", result.summary_csv_path)
        println()
        print(read(result.summary_path, String))
        result.status.pass || error(
            "experiment sweep incomplete: failed=$(result.status.failed), skipped=$(result.status.skipped); summary=$(result.summary_path)")
        return result
    end

    if args[1] == "--latest"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment_sweep.jl --latest [sweep]")
        spec_name = _load_or_default_sweep(args[2:end])
        sweep_spec = load_experiment_sweep_spec(spec_name)
        latest_dir = try
            latest_experiment_sweep_output_dir(sweep_spec)
        catch err
            err isa ArgumentError || rethrow()
            throw(ArgumentError(
                "no completed sweeps found for $(sweep_spec.id) under $(sweep_spec.output_root); " *
                "run it first with `./fiberlab sweep run $spec_name`"))
        end
        summary_path = joinpath(latest_dir, "SWEEP_SUMMARY.md")
        println("Latest sweep for $(sweep_spec.id): ", latest_dir)
        println("Summary: ", summary_path)
        println()
        print(read(summary_path, String))
        return (
            sweep_spec = sweep_spec,
            output_dir = latest_dir,
            summary_path = summary_path,
        )
    end

    length(args) == 1 || error(
        "usage: scripts/canonical/run_experiment_sweep.jl [sweep | --dry-run [sweep] | --execute sweep | --latest [sweep] | --list | --validate-all]")
    sweep_spec = load_experiment_sweep_spec(args[1])
    println(render_experiment_sweep_plan(sweep_spec))
    return sweep_spec
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_experiment_sweep_main(ARGS)
end
