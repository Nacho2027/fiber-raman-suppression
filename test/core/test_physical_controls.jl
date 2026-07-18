using TOML

function _physical_controls_problem(; nt=16, time_window_ps=5.0,
                                    raman_fraction=nothing)
    fiber = Fiber(
        preset = :SMF28_beta2_only,
        length_m = 1e-4,
        power_w = 1e-5,
        beta_order = 2,
        raman_fraction = raman_fraction,
    )
    return fiber_problem(
        fiber;
        pulse = Pulse(fwhm_s = 1e-12, rep_rate_hz = 50e6),
        grid = Grid(nt = nt, time_window_ps = time_window_ps, policy = :exact),
        raman_threshold_thz = -0.25,
    )
end

function _changed_problem(problem, mutation)
    changed = deepcopy(problem)
    mutation(changed)
    return changed
end

@testset "Physical Raman counterfactuals" begin
    @test Fiber(length_m = 1.0, power_w = 0.1).raman_fraction === nothing
    @test Fiber(:single_mode, :SMF28, 1.0, 0.1, 3).raman_fraction === nothing
    @test Fiber(length_m = 1.0, power_w = 0.1,
                raman_fraction = 0).raman_fraction === 0.0
    @test Fiber(length_m = 1.0, power_w = 0.1,
                raman_fraction = 1).raman_fraction === 1.0
    for invalid in (-eps(), 1 + eps(), NaN, Inf)
        @test_throws ArgumentError Fiber(
            length_m = 1.0,
            power_w = 0.1,
            raman_fraction = invalid,
        )
    end

    config_fiber = Fiber(
        preset = :SMF28_beta2_only,
        length_m = 1e-4,
        power_w = 1e-5,
        beta_order = 2,
        raman_fraction = 0.27,
    )
    config_experiment = Experiment(
        config_fiber;
        id = "explicit_raman_fraction",
        grid = Grid(nt = 16, time_window_ps = 0.5, policy = :exact),
    )
    config_text = experiment_config_text(config_experiment)
    @test TOML.parse(config_text)["problem"]["raman_fraction"] == 0.27
    @test !occursin(
        "\nraman_fraction =",
        experiment_config_text(Experiment(
            Fiber(preset = :SMF28, length_m = 1e-4, power_w = 1e-5);
            id = "preset_raman_fraction",
        )),
    )
    mktemp() do path, io
        close(io)
        write_experiment_config(path, config_experiment)
        parsed = load_experiment_spec(path)
        @test parsed.problem.raman_fraction == 0.27
        @test supported_experiment_run_kwargs(parsed).raman_fraction == 0.27
    end

    single_override = _physical_controls_problem(raman_fraction = 0.27)
    @test FiberLab._raman_response_metadata(single_override.fiber).fraction == 0.27
    @test single_override.metadata.requested_fiber.raman_fraction == 0.27

    problem = _physical_controls_problem()
    original_fiber = deepcopy(problem.fiber)
    original_response = FiberLab._raman_response_metadata(problem.fiber)
    original_numerical_sha = FiberLab._numerical_problem_signature(problem)
    original_resolved_sha = FiberLab._resolved_problem_signature(problem)
    @test original_response.fraction == 0.18

    off = with_raman_fraction(problem, 0.0)
    contract = raman_counterfactual_contract(problem, off)
    @test contract.pass
    @test contract.response_shape_matched

    mismatches = (
        launch = (_changed_problem(off, p -> p.uω0[1] += 1), :launch),
        grid = (_changed_problem(off, p -> p.sim["Δt"] *= 1.01), :simulation_grid),
        gamma = (_changed_problem(off, p -> p.fiber["γ"][1] += 1), :nonlinearity),
        length = (_changed_problem(off, p -> p.fiber["L"] *= 2), :length),
        tolerance = (_changed_problem(off, p -> p.fiber["reltol"] = 2e-8),
                     :solver_tolerances),
        fraction = (with_raman_fraction(problem, 0.1), :raman_off),
    )
    for (name, (candidate, failed_check)) in pairs(mismatches)
        @testset "$name mismatch" begin
            mismatch = raman_counterfactual_contract(problem, candidate)
            @test !mismatch.pass
            @test !getproperty(mismatch.checks, failed_check)
        end
    end
    missing_on = raman_counterfactual_contract(off, off)
    @test !missing_on.pass
    @test !missing_on.checks.raman_on

    changed_response = _changed_problem(
        off, p -> p.fiber["raman_tau1_fs"] += 1)
    response_mismatch = raman_counterfactual_contract(problem, changed_response)
    @test !response_mismatch.pass
    @test !response_mismatch.response_shape_matched
    response_control = raman_counterfactual_contract(
        problem, changed_response; allow_response_shape_change = true)
    @test response_control.pass
    @test response_control.declared_response_shape_control
    @test !raman_counterfactual_contract(
        problem, mismatches.launch[1]; allow_response_shape_change = true).pass
    @test FiberLab._raman_response_metadata(problem.fiber).fraction == 0.18
    @test problem.fiber == original_fiber
    @test off !== problem
    @test off.uω0 == problem.uω0
    @test off.uω0 !== problem.uω0
    @test off.sim == problem.sim
    @test off.sim !== problem.sim
    @test off.band_mask == problem.band_mask
    @test off.band_mask !== problem.band_mask
    @test off.frequency_offset_thz == problem.frequency_offset_thz
    @test off.raman_threshold_thz == problem.raman_threshold_thz
    @test off.fiber["Dω"] == problem.fiber["Dω"]
    @test off.fiber["γ"] == problem.fiber["γ"]
    @test off.fiber["Dω"] !== problem.fiber["Dω"]
    @test off.fiber["γ"] !== problem.fiber["γ"]
    for key in setdiff(
        collect(keys(problem.fiber)),
        ["hRω", "one_m_fR", "raman_fraction"],
    )
        @test isequal(off.fiber[key], problem.fiber[key])
    end
    @test iszero(off.fiber["one_m_fR"] - 1.0)
    @test all(iszero, off.fiber["hRω"])
    @test FiberLab._raman_response_metadata(off.fiber).fraction == 0.0
    @test off.metadata.requested_fiber.raman_fraction == 0.0
    @test off.metadata.construction_sha256 !== nothing
    @test off.metadata.construction_sha256 != problem.metadata.construction_sha256
    @test FiberLab._numerical_problem_signature(off) != original_numerical_sha
    @test FiberLab._resolved_problem_signature(off) != original_resolved_sha
    off_metadata = FiberLab._execution_metadata_from_problem(off)
    @test off_metadata.fiber.raman_fraction == 0.0
    @test off_metadata.source_metadata.raman_response.fraction == 0.0

    restored = with_raman_fraction(off, original_response.fraction)
    @test restored.uω0 == problem.uω0
    @test restored.fiber["Dω"] == problem.fiber["Dω"]
    @test restored.fiber["γ"] == problem.fiber["γ"]
    @test restored.fiber["hRω"] == problem.fiber["hRω"]
    @test restored.fiber["one_m_fR"] == problem.fiber["one_m_fR"]
    @test FiberLab._numerical_problem_signature(restored) == original_numerical_sha
    @test restored.metadata.construction_sha256 == problem.metadata.construction_sha256

    for invalid in (-0.01, 1.01, NaN, Inf)
    @test_throws ArgumentError with_raman_fraction(problem, invalid)
    end
    explicit_problem = fiber_field_problem(
        problem.uω0,
        problem.fiber,
        problem.sim;
        raman_threshold_thz = -0.25,
    )
    @test_throws ArgumentError with_raman_fraction(explicit_problem, 0.0)

    modes = 2
    multimode_fraction = 0.31
    multimode_problem = fiber_problem(
        Fiber(
            regime = :multimode,
            preset = :custom,
            length_m = 1e-4,
            power_w = 1e-5,
            beta_order = 2,
            raman_fraction = multimode_fraction,
        );
        modes = modes,
        pulse = Pulse(fwhm_s = 1e-12, rep_rate_hz = 50e6),
        grid = Grid(nt = 16, time_window_ps = 5.0, policy = :exact),
        initial_modes = ComplexF64[1, 1im],
        dispersion = zeros(16, modes),
        gamma_tensor = zeros(modes, modes, modes, modes),
        raman_threshold_thz = -0.25,
    )
    @test FiberLab._raman_response_metadata(multimode_problem.fiber).fraction ==
          multimode_fraction
    @test multimode_problem.metadata.requested_fiber.raman_fraction ==
          multimode_fraction
    multimode_off = with_raman_fraction(multimode_problem, 0)
    @test mode_count(multimode_off) == modes
    @test multimode_off.uω0 == multimode_problem.uω0
    @test multimode_off.fiber["Dω"] == multimode_problem.fiber["Dω"]
    @test multimode_off.fiber["γ"] == multimode_problem.fiber["γ"]
    @test FiberLab._raman_response_metadata(multimode_off.fiber).fraction == 0.0
