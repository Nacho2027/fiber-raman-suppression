# test/test_trust_region_pcg_integration.jl — Phase 34 Plan 03 Task 3.
# End-to-end integration tests for PreconditionedCGSolver on the Raman oracle.
# Nt=128 keeps runtime < 3 min on claude-code-host (follows Phase 33 precedent
# in test/test_trust_region_integration.jl).
#
# Run:  julia --project=. test/test_trust_region_pcg_integration.jl
#
# Physics parameters: SMF28, L=0.5m, P=0.05W, Nt=128, time_window=5.0ps.
# These match the Phase 33 integration test (test_trust_region_integration.jl
# §"Raman integration Nt=128") — the same config known to produce a valid
# band_mask at Nt=128 (Raman-shifted band falls within the 5ps spectral grid).
# L=2.0m / P=0.2W / time_window=40.0ps would place the Raman band outside the
# Nt=128 spectral grid (band_mask all-false → AssertionError).
#
# Covers:
#   1. PreconditionedCGSolver(:none) runs E2E on Raman oracle — no NaN/Inf
#   2. build_diagonal_precond + build_dispersion_precond factories compose with
#      the oracle (factory outputs are finite, correct length)
#   3. build_dct_precond with oracle-backed H_op at Nt=128, K=8 — no NaN/Inf
#   4. Regression: SteihaugSolver still produces finite results at Nt=128

using Test
using LinearAlgebra
using Random
using MultiModeNoise

# Pin determinism before any simulation call (matches optimize_spectral_phase_tr's
# internal pin — double-pinning is idempotent).
include(joinpath(@__DIR__, "..", "scripts", "determinism.jl"))
ensure_deterministic_environment()
include(joinpath(@__DIR__, "..", "scripts", "phase13_hvp.jl"))
ensure_deterministic_fftw()

include(joinpath(@__DIR__, "..", "scripts", "common.jl"))
include(joinpath(@__DIR__, "..", "scripts", "trust_region_core.jl"))
include(joinpath(@__DIR__, "..", "scripts", "trust_region_telemetry.jl"))
include(joinpath(@__DIR__, "..", "scripts", "trust_region_optimize.jl"))
include(joinpath(@__DIR__, "..", "scripts", "trust_region_preconditioner.jl"))
include(joinpath(@__DIR__, "..", "scripts", "trust_region_pcg.jl"))

# Shared problem config — SMF28 at short fiber / low power / narrow time window
# so the Raman-shifted band falls within the Nt=128 spectral grid.
const _INTEG_FIBER_PRESET = :SMF28
const _INTEG_L             = 0.5
const _INTEG_P             = 0.05
const _INTEG_Nt            = 128
const _INTEG_TW            = 5.0
const _INTEG_β_ORDER       = 3

@testset "PreconditionedCGSolver on Raman oracle (Nt=128, :none)" begin
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = _INTEG_FIBER_PRESET, L_fiber = _INTEG_L, P_cont = _INTEG_P,
        Nt = _INTEG_Nt, time_window = _INTEG_TW, β_order = _INTEG_β_ORDER,
    )
    n = length(uω0)

    solver = PreconditionedCGSolver(preconditioner=:none, max_iter=10)
    result = optimize_spectral_phase_tr(
        uω0, deepcopy(fiber), sim, band_mask;
        φ0 = zeros(Float64, n),
        solver = solver,
        max_iter = 3,       # short — just verify E2E wires correctly
        Δ0 = 0.3,
        g_tol = 1e-5, H_tol = -1e-6,
        log_cost = false,
        lambda_probe_cadence = 100,   # disable λ-probe for speed
    )
    @test length(result.minimizer) == n
    @test all(isfinite, result.minimizer)
    @test isfinite(result.J_final)
    @test result.iterations <= 3
end

