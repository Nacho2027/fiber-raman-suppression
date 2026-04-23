using Test
using Random
using Printf

const _ROOT = normpath(joinpath(@__DIR__, "..", ".."))

using MultiModeNoise
include(joinpath(_ROOT, "scripts", "lib", "common.jl"))
include(joinpath(_ROOT, "scripts", "lib", "determinism.jl"))
ensure_deterministic_environment()
include(joinpath(_ROOT, "scripts", "lib", "raman_optimization.jl"))

@testset "Phase 27 numerics regressions" begin
    @testset "Boundary checker measures pre-attenuator edge fraction" begin
        Nt = 128
        attenuator = ones(Nt, 1)
        attenuator[1:6, 1] .= 1e-4
        attenuator[end-5:end, 1] .= 1e-4
        sim = Dict("Nt" => Nt, "attenuator" => attenuator)

        ut_physical = zeros(Nt, 1)
        ut_physical[1:6, 1] .= 1.0
        ut_post = attenuator .* ut_physical

        ok, frac = check_boundary_conditions(ut_post, sim; threshold=1e-3)
        @test !ok
        @test frac > 0.9
    end

    @testset "Regularized log-cost gradient matches finite differences" begin
        Random.seed!(42)
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            Nt=2^7, time_window=5.0, β_order=2, L_fiber=0.05, P_cont=0.01)
        φ = 0.02 .* randn(sim["Nt"], sim["M"])

        J0, grad = cost_and_gradient(φ, uω0, fiber, sim, band_mask;
            λ_gdd=1e-4, λ_boundary=0.5, log_cost=true)

        spectral_power = vec(sum(abs2.(uω0), dims=2))
        idx = findmax(spectral_power)[2]
        ε = 1e-6

        φp = copy(φ)
        φp[idx, 1] += ε
        Jp, _ = cost_and_gradient(φp, uω0, fiber, sim, band_mask;
            λ_gdd=1e-4, λ_boundary=0.5, log_cost=true)

        φm = copy(φ)
        φm[idx, 1] -= ε
        Jm, _ = cost_and_gradient(φm, uω0, fiber, sim, band_mask;
            λ_gdd=1e-4, λ_boundary=0.5, log_cost=true)

        fd = (Jp - Jm) / (2ε)
        rel_err = abs(fd - grad[idx, 1]) / max(abs(fd), abs(grad[idx, 1]), 1e-12)

        @test isfinite(J0)
        @test rel_err < 5e-2
    end

    @testset "Gradient Taylor remainder tracks the scalar objective" begin
        Random.seed!(314)
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            Nt=2^7, time_window=5.0, β_order=2, L_fiber=0.05, P_cont=0.01)
        φ = 0.02 .* randn(sim["Nt"], sim["M"])
        v = randn(sim["Nt"], sim["M"])
        v ./= norm(v)

        result = validate_gradient_taylor(φ, v, uω0, fiber, sim, band_mask;
            λ_gdd=1e-4, λ_boundary=0.5, log_cost=true,
            eps_range=10.0 .^ (-2:-0.5:-5))

        @test result.slope > 1.7
        @test result.slope < 2.3
    end

    @testset "Chirp sensitivity returns linear J for plotting" begin
        Random.seed!(7)
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            Nt=2^7, time_window=5.0, β_order=2, L_fiber=0.05, P_cont=0.01)
        φ_opt = zeros(sim["Nt"], sim["M"])

        gdd_range, J_gdd, tod_range, J_tod = chirp_sensitivity(
            φ_opt, uω0, fiber, sim, band_mask;
            gdd_range=range(-0.01, 0.01, length=3),
            tod_range=range(-0.001, 0.001, length=3))

        @test all(J_gdd .> 0)
        @test all(J_tod .> 0)

        mktempdir() do dir
            save_prefix = joinpath(dir, "chirp")
            plot_chirp_sensitivity(gdd_range, J_gdd, tod_range, J_tod;
                save_prefix=save_prefix)
            @test isfile(save_prefix * ".png")
        end
    end

    @testset "Cost-surface spec is explicit about log vs linear" begin
        spec_log = raman_cost_surface_spec(log_cost=true, λ_gdd=1e-4, λ_boundary=0.5)
        spec_lin = raman_cost_surface_spec(log_cost=false, λ_gdd=1e-4, λ_boundary=0.5)

        @test spec_log.scalar_surface == "10*log10(physics + λ_gdd*R_gdd + λ_boundary*R_boundary)"
        @test spec_lin.scalar_surface == "physics + λ_gdd*R_gdd + λ_boundary*R_boundary"
        @test spec_log.regularizers_chained_into_surface
        @test spec_lin.regularizers_chained_into_surface
    end

    @testset "Canonical Raman result payload preserves schema keys" begin
        payload = build_raman_result_payload(;
            run_meta = (
                fiber_name = "SMF-28",
                P_cont_W = 0.2,
                lambda0_nm = 1550.0,
                fwhm_fs = 185.0,
            ),
            run_tag = "schema-test",
            fiber = Dict("L" => 2.0, "γ" => [1.1e-3], "betas" => [-2.17e-26, 1.2e-40]),
            sim = Dict("Δt" => 0.01, "ω0" => 1215.0),
            Nt = 8,
            time_window_ps = 0.08,
            J_before = 0.1,
            J_after = 0.001,
            delta_J_dB = -20.0,
            grad_norm = 3e-4,
            converged = true,
            iterations = 4,
            wall_time_s = 1.25,
            convergence_history = [-10.0, -20.0, -30.0],
            phi_opt = reshape(collect(1.0:8.0), 8, 1),
            uω0 = reshape(ComplexF64[complex(i, -i) for i in 1:8], 8, 1),
            E_conservation = 1e-6,
            bc_input_frac = 2e-4,
            bc_output_frac = 3e-4,
            bc_input_ok = true,
            bc_output_ok = true,
            trust_report = Dict{String,Any}("overall_verdict" => "PASS"),
            trust_report_md = "schema-test_trust.md",
            band_mask = [i <= 4 for i in 1:8],
        )

        expected_keys = (
            :fiber_name, :run_tag, :L_m, :P_cont_W, :lambda0_nm, :fwhm_fs,
            :gamma, :betas, :Nt, :time_window_ps, :J_before, :J_after,
            :delta_J_dB, :grad_norm, :converged, :iterations, :wall_time_s,
            :convergence_history, :phi_opt, :uomega0, :E_conservation,
            :bc_input_frac, :bc_output_frac, :bc_input_ok, :bc_output_ok,
            :trust_report, :trust_report_md, :band_mask, :sim_Dt, :sim_omega0,
        )
        @test keys(payload) == expected_keys
        @test payload.fiber_name == "SMF-28"
        @test payload.L_m == 2.0
        @test payload.Nt == 8
        @test payload.uomega0[3, 1] == 3 - 3im

        manifest_entry = build_raman_manifest_entry(payload, "result.jld2")
        @test manifest_entry["result_file"] == "result.jld2"
        @test manifest_entry["J_after_dB"] ≈ MultiModeNoise.lin_to_dB(0.001)
        @test manifest_entry["trust_overall"] == "PASS"
        @test manifest_entry["bc_ok"] == true

        mktempdir() do dir
            path = joinpath(dir, "payload.jld2")
            sidecar = save_run(path, payload)
            loaded = JLD2.load(path)
            expected_saved_keys = sort(vcat(collect(String.(expected_keys)), ["metadata"]))
            @test sort(collect(keys(loaded))) == expected_saved_keys
            @test loaded["run_tag"] == "schema-test"
            @test loaded["phi_opt"] == payload.phi_opt
            @test loaded["uomega0"] == payload.uomega0
            @test isfile(sidecar)
            rt = load_run(path)
            @test rt.run_tag == "schema-test"
            @test rt.sidecar.J_final_dB ≈ MultiModeNoise.lin_to_dB(payload.J_after)
        end
    end
end
