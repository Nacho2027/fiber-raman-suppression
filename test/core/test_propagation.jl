using FFTW
using LinearAlgebra
using SHA

@testset "Dense evidence hashing" begin
    dense = reshape(ComplexF64.(1:32768), 256, 128)
    payload = IOBuffer()
    write(payload, string(eltype(dense), ":", join(size(dense), "x"), ":"))
    write(payload, reinterpret(UInt8, vec(dense)))
    expected = bytes2hex(sha256(take!(payload)))
    @test FiberLab._array_sha256(dense) == expected
    @test FiberLab._array_sha256(copy(dense)) == expected
    @test FiberLab._array_sha256(@view dense[:, :]) == expected
    @test FiberLab._array_sha256(reshape(dense, 128, 256)) != expected
    FiberLab._array_sha256(dense)
    @test @allocated(FiberLab._array_sha256(dense)) < sizeof(dense) ÷ 4
end

@testset "FiberLab forward propagation" begin
    fiber = Fiber(
        preset = :SMF28_beta2_only,
        length_m = 1e-4,
        power_w = 1e-5,
        beta_order = 2,
    )
    pulse = Pulse(fwhm_s = 250e-15, rep_rate_hz = 50e6, shape = :gaussian)
    grid = Grid(nt = 128, time_window_ps = 3.0, policy = :exact)
    problem = fiber_problem(
        fiber;
        pulse = pulse,
        grid = grid,
        raman_threshold_thz = nothing,
    )
    z_m = [0.0, fiber.length_m / 2, fiber.length_m]
    result = propagate(problem; saveat = z_m)

    @test result isa PropagationResult
    @test result.z_m == z_m
    @test size(result.spectra) == (128, 1, 3)
    @test result.input_spectrum == result.spectra[:, :, 1]
    @test result.output_spectrum == result.spectra[:, :, end]
    @test all(isfinite, result.spectra)
    @test last(result.z_m) == fiber.length_m
    @test !hasproperty(result, :ode_solution)
    @test_throws MethodError PropagationResult(
        (getfield(result, index) for index in 1:fieldcount(PropagationResult))...)

    summary = summarize(result)
    @test summary.metadata_authority == :authoritative
    @test summary.raman_response.model == "blow_wood_single_damped_oscillator_v1"
    @test summary.raman_response.fraction == 0.18
    @test summary.requested_fiber == fiber
    @test summary.requested_pulse == pulse
    @test summary.requested_grid == grid
    @test summary.resolved_grid == grid
    @test length(summary.construction_sha256) == 64
    @test length(summary.numerical_sha256) == 64
    @test length(summary.resolved_sha256) == 64
    @test length(summary.evidence_sha256) == 64
    @test summary.solver == :Tsit5

    evidence = metrics(result)
    @test evidence.samples == 128
    @test evidence.modes == 1
    @test evidence.saved_positions == 3
    @test evidence.input_energy_pj ≈ fiber.power_w / pulse.rep_rate_hz * 1e12 rtol = 1e-5
    @test evidence.output_energy_pj > 0
    @test evidence.input_peak_power_w > 0
    @test evidence.output_peak_power_w > 0
    @test length(evidence.input_mode_energy_pj) == 1
    @test length(evidence.output_mode_energy_pj) == 1
    @test evidence.launch_samples_per_fwhm ≈ pulse.fwhm_s * 1e12 / problem.sim["Δt"]
    @test evidence.max_photon_number_drift < 1e-8

    verification = verify(result)
    @test verification.pass
    @test verification.integrity_ok
    @test verification.solver_success
    @test verification.finite_fields
    @test verification.temporal_edges_contained
    @test verification.spectral_edges_contained
    @test verification.launch_sampling_ok
    @test verification.photon_number_conserved
    @test !verify(result; min_launch_samples_per_fwhm = 16).pass
    @test verify(result; photon_drift_limit = nothing).photon_number_conserved === missing
    @test verify(result; energy_drift_limit = 1.0).energy_change_acceptable

    zero_phase_output = FiberLab._run_model_forward(
        fiber_model(problem),
        zeros(sample_count(problem)),
        nothing,
    )
    @test result.output_spectrum ≈ zero_phase_output rtol = 1e-11

    original_launch = problem.uω0[1, 1]
    problem.uω0[1, 1] = 2original_launch
    @test verify(result).pass
    problem.uω0[1, 1] = original_launch

    result.problem.fiber["Dω"][1, 1] += 1
    invalid_verification = verify(result)
    @test !invalid_verification.pass
    @test !invalid_verification.integrity_ok
    @test keys(invalid_verification) == keys(verification)
    @test invalid_verification.max_photon_number_drift === missing
    result.problem.fiber["Dω"][1, 1] -= 1

    malformed_result = deepcopy(result)
    empty!(malformed_result.z_m)
    @test !verify(malformed_result).integrity_ok

    changed_package_problem = deepcopy(problem)
    changed_package_problem.uω0 .*= 2
    @test_throws ArgumentError propagate(changed_package_problem)

    @test_throws ArgumentError propagate(problem; saveat = [fiber.length_m / 2, fiber.length_m])
    @test_throws ArgumentError propagate(problem; saveat = [0.0, fiber.length_m / 2])
    @test_throws ArgumentError propagate(problem; saveat = [0.0, 0.0, fiber.length_m])
    @test_throws ArgumentError propagate(problem; saveat = [0.0, fiber.length_m, fiber.length_m / 2])
    @test_throws ArgumentError propagate(problem; saveat = [0.0, NaN, fiber.length_m])
    @test_throws ArgumentError propagate(problem; saveat = [0.0, 2fiber.length_m])
