# Full Julia tier for supported behavior.

using Test

const _ROOT = normpath(joinpath(@__DIR__, ".."))

@testset "Full supported tier" begin
    @testset "Slow tier" begin
        include(joinpath(_ROOT, "test", "tier_slow.jl"))
    end

    @testset "Determinism" begin
        include(joinpath(_ROOT, "test", "core", "test_determinism.jl"))
    end
end
