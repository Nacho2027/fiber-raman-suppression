using JSON3
using JLD2

include(joinpath(_ROOT, "scripts", "lib", "run_artifacts.jl"))
include(joinpath(_ROOT, "scripts", "lib", "results_index.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "inspect_run.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "export_run.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "lab_ready.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "refine_amp_on_phase.jl"))

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
    sidecar_path = joinpath(run_dir, "opt_result.json")
    sidecar_text = read(sidecar_path, String)
    write(sidecar_path, replace(sidecar_text, "{" => "{\"timestamp_utc\":\"2026-04-26T22:00:00Z\",", count=1))
    write(joinpath(run_dir, "opt_trust.md"), "# trust\n")
    write(joinpath(run_dir, "run_config.toml"), """
id = "smf28_L2m_P0p2W"

[problem]
regime = "single_mode"

[controls]
variables = ["phase"]

[objective]
kind = "raman_band"

[solver]
kind = "lbfgs"
""")
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        write(joinpath(run_dir, "opt" * suffix), "")
    end

    summary = inspect_run_summary(run_dir)
    @test summary.artifact == artifact
    @test summary.run_config == joinpath(run_dir, "run_config.toml")
    @test summary.standard_images.complete
    @test !summary.export_handoff.complete
    @test summary.converged
    @test length(summary.trust_reports) == 1
    @test summary.quality == suppression_quality_label(payload.J_after; uppercase=true)
    @test summary.J_after_dB ≈ MultiModeNoise.lin_to_dB(payload.J_after)
    @test summary.schema_version == MultiModeNoise.OUTPUT_FORMAT_SCHEMA_VERSION

    direct_summary = canonical_run_summary(run_dir)
    @test direct_summary.result_file == artifact
    @test direct_summary.delta_J_dB ≈ payload.delta_J_dB
    @test direct_summary.quality == suppression_quality_label(payload.J_after; uppercase=true)

    sweep_dir = joinpath(tmp, "sweep")
    mkpath(sweep_dir)
    sweep_summary_path = joinpath(sweep_dir, "SWEEP_SUMMARY.md")
    write(sweep_summary_path, """
# Experiment Sweep Summary: demo_sweep

| Case | Value | Status | J_before [dB] | J_after [dB] | ΔJ [dB] | Quality | Converged | Iterations | Artifact / Error |
|---|---:|---|---:|---:|---:|---|---|---:|---|
| case_001 | 0.1 | complete | -20.0 | -42.0 | -22.0 | EXCELLENT | true | 4 | case_001/opt_result.jld2 |
| case_002 | 0.2 | failed |  |  |  | ERROR | false | 0 | failed |
| case_003 | 0.3 | complete | -19.0 | -35.0 | -16.0 | GOOD | true | 5 | case_003/opt_result.jld2 |
""")
    sweep_summary_json_path = joinpath(sweep_dir, "SWEEP_SUMMARY.json")
    open(sweep_summary_json_path, "w") do io
        JSON3.pretty(io, Dict(
            "schema" => "experiment_sweep_summary_v1",
            "sweep_id" => "demo_sweep",
            "case_count" => 3,
            "complete" => 2,
            "failed" => 1,
            "skipped" => 0,
            "cases" => [
                Dict("case" => "case_001", "status" => "complete", "J_after_dB" => -42.0),
                Dict("case" => "case_002", "status" => "failed", "J_after_dB" => nothing),
                Dict("case" => "case_003", "status" => "complete", "J_after_dB" => -50.0),
            ],
        ))
    end

    index = build_results_index([tmp])
    @test index.total == 2
    @test any(row -> row.kind == :run && row.path == artifact, index.rows)
    @test any(row -> row.kind == :sweep && row.path == sweep_summary_path, index.rows)
    run_row = only(filter(row -> row.kind == :run, index.rows))
    @test run_row.J_after_dB ≈ MultiModeNoise.lin_to_dB(payload.J_after)
    @test run_row.standard_images_complete
    @test run_row.config_id == "smf28_L2m_P0p2W"
    @test run_row.regime == "single_mode"
    @test run_row.objective_kind == "raman_band"
    @test run_row.variables == "phase"
    @test run_row.solver_kind == "lbfgs"
    @test occursin("T", run_row.timestamp_utc)
    @test basename(run_row.trust_report_path) == "opt_trust.md"
    @test run_row.trust_report_present
    @test run_row.lab_ready
    @test run_row.readiness == "ready"
    rendered_index = render_results_index(index)
    @test occursin("# Results Index", rendered_index)
    @test occursin("SMF-28", rendered_index)
    @test occursin("demo_sweep", rendered_index)
    run_only_index = filter_results_index(index; kind=:run, fiber="SMF-28", complete_images=true)
    @test run_only_index.total == 1
    @test only(run_only_index.rows).kind == :run
    @test filter_results_index(index; kind=:sweep).total == 1
    @test filter_results_index(index; contains="demo").total == 1
    @test filter_results_index(index; config_id="smf28_L2m_P0p2W").total == 1
    @test filter_results_index(index; objective="raman_band", regime="single_mode").total == 1
    @test filter_results_index(index; solver="lbfgs", lab_ready=true).total == 1
    @test filter_results_index(index; export_ready=true).total == 0
    comparison = compare_results_index(index)
    @test comparison.total == 1
    @test only(comparison.rows).lab_ready
    rendered_comparison = render_results_comparison(comparison)
    @test occursin("# Results Comparison", rendered_comparison)
    @test occursin("| 1 | true | ready | smf28_L2m_P0p2W | raman_band | phase |", rendered_comparison)
    comparison_csv = render_results_comparison_csv(comparison)
    @test startswith(comparison_csv, "rank,lab_ready,readiness,config_id,objective_kind")
    sweep_comparison = compare_sweep_summaries(index)
    @test sweep_comparison.total == 1
    sweep_row = only(sweep_comparison.rows)
    @test sweep_row.id == "demo_sweep"
    @test sweep_row.cases == 3
    @test sweep_row.complete == 2
    @test sweep_row.failed == 1
    @test sweep_row.best_case == "case_003"
    @test sweep_row.best_J_after_dB == -50.0
    @test sweep_row.median_J_after_dB == -46.0
    @test sweep_row.path == sweep_summary_json_path
    rendered_sweep_comparison = render_sweep_comparison(sweep_comparison)
    @test occursin("# Sweep Comparison", rendered_sweep_comparison)
    @test occursin("demo_sweep", rendered_sweep_comparison)
    sweep_comparison_csv = render_sweep_comparison_csv(sweep_comparison)
    @test startswith(sweep_comparison_csv, "rank,id,cases,complete,failed,skipped")
    csv_index = render_results_index_csv(run_only_index)
    @test startswith(csv_index, "kind,id,config_id,regime,objective_kind,variables,solver_kind,timestamp_utc")
    @test occursin("run,run,smf28_L2m_P0p2W,single_mode,raman_band,phase,lbfgs,", csv_index)
    @test occursin(",SMF-28,2.0,0.2,-20.0,-40.0,-20.0,GOOD,true,12,true,true,false,true,ready,", csv_index)
    @test !occursin("demo_sweep", csv_index)

    @test suppression_quality_label(NaN) == "crashed"
    @test suppression_quality_label(1e-5) == "excellent"
    @test suppression_quality_label(1e-5; uppercase=true) == "EXCELLENT"

    attenuated = zeros(Float64, 100, 1)
    attenuated[50, 1] = 1.0
    attenuated[1, 1] = 1e-12
    sim_with_attenuator = Dict("Nt" => 100, "attenuator" => fill(1.0, 100, 1))
    sim_with_attenuator["attenuator"][1, 1] = 1e-40
    _, legacy_frac = check_boundary_conditions(attenuated, sim_with_attenuator)
    raw_ok, raw_frac = check_raw_temporal_edges(attenuated)
    clamped_edge = 1e-12 / sqrt(eps(Float64))
    expected_legacy_frac = clamped_edge^2 / (1.0 + clamped_edge^2)
    @test legacy_frac ≈ expected_legacy_frac
    @test raw_frac < 1e-20
    @test raw_ok

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
    @test occursin("Run config:", rendered)
    @test occursin("Export handoff complete: false", rendered)
    @test occursin("SMF-28", rendered)

    gate = lab_ready_run_report(run_dir)
    @test gate.pass
    @test isempty(gate.blockers)
    @test gate.standard_images_complete
    @test gate.converged
    @test gate.quality == "GOOD"
    rendered_gate = sprint(io -> render_lab_ready_report(gate; io=io))
    @test occursin("Lab Readiness Gate", rendered_gate)
    @test occursin("Status: `PASS`", rendered_gate)

    export_required_gate = lab_ready_run_report(run_dir; require_export=true)
    @test !export_required_gate.pass
    @test "missing_export_handoff" in export_required_gate.blockers

    export_dir = joinpath(run_dir, "export_handoff")
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

    summary_with_export = inspect_run_summary(run_dir)
    @test summary_with_export.export_handoff.complete
    @test summary_with_export.export_handoff.phase_csv == exported.phase_csv
    @test summary_with_export.export_handoff.metadata_json == exported.metadata_json
    @test summary_with_export.export_handoff.source_config == joinpath(export_dir, "source_run_config.toml")
    @test summary_with_export.export_handoff.phase_csv_valid
    @test summary_with_export.export_handoff.phase_csv_rows == 8
    @test isempty(summary_with_export.export_handoff.phase_csv_errors)

    rendered_with_export = sprint(io -> render_run_summary(summary_with_export; io=io))
    @test occursin("Export handoff complete: true", rendered_with_export)
    @test occursin("phase_profile.csv", rendered_with_export)
    @test occursin("Export phase CSV rows: 8", rendered_with_export)

    exported_gate = lab_ready_run_report(run_dir; require_export=true)
    @test exported_gate.pass
    @test exported_gate.export_handoff_complete
    @test exported_gate.export_phase_csv_valid
    @test exported_gate.export_phase_csv_rows == 8

    write(exported.phase_csv, """
index,frequency_offset_THz,absolute_frequency_THz,wavelength_nm,phase_wrapped_rad,phase_unwrapped_rad,group_delay_fs
1,0.0,193.4,1550.0,0.0,0.0,0.0
2,0.2,NaN,1548.0,0.0,0.0,0.0
""")
    invalid_export_summary = inspect_run_summary(run_dir)
    @test !invalid_export_summary.export_handoff.complete
    @test invalid_export_summary.export_handoff.files_complete
    @test !invalid_export_summary.export_handoff.phase_csv_valid
    @test any(contains("invalid_absolute_frequency_THz"), invalid_export_summary.export_handoff.phase_csv_errors)

    invalid_export_gate = lab_ready_run_report(run_dir; require_export=true)
    @test !invalid_export_gate.pass
    @test "invalid_export_phase_csv" in invalid_export_gate.blockers

    amp_run_dir = joinpath(tmp, "amp_run")
    mkpath(amp_run_dir)
    amp_payload = (;
        payload...,
        amp_opt = reshape([0.9, 1.0, 1.1, 1.0, 0.95, 1.0, 1.05, 1.0], 8, 1),
    )
    amp_artifact = joinpath(amp_run_dir, "amp_result.jld2")
    MultiModeNoise.save_run(amp_artifact, amp_payload)

    amp_export_dir = joinpath(amp_run_dir, "export_handoff")
    amp_exported = export_run_bundle(amp_run_dir, amp_export_dir)
    @test isfile(amp_exported.amplitude_csv)
    @test isfile(amp_exported.roundtrip_json)

    amp_metadata = JSON3.read(read(amp_exported.metadata_json, String))
    @test amp_metadata.amplitude.present == true
    @test String(amp_metadata.amplitude.csv) == "amplitude_profile.csv"
    @test String(amp_metadata.amplitude.hardware_policy) == "loss_only_normalized_to_max"
    @test amp_metadata.amplitude.min_multiplier ≈ 0.9
    @test amp_metadata.amplitude.max_multiplier ≈ 1.1

    amp_csv_lines = readlines(amp_exported.amplitude_csv)
    @test startswith(first(amp_csv_lines), "index,frequency_offset_THz")
    @test occursin("amplitude_multiplier", first(amp_csv_lines))
    @test occursin("normalized_transmission_loss_only", first(amp_csv_lines))
    @test length(amp_csv_lines) == 9

    roundtrip = JSON3.read(read(amp_exported.roundtrip_json, String))
    @test roundtrip.complete == true
    @test roundtrip.phase_rows == 8
    @test roundtrip.amplitude_rows == 8
    @test roundtrip.normalized_transmission_max <= 1.0

    research_amp_dir = joinpath(tmp, "amp_research")
    mkpath(research_amp_dir)
    research_artifact = joinpath(research_amp_dir, "amp_research_result.jld2")
    JLD2.jldsave(research_artifact; amp_payload...)
    write(
        joinpath(research_amp_dir, "amp_research_slm.json"),
        JSON3.write(Dict(
            "schema_version" => "multivar_slm_v1",
            "outputs" => Dict(
                "phase" => Dict("storage_key" => "phi_opt"),
                "amplitude" => Dict("storage_key" => "amp_opt"),
            ),
        )),
    )
    research_exported = export_run_bundle(research_artifact, joinpath(research_amp_dir, "export_handoff"))
    @test isfile(research_exported.amplitude_csv)
    @test JSON3.read(read(research_exported.roundtrip_json, String)).complete == true

    refine_opts = parse_refine_amp_on_phase_args([
        "--dry-run",
        "--export",
        "--tag", "lab_smoke",
        "--L", "2.2",
        "--P", "0.33",
        "--phase-iter", "7",
        "--amp-iter", "8",
        "--delta-bound", "0.15",
        "--threshold-db", "2.5",
    ])
    @test refine_opts.dry_run
    @test refine_opts.export
    @test refine_opts.tag == "lab_smoke"
    @test refine_opts.L == 2.2
    @test refine_opts.P == 0.33
    @test refine_opts.phase_iter == 7
    @test refine_opts.amp_iter == 8
    @test refine_opts.delta_bound == 0.15
    @test refine_opts.threshold_db == 2.5

    refine_plan = refine_amp_on_phase_plan(refine_opts)
    @test refine_plan.output_dir == joinpath("results", "raman", "multivar", "amp_on_phase_lab_smoke")
    @test endswith(refine_plan.artifact, joinpath("amp_on_phase_lab_smoke", "amp_on_phase_result.jld2"))
    @test refine_plan.export_requested
    @test occursin("multivar_amp_on_phase_ablation.jl", refine_plan.command)

    rendered_refine = sprint(io -> render_refine_amp_on_phase_plan(refine_plan; io=io))
    @test occursin("experimental optional workflow", rendered_refine)
    @test occursin("Required closeout", rendered_refine)

    wrapper_refine = read(joinpath(_ROOT, "scripts", "canonical", "refine_amp_on_phase.jl"), String)
    @test occursin("workflows\", \"refine_amp_on_phase.jl", wrapper_refine)
    @test occursin("refine_amp_on_phase_main(ARGS)", wrapper_refine)

    lab_ready_wrapper = read(joinpath(_ROOT, "scripts", "canonical", "lab_ready.jl"), String)
    @test occursin("workflows\", \"lab_ready.jl", lab_ready_wrapper)
    @test occursin("lab_ready_main(ARGS)", lab_ready_wrapper)

    makefile = read(joinpath(_ROOT, "Makefile"), String)
    @test occursin("golden-smoke:", makefile)
    @test occursin("lab_ready.jl --latest research_engine_export_smoke --require-export", makefile)
end
