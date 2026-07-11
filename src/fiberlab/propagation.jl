struct _PropagationResultToken end
const _PROPAGATION_RESULT_TOKEN = _PropagationResultToken()

"""Stored, lab-frame samples and sealed numerical evidence from one passive fiber run."""
struct PropagationResult
    problem::FiberFieldProblem
    resolved_sha256::String
    z_m::Vector{Float64}
    spectra::Array{ComplexF64,3}
    input_spectrum::Matrix{ComplexF64}
    output_spectrum::Matrix{ComplexF64}
    evidence_sha256::String
    accepted_steps::Int
    rhs_evaluations::Int

    function PropagationResult(::_PropagationResultToken, problem, resolved_sha256,
                               z_m, spectra, input_spectrum, output_spectrum,
                               evidence_sha256, accepted_steps, rhs_evaluations)
        return new(problem, resolved_sha256, z_m, spectra, input_spectrum,
                   output_spectrum, evidence_sha256, accepted_steps,
                   rhs_evaluations)
    end
end

function _forward_input(problem::FiberFieldProblem, input_spectrum)
    field = Matrix{ComplexF64}(input_spectrum)
    size(field) == size(problem.uω0) || throw(ArgumentError(
        "input spectrum size $(size(field)) does not match $(size(problem.uω0))"))
    all(isfinite, field) || throw(ArgumentError("input spectrum must be finite"))
    norm(field) > 0 || throw(ArgumentError("input spectrum must be nonzero"))
    return field
end

_lab_spectrum(problem, solution, z_m) = Matrix{ComplexF64}(
    cis.(problem.fiber["Dω"] .* z_m) .* solution(z_m)
)

function _forward_propagation(problem::FiberFieldProblem, input_spectrum)
    _validate_package_problem_snapshot(problem)
    input = _forward_input(problem, input_spectrum)
    reltol = Float64(get(problem.fiber, "reltol", 1e-8))
    abstol = Float64(get(problem.fiber, "abstol", 1e-6))
    isfinite(reltol) && reltol > 0 || throw(ArgumentError("reltol must be positive and finite"))
    isfinite(abstol) && abstol > 0 || throw(ArgumentError("abstol must be positive and finite"))
    solver_fiber = copy(problem.fiber)
    solver_fiber["zsave"] = nothing
    solution = solve_disp_mmf(input, solver_fiber, problem.sim)["ode_sol"]
    successful = DifferentialEquations.SciMLBase.successful_retcode(solution)
    length_m = Float64(problem.fiber["L"])
    final_z_m = Float64(last(solution.t))
    successful || error("fiber propagation failed with retcode $(solution.retcode)")
    isapprox(final_z_m, length_m; rtol = 0, atol = 8eps(length_m)) || error(
        "fiber propagation stopped at z=$final_z_m before z=$length_m")
    return (
        output = _lab_spectrum(problem, solution, length_m),
        solution = solution,
    )
end

function _save_positions(saveat, length_m::Float64)
    saveat === nothing && return [0.0, length_m]
    saveat isa AbstractVector || throw(ArgumentError("saveat must be a vector of distances"))
    z_m = Float64.(collect(saveat))
    length(z_m) >= 2 || throw(ArgumentError("saveat must include 0 and the fiber length"))
    all(isfinite, z_m) || throw(ArgumentError("saveat distances must be finite"))
    all(diff(z_m) .> 0) || throw(ArgumentError("saveat distances must be sorted and unique"))
    first(z_m) == 0.0 && last(z_m) == length_m || throw(ArgumentError(
        "saveat must start at 0 and end at the fiber length $length_m"))
    return z_m
end

_propagation_evidence_sha256(resolved_sha256, z_m, spectra, accepted_steps,
                             rhs_evaluations) = bytes2hex(sha256(codeunits(repr((
    resolved_sha256 = resolved_sha256,
    z_m = _array_sha256(z_m),
    spectra = _array_sha256(spectra),
    accepted_steps = accepted_steps,
    rhs_evaluations = rhs_evaluations,
)))))

"""
    propagate(problem; saveat=nothing) -> PropagationResult

Propagate the launch stored in a resolved passive fiber problem. By default the
result stores only input and output spectra. `saveat` may be a sorted, unique
vector containing both `0` and the fiber length. Spectra use `(Nt, M, Nz)` lab-
frame ordering. To use a different launch, construct a new explicit problem.
"""
function propagate(problem::FiberFieldProblem; saveat=nothing)
    _validate_package_problem_snapshot(problem)
    snapshot = deepcopy(problem)
    resolved_sha256 = _resolved_problem_signature(snapshot)
    z_m = _save_positions(saveat, Float64(snapshot.fiber["L"]))
    propagation = _forward_propagation(snapshot, snapshot.uω0)
    spectra = Array{ComplexF64}(undef, sample_count(snapshot), mode_count(snapshot), length(z_m))
    for (index, z) in pairs(z_m)
        spectra[:, :, index] = _lab_spectrum(snapshot, propagation.solution, z)
    end
    _resolved_problem_signature(snapshot) == resolved_sha256 || error(
        "resolved problem changed during propagation")
    input = copy(@view spectra[:, :, 1])
    output = copy(@view spectra[:, :, end])
    isapprox(output, propagation.output; rtol = 1e-12) || error(
        "stored output does not match the solver endpoint")
    stats = propagation.solution.destats
    accepted_steps = hasproperty(stats, :naccept) ?
        Int(stats.naccept) : length(propagation.solution.t) - 1
    rhs_evaluations = hasproperty(stats, :nf) ? Int(stats.nf) : 0
    evidence_sha256 = _propagation_evidence_sha256(
        resolved_sha256, z_m, spectra, accepted_steps, rhs_evaluations)
    return PropagationResult(
        _PROPAGATION_RESULT_TOKEN,
        snapshot,
        resolved_sha256,
        z_m,
        spectra,
        input,
        output,
        evidence_sha256,
        accepted_steps,
        rhs_evaluations,
    )
