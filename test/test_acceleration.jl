"""
Unit + regression tests for scripts/acceleration.jl (Phase 32 Plan 01).

Task 1 — Tests 1–17: primitives (Aitken, polynomial_predict, MPE, RRE,
safeguard, gauge projection, stop-rule classifier, constants, include-guard).

Task 1 — Tests 18–19: additive numerical_trust schema contract.

Task 2 — Tests 20–26: `attach_acceleration_metadata!` + `## Acceleration`
render hook (schema must stay "28.0").

Run:
    julia -t auto --project=. test/test_acceleration.jl
"""

using Test, LinearAlgebra, Random, Statistics, Printf

const _ROOT = normpath(joinpath(@__DIR__, ".."))

using MultiModeNoise
include(joinpath(_ROOT, "scripts", "acceleration.jl"))
include(joinpath(_ROOT, "scripts", "numerical_trust.jl"))

@testset "Phase 32 acceleration primitives" begin

    @testset "T1: ACCELERATION_VERSION literal" begin
        @test ACCELERATION_VERSION == "32.0"
        @test ACCELERATION_VERSION isa String
    end

    @testset "T2: aitken recovers geometric-sequence limit" begin
        # x_k = 2 - (1/2)^k starting k=0 : [1, 1.5, 1.75, 1.875, 1.9375]
        seq = [1.0, 1.5, 1.75, 1.875, 1.9375]
        a∞ = aitken(seq)
        @test isfinite(a∞)
        @test abs(a∞ - 2.0) < 1e-10
    end

    @testset "T3: aitken denominator-zero branch returns NaN" begin
        @test isnan(aitken([1.0, 1.0, 1.0]))
        @test isnan(aitken([2.0, 2.0, 2.0]))
    end

    @testset "T4: polynomial_predict identity fallback (k=1)" begin
        result = polynomial_predict(
            s_history = [1.0],
            phi_history = [[0.1, 0.2, 0.3]],
            s_target = 2.0,
            max_degree = 2,
        )
        @test result ≈ [0.1, 0.2, 0.3]
    end

    @testset "T5: polynomial_predict linear extrapolation exact" begin
        v = [0.1, 0.2, 0.3]
        s_history = [1.0, 2.0]
        phi_history = [s_history[1] .* v, s_history[2] .* v]
        result = polynomial_predict(
            s_history = s_history,
            phi_history = phi_history,
            s_target = 3.0,
            max_degree = 2,
        )
        @test all(abs.(result .- 3.0 .* v) .< 1e-10)
    end

    @testset "T6: polynomial_predict quadratic extrapolation exact" begin
        v = [0.4, -0.1, 0.7]
        s_history = [1.0, 2.0, 3.0]
        phi_history = [(s^2) .* v for s in s_history]
        result = polynomial_predict(
            s_history = s_history,
            phi_history = phi_history,
            s_target = 4.0,
            max_degree = 2,
        )
        @test all(abs.(result .- 16.0 .* v) .< 1e-10)
    end

    @testset "T7: polynomial_predict enforces D = min(k-1, max_degree)" begin
        # 4 past points at max_degree=2 → Vandermonde should be 4×3 (D=2), not 4×4.
        s_history = [1.0, 2.0, 3.0, 4.0]
        V = _vandermonde(s_history, 2)
        @test size(V) == (4, 3)
        # Sanity: internal _vandermonde with D=3 would be 4×4.
        V3 = _vandermonde(s_history, 3)
        @test size(V3) == (4, 4)
        # End-to-end with a quadratic signal — D=2 should still recover exactly.
        v = [0.2, 0.3]
        phi_history = [(s^2) .* v for s in s_history]
        result = polynomial_predict(
            s_history = s_history,
            phi_history = phi_history,
            s_target = 5.0,
            max_degree = 2,
        )
        @test all(abs.(result .- 25.0 .* v) .< 1e-8)
    end

    @testset "T8: mpe_combine beats last-iterate on linear fixed point" begin
        # x_{k+1} = 0.5 * x_k + 0.5 * x*
        x_star = [1.0, -2.0, 0.5, 3.0]
        x1 = [10.0, 10.0, 10.0, 10.0]
        x2 = 0.5 .* x1 .+ 0.5 .* x_star
        x3 = 0.5 .* x2 .+ 0.5 .* x_star
        out = mpe_combine([x1, x2, x3])
        @test norm(out.combined .- x_star) < 0.5 * norm(x3 .- x_star)
    end

    @testset "T9: rre_combine on linear fixed point ≤ MPE" begin
        x_star = [1.0, -2.0, 0.5, 3.0]
        x1 = [10.0, 10.0, 10.0, 10.0]
        x2 = 0.5 .* x1 .+ 0.5 .* x_star
        x3 = 0.5 .* x2 .+ 0.5 .* x_star
        mpe_out = mpe_combine([x1, x2, x3])
        rre_out = rre_combine([x1, x2, x3])
        @test norm(rre_out.combined .- x_star) ≤ norm(mpe_out.combined .- x_star) + 1e-8
    end

    @testset "T10: safeguard_gamma threshold behavior" begin
        ok, reason = safeguard_gamma([0.5, 0.5])
        @test ok == true
        @test reason == "ok"
        bad, why = safeguard_gamma([2000.0, -1.0])
        @test bad == false
        @test occursin("max|γ| exceeded", why)
        nf, whynf = safeguard_gamma([NaN, 0.5])
        @test nf == false
        @test occursin("non-finite", whynf)
    end

    @testset "T11: project_gauge_phi zeroes mean and band-slope" begin
        Nt = 64
        ω = collect(range(-3.0, 3.0; length = Nt))
        band_mask = (ω .> -1.5) .& (ω .< 1.5)
        phi = 3.0 .+ 2.0 .* ω
        out = project_gauge_phi(phi, ω, band_mask)
        inds = findall(band_mask)
        @test abs(mean(view(out, inds))) < 1e-10
        ωb = ω[inds]
        ωb_c = ωb .- mean(ωb)
        yb = view(out, inds) .- mean(view(out, inds))
        slope = dot(ωb_c, yb) / dot(ωb_c, ωb_c)
        @test abs(slope) < 1e-10
    end

    @testset "T12: classify_acceleration_verdict WORTH_IT" begin
        v = classify_acceleration_verdict(Dict(
            "savings_frac" => 0.25,
            "worst_verdict_delta" => 0,
            "db_delta" => 0.3,
            "new_hard_halt" => false,
        ))
        @test v == "WORTH_IT"
    end

    @testset "T13: classify fails savings bar" begin
        v = classify_acceleration_verdict(Dict(
            "savings_frac" => 0.10,
            "worst_verdict_delta" => 0,
            "db_delta" => 0.3,
            "new_hard_halt" => false,
        ))
        @test v == "NOT_WORTH_IT"
    end

    @testset "T14: classify hard halt dominates" begin
        v = classify_acceleration_verdict(Dict(
            "savings_frac" => 0.50,
            "worst_verdict_delta" => 0,
            "db_delta" => 0.0,
            "new_hard_halt" => true,
        ))
        @test v == "NOT_WORTH_IT"
    end

    @testset "T15: classify INCONCLUSIVE on endpoint loss" begin
        v = classify_acceleration_verdict(Dict(
            "savings_frac" => 0.20,
            "worst_verdict_delta" => 0,
            "db_delta" => 1.5,
            "new_hard_halt" => false,
        ))
        @test v == "INCONCLUSIVE"
    end

    @testset "T16: named constants locked" begin
        @test ACCEL_STOP_SAVINGS_FRAC == 0.15
        @test ACCEL_STOP_DB_REGRESSION == 1.0
        @test ACCEL_SAFEGUARD_GAMMA_MAX == 1e3
    end

    @testset "T17: include guard is idempotent" begin
        # Second include must not throw (const redefinition would)
        @test_nowarn include(joinpath(_ROOT, "scripts", "acceleration.jl"))
        @test ACCELERATION_VERSION == "32.0"
    end
