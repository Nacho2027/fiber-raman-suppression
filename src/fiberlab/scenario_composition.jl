"""One source-validated model/objective pair in a shared-control optimization."""
struct ScenarioTerm{O<:AbstractFiberObjective}
    name::Symbol
    model::AdjointModel
    objective::O

    function ScenarioTerm(name::Symbol, model::AdjointModel,
                          objective::O) where {O<:AbstractFiberObjective}
        _nonempty_name(name, "scenario")
        has_terminal_adjoint(objective) || throw(ArgumentError(
            "scenario `$name` objective has no terminal adjoint"))
        _validate_scenario_source(name, model, objective)
        return new{O}(name, model, objective)
    end
end

"""Composed adjoint pair, explicit terms, aggregate, and source provenance."""
struct ScenarioComposition{T,A,P}
    model::AdjointModel
    objective::ObjectiveMap
    terms::T
    aggregate::A
    provenance::P
end

abstract type AbstractScenarioAggregate end

struct WeightedScenarioAggregate{W} <: AbstractScenarioAggregate
    weights::W
end

struct SquaredDifferenceScenarioAggregate <: AbstractScenarioAggregate
    minuend::Symbol
    subtrahend::Symbol
end

_scenario_names(terms) = Tuple(term.name for term in terms)
_named(names::Tuple, f) = NamedTuple{names}(map(f, names))
_named_terms(terms, f) = NamedTuple{_scenario_names(terms)}(map(f, terms))

function _ordered_scenarios(values, names::Tuple, label::AbstractString)
    values isa NamedTuple || throw(ArgumentError("$label must be a NamedTuple"))
    supplied = propertynames(values)
    Set(supplied) == Set(names) && length(supplied) == length(names) || throw(ArgumentError(
        "$label fields $(supplied) do not match scenarios $(names)"))
    return _named(names, name -> getproperty(values, name))
end

function _real_scenarios(values, names::Tuple, label::AbstractString)
    ordered = _ordered_scenarios(values, names, label)
    return _named(names, name -> begin
        value = getproperty(ordered, name)
        value isa Real || throw(ArgumentError("$label `$name` must be a real scalar"))
        number = Float64(value)
        isfinite(number) || throw(ArgumentError("$label `$name` must be finite"))
        number
    end)
end

"""
    weighted_scenario_aggregate([weights])

Return a linear aggregate callable. Omitted weights are all one; explicit
weights are a named tuple with one finite real value per scenario.
"""
function weighted_scenario_aggregate(weights=nothing)
    weights === nothing || weights isa NamedTuple || throw(ArgumentError(
        "scenario weights must be a NamedTuple"))
    return WeightedScenarioAggregate(weights)
end

function (aggregate::WeightedScenarioAggregate)(costs)
    names = propertynames(costs)
    partials = aggregate.weights === nothing ? _named(names, _ -> 1.0) :
        _real_scenarios(aggregate.weights, names, "scenario weights")
    return (
        cost = sum(getproperty(partials, name) * getproperty(costs, name) for name in names),
        partials = partials,
    )
end

"""
    squared_difference_aggregate(minuend, subtrahend)

Return the squared difference between two named component costs and its named
partial derivatives.
"""
function squared_difference_aggregate(minuend::Symbol, subtrahend::Symbol)
    _nonempty_name(minuend, "squared-difference minuend")
    _nonempty_name(subtrahend, "squared-difference subtrahend")
    minuend != subtrahend || throw(ArgumentError(
        "squared-difference scenarios must be different"))
    return SquaredDifferenceScenarioAggregate(minuend, subtrahend)
end

function (aggregate::SquaredDifferenceScenarioAggregate)(costs)
    names = propertynames(costs)
    aggregate.minuend in names && aggregate.subtrahend in names || throw(ArgumentError(
        "squared-difference scenarios must name component costs"))
    difference = getproperty(costs, aggregate.minuend) -
        getproperty(costs, aggregate.subtrahend)
    return (
        cost = difference^2,
        partials = _named(names, name ->
            name == aggregate.minuend ? 2difference :
            name == aggregate.subtrahend ? -2difference : 0.0),
    )
end

function _validate_scenario_source(name, model, objective)
    try
        _validate_adjoint_sources(model, objective)
    catch err
        err isa InterruptException && rethrow()
        throw(ArgumentError("scenario `$name`: $(sprint(showerror, err))"))
    end
    return nothing
end

