@testset "FiberLab API" begin
    fiber = Fiber(regime = :single_mode, preset = :SMF28, length_m = 2.0, power_w = 0.2)
    experiment = Experiment(
        fiber,
        Control(variables = (:phase,)),
        Objective(kind = :raman_band);
        id = "api_smf28_phase",
        solver = Solver(max_iter = 7),
    )

    summary = summarize(experiment)
    @test summary.id == "api_smf28_phase"
    @test summary.regime == :single_mode
    @test summary.variables == (:phase,)
    @test summary.max_iter == 7

    text = experiment_config_text(experiment)
    @test occursin("id = \"api_smf28_phase\"", text)
    @test occursin("[problem]", text)
    @test occursin("preset = \"SMF28\"", text)
    @test occursin("variables = [\"phase\"]", text)
    @test occursin("kind = \"raman_band\"", text)
    @test occursin("max_iter = 7", text)
end
