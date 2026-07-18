struct FiberProblemMetadata
    requested_fiber::Union{Missing,Fiber}
    requested_pulse::Union{Missing,Pulse}
    requested_grid::Union{Missing,Grid}
    preset::Symbol
    construction_sha256::Union{Nothing,String}
end

struct FiberFieldProblem
    uω0::Matrix{ComplexF64}
    fiber::Dict{String,Any}
    sim::Dict{String,Any}
    band_mask::Union{Nothing,Vector{Bool}}
    frequency_offset_thz::Vector{Float64}
    raman_threshold_thz::Union{Nothing,Float64}
    metadata::FiberProblemMetadata
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
        preset = problem.metadata.preset,
        samples = sample_count(problem),
        modes = mode_count(problem),
        length_m = Float64(problem.fiber["L"]),
        reference_power_w = ismissing(problem.metadata.requested_fiber) ?
            missing : problem.metadata.requested_fiber.power_w,
        raman_threshold_thz = problem.raman_threshold_thz,
        band_bins = band_bins,
        raman_response = _raman_response_metadata(problem.fiber),
    )
end

function _validate_package_inputs(fiber::Fiber, pulse::Pulse, wavelength_m::Real)
    isfinite(fiber.length_m) && fiber.length_m > 0 || throw(ArgumentError(
        "fiber length_m must be positive and finite"))
    isfinite(fiber.power_w) && fiber.power_w > 0 || throw(ArgumentError(
        "fiber power_w must be positive and finite"))
    fiber.beta_order >= 2 || throw(ArgumentError("fiber beta_order must be at least 2"))
    isfinite(pulse.fwhm_s) && pulse.fwhm_s > 0 || throw(ArgumentError(
        "pulse fwhm_s must be positive and finite"))
    isfinite(pulse.rep_rate_hz) && pulse.rep_rate_hz > 0 || throw(ArgumentError(
        "pulse rep_rate_hz must be positive and finite"))
    isfinite(wavelength_m) && wavelength_m > 0 || throw(ArgumentError(
        "wavelength_m must be positive and finite"))
    return nothing
end

_resolved_raman_fraction(fiber::Fiber, preset_fraction::Real) =
    fiber.raman_fraction === nothing ? Float64(preset_fraction) : fiber.raman_fraction

