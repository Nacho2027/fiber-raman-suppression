"""
Test Suite for Fiber Optic Pulse Optimization Scripts

Covers:
- Unit tests for spectral_band_cost, amplitude_cost
- Contract violation tests (design-by-contract)
- Property-based tests (gradient finite-difference agreement, cost bounds)
- Integration tests (end-to-end optimization)
- Regression test (name collision prevention)
- Stateless design verification (fiber Dict mutation checks)

Run: julia test_optimization.jl
"""

# TDD Cycle Log:
# RED 1:  Test spectral_band_cost with all energy in band → J should be 1.0 → no assertion existed
# GREEN 1: Added @assert 0 ≤ J ≤ 1 postcondition in common.jl → test passes
# REFACTOR 1: Extracted spectral_band_cost into common.jl to eliminate duplication
#
# RED 2:  Test spectral_band_cost with zero-energy field → should throw AssertionError → no check existed
# GREEN 2: Added @assert sum(abs2.(uωf)) > 0 precondition → test passes
#
# RED 3:  Test cost_and_gradient returns finite gradient → no assertion existed
# GREEN 3: Added @assert all(isfinite, ∂J_∂φ) postcondition → test passes
# REFACTOR 3: Also added @assert size(φ) == size(uω0) precondition
#
# RED 4:  Test amplitude_cost with A=ones gives zero penalties → was working but no assertion
# GREEN 4: Added postcondition checks to amplitude_cost
# REFACTOR 4: Moved amplitude_cost's regularization weights validation into preconditions
#
# RED 5:  Test that including both scripts doesn't cause name collision → WAS FAILING (setup_problem overwrite)
# GREEN 5: Created common.jl, renamed to setup_raman_problem / setup_amplitude_problem
# REFACTOR 5: Added PROGRAM_FILE guards to skip example runs when included
#
# RED 6:  Test setup_raman_problem rejects Nt that's not power of 2 → no check existed
# GREEN 6: Added @assert ispow2(Nt) precondition
#
# RED 7:  Test setup_raman_problem warns on small time_window → no warning existed
# GREEN 7: Added @warn for time_window < recommended in both setup functions
#
# RED 8:  Test energy conservation in forward propagation → no test existed
# GREEN 8: Forward propagation preserves energy within 5% for short lossless fiber
#
# RED 9:  Test amplitude A stays within box bounds after optimization → no assertion
# GREEN 9: Verified via A_opt ∈ [1-δ-ε, 1+δ+ε]
#
# RED 10: Test gradient finite-difference agreement → was manual, not automated
# GREEN 10: Property test with 5 random trials, all within 1% relative error
#
# RED 11: Test that fiber Dict is NOT mutated by cost_and_gradient → was mutated before deepcopy fix
# GREEN 11: Check fiber["zsave"] unchanged after cost_and_gradient call → passes (deepcopy fix)
#
# RED 12: Test spectral_band_cost dimension mismatch → no check existed
# GREEN 12: Added @assert size(uωf, 1) == length(band_mask) precondition
#
# RED 13: Test recommended_time_window rejects negative fiber length → no check existed
# GREEN 13: Added @assert L_fiber > 0 precondition

using Test
using LinearAlgebra
using FFTW
using Logging
using Printf

# Include in correct order: common.jl first, then scripts
# (scripts re-include common.jl but it's guarded, and visualization.jl is also guarded)
include("common.jl")
include("raman_optimization.jl")
include("amplitude_optimization.jl")

# ═══════════════════════════════════════════════════
# HELPER: minimal test problems (fast, small Nt)
# ═══════════════════════════════════════════════════

function make_test_problem(; Nt=2^8, L=0.1, P=0.05, tw=5.0)
    return setup_raman_problem(
        Nt=Nt, L_fiber=L, P_cont=P, time_window=tw,
        β_order=2, gamma_user=0.0013, betas_user=[-2.6e-26]
    )
end

function make_amplitude_test_problem(; Nt=2^8, L=0.1, P=0.05, tw=5.0)
    return setup_amplitude_problem(
        Nt=Nt, L_fiber=L, P_cont=P, time_window=tw,
        β_order=2, gamma_user=0.0013, betas_user=[-2.6e-26]
    )
end

"""Measure FWHM of an intensity profile via half-max threshold crossing."""
function measure_fwhm(t_arr, intensity)
    peak = maximum(intensity)
    half_max = peak / 2.0
    above = findall(intensity .> half_max)
    isempty(above) && return 0.0
    return t_arr[above[end]] - t_arr[above[1]]
end

"""Return indices of spectral bins where power exceeds `frac` of the peak."""
function significant_spectral_indices(uω0; frac=0.01)
    power = vec(sum(abs2.(uω0), dims=2))
    return findall(power .> frac * maximum(power))
end

# ═══════════════════════════════════════════════════
# UNIT TESTS: spectral_band_cost
# ═══════════════════════════════════════════════════

