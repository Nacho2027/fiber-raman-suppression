"""
API-native adjoint execution primitives.

This layer is deliberately model-agnostic. It does not know about Raman,
single-mode propagation, multimode propagation, or any particular control. It
only wires the generic adjoint contract:

control decode -> forward model -> objective cost -> terminal adjoint ->
physical gradient -> control pullback.
"""

struct ResolvedProblemSource{P}
    problem::P
    snapshot_sha256::String
end

struct NativeRunSource{M,P}
    metadata::M
    problem::P
    snapshot_sha256::String
end

"""
    AdjointModel(name; forward, physical_gradient, description="")

Generic model contract for API-native adjoint execution.

`forward(decoded_control, context)` returns the final state seen by the
objective. `physical_gradient(decoded_control, terminal_adjoint, context)`
returns the gradient with respect to the decoded physical control.
"""
struct AdjointModel
    name::Symbol
    forward_function::Function
    physical_gradient_function::Function
    description::String
    problem_source::Union{Nothing,ResolvedProblemSource}
    run_source::Union{Nothing,NativeRunSource}

    function AdjointModel(name::Symbol; forward::Function,
                          physical_gradient::Function,
                          description::AbstractString="")
        _nonempty_name(name, "adjoint model")
        return new(name, forward, physical_gradient, String(description), nothing, nothing)
    end

    function AdjointModel(name::Symbol, problem_source::ResolvedProblemSource;
                          run_source::Union{Nothing,NativeRunSource}=nothing,
                          forward::Function,
                          physical_gradient::Function,
                          description::AbstractString="")
        _nonempty_name(name, "adjoint model")
        return new(
            name,
            forward,
            physical_gradient,
            String(description),
            problem_source,
            run_source,
        )
    end
end

_adjoint_model(name::Symbol, source::ResolvedProblemSource;
               run_source::Union{Nothing,NativeRunSource}=nothing, kwargs...) =
    AdjointModel(name, source; run_source = run_source, kwargs...)

struct AdjointStepResult{M<:AdjointModel,E,O<:AbstractFiberObjective,F,A,P,G}
    model::M
    control_evaluation::E
    objective::O
    forward_state::F
    cost::Float64
    terminal_adjoint::A
    physical_gradient::P
    control_gradient::G
end

struct NativeArtifactContext{P<:ExperimentPlan}
    plan::P
    output_dir::String
    tag::String
    hook::Symbol
end

Base.@kwdef struct NativeAdjointBackend <: AbstractExecutionBackend
    model::AdjointModel
    initial_coordinates::Vector{Float64}
    step_size::Float64 = 1e-2
    max_iter::Union{Nothing,Int} = nothing
    gradient_tolerance::Float64 = 0.0
    context = nothing
    run_source::Union{Nothing,NativeRunSource} = nothing
    write_artifacts::Bool = false
    strict_artifacts::Bool = true
    output_dir::Union{Nothing,String} = nothing
    artifact_writers::Dict{Symbol,Function} = Dict{Symbol,Function}()
    feasibility::Union{Nothing,FeasibilityMap} = nothing
    bounds::Union{Nothing,CoordinateBounds} = nothing
    trust_profile = nothing
    require_trust::Bool = false
    trust_gradient_check::Bool = false

    function NativeAdjointBackend(model::AdjointModel;
                                  initial_coordinates,
                                  step_size::Real=1e-2,
                                  max_iter::Union{Nothing,Integer}=nothing,
                                  gradient_tolerance::Real=0.0,
                                  context=nothing,
                                  write_artifacts::Bool=false,
                                  strict_artifacts::Bool=true,
                                  output_dir::Union{Nothing,AbstractString}=nothing,
                                  artifact_writers=Dict{Symbol,Function}(),
                                  feasibility::Union{Nothing,FeasibilityMap}=nothing,
                                  bounds::Union{Nothing,CoordinateBounds}=nothing,
                                  trust_profile=nothing,
                                  require_trust::Bool=false,
                                  trust_gradient_check::Bool=false)
        coordinates = Float64.(collect(initial_coordinates))
        isempty(coordinates) && throw(ArgumentError(
            "NativeAdjointBackend requires at least one initial coordinate"))
        all(isfinite, coordinates) || throw(ArgumentError(
            "NativeAdjointBackend initial_coordinates contain non-finite values"))
        isfinite(Float64(step_size)) && Float64(step_size) > 0 || throw(ArgumentError(
            "NativeAdjointBackend step_size must be positive and finite"))
        max_iter !== nothing && Int(max_iter) > 0 || max_iter === nothing || throw(ArgumentError(
            "NativeAdjointBackend max_iter must be positive when provided"))
        isfinite(Float64(gradient_tolerance)) && Float64(gradient_tolerance) >= 0 || throw(ArgumentError(
            "NativeAdjointBackend gradient_tolerance must be non-negative and finite"))
        writers = _native_artifact_writers(artifact_writers)
        return new(model, coordinates, Float64(step_size),
                   max_iter === nothing ? nothing : Int(max_iter),
                   Float64(gradient_tolerance), context, model.run_source,
                   write_artifacts,
                   strict_artifacts,
                   output_dir === nothing ? nothing : String(output_dir),
                   writers,
                   feasibility,
                   bounds,
                   trust_profile,
                   require_trust,
                   trust_gradient_check)
    end
end

struct AdjointGradientCheckResult
    pass::Bool
    coordinates::Vector{Int}
    adjoint_gradient::Vector{Float64}
    finite_difference_gradient::Vector{Float64}
    absolute_error::Vector{Float64}
    relative_error::Vector{Float64}
    atol::Float64
    rtol::Float64
    step::Float64
end

function _native_solver_from_keywords(solver::Solver,
                                      max_iter::Union{Nothing,Integer},
                                      validate_gradient::Union{Nothing,Bool})
    max_iter_value = max_iter === nothing ? solver.max_iter : Int(max_iter)
    validate_value = validate_gradient === nothing ?
        solver.validate_gradient :
        Bool(validate_gradient)
    return Solver(;
        kind = solver.kind,
        max_iter = max_iter_value,
        validate_gradient = validate_value,
        store_trace = solver.store_trace,
    )
end

struct NativeAdjointResult{E<:ExperimentPlan,B<:NativeAdjointBackend,S}
    plan::E
    backend::B
    x_initial::Vector{Float64}
    x_final::Vector{Float64}
    cost_initial::Float64
    cost_final::Float64
    convergence_trace::Vector{NamedTuple{(:iteration,:cost,:gradient_norm),Tuple{Int,Float64,Float64}}}
    final_step::S
    converged::Bool
    gradient_check::Union{Nothing,AdjointGradientCheckResult}
    feasibility_evaluation
    output_dir::Union{Nothing,String}
    sidecar_path::Union{Nothing,String}
    artifact_paths::Dict{Symbol,String}
    trust_report
end

