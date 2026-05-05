using Test
using Random

const _NON_RAMAN_ROOT = isdefined(Main, :_ROOT) ?
    getfield(Main, :_ROOT) :
    normpath(joinpath(@__DIR__, "..", ".."))

if !isdefined(Main, :load_experiment_spec)
    using FiberLab
    include(joinpath(_NON_RAMAN_ROOT, "scripts", "lib", "experiment_spec.jl"))
end
if !isdefined(Main, :supported_experiment_run_kwargs)
    include(joinpath(_NON_RAMAN_ROOT, "scripts", "lib", "experiment_runner.jl"))
end

@testset "Non-Raman objective integration" begin
    @test :temporal_width in registered_objective_kinds(:single_mode)
    contract = objective_contract(:temporal_width, :single_mode)
    @test contract.maturity == "experimental"
    @test (:phase,) in contract.supported_variables
    @test (:reduced_phase,) in contract.supported_variables
    @test :temporal_width_fraction in contract.metrics

    spec = load_experiment_spec("research_engine_temporal_width_smoke")
    @test spec.id == "smf28_phase_temporal_width_smoke"
    @test spec.objective.kind == :temporal_width
    @test spec.controls.variables == (:phase,)
    @test spec.solver.f_abstol === :auto
    @test spec.solver.g_abstol === :auto
    @test experiment_execution_mode(spec) == :phase_only
    @test validate_experiment_spec(spec) isa NamedTuple
    kwargs = supported_experiment_run_kwargs(spec)
    @test kwargs.objective_kind == :temporal_width
    @test kwargs.solver_f_abstol === :auto
    @test kwargs.solver_g_abstol === :auto

    rendered = render_experiment_plan(spec)
    @test occursin("Objective: kind=temporal_width", rendered)
    @test occursin("backend=raman_optimization", rendered)

    rng = MersenneTwister(42)
    Nt = 16
    uωf = randn(rng, ComplexF64, Nt, 1)
    sim = Dict{String,Any}("Nt" => Nt, "Δt" => 0.01)
    J, grad = temporal_width_cost(uωf, sim)
    @test isfinite(J)
    @test J >= 0
    @test size(grad) == size(uωf)
    @test all(isfinite, grad)

    ε = 1e-6
    for idx in (3, 8, 13)
        real_step = zeros(ComplexF64, Nt, 1)
        real_step[idx, 1] = 1
        Jp, _ = temporal_width_cost(uωf .+ ε .* real_step, sim)
        Jm, _ = temporal_width_cost(uωf .- ε .* real_step, sim)
        fd_real = (Jp - Jm) / (2ε)
        adj_real = 2 * real(conj(grad[idx, 1]) * real_step[idx, 1])
        @test fd_real ≈ adj_real rtol=1e-5 atol=1e-7

        imag_step = zeros(ComplexF64, Nt, 1)
        imag_step[idx, 1] = 1im
        Jp_i, _ = temporal_width_cost(uωf .+ ε .* imag_step, sim)
        Jm_i, _ = temporal_width_cost(uωf .- ε .* imag_step, sim)
        fd_imag = (Jp_i - Jm_i) / (2ε)
        adj_imag = 2 * real(conj(grad[idx, 1]) * imag_step[idx, 1])
        @test fd_imag ≈ adj_imag rtol=1e-5 atol=1e-7
    end
end