function _preset_raman_fraction(preset::Symbol)
    haskey(SINGLE_MODE_FIBER_PRESETS, preset) &&
        return Float64(SINGLE_MODE_FIBER_PRESETS[preset].fR)
    haskey(MULTIMODE_FIBER_PRESETS, preset) &&
        return Float64(MULTIMODE_FIBER_PRESETS[preset].fR)
    return _SILICA_RAMAN_FRACTION
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
    _validate_package_inputs(fiber_spec, pulse, wavelength_m)
    fiber_spec.regime == :single_mode || throw(ArgumentError(
        "single_mode_fiber_problem requires fiber.regime = :single_mode"))
    preset = _single_mode_preset(fiber_spec.preset)
    resolved_grid = resolve_grid(fiber_spec, pulse, grid; wavelength_m=wavelength_m)
    sim = get_disp_sim_params(
        Float64(wavelength_m),
        1,
        resolved_grid.nt,
        resolved_grid.time_window_ps,
        fiber_spec.beta_order,
    )
    fiber = get_disp_fiber_params_user_defined(
        fiber_spec.length_m,
        sim;
        fR = _resolved_raman_fraction(fiber_spec, preset.fR),
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

function _problem_metadata(; requested_fiber=missing,
                           requested_pulse=missing,
                           requested_grid=missing,
                           preset::Symbol=:custom,
                           construction_sha256=nothing)
    return FiberProblemMetadata(
        requested_fiber,
        requested_pulse,
        requested_grid,
        preset,
        construction_sha256,
    )
end

function _raman_threshold(value::Real)
    threshold = Float64(value)
    isfinite(threshold) && threshold < 0 || throw(ArgumentError(
        "raman_threshold_thz must be finite and negative"))
    return threshold
end

function _array_sha256(array::Array)
    context = SHA.SHA256_CTX()
    header = string(eltype(array), ":", join(size(array), "x"), ":")
    SHA.update!(context, codeunits(header))
    SHA.update!(context, reinterpret(UInt8, vec(array)))
    return bytes2hex(SHA.digest!(context))
end

_array_sha256(values::AbstractArray) = _array_sha256(Array(values))

_signature_value(value::AbstractArray) = (
    eltype = string(eltype(value)),
    size = size(value),
    sha256 = _array_sha256(value),
)
_signature_value(value::AbstractDict) = Tuple(
    (String(key), _signature_value(value[key])) for key in sort!(collect(keys(value)))
)
_signature_value(value) = repr(value)

function _numerical_problem_signature(problem::FiberFieldProblem)
    components = (
        launch = _array_sha256(problem.uω0),
        fiber = _signature_value(problem.fiber),
        simulation = _signature_value(problem.sim),
        band_mask = problem.band_mask === nothing ? nothing : _array_sha256(problem.band_mask),
        frequency_offsets = _array_sha256(problem.frequency_offset_thz),
        raman_threshold_thz = problem.raman_threshold_thz,
        solver = (:Tsit5, get(problem.fiber, "reltol", 1e-8),
            get(problem.fiber, "abstol", 1e-6)),
    )
    return bytes2hex(sha256(codeunits(repr(components))))
end

function _resolved_problem_signature(problem::FiberFieldProblem)
    components = (
        metadata = repr(problem.metadata),
        numerical_sha256 = _numerical_problem_signature(problem),
    )
    return bytes2hex(sha256(codeunits(repr(components))))
end

function _seal_package_problem(problem::FiberFieldProblem)
    metadata = problem.metadata
    any(ismissing, (
        metadata.requested_fiber,
        metadata.requested_pulse,
        metadata.requested_grid,
    )) && return problem
    construction_sha256 = _numerical_problem_signature(problem)
    metadata.construction_sha256 === nothing ||
        metadata.construction_sha256 == construction_sha256 || throw(ArgumentError(
            "package-built problem changed after construction"))
    sealed_metadata = FiberProblemMetadata(
        metadata.requested_fiber,
        metadata.requested_pulse,
        metadata.requested_grid,
        metadata.preset,
        construction_sha256,
    )
    return FiberFieldProblem(
        problem.uω0,
        problem.fiber,
        problem.sim,
        problem.band_mask,
        problem.frequency_offset_thz,
        problem.raman_threshold_thz,
        sealed_metadata,
    )
end

function _validate_package_problem_snapshot(problem::FiberFieldProblem)
    construction_sha256 = problem.metadata.construction_sha256
    construction_sha256 === nothing && return nothing
    _numerical_problem_signature(problem) == construction_sha256 || throw(ArgumentError(
        "package-built problem changed after construction; wrap edited arrays with fiber_field_problem for an explicit numerical run"))
    return nothing
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
    threshold = _raman_threshold(raman_threshold_thz)
    band_mask = frequency_offset_fft .< threshold
    any(band_mask) || throw(ArgumentError(
        "raman_threshold_thz selects no frequency bins"))
    return _seal_package_problem(SingleModeFiberProblem(
        uω0,
        fiber,
        sim,
        Vector{Bool}(band_mask),
        fftshift(frequency_offset_fft),
        threshold,
        _problem_metadata(;
            requested_fiber = fiber_spec,
            requested_pulse = pulse,
            requested_grid = grid,
            preset = fiber_spec.preset,
        ),
    ))
end

single_mode_fiber_problem(experiment::Experiment; kwargs...) =
    single_mode_fiber_problem(
        experiment.fiber;
        pulse = experiment.pulse,
        grid = experiment.grid,
        kwargs...,
    )

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
multimode physics (`dispersion`, `gamma_tensor`, and `initial_modes`) on an
exact/fixed grid, or pass the low-level
`(uω0, fiber, sim)` objects directly. Sampled dispersion is never reinterpreted
after automatic grid changes.
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
                       gamma_tensor=nothing)
    _validate_package_inputs(fiber_spec, pulse, wavelength_m)
    mode_count = Int(modes)
    mode_count > 0 || throw(ArgumentError("fiber_problem modes must be positive"))
    expected_regime = mode_count == 1 ? :single_mode : :multimode
    fiber_spec.regime == expected_regime || throw(ArgumentError(
        "fiber regime $(fiber_spec.regime) does not match modes=$mode_count"))
    if mode_count == 1 && dispersion === nothing && gamma_tensor === nothing &&
            initial_modes === nothing
        uω0, fiber, sim = _single_mode_low_level_setup(
            fiber_spec,
            pulse,
            grid,
            wavelength_m,
        )
        return _fiber_field_problem(
            uω0,
            fiber,
            sim;
            band_mask = band_mask,
            raman_threshold_thz = band_mask === nothing ? raman_threshold_thz : nothing,
            metadata = _problem_metadata(
                requested_fiber = fiber_spec,
                requested_pulse = pulse,
                requested_grid = grid,
                preset = fiber_spec.preset,
            ),
        )
    end

    grid.policy in (:exact, :fixed) || throw(ArgumentError(
        "fiber_problem with explicit sampled dispersion requires grid.policy=:exact or :fixed"))
    resolved_grid = resolve_sampling_grid(grid; wavelength_m=Float64(wavelength_m))
    nt, time_window_ps = resolved_grid.nt, resolved_grid.time_window_ps
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
    raman = _single_oscillator_raman_fields(
        sim;
        fR = _resolved_raman_fraction(
            fiber_spec,
            _preset_raman_fraction(fiber_spec.preset),
        ),
        τ1 = _SILICA_RAMAN_TAU1_FS,
        τ2 = _SILICA_RAMAN_TAU2_FS,
    )
    fiber = Dict{String,Any}(
        "ϕ" => nothing,
        "Dω" => dispersion_matrix,
        "γ" => gamma,
        "L" => fiber_spec.length_m,
        "zsave" => nothing,
        "x" => nothing,
        "gain_parameters" => 0.0,
    )
    merge!(fiber, raman)
    return _fiber_field_problem(
        Matrix{ComplexF64}(uω0),
        fiber,
        sim;
        band_mask = band_mask,
        raman_threshold_thz = band_mask === nothing ? raman_threshold_thz : nothing,
        metadata = _problem_metadata(
            requested_fiber = fiber_spec,
            requested_pulse = pulse,
            requested_grid = grid,
            preset = fiber_spec.preset,
        ),
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

function _real_response_spectrum(response)
    nt = length(response)
    scale = max(1.0, maximum(abs, response))
    tolerance = 1e-12 * scale
    abs(imag(response[1])) <= tolerance || return false
    abs(imag(response[nt ÷ 2 + 1])) <= tolerance || return false
    return all(
        isapprox(response[index], conj(response[nt - index + 2]); rtol = 1e-12,
                 atol = tolerance)
        for index in 2:nt÷2
    )
end

"""
    fiber_field_problem(uω0, fiber, sim; band_mask=nothing, raman_threshold_thz=nothing, preset=:custom)

Wrap an explicit low-level propagation setup as a FiberLab adjoint problem. This
is the escape hatch for researcher-supplied multimode physics: callers provide
the actual initial field, fiber dictionary, and simulation dictionary used by
`solve_disp_mmf` and `solve_adjoint_disp_mmf`. Band-based built-in objectives
need either an explicit `band_mask` or a `raman_threshold_thz`; custom
objectives that do not use a band can omit both.
"""
function _fiber_field_problem(uω0, fiber, sim;
                              metadata::FiberProblemMetadata,
                              band_mask=nothing,
                              raman_threshold_thz=nothing)
    required_sim = ("Nt", "M", "Δt", "time_window", "λ0", "ω0", "ωs", "β_order")
    all(key -> haskey(sim, key), required_sim) || throw(ArgumentError(
        "simulation dictionary is missing required propagation fields"))
    field = Matrix{ComplexF64}(uω0)
    nt = Int(sim["Nt"])
    m = Int(sim["M"])
    nt >= 4 && ispow2(nt) || throw(ArgumentError("simulation Nt must be a power of two ≥ 4"))
    m > 0 || throw(ArgumentError("simulation M must be positive"))
    delta_t = Float64(sim["Δt"])
    time_window = Float64(sim["time_window"])
    wavelength = Float64(sim["λ0"])
    omega0 = Float64(sim["ω0"])
    isfinite(delta_t) && delta_t > 0 || throw(ArgumentError("simulation Δt must be positive and finite"))
    isfinite(time_window) && time_window > 0 || throw(ArgumentError(
        "simulation time_window must be positive and finite"))
    isapprox(time_window, nt * delta_t; rtol = 1e-12) || throw(ArgumentError(
        "simulation time_window must equal Nt * Δt"))
    isfinite(wavelength) && wavelength > 0 || throw(ArgumentError(
        "simulation λ0 must be positive and finite"))
    isfinite(omega0) && omega0 > 0 || throw(ArgumentError(
        "simulation ω0 must be positive and finite"))
    expected_f0 = 2.99792458e8 / wavelength / 1e12
    expected_omega0 = 2π * expected_f0
    isapprox(omega0, expected_omega0; rtol = 1e-12) || throw(ArgumentError(
        "simulation ω0 is inconsistent with λ0"))
    Int(sim["β_order"]) >= 2 || throw(ArgumentError(
        "simulation β_order must be at least 2"))
    sim["ωs"] isa AbstractVector && length(sim["ωs"]) == nt &&
        all(isfinite, sim["ωs"]) || throw(ArgumentError(
        "simulation ωs must be a finite Nt-vector"))
    expected_omegas = 2π .* (
        expected_f0 .+ fftshift(FFTW.fftfreq(nt, 1 / delta_t)))
    isapprox(sim["ωs"], expected_omegas; rtol = 1e-12) || throw(ArgumentError(
        "simulation ωs is inconsistent with λ0, Nt, and Δt"))
    all(>(0), sim["ωs"]) || throw(ArgumentError(
        "simulation absolute angular frequencies must be positive"))
    size(field) == (nt, m) || throw(ArgumentError(
        "uω0 size $(size(field)) does not match simulation size ($nt, $m)"))
    all(isfinite, field) || throw(ArgumentError("uω0 must contain only finite values"))
    field_norm = norm(field)
    isfinite(field_norm) && field_norm > 0 || throw(ArgumentError(
        "uω0 must contain a finite, nonzero launch field"))
    size(fiber["Dω"]) == (nt, m) || throw(ArgumentError(
        "fiber Dω size $(size(fiber["Dω"])) does not match ($nt, $m)"))
    size(fiber["γ"]) == (m, m, m, m) || throw(ArgumentError(
        "fiber γ size $(size(fiber["γ"])) does not match ($m, $m, $m, $m)"))
    haskey(fiber, "L") || throw(ArgumentError("fiber dictionary must contain \"L\""))
    haskey(fiber, "hRω") || throw(ArgumentError("fiber dictionary must contain \"hRω\""))
    haskey(fiber, "one_m_fR") || throw(ArgumentError(
        "fiber dictionary must contain \"one_m_fR\""))
    haskey(fiber, "zsave") || throw(ArgumentError("fiber dictionary must contain \"zsave\""))
    fiber["hRω"] isa AbstractVector && length(fiber["hRω"]) == nt || throw(ArgumentError(
        "fiber hRω length must match simulation Nt"))
    isfinite(Float64(fiber["L"])) && Float64(fiber["L"]) > 0 || throw(ArgumentError(
        "fiber L must be positive and finite"))
    all(isfinite, fiber["Dω"]) || throw(ArgumentError("fiber Dω must be finite"))
    _validate_real_gamma_storage(fiber["γ"])
    all(isfinite, fiber["hRω"]) || throw(ArgumentError("fiber hRω must be finite"))
    _real_response_spectrum(fiber["hRω"]) || throw(ArgumentError(
        "fiber hRω must have raw-FFT Hermitian symmetry for a real time response"))
    one_m_fR = Float64(fiber["one_m_fR"])
    isfinite(one_m_fR) && 0 <= one_m_fR <= 1 || throw(ArgumentError(
        "fiber one_m_fR must be finite and lie in [0, 1]"))
    raman = _raman_response_metadata(fiber)
    if !ismissing(raman)
        !isempty(raman.model) || throw(ArgumentError("Raman response model must be nonempty"))
        isfinite(raman.fraction) && 0 <= raman.fraction <= 1 || throw(ArgumentError(
            "Raman fraction must be finite and lie in [0, 1]"))
        isfinite(raman.tau1_fs) && raman.tau1_fs > 0 || throw(ArgumentError(
            "Raman tau1_fs must be positive and finite"))
        isfinite(raman.tau2_fs) && raman.tau2_fs > 0 || throw(ArgumentError(
            "Raman tau2_fs must be positive and finite"))
        isapprox(one_m_fR, 1 - raman.fraction; rtol = 0, atol = 8eps(Float64)) ||
            throw(ArgumentError("fiber one_m_fR disagrees with Raman fraction"))
        isapprox(fiber["hRω"][1], raman.fraction; rtol = 1e-12, atol = 1e-14) ||
            throw(ArgumentError("fiber hRω DC value disagrees with Raman fraction"))
        if raman.model == _RAMAN_RESPONSE_MODEL
            expected = _single_oscillator_raman_fields(
                sim;
                fR = raman.fraction,
                τ1 = raman.tau1_fs,
                τ2 = raman.tau2_fs,
            )["hRω"]
            isapprox(fiber["hRω"], expected; rtol = 1e-12, atol = 1e-14) ||
                throw(ArgumentError("fiber hRω disagrees with declared Raman model"))
        end
    end

    frequency_offset_fft = FFTW.fftfreq(nt, 1 / sim["Δt"])
    resolved_threshold = raman_threshold_thz === nothing ?
        nothing : _raman_threshold(raman_threshold_thz)
    resolved_band_mask = if band_mask !== nothing
        mask = Vector{Bool}(collect(band_mask))
        length(mask) == nt || throw(ArgumentError(
            "band_mask length $(length(mask)) does not match Nt=$nt"))
        any(mask) || throw(ArgumentError("band_mask must select at least one frequency bin"))
        mask
    elseif resolved_threshold !== nothing
        mask = frequency_offset_fft .< resolved_threshold
        any(mask) || throw(ArgumentError(
            "raman_threshold_thz selects no frequency bins"))
        Vector{Bool}(mask)
    else
        nothing
    end
    return _seal_package_problem(SingleModeFiberProblem(
        field,
        Dict{String,Any}(fiber),
        Dict{String,Any}(sim),
        resolved_band_mask,
        fftshift(frequency_offset_fft),
        resolved_threshold,
        metadata,
    ))
end

function fiber_field_problem(uω0, fiber, sim;
                             band_mask=nothing,
                             raman_threshold_thz=nothing,
                             preset::Symbol=:custom)
    return _fiber_field_problem(
        uω0,
        fiber,
        sim;
        band_mask = band_mask,
        raman_threshold_thz = raman_threshold_thz,
        metadata = _problem_metadata(preset = preset),
    )
end

function _fiber_with_raman_fraction(fiber::Fiber, fraction::Float64)
    return Fiber(
        regime = fiber.regime,
        preset = fiber.preset,
        length_m = fiber.length_m,
        power_w = fiber.power_w,
        beta_order = fiber.beta_order,
        raman_fraction = fraction,
    )
end

"""
    with_raman_fraction(problem, fraction) -> FiberFieldProblem

Construct a Raman counterfactual from a sealed package-built problem without
mutating it. The new problem preserves the launch, numerical grid, dispersion,
nonlinear coupling, band selection, and Raman time constants; only the delayed
Raman fraction and its response fields change. `fraction` must lie in `[0, 1]`.

This operation requires package provenance. Build explicit multimode physics
through `fiber_problem(Fiber(...); dispersion, gamma_tensor, initial_modes)`
when a sealed counterfactual is needed.
"""
function with_raman_fraction(problem::FiberFieldProblem, fraction::Real)
    value = Float64(fraction)
    isfinite(value) && 0 <= value <= 1 || throw(ArgumentError(
        "Raman fraction must be finite and lie in [0, 1]"))
    metadata = problem.metadata
    any(ismissing, (
        metadata.requested_fiber,
        metadata.requested_pulse,
        metadata.requested_grid,
    )) && throw(ArgumentError(
        "with_raman_fraction requires a package-built problem with complete provenance"))
    _validate_package_problem_snapshot(problem)

    raman = _raman_response_metadata(problem.fiber)
    ismissing(raman) && throw(ArgumentError(
        "with_raman_fraction requires declared Raman response provenance"))
    raman.model == _RAMAN_RESPONSE_MODEL || throw(ArgumentError(
        "with_raman_fraction does not know how to rescale Raman model `$(raman.model)`"))

    fiber = deepcopy(problem.fiber)
    merge!(fiber, _single_oscillator_raman_fields(
        problem.sim;
        fR = value,
        τ1 = raman.tau1_fs,
        τ2 = raman.tau2_fs,
    ))
    transformed_metadata = _problem_metadata(
        requested_fiber = _fiber_with_raman_fraction(metadata.requested_fiber, value),
        requested_pulse = metadata.requested_pulse,
        requested_grid = metadata.requested_grid,
        preset = metadata.preset,
    )
    return _fiber_field_problem(
        copy(problem.uω0),
        fiber,
        deepcopy(problem.sim);
        band_mask = problem.band_mask === nothing ? nothing : copy(problem.band_mask),
        raman_threshold_thz = problem.raman_threshold_thz,
        metadata = transformed_metadata,
    )
end

"""
    with_launch(problem, launch) -> FiberFieldProblem

Create an explicit numerical problem with a replacement launch field while
preserving the resolved fiber model, grid, and optional band selection. The
source problem is not mutated. Because the launch no longer follows directly
from the original `Fiber`/`Pulse` request, the returned problem intentionally
uses resolved-numerical rather than authoritative construction provenance.
"""
function with_launch(problem::FiberFieldProblem, launch)
    _validate_package_problem_snapshot(problem)
    return _fiber_field_problem(
        launch,
        deepcopy(problem.fiber),
        deepcopy(problem.sim);
        band_mask = problem.band_mask === nothing ? nothing : copy(problem.band_mask),
        raman_threshold_thz = problem.raman_threshold_thz,
        metadata = _problem_metadata(preset = problem.metadata.preset),
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
        values = Float64.(collect(decoded_phase))
        all(isfinite, values) || throw(ArgumentError("phase values must be finite"))
        column = reshape(values, nt, 1)
        return repeat(column, 1, m), :vector
    end
    if decoded_phase isa AbstractMatrix
        size(decoded_phase) == (nt, m) || throw(ArgumentError(
            "phase matrix size $(size(decoded_phase)) does not match ($nt, $m)"))
        values = Float64.(decoded_phase)
        all(isfinite, values) || throw(ArgumentError("phase values must be finite"))
        return values, :matrix
    end
    throw(ArgumentError("fiber field physics requires a vector or matrix decoded phase"))
end

function _field_matrix(field, problem::FiberFieldProblem, label::AbstractString)
    nt = problem.sim["Nt"]
    m = problem.sim["M"]
    if field isa Real
        value = Float64(field)
        isfinite(value) || throw(ArgumentError("$label must be finite"))
        return fill(value, nt, m), :scalar
    end
    if field isa AbstractVector
        length(field) == nt || throw(ArgumentError(
            "$label vector length $(length(field)) does not match Nt=$nt"))
        values = Float64.(collect(field))
        all(isfinite, values) || throw(ArgumentError("$label values must be finite"))
        column = reshape(values, nt, 1)
        return repeat(column, 1, m), :vector
    end
    if field isa AbstractMatrix
        size(field) == (nt, m) || throw(ArgumentError(
            "$label matrix size $(size(field)) does not match ($nt, $m)"))
        values = Float64.(field)
        all(isfinite, values) || throw(ArgumentError("$label values must be finite"))
        return values, :matrix
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
    shaped = fields.alpha .* fields.amplitude .* cis.(fields.phase) .* problem.uω0
    shaped_norm = norm(shaped)
    all(isfinite, shaped) && isfinite(shaped_norm) && shaped_norm > 0 || throw(ArgumentError(
        "decoded controls must produce a finite, nonzero launch field"))
    return shaped
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
    propagation = _forward_propagation(problem, shaped)
    solution = propagation.solution
    final_field = propagation.output

    cache.signature = signature
    cache.shaped_input = Matrix{ComplexF64}(shaped)
    cache.ode_solution = solution
    cache.final_field = Matrix{ComplexF64}(final_field)
    cache.physical_fields = fields
    return cache.final_field, cache.ode_solution, cache.shaped_input, fields
end

function _field_objective_from_cost_adjoint(kind::Symbol, cost_adjoint::Function,
                                            log_cost::Bool,
                                            problem::FiberFieldProblem,
                                            figure_hooks = nothing;
                                            contract_kind::Symbol=kind)
    hooks = if figure_hooks === nothing
        contract = objective_contract(contract_kind)
        contract === nothing ? (:field_summary, :convergence_trace) : contract.figure_hooks
    else
        Tuple(Symbol(hook) for hook in figure_hooks)
    end
    return ObjectiveMap(
        _OBJECTIVE_BINDING_TOKEN,
        kind;
        cost = field -> first(_maybe_log_cost(cost_adjoint(field)..., log_cost)),
        terminal_adjoint = (field, context) -> last(_maybe_log_cost(cost_adjoint(field)..., log_cost)),
        figure_hooks = hooks,
        cost_scale = log_cost ? :db : :linear,
        contract_kind = contract_kind,
        problem_sha256 = _resolved_problem_signature(problem),
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
        problem,
        nothing;
        contract_kind = :raman_band,
    )
end

function mode_sum_objective(problem::FiberFieldProblem; log_cost::Bool=false,
                            name::Symbol=:mode_sum)
    mask = _problem_band_mask(problem, name)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_spectral_band_cost(field, mask),
        log_cost,
        problem,
        nothing;
        contract_kind = :mmf_sum,
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
        problem,
        nothing;
        contract_kind = :mmf_fundamental,
    )
end

"""
    worst_mode_objective(problem; log_cost=false, worst_mode_tau=50.0, name=:worst_mode)

Create the differentiable worst-mode optimization objective. Its scalar cost
is a normalized log-sum-exp proxy over nonzero-energy modes and obeys
`max(leakage) - log(K)/worst_mode_tau ≤ cost ≤ max(leakage)`. Per-mode
artifact reporting uses the true leakage fractions and true maximum instead of
presenting this smooth proxy as a measurement.
"""
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
        problem,
        nothing;
        contract_kind = :mmf_worst_mode,
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
        problem,
        nothing;
        contract_kind = :raman_peak,
    )