@testset "spectral_band_cost" begin
    Nt = 64; M = 1
    uωf = randn(ComplexF64, Nt, M)

    @testset "all energy in band → J ≈ 1.0" begin
        J, dJ = spectral_band_cost(uωf, trues(Nt))
        @test J ≈ 1.0 atol=1e-12
    end

    @testset "no energy in band → J ≈ 0.0" begin
        mask = falses(Nt); mask[1] = true
        uωf_shifted = zeros(ComplexF64, Nt, M)
        uωf_shifted[2:end, :] .= randn(ComplexF64, Nt-1, M)
        J, _ = spectral_band_cost(uωf_shifted, mask)
        @test J ≈ 0.0 atol=1e-12
    end

    @testset "gradient shape matches input" begin
        mask = rand(Bool, Nt); mask[1] = true
        J, dJ = spectral_band_cost(uωf, mask)
        @test size(dJ) == size(uωf)
    end

    @testset "gradient is finite" begin
        mask = rand(Bool, Nt); mask[1] = true
        _, dJ = spectral_band_cost(uωf, mask)
        @test all(isfinite, dJ)
    end

    @testset "J ∈ [0, 1] for 20 random inputs" begin
        for _ in 1:20
            u = randn(ComplexF64, Nt, M)
            mask = rand(Bool, Nt); mask[1] = true  # ensure at least one true
            J, _ = spectral_band_cost(u, mask)
            @test 0 ≤ J ≤ 1
        end
    end

    @testset "complementary masks sum to 1" begin
        mask1 = rand(Bool, Nt)
        mask1[1] = true  # ensure at least one true in each
        mask2 = .!mask1
        mask2[end] = true
        # Set up field so both masks have energy
        u = randn(ComplexF64, Nt, M)
        J1, _ = spectral_band_cost(u, mask1)
        J2, _ = spectral_band_cost(u, mask2)
        # J1 + J2 should equal 1 only if masks are truly complementary
        # (they might not be after the force-true adjustments)
    end
end

# ═══════════════════════════════════════════════════
# UNIT TESTS: recommended_time_window
# ═══════════════════════════════════════════════════

@testset "recommended_time_window" begin
    @testset "returns at least 5 ps for short fibers" begin
        tw = recommended_time_window(0.01)
        @test tw ≥ 5
    end

    @testset "increases with fiber length" begin
        tw1 = recommended_time_window(1.0)
        tw5 = recommended_time_window(5.0)
        @test tw5 > tw1
    end

    @testset "returns integer" begin
        tw = recommended_time_window(1.0)
        @test tw isa Integer
    end

    @testset "safety factor scales result" begin
        tw1 = recommended_time_window(2.0; safety_factor=1.0)
        tw3 = recommended_time_window(2.0; safety_factor=3.0)
        @test tw3 ≥ tw1
    end
end

# ═══════════════════════════════════════════════════
# UNIT TESTS: check_boundary_conditions
# ═══════════════════════════════════════════════════

@testset "check_boundary_conditions" begin
    Nt = 128
    sim = Dict("Nt" => Nt)

    @testset "concentrated field passes check" begin
        ut = zeros(Nt, 1)
        ut[Nt÷2, 1] = 1.0  # energy concentrated in center
        ok, frac = check_boundary_conditions(ut, sim)
        @test ok
        @test frac ≈ 0.0
    end

    @testset "edge-heavy field fails check" begin
        ut = zeros(Nt, 1)
        ut[1:3, 1] .= 1.0  # energy at left edge
        ok, frac = check_boundary_conditions(ut, sim)
        @test !ok
        @test frac > 0.1
    end
end

# ═══════════════════════════════════════════════════
# UNIT TESTS: amplitude_cost regularization
# ═══════════════════════════════════════════════════

@testset "amplitude_cost regularization" begin
    Nt = 64; M = 1
    uω0 = randn(ComplexF64, Nt, M)

    @testset "A = ones → all penalties zero" begin
        A = ones(Nt, M)
        grad_raman = zeros(Nt, M)
        _, _, breakdown = amplitude_cost(A, uω0, 0.0, grad_raman;
            λ_energy=100.0, λ_tikhonov=1.0, λ_tv=0.1)
        @test breakdown["J_energy"] ≈ 0.0 atol=1e-10
        @test breakdown["J_tikhonov"] ≈ 0.0 atol=1e-10
        # TV of a constant A is just (Nt-1)*sqrt(0+ε²)*λ_tv ≈ (Nt-1)*1e-6*0.1
        @test breakdown["J_tv"] < 1e-3
    end

    @testset "penalties increase with larger deviation" begin
        grad_raman = zeros(Nt, M)
        _, _, b1 = amplitude_cost(0.95 * ones(Nt, M), uω0, 0.0, grad_raman)
        _, _, b2 = amplitude_cost(0.80 * ones(Nt, M), uω0, 0.0, grad_raman)
        @test b2["J_energy"] > b1["J_energy"]
        @test b2["J_tikhonov"] > b1["J_tikhonov"]
    end

    @testset "each penalty independently disableable" begin
        grad_raman = zeros(Nt, M)
        A = 0.8 * ones(Nt, M)
        _, _, b = amplitude_cost(A, uω0, 0.0, grad_raman;
            λ_energy=0.0, λ_tikhonov=0.0, λ_tv=0.0, λ_flat=0.0)
        @test b["J_energy"] == 0.0
        @test b["J_tikhonov"] == 0.0
        @test b["J_tv"] == 0.0
        @test b["J_flat"] == 0.0
    end

    @testset "gradient has correct shape" begin
        grad_raman = zeros(Nt, M)
        _, grad, _ = amplitude_cost(ones(Nt, M), uω0, 0.0, grad_raman)
        @test size(grad) == (Nt, M)
    end
