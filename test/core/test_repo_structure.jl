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

    include(joinpath(scripts_root, "lib", "telemetry_index.jl"))
    index_telemetry_script = joinpath(scripts_root, "canonical", "index_telemetry.jl")
    @test isfile(index_telemetry_script)

    telemetry_root = mktempdir()
    first_run = joinpath(telemetry_root, "smoke_a_20260428T010000Z")
    second_run = joinpath(telemetry_root, "smoke_b_20260428T020000Z")
    mkpath(first_run)
    mkpath(second_run)
    write(joinpath(first_run, "telemetry.json"), """
{
  "schema": "fiber_run_telemetry_v1",
  "label": "smoke-a",
  "command": "julia -t auto --project=. scripts/canonical/run_experiment.jl a",
  "hostname": "lab-host",
  "started_at_utc": "2026-04-28T01:00:00Z",
  "finished_at_utc": "2026-04-28T01:01:40Z",
  "elapsed_s": 100.0,
  "return_code": 0,
  "cpu_model": "test cpu",
  "cpu_threads_online": "16",
  "mem_total_kb": "33554432",
  "julia_num_threads": "16",
  "sampled_peak_cpu_percent_sum": 800.0,
  "sampled_peak_mem_percent_sum": 12.5,
  "sampled_peak_rss_kb_sum": 2097152,
  "time_max_rss_kb": "2100000"
}
""")
    write(joinpath(second_run, "telemetry.json"), """
{
  "schema": "fiber_run_telemetry_v1",
  "label": "smoke-b",
  "command": "julia -t auto --project=. scripts/canonical/run_experiment.jl b",
  "hostname": "lab-host",
  "started_at_utc": "2026-04-28T02:00:00Z",
  "finished_at_utc": "2026-04-28T02:05:00Z",
  "elapsed_s": 300.0,
  "return_code": 1,
  "cpu_model": "test cpu",
  "cpu_threads_online": "16",
  "mem_total_kb": "33554432",
  "julia_num_threads": "16",
  "sampled_peak_cpu_percent_sum": 1200.0,
  "sampled_peak_mem_percent_sum": 25.0,
  "sampled_peak_rss_kb_sum": 4194304,
  "time_max_rss_kb": "4200000"
}
""")

    telemetry_index = build_telemetry_index([telemetry_root])
    @test telemetry_index.total == 2
    @test telemetry_summary(telemetry_index).failed == 1
    @test telemetry_format_duration(3661.2) == "1h01m01s"
    failed_index = filter_telemetry_index(telemetry_index; failed=true)
    @test length(failed_index.rows) == 1
    @test only(failed_index.rows).label == "smoke-b"
    slowest = top_telemetry_index(
        sort_telemetry_index(telemetry_index; by=:elapsed, descending=true),
        1,
    )
    @test only(slowest.rows).label == "smoke-b"
    markdown = render_telemetry_index(slowest)
    @test occursin("# Compute Telemetry Index", markdown)
    @test occursin("smoke-b", markdown)
    csv = render_telemetry_index_csv(telemetry_index)
    @test startswith(csv, "id,label,started_at_utc")
    @test occursin("smoke-a", csv)
    cli_csv = read(
        `$(Base.julia_cmd()) --project=$(project_root) $index_telemetry_script --csv --sort elapsed --desc --top 1 $telemetry_root`,
        String,
    )
    @test occursin("smoke-b", cli_csv)
    @test !occursin("smoke-a", cli_csv)
end
