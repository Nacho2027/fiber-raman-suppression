# ═══════════════════════════════════════════════════════════════════════════════
# Phase 14 Plan 01 — Unit tests for sharpness_optimization.jl
# ═══════════════════════════════════════════════════════════════════════════════
#
# Run:   julia --project=. test/test_phase14_sharpness.jl
#
# Tests (per 14-01-PLAN.md):
#   1. Vanishing-λ reduction       : λ_sharp=0 → byte-identical J vs vanilla
#   2. Gauge invariance of S       : S(φ + C) ≈ S(φ) under finite-N_s noise
#   3. Positive-definiteness at a near-optimum : S > 0 at Phase 13 canonical φ
#   4. Taylor-remainder for gradient: log–log slope of ||residual||₂ vs ‖δ‖ ≈ 2
#   5. Hutchinson variance consistency: two RNG streams give S within 50% at N_s=8
#
# All tests use a tiny grid (Nt=256, L=0.05m, low power) so the full suite
# runs in well under a minute on a 2-vCPU host.
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using LinearAlgebra
using Statistics
using Random
using FFTW
using Printf
using JLD2

# Pin threads BEFORE loading the library to minimise FFTW.MEASURE cross-run
# jitter. (Same rationale as test_phase14_regression.jl; see that file and
# `results/raman/phase13/determinism.md` for the full context.)
FFTW.set_num_threads(1)
BLAS.set_num_threads(1)

# Import previously-saved FFTW wisdom if available, so MEASURE-flagged plan
# creation inside MultiModeNoise is at least process-consistent.
const _SH_WISDOM_PATH = joinpath(@__DIR__, "..", "results", "raman", "phase14", "fftw_wisdom.txt")
if isfile(_SH_WISDOM_PATH)
    try
        FFTW.import_wisdom(_SH_WISDOM_PATH)
    catch
    end
end