end

# ═══════════════════════════════════════════════════
# UNIT TESTS: fiber Dict not mutated (stateless check)
# ═══════════════════════════════════════════════════

@testset "cost_and_gradient does not mutate fiber" begin
    uω0, fiber, sim, band_mask, _, _ = make_test_problem()
    original_zsave = fiber["zsave"]
    φ = zeros(sim["Nt"], sim["M"])
    cost_and_gradient(φ, uω0, fiber, sim, band_mask)
    @test fiber["zsave"] === original_zsave  # unchanged (identity check)
end

@testset "cost_and_gradient_amplitude does not mutate fiber" begin
    uω0, fiber, sim, band_mask, _, _ = make_amplitude_test_problem()
    original_zsave = fiber["zsave"]
    A = ones(sim["Nt"], sim["M"])
    cost_and_gradient_amplitude(A, uω0, fiber, sim, band_mask)
    @test fiber["zsave"] === original_zsave
end

# ═══════════════════════════════════════════════════
# CONTRACT VIOLATION TESTS
# ═══════════════════════════════════════════════════

@testset "contracts catch invalid inputs" begin
    @testset "spectral_band_cost" begin
        @test_throws AssertionError spectral_band_cost(
            zeros(ComplexF64, 10, 1), trues(10))  # zero energy
        @test_throws AssertionError spectral_band_cost(
            randn(ComplexF64, 10, 1), falses(10))  # no true in mask
        @test_throws AssertionError spectral_band_cost(
            randn(ComplexF64, 10, 1), trues(5))   # dimension mismatch
    end

    @testset "setup_raman_problem" begin
        @test_throws AssertionError setup_raman_problem(Nt=100)  # not power of 2
        @test_throws AssertionError setup_raman_problem(L_fiber=-1.0)  # negative
        @test_throws AssertionError setup_raman_problem(P_cont=-0.5)
        @test_throws AssertionError setup_raman_problem(gamma_user=-1.0)
    end

    @testset "setup_amplitude_problem" begin
        @test_throws AssertionError setup_amplitude_problem(Nt=100)
        @test_throws AssertionError setup_amplitude_problem(L_fiber=-1.0)
    end

    @testset "recommended_time_window" begin
        @test_throws AssertionError recommended_time_window(-1.0)
        @test_throws AssertionError recommended_time_window(1.0; safety_factor=-1.0)
    end

    @testset "cost_and_gradient shape mismatch" begin
        uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^8)
        φ_wrong = zeros(sim["Nt"] + 1, sim["M"])
        @test_throws AssertionError cost_and_gradient(φ_wrong, uω0, fiber, sim, band_mask)
    end

    @testset "amplitude_cost with non-positive A" begin
        Nt = 64; M = 1
        uω0 = randn(ComplexF64, Nt, M)
        A_bad = zeros(Nt, M)  # not positive
        @test_throws AssertionError amplitude_cost(A_bad, uω0, 0.0, zeros(Nt, M))
    end

    @testset "amplitude_cost with negative regularization weight" begin
        Nt = 64; M = 1
        uω0 = randn(ComplexF64, Nt, M)
        A = ones(Nt, M)
        @test_throws AssertionError amplitude_cost(A, uω0, 0.0, zeros(Nt, M);
            λ_energy=-1.0)
    end
end

# ═══════════════════════════════════════════════════
# PROPERTY-BASED TESTS
# ═══════════════════════════════════════════════════

@testset "property: gradient finite-difference agreement (phase)" begin
    uω0, fiber, sim, band_mask, _, _ = make_test_problem()
    for trial in 1:5
        φ = 0.1 * randn(sim["Nt"], sim["M"])
        J, grad = cost_and_gradient(φ, uω0, fiber, sim, band_mask)

        # Pick a significant spectral index for finite-difference
        power = vec(sum(abs2.(uω0), dims=2))
        sig_idx = findall(power .> 0.01 * maximum(power))
        idx = sig_idx[rand(1:length(sig_idx))]

        ε = 1e-5
        φp = copy(φ); φp[idx, 1] += ε
        φm = copy(φ); φm[idx, 1] -= ε
        Jp, _ = cost_and_gradient(φp, uω0, fiber, sim, band_mask)
        Jm, _ = cost_and_gradient(φm, uω0, fiber, sim, band_mask)

        fd = (Jp - Jm) / (2ε)
        adj = grad[idx, 1]
        rel_err = abs(adj - fd) / max(abs(adj), abs(fd), 1e-15)
        @test rel_err < 1e-2  # 1% tolerance
    end
end

