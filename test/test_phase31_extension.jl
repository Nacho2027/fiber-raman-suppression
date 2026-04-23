using Test
using LinearAlgebra
using JLD2

include(joinpath(@__DIR__, "..", "scripts", "phase31_extension_lib.jl"))

@testset "Phase 31 extension helpers" begin
    @testset "project phi to basis reproduces least-squares coefficient" begin
        B = [1.0 0.0;
             0.0 1.0;
             1.0 1.0]
        c_true = [0.3, -0.2]
        phi = B * c_true
        c_fit = p31x_project_phi_to_basis(phi, B)
        @test norm(B * c_fit - phi) < 1e-12
        @test norm(c_fit - c_true) < 1e-12
    end

    @testset "basis row selection is unique and strict" begin
        rows = Dict{String,Any}[
            Dict("branch" => "A", "kind" => "cubic", "N_phi" => 128, "J_final" => -67.6),
            Dict("branch" => "A", "kind" => "linear", "N_phi" => 64, "J_final" => -63.9),
        ]
        row = p31x_find_basis_row(rows, "A", :cubic, 128)
        @test row["J_final"] == -67.6
        @test_throws ErrorException p31x_find_basis_row(rows, "A", :cubic, 64)
        push!(rows, Dict("branch" => "A", "kind" => "cubic", "N_phi" => 128, "J_final" => -60.0))
        @test_throws ErrorException p31x_find_basis_row(rows, "A", :cubic, 128)
    end

    @testset "default path program includes multiple continuation families" begin
        paths = p31x_default_path_program()
        names = [p.name for p in paths]
        @test "full_zero" in names
        @test "cubic128_full" in names
        @test "linear64_cubic128_full" in names
        hybrid = only([p for p in paths if p.name == "linear64_cubic128_full"])
        @test hybrid.steps[1].mode == :basis
        @test hybrid.steps[1].kind == :cubic
        @test hybrid.steps[end].mode == :full
    end

    @testset "step labels are stable" begin
        @test p31x_step_label((mode = :basis, kind = :cubic, N_phi = 32)) == "cubic_N032"
        @test p31x_step_label((mode = :full,)) == "full_grid"
    end

    @testset "load rows returns empty for missing JLD2" begin
        mktempdir() do dir
            missing = joinpath(dir, "nope.jld2")
            @test p31x_load_rows(missing) == Dict{String,Any}[]
        end
    end
end
