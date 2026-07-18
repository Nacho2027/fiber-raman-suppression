using FFTW
using LinearAlgebra

@testset "Scalar fixed-step propagation cross-check" begin
    fiber = Fiber(
        preset = :SMF28,
        length_m = 0.02,
        power_w = 0.02,
        beta_order = 3,
    )
    pulse = Pulse(fwhm_s = 185e-15, rep_rate_hz = 80.5e6, shape = :sech_sq)
    grid = Grid(nt = 128, time_window_ps = 4.0, policy = :exact)
    problem = fiber_problem(
        fiber;
        pulse = pulse,
        grid = grid,
        raman_threshold_thz = nothing,
    )

    @test_throws ArgumentError FiberLab._scalar_rk4_output(problem; steps = 0)
    @test_throws ArgumentError FiberLab._scalar_rk4_output(problem; steps = true)
    @test FiberLab._doubling_step_schedule((8, 16, 32)) == (8, 16, 32)
    @test_throws ArgumentError FiberLab._doubling_step_schedule((8, 16))
    @test_throws ArgumentError FiberLab._doubling_step_schedule((8, 12, 24))
    @test_throws ArgumentError FiberLab._doubling_step_schedule((8, true, 32))

    linear_fiber = deepcopy(problem.fiber)
    linear_fiber["γ"] .= 0
    linear = fiber_field_problem(
        problem.uω0,
        linear_fiber,
        deepcopy(problem.sim);
        preset = :linear_oracle,
    )
    linear_output = FiberLab._scalar_rk4_output(linear; steps = 4)
    expected_linear = cis.(linear.fiber["Dω"] .* linear.fiber["L"]) .* linear.uω0
    @test linear_output ≈ expected_linear rtol = 2e-15 atol = 2e-15

    cw_sim = FiberLab.get_disp_sim_params(1550e-9, 1, 64, 2.0, 2)
    cw_length, cw_gamma, cw_power = 2.0, 1.0, 5.0
    cw_fiber = FiberLab.get_disp_fiber_params_user_defined(
        cw_length,
        cw_sim;
        fR = 0.0,
        gamma_user = cw_gamma,
        betas_user = [0.0],
    )
    cw_time = fill(ComplexF64(sqrt(cw_power)), 64, 1)
    cw_launch = ifft(cw_time, 1)
    cw = fiber_field_problem(cw_launch, cw_fiber, cw_sim; preset = :cw_oracle)
    cw_exact = cw_launch .* cis(cw_gamma * cw_power * cw_length)
    cw_outputs = [FiberLab._scalar_rk4_output(cw; steps) for steps in (32, 64, 128)]
    cw_errors = [norm(output - cw_exact) for output in cw_outputs]
    @test log2(cw_errors[1] / cw_errors[2]) > 3.5
    @test log2(cw_errors[2] / cw_errors[3]) > 3.5
    @test cw_errors[end] / norm(cw_exact) < 1e-4

    strict(problem) = begin
        resolved = deepcopy(problem.fiber)
        resolved["reltol"], resolved["abstol"] = 1e-11, 1e-12
        fiber_field_problem(
            problem.uω0,
            resolved,
            deepcopy(problem.sim);
            preset = problem.metadata.preset,
        )
    end
    for candidate in (problem, with_raman_fraction(problem, 0.0))
        canonical = propagate(strict(candidate)).output_spectrum
        reference = FiberLab._scalar_rk4_output(candidate; steps = 128)
        @test norm(reference - canonical) / norm(canonical) < 1e-7
        @test FiberLab._scalar_reference_centroid_thz(reference, candidate) ≈
              counterfactual_spectrum_metrics(
                  reference, canonical, candidate.uω0, candidate).on.centroid_thz rtol = 1e-13
    end

    multimode_sim = deepcopy(problem.sim)
    multimode_sim["M"] = 2
    multimode_fiber = deepcopy(problem.fiber)
    multimode_fiber["Dω"] = repeat(problem.fiber["Dω"], 1, 2)
    multimode_fiber["γ"] = zeros(Float64, 2, 2, 2, 2)
    multimode = fiber_field_problem(
        repeat(problem.uω0, 1, 2),
        multimode_fiber,
        multimode_sim;
        preset = :multimode_rejection,
    )
    @test_throws ArgumentError FiberLab._scalar_rk4_output(multimode; steps = 8)

end