"""
    objective_value(objective, final_state)

Evaluate an objective on a propagated final field with the same scalar and
finite-value validation used by native adjoint execution.
"""
function objective_value(objective::AbstractFiberObjective, final_state)
    value = objective.cost(final_state)
    value isa Real || throw(ArgumentError(
        "objective `$(objective.name)` cost must return a real scalar"))
    isfinite(Float64(value)) || throw(ArgumentError(
        "objective `$(objective.name)` cost returned a non-finite value"))
    return Float64(value)
end

_objective_cost(objective::AbstractFiberObjective, final_state) =
    objective_value(objective, final_state)

function _run_model_forward(model::AdjointModel, decoded_control, context)
    final_state = model.forward_function(decoded_control, context)
    final_state === nothing && throw(ArgumentError(
        "adjoint model `$(model.name)` forward returned nothing"))
    return final_state
end

function _run_model_physical_gradient(model::AdjointModel, decoded_control,
                                      terminal_seed, context)
    gradient = model.physical_gradient_function(decoded_control, terminal_seed, context)
    gradient === nothing && throw(ArgumentError(
        "adjoint model `$(model.name)` physical_gradient returned nothing"))
    return gradient
end

function _decoded_value(evaluation::ControlEvaluation)
    return evaluation.decoded
end

function _decoded_value(evaluations::NamedTuple)
    pairs = Pair{Symbol,Any}[]
    for name in propertynames(evaluations)
        push!(pairs, name => getproperty(evaluations, name).decoded)
    end
    return (; pairs...)
end

function _flatten_gradient(gradient::ControlGradient)
    return gradient_vector(gradient)
end

function _flatten_gradient(gradients::NamedTuple)
    values = Float64[]
    for name in propertynames(gradients)
        append!(values, gradient_vector(getproperty(gradients, name)))
    end
    return values
end

function _add_physical_gradients(left, right)
    right === nothing && return left
    left === nothing && return right
    if left isa NamedTuple && right isa NamedTuple
        names = union(propertynames(left), propertynames(right))
        pairs = Pair{Symbol,Any}[]
        for name in names
            has_left = hasproperty(left, name)
            has_right = hasproperty(right, name)
            value = if has_left && has_right
                _add_physical_gradients(getproperty(left, name), getproperty(right, name))
            elseif has_left
                getproperty(left, name)
            else
                getproperty(right, name)
            end
            push!(pairs, name => value)
        end
        return (; pairs...)
    end
    if left isa AbstractDict && right isa AbstractDict
        keys_left = Symbol.(collect(keys(left)))
        keys_right = Symbol.(collect(keys(right)))
        merged = Dict{Symbol,Any}()
        for key in union(keys_left, keys_right)
            left_value = haskey(left, key) ? left[key] : get(left, String(key), nothing)
            right_value = haskey(right, key) ? right[key] : get(right, String(key), nothing)
            has_left = left_value !== nothing
            has_right = right_value !== nothing
            merged[key] = has_left && has_right ?
                _add_physical_gradients(left_value, right_value) :
                (has_left ? left_value : right_value)
        end
        return merged
    end
    return left .+ right
end

"""
    run_adjoint_step(model, control, objective, coordinates; context=nothing)

Run one generic adjoint-gradient evaluation. This is the simulation-light API
execution primitive used to validate custom controls/objectives before a full
optimizer loop is introduced.
"""
function run_adjoint_step(model::AdjointModel,
                          control,
                          objective::AbstractFiberObjective,
                          coordinates;
                          context=nothing,
                          feasibility::Union{Nothing,FeasibilityMap}=nothing)
    _validate_adjoint_sources(model, objective)
    assert_adjoint_ready(objective, control, :lbfgs)
    evaluation = evaluate_control(control, coordinates; context=context)
    decoded = _decoded_value(evaluation)
    final_state = _run_model_forward(model, decoded, context)
    feasibility_eval = feasibility === nothing ?
        nothing :
        evaluate_feasibility(feasibility, decoded, final_state; context=context)
    cost = _objective_cost(objective, final_state) +
        (feasibility_eval === nothing ? 0.0 : feasibility_eval.penalty)
    terminal_seed = terminal_adjoint(objective, final_state, context)
    physical_gradient = _run_model_physical_gradient(model, decoded, terminal_seed, context)
    feasibility_gradient = feasibility === nothing || !has_penalty(feasibility) ?
        nothing :
        feasibility_physical_gradient(feasibility, decoded, final_state; context=context)
    total_physical_gradient = _add_physical_gradients(physical_gradient, feasibility_gradient)
    control_gradient = pullback_gradient(evaluation, total_physical_gradient)

    return AdjointStepResult(
        model,
        evaluation,
        objective,
        final_state,
        cost,
        terminal_seed,
        total_physical_gradient,
        control_gradient,
    )
end

gradient_vector(result::AdjointStepResult) = gradient_vector(result.control_gradient)
gradient_vector(gradients::NamedTuple) = _flatten_gradient(gradients)

function _native_max_iter(plan::ExperimentPlan, backend::NativeAdjointBackend)
    return backend.max_iter === nothing ? plan.experiment.solver.max_iter : backend.max_iter
end

function _native_control(plan::ExperimentPlan)
    control = plan.experiment.control
    control isa AbstractControlMap || throw(FiberLabBackendError(
        plan,
        :native_adjoint,
        "NativeAdjointBackend requires an AbstractControlMap behavior object; symbolic Control experiments should use ConfigRunnerBackend or be lowered to a control map.",
    ))
    return control
end

function _native_objective(plan::ExperimentPlan)
    objective = plan.experiment.objective
    objective isa AbstractFiberObjective || throw(FiberLabBackendError(
        plan,
        :native_adjoint,
        "NativeAdjointBackend requires an AbstractFiberObjective behavior object; symbolic Objective experiments should use ConfigRunnerBackend or be lowered to an objective map.",
    ))
    return objective
end

function _native_trace_entry(iteration::Int, cost::Real, gradient)
    gradient_norm = norm(gradient)
    isfinite(Float64(cost)) || throw(ArgumentError(
        "native adjoint optimization produced a non-finite cost at iteration $(iteration)"))
    isfinite(Float64(gradient_norm)) || throw(ArgumentError(
        "native adjoint optimization produced a non-finite gradient norm at iteration $(iteration)"))
    return (
        iteration = iteration,
        cost = Float64(cost),
        gradient_norm = Float64(gradient_norm),
    )
end

function _trace_from_optim(result)
    trace = NamedTuple{(:iteration,:cost,:gradient_norm),Tuple{Int,Float64,Float64}}[]
    for item in Optim.trace(result)
        push!(trace, (
            iteration = Int(item.iteration),
            cost = Float64(item.value),
            gradient_norm = Float64(item.g_norm),
        ))
    end
    return trace
end

