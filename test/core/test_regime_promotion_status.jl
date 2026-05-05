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

    mv_default_policy = experiment_explore_run_policy(mv_spec)
    @test !mv_default_policy.allowed
    @test mv_default_policy.action == :front_layer
    @test :requires_local_smoke in mv_default_policy.blockers
    mv_smoke_policy = experiment_explore_run_policy(mv_spec; local_smoke=true)
    @test mv_smoke_policy.allowed
    @test mv_smoke_policy.action == :front_layer
    @test :experimental_run in mv_smoke_policy.warnings

    staged_default_policy = experiment_explore_run_policy(staged_mv_spec; local_smoke=true)
    @test !staged_default_policy.allowed
    @test staged_default_policy.action == :dedicated_workflow
    @test :requires_heavy_ok in staged_default_policy.blockers
    staged_heavy_policy = experiment_explore_run_policy(staged_mv_spec; heavy_ok=true)
    @test staged_heavy_policy.allowed
    @test staged_heavy_policy.action == :dedicated_workflow

    mmf_default_policy = experiment_explore_run_policy(mmf_spec; local_smoke=true)
    @test !mmf_default_policy.allowed
    @test mmf_default_policy.action == :front_layer
    @test :requires_heavy_ok in mmf_default_policy.blockers
    mmf_heavy_policy = experiment_explore_run_policy(mmf_spec; heavy_ok=true)
    @test mmf_heavy_policy.allowed
    @test mmf_heavy_policy.action == :front_layer
    @test :heavy_compute in mmf_heavy_policy.warnings

    long_default_policy = experiment_explore_run_policy(long_spec)
    @test !long_default_policy.allowed
    @test :requires_heavy_ok in long_default_policy.blockers
    long_heavy_policy = experiment_explore_run_policy(long_spec; heavy_ok=true)
    @test long_heavy_policy.allowed
    @test long_heavy_policy.action == :front_layer

    capabilities = sprint(io -> render_experiment_capabilities(; io=io))
    @test occursin("promotion_stages=planning, smoke, validated, lab_ready", capabilities)
    @test occursin("current_stage=", capabilities)
end