@testset "Regression: optimize_analytic_tr forwards M kwarg into solve_subproblem" begin
    H = Diagonal([2.0, 5.0])
    cost_fn = φ -> 0.5 * dot(φ, H * φ)
    grad_fn = φ -> H * φ
    φ0 = [1.0, -1.0]

    m_calls = Ref(0)
    M_probe = v -> begin
        m_calls[] += 1
        return copy(v)
    end

    solver = PreconditionedCGSolver(preconditioner=:diagonal, max_iter=10)
    result = optimize_analytic_tr(
        cost_fn, grad_fn, φ0;
        solver = solver,
        M = M_probe,
        max_iter = 1,
        Δ0 = 0.5,
        g_tol = 1e-12,
        lambda_probe_cadence = 100,
    )

    @test m_calls[] >= 1
    @test result.exit_code in (CONVERGED_2ND_ORDER, MAX_ITER, MAX_ITER_STALLED, RADIUS_COLLAPSE)
    @test all(isfinite, result.minimizer)
    @test isfinite(result.J_final)
end

@testset "PCG driver composes with build_diagonal_precond factory" begin
    # Factory exercise — does NOT wire M into outer loop (frozen), but
    # verifies the combo loads and factory outputs are correct.
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = _INTEG_FIBER_PRESET, L_fiber = _INTEG_L, P_cont = _INTEG_P,
        Nt = _INTEG_Nt, time_window = _INTEG_TW, β_order = _INTEG_β_ORDER,
    )
    M_diag = build_diagonal_precond(uω0)
    M_disp = build_dispersion_precond(sim)

    v = randn(length(uω0))
    @test length(M_diag(v)) == length(v)
    @test length(M_disp(v)) == length(v)
    @test all(isfinite, M_diag(v))
    @test all(isfinite, M_disp(v))
    # Preconditioners must return positive-valued outputs for positive inputs
    v_pos = abs.(v) .+ 0.1
    @test all(M_diag(v_pos) .> 0)
    @test all(M_disp(v_pos) .> 0)
end

@testset "PCG composes with build_dct_precond via oracle-backed H_op" begin
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = _INTEG_FIBER_PRESET, L_fiber = _INTEG_L, P_cont = _INTEG_P,
        Nt = _INTEG_Nt, time_window = _INTEG_TW, β_order = _INTEG_β_ORDER,
    )
    n = length(uω0)
    oracle = build_raman_oracle(uω0, deepcopy(fiber), sim, band_mask;
                                 log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
    φ0 = zeros(Float64, n)
    H_op = v -> fd_hvp(φ0, v, oracle.grad_fn;
                       eps = sqrt(eps(Float64) * max(1.0, norm(v))) / max(1.0, norm(v)))

    K = 8   # small — integration test must run < 3 min
    M_dct = build_dct_precond(H_op, n, K; σ_shift=:auto)
    v = randn(n)
    out = M_dct(v)
    @test length(out) == n
    @test all(isfinite, out)
    # Verify apply is a pure linear map: M_dct(α*v) ≈ α*M_dct(v)
    # Use rtol because output magnitudes can be O(1e16) for the FD-HVP
    # oracle near the Raman cost; absolute tolerance would be too tight.
    α = 2.5
    @test isapprox(M_dct(α .* v), α .* M_dct(v); rtol=1e-8)
    # Complement pass-through: zero vector maps to zero
    v_zero = zeros(n)
    @test M_dct(v_zero) ≈ v_zero atol=1e-14
end

@testset "Regression: SteihaugSolver still works at Nt=128" begin
    # Sanity check: the Phase-33 baseline must still pass.
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = _INTEG_FIBER_PRESET, L_fiber = _INTEG_L, P_cont = _INTEG_P,
        Nt = _INTEG_Nt, time_window = _INTEG_TW, β_order = _INTEG_β_ORDER,
    )
    n = length(uω0)
    solver = SteihaugSolver(max_iter=10)
    result = optimize_spectral_phase_tr(
        uω0, deepcopy(fiber), sim, band_mask;
        φ0 = zeros(Float64, n),
        solver = solver,
        max_iter = 3,
        Δ0 = 0.3,
        log_cost = false,
        lambda_probe_cadence = 100,
    )
    @test all(isfinite, result.minimizer)
    @test isfinite(result.J_final)
    @test result.iterations <= 3
end
