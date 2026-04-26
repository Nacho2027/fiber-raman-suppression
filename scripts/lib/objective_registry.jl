"""
Small registry for front-layer objective/cost contracts.

This is intentionally not a plugin system. It is a code-defined allowlist that
lets configs name an objective while keeping the actual physics and adjoint
implementation explicit in Julia.
"""

if !(@isdefined _OBJECTIVE_REGISTRY_JL_LOADED)
const _OBJECTIVE_REGISTRY_JL_LOADED = true

using TOML

const OBJECTIVE_EXTENSION_DIR = normpath(joinpath(@__DIR__, "..", "..", "lab_extensions", "objectives"))

_objective_normalize_symbol(x) = Symbol(replace(lowercase(String(x)), "-" => "_"))

const OBJECTIVE_CONTRACTS = (
    (
        kind = :raman_band,
        regime = :single_mode,
        backend = :raman_optimization,
        description = "Integrated Raman-band spectral power with optional regularization.",
        maturity = "supported",
        supported_variables = (
            (:phase,),
            (:phase, :amplitude),
            (:phase, :energy),
            (:phase, :amplitude, :energy),
        ),
        allowed_regularizers = (
            :gdd,
            :boundary,
            :energy,
            :tikhonov,
            :tv,
            :flat,
        ),
    ),
    (
        kind = :raman_peak,
        regime = :single_mode,
        backend = :raman_optimization,
        description = "Maximum single-bin Raman-band fractional leakage with optional phase regularization.",
        maturity = "experimental",
        supported_variables = ((:phase,),),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
    (
        kind = :raman_band,
        regime = :long_fiber,
        backend = :raman_optimization,
        description = "Integrated Raman-band spectral power for long-fiber single-mode planning.",
        maturity = "experimental",
        supported_variables = ((:phase,),),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
    (
        kind = :mmf_sum,
        regime = :multimode,
        backend = :mmf_raman_optimization,
        description = "Mode-summed multimode Raman leakage for shared spectral-phase planning.",
        maturity = "experimental",
        supported_variables = ((:phase,),),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
    (
        kind = :mmf_fundamental,
        regime = :multimode,
        backend = :mmf_raman_optimization,
        description = "Fundamental-mode multimode Raman leakage diagnostic objective.",
        maturity = "experimental",
        supported_variables = ((:phase,),),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
    (
        kind = :mmf_worst_mode,
        regime = :multimode,
        backend = :mmf_raman_optimization,
        description = "Worst-mode multimode Raman leakage diagnostic objective.",
        maturity = "experimental",
        supported_variables = ((:phase,),),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
)

function registered_objective_contracts(regime::Symbol)
    return Tuple(contract for contract in OBJECTIVE_CONTRACTS if contract.regime == regime)
end

function registered_objective_kinds(regime::Symbol)
    return Tuple(contract.kind for contract in registered_objective_contracts(regime))
end

function objective_contract(kind::Symbol, regime::Symbol)
    matches = Tuple(
        contract for contract in OBJECTIVE_CONTRACTS
        if contract.kind == kind && contract.regime == regime
    )
    isempty(matches) && throw(ArgumentError(
        "objective `$(kind)` is not registered for regime `$(regime)`; registered objectives: $(collect(registered_objective_kinds(regime)))"))
    return only(matches)
end

function _parse_variable_tuple(raw)
    return Tuple(Symbol(String(item)) for item in raw)
end

function _parse_extension_contract(path::AbstractString)
    parsed = TOML.parsefile(path)
    variables = haskey(parsed, "supported_variables") ?
        Tuple(_parse_variable_tuple(item) for item in parsed["supported_variables"]) :
        ((:phase,),)
    regularizers = haskey(parsed, "allowed_regularizers") ?
        Tuple(Symbol(String(item)) for item in parsed["allowed_regularizers"]) :
        Symbol[]

    return (
        kind = _objective_normalize_symbol(parsed["kind"]),
        regime = _objective_normalize_symbol(parsed["regime"]),
        backend = _objective_normalize_symbol(get(parsed, "backend", "lab_extension")),
        description = String(get(parsed, "description", parsed["kind"])),
        maturity = lowercase(String(get(parsed, "maturity", "research"))),
        execution = _objective_normalize_symbol(get(parsed, "execution", "planning_only")),
        source = String(get(parsed, "source", "")),
        function_name = String(get(parsed, "function", "")),
        gradient_name = String(get(parsed, "gradient", "")),
        validation = String(get(parsed, "validation", "")),
        supported_variables = variables,
        allowed_regularizers = Tuple(regularizers),
        config_path = abspath(path),
    )
end

function registered_objective_extension_contracts(regime::Union{Nothing,Symbol}=nothing)
    isdir(OBJECTIVE_EXTENSION_DIR) || return ()
    contracts = []
    for entry in readdir(OBJECTIVE_EXTENSION_DIR; join=true)
        isfile(entry) || continue
        endswith(entry, ".toml") || continue
        contract = _parse_extension_contract(entry)
        if isnothing(regime) || contract.regime == regime
            push!(contracts, contract)
        end
    end
    sort!(contracts; by = contract -> string(contract.kind))
    return Tuple(contracts)
end

function registered_objective_extension_kinds(regime::Symbol)
    return Tuple(contract.kind for contract in registered_objective_extension_contracts(regime))
end

function objective_extension_contract(kind::Symbol, regime::Symbol)
    matches = Tuple(
        contract for contract in registered_objective_extension_contracts(regime)
        if contract.kind == kind
    )
    isempty(matches) && throw(ArgumentError(
        "objective extension `$(kind)` is not registered for regime `$(regime)`; registered extensions: $(collect(registered_objective_extension_kinds(regime)))"))
    return only(matches)
end

function experiment_objective_contract(spec)
    contract = objective_contract(spec.objective.kind, spec.problem.regime)

    spec.controls.variables in contract.supported_variables || throw(ArgumentError(
        "objective `$(spec.objective.kind)` does not support variables $(spec.controls.variables); supported tuples: $(collect(contract.supported_variables))"))

    for name in keys(spec.objective.regularizers)
        name in contract.allowed_regularizers || throw(ArgumentError(
            "regularizer `$(name)` is not registered for objective `$(spec.objective.kind)`; allowed regularizers: $(collect(contract.allowed_regularizers))"))
    end

    return contract
end

function _objective_tuple_summary(tuples)
    return join((join(string.(vars), "+") for vars in tuples), "; ")
end

function render_objective_registry(; io::IO=stdout, regime::Union{Nothing,Symbol}=nothing)
    contracts = isnothing(regime) ? OBJECTIVE_CONTRACTS : registered_objective_contracts(regime)
    println(io, "Built-in objective contracts:")
    for contract in contracts
        println(io,
            "  ", contract.kind,
            "  regime=", contract.regime,
            "  backend=", contract.backend,
            "  maturity=", contract.maturity)
        println(io, "    variables=", _objective_tuple_summary(contract.supported_variables))
        println(io, "    regularizers=", join(string.(contract.allowed_regularizers), ", "))
        println(io, "    ", contract.description)
    end
    extension_contracts = registered_objective_extension_contracts(regime)
    println(io)
    println(io, "Research extension objective contracts:")
    if isempty(extension_contracts)
        println(io, "  none")
    else
        for contract in extension_contracts
            println(io,
                "  ", contract.kind,
                "  regime=", contract.regime,
                "  backend=", contract.backend,
                "  maturity=", contract.maturity,
                "  execution=", contract.execution)
            println(io, "    variables=", _objective_tuple_summary(contract.supported_variables))
            println(io, "    regularizers=", join(string.(contract.allowed_regularizers), ", "))
            if !isempty(contract.source)
                println(io, "    source=", contract.source)
            end
            println(io, "    ", contract.description)
        end
    end
    return nothing
end

end # include guard
