"""
Adjoint-contract primitives for FiberLab inverse-design experiments.

This layer is intentionally small. It gives controls and objectives a common
shape for direct native execution and compatibility preflight:

- controls decode optimizer coordinates into physical simulation controls
- controls pull physical gradients back to optimizer coordinates
- objectives either expose a terminal adjoint or are rejected by gradient
  solvers until such a contract exists
"""

abstract type AbstractControlMap end
abstract type AbstractFiberObjective end

_nonempty_name(name::Symbol, label::AbstractString) =
    name == Symbol("") && throw(ArgumentError("$label name cannot be empty"))

function _finite_real_vector(values, expected::Int, label::AbstractString)
    _require_vector_length(values, expected, label)
    vector = Float64.(collect(values))
    all(isfinite, vector) || throw(ArgumentError("$label contains non-finite values"))
    return vector
end

"""
    ControlEvaluation(control, coordinates, decoded, user_context)

Decoded control state for one optimizer point. Pullbacks receive this state as
context so nonlinear parameterizations can use the primal coordinates and
decoded physical value when applying the chain rule.
"""
struct ControlEvaluation{C<:AbstractControlMap,D,U}
    control::C
    coordinates::Vector{Float64}
    decoded::D
    user_context::U
end

"""
    ControlGradient(evaluation, physical_gradient, optimizer_gradient)

Result of pulling a physical adjoint gradient back to optimizer coordinates for
one evaluated control.
"""
struct ControlGradient{E<:ControlEvaluation,P}
    evaluation::E
    physical_gradient::P
    optimizer_gradient::Vector{Float64}
end

control_context(evaluation::ControlEvaluation) = (
    control = evaluation.control,
    coordinates = evaluation.coordinates,
    decoded = evaluation.decoded,
    user = evaluation.user_context,
)

gradient_vector(gradient::ControlGradient) = copy(gradient.optimizer_gradient)

"""
    CoordinateBounds(lower, upper)

Box bounds in optimizer-coordinate space. Use `-Inf` and `Inf` for unbounded
coordinates. These bounds are intentionally coordinate-level so they work for
any control map a researcher defines.
"""
struct CoordinateBounds
    lower::Vector{Float64}
    upper::Vector{Float64}

    function CoordinateBounds(lower, upper)
        lo = Float64.(collect(lower))
        hi = Float64.(collect(upper))
        isempty(lo) && throw(ArgumentError("CoordinateBounds requires at least one coordinate"))
        length(lo) == length(hi) || throw(ArgumentError(
            "CoordinateBounds lower length $(length(lo)) does not match upper length $(length(hi))"))
        all(isfinite_or_infinite, lo) && all(isfinite_or_infinite, hi) ||
            throw(ArgumentError("CoordinateBounds entries must be finite or infinite real values"))
        all(lo .<= hi) || throw(ArgumentError("CoordinateBounds lower entries must be <= upper entries"))
        return new(lo, hi)
    end
end

isfinite_or_infinite(value::Real) = !isnan(Float64(value))

"""
    ControlBlock(name, map)

Named continuous control block in an optimizer vector.
"""
struct ControlBlock{M<:AbstractControlMap}
    name::Symbol
    map::M
end

"""
    ControlSpace(blocks...)

Ordered collection of continuous control blocks. A control space owns the
packing convention for multivariable adjoint optimization.
"""
struct ControlSpace <: AbstractControlMap
    blocks::Tuple{Vararg{ControlBlock}}

    function ControlSpace(blocks::ControlBlock...)
        isempty(blocks) && throw(ArgumentError("ControlSpace requires at least one block"))
        names = Symbol[block.name for block in blocks]
        length(unique(names)) == length(names) || throw(ArgumentError(
            "ControlSpace block names must be unique, got $(names)"))
        return new(Tuple(blocks))
    end
end

ControlSpace(pairs::Pair{Symbol,<:AbstractControlMap}...) =
    ControlSpace((ControlBlock(first(pair), last(pair)) for pair in pairs)...)

