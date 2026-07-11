using FFTW
using JSON3

function _analytic_spectrum_result(; modes=1, nt=512, time_window_ps=200.0,
                                   center_nm=1550.0, sigma_nm=0.35,
                                   center_time=true)
    sim = FiberLab.get_disp_sim_params(1550e-9, modes, nt, time_window_ps, 2)
    wavelength_nm = 299792.458 ./ sim["fs"]
    density_per_nm = exp.(-0.5 .* ((wavelength_nm .- center_nm) ./ sigma_nm) .^ 2)
    density_per_thz = density_per_nm .* wavelength_nm .^ 2 ./ 299792.458
    dt_s = sim["Δt"] * 1e-12
    shifted_power = density_per_thz ./ ((nt * dt_s)^2 * 1e12)
    launch_mode = ComplexF64.(ifftshift(sqrt.(shifted_power)))
    center_time && (launch_mode .*= cis.(π .* (0:nt-1)))
    launch = repeat(reshape(ComplexF64.(launch_mode), nt, 1), 1, modes)
    fiber = FiberLab.get_disp_fiber_params_user_defined(
        1e-5, sim; fR=0.0, gamma_user=0.0, betas_user=[0.0])
    if modes > 1
        fiber["Dω"] = repeat(fiber["Dω"], 1, modes)
        fiber["γ"] = zeros(Float64, modes, modes, modes, modes)
    end
    return propagate(fiber_field_problem(launch, fiber, sim; preset=:analytic_osa))
end

@testset "OSA spectrum ingestion and integrity" begin
    wavelength = [1550.0, 1549.5, 1549.0]
    values = [-20.0, -10.0, -30.0]
    spectrum = MeasuredSpectrum(
        wavelength,
        values;
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=0.10,
        noise_floor_db=-28.0,
        instrument="synthetic OSA",
        acquired_at="2026-07-10T12:00:00-07:00",
    )
    wavelength[1] = 0.0
    values[1] = 0.0

    @test spectrum.wavelength_nm == [1549.0, 1549.5, 1550.0]
    @test spectrum.values_db == [-30.0, -10.0, -20.0]
    @test FiberLab._censor_mask(spectrum) == [true, false, false]
    @test summarize(spectrum).axis_order_original == :descending
    @test summarize(spectrum).source_authority == :in_memory
    @test verify(spectrum).pass
    @test ismissing(summarize(MeasuredSpectrum(
        [1549.0, 1550.0], [-20.0, -10.0];
        value_semantics=:relative_power_db, resolution_bandwidth_nm=0.1,
        noise_floor_db=nothing, instrument="OSA", acquired_at="synthetic")).censored_points)

    @test_throws ArgumentError MeasuredSpectrum(
        [1549.0, 1550.0, 1549.5], [-20.0, -10.0, -30.0];
        value_semantics=:relative_power_db, resolution_bandwidth_nm=0.1,
        noise_floor_db=nothing, instrument="OSA", acquired_at="synthetic")
    @test_throws ArgumentError MeasuredSpectrum(
        [1549.0, 1549.0], [-20.0, -10.0];
        value_semantics=:relative_power_db, resolution_bandwidth_nm=0.1,
        noise_floor_db=nothing, instrument="OSA", acquired_at="synthetic")
    @test_throws ArgumentError MeasuredSpectrum(
        [1549.0, NaN], [-20.0, -10.0];
        value_semantics=:relative_power_db, resolution_bandwidth_nm=0.1,
        noise_floor_db=nothing, instrument="OSA", acquired_at="synthetic")
    @test_throws ArgumentError MeasuredSpectrum(
        [1549.0, 1550.0], [-20.0, -10.0];
        value_semantics=:ambiguous_db, resolution_bandwidth_nm=0.1,
        noise_floor_db=nothing, instrument="OSA", acquired_at="synthetic")

    directory = mktempdir()
    path = joinpath(directory, "osa.csv")
    write(path, "lambda_nm,level_db\n1550,-20\n1549.5,-10\n1549,-30\n")
    loaded = load_osa_spectrum(
        path;
        wavelength_column=:lambda_nm,
        value_column=:level_db,
        value_semantics=:power_dbm_in_rbw,
        resolution_bandwidth_nm=0.10,
        noise_floor_db=-28.0,
        instrument="OSA-1",
        acquired_at="2026-07-10T12:00:00-07:00",
    )
    @test loaded.wavelength_nm == [1549.0, 1549.5, 1550.0]
    @test loaded.values_db == [-30.0, -10.0, -20.0]
    @test FiberLab._linear_power(loaded)[2] ≈ 1e-4
    @test summarize(loaded).source_authority == :file_sha256
    @test verify(loaded).source_matches
    @test loaded.metadata["wavelength_column"] == "lambda_nm"
    @test_throws ArgumentError load_osa_spectrum(
        path;
        wavelength_column=:missing,
        value_column=:level_db,
        value_semantics=:power_dbm_in_rbw,
        resolution_bandwidth_nm=0.1,
        noise_floor_db=nothing,
        instrument="OSA-1",
        acquired_at="synthetic",
    )
    write(path, "changed\n")
    @test !verify(loaded).source_matches
    @test !verify(loaded).pass

    damaged = deepcopy(spectrum)
    damaged.values_db[1] = 10.0
    @test !verify(damaged).pass
