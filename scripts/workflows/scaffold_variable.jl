"""
Create a planning-only optimization variable extension contract and Julia stub.

Usage:
    julia -t auto --project=. scripts/canonical/scaffold_variable.jl KIND [options]

Options:
    --regime NAME          Regime for the contract, default: single_mode.
    --dir PATH             Output directory, default: lab_extensions/variables.
    --description TEXT     Human-readable variable description.
    --units TEXT           Physical units or normalization.
    --bounds TEXT          Bounds/projection behavior.
    --parameterizations LIST
                           Comma-separated parameterizations, default: full_grid.
    --objectives LIST      Comma-separated compatible objectives, default: raman_band.
    --force                Overwrite an existing scaffold.
"""

include(joinpath(@__DIR__, "..", "lib", "variable_registry.jl"))

function _scaffold_variable_usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/scaffold_variable.jl KIND [options]

Options:
    --regime NAME          Regime for the contract, default: single_mode.
    --dir PATH             Output directory, default: lab_extensions/variables.
    --description TEXT     Human-readable variable description.
    --units TEXT           Physical units or normalization.
    --bounds TEXT          Bounds/projection behavior.
    --parameterizations LIST
                           Comma-separated parameterizations, default: full_grid.
    --objectives LIST      Comma-separated compatible objectives, default: raman_band.
    --force                Overwrite an existing scaffold.
    --help                 Show this message.
"""
end

function _split_scaffold_variable_list(value::AbstractString)
    items = [strip(item) for item in split(value, ",")]
    return Tuple(item for item in items if !isempty(item))
end

function parse_scaffold_variable_args(args)
    isempty(args) && error(_scaffold_variable_usage())
    if args[1] == "--help" || args[1] == "-h"
        return (help = true,)
    end

    kind = args[1]
    regime = :single_mode
    dir = VARIABLE_EXTENSION_DIR
    description = "Research variable contract. Replace with control semantics, units, and bounds."
    units = "document units"
    bounds = "document bounds/projection behavior"
    parameterizations = ("full_grid",)
    compatible_objectives = ("raman_band",)
    force = false

    i = 2
    while i <= length(args)
        arg = args[i]
        if arg == "--force"
            force = true
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
        elseif arg == "--units"
            i += 1
            i <= length(args) || error("--units requires a value")
            units = args[i]
        elseif arg == "--bounds"
            i += 1
            i <= length(args) || error("--bounds requires a value")
            bounds = args[i]
        elseif arg == "--parameterizations"
            i += 1
            i <= length(args) || error("--parameterizations requires a comma-separated value")
            parameterizations = _split_scaffold_variable_list(args[i])
        elseif arg == "--objectives"
            i += 1
            i <= length(args) || error("--objectives requires a comma-separated value")
            compatible_objectives = _split_scaffold_variable_list(args[i])
        elseif arg == "--help" || arg == "-h"
            return (help = true,)
        else
            error("Unknown scaffold_variable option: $arg")
        end
        i += 1
    end

    return (
        help = false,
        kind = kind,
        regime = regime,
        dir = dir,
        description = description,
        units = units,
        bounds = bounds,
        parameterizations = parameterizations,
        compatible_objectives = compatible_objectives,
        force = force,
    )
end

function scaffold_variable_main(args=ARGS)
    parsed = parse_scaffold_variable_args(String.(args))
    if parsed.help
        println(_scaffold_variable_usage())
        return nothing
    end

    scaffold = scaffold_variable_extension(
        parsed.kind;
        regime=parsed.regime,
        dir=parsed.dir,
        description=parsed.description,
        units=parsed.units,
        bounds=parsed.bounds,
        parameterizations=parsed.parameterizations,
        compatible_objectives=parsed.compatible_objectives,
        force=parsed.force,
    )

    println("Variable extension scaffold created:")
    println("  kind: ", scaffold.kind)
    println("  contract: ", scaffold.toml_path)
    println("  source: ", scaffold.source_path)
    println()
    println("Next checks:")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --variables")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-variables")
    return scaffold
end

if abspath(PROGRAM_FILE) == @__FILE__
    scaffold_variable_main(ARGS)
end
