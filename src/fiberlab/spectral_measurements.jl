using CSV

const _C_NM_THz = 299792.458
const _OSA_SEMANTICS = (:power_dbm_in_rbw, :relative_power_db)
const _SPECTRUM_DISPLAY_FLOOR_DB = -60.0
const _OSA_COMPARISON_POLICY = (
    observation=:assumed_gaussian_wavelength_rbw,
    kernel_truncation_sigma=4.0,
    kernel_captured_mass=0.9999366575163338,
    simulation_spacing_per_rbw_limit=1 / 3,
    measurement_spacing_per_rbw_limit=1 / 2,
    temporal_edge_limit=1e-3,
    spectral_edge_limit=1e-3,
    min_launch_samples_per_fwhm=8.0,
    require_launch_sampling=false,
    photon_drift_limit=1e-4,
    energy_drift_limit=nothing,
    normalization=:independent_area,
    axis_shift_nm=0.0,
    claim=:shape_only,
)

struct _MeasuredSpectrumToken end
const _MEASURED_SPECTRUM_TOKEN = _MeasuredSpectrumToken()

"""Authoritative OSA samples plus explicit acquisition and source provenance."""
struct MeasuredSpectrum
    wavelength_nm::Vector{Float64}
    values_db::Vector{Float64}
    value_semantics::Symbol
    resolution_bandwidth_nm::Float64
    noise_floor_db::Union{Nothing,Float64}
    instrument::String
    acquired_at::String
    axis_order_original::Symbol
    source_path::Union{Nothing,String}
    source_sha256::Union{Nothing,String}
    metadata::Dict{String,String}
    measurement_sha256::String

    function MeasuredSpectrum(::_MeasuredSpectrumToken, wavelength_nm, values_db,
                              value_semantics, rbw_nm, noise_floor_db, instrument,
                              acquired_at, axis_order, source_path, source_sha256,
                              metadata, measurement_sha256)
        new(wavelength_nm, values_db, value_semantics, rbw_nm, noise_floor_db,
            instrument, acquired_at, axis_order, source_path, source_sha256,
            metadata, measurement_sha256)
    end
end

_metadata(metadata) = metadata isa AbstractDict ?
    Dict{String,String}(string(k) => string(v) for (k, v) in metadata) :
    throw(ArgumentError("metadata must be a dictionary"))
_bytes_sha256(bytes) = bytes2hex(sha256(bytes))
_file_sha256(path) = _bytes_sha256(read(path))

function _measurement_sha256(wavelength, values, semantics, rbw, floor_db,
                             instrument, acquired_at, order, source_sha, metadata)
    payload = (
        wavelength_nm=_array_sha256(wavelength), values_db=_array_sha256(values),
        value_semantics=semantics, resolution_bandwidth_nm=rbw,
        noise_floor_db=floor_db, instrument=instrument, acquired_at=acquired_at,
        axis_order_original=order, source_sha256=source_sha,
        metadata=sort!(collect(metadata); by=first),
    )
    bytes2hex(sha256(codeunits(repr(payload))))
end

function _ordered_spectrum(wavelength_nm, values_db)
    wavelength, values = Float64.(collect(wavelength_nm)), Float64.(collect(values_db))
    length(wavelength) == length(values) >= 2 || throw(ArgumentError(
        "OSA wavelength and value columns must have the same length of at least two"))
    all(isfinite, wavelength) && all(>(0), wavelength) || throw(ArgumentError(
        "OSA wavelengths must be positive and finite"))
    all(isfinite, values) || throw(ArgumentError("OSA values must be finite"))
    steps = diff(wavelength)
    all(>(0), steps) && return wavelength, values, :ascending
    all(<(0), steps) && return reverse(wavelength), reverse(values), :descending
    throw(ArgumentError("OSA wavelengths must be strictly monotonic and unique"))
end

function _linear_power(values_db, semantics)
    semantics in _OSA_SEMANTICS || throw(ArgumentError(
        "value_semantics must be :power_dbm_in_rbw or :relative_power_db"))
    scale = semantics == :power_dbm_in_rbw ? 1e-3 : 1.0
    values = scale .* 10.0 .^ (values_db ./ 10.0)
    all(isfinite, values) && all(>(0), values) || throw(ArgumentError(
        "OSA dB values must map to finite positive linear power"))
    values
end

_linear_power(measurement::MeasuredSpectrum) =
    _linear_power(measurement.values_db, measurement.value_semantics)
_censor_mask(measurement::MeasuredSpectrum) = measurement.noise_floor_db === nothing ?
    falses(length(measurement.values_db)) :
    BitVector(measurement.values_db .<= measurement.noise_floor_db)

