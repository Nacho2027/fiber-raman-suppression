"""
Pure-unit tests for `multivar_optimization.jl` helpers that do NOT touch
the fiber simulator (so they can run on claude-code-host — no burst VM
needed, no compute-discipline Rule 1 violation).

Covers:
  - sanitize_variables (incl. mode_coeffs stripping per Decision D4)
  - mv_block_offsets layout
  - mv_pack / mv_unpack round-trip
  - build_scaling_vector correctness

    julia --project=. scripts/test_multivar_unit.jl
"""

ENV["MPLBACKEND"] = "Agg"
using Test
using LinearAlgebra

include(joinpath(@__DIR__, "..", "..", "lib", "multivar_optimization.jl"))

@testset "sanitize_variables" begin
    @test sanitize_variables((:phase,)) == (:phase,)
    @test sanitize_variables((:amplitude,)) == (:amplitude,)
    @test sanitize_variables((:phase, :amplitude)) == (:phase, :amplitude)
    # duplicates dropped
    @test sanitize_variables((:phase, :phase, :amplitude)) == (:phase, :amplitude)
    # mode_coeffs stripped with @warn (Decision D4)
    @test sanitize_variables((:phase, :mode_coeffs, :amplitude)) == (:phase, :amplitude)
    # mode_coeffs alone → error (no variables left)
    @test_throws ArgumentError sanitize_variables((:mode_coeffs,))
    # invalid name
    @test_throws ArgumentError sanitize_variables((:phase, :bogus))
    # empty
    @test_throws ArgumentError sanitize_variables(())
end

@testset "mv_block_offsets / mv_pack / mv_unpack" begin
    Nt = 64; M = 2
    E_ref = 1.5

    for vars in [(:phase,), (:amplitude,), (:phase, :amplitude), (:phase, :amplitude, :energy), (:energy,)]
        cfg = MVConfig(variables=vars)
        off = mv_block_offsets(cfg, Nt, M)
        expected_len = 0
        for v in vars
            expected_len += v === :energy ? 1 : Nt * M
        end
        @test off.n_total == expected_len

        φ = randn(Nt, M)
        A = 1.0 .+ 0.1 .* randn(Nt, M)
        E = E_ref * 1.2
        x = mv_pack(φ, A, E, cfg, Nt, M)
        @test length(x) == expected_len
        parts = mv_unpack(x, cfg, Nt, M, E_ref)
        # Enabled blocks should match exactly
        if :phase in vars
            @test parts.φ == φ
        else
            @test parts.φ == zeros(Nt, M)
        end
        if :amplitude in vars
            @test parts.A == A
        else
            @test parts.A == ones(Nt, M)
        end
        if :energy in vars
            @test parts.E == E
        else
            @test parts.E == E_ref
        end
    end
end

@testset "build_scaling_vector" begin
    Nt = 32; M = 1
    cfg = MVConfig(variables=(:phase, :amplitude, :energy),
                   s_φ=1.5, s_A=10.0, s_E=0.01)
    s = build_scaling_vector(cfg, Nt, M)
    @test length(s) == 2 * Nt * M + 1
    # first Nt*M entries are phase scale
    @test all(s[1:Nt*M] .== 1.5)
    # next Nt*M entries are amplitude scale
    @test all(s[Nt*M + 1 : 2*Nt*M] .== 10.0)
    # last entry is energy scale
    @test s[end] == 0.01
end

@testset "MVConfig defaults" begin
    c = MVConfig()
    @test c.variables == (:phase, :amplitude)
    @test c.δ_bound == MV_DEFAULT_DELTA_AMP
    @test c.log_cost === true
    @test c.λ_gdd == 0.0
end

@testset "legal variable name constants" begin
    @test MV_LEGAL_VARS == (:phase, :amplitude, :energy, :mode_coeffs)
end

@info "═══ All unit tests passed ═══"
