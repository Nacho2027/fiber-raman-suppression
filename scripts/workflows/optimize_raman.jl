"""
Run one approved canonical Raman optimization from a maintained TOML config.

Usage:
    julia --project=. -t auto scripts/canonical/optimize_raman.jl
    julia --project=. -t auto scripts/canonical/optimize_raman.jl smf28_L2m_P0p2W
    julia --project=. -t auto scripts/canonical/optimize_raman.jl path/to/run.toml
    julia --project=. -t auto scripts/canonical/optimize_raman.jl --list
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Dates
using Logging
using Printf

include(joinpath(@__DIR__, "..", "lib", "experiment_runner.jl"))
ensure_deterministic_environment()

function _print_approved_run_configs()
    println("Approved run configs:")
    for id in approved_run_config_ids()
        spec = load_canonical_run_config(id)
        println("  ", spec.id, "  —  ", spec.description)
    end
end

function canonical_optimize_main(args=ARGS)
    if length(args) > 1
        error("usage: scripts/canonical/optimize_raman.jl [run-config-id-or-path | --list]")
    end

    if !isempty(args) && args[1] == "--list"
        _print_approved_run_configs()
        return nothing
    end

    config_spec = isempty(args) ? DEFAULT_CANONICAL_RUN_ID : args[1]
    timestamp = Dates.format(now(UTC), "yyyymmdd_HHMMss")
    spec = load_experiment_spec(config_spec)
    result_bundle = run_supported_experiment(spec; timestamp=timestamp)

    @info "Canonical Raman optimization" config=spec.id output_dir=result_bundle.output_dir config_copy=result_bundle.config_copy
    @info @sprintf("Completed canonical run `%s` → %s", spec.id, result_bundle.output_dir)
    return (
        run_spec = spec,
        experiment_spec = spec,
        output_dir = result_bundle.output_dir,
        save_prefix = result_bundle.save_prefix,
        config_copy = result_bundle.config_copy,
        artifact_path = result_bundle.artifact_path,
        result = result_bundle.result,
        uω0 = result_bundle.uω0,
        fiber = result_bundle.fiber,
        sim = result_bundle.sim,
        band_mask = result_bundle.band_mask,
        Δf = result_bundle.Δf,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    canonical_optimize_main(ARGS)
end