function _native_step_gradient(model::AdjointModel,
                               control,
                               objective::AbstractFiberObjective,
                               coordinates,
                               context,
                               expected_dimension::Int,
                               feasibility::Union{Nothing,FeasibilityMap}=nothing)
    step = run_adjoint_step(
        model,
        control,
        objective,
        coordinates;
        context = context,
        feasibility = feasibility,
    )
    gradient = _flatten_gradient(step.control_gradient)
    length(gradient) == expected_dimension || throw(ArgumentError(
        "native adjoint gradient length $(length(gradient)) does not match control dimension $(expected_dimension)"))
    entry = _native_trace_entry(0, step.cost, gradient)
    return step, gradient, entry
end

function _optim_options(plan::ExperimentPlan, backend::NativeAdjointBackend)
    max_iter = _native_max_iter(plan, backend)
    kwargs = Dict{Symbol,Any}(
        :iterations => max_iter,
        :store_trace => true,
        :extended_trace => true,
    )
    backend.gradient_tolerance > 0 && (kwargs[:g_tol] = backend.gradient_tolerance)
    return Optim.Options(; kwargs...)
end

function _validate_native_solver(plan::ExperimentPlan, backend::NativeAdjointBackend)
    plan.solver == :lbfgs || throw(FiberLabBackendError(
        plan,
        backend,
        "NativeAdjointBackend currently supports solver kind `:lbfgs`; got `$(plan.solver)`.",
    ))
    return nothing
end

function _optim_method(plan::ExperimentPlan, backend::NativeAdjointBackend)
    _validate_native_solver(plan, backend)
    return Optim.LBFGS(
        alphaguess = Optim.LineSearches.InitialStatic(alpha = backend.step_size),
    )
end

function _native_gradient_check(plan::ExperimentPlan,
                                backend::NativeAdjointBackend,
                                control,
                                objective::AbstractFiberObjective)
    plan.experiment.solver.validate_gradient || return nothing
    result = check_adjoint_gradient(
        backend.model,
        control,
        objective,
        backend.initial_coordinates;
        context = backend.context,
        feasibility = backend.feasibility,
    )
    result.pass || throw(FiberLabBackendError(
        plan,
        backend,
        "NativeAdjointBackend gradient validation failed before optimization. Maximum absolute error: $(maximum(result.absolute_error)); maximum relative error: $(maximum(result.relative_error)).",
    ))
    return result
end

function _validate_native_bounds(bounds::Union{Nothing,CoordinateBounds},
                                 expected_dimension::Int,
                                 initial_coordinates::Vector{Float64})
    bounds === nothing && return nothing
    length(bounds.lower) == expected_dimension || throw(ArgumentError(
        "NativeAdjointBackend bounds length $(length(bounds.lower)) does not match control dimension $(expected_dimension)"))
    all(bounds.lower .<= initial_coordinates .<= bounds.upper) || throw(ArgumentError(
        "NativeAdjointBackend initial_coordinates must satisfy the declared bounds"))
    return nothing
end

function _native_optimize(cost_function,
                          gradient_function!,
                          initial_coordinates::Vector{Float64},
                          method,
                          options,
                          bounds::Union{Nothing,CoordinateBounds})
    bounds === nothing && return Optim.optimize(
        cost_function,
        gradient_function!,
        copy(initial_coordinates),
        method,
        options,
    )
    return Optim.optimize(
        cost_function,
        gradient_function!,
        bounds.lower,
        bounds.upper,
        copy(initial_coordinates),
        Optim.Fminbox(method),
        options,
    )
end

function _native_cost(model::AdjointModel,
                      control,
                      objective::AbstractFiberObjective,
                      coordinates::Vector{Float64},
                      context,
                      feasibility::Union{Nothing,FeasibilityMap}=nothing)
    evaluation = evaluate_control(control, coordinates; context=context)
    decoded = _decoded_value(evaluation)
    final_state = _run_model_forward(model, decoded, context)
    penalty = feasibility === nothing ?
        0.0 :
        feasibility_penalty(feasibility, decoded, final_state; context=context)
    return _objective_cost(objective, final_state) + penalty
end

_native_json_value(value::Nothing) = nothing
_native_json_value(value::Missing) = nothing
_native_json_value(value::Symbol) = String(value)
_native_json_value(value::AbstractString) = String(value)
_native_json_value(value::Bool) = value
_native_json_value(value::Integer) = Int(value)
_native_json_value(value::Real) = Float64(value)
_native_json_value(value::AbstractVector) = [_native_json_value(item) for item in value]
_native_json_value(value::Tuple) = [_native_json_value(item) for item in value]
_native_json_value(value::NamedTuple) =
    Dict(String(name) => _native_json_value(getproperty(value, name))
         for name in propertynames(value))
_native_json_value(value::AbstractDict) =
    Dict(String(key) => _native_json_value(item) for (key, item) in pairs(value))
_native_json_value(value::FeasibilityMap) = Dict(
    "name" => String(value.name),
    "description" => value.description,
    "has_penalty" => has_penalty(value),
    "has_physical_gradient" => has_physical_gradient(value),
    "has_projection" => has_projection(value),
    "has_check" => has_feasibility_check(value),
)
_native_json_value(value::FeasibilityEvaluation) = Dict(
    "name" => String(value.feasibility.name),
    "penalty" => value.penalty,
    "diagnostics" => _native_json_value(value.diagnostics),
)
_native_json_value(value::CoordinateBounds) = Dict(
    "lower" => _native_json_value(value.lower),
    "upper" => _native_json_value(value.upper),
)

function _native_json_value(value)
    names = propertynames(value)
    if !isempty(names) && !(value isa Function)
        return Dict(String(name) => _native_json_value(getproperty(value, name))
                    for name in names)
    end
    return string(value)
end

function _native_experiment_summary(experiment, metadata_authority::Symbol)
    return Dict(
        "id" => experiment.id,
        "description" => experiment.description,
        "fiber" => _native_json_value(experiment.fiber),
        "pulse" => _native_json_value(experiment.pulse),
        "grid" => _native_json_value(experiment.grid),
        "solver" => _native_json_value(experiment.solver),
        "artifacts" => _native_json_value(experiment.artifacts),
        "output_root" => experiment.output_root,
        "output_tag" => experiment.output_tag,
        "maturity" => String(experiment.maturity),
        "metadata_authority" => String(metadata_authority),
    )
end

function _check_coordinate_indices(indices, dimension::Int)
    coordinate_indices = Int.(collect(indices))
    isempty(coordinate_indices) && throw(ArgumentError(
        "gradient check requires at least one coordinate index"))
    all(index -> 1 <= index <= dimension, coordinate_indices) || throw(ArgumentError(
        "gradient check coordinate indices must be within 1:$(dimension)"))
    length(unique(coordinate_indices)) == length(coordinate_indices) || throw(ArgumentError(
        "gradient check coordinate indices must be unique"))
    return coordinate_indices
end