end

function _propagation_integrity(result::PropagationResult)
    try
        expected_size = (sample_count(result.problem), mode_count(result.problem), length(result.z_m))
        return length(result.z_m) >= 2 &&
            size(result.spectra) == expected_size &&
            all(isfinite, result.z_m) && all(diff(result.z_m) .> 0) &&
            _resolved_problem_signature(result.problem) == result.resolved_sha256 &&
            _propagation_evidence_sha256(
                result.resolved_sha256, result.z_m, result.spectra,
                result.accepted_steps, result.rhs_evaluations,
            ) == result.evidence_sha256 &&
            first(result.z_m) == 0.0 &&
            last(result.z_m) == Float64(result.problem.fiber["L"]) &&
            result.input_spectrum == result.problem.uω0 &&
            result.input_spectrum == result.spectra[:, :, 1] &&
            result.output_spectrum == result.spectra[:, :, end] &&
            result.accepted_steps >= 0 && result.rhs_evaluations >= 0
    catch
        return false
    end
end

function summarize(result::PropagationResult)
    _propagation_integrity(result) || throw(ArgumentError("propagation result was mutated"))
    problem, metadata = result.problem, result.problem.metadata
    return (
        metadata_authority = metadata.construction_sha256 === nothing ?
            :resolved_numerical : :authoritative,
        requested_fiber = metadata.requested_fiber,
        requested_pulse = metadata.requested_pulse,
        requested_grid = metadata.requested_grid,
        resolved_grid = Grid(
            nt = sample_count(problem),
            time_window_ps = Float64(problem.sim["time_window"]),
            policy = :exact,
        ),
        length_m = Float64(problem.fiber["L"]),
        wavelength_m = Float64(problem.sim["λ0"]),
        modes = mode_count(problem),
        raman_response = _raman_response_metadata(problem.fiber),
        construction_sha256 = metadata.construction_sha256,
        numerical_sha256 = _numerical_problem_signature(problem),
        resolved_sha256 = result.resolved_sha256,
        evidence_sha256 = result.evidence_sha256,
        solver = :Tsit5,
        reltol = Float64(get(problem.fiber, "reltol", 1e-8)),
        abstol = Float64(get(problem.fiber, "abstol", 1e-6)),
        retcode = "Success",
    )
end

function _edge_fraction(power)
    edge_samples = max(1, floor(Int, 0.05length(power)))
    total = sum(power)
    total > 0 || throw(ArgumentError("field power must be nonzero"))
    return Float64((sum(@view power[1:edge_samples]) +
                    sum(@view power[end-edge_samples+1:end])) / total)
end

function _photon_number(spectrum, sim)
    omega = fftshift(abs.(sim["ωs"]))
    return Float64(sim["Δt"] * sum(abs2.(spectrum) ./ reshape(omega, :, 1)))
end

function _field_metrics(spectrum, sim)
    temporal = fft(spectrum, 1)
    temporal_power = vec(sum(abs2, temporal; dims = 2))
    mode_energy = vec(sum(abs2, temporal; dims = 1)) .* Float64(sim["Δt"])
    spectral_power = fftshift(vec(sum(abs2, spectrum; dims = 2)))
    return (
        energy_pj = Float64(sum(mode_energy)),
        mode_energy_pj = Float64.(mode_energy),
        peak_power_w = Float64(maximum(temporal_power)),
        temporal_edge_fraction = _edge_fraction(temporal_power),
        spectral_edge_fraction = _edge_fraction(spectral_power),
        photon_number = _photon_number(spectrum, sim),
    )
end

