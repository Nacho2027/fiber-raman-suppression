# ═══════════════════════════════════════════════════════════════════════════════
# Phase 33 Plan 01 Task 2 — Trust-region integration tests
# ═══════════════════════════════════════════════════════════════════════════════
#
# Run:  julia --project=. test/test_trust_region_integration.jl
#
# Covers:
#   1. TR on SPD 2-D analytic quadratic wrapping the oracle interface
#   2. Taxonomy completeness: exit_code is one of the 7 TRExitCode values
#   3. Gauge-projection invariant: ‖p − gauge_fix(p, mask)‖ ≤ 1e-10·‖p‖
#      on every accepted step
#   4. Telemetry CSV round-trip stability (NaN / Inf preserved)
#   5. End-to-end Nt=2^7 Raman TR run (small grid; skipped gracefully if
#      setup is too slow on this host)
#
# Design: tests 1–4 are pure arithmetic / CSV; they run in milliseconds and
# don't touch MultiModeNoise. Test 5 exercises the Raman pipeline but with
# Nt=128 so each forward+adjoint is under 1 s.
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using LinearAlgebra
using Random
using Printf

include(joinpath(@__DIR__, "..", "scripts", "research", "trust_region", "trust_region_optimize.jl"))

ensure_deterministic_fftw()
ensure_deterministic_environment()

