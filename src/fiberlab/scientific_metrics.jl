"""Metrics used to separate numerical optimization from scientific attribution."""

"""
    raman_counterfactual_contract(on, off; allow_response_shape_change=false)

Check that two resolved problems form a matched delayed-response
counterfactual. Launch, grid, dispersion, nonlinearity, length, and solver
tolerances must match; the first problem must have a nonzero Raman fraction and
the second zero. Response model and time constants must also match unless an
explicit response-shape negative control opts out.
"""
function raman_counterfactual_contract(on::FiberFieldProblem,
                                       off::FiberFieldProblem;
                                       allow_response_shape_change::Bool=false)
    on_raman = _raman_response_metadata(on.fiber)
    off_raman = _raman_response_metadata(off.fiber)
    ismissing(on_raman) && throw(ArgumentError("Raman-on problem lacks response provenance"))
    ismissing(off_raman) && throw(ArgumentError("Raman-off problem lacks response provenance"))
    checks = (
        launch = on.uω0 == off.uω0,
        simulation_grid = on.sim == off.sim,
        dispersion = on.fiber["Dω"] == off.fiber["Dω"],
        nonlinearity = on.fiber["γ"] == off.fiber["γ"],
        length = on.fiber["L"] == off.fiber["L"],
        solver_tolerances = all(get(on.fiber, key, default) ==
            get(off.fiber, key, default) for (key, default) in
            (("reltol", 1e-8), ("abstol", 1e-6))),
        raman_on = on_raman.fraction > 0,
        raman_off = off_raman.fraction == 0,
        response_model = on_raman.model == off_raman.model,
        response_tau1 = on_raman.tau1_fs == off_raman.tau1_fs,
        response_tau2 = on_raman.tau2_fs == off_raman.tau2_fs,
    )
    response_names = (:response_model, :response_tau1, :response_tau2)
    core_match = all(value for (name, value) in pairs(checks)
                     if name ∉ response_names)
    response_shape_matched = all(getproperty(checks, name) for name in response_names)
    return (
        pass = core_match && (allow_response_shape_change || response_shape_matched),
        response_shape_matched = response_shape_matched,
        declared_response_shape_control = allow_response_shape_change,
        checks = checks,
    )
end

function _finite_spectrum(field, nt::Int, label::AbstractString)
    spectrum = field isa AbstractVector ?
        reshape(ComplexF64.(collect(field)), :, 1) : Matrix{ComplexF64}(field)
    size(spectrum, 1) == nt || throw(ArgumentError(
        "$label has $(size(spectrum, 1)) rows; expected Nt=$nt"))
    all(isfinite, spectrum) || throw(ArgumentError("$label must be finite"))
    sum(abs2, spectrum) > 0 || throw(ArgumentError("$label must be nonzero"))
    return spectrum
end

function _circular_offsets(nt::Int, center::Int)
    raw = collect(1:nt) .- center
    return mod.(raw .+ nt ÷ 2, nt) .- nt ÷ 2
end

function _circular_rms_duration(power::Vector{Float64}, delta_t_ps::Float64)
    nt = length(power)
    angles = 2π .* collect(0:nt-1) ./ nt
    resultant = sum(power .* cis.(angles))
    center_angle = abs(resultant) > 100eps(Float64) * sum(power) ?
        angle(resultant) : angles[argmax(power)]
    offsets = angle.(cis.(angles .- center_angle)) .* (nt * delta_t_ps / (2π))
    return sqrt(sum(power .* offsets .^ 2) / sum(power))
end

function _main_lobe_fraction(power::Vector{Float64}, half_width_samples::Int)
    offsets = abs.(_circular_offsets(length(power), argmax(power)))
    return sum(power[offsets .<= half_width_samples]) / sum(power)
end

function _reference_main_lobe(power::Vector{Float64}, target::Float64)
    offsets = abs.(_circular_offsets(length(power), argmax(power)))
    order = sortperm(offsets)
    cumulative = cumsum(power[order]) ./ sum(power)
    index = findfirst(>=(target), cumulative)
    half_width = offsets[order[something(index, lastindex(order))]]
    fraction = _main_lobe_fraction(power, half_width)
    return Int(half_width), Float64(fraction)