function _propagation_metrics(result::PropagationResult)
    samples = [_field_metrics(@view(result.spectra[:, :, index]), result.problem.sim)
               for index in axes(result.spectra, 3)]
    input, output = first(samples), last(samples)
    energy_drift = [sample.energy_pj / input.energy_pj - 1 for sample in samples]
    photon_drift = [sample.photon_number / input.photon_number - 1 for sample in samples]
    pulse = result.problem.metadata.requested_pulse
    launch_samples = ismissing(pulse) ? missing :
        pulse.fwhm_s * 1e12 / Float64(result.problem.sim["Δt"])
    return (
        samples = sample_count(result.problem),
        modes = mode_count(result.problem),
        saved_positions = length(result.z_m),
        length_m = Float64(result.problem.fiber["L"]),
        time_window_ps = Float64(result.problem.sim["time_window"]),
        delta_t_ps = Float64(result.problem.sim["Δt"]),
        frequency_spacing_thz = 1 / Float64(result.problem.sim["time_window"]),
        input_energy_pj = input.energy_pj,
        output_energy_pj = output.energy_pj,
        input_mode_energy_pj = input.mode_energy_pj,
        output_mode_energy_pj = output.mode_energy_pj,
        relative_energy_change = Float64(last(energy_drift)),
        max_relative_energy_change = Float64(maximum(abs, energy_drift)),
        input_peak_power_w = input.peak_power_w,
        output_peak_power_w = output.peak_power_w,
        max_temporal_edge_fraction = maximum(sample.temporal_edge_fraction for sample in samples),
        max_spectral_edge_fraction = maximum(sample.spectral_edge_fraction for sample in samples),
        max_photon_number_drift = Float64(maximum(abs, photon_drift)),
        launch_samples_per_fwhm = launch_samples,
        retcode = "Success",
        accepted_steps = result.accepted_steps,
        rhs_evaluations = result.rhs_evaluations,
    )
end

function metrics(result::PropagationResult)
    _propagation_integrity(result) || throw(ArgumentError("propagation result was mutated"))
    return _propagation_metrics(result)
end

function verify(result::PropagationResult;
                temporal_edge_limit::Real=1e-3,
                spectral_edge_limit::Real=1e-3,
                min_launch_samples_per_fwhm::Real=8.0,
                require_launch_sampling::Bool=false,
                photon_drift_limit::Union{Nothing,Real}=1e-4,
                energy_drift_limit::Union{Nothing,Real}=nothing)
    isfinite(temporal_edge_limit) && 0 <= temporal_edge_limit <= 1 || throw(ArgumentError(
        "temporal_edge_limit must be finite and lie in [0, 1]"))
    isfinite(spectral_edge_limit) && 0 <= spectral_edge_limit <= 1 || throw(ArgumentError(
        "spectral_edge_limit must be finite and lie in [0, 1]"))
    isfinite(min_launch_samples_per_fwhm) && min_launch_samples_per_fwhm > 0 ||
        throw(ArgumentError("min_launch_samples_per_fwhm must be positive and finite"))
    photon_drift_limit === nothing ||
        (isfinite(photon_drift_limit) && photon_drift_limit >= 0) || throw(ArgumentError(
            "photon_drift_limit must be nonnegative and finite"))
    energy_drift_limit === nothing ||
        (isfinite(energy_drift_limit) && energy_drift_limit >= 0) || throw(ArgumentError(
            "energy_drift_limit must be nonnegative and finite"))
    integrity_ok = _propagation_integrity(result)
    integrity_ok || return (
        pass = false, integrity_ok = false, solver_success = missing,
        finite_fields = missing, temporal_edges_contained = missing,
        spectral_edges_contained = missing, launch_sampling_ok = missing,
        photon_number_conserved = missing, energy_change_acceptable = missing,
        max_temporal_edge_fraction = missing,
        max_spectral_edge_fraction = missing,
        launch_samples_per_fwhm = missing,
        max_photon_number_drift = missing,
        max_relative_energy_change = missing,
    )
    evidence = _propagation_metrics(result)
    finite_fields = all(isfinite, result.spectra)
    temporal_ok = evidence.max_temporal_edge_fraction <= temporal_edge_limit
    spectral_ok = evidence.max_spectral_edge_fraction <= spectral_edge_limit
    sampling_ok = ismissing(evidence.launch_samples_per_fwhm) ? missing :
        evidence.launch_samples_per_fwhm >= min_launch_samples_per_fwhm
    sampling_gate = sampling_ok !== false && (!require_launch_sampling || sampling_ok === true)
    photon_ok = photon_drift_limit === nothing ? missing :
        evidence.max_photon_number_drift <= photon_drift_limit
    energy_ok = energy_drift_limit === nothing ? missing :
        evidence.max_relative_energy_change <= energy_drift_limit
    pass = finite_fields && temporal_ok && spectral_ok && sampling_gate &&
        photon_ok !== false && energy_ok !== false
    return (
        pass = pass,
        integrity_ok = true,
        solver_success = true,
        finite_fields = finite_fields,
        temporal_edges_contained = temporal_ok,
        spectral_edges_contained = spectral_ok,
        launch_sampling_ok = sampling_ok,
        photon_number_conserved = photon_ok,
        energy_change_acceptable = energy_ok,
        max_temporal_edge_fraction = evidence.max_temporal_edge_fraction,
        max_spectral_edge_fraction = evidence.max_spectral_edge_fraction,
        launch_samples_per_fwhm = evidence.launch_samples_per_fwhm,
        max_photon_number_drift = evidence.max_photon_number_drift,
        max_relative_energy_change = evidence.max_relative_energy_change,
    )
end