function _build_measured_spectrum(wavelength_nm, values_db;
                                  value_semantics, resolution_bandwidth_nm,
                                  noise_floor_db, instrument, acquired_at,
                                  metadata=Dict{String,String}(),
                                  source_path=nothing, source_sha256=nothing)
    wavelength, values, order = _ordered_spectrum(wavelength_nm, values_db)
    semantics = Symbol(value_semantics)
    _linear_power(values, semantics)
    rbw = Float64(resolution_bandwidth_nm)
    isfinite(rbw) && rbw > 0 || throw(ArgumentError(
        "resolution_bandwidth_nm must be positive and finite"))
    floor_db = noise_floor_db === nothing ? nothing : Float64(noise_floor_db)
    floor_db === nothing || isfinite(floor_db) || throw(ArgumentError(
        "noise_floor_db must be finite or nothing (explicitly unknown)"))
    instrument_text, acquired_text = strip(String(instrument)), strip(String(acquired_at))
    isempty(instrument_text) && throw(ArgumentError("instrument must be recorded"))
    isempty(acquired_text) && throw(ArgumentError("acquired_at must be recorded"))
    meta = _metadata(metadata)
    record_sha = _measurement_sha256(
        wavelength, values, semantics, rbw, floor_db, instrument_text,
        acquired_text, order, source_sha256, meta)
    MeasuredSpectrum(
        _MEASURED_SPECTRUM_TOKEN, copy(wavelength), copy(values), semantics, rbw,
        floor_db, instrument_text, acquired_text, order, source_path,
        source_sha256, copy(meta), record_sha)
end

"""
    MeasuredSpectrum(wavelength_nm, values_db; kwargs...)

Create a vacuum-wavelength OSA trace. Values must be either dBm measured in the
declared RBW (`:power_dbm_in_rbw`) or relative power dB
(`:relative_power_db`). The RBW is treated as the FWHM of an assumed Gaussian
intensity response. `noise_floor_db=nothing` explicitly means unknown.
"""
MeasuredSpectrum(wavelength_nm, values_db; value_semantics,
                 resolution_bandwidth_nm, noise_floor_db, instrument,
                 acquired_at, metadata=Dict{String,String}()) =
    _build_measured_spectrum(
        wavelength_nm, values_db; value_semantics, resolution_bandwidth_nm,
        noise_floor_db, instrument, acquired_at, metadata)

function _csv_column(rows, column, path)
    isempty(rows) && throw(ArgumentError("OSA CSV is empty: $path"))
    name = Symbol(column)
    name in propertynames(first(rows)) || throw(ArgumentError(
        "OSA CSV has no column `$(column)`"))
    map(rows) do row
        raw = getproperty(row, name)
        raw === missing && throw(ArgumentError("OSA CSV column `$(column)` contains missing data"))
        value = try
            raw isa Real ? Float64(raw) : parse(Float64, String(raw))
        catch
            throw(ArgumentError("OSA CSV column `$(column)` must be numeric"))
        end
        isfinite(value) || throw(ArgumentError("OSA CSV column `$(column)` must be finite"))
        value
    end
end

"""Load explicitly selected OSA CSV columns from one hashed byte snapshot."""
function load_osa_spectrum(path::AbstractString; wavelength_column, value_column,
                           value_semantics, resolution_bandwidth_nm,
                           noise_floor_db, instrument, acquired_at,
                           delimiter::Char=',', metadata=Dict{String,String}())
    source = abspath(String(path))
    isfile(source) || throw(ArgumentError("OSA CSV does not exist: $source"))
    bytes = read(source)
    rows = collect(CSV.File(IOBuffer(bytes); delim=delimiter))
    wavelength = _csv_column(rows, wavelength_column, source)
    values = _csv_column(rows, value_column, source)
    meta = _metadata(metadata)
    meta["wavelength_column"], meta["value_column"] =
        string(wavelength_column), string(value_column)
    meta["delimiter"] = string(delimiter)
    _build_measured_spectrum(
        wavelength, values; value_semantics, resolution_bandwidth_nm,
        noise_floor_db, instrument, acquired_at, metadata=meta,
        source_path=source, source_sha256=_bytes_sha256(bytes))
end

function _measurement_integrity(measurement)
    try
        wavelength, values, order = _ordered_spectrum(
            measurement.wavelength_nm, measurement.values_db)
        order == :ascending || return false
        measurement.axis_order_original in (:ascending, :descending) || return false
        _linear_power(values, measurement.value_semantics)
        expected = _measurement_sha256(
            wavelength, values, measurement.value_semantics,
            measurement.resolution_bandwidth_nm, measurement.noise_floor_db,
            measurement.instrument, measurement.acquired_at,
            measurement.axis_order_original, measurement.source_sha256,
            measurement.metadata)
        expected == measurement.measurement_sha256
    catch
        false
    end
end

function verify(measurement::MeasuredSpectrum)
    integrity = _measurement_integrity(measurement)
    source_available = measurement.source_path === nothing ? missing : isfile(measurement.source_path)
    source_matches = measurement.source_path === nothing ? missing :
        (source_available && _file_sha256(measurement.source_path) == measurement.source_sha256)
    (pass=integrity && (ismissing(source_matches) || source_matches), integrity,
     source_available, source_matches)
