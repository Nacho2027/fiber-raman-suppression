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

    @testset "T6: attach_continuation_metadata! happy path + merge" begin
        det_status = (applied=true, fftw_threads=1, blas_threads=1,
                      version="1.0.0", phase="15-01")
        report = build_numerical_trust_report(
            det_status=det_status,
            edge_input_frac=0.0, edge_output_frac=0.0,
            energy_drift=0.0,
            log_cost=true, λ_gdd=1e-4, λ_boundary=1.0)
        attach_continuation_metadata!(report, Dict{String,Any}(
            "continuation_id" => "smoke",
            "ladder_var"      => "lambda",
            "step_index"      => 1,
            "ladder_value"    => 1e-2,
            "predictor"       => "trivial",
            "corrector"       => "lbfgs_warm_restart",
            "path_status"     => "ok",
            "is_cold_start_baseline" => false,
        ))
        @test report["continuation"]["continuation_id"] == "smoke"
        @test report["schema_version"] == "28.0"
        # Merge semantics: second call accumulates without clobbering prior keys.
        attach_continuation_metadata!(report, Dict{String,Any}(
            "continuation_id" => "smoke",
            "ladder_var"      => "lambda",
            "step_index"      => 1,
            "path_status"     => "ok",
            "detectors"       => Dict{String,Any}("corrector_iters" => 7),
        ))
        @test report["continuation"]["detectors"]["corrector_iters"] == 7
        @test report["continuation"]["predictor"] == "trivial"
    end

    @testset "T7: attach_continuation_metadata! rejects bad enums" begin
        det_status = (applied=true, fftw_threads=1, blas_threads=1,
                      version="1.0.0", phase="15-01")
        report = build_numerical_trust_report(
            det_status=det_status,
            edge_input_frac=0.0, edge_output_frac=0.0,
            energy_drift=0.0,
            log_cost=true, λ_gdd=1e-4, λ_boundary=1.0)
        @test_throws ArgumentError attach_continuation_metadata!(report, Dict{String,Any}(
            "continuation_id" => "x",
            "ladder_var"      => "bogus",
            "step_index"      => 1,
            "path_status"     => "ok",
        ))
        @test_throws ArgumentError attach_continuation_metadata!(report, Dict{String,Any}(
            "continuation_id" => "x",
            "ladder_var"      => "L",
            "step_index"      => 1,
            "path_status"     => "not_a_status",
        ))
        # Missing required key `step_index` → ArgumentError
        @test_throws ArgumentError attach_continuation_metadata!(report, Dict{String,Any}(
            "continuation_id" => "x",
            "ladder_var"      => "L",
            "path_status"     => "ok",
        ))
    end

    @testset "T8: write_numerical_trust_report render hook" begin
        det_status = (applied=true, fftw_threads=1, blas_threads=1,
                      version="1.0.0", phase="15-01")
        # Baseline: plain report (no continuation) must render without a
        # `## Continuation` block.
        report_plain = build_numerical_trust_report(
            det_status=det_status,
            edge_input_frac=0.0, edge_output_frac=0.0,
            energy_drift=0.0,
            log_cost=true, λ_gdd=1e-4, λ_boundary=1.0)
        mktempdir() do d
            path_plain = joinpath(d, "plain_trust.md")
            write_numerical_trust_report(path_plain, report_plain)
            plain_text = read(path_plain, String)
            @test !occursin("## Continuation", plain_text)
            # Phase 30 report: same base, with metadata attached.
            report_cont = build_numerical_trust_report(
                det_status=det_status,
                edge_input_frac=0.0, edge_output_frac=0.0,
                energy_drift=0.0,
                log_cost=true, λ_gdd=1e-4, λ_boundary=1.0)
            attach_continuation_metadata!(report_cont, Dict{String,Any}(
                "continuation_id" => "render_test",
                "ladder_var"      => "L",
                "step_index"      => 2,
                "ladder_value"    => 10.0,
                "predictor"       => "trivial",
                "corrector"       => "lbfgs_warm_restart",
                "path_status"     => "ok",
                "is_cold_start_baseline" => false,
            ))
            path_cont = joinpath(d, "cont_trust.md")
            write_numerical_trust_report(path_cont, report_cont)
            cont_text = read(path_cont, String)
            @test occursin("## Continuation", cont_text)
            @test occursin("render_test", cont_text)
        end
    end

end
