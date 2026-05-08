struct FiberFieldProblem
    uω0::Matrix{ComplexF64}
    fiber::Dict{String,Any}
    sim::Dict{String,Any}
    band_mask::Union{Nothing,Vector{Bool}}
    frequency_offset_thz::Vector{Float64}
    raman_threshold_thz::Union{Nothing,Float64}
    preset::Symbol
    reference_power_w::Union{Nothing,Float64}
end

const SingleModeFiberProblem = FiberFieldProblem
const FiberProblem = FiberFieldProblem

"""
    sample_count(problem)

Number of frequency/time samples in a FiberLab propagation problem.
"""
sample_count(problem::FiberFieldProblem) = Int(problem.sim["Nt"])

"""
    mode_count(problem)

Number of propagated fields or modes in a FiberLab propagation problem.
"""
mode_count(problem::FiberFieldProblem) = Int(problem.sim["M"])

"""
    frequency_offsets(problem)

Frequency offsets in THz, ordered for plotting.
"""
frequency_offsets(problem::FiberFieldProblem) = copy(problem.frequency_offset_thz)

function summarize(problem::FiberFieldProblem)
    band_bins = problem.band_mask === nothing ? nothing : count(problem.band_mask)
    return (
        preset = problem.preset,
        samples = sample_count(problem),
        modes = mode_count(problem),
        length_m = Float64(problem.fiber["L"]),
        reference_power_w = problem.reference_power_w,
        raman_threshold_thz = problem.raman_threshold_thz,
        band_bins = band_bins,
    )
end

"""
    FullGridPhase(problem; kwargs...)

Construct a shared full-grid spectral phase control with one optimizer
coordinate per frequency sample in `problem`.
"""
FullGridPhase(problem::FiberFieldProblem; kwargs...) =
    FullGridPhase(sample_count(problem); kwargs...)

mutable struct SingleModePhaseCache
    signature
    shaped_input::Union{Nothing,Matrix{ComplexF64}}
    ode_solution
    final_field::Union{Nothing,Matrix{ComplexF64}}
    physical_fields
end

SingleModePhaseCache() = SingleModePhaseCache(nothing, nothing, nothing, nothing, nothing)

mutable struct SingleModePhasePhysics
    problem::FiberFieldProblem
    cache::SingleModePhaseCache
end

"""
    single_mode_fiber_problem(fiber; pulse=Pulse(), grid=Grid(), wavelength_m=1550e-9, raman_threshold_thz=-5.0)

Build the low-level single-mode propagation problem used by package-native
physics adapters. This function performs setup only; it does not run a forward
or adjoint solve.
"""
function _single_mode_low_level_setup(fiber_spec::Fiber, pulse::Pulse, grid::Grid,
                                      wavelength_m::Real)
    fiber_spec.regime == :single_mode || throw(ArgumentError(
        "single_mode_fiber_problem requires fiber.regime = :single_mode"))
    preset = _single_mode_preset(fiber_spec.preset)
    nt, time_window_ps = _resolved_grid(grid, fiber_spec, pulse, preset)
    sim = get_disp_sim_params(
        Float64(wavelength_m),
        1,
        nt,
        time_window_ps,
        fiber_spec.beta_order,
    )
    fiber = get_disp_fiber_params_user_defined(
        fiber_spec.length_m,
        sim;
        fR = preset.fR,
        gamma_user = preset.gamma,
        betas_user = preset.betas,
    )
    pulse_shape = _pulse_shape_string(pulse.shape)
    _, uω0 = get_initial_state(
        ones(1),
        fiber_spec.power_w,
        pulse.fwhm_s,
        pulse.rep_rate_hz,
        pulse_shape,
        sim,
    )
    return Matrix{ComplexF64}(uω0), Dict{String,Any}(fiber), Dict{String,Any}(sim)
end

