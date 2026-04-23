# ═══════════════════════════════════════════════════════════════════════════════
# Phase 13 Plan 02 — HVP tests
# ═══════════════════════════════════════════════════════════════════════════════
#
# Run:  julia --project=. test/test_phase13_hvp.jl
#
# These tests stamp out bugs BEFORE the eigendecomposition is run on the burst
# VM. Per user directive: "stamp out all bugs by yourself before i even look
# at anything."
#
# Tests (5 testsets, 13 assertions minimum):
#   1. HVP oracle pipeline smoke test at small Nt
#   2. HVP symmetry: v' (H w) ≈ w' (H v)
#   3. Taylor-remainder: slope ∈ [1.8, 2.2] on a random direction
#   4. Small-grid full Hessian: matches fd_hvp column-by-column and is symmetric
#   5. Zero-direction guard: fd_hvp(·, zeros, ·) throws a clear error
#
# Runtime budget: these tests use Nt=2^7 (128) so each oracle call is fast
# (< 1 s). Full suite finishes in under 2 minutes on the 2-vCPU host.
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using LinearAlgebra
using Statistics
using Random
using FFTW
using Printf

# Make the HVP library + phase13 primitives available
include(joinpath(@__DIR__, "..", "scripts", "phase13_hvp.jl"))

# Pin FFTW before any oracle call — test harness mirrors the real entry-point
ensure_deterministic_fftw()

# ─────────────────────────────────────────────────────────────────────────────
# Fixture: tiny SMF-28-like config for fast HVPs
# ─────────────────────────────────────────────────────────────────────────────
#
# Nt=2^7 keeps a single oracle call under 1 s. We still exercise the real
# MultiModeNoise pipeline — just at a smaller grid. The test does NOT aim to
# reproduce the canonical config's physics; it tests the HVP ARITHMETIC.

const TEST_CONFIG = (
    fiber_preset = :SMF28,
    L_fiber = 0.2,            # short fiber → less stiffness, faster solves
    P_cont = 0.05,            # low power → modest SPM
    Nt = 2^7,                 # 128 bins; tiny but resolves the pulse
    time_window = 5.0,
    β_order = 3,
)

@info "Building HVP oracle at Nt=$(TEST_CONFIG.Nt)..."
const TEST_ORACLE, TEST_META = build_oracle(TEST_CONFIG)
const TEST_N = TEST_META.Nt * TEST_META.M
@info "Oracle built. N=$TEST_N, input-band bins=$(sum(TEST_META.input_band_mask))"

# Shared base point: small random phase, same seed across testsets
function _base_phi(seed::Integer = 42)
    Random.seed!(seed)
    return 0.01 .* randn(TEST_N)     # small perturbation so we are near the origin
