using JSON3

include(joinpath(_ROOT, "scripts", "lib", "experiment_spec.jl"))
include(joinpath(_ROOT, "scripts", "lib", "experiment_sweep.jl"))
include(joinpath(_ROOT, "scripts", "lib", "experiment_runner.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "run_experiment.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "lab_ready.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "scaffold_objective.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "scaffold_variable.jl"))

@testset "Experiment front layer" begin
    @test "research_engine_poc" in approved_experiment_config_ids()
    @test "research_engine_smoke" in approved_experiment_config_ids()
    @test "research_engine_export_smoke" in approved_experiment_config_ids()
    @test "research_engine_peak_smoke" in approved_experiment_config_ids()
    @test "grin50_mmf_phase_sum_poc" in approved_experiment_config_ids()
    @test "smf28_longfiber_phase_poc" in approved_experiment_config_ids()
    @test "smf28_phase_amplitude_energy_poc" in approved_experiment_config_ids()
    @test "smf28_amp_on_phase_refinement_poc" in approved_experiment_config_ids()

    spec = load_experiment_spec("research_engine_poc")
    @test spec.id == "smf28_phase_lbfgs_poc"
    @test spec.schema == :experiment_v1
    @test spec.problem.regime == :single_mode
    @test spec.problem.preset == :SMF28
    @test spec.controls.variables == (:phase,)
    @test spec.controls.parameterization == :full_grid
    @test spec.controls.policy == :direct
    @test spec.objective.kind == :raman_band
    @test spec.solver.kind == :lbfgs
    @test spec.export_plan.profile == :neutral_csv_v1
    @test :phase in registered_variable_kinds(:single_mode)
    phase_variable_contract = variable_contract(:phase, :single_mode)
    @test phase_variable_contract.kind == :phase
    @test phase_variable_contract.backend == :spectral_phase
    @test :full_grid in phase_variable_contract.parameterizations
    @test :phase_profile in phase_variable_contract.artifact_hooks
    @test :group_delay in phase_variable_contract.artifact_hooks
    phase_layout = control_layout_plan(spec)
    @test phase_layout.total_length == string(spec.problem.Nt)
    @test only(phase_layout.blocks).name == :phase
    @test only(phase_layout.blocks).shape == "8192 x 1"
    @test occursin("rad", only(phase_layout.blocks).units)
    rendered_phase_layout = sprint(io -> render_control_layout_plan(spec; io=io))
    @test occursin("Control layout", rendered_phase_layout)
    @test occursin("optimizer_length=8192", rendered_phase_layout)
    @test occursin("phase_profile", rendered_phase_layout)
    @test :mode_weights_planning in registered_variable_extension_kinds(:multimode)
    variable_extension_contract_sample = variable_extension_contract(:mode_weights_planning, :multimode)
    @test variable_extension_contract_sample.execution == :planning_only
    @test variable_extension_contract_sample.backend == :lab_extension
    @test isfile(joinpath(_ROOT, variable_extension_contract_sample.source))
    variable_listing = sprint(io -> render_variable_registry(; io=io))
    @test occursin("Built-in optimization variable contracts", variable_listing)
    @test occursin("Research extension variable contracts", variable_listing)
    @test occursin("mode_weights_planning", variable_listing)
    variable_extension_report = validate_variable_extension_contracts()
    @test variable_extension_report.total >= 1
    @test variable_extension_report.valid == variable_extension_report.total
    @test variable_extension_report.promotable == 0
    mode_weights_row = only(filter(row -> row.kind == :mode_weights_planning, variable_extension_report.rows))
    @test mode_weights_row.valid
    @test !mode_weights_row.promotable
    @test "execution_planning_only" in mode_weights_row.blockers
    rendered_variable_extension_report = sprint(io -> render_variable_extension_validation_report(variable_extension_report; io=io))
    @test occursin("Variable extension validation", rendered_variable_extension_report)
    @test occursin("mode_weights_planning", rendered_variable_extension_report)
    cli_variable_extension_report = run_experiment_main(["--validate-variables"])
    @test cli_variable_extension_report.total == variable_extension_report.total
    @test cli_variable_extension_report.valid == variable_extension_report.valid
    @test :raman_band in registered_objective_kinds(:single_mode)
    band_contract = experiment_objective_contract(spec)
    @test band_contract.kind == :raman_band
    @test band_contract.backend == :raman_optimization
    @test (:phase,) in band_contract.supported_variables
    @test :J_after_dB in band_contract.metrics
    @test :spectrum_before_after in band_contract.artifact_hooks
    @test :gdd in band_contract.allowed_regularizers
    artifact_plan = experiment_artifact_plan(spec)
    @test artifact_plan.implemented
    @test :standard_image_set in Tuple(request.hook for request in artifact_plan.hooks)
    @test :spectrum_before_after in Tuple(request.hook for request in artifact_plan.hooks)
    @test :phase_profile in Tuple(request.hook for request in artifact_plan.hooks)
    rendered_artifact_plan = sprint(io -> render_experiment_artifact_plan(spec; io=io))
    @test occursin("Artifact plan", rendered_artifact_plan)
    @test occursin("implemented_now=true", rendered_artifact_plan)
    @test occursin("plots.phase_profile", rendered_artifact_plan)
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
    @test :pulse_compression_planning in registered_objective_extension_kinds(:single_mode)
    extension_contract = objective_extension_contract(:pulse_compression_planning, :single_mode)
    @test extension_contract.kind == :pulse_compression_planning
    @test extension_contract.execution == :planning_only
    @test extension_contract.backend == :lab_extension
    @test isfile(joinpath(_ROOT, extension_contract.source))
    extension_listing = sprint(io -> render_objective_registry(; io=io))
    @test occursin("Research extension objective contracts", extension_listing)
    @test occursin("pulse_compression_planning", extension_listing)
    @test occursin("execution=planning_only", extension_listing)
    objective_extension_report = validate_objective_extension_contracts()
    @test objective_extension_report.total >= 1
    @test objective_extension_report.valid == objective_extension_report.total
    @test objective_extension_report.promotable == 0
    pulse_extension_row = only(filter(row -> row.kind == :pulse_compression_planning, objective_extension_report.rows))
    @test pulse_extension_row.valid
    @test !pulse_extension_row.promotable
    @test "execution_planning_only" in pulse_extension_row.blockers
    @test isempty(pulse_extension_row.errors)
    rendered_objective_extension_report = sprint(io -> render_objective_extension_validation_report(objective_extension_report; io=io))
    @test occursin("Objective extension validation", rendered_objective_extension_report)
    @test occursin("pulse_compression_planning", rendered_objective_extension_report)
    @test occursin("execution_planning_only", rendered_objective_extension_report)
    cli_objective_extension_report = run_experiment_main(["--validate-objectives"])
    @test cli_objective_extension_report.total == objective_extension_report.total
    @test cli_objective_extension_report.valid == objective_extension_report.valid

    lab_ready_config = lab_ready_config_report("research_engine_smoke")
    @test lab_ready_config.pass
    @test lab_ready_config.mode == :phase_only
    @test lab_ready_config.objective == :raman_band
    rendered_lab_ready_config = sprint(io -> render_lab_ready_report(lab_ready_config; io=io))
    @test occursin("Lab Readiness Gate", rendered_lab_ready_config)
    @test occursin("Status: `PASS`", rendered_lab_ready_config)

    scaffold_dir = mktempdir()
    scaffold = scaffold_objective_extension(
        "mode_coupling_planning";
        dir=scaffold_dir,
        description="Planning-only objective for mode-coupling research.",
    )
    @test isfile(scaffold.toml_path)
    @test isfile(scaffold.source_path)
    @test scaffold.kind == :mode_coupling_planning
    @test occursin("kind = \"mode_coupling_planning\"", read(scaffold.toml_path, String))
    @test occursin("function mode_coupling_planning_cost", read(scaffold.source_path, String))
    scaffold_contract = _parse_extension_contract(scaffold.toml_path)
    scaffold_row = validate_objective_extension_contract(scaffold_contract)
    @test scaffold_row.valid
    @test !scaffold_row.promotable
    @test "execution_planning_only" in scaffold_row.blockers
    @test_throws ArgumentError scaffold_objective_extension("mode_coupling_planning"; dir=scaffold_dir)
    forced_scaffold = scaffold_objective_extension("mode_coupling_planning"; dir=scaffold_dir, force=true)
    @test forced_scaffold.toml_path == scaffold.toml_path
    cli_scaffold_dir = mktempdir()
    cli_scaffold = scaffold_objective_main([
        "notebook_metric",
        "--dir", cli_scaffold_dir,
        "--description", "Objective drafted from notebook exploration.",
    ])
    @test isfile(cli_scaffold.toml_path)
    @test isfile(cli_scaffold.source_path)
    @test occursin("notebook_metric", read(cli_scaffold.toml_path, String))
    variable_scaffold_dir = mktempdir()
    variable_scaffold = scaffold_variable_extension(
        "gain_tilt_planning";
        dir=variable_scaffold_dir,
        description="Planning-only variable for gain-tilt research.",
        units="dB",
        bounds="box constrained tilt coefficients",
    )
    @test isfile(variable_scaffold.toml_path)
    @test isfile(variable_scaffold.source_path)
    @test variable_scaffold.kind == :gain_tilt_planning
    @test occursin("kind = \"gain_tilt_planning\"", read(variable_scaffold.toml_path, String))
    @test occursin("function build_gain_tilt_planning_control", read(variable_scaffold.source_path, String))
    variable_scaffold_contract = _parse_variable_extension_contract(variable_scaffold.toml_path)
    variable_scaffold_row = validate_variable_extension_contract(variable_scaffold_contract)
    @test variable_scaffold_row.valid
    @test !variable_scaffold_row.promotable
    @test "execution_planning_only" in variable_scaffold_row.blockers
    @test_throws ArgumentError scaffold_variable_extension("gain_tilt_planning"; dir=variable_scaffold_dir)
    forced_variable_scaffold = scaffold_variable_extension("gain_tilt_planning"; dir=variable_scaffold_dir, force=true)
    @test forced_variable_scaffold.toml_path == variable_scaffold.toml_path
    cli_variable_scaffold_dir = mktempdir()
    cli_variable_scaffold = scaffold_variable_main([
        "notebook_control",
        "--dir", cli_variable_scaffold_dir,
        "--description", "Variable drafted from notebook exploration.",
        "--units", "normalized",
        "--bounds", "projected to feasible range",
    ])
    @test isfile(cli_variable_scaffold.toml_path)
    @test isfile(cli_variable_scaffold.source_path)
    @test occursin("notebook_control", read(cli_variable_scaffold.toml_path, String))
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
            artifact_status = "complete",
            trust_report_status = "present",
            standard_images_status = "complete",
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
            artifact_status = "incomplete",
            trust_report_status = "",
            standard_images_status = "",
            error = "boom",
        ),
    )
    sweep_summary_md = render_experiment_sweep_summary(sweep_spec, fake_sweep_results)
    @test occursin("# Experiment Sweep Summary: smf28_power_micro_sweep", sweep_summary_md)
    @test occursin("| Case | Value | Status | Artifact Status | Trust | Standard Images |", sweep_summary_md)
    @test occursin("| case_001 | 0.001 | complete | complete | present | complete | -20.00 | -30.00 | -10.00 | GOOD | true | 1 | /tmp/case_001/opt_result.jld2 |", sweep_summary_md)
    @test occursin("| case_002 | 0.002 | failed | incomplete |  |  |  |  |  |  |  |  | boom |", sweep_summary_md)
    sweep_payload = experiment_sweep_summary_payload(sweep_spec, fake_sweep_results)
    @test sweep_payload["schema"] == "experiment_sweep_summary_v1"
    @test sweep_payload["sweep_id"] == "smf28_power_micro_sweep"
    @test sweep_payload["case_count"] == 2
    @test sweep_payload["complete"] == 1
    @test sweep_payload["failed"] == 1
    @test sweep_payload["cases"][1]["J_after_dB"] == -30.0
    sweep_summary_csv = render_experiment_sweep_summary_csv(sweep_spec, fake_sweep_results)
    @test startswith(sweep_summary_csv, "case,value,status,artifact_status")
    @test occursin("case_001,0.001,complete,complete,present,complete,-20.0,-30.0,-10.0,GOOD,true,1", sweep_summary_csv)
    sweep_summary_dir = mktempdir()
    sweep_summary_paths = write_experiment_sweep_summary_files(sweep_spec, fake_sweep_results, sweep_summary_dir)
    @test isfile(sweep_summary_paths.summary_path)
    @test isfile(sweep_summary_paths.summary_json_path)
    @test isfile(sweep_summary_paths.summary_csv_path)
    written_payload = JSON3.read(read(sweep_summary_paths.summary_json_path, String))
    @test written_payload.sweep_id == "smf28_power_micro_sweep"
    @test length(written_payload.cases) == 2
    sweep_latest_root = mktempdir()
    old_sweep_dir = joinpath(sweep_latest_root, "sample_20260101_000000")
    new_sweep_dir = joinpath(sweep_latest_root, "sample_20260102_000000")
    incomplete_sweep_dir = joinpath(sweep_latest_root, "sample_20260103_000000")
    other_sweep_dir = joinpath(sweep_latest_root, "other_20260104_000000")
    for dir in (old_sweep_dir, new_sweep_dir, incomplete_sweep_dir, other_sweep_dir)
        mkpath(dir)
    end
    write(joinpath(old_sweep_dir, "SWEEP_SUMMARY.md"), "# old\n")
    write(joinpath(new_sweep_dir, "SWEEP_SUMMARY.md"), "# new\n")
    write(joinpath(other_sweep_dir, "SWEEP_SUMMARY.md"), "# other\n")
    latest_sweep_spec = (;
        sweep_spec...,
        output_root = sweep_latest_root,
        output_tag = "sample",
    )
    @test experiment_sweep_output_directories(latest_sweep_spec) == [old_sweep_dir, new_sweep_dir]
    @test latest_experiment_sweep_output_dir(latest_sweep_spec) == new_sweep_dir
    empty_latest_sweep_spec = (;
        sweep_spec...,
        output_root = mktempdir(),
        output_tag = "missing",
    )
    @test_throws ArgumentError latest_experiment_sweep_output_dir(empty_latest_sweep_spec)
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
    @test long_spec.controls.policy == :fresh
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
    @test occursin("LF100_MODE=fresh", long_compute_plan)
    @test occursin("LF100_L=100.0", long_compute_plan)
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
    explore_plan_spec = run_experiment_main(["--explore-plan", "grin50_mmf_phase_sum_poc"])
    @test explore_plan_spec.id == mmf_spec.id
    @test_throws ErrorException run_experiment_main(["--explore-run", "--local-smoke", "grin50_mmf_phase_sum_poc"])
    explore_heavy_dry_spec = run_experiment_main(["--explore-run", "--heavy-ok", "--dry-run", "grin50_mmf_phase_sum_poc"])
    @test explore_heavy_dry_spec.id == mmf_spec.id
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
    @test mv_spec.controls.policy == :direct
    @test mv_spec.artifacts.bundle == :experimental_multivar
    @test mv_spec.objective.regularizers[:energy] == 1.0
    mv_caps = validate_experiment_spec(mv_spec)
    @test (:phase, :amplitude, :energy) in mv_caps.variables
    mv_layout = control_layout_plan(mv_spec)
    @test length(mv_layout.blocks) == 3
    @test mv_layout.total_length == string(2 * mv_spec.problem.Nt + 1)
    @test :amplitude_mask in only(filter(block -> block.name == :amplitude, mv_layout.blocks)).artifact_hooks
    mv_artifact_plan = experiment_artifact_plan(mv_spec)
    @test mv_artifact_plan.implemented
    @test :amplitude_mask in Tuple(request.hook for request in mv_artifact_plan.hooks)
    @test :energy_scale in Tuple(request.hook for request in mv_artifact_plan.hooks)
    @test !(:trust_report in Tuple(request.hook for request in mv_artifact_plan.hooks))
    @test isempty(mv_artifact_plan.planned)

    phase_exec = experiment_execution_mode(spec)
    @test phase_exec == :phase_only
    mv_exec = experiment_execution_mode(mv_spec)
    @test mv_exec == :multivar

    staged_mv_spec = load_experiment_spec("smf28_amp_on_phase_refinement_poc")
    @test staged_mv_spec.id == "smf28_amp_on_phase_refinement_poc"
    @test staged_mv_spec.controls.variables == (:phase, :amplitude)
    @test staged_mv_spec.controls.policy == :amp_on_phase
    @test staged_mv_spec.controls.policy_options[:delta_bound] == 0.10
    @test experiment_execution_mode(staged_mv_spec) == :amp_on_phase
    @test (:phase, :amplitude) in validate_experiment_spec(staged_mv_spec).variables
    staged_mv_plan = render_experiment_plan(staged_mv_spec)
    @test occursin("Execution: mode=amp_on_phase", staged_mv_plan)
    @test occursin("policy=amp_on_phase", staged_mv_plan)
    staged_mv_compute_plan = render_experiment_compute_plan(staged_mv_spec)
    @test occursin("Staged multivar command", staged_mv_compute_plan)
    @test occursin("scripts/canonical/refine_amp_on_phase.jl", staged_mv_compute_plan)
    @test occursin("--delta-bound 0.1", staged_mv_compute_plan)
    @test_throws ErrorException run_experiment_main(["--explore-run", "--local-smoke", "smf28_amp_on_phase_refinement_poc"])
    staged_mv_explore_dry = run_experiment_main(["--explore-run", "--heavy-ok", "--dry-run", "smf28_amp_on_phase_refinement_poc"])
    @test staged_mv_explore_dry.id == staged_mv_spec.id
    @test_throws ArgumentError run_supported_experiment(staged_mv_spec; timestamp="test")

    mv_kwargs = supported_experiment_run_kwargs(mv_spec)
    @test mv_kwargs.variables == (:phase, :amplitude, :energy)
    @test mv_kwargs.max_iter == 30
    @test mv_kwargs.fiber_preset == :SMF28
    @test mv_kwargs.validate == false

    @test_throws ErrorException run_experiment_main(["--explore-run", "research_engine_gain_tilt_smoke"])
    gain_tilt_explore_dry = run_experiment_main(["--explore-run", "--local-smoke", "--dry-run", "research_engine_gain_tilt_smoke"])
    @test gain_tilt_explore_dry.id == "smf28_phase_gain_tilt_smoke"

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
    @test occursin("Control layout: optimizer_length=8192", rendered)
    @test occursin("Objective: kind=raman_band", rendered)
    @test occursin("backend=raman_optimization", rendered)
    @test occursin("Artifact plan: implemented_now=true", rendered)
    cli_control_layout = run_experiment_main(["--control-layout", "research_engine_poc"])
    @test cli_control_layout.total_length == "8192"
    cli_artifact_plan = run_experiment_main(["--artifact-plan", "research_engine_poc"])
    @test cli_artifact_plan.implemented
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

    artifact_tmp = mktempdir()
    artifact_prefix = joinpath(artifact_tmp, "mv_opt")
    artifact_uω0, artifact_fiber, artifact_sim, artifact_band_mask, _, _ = setup_raman_problem_exact(
        Nt=64,
        time_window=2.0,
        L_fiber=0.001,
        P_cont=0.001,
        β_order=3,
        fiber_preset=:SMF28,
    )
    artifact_A = reshape(1.0 .+ 0.05 .* sin.(range(0, 2π; length=artifact_sim["Nt"])), artifact_sim["Nt"], 1)
    artifact_outcome = (
        A_opt = artifact_A,
        φ_opt = zeros(artifact_sim["Nt"], 1),
        E_opt = 2.0,
        E_ref = 1.0,
        diagnostics = Dict{Symbol,Any}(
            :alpha => sqrt(2.0),
            :A_extrema => extrema(artifact_A),
        ),
    )
    artifact_bundle = (
        output_dir = artifact_tmp,
        save_prefix = artifact_prefix,
        outcome = artifact_outcome,
        meta = Dict{Symbol,Any}(:lambda0_nm => 1550.0, :fwhm_fs => 185.0),
        uω0 = artifact_uω0,
        fiber = artifact_fiber,
        sim = artifact_sim,
        band_mask = artifact_band_mask,
    )
    mv_variable_artifacts = write_multivar_variable_artifacts(mv_spec, artifact_bundle)
    @test mv_variable_artifacts.complete
    @test isfile(mv_variable_artifacts.paths[:amplitude_mask])
    @test isfile(mv_variable_artifacts.paths[:energy_throughput])
    @test isfile(mv_variable_artifacts.paths[:energy_scale])
    @test isfile(mv_variable_artifacts.paths[:peak_power])
    energy_metrics = JSON3.read(read(mv_variable_artifacts.paths[:energy_scale], String))
    @test energy_metrics.schema_version == "multivar_energy_metrics_v1"
    @test energy_metrics.E_opt_over_E_ref == 2.0
    pulse_metrics = JSON3.read(read(mv_variable_artifacts.paths[:peak_power], String))
    @test pulse_metrics.schema_version == "multivar_pulse_metrics_v1"
    @test pulse_metrics.energy_scale_alpha == sqrt(2.0)

    mv_artifact_path = string(artifact_prefix, "_result.jld2")
    mv_sidecar_path = string(artifact_prefix, "_slm.json")
    mv_config_copy = joinpath(artifact_tmp, "run_config.toml")
    write(mv_artifact_path, "fake multivar jld2\n")
    write(mv_sidecar_path, "{}\n")
    write(mv_config_copy, "id = \"smf28_phase_amplitude_energy_poc\"\n")
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        write(string(artifact_prefix, suffix), "")
    end
    mv_validation_bundle = (
        spec = mv_spec,
        output_dir = artifact_tmp,
        save_prefix = artifact_prefix,
        config_copy = mv_config_copy,
        artifact_path = mv_artifact_path,
        sidecar_path = mv_sidecar_path,
    )
    mv_artifact_report = validate_experiment_artifacts(mv_validation_bundle)
    @test mv_artifact_report.complete
    @test mv_artifact_report.extra_artifacts.complete
    @test :amplitude_mask in mv_artifact_report.extra_artifacts.hooks
    @test :energy_scale in mv_artifact_report.extra_artifacts.hooks
    @test :peak_power in mv_artifact_report.extra_artifacts.hooks
    rm(mv_variable_artifacts.paths[:peak_power])
    broken_mv_artifact_report = validate_experiment_artifacts(mv_validation_bundle; throw_on_error=false)
    @test !broken_mv_artifact_report.complete
    @test !broken_mv_artifact_report.extra_artifacts.complete
    @test any(endswith("_pulse_metrics.json"), broken_mv_artifact_report.extra_artifacts.missing)

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
    old_dir = joinpath(latest_root, "sample_20260101_000000")
    new_dir = joinpath(latest_root, "sample_20260102_000000")
    incomplete_dir = joinpath(latest_root, "sample_20260103_000000")
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
        output_tag = "sample",
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
    scaffold_wrapper = read(joinpath(_ROOT, "scripts", "canonical", "scaffold_objective.jl"), String)
    @test occursin("workflows\", \"scaffold_objective.jl", scaffold_wrapper)
    @test occursin("scaffold_objective_main(ARGS)", scaffold_wrapper)
    variable_scaffold_wrapper = read(joinpath(_ROOT, "scripts", "canonical", "scaffold_variable.jl"), String)
    @test occursin("workflows\", \"scaffold_variable.jl", variable_scaffold_wrapper)
    @test occursin("scaffold_variable_main(ARGS)", variable_scaffold_wrapper)

    workflow = read(joinpath(_ROOT, "scripts", "workflows", "run_experiment.jl"), String)
    @test count("render_experiment_completion_summary", workflow) >= 2
    @test occursin("--objectives", workflow)
    @test occursin("--validate-objectives", workflow)
    @test occursin("--variables", workflow)
    @test occursin("--validate-variables", workflow)
    @test occursin("--control-layout", workflow)
    @test occursin("--artifact-plan", workflow)
    @test occursin("--latest", workflow)
    @test occursin("--compute-plan", workflow)

    optimize_workflow = read(joinpath(_ROOT, "scripts", "workflows", "optimize_raman.jl"), String)
    @test occursin("artifact_validation", optimize_workflow)
end