function single_mode_fiber_problem(fiber_spec::Fiber;
                                   pulse::Pulse=Pulse(),
                                   grid::Grid=Grid(),
                                   wavelength_m::Real=1550e-9,
                                   raman_threshold_thz::Real=-5.0)
    uω0, fiber, sim = _single_mode_low_level_setup(
        fiber_spec,
        pulse,
        grid,
        wavelength_m,
    )
    nt = Int(sim["Nt"])
    frequency_offset_fft = FFTW.fftfreq(nt, 1 / sim["Δt"])
    band_mask = frequency_offset_fft .< Float64(raman_threshold_thz)
    any(band_mask) || throw(ArgumentError(
        "raman_threshold_thz selects no frequency bins"))
    return SingleModeFiberProblem(
        uω0,
        fiber,
        sim,
        Vector{Bool}(band_mask),
        fftshift(frequency_offset_fft),
        Float64(raman_threshold_thz),
        fiber_spec.preset,
        fiber_spec.power_w,
    )
end

single_mode_fiber_problem(experiment::Experiment; kwargs...) =
    single_mode_fiber_problem(
        experiment.fiber;
        pulse = experiment.pulse,
        grid = experiment.grid,
        kwargs...,
    )

function _single_mode_grid_fiber(fiber_spec::Fiber)
    haskey(SINGLE_MODE_FIBER_PRESETS, fiber_spec.preset) && return fiber_spec
    return Fiber(;
        regime = :single_mode,
        preset = :SMF28,
        length_m = fiber_spec.length_m,
        power_w = fiber_spec.power_w,
        beta_order = fiber_spec.beta_order,
    )
end

function _validated_multimode_launch(initial_modes, mode_count::Int)
    initial_modes !== nothing || throw(ArgumentError(
        "fiber_problem with multimode package-built setup requires explicit initial_modes"))
    launch = ComplexF64.(collect(initial_modes))
    length(launch) == mode_count || throw(ArgumentError(
        "initial_modes length $(length(launch)) does not match modes=$mode_count"))
    norm(launch) > 0 || throw(ArgumentError("initial_modes must have nonzero norm"))
    return launch ./ norm(launch)
end

function _validated_multimode_dispersion(dispersion, nt::Int, mode_count::Int)
    dispersion !== nothing || throw(ArgumentError(
        "fiber_problem with multimode package-built setup requires explicit dispersion; pass an Nt×modes matrix matching the grid"))
    matrix = Matrix{Float64}(dispersion)
    size(matrix) == (nt, mode_count) || throw(ArgumentError(
        "dispersion size $(size(matrix)) does not match ($nt, $mode_count)"))
    return matrix
end

function _validated_multimode_gamma(gamma_tensor, mode_count::Int)
    gamma_tensor !== nothing || throw(ArgumentError(
        "fiber_problem with multimode package-built setup requires explicit gamma_tensor with size (modes,modes,modes,modes)"))
    gamma = Array{Float64,4}(gamma_tensor)
    size(gamma) == (mode_count, mode_count, mode_count, mode_count) || throw(ArgumentError(
        "gamma_tensor size $(size(gamma)) does not match ($mode_count, $mode_count, $mode_count, $mode_count)"))
    return gamma
end