"""
    FullGridPhase(nt; name=:phase, units="rad")

Full-grid spectral phase control. Optimizer coordinates are already the
physical phase samples, so decode and pullback are both identity maps with
finite-value and length checks.
"""
struct FullGridPhase <: AbstractControlMap
    name::Symbol
    nt::Int
    units::String
    figure_hooks::Tuple{Vararg{Symbol}}

    function FullGridPhase(nt::Integer; name::Symbol=:phase,
                           units::AbstractString="rad",
                           figure_hooks=(:phase_profile, :group_delay))
        _nonempty_name(name, "control")
        nt > 0 || throw(ArgumentError("FullGridPhase requires a positive sample count"))
        hooks = Tuple(Symbol(hook) for hook in figure_hooks)
        return new(name, Int(nt), String(units), hooks)
    end
end

"""
    ScalarControl(name; units="", figure_hooks=())

Single real-valued identity control. This is intentionally not a positivity or
bounded transform; use a custom `ControlMap` when the transform carries
scientific meaning.
"""
struct ScalarControl <: AbstractControlMap
    name::Symbol
    units::String
    figure_hooks::Tuple{Vararg{Symbol}}

    function ScalarControl(name::Symbol; units::AbstractString="", figure_hooks=())
        _nonempty_name(name, "control")
        hooks = Tuple(Symbol(hook) for hook in figure_hooks)
        return new(name, String(units), hooks)
    end
end

"""
    PositiveScalar(name; units="", figure_hooks=())

Single positive scalar control using an explicit log-coordinate
parameterization: `decoded = exp(x[1])`. This is intentionally a separate type
so positivity is visible at the call site instead of being a hidden default.
"""
struct PositiveScalar <: AbstractControlMap
    name::Symbol
    units::String
    figure_hooks::Tuple{Vararg{Symbol}}

    function PositiveScalar(name::Symbol; units::AbstractString="", figure_hooks=())
        _nonempty_name(name, "control")
        hooks = Tuple(Symbol(hook) for hook in figure_hooks)
        return new(name, String(units), hooks)
    end
end

"""
    ControlMap(name; dimension, decode, pullback=nothing, figure_hooks=(), units="", description="")

User-defined continuous control map. `decode(values, context)` maps optimizer
coordinates into a physical control, and `pullback(physical_gradient, context)`
maps physical adjoint gradients back to optimizer coordinates.
"""
struct ControlMap <: AbstractControlMap
    name::Symbol
    dimension::Int
    decode_function::Function
    pullback_function::Union{Nothing,Function}
    figure_hooks::Tuple{Vararg{Symbol}}
    units::String
    description::String

    function ControlMap(name::Symbol; dimension::Integer,
                        decode::Function,
                        pullback::Union{Nothing,Function}=nothing,
                        figure_hooks=(),
                        units::AbstractString="",
                        description::AbstractString="")
        _nonempty_name(name, "control")
        dimension > 0 || throw(ArgumentError("control `$(name)` dimension must be positive"))
        hooks = Tuple(Symbol(hook) for hook in figure_hooks)
        return new(name, Int(dimension), decode, pullback, hooks, String(units), String(description))
    end
end

"""
    PhaseBasis(basis; name=:phase, units="rad")

Linear spectral-phase control map. If `x` is the optimizer coefficient vector,
the physical phase profile is `basis * x`. The adjoint pullback is therefore
`basis' * grad_phase`.
"""
struct PhaseBasis <: AbstractControlMap
    name::Symbol
    basis::Matrix{Float64}
    units::String

    function PhaseBasis(basis::AbstractMatrix{<:Real};
                        name::Symbol=:phase,
                        units::AbstractString="rad")
        rows, cols = size(basis)
        rows > 0 || throw(ArgumentError("PhaseBasis requires at least one grid row"))
        cols > 0 || throw(ArgumentError("PhaseBasis requires at least one basis column"))
        return new(name, Matrix{Float64}(basis), String(units))
    end
