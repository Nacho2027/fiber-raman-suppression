"""
Build a lightweight Markdown index of run artifacts and sweep summaries.

Usage:
    julia -t auto --project=. scripts/canonical/index_results.jl [options] [root ...]

Options:
    --csv                 Render CSV instead of Markdown.
    --kind run|sweep      Keep only run artifacts or sweep summaries.
    --fiber NAME          Keep only rows with an exact fiber-name match.
    --complete-images     Keep only runs with the standard image set complete.
    --contains TEXT       Keep only rows whose id/fiber/path contains TEXT.
"""

include(joinpath(@__DIR__, "..", "lib", "results_index.jl"))

function _index_results_usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/index_results.jl [options] [root ...]

Options:
    --csv                 Render CSV instead of Markdown.
    --kind run|sweep      Keep only run artifacts or sweep summaries.
    --fiber NAME          Keep only rows with an exact fiber-name match.
    --complete-images     Keep only runs with the standard image set complete.
    --contains TEXT       Keep only rows whose id/fiber/path contains TEXT.
    --help                Show this message.
"""
end

function parse_index_results_args(args)
    roots = String[]
    csv = false
    kind = nothing
    fiber = nothing
    complete_images = false
    contains = nothing

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            return (
                roots = String[],
                csv = false,
                kind = nothing,
                fiber = nothing,
                complete_images = false,
                contains = nothing,
                help = true,
            )
        elseif arg == "--csv"
            csv = true
        elseif arg == "--complete-images"
            complete_images = true
        elseif arg == "--kind"
            i += 1
            i <= length(args) || error("--kind requires run or sweep")
            value = lowercase(args[i])
            value in ("run", "sweep") || error("--kind must be run or sweep")
            kind = Symbol(value)
        elseif arg == "--fiber"
            i += 1
            i <= length(args) || error("--fiber requires a value")
            fiber = args[i]
        elseif arg == "--contains"
            i += 1
            i <= length(args) || error("--contains requires a value")
            contains = args[i]
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
        csv = csv,
        kind = kind,
        fiber = fiber,
        complete_images = complete_images,
        contains = contains,
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
        fiber=parsed.fiber,
        complete_images=parsed.complete_images,
        contains=parsed.contains,
    )
    rendered = parsed.csv ? render_results_index_csv(index) : render_results_index(index)
    println(rendered)
    return index
end

if abspath(PROGRAM_FILE) == @__FILE__
    index_results_main(ARGS)
end
