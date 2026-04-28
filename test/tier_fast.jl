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
# visible in the including scope (matches test/core/test_determinism.jl pattern).
using MultiModeNoise
include(joinpath(_ROOT, "scripts", "lib", "common.jl"))
include(joinpath(_ROOT, "scripts", "lib", "canonical_runs.jl"))
include(joinpath(_ROOT, "scripts", "lib", "experiment_spec.jl"))
include(joinpath(_ROOT, "scripts", "lib", "manifest_io.jl"))
include(joinpath(_ROOT, "scripts", "lib", "objective_surface.jl"))
include(joinpath(_ROOT, "scripts", "lib", "regularizers.jl"))
include(joinpath(@__DIR__, "core", "test_repo_structure.jl"))
include(joinpath(@__DIR__, "core", "test_canonical_lab_surface.jl"))
include(joinpath(@__DIR__, "core", "test_experiment_front_layer.jl"))
include(joinpath(@__DIR__, "core", "test_experiment_sweep_sidecars.jl"))
include(joinpath(@__DIR__, "core", "test_research_engine_acceptance.jl"))
include(joinpath(@__DIR__, "core", "test_experiment_config_adversarial.jl"))
include(joinpath(@__DIR__, "core", "test_experiment_sweep_adversarial.jl"))
include(joinpath(@__DIR__, "core", "test_research_extension_integration.jl"))
include(joinpath(@__DIR__, "core", "test_non_raman_objective_integration.jl"))
include(joinpath(@__DIR__, "core", "test_gain_tilt_variable_integration.jl"))
include(joinpath(@__DIR__, "core", "test_regime_promotion_status.jl"))

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

    @testset "Single-mode setup contract" begin
        kwargs = (
            λ0 = 1550e-9,
            M = 1,
            Nt = 1024,
            time_window = 10.0,
            β_order = 3,
            L_fiber = 1.0,
            P_cont = 0.05,
            pulse_fwhm = 185e-15,
            pulse_rep_rate = 80.5e6,
            pulse_shape = "sech_sq",
            raman_threshold = -5.0,
            fiber_preset = :SMF28,
        )

        uω0_r, fiber_r, sim_r, band_r, Δf_r, thr_r = setup_raman_problem(; kwargs...)
        uω0_a, fiber_a, sim_a, band_a, Δf_a, thr_a = setup_amplitude_problem(; kwargs...)

        @test size(uω0_r) == (sim_r["Nt"], sim_r["M"])
        @test sim_r["Nt"] == sim_a["Nt"]
        @test sim_r["M"] == sim_a["M"]
        @test sim_r["Δt"] == sim_a["Δt"]
        @test fiber_r["L"] == fiber_a["L"]
        @test fiber_r["γ"] == fiber_a["γ"]
        @test fiber_r["Dω"] == fiber_a["Dω"]
        @test uω0_r == uω0_a
        @test band_r == band_a
        @test Δf_r == Δf_a
        @test thr_r == thr_a == kwargs.raman_threshold
        @test any(band_r)
    end

    @testset "Average-to-peak power conversion" begin
        P_cont = 0.20
        fwhm = 185e-15
        rep_rate = 80.5e6

        P_peak_sech = peak_power_from_average_power(P_cont, fwhm, rep_rate)
        P_peak_gauss = peak_power_from_average_power(P_cont, fwhm, rep_rate;
            pulse_shape="gaussian")
        @test P_peak_sech ≈ 0.881374 * P_cont / (fwhm * rep_rate)
        @test P_peak_gauss ≈ 0.939437 * P_cont / (fwhm * rep_rate)

        summary = print_fiber_summary(
            gamma = 1.1e-3,
            betas = [-2.17e-26, 1.2e-40],
            P_cont = P_cont,
            pulse_fwhm = fwhm,
            pulse_rep_rate = rep_rate,
        )
        @test summary.P_peak ≈ P_peak_sech
    end

    @testset "Exact single-mode setup preserves requested grid" begin
        exact_kwargs = (
            λ0 = 1550e-9,
            M = 1,
            Nt = 1024,
            time_window = 5.0,
            β_order = 3,
            L_fiber = 10.0,
            P_cont = 0.10,
            pulse_fwhm = 185e-15,
            pulse_rep_rate = 80.5e6,
            pulse_shape = "sech_sq",
            raman_threshold = -5.0,
            fiber_preset = :SMF28,
        )

        uω0_exact, fiber_exact, sim_exact, band_exact, Δf_exact, thr_exact =
            setup_raman_problem_exact(; exact_kwargs...)
        uω0_auto, fiber_auto, sim_auto, band_auto, Δf_auto, thr_auto =
            setup_raman_problem(; exact_kwargs...)

        @test sim_exact["Nt"] == exact_kwargs.Nt
        @test sim_exact["Δt"] * sim_exact["Nt"] == exact_kwargs.time_window
        @test size(uω0_exact) == (exact_kwargs.Nt, exact_kwargs.M)
        @test size(fiber_exact["Dω"]) == (exact_kwargs.Nt, exact_kwargs.M)
        @test length(band_exact) == exact_kwargs.Nt
        @test length(Δf_exact) == exact_kwargs.Nt
        @test thr_exact == exact_kwargs.raman_threshold

        @test sim_auto["Nt"] >= sim_exact["Nt"]
        @test sim_auto["Δt"] * sim_auto["Nt"] >= sim_exact["Δt"] * sim_exact["Nt"]
        @test sim_auto["Nt"] > sim_exact["Nt"] ||
              sim_auto["Δt"] * sim_auto["Nt"] > sim_exact["Δt"] * sim_exact["Nt"]
        @test fiber_exact["L"] == fiber_auto["L"] == exact_kwargs.L_fiber
        @test fiber_exact["γ"] == fiber_auto["γ"]
        @test thr_auto == thr_exact
        @test any(band_auto) && any(band_exact)
    end

    @testset "Canonical run registry" begin
        specs = canonical_raman_run_specs()
        ids = [spec.id for spec in specs]

        @test length(specs) == 5
        @test ids == [
            :smf28_L1m_P005W,
            :smf28_L2m_P030W,
            :hnlf_L1m_P005W,
            :hnlf_L2m_P005W,
            :smf28_L5m_P015W,
        ]
        @test [spec.fiber_preset for spec in specs] == [
            :SMF28, :SMF28, :HNLF, :HNLF, :SMF28,
        ]
        @test specs[1].kwargs.fiber_name == "SMF-28"
        @test specs[3].kwargs.fiber_name == "HNLF"
        @test specs[4].kwargs.max_iter == 100
        @test specs[5].kwargs.P_cont == 0.15
        @test canonical_run_output_dir("tmpfiber", "L1m_P1W"; create=false) ==
              joinpath("results", "raman", "tmpfiber", "L1m_P1W")
    end

    @testset "Regularizer helper formulas" begin
        φ = reshape(collect(range(-0.2, stop=0.3, length=18)), 6, 3)
        Δt = 0.0125
        λ_gdd = 2e-4
        grad = zeros(size(φ))
        J_helper = add_gdd_penalty!(grad, φ, Δt, λ_gdd)

        Δω = 2π / (size(φ, 1) * Δt)
        inv_Δω3 = 1.0 / Δω^3
        J_ref = 0.0
        grad_ref = zeros(size(φ))
        for m in 1:size(φ, 2)
            for i in 2:(size(φ, 1) - 1)
                d2 = φ[i+1, m] - 2φ[i, m] + φ[i-1, m]
                J_ref += λ_gdd * inv_Δω3 * d2^2
                coeff = 2 * λ_gdd * inv_Δω3 * d2
                grad_ref[i-1, m] += coeff
                grad_ref[i, m] -= 2 * coeff
                grad_ref[i+1, m] += coeff
            end
        end
        @test J_helper ≈ J_ref
        @test grad ≈ grad_ref

        uω = ComplexF64[sin(i / 3) + im*cos(i / 5) for i in 1:16, _ in 1:2]
        grad_b = zeros(Float64, size(uω))
        J_b = add_boundary_phase_penalty!(grad_b, uω, 0.7; edge_fraction_floor=0.0)

        Nt = size(uω, 1)
        n_edge = max(1, Nt ÷ 20)
        ut0 = ifft(uω, 1)
        mask_edge = zeros(Float64, size(uω))
        mask_edge[1:n_edge, :] .= 1.0
        mask_edge[end-n_edge+1:end, :] .= 1.0
        E_total_input = max(sum(abs2, ut0), eps())
        edge_frac = sum(abs2.(ut0) .* mask_edge) / E_total_input
        grad_b_ref = (2 * 0.7 / (Nt * E_total_input)) .* imag.(conj.(uω) .* fft(mask_edge .* ut0, 1))
        @test J_b ≈ 0.7 * edge_frac
        @test grad_b ≈ grad_b_ref

        grad_log = copy(grad_b_ref)
        J_log = apply_log_surface!(grad_log, J_b)
        @test J_log ≈ 10 * log10(max(J_b, 1e-15))
        @test grad_log ≈ grad_b_ref .* (10.0 / (max(J_b, 1e-15) * log(10.0)))
    end

    @testset "Objective surface helper" begin
        terms = active_linear_terms(
            ["J_physics"],
            [(true, "λ_gdd*R_gdd"), (false, "λ_boundary*R_boundary"), (true, "λ_tv*R_tv")],
        )
        spec = build_objective_surface_spec(;
            objective_label = "test objective",
            log_cost = true,
            linear_terms = terms,
            leading_fields = (variant = "sum",),
            trailing_fields = (lambda_gdd = 1e-4, lambda_tv = 0.2),
        )

        @test spec.variant == "sum"
        @test spec.objective_label == "test objective"
        @test spec.scale == "dB"
        @test spec.pre_log_linear_surface == "J_physics + λ_gdd*R_gdd + λ_tv*R_tv"
        @test spec.scalar_surface == "10*log10(J_physics + λ_gdd*R_gdd + λ_tv*R_tv)"
        @test spec.regularizers_chained_into_surface === true
        @test spec.lambda_gdd == 1e-4
    end

    @testset "Manifest append/replace helper" begin
        mktempdir() do dir
            path = joinpath(dir, "manifest.json")
            n1 = update_manifest_entry(path, Dict{String,Any}(
                "result_file" => "a.jld2", "J_after_dB" => -10.0))
            n2 = update_manifest_entry(path, Dict{String,Any}(
                "result_file" => "b.jld2", "J_after_dB" => -20.0))
            n3 = update_manifest_entry(path, Dict{String,Any}(
                "result_file" => "a.jld2", "J_after_dB" => -30.0))

            manifest = read_manifest(path)
            @test n1 == 1
            @test n2 == 2
            @test n3 == 2
            @test length(manifest) == 2
            @test manifest[1]["result_file"] == "a.jld2"
            @test manifest[1]["J_after_dB"] == -30.0
            @test manifest[2]["result_file"] == "b.jld2"
        end
    end

    @testset "Canonical run loader via package manifest helpers" begin
        mktempdir() do dir
            manifest_path = joinpath(dir, "manifest.json")

            payload_a = (
                fiber_name = "SMF-28",
                run_tag = "a",
                L_m = 1.0,
                P_cont_W = 0.1,
                lambda0_nm = 1550.0,
                fwhm_fs = 185.0,
                gamma = 1.1e-3,
                betas = [-2.17e-26, 1.2e-40],
                Nt = 8,
                time_window_ps = 0.08,
                J_before = 1e-3,
                J_after = 1e-5,
                delta_J_dB = -20.0,
                grad_norm = 1e-4,
                converged = true,
                iterations = 3,
                wall_time_s = 0.1,
                convergence_history = [-10.0, -20.0],
                phi_opt = reshape(collect(1.0:8.0), 8, 1),
                uomega0 = reshape(ComplexF64[complex(i, -i) for i in 1:8], 8, 1),
                E_conservation = 1e-6,
                bc_input_frac = 1e-7,
                bc_output_frac = 2e-7,
                bc_input_ok = true,
                bc_output_ok = true,
                trust_report = Dict{String,Any}("overall_verdict" => "PASS"),
                trust_report_md = "a.md",
                band_mask = [i <= 4 for i in 1:8],
                sim_Dt = 0.01,
                sim_omega0 = 1215.0,
            )
            payload_b = merge(payload_a, (run_tag = "b", J_after = 1e-6, trust_report_md = "b.md"))

            path_a = joinpath(dir, "a.jld2")
            path_b = joinpath(dir, "b.jld2")
            save_run(path_a, payload_a)
            save_run(path_b, payload_b)

            n1 = update_run_manifest_entry(manifest_path, Dict{String,Any}(
                "result_file" => path_a,
                "J_after_dB" => MultiModeNoise.lin_to_dB(payload_a.J_after),
                "fiber_name" => payload_a.fiber_name,
            ))
            n2 = update_run_manifest_entry(manifest_path, Dict{String,Any}(
                "result_file" => path_b,
                "J_after_dB" => MultiModeNoise.lin_to_dB(payload_b.J_after),
                "fiber_name" => payload_b.fiber_name,
            ))

            @test n1 == 1
            @test n2 == 2

            runs = load_canonical_runs(manifest_path)
            @test length(runs) == 2
            @test runs[1]["result_file"] == path_a
            @test runs[1]["run_tag"] == "a"
            @test runs[2]["run_tag"] == "b"
            @test runs[2]["J_after"] == payload_b.J_after
        end
    end

    @testset "Output format round trip (legacy package schema)" begin
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

    @testset "Output format round trip (canonical Raman schema)" begin
        mktempdir() do dir
            path = joinpath(dir, "canon.jld2")
            result = (
                fiber_name = "SMF-28",
                run_tag = "canon-rt",
                L_m = 2.0,
                P_cont_W = 0.2,
                lambda0_nm = 1550.0,
                fwhm_fs = 185.0,
                gamma = 1.1e-3,
                betas = [-2.17e-26, 1.2e-40],
                Nt = 64,
                time_window_ps = 12.0,
                J_before = 1e-3,
                J_after = 1e-5,
                delta_J_dB = -20.0,
                grad_norm = 1e-4,
                converged = true,
                iterations = 7,
                wall_time_s = 1.5,
                convergence_history = Float64[-10.0, -20.0, -30.0],
                phi_opt = reshape(collect(range(0.0, stop=π, length=64)), 64, 1),
                uomega0 = reshape(ComplexF64[i + 0.5im for i in 1:64], 64, 1),
                E_conservation = 1e-6,
                bc_input_frac = 1e-7,
                bc_output_frac = 2e-7,
                bc_input_ok = true,
                bc_output_ok = true,
                trust_report = Dict{String,Any}("overall_verdict" => "PASS"),
                trust_report_md = "canon_trust.md",
                band_mask = [i <= 16 for i in 1:64],
                sim_Dt = 1.5e-3,
                sim_omega0 = 1215.0,
            )

            sidecar_path = save_run(path, result)
            @test isfile(path)
            @test isfile(sidecar_path)

            loaded = load_run(path)
            @test loaded.run_tag == result.run_tag
            @test loaded.phi_opt == result.phi_opt
            @test loaded.uomega0 == result.uomega0
            @test loaded.J_after == result.J_after
            @test loaded.metadata["run_id"] == "canon"
            @test loaded.metadata["fiber_preset"] == "SMF-28"
            @test loaded.sidecar.J_final_dB ≈ MultiModeNoise.lin_to_dB(result.J_after)

            loaded_json = load_run(joinpath(dir, "canon.json"))
            @test loaded_json.run_tag == result.run_tag
            @test loaded_json.band_mask == result.band_mask
        end
    end

    @testset "Determinism helper smoke test (Phase 15)" begin
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
