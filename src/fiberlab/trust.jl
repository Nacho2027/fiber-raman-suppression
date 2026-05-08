"""
Physics credibility checks for FiberLab adjoint exploration runs.

These checks do not prove experimental truth. They make numerical and
lab-realizability failures explicit before a researcher treats an optimization
result as evidence.
"""

struct TrustCheck
    name::Symbol
    pass::Union{Bool,Missing}
    severity::Symbol
    message::String
    value
end

struct TrustReport
    pass::Bool
    checks::Tuple{Vararg{TrustCheck}}
end

struct LabProfile
    phase_range::Tuple{Float64,Float64}
    phase_levels::Union{Nothing,Int}
    max_phase_step::Union{Nothing,Float64}
    amplitude_range::Tuple{Float64,Float64}
    max_amplitude_step::Union{Nothing,Float64}
    coordinate_range::Union{Nothing,Tuple{Float64,Float64}}
    max_projected_cost_increase::Union{Nothing,Float64}
    projected_cost_atol::Float64

    function LabProfile(; phase_range=(0.0, 2π),
                        phase_levels::Union{Nothing,Integer}=nothing,
                        max_phase_step::Union{Nothing,Real}=nothing,
                        amplitude_range=(0.0, Inf),
                        max_amplitude_step::Union{Nothing,Real}=nothing,
                        coordinate_range::Union{Nothing,Tuple{<:Real,<:Real}}=nothing,
                        max_projected_cost_increase::Union{Nothing,Real}=nothing,
                        projected_cost_atol::Real=1e-12)
        phase_min, phase_max = Float64.(phase_range)
        phase_max > phase_min || throw(ArgumentError("LabProfile phase_range must be increasing"))
        phase_levels !== nothing && Int(phase_levels) > 1 || phase_levels === nothing ||
            throw(ArgumentError("LabProfile phase_levels must be greater than 1"))
        phase_step = max_phase_step === nothing ? nothing : Float64(max_phase_step)
        phase_step === nothing || (isfinite(phase_step) && phase_step > 0) ||
            throw(ArgumentError("LabProfile max_phase_step must be positive and finite"))

        amplitude_min, amplitude_max = Float64.(amplitude_range)
        amplitude_min >= 0 || throw(ArgumentError("LabProfile amplitude lower bound must be non-negative"))
        amplitude_max > amplitude_min || throw(ArgumentError("LabProfile amplitude_range must be increasing"))
        amplitude_step = max_amplitude_step === nothing ? nothing : Float64(max_amplitude_step)
        amplitude_step === nothing || (isfinite(amplitude_step) && amplitude_step > 0) ||
            throw(ArgumentError("LabProfile max_amplitude_step must be positive and finite"))

        coordinates = if coordinate_range === nothing
            nothing
        else
            low, high = Float64.(coordinate_range)
            high > low || throw(ArgumentError("LabProfile coordinate_range must be increasing"))
            (low, high)
        end
        projected_increase = max_projected_cost_increase === nothing ?
            nothing :
            Float64(max_projected_cost_increase)
        projected_increase === nothing ||
            (isfinite(projected_increase) && projected_increase >= 0) ||
            throw(ArgumentError("LabProfile max_projected_cost_increase must be non-negative and finite"))
        projected_atol = Float64(projected_cost_atol)
        isfinite(projected_atol) && projected_atol >= 0 ||
            throw(ArgumentError("LabProfile projected_cost_atol must be non-negative and finite"))
        return new(
            (phase_min, phase_max),
            phase_levels === nothing ? nothing : Int(phase_levels),
            phase_step,
            (amplitude_min, amplitude_max),
            amplitude_step,
            coordinates,
            projected_increase,
            projected_atol,
        )
    end
end

function _trust_check(name::Symbol, pass::Union{Bool,Missing}, severity::Symbol,
                      message::AbstractString, value=nothing)
    severity in (:blocker, :warning, :info) || throw(ArgumentError(
        "trust check severity must be :blocker, :warning, or :info"))
    return TrustCheck(name, pass, severity, String(message), value)
end

function _trust_report(checks::Vector{TrustCheck})
    pass = all(check -> check.severity != :blocker || check.pass !== false, checks)
    return TrustReport(pass, Tuple(checks))
end

function _trust_finite(value)
    value === nothing && return true
    value isa Missing && return false
    value isa Real && return isfinite(Float64(value))
    value isa Complex && return isfinite(real(value)) && isfinite(imag(value))
    if value isa AbstractArray
        return all(_trust_finite, value)
    end
    if value isa NamedTuple
        return all(name -> _trust_finite(getproperty(value, name)), propertynames(value))
    end
    if value isa AbstractDict
        return all(_trust_finite, values(value))
    end
    return true
end

