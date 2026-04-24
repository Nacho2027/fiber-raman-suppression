include(joinpath(_ROOT, "scripts", "lib", "experiment_spec.jl"))
include(joinpath(_ROOT, "scripts", "lib", "experiment_runner.jl"))

@testset "Experiment front layer" begin
    @test "research_engine_poc" in approved_experiment_config_ids()
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
    caps = validate_experiment_spec(spec)
    @test (:phase,) in caps.variables

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

    rendered_mv = render_experiment_plan(mv_spec)
    @test occursin("Execution: mode=multivar", rendered_mv)
    @test occursin("export_supported=false", rendered_mv)

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

    wrapper = read(joinpath(_ROOT, "scripts", "canonical", "run_experiment.jl"), String)
    @test occursin("workflows\", \"run_experiment.jl", wrapper)
    @test occursin("run_experiment_main(ARGS)", wrapper)
end
