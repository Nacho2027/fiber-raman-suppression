"""
Run a freeform exploration contract bundle.

Usage:
    julia --project=. scripts/canonical/run_exploration_contract.jl [--check] [--dry-run] [--max-iter N] [--output-root DIR] path/to/contract_dir

The bundle must contain `contract.json` and an execution source file. The
execution source defines `loss_gradient(x, context)`, which may implement any
physics/adjoint math the researcher wants.
"""

ENV["MPLBACKEND"] = get(ENV, "MPLBACKEND", "Agg")

include(joinpath(@__DIR__, "..", "lib", "exploration_contract_runner.jl"))

function _parse_exploration_contract_args(args)
    check = false
    dry_run = false
    max_iter = nothing
    output_root = nothing
    bundle = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--check"
            check = true
        elseif arg == "--dry-run"
            dry_run = true
        elseif arg == "--max-iter"
            i == length(args) && error("--max-iter requires a value")
            i += 1
            max_iter = parse(Int, args[i])
        elseif arg == "--output-root"
            i == length(args) && error("--output-root requires a value")
            i += 1
            output_root = args[i]
        elseif startswith(arg, "--")
            error("unknown run_exploration_contract option `$arg`")
        elseif bundle === nothing
            bundle = arg
        else
            error("unexpected extra argument `$arg`")
        end
        i += 1
    end
    bundle === nothing && error(
        "usage: scripts/canonical/run_exploration_contract.jl [--check] [--dry-run] [--max-iter N] [--output-root DIR] contract_dir")
    return (
        check = check,
        dry_run = dry_run,
        max_iter = max_iter,
        output_root = output_root,
        bundle = bundle,
    )
end

function run_exploration_contract_main(args=ARGS)
    parsed = _parse_exploration_contract_args(args)
    if parsed.check
        report = check_exploration_contract_bundle(parsed.bundle)
        println("# Exploration Contract Check")
        println()
        println("- Status: `PASS`")
        println("- Dimension: `", report.dimension, "`")
        println("- Initial cost: `", report.initial_cost, "`")
        println("- Initial gradient norm: `", report.initial_grad_norm, "`")
        println("- Source: `", report.source_path, "`")
        return report
    end

    result = run_exploration_contract_bundle(
        parsed.bundle;
        output_root = parsed.output_root,
        max_iter = parsed.max_iter,
        dry_run = parsed.dry_run,
    )
    if parsed.dry_run
        println("# Exploration Contract Dry Run")
        println()
        println("- Status: `PASS`")
        println("- Dimension: `", result.dimension, "`")
        println("- Initial cost: `", result.initial_cost, "`")
        return result
    end

    println("# Exploration Contract Run")
    println()
    println("- Output dir: `", result.output_dir, "`")
    println("- Artifact: `", result.artifact_path, "`")
    println("- Manifest: `", result.manifest_json, "`")
    println("- Trace CSV: `", result.trace_csv, "`")
    result.trace_png !== nothing && println("- Trace plot: `", result.trace_png, "`")
    result.gradient_trace_png !== nothing && println("- Gradient plot: `", result.gradient_trace_png, "`")
    result.parameter_before_after_png !== nothing && println("- Parameter plot: `", result.parameter_before_after_png, "`")
    result.parameter_delta_png !== nothing && println("- Parameter delta plot: `", result.parameter_delta_png, "`")
    result.diagnostics_final_png !== nothing && println("- Diagnostics plot: `", result.diagnostics_final_png, "`")
    result.diagnostics_trace_png !== nothing && println("- Diagnostics trace plot: `", result.diagnostics_trace_png, "`")
    result.diagnostics_delta_png !== nothing && println("- Diagnostics delta plot: `", result.diagnostics_delta_png, "`")
    println("- Run index: `", result.run_index, "`")
    if result.artifact_error !== nothing
        println("- Artifact warning: `", result.artifact_error, "`")
        println("- Artifact error file: `", result.artifact_error_path, "`")
    end
    return result
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_exploration_contract_main()
end