end

function summarize(measurement::MeasuredSpectrum)
    _measurement_integrity(measurement) || throw(ArgumentError("measured spectrum was mutated"))
    censored = measurement.noise_floor_db === nothing ? missing : count(_censor_mask(measurement))
    (
        points=length(measurement.wavelength_nm),
        wavelength_range_nm=extrema(measurement.wavelength_nm),
        value_semantics=measurement.value_semantics,
        resolution_bandwidth_nm=measurement.resolution_bandwidth_nm,
        noise_floor_db=measurement.noise_floor_db, censored_points=censored,
        instrument=measurement.instrument, acquired_at=measurement.acquired_at,
        axis_order_original=measurement.axis_order_original,
        source_authority=measurement.source_path === nothing ? :in_memory : :file_sha256,
        source_path=measurement.source_path, source_sha256=measurement.source_sha256,
        measurement_sha256=measurement.measurement_sha256,
    )
end

_trapz(x, y) = length(x) == length(y) >= 2 ?
    sum((x[i + 1] - x[i]) * (y[i + 1] + y[i]) / 2 for i in 1:length(x)-1) :
    throw(ArgumentError("integration arrays must have equal length of at least two"))

function _quadrature_weights(x)
    length(x) >= 2 && all(diff(x) .> 0) || throw(ArgumentError(
        "quadrature axis must be strictly increasing"))
    weights = zeros(Float64, length(x))
    weights[[1, end]] = [(x[2] - x[1]) / 2, (x[end] - x[end - 1]) / 2]
    for i in 2:length(x)-1
        weights[i] = (x[i + 1] - x[i - 1]) / 2
    end
    weights
end

function _frequency_to_wavelength_density(frequency_thz, density_per_thz)
    frequency, density = Float64.(collect(frequency_thz)), Float64.(collect(density_per_thz))
    length(frequency) == length(density) >= 2 || throw(ArgumentError(
        "frequency and density arrays must have equal length"))
    all(diff(frequency) .> 0) && all(>(0), frequency) && all(isfinite, frequency) ||
        throw(ArgumentError("absolute frequency must be positive, finite, and increasing"))
    all(isfinite, density) && all(>=(0), density) || throw(ArgumentError(
        "spectral density must be nonnegative and finite"))
    wavelength = _C_NM_THz ./ frequency
    reverse(wavelength), reverse(density .* _C_NM_THz ./ wavelength .^ 2)
end

"""Return final single-mode pulse energy density on frequency and wavelength axes."""
function spectral_density(result::PropagationResult)
    _propagation_integrity(result) || throw(ArgumentError("propagation result was mutated"))
    mode_count(result.problem) == 1 || throw(ArgumentError(
        "spectral_density requires a single-mode result; no detector collection model was declared"))
    sim, nt = result.problem.sim, sample_count(result.problem)
    dt_s = Float64(sim["Δt"]) * 1e-12
    density_hz = (nt * dt_s)^2 .* fftshift(vec(abs2.(result.output_spectrum[:, 1])))
    frequency = Float64.(sim["fs"])
    wavelength, density_nm = _frequency_to_wavelength_density(frequency, density_hz .* 1e12)
    (frequency_thz=frequency, frequency_offset_thz=frequency .- Float64(sim["f0"]),
     energy_density_j_per_hz=density_hz, wavelength_nm=wavelength,
     energy_density_j_per_nm=density_nm)
end

function _gaussian_osa_observation(sim_wavelength_nm, sim_linear_shape,
                                   measured_wavelength_nm, rbw_nm,
                                   policy=_OSA_COMPARISON_POLICY)
    wavelength, shape = Float64.(collect(sim_wavelength_nm)), Float64.(collect(sim_linear_shape))
    samples, fwhm = Float64.(collect(measured_wavelength_nm)), Float64(rbw_nm)
    length(wavelength) == length(shape) >= 2 && all(diff(wavelength) .> 0) ||
        throw(ArgumentError("simulation wavelength and shape arrays must match and increase"))
    all(isfinite, shape) && all(>=(0), shape) || throw(ArgumentError(
        "simulation spectral shape must be nonnegative and finite"))
    all(diff(samples) .> 0) && isfinite(fwhm) && fwhm > 0 || throw(ArgumentError(
        "measurement wavelength must increase and OSA RBW must be positive"))
    sigma = fwhm / (2sqrt(2log(2)))
    radius = policy.kernel_truncation_sigma * sigma
    first(samples) - radius >= first(wavelength) && last(samples) + radius <= last(wavelength) ||
        throw(ArgumentError("simulation spectrum lacks full measured-axis support plus the assumed Gaussian ±$(policy.kernel_truncation_sigma)σ RBW kernel"))
    lo, hi = searchsortedfirst(wavelength, first(samples) - radius),
             searchsortedlast(wavelength, last(samples) + radius)
    spacing_ratio = hi > lo ? maximum(diff(@view wavelength[lo:hi])) / fwhm : Inf
    if spacing_ratio > policy.simulation_spacing_per_rbw_limit
        required_factor = spacing_ratio / policy.simulation_spacing_per_rbw_limit
        throw(ArgumentError(@sprintf(
            "simulation wavelength spacing/RBW is %.3g; require ≤ %.3g. Increase the time window by at least %.2f× while retaining temporal resolution.",
            spacing_ratio, policy.simulation_spacing_per_rbw_limit, required_factor)))
    end
    observed = zeros(Float64, length(samples))
    for (i, center) in pairs(samples)
        left, right = searchsortedfirst(wavelength, center - radius),
                      searchsortedlast(wavelength, center + radius)
        x, y = @view(wavelength[left:right]), @view(shape[left:right])
        response = exp.(-0.5 .* ((x .- center) ./ sigma) .^ 2)
        observed[i] = _trapz(x, y .* response) / _trapz(x, response)
    end
    all(isfinite, observed) && all(>=(0), observed) && sum(observed) > 0 ||
        throw(ArgumentError("OSA observation must contain finite nonnegative power and positive total power"))
    (values=observed, simulation_spacing_per_rbw=spacing_ratio)