end

@testset "Spectral density and OSA observation model" begin
    result = _analytic_spectrum_result()
    density = spectral_density(result)
    sim = result.problem.sim
    temporal = fft(result.output_spectrum, 1)
    pulse_energy_j = sim["Δt"] * 1e-12 * sum(abs2, temporal)
    df_hz = 1 / (sim["Nt"] * sim["Δt"] * 1e-12)
    @test sum(density.energy_density_j_per_hz) * df_hz ≈ pulse_energy_j rtol=1e-12

    frequency_thz = collect(range(190.0, 200.0; length=20_001))
    flat_per_thz = ones(length(frequency_thz))
    wavelength_nm, density_per_nm = FiberLab._frequency_to_wavelength_density(
        frequency_thz, flat_per_thz)
    @test density_per_nm .* wavelength_nm .^ 2 ≈
        fill(299792.458, length(wavelength_nm)) rtol=1e-12
    @test FiberLab._trapz(wavelength_nm, density_per_nm) ≈
        FiberLab._trapz(frequency_thz, flat_per_thz) rtol=1e-7

    pump_nm = 1550.0
    pump_thz = 299792.458 / pump_nm
    @test 299792.458 / (pump_thz - 13.2) > pump_nm

    sigma_signal_nm = 0.35
    rbw_nm = 0.20
    sigma_rbw_nm = rbw_nm / (2sqrt(2log(2)))
    expected_sigma_nm = sqrt(sigma_signal_nm^2 + sigma_rbw_nm^2)
    sample_nm = collect(range(1548.5, 1551.5; length=121))
    observed = FiberLab._gaussian_osa_observation(
        density.wavelength_nm,
        density.energy_density_j_per_nm,
        sample_nm,
        rbw_nm,
    ).values
    weights = FiberLab._quadrature_weights(sample_nm)
    area = sum(weights .* observed)
    center = sum(weights .* sample_nm .* observed) / area
    sigma = sqrt(sum(weights .* (sample_nm .- center) .^ 2 .* observed) / area)
    @test sigma ≈ expected_sigma_nm atol=0.01

    # Independent oracle: a time-domain Gaussian has an analytic Gaussian
    # power spectrum with σ_f = 1/(2√2πσ_t).
    gaussian_sim = FiberLab.get_disp_sim_params(1550e-9, 1, 1024, 100.0, 2)
    sigma_t_ps = 2.0
    temporal = reshape(ComplexF64.(exp.(-0.5 .* ((gaussian_sim["ts"] .* 1e12) ./ sigma_t_ps) .^ 2)), 1024, 1)
    gaussian_launch = ifft(temporal, 1)
    gaussian_fiber = FiberLab.get_disp_fiber_params_user_defined(
        1e-5, gaussian_sim; fR=0.0, gamma_user=0.0, betas_user=[0.0])
    gaussian_result = propagate(fiber_field_problem(
        gaussian_launch, gaussian_fiber, gaussian_sim; preset=:time_gaussian_oracle))
    gaussian_density = spectral_density(gaussian_result)
    sigma_f_thz = 1 / (2sqrt(2) * π * sigma_t_ps)
    expected_frequency_shape = exp.(-0.5 .* (gaussian_density.frequency_offset_thz ./ sigma_f_thz) .^ 2)
    observed_frequency_shape = gaussian_density.energy_density_j_per_hz ./
        maximum(gaussian_density.energy_density_j_per_hz)
    @test maximum(abs.(observed_frequency_shape .- expected_frequency_shape)) < 1e-10

    # Legitimate zero predictions remain representable in linear space.
    sparse_shape = zeros(length(density.wavelength_nm))
    sparse_shape[findmin(abs.(density.wavelength_nm .- 1550.0))[2]] = 1.0
    zero_observation = FiberLab._gaussian_osa_observation(
        density.wavelength_nm, sparse_shape,
        collect(range(1548.5, 1551.5; length=61)), rbw_nm).values
    @test any(==(0.0), zero_observation)

    # A standard short-window grid cannot resolve a realistic OSA RBW; the
    # failure must tell the researcher how to repair the simulation.
    coarse_sim = FiberLab.get_disp_sim_params(1550e-9, 1, 4096, 12.0, 2)
    coarse_wavelength = sort(299792.458 ./ coarse_sim["fs"])
    coarse_error = try
        FiberLab._gaussian_osa_observation(
            coarse_wavelength, ones(length(coarse_wavelength)),
            collect(range(1549.8, 1550.2; length=9)), 0.1)
        nothing
    catch error
        error
    end
    @test coarse_error isa ArgumentError
    @test occursin("Increase the time window", sprint(showerror, coarse_error))