end

@testset "Explicit launch replacement" begin
    problem = _physical_controls_problem()
    phase = 0.2 .* sin.(range(0, 2π; length = sample_count(problem)))
    launch = problem.uω0 .* cis.(reshape(phase, :, 1))
    shaped = with_launch(problem, launch)
    @test shaped.uω0 == launch
    @test problem.uω0 != launch
    @test shaped.fiber == problem.fiber
    @test shaped.fiber !== problem.fiber
    @test shaped.fiber["Dω"] !== problem.fiber["Dω"]
    @test shaped.sim == problem.sim
    @test shaped.sim !== problem.sim
    @test shaped.band_mask == problem.band_mask
    @test shaped.band_mask !== problem.band_mask
    @test shaped.raman_threshold_thz == problem.raman_threshold_thz
    @test shaped.metadata.construction_sha256 === nothing
    @test_throws ArgumentError with_launch(problem, launch[1:end-1, :])
    invalid = copy(launch)
    invalid[1] = NaN
    @test_throws ArgumentError with_launch(problem, invalid)

    stale = deepcopy(problem)
    stale.fiber["L"] *= 2
    @test_throws ArgumentError with_launch(stale, launch)

    explicit = fiber_field_problem(
        problem.uω0, problem.fiber, problem.sim;
        band_mask = problem.band_mask, preset = :explicit_test)
    @test with_launch(explicit, launch).uω0 == launch
