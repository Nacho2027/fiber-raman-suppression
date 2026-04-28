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

    telemetry_wrapper = joinpath(scripts_root, "ops", "run_with_telemetry.sh")
    @test isfile(telemetry_wrapper)
    @test success(pipeline(`bash -n $telemetry_wrapper`, stdout=devnull, stderr=devnull))

    telemetry_dir = mktempdir()
    telemetry_cmd = `$telemetry_wrapper --label test-telemetry --out-dir $telemetry_dir --sample-interval 0.05 -- bash -c "sleep 0.1"`
    @test success(pipeline(telemetry_cmd, stdout=devnull, stderr=devnull))
    @test isfile(joinpath(telemetry_dir, "telemetry.json"))
    @test isfile(joinpath(telemetry_dir, "resource_samples.csv"))
    telemetry_json = read(joinpath(telemetry_dir, "telemetry.json"), String)
    @test occursin("\"schema\": \"fiber_run_telemetry_v1\"", telemetry_json)
    @test occursin("\"return_code\": 0", telemetry_json)
    samples = readlines(joinpath(telemetry_dir, "resource_samples.csv"))
    @test startswith(first(samples), "timestamp_utc,elapsed_s,processes")
    @test length(samples) >= 2
end
