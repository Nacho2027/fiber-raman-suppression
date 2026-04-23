using Test

const _PHASE29_ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(_PHASE29_ROOT, "scripts", "roofline_model.jl"))

@testset "Phase 29 roofline model" begin

    @testset "arithmetic_intensity" begin
        @test arithmetic_intensity(1e9, 1e9) ≈ 1.0
        @test arithmetic_intensity(0, 1) == 0.0
        @test arithmetic_intensity(5.0, 2.0) ≈ 2.5
        @test_throws AssertionError arithmetic_intensity(1.0, 0.0)
        @test_throws AssertionError arithmetic_intensity(-1.0, 1.0)
    end

    @testset "roofline_bound" begin
        # Low AI -> memory-bound: 0.1 FLOP/B × 1e11 B/s = 1e10 FLOP/s << 1e12 peak
        r_mem = roofline_bound(0.1, 1e12, 1e11)
        @test r_mem.regime == "MEMORY_BOUND"
        @test r_mem.bound_flops_s ≈ 1e10
        # High AI -> compute-bound: 100 FLOP/B × 1e11 B/s = 1e13 FLOP/s > 1e12 peak
        r_comp = roofline_bound(100.0, 1e12, 1e11)
        @test r_comp.regime == "COMPUTE_BOUND"
        @test r_comp.bound_flops_s ≈ 1e12
        # Ridge point: AI = peak_flops / peak_bw = 10 FLOP/B
        r_ridge = roofline_bound(10.0, 1e12, 1e11)
        @test r_ridge.regime == "COMPUTE_BOUND"          # tie breaks to compute-bound
        @test r_ridge.bound_flops_s ≈ 1e12
        @test_throws AssertionError roofline_bound(-1.0, 1e12, 1e11)
        @test_throws AssertionError roofline_bound(1.0, 0.0, 1e11)
    end

    @testset "fit_amdahl recovers p from synthetic data" begin
        # Build T(n) = T1 · ((1-p) + p/n) for p_true = 0.9
        p_true = 0.9
        T1     = 10.0
        ns = [1, 2, 4, 8, 16, 22]
        ts = [T1 * ((1 - p_true) + p_true / n) for n in ns]
        f = fit_amdahl(ns, ts)
        @test isapprox(f.p, p_true; atol = 1e-10)
        @test isapprox(f.speedup_inf, 1.0 / (1.0 - p_true); atol = 1e-8)
        @test f.rmse < 1e-8
        # Bounds — all-parallel case
        f_all = fit_amdahl([1, 2, 4, 8], [8.0, 4.0, 2.0, 1.0])
        @test isapprox(f_all.p, 1.0; atol = 1e-10)
        @test !isfinite(f_all.speedup_inf)
    end

    @testset "fit_amdahl input validation" begin
        @test_throws AssertionError fit_amdahl([1, 2], [1.0])           # length mismatch
        @test_throws AssertionError fit_amdahl([0, 2], [1.0, 0.5])      # n < 1
        @test_throws AssertionError fit_amdahl([1, 2], [0.0, 1.0])      # t ≤ 0
    end

    @testset "fit_gustafson perfect-parallel input" begin
        # Perfect parallelism: T(n) = T(1)/n → true speedup = n at each n.
        # fit_gustafson's naive S = T1/ts·ns = n² here (overcounts, as documented
        # in the docstring — this is why Phase 29 reports Amdahl primarily).
        # What matters is that s clamps to 0 and the reported speedup_n is
        # the maximum of the S column, which is n_max² = 16 for [1,2,4].
        g = fit_gustafson([1, 2, 4], [1.0, 0.5, 0.25])
        @test g.s == 0.0
        @test g.speedup_n ≈ 16.0
    end

    @testset "kernel_regime_verdict" begin
        @test kernel_regime_verdict(0.5, "UNKNOWN") == "MEMORY_BOUND"
        @test kernel_regime_verdict(50.0, "UNKNOWN") == "COMPUTE_BOUND"
        # Mid-range — trust the roofline caller
        @test kernel_regime_verdict(5.0, "MEMORY_BOUND") == "MEMORY_BOUND"
        @test kernel_regime_verdict(5.0, "COMPUTE_BOUND") == "COMPUTE_BOUND"
        @test_throws ArgumentError kernel_regime_verdict(1.0, "GARBAGE")
        @test_throws AssertionError kernel_regime_verdict(-0.1, "UNKNOWN")
    end

    @testset "assemble_roofline_memo has required headings" begin
        stub = Dict(
            "timestamp"          => "2026-04-21T00:00:00",
            "executive_verdict"  => "TEST-VERDICT",
            "kernels_md"         => "KT-ROW",
            "amdahl_md"          => "AM-ROW",
            "roofline_md"        => "RF-ROW",
            "recommendations_md" => "RC-ROW",
        )
        hw = Dict(
            "hostname"      => "testhost",
            "cpu_info"      => "TestCPU",
            "julia_threads" => 1,
            "git_commit"    => "deadbeef",
        )
        md = assemble_roofline_memo(stub; hw_profile = hw)
        for heading in ["# Phase 29 Report", "## Executive Verdict",
                        "## Kernel Timings", "## Amdahl Fits",
                        "## Roofline Regimes", "## Recommendations"]
            @test occursin(heading, md)
        end
        # Substitutions present
        for marker in ["TEST-VERDICT", "KT-ROW", "AM-ROW", "RF-ROW",
                       "RC-ROW", "testhost", "TestCPU", "deadbeef"]
            @test occursin(marker, md)
        end
    end

end
