using Test
using FiberLab

function _linear_scenario_term(objective, name, scale, shift; gradient_scale=scale)
    return ScenarioTerm(
        name,
        AdjointModel(
            name;
            forward = (decoded, context) -> scale .* decoded .+ shift,
            physical_gradient = (decoded, seed, context) -> gradient_scale .* seed,
        ),
        objective,
    )
end

@testset "FiberLab scenario composition" begin
    control = FullGridPhase(2; figure_hooks = ())
    objective = ObjectiveMap(
        :quadratic;
        cost = state -> sum(abs2, state),
        terminal_adjoint = (state, context) -> 2 .* state,
    )
    terms = (
        _linear_scenario_term(objective, :shifted, 1.0, [1.0, -0.5]),
        _linear_scenario_term(objective, :scaled, 2.0, [-0.25, -1.0]),
    )
    bundle = compose_scenarios(
        terms...;
        aggregate = weighted_scenario_aggregate((shifted = 0.25, scaled = 1.5)),
    )
    coordinates = [0.3, -0.2]
    run(bundle) = run_adjoint_step(bundle.model, control, bundle.objective, coordinates)
    step = run(bundle)
    costs = component_costs(bundle, step.forward_state)
    @test costs.shifted ≈ sum(abs2, coordinates .+ [1.0, -0.5])
    @test costs.scaled ≈ sum(abs2, 2 .* coordinates .- [0.25, 1.0])
    @test component_costs(bundle, coordinates; control = control) == costs
    @test step.cost ≈ 0.25 * costs.shifted + 1.5 * costs.scaled
    @test run(compose_scenarios(terms...)).cost ≈ sum(values(costs))
    @test run(compose_scenarios(terms[1])).cost ≈ costs.shifted
    @test propertynames(step.forward_state) == (:shifted, :scaled)
    @test propertynames(step.terminal_adjoint) == (:shifted, :scaled)
    @test bundle.model.provenance == bundle.provenance
    @test bundle.provenance.schema == :scenario_composition_v1
    @test bundle.provenance.objective == bundle.objective.name
    @test bundle.provenance.aggregate == (
        kind = :weighted_sum, weights = (shifted = 0.25, scaled = 1.5))
    @test !bundle.provenance.all_terms_sealed
    @test bundle.provenance.terms.shifted.problem_sha256 === nothing
    @test bundle.provenance.terms.shifted.source_authority == :declared_names_only
    @test check_adjoint_gradient(bundle.model, control, bundle.objective, coordinates).pass

    difference_bundle = compose_scenarios(
        terms...;
        aggregate = squared_difference_aggregate(:shifted, :scaled),
    )
    @test run(difference_bundle).cost ≈ (costs.shifted - costs.scaled)^2
    @test difference_bundle.provenance.aggregate == (
        kind = :squared_difference,
        minuend = :shifted,
        subtrahend = :scaled,
    )
    @test check_adjoint_gradient(
        difference_bundle.model, control, difference_bundle.objective, coordinates).pass

    structured_objective = ObjectiveMap(
        :structured;
        cost = state -> sum(abs2, state.left) + sum(abs2, state.right),
        terminal_adjoint = (state, context) -> map(x -> 2 .* x, state),
    )
    structured_state = (left = [1.0, 2.0], right = [3.0])
    @test terminal_adjoint(structured_objective, structured_state) ==
          (left = [2.0, 4.0], right = [6.0])
    @test_throws ArgumentError terminal_adjoint(
        ObjectiveMap(
            :wrong_names;
            cost = state -> 0.0,
            terminal_adjoint = (state, context) ->
                (left = state.left, other = state.right),
        ),
        structured_state,
    )
    @test_throws ArgumentError terminal_adjoint(
        ObjectiveMap(
            :wrong_shape;
            cost = state -> 0.0,
            terminal_adjoint = (state, context) ->
                (left = [1.0], right = state.right),
        ),
        structured_state,
    )

    @test_throws ArgumentError compose_scenarios(terms[1], terms[1])
    @test_throws ArgumentError ScenarioTerm(
        :no_seed, terms[1].model, ScalarObjective(:no_seed, state -> sum(abs2, state)))
    @test_throws ArgumentError compose_scenarios(
        terms...;
        aggregate = costs ->
            (cost = costs.shifted, partials = (shifted = 1.0, scaled = 0.0)),
    )
    @test_throws ArgumentError compose_scenarios(
        terms...; aggregate = weighted_scenario_aggregate((shifted = 1.0,)))
    @test_throws ArgumentError compose_scenarios(
        terms...;
        aggregate = weighted_scenario_aggregate((shifted = Inf, scaled = 0.0)),
    )
    @test_throws ArgumentError squared_difference_aggregate(:shifted, :shifted)

    artifact_result = solve(
        Experiment(
            Fiber(preset = :SMF28, length_m = 0.05, power_w = 0.001),
            control,
            bundle.objective;
            id = "native_scenario_provenance",
            solver = Solver(kind = :lbfgs, max_iter = 1),
        );
        backend = NativeAdjointBackend(
            bundle.model;
            initial_coordinates = coordinates,
            write_artifacts = true,
            output_dir = mktempdir(),
        ),
    )
    sidecar = FiberLab.JSON3.read(read(artifact_result.sidecar_path, String))
    @test String(sidecar.model_provenance.schema) == "scenario_composition_v1"
    @test String(sidecar.model_provenance.objective) == String(sidecar.objective)
    @test String(sidecar.model_provenance.aggregate.kind) == "weighted_sum"
    @test sidecar.model_provenance.aggregate.weights.shifted == 0.25
    @test sidecar.model_provenance.aggregate.weights.scaled == 1.5
    @test String(sidecar.model_provenance.terms.shifted.model) == "shifted"
    @test sidecar.model_provenance.terms.shifted.problem_sha256 === nothing
    @test sidecar.resolved_problem_sha256 === nothing

    incompatible_forward = compose_scenarios(
        terms[1],
        ScenarioTerm(
            :incompatible,
            AdjointModel(
                :incompatible;
                forward = (decoded, context) -> decoded.phase,
                physical_gradient = (decoded, seed, context) -> seed,
            ),
            objective,
        ),
    )
    incompatible_gradient = compose_scenarios(
        terms[1],
        _linear_scenario_term(
            objective, :incompatible, 1.0, zeros(2); gradient_scale = [1.0 0.0]),
    )
    @test_throws ArgumentError run(incompatible_forward)
    @test_throws ArgumentError run(incompatible_gradient)