function _validate_scenario_sources(terms)
    foreach(term -> _validate_scenario_source(term.name, term.model, term.objective), terms)
    return nothing
end

_scenario_grid(problem::FiberFieldProblem) = (
    nt = sample_count(problem),
    modes = mode_count(problem),
    delta_t = Float64(problem.sim["Δt"]),
    frequencies = problem.frequency_offset_thz,
)

function _validate_scenario_grids(terms)
    sources = map(term -> term.model.problem_source, terms)
    all(source -> source !== nothing && source.problem isa FiberFieldProblem, sources) ||
        return nothing
    grids = map(source -> _scenario_grid(source.problem), sources)
    all(==(first(grids)), grids) || throw(ArgumentError(
        "source-bound scenarios must share Nt, modes, Δt, and frequency grid"))
    return nothing
end

function _scenario_call(operation, term, action::AbstractString)
    try
        return operation()
    catch err
        err isa InterruptException && rethrow()
        throw(ArgumentError(
            "scenario `$(term.name)` cannot $action the shared decoded control: $(sprint(showerror, err))"))
    end
end

function _scenario_forward(terms, decoded, context)
    _validate_scenario_sources(terms)
    return _named_terms(terms, term -> _scenario_call(term, "evaluate") do
        _run_model_forward(term.model, decoded, context)
    end)
end

function _scenario_costs(terms, states)
    _validate_scenario_sources(terms)
    ordered = _ordered_scenarios(states, _scenario_names(terms), "scenario state")
    return _named_terms(terms, term ->
        objective_value(term.objective, getproperty(ordered, term.name)))
end

function _aggregate_result(aggregate, costs)
    result = try
        aggregate(costs)
    catch err
        err isa InterruptException && rethrow()
        throw(ArgumentError("scenario aggregate failed: $(sprint(showerror, err))"))
    end
    result isa NamedTuple && hasproperty(result, :cost) && hasproperty(result, :partials) ||
        throw(ArgumentError("scenario aggregate must return `(cost=..., partials=...)`"))
    cost = result.cost
    cost isa Real && isfinite(Float64(cost)) || throw(ArgumentError(
        "scenario aggregate cost must be a finite real scalar"))
    return (
        cost = Float64(cost),
        partials = _real_scenarios(
            result.partials, propertynames(costs), "scenario aggregate partials"),
    )
end

_scale_scenario(scale, value::Number) = scale * value
_scale_scenario(scale, value::AbstractArray) = scale .* value
_scale_scenario(scale, value::NamedTuple) =
    _named(propertynames(value), name -> _scale_scenario(scale, getproperty(value, name)))
_scale_scenario(scale, value::Tuple) = map(item -> _scale_scenario(scale, item), value)

_gradient_structure(value::Number) = :scalar
_gradient_structure(value::AbstractArray) = (:array, size(value))
_gradient_structure(value::NamedTuple) = (
    :named,
    propertynames(value),
    map(name -> _gradient_structure(getproperty(value, name)), propertynames(value)),
)
_gradient_structure(value::Tuple) = (:tuple, map(_gradient_structure, value))
function _gradient_structure(value::AbstractDict)
    names = Tuple(sort!(Symbol.(collect(keys(value))); by=string))
    return (:dict, names, map(name -> _gradient_structure(
        haskey(value, name) ? value[name] : value[String(name)]), names))
end
_gradient_structure(value) = typeof(value)

function _scenario_gradient(terms, decoded, seeds, context)
    _validate_scenario_sources(terms)
    ordered = _ordered_scenarios(seeds, _scenario_names(terms), "scenario terminal adjoint")
    gradients = map(terms) do term
        _scenario_call(term, "differentiate") do
            _run_model_physical_gradient(
                term.model, decoded, getproperty(ordered, term.name), context)
        end
    end
    structure = _gradient_structure(first(gradients))
    all(gradient -> _gradient_structure(gradient) == structure, gradients) ||
        throw(ArgumentError("scenario physical-gradient structures do not match"))
    return try
        foldl(_add_physical_gradients, gradients)
    catch err
        err isa InterruptException && rethrow()
        throw(ArgumentError("scenario physical gradients cannot be summed: $(sprint(showerror, err))"))
    end
end

