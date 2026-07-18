using FFTW

@testset "Scientific comparison metrics" begin
    sim = FiberLab.get_disp_sim_params(1550e-9, 1, 256, 8.0, 2)
    time_ps = (collect(0:255) .- 128) .* sim["Δt"]
    reference_time = ComplexF64.(exp.(-0.5 .* (time_ps ./ 0.10) .^ 2))
    reference = ifft(reference_time)

    neutral = FiberLab.pulse_quality_metrics(reference, reference, sim)
    @test neutral.energy_ratio ≈ 1
    @test neutral.rms_duration_ratio ≈ 1
    @test neutral.peak_power_ratio ≈ 1
    @test neutral.main_lobe_energy_ratio ≈ 1
    @test neutral.main_lobe_reference_fraction >= 0.9
    neutral_check = FiberLab.pulse_quality_check(
        neutral;
        max_rms_duration_ratio = 1.1,
        min_peak_power_ratio = 0.85,
        min_main_lobe_energy_ratio = 0.9,
    )
    @test neutral_check.pass

    broadened_time = ComplexF64.(exp.(-0.5 .* (time_ps ./ 0.15) .^ 2))
    broadened_time .*= sqrt(sum(abs2, reference_time) / sum(abs2, broadened_time))
    broadened = ifft(broadened_time)
    quality = FiberLab.pulse_quality_metrics(reference, broadened, sim)
    @test quality.energy_ratio ≈ 1 rtol = 1e-12
    @test quality.rms_duration_ratio ≈ 1.5 rtol = 1e-3
    @test quality.peak_power_ratio < 1
    @test quality.main_lobe_energy_ratio < 1
    @test !FiberLab.pulse_quality_check(
        quality;
        max_rms_duration_ratio = 1.1,
        min_peak_power_ratio = 0.85,
        min_main_lobe_energy_ratio = 0.9,
    ).pass

    frequency = FFTW.fftfreq(256, 1 / sim["Δt"])
    shifted = reference .* cis.(-2π .* frequency .* (11 * sim["Δt"]))
    shifted_quality = FiberLab.pulse_quality_metrics(reference, shifted, sim)
    @test shifted_quality.rms_duration_ratio ≈ 1 rtol = 1e-12
    @test shifted_quality.main_lobe_energy_ratio ≈ 1 rtol = 1e-12

    red = FiberLab.frequency_band_mask(sim, (-16.0, -10.0))
    blue = FiberLab.frequency_band_mask(sim, (10.0, 16.0))
    @test red == ((-16.0 .<= frequency) .& (frequency .<= -10.0))
    @test blue == ((10.0 .<= frequency) .& (frequency .<= 16.0))
    @test !any(red .& blue)
    @test_throws ArgumentError FiberLab.frequency_band_mask(sim, (2.0, -2.0))
    @test_throws ArgumentError FiberLab.frequency_band_mask(sim, (100.0, 101.0))

    launch = ones(ComplexF64, 256, 1)
    raman_on = copy(launch)
    raman_off = copy(launch)
    raman_on[red, :] .*= 2
    raman_on[blue, :] .*= 1.25
    raman_off[red, :] .*= 1.5
    raman_off[blue, :] .*= 1.25
    attribution = FiberLab.counterfactual_band_metrics(
        raman_on,
        raman_off,
        launch;
        red_mask = red,
        blue_mask = blue,
    )
    @test attribution.red.on.relative_band_energy > attribution.red.off.relative_band_energy
    @test attribution.blue.on.relative_band_energy ≈ attribution.blue.off.relative_band_energy
    @test attribution.model_attributed_red_excess > 0
    @test attribution.model_attributed_asymmetry > 0
    @test attribution.red_log_ratio_db > 0

    spectrum_attribution = FiberLab.counterfactual_spectrum_metrics(
        raman_on,
        raman_off,
        launch,
        sim,
    )
    @test spectrum_attribution.on.relative_energy >
          spectrum_attribution.off.relative_energy
    @test spectrum_attribution.model_attributed_centroid_shift_thz < 0

    @test_throws ArgumentError FiberLab.counterfactual_band_metrics(
        raman_on,
        raman_off,
        launch;
        red_mask = red,
        blue_mask = red,
    )

    fiber = FiberLab.get_disp_fiber_params_user_defined(
        0.01,
        sim;
        fR = 0.18,
        gamma_user = 0.0,
        betas_user = [0.0],
    )
    problem = fiber_field_problem(launch, fiber, sim; band_mask = red)
    band_objective = FiberLab.spectral_band_energy_objective(problem, red)
    asymmetry_objective = FiberLab.spectral_asymmetry_objective(problem, red, blue)
    centroid_objective = FiberLab.spectral_centroid_objective(problem)
    probe = copy(launch)
    probe[red, :] .*= 2
    probe[blue, :] .*= 0.5
    launch_energy = sum(abs2, launch)
    expected_red = sum(abs2, probe[red, :]) / launch_energy
    expected_blue = sum(abs2, probe[blue, :]) / launch_energy
    @test objective_value(band_objective, probe) ≈ expected_red
    @test objective_value(asymmetry_objective, probe) ≈ expected_red - expected_blue
    expected_centroid = sum(
        frequency .* vec(sum(abs2, probe; dims = 2)),
    ) / sum(abs2, probe)
    @test objective_value(centroid_objective, probe) ≈ expected_centroid

    direction = reshape(ComplexF64.(cis.(range(0, 2π; length = 256))), :, 1)
    step = 1e-6
    for objective in (band_objective, asymmetry_objective, centroid_objective)
        finite_difference = (
            objective_value(objective, probe .+ step .* direction) -
            objective_value(objective, probe .- step .* direction)
        ) / (2step)
        terminal = terminal_adjoint(objective, probe)
        analytic = 2real(sum(conj.(terminal) .* direction))
        @test finite_difference ≈ analytic rtol = 1e-7 atol = 1e-10
    end
    @test_throws ArgumentError FiberLab.spectral_asymmetry_objective(
        problem,
        red,
        red,
    )
end
