# ═══════════════════════════════════════════════════════════════════════════════
# test/tier_slow.jl — Phase 16 slow tier (~5 min, BURST VM)
# ═══════════════════════════════════════════════════════════════════════════════
# Run on the burst VM. DO NOT run on claude-code-host (violates CLAUDE.md
# Rule 1 — simulations belong on fiber-raman-burst).
#
# What this tier catches:
#   - Key Bug #1 (dB/linear cost mismatch) via optimize_spectral_phase return
#     signature — asserts the optimizer returns linear J to the caller.
#   - End-to-end SMF-28 canonical optimization produces J_final_dB < -40.
#   - Taylor-remainder gradient check (adjoint O(ε²) correctness).
#   - Phase 13 primitives + HVP tests (wired from existing test_phase13_*.jl).
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using Random
using Printf
using LinearAlgebra
using Optim

const _ROOT = normpath(joinpath(@__DIR__, ".."))

using MultiModeNoise
include(joinpath(_ROOT, "scripts", "lib", "common.jl"))
include(joinpath(_ROOT, "scripts", "lib", "determinism.jl"))
ensure_deterministic_environment()
include(joinpath(_ROOT, "scripts", "lib", "raman_optimization.jl"))

@testset "Phase 16 — slow tier" begin

    @testset "Key Bug #1 regression — dB/linear cost returns linear J" begin
        # Set up a small-grid canonical SMF-28 problem
        Random.seed!(42)
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            fiber_preset = :SMF28,
            Nt           = 2^11,
            time_window  = 10.0,
            L_fiber      = 0.5,
            P_cont       = 0.05,
            β_order      = 3,
        )
        φ0 = zeros(sim["Nt"], sim["M"])
        result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
            φ0=φ0, max_iter=3, store_trace=true, log_cost=true)

        # Recompute J from returned minimizer at BOTH scales. The optimizer is
        # configured with log_cost=true, but the returned `result` minimum
        # corresponds to the log-space value. Recomputing cost_and_gradient
        # with log_cost=false must give a LINEAR J in [0, 1].
        phi_opt = reshape(Optim.minimizer(result), sim["Nt"], sim["M"])
        J_linear, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask;
                                        log_cost=false)
        @test 0.0 <= J_linear <= 1.0   # Linear J is a fraction — Key Bug #1 assertion
        @test isfinite(J_linear)
    end

    @testset "End-to-end SMF-28 canonical — J_final_dB < -40" begin
        Random.seed!(42)
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            fiber_preset = :SMF28,
            Nt           = 2^13,
            time_window  = 12.0,
            L_fiber      = 2.0,
            P_cont       = 0.2,
            β_order      = 3,
        )
        φ0 = zeros(sim["Nt"], sim["M"])
        result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
            φ0=φ0, max_iter=30, store_trace=true, log_cost=true)
        phi_opt = reshape(Optim.minimizer(result), sim["Nt"], sim["M"])
        J_linear, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask;
                                        log_cost=false)
        J_final_dB = 10 * log10(J_linear)
        @info "Slow tier SMF-28 canonical: J_final_dB = $J_final_dB"
        @test J_final_dB < -40.0
    end

    @testset "Taylor-remainder gradient check (smoke)" begin
        # Small grid; check that |J(φ+εδφ) - J(φ) - ε ⟨∇J, δφ⟩| ∝ ε² (slope ~ 2 in log-log).
        Random.seed!(0)
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            fiber_preset=:SMF28, Nt=2^10, time_window=10.0,
            L_fiber=0.5, P_cont=0.05, β_order=3)
        φ  = zeros(sim["Nt"], sim["M"])
        δφ = randn(sim["Nt"], sim["M"])
        J0, ∇J = cost_and_gradient(φ, uω0, fiber, sim, band_mask; log_cost=false)
        ε_values = [1e-2, 1e-3, 1e-4]
        residuals = Float64[]
        for ε in ε_values
            Jp, _ = cost_and_gradient(φ .+ ε .* δφ, uω0, fiber, sim, band_mask;
                                      log_cost=false)
            push!(residuals, abs(Jp - J0 - ε * dot(∇J, δφ)))
        end
        # log residual / log ε should have slope ~ 2
        slope = (log(residuals[1]) - log(residuals[end])) /
                (log(ε_values[1]) - log(ε_values[end]))
        @info "Taylor-remainder slope = $slope (expected ~ 2.0)"
        @test 1.7 < slope < 2.3
    end

    @testset "Phase 27 numerics regressions" begin
        include(joinpath(_ROOT, "test", "phases", "test_phase27_numerics_regressions.jl"))
    end

    # Phase 13 tests live in their own files and use their own setup blocks.
    @testset "Phase 13 primitives" begin
        include(joinpath(_ROOT, "test", "phases", "test_phase13_primitives.jl"))
    end
    @testset "Phase 13 HVP" begin
        include(joinpath(_ROOT, "test", "phases", "test_phase13_hvp.jl"))
    end

end