end


@testset "Shape-only spectrum comparison" begin
    result = _analytic_spectrum_result()
    rbw_nm = 0.20
    sigma_signal_nm = 0.35
    sigma_rbw_nm = rbw_nm / (2sqrt(2log(2)))
    sigma_observed_nm = sqrt(sigma_signal_nm^2 + sigma_rbw_nm^2)
    wavelength_nm = collect(range(1548.8, 1551.2; length=81))
    analytic_linear = exp.(-0.5 .* ((wavelength_nm .- 1550.0) ./ sigma_observed_nm) .^ 2)
    analytic_db = 10 .* log10.(analytic_linear)
    measured = MeasuredSpectrum(
        wavelength_nm,
        analytic_db;
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-50.0,
        instrument="analytic Gaussian OSA",
        acquired_at="synthetic",
    )
    comparison = compare_spectrum(result, measured)
    evidence = metrics(comparison)
    @test evidence.total_variation_distance < 2e-3
    @test abs(evidence.centroid_error_nm) < 1e-3
    @test evidence.simulation_axis_support_fraction == 1.0
    @test evidence.metrics_status == :available
    @test summarize(comparison).claim == :shape_only
    @test summarize(comparison).normalization == :independent_area
    @test summarize(comparison).removed_global_scale
    @test summarize(comparison).axis_shift_nm == 0.0
    @test verify(comparison).pass

    scaled = MeasuredSpectrum(
        wavelength_nm,
        analytic_db .+ 27.0;
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-23.0,
        instrument="scaled analytic OSA",
        acquired_at="synthetic",
    )
    scaled_metrics = metrics(compare_spectrum(result, scaled))
    @test scaled_metrics.total_variation_distance ≈
        evidence.total_variation_distance atol=1e-12

    shifted_linear = exp.(-0.5 .* ((wavelength_nm .- 1550.20) ./ sigma_observed_nm) .^ 2)
    shifted = MeasuredSpectrum(
        wavelength_nm,
        10 .* log10.(shifted_linear);
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-50.0,
        instrument="shifted analytic OSA",
        acquired_at="synthetic",
    )
    shifted_comparison = compare_spectrum(result, shifted)
    @test abs(metrics(shifted_comparison).centroid_error_nm) > 0.15
    @test summarize(shifted_comparison).axis_shift_nm == 0.0

    outside = MeasuredSpectrum(
        collect(range(1540.0, 1541.0; length=11)),
        fill(-10.0, 11);
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=nothing,
        instrument="outside OSA",
        acquired_at="synthetic",
    )
    @test_throws ArgumentError compare_spectrum(result, outside)

    coarse_measurement = MeasuredSpectrum(
        [1549.0, 1550.0, 1551.0], [-10.0, 0.0, -10.0];
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-50.0,
        instrument="undersampled OSA",
        acquired_at="synthetic",
    )
    coarse_comparison = compare_spectrum(result, coarse_measurement)
    @test !verify(coarse_comparison).pass
    @test :measurement_sampling_too_coarse in verify(coarse_comparison).reasons

    mostly_censored = MeasuredSpectrum(
        wavelength_nm,
        analytic_db;
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-0.001,
        instrument="censored OSA",
        acquired_at="synthetic",
    )
    censored_metrics = metrics(compare_spectrum(result, mostly_censored))
    @test censored_metrics.censored_points > length(wavelength_nm) - 3
    @test censored_metrics.metrics_status == :unavailable
    @test :censored_evaluation_samples in censored_metrics.reasons
    @test ismissing(censored_metrics.total_variation_distance)

    unknown_floor = MeasuredSpectrum(
        wavelength_nm,
        analytic_db;
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=nothing,
        instrument="unknown-floor OSA",
        acquired_at="synthetic",
    )
    unknown_comparison = compare_spectrum(result, unknown_floor)
    @test ismissing(metrics(unknown_comparison).total_variation_distance)
    @test !verify(unknown_comparison).pass
    @test :unknown_noise_floor in verify(unknown_comparison).reasons

    narrow_result = _analytic_spectrum_result(sigma_nm=0.05)
    tail_axis = collect(range(1545.5, 1550.5; step=0.05))
    tail_measurement = MeasuredSpectrum(
        tail_axis, fill(-10.0, length(tail_axis));
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-80.0,
        instrument="tail-band OSA",
        acquired_at="synthetic",
    )
    zero_area_error = try
        compare_spectrum(
            narrow_result, tail_measurement;
            evaluation_band_nm=(1545.5, 1546.0),
        )
        nothing
    catch error
        error
    end
    @test zero_area_error isa ArgumentError
    @test occursin("zero_predicted_evaluation_area", sprint(showerror, zero_area_error))

    tail_comparison = compare_spectrum(narrow_result, tail_measurement)
    tail_view = FiberLab._comparison_view(tail_comparison)
    tail_predicted_db, _, tail_floor_db, _ =
        FiberLab._display_view(tail_comparison, tail_view)
    @test tail_floor_db < -60
    @test minimum(tail_predicted_db) < -60

    broad_linear = exp.(-0.5 .* ((wavelength_nm .- 1550.0) ./ 0.8) .^ 2)
    broad_measurement = MeasuredSpectrum(
        wavelength_nm, 10 .* log10.(broad_linear);
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-50.0,
        instrument="broad-spectrum OSA",
        acquired_at="synthetic",
    )
    broad_comparison = compare_spectrum(narrow_result, broad_measurement)
    broad_view = FiberLab._comparison_view(broad_comparison)
    predicted_db, measured_db, _, plotted_floor_db =
        FiberLab._display_view(broad_comparison, broad_view)
    _, y_upper = FiberLab._spectrum_display_limits(
        predicted_db, measured_db, broad_view.censored, plotted_floor_db)
    @test maximum(predicted_db) > 3
    @test y_upper > maximum(predicted_db)

    contradictory_db = copy(analytic_db)
    contradictory_db[1:10] .= -50.0
    contradictory_db[end-9:end] .= -50.0
    contradictory = MeasuredSpectrum(
        wavelength_nm, contradictory_db;
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-40.0,
        instrument="censored-tail OSA",
        acquired_at="synthetic",
    )
    central_comparison = compare_spectrum(
        result, contradictory; evaluation_band_nm=(1549.4, 1550.6))
    @test verify(central_comparison).pass
    @test metrics(central_comparison).censor_limit_violations >= 2
    view = FiberLab._comparison_view(central_comparison)
    _, _, true_floor_db, plotted_floor_db = FiberLab._display_view(central_comparison, view)
    expected_floor_shape = only(FiberLab._linear_power(
        [-40.0], :relative_power_db)) /
        sum(view.weights[view.trusted] .* FiberLab._linear_power(contradictory)[view.trusted])
    reference = maximum(view.measured_shape[view.trusted])
    @test true_floor_db ≈ 10log10(expected_floor_shape / reference)
    @test plotted_floor_db == true_floor_db

    deep_floor = MeasuredSpectrum(
        wavelength_nm, analytic_db;
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-75.0,
        instrument="deep-floor OSA",
        acquired_at="synthetic",
    )
    deep_view = FiberLab._comparison_view(compare_spectrum(result, deep_floor))
    _, _, deep_true_floor, deep_plotted_floor = FiberLab._display_view(
        compare_spectrum(result, deep_floor), deep_view)
    @test deep_true_floor < -60
    @test deep_plotted_floor == deep_true_floor

    nonuniform_axis = [1549.4, 1549.55, 1549.7, 1549.9, 1550.0,
                       1550.12, 1550.3, 1550.45, 1550.6]
    nonuniform_linear = exp.(-0.5 .* ((nonuniform_axis .- 1550.0) ./ sigma_observed_nm) .^ 2)
    nonuniform = MeasuredSpectrum(
        nonuniform_axis, 10 .* log10.(nonuniform_linear);
        value_semantics=:relative_power_db,
        resolution_bandwidth_nm=0.40,
        noise_floor_db=-50.0,
        instrument="nonuniform OSA",
        acquired_at="synthetic",
    )
    nonuniform_comparison = compare_spectrum(
        result, nonuniform; evaluation_band_nm=(1549.55, 1550.45))
    nonuniform_view = FiberLab._comparison_view(nonuniform_comparison)
    @test nonuniform_view.weights[nonuniform_view.evaluation] ==
        FiberLab._quadrature_weights(nonuniform_axis[nonuniform_view.evaluation])
    @test all(iszero, nonuniform_view.weights[.!nonuniform_view.evaluation])

    untrusted = _analytic_spectrum_result(center_time=false)
    @test !verify(untrusted).pass
    @test_throws ArgumentError compare_spectrum(untrusted, measured)

    multimode = _analytic_spectrum_result(modes=2)
    @test_throws ArgumentError compare_spectrum(multimode, measured)

    damaged = deepcopy(comparison)
    damaged.predicted_linear_shape[1] *= 2
    @test !verify(damaged).pass
    @test_throws ArgumentError metrics(damaged)
    result.output_spectrum[1] *= 2
    @test !verify(comparison).pass
