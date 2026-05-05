using Test
using FiberLab

include(joinpath(_ROOT, "scripts", "lib", "experiment_runner.jl"))
include(joinpath(_ROOT, "scripts", "lib", "results_index.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "run_experiment.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "export_run.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "lab_ready.jl"))

function _acceptance_payload()
    return (
        fiber_name = "SMF-28",
        run_tag = "acceptance",
        L_m = 0.05,
        P_cont_W = 0.001,
        lambda0_nm = 1550.0,
        fwhm_fs = 185.0,
        gamma = 1.1e-3,
        betas = [-2.17e-26, 1.2e-40],
        Nt = 16,
        time_window_ps = 1.0,
        J_before = 1e-2,
        J_after = 1e-4,
        delta_J_dB = FiberLab.lin_to_dB(1e-4) - FiberLab.lin_to_dB(1e-2),
        grad_norm = 1e-6,
        converged = true,
        iterations = 1,
        wall_time_s = 0.01,
        convergence_history = [-20.0, -40.0],
        phi_opt = reshape(collect(range(-0.05, stop=0.05, length=16)), 16, 1),
        uω0 = ones(ComplexF64, 16, 1),
        E_conservation = 0.0,
        bc_input_frac = 1e-8,
        bc_output_frac = 1e-8,
        bc_input_ok = true,
        bc_output_ok = true,
        trust_report = Dict("overall_verdict" => "PASS"),
        trust_report_md = "opt_trust.md",
        band_mask = trues(16),
        sim_Dt = 0.01,
        sim_omega0 = 2π * 193.4,
    )
end

function _write_standard_image_placeholders(prefix::AbstractString)
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        write(string(prefix, suffix), "")
    end
end

@testset "Research engine acceptance harness" begin
    validation_report = validate_all_experiment_configs()
    @test validation_report.complete
    @test validation_report.total >= 7

    supported_spec = load_experiment_spec("research_engine_export_smoke")
    @test supported_spec.maturity == "supported"
    @test experiment_execution_mode(supported_spec) == :phase_only
    @test lab_ready_config_report("research_engine_export_smoke").pass
    @test run_experiment_main(["--dry-run", "research_engine_export_smoke"]).id == supported_spec.id
    @test run_experiment_main(["--control-layout", "research_engine_export_smoke"]).total_length == string(supported_spec.problem.Nt)
    @test run_experiment_main(["--artifact-plan", "research_engine_export_smoke"]).implemented

    mktempdir() do tmp
        run_dir = joinpath(tmp, "smf28_phase_export_smoke_acceptance")
        mkpath(run_dir)
        save_prefix = joinpath(run_dir, "opt")
        artifact_path = string(save_prefix, "_result.jld2")
        config_copy = joinpath(run_dir, "run_config.toml")

        FiberLab.save_run(artifact_path, _acceptance_payload())
        cp(supported_spec.config_path, config_copy; force=true)
        write(string(save_prefix, "_trust.md"), "# trust\n\nPASS\n")
        _write_standard_image_placeholders(save_prefix)

        exported = export_run_bundle(run_dir, joinpath(run_dir, "export_handoff"))
        export_report = validate_experiment_export_bundle(supported_spec, exported)
        @test export_report.complete

        run_bundle = (
            spec = supported_spec,
            output_dir = run_dir,
            save_prefix = save_prefix,
            config_copy = config_copy,
            artifact_path = artifact_path,
        )
        artifact_report = validate_experiment_artifacts(run_bundle)
        @test artifact_report.complete
        @test artifact_report.standard_images.complete

        run_gate = lab_ready_run_report(run_dir; require_export=true)
        @test run_gate.pass
        @test run_gate.export_handoff_complete

        index = build_results_index([tmp])
        @test index.total == 1
        row = only(index.rows)
        @test row.lab_ready
        @test row.export_handoff_complete
        @test row.config_id == supported_spec.id
        @test row.standard_images_complete
        @test row.trust_report_present

        rendered_index = render_results_index(index)
        @test occursin("Results Index", rendered_index)
        @test occursin(supported_spec.id, rendered_index)

        comparison = compare_results_index(index; lab_ready_only=true, export_ready_only=true)
        @test comparison.total == 1
        @test only(comparison.rows).path == artifact_path
    end

    for spec_id in ("smf28_phase_amplitude_energy_poc",)
        spec = load_experiment_spec(spec_id)
        @test spec.maturity == "experimental"
        @test validate_experiment_spec(spec) isa NamedTuple
        @test run_experiment_main(["--dry-run", spec_id]).id == spec.id
        @test run_experiment_main(["--compute-plan", spec_id]).id == spec.id
        @test lab_ready_config_report(spec_id).pass
    end

    for spec_id in ("smf28_longfiber_phase_poc", "grin50_mmf_phase_sum_poc")
        spec = load_experiment_spec(spec_id)
        @test spec.maturity == "experimental"
        @test validate_experiment_spec(spec) isa NamedTuple
        @test run_experiment_main(["--dry-run", spec_id]).id == spec.id
        @test run_experiment_main(["--compute-plan", spec_id]).id == spec.id
        config_gate = lab_ready_config_report(spec_id)
        @test !config_gate.pass
        @test "planning_only_execution_mode" in config_gate.blockers
    end

    @test experiment_execution_mode(load_experiment_spec("smf28_phase_amplitude_energy_poc")) == :multivar
    @test experiment_artifact_plan(load_experiment_spec("smf28_phase_amplitude_energy_poc")).implemented
    @test_throws ErrorException run_experiment_main(["smf28_longfiber_phase_poc"])
    @test_throws ErrorException run_experiment_main(["grin50_mmf_phase_sum_poc"])
end