end

@testset "Explicit multimode linear propagation" begin
    nt, modes, length_m = 32, 2, 0.1
    sim = FiberLab.get_disp_sim_params(1550e-9, modes, nt, 5.0, 2)
    t_ps = sim["ts"] .* 1e12
    envelope = exp.(-0.5 .* (t_ps ./ 0.4) .^ 2)
    second_mode = (0.4 + 0.2im) .* exp.(-0.5 .* ((t_ps .- 0.25) ./ 0.25) .^ 2)
    time_field = hcat(envelope, second_mode)
    launch = ifft(time_field, 1)
    offsets = FFTW.fftfreq(nt, 1 / sim["Δt"])
    dispersion = hcat(0.02 .* offsets .^ 2, -0.015 .* offsets .^ 2)
    fiber = Dict{String,Any}(
        "Dω" => dispersion,
        "γ" => zeros(Float64, modes, modes, modes, modes),
        "L" => length_m,
        "hRω" => zeros(ComplexF64, nt),
        "one_m_fR" => 1.0,
        "zsave" => nothing,
    )
    problem = fiber_field_problem(launch, fiber, sim; preset = :linear_two_mode)
    z_m = [0.0, length_m / 3, length_m]
    result = propagate(problem; saveat = z_m)

    @test size(result.spectra) == (nt, modes, length(z_m))
    for (index, z) in pairs(z_m)
        expected = cis.(dispersion .* z) .* launch
        @test norm(result.spectra[:, :, index] - expected) / norm(expected) < 1e-12
    end
    @test summarize(result).metadata_authority == :resolved_numerical
    @test ismissing(summarize(result).raman_response)
    @test ismissing(summarize(result).requested_fiber)
    @test ismissing(summarize(result).requested_pulse)
    evidence = metrics(result)
    @test evidence.launch_samples_per_fwhm === missing
    @test evidence.max_photon_number_drift < 1e-12
    @test evidence.input_mode_energy_pj ≈ evidence.output_mode_energy_pj rtol = 1e-12
    verification = verify(result)
    @test verification.pass
    @test verification.launch_sampling_ok === missing
    @test !verify(result; require_launch_sampling = true).pass

    endpoints = propagate(problem)
    @test endpoints.z_m == [0.0, length_m]
    @test endpoints.output_spectrum ≈ result.output_spectrum rtol = 1e-12

    legacy_storage = deepcopy(problem)
    legacy_storage.fiber["zsave"] = [length_m / 5, 3length_m / 5]
    legacy_result = propagate(legacy_storage; saveat = z_m)
    @test legacy_result.z_m == z_m
    @test legacy_result.output_spectrum ≈ result.output_spectrum rtol = 1e-12

    invalid_tolerance = deepcopy(problem)
    invalid_tolerance.fiber["reltol"] = 0.0
    @test_throws ArgumentError propagate(invalid_tolerance)

    nonsymmetric_fiber = deepcopy(fiber)
    nonsymmetric_fiber["γ"][1, 1, 1, 2] = 0.1
    nonsymmetric = fiber_field_problem(
        launch, nonsymmetric_fiber, sim; preset = :nonsymmetric_forward)
    @test propagate(nonsymmetric) isa PropagationResult
    @test_throws ArgumentError fiber_model(nonsymmetric)
    forward_solution = FiberLab.solve_disp_mmf(
        nonsymmetric.uω0, nonsymmetric.fiber, nonsymmetric.sim)["ode_sol"]
    @test_throws ArgumentError FiberLab.solve_adjoint_disp_mmf(
        ones(ComplexF64, nt, modes),
        forward_solution,
        nonsymmetric.fiber,
        nonsymmetric.sim,
    )

    complex_fiber = deepcopy(fiber)
    complex_fiber["γ"] = complex.(complex_fiber["γ"])
    @test_throws ArgumentError fiber_field_problem(
        launch, complex_fiber, sim; preset = :complex_gamma)
    @test_throws ArgumentError FiberLab.get_p_disp_mmf(
        sim["ωs"], sim["ω0"], fiber["Dω"], complex_fiber["γ"],
        fiber["hRω"], fiber["one_m_fR"], nt, modes)
    @test_throws ArgumentError FiberLab.get_p_adjoint_disp_mmf(
        forward_solution, fftshift(sim["ωs"] / sim["ω0"]), fiber["Dω"],
        fiber["hRω"], complex_fiber["γ"], fiber["one_m_fR"], nt, modes)
end
