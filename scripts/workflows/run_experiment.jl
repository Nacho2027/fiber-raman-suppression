"""
Run one validated front-layer experiment config.

Usage:
    julia --project=. -t auto scripts/canonical/run_experiment.jl
    julia --project=. -t auto scripts/canonical/run_experiment.jl research_engine_poc
    julia --project=. -t auto scripts/canonical/run_experiment.jl path/to/experiment.toml
    julia --project=. -t auto scripts/canonical/run_experiment.jl smf28_L2m_P0p2W
    julia --project=. -t auto scripts/canonical/run_experiment.jl --list
    julia --project=. -t auto scripts/canonical/run_experiment.jl --objectives
    julia --project=. -t auto scripts/canonical/run_experiment.jl --dry-run [spec]

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

    if args[1] == "--objectives"
        length(args) == 1 || error("usage: scripts/canonical/run_experiment.jl --objectives")
        render_objective_registry()
        return nothing
    end

    if args[1] == "--dry-run"
        length(args) in (1, 2) || error("usage: scripts/canonical/run_experiment.jl --dry-run [spec]")
        spec = load_experiment_spec(_load_or_default_experiment(args[2:end]))
        validate_experiment_spec(spec)
        println(render_experiment_plan(spec))
        return spec
    end

    length(args) == 1 || error(
        "usage: scripts/canonical/run_experiment.jl [spec | --list | --objectives | --dry-run [spec]]")

    spec = load_experiment_spec(args[1])
    result = run_supported_experiment(spec)

    if spec.export_plan.enabled || spec.artifacts.export_phase_handoff
        export_dir = joinpath(result.output_dir, "export_handoff")
        exported = export_run_bundle(result.artifact_path, export_dir)
        @info "Exported front-layer handoff bundle" output_dir=exported.output_dir
        completed = (; result..., exported=exported)
        render_experiment_completion_summary(completed)
        return completed
    end

    render_experiment_completion_summary(result)
    return result
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_experiment_main(ARGS)
end
