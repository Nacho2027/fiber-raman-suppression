"""
Create a planning-only objective extension contract and Julia stub.

Usage:
    julia -t auto --project=. scripts/canonical/scaffold_objective.jl KIND [options]

Options:
    --regime NAME          Regime for the contract, default: single_mode.
    --dir PATH             Output directory, default: lab_extensions/objectives.
    --description TEXT     Human-readable objective description.
    --variables LIST       Comma-separated variables, default: phase.
    --regularizers LIST    Comma-separated regularizers, default: gdd,boundary.
    --executable-scalar    Create an executable scalar-extension objective template.
    --force                Overwrite an existing scaffold.
"""

include(joinpath(@__DIR__, "..", "lib", "objective_registry.jl"))

function _scaffold_usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/scaffold_objective.jl KIND [options]

Options:
    --regime NAME          Regime for the contract, default: single_mode.
    --dir PATH             Output directory, default: lab_extensions/objectives.
    --description TEXT     Human-readable objective description.
    --variables LIST       Comma-separated variables, default: phase.
    --regularizers LIST    Comma-separated regularizers, default: gdd,boundary.
    --executable-scalar    Create an executable scalar-extension objective template.
    --force                Overwrite an existing scaffold.
    --help                 Show this message.
"""
end

function _split_scaffold_list(value::AbstractString)
    items = [strip(item) for item in split(value, ",")]
    return Tuple(item for item in items if !isempty(item))
end

function parse_scaffold_objective_args(args)
    isempty(args) && error(_scaffold_usage())
    if args[1] == "--help" || args[1] == "-h"
        return (help = true,)
    end

    kind = args[1]
    regime = :single_mode
    dir = OBJECTIVE_EXTENSION_DIR
    description = "Research objective contract. Replace with physical quantity, units, and normalization."
    variables = ("phase",)
    regularizers = ("gdd", "boundary")
    force = false
    executable_scalar = false

    i = 2
    while i <= length(args)
        arg = args[i]
        if arg == "--force"
            force = true
        elseif arg == "--executable-scalar"
            executable_scalar = true
        elseif arg == "--regime"
            i += 1
            i <= length(args) || error("--regime requires a value")
            regime = Symbol(args[i])
        elseif arg == "--dir"
            i += 1
            i <= length(args) || error("--dir requires a value")
            dir = args[i]
        elseif arg == "--description"
            i += 1
            i <= length(args) || error("--description requires a value")
            description = args[i]
        elseif arg == "--variables"
            i += 1
            i <= length(args) || error("--variables requires a comma-separated value")
            variables = _split_scaffold_list(args[i])
        elseif arg == "--regularizers"
            i += 1
            i <= length(args) || error("--regularizers requires a comma-separated value")
            regularizers = _split_scaffold_list(args[i])
        elseif arg == "--help" || arg == "-h"
            return (help = true,)
        else
            error("Unknown scaffold_objective option: $arg")
        end
        i += 1
    end

    return (
        help = false,
        kind = kind,
        regime = regime,
        dir = dir,
        description = description,
        variables = (Tuple(variables),),
        regularizers = regularizers,
        executable_scalar = executable_scalar,
        force = force,
    )
end

function scaffold_objective_main(args=ARGS)
    parsed = parse_scaffold_objective_args(String.(args))
    if parsed.help
        println(_scaffold_usage())
        return nothing
    end

    scaffold = scaffold_objective_extension(
        parsed.kind;
        regime=parsed.regime,
        dir=parsed.dir,
        description=parsed.description,
        variables=parsed.variables,
        regularizers=parsed.regularizers,
        backend=parsed.executable_scalar ? :scalar_extension : :lab_extension,
        maturity=parsed.executable_scalar ? "experimental" : "research",
        execution=parsed.executable_scalar ? :executable : :planning_only,
        validation=parsed.executable_scalar ?
            "Runtime-checked by exploration doctor; replace template physics and add science validation before promotion." :
            "Requires units, gradient check, artifact metrics, and a promoted backend before execution.",
        force=parsed.force,
    )

    println("Objective extension scaffold created:")
    println("  kind: ", scaffold.kind)
    println("  contract: ", scaffold.toml_path)
    println("  source: ", scaffold.source_path)
    println()
    println("Next checks:")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --objectives")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-objectives")
    return scaffold
end

if abspath(PROGRAM_FILE) == @__FILE__
    scaffold_objective_main(ARGS)
end
