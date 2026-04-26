include(joinpath(_ROOT, "scripts", "lib", "experiment_spec.jl"))
include(joinpath(_ROOT, "scripts", "lib", "experiment_sweep.jl"))
include(joinpath(_ROOT, "scripts", "lib", "experiment_runner.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "run_experiment.jl"))

@testset "Experiment front layer" begin
    @test "research_engine_poc" in approved_experiment_config_ids()
    @test "research_engine_smoke" in approved_experiment_config_ids()
    @test "research_engine_export_smoke" in approved_experiment_config_ids()
    @test "research_engine_peak_smoke" in approved_experiment_config_ids()
    @test "grin50_mmf_phase_sum_poc" in approved_experiment_config_ids()
    @test "smf28_longfiber_phase_poc" in approved_experiment_config_ids()
    @test "smf28_phase_amplitude_energy_poc" in approved_experiment_config_ids()

    spec = load_experiment_spec("research_engine_poc")
    @test spec.id == "smf28_phase_lbfgs_poc"
    @test spec.schema == :experiment_v1
    @test spec.problem.regime == :single_mode
    @test spec.problem.preset == :SMF28
    @test spec.controls.variables == (:phase,)
    @test spec.controls.parameterization == :full_grid
    @test spec.objective.kind == :raman_band
    @test spec.solver.kind == :lbfgs
    @test spec.export_plan.profile == :neutral_csv_v1
    @test :raman_band in registered_objective_kinds(:single_mode)
    band_contract = experiment_objective_contract(spec)
    @test band_contract.kind == :raman_band
    @test band_contract.backend == :raman_optimization
    @test (:phase,) in band_contract.supported_variables
    @test :gdd in band_contract.allowed_regularizers
    @test :raman_peak in registered_objective_kinds(:single_mode)
    peak_contract = objective_contract(:raman_peak, :single_mode)
    @test peak_contract.kind == :raman_peak
    @test peak_contract.supported_variables == ((:phase,),)
    @test peak_contract.allowed_regularizers == (:gdd, :boundary)
    capabilities = sprint(io -> render_experiment_capabilities(; io=io))
    @test occursin("Experiment capabilities", capabilities)
    @test occursin("single_mode", capabilities)
    @test occursin("long_fiber", capabilities)
    @test occursin("multimode", capabilities)
    @test occursin("neutral_csv_v1", capabilities)
    @test occursin("raman_band", capabilities)
    @test occursin("raman_peak", capabilities)
    @test occursin("mmf_sum", capabilities)
    @test :pulse_compression_demo in registered_objective_extension_kinds(:single_mode)
    extension_contract = objective_extension_contract(:pulse_compression_demo, :single_mode)
    @test extension_contract.kind == :pulse_compression_demo
    @test extension_contract.execution == :planning_only
    @test extension_contract.backend == :lab_extension
    @test isfile(joinpath(_ROOT, extension_contract.source))
    extension_listing = sprint(io -> render_objective_registry(; io=io))
    @test occursin("Research extension objective contracts", extension_listing)
    @test occursin("pulse_compression_demo", extension_listing)
    @test occursin("execution=planning_only", extension_listing)
    validation_report = validate_all_experiment_configs()
    @test validation_report.complete
    @test validation_report.total == length(approved_experiment_config_ids())
    @test validation_report.failed == 0
    rendered_validation = sprint(io -> render_experiment_validation_report(validation_report; io=io))
    @test occursin("Experiment config validation", rendered_validation)
    @test occursin("complete=true", rendered_validation)
    @test occursin("research_engine_poc", rendered_validation)
    @test occursin("grin50_mmf_phase_sum_poc", rendered_validation)
    @test "smf28_power_micro_sweep" in approved_experiment_sweep_config_ids()
    sweep_spec = load_experiment_sweep_spec("smf28_power_micro_sweep")
    @test sweep_spec.id == "smf28_power_micro_sweep"
    @test sweep_spec.base_experiment == "research_engine_smoke"
    @test sweep_spec.sweep.parameter == "problem.P_cont"
    expanded_sweep = expand_experiment_sweep(sweep_spec)
    @test length(expanded_sweep.cases) == 3
    @test expanded_sweep.cases[1].spec.problem.P_cont == 0.001
    @test expanded_sweep.cases[2].spec.problem.P_cont == 0.002
    @test expanded_sweep.cases[3].spec.problem.P_cont == 0.003
    @test all(case -> (:phase,) in validate_experiment_spec(case.spec).variables, expanded_sweep.cases)
    @test all(case -> startswith(case.spec.output_tag, "smf28_power_micro_sweep__case_"), expanded_sweep.cases)
    sweep_plan = render_experiment_sweep_plan(sweep_spec)
    @test occursin("Experiment sweep: smf28_power_micro_sweep", sweep_plan)
    @test occursin("Base experiment: research_engine_smoke", sweep_plan)
    @test occursin("parameter=problem.P_cont", sweep_plan)
    @test occursin("case_001", sweep_plan)
    sweep_validation = validate_all_experiment_sweeps()
    @test sweep_validation.complete
    @test sweep_validation.total == length(approved_experiment_sweep_config_ids())
    rendered_sweep_validation = sprint(io -> render_experiment_sweep_validation_report(sweep_validation; io=io))
    @test occursin("Experiment sweep validation", rendered_sweep_validation)
    @test occursin("smf28_power_micro_sweep", rendered_sweep_validation)
    fake_sweep_results = (
        (
            label = "case_001",
            value = 0.001,
            status = :complete,
            output_dir = "/tmp/case_001",
            artifact_path = "/tmp/case_001/opt_result.jld2",
            summary = (
                J_before_dB = -20.0,
                J_after_dB = -30.0,
                delta_J_dB = -10.0,
                quality = "GOOD",
                converged = true,
                iterations = 1,
            ),
        ),
        (
            label = "case_002",
            value = 0.002,
            status = :failed,
            output_dir = "",
            artifact_path = "",
            summary = nothing,
            error = "boom",
        ),
    )
    sweep_summary_md = render_experiment_sweep_summary(sweep_spec, fake_sweep_results)
    @test occursin("# Experiment Sweep Summary: smf28_power_micro_sweep", sweep_summary_md)
    @test occursin("| case_001 | 0.001 | complete | -20.00 | -30.00 | -10.00 | GOOD | true | 1 | /tmp/case_001/opt_result.jld2 |", sweep_summary_md)
    @test occursin("| case_002 | 0.002 | failed |  |  |  |  |  |  | boom |", sweep_summary_md)
    caps = validate_experiment_spec(spec)
    @test (:phase,) in caps.variables

    smoke_spec = load_experiment_spec("research_engine_smoke")
    @test smoke_spec.id == "smf28_phase_smoke"
    @test smoke_spec.maturity == "supported"
    @test smoke_spec.problem.regime == :single_mode
    @test smoke_spec.controls.variables == (:phase,)
    @test smoke_spec.solver.max_iter == 1
    smoke_kwargs = supported_experiment_run_kwargs(smoke_spec)
    @test smoke_kwargs.Nt == 1024
    @test smoke_kwargs.L_fiber == 0.05
    @test smoke_kwargs.P_cont == 0.001

    export_spec = load_experiment_spec("research_engine_export_smoke")
    @test export_spec.id == "smf28_phase_export_smoke"
    @test export_spec.export_plan.enabled
    @test experiment_export_requested(export_spec)
    export_contract = export_profile_contract(export_spec.export_plan.profile)
    @test export_contract.profile == :neutral_csv_v1
    @test :phase_profile_csv in export_contract.required_files

    peak_spec = load_experiment_spec("research_engine_peak_smoke")
    @test peak_spec.id == "smf28_phase_peak_smoke"
    @test peak_spec.objective.kind == :raman_peak
    @test experiment_objective_contract(peak_spec).kind == :raman_peak
    @test supported_experiment_run_kwargs(peak_spec).objective_kind == :raman_peak

    long_spec = load_experiment_spec("smf28_longfiber_phase_poc")
    @test long_spec.id == "smf28_longfiber_phase_poc"
    @test long_spec.maturity == "experimental"
    @test long_spec.problem.regime == :long_fiber
    @test long_spec.controls.variables == (:phase,)
    @test long_spec.objective.kind == :raman_band
    @test long_spec.verification.mode == :burst_required
    @test experiment_execution_mode(long_spec) == :long_fiber_phase
    @test experiment_objective_contract(long_spec).regime == :long_fiber
    @test (:phase,) in validate_experiment_spec(long_spec).variables
    rendered_long = render_experiment_plan(long_spec)
    @test occursin("Execution: mode=long_fiber_phase", rendered_long)
    @test occursin("burst_required=true", rendered_long)
    @test occursin("regime=long_fiber", rendered_long)
    long_compute_plan = render_experiment_compute_plan(long_spec)
    @test occursin("Compute plan: smf28_longfiber_phase_poc", long_compute_plan)
    @test occursin("Provider-neutral path", long_compute_plan)
    @test occursin("Optional Rivera Lab burst helper", long_compute_plan)
    @test occursin("No command in this plan is launched automatically", long_compute_plan)
    @test occursin("scripts/research/longfiber/longfiber_optimize_100m.jl", long_compute_plan)
    @test_throws ArgumentError run_supported_experiment(long_spec; timestamp="test")
    @test_throws ErrorException run_experiment_main(["smf28_longfiber_phase_poc"])

    mmf_spec = load_experiment_spec("grin50_mmf_phase_sum_poc")
    @test mmf_spec.id == "grin50_mmf_phase_sum_poc"
    @test mmf_spec.maturity == "experimental"
    @test mmf_spec.problem.regime == :multimode
    @test mmf_spec.problem.preset == :GRIN_50
    @test mmf_spec.controls.variables == (:phase,)
    @test mmf_spec.controls.parameterization == :shared_across_modes
    @test mmf_spec.objective.kind == :mmf_sum
    @test mmf_spec.artifacts.bundle == :mmf_planning
    @test mmf_spec.verification.mode == :burst_required
    @test experiment_execution_mode(mmf_spec) == :multimode_phase
    @test experiment_objective_contract(mmf_spec).regime == :multimode
    @test (:phase,) in validate_experiment_spec(mmf_spec).variables
    rendered_mmf = render_experiment_plan(mmf_spec)
    @test occursin("Execution: mode=multimode_phase", rendered_mmf)
    @test occursin("burst_required=true", rendered_mmf)
    @test occursin("regime=multimode", rendered_mmf)
    mmf_compute_plan = render_experiment_compute_plan(mmf_spec)
    @test occursin("Compute plan: grin50_mmf_phase_sum_poc", mmf_compute_plan)
    @test occursin("Provider-neutral path", mmf_compute_plan)
    @test occursin("Optional Rivera Lab burst helper", mmf_compute_plan)
    @test occursin("scripts/research/mmf/baseline.jl", mmf_compute_plan)
    @test_throws ArgumentError run_supported_experiment(mmf_spec; timestamp="test")
    @test_throws ErrorException run_experiment_main(["grin50_mmf_phase_sum_poc"])

    uωf = ComplexF64[1 + 0im, 2 + 0im, 3 + 0im, 4 + 0im]
    band_mask = Bool[false, true, true, false]
    J_peak, dJ_peak = spectral_peak_band_cost(reshape(uωf, :, 1), band_mask)
    @test J_peak ≈ 9 / 30
    @test dJ_peak[3, 1] ≈ uωf[3] * (1 - J_peak) / 30
    @test dJ_peak[2, 1] ≈ uωf[2] * (0 - J_peak) / 30

    mv_spec = load_experiment_spec("smf28_phase_amplitude_energy_poc")
    @test mv_spec.id == "smf28_phase_amplitude_energy_poc"
    @test mv_spec.maturity == "experimental"
    @test mv_spec.controls.variables == (:phase, :amplitude, :energy)
    @test mv_spec.artifacts.bundle == :experimental_multivar
    @test mv_spec.objective.regularizers[:energy] == 1.0
    mv_caps = validate_experiment_spec(mv_spec)
    @test (:phase, :amplitude, :energy) in mv_caps.variables

    phase_exec = experiment_execution_mode(spec)
    @test phase_exec == :phase_only
    mv_exec = experiment_execution_mode(mv_spec)
    @test mv_exec == :multivar

    mv_kwargs = supported_experiment_run_kwargs(mv_spec)
    @test mv_kwargs.variables == (:phase, :amplitude, :energy)
    @test mv_kwargs.max_iter == 30
    @test mv_kwargs.fiber_preset == :SMF28
    @test mv_kwargs.validate == false

    adapted = load_experiment_spec("smf28_L2m_P0p2W")
    @test adapted.schema == :canonical_run_adapter
    @test adapted.id == "smf28_L2m_P0p2W"
    @test adapted.problem.regime == :single_mode
    @test adapted.controls.variables == (:phase,)
    @test adapted.objective.kind == :raman_band
    @test adapted.problem.preset == :SMF28
    @test adapted.maturity == "supported"

    rendered = render_experiment_plan(spec)
    @test occursin("Experiment spec: smf28_phase_lbfgs_poc", rendered)
    @test occursin("Execution: mode=phase_only", rendered)
    @test occursin("Controls: variables=[:phase]", rendered)
    @test occursin("Objective: kind=raman_band", rendered)
    @test occursin("backend=raman_optimization", rendered)
    local_compute_plan = render_experiment_compute_plan(spec)
    @test occursin("Local command", local_compute_plan)
    @test occursin("run_experiment.jl research_engine_poc", local_compute_plan)
    @test !occursin("Optional Rivera Lab burst helper", local_compute_plan)

    rendered_mv = render_experiment_plan(mv_spec)
    @test occursin("Execution: mode=multivar", rendered_mv)
    @test occursin("export_supported=false", rendered_mv)

    rendered_export = render_experiment_plan(export_spec)
    @test occursin("export_requested=true", rendered_export)
    @test occursin("export_profile=neutral_csv_v1", rendered_export)

    rendered_peak = render_experiment_plan(peak_spec)
    @test occursin("Objective: kind=raman_peak", rendered_peak)
    @test occursin("backend=raman_optimization", rendered_peak)

    tmp = mktempdir()
    save_prefix = joinpath(tmp, "opt")
    artifact_path = string(save_prefix, "_result.jld2")
    sidecar_path = string(save_prefix, "_result.json")
    trust_path = string(save_prefix, "_trust.md")
    config_copy = joinpath(tmp, "run_config.toml")
    write(artifact_path, "fake jld2\n")
    write(sidecar_path, "{}\n")
    write(trust_path, "# trust\n")
    write(config_copy, "id = \"smf28_phase_lbfgs_poc\"\n")
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        write(string(save_prefix, suffix), "")
    end

    fake_bundle = (
        spec = spec,
        output_dir = tmp,
        save_prefix = save_prefix,
        config_copy = config_copy,
        artifact_path = artifact_path,
    )
    artifact_report = validate_experiment_artifacts(fake_bundle)
    @test artifact_report.complete
    @test isempty(artifact_report.missing)
    @test artifact_report.standard_images.complete
    @test artifact_report.sidecar_path == sidecar_path
    @test artifact_report.trust_report_path == trust_path

    completed_bundle = (; fake_bundle..., artifact_validation = artifact_report)
    cli_summary = sprint(io -> render_experiment_completion_summary(completed_bundle; io=io))
    @test occursin("Experiment run complete", cli_summary)
    @test occursin("Output directory: $tmp", cli_summary)
    @test occursin("Artifact: $artifact_path", cli_summary)
    @test occursin("Artifact validation: complete", cli_summary)
    @test occursin("Standard images: complete", cli_summary)

    export_dir = joinpath(tmp, "export_handoff")
    mkpath(export_dir)
    phase_csv = joinpath(export_dir, "phase_profile.csv")
    metadata_json = joinpath(export_dir, "metadata.json")
    export_readme = joinpath(export_dir, "README.md")
    source_config = joinpath(export_dir, "source_run_config.toml")
    write(phase_csv, "index,frequency_offset_THz,absolute_frequency_THz,wavelength_nm,phase_wrapped_rad,phase_unwrapped_rad,group_delay_fs\n")
    write(metadata_json, "{\"export_schema_version\":\"1.0\",\"phase_csv\":\"phase_profile.csv\"}\n")
    write(export_readme, "# Experimental Handoff Bundle\n")
    write(source_config, "id = \"smf28_phase_export_smoke\"\n")
    exported = (
        output_dir = export_dir,
        phase_csv = phase_csv,
        metadata_json = metadata_json,
        readme = export_readme,
    )
    export_report = validate_experiment_export_bundle(export_spec, exported)
    @test export_report.complete
    @test isempty(export_report.missing)

    write(phase_csv, "")
    write(metadata_json, "not json\n")
    malformed_export = validate_experiment_export_bundle(export_spec, exported; throw_on_error=false)
    @test !malformed_export.complete
    @test any(endswith("header"), malformed_export.missing)
    @test any(endswith("parse"), malformed_export.missing)

    objective_listing = sprint(io -> render_objective_registry(; io=io))
    @test occursin("Built-in objective contracts", objective_listing)
    @test occursin("raman_band", objective_listing)
    @test occursin("backend=raman_optimization", objective_listing)
    @test occursin("regularizers=gdd, boundary", objective_listing)

    rm(string(save_prefix, "_phase_diagnostic.png"))
    @test_throws ArgumentError validate_experiment_artifacts(fake_bundle)

    unsupported = (
        spec...,
        controls = (spec.controls..., variables = (:phase, :amplitude)),
    )
    @test_throws ArgumentError validate_experiment_spec(unsupported)

    unsupported_mv = (
        mv_spec...,
        controls = (mv_spec.controls..., variables = (:phase, :mode_coeffs)),
    )
    @test_throws ArgumentError validate_experiment_spec(unsupported_mv)

    unknown_objective = (
        spec...,
        objective = (spec.objective..., kind = :made_up_cost),
    )
    @test_throws ArgumentError validate_experiment_spec(unknown_objective)

    unknown_regularizer = (
        spec...,
        objective = (spec.objective..., regularizers = Dict{Symbol,Any}(:not_a_real_penalty => 1.0)),
    )
    @test_throws ArgumentError validate_experiment_spec(unknown_regularizer)

    peak_multivar = (
        mv_spec...,
        objective = (mv_spec.objective..., kind = :raman_peak),
    )
    @test_throws ArgumentError validate_experiment_spec(peak_multivar)

    long_export = (
        long_spec...,
        export_plan = (long_spec.export_plan..., enabled = true),
    )
    @test_throws ArgumentError validate_experiment_spec(long_export)

    long_not_burst = (
        long_spec...,
        verification = (long_spec.verification..., mode = :standard),
    )
    @test_throws ArgumentError validate_experiment_spec(long_not_burst)

    mmf_export = (
        mmf_spec...,
        export_plan = (mmf_spec.export_plan..., enabled = true),
    )
    @test_throws ArgumentError validate_experiment_spec(mmf_export)

    mmf_not_burst = (
        mmf_spec...,
        verification = (mmf_spec.verification..., mode = :standard),
    )
    @test_throws ArgumentError validate_experiment_spec(mmf_not_burst)

    mv_export = (
        mv_spec...,
        export_plan = (mv_spec.export_plan..., enabled = true),
    )
    @test_throws ArgumentError validate_experiment_spec(mv_export)

    mv_handoff = (
        mv_spec...,
        artifacts = (mv_spec.artifacts..., export_phase_handoff = true),
    )
    @test_throws ArgumentError validate_experiment_spec(mv_handoff)

    export_without_unwrapped = (
        export_spec...,
        export_plan = (export_spec.export_plan..., include_unwrapped_phase = false),
    )
    @test_throws ArgumentError validate_experiment_spec(export_without_unwrapped)

    export_without_group_delay = (
        export_spec...,
        export_plan = (export_spec.export_plan..., include_group_delay = false),
    )
    @test_throws ArgumentError validate_experiment_spec(export_without_group_delay)

    latest_root = mktempdir()
    old_dir = joinpath(latest_root, "demo_20260101_000000")
    new_dir = joinpath(latest_root, "demo_20260102_000000")
    incomplete_dir = joinpath(latest_root, "demo_20260103_000000")
    other_dir = joinpath(latest_root, "other_20260104_000000")
    for dir in (old_dir, new_dir, incomplete_dir, other_dir)
        mkpath(dir)
    end
    write(joinpath(old_dir, "opt_result.jld2"), "fake\n")
    write(joinpath(new_dir, "opt_result.jld2"), "fake\n")
    write(joinpath(other_dir, "opt_result.jld2"), "fake\n")
    latest_spec = (
        spec...,
        output_root = latest_root,
        output_tag = "demo",
    )
    run_dirs = experiment_run_directories(latest_spec)
    @test run_dirs == [old_dir, new_dir]
    @test latest_experiment_output_dir(latest_spec) == new_dir

    empty_latest_spec = (
        spec...,
        output_root = mktempdir(),
        output_tag = "missing",
    )
    @test_throws ArgumentError latest_experiment_output_dir(empty_latest_spec)

    wrapper = read(joinpath(_ROOT, "scripts", "canonical", "run_experiment.jl"), String)
    @test occursin("workflows\", \"run_experiment.jl", wrapper)
    @test occursin("run_experiment_main(ARGS)", wrapper)

    workflow = read(joinpath(_ROOT, "scripts", "workflows", "run_experiment.jl"), String)
    @test count("render_experiment_completion_summary", workflow) >= 2
    @test occursin("--objectives", workflow)
    @test occursin("--latest", workflow)
    @test occursin("--compute-plan", workflow)

    optimize_workflow = read(joinpath(_ROOT, "scripts", "workflows", "optimize_raman.jl"), String)
    @test occursin("artifact_validation", optimize_workflow)
end
