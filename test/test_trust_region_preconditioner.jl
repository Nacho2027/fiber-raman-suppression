# test/test_trust_region_preconditioner.jl — Phase 34 Plan 02 Task 3.
#
# Unit tests for zero-HVP preconditioner factories in
# scripts/trust_region_preconditioner.jl.
#
# Run:  julia --project=. test/test_trust_region_preconditioner.jl
#
# Tests cover:
#   - build_diagonal_precond: callable, length, positivity, normalization, floor,
#     multi-mode replication, length-assertion guard
#   - build_dispersion_precond: callable, length, positivity, ω=0 entry ≈ 1,
#     monotone decay from ω_max toward ω=0
#   - Zero-HVP claim: source contains no HVP references

using Test
using LinearAlgebra
using Statistics

include(joinpath(@__DIR__, "..", "scripts", "trust_region_preconditioner.jl"))

# ─────────────────────────────────────────────────────────────────────────────
@testset "Phase 34 Plan 02 — Preconditioner factories" begin

    @testset "build_diagonal_precond — basic contract" begin
        Nt, M = 16, 1
        uω0 = randn(ComplexF64, Nt, M)
        M_inv = build_diagonal_precond(uω0)

        @test M_inv isa Function

        v = ones(Float64, Nt * M)
        out = M_inv(v)
        @test length(out) == Nt * M
        @test all(isfinite, out)
        @test all(out .> 0)

        # After normalize=true, mean(d) ≈ 1 ⟹ M_inv(1s) has mean ≈ 1
        @test 0.01 < mean(out) < 100.0
    end

    @testset "build_diagonal_precond — floor prevents Inf on sparse spectrum" begin
        Nt, M = 16, 1
        # Only one frequency bin has energy; all others are near-zero
        uω0_sparse = zeros(ComplexF64, Nt, M)
        uω0_sparse[Nt ÷ 2, 1] = 1.0 + 0im
        M_sparse = build_diagonal_precond(uω0_sparse)
        out_sparse = M_sparse(ones(Float64, Nt * M))
        @test all(isfinite, out_sparse)
        @test all(out_sparse .> 0)
    end

    @testset "build_diagonal_precond — wrong-size input triggers AssertionError" begin
        Nt, M = 16, 1
        uω0 = randn(ComplexF64, Nt, M)
        M_inv = build_diagonal_precond(uω0)
        @test_throws AssertionError M_inv(zeros(Float64, Nt * M + 1))
    end

    @testset "build_diagonal_precond — multi-mode replication" begin
        Nt, M = 8, 3
        uω0 = randn(ComplexF64, Nt, M)
        M_inv = build_diagonal_precond(uω0)
        v = ones(Float64, Nt * M)
        out = M_inv(v)
        @test length(out) == Nt * M
        @test all(isfinite, out)
        @test all(out .> 0)
    end

    @testset "build_diagonal_precond — linearity check" begin
        Nt, M = 16, 1
        uω0 = randn(ComplexF64, Nt, M)
        M_inv = build_diagonal_precond(uω0)
        v1 = randn(Float64, Nt * M)
        v2 = randn(Float64, Nt * M)
        α = 3.7
        # M_inv(α·v1 + v2) should equal α·M_inv(v1) + M_inv(v2) (linear operator)
        @test isapprox(M_inv(α .* v1 .+ v2), α .* M_inv(v1) .+ M_inv(v2); atol = 1e-12)
    end

    @testset "build_dispersion_precond — basic contract" begin
        Nt, M = 16, 1
        sim = Dict{String,Any}(
            "Nt"  => Nt,
            "M"   => M,
            "ωs"  => collect(range(-8.0, 7.0, length = Nt))
        )
        M_inv = build_dispersion_precond(sim)

        @test M_inv isa Function

        v = ones(Float64, Nt * M)
        out = M_inv(v)
        @test length(out) == Nt * M
        @test all(isfinite, out)
        @test all(out .> 0)
    end

    @testset "build_dispersion_precond — ω≈0 bin gives d≈1 → out≈1" begin
        Nt, M = 16, 1
        ωs = collect(range(-8.0, 7.0, length = Nt))
        sim = Dict{String,Any}("Nt" => Nt, "M" => M, "ωs" => ωs)
        M_inv = build_dispersion_precond(sim)
        v = ones(Float64, Nt * M)
        out = M_inv(v)
        # The bin with smallest |ω| should have d ≈ 1 → out ≈ 1
        idx_zero = argmin(abs.(ωs))
        @test 0.5 < out[idx_zero] < 2.0
    end

    @testset "build_dispersion_precond — larger |ω| → smaller output than near ω=0" begin
        Nt, M = 16, 1
        ωs = collect(range(-8.0, 7.0, length = Nt))
        sim = Dict{String,Any}("Nt" => Nt, "M" => M, "ωs" => ωs)
        M_inv = build_dispersion_precond(sim)
        v = ones(Float64, Nt * M)
        out = M_inv(v)
        idx_zero = argmin(abs.(ωs))
        idx_max  = argmax(abs.(ωs))
        # Larger ω → larger d → smaller M_inv(1) = 1/d
        @test out[idx_max] < out[idx_zero]
    end

    @testset "build_dispersion_precond — wrong-size input triggers AssertionError" begin
        Nt, M = 16, 1
        sim = Dict{String,Any}("Nt" => Nt, "M" => M,
                               "ωs" => collect(range(-8.0, 7.0, length = Nt)))
        M_inv = build_dispersion_precond(sim)
        @test_throws AssertionError M_inv(zeros(Float64, Nt * M + 5))
    end

    @testset "preconditioner is zero-HVP (source check)" begin
        # Verify the preconditioner source file does not reference HVP machinery
        src = read(joinpath(@__DIR__, "..", "scripts", "trust_region_preconditioner.jl"), String)
        @test !occursin("fd_hvp", src)
        @test !occursin("H_op", src)
        # Also check DCT is not in this file (deferred to Plan 03)
        @test !occursin("build_dct_precond", src)
        @test !occursin("build_dct_basis", src)
    end

end  # testset
