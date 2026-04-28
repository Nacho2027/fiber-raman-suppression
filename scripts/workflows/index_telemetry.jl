"""
Build a lightweight index of compute telemetry captured by run wrappers.

Usage:
    julia -t auto --project=. scripts/canonical/index_telemetry.jl [options] [root ...]

Options:
    --csv                 Render CSV instead of Markdown.
    --contains TEXT       Keep only rows whose id/label/host/command/path contains TEXT.
    --label LABEL         Keep only rows with an exact telemetry label or directory id.
    --ok                  Keep only successful commands.
    --failed              Keep only failed commands.
    --sort KEY            Sort by started, elapsed, rss, cpu, or label.
    --desc                Reverse the sort order.
    --top N               Keep only the first N rows after filtering and sorting.
    --help                Show this message.
"""

include(joinpath(@__DIR__, "..", "lib", "telemetry_index.jl"))

function _index_telemetry_usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/index_telemetry.jl [options] [root ...]

Options:
    --csv                 Render CSV instead of Markdown.
    --contains TEXT       Keep only rows whose id/label/host/command/path contains TEXT.
    --label LABEL         Keep only rows with an exact telemetry label or directory id.
    --ok                  Keep only successful commands.
    --failed              Keep only failed commands.
    --sort KEY            Sort by started, elapsed, rss, cpu, or label.
    --desc                Reverse the sort order.
    --top N               Keep only the first N rows after filtering and sorting.
    --help                Show this message.
"""
end

function parse_index_telemetry_args(args)
    roots = String[]
    csv = false
    contains = nothing
    label = nothing
    ok = nothing
    failed = false
    sort_key = :started
    desc = false
    top = nothing

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            return (
                roots = String[],
                csv = false,
                contains = nothing,
                label = nothing,
                ok = nothing,
                failed = false,
                sort_key = :started,
                desc = false,
                top = nothing,
                help = true,
            )
        elseif arg == "--csv"
            csv = true
        elseif arg == "--ok"
            ok = true
        elseif arg == "--failed"
            failed = true
        elseif arg == "--desc"
            desc = true
        elseif arg == "--contains"
            i += 1
            i <= length(args) || error("--contains requires a value")
            contains = args[i]
        elseif arg == "--label"
            i += 1
            i <= length(args) || error("--label requires a value")
            label = args[i]
        elseif arg == "--sort"
            i += 1
            i <= length(args) || error("--sort requires started, elapsed, rss, cpu, or label")
            value = Symbol(lowercase(args[i]))
            value in (:started, :elapsed, :rss, :cpu, :label) ||
                error("--sort requires started, elapsed, rss, cpu, or label")
            sort_key = value
        elseif arg == "--top"
            i += 1
            i <= length(args) || error("--top requires a nonnegative integer")
            top = parse(Int, args[i])
            top >= 0 || error("--top requires a nonnegative integer")
        elseif startswith(arg, "--")
            error("Unknown index_telemetry option: $arg")
        else
            push!(roots, arg)
        end
        i += 1
    end

    ok === true && failed && error("Use only one of --ok or --failed")
    isempty(roots) && push!(roots, "results/telemetry")
    return (
        roots = roots,
        csv = csv,
        contains = contains,
        label = label,
        ok = ok,
        failed = failed,
        sort_key = sort_key,
        desc = desc,
        top = top,
        help = false,
    )
end

function index_telemetry_main(args=ARGS)
    parsed = parse_index_telemetry_args(String.(args))
    if parsed.help
        println(_index_telemetry_usage())
        return nothing
    end
    index = build_telemetry_index(parsed.roots)
    index = filter_telemetry_index(
        index;
        contains=parsed.contains,
        label=parsed.label,
        ok=parsed.ok,
        failed=parsed.failed,
    )
    index = sort_telemetry_index(index; by=parsed.sort_key, descending=parsed.desc)
    index = top_telemetry_index(index, parsed.top)
    rendered = parsed.csv ? render_telemetry_index_csv(index) : render_telemetry_index(index)
    println(rendered)
    return index
end

if abspath(PROGRAM_FILE) == @__FILE__
    index_telemetry_main(ARGS)
end