function _trust_real_vector(value)
    value isa AbstractVector || return nothing
    vector = try
        Float64.(collect(value))
    catch
        return nothing
    end
    all(isfinite, vector) || return nothing
    return vector
end

function _trust_named_value(decoded, name::Symbol)
    if decoded isa NamedTuple && hasproperty(decoded, name)
        return getproperty(decoded, name)
    end
    if decoded isa AbstractDict
        haskey(decoded, name) && return decoded[name]
        haskey(decoded, String(name)) && return decoded[String(name)]
    end
    return nothing
end

function _trust_control_value(evaluation::ControlEvaluation, name::Symbol)
    hasproperty(evaluation.control, :name) && getproperty(evaluation.control, :name) == name &&
        return evaluation.decoded
    return _trust_named_value(evaluation.decoded, name)
end

function _trust_control_value(evaluations::NamedTuple, name::Symbol)
    if hasproperty(evaluations, name)
        return getproperty(evaluations, name).decoded
    end
    for block_name in propertynames(evaluations)
        value = _trust_control_value(getproperty(evaluations, block_name), name)
        value !== nothing && return value
    end
    return nothing
end

_trust_coordinates(evaluation::ControlEvaluation) = evaluation.coordinates

function _trust_coordinates(evaluations::NamedTuple)
    chunks = Vector{Float64}[]
    for name in propertynames(evaluations)
        push!(chunks, Float64.(_trust_coordinates(getproperty(evaluations, name))))
    end
    isempty(chunks) && return Float64[]
    return vcat(chunks...)
end

function _trust_phase_checks!(checks::Vector{TrustCheck}, phase, profile::LabProfile)
    vector = _trust_real_vector(phase)
    if vector === nothing
        push!(checks, _trust_check(
            :lab_phase_profile,
            missing,
            :info,
            "No vector phase control was available for lab-profile checks.",
        ))
        return checks
    end
    period = profile.phase_range[2] - profile.phase_range[1]
    wrapped = mod.(vector .- profile.phase_range[1], period) .+ profile.phase_range[1]
    in_range = all(value -> profile.phase_range[1] <= value <= profile.phase_range[2], wrapped)
    push!(checks, _trust_check(
        :lab_phase_range,
        in_range,
        :blocker,
        "Decoded phase is finite and wrappable into the declared lab phase range.",
        (min = minimum(wrapped), max = maximum(wrapped)),
    ))

    if profile.phase_levels !== nothing
        level_step = period / (profile.phase_levels - 1)
        quantized = round.((wrapped .- profile.phase_range[1]) ./ level_step) .* level_step .+
            profile.phase_range[1]
        error = maximum(abs.(wrapped .- quantized))
        push!(checks, _trust_check(
            :lab_phase_quantization,
            isfinite(error),
            :warning,
            "Decoded phase can be projected to the declared phase quantization levels.",
            (levels = profile.phase_levels, max_error = error),
        ))
    end

    if profile.max_phase_step !== nothing && length(vector) > 1
        local_step = abs.(angle.(exp.(im .* diff(vector))))
        max_step = maximum(local_step)
        push!(checks, _trust_check(
            :lab_phase_step,
            max_step <= profile.max_phase_step,
            :blocker,
            "Decoded phase does not exceed the declared per-sample phase-step limit.",
            (max_step = max_step, limit = profile.max_phase_step),
        ))
    end
    return checks
end

function _trust_amplitude_checks!(checks::Vector{TrustCheck}, amplitude, profile::LabProfile)
    vector = _trust_real_vector(amplitude)
    if vector === nothing
        push!(checks, _trust_check(
            :lab_amplitude_profile,
            missing,
            :info,
            "No vector amplitude control was available for lab-profile checks.",
        ))
        return checks
    end
    in_range = all(value -> profile.amplitude_range[1] <= value <= profile.amplitude_range[2], vector)
    push!(checks, _trust_check(
        :lab_amplitude_range,
        in_range,
        :blocker,
        "Decoded amplitude stays within the declared lab amplitude range.",
        (min = minimum(vector), max = maximum(vector)),
    ))
    if profile.max_amplitude_step !== nothing && length(vector) > 1
        max_step = maximum(abs.(diff(vector)))
        push!(checks, _trust_check(
            :lab_amplitude_step,
            max_step <= profile.max_amplitude_step,
            :blocker,
            "Decoded amplitude does not exceed the declared per-sample amplitude-step limit.",
            (max_step = max_step, limit = profile.max_amplitude_step),
        ))
    end
    return checks
end

function _trust_project_phase(phase, profile::LabProfile)
    vector = _trust_real_vector(phase)
    vector === nothing && return phase, false
    period = profile.phase_range[2] - profile.phase_range[1]
    projected = mod.(vector .- profile.phase_range[1], period) .+ profile.phase_range[1]
    if profile.phase_levels !== nothing
        level_step = period / (profile.phase_levels - 1)
        projected = round.((projected .- profile.phase_range[1]) ./ level_step) .* level_step .+
            profile.phase_range[1]
    end
    return projected, maximum(abs.(projected .- vector)) > 0
