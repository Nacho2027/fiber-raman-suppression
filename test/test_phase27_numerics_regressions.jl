using Test
using Random
using Printf

const _ROOT = normpath(joinpath(@__DIR__, ".."))

using MultiModeNoise
include(joinpath(_ROOT, "scripts", "common.jl"))
include(joinpath(_ROOT, "scripts", "determinism.jl"))
ensure_deterministic_environment()
include(joinpath(_ROOT, "scripts", "raman_optimization.jl"))

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
end