"""
    fiber_problem(fiber; modes=1, pulse=Pulse(), grid=Grid(), kwargs...)
    fiber_problem(uω0, fiber, sim; kwargs...)

Build a direct FiberLab propagation problem.

For `modes == 1`, FiberLab can construct the package-native setup from a
`Fiber`, `Pulse`, and `Grid`. For `modes > 1`, callers must provide explicit
multimode physics (`dispersion`, `gamma_tensor`, and optionally
`initial_modes`) or pass the low-level `(uω0, fiber, sim)` objects directly.
This keeps multimode support real rather than silently inventing fiber physics.
"""
function fiber_problem(fiber_spec::Fiber;
                       modes::Integer=1,
                       pulse::Pulse=Pulse(),
                       grid::Grid=Grid(),
                       wavelength_m::Real=1550e-9,
                       raman_threshold_thz=-5.0,
                       band_mask=nothing,
                       initial_modes=nothing,
                       dispersion=nothing,
                       gamma_tensor=nothing,
                       preset::Symbol=fiber_spec.preset)
    mode_count = Int(modes)
    mode_count > 0 || throw(ArgumentError("fiber_problem modes must be positive"))
    if mode_count == 1 && dispersion === nothing && gamma_tensor === nothing &&
            initial_modes === nothing
        uω0, fiber, sim = _single_mode_low_level_setup(
            fiber_spec,
            pulse,
            grid,
            wavelength_m,
        )
        return fiber_field_problem(
            uω0,
            fiber,
            sim;
            band_mask = band_mask,
            raman_threshold_thz = band_mask === nothing ? raman_threshold_thz : nothing,
            preset = preset,
            reference_power_w = fiber_spec.power_w,
        )
    end

    grid_fiber = _single_mode_grid_fiber(fiber_spec)
    base_preset = _single_mode_preset(grid_fiber.preset)
    nt, time_window_ps = _resolved_grid(grid, grid_fiber, pulse, base_preset)
    sim = get_disp_sim_params(
        Float64(wavelength_m),
        mode_count,
        nt,
        time_window_ps,
        fiber_spec.beta_order,
    )
    dispersion_matrix = _validated_multimode_dispersion(dispersion, nt, mode_count)
    gamma = _validated_multimode_gamma(gamma_tensor, mode_count)
    launch = _validated_multimode_launch(initial_modes, mode_count)
    _, uω0 = get_initial_state(
        launch,
        fiber_spec.power_w,
        pulse.fwhm_s,
        pulse.rep_rate_hz,
        _pulse_shape_string(pulse.shape),
        sim,
    )
    raman_fiber = get_disp_fiber_params_user_defined(
        fiber_spec.length_m,
        sim;
        gamma_user = maximum(abs, gamma),
        betas_user = [0.0],
    )
    fiber = Dict{String,Any}(
        "ϕ" => nothing,
        "Dω" => dispersion_matrix,
        "γ" => gamma,
        "L" => fiber_spec.length_m,
        "hRω" => raman_fiber["hRω"],
        "one_m_fR" => raman_fiber["one_m_fR"],
        "zsave" => nothing,
        "x" => nothing,
        "gain_parameters" => 0.0,
    )
    return fiber_field_problem(
        Matrix{ComplexF64}(uω0),
        fiber,
        sim;
        band_mask = band_mask,
        raman_threshold_thz = band_mask === nothing ? raman_threshold_thz : nothing,
        preset = preset,
        reference_power_w = fiber_spec.power_w,
    )
end

fiber_problem(experiment::Experiment; kwargs...) =
    fiber_problem(
        experiment.fiber;
        pulse = experiment.pulse,
        grid = experiment.grid,
        kwargs...,
    )

fiber_problem(uω0, fiber, sim; kwargs...) =
    fiber_field_problem(uω0, fiber, sim; kwargs...)

"""
    fiber_field_problem(uω0, fiber, sim; band_mask=nothing, raman_threshold_thz=nothing, preset=:custom)

Wrap an explicit low-level propagation setup as a FiberLab adjoint problem. This
is the escape hatch for researcher-supplied multimode physics: callers provide
the actual initial field, fiber dictionary, and simulation dictionary used by
`solve_disp_mmf` and `solve_adjoint_disp_mmf`. Band-based built-in objectives
need either an explicit `band_mask` or a `raman_threshold_thz`; custom
objectives that do not use a band can omit both.
"""
function fiber_field_problem(uω0, fiber, sim;
                             band_mask=nothing,
                             raman_threshold_thz=nothing,
                             preset::Symbol=:custom,
                             reference_power_w=nothing)
    nt = Int(sim["Nt"])
    m = Int(sim["M"])
    size(uω0) == (nt, m) || throw(ArgumentError(
        "uω0 size $(size(uω0)) does not match simulation size ($nt, $m)"))
    size(fiber["Dω"]) == (nt, m) || throw(ArgumentError(
        "fiber Dω size $(size(fiber["Dω"])) does not match ($nt, $m)"))
    size(fiber["γ"]) == (m, m, m, m) || throw(ArgumentError(
        "fiber γ size $(size(fiber["γ"])) does not match ($m, $m, $m, $m)"))
    haskey(fiber, "L") || throw(ArgumentError("fiber dictionary must contain \"L\""))
    haskey(fiber, "hRω") || throw(ArgumentError("fiber dictionary must contain \"hRω\""))
    haskey(fiber, "one_m_fR") || throw(ArgumentError(
        "fiber dictionary must contain \"one_m_fR\""))
    haskey(fiber, "zsave") || throw(ArgumentError("fiber dictionary must contain \"zsave\""))

    frequency_offset_fft = FFTW.fftfreq(nt, 1 / sim["Δt"])
    resolved_band_mask = if band_mask !== nothing
        mask = Vector{Bool}(collect(band_mask))
        length(mask) == nt || throw(ArgumentError(
            "band_mask length $(length(mask)) does not match Nt=$nt"))
        any(mask) || throw(ArgumentError("band_mask must select at least one frequency bin"))
        mask
    elseif raman_threshold_thz !== nothing
        mask = frequency_offset_fft .< Float64(raman_threshold_thz)
        any(mask) || throw(ArgumentError(
            "raman_threshold_thz selects no frequency bins"))
        Vector{Bool}(mask)
    else
        nothing
    end
    return SingleModeFiberProblem(
        Matrix{ComplexF64}(uω0),
        Dict{String,Any}(fiber),
        Dict{String,Any}(sim),
        resolved_band_mask,
        fftshift(frequency_offset_fft),
        raman_threshold_thz === nothing ? nothing : Float64(raman_threshold_thz),
        preset,
        reference_power_w === nothing ? nothing : Float64(reference_power_w),
    )
