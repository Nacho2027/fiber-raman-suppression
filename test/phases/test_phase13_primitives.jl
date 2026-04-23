# ═══════════════════════════════════════════════════════════════════════════════
# Phase 13 primitives — unit tests
# ═══════════════════════════════════════════════════════════════════════════════
#
# Run:  julia --project=. test/phases/test_phase13_primitives.jl
#
# Tests defined here (minimum 6 per plan 13-01-PLAN.md Task 1):
#   1. gauge_fix idempotence           — applying twice == applying once
#   2. gauge_fix gauge invariance      — removes arbitrary C + α·ω exactly
#   3. polynomial_project exactness    — polynomial-in input → near-zero residual
#   4. polynomial_project recovery     — coefficients recovered within 1e-8
#   5. phase_similarity symmetry       — (a,b) == (b,a)
#   6. phase_similarity self-identity  — (a,a).cosine_sim ≈ 1, rms ≈ 0
#   7. gauge_fix on 2D (Nt, 1) phi     — preserves shape
#   8. input_band_mask covers 99.9% energy
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using LinearAlgebra
using Statistics
using Random
using FFTW

# Make the primitives available
include(joinpath(@__DIR__, "..", "..", "scripts", "research", "phases", "phase13", "primitives.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Fixture: mimic the real JLD2 grid (Nt=1024 for fast tests)
# ─────────────────────────────────────────────────────────────────────────────

const TEST_Nt = 1024
const TEST_Dt = 0.01                                   # ps
const TEST_OMEGA = omega_vector(1215.26, TEST_Dt, TEST_Nt)

# Build a realistic input-band mask: central ±3 THz (Gaussian pulse-like)
function _make_band_mask()
    Δf = fftfreq(TEST_Nt, 1 / TEST_Dt)          # THz
    return Δf .|> f -> abs(f) <= 3.0           # ±3 THz around carrier
end
const TEST_MASK = _make_band_mask()

# Guard: make sure fixture is consistent
@assert length(TEST_OMEGA) == TEST_Nt
@assert length(TEST_MASK) == TEST_Nt
@assert sum(TEST_MASK) >= 20

# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 13 primitives" begin

    @testset "1. gauge_fix idempotence" begin
        Random.seed!(0)
        φ = randn(TEST_Nt)
        φ1, _ = gauge_fix(φ, TEST_MASK, TEST_OMEGA)
        φ2, gauge2 = gauge_fix(φ1, TEST_MASK, TEST_OMEGA)
        @test maximum(abs.(φ1 .- φ2)) < 1e-12
        # Second pass should find C ≈ 0 and α ≈ 0
        @test abs(gauge2[1]) < 1e-12
        @test abs(gauge2[2]) < 1e-12
    end

    @testset "2. gauge_fix gauge invariance (removes C + α·ω exactly)" begin
        Random.seed!(1)
        φ = randn(TEST_Nt)
        C = 3.14
        α = -0.7
        φ_prime = φ .+ C .+ α .* TEST_OMEGA
        φa, _ = gauge_fix(φ, TEST_MASK, TEST_OMEGA)
        φb, _ = gauge_fix(φ_prime, TEST_MASK, TEST_OMEGA)
        @test maximum(abs.(φa .- φb)) < 1e-10
        # Mean over band is zero
        @test abs(mean(φa[TEST_MASK])) < 1e-12
        # Slope over band is zero (least-squares)
        ω_b = TEST_OMEGA[TEST_MASK]
        ω_c = ω_b .- mean(ω_b)
        slope = sum(ω_c .* (φa[TEST_MASK] .- mean(φa[TEST_MASK]))) / sum(ω_c .^ 2)
        @test abs(slope) < 1e-12
    end

    @testset "3. polynomial_project exactness on polynomial input" begin
        # Build φ = a2·x² + a3·x³ + a4·x⁴ + a5·x⁵ + a6·x⁶ directly (no gauge fix,
        # since on a finite interval x³ and x⁵ have nonzero least-squares slopes
        # and gauge-fixing them would mix their linear components with the
        # polynomial orders in the projection basis — that's a real physical
        # effect, not a bug). polynomial_project should recover the coeffs
        # bit-perfectly when the input is exactly a polynomial over the band.
        ω_b = TEST_OMEGA[TEST_MASK]
        ω_mean = mean(ω_b)
        ω_range = maximum(ω_b) - minimum(ω_b)
        x_full = 2 .* (TEST_OMEGA .- ω_mean) ./ ω_range
        coeffs_truth = (a2=1.1, a3=0.5, a4=-0.3, a5=2.0, a6=0.07)
        φ_input = coeffs_truth.a2 .* x_full .^ 2 .+
                  coeffs_truth.a3 .* x_full .^ 3 .+
                  coeffs_truth.a4 .* x_full .^ 4 .+
                  coeffs_truth.a5 .* x_full .^ 5 .+
                  coeffs_truth.a6 .* x_full .^ 6
        proj = polynomial_project(φ_input, TEST_OMEGA, TEST_MASK; orders=2:6)
        @test proj.residual_fraction < 1e-10
        @test abs(proj.coeffs.a2 - coeffs_truth.a2) < 1e-8
        @test abs(proj.coeffs.a3 - coeffs_truth.a3) < 1e-8
        @test abs(proj.coeffs.a4 - coeffs_truth.a4) < 1e-8
        @test abs(proj.coeffs.a5 - coeffs_truth.a5) < 1e-8
        @test abs(proj.coeffs.a6 - coeffs_truth.a6) < 1e-8
    end

    @testset "3b. gauge_fix on even polynomial removes only the mean" begin
        # For an even polynomial (no odd components), gauge_fix should find
        # α = 0 because the least-squares slope of an even function on a
        # symmetric band is zero. It still subtracts a nonzero mean C.
        ω_b = TEST_OMEGA[TEST_MASK]
        ω_mean = mean(ω_b)
        ω_range = maximum(ω_b) - minimum(ω_b)
        x_full = 2 .* (TEST_OMEGA .- ω_mean) ./ ω_range
        φ_input = 1.3 .* x_full .^ 2 .+ 0.7 .* x_full .^ 4 .+ 0.1 .* x_full .^ 6
        φ_g, (C, α) = gauge_fix(φ_input, TEST_MASK, TEST_OMEGA)
        @test abs(α) < 1e-12   # no linear gauge on even functions
        @test abs(mean(φ_g[TEST_MASK])) < 1e-12
        # After removing only the mean, the structure is still recognisable
        # by a polynomial fit that ALSO allows an offset — here we test that
        # residual_fraction is tiny when we add a polynomial offset check by
        # gauge-fixing twice (idempotence already tested, but confirming
        # the phase retains its quadratic-leading character):
        @test maximum(abs.(φ_g .- (φ_input .- C))) < 1e-12
    end

    @testset "4. polynomial_project recovery under noise" begin
        # Polynomial + small broadband noise → coefficients still recovered
        ω_b = TEST_OMEGA[TEST_MASK]
        ω_mean = mean(ω_b)
        ω_range = maximum(ω_b) - minimum(ω_b)
        x_full = 2 .* (TEST_OMEGA .- ω_mean) ./ ω_range
        Random.seed!(2)
        φ_clean = 1.1 .* x_full .^ 2 .+ (-0.4) .* x_full .^ 3 .+ 0.8 .* x_full .^ 4
        φ_noisy = φ_clean .+ 1e-6 .* randn(TEST_Nt)
        proj = polynomial_project(φ_noisy, TEST_OMEGA, TEST_MASK; orders=2:6)
        @test abs(proj.coeffs.a2 - 1.1) < 1e-4
        @test abs(proj.coeffs.a3 - (-0.4)) < 1e-4
        @test abs(proj.coeffs.a4 - 0.8) < 1e-4
        @test proj.residual_fraction < 1e-6
    end

    @testset "5. phase_similarity symmetry" begin
        Random.seed!(3)
        a = randn(TEST_Nt)
        b = randn(TEST_Nt)
        s_ab = phase_similarity(a, b, TEST_MASK)
        s_ba = phase_similarity(b, a, TEST_MASK)
        @test s_ab.rms_diff ≈ s_ba.rms_diff atol=1e-15
        @test s_ab.cosine_sim ≈ s_ba.cosine_sim atol=1e-15
    end

    @testset "6. phase_similarity self-identity" begin
        Random.seed!(4)
        a = randn(TEST_Nt)
        s = phase_similarity(a, a, TEST_MASK)
        @test s.rms_diff < 1e-15
        @test abs(s.cosine_sim - 1.0) < 1e-15
    end

    @testset "7. gauge_fix preserves (Nt, 1) matrix shape" begin
        Random.seed!(5)
        φ_mat = reshape(randn(TEST_Nt), TEST_Nt, 1)
        φ_fixed, _ = gauge_fix(φ_mat, TEST_MASK, TEST_OMEGA)
        @test size(φ_fixed) == (TEST_Nt, 1)
        @test abs(mean(φ_fixed[TEST_MASK, 1])) < 1e-12
    end

    @testset "8. input_band_mask captures 99.9% of energy" begin
        Random.seed!(6)
        # Simulate a spectrally narrow pulse: 1D complex
        Δf = fftfreq(TEST_Nt, 1 / TEST_Dt)
        pulse_spec = complex.(exp.(-(Δf ./ 1.0) .^ 2))   # Gaussian, 1 THz 1/e
        mask = input_band_mask(pulse_spec; energy_fraction=0.999)
        E_total = sum(abs2.(pulse_spec))
        E_masked = sum(abs2.(pulse_spec[mask]))
        @test E_masked / E_total >= 0.999
        # Mask should be substantially smaller than full grid for a narrow pulse
        @test sum(mask) < TEST_Nt ÷ 2
    end

    @testset "9. omega_vector consistency" begin
        ω = omega_vector(1215.26, TEST_Dt, TEST_Nt)
        @test length(ω) == TEST_Nt
        # FFT order: first bin is 0, Nyquist is at index Nt/2 + 1
        @test ω[1] == 0.0
        # fftfreq returns THz, so 2π·THz = rad/ps. Bin spacing check:
        expected_dω = 2π / (TEST_Nt * TEST_Dt)
        @test ω[2] - ω[1] ≈ expected_dω atol=1e-12
    end

    @testset "10. polynomial_project handles linear gauge residual gracefully" begin
        # A *pure* linear input should project mostly to zero (it's a gauge mode)
        # after gauge fix: polynomial_project on gauge-fixed pure linear → all ~0
        φ_linear = 2.5 .* TEST_OMEGA .+ 1.2
        φ_g, _ = gauge_fix(φ_linear, TEST_MASK, TEST_OMEGA)
        proj = polynomial_project(φ_g, TEST_OMEGA, TEST_MASK; orders=2:6)
        @test maximum(abs.(collect(values(Dict(k => v for (k, v) in pairs(proj.coeffs)
                                                 if startswith(String(k), "a"))))) ) < 1e-10
    end
end

@info "All Phase 13 primitive tests passed."