end

struct _SpectrumComparisonToken end
const _SPECTRUM_COMPARISON_TOKEN = _SpectrumComparisonToken()

"""Sealed output-only OSA observation and its explicit shape-comparison policy."""
struct SpectrumComparison
    simulation::PropagationResult
    measurement::MeasuredSpectrum
    predicted_linear_shape::Vector{Float64}
    evaluation_band_nm::Tuple{Float64,Float64}
    simulation_spacing_per_rbw::Float64
    policy::NamedTuple
    comparison_sha256::String

    function SpectrumComparison(::_SpectrumComparisonToken, simulation, measurement,
                                prediction, band, spacing_ratio, policy, hash)
        new(simulation, measurement, prediction, band, spacing_ratio, policy, hash)
    end
end

function _comparison_sha256(simulation, measurement, prediction, band, spacing_ratio,
                            policy)
    payload = (
        simulation_evidence_sha256=simulation.evidence_sha256,
        measurement_sha256=measurement.measurement_sha256,
        predicted_linear_shape=_array_sha256(prediction),
        evaluation_band_nm=band, simulation_spacing_per_rbw=spacing_ratio,
        policy=policy,
    )
    bytes2hex(sha256(codeunits(repr(payload))))
end

_verify_simulation(result, policy) = verify(
    result;
    temporal_edge_limit=policy.temporal_edge_limit,
    spectral_edge_limit=policy.spectral_edge_limit,
    min_launch_samples_per_fwhm=policy.min_launch_samples_per_fwhm,
    require_launch_sampling=policy.require_launch_sampling,
    photon_drift_limit=policy.photon_drift_limit,
    energy_drift_limit=policy.energy_drift_limit,
)

"""
    compare_spectrum(result, measurement; evaluation_band_nm=nothing)

Apply an assumed Gaussian wavelength-RBW response in linear power. Independent
area normalization over the predeclared evaluation band removes the global
scale degree; no wavelength shift is fitted and no absolute claim is available.
"""
function compare_spectrum(result::PropagationResult, measurement::MeasuredSpectrum;
                          evaluation_band_nm=nothing)
    policy = _OSA_COMPARISON_POLICY
    _propagation_integrity(result) || throw(ArgumentError("propagation result was mutated"))
    _verify_simulation(result, policy).pass || throw(ArgumentError(
        "propagation verification failed; fix containment/conservation before measurement comparison"))
    verify(measurement).pass || throw(ArgumentError(
        "measured spectrum or its raw source failed integrity verification"))
    mode_count(result.problem) == 1 || throw(ArgumentError(
        "OSA comparison requires single-mode output until a detector collection model exists"))
    band = evaluation_band_nm === nothing ? extrema(measurement.wavelength_nm) :
        (Float64(first(evaluation_band_nm)), Float64(last(evaluation_band_nm)))
    band[1] < band[2] && band[1] >= first(measurement.wavelength_nm) &&
        band[2] <= last(measurement.wavelength_nm) || throw(ArgumentError(
        "evaluation_band_nm must be an increasing interval inside the measured axis"))
    count((measurement.wavelength_nm .>= band[1]) .&
          (measurement.wavelength_nm .<= band[2])) >= 3 || throw(ArgumentError(
        "evaluation_band_nm must contain at least three measured samples"))
    tolerance = 8eps(maximum(abs, measurement.wavelength_nm))
    all(endpoint -> any(isapprox.(measurement.wavelength_nm, endpoint;
                                  rtol=0, atol=tolerance)), band) ||
        throw(ArgumentError(
            "evaluation_band_nm endpoints must coincide with measured wavelength samples"))
    density = spectral_density(result)
    observed = _gaussian_osa_observation(
        density.wavelength_nm, density.energy_density_j_per_nm,
        measurement.wavelength_nm, measurement.resolution_bandwidth_nm, policy)
    evaluation = BitVector((measurement.wavelength_nm .>= band[1]) .&
                           (measurement.wavelength_nm .<= band[2]))
    trusted = evaluation .& .!_censor_mask(measurement)
    any(trusted) || throw(ArgumentError(
        "no_uncensored_evaluation_samples: area normalization is undefined"))
    weights = _quadrature_weights(measurement.wavelength_nm[evaluation])
    predicted_area = sum(weights[trusted[evaluation]] .* observed.values[trusted])
    predicted_area > 0 || throw(ArgumentError(
        "zero_predicted_evaluation_area: choose a band containing simulated power"))
    hash = _comparison_sha256(result, measurement, observed.values, band,
                              observed.simulation_spacing_per_rbw, policy)
    SpectrumComparison(
        _SPECTRUM_COMPARISON_TOKEN, result, measurement, observed.values,
        band, observed.simulation_spacing_per_rbw, policy, hash)
