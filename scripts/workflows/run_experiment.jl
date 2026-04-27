"""
Run one validated front-layer experiment config.

Usage:
    julia --project=. -t auto scripts/canonical/run_experiment.jl
    julia --project=. -t auto scripts/canonical/run_experiment.jl research_engine_poc
    julia --project=. -t auto scripts/canonical/run_experiment.jl path/to/experiment.toml
    julia --project=. -t auto scripts/canonical/run_experiment.jl smf28_L2m_P0p2W
    julia --project=. -t auto scripts/canonical/run_experiment.jl --list
    julia --project=. -t auto scripts/canonical/run_experiment.jl --capabilities
    julia --project=. -t auto scripts/canonical/run_experiment.jl --objectives
    julia --project=. -t auto scripts/canonical/run_experiment.jl --validate-objectives
    julia --project=. -t auto scripts/canonical/run_experiment.jl --variables
    julia --project=. -t auto scripts/canonical/run_experiment.jl --validate-variables
    julia --project=. -t auto scripts/canonical/run_experiment.jl --validate-all
    julia --project=. -t auto scripts/canonical/run_experiment.jl --dry-run [spec]
    julia --project=. -t auto scripts/canonical/run_experiment.jl --compute-plan [spec]
    julia --project=. -t auto scripts/canonical/run_experiment.jl --latest [spec]

The current implementation is intentionally narrow:

- supported execution path: single-mode, phase-only Raman optimization
- supported input sources: front-layer configs under `configs/experiments/*.toml`
  plus adapted legacy canonical run configs under `configs/runs/*.toml`
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Logging

include(joinpath(@__DIR__, "..", "lib", "experiment_runner.jl"))
include(joinpath(@__DIR__, "export_run.jl"))
include(joinpath(@__DIR__, "inspect_run.jl"))
ensure_deterministic_environment()

function _print_available_experiment_configs()
    println("Front-layer experiment configs:")
    for id in approved_experiment_config_ids()
        spec = load_experiment_spec(id)
        println("  ", spec.id, "  —  ", spec.description, "  [", spec.maturity, "]")
    end
    println()
    println("Adapted canonical run configs:")
    for id in approved_run_config_ids()
        spec = load_experiment_spec(id)
        println("  ", spec.id, "  —  ", spec.description, "  [", spec.maturity, "]")
    end
end

function _load_or_default_experiment(args)
    return isempty(args) ? DEFAULT_EXPERIMENT_SPEC : args[1]
end

function run_experiment_main(args=ARGS)
    if isempty(args)
        spec = load_experiment_spec()
        result = run_supported_experiment(spec)
        render_experiment_completion_summary(result)
        return result
    end

    if args[1] == "--list"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment.jl --list")
        _print_available_experiment_configs()
        return nothing
    end

    if args[1] == "--capabilities"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment.jl --capabilities")
        render_experiment_capabilities()
        return nothing
    end

    if args[1] == "--objectives"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment.jl --objectives")
        render_objective_registry()
        return nothing
    end

    if args[1] == "--validate-objectives"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment.jl --validate-objectives")
        report = validate_objective_extension_contracts()
        render_objective_extension_validation_report(report)
        report.invalid == 0 || error("one or more objective extension contracts failed validation")
        return report
    end

    if args[1] == "--variables"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment.jl --variables")
        render_variable_registry()
        return nothing
    end

    if args[1] == "--validate-variables"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment.jl --validate-variables")
        report = validate_variable_extension_contracts()
        render_variable_extension_validation_report(report)
        report.invalid == 0 || error("one or more variable extension contracts failed validation")
        return report
    end

    if args[1] == "--validate-all"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment.jl --validate-all")
        report = validate_all_experiment_configs()
        render_experiment_validation_report(report)
        report.complete || error("one or more experiment configs failed validation")
        return report
    end

    if args[1] == "--dry-run"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment.jl --dry-run [spec]")
        spec = load_experiment_spec(_load_or_default_experiment(args[2:end]))
        validate_experiment_spec(spec)
        println(render_experiment_plan(spec))
        return spec
    end

    if args[1] == "--compute-plan"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment.jl --compute-plan [spec]")
        spec = load_experiment_spec(_load_or_default_experiment(args[2:end]))
        println(render_experiment_compute_plan(spec))
        return spec
    end

    if args[1] == "--latest"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment.jl --latest [spec]")
        spec = load_experiment_spec(_load_or_default_experiment(args[2:end]))
        validate_experiment_spec(spec)
        latest_dir = try
            latest_experiment_output_dir(spec)
        catch err
            err isa ArgumentError || rethrow()
            println(stderr, "No completed runs found for $(spec.id) under $(spec.output_root).")
            println(stderr, "Run it first with: julia -t auto --project=. scripts/canonical/run_experiment.jl ",
                isempty(args[2:end]) ? DEFAULT_EXPERIMENT_SPEC : args[2])
            return nothing
        end
        println("Latest run for $(spec.id): ", latest_dir)
        summary = inspect_run_summary(latest_dir)
        render_run_summary(summary)
        return summary
    end

    length(args) == 1 || error(
        "usage: scripts/canonical/run_experiment.jl [spec | --list | --capabilities | --objectives | --validate-objectives | --variables | --validate-variables | --validate-all | --dry-run [spec] | --compute-plan [spec] | --latest [spec]]")

    spec = load_experiment_spec(args[1])
    mode = experiment_execution_mode(spec)
    if mode in (:long_fiber_phase, :multimode_phase)
        regime_label = mode == :long_fiber_phase ? "Long-fiber" : "Multimode"
        workflow_label = mode == :long_fiber_phase ? "burst long-fiber" : "multimode baseline"
        error(
            "$(regime_label) front-layer configs are validation/dry-run only on this machine. " *
            "Inspect the plan with `julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run $(args[1])`, " *
            "then stage execution through the dedicated $(workflow_label) workflow.")
    end
    result = run_supported_experiment(spec)

    render_experiment_completion_summary(result)
    return result
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_experiment_main(ARGS)
end