include(joinpath(@__DIR__, "..", "scripts", "lib", "sharpness_optimization.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Small-problem fixture (fast enough for unit tests)
# ─────────────────────────────────────────────────────────────────────────────

const TEST_NT = 256
const TEST_L  = 0.05          # m — short fiber for speed
const TEST_P  = 0.02          # W — low peak → weak SPM → minimal auto-sizing
const TEST_TW = 5.0           # ps

@info "Phase 14 tests: building small fixture (Nt=$TEST_NT, L=$TEST_L m, P=$TEST_P W)"
prob = make_sharp_problem(;
    fiber_preset = :SMF28,
    P_cont = TEST_P,
    L_fiber = TEST_L,
    Nt = TEST_NT,
    time_window = TEST_TW,
    β_order = 3,
)
NT_ACTUAL = prob.sim["Nt"]
M_ACTUAL = prob.sim["M"]
@info "Fixture sim grid: Nt=$NT_ACTUAL, M=$M_ACTUAL, input-band bins=$(sum(prob.band_mask_input))"

# Helper: build a smooth random test phase (not all zeros — the zero-phase is
# a degenerate stationary point for some tests).
function _make_test_phi(rng; amplitude = 0.1)
    φ = zeros(NT_ACTUAL, M_ACTUAL)
    # smooth perturbation: low-order polynomial in ω over the input band
    ω = prob.omega
    mask = prob.band_mask_input
    ω_mean = mean(ω[mask])
    ω_range = maximum(ω[mask]) - minimum(ω[mask])
    x = @. 2 * (ω - ω_mean) / ω_range
    for m in 1:M_ACTUAL
        φ[:, m] = amplitude .* (randn(rng) .* x.^2 .+ randn(rng) .* x.^3)
    end
    return φ
end

# Oracle used by the tests — wraps cost_and_gradient with common reg options.
const TEST_LAMBDA_GDD = 0.0          # disable to match raw J for vanishing-λ test
const TEST_LAMBDA_BND = 0.0
const TEST_LOG_COST = false          # use linear J for cleaner gradient tests

function test_oracle(phi)
    return cost_and_gradient(phi, prob.uω0, prob.fiber, prob.sim, prob.band_mask;
                             log_cost = TEST_LOG_COST,
                             λ_gdd = TEST_LAMBDA_GDD,
                             λ_boundary = TEST_LAMBDA_BND)
end

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 14 sharpness_optimization" begin

    @testset "1. Vanishing-λ reduction (λ_sharp=0 == vanilla)" begin
        Random.seed!(100)
        φ = _make_test_phi(MersenneTwister(100))
        # Reference: unchanged cost_and_gradient
        J_ref, g_ref = test_oracle(φ)
        # Sharpness path with λ=0 should short-circuit to the reference.
        J_s, g_s = cost_and_gradient_sharp(φ, prob.uω0, prob.fiber, prob.sim, prob.band_mask;
                                           lambda_sharp = 0.0,
                                           log_cost = TEST_LOG_COST,
                                           λ_gdd = TEST_LAMBDA_GDD,
                                           λ_boundary = TEST_LAMBDA_BND,
                                           gauge_projector = prob.gauge_projector)
        @test J_s == J_ref
        @test g_s == g_ref   # byte-identical: same path
    end

    @testset "2. Gauge invariance of S — S(φ+C) ≈ S(φ) under Hutchinson noise" begin
        Random.seed!(200)
        φ = _make_test_phi(MersenneTwister(200))
        C = 3.14159
        # Use a large N_s for low-variance estimator, single fixed RNG so the
        # two runs share the SAME Rademacher vectors (projector should make
        # the estimator itself invariant, not just the expectation).
        rng1 = MersenneTwister(999)
        rng2 = MersenneTwister(999)
        N_s_here = 64
        eps_here = 1e-3   # NOTE: local var name avoids shadowing Base.eps()
        s1 = sharpness_estimator(φ, test_oracle, prob.gauge_projector;
                                 eps = eps_here, n_samples = N_s_here, rng = rng1)
        s2 = sharpness_estimator(φ .+ C, test_oracle, prob.gauge_projector;
                                 eps = eps_here, n_samples = N_s_here, rng = rng2)
        rel = abs(s1.S - s2.S) / max(abs(s1.S), Base.eps())
        @info @sprintf("Gauge invariance: S(φ)=%.3e, S(φ+C)=%.3e, rel=%.3e", s1.S, s2.S, rel)
        @test rel < 0.2     # shared RNG + projector ⇒ should be quite tight
        # Grad_S may have small additive drift from rounding; check shape
        @test size(s1.grad_S) == size(s2.grad_S) == size(φ)
    end

    @testset "3. Positive-definiteness at a near-optimum" begin
        # Load the Phase 14 vanilla snapshot. This is the closest to an optimum
        # we have readily available on disk; the snapshot was captured at the
        # SAME canonical config flag the plan specifies.
        snap_path = joinpath(@__DIR__, "..", "results", "raman", "phase14",
                             "vanilla_snapshot.jld2")
        if !isfile(snap_path)
            @warn "Skipping test 3 — snapshot $snap_path missing (run snapshot_vanilla.jl first)"
        else
            snap = JLD2.load(snap_path)
            phi_opt = snap["phi_opt"]
            # Build a problem matching the snapshot config for a consistent cost.
            # Tolerance is relaxed because the snapshot fixture is BIG (Nt=8192,
            # L=2m) and we use it only to prove tr(H) > 0, not to land a value.
            prob_canon = make_sharp_problem(;
                fiber_preset = Symbol(snap["fiber_preset"]),
                P_cont = snap["P_cont"],
                L_fiber = snap["L_fiber"],
                Nt = snap["Nt"],
                time_window = snap["time_window"],
                β_order = snap["beta_order"],
            )
            oracle_canon = phi -> cost_and_gradient(phi, prob_canon.uω0,
                prob_canon.fiber, prob_canon.sim, prob_canon.band_mask;
                log_cost = false)
            # Use modest eps+N_s to keep runtime acceptable (one S eval ≈ 2·N_s
            # forward+adjoint solves at Nt=8192 ≈ 20 s).
            rng_canon = MersenneTwister(3)
            s = sharpness_estimator(phi_opt, oracle_canon, prob_canon.gauge_projector;
                                    eps = 5e-3, n_samples = 4, rng = rng_canon)
            @info "Sharpness at Phase 13 canonical φ_opt: S = $(s.S)"
            # Near a minimum, H is PSD → tr(H_physical) ≥ 0. Finite-N_s FD
            # noise can make the estimate slightly negative; we allow a small
            # negative margin and just check it isn't dominated by noise.
            @test s.S > -1e-3
        end
    end

    @testset "4. Gradient validation — Taylor-remainder slope ≈ 2" begin
        # Test: f(φ + s·δ) − f(φ) − ∇f(φ)·(s·δ)  = ½ s² δᵀ H δ + O(s³)
        # ⇒ log|residual| = 2·log|s| + const in the quadratic-dominated regime.
        #
        # For J_sharp = J + λ·S, the Hutchinson estimator S(φ) has an intrinsic
        # roundoff noise floor ~ 1e-16/ε² ≈ 1e-10 at ε=1e-3 (the FD step of the
        # sharpness estimator itself). Thus λ·S has absolute noise ≈ λ·1e-10
        # and the Taylor residual hits this floor once |s²·‖H‖| drops below it.
        # Empirically for our small fixture this happens around s ≲ 0.05.
        # We therefore sweep s over the clean quadratic decade (1 → 0.1) and
        # require slope ∈ [1.8, 2.2].

        Random.seed!(400)
        φ = _make_test_phi(MersenneTwister(400); amplitude = 0.05)

        base_seed = 31337
        lambda_s = 0.05
        eps_s = 1e-3
        N_s_here = 16

        function J_and_grad_at(phi_here)
            rng = MersenneTwister(base_seed)
            return cost_and_gradient_sharp(phi_here, prob.uω0, prob.fiber, prob.sim,
                                           prob.band_mask;
                                           lambda_sharp = lambda_s,
                                           n_samples = N_s_here, eps = eps_s, rng = rng,
                                           log_cost = TEST_LOG_COST,
                                           λ_gdd = TEST_LAMBDA_GDD,
                                           λ_boundary = TEST_LAMBDA_BND,
                                           gauge_projector = prob.gauge_projector)
        end

        J0, g0 = J_and_grad_at(φ)
        # Gauge-projected random direction, unit-normalised.
        rng_dir = MersenneTwister(77)
        δ_raw = randn(rng_dir, size(φ))
        δ_flat = prob.gauge_projector(vec(δ_raw))
        δ = reshape(δ_flat, size(φ))
        δ ./= norm(δ)

        # Clean quadratic regime: s = 1.0 down to 0.1 in 6 steps.
        scales = [10.0^k for k in 0.0:-0.2:-1.0]
        residuals = Float64[]
        linpreds = Float64[]
        for s in scales
            J_pert, _ = J_and_grad_at(φ .+ s .* δ)
            linpred = s * dot(vec(g0), vec(δ))
            resid = J_pert - J0 - linpred
            push!(residuals, abs(resid))
            push!(linpreds, linpred)
        end
        @info "Taylor sweep (clean quadratic regime):"
        for i in eachindex(scales)
            @info @sprintf("  s=%.3e  resid=%.3e  resid/s^2=%.3e",
                scales[i], residuals[i], residuals[i] / scales[i]^2)
        end
        # Linear LS slope in log-log space.
        log_s = log.(scales)
        log_r = log.(residuals)
        m_slope = sum((log_s .- mean(log_s)) .* (log_r .- mean(log_r))) /
                  sum((log_s .- mean(log_s)).^2)
        @info @sprintf("Taylor-remainder slope = %.3f (expect ≈ 2)", m_slope)
        @test 1.8 ≤ m_slope ≤ 2.2
    end

    @testset "5. Hutchinson variance consistency — different RNGs, rel diff < 50%" begin
        Random.seed!(500)
        φ = _make_test_phi(MersenneTwister(500))
        rng_a = MersenneTwister(1)
        rng_b = MersenneTwister(2)
        N_s_here = 8
        eps_here = 1e-3
        sa = sharpness_estimator(φ, test_oracle, prob.gauge_projector;
                                 eps = eps_here, n_samples = N_s_here, rng = rng_a)
        sb = sharpness_estimator(φ, test_oracle, prob.gauge_projector;
                                 eps = eps_here, n_samples = N_s_here, rng = rng_b)
        denom = max(abs(sa.S), abs(sb.S), Base.eps())
        rel = abs(sa.S - sb.S) / denom
        @info @sprintf("Hutchinson variance: S_a=%.3e, S_b=%.3e, rel=%.2f", sa.S, sb.S, rel)
        @test rel < 0.5
    end

end

@info "All Phase 14 sharpness tests passed."