end

function _problem_band_mask(problem::FiberFieldProblem, objective_name::Symbol)
    problem.band_mask !== nothing && return problem.band_mask
    throw(ArgumentError(
        "objective `$(objective_name)` requires a band_mask; pass band_mask or raman_threshold_thz to fiber_field_problem"))
end

function _phase_matrix(decoded_phase, problem::FiberFieldProblem)
    nt = problem.sim["Nt"]
    m = problem.sim["M"]
    if decoded_phase isa AbstractVector
        length(decoded_phase) == nt || throw(ArgumentError(
            "phase vector length $(length(decoded_phase)) does not match Nt=$nt"))
        column = reshape(Float64.(collect(decoded_phase)), nt, 1)
        return repeat(column, 1, m), :vector
    end
    if decoded_phase isa AbstractMatrix
        size(decoded_phase) == (nt, m) || throw(ArgumentError(
            "phase matrix size $(size(decoded_phase)) does not match ($nt, $m)"))
        return Float64.(decoded_phase), :matrix
    end
    throw(ArgumentError("fiber field physics requires a vector or matrix decoded phase"))
end

function _field_matrix(field, problem::FiberFieldProblem, label::AbstractString)
    nt = problem.sim["Nt"]
    m = problem.sim["M"]
    if field isa Real
        return fill(Float64(field), nt, m), :scalar
    end
    if field isa AbstractVector
        length(field) == nt || throw(ArgumentError(
            "$label vector length $(length(field)) does not match Nt=$nt"))
        column = reshape(Float64.(collect(field)), nt, 1)
        return repeat(column, 1, m), :vector
    end
    if field isa AbstractMatrix
        size(field) == (nt, m) || throw(ArgumentError(
            "$label matrix size $(size(field)) does not match ($nt, $m)"))
        return Float64.(field), :matrix
    end
    throw(ArgumentError("$label must be a real scalar, vector, or matrix"))
end

function _physical_gradient_for_shape(gradient, shape::Symbol)
    shape == :scalar && return [sum(gradient)]
    shape == :vector && return vec(sum(gradient; dims = 2))
    shape == :matrix && return gradient
    throw(ArgumentError("unsupported physical field shape `$(shape)`"))
end

function _control_field(decoded_control, name::Symbol, default)
    if decoded_control isa NamedTuple && hasproperty(decoded_control, name)
        return getproperty(decoded_control, name)
    end
    if decoded_control isa AbstractDict
        haskey(decoded_control, name) && return decoded_control[name]
        haskey(decoded_control, String(name)) && return decoded_control[String(name)]
    end
    if name == :phase
        return decoded_control
    end
    return default
end

