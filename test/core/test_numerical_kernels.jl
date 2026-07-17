using FFTW
using LinearAlgebra
using Printf

@testset "YDFA gain initialization and propagation" begin
    sim = FiberLab.get_disp_sim_params(1030e-9, 1, 32, 5.0, 2)
    gain = FiberLab.get_YDFAParams(sim)
    @test length(gain.σas) == sim["Nt"]
    @test length(gain.σes) == sim["Nt"]
    @test all(isfinite, gain.σas)
    @test all(isfinite, gain.σes)
    @test all(>=(0), gain.σas)
    @test all(>=(0), gain.σes)

    _, launch = FiberLab.get_initial_state_gain_smf(
        [1.0], 1e-4, 300e-15, 80e6, "gauss", sim)
    fiber = FiberLab.get_disp_fiber_params_user_defined(
        1e-5, sim; fR = 0.0, gamma_user = 0.0, betas_user = [0.0])
    fiber["gain_parameters"] = gain
    solution = FiberLab.solve_disp_gain_smf(
        launch, fiber, sim; pump_power = 0.05)["ode_sol"]
    @test string(solution.retcode) == "Success"
    @test all(isfinite, solution(fiber["L"]))
end

@testset "Fourier convention in diagnostics" begin
    sim = FiberLab.get_disp_sim_params(1550e-9, 1, 64, 5.0, 2)
    tone_bin = 6
    spectrum = zeros(ComplexF64, sim["Nt"])
    spectrum[tone_bin] = 1.0
    temporal = fft(spectrum)
    expected_thz = FFTW.fftfreq(sim["Nt"], 1 / sim["Δt"])[tone_bin]

    @test FiberLab.compute_instantaneous_frequency(temporal, sim) ≈
        fill(expected_thz, sim["Nt"]) atol = 1e-12
end

@testset "Low-level simulation grid validation" begin
    @test_throws ArgumentError FiberLab.get_disp_sim_params(-1550e-9, 1, 64, 3.0, 2)
    @test_throws ArgumentError FiberLab.get_disp_sim_params(1550e-9, 0, 64, 3.0, 2)
    @test_throws ArgumentError FiberLab.get_disp_sim_params(1550e-9, 1, 63, 3.0, 2)
    @test_throws ArgumentError FiberLab.get_disp_sim_params(1550e-9, 1, 2, 3.0, 2)
    @test_throws ArgumentError FiberLab.get_disp_sim_params(1550e-9, 1, 64, -3.0, 2)
    @test_throws ArgumentError FiberLab.get_disp_sim_params(1550e-9, 1, 64, 3.0, 1)
    optical_grid_error = try
        FiberLab.get_disp_sim_params(1550e-9, 1, 8192, 12.0, 2)
        nothing
    catch error
        error
    end
    @test optical_grid_error isa ArgumentError
    @test occursin("requires time_window >", sprint(showerror, optical_grid_error))
    @test occursin("use at least 21.178 ps", sprint(showerror, optical_grid_error))

    mutated = FiberLab.get_disp_sim_params(1550e-9, 1, 64, 3.0, 2)
    mutated["Δt"] = -mutated["Δt"]
    @test_throws ArgumentError FiberLab.get_disp_fiber_params_user_defined(
        0.01, mutated; gamma_user = 1.0, betas_user = [0.0])
    mutated = FiberLab.get_disp_sim_params(1550e-9, 1, 64, 3.0, 2)
    mutated["Nt"] = 63
    @test_throws ArgumentError FiberLab.get_disp_fiber_params_user_defined(
        0.01, mutated; gamma_user = 1.0, betas_user = [0.0])
end