end

@testset "Spectrum comparison artifacts are descriptive" begin
    result = _analytic_spectrum_result()
    rbw_nm = 0.20
    sigma_nm = sqrt(0.35^2 + (rbw_nm / (2sqrt(2log(2))))^2)
    wavelength_nm = collect(range(1548.8, 1551.2; length=81))
    directory = mktempdir()
    source_path = joinpath(directory, "analytic_osa.csv")
    source_db = -3.0 .+ 10 .* log10.(exp.(-0.5 .* ((wavelength_nm .- 1550.0) ./ sigma_nm) .^ 2))
    open(source_path, "w") do io
        println(io, "wavelength_nm,power_dbm")
        for i in eachindex(wavelength_nm)
            println(io, wavelength_nm[i], ",", source_db[i])
        end
    end
    measured = load_osa_spectrum(
        source_path;
        wavelength_column=:wavelength_nm,
        value_column=:power_dbm,
        value_semantics=:power_dbm_in_rbw,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=-53.0,
        instrument="analytic OSA",
        acquired_at="synthetic",
        metadata=Dict("calibration_id" => "synthetic-only"),
    )
    comparison = compare_spectrum(result, measured)
    output_dir = mktempdir()
    paths = write_spectrum_report(comparison; output_dir=output_dir, tag="osa")
    @test isfile(paths.figure)
    @test isfile(paths.json)
    @test isfile(paths.markdown)
    @test isfile(paths.raw_source)
    @test read(paths.raw_source) == read(source_path)
    @test FiberLab._native_png_passes_audit(paths.figure)
    payload = JSON3.read(read(paths.json, String))
    @test payload.schema_version == "fiberlab_spectrum_comparison_v1"
    @test payload.simulation.evidence_sha256 == result.evidence_sha256
    @test payload.measurement.measurement_sha256 == measured.measurement_sha256
    @test payload.measurement.metadata.calibration_id == "synthetic-only"
    @test collect(payload.measurement.wavelength_nm) == measured.wavelength_nm
    @test collect(payload.measurement.values_db) == measured.values_db
    @test payload.measurement.censoring_status == "declared_floor"
    @test payload.comparison.kernel_truncation_sigma == 4.0
    @test payload.comparison.metrics_status == "available"
    @test payload.comparison.policy.simulation_spacing_per_rbw_limit == 1 / 3
    @test payload.comparison.policy.measurement_spacing_per_rbw_limit == 1 / 2
    @test payload.comparison.policy.temporal_edge_limit == 1e-3
    @test payload.comparison.policy.spectral_edge_limit == 1e-3
    @test payload.comparison.policy.photon_drift_limit == 1e-4

    unknown = MeasuredSpectrum(
        wavelength_nm, source_db;
        value_semantics=:power_dbm_in_rbw,
        resolution_bandwidth_nm=rbw_nm,
        noise_floor_db=nothing,
        instrument="unknown-floor OSA",
        acquired_at="synthetic",
    )
    unknown_paths = write_spectrum_report(
        compare_spectrum(result, unknown);
        output_dir=mktempdir(),
        tag="unknown_floor",
    )
    unknown_payload = JSON3.read(read(unknown_paths.json, String))
    @test unknown_payload.measurement.censoring_status == "unknown_floor"
    @test unknown_payload.data.censored === nothing
    @test occursin("noise floor: `unknown", lowercase(read(unknown_paths.markdown, String)))
    report = lowercase(read(paths.markdown, String))
    @test occursin("area-normalized shape-only comparison", report)
    @test occursin("no fitted axis shift", report)
    @test occursin("resolution bandwidth", report)
    @test !occursin("lab ready", report)
    @test !occursin("validated", report)
end