function _single_mode_fields(decoded_control, problem::FiberFieldProblem)
    default_phase = zeros(problem.sim["Nt"], problem.sim["M"])
    phase, phase_shape = _phase_matrix(_control_field(decoded_control, :phase, default_phase), problem)
    amplitude, amplitude_shape = _field_matrix(
        _control_field(decoded_control, :amplitude, 1.0),
        problem,
        "amplitude",
    )
    all(>(0), amplitude) || throw(ArgumentError(
        "fiber field amplitude control must be strictly positive"))
    energy = Float64(_control_field(decoded_control, :energy, 1.0))
    isfinite(energy) && energy > 0 || throw(ArgumentError(
        "fiber field energy control must be positive and finite"))
    return (
        phase = phase,
        phase_shape = phase_shape,
        amplitude = amplitude,
        amplitude_shape = amplitude_shape,
        energy = energy,
        alpha = sqrt(energy),
    )
end

function _single_mode_signature(fields)
    return (
        phase = copy(fields.phase),
        amplitude = copy(fields.amplitude),
        energy = fields.energy,
    )
end

function _same_signature(left, right)
    left === nothing && return false
    return left.energy == right.energy &&
        left.phase == right.phase &&
        left.amplitude == right.amplitude
end

function _shaped_input(problem::FiberFieldProblem, fields)
    return fields.alpha .* fields.amplitude .* cis.(fields.phase) .* problem.uω0
end

function _cached_forward!(physics::SingleModePhasePhysics, decoded_control)
    problem = physics.problem
    fields = _single_mode_fields(decoded_control, problem)
    signature = _single_mode_signature(fields)
    cache = physics.cache
    if _same_signature(cache.signature, signature) && cache.final_field !== nothing
        return cache.final_field, cache.ode_solution, cache.shaped_input, cache.physical_fields
    end

    shaped = _shaped_input(problem, fields)
    sol = solve_disp_mmf(shaped, problem.fiber, problem.sim)["ode_sol"]
    final_field = cis.(problem.fiber["Dω"] .* problem.fiber["L"]) .* sol(problem.fiber["L"])

    cache.signature = signature
    cache.shaped_input = Matrix{ComplexF64}(shaped)
    cache.ode_solution = sol
    cache.final_field = Matrix{ComplexF64}(final_field)
    cache.physical_fields = fields
    return cache.final_field, cache.ode_solution, cache.shaped_input, fields
end

function _field_objective_from_cost_adjoint(kind::Symbol, cost_adjoint::Function,
                                            log_cost::Bool,
                                            figure_hooks = (:field_summary, :convergence_trace))
    return ObjectiveMap(
        kind;
        cost = field -> first(_maybe_log_cost(cost_adjoint(field)..., log_cost)),
        terminal_adjoint = (field, context) -> last(_maybe_log_cost(cost_adjoint(field)..., log_cost)),
        figure_hooks = Tuple(Symbol(hook) for hook in figure_hooks),
    )
end

"""
    raman_band_objective(problem; log_cost=false, name=:raman_band)

Create a mode-summed Raman-band field objective. This is an explicit constructor
that returns an `ObjectiveMap`; custom objectives should be written directly as
`ObjectiveMap(...)` objects.
"""
function raman_band_objective(problem::FiberFieldProblem;
                              log_cost::Bool=false,
                              name::Symbol=:raman_band)
    mask = _problem_band_mask(problem, name)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_spectral_band_cost(field, mask),
        log_cost,
    )
end

function mode_sum_objective(problem::FiberFieldProblem; log_cost::Bool=false,
                            name::Symbol=:mode_sum)
    mask = _problem_band_mask(problem, name)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_spectral_band_cost(field, mask),
        log_cost,
        (:field_summary, :mode_resolved_spectra, :per_mode_leakage_table, :convergence_trace),
    )
end

function fundamental_mode_objective(problem::FiberFieldProblem;
                                    log_cost::Bool=false,
                                    name::Symbol=:fundamental_mode)
    mask = _problem_band_mask(problem, name)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_fundamental_band_cost(field, mask),
        log_cost,
        (:field_summary, :mode_resolved_spectra, :convergence_trace),
    )
end

function worst_mode_objective(problem::FiberFieldProblem;
                              log_cost::Bool=false,
                              worst_mode_tau::Real=50.0,
                              name::Symbol=:worst_mode)
    mask = _problem_band_mask(problem, name)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_worst_mode_band_cost(
            field,
            mask;
            τ = worst_mode_tau,
        ),
        log_cost,
        (:field_summary, :mode_resolved_spectra, :per_mode_leakage_table, :convergence_trace),
    )
