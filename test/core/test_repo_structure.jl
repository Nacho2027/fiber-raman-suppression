using Test

@testset "Repository structure" begin
    scripts_root = joinpath(@__DIR__, "..", "..", "scripts")
    test_root = joinpath(@__DIR__, "..")
    project_root = normpath(joinpath(test_root, ".."))

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

    grouped_test_dirs = [
        "core",
        "cost_audit",
        "phases",
        "trust_region",
    ]
    for dir in grouped_test_dirs
        @test isdir(joinpath(test_root, dir))
    end
    @test isfile(joinpath(test_root, "README.md"))

    include_smoke_scripts = [
        joinpath(scripts_root, "workflows", "run_comparison.jl"),
        joinpath(scripts_root, "canonical", "generate_reports.jl"),
        joinpath(scripts_root, "research", "simple_profile", "simple_profile_driver.jl"),
    ]
    for script_path in include_smoke_scripts
        include_expr = "using MultiModeNoise; include($(repr(script_path))); println(\"include ok\")"
        cmd = `$(Base.julia_cmd()) --project=$(project_root) -e $(include_expr)`
        @test success(pipeline(cmd, stdout=devnull, stderr=devnull))
    end
end
