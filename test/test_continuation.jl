"""
Unit + smoke tests for scripts/continuation.jl (Phase 30).

Tests 1-4: pure detector functions (no side effects, fast).
Test 5  : smoke test — tiny lambda-ladder through `run_ladder` end-to-end
          at Nt=2^12, SMF-28, L=2m, P=0.2W, max_iter=5. Must produce 2 step
          results with path_status in (:ok, :degraded). Slow (~10-30s on a
          laptop); NOT gated by burst VM.

Tests 6-7 for `attach_continuation_metadata!` are appended by Phase 30 Plan 01
Task 2 (numerical_trust.jl additive extension).

Run:
    julia -t auto --project=. test/test_continuation.jl
"""

using Test

const _ROOT = normpath(joinpath(@__DIR__, ".."))

# continuation.jl re-includes its dependencies (common, determinism,
# numerical_trust, raman_optimization, longfiber_setup). Include guards prevent
# duplicate definitions.
using MultiModeNoise
include(joinpath(_ROOT, "scripts", "continuation.jl"))

@testset "Phase 30 continuation" begin

    @testset "T1: detect_cost_discontinuity" begin
        @test detect_cost_discontinuity(-70.0, -65.0)     # +5 dB jump > 3
        @test !detect_cost_discontinuity(-70.0, -72.0)    # improvement
        @test !detect_cost_discontinuity(-70.0, -69.0)    # +1 dB < 3
        @test detect_cost_discontinuity(-70.0, -60.0; threshold_dB=5.0)
        @test !detect_cost_discontinuity(NaN, -70.0)      # no baseline → false
    end

    @testset "T2: detect_phase_jump norm-zero guard" begin
        @test !detect_phase_jump(zeros(128), zeros(128))
        @test !detect_phase_jump(zeros(128), randn(128))  # cold start guard
    end

    @testset "T3: detect_phase_jump fires when ratio > 10" begin
        phi_prev = fill(0.1, 128)                          # norm = 0.1·sqrt(128) ≈ 1.13
        phi_opt  = fill(2.0, 128)                          # diff norm = 1.9·sqrt(128) ≈ 21.5
        @test detect_phase_jump(phi_prev, phi_opt)
        # Same vector → no jump.
        @test !detect_phase_jump(phi_prev, phi_prev)
    end

    @testset "T4: detect_edge_growth" begin
        @test detect_edge_growth(1e-6, 2e-5)           # 20× growth
        @test !detect_edge_growth(1e-4, 1.5e-4)         # 1.5× growth
        @test detect_edge_growth(1e-6, 0.02)           # absolute ceiling
        @test detect_edge_growth(NaN, NaN)             # bad value → hard flag
    end

    @testset "T5: run_ladder smoke (lambda-ladder, easy regime)" begin
        # Easy regime: L=0.5 m, P=0.05 W on SMF-28. Five L-BFGS iterations are
        # more than enough to produce output with edge fraction < 1% (D8
        # threshold), so the smoke exercises the pipeline without hitting a
        # detector-driven hard halt that is unrelated to the code under test.
        schedule = ContinuationSchedule(
            continuation_id = "smoke_lambda",
            ladder_var = :lambda,
            values = [1e-2, 1e-3],
            base_config = Dict{String,Any}(
                "L_fiber"       => 0.5,
                "P_cont"        => 0.05,
                "Nt"            => 2^12,
                "time_window"   => 10.0,
                "fiber_preset"  => :SMF28,
                "β_order"       => 3,
            ),
            predictor = :trivial,
            corrector = :lbfgs_warm_restart,
            max_iter_per_step = 5,
            enable_hessian_probe = false,
        )
        results = run_ladder(schedule)
        @test length(results) == 2
        @test results[1].step_index == 1
        @test results[2].step_index == 2
        # First step is cold-start (prev_phi=nothing) regardless of flag,
        # so path_status should not be :broken without real pathology.
        @test results[1].path_status in (:ok, :degraded)
        @test results[2].path_status in (:ok, :degraded)
    end

end