end

@testset "Physical Taylor phase basis" begin
    coarse = _physical_controls_problem(nt = 16, time_window_ps = 4.0)
    fine = _physical_controls_problem(nt = 32, time_window_ps = 8.0)
    orders = (2, 3, 4)
    coarse_basis = taylor_phase_basis(coarse, orders)
    fine_basis = taylor_phase_basis(fine, orders)
    coarse_frequencies = FFTW.fftfreq(
        sample_count(coarse), 1 / coarse.sim["Δt"])
    fine_frequencies = FFTW.fftfreq(
        sample_count(fine), 1 / fine.sim["Δt"])
    for (coarse_index, frequency) in enumerate(coarse_frequencies)
        fine_index = findfirst(==(frequency), fine_frequencies)
        @test fine_index !== nothing
        @test coarse_basis[coarse_index, :] ≈ fine_basis[fine_index, :]
    end

    phi2_fs2 = 125.0
    phi2_basis = taylor_phase_basis(coarse, 2)
    omega_rad_ps = 2π .* coarse_frequencies
    expected_phase = (phi2_fs2 * 1e-6 / 2) .* omega_rad_ps .^ 2
    @test phi2_basis[:, 1] .* phi2_fs2 ≈ expected_phase

    scales = (125.0, 2_000.0, 50_000.0)
    scaled_basis = taylor_phase_basis(
        coarse,
        orders;
        coefficient_scales_fs = scales,
    )
    @test scaled_basis ≈ coarse_basis .* reshape(collect(scales), 1, :)
    @test taylor_phase_basis(
        coarse,
        2;
        coefficient_scales_fs = phi2_fs2,
    )[:, 1] ≈ expected_phase
    @test coarse_basis[1, :] == zeros(length(orders))
    @test coarse_basis[2, 2] ≈ -coarse_basis[end, 2]

    @test_throws ArgumentError taylor_phase_basis(coarse, Int[])
    @test_throws ArgumentError taylor_phase_basis(coarse, (-1, 2))
    @test_throws ArgumentError taylor_phase_basis(coarse, (2.0, 3.0))
    @test_throws ArgumentError taylor_phase_basis(coarse, (2, 2))
    @test_throws ArgumentError taylor_phase_basis(
        coarse, orders; coefficient_scales_fs = (1.0, 2.0))
    @test_throws ArgumentError taylor_phase_basis(
        coarse, orders; coefficient_scales_fs = (1.0, 0.0, 2.0))
    @test_throws ArgumentError taylor_phase_basis(
        coarse, orders; coefficient_scales_fs = (1.0, Inf, 2.0))
end
