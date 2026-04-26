"""
Validate and inspect front-layer experiment sweeps.

Usage:
    julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --list
    julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --validate-all
    julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --dry-run [sweep]
    julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --execute [sweep]

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

function execute_experiment_sweep(sweep_spec;
                                  timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"))
    expanded = expand_experiment_sweep(sweep_spec)
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
            run_bundle = run_supported_experiment(case.spec; timestamp=timestamp)
            summary = canonical_run_summary(run_bundle.artifact_path)
            push!(results, (
                label = case.label,
                value = case.value,
                status = :complete,
                output_dir = run_bundle.output_dir,
                artifact_path = run_bundle.artifact_path,
                summary = summary,
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

    summary_md = render_experiment_sweep_summary(sweep_spec, Tuple(results))
    summary_path = joinpath(sweep_dir, "SWEEP_SUMMARY.md")
    write(summary_path, summary_md)
    return (
        sweep_spec = sweep_spec,
        output_dir = sweep_dir,
        summary_path = summary_path,
        results = Tuple(results),
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
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment_sweep.jl --execute [sweep]")
        spec_name = _load_or_default_sweep(args[2:end])
        sweep_spec = load_experiment_sweep_spec(spec_name)
        result = execute_experiment_sweep(sweep_spec)
        println("Experiment sweep complete")
        println("Output directory: ", result.output_dir)
        println("Summary: ", result.summary_path)
        println()
        print(read(result.summary_path, String))
        return result
    end

    length(args) == 1 || error(
        "usage: scripts/canonical/run_experiment_sweep.jl [sweep | --dry-run [sweep] | --execute [sweep] | --list | --validate-all]")
    sweep_spec = load_experiment_sweep_spec(args[1])
    println(render_experiment_sweep_plan(sweep_spec))
    return sweep_spec
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_experiment_sweep_main(ARGS)
end