end

function _comparison_integrity(comparison)
    try
        _propagation_integrity(comparison.simulation) &&
        _measurement_integrity(comparison.measurement) &&
        comparison.comparison_sha256 == _comparison_sha256(
            comparison.simulation, comparison.measurement,
            comparison.predicted_linear_shape, comparison.evaluation_band_nm,
            comparison.simulation_spacing_per_rbw, comparison.policy)
    catch
        false
    end
end

function _comparison_view(comparison)
    x = comparison.measurement.wavelength_nm
    censored = _censor_mask(comparison.measurement)
    evaluation = BitVector((x .>= comparison.evaluation_band_nm[1]) .&
                           (x .<= comparison.evaluation_band_nm[2]))
    weights = zeros(length(x))
    weights[evaluation] .= _quadrature_weights(x[evaluation])
    trusted = evaluation .& .!censored
    count(trusted) > 0 || throw(ArgumentError("evaluation band has no uncensored power"))
    measured = _linear_power(comparison.measurement)
    predicted_area = sum(weights[trusted] .* comparison.predicted_linear_shape[trusted])
    measured_area = sum(weights[trusted] .* measured[trusted])
    predicted_area > 0 && measured_area > 0 || throw(ArgumentError(
        "evaluation band must contain positive predicted and measured power"))
    measurement_ratio = maximum(diff(x[evaluation])) /
        comparison.measurement.resolution_bandwidth_nm
    predicted_shape, measured_shape =
        comparison.predicted_linear_shape ./ predicted_area, measured ./ measured_area
    floor_shape = comparison.measurement.noise_floor_db === nothing ? missing :
        only(_linear_power([comparison.measurement.noise_floor_db],
                           comparison.measurement.value_semantics)) / measured_area
    reasons = Symbol[]
    comparison.measurement.noise_floor_db === nothing && push!(reasons, :unknown_noise_floor)
    any(censored .& evaluation) && push!(reasons, :censored_evaluation_samples)
    count(trusted) < 3 && push!(reasons, :insufficient_uncensored_evaluation_samples)
    measurement_ratio > comparison.policy.measurement_spacing_per_rbw_limit &&
        push!(reasons, :measurement_sampling_too_coarse)
    (
        x=x, weights=weights, censored=censored, evaluation=evaluation,
        trusted=trusted, predicted_shape=predicted_shape,
        measured_shape=measured_shape, floor_shape=floor_shape,
        measurement_spacing_per_rbw=measurement_ratio,
        reasons=unique(reasons),
    )
end

function _comparison_status(comparison)
    integrity = _comparison_integrity(comparison) && verify(comparison.measurement).pass
    simulation_trust = _propagation_integrity(comparison.simulation) &&
        _verify_simulation(comparison.simulation, comparison.policy).pass
    view = try _comparison_view(comparison) catch; nothing end
    reasons = view === nothing ? [:invalid_comparison_view] : copy(view.reasons)
    integrity || push!(reasons, :record_or_source_integrity_failed)
    simulation_trust || push!(reasons, :simulation_trust_failed)
    unique!(reasons)
    valid = integrity && simulation_trust && isempty(reasons)
    (pass=valid, integrity_ok=integrity, simulation_trust_pass=simulation_trust,
     comparison_valid=valid, metrics_status=valid ? :available : :unavailable,
     reasons=reasons)
end

verify(comparison::SpectrumComparison) = _comparison_status(comparison)