end

"""
    AmplitudeBasis(basis; name=:amplitude, offset=1.0, scale=1.0, units="relative field amplitude")

Linear spectral-amplitude control around a positive offset:
`decoded = offset .+ scale .* (basis * x)`. The decoded profile must remain
strictly positive. For bounded or nonlinear amplitude parameterizations, use
`ControlMap` so the transform and pullback are explicit.
"""
struct AmplitudeBasis <: AbstractControlMap
    name::Symbol
    basis::Matrix{Float64}
    offset::Float64
    scale::Float64
    units::String
    figure_hooks::Tuple{Vararg{Symbol}}

    function AmplitudeBasis(basis::AbstractMatrix{<:Real};
                            name::Symbol=:amplitude,
                            offset::Real=1.0,
                            scale::Real=1.0,
                            units::AbstractString="relative field amplitude",
                            figure_hooks=control_contract(:amplitude).figure_hooks)
        _nonempty_name(name, "control")
        rows, cols = size(basis)
        rows > 0 || throw(ArgumentError("AmplitudeBasis requires at least one grid row"))
        cols > 0 || throw(ArgumentError("AmplitudeBasis requires at least one basis column"))
        isfinite(Float64(offset)) || throw(ArgumentError("AmplitudeBasis offset must be finite"))
        isfinite(Float64(scale)) || throw(ArgumentError("AmplitudeBasis scale must be finite"))
        hooks = Tuple(Symbol(hook) for hook in figure_hooks)
        return new(name, Matrix{Float64}(basis), Float64(offset), Float64(scale),
                   String(units), hooks)
    end
end

dimension(control::ControlMap) = control.dimension
dimension(control::FullGridPhase) = control.nt
dimension(control::PhaseBasis) = size(control.basis, 2)
dimension(control::AmplitudeBasis) = size(control.basis, 2)
dimension(::ScalarControl) = 1
dimension(::PositiveScalar) = 1

function _require_vector_length(values, expected::Int, label::AbstractString)
    length(values) == expected || throw(ArgumentError(
        "$label length $(length(values)) does not match expected length $expected"))
    return nothing
end

"""
    decode(control, values, context=nothing)

Map optimizer coordinates into the physical simulation coordinates owned by a
control map.
"""
function decode(control::PhaseBasis, values, context=nothing)
    _require_vector_length(values, size(control.basis, 2), "phase-basis coefficient")
    return control.basis * Float64.(collect(values))
end

decode(control::FullGridPhase, values, context=nothing) =
    _finite_real_vector(values, control.nt, "full-grid phase")

function decode(control::ScalarControl, values, context=nothing)
    vector = _finite_real_vector(values, 1, "scalar control `$(control.name)`")
    return first(vector)
end

function decode(control::PositiveScalar, values, context=nothing)
    vector = _finite_real_vector(values, 1, "positive scalar control `$(control.name)`")
    return exp(first(vector))
end

function decode(control::AmplitudeBasis, values, context=nothing)
    _require_vector_length(values, size(control.basis, 2), "amplitude-basis coefficient")
    decoded = control.offset .+ control.scale .* (control.basis * Float64.(collect(values)))
    all(isfinite, decoded) || throw(ArgumentError(
        "amplitude control `$(control.name)` decoded non-finite values"))
    minimum(decoded) > 0 || throw(ArgumentError(
        "amplitude control `$(control.name)` decoded non-positive values"))
    return decoded
end

function decode(control::ControlMap, values, context=nothing)
    x = _finite_real_vector(values, control.dimension, "control `$(control.name)` coordinate")
    decoded = control.decode_function(x, context)
    decoded === nothing && throw(ArgumentError("control `$(control.name)` decode returned nothing"))
    return decoded
end