end

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 13 HVP tests" begin

    @testset "1. Oracle pipeline smoke test" begin
        φ = _base_phi()
        g = TEST_ORACLE(φ)
        @test length(g) == TEST_N
        @test all(isfinite, g)
        # Gradient at a small random phi should have nontrivial norm
        @test norm(g) > 1e-14
        @test TEST_META.objective_spec.log_cost == false
        @test TEST_META.objective_spec.lambda_gdd == 0.0
        @test TEST_META.objective_spec.lambda_boundary == 0.0
    end

    @testset "2. HVP symmetry: v' H w ≈ w' H v" begin
        φ = _base_phi()
        Random.seed!(101)
        v = randn(TEST_N); v ./= norm(v)
        w = randn(TEST_N); w ./= norm(w)
        ε = 1e-3
        Hv = fd_hvp(φ, v, TEST_ORACLE; eps=ε)
        Hw = fd_hvp(φ, w, TEST_ORACLE; eps=ε)
        vHw = dot(v, Hw)
        wHv = dot(w, Hv)
        # Symmetry: |vHw − wHv| should be small relative to |vHw|
        sym_err = abs(vHw - wHv)
        sym_ref = max(abs(vHw), abs(wHv), 1e-14)
        rel_err = sym_err / sym_ref
        @info @sprintf("  v'Hw = %.6e, w'Hv = %.6e, rel-err = %.3e", vHw, wHv, rel_err)
        # Tolerance: FD noise scales with ε, then doubled because there are two
        # independent HVPs. At ε=1e-3, Hv accuracy ~ ε² ~ 1e-6, so the
        # symmetry residual should easily be under 1e-3 relative.
        @test rel_err < 1e-3
    end

    @testset "3. Taylor-remainder slope ∈ [1.8, 2.2]" begin
        φ = _base_phi()
        Random.seed!(202)
        v_test = randn(TEST_N); v_test ./= norm(v_test)
        result = validate_hvp_taylor(φ, v_test, TEST_ORACLE;
            eps_range = 10.0 .^ (-1:-0.5:-6))
        @info "  Taylor-remainder results:"
        for (ε, r) in zip(result.eps_values, result.residuals)
            @info @sprintf("    ε=%.2e  ‖ΔHv‖=%.3e", ε, r)
        end
        @info @sprintf("  slope = %.3f (region = %s)", result.slope, string(result.slope_region))
        # Central-difference truncation error is O(ε²); halving ε should reduce
        # the residual by 4×, giving a log-log slope of 2.
        @test result.slope > 1.8
        @test result.slope < 2.2
    end

    @testset "4. Small-grid full Hessian: symmetric + matches column-wise FD" begin
        # Build the dense Hessian at tiny N and verify it's symmetric.
        # Rebuild oracle at Nt=2^6 to keep runtime reasonable; 64 bins → 128
        # oracle calls for dense construction.
        small_cfg = merge(TEST_CONFIG, (Nt = 2^6, time_window = 5.0))
        small_oracle, small_meta = build_oracle(small_cfg)
        N_small = small_meta.Nt * small_meta.M
        Random.seed!(303)
        φ_small = 0.01 .* randn(N_small)
        H, max_asym = build_full_hessian_small(φ_small, small_oracle; eps=1e-3)
        @info @sprintf("  N_small=%d, ‖H‖_F = %.3e, max|H-H'| = %.3e",
                       N_small, norm(H), max_asym)
        # Symmetry: finite-difference noise at ε=1e-3 is ~ε² · ‖∇²²J‖ ~ 1e-6 times
        # typical Hessian entry magnitude. Relative asymmetry should be ≪ 1.
        rel_asym = max_asym / max(opnorm(H, Inf), 1e-14)
        @test rel_asym < 1e-3
        # Cross-check: dense Hv(e_k) must match fd_hvp(e_k) (same call, same ε)
        # Already holds by construction because build_full_hessian_small uses
        # fd_hvp internally. Instead, we check that H·v (matrix product) matches
        # fd_hvp(φ, v) for a random v — this guards against index ordering bugs.
        Random.seed!(304)
        v_probe = randn(N_small); v_probe ./= norm(v_probe)
        Hv_fd = fd_hvp(φ_small, v_probe, small_oracle; eps=1e-3)
        Hv_matmul = H * v_probe
        mismatch = norm(Hv_fd .- Hv_matmul) / max(norm(Hv_fd), 1e-14)
        @info @sprintf("  rel-mismatch(H·v via matrix vs fd_hvp) = %.3e", mismatch)
        # This should be essentially zero modulo FD noise in a single-column call
        # (column k of H is fd_hvp(e_k), and H·v = Σ_k v_k · fd_hvp(e_k), which
        # is not exactly fd_hvp(v) because fd_hvp is nonlinear in the direction
        # — the central difference approximates a linear operator only to O(ε²).
        # Tolerance reflects this: O(ε²·‖v‖) noise per call.
        @test mismatch < 1e-3
    end

    @testset "5. Zero-direction guard" begin
        φ = _base_phi()
        zero_v = zeros(TEST_N)
        @test_throws AssertionError fd_hvp(φ, zero_v, TEST_ORACLE; eps=1e-4)
    end

    @testset "6. HVP oracle can target the regularized dB surface explicitly" begin
        cfg = merge(TEST_CONFIG, (Nt = 2^6, time_window = 5.0))
        oracle_dB, meta_dB = build_oracle(cfg; log_cost=true, λ_gdd=1e-4, λ_boundary=0.5)
        φ = 0.01 .* randn(meta_dB.Nt * meta_dB.M)
        g = oracle_dB(φ)
        @test all(isfinite, g)
        @test meta_dB.objective_spec.log_cost == true
        @test meta_dB.objective_spec.lambda_gdd == 1e-4
        @test meta_dB.objective_spec.lambda_boundary == 0.5
        @test occursin("10*log10", meta_dB.objective_spec.scalar_surface)
    end

end  # @testset

@info "All Phase 13 HVP tests passed."
