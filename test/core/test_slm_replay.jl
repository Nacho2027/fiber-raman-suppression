using JSON3

include(joinpath(_ROOT, "scripts", "lib", "slm_replay.jl"))

@testset "Generic SLM replay" begin
    @testset "Profile loading validates the device-agnostic contract" begin
        mktempdir() do dir
            profile_path = joinpath(dir, "generic.toml")
            write(profile_path, """
profile_id = "generic_test_4px"
kind = "spectral_phase_slm"
vendor = "generic"
device_model = "abstract"

[pixel_grid]
axis = "frequency"
n_pixels = 4
active_min_THz = -2.0
active_max_THz = 2.0
interpolation = "linear"
outside_active_policy = "zero_phase"

[phase]
units = "rad"
range = "0_to_2pi"
wrap = true
bit_depth = 10
quantize = true

[calibration]
wavelength_to_pixel = "none"
phase_lut = "none"
wavefront_correction = "none"
polarization = "assumed_aligned"

[replay]
smoothing_kernel_pixels = 0
crosstalk_kernel = "none"
require_replay_simulation = true
max_allowed_replay_loss_dB = 6.0
""")

            profile = load_slm_replay_profile(profile_path)
            @test profile.profile_id == "generic_test_4px"
            @test profile.pixel_grid.n_pixels == 4
            @test profile.phase.bit_depth == 10
            @test profile.replay.max_allowed_replay_loss_dB == 6.0
        end

        mktempdir() do dir
            bad_profile = joinpath(dir, "bad.toml")
            write(bad_profile, """
profile_id = "bad"
kind = "spectral_phase_slm"

[pixel_grid]
n_pixels = 0
active_min_THz = -1.0
active_max_THz = 1.0

[phase]
range = "0_to_2pi"
bit_depth = 8
""")
            @test_throws ArgumentError load_slm_replay_profile(bad_profile)
        end
    end

    @testset "Linear replay preserves linear phase on the active band" begin
        profile = slm_replay_profile(;
            profile_id = "linear_no_quant",
            n_pixels = 5,
            active_min_THz = -2.0,
            active_max_THz = 2.0,
            quantize = false,
            wrap = false,
            smoothing_kernel_pixels = 0,
        )
        rel_f = collect(-4.0:1.0:4.0)
        phi = 0.3 .* rel_f .+ 0.2

        replay = replay_slm_phase(phi, rel_f, profile)
        active = findall(x -> -2.0 <= x <= 2.0, rel_f)
        inactive = setdiff(eachindex(rel_f), active)

        @test replay.phi_replayed[active] ≈ phi[active] atol=1e-12
        @test all(iszero, replay.phi_replayed[inactive])
        @test length(replay.pixel_centers_THz) == 5
        @test replay.profile_id == "linear_no_quant"
    end

    @testset "Wrapped quantized replay emits legal hardware phase levels" begin
        profile = slm_replay_profile(;
            profile_id = "wrapped_2bit",
            n_pixels = 4,
            active_min_THz = -1.5,
            active_max_THz = 1.5,
            quantize = true,
            wrap = true,
            bit_depth = 2,
            smoothing_kernel_pixels = 0,
        )
        rel_f = [-1.5, -0.5, 0.5, 1.5]
        phi = [-0.1, 0.2, 2pi + 0.3, 4pi - 0.1]

        replay = replay_slm_phase(phi, rel_f, profile)
        step = 2pi / 2^profile.phase.bit_depth

        @test all(0 .<= replay.pixel_phase_rad .< 2pi)
        @test all(isapprox.(replay.pixel_phase_rad ./ step,
            round.(replay.pixel_phase_rad ./ step); atol=1e-12))
        @test all(0 .<= mod.(replay.phi_replayed, 2pi) .< 2pi)
    end

    @testset "Replay survival status uses ideal-vs-replayed dB degradation" begin
        profile = slm_replay_profile(;
            profile_id = "threshold",
            n_pixels = 8,
            active_min_THz = -4.0,
            active_max_THz = 4.0,
            max_allowed_replay_loss_dB = 6.0,
        )

        pass_status = slm_replay_survival_status(-45.0, -40.0, profile)
        fail_status = slm_replay_survival_status(-45.0, -35.0, profile)

        @test pass_status.pass
        @test pass_status.replay_loss_dB == 5.0
        @test !fail_status.pass
        @test fail_status.replay_loss_dB == 10.0
    end

    @testset "Replay bundle writes phase CSV and machine-readable metadata" begin
        profile = slm_replay_profile(;
            profile_id = "bundle_test",
            n_pixels = 3,
            active_min_THz = -1.0,
            active_max_THz = 1.0,
            quantize = false,
            wrap = false,
        )
        rel_f = [-2.0, -1.0, 0.0, 1.0, 2.0]
        phi = [9.0, 0.1, 0.2, 0.3, 9.0]
        replay = replay_slm_phase(phi, rel_f, profile)

        mktempdir() do dir
            bundle = write_slm_replay_bundle(dir, replay;
                source_artifact = "source_result.jld2",
                ideal_J_dB = -30.0,
                replayed_J_dB = -28.0,
            )

            @test isfile(bundle.replayed_phase_csv)
            @test isfile(bundle.pixel_phase_csv)
            @test isfile(bundle.metadata_json)

            metadata = JSON3.read(read(bundle.metadata_json, String))
            @test metadata.profile_id == "bundle_test"
            @test metadata.source_artifact == "source_result.jld2"
            @test metadata.survival.pass == true
            @test metadata.survival.replay_loss_dB == 2.0
        end
    end

    @testset "Replay bundle can omit forward evaluation without invalid JSON" begin
        profile = slm_replay_profile(;
            profile_id = "no_eval_bundle",
            n_pixels = 3,
            active_min_THz = -1.0,
            active_max_THz = 1.0,
            quantize = false,
            wrap = false,
        )
        replay = replay_slm_phase([0.0, 0.1, 0.2], [-1.0, 0.0, 1.0], profile)

        mktempdir() do dir
            bundle = write_slm_replay_bundle(dir, replay; source_artifact = "source_result.jld2")
            metadata = JSON3.read(read(bundle.metadata_json, String))
            @test metadata.survival.pass == false
            @test metadata.survival.ideal_J_dB === nothing
            @test metadata.survival.replayed_J_dB === nothing
            @test metadata.survival.replay_loss_dB === nothing
        end
    end
end
