include(joinpath(_ROOT, "scripts", "lib", "experiment_spec.jl"))
include(joinpath(_ROOT, "scripts", "lib", "experiment_runner.jl"))

@testset "Experiment front layer" begin
    @test "research_engine_poc" in approved_experiment_config_ids()
    @test "research_engine_smoke" in approved_experiment_config_ids()
    @test "research_engine_export_smoke" in approved_experiment_config_ids()
    @test "research_engine_peak_smoke" in approved_experiment_config_ids()
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
    @test occursin("Registered objective contracts", objective_listing)
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

    wrapper = read(joinpath(_ROOT, "scripts", "canonical", "run_experiment.jl"), String)
    @test occursin("workflows\", \"run_experiment.jl", wrapper)
    @test occursin("run_experiment_main(ARGS)", wrapper)

    workflow = read(joinpath(_ROOT, "scripts", "workflows", "run_experiment.jl"), String)
    @test count("render_experiment_completion_summary", workflow) >= 2
    @test occursin("--objectives", workflow)

    optimize_workflow = read(joinpath(_ROOT, "scripts", "workflows", "optimize_raman.jl"), String)
    @test occursin("artifact_validation", optimize_workflow)
end