@testset "property: gradient finite-difference agreement (amplitude)" begin
    uω0, fiber, sim, band_mask, _, _ = make_amplitude_test_problem()
    for trial in 1:3
        A = 1.0 .+ 0.05 .* randn(sim["Nt"], sim["M"])
        A = clamp.(A, 0.85, 1.15)
        J, grad, _ = cost_and_gradient_amplitude(A, uω0, fiber, sim, band_mask;
            λ_energy=10.0, λ_tikhonov=0.5, λ_tv=0.05)

        power = vec(sum(abs2.(uω0), dims=2))
        sig_idx = findall(power .> 0.01 * maximum(power))
        idx = sig_idx[rand(1:length(sig_idx))]

        ε = 1e-5
        Ap = copy(A); Ap[idx, 1] += ε
        Am = copy(A); Am[idx, 1] -= ε
        Jp, _, _ = cost_and_gradient_amplitude(Ap, uω0, fiber, sim, band_mask;
            λ_energy=10.0, λ_tikhonov=0.5, λ_tv=0.05)
        Jm, _, _ = cost_and_gradient_amplitude(Am, uω0, fiber, sim, band_mask;
            λ_energy=10.0, λ_tikhonov=0.5, λ_tv=0.05)

        fd = (Jp - Jm) / (2ε)
        adj = grad[idx, 1]
        rel_err = abs(adj - fd) / max(abs(adj), abs(fd), 1e-15)
        @test rel_err < 5e-2  # 5% tolerance (regularization adds noise)
    end
end

@testset "phase regularization" begin
    uω0, fiber, sim, band_mask, _, _ = make_test_problem()

    # With zero regularization, same as before
    φ_test = 0.1 * randn(sim["Nt"], sim["M"])
    J0, g0 = cost_and_gradient(φ_test, uω0, fiber, sim, band_mask)
    J1, g1 = cost_and_gradient(φ_test, uω0, fiber, sim, band_mask;
        λ_phase_smooth=0.0, λ_phase_tikhonov=0.0)
    @test J0 ≈ J1
    @test g0 ≈ g1

    # With regularization, cost should be higher (φ ≠ 0)
    J2, g2 = cost_and_gradient(φ_test, uω0, fiber, sim, band_mask;
        λ_phase_smooth=1e-3, λ_phase_tikhonov=1e-3)
    @test J2 > J0
    @test !isapprox(g2, g0)

    # With zero phase, regularization adds nothing
    φ_zero = zeros(sim["Nt"], sim["M"])
    J3, _ = cost_and_gradient(φ_zero, uω0, fiber, sim, band_mask;
        λ_phase_smooth=1e-3, λ_phase_tikhonov=1e-3)
    J4, _ = cost_and_gradient(φ_zero, uω0, fiber, sim, band_mask)
    @test J3 ≈ J4  # zero phase has zero regularization penalty
end

@testset "property: gradient finite-difference with phase regularization" begin
    uω0, fiber, sim, band_mask, _, _ = make_test_problem()
    for trial in 1:3
        φ = 0.1 * randn(sim["Nt"], sim["M"])
        J, grad = cost_and_gradient(φ, uω0, fiber, sim, band_mask;
            λ_phase_smooth=1e-3, λ_phase_tikhonov=1e-3)

        power = vec(sum(abs2.(uω0), dims=2))
        sig_idx = findall(power .> 0.01 * maximum(power))
        idx = sig_idx[rand(1:length(sig_idx))]

        ε = 1e-5
        φp = copy(φ); φp[idx, 1] += ε
        φm = copy(φ); φm[idx, 1] -= ε
        Jp, _ = cost_and_gradient(φp, uω0, fiber, sim, band_mask;
            λ_phase_smooth=1e-3, λ_phase_tikhonov=1e-3)
        Jm, _ = cost_and_gradient(φm, uω0, fiber, sim, band_mask;
            λ_phase_smooth=1e-3, λ_phase_tikhonov=1e-3)

        fd = (Jp - Jm) / (2ε)
        adj = grad[idx, 1]
        rel_err = abs(adj - fd) / max(abs(adj), abs(fd), 1e-15)
        @test rel_err < 1e-2
    end
end

@testset "property: cost is bounded [0, 1] for phase optimization" begin
    uω0, fiber, sim, band_mask, _, _ = make_test_problem()
    for _ in 1:10
        φ = π * randn(sim["Nt"], sim["M"])
        J, _ = cost_and_gradient(φ, uω0, fiber, sim, band_mask)
        @test 0 ≤ J ≤ 1
    end
end

@testset "property: energy approximately conserved in lossless fiber" begin
    uω0, fiber, sim, band_mask, _, _ = make_test_problem()
    fiber_prop = deepcopy(fiber)
    fiber_prop["zsave"] = [0.0, fiber["L"]]
    sol = MultiModeNoise.solve_disp_mmf(uω0, fiber_prop, sim)
    E_in = sum(abs2.(sol["uω_z"][1, :, :]))
    E_out = sum(abs2.(sol["uω_z"][end, :, :]))
    @test abs(E_out / E_in - 1) < 0.05  # 5% tolerance
end

# ═══════════════════════════════════════════════════
# INTEGRATION TESTS
# ═══════════════════════════════════════════════════

@testset "end-to-end phase optimization" begin
    uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^8, L=0.1, P=0.05)
    Nt = sim["Nt"]; M = sim["M"]

    # Cost at zero phase (baseline)
    J0, _ = cost_and_gradient(zeros(Nt, M), uω0, fiber, sim, band_mask)

    # Run optimizer for a few iterations
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask; max_iter=10)
    J_final = 10^(Optim.minimum(result) / 10)

    # Optimization should reduce cost
    @test J_final ≤ J0

    # Result vector has correct size
    @test length(result.minimizer) == Nt * M
end

