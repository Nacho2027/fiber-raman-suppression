using Test
using Printf
using JLD2

const _ROOT = normpath(joinpath(@__DIR__, ".."))

using MultiModeNoise
include(joinpath(_ROOT, "scripts", "lib", "common.jl"))
include(joinpath(_ROOT, "scripts", "lib", "determinism.jl"))
include(joinpath(_ROOT, "scripts", "research", "analysis", "numerical_trust.jl"))
include(joinpath(_ROOT, "scripts", "lib", "raman_optimization.jl"))

@testset "Phase 28 trust report" begin
    @testset "utility verdicts are stable" begin
        det_status = (
            applied = true,
            fftw_threads = 1,
            blas_threads = 1,
            version = "1.0.0",
            phase = "15-01",
        )
        grad = (max_rel_err = 1e-3, mean_rel_err = 5e-4, n_checks = 3, epsilon = 1e-5)
        report = build_numerical_trust_report(
            det_status=det_status,
            edge_input_frac=1e-5,
            edge_output_frac=2e-5,
            energy_drift=5e-5,
            gradient_validation=grad,
            log_cost=true,
            λ_gdd=1e-4,
            λ_boundary=1.0)

        @test report["overall_verdict"] == "PASS"
        @test report["cost_surface"]["regularizers_chained_into_surface"] == true
        @test report["cost_surface"]["surface"] == "10*log10(physics + λ_gdd*R_gdd + λ_boundary*R_boundary)"
        @test report["cost_surface"]["scale"] == "dB"
        @test report["boundary"]["verdict"] == "PASS"
    end

    @testset "run_optimization writes trust report artifacts" begin
        mktempdir() do dir
            save_prefix = joinpath(dir, "trust_case")
            run_optimization(
                L_fiber=0.05, P_cont=0.01, max_iter=1,
                Nt=2^7, β_order=2, time_window=5.0,
                gamma_user=0.0013, betas_user=[-2.6e-26],
                fiber_name="TestFiber",
                save_prefix=save_prefix,
                do_plots=false,
                validate=true,
            )

            trust_md = save_prefix * "_trust.md"
            result = JLD2.load(save_prefix * "_result.jld2")

            @test isfile(trust_md)
            @test haskey(result, "trust_report")
            @test result["trust_report"]["cost_surface"]["regularizers_chained_into_surface"] == true
            @test haskey(result["trust_report"]["cost_surface"], "pre_log_linear_surface")
            @test haskey(result["trust_report"], "overall_verdict")
        end
    end
end
