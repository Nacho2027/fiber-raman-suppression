# ═══════════════════════════════════════════════════════════════════════════════
# Phase 16 Plan 01 — Cost-audit integration on config A (smoke)
# ═══════════════════════════════════════════════════════════════════════════════
# Run:   julia --project=. test/test_cost_audit_integration_A.jl
#
# For each of the 4 cost variants (:linear, :log_dB, :sharp, :curvature) drive
# `run_one(variant, :A; max_iter=10, Nt=1024, save=false, strict_nt=false)` and
# assert the returned `J_final` is finite and non-NaN.
#
# MUST run on fiber-raman-burst (CLAUDE.md Rule 1, strict — run_one calls the
# full forward+adjoint+Hessian solver).
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using Random
using LinearAlgebra
using Printf
using FFTW
using Statistics

FFTW.set_num_threads(1)
BLAS.set_num_threads(1)

const _PHASE16_WISDOM = joinpath(@__DIR__, "..", "results", "raman", "phase14", "fftw_wisdom.txt")
isfile(_PHASE16_WISDOM) && try; FFTW.import_wisdom(_PHASE16_WISDOM); catch; end

include(joinpath(@__DIR__, "..", "scripts", "common.jl"))
include(joinpath(@__DIR__, "..", "scripts", "raman_optimization.jl"))

const _CA_DRIVER_PATH = joinpath(@__DIR__, "..", "scripts", "cost_audit_driver.jl")
if isfile(_CA_DRIVER_PATH)
    include(_CA_DRIVER_PATH)
    const _CA_DRIVER_READY = true
else
    const _CA_DRIVER_READY = false
end

# run_one is exported by Task 3:
#   run_one(variant::Symbol, config_tag::Symbol;
#           max_iter, Nt, save::Bool=false, strict_nt::Bool=true)
# I-7: strict_nt=false turns Nt auto-grow from ERROR into @warn so the small
# test grid (Nt=1024) can still exercise the driver path.

@testset "Phase 16 cost audit — integration on config A (Nt=1024, max_iter=10)" begin
    @testset "variants_run_config_A" begin
        @testset "variant=linear" begin
            if !_CA_DRIVER_READY
                @test_skip "cost_audit_driver.jl not yet present (Task 3)"
            else
                result = run_one(:linear, :A;
                                 max_iter=10, Nt=1024, save=false, strict_nt=false)
                @test isfinite(result.J_final) && !isnan(result.J_final)
                @test result.iterations >= 1
            end
        end

        @testset "variant=log_dB" begin
            if !_CA_DRIVER_READY
                @test_skip "cost_audit_driver.jl not yet present (Task 3)"
            else
                result = run_one(:log_dB, :A;
                                 max_iter=10, Nt=1024, save=false, strict_nt=false)
                @test isfinite(result.J_final) && !isnan(result.J_final)
                @test result.iterations >= 1
            end
        end

        @testset "variant=sharp" begin
            if !_CA_DRIVER_READY
                @test_skip "cost_audit_driver.jl not yet present (Task 3)"
            else
                result = run_one(:sharp, :A;
                                 max_iter=10, Nt=1024, save=false, strict_nt=false)
                @test isfinite(result.J_final) && !isnan(result.J_final)
                @test result.iterations >= 1
            end
        end

        @testset "variant=curvature" begin
            if !_CA_DRIVER_READY
                @test_skip "cost_audit_driver.jl not yet present (Task 3)"
            else
                result = run_one(:curvature, :A;
                                 max_iter=10, Nt=1024, save=false, strict_nt=false)
                @test isfinite(result.J_final) && !isnan(result.J_final)
                @test result.iterations >= 1
            end
        end
    end
end
