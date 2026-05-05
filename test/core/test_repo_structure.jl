using Test

@testset "Repository structure" begin
    scripts_root = joinpath(@__DIR__, "..", "..", "scripts")
    test_root = joinpath(@__DIR__, "..")
    project_root = normpath(joinpath(test_root, ".."))

    loose_files = sort(filter(name -> isfile(joinpath(scripts_root, name)), readdir(scripts_root)))
    @test loose_files == ["README.md"]

    expected_script_dirs = [
        "burst",
        "canonical",
        "dev",
        "lib",
        "ops",
        "workflows",
    ]
    for dir in expected_script_dirs
        @test isdir(joinpath(scripts_root, dir))
    end

    canonical_files = [
        "AGENTS.md",
        "README.md",
        "llms.txt",
        "fiberlab",
        "docs/README.md",
        "docs/research-verdicts.md",
        "agent-docs/README.md",
        "agent-docs/current-agent-context/INDEX.md",
        "docs/architecture/repo-navigation.md",
        "docs/guides/supported-workflows.md",
        "docs/guides/installation.md",
        "results/README.md",
    ]
    for rel in canonical_files
        @test isfile(joinpath(project_root, rel))
    end

    @test !isdir(joinpath(project_root, "python"))
    @test !isfile(joinpath(project_root, "pyproject.toml"))
    @test !isdir(joinpath(project_root, "docs", "planning-history"))

    source_roots = ["configs", "lab_extensions", "scripts", "src", "test"]
    source_sync_conflicts = String[]
    for root_name in source_roots
        root_path = joinpath(project_root, root_name)
        isdir(root_path) || continue
        for (root, _, files) in walkdir(root_path)
            for file in files
                occursin("sync-conflict", file) &&
                    push!(source_sync_conflicts, relpath(joinpath(root, file), project_root))
            end
        end
    end
    @test isempty(sort!(source_sync_conflicts))

    readme = read(joinpath(project_root, "README.md"), String)
    @test occursin("Julia-first", readme)
    @test occursin("Python is not a supported API surface", readme)

    fiberlab = joinpath(project_root, "fiberlab")
    @test success(pipeline(`bash -n $fiberlab`, stdout=devnull, stderr=devnull))

    telemetry_wrapper = joinpath(scripts_root, "ops", "run_with_telemetry.sh")
    @test isfile(telemetry_wrapper)
    @test success(pipeline(`bash -n $telemetry_wrapper`, stdout=devnull, stderr=devnull))

    missing_canonical_includes = String[]
    for name in readdir(joinpath(scripts_root, "canonical"))
        endswith(name, ".jl") || continue
        path = joinpath(scripts_root, "canonical", name)
        text = read(path, String)
        for match in eachmatch(
            r"include\(joinpath\(@__DIR__, \"\.\.\", \"([^\"]+)\", \"([^\"]+)\"\)\)",
            text,
        )
            target = joinpath(scripts_root, String(match.captures[1]), String(match.captures[2]))
            isfile(target) || push!(missing_canonical_includes, relpath(target, project_root))
        end
    end
    @test isempty(sort!(missing_canonical_includes))
end