function _scenario_term_provenance(terms)
    return _named_terms(terms, term -> begin
        source = term.model.problem_source
        problem_sha256 = source === nothing ? nothing : source.snapshot_sha256
        objective_sha256 = _objective_problem_sha256(term.objective)
        (
            model = term.model.name,
            objective = term.objective.name,
            objective_contract = _objective_contract_kind(term.objective),
            objective_cost_scale = _objective_cost_scale(term.objective),
            problem_sha256 = problem_sha256,
            objective_problem_sha256 = objective_sha256,
            source_authority = problem_sha256 === nothing ? :declared_names_only :
                objective_sha256 == problem_sha256 ? :sealed_problem : :problem_only,
        )
    end)
end

function _scenario_aggregate_provenance(aggregate::WeightedScenarioAggregate,
                                        names::Tuple)
    weights = aggregate.weights === nothing ? _named(names, _ -> 1.0) :
        _real_scenarios(aggregate.weights, names, "scenario weights")
    return (kind = :weighted_sum, weights = weights)
end

function _scenario_aggregate_provenance(aggregate::SquaredDifferenceScenarioAggregate,
                                        names::Tuple)
    aggregate.minuend in names && aggregate.subtrahend in names || throw(ArgumentError(
        "squared-difference scenarios must name component costs"))
    return (
        kind = :squared_difference,
        minuend = aggregate.minuend,
        subtrahend = aggregate.subtrahend,
    )
end

function _scenario_aggregate_provenance(aggregate, names::Tuple)
    throw(ArgumentError(
        "scenario aggregate `$(typeof(aggregate))` has no serializable identity; " *
        "use a package-defined scenario aggregate"))
end

function _scenario_provenance(name::Symbol, terms, aggregate)
    names = _scenario_names(terms)
    term_provenance = _scenario_term_provenance(terms)
    return (
        schema = :scenario_composition_v1,
        name = name,
        objective = Symbol(name, :_objective),
        aggregate = _scenario_aggregate_provenance(aggregate, names),
        all_terms_sealed = all(
            term.source_authority == :sealed_problem for term in values(term_provenance)),
        terms = term_provenance,
    )
end

"""
    compose_scenarios(terms...; aggregate=weighted_scenario_aggregate())

Compose named scenarios around one decoded control. Aggregate partials scale
the per-scenario terminal seeds; physical gradients are validated, summed, and
then handled by the ordinary control pullback. Aggregates are package-defined
callable structs so their exact parameters can be written to result provenance.
"""
function compose_scenarios(terms::ScenarioTerm...;
                           aggregate=weighted_scenario_aggregate(),
                           name::Symbol=:scenario_composition)
    isempty(terms) && throw(ArgumentError("compose_scenarios requires a term"))
    _nonempty_name(name, "scenario composition")
    names = _scenario_names(terms)
    length(unique(names)) == length(names) || throw(ArgumentError(
        "scenario names must be unique, got $(names)"))
    _validate_scenario_sources(terms)
    _validate_scenario_grids(terms)
    provenance = _scenario_provenance(name, terms, aggregate)

    model = AdjointModel(
        name;
        forward = (decoded, context) -> _scenario_forward(terms, decoded, context),
        physical_gradient = (decoded, seeds, context) ->
            _scenario_gradient(terms, decoded, seeds, context),
        description = "Shared-control adjoint over $(length(terms)) scenarios.",
        provenance = provenance,
    )
    objective = ObjectiveMap(
        Symbol(name, :_objective);
        cost = states -> _aggregate_result(aggregate, _scenario_costs(terms, states)).cost,
        terminal_adjoint = (states, context) -> begin
            ordered = _ordered_scenarios(states, names, "scenario state")
            result = _aggregate_result(aggregate, _scenario_costs(terms, ordered))
            _named_terms(terms, term -> _scale_scenario(
                getproperty(result.partials, term.name),
                terminal_adjoint(term.objective, getproperty(ordered, term.name), context),
            ))
        end,
        description = "Validated aggregate of named scenario objectives.",
    )
    return ScenarioComposition(
        model, objective, terms, aggregate, provenance)
end

"""
    component_costs(bundle, states)
    component_costs(bundle, coordinates; control, context=nothing)

Return every named component cost without applying the aggregate.
"""
component_costs(bundle::ScenarioComposition, states::NamedTuple) =
    _scenario_costs(bundle.terms, states)

function component_costs(bundle::ScenarioComposition, coordinates;
                         control::AbstractControlMap, context=nothing)
    evaluation = evaluate_control(control, coordinates; context=context)
    states = _run_model_forward(bundle.model, _decoded_value(evaluation), context)
    return _scenario_costs(bundle.terms, states)
end