@testset "Grid-independent silica Raman response" begin
    fraction, tau1_ps, tau2_ps = 0.18, 12.2e-3, 32.0e-3
    for nt in (64, 128, 256, 512)
        sim = FiberLab.get_disp_sim_params(1550e-9, 1, nt, 3.0, 2)
        fiber = FiberLab.get_disp_fiber_params_user_defined(
            0.01,
            sim;
            fR = fraction,
            τ1 = 1e3tau1_ps,
            τ2 = 1e3tau2_ps,
            gamma_user = 1.0,
            betas_user = [0.0],
        )
        omega = 2π .* FFTW.fftfreq(nt, 1 / sim["Δt"])
        decay, resonance = inv(tau2_ps), inv(tau1_ps)
        amplitude = (tau1_ps^2 + tau2_ps^2) / (tau1_ps * tau2_ps^2)
        response = fraction .* amplitude .* resonance ./
            ((decay .+ 1im .* omega) .^ 2 .+ resonance^2)
        centered_response = cis.(-omega .* sim["time_window"] ./ 2) .* response
        centered_response[nt ÷ 2 + 1] = real(centered_response[nt ÷ 2 + 1])

        @test fiber["hRω"] ≈ centered_response rtol = 5e-14 atol = 5e-14
        @test real(fiber["hRω"][1]) ≈ fraction rtol = 5e-14
        @test fiber["one_m_fR"] ≈ 1 - fraction
        @test isreal(fiber["hRω"][nt ÷ 2 + 1])
        @test fiber["hRω"][2:nt÷2] ≈ conj.(reverse(fiber["hRω"][nt÷2+2:end]))
        @test fiber["raman_response_model"] == "blow_wood_single_damped_oscillator_v1"
        @test fiber["raman_fraction"] == fraction
        @test fiber["raman_tau1_fs"] == 1e3tau1_ps
        @test fiber["raman_tau2_fs"] == 1e3tau2_ps
    end

    sim = FiberLab.get_disp_sim_params(1550e-9, 1, 64, 3.0, 2)
    @test_throws ArgumentError FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; fR = -0.1, gamma_user = 1.0, betas_user = [0.0])
    @test_throws ArgumentError FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; fR = 1.1, gamma_user = 1.0, betas_user = [0.0])
    @test_throws ArgumentError FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; τ1 = 0.0, gamma_user = 1.0, betas_user = [0.0])
    @test_throws ArgumentError FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; τ2 = Inf, gamma_user = 1.0, betas_user = [0.0])
    @test_throws ArgumentError FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; τ1 = 1e-300, τ2 = 1e-300, gamma_user = 1.0, betas_user = [0.0])
    @test_throws ArgumentError FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; τ1 = 1e300, τ2 = 1e300, gamma_user = 1.0, betas_user = [0.0])

    partial = FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; gamma_user = 1.0, betas_user = [0.0])
    delete!(partial, "raman_tau2_fs")
    @test_throws ArgumentError fiber_field_problem(
        ones(ComplexF64, 64, 1), partial, sim)
    inconsistent = FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; gamma_user = 1.0, betas_user = [0.0])
    inconsistent["raman_fraction"] = 0.2
    @test_throws ArgumentError fiber_field_problem(
        ones(ComplexF64, 64, 1), inconsistent, sim)
    nonhermitian = FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; gamma_user = 1.0, betas_user = [0.0])
    nonhermitian["hRω"][2] += 0.1im
    @test_throws ArgumentError fiber_field_problem(
        ones(ComplexF64, 64, 1), nonhermitian, sim)
    false_model = FiberLab.get_disp_fiber_params_user_defined(
        0.01, sim; gamma_user = 1.0, betas_user = [0.0])
    false_model["hRω"][2] = false_model["hRω"][end] = 0
    @test_throws ArgumentError fiber_field_problem(
        ones(ComplexF64, 64, 1), false_model, sim)
end

@testset "Raman adjoint at the Nyquist seam" begin
    nt = 64
    sim = FiberLab.get_disp_sim_params(1550e-9, 1, nt, 3.0, 2)
    t_ps = sim["ts"] .* 1e12
    temporal = reshape(
        exp.(-0.5 .* (t_ps ./ 0.07) .^ 2) .* cis.(8 .* (t_ps ./ 0.07) .^ 2),
        :, 1,
    )
    launch = ifft(temporal, 1)
    fiber = FiberLab.get_disp_fiber_params_user_defined(
        0.05, sim; fR = 0.18, gamma_user = 2.0, betas_user = [0.0])
    problem = fiber_field_problem(launch, fiber, sim; preset = :nyquist_raman)
    weights = reshape(collect(range(0.3, 1.7; length = nt)), :, 1)
    objective = ObjectiveMap(
        :nyquist_probe;
        cost = field -> sum(weights .* abs2.(field)),
        terminal_adjoint = (field, context) -> weights .* field,
    )
    check = check_adjoint_gradient(
        fiber_model(problem),
        FullGridPhase(problem),
        objective,
        zeros(nt);
        coordinate_indices = [2, nt ÷ 2, nt ÷ 2 + 1, nt],
        step = 1e-6,
        atol = 1e-12,
        rtol = 1e-4,
    )
    @test check.pass
    @test maximum(check.relative_error) < 2e-5
