"""
Build a lightweight Markdown index of run artifacts and sweep summaries.

Usage:
    julia -t auto --project=. scripts/canonical/index_results.jl [options] [root ...]

Options:
    --compare             Rank run artifacts by lab readiness, then suppression.
    --compare-sweeps      Rank sweep summaries by best completed case.
    --csv                 Render CSV instead of Markdown.
    --kind run|sweep      Keep only run artifacts or sweep summaries.
    --config-id ID        Keep only rows from a front-layer config id.
    --regime NAME         Keep only rows from a regime such as single_mode.
    --objective NAME      Keep only rows from an objective such as raman_band.
    --solver NAME         Keep only rows from a solver such as lbfgs.
    --fiber NAME          Keep only rows with an exact fiber-name match.
    --complete-images     Keep only runs with the standard image set complete.
    --lab-ready           Keep only mechanically lab-ready runs.
    --export-ready        Keep only runs with a complete neutral export handoff.
    --contains TEXT       Keep only rows whose id/fiber/path contains TEXT.
    --top N               Keep only the first N ranked rows with --compare/--compare-sweeps.
"""

include(joinpath(@__DIR__, "..", "lib", "results_index.jl"))

function _index_results_usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/index_results.jl [options] [root ...]

Options:
    --compare             Rank run artifacts by lab readiness, then suppression.
    --compare-sweeps      Rank sweep summaries by best completed case.
    --csv                 Render CSV instead of Markdown.
    --kind run|sweep      Keep only run artifacts or sweep summaries.
    --config-id ID        Keep only rows from a front-layer config id.
    --regime NAME         Keep only rows from a regime such as single_mode.
    --objective NAME      Keep only rows from an objective such as raman_band.
    --solver NAME         Keep only rows from a solver such as lbfgs.
    --fiber NAME          Keep only rows with an exact fiber-name match.
    --complete-images     Keep only runs with the standard image set complete.
    --lab-ready           Keep only mechanically lab-ready runs.
    --export-ready        Keep only runs with a complete neutral export handoff.
    --contains TEXT       Keep only rows whose id/fiber/path contains TEXT.
    --top N               Keep only the first N ranked rows with --compare/--compare-sweeps.
    --help                Show this message.
"""
end

function parse_index_results_args(args)
    roots = String[]
    compare = false
    compare_sweeps = false
    csv = false
    kind = nothing
    config_id = nothing
    regime = nothing
    objective = nothing
    solver = nothing
    fiber = nothing
    complete_images = false
    lab_ready = false
    export_ready = false
    contains = nothing
    top = nothing

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            return (
                roots = String[],
                compare = false,
                compare_sweeps = false,
                csv = false,
                kind = nothing,
                config_id = nothing,
                regime = nothing,
                objective = nothing,
                solver = nothing,
                fiber = nothing,
                complete_images = false,
                lab_ready = false,
                export_ready = false,
                contains = nothing,
                top = nothing,
                help = true,
            )
        elseif arg == "--compare"
            compare = true
        elseif arg == "--compare-sweeps"
            compare_sweeps = true
        elseif arg == "--csv"
            csv = true
        elseif arg == "--complete-images"
            complete_images = true
        elseif arg == "--lab-ready"
            lab_ready = true
        elseif arg == "--export-ready"
            export_ready = true
        elseif arg == "--kind"
            i += 1
            i <= length(args) || error("--kind requires run or sweep")
            value = lowercase(args[i])
            value in ("run", "sweep") || error("--kind must be run or sweep")
            kind = Symbol(value)
        elseif arg == "--config-id"
            i += 1
            i <= length(args) || error("--config-id requires a value")
            config_id = args[i]
        elseif arg == "--regime"
            i += 1
            i <= length(args) || error("--regime requires a value")
            regime = args[i]
        elseif arg == "--objective"
            i += 1
            i <= length(args) || error("--objective requires a value")
            objective = args[i]
        elseif arg == "--solver"
            i += 1
            i <= length(args) || error("--solver requires a value")
            solver = args[i]
        elseif arg == "--fiber"
            i += 1
            i <= length(args) || error("--fiber requires a value")
            fiber = args[i]
        elseif arg == "--contains"
            i += 1
            i <= length(args) || error("--contains requires a value")
            contains = args[i]
        elseif arg == "--top"
            i += 1
            i <= length(args) || error("--top requires a nonnegative integer")
            top = parse(Int, args[i])
            top >= 0 || error("--top requires a nonnegative integer")
        elseif startswith(arg, "--")
            error("Unknown index_results option: $arg")
        else
            push!(roots, arg)
        end
        i += 1
    end

    isempty(roots) && push!(roots, "results/raman")
    return (
        roots = roots,
        compare = compare,
        compare_sweeps = compare_sweeps,
        csv = csv,
        kind = kind,
        config_id = config_id,
        regime = regime,
        objective = objective,
        solver = solver,
        fiber = fiber,
        complete_images = complete_images,
        lab_ready = lab_ready,
        export_ready = export_ready,
        contains = contains,
        top = top,
        help = false,
    )
end

function index_results_main(args=ARGS)
    parsed = parse_index_results_args(String.(args))
    if parsed.help
        println(_index_results_usage())
        return nothing
    end
    index = build_results_index(parsed.roots)
    index = filter_results_index(
        index;
        kind=parsed.kind,
        config_id=parsed.config_id,
        regime=parsed.regime,
        objective=parsed.objective,
        solver=parsed.solver,
        fiber=parsed.fiber,
        complete_images=parsed.complete_images,
        lab_ready=parsed.lab_ready,
        export_ready=parsed.export_ready,
        contains=parsed.contains,
    )
    if parsed.compare && parsed.compare_sweeps
        error("Use only one of --compare or --compare-sweeps")
    elseif parsed.compare
        comparison = compare_results_index(
            index;
            lab_ready_only=parsed.lab_ready,
            export_ready_only=parsed.export_ready,
            top=parsed.top,
        )
        rendered = parsed.csv ? render_results_comparison_csv(comparison) : render_results_comparison(comparison)
        println(rendered)
        return comparison
    elseif parsed.compare_sweeps
        comparison = compare_sweep_summaries(index; top=parsed.top)
        rendered = parsed.csv ? render_sweep_comparison_csv(comparison) : render_sweep_comparison(comparison)
        println(rendered)
        return comparison
    end
    rendered = parsed.csv ? render_results_index_csv(index) : render_results_index(index)
    println(rendered)
    return index
end

if abspath(PROGRAM_FILE) == @__FILE__
    index_results_main(ARGS)
end