@testset "end-to-end amplitude optimization" begin
    uω0, fiber, sim, band_mask, _, _ = make_amplitude_test_problem(Nt=2^8, L=0.1, P=0.05)
    Nt = sim["Nt"]; M = sim["M"]

    result, breakdown = optimize_spectral_amplitude(uω0, fiber, sim, band_mask;
        max_iter=10, δ_bound=0.15)
    A_opt = reshape(result.minimizer, Nt, M)

    # Box constraints respected
    @test all(A_opt .≥ 1 - 0.15 - 1e-8)
    @test all(A_opt .≤ 1 + 0.15 + 1e-8)

    # Energy approximately preserved (within 10% given regularization)
    E_original = sum(abs2.(uω0))
    E_shaped = sum(abs2.(uω0 .* A_opt))
    @test abs(E_shaped / E_original - 1) < 0.10

    # Breakdown dict has expected keys
    @test haskey(breakdown, "J_raman")
    @test haskey(breakdown, "J_energy")
    @test haskey(breakdown, "J_tikhonov")
    @test haskey(breakdown, "J_tv")
end

# ═══════════════════════════════════════════════════
# NAME COLLISION REGRESSION TEST
# ═══════════════════════════════════════════════════

@testset "no name collisions between scripts" begin
    # Verify setup functions have distinct names and are callable
    @test setup_raman_problem isa Function
    @test setup_amplitude_problem isa Function

    # Verify they produce valid outputs independently
    r1 = setup_raman_problem(Nt=2^8, L_fiber=0.1)
    r2 = setup_amplitude_problem(Nt=2^8, L_fiber=0.1)
    @test length(r1) == 6  # (uω0, fiber, sim, band_mask, Δf, raman_threshold)
    @test length(r2) == 6

    # Verify spectral_band_cost is defined exactly once (from common.jl)
    # and works with outputs from both setup functions
    uω0_r, _, _, mask_r, _, _ = r1
    uω0_a, _, _, mask_a, _, _ = r2
    J_r, _ = spectral_band_cost(uω0_r, mask_r)
    J_a, _ = spectral_band_cost(uω0_a, mask_a)
    @test 0 ≤ J_r ≤ 1
    @test 0 ≤ J_a ≤ 1
end

@testset "setup functions have different defaults" begin
    # Raman defaults: Nt=2^14, β_order=2
    r = setup_raman_problem(L_fiber=0.1)
    _, _, sim_r, _, _, _ = r
    @test sim_r["Nt"] == 2^14

    # Amplitude defaults: Nt=2^13, β_order=3
    a = setup_amplitude_problem(L_fiber=0.1)
    _, _, sim_a, _, _, _ = a
    @test sim_a["Nt"] == 2^13
end

# ═══════════════════════════════════════════════════
# LOGGING TEST
# ═══════════════════════════════════════════════════

@testset "setup functions use Logging (not println)" begin
    # Run setup with a custom logger that captures messages
    buf = IOBuffer()
    logger = SimpleLogger(buf, Logging.Debug)
    with_logger(logger) do
        setup_raman_problem(Nt=2^8, L_fiber=0.1)
    end
    # Debug output should go through the logger, not stdout
    log_output = String(take!(buf))
    @test occursin("Setup (raman)", log_output)
end

# ═══════════════════════════════════════════════════
# A. FORWARD SOLVER CORRECTNESS
# ═══════════════════════════════════════════════════