end

"""
    pulse_quality_metrics(reference_spectrum, candidate_spectrum, sim;
                          main_lobe_reference_fraction=0.9)

Compare two launch pulses at equal sampling. RMS duration is shift-invariant on
the periodic grid. The main-lobe window is the smallest symmetric window about
the reference peak containing the requested reference-energy fraction; the same
window width is recentered on the candidate peak. Energy, peak, RMS duration,
and main-lobe ratios are all reported because any one can hide satellite-pulse
or pulse-stretching degradation.
"""
function pulse_quality_metrics(reference_spectrum,
                               candidate_spectrum,
                               sim;
                               main_lobe_reference_fraction::Real=0.9)
    nt = Int(sim["Nt"])
    delta_t_ps = Float64(sim["Δt"])
    isfinite(delta_t_ps) && delta_t_ps > 0 || throw(ArgumentError(
        "simulation Δt must be positive and finite"))
    target = Float64(main_lobe_reference_fraction)
    0 < target < 1 || throw(ArgumentError(
        "main_lobe_reference_fraction must lie strictly between 0 and 1"))
    reference = _finite_spectrum(reference_spectrum, nt, "reference spectrum")
    candidate = _finite_spectrum(candidate_spectrum, nt, "candidate spectrum")
    size(reference) == size(candidate) || throw(ArgumentError(
        "reference and candidate spectra must have identical shapes"))

    reference_power = Float64.(vec(sum(abs2, fft(reference, 1); dims=2)))
    candidate_power = Float64.(vec(sum(abs2, fft(candidate, 1); dims=2)))
    reference_energy = sum(reference_power) * delta_t_ps
    candidate_energy = sum(candidate_power) * delta_t_ps
    reference_rms = _circular_rms_duration(reference_power, delta_t_ps)
    candidate_rms = _circular_rms_duration(candidate_power, delta_t_ps)
    half_width, reference_lobe = _reference_main_lobe(reference_power, target)
    candidate_lobe = _main_lobe_fraction(candidate_power, half_width)

    return (
        reference_energy = Float64(reference_energy),
        candidate_energy = Float64(candidate_energy),
        energy_ratio = Float64(candidate_energy / reference_energy),
        reference_rms_duration_ps = Float64(reference_rms),
        candidate_rms_duration_ps = Float64(candidate_rms),
        rms_duration_ratio = Float64(candidate_rms / reference_rms),
        reference_peak_power = Float64(maximum(reference_power)),
        candidate_peak_power = Float64(maximum(candidate_power)),
        peak_power_ratio = Float64(maximum(candidate_power) / maximum(reference_power)),
        main_lobe_half_width_ps = Float64(half_width * delta_t_ps),
        main_lobe_reference_fraction = reference_lobe,
        main_lobe_candidate_fraction = Float64(candidate_lobe),
        main_lobe_energy_ratio = Float64(candidate_lobe / reference_lobe),
    )
end