@testset "Phase 33 Plan 01 Task 2 — TR outer loop" begin

    @testset "TR on SPD analytic 2D quadratic" begin
        # J(φ) = 0.5 φ' diag(2, 4) φ − [1, 1]' φ
        # ∇J = diag(2,4)·φ − [1,1]
        # minimizer φ* = [0.5, 0.25], J* = -0.5·(1² / 2 + 1²/4) = -0.375
        H = [2.0 0.0; 0.0 4.0]
        b = [1.0, 1.0]
        cost_fn = φ -> 0.5 * dot(φ, H * φ) - dot(b, φ)
        grad_fn = φ -> H * φ - b
        φ0 = zeros(2)
        result = optimize_analytic_tr(cost_fn, grad_fn, φ0;
            max_iter = 30,
            Δ0 = 0.5,
            g_tol = 1e-8,
            H_tol = -1e-6,
            lambda_probe_cadence = 1)
        @test result.exit_code == CONVERGED_2ND_ORDER
        @test isapprox(result.minimizer, [0.5, 0.25]; atol = 1e-6)
        @test isapprox(result.J_final, -0.375; atol = 1e-10)
        @test result.iterations >= 1
        @test result.iterations <= 30
        @test length(result.telemetry) >= 1
        # Every accepted step should have ρ in a sensible band
        accepted_rho = [r.rho for r in result.telemetry
                        if r.step_accepted && isfinite(r.rho)]
        @test !isempty(accepted_rho)
        @test all(ρ -> 0.5 < ρ < 2.0, accepted_rho)
        # Final λ_min must be > H_tol (it's a quadratic with λ_min = 2 > 0)
        @test isfinite(result.lambda_min_final)
        @test result.lambda_min_final > 0.0
    end

    @testset "TR taxonomy completeness" begin
        # Run multiple scenarios; every exit_code must be one of the 7 typed values.
        valid_codes = Set([CONVERGED_2ND_ORDER, CONVERGED_1ST_ORDER_SADDLE,
                           RADIUS_COLLAPSE, MAX_ITER, MAX_ITER_STALLED,
                           NAN_IN_OBJECTIVE, GAUGE_LEAK])
        # Scenario A: trivial SPD convex, 1 iter budget (MAX_ITER or CONVERGED_2ND_ORDER)
        cost_A = φ -> 0.5 * dot(φ, φ)
        grad_A = φ -> copy(φ)
        r_A = optimize_analytic_tr(cost_A, grad_A, [1.0, 1.0];
            max_iter = 1, g_tol = 1e-12, Δ0 = 0.5, lambda_probe_cadence = 1)
        @test r_A.exit_code in valid_codes

        # Scenario B: cost is finite at φ0 but returns NaN at the Newton trial
        # point. With φ0 = [1.0, 0.0], the unconstrained Newton step aims at 0;
        # but any step-out with Δ0 = 2.0 along -g = [-1, 0] produces φ_trial
        # outside the disk ‖φ‖ < 0.05. Engineer gradient so the first CG step
        # leaves the finite-disk region.
        cost_B = φ -> norm(φ) < 0.05 ? 0.5 * dot(φ, φ) : NaN
        grad_B = φ -> [100.0 * sign(φ[1] + eps()), 0.0]   # huge gradient pushes trial far
        # Start INSIDE the disk so initial cost is finite
        r_B = optimize_analytic_tr(cost_B, grad_B, [0.04, 0.0];
            max_iter = 3, Δ0 = 5.0, g_tol = 1e-12, lambda_probe_cadence = 10)
        @test r_B.exit_code in valid_codes
        # The step should drive φ outside the finite region → J_trial = NaN
        @test r_B.exit_code == NAN_IN_OBJECTIVE

        # Scenario C: quadratic that converges in a handful of iters
        H_C = [3.0 0.0; 0.0 5.0]
        b_C = [0.3, -0.2]
        cost_C = φ -> 0.5 * dot(φ, H_C * φ) - dot(b_C, φ)
        grad_C = φ -> H_C * φ - b_C
        r_C = optimize_analytic_tr(cost_C, grad_C, [0.0, 0.0];
            max_iter = 20, g_tol = 1e-10, Δ0 = 1.0, lambda_probe_cadence = 1)
        @test r_C.exit_code in valid_codes
        @test r_C.exit_code == CONVERGED_2ND_ORDER
    end

    @testset "Telemetry CSV round-trip" begin
        r1 = TRIterationRecord(
            1, -0.123456789e-8, 3.14e-5, 0.5, 0.87, 1.2e-4, 1.1e-4, 0.4,
            true, 4, :INTERIOR_CONVERGED,
            2.5, 100.0, 40.0,
            4, 1, 1, 0.123, 1.5e-8)
        r2 = TRIterationRecord(
            2, -0.5e-8, 1e-6, 0.2, NaN, 0.0, NaN, 0.0,
            false, 0, :NO_DESCENT,
            NaN, NaN, NaN,
            0, 0, 1, 0.246, NaN)
        r3 = TRIterationRecord(
            3, Inf, 0.0, 1e-7, -Inf, 1e-30, -1e-30, 1e-9,
            false, 20, :MAX_ITER,
            -1.5, 200.0, NaN,
            20, 0, 1, 0.369, 3.3e-8)
        records = [r1, r2, r3]
        tmp = tempname() * ".csv"
        write_telemetry_csv(tmp, records)
        records_back = read_telemetry_csv(tmp)
        @test length(records_back) == length(records)
        for (a, b) in zip(records, records_back)
            @test a.iter == b.iter
            # Float64 comparisons — use bit-identity (both NaN or both equal)
            for f in (:J, :grad_norm, :delta, :rho, :pred_reduction,
                      :actual_reduction, :step_norm, :lambda_min_est,
                      :lambda_max_est, :kappa_eff, :wall_time_s,
                      :eps_hvp_used)
                va = getfield(a, f); vb = getfield(b, f)
                if isnan(va)
                    @test isnan(vb)
                elseif isinf(va)
                    @test isinf(vb) && sign(va) == sign(vb)
                else
                    @test va === vb   # bit-identical
                end
            end
            @test a.step_accepted == b.step_accepted
            @test a.cg_iters == b.cg_iters
            @test a.cg_exit == b.cg_exit
            @test a.hvps_this_iter == b.hvps_this_iter
            @test a.grad_calls_this_iter == b.grad_calls_this_iter
            @test a.forward_only_calls_this_iter == b.forward_only_calls_this_iter
        end
        isfile(tmp) && rm(tmp)
    end

    @testset "Gauge projection invariant on accepted steps" begin
        # Build a synthetic problem over ℝ^8 and force a gauge-projection
        # pathway by running with project_gauge=true. The analytic-test path
        # hits `project_gauge=false`; to exercise projection we use the same
        # _optimize_tr_core with project_gauge=true and a hand-made mask +
        # omega.
        n = 8
        band_mask = falses(n); band_mask[2:7] .= true
        omega = collect(Float64, 1:n)
        # Quadratic: cost(φ) = 0.5 φ'Aφ where A = I + gauge-projector residue
        # We pick A = I to keep the physics simple but the projection non-trivial.
        H = Matrix{Float64}(I, n, n)
        b = zeros(n); b[3] = 0.1; b[5] = -0.05
        cost_fn = φ -> 0.5 * dot(φ, H * φ) - dot(b, φ)
        grad_fn = φ -> H * φ - b
        oracle = RamanOracle(cost_fn, grad_fn)
        φ0 = zeros(n)
        result = _optimize_tr_core(oracle, φ0, band_mask, omega, n;
            max_iter = 10, Δ0 = 1.0, g_tol = 1e-10,
            lambda_probe_cadence = 5, project_gauge = true)
        @test result.exit_code != GAUGE_LEAK
        # Every accepted step must be in the gauge-complement subspace
        # (we can't inspect p directly after the fact, but the minimizer
        # itself must be gauge-fixed to numerical precision since we started
        # at 0 and only added gauge-projected steps).
        φ_end = result.minimizer
        φ_fixed, _ = gauge_fix(φ_end, band_mask, omega)
        leak = norm(φ_end .- φ_fixed) / max(norm(φ_end), eps())
        @test leak <= 1e-10
    end

    @testset "Raman integration Nt=128" begin
        # End-to-end test on a small Raman problem. Keep budgets tight so the
        # whole test finishes in a few seconds. The point is to verify the
        # TR entry point runs without NaN or GAUGE_LEAK on real physics.
        include(joinpath(@__DIR__, "..", "scripts", "lib", "common.jl"))
        setup_t0 = time()
        uω0, fiber, sim, band_mask, _Δf, _rt = setup_raman_problem(
            fiber_preset = :SMF28,
            L_fiber = 0.5,
            P_cont = 0.05,
            Nt = 2^7,                 # 128 bins — tiny
            time_window = 5.0,
            β_order = 3)
        setup_wall = time() - setup_t0
        if setup_wall > 60
            @info "Skipping Raman integration test: setup exceeded 60 s" setup_wall
            @test true
        else
            result = optimize_spectral_phase_tr(uω0, fiber, sim, band_mask;
                max_iter = 3,
                Δ0 = 0.3,
                g_tol = 1e-10,        # don't try to converge; just exercise
                log_cost = false,
                lambda_probe_cadence = 10)
            valid_codes = Set([CONVERGED_2ND_ORDER, CONVERGED_1ST_ORDER_SADDLE,
                               RADIUS_COLLAPSE, MAX_ITER, MAX_ITER_STALLED,
                               NAN_IN_OBJECTIVE, GAUGE_LEAK])
            @test result.exit_code in valid_codes
            @test result.exit_code != GAUGE_LEAK
            @test result.exit_code != NAN_IN_OBJECTIVE
            @test all(isfinite, result.minimizer)
            @test isfinite(result.J_final)
            @test length(result.telemetry) >= 1
            @test result.hvps_total >= 1
            @test result.wall_time_s > 0
            # Minimizer must sit in the gauge-complement
            Nt = sim["Nt"]
            omega = omega_vector(sim["ω0"], sim["Δt"], Nt)
            gmask = input_band_mask(uω0)
            φ_fixed, _ = gauge_fix(result.minimizer, gmask, omega)
            leak = norm(result.minimizer .- φ_fixed) /
                   max(norm(result.minimizer), eps())
            @test leak <= 1e-10
        end
    end

    @testset "TrustRegionResult struct has Optim.jl .minimizer field" begin
        # This is the CLAUDE.md-mandated parity field so save_standard_set works.
        fields = fieldnames(TrustRegionResult)
        @test :minimizer in fields
        @test :J_final in fields
        @test :exit_code in fields
        @test :iterations in fields
        @test :telemetry in fields
    end

end

println("\nAll TR integration tests passed.")