end

@testset "FiberLab source-bound scenario composition" begin
    pulse = Pulse(fwhm_s = 1e-12, rep_rate_hz = 50e6, shape = :gaussian)
    problem(length_m; time_window_ps=5.0) = fiber_problem(
        Fiber(
            preset = :SMF28_beta2_only,
            length_m = length_m,
            power_w = 1e-5,
            beta_order = 2,
        );
        pulse = pulse,
        grid = Grid(nt = 16, time_window_ps = time_window_ps, policy = :exact),
        raman_threshold_thz = -0.25,
    )
    term(name, problem) = ScenarioTerm(
        name, fiber_model(problem), temporal_width_objective(problem))
    short_problem, long_problem = problem(1e-4), problem(2e-4)
    short_term, long_term = term(:short, short_problem), term(:long, long_problem)
    bundle = compose_scenarios(
        short_term,
        long_term;
        aggregate = weighted_scenario_aggregate((short = 1.0, long = 0.5)),
    )
    @test bundle.provenance.all_terms_sealed
    @test length(bundle.provenance.terms.short.problem_sha256) == 64
    @test bundle.provenance.terms.short.problem_sha256 ==
          bundle.provenance.terms.short.objective_problem_sha256
    @test bundle.provenance.terms.short.source_authority == :sealed_problem

    basis = reshape(collect(range(-0.25, 0.35; length = 16)), 16, 1)
    gradient_check = check_adjoint_gradient(
        bundle.model,
        PhaseBasis(basis),
        bundle.objective,
        [0.2];
        step = 1e-5,
        atol = 1e-7,
        rtol = 5e-2,
    )
    @test gradient_check.pass
    @test abs(only(gradient_check.adjoint_gradient)) > 1e-4

    @test_throws ArgumentError compose_scenarios(
        short_term, term(:other_grid, problem(1e-4; time_window_ps = 6.0)))
    @test_throws ArgumentError ScenarioTerm(
        :wrong_binding, fiber_model(short_problem), temporal_width_objective(long_problem))

    stale_problem = deepcopy(short_problem)
    stale_bundle = compose_scenarios(term(:stale, stale_problem))
    stale_problem.fiber["L"] *= 2
    @test_throws ArgumentError run_adjoint_step(
        stale_bundle.model, PhaseBasis(basis), stale_bundle.objective, [0.2])
end