"""
    pulse_quality_check(metrics; max_rms_duration_ratio, min_peak_power_ratio,
                        min_main_lobe_energy_ratio, energy_ratio_tolerance=1e-6)

Apply explicit, predeclared launch-quality limits. No default scientific
thresholds are supplied because acceptable pulse quality belongs to the
experiment, not the software.
"""
function pulse_quality_check(metrics;
                             max_rms_duration_ratio::Real,
                             min_peak_power_ratio::Real,
                             min_main_lobe_energy_ratio::Real,
                             energy_ratio_tolerance::Real=1e-6)
    max_rms = Float64(max_rms_duration_ratio)
    min_peak = Float64(min_peak_power_ratio)
    min_lobe = Float64(min_main_lobe_energy_ratio)
    energy_tolerance = Float64(energy_ratio_tolerance)
    isfinite(max_rms) && max_rms >= 1 || throw(ArgumentError(
        "max_rms_duration_ratio must be finite and at least 1"))
    isfinite(min_peak) && 0 <= min_peak <= 1 || throw(ArgumentError(
        "min_peak_power_ratio must lie in [0, 1]"))
    isfinite(min_lobe) && 0 <= min_lobe <= 1 || throw(ArgumentError(
        "min_main_lobe_energy_ratio must lie in [0, 1]"))
    isfinite(energy_tolerance) && energy_tolerance >= 0 || throw(ArgumentError(
        "energy_ratio_tolerance must be nonnegative and finite"))

    checks = (
        energy_preserved = abs(Float64(metrics.energy_ratio) - 1) <= energy_tolerance,
        rms_duration = Float64(metrics.rms_duration_ratio) <= max_rms,
        peak_power = Float64(metrics.peak_power_ratio) >= min_peak,
        main_lobe_energy = Float64(metrics.main_lobe_energy_ratio) >= min_lobe,
    )
    return (
        pass = all(values(checks)),
        checks = checks,
        thresholds = (
            max_rms_duration_ratio = max_rms,
            min_peak_power_ratio = min_peak,
            min_main_lobe_energy_ratio = min_lobe,
            energy_ratio_tolerance = energy_tolerance,
        ),
    )
end

"""
    frequency_band_mask(sim_or_problem, (lower_thz, upper_thz))

Build an inclusive finite frequency-band mask in raw FFT/solver order. A finite
band is preferable to a cumulative red tail when a particular physical feature
is being interpreted.
"""
function frequency_band_mask(sim::AbstractDict, interval::Tuple{<:Real,<:Real})
    lower, upper = Float64.(interval)
    isfinite(lower) && isfinite(upper) && lower < upper || throw(ArgumentError(
        "frequency band must contain finite lower < upper bounds"))
    nt = Int(sim["Nt"])
    delta_t_ps = Float64(sim["Δt"])
    frequency_thz = FFTW.fftfreq(nt, 1 / delta_t_ps)
    mask = Vector{Bool}((lower .<= frequency_thz) .& (frequency_thz .<= upper))
    any(mask) || throw(ArgumentError(
        "frequency band [$lower, $upper] THz selects no bins on this grid"))
    return mask
end

frequency_band_mask(problem::FiberFieldProblem, interval::Tuple{<:Real,<:Real}) =
    frequency_band_mask(problem.sim, interval)

function _band_metrics(field::Matrix{ComplexF64},
                       reference_energy::Float64,
                       mask::Vector{Bool})
    band_energy = sum(abs2, @view field[mask, :])
    total_energy = sum(abs2, field)
    return (
        band_energy = Float64(band_energy),
        total_energy = Float64(total_energy),
        fraction = Float64(band_energy / total_energy),
        relative_band_energy = Float64(band_energy / reference_energy),
        relative_total_energy = Float64(total_energy / reference_energy),
    )
end

