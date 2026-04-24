"""
Small registry for front-layer objective/cost contracts.

This is intentionally not a plugin system. It is a code-defined allowlist that
lets configs name an objective while keeping the actual physics and adjoint
implementation explicit in Julia.
"""

if !(@isdefined _OBJECTIVE_REGISTRY_JL_LOADED)
const _OBJECTIVE_REGISTRY_JL_LOADED = true

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
    println(io, "Registered objective contracts:")
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
    return nothing
end

end # include guard