end

@testset "Silica Raman shift has the Stokes sign" begin
    problem = fiber_problem(
        Fiber(
            preset = :HNLF_zero_disp,
            length_m = 0.02,
            power_w = 0.05,
            beta_order = 3,
        );
        grid = Grid(nt = 256, time_window_ps = 3.0, policy = :exact),
        raman_threshold_thz = nothing,
    )
    result = propagate(problem)
    frequency = FFTW.fftfreq(sample_count(problem), 1 / problem.sim["Δt"])
    centroid(field) = sum(frequency .* vec(sum(abs2, field; dims = 2))) / sum(abs2, field)
    shift_thz = centroid(result.output_spectrum) - centroid(result.input_spectrum)
    @test shift_thz < -1e-3
    @test metrics(result).max_photon_number_drift < 1e-6
end

@testset "Adjoint remains valid near temporal boundaries" begin
    nt = 128
    sim = FiberLab.get_disp_sim_params(1550e-9, 1, nt, 2.0, 2)
    sample = collect(1:nt)
    temporal = reshape((
        @. sqrt(4.0) * exp(-0.5 * ((sample - 5) / 5.0)^2) *
            cis(0.08 * (sample - 5)^2)
    ), nt, 1)
    gamma = fill(0.8, 1, 1, 1, 1)
    fiber = Dict{String,Any}(
        "Dω" => zeros(nt, 1),
        "γ" => gamma,
        "L" => 0.3,
        "hRω" => zeros(ComplexF64, nt),
        "one_m_fR" => 1.0,
        "zsave" => nothing,
        "reltol" => 1e-10,
        "abstol" => 1e-12,
    )
    band = FFTW.fftfreq(nt, 1 / sim["Δt"]) .< -3.0
    problem = fiber_field_problem(ifft(temporal, 1), fiber, sim; band_mask = band)
    coordinate = collect(0:nt-1)
    phase = @. 0.09sin(4π * coordinate / nt) + 0.04cos(10π * coordinate / nt)
    check = check_adjoint_gradient(
        fiber_model(problem),
        FullGridPhase(problem),
        raman_band_objective(problem),
        phase;
        coordinate_indices = [1, 5, nt ÷ 2, nt],
        step = 1e-5,
        atol = 1e-9,
        rtol = 2e-3,
    )
    @test check.pass
end

@testset "FFT and containment conventions" begin
    nt = 64
    sim = FiberLab.get_disp_sim_params(1550e-9, 1, nt, 10.0, 2)
    temporal = ComplexF64.(cis.(2π .* (0:nt-1) ./ nt))
    spectrum = ifft(temporal)
    @test fft(spectrum) ≈ temporal rtol = 1e-14
    @test nt * sum(abs2, spectrum) ≈ sum(abs2, temporal) rtol = 1e-14

    constant_metrics = FiberLab._field_metrics(ifft(ones(ComplexF64, nt, 1), 1), sim)
    impulse = zeros(ComplexF64, nt, 1)
    impulse[nt ÷ 2 + 1] = 1
    impulse_metrics = FiberLab._field_metrics(ifft(impulse, 1), sim)
    @test constant_metrics.temporal_edge_fraction == 6 / nt
    @test constant_metrics.spectral_edge_fraction == 0
    @test impulse_metrics.temporal_edge_fraction == 0
    @test impulse_metrics.spectral_edge_fraction == 6 / nt

    centered_impulse = zeros(ComplexF64, nt, 1)
    centered_impulse[nt ÷ 2 + 1] = 1
    edge_impulse = zeros(ComplexF64, nt, 1)
    edge_impulse[1] = 1
    centered_cost, _ = FiberLab._field_temporal_width_cost(
        ifft(centered_impulse, 1), sim)
    edge_cost, _ = FiberLab._field_temporal_width_cost(ifft(edge_impulse, 1), sim)
    @test centered_cost == 0
    @test edge_cost == 1

    field = reshape(ComplexF64.(cis.(0.17 .* (1:nt))), nt, 1)
    direction = reshape(ComplexF64.(cis.(0.31 .* (1:nt))), nt, 1)
    _, terminal = FiberLab._field_temporal_width_cost(field, sim)
    step = 1e-6
    plus = first(FiberLab._field_temporal_width_cost(field .+ step .* direction, sim))
    minus = first(FiberLab._field_temporal_width_cost(field .- step .* direction, sim))
    finite_difference = (plus - minus) / (2step)
    adjoint_direction = 2real(sum(conj.(terminal) .* direction))
    @test finite_difference ≈ adjoint_direction rtol = 1e-6 atol = 1e-8