"""
    counterfactual_band_metrics(raman_on, raman_off, launch;
                                red_mask, blue_mask, epsilon=1e-30)

Report visible Raman-on/off component metrics on matched finite red and blue
bands. `model_attributed_*` values are counterfactual differences between the
declared models, not direct experimental measurements or a unique decomposition
of nonlinear energy transfer.
"""
function counterfactual_band_metrics(raman_on,
                                     raman_off,
                                     launch;
                                     red_mask,
                                     blue_mask,
                                     epsilon::Real=1e-30)
    nt = size(launch, 1)
    launch_field = _finite_spectrum(launch, nt, "launch spectrum")
    on_field = _finite_spectrum(raman_on, nt, "Raman-on spectrum")
    off_field = _finite_spectrum(raman_off, nt, "Raman-off spectrum")
    size(on_field) == size(off_field) == size(launch_field) || throw(ArgumentError(
        "launch, Raman-on, and Raman-off spectra must have identical shapes"))
    red = Vector{Bool}(red_mask)
    blue = Vector{Bool}(blue_mask)
    length(red) == nt && length(blue) == nt || throw(ArgumentError(
        "band masks must have one entry per frequency sample"))
    any(red) && any(blue) || throw(ArgumentError("red and blue masks must be nonempty"))
    !any(red .& blue) || throw(ArgumentError("red and blue masks must be disjoint"))
    floor_value = Float64(epsilon)
    isfinite(floor_value) && floor_value > 0 || throw(ArgumentError(
        "epsilon must be positive and finite"))

    reference_energy = Float64(sum(abs2, launch_field))
    red_on = _band_metrics(on_field, reference_energy, red)
    red_off = _band_metrics(off_field, reference_energy, red)
    blue_on = _band_metrics(on_field, reference_energy, blue)
    blue_off = _band_metrics(off_field, reference_energy, blue)
    red_log_ratio_db = 10log10(
        (red_on.relative_band_energy + floor_value) /
        (red_off.relative_band_energy + floor_value),
    )
    asymmetry_on = red_on.relative_band_energy - blue_on.relative_band_energy
    asymmetry_off = red_off.relative_band_energy - blue_off.relative_band_energy

    return (
        red = (on = red_on, off = red_off),
        blue = (on = blue_on, off = blue_off),
        red_log_ratio_db = Float64(red_log_ratio_db),
        model_attributed_red_excess = Float64(
            red_on.relative_band_energy - red_off.relative_band_energy),
        model_attributed_asymmetry = Float64(asymmetry_on - asymmetry_off),
        asymmetry = (on = Float64(asymmetry_on), off = Float64(asymmetry_off)),
        epsilon = floor_value,
    )
end

function _spectrum_summary(field::Matrix{ComplexF64}, reference_energy::Float64,
                           frequency_thz::Vector{Float64})
    bin_energy = vec(sum(abs2, field; dims=2))
    total_energy = sum(bin_energy)
    centroid_thz = sum(frequency_thz .* bin_energy) / total_energy
    return (
        total_energy = Float64(total_energy),
        relative_energy = Float64(total_energy / reference_energy),
        centroid_thz = Float64(centroid_thz),
    )
end

"""
    counterfactual_spectrum_metrics(raman_on, raman_off, launch, sim_or_problem)

Compare matched full-spectrum outputs. The centroid and total-energy differences
are model counterfactuals, not a unique decomposition of measured Raman transfer.
Unlike a selected-band metric, these diagnostics cannot improve merely by moving
the model difference outside a declared mask.
"""
function counterfactual_spectrum_metrics(raman_on, raman_off, launch,
                                         sim::AbstractDict)
    nt = Int(sim["Nt"])
    launch_field = _finite_spectrum(launch, nt, "launch spectrum")
    on_field = _finite_spectrum(raman_on, nt, "Raman-on spectrum")
    off_field = _finite_spectrum(raman_off, nt, "Raman-off spectrum")
    size(on_field) == size(off_field) == size(launch_field) || throw(ArgumentError(
        "launch, Raman-on, and Raman-off spectra must have identical shapes"))
    frequency_thz = Float64.(FFTW.fftfreq(nt, 1 / Float64(sim["Δt"])))
    reference_energy = Float64(sum(abs2, launch_field))
    on = _spectrum_summary(on_field, reference_energy, frequency_thz)
    off = _spectrum_summary(off_field, reference_energy, frequency_thz)
    return (
        on = on,
        off = off,
        model_attributed_centroid_shift_thz = Float64(
            on.centroid_thz - off.centroid_thz),
        model_attributed_energy_change = Float64(
            on.relative_energy - off.relative_energy),
    )
end


counterfactual_spectrum_metrics(raman_on, raman_off, launch,
                                problem::FiberFieldProblem) =
    counterfactual_spectrum_metrics(raman_on, raman_off, launch, problem.sim)

function _scientific_band_mask(problem::FiberFieldProblem, band, label::AbstractString)
    mask = band isa Tuple{<:Real,<:Real} ?
        frequency_band_mask(problem, band) : Vector{Bool}(band)
    length(mask) == sample_count(problem) || throw(ArgumentError(
        "$label must have one entry per frequency sample"))
    any(mask) || throw(ArgumentError("$label must select at least one frequency bin"))
    return mask
