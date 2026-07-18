using JSON3

include(joinpath(_ROOT, "scripts", "lib", "experiment_spec.jl"))
include(joinpath(_ROOT, "scripts", "lib", "experiment_sweep.jl"))
include(joinpath(_ROOT, "scripts", "lib", "experiment_runner.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "run_experiment.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "lab_ready.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "scaffold_objective.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "scaffold_variable.jl"))

if !(@isdefined _write_valid_test_png)
    function _write_valid_test_png(path::AbstractString)
        pixels = zeros(Float64, 8, 8)
        pixels[3:6, 3:6] .= 1.0
        FiberLab.PyPlot.imsave(path, pixels; cmap="viridis")
        return path
    end
end

@testset "Experiment front layer" begin
    listed_configs = sprint(io -> _print_available_experiment_configs(; io=io))
    for config_id in approved_experiment_config_ids()
        spec = load_experiment_spec(config_id)
        @test experiment_cli_spec_hint(spec) == config_id
        @test load_experiment_spec(experiment_cli_spec_hint(spec)).config_path == spec.config_path
        @test occursin("  $(config_id)  —", listed_configs)
    end
    @test_throws ErrorException run_experiment_main(String[])
    legacy_message = try
        load_experiment_spec("smf28_L2m_P0p2W")
        ""
    catch err
        sprint(showerror, err)
    end
    @test occursin("migration: use maintained config `research_engine_poc`", legacy_message)
    @test "research_engine_poc" in approved_experiment_config_ids()
    @test "research_engine_smoke" in approved_experiment_config_ids()
    @test "research_engine_export_smoke" in approved_experiment_config_ids()
    @test "research_engine_peak_smoke" in approved_experiment_config_ids()
    @test "grin50_mmf_phase_sum_poc" in approved_experiment_config_ids()
    @test "smf28_longfiber_phase_poc" in approved_experiment_config_ids()
    @test "smf28_phase_amplitude_energy_poc" in approved_experiment_config_ids()
    @test "smf28_amp_on_phase_refinement_poc" in approved_experiment_config_ids()
    @test "research_engine_gain_tilt_scalar_search_smoke" in approved_experiment_config_ids()
    @test "research_engine_temporal_peak_scalar_smoke" in approved_experiment_config_ids()
    @test "research_engine_temporal_peak_quadratic_phase_smoke" in approved_experiment_config_ids()

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
    grid_resolution = resolve_experiment_grid(spec)
    @test grid_resolution.requested == Grid(
        nt = 8192, time_window_ps = 12.0, policy = :auto_if_undersized)
    @test grid_resolution.resolved == Grid(
        nt = 8192, time_window_ps = 27.0, policy = :exact)
    @test occursin("resolved Nt=8192 tw=27.0ps", render_experiment_plan(spec))
    undersized_spec = merge(spec, (problem=merge(spec.problem, (Nt=1024,)),))
    @test resolve_experiment_grid(undersized_spec).resolved.nt == 4096
    @test control_layout_plan(undersized_spec).total_length == "4096"
    @test occursin("optimizer_length=4096", render_experiment_plan(undersized_spec))
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
    @test variable_extension_report.promotable >= 3
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
    @test !(:flat in band_contract.allowed_regularizers)
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
    @test (:phase,) in peak_contract.supported_variables
    @test (:reduced_phase,) in peak_contract.supported_variables
    @test peak_contract.allowed_regularizers == (:gdd, :boundary)
    for (kind, regime) in (
        (:raman_band, :single_mode),
        (:raman_peak, :single_mode),
        (:temporal_width, :single_mode),
        (:mmf_sum, :multimode),
        (:mmf_fundamental, :multimode),
        (:mmf_worst_mode, :multimode),
    )
        @test objective_contract(kind, regime).artifact_hooks ==
              FiberLab.objective_contract(kind).figure_hooks
    end
    for kind in (:phase, :reduced_phase, :amplitude, :energy, :gain_tilt)
        @test variable_contract(kind, :single_mode).artifact_hooks ==
              FiberLab.control_contract(kind).figure_hooks
    end
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
    @test objective_extension_report.promotable >= 1
    pulse_extension_row = only(filter(row -> row.kind == :pulse_compression_planning, objective_extension_report.rows))
    @test pulse_extension_row.valid
    @test !pulse_extension_row.promotable
    @test "execution_planning_only" in pulse_extension_row.blockers
    @test isempty(pulse_extension_row.errors)
    scalar_extension_row = only(filter(row -> row.kind == :temporal_peak_scalar, objective_extension_report.rows))
    @test scalar_extension_row.valid
    @test scalar_extension_row.promotable
    @test :temporal_peak_scalar in registered_objective_kinds(:single_mode)
    scalar_contract = objective_contract(:temporal_peak_scalar, :single_mode)
    @test scalar_contract.backend == :scalar_extension
    @test (:gain_tilt,) in scalar_contract.supported_variables
    @test (:quadratic_phase,) in scalar_contract.supported_variables
    rendered_objective_extension_report = sprint(io -> render_objective_extension_validation_report(objective_extension_report; io=io))
    @test occursin("Objective extension validation", rendered_objective_extension_report)
    @test occursin("pulse_compression_planning", rendered_objective_extension_report)
    @test occursin("temporal_peak_scalar", rendered_objective_extension_report)
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

    supported_check = research_config_check_report("research_engine_smoke")
    @test supported_check.pass
    @test supported_check.run_path == :run
    @test supported_check.compare_ready
    rendered_supported_check = sprint(io -> render_research_config_check(supported_check; io=io))
    @test occursin("Research Config Check", rendered_supported_check)
    @test occursin("Run path: `./fiberlab run research_engine_smoke`", rendered_supported_check)
    @test occursin("Missing pieces: `none`", rendered_supported_check)
    cli_supported_check = run_experiment_main(["--check", "research_engine_smoke"])
    @test cli_supported_check.pass

    gain_tilt_check = research_config_check_report("research_engine_gain_tilt_smoke")
    @test !gain_tilt_check.pass
    @test gain_tilt_check.run_path == :explore_local_smoke
    @test :experimental_maturity in gain_tilt_check.missing
    @test :no_export_handoff in gain_tilt_check.missing
    rendered_gain_tilt_check = sprint(io -> render_research_config_check(gain_tilt_check; io=io))
    @test occursin("Run path: `./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke`", rendered_gain_tilt_check)
    @test occursin("Compare-ready metadata: `false`", rendered_gain_tilt_check)
    @test_throws ErrorException run_experiment_main(["research_engine_gain_tilt_smoke"])

    scalar_search_spec = load_experiment_spec("research_engine_gain_tilt_scalar_search_smoke")
    @test scalar_search_spec.id == "smf28_gain_tilt_scalar_search_smoke"
    @test scalar_search_spec.controls.variables == (:gain_tilt,)
    @test scalar_search_spec.solver.kind == :bounded_scalar
    @test scalar_search_spec.solver.scalar_lower == -0.09
    @test scalar_search_spec.solver.scalar_upper == 0.09
    @test scalar_search_spec.plots.temporal_pulse.time_range == (-0.75, 0.75)
    @test scalar_search_spec.plots.temporal_pulse.normalize
    @test scalar_search_spec.plots.spectrum.dynamic_range_dB == 55.0
    @test experiment_execution_mode(scalar_search_spec) == :scalar_search
    @test validate_experiment_spec(scalar_search_spec) isa NamedTuple
    @test (:gain_tilt,) in objective_contract(:raman_band, :single_mode).supported_variables
    @test (:gain_tilt,) in validate_experiment_spec(scalar_search_spec).variables
    scalar_search_kwargs = supported_experiment_run_kwargs(scalar_search_spec)
    @test scalar_search_kwargs.variables == (:gain_tilt,)
    @test scalar_search_kwargs.scalar_lower == -0.09
    @test scalar_search_kwargs.scalar_upper == 0.09
    @test scalar_search_kwargs.δ_bound == 0.10
    scalar_search_plan = experiment_artifact_plan(scalar_search_spec)
    scalar_search_hooks = Tuple(request.hook for request in scalar_search_plan.hooks)
    @test :gain_tilt_profile in scalar_search_hooks
    @test :exploratory_summary in scalar_search_hooks
    @test scalar_search_plan.implemented
    rendered_scalar_search = render_experiment_plan(scalar_search_spec)
    @test occursin("Execution: mode=scalar_search", rendered_scalar_search)
    @test occursin("Solver: kind=bounded_scalar", rendered_scalar_search)

    quadratic_scalar_spec = load_experiment_spec("research_engine_temporal_peak_quadratic_phase_smoke")
    @test quadratic_scalar_spec.id == "smf28_temporal_peak_quadratic_phase_smoke"
    @test quadratic_scalar_spec.objective.kind == :temporal_peak_scalar
    @test quadratic_scalar_spec.controls.variables == (:quadratic_phase,)
    @test quadratic_scalar_spec.solver.kind == :bounded_scalar
    @test quadratic_scalar_spec.solver.scalar_lower == -4.0
    @test quadratic_scalar_spec.solver.scalar_upper == 4.0
    @test experiment_execution_mode(quadratic_scalar_spec) == :scalar_search
    @test validate_experiment_spec(quadratic_scalar_spec) isa NamedTuple
    @test (:quadratic_phase,) in validate_experiment_spec(quadratic_scalar_spec).variables
    quadratic_kwargs = supported_experiment_run_kwargs(quadratic_scalar_spec)
    @test quadratic_kwargs.variables == (:quadratic_phase,)
    @test quadratic_kwargs.objective_kind == :temporal_peak_scalar
    rendered_quadratic_scalar = render_experiment_plan(quadratic_scalar_spec)
    @test occursin("Execution: mode=scalar_search", rendered_quadratic_scalar)
    @test occursin("variables=[:quadratic_phase]", rendered_quadratic_scalar)

    mmf_check = research_config_check_report("grin50_mmf_phase_sum_poc")
    @test !mmf_check.pass
    @test mmf_check.run_path == :explore_heavy_dry_run
    @test :requires_dedicated_workflow in mmf_check.missing
    @test mmf_check.artifact_plan_implemented
    @test !(:artifact_plan_not_implemented in mmf_check.missing)
    rendered_mmf_check = sprint(io -> render_research_config_check(mmf_check; io=io))
    @test occursin("Run path: `./fiberlab explore run grin50_mmf_phase_sum_poc --heavy-ok --dry-run`", rendered_mmf_check)

    exploratory_spec = load_experiment_spec("research_engine_gain_tilt_smoke")
    exploratory_plan = experiment_artifact_plan(exploratory_spec)
    exploratory_hooks = Tuple(request.hook for request in exploratory_plan.hooks)
    @test :exploratory_summary in exploratory_hooks
    @test :exploratory_overview in exploratory_hooks
    rendered_exploratory_plan = sprint(io -> render_experiment_artifact_plan(exploratory_spec; io=io))
    @test occursin("exploratory_summary", rendered_exploratory_plan)
    @test occursin("plots.explore", rendered_exploratory_plan)

    generic_dir = mktempdir()
    generic_spec = load_experiment_spec("research_engine_temporal_width_smoke")
    Nt_generic = 32
    generic_uω0 = reshape(ComplexF64.(range(1.0, stop=2.0, length=Nt_generic)), Nt_generic, 1)
    generic_phi = reshape(collect(range(-0.2, stop=0.2, length=Nt_generic)), Nt_generic, 1)
    generic_bundle = (
        spec = generic_spec,
        output_dir = generic_dir,
        save_prefix = joinpath(generic_dir, "opt"),
        artifact_path = joinpath(generic_dir, "opt_result.jld2"),
        result = (
            phi_opt = generic_phi,
            convergence_history = [-12.0, -18.0, -21.0],
            J_before = 1e-2,
            J_after = 1e-4,
            iterations = 3,
        ),
        uω0 = generic_uω0,
        sim = Dict{String,Any}("Nt" => Nt_generic, "M" => 1, "Δt" => 0.01, "f0" => 193.4),
    )
    generic_artifacts = write_exploratory_artifacts(generic_spec, generic_bundle)
    @test generic_artifacts.complete
    @test isfile(generic_artifacts.paths[:exploratory_summary])
    @test isfile(generic_artifacts.paths[:exploratory_overview])
    generic_summary = JSON3.read(read(generic_artifacts.paths[:exploratory_summary], String))
    @test generic_summary.schema_version == "exploratory_artifacts_v1"
    @test generic_summary.config.id == "smf28_phase_temporal_width_smoke"
    @test "phase" in collect(generic_summary.controls.variables)
    @test generic_summary.objective.kind == "temporal_width"
    @test generic_summary.problem.requested_grid.nt == generic_spec.problem.Nt
    @test generic_summary.problem.resolved_grid.nt == Nt_generic
    @test generic_summary.problem.resolved_grid.source == "runtime_sim"
    @test generic_summary.zoom.time_window_samples >= 1
    override_dir = mktempdir()
    override_spec = load_experiment_spec("research_engine_gain_tilt_scalar_search_smoke")
    override_t = collect(range(-1.0, stop=1.0, length=Nt_generic))
    override_temporal = reshape(ComplexF64.(exp.(-(override_t ./ 0.12) .^ 2)), Nt_generic, 1)
    override_bundle = (
        spec = override_spec,
        output_dir = override_dir,
        save_prefix = joinpath(override_dir, "opt"),
        artifact_path = joinpath(override_dir, "opt_result.jld2"),
        result = (
            phi_opt = zeros(Nt_generic, 1),
            convergence_history = [-12.0, -13.0],
            J_before = 1e-2,
            J_after = 1e-3,
            iterations = 2,
        ),
        uω0 = ifft(override_temporal, 1),
        sim = Dict{String,Any}("Nt" => Nt_generic, "M" => 1, "Δt" => 2.0 / (Nt_generic - 1), "f0" => 193.4),
    )
    override_artifacts = write_exploratory_artifacts(override_spec, override_bundle)
    override_summary = JSON3.read(read(override_artifacts.paths[:exploratory_summary], String))
    @test override_summary.zoom.source == "config_time_range"
    @test override_summary.zoom.time_range == [-0.75, 0.75]
    @test override_summary.plots.temporal_pulse.normalize == true
    @test override_summary.plots.spectrum.dynamic_range_dB == 55.0
    centered_temporal = zeros(ComplexF64, Nt_generic, 1)
    centered_temporal[Nt_generic ÷ 2 + 3] = 1.0
    centered_spectrum = ifft(centered_temporal, 1)
    centered_power = _explore_temporal_power(centered_spectrum)
    @test argmax(centered_power) == Nt_generic ÷ 2 + 3
    @test _explore_axis(Dict("Nt" => 8, "Δt" => 0.25), 8) ==
        [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75]
    explicit_times = collect(-4:3) .* 1e-12
    @test _explore_axis(Dict("ts" => explicit_times, "Δt" => 99.0), 8) ≈
        collect(-4:3)

    manifest_dir = mktempdir()
    manifest_artifact = joinpath(manifest_dir, "opt_result.jld2")
    manifest_config = joinpath(manifest_dir, "run_config.toml")
    write(manifest_artifact, "placeholder")
    write(manifest_config, "placeholder")
    provenance_sim = FiberLab.get_disp_sim_params(1550e-9, 1, 8, 2.0, 2)
    provenance_fiber = FiberLab.get_disp_fiber_params_user_defined(
        1.0,
        provenance_sim;
        fR = 0.27,
        gamma_user = 1.0e-3,
        betas_user = [-2.6e-26],
    )
    manifest_bundle = (
        spec = load_experiment_spec("research_engine_gain_tilt_smoke"),
        fiber = provenance_fiber,
        output_dir = manifest_dir,
        save_prefix = joinpath(manifest_dir, "opt"),
        config_copy = manifest_config,
        artifact_path = manifest_artifact,
        sidecar_path = joinpath(manifest_dir, "opt_result.json"),
        artifact_validation = (
            complete = true,
            checked = String[manifest_artifact, manifest_config],
            missing = String[],
            standard_images = (complete = true, present = String["_phase_profile.png"], missing = String[]),
            extra_artifacts = (complete = true, hooks = (:gain_tilt_profile,), checked = String[], missing = String[]),
        ),
    )
    manifest_data = experiment_run_manifest_data(
        manifest_bundle;
        run_context=:explore_local_smoke,
        run_command="./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke",
    )
    @test manifest_data["schema_version"] == "run_manifest_v1"
    @test manifest_data["run_context"] == "explore_local_smoke"
    @test manifest_data["config"]["id"] == "smf28_phase_gain_tilt_smoke"
    @test manifest_data["problem"]["requested_grid"]["time_window_ps"] ==
          manifest_bundle.spec.problem.time_window
    @test manifest_data["problem"]["resolved_grid"]["time_window_ps"] == 5.0
    @test manifest_data["problem"]["Nt"] ==
          manifest_data["problem"]["resolved_grid"]["nt"]
    @test manifest_data["problem"]["raman_fraction_override"] === nothing
    @test manifest_data["problem"]["raman_fraction_resolved"] == 0.27
    manifest_response = manifest_data["problem"]["raman_response"]
    @test manifest_response == Dict{String,Any}(
        "requested_fraction" => nothing,
        "resolved_fraction" => 0.27,
        "model" => "blow_wood_single_damped_oscillator_v1",
        "tau1_fs" => 12.2,
        "tau2_fs" => 32.0,
    )
    @test !haskey(manifest_response, "one_m_fR")
    @test manifest_data["artifacts"]["complete"] == true
    @test manifest_data["pre_run_check"]["compare_ready"] == false
    manifest_path = write_experiment_run_manifest(
        manifest_bundle;
        run_context=:explore_local_smoke,
        run_command="./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke",
    )
    @test basename(manifest_path) == "run_manifest.json"
    @test isfile(manifest_path)
    parsed_manifest = JSON3.read(read(manifest_path, String))
    @test parsed_manifest.schema_version == "run_manifest_v1"
    @test parsed_manifest.config.id == "smf28_phase_gain_tilt_smoke"
    @test parsed_manifest.problem.raman_response.resolved_fraction == 0.27
    @test !haskey(parsed_manifest.problem.raman_response, :one_m_fR)

    canonical_payload = build_raman_result_payload(;
        run_meta = (
            fiber_name = "unit-test",
            P_cont_W = 0.1,
            lambda0_nm = 1550.0,
            fwhm_fs = 185.0,
        ),
        run_tag = "provenance-test",
        fiber = provenance_fiber,
        sim = provenance_sim,
        Nt = 8,
        time_window_ps = 2.0,
        J_before = 0.2,
        J_after = 0.1,
        delta_J_dB = -3.0,
        grad_norm = 0.01,
        converged = true,
        iterations = 1,
        wall_time_s = 0.1,
        convergence_history = [0.2, 0.1],
        phi_opt = zeros(8),
        uω0 = zeros(ComplexF64, 8, 1),
        E_conservation = 0.0,
        bc_input_frac = 0.0,
        bc_output_frac = 0.0,
        bc_input_ok = true,
        bc_output_ok = true,
        trust_report = Dict{String,Any}(),
        trust_report_md = "trust.md",
        band_mask = falses(8),
        raman_response = raman_response_identity(0.27, provenance_fiber),
    )
    canonical_jld2 = joinpath(manifest_dir, "canonical_result.jld2")
    canonical_sidecar = FiberLab.save_run(canonical_jld2, canonical_payload)
    canonical_stored = JLD2.load(canonical_jld2)
    @test canonical_stored["raman_response"]["requested_fraction"] == 0.27
    @test canonical_stored["raman_response"]["resolved_fraction"] == 0.27
    @test !haskey(canonical_stored["raman_response"], "one_m_fR")
    canonical_json = JSON3.read(read(canonical_sidecar, String))
    @test canonical_json.raman_response.model ==
          "blow_wood_single_damped_oscillator_v1"
    @test canonical_json.raman_response.tau1_fs == 12.2
    @test canonical_json.raman_response.tau2_fs == 32.0
    @test !haskey(canonical_json.raman_response, :one_m_fR)

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
    @test validation_report.total == length(experiment_config_validation_targets())
    @test Set(("templates/single_mode_phase_template",
               "templates/multimode_phase_planning_template")) ⊆
          Set(experiment_config_validation_targets())
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
    @test smoke_kwargs.store_trace == smoke_spec.solver.store_trace
    no_trace_spec = (; smoke_spec..., solver=(; smoke_spec.solver..., store_trace=false))
    @test !supported_experiment_run_kwargs(no_trace_spec).store_trace

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
    @test long_spec.verification.mode == :high_resource
    @test experiment_execution_mode(long_spec) == :long_fiber_phase
    @test experiment_objective_contract(long_spec).regime == :long_fiber
    @test (:phase,) in validate_experiment_spec(long_spec).variables
    @test experiment_artifact_plan(long_spec).implemented
    rendered_long = render_experiment_plan(long_spec)
    @test occursin("Execution: mode=long_fiber_phase", rendered_long)
    @test occursin("high_resource=true", rendered_long)
    @test occursin("regime=long_fiber", rendered_long)
    long_compute_plan = render_experiment_compute_plan(long_spec)
    @test occursin("Compute plan: smf28_longfiber_phase_poc", long_compute_plan)
    @test occursin("Provider-neutral path", long_compute_plan)
    @test occursin("No command in this plan is launched automatically", long_compute_plan)
    @test occursin("./fiberlab run --heavy-ok", long_compute_plan)
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
    @test mmf_spec.verification.mode == :high_resource
    @test experiment_execution_mode(mmf_spec) == :multimode_phase
    @test experiment_objective_contract(mmf_spec).regime == :multimode
    @test (:phase,) in validate_experiment_spec(mmf_spec).variables
    @test experiment_artifact_plan(mmf_spec).implemented
    @test :standard_image_set in
          Tuple(request.hook for request in experiment_artifact_plan(mmf_spec).hooks)
    fake_cost_report = (
        sum_lin=0.1, sum_dB=-10.0,
        fundamental_lin=0.2, fundamental_dB=-6.9897,
        worst_mode_lin=0.3, worst_mode_dB=-5.2288,
        worst_mode_smooth_proxy_lin=0.29,
        worst_mode_smooth_proxy_dB=-5.376,
    )
    @test _mmf_primary_metrics(fake_cost_report, :sum).linear == 0.1
    @test _mmf_primary_metrics(fake_cost_report, :fundamental).linear == 0.2
    @test _mmf_primary_metrics(fake_cost_report, :worst_mode).linear == 0.3
    mmf_band = Bool[true, true, false, false]
    zero_leakage_field = ComplexF64[
        0 0 0;
        0 0 0;
        1 2 0;
        0 0 0
    ]
    zero_proxy, _ = mmf_cost_worst_mode(zero_leakage_field, mmf_band)
    zero_report = mmf_cost_report(zero_leakage_field, mmf_band)
    @test zero_proxy == 0.0
    @test zero_report.worst_mode_lin == 0.0

    unit_leakage_field = ComplexF64[
        1 0 0;
        0 0 0;
        0 0 0;
        0 0 0
    ]
    unit_proxy, unit_gradient = mmf_cost_worst_mode(unit_leakage_field, mmf_band)
    unit_report = mmf_cost_report(unit_leakage_field, mmf_band)
    @test unit_proxy == 1.0
    @test unit_report.worst_mode_lin == 1.0
    @test isnan(unit_report.per_mode_lin[2])
    @test isnan(unit_report.per_mode_dB[2])
    @test all(iszero, unit_gradient[:, 2:3])

    inactive_fundamental_field = ComplexF64[
        0 0;
        0 0;
        0 1;
        0 0
    ]
    inactive_fundamental_report = mmf_cost_report(
        inactive_fundamental_field, mmf_band)
    @test inactive_fundamental_report.sum_lin == 0.0
    @test inactive_fundamental_report.worst_mode_lin == 0.0
    @test isnan(inactive_fundamental_report.fundamental_lin)
    @test_throws ArgumentError _mmf_primary_metrics(
        inactive_fundamental_report, :fundamental)
    @test maximum(abs, _mmf_gauge_fix_phase(
        3 .* 2π .* FFTW.fftfreq(16, 1.0))) < 1e-12

    mixed_leakage_field = ComplexF64[
        1 0 0;
        0 0 0;
        0 1 0;
        0 0 0
    ]
    mixed_proxy, mixed_gradient = mmf_cost_worst_mode(
        mixed_leakage_field, mmf_band; τ=50.0)
    mixed_report = mmf_cost_report(mixed_leakage_field, mmf_band; τ=50.0)
    @test 1 - log(2) / 50 <= mixed_proxy <= 1
    @test mixed_report.worst_mode_lin == 1.0
    @test mixed_report.worst_mode_smooth_proxy_lin == mixed_proxy
    @test mixed_report.active_mode_count == 2
    @test _mmf_primary_metrics(mixed_report, :worst_mode).linear == 1.0
    @test _mmf_standard_mode_views(mixed_report, unit_report, :sum) == (:sum, :sum)
    @test _mmf_standard_mode_views(mixed_report, unit_report, :fundamental) == (1, 1)
    @test _mmf_standard_mode_views(mixed_report, unit_report, :worst_mode) == (1, 1)
    switching_before = (per_mode_lin = [0.1, 0.9, NaN],)
    switching_after = (per_mode_lin = [0.2, 0.3, 0.8],)
    @test _mmf_standard_mode_views(
        switching_before, switching_after, :worst_mode) == (2, 3)
    @test all(iszero, mixed_gradient[:, 3])
    @test _safe_mmf_iterations((result=nothing,)) == 0
    rendered_mmf = render_experiment_plan(mmf_spec)
    @test occursin("Execution: mode=multimode_phase", rendered_mmf)
    @test occursin("high_resource=true", rendered_mmf)
    @test occursin("regime=multimode", rendered_mmf)
    mmf_layout = control_layout_plan(mmf_spec)
    @test mmf_layout.total_length == "phase=resolved_Nt"
    @test mmf_layout.dimension_authority == :runtime_modal
    @test only(mmf_layout.blocks).shape == "resolved_Nt shared across modes"
    @test occursin("optimizer_length=phase=resolved_Nt", rendered_mmf)
    mmf_sampling_request = merge(
        mmf_spec,
        (problem=merge(mmf_spec.problem, (Nt=8192, time_window=10.0)),),
    )
    mmf_sampling_grid = resolve_experiment_grid(mmf_sampling_request)
    @test mmf_sampling_grid.requested == Grid(
        nt=8192, time_window_ps=10.0, policy=:auto_if_undersized)
    @test mmf_sampling_grid.initial.nt == 8192
    @test mmf_sampling_grid.initial.time_window_ps > 10.0
    @test ismissing(mmf_sampling_grid.resolved)
    @test validate_experiment_spec(mmf_sampling_request) isa NamedTuple
    mmf_exact_spec = merge(
        mmf_spec,
        (problem=merge(mmf_spec.problem, (grid_policy=:exact,)),),
    )
    mmf_exact_grid = resolve_experiment_grid(mmf_exact_spec)
    @test mmf_exact_grid.resolved == mmf_exact_grid.initial
    @test mmf_exact_grid.authority == :user_exact
    @test control_layout_plan(mmf_exact_spec).total_length == "4096"
    mmf_preset = get_mmf_fiber_preset(:GRIN_50)
    cache_sim = FiberLab.get_disp_sim_params(1550e-9, mmf_preset.M, 16, 5.0,
                                             mmf_preset.β_order)
    cache_path = _mmf_modal_cache_path("cache", :GRIN_50, mmf_preset, cache_sim)
    changed_wavelength_sim = FiberLab.get_disp_sim_params(
        1540e-9, mmf_preset.M, 16, 5.0, mmf_preset.β_order)
    @test cache_path != _mmf_modal_cache_path(
        "cache", :GRIN_50, mmf_preset, changed_wavelength_sim)
    @test cache_path != _mmf_modal_cache_path(
        "cache", :GRIN_50, merge(mmf_preset, (nx=mmf_preset.nx + 2,)), cache_sim)
    mmf_compute_plan = render_experiment_compute_plan(mmf_spec)
    @test occursin("Compute plan: grin50_mmf_phase_sum_poc", mmf_compute_plan)
    @test occursin("Provider-neutral path", mmf_compute_plan)
    @test occursin("./fiberlab run --heavy-ok", mmf_compute_plan)
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
    @test occursin("./fiberlab run research_engine_poc", local_compute_plan)

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
        _write_valid_test_png(string(save_prefix, suffix))
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

    corrupt_standard_image = string(save_prefix, first(REQUIRED_STANDARD_IMAGE_SUFFIXES))
    write(corrupt_standard_image, "not a png")
    invalid_artifact_report = validate_experiment_artifacts(
        fake_bundle; throw_on_error=false)
    @test !invalid_artifact_report.complete
    @test corrupt_standard_image in invalid_artifact_report.checked
    @test corrupt_standard_image in invalid_artifact_report.missing
    @test first(REQUIRED_STANDARD_IMAGE_SUFFIXES) in
          invalid_artifact_report.standard_images.invalid
    _write_valid_test_png(corrupt_standard_image)

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
    mv_exploratory_artifacts = write_exploratory_artifacts(mv_spec, artifact_bundle)
    @test mv_exploratory_artifacts.complete
    @test isfile(mv_exploratory_artifacts.paths[:exploratory_summary])
    @test isfile(mv_exploratory_artifacts.paths[:exploratory_overview])
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
        _write_valid_test_png(string(artifact_prefix, suffix))
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
    @test :exploratory_summary in mv_artifact_report.extra_artifacts.hooks
    @test :exploratory_overview in mv_artifact_report.extra_artifacts.hooks
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

    phase_with_amplitude_penalty = (
        spec...,
        objective = (
            spec.objective...,
            regularizers = Dict{Symbol,Any}(:tikhonov => 1.0),
        ),
    )
    @test_throws ArgumentError validate_experiment_spec(phase_with_amplitude_penalty)

    multivar_with_amplitude_penalties = (
        mv_spec...,
        objective = (
            mv_spec.objective...,
            regularizers = Dict{Symbol,Any}(:tikhonov => 0.2, :tv => 0.1),
        ),
    )
    @test validate_experiment_spec(multivar_with_amplitude_penalties) isa NamedTuple

    energy_without_amplitude = (
        mv_spec...,
        controls = (mv_spec.controls..., variables = (:phase, :energy)),
        objective = (
            mv_spec.objective...,
            regularizers = Dict{Symbol,Any}(:energy => 1.0),
        ),
    )
    @test validate_experiment_spec(energy_without_amplitude) isa NamedTuple

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

    long_not_high_resource = (
        long_spec...,
        verification = (long_spec.verification..., mode = :standard),
    )
    @test_throws ArgumentError validate_experiment_spec(long_not_high_resource)

    mmf_export = (
        mmf_spec...,
        export_plan = (mmf_spec.export_plan..., enabled = true),
    )
    @test_throws ArgumentError validate_experiment_spec(mmf_export)

    mmf_not_high_resource = (
        mmf_spec...,
        verification = (mmf_spec.verification..., mode = :standard),
    )
    @test validate_experiment_spec(mmf_not_high_resource) isa NamedTuple

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

    empty_latest_config = joinpath(mktempdir(), "empty_latest.toml")
    empty_latest_text = replace(
        read(spec.config_path, String),
        "output_root = \"results/raman\"" =>
            "output_root = \"$(replace(mktempdir(), "\\" => "\\\\"))\"",
    )
    write(empty_latest_config, empty_latest_text)
    @test_throws ArgumentError run_experiment_main(["--latest", empty_latest_config])

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

end
