"""
Run one validated front-layer experiment config.

Usage:
    julia --project=. -t auto scripts/canonical/run_experiment.jl research_engine_poc
    julia --project=. -t auto scripts/canonical/run_experiment.jl path/to/experiment.toml
    julia --project=. -t auto scripts/canonical/run_experiment.jl --list
    julia --project=. -t auto scripts/canonical/run_experiment.jl --capabilities
    julia --project=. -t auto scripts/canonical/run_experiment.jl --objectives
    julia --project=. -t auto scripts/canonical/run_experiment.jl --validate-objectives
    julia --project=. -t auto scripts/canonical/run_experiment.jl --variables
    julia --project=. -t auto scripts/canonical/run_experiment.jl --validate-variables
    julia --project=. -t auto scripts/canonical/run_experiment.jl --control-layout [spec]
    julia --project=. -t auto scripts/canonical/run_experiment.jl --artifact-plan [spec]
    julia --project=. -t auto scripts/canonical/run_experiment.jl --check [spec]
    julia --project=. -t auto scripts/canonical/run_experiment.jl --validate-all
    julia --project=. -t auto scripts/canonical/run_experiment.jl --dry-run [spec]
    julia --project=. -t auto scripts/canonical/run_experiment.jl --compute-plan [spec]
    julia --project=. -t auto scripts/canonical/run_experiment.jl --explore-plan [spec]
    julia --project=. -t auto scripts/canonical/run_experiment.jl --exploration-check [--local-smoke] [--heavy-ok] spec
    julia --project=. -t auto scripts/canonical/run_experiment.jl --explore-run [--local-smoke] [--heavy-ok] [--dry-run] spec
    julia --project=. -t auto scripts/canonical/run_experiment.jl --heavy-ok spec
    julia --project=. -t auto scripts/canonical/run_experiment.jl --latest [spec]

Configs under `configs/experiments/` select validated execution modes. Heavy
long-fiber and multimode runs require explicit acknowledgement.
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Logging

include(joinpath(@__DIR__, "..", "lib", "experiment_runner.jl"))
include(joinpath(@__DIR__, "export_run.jl"))
include(joinpath(@__DIR__, "inspect_run.jl"))
ensure_deterministic_environment()

function _print_available_experiment_configs(; io::IO=stdout)
    println(io, "Front-layer experiment configs:")
    for config_id in approved_experiment_config_ids()
        spec = load_experiment_spec(config_id)
        println(io, "  ", config_id, "  —  ", spec.description,
            "  [experiment_id=", spec.id, ", ", spec.maturity, "]")
    end
end

function _load_or_default_experiment(args)
    return isempty(args) ? DEFAULT_EXPERIMENT_SPEC : args[1]
end

function _parse_exploration_check_args(args)
    local_smoke = false
    heavy_ok = false
    specs = String[]

    for arg in args
        if arg == "--local-smoke"
            local_smoke = true
        elseif arg == "--heavy-ok"
            heavy_ok = true
        elseif startswith(arg, "--")
            error("unknown --exploration-check option `$arg`")
        else
            push!(specs, arg)
        end
    end

    length(specs) == 1 || error(
        "usage: scripts/canonical/run_experiment.jl --exploration-check [--local-smoke] [--heavy-ok] spec")
    return (
        spec = only(specs),
        local_smoke = local_smoke,
        heavy_ok = heavy_ok,
    )
end

function _parse_explore_run_args(args)
    local_smoke = false
    heavy_ok = false
    dry_run = false
    specs = String[]

    for arg in args
        if arg == "--local-smoke"
            local_smoke = true
        elseif arg == "--heavy-ok"
            heavy_ok = true
        elseif arg == "--dry-run"
            dry_run = true
        elseif startswith(arg, "--")
            error("unknown --explore-run option `$arg`")
        else
            push!(specs, arg)
        end
    end

    length(specs) == 1 || error(
        "usage: scripts/canonical/run_experiment.jl --explore-run [--local-smoke] [--heavy-ok] [--dry-run] spec")
    return (
        spec = only(specs),
        local_smoke = local_smoke,
        heavy_ok = heavy_ok,
        dry_run = dry_run,
    )
end

function run_experiment_main(args=ARGS)
    if isempty(args)
        error("usage: scripts/canonical/run_experiment.jl spec (execution requires an explicit config)")
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

    if args[1] == "--control-layout"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment.jl --control-layout [spec]")
        spec = load_experiment_spec(_load_or_default_experiment(args[2:end]))
        validate_experiment_spec(spec)
        render_control_layout_plan(spec)
        return control_layout_plan(spec)
    end

    if args[1] == "--artifact-plan"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment.jl --artifact-plan [spec]")
        spec = load_experiment_spec(_load_or_default_experiment(args[2:end]))
        validate_experiment_spec(spec)
        render_experiment_artifact_plan(spec)
        return experiment_artifact_plan(spec)
    end

    if args[1] == "--check"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment.jl --check [spec]")
        spec = load_experiment_spec(_load_or_default_experiment(args[2:end]))
        report = research_config_check_report(spec)
        render_research_config_check(report)
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

    if args[1] == "--explore-plan"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment.jl --explore-plan [spec]")
        spec = load_experiment_spec(_load_or_default_experiment(args[2:end]))
        validate_experiment_spec(spec)
        println(render_experiment_plan(spec))
        render_explore_run_policy(spec)
        return spec
    end

    if args[1] == "--exploration-check"
        parsed = _parse_exploration_check_args(args[2:end])
        spec = load_experiment_spec(parsed.spec)
        check = research_config_check_report(spec)
        render_research_config_check(check)
        check.validation_ok || error("exploration check failed config validation")
        extension_report = runtime_check_research_extensions(spec)
        render_runtime_extension_check(extension_report)
        extension_report.complete || error("exploration check failed runtime extension doctor")
        policy = render_explore_run_policy(
            spec;
            local_smoke=parsed.local_smoke,
            heavy_ok=parsed.heavy_ok,
        )
        policy.allowed || error(
            "exploration check failed run policy; blockers: $(join(string.(policy.blockers), ", "))")
        return (
            config = check,
            extensions = extension_report,
            policy = policy,
        )
    end

    if args[1] == "--explore-run"
        parsed = _parse_explore_run_args(args[2:end])
        spec = load_experiment_spec(parsed.spec)
        validate_experiment_spec(spec)
        policy = render_explore_run_policy(
            spec;
            local_smoke=parsed.local_smoke,
            heavy_ok=parsed.heavy_ok,
        )
        if parsed.dry_run && parsed.heavy_ok
            println(render_experiment_compute_plan(spec))
            return spec
        end
        if !policy.allowed
            error(
                "explore run refused; blockers: $(join(string.(policy.blockers), ", ")). " *
                "Use --local-smoke for executable experimental local smoke configs or --heavy-ok for dedicated heavy workflows.")
        end
        if parsed.dry_run
            println(render_experiment_compute_plan(spec))
            return spec
        end
        if policy.action == :front_layer
            command = "./fiberlab explore run $(experiment_cli_spec_hint(spec))" *
                (parsed.local_smoke ? " --local-smoke" : "") *
                (parsed.heavy_ok ? " --heavy-ok" : "")
            result = run_supported_experiment(
                spec;
                run_context=parsed.heavy_ok ? :explore_heavy : :explore_local_smoke,
                run_command=command,
                allow_high_resource=parsed.heavy_ok,
            )
            render_experiment_completion_summary(result)
            return result
        end
        println(render_experiment_compute_plan(spec))
        error(
            "explore run for dedicated workflow `$(policy.mode)` is not launched automatically yet; " *
            "run the command from the compute plan on appropriate compute.")
    end

    if args[1] == "--heavy-ok"
        length(args) == 2 || error("usage: scripts/canonical/run_experiment.jl --heavy-ok spec")
        spec = load_experiment_spec(args[2])
        mode = experiment_execution_mode(spec)
        mode in (:long_fiber_phase, :multimode_phase) || error(
            "--heavy-ok is only needed for high-resource long-fiber or multimode front-layer configs")
        command = "./fiberlab run --heavy-ok $(experiment_cli_spec_hint(spec))"
        result = run_supported_experiment(
            spec;
            run_context=:run_heavy,
            run_command=command,
            allow_high_resource=true,
        )
        render_experiment_completion_summary(result)
        return result
    end

    if args[1] == "--latest"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment.jl --latest [spec]")
        spec = load_experiment_spec(_load_or_default_experiment(args[2:end]))
        validate_experiment_spec(spec)
        latest_dir = try
            latest_experiment_output_dir(spec)
        catch err
            err isa ArgumentError || rethrow()
            hint = isempty(args[2:end]) ? DEFAULT_EXPERIMENT_SPEC : args[2]
            throw(ArgumentError(
                "no completed runs found for $(spec.id) under $(spec.output_root); " *
                "run it first with `./fiberlab run $hint`"))
        end
        println("Latest run for $(spec.id): ", latest_dir)
        summary = inspect_run_summary(latest_dir)
        render_run_summary(summary)
        return summary
    end

    length(args) == 1 || error(
        "usage: scripts/canonical/run_experiment.jl [spec | --list | --capabilities | --objectives | --validate-objectives | --variables | --validate-variables | --control-layout [spec] | --artifact-plan [spec] | --check [spec] | --validate-all | --dry-run [spec] | --compute-plan [spec] | --explore-plan [spec] | --exploration-check [--local-smoke] [--heavy-ok] spec | --explore-run [--local-smoke] [--heavy-ok] [--dry-run] spec | --heavy-ok spec | --latest [spec]]")

    spec = load_experiment_spec(args[1])
    mode = experiment_execution_mode(spec)
    if mode in (:long_fiber_phase, :multimode_phase)
        regime_label = mode == :long_fiber_phase ? "Long-fiber" : "Multimode"
        error(
            "$(regime_label) execution requires explicit high-resource acknowledgement. " *
            "Inspect `./fiberlab compute-plan $(args[1])`, then run " *
            "`./fiberlab run --heavy-ok $(args[1])` on suitable compute.")
    elseif mode == :amp_on_phase
        error(
            "Amp-on-phase refinement uses its dedicated staged workflow. " *
            "Inspect and run the command from `./fiberlab compute-plan $(args[1])`.")
    end
    if spec.maturity != "supported"
        error(
            "Direct execution is reserved for supported configs; `$(spec.id)` is $(spec.maturity). " *
            "Run this experimental config explicitly with " *
            "`./fiberlab explore run $(experiment_cli_spec_hint(spec)) --local-smoke`.")
    end
    command = "./fiberlab run $(experiment_cli_spec_hint(spec))"
    result = run_supported_experiment(spec; run_context=:run, run_command=command)

    render_experiment_completion_summary(result)
    return result
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_experiment_main(ARGS)
end