"""
    check_adjoint_gradient(model, control, objective, coordinates; kwargs...)

Compare the API-native adjoint gradient with centered finite differences at one
optimizer point. This is intended for custom controls, objectives, and model
adjoints before trusting larger optimization runs.
"""
function check_adjoint_gradient(model::AdjointModel,
                                control,
                                objective::AbstractFiberObjective,
                                coordinates;
                                context=nothing,
                                feasibility::Union{Nothing,FeasibilityMap}=nothing,
                                step::Real=1e-6,
                                atol::Real=1e-6,
                                rtol::Real=1e-4,
                                coordinate_indices=nothing)
    _validate_adjoint_sources(model, objective)
    n = dimension(control)
    x = _finite_real_vector(coordinates, n, "gradient-check coordinate")
    h = Float64(step)
    abs_tol = Float64(atol)
    rel_tol = Float64(rtol)
    isfinite(h) && h > 0 || throw(ArgumentError(
        "gradient check step must be positive and finite"))
    isfinite(abs_tol) && abs_tol >= 0 || throw(ArgumentError(
        "gradient check atol must be non-negative and finite"))
    isfinite(rel_tol) && rel_tol >= 0 || throw(ArgumentError(
        "gradient check rtol must be non-negative and finite"))

    indices = coordinate_indices === nothing ?
        collect(1:n) :
        _check_coordinate_indices(coordinate_indices, n)

    step_result = run_adjoint_step(
        model,
        control,
        objective,
        x;
        context = context,
        feasibility = feasibility,
    )
    adjoint_gradient = _flatten_gradient(step_result.control_gradient)
    length(adjoint_gradient) == n || throw(ArgumentError(
        "adjoint gradient length $(length(adjoint_gradient)) does not match control dimension $(n)"))

    fd_gradient = similar(adjoint_gradient, length(indices))
    selected_adjoint = similar(adjoint_gradient, length(indices))
    for (slot, index) in pairs(indices)
        x_plus = copy(x)
        x_minus = copy(x)
        x_plus[index] += h
        x_minus[index] -= h
        cost_plus = _native_cost(model, control, objective, x_plus, context, feasibility)
        cost_minus = _native_cost(model, control, objective, x_minus, context, feasibility)
        fd_gradient[slot] = (cost_plus - cost_minus) / (2h)
        selected_adjoint[slot] = adjoint_gradient[index]
    end

    absolute_error = abs.(selected_adjoint .- fd_gradient)
    denominator = max.(abs.(fd_gradient), abs_tol)
    relative_error = absolute_error ./ denominator
    pass = all(absolute_error .<= abs_tol .+ rel_tol .* abs.(fd_gradient))

    return AdjointGradientCheckResult(
        pass,
        indices,
        selected_adjoint,
        fd_gradient,
        absolute_error,
        relative_error,
        abs_tol,
        rel_tol,
        h,
    )
end

function _native_output_dir(plan::ExperimentPlan, backend::NativeAdjointBackend)
    backend.output_dir !== nothing && return backend.output_dir
    return joinpath(plan.output_root, plan.output_tag)
end

function _native_convergence_payload(trace)
    return [
        Dict(
            "iteration" => item.iteration,
            "cost" => item.cost,
            "gradient_norm" => item.gradient_norm,
        )
        for item in trace
    ]
end

function _native_gradient_check_payload(check_result::Union{Nothing,AdjointGradientCheckResult})
    check_result === nothing && return nothing
    return Dict(
        "pass" => check_result.pass,
        "coordinates" => check_result.coordinates,
        "max_absolute_error" => maximum(check_result.absolute_error),
        "max_relative_error" => maximum(check_result.relative_error),
        "atol" => check_result.atol,
        "rtol" => check_result.rtol,
        "step" => check_result.step,
    )
end

function _native_artifact_writers(writers)
    normalized = Dict{Symbol,Function}()
    for (hook, writer) in pairs(writers)
        writer isa Function || throw(ArgumentError(
            "native artifact writer for hook `$(hook)` must be a function"))
        normalized[Symbol(hook)] = writer
    end
    return normalized
end

function _normalize_native_artifact_path(path::AbstractString)
    normalized = String(path)
    isfile(normalized) || throw(ArgumentError(
        "native artifact writer returned a path that does not exist: `$normalized`"))
    return normalized
end

function _normalize_native_artifact_paths(hook::Symbol, returned)
    returned === nothing && return Dict{Symbol,String}()
    returned isa AbstractString && return Dict(hook => _normalize_native_artifact_path(returned))
    returned isa Pair && return Dict(
        Symbol(first(returned)) => _normalize_native_artifact_path(last(returned)),
    )
    if returned isa AbstractDict
        paths = Dict{Symbol,String}()
        for (key, path) in pairs(returned)
            paths[Symbol(key)] = _normalize_native_artifact_path(path)
        end
        return paths
    end
    throw(ArgumentError(
        "native artifact writer for hook `$(hook)` must return nothing, a path string, a Pair, or a Dict"))
end

function _native_decoded_named_value(decoded, name::Symbol)
    if decoded isa NamedTuple && hasproperty(decoded, name)
        return getproperty(decoded, name)
    end
    if decoded isa AbstractDict
        haskey(decoded, name) && return decoded[name]
        haskey(decoded, String(name)) && return decoded[String(name)]
    end
    return nothing
end

function _native_decoded_control_value(result::NativeAdjointResult, name::Symbol)
    decoded = decoded_final(result)
    value = _native_decoded_named_value(decoded, name)
    value !== nothing && return value
    control = result.final_step.control_evaluation.control
    if hasproperty(control, :name) && getproperty(control, :name) == name
        return decoded
    end
    return nothing
end

function _native_real_profile(value)
    value === nothing && return nothing
    if value isa Real
        return [Float64(value)]
    end
    if value isa AbstractVector
        profile = Float64.(collect(value))
        all(isfinite, profile) || return nothing
        return profile
    end
    if value isa AbstractMatrix
        profile = Float64.(vec(sum(value; dims = 2)))
        all(isfinite, profile) || return nothing
        return profile
    end
    return nothing
end

function _native_field_power_profile(field)
    field isa AbstractVector && return abs2.(collect(field))
    field isa AbstractMatrix && return vec(sum(abs2, field; dims = 2))
    return nothing
end

function _native_mode_power_matrix(field)
    field isa AbstractMatrix || return nothing
    matrix = Float64.(abs2.(collect(field)))
    all(isfinite, matrix) || return nothing
    return matrix
end

function _save_native_line_plot(path::AbstractString, y;
                                title::AbstractString,
                                ylabel::AbstractString,
                                xlabel::AbstractString="sample")
    isempty(y) && return nothing
    fig = figure(figsize = (7, 3))
    try
        PyPlot.plot(collect(1:length(y)), y, lw = 1.4)
        PyPlot.title(title)
        PyPlot.xlabel(xlabel)
        PyPlot.ylabel(ylabel)
        PyPlot.ticklabel_format(axis = "y", useOffset = false)
        PyPlot.grid(true, alpha = 0.25)
        PyPlot.tight_layout()
        PyPlot.savefig(path, dpi = 140)
    finally
        PyPlot.close(fig)
    end
    return path