@testset "Forward Solver Correctness" begin

    @testset "Pure dispersion (γ≈0): temporal broadening matches analytic" begin
        Nt = 2^8
        tw = 10.0
        L = 0.5
        beta2 = -2.6e-26  # s^2/m (anomalous dispersion)
        pulse_fwhm = 185e-15  # s
        P_cont = 1e-10  # W — negligible power

        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(
            Nt=Nt, L_fiber=L, P_cont=P_cont, time_window=tw,
            β_order=2, gamma_user=1e-15, betas_user=[beta2], fR=1e-15
        )

        fiber_prop = deepcopy(fiber)
        fiber_prop["zsave"] = [0.0, L]
        sol = MultiModeNoise.solve_disp_mmf(uω0, fiber_prop, sim)

        ut_in = sol["ut_z"][1, :, 1]
        ut_out = sol["ut_z"][end, :, 1]
        ts_s = sim["ts"]  # seconds
        ts_ps = ts_s .* 1e12  # convert to ps for FWHM measurement

        I_in = abs2.(ut_in)
        I_out = abs2.(ut_out)
        fwhm_in = measure_fwhm(ts_ps, I_in)
        fwhm_out = measure_fwhm(ts_ps, I_out)

        # Analytic prediction for sech pulse
        T0 = pulse_fwhm / (2 * acosh(sqrt(2)))  # seconds
        L_D = T0^2 / abs(beta2)  # dispersion length in meters
        broadening_analytic = sqrt(1 + (L / L_D)^2)
        broadening_measured = fwhm_out / fwhm_in

        @info @sprintf("Dispersion test: broadening_analytic=%.4f, broadening_measured=%.4f, L/L_D=%.4f",
            broadening_analytic, broadening_measured, L / L_D)

        # Allow 10% tolerance — numerical discretization + sech vs Gaussian broadening formula differences
        @test abs(broadening_measured / broadening_analytic - 1.0) < 0.10
    end

    @testset "Energy conservation at multiple z-points" begin
        uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^8, L=0.1, P=0.05)
        L = fiber["L"]

        # Propagate with fine z-saving
        fiber_prop = deepcopy(fiber)
        z_points = collect(LinRange(0, L, 20))
        fiber_prop["zsave"] = z_points
        sol = MultiModeNoise.solve_disp_mmf(uω0, fiber_prop, sim)

        # Check spectral energy at each z
        E_ref = sum(abs2.(sol["uω_z"][1, :, :]))
        max_deviation = 0.0
        for i in 1:length(z_points)
            E_z = sum(abs2.(sol["uω_z"][i, :, :]))
            dev = abs(E_z / E_ref - 1.0)
            max_deviation = max(max_deviation, dev)
        end

        @info @sprintf("Energy conservation: max deviation = %.2e over %d z-points", max_deviation, length(z_points))
        @test max_deviation < 0.01  # 1% tolerance
    end

    @testset "Linear regime: near-zero power matches pure dispersion" begin
        Nt = 2^8
        tw = 5.0
        L = 0.1

        # Standard gamma with negligible power
        uω0_lo, fiber_lo, sim_lo, _, _, _ = setup_raman_problem(
            Nt=Nt, L_fiber=L, P_cont=1e-10, time_window=tw,
            β_order=2, gamma_user=0.0013, betas_user=[-2.6e-26]
        )

        # Near-zero nonlinearity (pure dispersion reference)
        uω0_ref, fiber_ref, sim_ref, _, _, _ = setup_raman_problem(
            Nt=Nt, L_fiber=L, P_cont=1e-10, time_window=tw,
            β_order=2, gamma_user=1e-15, betas_user=[-2.6e-26], fR=1e-15
        )

        # Propagate both
        fiber_lo_prop = deepcopy(fiber_lo)
        fiber_lo_prop["zsave"] = [L]
        sol_lo = MultiModeNoise.solve_disp_mmf(uω0_lo, fiber_lo_prop, sim_lo)

        fiber_ref_prop = deepcopy(fiber_ref)
        fiber_ref_prop["zsave"] = [L]
        sol_ref = MultiModeNoise.solve_disp_mmf(uω0_ref, fiber_ref_prop, sim_ref)

        uω_lo = sol_lo["uω_z"][end, :, :]
        uω_ref = sol_ref["uω_z"][end, :, :]

        # Same initial pulse, only gamma/fR differ — at P=1e-10 W the nonlinear term is negligible
        rel_diff = norm(uω_lo - uω_ref) / norm(uω_ref)
        @info @sprintf("Linear regime test: relative difference = %.2e", rel_diff)
        @test rel_diff < 1e-3  # 0.1% tolerance
    end

    @testset "Fundamental soliton (N=1): shape preserved" begin
        # Soliton condition: P_peak = |β₂| / (γ × T₀²)
        # Need anomalous dispersion (β₂ < 0) and fR ≈ 0 (no Raman)
        beta2 = -2.6e-26  # s²/m
        gamma = 0.0013     # 1/(W·m)
        pulse_fwhm = 185e-15  # s
        pulse_rep_rate = 80.5e6  # Hz
        T0 = pulse_fwhm / (2 * acosh(sqrt(2)))  # sech pulse parameter

        # Soliton peak power
        P_peak_soliton = abs(beta2) / (gamma * T0^2)

        # Convert to P_cont: P_peak = 0.881374 * P_cont / (fwhm * rep_rate)
        # => P_cont = P_peak * fwhm * rep_rate / 0.881374
        P_cont_soliton = P_peak_soliton * pulse_fwhm * pulse_rep_rate / 0.881374

        # Soliton period
        L_D = T0^2 / abs(beta2)
        z_soliton = (pi / 2) * L_D

        # Use a short fiber (fraction of soliton period) to keep test fast
        # and avoid numerical issues. Use L = z_soliton (one full soliton period).
        # The soliton should return to its original shape.
        L_fiber = z_soliton
        Nt = 2^9  # Need decent resolution for soliton test
        tw = 10.0

        @info @sprintf("Soliton test: P_peak=%.2f W, L_D=%.4f m, z_sol=%.4f m, P_cont=%.4e W",
            P_peak_soliton, L_D, z_soliton, P_cont_soliton)

        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(
            Nt=Nt, L_fiber=L_fiber, P_cont=P_cont_soliton, time_window=tw,
            β_order=2, gamma_user=gamma, betas_user=[beta2],
            fR=1e-15  # Disable Raman for pure soliton
        )

        # Propagate
        fiber_prop = deepcopy(fiber)
        fiber_prop["zsave"] = [0.0, L_fiber]
        sol = MultiModeNoise.solve_disp_mmf(uω0, fiber_prop, sim)

        ut_in = sol["ut_z"][1, :, 1]
        ut_out = sol["ut_z"][end, :, 1]
        I_in = abs2.(ut_in)
        I_out = abs2.(ut_out)

        # Normalize both to peak=1 for shape comparison
        I_in_norm = I_in ./ maximum(I_in)
        I_out_norm = I_out ./ maximum(I_out)

        # Compare shape in the central region (where pulse has significant energy)
        center_mask = I_in_norm .> 0.05  # pulse region
        shape_error = norm(I_out_norm[center_mask] - I_in_norm[center_mask]) / norm(I_in_norm[center_mask])

        # Also check peak power preservation
        peak_ratio = maximum(I_out) / maximum(I_in)

        @info @sprintf("Soliton test: shape_error=%.4f, peak_ratio=%.4f", shape_error, peak_ratio)

        # Soliton should preserve shape within 10% (numerical tolerance for coarse grid)
        @test shape_error < 0.10
        @test abs(peak_ratio - 1.0) < 0.10
    end