"""
    evaluate_control(control, values; context=nothing) -> ControlEvaluation

Decode a control and keep the optimizer coordinates alongside the physical
decoded value. This is the API-native execution primitive that makes nonlinear
control pullbacks well-defined.
"""
function evaluate_control(control::AbstractControlMap, values; context=nothing)
    x = _finite_real_vector(values, dimension(control), "control `$(control.name)` coordinate")
    decoded = decode(control, x, context)
    return ControlEvaluation(control, x, decoded, context)
end

function evaluate_control(space::ControlSpace, values; context=nothing)
    layout = control_slices(space)
    x = _finite_real_vector(values, layout.total_dimension, "control-space vector")
    pairs = Pair{Symbol,Any}[]
    for block in space.blocks
        block_values = view(x, layout.slices[block.name])
        push!(pairs, block.name => evaluate_control(block.map, block_values; context=context))
    end
    return (; pairs...)
end

"""
    pullback(control, physical_gradient, context=nothing)

Map a gradient in physical simulation coordinates back to optimizer
coordinates. For a linear basis phase control this is the basis transpose.
"""
function pullback(control::PhaseBasis, physical_gradient, context=nothing)
    _require_vector_length(physical_gradient, size(control.basis, 1), "phase-basis gradient")
    return transpose(control.basis) * Float64.(collect(physical_gradient))
end

pullback(control::FullGridPhase, physical_gradient, context=nothing) =
    _finite_real_vector(physical_gradient, control.nt, "full-grid phase gradient")

function pullback(control::ScalarControl, physical_gradient, context=nothing)
    vector = _finite_real_vector(physical_gradient, 1, "scalar control `$(control.name)` gradient")
    return vector
end

function pullback(control::PositiveScalar, physical_gradient, context=nothing)
    vector = _finite_real_vector(physical_gradient, 1, "positive scalar control `$(control.name)` gradient")
    decoded = if context !== nothing && hasproperty(context, :decoded)
        Float64(context.decoded)
    else
        1.0
    end
    isfinite(decoded) && decoded > 0 || throw(ArgumentError(
        "positive scalar control `$(control.name)` pullback requires positive decoded value"))
    return [first(vector) * decoded]
end

function pullback(control::AmplitudeBasis, physical_gradient, context=nothing)
    _require_vector_length(physical_gradient, size(control.basis, 1), "amplitude-basis gradient")
    return control.scale .* (transpose(control.basis) * Float64.(collect(physical_gradient)))
end

function pullback(control::ControlMap, physical_gradient, context=nothing)
    control.pullback_function === nothing && throw(ArgumentError(
        "control `$(control.name)` does not declare a pullback"))
    gradient = control.pullback_function(physical_gradient, context)
    return _finite_real_vector(gradient, control.dimension, "control `$(control.name)` pullback")
end

pullback(evaluation::ControlEvaluation, physical_gradient) =
    pullback(evaluation.control, physical_gradient, control_context(evaluation))

"""
    pullback_gradient(evaluation, physical_gradient) -> ControlGradient

Structured pullback result for API-native adjoint execution. The optimizer
gradient is always a finite `Vector{Float64}` with the evaluated control's
dimension.
"""
function pullback_gradient(evaluation::ControlEvaluation, physical_gradient)
    optimizer_gradient = pullback(evaluation, physical_gradient)
    _require_vector_length(
        optimizer_gradient,
        dimension(evaluation.control),
        "optimizer gradient for control `$(evaluation.control.name)`",
    )
    return ControlGradient(evaluation, physical_gradient, optimizer_gradient)
end

function pullback_gradient(evaluations::NamedTuple, physical_gradients)
    pairs = Pair{Symbol,Any}[]
    for name in propertynames(evaluations)
        hasproperty(physical_gradients, name) || throw(ArgumentError(
            "physical gradients are missing evaluated control `$(name)`"))
        push!(pairs, name => pullback_gradient(
            getproperty(evaluations, name),
            getproperty(physical_gradients, name),
        ))
    end
    return (; pairs...)
end