end

@testset "Phase 32 additive trust-schema contract" begin

    function _fresh_report()
        det_status = (
            applied = true,
            fftw_threads = 1,
            blas_threads = 1,
            version = "1.0.0",
            phase = "32-01",
        )
        return build_numerical_trust_report(
            det_status = det_status,
            edge_input_frac = 1e-5,
            edge_output_frac = 2e-5,
            energy_drift = 5e-5,
            gradient_validation = nothing,
            log_cost = true,
            λ_gdd = 1e-4,
            λ_boundary = 1.0,
        )
    end

    @testset "T18: schema version unchanged after attach" begin
        report = _fresh_report()
        meta = Dict{String,Any}(
            "accelerator" => "polynomial_d2",
            "prediction_norm" => 0.3,
            "corrector_iters_saved" => 4,
            "j_opt_db_delta" => 0.1,
            "coefficient_max" => 1.2,
        )
        attach_acceleration_metadata!(report, meta)
        @test report["schema_version"] == "28.0"
    end

    @testset "T19: acceleration sub-dict carries supplied keys" begin
        report = _fresh_report()
        meta = Dict{String,Any}(
            "accelerator" => "mpe",
            "prediction_norm" => 0.7,
            "corrector_iters_saved" => 3,
            "j_opt_db_delta" => 0.2,
            "coefficient_max" => 5.5,
        )
        attach_acceleration_metadata!(report, meta)
        @test report["acceleration"] isa Dict{String,Any}
        for key in ("accelerator", "prediction_norm", "corrector_iters_saved",
                    "j_opt_db_delta", "coefficient_max")
            @test haskey(report["acceleration"], key)
        end
        @test report["acceleration"]["accelerator"] == "mpe"
    end

    @testset "T20: missing required key raises ArgumentError" begin
        report = _fresh_report()
        meta = Dict{String,Any}("prediction_norm" => 0.5)
        err = try
            attach_acceleration_metadata!(report, meta); nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("missing required key", err.msg)
    end

    @testset "T21: invalid accelerator enum raises" begin
        report = _fresh_report()
        meta = Dict{String,Any}("accelerator" => "bogus")
        err = try
            attach_acceleration_metadata!(report, meta); nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("bogus", err.msg)
        # Accepted enum members must appear in message
        @test occursin("polynomial", err.msg) || occursin("mpe", err.msg)
    end

    @testset "T22: merge semantics copy keys bit-identically" begin
        report = _fresh_report()
        meta = Dict{String,Any}(
            "accelerator" => "polynomial_d1",
            "prediction_norm" => 0.123456789,
            "corrector_iters_saved" => 7,
            "j_opt_db_delta" => -0.05,
            "coefficient_max" => 2.5,
            "verdict" => "WORTH_IT",
        )
        attach_acceleration_metadata!(report, meta)
        for (k, v) in meta
            @test report["acceleration"][k] == v
        end
    end

    @testset "T23: schema grep-invariant after attach" begin
        report = _fresh_report()
        attach_acceleration_metadata!(report, Dict{String,Any}(
            "accelerator" => "rre",
        ))
        @test report["schema_version"] == "28.0"
        # grep-style invariant on the source file
        src = read(joinpath(_ROOT, "scripts", "numerical_trust.jl"), String)
        # Count occurrences of the literal constant definition line
        matches = collect(eachmatch(
            r"NUMERICAL_TRUST_SCHEMA_VERSION = \"28.0\"", src))
        @test length(matches) == 1
    end

    @testset "T24: multiple attach calls merge with later winning" begin
        report = _fresh_report()
        attach_acceleration_metadata!(report, Dict{String,Any}(
            "accelerator" => "polynomial_d2",
            "prediction_norm" => 0.4,
            "corrector_iters_saved" => 2,
        ))
        attach_acceleration_metadata!(report, Dict{String,Any}(
            "accelerator" => "polynomial_d2",
            "prediction_norm" => 0.9,   # updated
            "j_opt_db_delta" => 0.05,   # new
        ))
        @test report["acceleration"]["prediction_norm"] == 0.9
        @test report["acceleration"]["corrector_iters_saved"] == 2
        @test report["acceleration"]["j_opt_db_delta"] == 0.05
    end

    @testset "T25: render hook present iff acceleration set" begin
        tmp1 = tempname() * ".md"
        tmp2 = tempname() * ".md"
        r_without = _fresh_report()
        write_numerical_trust_report(tmp1, r_without)
        txt_without = read(tmp1, String)
        @test !occursin("## Acceleration", txt_without)

        r_with = _fresh_report()
        attach_acceleration_metadata!(r_with, Dict{String,Any}(
            "accelerator" => "mpe",
            "prediction_norm" => 0.6,
            "corrector_iters_saved" => 3,
            "j_opt_db_delta" => 0.05,
            "coefficient_max" => 2.0,
            "safeguard_passed" => true,
            "safeguard_reason" => "ok",
            "verdict" => "WORTH_IT",
        ))
        write_numerical_trust_report(tmp2, r_with)
        txt_with = read(tmp2, String)
        @test occursin("## Acceleration", txt_with)
        @test occursin("mpe", txt_with)
        @test occursin("WORTH_IT", txt_with)
        rm(tmp1; force = true)
        rm(tmp2; force = true)
    end

    @testset "T26: continuation and acceleration render in stable order" begin
        tmp = tempname() * ".md"
        report = _fresh_report()
        attach_continuation_metadata!(report, Dict{String,Any}(
            "continuation_id" => "p32_test_L",
            "ladder_var" => "L",
            "step_index" => 1,
            "path_status" => "ok",
            "ladder_value" => 2.0,
            "predictor" => "trivial",
            "corrector" => "lbfgs_warm_restart",
            "is_cold_start_baseline" => false,
        ))
        attach_acceleration_metadata!(report, Dict{String,Any}(
            "accelerator" => "polynomial_d2",
            "verdict" => "WORTH_IT",
        ))
        write_numerical_trust_report(tmp, report)
        txt = read(tmp, String)
        cont_idx = findfirst("## Continuation", txt)
        accel_idx = findfirst("## Acceleration", txt)
        @test cont_idx !== nothing
        @test accel_idx !== nothing
        @test first(cont_idx) < first(accel_idx)
        rm(tmp; force = true)
    end
end
