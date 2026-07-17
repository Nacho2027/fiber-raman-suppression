using JSON3
using JLD2

include(joinpath(_ROOT, "scripts", "lib", "run_artifacts.jl"))
include(joinpath(_ROOT, "scripts", "lib", "results_index.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "inspect_run.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "export_run.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "lab_ready.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "refine_amp_on_phase.jl"))

@testset "Canonical lab-facing surface" begin
    tmp = mktempdir()
    run_dir = joinpath(tmp, "run")
    mkpath(run_dir)

    export_frequency = FFTW.fftfreq(8, 1 / 0.01)
    export_delay_ps = 0.001
    phase_turns = [0, 3, -2, 5, -4, 1, -3, 2]
    phase_storage = export_delay_ps .* 2π .* export_frequency .+ 2π .* phase_turns
    exported_phase = _phase_export_data(phase_storage)
    @test all(-π .<= exported_phase.wrapped .<= π)
    @test _group_delay_fs(exported_phase.unwrapped, 2π / (8 * 0.01)) ≈
          fill(1.0, 8) atol=1e-10

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
        delta_J_dB = FiberLab.lin_to_dB(1e-4) - FiberLab.lin_to_dB(1e-2),
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
    FiberLab.save_run(artifact, payload)
    sidecar_path = joinpath(run_dir, "opt_result.json")
    sidecar_payload = copy(JSON3.read(read(sidecar_path, String), Dict{String,Any}))
    sidecar_payload["timestamp_utc"] = "2026-04-26T22:00:00Z"
    open(sidecar_path, "w") do io
        JSON3.pretty(io, sidecar_payload)
    end
    write(joinpath(run_dir, "opt_trust.md"),
        "# Numerical Trust Report\n\n- Overall verdict: **PASS**\n")
    supported_config = read(
        resolve_experiment_config_path("research_engine_poc"), String)
    write(
        joinpath(run_dir, "run_config.toml"),
        replace(
            supported_config,
            "id = \"smf28_phase_lbfgs_poc\"" =>
                "id = \"smf28_L2m_P0p2W\"";
            count = 1,
        ),
    )
    run_manifest_path = joinpath(run_dir, "run_manifest.json")
    open(run_manifest_path, "w") do io
        JSON3.pretty(io, Dict(
            "schema_version" => "run_manifest_v1",
            "run_context" => "explore_local_smoke",
            "command" => "./fiberlab explore run sample --local-smoke",
            "execution" => Dict(
                "compare_ready" => true,
                "missing" => ["experimental_maturity", "no_export_handoff"],
            ),
            "artifacts" => Dict(
                "complete" => true,
                "standard_images_complete" => true,
                "variable_artifacts_complete" => true,
            ),
        ))
    end
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        write(joinpath(run_dir, "opt" * suffix), "")
    end

    invalid_image_summary = inspect_run_summary(run_dir)
    @test !invalid_image_summary.standard_images.complete
    @test sort(invalid_image_summary.standard_images.invalid) ==
        sort(collect(REQUIRED_STANDARD_IMAGE_SUFFIXES))

    seed_png = joinpath(tmp, "nonblank.png")
    figure, axis = FiberLab.PyPlot.subplots(figsize=(2, 2))
    axis.plot([0.0, 1.0], [0.0, 1.0], color="tab:blue")
    axis.set_xlabel("x")
    axis.set_ylabel("y")
    figure.savefig(seed_png, dpi=72)
    FiberLab.PyPlot.close(figure)
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        cp(seed_png, joinpath(run_dir, "opt" * suffix); force=true)
    end

    summary = inspect_run_summary(run_dir)
    @test summary.artifact == artifact
    @test summary.run_config == joinpath(run_dir, "run_config.toml")
    @test summary.standard_images.complete
    @test !summary.export_handoff.complete
    @test summary.converged
    @test length(summary.trust_reports) == 1
    @test summary.quality == suppression_quality_label(payload.J_after; uppercase=true)
    @test summary.J_after_dB ≈ FiberLab.lin_to_dB(payload.J_after)
    @test summary.schema_version == FiberLab.OUTPUT_FORMAT_SCHEMA_VERSION

    direct_summary = canonical_run_summary(run_dir)
    @test direct_summary.result_file == artifact
    @test direct_summary.delta_J_dB ≈ payload.delta_J_dB
    @test direct_summary.quality == suppression_quality_label(payload.J_after; uppercase=true)

    sweep_dir = joinpath(tmp, "sweep")
    mkpath(sweep_dir)
    sweep_summary_path = joinpath(sweep_dir, "SWEEP_SUMMARY.md")
    write(sweep_summary_path, """
# Experiment Sweep Summary: sample_sweep

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
            "sweep_id" => "sample_sweep",
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
    @test run_row.J_after_dB ≈ FiberLab.lin_to_dB(payload.J_after)
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
    @test run_row.manifest_present
    @test run_row.run_context == "explore_local_smoke"
    @test occursin("explore run sample", run_row.manifest_command)
    @test run_row.manifest_compare_ready
    @test occursin("experimental_maturity", run_row.manifest_missing)
    @test run_row.manifest_path == run_manifest_path
    rendered_index = render_results_index(index)
    @test occursin("# Results Index", rendered_index)
    @test occursin("SMF-28", rendered_index)
    @test occursin("sample_sweep", rendered_index)
    @test occursin("Run Context", rendered_index)
    @test occursin("explore_local_smoke", rendered_index)
    run_only_index = filter_results_index(index; kind=:run, fiber="SMF-28", complete_images=true)
    @test run_only_index.total == 1
    @test only(run_only_index.rows).kind == :run
    @test filter_results_index(index; kind=:sweep).total == 1
    @test filter_results_index(index; contains="sample_sweep").total == 1
    @test filter_results_index(index; contains="explore_local_smoke").total == 1
    @test filter_results_index(index; config_id="smf28_L2m_P0p2W").total == 1
    @test filter_results_index(index; objective="raman_band", regime="single_mode").total == 1
    @test filter_results_index(index; solver="lbfgs", lab_ready=true).total == 1
    @test filter_results_index(index; export_ready=true).total == 0
    comparison = compare_results_index(index)
    @test comparison.total == 1
    @test only(comparison.rows).lab_ready
    rendered_comparison = render_results_comparison(comparison)
    @test occursin("# Results Comparison", rendered_comparison)
    @test occursin("| 1 | true | ready | explore_local_smoke | true | experimental_maturity,no_export_handoff | smf28_L2m_P0p2W | raman_band | phase |", rendered_comparison)
    comparison_csv = render_results_comparison_csv(comparison)
    @test startswith(comparison_csv, "rank,lab_ready,readiness,run_context,manifest_compare_ready,manifest_missing,config_id,objective_kind")
    sweep_comparison = compare_sweep_summaries(index)
    @test sweep_comparison.total == 1
    sweep_row = only(sweep_comparison.rows)
    @test sweep_row.id == "sample_sweep"
    @test sweep_row.cases == 3
    @test sweep_row.complete == 2
    @test sweep_row.failed == 1
    @test sweep_row.best_case == "case_003"
    @test sweep_row.best_J_after_dB == -50.0
    @test sweep_row.median_J_after_dB == -46.0
    @test sweep_row.path == sweep_summary_json_path
    rendered_sweep_comparison = render_sweep_comparison(sweep_comparison)
    @test occursin("# Sweep Comparison", rendered_sweep_comparison)
    @test occursin("sample_sweep", rendered_sweep_comparison)
    sweep_comparison_csv = render_sweep_comparison_csv(sweep_comparison)
    @test startswith(sweep_comparison_csv, "rank,id,cases,complete,failed,skipped")
    csv_index = render_results_index_csv(run_only_index)
    @test startswith(csv_index, "kind,id,config_id,regime,objective_kind,variables,solver_kind,timestamp_utc,run_context")
    @test occursin("run,run,smf28_L2m_P0p2W,single_mode,raman_band,phase,lbfgs,2026-04-26T22:00:00Z,explore_local_smoke", csv_index)
    @test occursin("variable_artifacts_complete", csv_index)
    @test occursin(",SMF-28,2.0,0.2,-20.0,-40.0,-20.0,GOOD,true,12,true,true", csv_index)
    @test !occursin("sample_sweep", csv_index)

    mv_tmp = mktempdir()
    mv_dir = joinpath(mv_tmp, "mv_run")
    mkpath(mv_dir)
    mv_artifact = joinpath(mv_dir, "opt_result.jld2")
    FiberLab.save_run(mv_artifact, payload)
    rm(joinpath(mv_dir, "opt_result.json"); force=true)
    write(joinpath(mv_dir, "opt_slm.json"), "{\"generated_at\":\"2026-04-27T00:00:00\"}\n")
    cp(resolve_experiment_config_path("smf28_phase_amplitude_energy_poc"), joinpath(mv_dir, "run_config.toml"); force=true)
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        cp(seed_png, joinpath(mv_dir, "opt" * suffix); force=true)
    end
    cp(seed_png, joinpath(mv_dir, "opt_amplitude_mask.png"); force=true)
    write(joinpath(mv_dir, "opt_energy_metrics.json"), "{\"schema_version\":\"multivar_energy_metrics_v1\"}\n")
    write(joinpath(mv_dir, "opt_pulse_metrics.json"), "{\"schema_version\":\"multivar_pulse_metrics_v1\"}\n")
    write(joinpath(mv_dir, "opt_explore_summary.json"), "{\"schema_version\":\"exploratory_artifacts_v1\"}\n")
    cp(seed_png, joinpath(mv_dir, "opt_explore_overview.png"); force=true)

    mv_index = build_results_index([mv_tmp])
    @test mv_index.total == 1
    mv_row = only(mv_index.rows)
    @test mv_row.config_id == "smf28_phase_amplitude_energy_poc"
    @test mv_row.variables == "phase,amplitude,energy"
    @test mv_row.variable_artifacts_complete
    @test occursin("amplitude_mask", mv_row.variable_artifact_hooks)
    @test occursin("energy_scale", mv_row.variable_artifact_hooks)
    @test occursin("peak_power", mv_row.variable_artifact_hooks)
    @test occursin("opt_amplitude_mask.png", mv_row.variable_artifact_paths)
    @test isempty(mv_row.variable_artifacts_missing)
    @test !mv_row.trust_report_present
    @test !mv_row.lab_ready
    @test occursin("promotion_stage_smoke", mv_row.readiness)
    @test occursin("2026-04-27", mv_row.timestamp_utc)
    rendered_mv_index = render_results_index(mv_index)
    @test occursin("Variable Artifacts", rendered_mv_index)
    @test occursin("smf28_phase_amplitude_energy_poc", rendered_mv_index)
    mv_csv_index = render_results_index_csv(mv_index)
    @test occursin("variable_artifact_paths", mv_csv_index)
    @test filter_results_index(mv_index; contains="pulse_metrics").total == 1

    mv_gate = lab_ready_run_report(mv_dir)
    @test !mv_gate.pass
    @test "promotion_stage_smoke" in mv_gate.blockers
    @test mv_gate.trust_report_required == false
    @test isempty(mv_gate.trust_reports)
    @test mv_gate.variable_artifacts_complete
    @test :amplitude_mask in mv_gate.variable_artifact_hooks
    @test :peak_power in mv_gate.variable_artifact_hooks
    @test occursin("opt_slm.json", mv_gate.sidecar_path)
    rendered_mv_gate = sprint(io -> render_lab_ready_report(mv_gate; io=io))
    @test occursin("Variable artifacts complete: `true`", rendered_mv_gate)
    @test occursin("Trust report required: `false`", rendered_mv_gate)

    rm(joinpath(mv_dir, "opt_pulse_metrics.json"))
    mv_missing_index = build_results_index([mv_tmp])
    mv_missing_row = only(mv_missing_index.rows)
    @test !mv_missing_row.variable_artifacts_complete
    @test occursin("opt_pulse_metrics.json", mv_missing_row.variable_artifacts_missing)
    @test !mv_missing_row.lab_ready
    @test occursin("missing_variable_artifacts", mv_missing_row.readiness)
    mv_missing_gate = lab_ready_run_report(mv_dir)
    @test !mv_missing_gate.pass
    @test "missing_variable_artifacts" in mv_missing_gate.blockers
    @test occursin("opt_pulse_metrics.json", only(mv_missing_gate.variable_artifacts_missing))

    @test suppression_quality_label(NaN) == "crashed"
    @test suppression_quality_label(1e-5) == "excellent"
    @test suppression_quality_label(1e-5; uppercase=true) == "EXCELLENT"

    edge_fixture = zeros(Float64, 100, 1)
    edge_fixture[50, 1] = 1.0
    edge_fixture[1, 1] = 1e-12
    raw_ok, raw_frac = check_raw_temporal_edges(edge_fixture)
    @test raw_frac < 1e-20
    @test raw_ok


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
    @test_throws ArgumentError _export_bundle_path(export_dir, "../escape.csv")
    @test_throws ArgumentError _export_bundle_path(export_dir, abspath(artifact))
    @test isfile(exported.phase_csv)
    @test isfile(exported.metadata_json)
    @test isfile(exported.roundtrip_json)
    @test isfile(exported.readme)
    @test isfile(joinpath(export_dir, "source_run_config.toml"))
    @test isfile(joinpath(export_dir, "source_trust_report.md"))
    @test isfile(joinpath(export_dir, "source_run_manifest.json"))

    metadata = JSON3.read(read(exported.metadata_json, String))
    @test String(metadata.export_schema_version) == EXPORT_SCHEMA_VERSION
    @test String(metadata.fiber_name) == "SMF-28"
    @test metadata.converged == true
    @test String(metadata.source_artifact) == basename(artifact)
    @test metadata.source_artifact_included == false
    @test String(metadata.source_artifact_sha256) == export_file_sha256(artifact)
    @test !hasproperty(metadata, :source_dir)
    @test !hasproperty(metadata, :sidecar)
    @test String(metadata.run_context) == "explore_local_smoke"
    @test String(metadata.trust_verdict) == "PASS"
    @test String(metadata.provenance.source_config) == "source_run_config.toml"
    @test String(metadata.provenance.source_trust_report) == "source_trust_report.md"
    @test String(metadata.provenance.source_run_manifest) == "source_run_manifest.json"
    @test String(metadata.integrity.phase_profile.sha256) == export_file_sha256(exported.phase_csv)
    @test String(metadata.integrity.source_config.sha256) ==
        export_file_sha256(joinpath(export_dir, "source_run_config.toml"))
    @test String(metadata.integrity.source_trust_report.sha256) ==
        export_file_sha256(joinpath(export_dir, "source_trust_report.md"))
    @test String(metadata.integrity.source_run_manifest.sha256) ==
        export_file_sha256(joinpath(export_dir, "source_run_manifest.json"))

    original_metadata = read(exported.metadata_json, String)
    metadata_without_phase_digest = JSON3.read(
        original_metadata, Dict{String,Any})
    delete!(metadata_without_phase_digest["integrity"], "phase_profile")
    open(exported.metadata_json, "w") do io
        JSON3.pretty(io, metadata_without_phase_digest)
    end
    missing_digest_status = export_handoff_status(
        run_dir; source_artifact=artifact)
    @test !missing_digest_status.integrity_valid
    @test "phase_profile:missing_integrity_entry" in
          missing_digest_status.integrity_errors
    @test !_export_handoff_complete(run_dir, artifact).complete
    write(exported.metadata_json, original_metadata)

    original_artifact = read(artifact)
    open(artifact, "a") do io
        write(io, UInt8(0))
    end
    mutated_source_status = export_handoff_status(
        run_dir; source_artifact=artifact)
    @test !mutated_source_status.integrity_valid
    @test "source_artifact:sha256_mismatch" in
          mutated_source_status.integrity_errors
    @test !_export_handoff_complete(run_dir, artifact).complete
    write(artifact, original_artifact)

    roundtrip_bytes = read(exported.roundtrip_json)
    rm(exported.roundtrip_json)
    @test !export_handoff_status(run_dir; source_artifact=artifact).complete
    @test !_export_handoff_complete(run_dir, artifact).complete
    write(exported.roundtrip_json, roundtrip_bytes)

    csv_lines = readlines(exported.phase_csv)
    @test startswith(first(csv_lines), "index,frequency_offset_THz")
    @test length(csv_lines) == 9
    csv_fields = split.(csv_lines[2:end], ',')
    exported_frequencies = parse.(Float64, getindex.(csv_fields, 2))
    exported_wrapped_phase = parse.(Float64, getindex.(csv_fields, 5))
    @test issorted(exported_frequencies)
    @test all(-π .<= exported_wrapped_phase .<= π)

    export_readme = read(exported.readme, String)
    @test occursin("Experimental Handoff Bundle", export_readme)

    summary_with_export = inspect_run_summary(run_dir)
    @test summary_with_export.export_handoff.complete
    @test summary_with_export.export_handoff.phase_csv == exported.phase_csv
    @test summary_with_export.export_handoff.metadata_json == exported.metadata_json
    @test summary_with_export.export_handoff.source_config == joinpath(export_dir, "source_run_config.toml")
    @test summary_with_export.export_handoff.phase_csv_valid
    @test summary_with_export.export_handoff.integrity_valid
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

    untampered_phase_csv = read(exported.phase_csv, String)
    hash_tampered_lines = readlines(exported.phase_csv)
    hash_tampered_fields = split(hash_tampered_lines[2], ",")
    hash_tampered_fields[5] = "0.123456789"
    hash_tampered_lines[2] = join(hash_tampered_fields, ",")
    write(exported.phase_csv, join(hash_tampered_lines, "\n") * "\n")
    hash_tampered_summary = inspect_run_summary(run_dir)
    @test hash_tampered_summary.export_handoff.phase_csv_valid
    @test !hash_tampered_summary.export_handoff.integrity_valid
    hash_tampered_gate = lab_ready_run_report(run_dir; require_export=true)
    @test !hash_tampered_gate.pass
    @test "invalid_export_integrity" in hash_tampered_gate.blockers
    write(exported.phase_csv, untampered_phase_csv)

    write(exported.phase_csv, """
index,frequency_offset_THz,absolute_frequency_THz,wavelength_nm,phase_wrapped_rad,phase_unwrapped_rad,group_delay_fs
1,0.0,193.4,1550.0,0.0,0.0,0.0
2,0.2,NaN,1548.0,0.0,0.0,0.0
""")
    invalid_export_summary = inspect_run_summary(run_dir)
    @test !invalid_export_summary.export_handoff.complete
    @test invalid_export_summary.export_handoff.files_complete
    @test !invalid_export_summary.export_handoff.phase_csv_valid
    @test !invalid_export_summary.export_handoff.integrity_valid
    @test any(contains("invalid_absolute_frequency_THz"), invalid_export_summary.export_handoff.phase_csv_errors)
    @test any(contains("phase_profile:sha256_mismatch"), invalid_export_summary.export_handoff.integrity_errors)

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
    FiberLab.save_run(amp_artifact, amp_payload)

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
    @test occursin("run_amp_on_phase_refinement", refine_plan.command)

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
