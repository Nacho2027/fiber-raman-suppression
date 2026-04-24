using JSON3

include(joinpath(_ROOT, "scripts", "lib", "run_artifacts.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "inspect_run.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "export_run.jl"))

@testset "Canonical lab-facing surface" begin
    @test "smf28_L2m_P0p2W" in approved_run_config_ids()
    @test "smf28_hnlf_default" in approved_sweep_config_ids()

    run_spec = load_canonical_run_config("smf28_L2m_P0p2W")
    @test run_spec.id == "smf28_L2m_P0p2W"
    @test run_spec.kwargs.fiber_name == "SMF-28"
    @test run_spec.kwargs.P_cont == 0.2
    @test run_spec.kwargs.β_order == 3

    sweep_spec = load_canonical_sweep_config("smf28_hnlf_default")
    @test sweep_spec.id == "smf28_hnlf_default"
    @test sweep_spec.Nt_floor == 8192
    @test length(sweep_spec.fibers) == 2
    @test sweep_spec.fibers[1].name == "SMF-28"
    @test sweep_spec.multistart.enabled

    optimize_wrapper = read(joinpath(_ROOT, "scripts", "canonical", "optimize_raman.jl"), String)
    @test occursin("workflows\", \"optimize_raman.jl", optimize_wrapper)
    @test occursin("canonical_optimize_main(ARGS)", optimize_wrapper)

    sweep_wrapper = read(joinpath(_ROOT, "scripts", "canonical", "run_sweep.jl"), String)
    @test occursin("workflows\", \"run_sweep.jl", sweep_wrapper)
    @test occursin("run_sweep_main(ARGS)", sweep_wrapper)

    tmp = mktempdir()
    run_dir = joinpath(tmp, "run")
    mkpath(run_dir)

    payload = (
        fiber_name = "SMF-28",
        run_tag = "test",
        L_m = 2.0,
        P_cont_W = 0.2,
        lambda0_nm = 1550.0,
        fwhm_fs = 185.0,
        gamma = 1.1e-3,
        betas = [-2.17e-26, 1.2e-40],
        Nt = 8,
        time_window_ps = 0.08,
        J_before = 1e-2,
        J_after = 1e-4,
        delta_J_dB = MultiModeNoise.lin_to_dB(1e-4) - MultiModeNoise.lin_to_dB(1e-2),
        grad_norm = 1e-6,
        converged = true,
        iterations = 12,
        wall_time_s = 1.0,
        convergence_history = [-20.0, -30.0, -40.0],
        phi_opt = reshape(collect(range(-0.2, stop=0.2, length=8)), 8, 1),
        uω0 = ones(ComplexF64, 8, 1),
        E_conservation = 0.0,
        bc_input_frac = 1e-6,
        bc_output_frac = 1e-6,
        bc_input_ok = true,
        bc_output_ok = true,
        trust_report = Dict("overall_verdict" => "PASS"),
        trust_report_md = "opt_trust.md",
        band_mask = trues(8),
        sim_Dt = 0.01,
        sim_omega0 = 2π * 193.4,
    )

    artifact = joinpath(run_dir, "opt_result.jld2")
    MultiModeNoise.save_run(artifact, payload)
    write(joinpath(run_dir, "opt_trust.md"), "# trust\n")
    write(joinpath(run_dir, "run_config.toml"), "id = \"smf28_L2m_P0p2W\"\n")
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        write(joinpath(run_dir, "opt" * suffix), "")
    end

    summary = inspect_run_summary(run_dir)
    @test summary.artifact == artifact
    @test summary.standard_images.complete
    @test summary.converged
    @test length(summary.trust_reports) == 1
    @test summary.quality == suppression_quality_label(payload.J_after; uppercase=true)
    @test summary.J_after_dB ≈ MultiModeNoise.lin_to_dB(payload.J_after)
    @test summary.schema_version == MultiModeNoise.OUTPUT_FORMAT_SCHEMA_VERSION

    direct_summary = canonical_run_summary(run_dir)
    @test direct_summary.result_file == artifact
    @test direct_summary.delta_J_dB ≈ payload.delta_J_dB
    @test direct_summary.quality == suppression_quality_label(payload.J_after; uppercase=true)

    @test suppression_quality_label(NaN) == "crashed"
    @test suppression_quality_label(1e-5) == "excellent"
    @test suppression_quality_label(1e-5; uppercase=true) == "EXCELLENT"

    aggregate = Dict{String,Any}(
        "L_vals" => [1.0, 2.0],
        "P_vals" => [0.05, 0.10],
        "J_after_grid" => [1e-4 1e-5; NaN 1e-3],
        "converged_grid" => [true false; false true],
        "window_limited_grid" => [false false; true false],
        "drift_pct_grid" => [0.1 0.2; NaN 0.4],
        "N_sol_grid" => [2.0 3.0; NaN 4.0],
        "Nt_grid" => [8192 8192; 0 16384],
        "time_window_grid" => [10.0 20.0; NaN 30.0],
    )
    points = sweep_aggregate_points(aggregate)
    @test length(points) == 4
    @test points[1].L == 1.0
    @test points[1].P == 0.05
    @test points[1].quality == "GOOD"
    @test points[3].quality == "CRASHED"
    @test points[3].window_limited

    sorted_points = sort_sweep_points_by_suppression!(copy(points))
    @test sorted_points[1].J_after == 1e-5
    @test isnan(sorted_points[end].J_dB)

    ms_points = multistart_result_points([
        (start_idx = 1, sigma = 0.0, J_final = 1e-4, converged = true),
        (start_idx = 2, sigma = 0.5, J_final = -42.0, converged = false),
        (start_idx = 3, sigma = 1.0, J_final = NaN, converged = false),
    ])
    @test length(ms_points) == 3
    @test ms_points[1].J_dB ≈ MultiModeNoise.lin_to_dB(1e-4)
    @test ms_points[2].J_dB == -42.0
    @test isnan(ms_points[3].J_dB)

    ms_spread = multistart_spread_summary(ms_points)
    @test ms_spread.n_valid == 2
    @test ms_spread.best_dB == -42.0
    @test ms_spread.worst_dB ≈ MultiModeNoise.lin_to_dB(1e-4)
    @test occursin("single basin", ms_spread.landscape)

    rendered = sprint(io -> render_run_summary(summary; io=io))
    @test occursin("Standard image set complete: true", rendered)
    @test occursin("SMF-28", rendered)

    export_dir = joinpath(tmp, "export")
    exported = export_run_bundle(run_dir, export_dir)
    @test isfile(exported.phase_csv)
    @test isfile(exported.metadata_json)
    @test isfile(exported.readme)
    @test isfile(joinpath(export_dir, "source_run_config.toml"))

    metadata = JSON3.read(read(exported.metadata_json, String))
    @test String(metadata.export_schema_version) == EXPORT_SCHEMA_VERSION
    @test String(metadata.fiber_name) == "SMF-28"
    @test metadata.converged == true

    csv_lines = readlines(exported.phase_csv)
    @test startswith(first(csv_lines), "index,frequency_offset_THz")
    @test length(csv_lines) == 9

    export_readme = read(exported.readme, String)
    @test occursin("Experimental Handoff Bundle", export_readme)
end