end

function _trust_project_amplitude(amplitude, profile::LabProfile)
    vector = _trust_real_vector(amplitude)
    vector === nothing && return amplitude, false
    projected = clamp.(vector, profile.amplitude_range[1], profile.amplitude_range[2])
    return projected, maximum(abs.(projected .- vector)) > 0
end

function _trust_project_decoded(decoded, profile::LabProfile)
    changed = false
    if decoded isa NamedTuple
        pairs = Pair{Symbol,Any}[]
        for name in propertynames(decoded)
            value = getproperty(decoded, name)
            projected, local_changed = if name == :phase
                _trust_project_phase(value, profile)
            elseif name == :amplitude
                _trust_project_amplitude(value, profile)
            else
                value, false
            end
            changed |= local_changed
            push!(pairs, name => projected)
        end
        return (; pairs...), changed
    end
    if decoded isa AbstractDict
        projected = copy(decoded)
        for name in (:phase, :amplitude)
            if haskey(projected, name) || haskey(projected, String(name))
                key = haskey(projected, name) ? name : String(name)
                value = projected[key]
                projected_value, local_changed = name == :phase ?
                    _trust_project_phase(value, profile) :
                    _trust_project_amplitude(value, profile)
                projected[key] = projected_value
                changed |= local_changed
            end
        end
        return projected, changed
    end
    return decoded, false
end

function _trust_project_evaluation(evaluation::ControlEvaluation, profile::LabProfile)
    control_name = hasproperty(evaluation.control, :name) ? getproperty(evaluation.control, :name) : Symbol("")
    if control_name == :phase
        return _trust_project_phase(evaluation.decoded, profile)
    elseif control_name == :amplitude
        return _trust_project_amplitude(evaluation.decoded, profile)
    end
    return _trust_project_decoded(evaluation.decoded, profile)
end

function _trust_project_evaluation(evaluations::NamedTuple, profile::LabProfile)
    pairs = Pair{Symbol,Any}[]
    changed = false
    for name in propertynames(evaluations)
        projected, local_changed = _trust_project_evaluation(getproperty(evaluations, name), profile)
        push!(pairs, name => projected)
        changed |= local_changed
    end
    return (; pairs...), changed
end

function _trust_projected_cost_check!(checks::Vector{TrustCheck}, model::AdjointModel,
                                      objective::AbstractFiberObjective,
                                      step::AdjointStepResult,
                                      profile)
    profile === nothing && return checks
    profile isa LabProfile || throw(ArgumentError("trust profile must be a LabProfile"))
    projected_decoded, changed = _trust_project_evaluation(step.control_evaluation, profile)
    if !changed
        push!(checks, _trust_check(
            :lab_projected_cost,
            missing,
            :info,
            "Lab projection did not alter the decoded control.",
        ))
        return checks
    end
    projected_state = _run_model_forward(model, projected_decoded, step.control_evaluation.user_context)
    projected_cost = _objective_cost(objective, projected_state)
    increase = projected_cost - step.cost
    tolerance = if profile.max_projected_cost_increase === nothing
        nothing
    else
        profile.projected_cost_atol +
            profile.max_projected_cost_increase * max(abs(step.cost), profile.projected_cost_atol)
    end
    pass = tolerance === nothing ? missing : increase <= tolerance
    severity = tolerance === nothing ? :warning : :blocker
    push!(checks, _trust_check(
        :lab_projected_cost,
        pass,
        severity,
        "Objective cost after lab projection stays within the declared tolerance.",
        (
            original_cost = step.cost,
            projected_cost = projected_cost,
            increase = increase,
            tolerance = tolerance,
        ),
    ))
    return checks
end

function _trust_lab_checks!(checks::Vector{TrustCheck}, evaluation, coordinates, profile)
    profile === nothing && return checks
    profile isa LabProfile || throw(ArgumentError("trust profile must be a LabProfile"))
    if profile.coordinate_range !== nothing
        low, high = profile.coordinate_range
        in_range = all(value -> low <= value <= high, coordinates)
        push!(checks, _trust_check(
            :lab_coordinate_range,
            in_range,
            :blocker,
            "Optimizer coordinates stay within the declared lab coordinate range.",
            (min = minimum(coordinates), max = maximum(coordinates)),
        ))
    end
    _trust_phase_checks!(checks, _trust_control_value(evaluation, :phase), profile)
    _trust_amplitude_checks!(checks, _trust_control_value(evaluation, :amplitude), profile)
    return checks
end