end

function _save_native_mode_plot(path::AbstractString, power::AbstractMatrix;
                                title::AbstractString)
    isempty(power) && return nothing
    fig = figure(figsize = (7, 3.5))
    try
        x = collect(1:size(power, 1))
        for mode_index in axes(power, 2)
            linestyle = mode_index == first(axes(power, 2)) ? "-" : "--"
            PyPlot.plot(x, power[:, mode_index], lw = 1.2,
                        linestyle = linestyle,
                        alpha = 0.85,
                        label = string("mode ", mode_index))
        end
        size(power, 2) <= 12 && PyPlot.legend(fontsize = 8, loc = "best")
        PyPlot.title(title)
        PyPlot.xlabel("sample")
        PyPlot.ylabel("power")
        PyPlot.grid(true, alpha = 0.25)
        PyPlot.tight_layout()
        PyPlot.savefig(path, dpi = 140)
    finally
        PyPlot.close(fig)
    end
    return path
end

function _write_native_field_summary(context::NativeArtifactContext,
                                     result::NativeAdjointResult)
    profile = _native_field_power_profile(result.final_step.forward_state)
    profile === nothing && return nothing
    path = joinpath(context.output_dir, string(context.tag, "_field_summary.png"))
    return _save_native_line_plot(
        path,
        Float64.(profile);
        title = "Final field power summary",
        ylabel = "power",
    )
end

function _write_native_mode_resolved_spectra(context::NativeArtifactContext,
                                             result::NativeAdjointResult)
    power = _native_mode_power_matrix(result.final_step.forward_state)
    power === nothing && return nothing
    path = joinpath(context.output_dir, string(context.tag, "_mode_resolved_spectra.png"))
    return _save_native_mode_plot(
        path,
        power;
        title = "Mode-resolved final field power",
    )
end

function _write_native_per_mode_summary(context::NativeArtifactContext,
                                        result::NativeAdjointResult)
    power = _native_mode_power_matrix(result.final_step.forward_state)
    power === nothing && return nothing
    path = joinpath(context.output_dir, string(context.tag, "_per_mode_summary.csv"))
    open(path, "w") do io
        println(io, "mode,total_power,peak_power")
        for mode_index in axes(power, 2)
            mode_power = power[:, mode_index]
            println(io, join((
                mode_index,
                sum(mode_power),
                maximum(mode_power),
            ), ","))
        end
    end
    return path
end

function _write_native_phase_profile(context::NativeArtifactContext,
                                     result::NativeAdjointResult)
    profile = _native_real_profile(_native_decoded_control_value(result, :phase))
    profile === nothing && return nothing
    path = joinpath(context.output_dir, string(context.tag, "_phase_profile.png"))
    return _save_native_line_plot(
        path,
        profile;
        title = "Decoded phase control",
        ylabel = "phase",
    )
end

function _write_native_group_delay(context::NativeArtifactContext,
                                   result::NativeAdjointResult)
    profile = _native_real_profile(_native_decoded_control_value(result, :phase))
    profile === nothing && return nothing
    length(profile) > 1 || return nothing
    group_delay = diff(profile)
    path = joinpath(context.output_dir, string(context.tag, "_group_delay.png"))
    return _save_native_line_plot(
        path,
        group_delay;
        title = "Decoded phase finite difference",
        ylabel = "delta phase",
    )
end

function _write_native_amplitude_profile(context::NativeArtifactContext,
                                         result::NativeAdjointResult)
    profile = _native_real_profile(_native_decoded_control_value(result, :amplitude))
    profile === nothing && return nothing
    path = joinpath(context.output_dir, string(context.tag, "_amplitude_profile.png"))
    return _save_native_line_plot(
        path,
        profile;
        title = "Decoded amplitude control",
        ylabel = "amplitude",
    )
end

function _write_native_scalar_summary(context::NativeArtifactContext,
                                      result::NativeAdjointResult,
                                      name::Symbol)
    value = _native_scalar_artifact_value(_native_decoded_control_value(result, name))
    value === nothing && return nothing
    path = joinpath(context.output_dir, string(context.tag, "_", name, ".txt"))
    write(path, string(name, " = ", value, "\n"))
    return path
end

function _native_scalar_artifact_value(value)
    if value isa Real
        scalar = Float64(value)
        isfinite(scalar) || return nothing
        return scalar
    end
    if value isa AbstractVector && length(value) == 1
        scalar = only(value)
        scalar isa Real || return nothing
        isfinite(Float64(scalar)) || return nothing
        return Float64(scalar)
    end
    return nothing
end

const _NATIVE_DEFAULT_ARTIFACT_WRITERS = Dict{Symbol,Function}(
    :field_summary => _write_native_field_summary,
    :mode_resolved_spectra => _write_native_mode_resolved_spectra,
    :mode_resolved_summary => _write_native_per_mode_summary,
    :per_mode_leakage_table => _write_native_per_mode_summary,
    :phase_profile => _write_native_phase_profile,
    :group_delay => _write_native_group_delay,
    :amplitude_profile => _write_native_amplitude_profile,
    :amplitude_mask => _write_native_amplitude_profile,
    :energy_scale => (context, result) -> _write_native_scalar_summary(context, result, :energy),
    :energy_throughput => (context, result) -> _write_native_scalar_summary(context, result, :energy),
)

const _NATIVE_BUILTIN_ARTIFACT_HOOKS = Set((:convergence_trace, :trust_report))

function _native_supported_artifact_hooks(backend::NativeAdjointBackend)
    return Set(vcat(
        collect(_NATIVE_BUILTIN_ARTIFACT_HOOKS),
        collect(keys(_NATIVE_DEFAULT_ARTIFACT_WRITERS)),
        collect(keys(backend.artifact_writers)),
    ))
end

function _preflight_backend(plan::ExperimentPlan, backend::NativeAdjointBackend)
    _validate_native_solver(plan, backend)
    control = _native_control(plan)
    objective = _native_objective(plan)
    _validate_native_sources(plan, backend, objective)
    expected_dimension = dimension(control)
    length(backend.initial_coordinates) == expected_dimension || throw(ArgumentError(
        "NativeAdjointBackend initial coordinate length $(length(backend.initial_coordinates)) does not match control dimension $(expected_dimension)"))
    _validate_native_bounds(backend.bounds, expected_dimension, backend.initial_coordinates)
    if backend.feasibility !== nothing && has_penalty(backend.feasibility) &&
            !has_physical_gradient(backend.feasibility)
        throw(FiberLabBackendError(
            plan,
            backend,
            "NativeAdjointBackend feasibility `$(backend.feasibility.name)` declares a penalty but no physical_gradient callback.",
        ))
    end
    backend.write_artifacts || return nothing
    requested_hooks = Set(plan.figure_hooks)
    extra_hooks = setdiff(Set(keys(backend.artifact_writers)), requested_hooks)
    isempty(extra_hooks) || throw(FiberLabBackendError(
        plan,
        backend,
        "NativeAdjointBackend artifact writers were provided for hooks not requested by the control/objective: $(collect(extra_hooks))",
    ))
    backend.strict_artifacts || return nothing
    missing_hooks = setdiff(requested_hooks, _native_supported_artifact_hooks(backend))
    isempty(missing_hooks) || throw(FiberLabBackendError(
        plan,
        backend,
        "NativeAdjointBackend strict artifact preflight failed. No artifact writer is available for requested hooks: $(collect(missing_hooks)). Provide artifact_writers for these hooks, remove the hooks, or set strict_artifacts=false.",
    ))
    return nothing
