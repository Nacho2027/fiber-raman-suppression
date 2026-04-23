using Test

@testset "Repository structure" begin
    scripts_root = joinpath(@__DIR__, "..", "scripts")

    loose_files = sort(filter(name -> isfile(joinpath(scripts_root, name)), readdir(scripts_root)))
    @test loose_files == ["README.md"]

    expected_dirs = [
        "archive",
        "burst",
        "canonical",
        "dev",
        "lib",
        "ops",
        "research",
        "validation",
        "workflows",
    ]
    for dir in expected_dirs
        @test isdir(joinpath(scripts_root, dir))
    end

    active_phase_prefixed = String[]
    research_root = joinpath(scripts_root, "research")
    for (root, _, files) in walkdir(research_root)
        for file in files
            if occursin(r"^_?phase\d+_.*\.jl$", file)
                push!(active_phase_prefixed, relpath(joinpath(root, file), scripts_root))
            end
        end
    end
    @test isempty(active_phase_prefixed)
end
