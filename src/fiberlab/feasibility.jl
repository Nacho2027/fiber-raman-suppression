"""
Generic feasibility contracts for FiberLab optimization.

Feasibility is intentionally behavior-based. FiberLab does not need to know
whether a researcher is enforcing amplitude transmission, modal normalization,
hardware calibration, smoothness, manufacturability, or a lab-specific rule.
The solver only consumes optional callbacks for penalties, physical gradients,
projection, and diagnostics.
"""

abstract type AbstractFeasibilityMap end

struct FeasibilityMap <: AbstractFeasibilityMap
    name::Symbol
    penalty_function::Union{Nothing,Function}
    physical_gradient_function::Union{Nothing,Function}
    project_function::Union{Nothing,Function}
    check_function::Union{Nothing,Function}
    description::String

    function FeasibilityMap(name::Symbol;
                            penalty::Union{Nothing,Function}=nothing,
                            physical_gradient::Union{Nothing,Function}=nothing,
                            project::Union{Nothing,Function}=nothing,
                            check::Union{Nothing,Function}=nothing,
                            description::AbstractString="")
        _nonempty_name(name, "feasibility")
        return new(name, penalty, physical_gradient, project, check, String(description))
    end
end

struct FeasibilityEvaluation{F<:AbstractFeasibilityMap,D,S,U}
    feasibility::F
    decoded::D
    forward_state::S
    user_context::U
    penalty::Float64
    diagnostics
end

function feasibility_context(decoded, forward_state, user_context)
    return (
        decoded = decoded,
        forward_state = forward_state,
        user = user_context,
    )
end
has_penalty(feasibility::FeasibilityMap) = feasibility.penalty_function !== nothing
has_physical_gradient(feasibility::FeasibilityMap) =
    feasibility.physical_gradient_function !== nothing
has_projection(feasibility::FeasibilityMap) = feasibility.project_function !== nothing
has_feasibility_check(feasibility::FeasibilityMap) =
    feasibility.check_function !== nothing

function feasibility_penalty(feasibility::FeasibilityMap,
                             decoded,
                             forward_state=nothing;
                             context=nothing)
    feasibility.penalty_function === nothing && return 0.0
    value = feasibility.penalty_function(
        decoded,
        feasibility_context(decoded, forward_state, context),
    )
    value isa Real || throw(ArgumentError(
        "feasibility `$(feasibility.name)` penalty must return a real scalar"))
    isfinite(Float64(value)) || throw(ArgumentError(
        "feasibility `$(feasibility.name)` penalty returned a non-finite value"))
    return Float64(value)
end

function feasibility_physical_gradient(feasibility::FeasibilityMap,
                                       decoded,
                                       forward_state=nothing;
                                       context=nothing)
    feasibility.physical_gradient_function === nothing && throw(ArgumentError(
        "feasibility `$(feasibility.name)` declares no physical_gradient callback"))
    gradient = feasibility.physical_gradient_function(
        decoded,
        feasibility_context(decoded, forward_state, context),
    )
    gradient === nothing && throw(ArgumentError(
        "feasibility `$(feasibility.name)` physical_gradient returned nothing"))
    return gradient
end

function project(feasibility::FeasibilityMap, decoded; context=nothing)
    feasibility.project_function === nothing && return decoded
    projected = feasibility.project_function(
        decoded,
        feasibility_context(decoded, nothing, context),
    )
    projected === nothing && throw(ArgumentError(
        "feasibility `$(feasibility.name)` project returned nothing"))
    return projected
end

function feasibility_check(feasibility::FeasibilityMap,
                           decoded,
                           forward_state=nothing;
                           context=nothing)
    feasibility.check_function === nothing && return missing
    return feasibility.check_function(
        decoded,
        feasibility_context(decoded, forward_state, context),
    )
end

function evaluate_feasibility(feasibility::FeasibilityMap,
                              decoded,
                              forward_state=nothing;
                              context=nothing)
    penalty = feasibility_penalty(feasibility, decoded, forward_state; context=context)
    diagnostics = feasibility_check(feasibility, decoded, forward_state; context=context)
    return FeasibilityEvaluation(
        feasibility,
        decoded,
        forward_state,
        context,
        penalty,
        diagnostics,
    )
end