end

_preflight_in_execute(::NativeAdjointBackend) = true

function _write_native_hook_artifacts(plan::ExperimentPlan, result::NativeAdjointResult,
                                      output_dir::AbstractString, tag::AbstractString)
    paths = Dict{Symbol,String}()

    requested_hooks = Set(plan.figure_hooks)
    for hook in plan.figure_hooks
        writer = get(
            result.backend.artifact_writers,
            hook,
            get(_NATIVE_DEFAULT_ARTIFACT_WRITERS, hook, nothing),
        )
        writer === nothing && continue
        context = NativeArtifactContext(plan, String(output_dir), String(tag), hook)
        merge!(paths, _normalize_native_artifact_paths(hook, writer(context, result)))
    end

    extra_hooks = setdiff(Set(keys(result.backend.artifact_writers)), requested_hooks)
    isempty(extra_hooks) || throw(ArgumentError(
        "native artifact writers were provided for hooks not requested by the control/objective: $(collect(extra_hooks))"))
    return paths
end

function _write_native_artifacts(plan::ExperimentPlan, result::NativeAdjointResult)
    result.backend.write_artifacts || return (
        output_dir = nothing,
        sidecar_path = nothing,
        artifact_paths = Dict{Symbol,String}(),
    )
    _validate_native_sources(plan, result.backend, result.final_step.objective)

    output_dir = _native_output_dir(plan, result.backend)
    mkpath(output_dir)
    tag = isempty(plan.output_tag) ? plan.experiment.id : plan.output_tag
    sidecar_path = joinpath(output_dir, string(tag, "_native_result.json"))
    trace_path = joinpath(output_dir, string(tag, "_convergence_trace.json"))
    trust_path = joinpath(output_dir, string(tag, "_trust_report.json"))
    trace_payload = _native_convergence_payload(result.convergence_trace)
    result_metrics = metrics(result)
    artifact_paths = Dict(
        :native_result => sidecar_path,
        :convergence_trace => trace_path,
        :trust_report => trust_path,
    )
    merge!(artifact_paths, _write_native_hook_artifacts(plan, result, output_dir, tag))

    write_json_file(trace_path, trace_payload)
    write_json_file(trust_path, _native_json_value(result.trust_report))
    write_json_file(sidecar_path, Dict(
        "schema_version" => "native_adjoint_result_v1",
        "experiment_id" => plan.experiment.id,
        "model" => String(result.backend.model.name),
        "controls" => [String(variable) for variable in plan.variables],
        "control" => String(plan.variables[1]),
        "objective" => String(plan.objective),
        "objective_problem_sha256" => _objective_problem_sha256(result.final_step.objective),
        "resolved_problem_sha256" => result.backend.model.problem_source === nothing ?
            nothing : result.backend.model.problem_source.snapshot_sha256,
        "metadata_authority" => String(_native_metadata_authority(plan, result.backend)),
        "solver" => String(plan.solver),
        "experiment_summary" => _native_experiment_summary(
            plan.experiment,
            _native_metadata_authority(plan, result.backend),
        ),
        "source_metadata" => _native_json_value(
            result.backend.run_source === nothing ? nothing : result.backend.run_source.metadata),
        "x_initial" => result.x_initial,
        "x_final" => result.x_final,
        "decoded_final" => _native_json_value(decoded_final(result)),
        "metrics" => _native_json_value(result_metrics),
        "verification" => _native_json_value(
            _native_verification(result, artifact_paths; assume_native_result = true)),
        "trust_report" => _native_json_value(result.trust_report),
        "feasibility" => _native_json_value(result.feasibility_evaluation),
        "bounds" => _native_json_value(result.backend.bounds),
        "gradient_check" => _native_gradient_check_payload(result.gradient_check),
        "convergence_trace_file" => basename(trace_path),
        "artifact_files" => Dict(String(key) => basename(path)
                                 for (key, path) in artifact_paths),
    ))

    return (
        output_dir = output_dir,
        sidecar_path = sidecar_path,
        artifact_paths = artifact_paths,
    )
end

function execute(plan::ExperimentPlan, backend::NativeAdjointBackend)
    _preflight_backend(plan, backend)
    control = _native_control(plan)
    objective = _native_objective(plan)
    expected_dimension = dimension(control)
    gradient_check = _native_gradient_check(plan, backend, control, objective)

    function cost_function(x)
        return _native_cost(
            backend.model,
            control,
            objective,
            x,
            backend.context,
            backend.feasibility,
        )
    end

    function gradient_function!(storage, x)
        _, gradient, _ = _native_step_gradient(
            backend.model,
            control,
            objective,
            x,
            backend.context,
            expected_dimension,
            backend.feasibility,
        )
        storage .= gradient
        return storage
    end

    optim_result = _native_optimize(
        cost_function,
        gradient_function!,
        copy(backend.initial_coordinates),
        _optim_method(plan, backend),
        _optim_options(plan, backend),
        backend.bounds,
    )
    x_final = Vector{Float64}(Optim.minimizer(optim_result))
    final_step, _, final_entry = _native_step_gradient(
        backend.model,
        control,
        objective,
        x_final,
        backend.context,
        expected_dimension,
        backend.feasibility,
    )
    trace = _trace_from_optim(optim_result)
    isempty(trace) && push!(trace, final_entry)

    provisional_result = NativeAdjointResult(
        plan,
        backend,
        copy(backend.initial_coordinates),
        x_final,
        first(trace).cost,
        final_step.cost,
        trace,
        final_step,
        Optim.converged(optim_result),
        gradient_check,
        backend.feasibility === nothing ?
            nothing :
            evaluate_feasibility(
                backend.feasibility,
                _decoded_value(final_step.control_evaluation),
                final_step.forward_state;
                context = backend.context,
            ),
        nothing,
        nothing,
        Dict{Symbol,String}(),
        nothing,
    )
    trust_report = trust_check(
        backend.model,
        control,
        objective,
        x_final;
        context = backend.context,
        profile = backend.trust_profile,
        gradient_check = backend.trust_gradient_check,
    )
    if backend.require_trust && !trust_report.pass
        failed = [check.name for check in trust_report.checks
                  if check.pass === false && check.severity == :blocker]
        throw(FiberLabBackendError(
            plan,
            backend,
            "NativeAdjointBackend trust check failed for blocker checks: $(failed)",
        ))
    end
    result = NativeAdjointResult(
        provisional_result.plan,
        provisional_result.backend,
        provisional_result.x_initial,
        provisional_result.x_final,
        provisional_result.cost_initial,
        provisional_result.cost_final,
        provisional_result.convergence_trace,
        provisional_result.final_step,
        provisional_result.converged,
        provisional_result.gradient_check,
        provisional_result.feasibility_evaluation,
        provisional_result.output_dir,
        provisional_result.sidecar_path,
        provisional_result.artifact_paths,
        trust_report,
    )
    artifacts = _write_native_artifacts(plan, result)
    return NativeAdjointResult(
        result.plan,
        result.backend,
        result.x_initial,
        result.x_final,
        result.cost_initial,
        result.cost_final,
        result.convergence_trace,
        result.final_step,
        result.converged,
        result.gradient_check,
        result.feasibility_evaluation,
        artifacts.output_dir,
        artifacts.sidecar_path,
        artifacts.artifact_paths,
        result.trust_report,
    )
