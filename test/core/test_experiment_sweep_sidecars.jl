using JSON3

include(joinpath(_ROOT, "scripts", "lib", "experiment_sweep.jl"))

@testset "Experiment sweep sidecars" begin
    sweep_spec = load_experiment_sweep_spec("smf28_power_micro_sweep")
    fake_results = (
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

    payload = experiment_sweep_summary_payload(sweep_spec, fake_results)
    @test payload["schema"] == "experiment_sweep_summary_v1"
    @test payload["sweep_id"] == "smf28_power_micro_sweep"
    @test payload["case_count"] == 2
    @test payload["complete"] == 1
    @test payload["failed"] == 1
    @test payload["cases"][1]["J_after_dB"] == -30.0

    csv = render_experiment_sweep_summary_csv(sweep_spec, fake_results)
    @test startswith(csv, "case,value,status,artifact_status")
    @test occursin("case_001,0.001,complete,complete,present,complete,-20.0,-30.0,-10.0,GOOD,true,1", csv)

    summary_dir = mktempdir()
    paths = write_experiment_sweep_summary_files(sweep_spec, fake_results, summary_dir)
    @test isfile(paths.summary_path)
    @test isfile(paths.summary_json_path)
    @test isfile(paths.summary_csv_path)
    written_payload = JSON3.read(read(paths.summary_json_path, String))
    @test written_payload.sweep_id == "smf28_power_micro_sweep"
    @test length(written_payload.cases) == 2
end