has_pullback(::AbstractControlMap) = false
has_pullback(control::ControlMap) = control.pullback_function !== nothing
has_pullback(::FullGridPhase) = true
has_pullback(::PhaseBasis) = true
has_pullback(::AmplitudeBasis) = true
has_pullback(::ScalarControl) = true
has_pullback(::PositiveScalar) = true

dimension(block::ControlBlock) = dimension(block.map)

function control_slices(space::ControlSpace)
    slices = Dict{Symbol,UnitRange{Int}}()
    cursor = 1
    for block in space.blocks
        n = dimension(block)
        slices[block.name] = cursor:(cursor + n - 1)
        cursor += n
    end
    return (
        slices = slices,
        total_dimension = cursor - 1,
        names = Tuple(block.name for block in space.blocks),
    )
end

dimension(space::ControlSpace) = control_slices(space).total_dimension

function _bound_vector(value, n::Int, label::AbstractString, default::Float64)
    value === nothing && return fill(default, n)
    if value isa Real
        number = Float64(value)
        isnan(number) && throw(ArgumentError("$label bound cannot be NaN"))
        return fill(number, n)
    end
    vector = Float64.(collect(value))
    length(vector) == n || throw(ArgumentError(
        "$label bound length $(length(vector)) does not match expected length $n"))
    any(isnan, vector) && throw(ArgumentError("$label bound cannot contain NaN"))
    return vector
end

function _coerce_coordinate_bounds(spec, n::Int, label::AbstractString)
    spec isa CoordinateBounds && begin
        length(spec.lower) == n || throw(ArgumentError(
            "$label bounds length $(length(spec.lower)) does not match expected length $n"))
        return spec
    end
    if spec isa NamedTuple
        lower = hasproperty(spec, :lower) ? getproperty(spec, :lower) : nothing
        upper = hasproperty(spec, :upper) ? getproperty(spec, :upper) : nothing
        return CoordinateBounds(
            _bound_vector(lower, n, "$label lower", -Inf),
            _bound_vector(upper, n, "$label upper", Inf),
        )
    end
    if spec isa Tuple && length(spec) == 2
        return CoordinateBounds(
            _bound_vector(spec[1], n, "$label lower", -Inf),
            _bound_vector(spec[2], n, "$label upper", Inf),
        )
    end
    throw(ArgumentError(
        "$label bounds must be CoordinateBounds, a (lower, upper) tuple, or a NamedTuple with lower/upper"))
end

"""
    control_bounds(control; lower=nothing, upper=nothing)
    control_bounds(space, :phase => (lower, upper), :amplitude => (lower, upper))

Build optimizer-coordinate bounds for any control map. For `ControlSpace`, pass
only the blocks that need bounds; unspecified blocks remain unbounded.
"""
function control_bounds(control::AbstractControlMap; lower=nothing, upper=nothing)
    n = dimension(control)
    return CoordinateBounds(
        _bound_vector(lower, n, "control lower", -Inf),
        _bound_vector(upper, n, "control upper", Inf),
    )
end

function control_bounds(space::ControlSpace, block_bounds::Pair{Symbol}...)
    layout = control_slices(space)
    lower = fill(-Inf, layout.total_dimension)
    upper = fill(Inf, layout.total_dimension)
    block_dimensions = Dict(block.name => dimension(block) for block in space.blocks)
    for (name, spec) in block_bounds
        haskey(layout.slices, name) || throw(ArgumentError(
            "control-space bounds reference unknown block `$(name)`"))
        bounds = _coerce_coordinate_bounds(spec, block_dimensions[name], "block `$(name)`")
        lower[layout.slices[name]] .= bounds.lower
        upper[layout.slices[name]] .= bounds.upper
    end
    return CoordinateBounds(lower, upper)
end