end

function _adjoint_source_error(model::AdjointModel,
                               objective::AbstractFiberObjective)
    source = model.problem_source
    if source !== nothing &&
            _resolved_problem_signature(source.problem) != source.snapshot_sha256
        return "resolved problem changed after its native model was constructed"
    end
    signature = _objective_problem_sha256(objective)
    if signature !== nothing &&
            (source === nothing || signature != source.snapshot_sha256)
        return "objective was constructed from a different resolved problem"
    end
    return nothing
end

function _validate_adjoint_sources(model::AdjointModel,
                                   objective::AbstractFiberObjective)
    message = _adjoint_source_error(model, objective)
    message === nothing || throw(ArgumentError(message))
    return nothing
end

function _validate_native_sources(plan::ExperimentPlan,
                                  backend::NativeAdjointBackend,
                                  objective::AbstractFiberObjective)
    message = _adjoint_source_error(backend.model, objective)
    message === nothing && (message = _native_plan_metadata_error(backend.model, plan.experiment))
    message === nothing || throw(
        FiberLabBackendError(plan, backend, message)
    )
    return nothing
end

function _validate_model_source_metadata(model::AdjointModel, fiber, pulse, grid)
    message = _model_source_metadata_error(model, fiber, pulse, grid)
    message === nothing || throw(ArgumentError(message))
    return nothing
end

function _model_source_metadata_error(model::AdjointModel, fiber, pulse, grid)
    source = model.run_source
    source === nothing && return nothing
    metadata = source.metadata
    fiber == metadata.requested_fiber || return "fiber metadata does not match the resolved model source"
    pulse == metadata.requested_pulse || return "pulse metadata does not match the resolved model source"
    grid == metadata.resolved_grid || return "grid metadata must equal the model's resolved grid"
    return nothing
end

function _resolved_model_grid(model::AdjointModel)
    source = model.problem_source
    source === nothing && return missing
    problem = source.problem
    hasproperty(problem, :sim) || return missing
    sim = problem.sim
    return Grid(
        nt = Int(sim["Nt"]),
        time_window_ps = Float64(sim["time_window"]),
        policy = :exact,
    )
end

function _asserted_model_metadata_error(model::AdjointModel, fiber, pulse, grid)
    if any(ismissing, (fiber, pulse, grid))
        return "user-asserted metadata must provide Fiber, Pulse, and Grid together"
    end
    model.problem_source === nothing && return nothing
    resolved_grid = _resolved_model_grid(model)
    if !ismissing(resolved_grid) && grid != resolved_grid
        return "user-asserted grid must equal the model's resolved numerical grid"
    end
    problem = model.problem_source.problem
    if hasproperty(problem, :fiber) && hasproperty(problem, :sim)
        expected_regime = Int(problem.sim["M"]) == 1 ? :single_mode : :multimode
        if fiber.regime != expected_regime
            return "user-asserted fiber regime does not match the numerical mode count"
        end
        if fiber.length_m != Float64(problem.fiber["L"])
            return "user-asserted fiber length does not match the numerical problem"
        end
        if fiber.beta_order != Int(problem.sim["β_order"])
            return "user-asserted fiber beta order does not match the numerical problem"
        end
    end
    return nothing
end

function _native_plan_metadata_error(model::AdjointModel, experiment)
    if model.run_source !== nothing
        return _model_source_metadata_error(
            model,
            experiment.fiber,
            experiment.pulse,
            experiment.grid,
        )
    end
    if model.problem_source === nothing
        experiment isa NativeExperiment || return nothing
        if experiment.metadata_authority != :user_asserted
            return "source-free custom models can only record user-asserted metadata"
        end
        return _asserted_model_metadata_error(
            model,
            experiment.fiber,
            experiment.pulse,
            experiment.grid,
        )
    end
    if !(experiment isa NativeExperiment)
        return "explicit numerical models must use the model-first solve path so metadata authority is recorded"
    end
    if experiment.metadata_authority == :resolved_numerical
        if !ismissing(experiment.fiber) || !ismissing(experiment.pulse)
            return "resolved-numerical metadata must not claim a Fiber or Pulse"
        end
        if experiment.grid != _resolved_model_grid(model)
            return "resolved-numerical grid does not match the model"
        end
        return nothing
    end
    if experiment.metadata_authority != :user_asserted
        return "unsupported native metadata authority `$(experiment.metadata_authority)`"
    end
    return _asserted_model_metadata_error(
        model,
        experiment.fiber,
        experiment.pulse,
        experiment.grid,
    )
end

function _native_metadata_authority(plan::ExperimentPlan, backend::NativeAdjointBackend)
    backend.model.run_source !== nothing && return :authoritative
    experiment = plan.experiment
    backend.model.problem_source !== nothing && experiment isa NativeExperiment &&
        return experiment.metadata_authority
    return :user_asserted
end

function _model_first_metadata(model::AdjointModel, fiber, pulse, grid)
    if model.run_source !== nothing
        source = model.run_source.metadata
        resolved = (
            fiber = fiber === nothing ? source.requested_fiber : fiber,
            pulse = pulse === nothing ? source.requested_pulse : pulse,
            grid = grid === nothing ? source.resolved_grid : grid,
            authority = :authoritative,
        )
        _validate_model_source_metadata(model, resolved.fiber, resolved.pulse, resolved.grid)
        return resolved
    end

    supplied = (fiber !== nothing, pulse !== nothing, grid !== nothing)
    if model.problem_source !== nothing && !any(supplied)
        return (
            fiber = missing,
            pulse = missing,
            grid = _resolved_model_grid(model),
            authority = :resolved_numerical,
        )
    end
    all(supplied) || throw(ArgumentError(
        "provide Fiber, Pulse, and Grid together for user-asserted metadata, or omit all three for an explicit numerical model"))
    if model.problem_source !== nothing
        message = _asserted_model_metadata_error(model, fiber, pulse, grid)
        message === nothing || throw(ArgumentError(message))
    end
    return (fiber = fiber, pulse = pulse, grid = grid, authority = :user_asserted)