end

function raman_peak_objective(problem::FiberFieldProblem;
                              log_cost::Bool=false,
                              name::Symbol=:raman_peak)
    mask = _problem_band_mask(problem, name)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_spectral_peak_cost(field, mask),
        log_cost,
    )
end

function temporal_width_objective(problem::FiberFieldProblem;
                                  log_cost::Bool=false,
                                  name::Symbol=:temporal_width)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_temporal_width_cost(field, problem.sim),
        log_cost,
    )
end

_field_objective(::Val{:raman_band}, problem::FiberFieldProblem; kwargs...) =
    raman_band_objective(problem; kwargs...)
_field_objective(::Val{:mode_sum}, problem::FiberFieldProblem; kwargs...) =
    mode_sum_objective(problem; kwargs...)
_field_objective(::Val{:mmf_sum}, problem::FiberFieldProblem; kwargs...) =
    mode_sum_objective(problem; name = :mmf_sum, kwargs...)
_field_objective(::Val{:fundamental_mode}, problem::FiberFieldProblem; kwargs...) =
    fundamental_mode_objective(problem; kwargs...)
_field_objective(::Val{:mmf_fundamental}, problem::FiberFieldProblem; kwargs...) =
    fundamental_mode_objective(problem; name = :mmf_fundamental, kwargs...)
_field_objective(::Val{:worst_mode}, problem::FiberFieldProblem; kwargs...) =
    worst_mode_objective(problem; kwargs...)
_field_objective(::Val{:mmf_worst_mode}, problem::FiberFieldProblem; kwargs...) =
    worst_mode_objective(problem; name = :mmf_worst_mode, kwargs...)
_field_objective(::Val{:raman_peak}, problem::FiberFieldProblem; kwargs...) =
    raman_peak_objective(problem; kwargs...)
_field_objective(::Val{:temporal_width}, problem::FiberFieldProblem; kwargs...) =
    temporal_width_objective(problem; kwargs...)

"""
    field_objective(kind, problem; log_cost=false, kwargs...)

Compatibility helper for symbolic configs and quick notebooks. The behavior-
first API is to call explicit constructors such as `raman_band_objective` or to
pass a custom `ObjectiveMap` directly.
"""
function field_objective(kind::Symbol, problem::FiberFieldProblem; kwargs...)
    hasmethod(_field_objective, Tuple{Val{kind}, FiberFieldProblem}) || throw(ArgumentError(
        "unsupported field objective `$(kind)`; call an explicit objective constructor or pass an ObjectiveMap directly for custom objectives"))
    return try
        _field_objective(Val(kind), problem; kwargs...)
    catch err
        err isa MethodError && throw(ArgumentError(
            "unsupported field objective keyword for `$(kind)`: $(sprint(showerror, err))"))
        rethrow()
    end
end

"""
    single_mode_phase_model(problem) -> AdjointModel

Compatibility alias for `fiber_model(problem)`.
"""
function single_mode_phase_model(problem::FiberFieldProblem)
    return spectral_shaper_model(problem)
end

"""
    single_mode_shaper_model(problem) -> AdjointModel

Compatibility alias for `fiber_model(problem)`.
"""
function single_mode_shaper_model(problem::FiberFieldProblem)
    return spectral_shaper_model(problem)
end

"""
    fiber_model(problem) -> AdjointModel

Return the package-native adjoint model for a fiber field problem. The decoded
control may be a phase vector/matrix, or a NamedTuple/Dict with optional
`phase`, `amplitude`, and `energy` fields.
"""
function fiber_model(problem::FiberFieldProblem)
    return spectral_shaper_model(problem)
end

