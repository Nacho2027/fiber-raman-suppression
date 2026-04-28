if !isdefined(Main, :_PROMOTION_STATUS_ROOT)
    const _PROMOTION_STATUS_ROOT = isdefined(Main, :_ROOT) ? _ROOT : normpath(joinpath(@__DIR__, "..", ".."))
end

if !isdefined(Main, :load_experiment_spec)
    include(joinpath(_PROMOTION_STATUS_ROOT, "scripts", "lib", "experiment_spec.jl"))
end

@testset "Regime promotion status contract" begin
    phase_spec = load_experiment_spec("research_engine_export_smoke")
    phase_status = experiment_promotion_status(phase_spec)
    @test phase_status.stage == :lab_ready
    @test phase_status.executable == true
    @test phase_status.local_execution_allowed == true
    @test isempty(phase_status.blockers)
    @test occursin("Promotion stage: lab_ready", render_experiment_plan(phase_spec))

    mv_spec = load_experiment_spec("smf28_phase_amplitude_energy_poc")
    mv_status = experiment_promotion_status(mv_spec)
    @test mv_status.stage == :smoke
    @test mv_status.executable == true
    @test mv_status.local_execution_allowed == true
    @test :experimental_maturity in mv_status.blockers
    @test :no_trust_report in mv_status.blockers
    @test :no_export_handoff in mv_status.blockers
    @test occursin("Promotion stage: smoke", render_experiment_plan(mv_spec))
    @test occursin("Promotion blockers:", render_experiment_plan(mv_spec))

    staged_mv_spec = load_experiment_spec("smf28_amp_on_phase_refinement_poc")
    staged_mv_status = experiment_promotion_status(staged_mv_spec)
    @test staged_mv_status.stage == :planning
    @test staged_mv_status.executable == false
    @test :dedicated_workflow_only in staged_mv_status.blockers
    @test occursin("Promotion stage: planning", render_experiment_compute_plan(staged_mv_spec))

    long_spec = load_experiment_spec("smf28_longfiber_phase_poc")
    long_status = experiment_promotion_status(long_spec)
    @test long_status.stage == :planning
    @test long_status.executable == false
    @test long_status.local_execution_allowed == false
    @test :burst_required in long_status.blockers
    @test :front_layer_execution_blocked in long_status.blockers
    @test :unimplemented_artifacts in long_status.blockers
    @test occursin("Promotion stage: planning", render_experiment_plan(long_spec))
    @test occursin("Promotion blockers:", render_experiment_plan(long_spec))
    @test occursin("Promotion status:", render_experiment_compute_plan(long_spec))

    mmf_spec = load_experiment_spec("grin50_mmf_phase_sum_poc")
    mmf_status = experiment_promotion_status(mmf_spec)
    @test mmf_status.stage == :planning
    @test mmf_status.executable == false
    @test mmf_status.local_execution_allowed == false
    @test :burst_required in mmf_status.blockers
    @test :front_layer_execution_blocked in mmf_status.blockers
    @test :unimplemented_artifacts in mmf_status.blockers
    @test occursin("Promotion stage: planning", render_experiment_plan(mmf_spec))
    @test occursin("Promotion blockers:", render_experiment_plan(mmf_spec))

    capabilities = sprint(io -> render_experiment_capabilities(; io=io))
    @test occursin("promotion_stages=planning, smoke, validated, lab_ready", capabilities)
    @test occursin("current_stage=", capabilities)
end