end

function temporal_width_objective(problem::FiberFieldProblem;
                                  log_cost::Bool=false,
                                  name::Symbol=:temporal_width)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_temporal_width_cost(field, problem.sim),
        log_cost,
        problem,
        nothing;
        contract_kind = :temporal_width,
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
`phase`, `amplitude`, and `energy` fields. Multimode adjoints require a fully
permutation-symmetric nonlinear coupling tensor; forward-only `propagate`
supports nonsymmetric tensors.
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
    _adjoint_gamma_symmetric(problem.fiber["γ"]) || throw(ArgumentError(
        "fiber adjoint requires a fully permutation-symmetric gamma tensor; " *
        "use propagate(problem) for forward-only nonsymmetric models"))
    physics = SingleModePhasePhysics(problem, SingleModePhaseCache())
    problem_source = _resolved_problem_source(problem)
    return _adjoint_model(
        :spectral_shaper_propagation,
        problem_source;
        run_source = _native_run_source(problem, problem_source),
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

function _execution_metadata_from_problem(problem::FiberFieldProblem)
    recorded = problem.metadata
    any(ismissing, (
        recorded.requested_fiber,
        recorded.requested_pulse,
        recorded.requested_grid,
    )) && throw(ArgumentError(
        "solve(problem, ...) is only available for package-built problems; " *
        "explicit low-level problems must use solve(fiber_model(problem), ...) " *
        "and state their metadata explicitly"))
    _validate_package_problem_snapshot(problem)

    resolved_fiber = Fiber(
        regime = mode_count(problem) == 1 ? :single_mode : :multimode,
        preset = recorded.preset,
        length_m = Float64(problem.fiber["L"]),
        power_w = recorded.requested_fiber.power_w,
        beta_order = Int(problem.sim["β_order"]),
        raman_fraction = recorded.requested_fiber.raman_fraction,
    )
    recorded.requested_fiber == resolved_fiber || throw(ArgumentError(
        "requested fiber metadata disagrees with the resolved problem"))

    resolved_grid = Grid(
        nt = sample_count(problem),
        time_window_ps = Float64(problem.sim["time_window"]),
        policy = :exact,
    )
    return (
        fiber = resolved_fiber,
        pulse = recorded.requested_pulse,
        grid = resolved_grid,
        source_metadata = (
            requested_fiber = recorded.requested_fiber,
            requested_pulse = recorded.requested_pulse,
            requested_grid = recorded.requested_grid,
            resolved_grid = resolved_grid,
            wavelength_m = Float64(problem.sim["λ0"]),
            modes = mode_count(problem),
            raman_response = _raman_response_metadata(problem.fiber),
            construction_sha256 = recorded.construction_sha256,
        ),
    )
end

_resolved_problem_source(problem::FiberFieldProblem) =
    ResolvedProblemSource(problem, _resolved_problem_signature(problem))

function _native_run_source(problem::FiberFieldProblem,
                            problem_source::ResolvedProblemSource)
    recorded = problem.metadata
    any(ismissing, (
        recorded.requested_fiber,
        recorded.requested_pulse,
        recorded.requested_grid,
    )) && return nothing
    source_metadata = _execution_metadata_from_problem(problem).source_metadata
    return NativeRunSource(
        merge(source_metadata, (snapshot_sha256 = problem_source.snapshot_sha256,)),
        problem_source.problem,
        problem_source.snapshot_sha256,
    )
end

"""
    solve(problem, control, objective, initial_coordinates; kwargs...)

Notebook-first convenience path for package-native fiber physics. It builds
`fiber_model(problem)` and delegates to the same native adjoint execution used
by `solve(model, control, objective, initial_coordinates; ...)`.

Package-built problems retain the exact requested Fiber and Pulse plus the
resolved Grid used by the simulation. Metadata overrides are rejected.
Explicit low-level problems use the model-first overload so FiberLab never
invents high-level metadata for researcher-supplied arrays.
"""
function solve(problem::FiberFieldProblem,
               control::AbstractControlMap,
               objective::AbstractFiberObjective,
               initial_coordinates;
               kwargs...)
    forbidden = intersect(
        Set(keys(kwargs)),
        Set((:fiber, :pulse, :grid, :reference_power_w, :source_metadata, :source_problem)),
    )
    isempty(forbidden) || throw(ArgumentError(
        "solve(problem, ...) does not accept metadata overrides: $(sort!(collect(forbidden)))"))
    snapshot = deepcopy(problem)
    metadata = _execution_metadata_from_problem(snapshot)
    return solve(
        fiber_model(snapshot),
        control,
        objective,
        initial_coordinates;
        fiber = metadata.fiber,
        pulse = metadata.pulse,
        grid = metadata.grid,
        kwargs...,
    )
end

function solve(problem::FiberFieldProblem,
               control::AbstractControlMap,
               objective::AbstractFiberObjective;
               kwargs...)
    return solve(problem, control, objective, initial_coordinates(control); kwargs...)
end
