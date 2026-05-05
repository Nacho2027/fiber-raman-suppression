# Slow Julia tier for supported Raman optimization behavior.

using Test
using Random
using LinearAlgebra
using Optim

const _ROOT = normpath(joinpath(@__DIR__, ".."))

using MultiModeNoise
include(joinpath(_ROOT, "scripts", "lib", "common.jl"))
include(joinpath(_ROOT, "scripts", "lib", "determinism.jl"))
ensure_deterministic_environment()
include(joinpath(_ROOT, "scripts", "lib", "raman_optimization.jl"))

@testset "Slow Raman optimization tier" begin
    @testset "Optimizer returns linear objective on recompute" begin
        Random.seed!(42)
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            fiber_preset = :SMF28,
            Nt = 2^11,
            time_window = 10.0,
            L_fiber = 0.5,
            P_cont = 0.05,
            β_order = 3,
        )
        φ0 = zeros(sim["Nt"], sim["M"])
        result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
            φ0=φ0, max_iter=3, store_trace=true, log_cost=true)
        phi_opt = reshape(Optim.minimizer(result), sim["Nt"], sim["M"])
        J_linear, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask;
            log_cost=false)
        @test 0.0 <= J_linear <= 1.0
        @test isfinite(J_linear)
    end

    @testset "Taylor-remainder gradient smoke" begin
        Random.seed!(0)
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            fiber_preset=:SMF28, Nt=2^10, time_window=10.0,
            L_fiber=0.5, P_cont=0.05, β_order=3)
        φ = zeros(sim["Nt"], sim["M"])
        δφ = randn(sim["Nt"], sim["M"])
        J0, ∇J = cost_and_gradient(φ, uω0, fiber, sim, band_mask; log_cost=false)
        ε_values = [1e-2, 1e-3, 1e-4]
        residuals = Float64[]
        for ε in ε_values
            Jp, _ = cost_and_gradient(φ .+ ε .* δφ, uω0, fiber, sim, band_mask;
                log_cost=false)
            push!(residuals, abs(Jp - J0 - ε * dot(∇J, δφ)))
        end
        slope = (log(residuals[1]) - log(residuals[end])) /
            (log(ε_values[1]) - log(ε_values[end]))
        @test 1.7 < slope < 2.3
    end
end
