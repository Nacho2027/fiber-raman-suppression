# ═══════════════════════════════════════════════════════════════════════════════
# Phase 16 Plan 01 — Cost-audit analyzer contracts
# ═══════════════════════════════════════════════════════════════════════════════
# Run:   julia --project=. test/test_cost_audit_analyzer.jl
#
# Contract-level gates for the analyzer output (runs against Wave-2 outputs):
#   - csv_schema        — per-config summary.csv has exact 17 columns (D-16).
#   - figures_exist     — 4 PNGs each > 20 KB (D-18).
#   - nyquist_complete  — summary_all.csv rows have no NaN except dnf=true.
#
# When the batch has not yet run, testsets skip gracefully.
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using FFTW
using LinearAlgebra

FFTW.set_num_threads(1)
BLAS.set_num_threads(1)

const _PHASE16_WISDOM = joinpath(@__DIR__, "..", "results", "raman", "phase14", "fftw_wisdom.txt")
isfile(_PHASE16_WISDOM) && try; FFTW.import_wisdom(_PHASE16_WISDOM); catch; end

include(joinpath(@__DIR__, "..", "scripts", "common.jl"))
include(joinpath(@__DIR__, "..", "scripts", "raman_optimization.jl"))

const _SUMMARY_A   = joinpath(@__DIR__, "..", "results", "cost_audit", "A", "summary.csv")
const _SUMMARY_ALL = joinpath(@__DIR__, "..", "results", "cost_audit", "summary_all.csv")
const _FIG_PATHS   = [joinpath(@__DIR__, "..", "results", "cost_audit", "fig$(i)_$(name).png")
    for (i, name) in [(1, "convergence"), (2, "robustness"),
                       (3, "eigenspectra"), (4, "winner_heatmap")]]

@testset "Phase 16 cost audit — analyzer contracts (runs against Wave 2 outputs)" begin
    @testset "csv_schema (per-config summary has exact 17 columns)" begin
        if !isfile(_SUMMARY_A)
            @test_skip "Batch not yet run (Wave 2, plan 16-02)"
        else
            using CSV, DataFrames
            df = CSV.read(_SUMMARY_A, DataFrame)
            expected = ["variant", "final_J_linear", "final_J_dB", "delta_J_dB",
                        "iterations", "iter_to_90pct", "wall_s", "lambda_max", "cond_proxy",
                        "robust_sigma_0.01_mean_dB", "robust_sigma_0.01_max_dB",
                        "robust_sigma_0.05_mean_dB", "robust_sigma_0.05_max_dB",
                        "robust_sigma_0.1_mean_dB",  "robust_sigma_0.1_max_dB",
                        "robust_sigma_0.2_mean_dB",  "robust_sigma_0.2_max_dB"]
            @test Set(names(df)) == Set(expected)
            @test size(df, 1) == 4  # one row per variant
        end
    end

    @testset "figures_exist (4 PNGs > 20 KB each)" begin
        for p in _FIG_PATHS
            if !isfile(p)
                @test_skip "Figure $p not yet produced (Wave 2)"
            else
                @test filesize(p) > 20_000
            end
        end
    end

    @testset "nyquist_complete (every variant has all metrics populated)" begin
        if !isfile(_SUMMARY_ALL)
            @test_skip "summary_all.csv not yet produced (Wave 2)"
        else
            using CSV, DataFrames
            df = CSV.read(_SUMMARY_ALL, DataFrame)
            non_dnf = hasproperty(df, :dnf) ? filter(:dnf => x -> x != true, df) : df
            @test all(x -> !isnan(x), non_dnf.value)
        end
    end
end