"""
    spectral_shaper_model(problem) -> AdjointModel

Low-level model constructor used by `fiber_model(problem)`. New notebook code
should call `fiber_model(problem)`.
"""
function spectral_shaper_model(problem::FiberFieldProblem)
    physics = SingleModePhasePhysics(problem, SingleModePhaseCache())
    return AdjointModel(
        :spectral_shaper_propagation;
        forward = (decoded_control, context) -> first(_cached_forward!(physics, decoded_control)),
        physical_gradient = (decoded_control, terminal_seed, context) -> begin
            _, forward_solution, shaped_input, fields = _cached_forward!(physics, decoded_control)
            adjoint_solution = solve_adjoint_disp_mmf(
                terminal_seed,
                forward_solution,
                problem.fiber,
                problem.sim,
            )
            λ0 = adjoint_solution(0)
            phase_gradient = 2.0 .* real.(conj.(λ0) .* (1im .* shaped_input))
            amplitude_gradient = 2.0 .* fields.alpha .* real.(
                conj.(λ0) .* cis.(fields.phase) .* problem.uω0
            )
            energy_gradient = real(sum(conj.(λ0) .* shaped_input)) / fields.energy
            all(isfinite, phase_gradient) || throw(ArgumentError(
                "fiber field phase physical gradient contains non-finite values"))
            all(isfinite, amplitude_gradient) || throw(ArgumentError(
                "fiber field amplitude physical gradient contains non-finite values"))
            isfinite(energy_gradient) || throw(ArgumentError(
                "fiber field energy physical gradient is not finite"))
            if decoded_control isa NamedTuple
                gradients = Pair{Symbol,Any}[]
                hasproperty(decoded_control, :phase) && push!(gradients, :phase =>
                    _physical_gradient_for_shape(phase_gradient, fields.phase_shape))
                hasproperty(decoded_control, :amplitude) && push!(gradients, :amplitude =>
                    _physical_gradient_for_shape(amplitude_gradient, fields.amplitude_shape))
                hasproperty(decoded_control, :energy) && push!(gradients, :energy => [energy_gradient])
                return NamedTuple(gradients)
            end
            if decoded_control isa AbstractDict
                gradients = Dict{Symbol,Any}()
                if haskey(decoded_control, :phase) || haskey(decoded_control, "phase")
                    (gradients[:phase] = _physical_gradient_for_shape(
                        phase_gradient, fields.phase_shape))
                end
                if haskey(decoded_control, :amplitude) || haskey(decoded_control, "amplitude")
                    (gradients[:amplitude] = _physical_gradient_for_shape(
                        amplitude_gradient, fields.amplitude_shape))
                end
                if haskey(decoded_control, :energy) || haskey(decoded_control, "energy")
                    (gradients[:energy] = [energy_gradient])
                end
                return gradients
            end
            return _physical_gradient_for_shape(phase_gradient, fields.phase_shape)
        end,
        description = "Nonlinear fiber propagation with spectral shaper adjoint.",
    )
end

function _fiber_metadata_from_problem(problem::FiberFieldProblem, reference_power_w)
    power_source = reference_power_w === nothing ? problem.reference_power_w : reference_power_w
    power_source !== nothing || throw(ArgumentError(
        "solve(problem, ...) needs reference_power_w metadata for this explicit low-level problem; pass `reference_power_w=...` or build the problem from a Fiber"))
    power = Float64(power_source)
    isfinite(power) && power > 0 || throw(ArgumentError(
        "reference_power_w must be positive and finite when solving from a FiberFieldProblem"))
    return Fiber(;
        regime = mode_count(problem) == 1 ? :single_mode : :multimode,
        preset = problem.preset,
        length_m = Float64(problem.fiber["L"]),
        power_w = power,
    )
end

"""
    solve(problem, control, objective, initial_coordinates; kwargs...)

Notebook-first convenience path for package-native fiber physics. It builds
`fiber_model(problem)` and delegates to the same native adjoint execution used
by `solve(model, control, objective, initial_coordinates; ...)`.

`reference_power_w` is metadata for the experiment record only; the physical
launch field is already contained in `problem.uω0`.
"""
function solve(problem::FiberFieldProblem,
               control::AbstractControlMap,
               objective::AbstractFiberObjective,
               initial_coordinates;
               reference_power_w=nothing,
               kwargs...)
    return solve(
        fiber_model(problem),
        control,
        objective,
        initial_coordinates;
        fiber = _fiber_metadata_from_problem(problem, reference_power_w),
        kwargs...,
    )
end

function solve(problem::FiberFieldProblem,
               control::AbstractControlMap,
               objective::AbstractFiberObjective;
               kwargs...)
    return solve(problem, control, objective, initial_coordinates(control); kwargs...)
end
