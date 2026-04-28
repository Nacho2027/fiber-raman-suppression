using Test

const _GAIN_TILT_ROOT = isdefined(Main, :_ROOT) ?
    getfield(Main, :_ROOT) :
    normpath(joinpath(@__DIR__, "..", ".."))

if !isdefined(Main, :load_experiment_spec)
    using MultiModeNoise
    include(joinpath(_GAIN_TILT_ROOT, "scripts", "lib", "experiment_spec.jl"))
end
if !isdefined(Main, :supported_experiment_run_kwargs)
    include(joinpath(_GAIN_TILT_ROOT, "scripts", "lib", "experiment_runner.jl"))
end
if !isdefined(Main, :mv_block_offsets)
    include(joinpath(_GAIN_TILT_ROOT, "scripts", "research", "multivar", "multivar_optimization.jl"))
end

@testset "Gain-tilt variable integration" begin
    @test :gain_tilt in registered_variable_kinds(:single_mode)
    contract = variable_contract(:gain_tilt, :single_mode)
    @test contract.maturity == "experimental"
    @test :gain_tilt_profile in contract.artifact_hooks
    @test :energy_throughput in contract.artifact_hooks

    objective = objective_contract(:raman_band, :single_mode)
    @test (:phase, :gain_tilt) in objective.supported_variables

    spec = load_experiment_spec("research_engine_gain_tilt_smoke")
    @test spec.id == "smf28_phase_gain_tilt_smoke"
    @test spec.controls.variables == (:phase, :gain_tilt)
    @test spec.objective.kind == :raman_band
    @test spec.artifacts.bundle == :experimental_multivar
    @test experiment_execution_mode(spec) == :multivar
    @test validate_experiment_spec(spec) isa NamedTuple

    layout = control_layout_plan(spec)
    @test layout.total_length == "1025"
    @test only(filter(block -> block.name == :gain_tilt, layout.blocks)).length == "1"
    @test occursin("gain tilt", only(filter(block -> block.name == :gain_tilt, layout.blocks)).bounds)

    plan = experiment_artifact_plan(spec)
    hooks = Tuple(request.hook for request in plan.hooks)
    @test :standard_image_set in hooks
    @test :gain_tilt_profile in hooks
    @test :energy_throughput in hooks
    @test plan.implemented

    kwargs = supported_experiment_run_kwargs(spec)
    @test kwargs.variables == (:phase, :gain_tilt)
    @test kwargs.δ_bound == 0.10

    rendered = render_experiment_plan(spec)
    @test occursin("variables=[:phase, :gain_tilt]", rendered)
    @test occursin("Artifact plan: implemented_now=true", rendered)

    cfg = MVConfig(variables = (:phase, :gain_tilt), δ_bound = 0.10)
    offsets = mv_block_offsets(cfg, 16, 1)
    @test offsets.n_total == 17
    @test offsets.ranges[:phase] == 1:16
    @test offsets.ranges[:gain_tilt] == 17:17

    sim = Dict{String,Any}("Nt" => 16, "M" => 1, "Δt" => 0.01)
    basis = mv_gain_tilt_basis(sim, 16, 1)
    @test size(basis) == (16, 1)
    @test maximum(abs.(basis)) ≈ 1.0
    @test abs(sum(basis)) < 1e-12

    A_tilt, dA_dξ, physical_slope = mv_gain_tilt_amplitude(0.7, cfg, sim, 16, 1)
    @test size(A_tilt) == (16, 1)
    @test all(0.90 .<= A_tilt .<= 1.10)
    @test any(abs.(A_tilt .- 1.0) .> 0)
    @test size(dA_dξ) == (16, 1)
    @test isfinite(physical_slope)

    x = mv_pack(zeros(16, 1), ones(16, 1), 1.0, cfg, 16, 1; gain_tilt = 0.7)
    unpacked = mv_unpack(x, cfg, 16, 1, 1.0)
    @test unpacked.gain_tilt == 0.7
    physical = mv_physical_amplitude(unpacked, cfg, sim, 16, 1)
    @test physical.slope == physical_slope
    @test physical.A == A_tilt
end