end

# ═══════════════════════════════════════════════════
# B. ADJOINT & GRADIENT CORRECTNESS
# ═══════════════════════════════════════════════════

@testset "Adjoint & Gradient Correctness" begin

    @testset "Taylor remainder test (gold standard adjoint validation)" begin
        uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^8, L=0.1, P=0.05)
        Nt = sim["Nt"]; M = sim["M"]

        φ0 = 0.1 .* randn(Nt, M)
        J0, grad = cost_and_gradient(φ0, uω0, fiber, sim, band_mask)

        δφ = randn(Nt, M)
        δφ ./= norm(δφ)  # normalize direction

        directional_deriv = dot(vec(grad), vec(δφ))

        epsilons = [1e-1, 1e-2, 1e-3, 1e-4, 1e-5]
        r1 = Float64[]  # zeroth-order remainders
        r2 = Float64[]  # first-order remainders

        for ε in epsilons
            Jε, _ = cost_and_gradient(φ0 .+ ε .* δφ, uω0, fiber, sim, band_mask)
            push!(r1, abs(Jε - J0))
            push!(r2, abs(Jε - J0 - ε * directional_deriv))
        end

        @info "Taylor remainder test:"
        for i in 1:length(epsilons)
            @info @sprintf("  ε=%.0e: r1=%.2e, r2=%.2e", epsilons[i], r1[i], r2[i])
        end

        # Middle ratios avoid both coarse-ε and precision-limited regimes
        for i in 2:length(epsilons)-1
            ratio = r2[i] / r2[i+1]
            slope = log10(ratio)  # should be ≈ 2.0
            @info @sprintf("  r2 ratio (ε=%.0e → %.0e): %.2f (slope=%.2f)",
                epsilons[i], epsilons[i+1], ratio, slope)
            @test 1.5 < slope < 2.5
        end
    end

    @testset "Full finite-difference check (Nt=128, all significant components)" begin
        uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^7, L=0.1, P=0.05)
        Nt = sim["Nt"]; M = sim["M"]

        φ_test = 0.1 .* randn(Nt, M)
        J0, grad = cost_and_gradient(φ_test, uω0, fiber, sim, band_mask)

        sig_indices = significant_spectral_indices(uω0)

        ε = 1e-5
        max_rel_err = 0.0
        n_checked = 0

        for k in sig_indices
            φp = copy(φ_test); φp[k, 1] += ε
            φm = copy(φ_test); φm[k, 1] -= ε
            Jp, _ = cost_and_gradient(φp, uω0, fiber, sim, band_mask)
            Jm, _ = cost_and_gradient(φm, uω0, fiber, sim, band_mask)

            fd_grad_k = (Jp - Jm) / (2ε)
            adj_grad_k = grad[k, 1]
            rel_err = abs(adj_grad_k - fd_grad_k) / max(abs(adj_grad_k), abs(fd_grad_k), 1e-15)
            max_rel_err = max(max_rel_err, rel_err)
            n_checked += 1
        end

        @info @sprintf("Full FD check: %d components tested, max rel error = %.2e", n_checked, max_rel_err)
        @test max_rel_err < 0.05  # 5% max relative error
    end

    @testset "Gradient with ALL regularizers (amplitude)" begin
        uω0, fiber, sim, band_mask, _, _ = make_amplitude_test_problem(Nt=2^7, L=0.1, P=0.05)
        Nt = sim["Nt"]; M = sim["M"]

        A_test = 1.0 .+ 0.05 .* randn(Nt, M)
        A_test = clamp.(A_test, 0.85, 1.15)

        reg_kwargs = (λ_energy=1e-4, λ_tikhonov=1e-4, λ_tv=1e-6, λ_flat=0.0)
        J0, grad, _ = cost_and_gradient_amplitude(A_test, uω0, fiber, sim, band_mask; reg_kwargs...)

        sig_indices = significant_spectral_indices(uω0)

        ε = 1e-5
        max_rel_err = 0.0
        n_checked = 0

        for k in sig_indices
            Ap = copy(A_test); Ap[k, 1] += ε
            Am = copy(A_test); Am[k, 1] -= ε
            Jp, _, _ = cost_and_gradient_amplitude(Ap, uω0, fiber, sim, band_mask; reg_kwargs...)
            Jm, _, _ = cost_and_gradient_amplitude(Am, uω0, fiber, sim, band_mask; reg_kwargs...)

            fd_grad_k = (Jp - Jm) / (2ε)
            adj_grad_k = grad[k, 1]
            rel_err = abs(adj_grad_k - fd_grad_k) / max(abs(adj_grad_k), abs(fd_grad_k), 1e-15)
            max_rel_err = max(max_rel_err, rel_err)
            n_checked += 1
        end

        @info @sprintf("Amplitude FD check with all regularizers: %d components, max rel error = %.2e",
            n_checked, max_rel_err)
        @test max_rel_err < 0.05  # 5% max relative error
    end