function _trust_gradient_check!(checks::Vector{TrustCheck}, model, control, objective,
                                coordinates; context, gradient_check, kwargs...)
    gradient_check || return checks
    result = check_adjoint_gradient(
        model,
        control,
        objective,
        coordinates;
        context = context,
        kwargs...,
    )
    push!(checks, _trust_check(
        :adjoint_gradient_check,
        result.pass,
        :blocker,
        "Adjoint gradient agrees with centered finite differences at sampled coordinates.",
        (
            coordinates = result.coordinates,
            max_absolute_error = maximum(result.absolute_error),
            max_relative_error = maximum(result.relative_error),
        ),
    ))
    return checks
end

"""
    trust_check(model, control, objective, coordinates; profile=nothing, gradient_check=false, kwargs...)

Run credibility checks at one optimizer point. Cheap finite-value and adjoint
contract checks always run. `profile=LabProfile(...)` adds lab-realizability
checks for decoded phase/amplitude controls. `gradient_check=true` adds a
finite-difference adjoint check.
"""
function trust_check(model::AdjointModel,
                     control::AbstractControlMap,
                     objective::AbstractFiberObjective,
                     coordinates;
                     context=nothing,
                     profile=nothing,
                     gradient_check::Bool=false,
                     gradient_check_kwargs...)
    checks = TrustCheck[]
    n = dimension(control)
    x = _finite_real_vector(coordinates, n, "trust-check coordinate")
    push!(checks, _trust_check(
        :finite_coordinates,
        all(isfinite, x),
        :blocker,
        "Optimizer coordinates are finite.",
        (dimension = n,),
    ))

    ready = try
        assert_adjoint_ready(objective, control, :lbfgs)
        true
    catch
        false
    end
    push!(checks, _trust_check(
        :adjoint_contract,
        ready,
        :blocker,
        "Objective terminal adjoint and control pullback are declared.",
    ))
    ready || return _trust_report(checks)

    step = run_adjoint_step(model, control, objective, x; context=context)
    push!(checks, _trust_check(
        :finite_decoded_control,
        _trust_finite(_decoded_value(step.control_evaluation)),
        :blocker,
        "Decoded physical control contains only finite values.",
    ))
    push!(checks, _trust_check(
        :finite_forward_state,
        _trust_finite(step.forward_state),
        :blocker,
        "Forward model state contains only finite values.",
    ))
    push!(checks, _trust_check(
        :finite_cost,
        isfinite(step.cost),
        :blocker,
        "Objective cost is finite.",
        step.cost,
    ))
    push!(checks, _trust_check(
        :finite_terminal_adjoint,
        _trust_finite(step.terminal_adjoint),
        :blocker,
        "Terminal adjoint seed contains only finite values.",
    ))
    push!(checks, _trust_check(
        :finite_physical_gradient,
        _trust_finite(step.physical_gradient),
        :blocker,
        "Physical adjoint gradient contains only finite values.",
    ))
    push!(checks, _trust_check(
        :finite_optimizer_gradient,
        _trust_finite(gradient_vector(step)),
        :blocker,
        "Optimizer-space gradient contains only finite values.",
        (norm = norm(gradient_vector(step)),),
    ))

    _trust_lab_checks!(checks, step.control_evaluation, x, profile)
    _trust_projected_cost_check!(checks, model, objective, step, profile)
    _trust_gradient_check!(
        checks,
        model,
        control,
        objective,
        x;
        context = context,
        gradient_check = gradient_check,
        gradient_check_kwargs...,
    )
    return _trust_report(checks)
end

function trust_check(step::AdjointStepResult; profile=nothing)
    checks = TrustCheck[
        _trust_check(:finite_decoded_control, _trust_finite(_decoded_value(step.control_evaluation)),
                     :blocker, "Decoded physical control contains only finite values."),
        _trust_check(:finite_forward_state, _trust_finite(step.forward_state),
                     :blocker, "Forward model state contains only finite values."),
        _trust_check(:finite_cost, isfinite(step.cost),
                     :blocker, "Objective cost is finite.", step.cost),
        _trust_check(:finite_terminal_adjoint, _trust_finite(step.terminal_adjoint),
                     :blocker, "Terminal adjoint seed contains only finite values."),
        _trust_check(:finite_physical_gradient, _trust_finite(step.physical_gradient),
                     :blocker, "Physical adjoint gradient contains only finite values."),
        _trust_check(:finite_optimizer_gradient, _trust_finite(gradient_vector(step)),
                     :blocker, "Optimizer-space gradient contains only finite values.",
                     (norm = norm(gradient_vector(step)),)),
    ]
    _trust_lab_checks!(checks, step.control_evaluation, _trust_coordinates(step.control_evaluation), profile)
    return _trust_report(checks)
end

trust_check(result::NativeAdjointResult; profile=nothing) =
    trust_check(result.final_step; profile=profile)