end

@testset "Default-grid launch and Raman-convolution convergence" begin
    for wavelength_m in (1550e-9, 1030e-9)
        grid = resolve_sampling_grid(Grid(); wavelength_m=wavelength_m)
        @test grid == Grid(nt=1024, time_window_ps=10.0, policy=:exact)
        sim = FiberLab.get_disp_sim_params(
            wavelength_m, 1, grid.nt, grid.time_window_ps, 2)
        @test all(>(0), sim["fs"])
        @test minimum(sim["fs"]) / sim["f0"] > 0.7
    end

    function launch_and_raman(nt)
        sim = FiberLab.get_disp_sim_params(1550e-9, 1, nt, 10.0, 2)
        fiber = FiberLab.get_disp_fiber_params_user_defined(
            1e-5, sim; fR=0.18, gamma_user=0.0, betas_user=[0.0])
        _, uω = FiberLab.get_initial_state(
            ones(1), 0.05, 185e-15, 80.5e6, "sech_sq", sim)
        intensity = abs2.(fft(uω, 1)[:, 1])
        raman = real.(fftshift(ifft(fiber["hRω"] .* fft(ComplexF64.(intensity)))))
        return intensity, raman
    end

    intensity_1024, raman_1024 = launch_and_raman(1024)
    intensity_2048, raman_2048 = launch_and_raman(2048)
    matching = 1:2:2048
    @test maximum(abs.(intensity_1024 .- intensity_2048[matching])) /
          maximum(intensity_2048) < 1e-13
    @test maximum(abs.(raman_1024 .- raman_2048[matching])) /
          maximum(abs, raman_2048) < 1e-12
    @test norm(raman_1024 .- raman_2048[matching]) /
          norm(raman_2048[matching]) < 1e-12
end

@testset "Analytic continuous-wave Kerr propagation" begin
    nt, length_m, power_w, gamma = 64, 5.0, 2.0, 0.73
    sim = FiberLab.get_disp_sim_params(1550e-9, 1, nt, 10.0, 2)
    temporal = fill(ComplexF64(sqrt(power_w)), nt, 1)
    launch = ifft(temporal, 1)
    gamma_tensor = fill(gamma, 1, 1, 1, 1)
    fiber = Dict{String,Any}(
        "Dω" => zeros(Float64, nt, 1),
        "γ" => gamma_tensor,
        "L" => length_m,
        "hRω" => zeros(ComplexF64, nt),
        "one_m_fR" => 1.0,
        "zsave" => nothing,
    )
    base = fiber_field_problem(launch, fiber, sim; preset = :cw_kerr)
    loose, tight = deepcopy(base), deepcopy(base)
    loose.fiber["reltol"], loose.fiber["abstol"] = 1e-4, 1e-6
    tight.fiber["reltol"], tight.fiber["abstol"] = 1e-10, 1e-12
    expected = launch .* cis(gamma * power_w * length_m)
    loose_error = norm(propagate(loose).output_spectrum - expected) / norm(expected)
    tight_error = norm(propagate(tight).output_spectrum - expected) / norm(expected)

    @test tight_error < 1e-8
    @test tight_error < 1e-3loose_error
end