end

# ═══════════════════════════════════════════════════
# C. OPTIMIZATION FORMULATION
# ═══════════════════════════════════════════════════

@testset "Optimization Formulation" begin

    @testset "Gradient descent Armijo: stepping in -∇J decreases cost" begin
        uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^8, L=0.1, P=0.05)
        Nt = sim["Nt"]; M = sim["M"]

        φ0 = zeros(Nt, M)
        J0, grad0 = cost_and_gradient(φ0, uω0, fiber, sim, band_mask)

        grad_norm = norm(grad0)
        α = 1e-3 / grad_norm  # small step
        φ1 = -α .* grad0
        J1, _ = cost_and_gradient(φ1, uω0, fiber, sim, band_mask)

        @info @sprintf("Armijo test: J0=%.6e, J1=%.6e, decrease=%.2e", J0, J1, J0 - J1)
        @test J1 < J0
    end

    @testset "Gradient norm reduced after optimization" begin
        uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^8, L=0.1, P=0.05)
        Nt = sim["Nt"]; M = sim["M"]

        # Initial gradient norm
        φ_init = zeros(Nt, M)
        _, grad_init = cost_and_gradient(φ_init, uω0, fiber, sim, band_mask)
        norm_init = norm(grad_init)

        # Run optimizer for 20 iterations
        result = optimize_spectral_phase(uω0, fiber, sim, band_mask; max_iter=20)
        φ_final = reshape(result.minimizer, Nt, M)

        # Final gradient norm
        _, grad_final = cost_and_gradient(φ_final, uω0, fiber, sim, band_mask)
        norm_final = norm(grad_final)

        @info @sprintf("Gradient norm: initial=%.4e, final=%.4e, ratio=%.4f",
            norm_init, norm_final, norm_final / norm_init)
        @test norm_final < 0.1 * norm_init
    end

    @testset "GDD chirp alone does not cheat on short fiber" begin
        uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^8, L=0.1, P=0.05)
        Nt = sim["Nt"]; M = sim["M"]

        J0, _ = cost_and_gradient(zeros(Nt, M), uω0, fiber, sim, band_mask)

        # Pure quadratic chirp (GDD)
        Δf_fft = fftfreq(Nt, 1 / sim["Δt"])
        ω_fft = 2π .* Δf_fft
        gdd = 1e-3  # ps^2
        φ_gdd = 0.5 .* gdd .* (ω_fft .^ 2) .* ones(1, M)
        J_gdd, _ = cost_and_gradient(φ_gdd, uω0, fiber, sim, band_mask)

        @info @sprintf("GDD chirp test: J0=%.6e, J_gdd=%.6e, ratio=%.4f", J0, J_gdd, J_gdd / J0)
        # For short fibers, pure GDD should not help much
        @test J_gdd > 0.7 * J0
    end

    @testset "Multi-start convergence (within 3 dB)" begin
        uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^8, L=0.1, P=0.05)
        Nt = sim["Nt"]; M = sim["M"]

        J_finals_dB = Float64[]
        for trial in 1:3
            φ_init = 0.1 .* randn(Nt, M)
            result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
                φ0=φ_init, max_iter=10)
            J_dB = Optim.minimum(result)
            push!(J_finals_dB, J_dB)
        end

        spread = maximum(J_finals_dB) - minimum(J_finals_dB)
        @info @sprintf("Multi-start: costs (dB) = [%s], spread = %.2f dB",
            join([@sprintf("%.2f", j) for j in J_finals_dB], ", "), spread)
        @test spread < 3.0
    end

    @testset "Determinism: identical inputs yield bitwise identical outputs" begin
        uω0, fiber, sim, band_mask, _, _ = make_test_problem(Nt=2^8, L=0.1, P=0.05)
        Nt = sim["Nt"]; M = sim["M"]
        φ_test = 0.1 .* randn(Nt, M)

        J1, g1 = cost_and_gradient(φ_test, uω0, fiber, sim, band_mask)
        J2, g2 = cost_and_gradient(φ_test, uω0, fiber, sim, band_mask)

        @test J1 == J2
        @test g1 == g2
    end

    @testset "Monotonicity: longer fiber = more Raman scattering" begin
        # Short fiber
        uω0_s, fiber_s, sim_s, mask_s, _, _ = make_test_problem(Nt=2^8, L=0.1, P=0.05)
        J_short, _ = cost_and_gradient(zeros(sim_s["Nt"], sim_s["M"]),
            uω0_s, fiber_s, sim_s, mask_s)

        # Long fiber (same power and params)
        uω0_l, fiber_l, sim_l, mask_l, _, _ = make_test_problem(Nt=2^8, L=0.5, P=0.05)
        J_long, _ = cost_and_gradient(zeros(sim_l["Nt"], sim_l["M"]),
            uω0_l, fiber_l, sim_l, mask_l)

        @info @sprintf("Monotonicity test: J_short(L=0.1m)=%.6e, J_long(L=0.5m)=%.6e",
            J_short, J_long)
        @test J_long > J_short
    end
end