end

figure_paths(result::NativeAdjointResult) = copy(result.artifact_paths)

decoded_final(result::NativeAdjointResult) = _decoded_value(result.final_step.control_evaluation)

function metrics(result::NativeAdjointResult)
    final_gradient_norm = isempty(result.convergence_trace) ?
        norm(gradient_vector(result.final_step)) :
        last(result.convergence_trace).gradient_norm
    return (
        cost_initial = result.cost_initial,
        cost_final = result.cost_final,
        delta_cost = result.cost_final - result.cost_initial,
        iterations = max(length(result.convergence_trace) - 1, 0),
        converged = result.converged,
        gradient_norm_final = final_gradient_norm,
        gradient_check_pass = result.gradient_check === nothing ? missing : result.gradient_check.pass,
        feasibility_penalty = result.feasibility_evaluation === nothing ?
            missing :
            result.feasibility_evaluation.penalty,
        trust_check_pass = result.trust_report === nothing ? missing : result.trust_report.pass,
    )
end

function _native_requested_artifact_hooks(result::NativeAdjointResult)
    result.backend.write_artifacts || return Symbol[]
    return Symbol[hook for hook in result.plan.figure_hooks]
end

function _native_artifact_file_complete(paths::Dict{Symbol,String};
                                        assume_native_result::Bool=false)
    isempty(paths) && return missing
    return all(pair -> begin
        hook, path = pair
        (assume_native_result && hook == :native_result) ||
            _native_artifact_file_passes_audit(path)
    end, paths)
end

function _native_artifact_file_passes_audit(path::AbstractString)
    isfile(path) || return false
    lowercase(splitext(path)[2]) == ".png" || return true
    return _native_png_passes_audit(path)
end

function _native_png_passes_audit(path::AbstractString)
    image = try
        PyPlot.imread(path)
    catch
        return false
    end
    ndims(image) >= 2 || return false
    size(image, 1) > 1 && size(image, 2) > 1 || return false
    pixels = if ndims(image) == 2
        Float64.(vec(image))
    else
        channel_count = min(size(image, 3), 3)
        channel_count > 0 || return false
        Float64.(vec(sum(image[:, :, 1:channel_count]; dims = 3))) ./ channel_count
    end
    isempty(pixels) && return false
    all(isfinite, pixels) || return false
    return maximum(pixels) > minimum(pixels)
end

function _native_verification(result::NativeAdjointResult,
                              artifact_paths::Dict{Symbol,String};
                              assume_native_result::Bool=false)
    gradient_check_pass = result.gradient_check === nothing ? missing : result.gradient_check.pass
    requested_hooks = _native_requested_artifact_hooks(result)
    written_hooks = Symbol[hook for hook in requested_hooks if haskey(artifact_paths, hook)]
    missing_hooks = setdiff(requested_hooks, written_hooks)
    artifact_files_exist = _native_artifact_file_complete(
        artifact_paths;
        assume_native_result = assume_native_result,
    )
    artifact_complete = artifact_files_exist === missing ?
        missing :
        artifact_files_exist && isempty(missing_hooks)
    return (
        artifact_complete = artifact_complete,
        artifact_files_exist = artifact_files_exist,
        requested_artifact_hooks = requested_hooks,
        written_artifact_hooks = written_hooks,
        missing_artifact_hooks = missing_hooks,
        export_complete = missing,
        converged = result.converged,
        gradient_check_pass = gradient_check_pass,
        cost_decreased = result.cost_final <= result.cost_initial,
        finite_final_cost = isfinite(result.cost_final),
        finite_final_coordinates = all(isfinite, result.x_final),
        trust_check_pass = result.trust_report === nothing ? missing : result.trust_report.pass,
    )
end

function verify(result::NativeAdjointResult)
    return _native_verification(result, result.artifact_paths)
end

"""
    solve(model, control, objective, initial_coordinates; fiber=nothing, pulse=nothing, grid=nothing, kwargs...)

Run a direct adjoint optimization without manually constructing an
`Experiment` or `NativeAdjointBackend`.

This is the shortest notebook path for researcher-owned models, controls, and
objectives. It still uses the same defensive preflight, gradient-validation
option, native Optim.jl execution, artifact writing, and result verification as
the explicit `Experiment(...); backend=NativeAdjointBackend(...)` path.
"""
function solve(model::AdjointModel,
               control::AbstractControlMap,
               objective::AbstractFiberObjective,
               initial_coordinates;
               fiber::Union{Nothing,Fiber}=nothing,
               id::AbstractString="native_adjoint_notebook",
               description::AbstractString=String(id),
               pulse::Union{Nothing,Pulse}=nothing,
               grid::Union{Nothing,Grid}=nothing,
               solver::Solver=Solver(),
               max_iter::Union{Nothing,Integer}=nothing,
               validate_gradient::Union{Nothing,Bool}=nothing,
               artifacts::ArtifactPolicy=ArtifactPolicy(),
               output_root::AbstractString=joinpath("results", "fiberlab"),
               output_tag::AbstractString=String(id),
               maturity::Symbol=:experimental,
               step_size::Real=1e-2,
               gradient_tolerance::Real=0.0,
               context=nothing,
               write_artifacts::Bool=false,
               strict_artifacts::Bool=true,
               output_dir::Union{Nothing,AbstractString}=nothing,
               artifact_writers=Dict{Symbol,Function}(),
               feasibility::Union{Nothing,FeasibilityMap}=nothing,
               bounds::Union{Nothing,CoordinateBounds}=nothing,
               trust_profile=nothing,
               require_trust::Bool=false,
               trust_gradient_check::Bool=false)
    metadata = _model_first_metadata(model, fiber, pulse, grid)
    native_solver = _native_solver_from_keywords(solver, max_iter, validate_gradient)
    experiment = NativeExperiment(;
        id = id,
        description = description,
        fiber = metadata.fiber,
        pulse = metadata.pulse,
        grid = metadata.grid,
        control = control,
        objective = objective,
        solver = native_solver,
        artifacts = artifacts,
        output_root = output_root,
        output_tag = output_tag,
        maturity = maturity,
        metadata_authority = metadata.authority,
    )
    backend = NativeAdjointBackend(
        model;
        initial_coordinates = initial_coordinates,
        step_size = step_size,
        max_iter = max_iter,
        gradient_tolerance = gradient_tolerance,
        context = context,
        write_artifacts = write_artifacts,
        strict_artifacts = strict_artifacts,
        output_dir = output_dir,
        artifact_writers = artifact_writers,
        feasibility = feasibility,
        bounds = bounds,
        trust_profile = trust_profile,
        require_trust = require_trust,
        trust_gradient_check = trust_gradient_check,
    )
    return solve(experiment; backend = backend)
end