end

function _field_launch_normalized_cost(field, weights::Vector{Float64},
                                       launch_energy::Float64)
    size(field, 1) == length(weights) || throw(ArgumentError(
        "field rows $(size(field, 1)) do not match spectral weights"))
    all(isfinite, field) || throw(ArgumentError("field must be finite"))
    cost = sum(weights .* abs2.(field)) / launch_energy
    terminal = field .* weights ./ launch_energy
    return Float64(cost), terminal
end

function _field_spectral_centroid_cost(field, frequency_thz::Vector{Float64})
    size(field, 1) == length(frequency_thz) || throw(ArgumentError(
        "field rows $(size(field, 1)) do not match the frequency grid"))
    all(isfinite, field) || throw(ArgumentError("field must be finite"))
    bin_energy = vec(sum(abs2, field; dims=2))
    total_energy = sum(bin_energy)
    total_energy > 0 || throw(ArgumentError("field must have nonzero spectral energy"))
    centroid = sum(frequency_thz .* bin_energy) / total_energy
    terminal = field .* (frequency_thz .- centroid) ./ total_energy
    return Float64(centroid), terminal
end

"""
    spectral_band_energy_objective(problem, band; name=:spectral_band_energy)

Create a source-bound objective for energy in a finite spectral band, normalized
by the resolved problem's launch energy. `band` is either a `(lower, upper)` THz
interval or a Boolean mask in raw FFT order. The fixed launch normalization is
deliberate: it keeps matched, phase-only scenarios on one physical scale rather
than renormalizing away changes in output energy.
"""
function spectral_band_energy_objective(problem::FiberFieldProblem, band;
                                        name::Symbol=:spectral_band_energy)
    mask = _scientific_band_mask(problem, band, "spectral band")
    launch_energy = Float64(sum(abs2, problem.uω0))
    weights = Float64.(mask)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_launch_normalized_cost(field, weights, launch_energy),
        false,
        problem,
        (:spectrum_before_after, :convergence_trace);
        contract_kind = name,
    )
end

"""
    spectral_asymmetry_objective(problem, red_band, blue_band;
                                 name=:spectral_asymmetry)

Create the signed, launch-normalized spectral asymmetry
`(E_red - E_blue) / E_launch`. Bands may be THz intervals or raw-order Boolean
masks and must be disjoint. The objective is intentionally mechanism-neutral;
Raman attribution requires comparing matched Raman-on and Raman-off scenarios.
"""
function spectral_asymmetry_objective(problem::FiberFieldProblem,
                                      red_band,
                                      blue_band;
                                      name::Symbol=:spectral_asymmetry)
    red = _scientific_band_mask(problem, red_band, "red band")
    blue = _scientific_band_mask(problem, blue_band, "blue band")
    any(red .& blue) && throw(ArgumentError("red and blue bands must be disjoint"))
    launch_energy = Float64(sum(abs2, problem.uω0))
    weights = Float64.(red) .- Float64.(blue)
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_launch_normalized_cost(field, weights, launch_energy),
        false,
        problem,
        (:spectrum_before_after, :convergence_trace);
        contract_kind = name,
    )
end

"""
    spectral_centroid_objective(problem; name=:spectral_centroid)

Create a source-bound objective for the full-spectrum energy centroid in THz
relative to the carrier. Pair matched model scenarios and aggregate their
centroid difference to study a model-attributed spectral shift.
"""
function spectral_centroid_objective(problem::FiberFieldProblem;
                                     name::Symbol=:spectral_centroid)
    frequency_thz = Float64.(FFTW.fftfreq(
        sample_count(problem),
        1 / Float64(problem.sim["Δt"]),
    ))
    return _field_objective_from_cost_adjoint(
        name,
        field -> _field_spectral_centroid_cost(field, frequency_thz),
        false,
        problem,
        (:spectrum_before_after, :convergence_trace);
        contract_kind = name,
    )
end