function summarize(comparison::SpectrumComparison)
    _comparison_integrity(comparison) || throw(ArgumentError("spectrum comparison was mutated"))
    view, status = _comparison_view(comparison), _comparison_status(comparison)
    (
        claim=comparison.policy.claim, normalization=comparison.policy.normalization,
        removed_global_scale=true, observation=comparison.policy.observation,
        resolution_bandwidth_nm=comparison.measurement.resolution_bandwidth_nm,
        kernel_truncation_sigma=comparison.policy.kernel_truncation_sigma,
        kernel_captured_mass=comparison.policy.kernel_captured_mass,
        evaluation_band_nm=comparison.evaluation_band_nm,
        axis_shift_nm=comparison.policy.axis_shift_nm, simulation_axis_support_fraction=1.0,
        simulation_spacing_per_rbw=comparison.simulation_spacing_per_rbw,
        measurement_spacing_per_rbw=view.measurement_spacing_per_rbw,
        metrics_status=status.metrics_status, metrics_reasons=status.reasons,
        simulation_evidence_sha256=comparison.simulation.evidence_sha256,
        measurement_sha256=comparison.measurement.measurement_sha256,
        comparison_sha256=comparison.comparison_sha256,
    )
end

function metrics(comparison::SpectrumComparison)
    _comparison_integrity(comparison) || throw(ArgumentError("spectrum comparison was mutated"))
    view, status = _comparison_view(comparison), _comparison_status(comparison)
    censored_points = comparison.measurement.noise_floor_db === nothing ? missing : count(view.censored)
    violations = ismissing(view.floor_shape) ? missing :
        count(comparison.predicted_linear_shape[view.censored] .>
              view.floor_shape * sum(view.weights[view.trusted] .*
                                     comparison.predicted_linear_shape[view.trusted]))
    common = (
        metrics_status=status.metrics_status, reasons=status.reasons,
        evaluation_points=count(view.evaluation),
        uncensored_evaluation_points=count(view.trusted),
        censored_points=censored_points, censor_limit_violations=violations,
        simulation_axis_support_fraction=1.0,
        simulation_spacing_per_rbw=comparison.simulation_spacing_per_rbw,
        measurement_spacing_per_rbw=view.measurement_spacing_per_rbw,
        zero_prediction_points=count(==(0.0), comparison.predicted_linear_shape),
    )
    status.comparison_valid || return merge(common, (
        total_variation_distance=missing, centroid_error_nm=missing))
    w, x = view.weights[view.evaluation], view.x[view.evaluation]
    p, m = view.predicted_shape[view.evaluation], view.measured_shape[view.evaluation]
    tv = 0.5 * sum(w .* abs.(p .- m))
    centroid_error = sum(w .* x .* p) - sum(w .* x .* m)
    merge(common, (total_variation_distance=Float64(tv),
                   centroid_error_nm=Float64(centroid_error)))
end

function _display_view(comparison, view)
    reference = maximum(view.measured_shape[view.trusted])
    true_floor_db = ismissing(view.floor_shape) ? missing :
        10log10(view.floor_shape / reference)
    plotted_floor_db = ismissing(true_floor_db) ? missing : max(true_floor_db, -100.0)
    curve_floor_db = ismissing(plotted_floor_db) ? _SPECTRUM_DISPLAY_FLOOR_DB :
        min(_SPECTRUM_DISPLAY_FLOOR_DB, plotted_floor_db - 3)
    floor_linear = 10.0^(curve_floor_db / 10)
    to_db(values) = 10 .* log10.(max.(values ./ reference, floor_linear))
    predicted_db, measured_db = to_db(view.predicted_shape), to_db(view.measured_shape)
    predicted_db, measured_db, true_floor_db, plotted_floor_db
end

function _spectrum_display_limits(predicted_db, measured_db, censored, plotted_floor_db)
    y_lower = ismissing(plotted_floor_db) ? _SPECTRUM_DISPLAY_FLOOR_DB :
        min(_SPECTRUM_DISPLAY_FLOOR_DB, plotted_floor_db - 3)
    measured_above_floor = measured_db[.!censored]
    visible_peak = max(maximum(predicted_db),
        isempty(measured_above_floor) ? -Inf : maximum(measured_above_floor))
    y_lower, max(3.0, visible_peak) + 1.0
end