function decode(space::ControlSpace, values, context=nothing)
    layout = control_slices(space)
    _require_vector_length(values, layout.total_dimension, "control-space vector")
    x = Float64.(collect(values))
    pairs = Pair{Symbol,Any}[]
    for block in space.blocks
        push!(pairs, block.name => decode(block.map, view(x, layout.slices[block.name]), context))
    end
    return (; pairs...)
end

function pullback(space::ControlSpace, physical_gradients, context=nothing)
    layout = control_slices(space)
    gradient = zeros(Float64, layout.total_dimension)
    for block in space.blocks
        hasproperty(physical_gradients, block.name) || throw(ArgumentError(
            "physical gradients are missing block `$(block.name)`"))
        block_gradient = pullback(block.map, getproperty(physical_gradients, block.name), context)
        _require_vector_length(block_gradient, dimension(block), "control-space block gradient")
        gradient[layout.slices[block.name]] .= block_gradient
    end
    return gradient
end

has_pullback(space::ControlSpace) = all(block -> has_pullback(block.map), space.blocks)

"""
    ScalarObjective(name, cost; description="")

Objective with a cost function but no declared terminal adjoint. This can be
used for planning and documentation, but `assert_adjoint_ready` rejects it for
gradient-based adjoint execution.
"""
struct ScalarObjective <: AbstractFiberObjective
    name::Symbol
    cost::Function
    description::String

    function ScalarObjective(name::Symbol, cost::Function; description::AbstractString="")
        _nonempty_name(name, "objective")
        return new(name, cost, String(description))
    end
end

"""
    AdjointObjective(name; cost, terminal_adjoint, description="")

Objective with the terminal-adjoint seed required by adjoint propagation.
"""
struct AdjointObjective <: AbstractFiberObjective
    name::Symbol
    cost::Function
    terminal_adjoint_function::Function
    description::String

    function AdjointObjective(name::Symbol;
                              cost::Function,
                              terminal_adjoint::Function,
                              description::AbstractString="")
        _nonempty_name(name, "objective")
        return new(name, cost, terminal_adjoint, String(description))
    end
end

"""
    ObjectiveMap(name; cost, terminal_adjoint=nothing, figure_hooks=(), cost_scale=:linear,
                 contract_kind=name, description="")

User-defined objective. Gradient-based adjoint solvers require
`terminal_adjoint(final_state, context)`, which seeds the adjoint propagation at
the output of the forward model.
"""
struct _ObjectiveProblemBinding
    sha256::String
end

struct _ObjectiveBindingToken end
const _OBJECTIVE_BINDING_TOKEN = _ObjectiveBindingToken()

struct ObjectiveMap <: AbstractFiberObjective
    name::Symbol
    contract_kind::Symbol
    cost::Function
    terminal_adjoint_function::Union{Nothing,Function}
    figure_hooks::Tuple{Vararg{Symbol}}
    cost_scale::Symbol
    description::String
    _problem_binding::Union{Nothing,_ObjectiveProblemBinding}

    function ObjectiveMap(name::Symbol; cost::Function,
                          terminal_adjoint::Union{Nothing,Function}=nothing,
                          figure_hooks=(),
                          cost_scale::Symbol=:linear,
                          contract_kind::Symbol=name,
                          description::AbstractString="")
        _nonempty_name(name, "objective")
        _nonempty_name(contract_kind, "objective contract")
        cost_scale in (:linear, :db) || throw(ArgumentError(
            "ObjectiveMap cost_scale must be :linear or :db"))
        hooks = Tuple(Symbol(hook) for hook in figure_hooks)
        return new(
            name,
            contract_kind,
            cost,
            terminal_adjoint,
            hooks,
            cost_scale,
            String(description),
            nothing,
        )
    end

    function ObjectiveMap(token::_ObjectiveBindingToken, name::Symbol;
                          cost::Function,
                          terminal_adjoint::Union{Nothing,Function}=nothing,
                          figure_hooks=(),
                          cost_scale::Symbol=:linear,
                          contract_kind::Symbol=name,
                          description::AbstractString="",
                          problem_sha256::AbstractString)
        token === _OBJECTIVE_BINDING_TOKEN || throw(ArgumentError(
            "problem-bound objectives can only be created by FiberLab"))
        _nonempty_name(name, "objective")
        _nonempty_name(contract_kind, "objective contract")
        cost_scale in (:linear, :db) || throw(ArgumentError(
            "ObjectiveMap cost_scale must be :linear or :db"))
        hooks = Tuple(Symbol(hook) for hook in figure_hooks)
        return new(
            name,
            contract_kind,
            cost,
            terminal_adjoint,
            hooks,
            cost_scale,
            String(description),
            _ObjectiveProblemBinding(String(problem_sha256)),
        )
    end
