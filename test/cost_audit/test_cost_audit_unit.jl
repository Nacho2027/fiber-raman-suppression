# ═══════════════════════════════════════════════════════════════════════════════
# Phase 16 Plan 01 — Cost-audit unit tests
# ═══════════════════════════════════════════════════════════════════════════════
# Run:   julia --project=. test/cost_audit/test_cost_audit_unit.jl
#
# Gates:
#   1. d04_gradient        — Taylor-remainder slope ∈ [1.8, 2.2] for the D-04
#                            curvature-penalty analytic gradient.
#   2. d04_zero_penalty    — γ_curv = 0 returns a byte-identical (J, grad) tuple
#                            to cost_and_gradient (D-01 reduction control).
#   3. determinism         — Same-seed → bit-identical φ_opt at 5 L-BFGS iters.
#
# The first two gates are skipped until Task 2 produces
# scripts/research/cost_audit/cost_audit_noise_aware.jl. `determinism` runs unconditionally and
# calls the full nonlinear solver → MUST run on fiber-raman-burst per
# CLAUDE.md Rule 1.
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using Random
using LinearAlgebra
using Printf
using FFTW
using Statistics

FFTW.set_num_threads(1)
BLAS.set_num_threads(1)

const _PHASE16_WISDOM = joinpath(@__DIR__, "..", "..", "results", "raman", "phase14", "fftw_wisdom.txt")
isfile(_PHASE16_WISDOM) && try; FFTW.import_wisdom(_PHASE16_WISDOM); catch; end

include(joinpath(@__DIR__, "..", "..", "scripts", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "scripts", "lib", "raman_optimization.jl"))

const _CA_NOISE_AWARE_PATH = joinpath(@__DIR__, "..", "..", "scripts", "research", "cost_audit", "cost_audit_noise_aware.jl")
if isfile(_CA_NOISE_AWARE_PATH)
    include(_CA_NOISE_AWARE_PATH)
    const _CA_READY = true
else
    const _CA_READY = false
end

@testset "Phase 16 cost audit — unit" begin
    @testset "d04_gradient (FD ≈ analytic for curvature block)" begin
        if !_CA_READY
            @test_skip "scripts/research/cost_audit/cost_audit_noise_aware.jl not yet present (Task 2)"
        else
            # P(φ) is quadratic in each φ[i], so centered FD is mathematically
            # exact — the measured residual is pure round-off scaling as
            # ε_machine·|P|/ε (slope ≈ −1, not +2). A Taylor-remainder slope
            # test therefore can't work on this function; verify gradient
            # correctness by direct FD ≈ analytic agreement at a well-
            # conditioned ε instead.
            Random.seed!(0xD04)
            uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
                Nt=1024, time_window=5.0, β_order=3,
                fiber_preset=:SMF28, L_fiber=0.5, P_cont=0.05)
            φ = 0.1 .* randn(MersenneTwister(42), sim["Nt"], sim["M"])
            band_idx = findall(band_mask)
            @assert !isempty(band_idx)
            indices = band_idx[rand(MersenneTwister(1), 1:length(band_idx), 3)]
            γ_curv = 1.0
            _, grad_total  = cost_and_gradient_curvature(φ, uω0, fiber, sim, band_mask;
                                                         γ_curv=γ_curv)
            _, grad_linear = cost_and_gradient_curvature(φ, uω0, fiber, sim, band_mask;
                                                         γ_curv=0.0)
            grad_curv_only = grad_total .- grad_linear
            # Tolerance: centered-FD round-off ≈ ε_machine·|P|/ε. At ε=1e-3 and
            # P≈1 we expect ≈1e-13; allow 1e-9 as a generous gate that would
            # still catch a materially-wrong analytic gradient.
            ε = 1e-3
            max_rel_err = 0.0
            for idx in indices
                φp = copy(φ); φp[idx, 1] += ε
                φm = copy(φ); φm[idx, 1] -= ε
                Pp = curvature_penalty(φp, band_mask, sim)
                Pm = curvature_penalty(φm, band_mask, sim)
                fd_curv = γ_curv * (Pp - Pm) / (2ε)
                analytic = grad_curv_only[idx, 1]
                rel_err = abs(fd_curv - analytic) / (abs(analytic) + 1e-30)
                max_rel_err = max(max_rel_err, rel_err)
                @info @sprintf("D-04 grad at idx=%d: FD=%.6e analytic=%.6e rel_err=%.2e",
                               idx, fd_curv, analytic, rel_err)
            end
            @test max_rel_err < 1e-9
        end
    end

    @testset "d04_zero_penalty (γ_curv=0 ≡ D-01 byte-identical)" begin
        if !_CA_READY
            @test_skip "scripts/research/cost_audit/cost_audit_noise_aware.jl not yet present (Task 2)"
        else
            uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
                Nt=1024, time_window=5.0, β_order=3,
                fiber_preset=:SMF28, L_fiber=0.5, P_cont=0.05)
            φ = 0.1 .* randn(MersenneTwister(42), sim["Nt"], sim["M"])
            J_lin, g_lin = cost_and_gradient(φ, uω0, fiber, sim, band_mask;
                log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
            J_curv, g_curv = cost_and_gradient_curvature(φ, uω0, fiber, sim, band_mask;
                γ_curv=0.0)
            @test J_lin == J_curv
            @test g_lin == g_curv
        end
    end

    @testset "determinism (same seed → bit-identical φ_opt at 5 iters)" begin
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            Nt=1024, time_window=5.0, β_order=3,
            fiber_preset=:SMF28, L_fiber=0.5, P_cont=0.05)
        φ0 = 0.1 .* randn(MersenneTwister(42), sim["Nt"], sim["M"])
        res_a = optimize_spectral_phase(uω0, fiber, sim, band_mask;
            φ0=copy(φ0), max_iter=5, log_cost=false)
        φ_a = reshape(Optim.minimizer(res_a), sim["Nt"], sim["M"])
        # Reset sim["zsave"] side-effect by setting up again.
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            Nt=1024, time_window=5.0, β_order=3,
            fiber_preset=:SMF28, L_fiber=0.5, P_cont=0.05)
        res_b = optimize_spectral_phase(uω0, fiber, sim, band_mask;
            φ0=copy(φ0), max_iter=5, log_cost=false)
        φ_b = reshape(Optim.minimizer(res_b), sim["Nt"], sim["M"])
        @test maximum(abs.(φ_a .- φ_b)) == 0.0
    end
end