function _write_spectrum_figure(comparison, path)
    view, evidence, status = _comparison_view(comparison), metrics(comparison), verify(comparison)
    predicted_db, measured_db, true_floor_db, plotted_floor_db =
        _display_view(comparison, view)
    fig, axes = PyPlot.subplots(2, 1; figsize=(9, 6.5), sharex=true,
        gridspec_kw=Dict("height_ratios" => [2.2, 1.0]))
    axes[1].plot(view.x, predicted_db; color="#0072B2", linewidth=1.8,
                 label="Simulation after assumed OSA response")
    measured_label = comparison.measurement.noise_floor_db === nothing ?
        "Measured (floor unknown)" : "Measured above floor"
    axes[1].scatter(view.x[.!view.censored], measured_db[.!view.censored];
                    color="#D55E00", s=18, label=measured_label, zorder=3)
    if any(view.censored)
        floor_label = true_floor_db < -100 ?
            "Censored upper limit (clipped; true $(round(true_floor_db; digits=1)) dB)" :
            "Censored upper limit"
        axes[1].axhline(plotted_floor_db; color="#CC79A7", linestyle="--",
                        linewidth=0.8, zorder=1)
        axes[1].scatter(view.x[view.censored], fill(plotted_floor_db, count(view.censored));
                        color="#CC79A7", marker="v", s=24,
                        label=floor_label, zorder=3)
    end
    for axis in axes
        first(view.x) < comparison.evaluation_band_nm[1] && axis.axvspan(
            first(view.x), comparison.evaluation_band_nm[1]; color="0.9")
        comparison.evaluation_band_nm[2] < last(view.x) && axis.axvspan(
            comparison.evaluation_band_nm[2], last(view.x); color="0.9")
        axis.grid(true, alpha=0.25)
    end
    y_lower, y_upper = _spectrum_display_limits(
        predicted_db, measured_db, view.censored, plotted_floor_db)
    axes[1].set_ylim(y_lower, y_upper)
    axes[1].set_ylabel("Area-normalized shape [dB]")
    axes[1].set_title("OSA spectrum: shape-only comparison")
    axes[1].legend(loc="best")
    difference = view.predicted_shape .- view.measured_shape
    axes[2].axhline(0.0; color="black", linewidth=0.8)
    axes[2].scatter(view.x[view.trusted], difference[view.trusted];
                    color="#009E73", s=14)
    residual_span = max(1.1maximum(abs, difference[view.trusted]),
                        0.05maximum(view.measured_shape[view.trusted]))
    axes[2].set_ylim(-residual_span, residual_span)
    axes[2].set_xlabel("Vacuum wavelength [nm]")
    axes[2].set_ylabel("Shape difference [1/nm]")
    status.metrics_status == :unavailable && axes[2].text(
        0.02, 0.92, "Metrics withheld: $(join(string.(status.reasons), ", "))";
        transform=axes[2].transAxes, va="top", fontsize=8)
    footer = @sprintf(
        "Independent area normalization removes global scale | assumed Gaussian RBW %.4g nm (±%.3gσ mass %.6f) | censor violations %s | no fitted axis shift",
        comparison.measurement.resolution_bandwidth_nm,
        comparison.policy.kernel_truncation_sigma,
        comparison.policy.kernel_captured_mass,
        string(evidence.censor_limit_violations))
    fig.text(0.5, 0.012, footer; ha="center", fontsize=8)
    fig.tight_layout(rect=(0, 0.045, 1, 1))
    mkpath(dirname(abspath(path)))
    fig.savefig(path; dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    String(path)
end

function _raw_source_copy(measurement, prefix)
    measurement.source_path === nothing && return nothing
    bytes = read(measurement.source_path)
    _bytes_sha256(bytes) == measurement.source_sha256 || throw(ArgumentError(
        "raw OSA source changed before report writing"))
    path = string(prefix, "_raw", splitext(measurement.source_path)[2])
    write(path, bytes)
    path
end

"""Write a descriptive PNG, self-contained JSON, Markdown, and raw-source copy."""
function write_spectrum_report(comparison::SpectrumComparison; output_dir, tag="spectrum_comparison")
    _comparison_integrity(comparison) || throw(ArgumentError("spectrum comparison was mutated"))
    directory, prefix = abspath(String(output_dir)), ""
    mkpath(directory)
    prefix = joinpath(directory, String(tag))
    figure_path = _write_spectrum_figure(comparison, string(prefix, ".png"))
    raw_path = _raw_source_copy(comparison.measurement, prefix)
    view, evidence, summary = _comparison_view(comparison), metrics(comparison), summarize(comparison)
    difference = view.predicted_shape .- view.measured_shape
    propagation = metrics(comparison.simulation)
    payload = Dict(
        "schema_version" => "fiberlab_spectrum_comparison_v1",
        "measurement" => Dict(
            "instrument" => comparison.measurement.instrument,
            "acquired_at" => comparison.measurement.acquired_at,
            "value_semantics" => string(comparison.measurement.value_semantics),
            "resolution_bandwidth_nm" => comparison.measurement.resolution_bandwidth_nm,
            "noise_floor_db" => comparison.measurement.noise_floor_db,
            "censoring_status" => comparison.measurement.noise_floor_db === nothing ?
                "unknown_floor" : "declared_floor",
            "axis_order_original" => string(comparison.measurement.axis_order_original),
            "wavelength_range_nm" => collect(extrema(view.x)), "points" => length(view.x),
            "wavelength_nm" => comparison.measurement.wavelength_nm,
            "values_db" => comparison.measurement.values_db,
            "metadata" => comparison.measurement.metadata,
            "source_path" => comparison.measurement.source_path,
            "source_sha256" => comparison.measurement.source_sha256,
            "raw_source_copy" => raw_path === nothing ? nothing : basename(raw_path),
            "measurement_sha256" => comparison.measurement.measurement_sha256,
        ),
        "simulation" => Dict(
            "resolved_sha256" => comparison.simulation.resolved_sha256,
            "evidence_sha256" => comparison.simulation.evidence_sha256,
            "verification_pass" => _verify_simulation(
                comparison.simulation, comparison.policy).pass,
            "time_window_ps" => propagation.time_window_ps,
            "frequency_spacing_thz" => propagation.frequency_spacing_thz,
            "max_temporal_edge_fraction" => propagation.max_temporal_edge_fraction,
            "max_spectral_edge_fraction" => propagation.max_spectral_edge_fraction,
            "max_photon_number_drift" => propagation.max_photon_number_drift,
        ),
        "comparison" => Dict(
            "claim" => string(comparison.policy.claim),
            "normalization" => string(comparison.policy.normalization),
            "removed_global_scale" => true,
            "axis_shift_nm" => comparison.policy.axis_shift_nm,
            "observation" => string(comparison.policy.observation),
            "kernel_truncation_sigma" => comparison.policy.kernel_truncation_sigma,
            "kernel_captured_mass" => comparison.policy.kernel_captured_mass,
            "evaluation_band_nm" => collect(comparison.evaluation_band_nm),
            "simulation_axis_support_fraction" => 1.0,
            "simulation_spacing_per_rbw" => summary.simulation_spacing_per_rbw,
            "measurement_spacing_per_rbw" => summary.measurement_spacing_per_rbw,
            "metrics_status" => string(summary.metrics_status),
            "metrics_reasons" => string.(summary.metrics_reasons),
            "metrics" => Dict(string(k) => v for (k, v) in pairs(evidence)),
            "policy" => Dict(
                "simulation_spacing_per_rbw_limit" =>
                    comparison.policy.simulation_spacing_per_rbw_limit,
                "measurement_spacing_per_rbw_limit" =>
                    comparison.policy.measurement_spacing_per_rbw_limit,
                "temporal_edge_limit" => comparison.policy.temporal_edge_limit,
                "spectral_edge_limit" => comparison.policy.spectral_edge_limit,
                "min_launch_samples_per_fwhm" =>
                    comparison.policy.min_launch_samples_per_fwhm,
                "require_launch_sampling" => comparison.policy.require_launch_sampling,
                "photon_drift_limit" => comparison.policy.photon_drift_limit,
                "energy_drift_limit" => comparison.policy.energy_drift_limit,
            ),
            "comparison_sha256" => comparison.comparison_sha256,
        ),
        "data" => Dict(
            "wavelength_nm" => view.x, "predicted_shape_per_nm" => view.predicted_shape,
            "measured_shape_per_nm" => view.measured_shape,
            "shape_difference_per_nm" => difference,
            "censored" => comparison.measurement.noise_floor_db === nothing ?
                nothing : view.censored,
            "evaluation_mask" => view.evaluation,
        ),
    )
    json_path = write_json_file(string(prefix, ".json"), payload)
    markdown_path = string(prefix, ".md")
    open(markdown_path, "w") do io
        println(io, "# OSA Spectrum Comparison\n")
        println(io, "This is an **area-normalized shape-only comparison**. Independent normalization removes the global scale, so absolute power, throughput, and calibration accuracy are unavailable.\n")
        println(io, "- Instrument: `$(comparison.measurement.instrument)`")
        println(io, "- Assumed response: Gaussian intensity resolution bandwidth FWHM `$(comparison.measurement.resolution_bandwidth_nm) nm`, truncated at `±$(comparison.policy.kernel_truncation_sigma)σ` (captured mass `$(comparison.policy.kernel_captured_mass)`)")
        floor_text = comparison.measurement.noise_floor_db === nothing ?
            "unknown (censor state and metrics withheld)" :
            "$(comparison.measurement.noise_floor_db) dB"
        println(io, "- Noise floor: `$floor_text`; censor-limit violations: `$(evidence.censor_limit_violations)`")
        println(io, "- Evaluation band: `$(comparison.evaluation_band_nm) nm`")
        println(io, "- Metrics: `$(summary.metrics_status)`; reasons: `$(summary.metrics_reasons)`")
        println(io, "- Total-variation shape distance: `$(evidence.total_variation_distance)`")
        println(io, "- Centroid error: `$(evidence.centroid_error_nm) nm`")
        println(io, "- Alignment: `no fitted axis shift` (axis shift = 0 nm)")
        println(io, "- Simulation support: full measured axis plus the declared truncated kernel\n")
        println(io, "The model was converted from frequency density to vacuum-wavelength density with the Jacobian, convolved in linear power, and sampled at measured wavelengths. This experimental core does not establish compatibility with an untouched Rivera Lab export.")
    end
    (figure=figure_path, json=json_path, markdown=markdown_path, raw_source=raw_path)
end