end

_objective_cost_scale(::AbstractFiberObjective) = :linear
_objective_cost_scale(objective::ObjectiveMap) = objective.cost_scale

_objective_contract_kind(objective::AbstractFiberObjective) = objective.name
_objective_contract_kind(objective::ObjectiveMap) = objective.contract_kind

_objective_problem_sha256(::AbstractFiberObjective) = nothing
function _objective_problem_sha256(objective::ObjectiveMap)
    binding = getfield(objective, :_problem_binding)
    return binding === nothing ? nothing : binding.sha256
end

has_terminal_adjoint(::AbstractFiberObjective) = false
has_terminal_adjoint(::AdjointObjective) = true
has_terminal_adjoint(objective::ObjectiveMap) = objective.terminal_adjoint_function !== nothing

function terminal_adjoint(objective::AdjointObjective, final_state, context=nothing)
    adjoint = objective.terminal_adjoint_function(final_state, context)
    size(adjoint) == size(final_state) || throw(ArgumentError(
        "terminal adjoint shape $(size(adjoint)) does not match final state shape $(size(final_state))"))
    all(isfinite, real.(adjoint)) && all(isfinite, imag.(adjoint)) || throw(ArgumentError(
        "terminal adjoint for objective `$(objective.name)` contains non-finite values"))
    return adjoint
end

function terminal_adjoint(objective::ObjectiveMap, final_state, context=nothing)
    objective.terminal_adjoint_function === nothing && throw(ArgumentError(
        "objective `$(objective.name)` does not declare a terminal adjoint"))
    adjoint = objective.terminal_adjoint_function(final_state, context)
    size(adjoint) == size(final_state) || throw(ArgumentError(
        "terminal adjoint shape $(size(adjoint)) does not match final state shape $(size(final_state))"))
    all(isfinite, real.(adjoint)) && all(isfinite, imag.(adjoint)) || throw(ArgumentError(
        "terminal adjoint for objective `$(objective.name)` contains non-finite values"))
    return adjoint
end

function terminal_adjoint(objective::ScalarObjective, final_state, context=nothing)
    throw(ArgumentError(
        "objective `$(objective.name)` does not declare a terminal adjoint; " *
        "provide an AdjointObjective or use a non-adjoint planning workflow"))
end

_solver_requires_gradient(solver::Solver) = solver.kind in (:lbfgs,)
_solver_requires_gradient(solver::Symbol) = solver in (:lbfgs,)
_objective_name(objective::AbstractFiberObjective) = objective.name

"""
    assert_adjoint_ready(objective, control, solver)

Defensive execution gate for adjoint-gradient solvers. Gradient-based solvers
require both an objective terminal adjoint and a control pullback.
"""
function assert_adjoint_ready(objective::AbstractFiberObjective,
                              control::AbstractControlMap,
                              solver)
    _solver_requires_gradient(solver) || return true
    has_terminal_adjoint(objective) || throw(ArgumentError(
        "solver `$(solver isa Solver ? solver.kind : solver)` requires a terminal adjoint for objective `$(_objective_name(objective))`"))
    has_pullback(control) || throw(ArgumentError(
        "solver `$(solver isa Solver ? solver.kind : solver)` requires a pullback for control `$(typeof(control))`"))
    return true
end
