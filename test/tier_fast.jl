# ═══════════════════════════════════════════════════════════════════════════════
# test/tier_fast.jl — Phase 16 fast tier (≤30 s, simulation-free)
# ═══════════════════════════════════════════════════════════════════════════════
# Pre-commit gate. No forward/adjoint solver calls. Runs on claude-code-host
# or any dev laptop without needing the burst VM.
#
# What this tier catches:
#   - Key Bug #2 (SPM time-window formula) via recommended_time_window().
#   - Output-format regressions via save_run/load_run round trip.
#   - Determinism-environment regressions via ensure_deterministic_environment().
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using Dates
using Printf

const _ROOT = normpath(joinpath(@__DIR__, ".."))

# We need common.jl's recommended_time_window. common.jl pulls in the full
# MultiModeNoise module which is heavy but import-time only (no simulation).
# Using MultiModeNoise first lets common.jl's `using MultiModeNoise` resolve.
# Printf must be imported at top-level BEFORE include(common.jl) because
# common.jl uses @sprintf — macros resolve at parse time and need Printf
# visible in the including scope (matches test/test_determinism.jl pattern).
using MultiModeNoise
include(joinpath(_ROOT, "scripts", "common.jl"))

@testset "Phase 16 — fast tier" begin

    @testset "SPM time window formula (Key Bug #2)" begin
        # Regression for STATE.md "Key Bugs Fixed" #2. Fixed formula:
        #   φ_NL = γ · P · L         (dimensionless radians, nonlinear phase)
        #   T0   = fwhm / 1.763      (sech² 1/e half-width, matches common.jl)
        #   δω_SPM = 0.86 · φ_NL / T0                 (rad/s)
        #   spm_ps = |β₂| · L · δω_SPM · 1e12         (ps contribution from SPM)
        #   walk_off_ps = |β₂| · L · 2π · 13e12 · 1e12
        #   total_ps    = walk_off_ps + spm_ps + 0.5 (pulse_extent)
        #   return max(5, ceil(Int, total_ps · safety_factor))
        #
        # Pre-fix bug: `γ·P·L` was treated as δω directly (wrong units), so the
        # SPM contribution was O(10^−15) too small → 5–7× undersized windows at
        # high power / long fiber.
        #
        # We use TWO assertions to pin both sides:
        #   (a) helper's output matches the fixed closed-form formula exactly
        #       (it's the same code path; drift would mean common.jl was edited
        #       away from the known-good form).
        #   (b) helper's output does NOT match the pre-bug formula, which
        #       would have produced the no-SPM window (δω_SPM ≈ 0 numerically).

        # HNLF-regime parameters chosen so SPM contribution exceeds ~1 ps,
        # survives the ceil() rounding, and is distinguishable from both the
        # no-SPM path and the pre-bug (γ·P·L-as-rad/s) formula.
        #
        # With these numbers:
        #   φ_NL       = 10 rad                 (deep nonlinear regime)
        #   T0         ≈ 1.05e-13 s
        #   δω_SPM     ≈ 8.2e13 rad/s
        #   spm_ps     ≈ 16.4 ps
        #   walk_off_ps ≈ 16.3 ps
        #   → tw_spm = 67, tw_no_spm = 34  (difference = 33 ps)
        #
        # Pre-bug formula with δω=γ·P·L would give δω_bug ≈ 10 rad/s,
        # spm_bug_ps ≈ 1.7e-12 ps → tw_bug = 34 (indistinguishable from no-SPM).
        γ    = 10e-3         # W^-1 m^-1 (HNLF regime — amplifies SPM signal)
        P    = 100.0         # W         (peak power)
        L    = 10.0          # m         (long fiber)
        β2   = 20e-27        # s²/m
        fwhm = 185e-15       # s

        # No-SPM baseline: helper called without gamma/P_peak kwargs.
        tw_no_spm = recommended_time_window(L; beta2=β2, pulse_fwhm=fwhm,
                                             safety_factor=2.0)

        # With-SPM: helper called with gamma/P_peak; activates the SPM branch.
        tw_spm = recommended_time_window(L; beta2=β2, gamma=γ, P_peak=P,
                                          pulse_fwhm=fwhm, safety_factor=2.0)

        # Closed-form recomputation (must match common.jl line-for-line).
        Δω_raman    = 2π * 13e12
        walk_off_ps = β2 * L * Δω_raman * 1e12
        T0          = fwhm / 1.763
        φ_NL        = γ * P * L
        δω_SPM      = 0.86 * φ_NL / T0
        spm_ps      = β2 * L * δω_SPM * 1e12
        expected_total_ps_spm    = walk_off_ps + spm_ps + 0.5
        expected_total_ps_no_spm = walk_off_ps + 0.5
        expected_tw_spm    = max(5, ceil(Int, expected_total_ps_spm * 2.0))
        expected_tw_no_spm = max(5, ceil(Int, expected_total_ps_no_spm * 2.0))

        # (a) Exact match with fixed formula.
        @test tw_spm    == expected_tw_spm
        @test tw_no_spm == expected_tw_no_spm

        # (b) SPM correction is observable (not swallowed by ceil/max floor).
        #     With the HNLF parameters above, SPM adds ~33 ps after safety×2.
        @test tw_spm > tw_no_spm
        @test (tw_spm - tw_no_spm) >= 10   # at least 10 ps of SPM-driven expansion

        # (c) Pre-bug formula check: if anyone restores δω = γ·P·L directly
        #     (treating radians as rad/s), δω_SPM_bug ≈ 0.065 rad/s → spm_ps_bug
        #     is O(10^−14) ps → indistinguishable from no-SPM window. The
        #     current helper MUST differ from that.
        δω_SPM_bug      = 0.86 * φ_NL            # wrong: treats φ_NL as rad/s
        spm_ps_bug      = β2 * L * δω_SPM_bug * 1e12
        expected_tw_bug = max(5, ceil(Int, (walk_off_ps + spm_ps_bug + 0.5) * 2.0))
        @test tw_spm != expected_tw_bug   # regression guard: bug is detectable
    end

    @testset "Output format round trip (D2 schema)" begin
        include(joinpath(_ROOT, "scripts", "polish_output_format.jl"))

        mktempdir() do dir
            path = joinpath(dir, "rt.jld2")
            result = (
                phi_opt             = collect(range(0.0, stop=π, length=64)),
                uω0                 = ComplexF64[i + 0.5im for i in 1:64],
                uωf                 = ComplexF64[0.1*i - 0.2im for i in 1:64],
                convergence_history = Float64[-3.0, -10.0, -25.0, -45.0],
                grid                = Dict("Nt"=>64, "Δt"=>1.5e-3,
                                           "ts"=>collect(1:64), "fs"=>collect(1:64),
                                           "ωs"=>collect(1:64)),
                fiber               = Dict("preset"=>"SMF28", "L"=>2.0),
                metadata            = Dict(
                    "run_id"         => "fastrt",
                    "git_sha"        => "0000000",
                    "julia_version"  => string(VERSION),
                    "timestamp_utc"  => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
                    "fiber_preset"   => "SMF28",
                    "L_m"            => 2.0,
                    "P_W"            => 0.2,
                    "lambda0_nm"     => 1550.0,
                    "pulse_fwhm_fs"  => 185.0,
                    "Nt"             => 64,
                    "time_window_ps" => 12.0,
                    "J_final_dB"     => -45.0,
                    "J_initial_dB"   => -3.0,
                    "n_iter"         => 3,
                    "converged"      => true,
                    "seed"           => 42,
                ),
            )
            sidecar_path = save_run(path, result)
            @test isfile(path)
            @test isfile(sidecar_path)

            loaded = load_run(path)
            @test loaded.phi_opt == result.phi_opt
            @test loaded.uω0     == result.uω0
            @test loaded.uωf     == result.uωf
            @test loaded.convergence_history == result.convergence_history
            @test String(loaded.sidecar.schema_version) == OUTPUT_FORMAT_SCHEMA_VERSION
            @test loaded.metadata["run_id"] == "fastrt"

            # Also: loading via the JSON sidecar path resolves to the same data.
            loaded_json = load_run(joinpath(dir, "rt.json"))
            @test loaded_json.phi_opt == result.phi_opt
        end
    end

    @testset "Determinism helper smoke test (Phase 15)" begin
        include(joinpath(_ROOT, "scripts", "determinism.jl"))

        ensure_deterministic_environment()
        st1 = deterministic_environment_status()
        @test st1.applied == true
        @test st1.fftw_threads == 1
        @test st1.blas_threads == 1

        # Idempotent — second call changes nothing
        ensure_deterministic_environment()
        st2 = deterministic_environment_status()
        @test st2 == st1
    end

    @testset "Pulse form validation" begin
        sim = Dict(
            "M" => 1,
            "Nt" => 8,
            "ts" => collect(range(-1.0, 1.0; length=8)),
        )
        u0_modes = [1.0]

        @test_throws ArgumentError MultiModeNoise.get_initial_state(
            u0_modes, 0.1, 185e-15, 80.5e6, "lorentzian", sim)
        @test_throws ArgumentError MultiModeNoise.get_initial_state_gain_smf(
            u0_modes, 0.1, 185e-15, 80.5e6, "lorentzian", sim)
    end

end
