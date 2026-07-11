struct TestFiberDesign
    core_radius_um::Float64
    numerical_aperture::Float64
end

@testset "FiberLab API" begin
    fiber = Fiber(preset = :SMF28, length_m = 2.0, power_w = 0.2)
    @test fiber.regime == :single_mode
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

@testset "FiberLab adjoint contracts" begin
    B = [
        1.0 0.0;
        0.5 1.0;
        0.0 2.0;
    ]
    control = PhaseBasis(B; name = :test_phase)
    x = [2.0, 3.0]

    @test decode(control, x) == B * x

    grad_phase = [1.0, 2.0, 4.0]
    @test pullback(control, grad_phase) == transpose(B) * grad_phase
    @test has_pullback(control)

    scalar_objective = ScalarObjective(:custom_cost, field -> sum(abs2, field))
    @test !has_terminal_adjoint(scalar_objective)
    @test_throws ArgumentError terminal_adjoint(scalar_objective, ones(ComplexF64, 3))
    @test_throws ArgumentError assert_adjoint_ready(scalar_objective, control, Solver(kind = :lbfgs))

    adjoint_objective = AdjointObjective(
        :energy;
        cost = field -> sum(abs2, field),
        terminal_adjoint = (field, context) -> 2 .* field,
    )
    field = ComplexF64[1 + 0im, 2 - 1im, -1 + 0.5im]
    @test has_terminal_adjoint(adjoint_objective)
    @test terminal_adjoint(adjoint_objective, field) == 2 .* field
    @test assert_adjoint_ready(adjoint_objective, control, Solver(kind = :lbfgs))

    full_grid = FullGridPhase(3)
    @test dimension(full_grid) == 3
    @test decode(full_grid, [0.1, 0.2, 0.3]) == [0.1, 0.2, 0.3]
    @test pullback(full_grid, [1.0, 2.0, 3.0]) == [1.0, 2.0, 3.0]
    @test has_pullback(full_grid)
    @test :phase_profile in full_grid.figure_hooks
    @test_throws ArgumentError FullGridPhase(0)
    @test_throws ArgumentError decode(full_grid, [1.0, 2.0])
    @test_throws ArgumentError pullback(full_grid, [1.0, NaN, 3.0])

    scalar_control = ScalarControl(:energy; units = "relative pulse energy")
    @test dimension(scalar_control) == 1
    @test decode(scalar_control, [2.0]) == 2.0
    @test pullback(scalar_control, [3.0]) == [3.0]
    @test has_pullback(scalar_control)
    @test_throws ArgumentError ScalarControl(Symbol(""))
    @test_throws ArgumentError decode(scalar_control, [1.0, 2.0])

    positive_scalar = PositiveScalar(:energy; units = "relative pulse energy")
    positive_evaluation_builtin = evaluate_control(positive_scalar, [log(2.0)])
    @test positive_evaluation_builtin.decoded ≈ 2.0
    @test pullback(positive_evaluation_builtin, [3.0]) ≈ [6.0]
    @test has_pullback(positive_scalar)

    amplitude_basis = AmplitudeBasis(
        [1.0 0.0; 0.0 1.0; 1.0 -1.0];
        scale = 0.1,
    )
    @test decode(amplitude_basis, [0.5, -0.5]) ≈ [1.05, 0.95, 1.1]
    @test pullback(amplitude_basis, [1.0, 2.0, 3.0]) ≈ [0.4, -0.1]
    @test has_pullback(amplitude_basis)
    @test_throws ArgumentError AmplitudeBasis(zeros(0, 2))
    @test_throws ArgumentError decode(
        AmplitudeBasis(ones(3, 1); offset = 0.01, scale = 1.0),
        [-1.0],
    )

    positive_control = ControlMap(
        :positive_energy;
        dimension = 1,
        decode = (values, context) -> exp(values[1]),
        pullback = (physical_gradient, context) -> [
            only(physical_gradient) * context.decoded
        ],
    )
    positive_evaluation = evaluate_control(positive_control, [log(2.0)])
    @test positive_evaluation isa ControlEvaluation
    @test positive_evaluation.decoded ≈ 2.0
    @test positive_evaluation.coordinates == [log(2.0)]
    @test pullback(positive_evaluation, [3.0]) ≈ [6.0]
    positive_gradient = pullback_gradient(positive_evaluation, [3.0])
    @test positive_gradient isa ControlGradient
    @test gradient_vector(positive_gradient) ≈ [6.0]
    @test positive_gradient.physical_gradient == [3.0]

    custom_control = ControlMap(
        :custom_phase;
        dimension = 2,
        decode = (values, context) -> [values[1], values[2], sum(values)],
        pullback = (physical_gradient, context) ->
            [physical_gradient[1] + physical_gradient[3],
             physical_gradient[2] + physical_gradient[3]],
        figure_hooks = (:custom_phase_plot,),
    )
    @test dimension(custom_control) == 2
    @test decode(custom_control, [1.0, 2.0]) == [1.0, 2.0, 3.0]
    @test pullback(custom_control, [0.5, 1.5, 2.0]) == [2.5, 3.5]
    @test has_pullback(custom_control)
    @test_throws ArgumentError decode(custom_control, [1.0])
    @test_throws ArgumentError ControlMap(:bad_control; dimension = 0, decode = (x, ctx) -> x)
    @test_throws ArgumentError pullback(
        ControlMap(:no_pullback; dimension = 1, decode = (x, ctx) -> x),
        [1.0],
    )
    @test_throws ArgumentError pullback(
        ControlMap(
            :bad_pullback;
            dimension = 2,
            decode = (x, ctx) -> x,
            pullback = (g, ctx) -> [1.0],
        ),
        [1.0],
    )

    mapped_objective = ObjectiveMap(
        :mapped_energy;
        cost = field -> sum(abs2, field),
        terminal_adjoint = (field, context) -> 2 .* field,
        figure_hooks = (:mapped_energy_plot,),
    )
    @test has_terminal_adjoint(mapped_objective)
    @test objective_value(mapped_objective, field) ≈ sum(abs2, field)
    @test terminal_adjoint(mapped_objective, field) == 2 .* field
    @test assert_adjoint_ready(mapped_objective, custom_control, Solver(kind = :lbfgs))
    @test_throws MethodError ObjectiveMap(
        :forged_problem_binding;
        cost = f -> sum(abs2, f),
        terminal_adjoint = (f, ctx) -> f,
        problem_sha256 = repeat("0", 64),
    )
    @test_throws ArgumentError terminal_adjoint(
        ObjectiveMap(
            :wrong_shape;
            cost = f -> sum(abs2, f),
            terminal_adjoint = (f, ctx) -> ones(ComplexF64, length(f) + 1),
        ),
        field,
    )
    @test_throws ArgumentError terminal_adjoint(
        ObjectiveMap(
            :nonfinite_adjoint;
            cost = f -> sum(abs2, f),
            terminal_adjoint = (f, ctx) -> fill(ComplexF64(NaN), size(f)),
        ),
        field,
    )
end

@testset "FiberLab control spaces" begin
    B_phase = [
        1.0 0.0;
        0.0 1.0;
        1.0 1.0;
    ]
    B_amp = reshape([1.0, 2.0, 3.0], 3, 1)
    space = ControlSpace(
        :phase => PhaseBasis(B_phase),
        :amplitude => PhaseBasis(B_amp; name = :amplitude, units = "dimensionless"),
    )

    layout = control_slices(space)
    @test layout.names == (:phase, :amplitude)
    @test layout.total_dimension == 3
    @test layout.slices[:phase] == 1:2
    @test layout.slices[:amplitude] == 3:3

    decoded = decode(space, [2.0, 3.0, 0.5])
    @test decoded.phase == B_phase * [2.0, 3.0]
    @test decoded.amplitude == B_amp * [0.5]

    evaluated = evaluate_control(space, [2.0, 3.0, 0.5])
    @test evaluated.phase.decoded == decoded.phase
    @test evaluated.amplitude.decoded == decoded.amplitude
    @test evaluated.phase.coordinates == [2.0, 3.0]
    @test evaluated.amplitude.coordinates == [0.5]

    physical_gradients = (
        phase = [1.0, 2.0, 4.0],
        amplitude = [0.5, 1.0, 1.5],
    )
    expected = vcat(transpose(B_phase) * physical_gradients.phase,
                    transpose(B_amp) * physical_gradients.amplitude)
    @test pullback(space, physical_gradients) == expected
    gradient_evaluations = pullback_gradient(evaluated, physical_gradients)
    @test gradient_vector(gradient_evaluations.phase) ==
          transpose(B_phase) * physical_gradients.phase
    @test gradient_vector(gradient_evaluations.amplitude) ==
          transpose(B_amp) * physical_gradients.amplitude
    @test_throws ArgumentError pullback_gradient(evaluated, (phase = physical_gradients.phase,))
    @test has_pullback(space)
end

@testset "FiberLab API-native adjoint step" begin
    B = [
        1.0 0.0;
        0.0 1.0;
        1.0 1.0;
    ]
    control = PhaseBasis(B)
    objective = ObjectiveMap(
        :quadratic_state;
        cost = state -> sum(abs2, state),
        terminal_adjoint = (state, context) -> 2 .* state,
    )
    model = AdjointModel(
        :identity_model;
        forward = (decoded_control, context) -> decoded_control .+ [1.0, 0.0, -1.0],
        physical_gradient = (decoded_control, terminal_seed, context) -> terminal_seed,
    )

    result = run_adjoint_step(model, control, objective, [2.0, 3.0])
    expected_state = B * [2.0, 3.0] .+ [1.0, 0.0, -1.0]
    @test result isa AdjointStepResult
    @test result.forward_state == expected_state
    @test result.cost == sum(abs2, expected_state)
    @test result.terminal_adjoint == 2 .* expected_state
    @test result.physical_gradient == 2 .* expected_state
    @test gradient_vector(result) == transpose(B) * (2 .* expected_state)

    gradient_check = check_adjoint_gradient(model, control, objective, [2.0, 3.0])
    @test gradient_check isa AdjointGradientCheckResult
    @test gradient_check.pass
    @test gradient_check.coordinates == [1, 2]
    @test gradient_check.adjoint_gradient ≈ transpose(B) * (2 .* expected_state)
    @test isapprox(
        gradient_check.finite_difference_gradient,
        gradient_check.adjoint_gradient;
        rtol = 1e-6,
    )

    subset_check = check_adjoint_gradient(
        model,
        control,
        objective,
        [2.0, 3.0];
        coordinate_indices = [2],
    )
    @test subset_check.pass
    @test subset_check.coordinates == [2]

    trust = trust_check(
        model,
        control,
        objective,
        [0.01, -0.02];
        profile = LabProfile(phase_levels = 256, max_phase_step = 0.2),
        gradient_check = true,
        coordinate_indices = [1],
    )
    @test trust isa TrustReport
    @test trust.pass
    @test :finite_forward_state in Tuple(check.name for check in trust.checks)
    @test :lab_phase_step in Tuple(check.name for check in trust.checks)
    @test :adjoint_gradient_check in Tuple(check.name for check in trust.checks)

    unrealistic_trust = trust_check(
        model,
        control,
        objective,
        [3.0, -3.0];
        profile = LabProfile(max_phase_step = 0.1),
    )
    @test !unrealistic_trust.pass
    @test any(check -> check.name == :lab_phase_step && check.pass === false,
              unrealistic_trust.checks)

    projection_sensitive_model = AdjointModel(
        :projection_sensitive_model;
        forward = (decoded_control, context) -> decoded_control,
        physical_gradient = (decoded_control, terminal_seed, context) -> terminal_seed,
    )
    projection_objective = ObjectiveMap(
        :projection_sensitive_objective;
        cost = state -> sum(abs2, state .- [0.0, 0.3]),
        terminal_adjoint = (state, context) -> 2 .* (state .- [0.0, 0.3]),
    )
    projection_trust = trust_check(
        projection_sensitive_model,
        FullGridPhase(2),
        projection_objective,
        [0.0, 0.3];
        profile = LabProfile(
            phase_levels = 2,
            max_projected_cost_increase = 0.01,
        ),
    )
    @test !projection_trust.pass
    @test any(check -> check.name == :lab_projected_cost && check.pass === false,
              projection_trust.checks)

    projection_info = trust_check(
        projection_sensitive_model,
        FullGridPhase(2),
        projection_objective,
        [0.0, 0.3];
        profile = LabProfile(phase_levels = 2),
    )
    projected_cost_check = only(filter(check -> check.name == :lab_projected_cost,
                                       projection_info.checks))
    @test projection_info.pass
    @test projected_cost_check.pass === missing
    @test projected_cost_check.severity == :warning

    nonlinear = ControlMap(
        :positive_scalar;
        dimension = 1,
        decode = (x, context) -> exp(x[1]),
        pullback = (physical_gradient, context) -> [only(physical_gradient) * context.decoded],
    )
    scalar_model = AdjointModel(
        :scalar_identity;
        forward = (decoded_control, context) -> [decoded_control],
        physical_gradient = (decoded_control, terminal_seed, context) -> terminal_seed,
    )
    scalar_result = run_adjoint_step(scalar_model, nonlinear, objective, [log(2.0)])
    @test scalar_result.forward_state == [2.0]
    @test gradient_vector(scalar_result) == [8.0]

    space = ControlSpace(
        :phase => PhaseBasis(B),
        :energy => ScalarControl(:energy),
    )
    multivar_model = AdjointModel(
        :multivar_model;
        forward = (decoded_control, context) ->
            decoded_control.phase .+ decoded_control.energy,
        physical_gradient = (decoded_control, terminal_seed, context) -> (
            phase = terminal_seed,
            energy = [sum(terminal_seed)],
        ),
    )
    multivar_result = run_adjoint_step(multivar_model, space, objective, [2.0, 3.0, 0.5])
    expected_multivar_state = B * [2.0, 3.0] .+ 0.5
    @test multivar_result.forward_state == expected_multivar_state
    @test dimension(space) == 3
    @test gradient_vector(multivar_result.control_gradient.phase) ==
          transpose(B) * (2 .* expected_multivar_state)
    @test gradient_vector(multivar_result.control_gradient.energy) ==
          [sum(2 .* expected_multivar_state)]
    @test gradient_vector(multivar_result) ==
          vcat(
              transpose(B) * (2 .* expected_multivar_state),
              [sum(2 .* expected_multivar_state)],
          )
    multivar_trust = trust_check(
        multivar_result;
        profile = LabProfile(coordinate_range = (-10.0, 10.0)),
    )
    @test multivar_trust.pass
    @test any(check -> check.name == :lab_coordinate_range, multivar_trust.checks)

    feasibility = FeasibilityMap(
        :keep_energy_nonzero;
        penalty = (decoded, ctx) -> 10.0 * (decoded.energy - 1.0)^2,
        physical_gradient = (decoded, ctx) -> (
            energy = [20.0 * (decoded.energy - 1.0)],
        ),
        project = (decoded, ctx) -> (
            phase = decoded.phase,
            energy = max(decoded.energy, 0.2),
        ),
        check = (decoded, ctx) -> (
            energy_positive = decoded.energy > 0,
        ),
    )
    feasibility_step = run_adjoint_step(
        multivar_model,
        space,
        objective,
        [0.0, 0.0, 0.5];
        feasibility = feasibility,
    )
    @test feasibility_step.cost ≈ sum(abs2, B * [0.0, 0.0] .+ 0.5) + 10.0 * 0.5^2
    @test gradient_vector(feasibility_step.control_gradient.energy) ≈
          [sum(2 .* fill(0.5, 3)) - 10.0]
    @test project(feasibility, (phase = zeros(3), energy = -1.0)).energy == 0.2
    @test feasibility_check(feasibility, (phase = zeros(3), energy = 0.5)).energy_positive

    bad_cost = ObjectiveMap(
        :bad_cost;
        cost = state -> NaN,
        terminal_adjoint = (state, context) -> state,
    )
    @test_throws ArgumentError objective_value(bad_cost, [1.0, 2.0])
    @test_throws ArgumentError run_adjoint_step(model, control, bad_cost, [2.0, 3.0])

    bad_model = AdjointModel(
        :bad_model;
        forward = (decoded_control, context) -> nothing,
        physical_gradient = (decoded_control, terminal_seed, context) -> terminal_seed,
    )
    @test_throws ArgumentError run_adjoint_step(bad_model, control, objective, [2.0, 3.0])

    wrong_gradient_model = AdjointModel(
        :wrong_gradient;
        forward = (decoded_control, context) -> decoded_control .+ [1.0, 0.0, -1.0],
        physical_gradient = (decoded_control, terminal_seed, context) -> -terminal_seed,
    )
    failed_check = check_adjoint_gradient(
        wrong_gradient_model,
        control,
        objective,
        [2.0, 3.0],
    )
    @test !failed_check.pass
    @test_throws ArgumentError check_adjoint_gradient(
        model,
        control,
        objective,
        [2.0, 3.0];
        step = 0.0,
    )
    @test_throws ArgumentError check_adjoint_gradient(
        model,
        control,
        objective,
        [2.0, 3.0];
        coordinate_indices = [1, 1],
    )
end

@testset "FiberLab native adjoint backend" begin
    fiber = Fiber(regime = :single_mode, preset = :SMF28, length_m = 0.05, power_w = 0.001)
    control = ScalarControl(:x)
    objective = ObjectiveMap(
        :quadratic_state;
        cost = state -> sum(abs2, state),
        terminal_adjoint = (state, context) -> 2 .* state,
    )
    model = AdjointModel(
        :identity_scalar;
        forward = (decoded_control, context) -> [decoded_control],
        physical_gradient = (decoded_control, terminal_seed, context) -> terminal_seed,
    )
    experiment = Experiment(
        fiber,
        control,
        objective;
        id = "native_scalar_quadratic",
        solver = Solver(kind = :lbfgs, max_iter = 6),
        maturity = :supported,
    )

    result = solve(
        experiment;
        backend = NativeAdjointBackend(
            model;
            initial_coordinates = [2.0],
            step_size = 0.25,
        ),
    )
    @test result isa NativeAdjointResult
    @test result.x_initial == [2.0]
    @test isapprox(result.x_final[1], 0.0; atol = 1e-12)
    @test result.cost_initial == 4.0
    @test isapprox(result.cost_final, 0.0; atol = 1e-12)
    @test result.cost_final < result.cost_initial
    @test length(result.convergence_trace) >= 2
    @test result.convergence_trace[1].iteration == 0
    @test result.final_step isa AdjointStepResult
    @test result.converged
    @test result.gradient_check === nothing
    @test decoded_final(result) ≈ 0.0
    result_metrics = metrics(result)
    @test result_metrics.cost_initial == 4.0
    @test isapprox(result_metrics.cost_final, 0.0; atol = 1e-12)
    @test result_metrics.delta_cost < 0
    @test result_metrics.iterations == length(result.convergence_trace) - 1
    @test result_metrics.converged
    @test result_metrics.gradient_check_pass === missing
    @test result_metrics.trust_check_pass
    @test result.trust_report isa TrustReport
    @test isempty(figure_paths(result))
    verification = verify(result)
    @test verification.converged
    @test verification.gradient_check_pass === missing
    @test verification.cost_decreased
    @test verification.finite_final_cost
    @test verification.finite_final_coordinates
    @test verification.trust_check_pass
    @test verification.artifact_files_exist === missing
    @test isempty(verification.requested_artifact_hooks)
    @test isempty(verification.missing_artifact_hooks)

    for authority in (:resolved_numerical, :authoritative, :user_asserted)
        bypass_output = mktempdir()
        incomplete_native_experiment = FiberLab.NativeExperiment(;
            id = "incomplete_custom_metadata_$(authority)",
            control = control,
            objective = objective,
            solver = Solver(kind = :lbfgs, max_iter = 1),
            maturity = :supported,
            metadata_authority = authority,
        )
        @test_throws FiberLabBackendError solve(
            incomplete_native_experiment;
            backend = NativeAdjointBackend(
                model;
                initial_coordinates = [2.0],
                max_iter = 1,
                write_artifacts = true,
                output_dir = bypass_output,
            ),
        )
        @test isempty(readdir(bypass_output))
    end

    direct_result = solve(
        model,
        control,
        objective,
        [2.0];
        fiber = fiber,
        pulse = Pulse(),
        grid = Grid(),
        id = "direct_native_scalar_quadratic",
        max_iter = 6,
        validate_gradient = true,
        step_size = 0.25,
        maturity = :supported,
    )
    @test direct_result isa NativeAdjointResult
    @test direct_result.plan.experiment.id == "direct_native_scalar_quadratic"
    @test direct_result.gradient_check.pass
    @test direct_result.trust_report.pass
    @test isapprox(direct_result.x_final[1], 0.0; atol = 1e-12)
    @test verify(direct_result).gradient_check_pass
    @test_throws ArgumentError solve(
        model,
        control,
        objective,
        [2.0];
        fiber = fiber,
        max_iter = 1,
    )

    artifact_dir = mktempdir()
    artifact_result = solve(
        experiment;
        backend = NativeAdjointBackend(
            model;
            initial_coordinates = [2.0],
            write_artifacts = true,
            output_dir = artifact_dir,
        ),
    )
    @test artifact_result.output_dir == artifact_dir
    @test artifact_result.sidecar_path !== nothing
    @test isfile(artifact_result.sidecar_path)
    @test isfile(figure_paths(artifact_result)[:convergence_trace])
    @test isfile(figure_paths(artifact_result)[:trust_report])
    artifact_verification = verify(artifact_result)
    @test artifact_verification.artifact_complete
    @test artifact_verification.artifact_files_exist
    @test isempty(artifact_verification.requested_artifact_hooks)
    @test isempty(artifact_verification.missing_artifact_hooks)
    native_sidecar = read(artifact_result.sidecar_path, String)
    @test occursin("\"schema_version\": \"native_adjoint_result_v1\"", native_sidecar)
    @test occursin("\"experiment_id\": \"native_scalar_quadratic\"", native_sidecar)
    @test occursin("\"decoded_final\"", native_sidecar)
    @test occursin("\"metrics\"", native_sidecar)
    @test occursin("\"trust_report\"", native_sidecar)
    @test occursin("\"trust_report\": \"native_scalar_quadratic_trust_report.json\"", native_sidecar)
    @test occursin("\"convergence_trace_file\"", native_sidecar)
    @test occursin("\"metadata_authority\": \"user_asserted\"", native_sidecar)

    figure_control = FullGridPhase(4)
    figure_objective = ObjectiveMap(
        :field_summary_objective;
        cost = state -> sum(abs2, state),
        terminal_adjoint = (state, context) -> 2 .* state,
        figure_hooks = (:field_summary, :convergence_trace),
    )
    figure_model = AdjointModel(
        :figure_identity;
        forward = (decoded_control, context) -> decoded_control,
        physical_gradient = (decoded_control, terminal_seed, context) -> terminal_seed,
    )
    figure_experiment = Experiment(
        fiber,
        figure_control,
        figure_objective;
        id = "native_default_figures",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    default_figure_dir = mktempdir()
    default_figure_result = solve(
        figure_experiment;
        backend = NativeAdjointBackend(
            figure_model;
            initial_coordinates = [0.5, -0.25, 0.1, -0.05],
            write_artifacts = true,
            output_dir = default_figure_dir,
        ),
    )
    default_figures = figure_paths(default_figure_result)
    @test isfile(default_figures[:field_summary])
    @test isfile(default_figures[:convergence_trace])
    @test isfile(default_figures[:phase_profile])
    @test isfile(default_figures[:group_delay])
    @test FiberLab._native_png_passes_audit(default_figures[:field_summary])
    @test FiberLab._native_png_passes_audit(default_figures[:phase_profile])
    @test FiberLab._native_png_passes_audit(default_figures[:group_delay])
    default_figure_verification = verify(default_figure_result)
    @test default_figure_verification.artifact_complete
    @test default_figure_verification.artifact_files_exist
    @test Set(default_figure_verification.requested_artifact_hooks) ==
          Set((:field_summary, :convergence_trace, :phase_profile, :group_delay))
    @test isempty(default_figure_verification.missing_artifact_hooks)

    invalid_png_dir = mktempdir()
    corrupt_png = joinpath(invalid_png_dir, "corrupt.png")
    write(corrupt_png, "not a png")
    blank_png = joinpath(invalid_png_dir, "blank.png")
    FiberLab.PyPlot.imsave(blank_png, ones(4, 4), cmap = "gray")
    @test !FiberLab._native_artifact_file_passes_audit(corrupt_png)
    @test !FiberLab._native_artifact_file_passes_audit(blank_png)
    @test !FiberLab._native_artifact_file_complete(Dict(:bad => corrupt_png))
    @test !FiberLab._native_artifact_file_complete(Dict(:blank => blank_png))

    direct_figure_dir = mktempdir()
    direct_figure_result = solve(
        figure_model,
        figure_control,
        figure_objective,
        [0.5, -0.25, 0.1, -0.05];
        fiber = fiber,
        pulse = Pulse(),
        grid = Grid(),
        id = "direct_native_default_figures",
        max_iter = 1,
        write_artifacts = true,
        output_dir = direct_figure_dir,
        maturity = :supported,
    )
    direct_figures = figure_paths(direct_figure_result)
    @test isfile(direct_figures[:field_summary])
    @test isfile(direct_figures[:convergence_trace])
    @test isfile(direct_figures[:phase_profile])
    @test isfile(direct_figures[:group_delay])
    @test FiberLab._native_png_passes_audit(direct_figures[:field_summary])
    @test FiberLab._native_png_passes_audit(direct_figures[:phase_profile])
    @test FiberLab._native_png_passes_audit(direct_figures[:group_delay])
    @test verify(direct_figure_result).artifact_complete

    trust_required_result = solve(
        figure_model,
        figure_control,
        figure_objective,
        [0.01, -0.02, 0.01, -0.02];
        fiber = fiber,
        pulse = Pulse(),
        grid = Grid(),
        id = "direct_native_trust_required",
        max_iter = 1,
        gradient_tolerance = 1e99,
        maturity = :supported,
        trust_profile = LabProfile(max_phase_step = 0.2),
        require_trust = true,
    )
    @test trust_required_result.trust_report.pass
    @test_throws FiberLabBackendError solve(
        figure_model,
        figure_control,
        figure_objective,
        [2.0, -2.0, 2.0, -2.0];
        fiber = fiber,
        pulse = Pulse(),
        grid = Grid(),
        id = "direct_native_trust_rejected",
        max_iter = 1,
        gradient_tolerance = 1e99,
        maturity = :supported,
        trust_profile = LabProfile(max_phase_step = 0.1),
        require_trust = true,
    )

    multimode_figure_objective = ObjectiveMap(
        :mode_resolved_summary_objective;
        cost = state -> sum(abs2, state),
        terminal_adjoint = (state, context) -> 2 .* state,
        figure_hooks = (:mode_resolved_spectra, :per_mode_leakage_table),
    )
    multimode_figure_model = AdjointModel(
        :mode_resolved_identity;
        forward = (decoded_control, context) -> hcat(decoded_control, 2 .* decoded_control),
        physical_gradient = (decoded_control, terminal_seed, context) ->
            terminal_seed[:, 1] .+ 2 .* terminal_seed[:, 2],
    )
    multimode_figure_experiment = Experiment(
        Fiber(regime = :multimode, preset = :custom, length_m = 0.05, power_w = 0.001),
        figure_control,
        multimode_figure_objective;
        id = "native_default_multimode_figures",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    multimode_figure_dir = mktempdir()
    multimode_figure_result = solve(
        multimode_figure_experiment;
        backend = NativeAdjointBackend(
            multimode_figure_model;
            initial_coordinates = [0.5, -0.25, 0.1, -0.05],
            write_artifacts = true,
            output_dir = multimode_figure_dir,
        ),
    )
    multimode_figures = figure_paths(multimode_figure_result)
    @test isfile(multimode_figures[:mode_resolved_spectra])
    @test isfile(multimode_figures[:per_mode_leakage_table])
    @test FiberLab._native_png_passes_audit(multimode_figures[:mode_resolved_spectra])
    @test occursin("mode,total_power,peak_power",
                   read(multimode_figures[:per_mode_leakage_table], String))
    multimode_verification = verify(multimode_figure_result)
    @test multimode_verification.artifact_complete
    @test Set(multimode_verification.requested_artifact_hooks) ==
          Set((:mode_resolved_spectra, :per_mode_leakage_table, :phase_profile, :group_delay))
    @test isempty(multimode_verification.missing_artifact_hooks)

    converged = solve(
        experiment;
        backend = NativeAdjointBackend(
            model;
            initial_coordinates = [0.0],
            step_size = 0.25,
            gradient_tolerance = 1e-12,
        ),
    )
    @test converged.converged
    @test length(converged.convergence_trace) == 1

    validated_experiment = Experiment(
        fiber,
        control,
        objective;
        id = "native_validated_quadratic",
        solver = Solver(kind = :lbfgs, max_iter = 6, validate_gradient = true),
        maturity = :supported,
    )
    validated = solve(
        validated_experiment;
        backend = NativeAdjointBackend(model; initial_coordinates = [2.0]),
    )
    @test validated.gradient_check isa AdjointGradientCheckResult
    @test validated.gradient_check.pass
    @test verify(validated).gradient_check_pass

    multivar_control = ControlSpace(
        :phase_scale => ScalarControl(:phase_scale),
        :energy => ScalarControl(:energy),
    )
    multivar_model = AdjointModel(
        :packed_scalar_model;
        forward = (decoded_control, context) ->
            [decoded_control.phase_scale, decoded_control.energy],
        physical_gradient = (decoded_control, terminal_seed, context) -> (
            phase_scale = [terminal_seed[1]],
            energy = [terminal_seed[2]],
        ),
    )
    multivar_experiment = Experiment(
        fiber,
        multivar_control,
        objective;
        id = "native_multivar_quadratic",
        solver = Solver(kind = :lbfgs, max_iter = 3),
        maturity = :supported,
    )
    multivar_result = solve(
        multivar_experiment;
        backend = NativeAdjointBackend(
            multivar_model;
            initial_coordinates = [2.0, -4.0],
            step_size = 0.25,
        ),
    )
    @test isapprox(multivar_result.x_final, [0.0, 0.0]; atol = 1e-12)
    @test decoded_final(multivar_result).phase_scale ≈ 0.0
    @test decoded_final(multivar_result).energy ≈ 0.0
    @test multivar_result.cost_final < multivar_result.cost_initial
    @test gradient_vector(multivar_result.final_step) ≈
          2 .* multivar_result.final_step.forward_state

    bounded_model = AdjointModel(
        :bounded_multivar_model;
        forward = (decoded_control, context) -> [
            decoded_control.phase_scale - 5.0,
            decoded_control.energy + 5.0,
        ],
        physical_gradient = (decoded_control, terminal_seed, context) -> (
            phase_scale = [terminal_seed[1]],
            energy = [terminal_seed[2]],
        ),
    )
    bounded_result = solve(
        multivar_experiment;
        backend = NativeAdjointBackend(
            bounded_model;
            initial_coordinates = [0.5, -0.5],
            step_size = 0.25,
            bounds = control_bounds(
                multivar_control,
                :phase_scale => (0.0, 1.0),
                :energy => (lower = -1.0, upper = 0.0),
            ),
        ),
    )
    @test isapprox(decoded_final(bounded_result).phase_scale, 1.0; atol = 1e-8)
    @test isapprox(decoded_final(bounded_result).energy, -1.0; atol = 1e-8)
    @test bounded_result.cost_final < bounded_result.cost_initial
    @test_throws ArgumentError solve(
        multivar_experiment;
        backend = NativeAdjointBackend(
            bounded_model;
            initial_coordinates = [2.0, 0.0],
            bounds = control_bounds(
                multivar_control,
                :phase_scale => (0.0, 1.0),
            ),
        ),
    )

    feasibility = FeasibilityMap(
        :keep_energy_near_one;
        penalty = (decoded, ctx) -> 10.0 * (decoded.energy - 1.0)^2,
        physical_gradient = (decoded, ctx) -> (
            energy = [20.0 * (decoded.energy - 1.0)],
        ),
        check = (decoded, ctx) -> (energy = decoded.energy,),
    )
    feasibility_experiment = Experiment(
        fiber,
        multivar_control,
        objective;
        id = "native_multivar_feasibility",
        solver = Solver(kind = :lbfgs, max_iter = 12, validate_gradient = true),
        maturity = :supported,
    )
    feasibility_result = solve(
        feasibility_experiment;
        backend = NativeAdjointBackend(
            multivar_model;
            initial_coordinates = [2.0, -4.0],
            step_size = 0.25,
            feasibility = feasibility,
        ),
    )
    @test feasibility_result.gradient_check.pass
    @test isapprox(decoded_final(feasibility_result).phase_scale, 0.0; atol = 1e-8)
    @test isapprox(decoded_final(feasibility_result).energy, 10 / 11; atol = 1e-8)
    @test feasibility_result.feasibility_evaluation.penalty ≈
          10.0 * (10 / 11 - 1)^2
    @test metrics(feasibility_result).feasibility_penalty ≈
          feasibility_result.feasibility_evaluation.penalty

    @test_throws FiberLabBackendError solve(
        feasibility_experiment;
        backend = NativeAdjointBackend(
            multivar_model;
            initial_coordinates = [2.0, -4.0],
            feasibility = FeasibilityMap(
                :penalty_without_gradient;
                penalty = (decoded, ctx) -> decoded.energy^2,
            ),
        ),
    )

    multivar_artifact_dir = mktempdir()
    multivar_artifact_result = solve(
        multivar_experiment;
        backend = NativeAdjointBackend(
            multivar_model;
            initial_coordinates = [2.0, -4.0],
            write_artifacts = true,
            output_dir = multivar_artifact_dir,
        ),
    )
    multivar_sidecar = read(multivar_artifact_result.sidecar_path, String)
    @test occursin("\"controls\": [", multivar_sidecar)
    @test occursin("\"phase_scale\"", multivar_sidecar)
    @test occursin("\"energy\"", multivar_sidecar)

    vector_energy_control = ControlMap(
        :energy;
        dimension = 1,
        decode = (x, context) -> [exp(x[1])],
        pullback = (physical_gradient, context) ->
            [only(physical_gradient) * only(context.decoded)],
        figure_hooks = (:energy_scale,),
    )
    vector_energy_space = ControlSpace(
        :phase_scale => ScalarControl(:phase_scale),
        :energy => vector_energy_control,
    )
    vector_energy_model = AdjointModel(
        :vector_energy_model;
        forward = (decoded_control, context) ->
            [decoded_control.phase_scale, only(decoded_control.energy)],
        physical_gradient = (decoded_control, terminal_seed, context) -> (
            phase_scale = [terminal_seed[1]],
            energy = [terminal_seed[2]],
        ),
    )
    vector_energy_experiment = Experiment(
        fiber,
        vector_energy_space,
        objective;
        id = "native_vector_energy_artifact",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    vector_energy_artifact_result = solve(
        vector_energy_experiment;
        backend = NativeAdjointBackend(
            vector_energy_model;
            initial_coordinates = [0.5, log(2.0)],
            write_artifacts = true,
            output_dir = mktempdir(),
        ),
    )
    vector_energy_figures = figure_paths(vector_energy_artifact_result)
    @test isfile(vector_energy_figures[:energy_scale])
    @test occursin("energy = ", read(vector_energy_figures[:energy_scale], String))
    @test verify(vector_energy_artifact_result).artifact_complete

    schedule_control = ControlMap(
        :pump_gain_schedule;
        dimension = 3,
        decode = (x, context) -> (
            pump = [x[1], x[2]],
            gain_offset = x[3],
        ),
        pullback = (physical_gradient, context) -> [
            physical_gradient.pump[1],
            physical_gradient.pump[2],
            physical_gradient.gain_offset,
        ],
        units = "arb.",
        figure_hooks = (:pump_schedule, :gain_profile),
    )
    schedule_model = AdjointModel(
        :schedule_response;
        forward = (decoded_control, context) -> [
            decoded_control.pump[1] + decoded_control.gain_offset,
            decoded_control.pump[2] - decoded_control.gain_offset,
            decoded_control.gain_offset,
        ],
        physical_gradient = (decoded_control, terminal_seed, context) -> (
            pump = [terminal_seed[1], terminal_seed[2]],
            gain_offset = terminal_seed[1] - terminal_seed[2] + terminal_seed[3],
        ),
    )
    schedule_experiment = Experiment(
        fiber,
        schedule_control,
        objective;
        id = "native_structured_schedule",
        solver = Solver(kind = :lbfgs, max_iter = 8, validate_gradient = true),
        maturity = :supported,
    )
    schedule_result = solve(
        schedule_experiment;
        backend = NativeAdjointBackend(
            schedule_model;
            initial_coordinates = [1.0, -2.0, 3.0],
        ),
    )
    @test schedule_result.gradient_check.pass
    @test schedule_result.cost_final < 1e-18
    @test isapprox(decoded_final(schedule_result).pump, [0.0, 0.0]; atol = 1e-8)
    @test isapprox(decoded_final(schedule_result).gain_offset, 0.0; atol = 1e-8)
    @test metrics(schedule_result).gradient_check_pass

    strict_schedule_dir = mktempdir()
    strict_schedule_backend = NativeAdjointBackend(
        schedule_model;
        initial_coordinates = [1.0, -2.0, 3.0],
        write_artifacts = true,
        output_dir = strict_schedule_dir,
        artifact_writers = Dict(:pump_schedule => (context, result) -> nothing),
    )
    @test_throws FiberLabBackendError solve(
        schedule_experiment;
        dry_run = true,
        backend = strict_schedule_backend,
    )
    @test_throws FiberLabBackendError solve(
        schedule_experiment;
        backend = strict_schedule_backend,
    )
    @test isempty(readdir(strict_schedule_dir))

    schedule_artifact_dir = mktempdir()
    schedule_artifact_result = solve(
        schedule_experiment;
        backend = NativeAdjointBackend(
            schedule_model;
            initial_coordinates = [1.0, -2.0, 3.0],
            write_artifacts = true,
            strict_artifacts = false,
            output_dir = schedule_artifact_dir,
            artifact_writers = Dict(
                :pump_schedule => (context, result) -> begin
                    @test context isa NativeArtifactContext
                    @test context.hook == :pump_schedule
                    @test context.output_dir == schedule_artifact_dir
                    path = joinpath(context.output_dir, string(context.tag, "_pump_schedule.txt"))
                    open(path, "w") do io
                        println(io, decoded_final(result).pump)
                    end
                    path
                end,
            ),
        ),
    )
    @test isfile(figure_paths(schedule_artifact_result)[:pump_schedule])
    schedule_artifact_verification = verify(schedule_artifact_result)
    @test !schedule_artifact_verification.artifact_complete
    @test schedule_artifact_verification.artifact_files_exist
    @test schedule_artifact_verification.missing_artifact_hooks == [:gain_profile]
    schedule_sidecar = read(schedule_artifact_result.sidecar_path, String)
    @test occursin("\"artifact_files\"", schedule_sidecar)
    @test occursin("\"pump_schedule\"", schedule_sidecar)
    @test occursin("\"missing_artifact_hooks\"", schedule_sidecar)
    @test occursin("\"gain_profile\"", schedule_sidecar)

    @test_throws FiberLabBackendError solve(
        schedule_experiment;
        backend = NativeAdjointBackend(
            schedule_model;
            initial_coordinates = [1.0, -2.0, 3.0],
            write_artifacts = true,
            output_dir = mktempdir(),
            artifact_writers = Dict(:not_requested => (context, result) -> nothing),
        ),
    )
    @test_throws ArgumentError solve(
        schedule_experiment;
        backend = NativeAdjointBackend(
            schedule_model;
            initial_coordinates = [1.0, -2.0, 3.0],
            write_artifacts = true,
            strict_artifacts = false,
            output_dir = mktempdir(),
            artifact_writers = Dict(
                :pump_schedule => (context, result) ->
                    joinpath(context.output_dir, "missing_artifact.txt"),
            ),
        ),
    )

    launch_control = ControlMap(
        :multimode_launch_weights;
        dimension = 3,
        decode = (x, context) -> (modal_weights = copy(x),),
        pullback = (physical_gradient, context) -> copy(physical_gradient.modal_weights),
        units = "relative mode amplitude",
        figure_hooks = (:mode_weights, :mode_resolved_summary),
    )
    launch_model = AdjointModel(
        :mode_launch_target;
        forward = (decoded_control, context) ->
            decoded_control.modal_weights .- [0.7, -0.2, 0.1],
        physical_gradient = (decoded_control, terminal_seed, context) -> (
            modal_weights = terminal_seed,
        ),
    )
    launch_experiment = Experiment(
        fiber,
        launch_control,
        objective;
        id = "native_multimode_launch_weights",
        solver = Solver(kind = :lbfgs, max_iter = 8, validate_gradient = true),
        maturity = :supported,
    )
    launch_result = solve(
        launch_experiment;
        backend = NativeAdjointBackend(
            launch_model;
            initial_coordinates = [-1.0, 1.0, 2.0],
        ),
    )
    @test launch_result.gradient_check.pass
    @test isapprox(decoded_final(launch_result).modal_weights,
                   [0.7, -0.2, 0.1]; atol = 1e-8)
    @test launch_result.cost_final < 1e-18

    temporal_gate = ControlMap(
        :temporal_gate;
        dimension = 2,
        decode = (x, context) -> (
            center_ps = x[1],
            width_ps = exp(x[2]),
        ),
        pullback = (physical_gradient, context) -> [
            physical_gradient.center_ps,
            physical_gradient.width_ps * context.decoded.width_ps,
        ],
        units = "ps",
        figure_hooks = (:temporal_gate, :pulse_window),
    )
    temporal_model = AdjointModel(
        :temporal_gate_target;
        forward = (decoded_control, context) -> [
            decoded_control.center_ps - 1.0,
            decoded_control.width_ps - 2.0,
        ],
        physical_gradient = (decoded_control, terminal_seed, context) -> (
            center_ps = terminal_seed[1],
            width_ps = terminal_seed[2],
        ),
    )
    temporal_experiment = Experiment(
        fiber,
        temporal_gate,
        objective;
        id = "native_temporal_gate",
        solver = Solver(kind = :lbfgs, max_iter = 30, validate_gradient = true),
        maturity = :supported,
    )
    temporal_result = solve(
        temporal_experiment;
        backend = NativeAdjointBackend(
            temporal_model;
            initial_coordinates = [3.0, log(0.5)],
        ),
    )
    @test temporal_result.gradient_check.pass
    @test isapprox(decoded_final(temporal_result).center_ps, 1.0; atol = 1e-8)
    @test isapprox(decoded_final(temporal_result).width_ps, 2.0; atol = 1e-8)

    window_control = ControlMap(
        :objective_window;
        dimension = 2,
        decode = (x, context) -> (
            lower_thz = x[1],
            upper_thz = x[2],
        ),
        pullback = (physical_gradient, context) -> [
            physical_gradient.lower_thz,
            physical_gradient.upper_thz,
        ],
        units = "THz",
        figure_hooks = (:objective_window_overlay,),
    )
    window_model = AdjointModel(
        :window_target;
        forward = (decoded_control, context) -> [
            decoded_control.lower_thz + 1.5,
            decoded_control.upper_thz - 4.0,
        ],
        physical_gradient = (decoded_control, terminal_seed, context) -> (
            lower_thz = terminal_seed[1],
            upper_thz = terminal_seed[2],
        ),
    )
    window_experiment = Experiment(
        fiber,
        window_control,
        objective;
        id = "native_objective_window",
        solver = Solver(kind = :lbfgs, max_iter = 8, validate_gradient = true),
        maturity = :supported,
    )
    window_result = solve(
        window_experiment;
        backend = NativeAdjointBackend(
            window_model;
            initial_coordinates = [2.0, -3.0],
        ),
    )
    @test window_result.gradient_check.pass
    @test isapprox(decoded_final(window_result).lower_thz, -1.5; atol = 1e-8)
    @test isapprox(decoded_final(window_result).upper_thz, 4.0; atol = 1e-8)

    fiber_design_control = ControlMap(
        :fiber_design_object;
        dimension = 2,
        decode = (x, context) -> TestFiberDesign(x[1], x[2]),
        pullback = (physical_gradient, context) -> [
            physical_gradient.core_radius_um,
            physical_gradient.numerical_aperture,
        ],
        units = "domain object",
        figure_hooks = (:fiber_design_summary,),
    )
    fiber_design_model = AdjointModel(
        :fiber_design_target;
        forward = (decoded_control, context) -> [
            decoded_control.core_radius_um - 25.0,
            decoded_control.numerical_aperture - 0.2,
        ],
        physical_gradient = (decoded_control, terminal_seed, context) ->
            TestFiberDesign(terminal_seed[1], terminal_seed[2]),
    )
    fiber_design_experiment = Experiment(
        fiber,
        fiber_design_control,
        objective;
        id = "native_custom_fiber_design_object",
        solver = Solver(kind = :lbfgs, max_iter = 8, validate_gradient = true),
        maturity = :supported,
    )
    fiber_design_result = solve(
        fiber_design_experiment;
        backend = NativeAdjointBackend(
            fiber_design_model;
            initial_coordinates = [10.0, 0.5],
        ),
    )
    @test fiber_design_result.gradient_check.pass
    @test decoded_final(fiber_design_result) isa TestFiberDesign
    @test isapprox(decoded_final(fiber_design_result).core_radius_um, 25.0; atol = 1e-8)
    @test isapprox(decoded_final(fiber_design_result).numerical_aperture, 0.2; atol = 1e-8)

    @test_throws ArgumentError NativeAdjointBackend(
        model;
        initial_coordinates = [NaN],
    )
    @test_throws ArgumentError NativeAdjointBackend(
        model;
        initial_coordinates = [2.0],
        step_size = 0.0,
    )
    @test_throws ArgumentError NativeAdjointBackend(
        model;
        initial_coordinates = [2.0],
        artifact_writers = Dict(:bad_writer => "not a function"),
    )
    @test_throws ArgumentError solve(
        experiment;
        backend = NativeAdjointBackend(model; initial_coordinates = [2.0, 3.0]),
    )

    symbolic_experiment = Experiment(
        fiber,
        Control(variables = (:phase,)),
        Objective(kind = :raman_band);
        id = "native_symbolic_rejected",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    @test_throws FiberLabBackendError solve(
        symbolic_experiment;
        backend = NativeAdjointBackend(model; initial_coordinates = [0.0]),
    )

    unsupported_solver_experiment = Experiment(
        fiber,
        control,
        objective;
        id = "native_unsupported_solver",
        solver = Solver(kind = :nelder_mead, max_iter = 1),
        maturity = :supported,
    )
    unsupported_solver_backend = NativeAdjointBackend(model; initial_coordinates = [2.0])
    @test_throws FiberLabBackendError solve(
        unsupported_solver_experiment;
        dry_run = true,
        backend = unsupported_solver_backend,
    )
    @test_throws FiberLabBackendError solve(
        unsupported_solver_experiment;
        backend = unsupported_solver_backend,
    )

    wrong_gradient_model = AdjointModel(
        :wrong_native_gradient;
        forward = (decoded_control, context) -> [decoded_control],
        physical_gradient = (decoded_control, terminal_seed, context) -> -terminal_seed,
    )
    @test_throws FiberLabBackendError solve(
        validated_experiment;
        backend = NativeAdjointBackend(
            wrong_gradient_model;
            initial_coordinates = [2.0],
        ),
    )

    bad_gradient_model = AdjointModel(
        :bad_gradient;
        forward = (decoded_control, context) -> [decoded_control],
        physical_gradient = (decoded_control, terminal_seed, context) -> [NaN],
    )
    @test_throws ArgumentError solve(
        experiment;
        backend = NativeAdjointBackend(
            bad_gradient_model;
            initial_coordinates = [2.0],
        ),
    )

    missing_block_gradient_model = AdjointModel(
        :missing_block_gradient;
        forward = (decoded_control, context) ->
            [decoded_control.phase_scale, decoded_control.energy],
        physical_gradient = (decoded_control, terminal_seed, context) -> (
            phase_scale = [terminal_seed[1]],
        ),
    )
    @test_throws ArgumentError solve(
        multivar_experiment;
        backend = NativeAdjointBackend(
            missing_block_gradient_model;
            initial_coordinates = [2.0, -4.0],
        ),
    )
end

@testset "FiberLab native physics adapter" begin
    fiber = Fiber(
        preset = :SMF28_beta2_only,
        length_m = 1e-4,
        power_w = 1e-5,
        beta_order = 2,
    )
    grid = Grid(nt = 16, time_window_ps = 5.0, policy = :exact)
    pulse = Pulse(fwhm_s = 1e-12, rep_rate_hz = 50e6, shape = :gaussian)
    problem = fiber_problem(
        fiber;
        pulse = pulse,
        grid = grid,
        raman_threshold_thz = -0.25,
    )
    @test problem isa FiberProblem
    @test problem isa FiberFieldProblem
    @test problem isa SingleModeFiberProblem
    @test size(problem.uω0) == (16, 1)
    @test sample_count(problem) == 16
    @test mode_count(problem) == 1
    @test length(frequency_offsets(problem)) == sample_count(problem)
    @test any(problem.band_mask)
    problem_summary = summarize(problem)
    @test problem_summary.preset == :SMF28_beta2_only
    @test problem_summary.samples == sample_count(problem)
    @test problem_summary.modes == mode_count(problem)
    @test problem_summary.raman_threshold_thz == -0.25
    @test problem_summary.band_bins == count(problem.band_mask)
    @test problem_summary.reference_power_w == fiber.power_w
    @test problem.metadata.requested_fiber == fiber
    @test problem.metadata.requested_pulse == pulse
    @test problem.metadata.requested_grid == grid

    auto_grid = Grid(nt = 16, time_window_ps = 1.0, policy = :auto_if_undersized)
    auto_problem = fiber_problem(
        fiber;
        grid = auto_grid,
        raman_threshold_thz = -0.25,
    )
    @test auto_problem.metadata.requested_grid == auto_grid
    @test auto_problem.sim["Nt"] > auto_grid.nt
    @test auto_problem.sim["time_window"] > auto_grid.time_window_ps
    @test_throws ArgumentError fiber_problem(Fiber(
        preset = :SMF28_beta2_only,
        length_m = 1e-4,
        power_w = 0.0,
        beta_order = 2,
    ))
    @test_throws ArgumentError fiber_problem(
        fiber;
        pulse = Pulse(fwhm_s = 0.0),
        grid = grid,
    )
    @test_throws ArgumentError fiber_problem(fiber; modes = 2, grid = grid)

    negative_dt = deepcopy(problem.sim)
    negative_dt["Δt"] *= -1
    @test_throws ArgumentError fiber_field_problem(problem.uω0, problem.fiber, negative_dt)
    inconsistent_omega = deepcopy(problem.sim)
    inconsistent_omega["ωs"] = zeros(sample_count(problem))
    @test_throws ArgumentError fiber_field_problem(
        problem.uω0,
        problem.fiber,
        inconsistent_omega,
    )
    short_raman = deepcopy(problem.fiber)
    short_raman["hRω"] = short_raman["hRω"][1:end-1]
    @test_throws ArgumentError fiber_field_problem(problem.uω0, short_raman, problem.sim)
    @test_throws MethodError fiber_field_problem(
        problem.uω0,
        problem.fiber,
        problem.sim;
        requested_fiber = fiber,
    )
    @test_throws ArgumentError fiber_problem(
        fiber;
        pulse = pulse,
        grid = grid,
        raman_threshold_thz = Inf,
    )

    setup_experiment = Experiment(
        fiber,
        Control(variables = (:phase,)),
        Objective(kind = :raman_band, log_cost = false);
        id = "native_physics_setup",
        pulse = pulse,
        grid = grid,
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    experiment_problem = single_mode_fiber_problem(
        setup_experiment;
        raman_threshold_thz = -0.25,
    )
    universal_experiment_problem = fiber_problem(
        setup_experiment;
        raman_threshold_thz = -0.25,
    )
    @test sample_count(experiment_problem) == sample_count(problem)
    @test experiment_problem.fiber["L"] == problem.fiber["L"]
    @test universal_experiment_problem isa FiberProblem
    @test sample_count(universal_experiment_problem) == sample_count(problem)
    @test universal_experiment_problem.fiber["L"] == problem.fiber["L"]

    bandless_direct_problem = fiber_problem(
        fiber;
        grid = grid,
        raman_threshold_thz = nothing,
    )
    @test bandless_direct_problem.band_mask === nothing

    control = FullGridPhase(problem)
    @test dimension(control) == sample_count(problem)
    objective = raman_band_objective(problem; log_cost = false)
    model = fiber_model(problem)
    @test model isa AdjointModel
    @test length(problem.metadata.construction_sha256) == 64
    coordinates = zeros(sample_count(problem))
    explicit_problem = fiber_field_problem(
        problem.uω0,
        problem.fiber,
        problem.sim;
        band_mask = problem.band_mask,
        preset = :explicit_test_problem,
    )
    explicit_model = fiber_model(explicit_problem)
    explicit_objective = raman_band_objective(explicit_problem; log_cost = false)
    @test explicit_model.run_source === nothing
    @test explicit_model.problem_source !== nothing
    @test explicit_problem.metadata.construction_sha256 === nothing
    @test isfinite(run_adjoint_step(
        explicit_model,
        control,
        explicit_objective,
        coordinates,
    ).cost)
    @test check_adjoint_gradient(
        explicit_model,
        control,
        explicit_objective,
        coordinates;
        coordinate_indices = [1],
        step = 1e-5,
        atol = 1e-6,
        rtol = 5e-2,
    ).pass
    explicit_result = solve(
        explicit_model,
        control,
        explicit_objective,
        coordinates;
        id = "explicit_numerical_metadata",
        max_iter = 1,
        gradient_tolerance = 1e99,
        write_artifacts = true,
        output_dir = mktempdir(),
        maturity = :supported,
    )
    @test ismissing(explicit_result.plan.experiment.fiber)
    @test ismissing(explicit_result.plan.experiment.pulse)
    @test explicit_result.plan.experiment.grid ==
        Grid(nt = problem.sim["Nt"], time_window_ps = problem.sim["time_window"], policy = :exact)
    @test explicit_result.plan.experiment.metadata_authority == :resolved_numerical
    explicit_sidecar = FiberLab.JSON3.read(
        read(explicit_result.sidecar_path, String),
        Dict{String,Any},
    )
    @test explicit_sidecar["metadata_authority"] == "resolved_numerical"
    @test explicit_sidecar["experiment_summary"]["fiber"] === nothing
    @test explicit_sidecar["experiment_summary"]["pulse"] === nothing
    @test explicit_sidecar["experiment_summary"]["grid"]["nt"] == problem.sim["Nt"]
    @test explicit_sidecar["source_metadata"] === nothing
    @test_throws ArgumentError solve(
        explicit_model,
        control,
        explicit_objective,
        coordinates;
        fiber = fiber,
        max_iter = 1,
    )
    @test_throws ArgumentError solve(
        explicit_model,
        control,
        explicit_objective,
        coordinates;
        fiber = Fiber(
            regime = :multimode,
            preset = :custom,
            length_m = problem.fiber["L"],
            power_w = fiber.power_w,
            beta_order = problem.sim["β_order"],
        ),
        pulse = pulse,
        grid = Grid(nt = problem.sim["Nt"], time_window_ps = problem.sim["time_window"], policy = :exact),
        max_iter = 1,
    )
    @test_throws ArgumentError solve(
        explicit_model,
        control,
        explicit_objective,
        coordinates;
        fiber = fiber,
        pulse = pulse,
        grid = Grid(nt = 32, time_window_ps = 7.0, policy = :exact),
        max_iter = 1,
    )
    @test_throws ArgumentError FiberLab._single_mode_fields(
        fill(NaN, sample_count(problem)),
        problem,
    )
    @test_throws ArgumentError FiberLab._single_mode_fields(
        (
            phase = zeros(sample_count(problem)),
            amplitude = fill(Inf, sample_count(problem)),
            energy = 1.0,
        ),
        problem,
    )
    step = run_adjoint_step(model, control, objective, coordinates)
    @test step.cost >= 0
    @test isfinite(step.cost)
    @test size(step.forward_state) == size(problem.uω0)
    @test length(gradient_vector(step)) == sample_count(problem)
    @test all(isfinite, gradient_vector(step))

    gradient_check = check_adjoint_gradient(
        model,
        control,
        objective,
        coordinates;
        coordinate_indices = [2, 9],
        step = 1e-5,
        atol = 1e-6,
        rtol = 5e-2,
    )
    @test gradient_check.pass

    basis = hcat(
        ones(sample_count(problem)),
        range(-1.0, 1.0; length = sample_count(problem)),
    )
    demo_basis = polynomial_basis(problem, 0:2)
    @test size(demo_basis) == (sample_count(problem), 3)
    smooth_basis = fourier_basis(problem, 2)
    @test size(smooth_basis) == (sample_count(problem), 5)
    @test all(isfinite, smooth_basis)
    @test smooth_basis[:, 1] == ones(sample_count(problem))
    bounded_full_phase = phase_control(problem; bounds = (-0.2, 0.2))
    @test dimension(bounded_full_phase) == sample_count(problem)
    bounded_phase_values = decode(
        bounded_full_phase,
        fill(0.5, dimension(bounded_full_phase)),
    )
    @test all(abs.(bounded_phase_values) .<= 0.2)
    @test length(pullback(
        bounded_full_phase,
        ones(sample_count(problem)),
        evaluate_control(bounded_full_phase, fill(0.5, dimension(bounded_full_phase))),
    )) == sample_count(problem)
    demo_control = controls(
        phase_control(problem; basis = demo_basis, bounds = (-0.1, 0.1)),
        amplitude_control(problem; basis = demo_basis, bounds = (0.9, 1.1)),
        energy_control(),
    )
    @test dimension(demo_control) == 7
    @test length(initial_coordinates(demo_control)) == dimension(demo_control)
    demo_decoded = decode(demo_control, initial_coordinates(demo_control))
    @test hasproperty(demo_decoded, :phase)
    @test hasproperty(demo_decoded, :amplitude)
    @test hasproperty(demo_decoded, :energy)
    @test all(abs.(demo_decoded.phase) .<= 0.1)
    @test all(demo_decoded.amplitude .>= 0.9)
    @test all(demo_decoded.amplitude .<= 1.1)
    @test demo_decoded.energy == 1.0

    basis_control = PhaseBasis(basis; name = :two_parameter_phase)
    basis_check = check_adjoint_gradient(
        model,
        basis_control,
        objective,
        [0.01, -0.02];
        coordinate_indices = [1, 2],
        step = 1e-5,
        atol = 1e-6,
        rtol = 5e-2,
    )
    @test basis_check.pass

    weights = reshape(collect(range(0.5, 1.5; length = sample_count(problem))), :, 1)
    custom_objective = ObjectiveMap(
        :test_researcher_defined_field_metric;
        cost = field -> sum(weights .* abs2.(field)),
        terminal_adjoint = (field, context) -> weights .* field,
        figure_hooks = (:test_researcher_defined_summary,),
    )
    custom_check = check_adjoint_gradient(
        model,
        basis_control,
        custom_objective,
        [0.01, -0.02];
        coordinate_indices = [1, 2],
        step = 1e-5,
        atol = 1e-6,
        rtol = 5e-2,
    )
    @test custom_check.pass

    bandless_problem = fiber_field_problem(
        problem.uω0,
        problem.fiber,
        problem.sim;
        preset = :test_bandless_single_mode,
    )
    @test bandless_problem.band_mask === nothing
    @test ismissing(bandless_problem.metadata.requested_fiber)
    @test_throws ArgumentError FiberLab._standard_reference_power(bandless_problem)
    @test_throws ArgumentError FiberLab._standard_pulse(bandless_problem)
    @test_throws ArgumentError FiberLab._standard_raman_threshold(bandless_problem)
    bandless_custom_check = check_adjoint_gradient(
        fiber_model(bandless_problem),
        basis_control,
        custom_objective,
        [0.01, -0.02];
        coordinate_indices = [1, 2],
        step = 1e-5,
        atol = 1e-6,
        rtol = 5e-2,
    )
    @test bandless_custom_check.pass
    @test_throws ArgumentError raman_band_objective(bandless_problem)

    multivar_physics_control = ControlSpace(
        :phase => basis_control,
        :amplitude => AmplitudeBasis(basis; scale = 0.02),
        :energy => PositiveScalar(:energy),
    )
    multivar_physics_check = check_adjoint_gradient(
        fiber_model(problem),
        multivar_physics_control,
        objective,
        [0.01, -0.02, 0.03, -0.01, log(1.02)];
        coordinate_indices = [1, 3, 5],
        step = 1e-5,
        atol = 1e-6,
        rtol = 5e-2,
    )
    @test multivar_physics_check.pass

    bounded_phase_control = ControlMap(
        :phase;
        dimension = 2,
        decode = (x, context) -> 0.05 .* tanh.(basis * x),
        pullback = (physical_gradient, context) -> begin
            z = basis * context.coordinates
            0.05 .* (transpose(basis) * (Float64.(collect(physical_gradient)) .* (1 .- tanh.(z).^2)))
        end,
        figure_hooks = (:phase_profile, :group_delay),
    )
    bounded_amplitude_control = ControlMap(
        :amplitude;
        dimension = 2,
        decode = (x, context) -> 1.0 .+ 0.01 .* tanh.(basis * x),
        pullback = (physical_gradient, context) -> begin
            z = basis * context.coordinates
            0.01 .* (transpose(basis) * (Float64.(collect(physical_gradient)) .* (1 .- tanh.(z).^2)))
        end,
        figure_hooks = (:amplitude_profile,),
    )
    multivar_artifact_control = ControlSpace(
        :phase => bounded_phase_control,
        :amplitude => bounded_amplitude_control,
        :energy => PositiveScalar(:energy; figure_hooks = (:energy_scale,)),
    )
    multivar_artifact_result = solve(
        problem,
        multivar_artifact_control,
        objective,
        [0.01, -0.02, 0.03, -0.01, log(1.02)];
        id = "native_multivar_physics_artifacts",
        max_iter = 1,
        write_artifacts = true,
        output_dir = mktempdir(),
        maturity = :supported,
        step_size = 1e-3,
        gradient_tolerance = 1e99,
    )
    multivar_artifacts = figure_paths(multivar_artifact_result)
    @test isfile(multivar_artifacts[:field_summary])
    @test isfile(multivar_artifacts[:convergence_trace])
    @test isfile(multivar_artifacts[:phase_profile])
    @test isfile(multivar_artifacts[:group_delay])
    @test isfile(multivar_artifacts[:amplitude_profile])
    @test isfile(multivar_artifacts[:energy_scale])
    @test FiberLab._native_png_passes_audit(multivar_artifacts[:field_summary])
    @test FiberLab._native_png_passes_audit(multivar_artifacts[:phase_profile])
    @test FiberLab._native_png_passes_audit(multivar_artifacts[:group_delay])
    @test FiberLab._native_png_passes_audit(multivar_artifacts[:amplitude_profile])
    @test verify(multivar_artifact_result).artifact_complete
    @test multivar_artifact_result.backend.run_source.problem !== problem
    @test FiberLab._same_resolved_problem(
        problem,
        multivar_artifact_result.backend.run_source.problem,
    )
    native_sidecar = FiberLab.JSON3.read(
        read(multivar_artifact_result.sidecar_path, String),
        Dict{String,Any},
    )
    @test native_sidecar["experiment_summary"]["fiber"]["power_w"] == fiber.power_w
    @test native_sidecar["experiment_summary"]["pulse"]["fwhm_s"] == pulse.fwhm_s
    source_metadata = native_sidecar["source_metadata"]
    @test source_metadata["requested_fiber"]["preset"] == String(fiber.preset)
    @test source_metadata["requested_fiber"]["power_w"] == fiber.power_w
    @test source_metadata["requested_pulse"]["fwhm_s"] == pulse.fwhm_s
    @test source_metadata["requested_grid"]["nt"] == grid.nt
    @test source_metadata["requested_grid"]["policy"] == String(grid.policy)
    @test source_metadata["resolved_grid"]["nt"] == problem.sim["Nt"]
    @test source_metadata["resolved_grid"]["time_window_ps"] == problem.sim["time_window"]
    @test source_metadata["wavelength_m"] == problem.sim["λ0"]
    @test source_metadata["modes"] == problem.sim["M"]
    @test source_metadata["raman_response"]["model"] ==
        "blow_wood_single_damped_oscillator_v1"
    @test source_metadata["raman_response"]["fraction"] == 0.18
    @test source_metadata["raman_response"]["tau1_fs"] == 12.2
    @test source_metadata["raman_response"]["tau2_fs"] == 32.0
    @test source_metadata["construction_sha256"] == problem.metadata.construction_sha256
    @test length(source_metadata["snapshot_sha256"]) == 64
    @test native_sidecar["objective_problem_sha256"] == source_metadata["snapshot_sha256"]
    @test native_sidecar["resolved_problem_sha256"] == source_metadata["snapshot_sha256"]
    @test native_sidecar["metadata_authority"] == "authoritative"

    mismatched_problem = fiber_problem(
        Fiber(
            preset = fiber.preset,
            length_m = fiber.length_m,
            power_w = 2 * fiber.power_w,
            beta_order = fiber.beta_order,
        );
        pulse = pulse,
        grid = grid,
        raman_threshold_thz = -0.25,
    )
    @test_throws ArgumentError standard_figures(
        mismatched_problem,
        multivar_artifact_result;
        output_dir = mktempdir(),
        n_z_samples = 2,
    )
    run_snapshot = multivar_artifact_result.backend.run_source.problem
    original_launch_value = run_snapshot.uω0[1, 1]
    run_snapshot.uω0[1, 1] = 2 * original_launch_value
    @test_throws ArgumentError standard_figures(
        problem,
        multivar_artifact_result;
        output_dir = mktempdir(),
        n_z_samples = 2,
    )
    run_snapshot.uω0[1, 1] = original_launch_value

    standard_artifacts = standard_figures(
        problem,
        multivar_artifact_result;
        output_dir = mktempdir(),
        tag = "native_standard_figures",
        n_z_samples = 2,
        also_unshaped = false,
    )
    @test isfile(standard_artifacts.metric_summary)
    @test isfile(standard_artifacts.evolution_comparison)
    @test isfile(standard_artifacts.phase_profile)
    @test isfile(standard_artifacts.evolution)
    @test isfile(standard_artifacts.phase_diagnostic)
    @test !haskey(pairs(standard_artifacts), :evolution_unshaped)
    @test FiberLab._native_png_passes_audit(standard_artifacts.metric_summary)
    @test FiberLab._native_png_passes_audit(standard_artifacts.evolution_comparison)
    @test FiberLab._native_png_passes_audit(standard_artifacts.phase_profile)
    @test FiberLab._native_png_passes_audit(standard_artifacts.evolution)
    @test FiberLab._native_png_passes_audit(standard_artifacts.phase_diagnostic)

    multimode_sim = FiberLab.get_disp_sim_params(1550e-9, 2, 16, 5.0, 2)
    _, multimode_uω0 = FiberLab.get_initial_state(
        [1 / sqrt(2), 1im / sqrt(2)],
        1e-5,
        185e-15,
        80.5e6,
        "sech_sq",
        multimode_sim,
    )
    raman_fiber = FiberLab.get_disp_fiber_params_user_defined(
        1e-4,
        multimode_sim;
        gamma_user = 1.0e-3,
        betas_user = [0.0],
    )
    multimode_gamma = zeros(Float64, 2, 2, 2, 2)
    multimode_gamma[1, 1, 1, 1] = 1.0e-3
    multimode_gamma[2, 2, 2, 2] = 0.8e-3
    for indices in (
        (1, 1, 2, 2), (1, 2, 1, 2), (1, 2, 2, 1),
        (2, 1, 1, 2), (2, 1, 2, 1), (2, 2, 1, 1),
    )
        multimode_gamma[indices...] = 0.15e-3
    end
    multimode_fiber = Dict{String,Any}(
        "ϕ" => nothing,
        "Dω" => hcat(zeros(16), 1.0e-4 .* collect(range(-1.0, 1.0; length = 16))),
        "γ" => multimode_gamma,
        "L" => 1e-4,
        "hRω" => raman_fiber["hRω"],
        "one_m_fR" => raman_fiber["one_m_fR"],
        "zsave" => nothing,
        "x" => nothing,
        "gain_parameters" => 0.0,
    )
    explicit_multimode_problem = fiber_problem(
        Matrix{ComplexF64}(multimode_uω0),
        multimode_fiber,
        multimode_sim;
        band_mask = FFTW.fftfreq(16, 1 / multimode_sim["Δt"]) .< -0.25,
        preset = :test_two_mode,
    )
    multimode_problem = fiber_problem(
        Fiber(regime = :multimode, preset = :test_two_mode, length_m = 1e-4, power_w = 1e-5);
        modes = 2,
        grid = grid,
        initial_modes = [1 / sqrt(2), 1im / sqrt(2)],
        dispersion = multimode_fiber["Dω"],
        gamma_tensor = multimode_gamma,
        band_mask = FFTW.fftfreq(16, 1 / multimode_sim["Δt"]) .< -0.25,
    )
    @test explicit_multimode_problem isa FiberProblem
    @test multimode_problem isa FiberFieldProblem
    @test size(multimode_problem.uω0) == (16, 2)
    @test multimode_problem.sim["M"] == 2
    @test multimode_problem.fiber["Dω"] == explicit_multimode_problem.fiber["Dω"]
    @test ismissing(explicit_multimode_problem.metadata.requested_fiber)
    @test multimode_problem.metadata.requested_fiber.regime == :multimode
    @test multimode_problem.metadata.preset == :test_two_mode
    @test_throws ArgumentError fiber_problem(
        Fiber(regime = :multimode, preset = :custom, length_m = 1e-4, power_w = 1e-5);
        modes = 2,
        grid = grid,
    )

    multimode_control = ControlSpace(
        :phase => basis_control,
        :amplitude => AmplitudeBasis(basis; scale = 0.01),
        :energy => PositiveScalar(:energy),
    )
    @test_throws ArgumentError solve(
        fiber_model(explicit_multimode_problem),
        multimode_control,
        mode_sum_objective(explicit_multimode_problem; log_cost = false),
        [0.01, -0.02, 0.02, -0.01, log(0.98)];
        fiber = Fiber(
            regime = :single_mode,
            preset = :custom,
            length_m = explicit_multimode_problem.fiber["L"],
            power_w = 1e-5,
            beta_order = explicit_multimode_problem.sim["β_order"],
        ),
        pulse = Pulse(),
        grid = Grid(
            nt = explicit_multimode_problem.sim["Nt"],
            time_window_ps = explicit_multimode_problem.sim["time_window"],
            policy = :exact,
        ),
        max_iter = 1,
    )
    multimode_model = fiber_model(multimode_problem)
    multimode_step = run_adjoint_step(
        multimode_model,
        multimode_control,
        mode_sum_objective(multimode_problem; log_cost = false),
        [0.01, -0.02, 0.02, -0.01, log(0.98)],
    )
    @test size(multimode_step.forward_state) == (16, 2)
    @test length(gradient_vector(multimode_step)) == 5
    @test all(isfinite, gradient_vector(multimode_step))
    multimode_check = check_adjoint_gradient(
        multimode_model,
        multimode_control,
        mode_sum_objective(multimode_problem; log_cost = false),
        [0.01, -0.02, 0.02, -0.01, log(0.98)];
        coordinate_indices = [1, 3, 5],
        step = 1e-5,
        atol = 1e-6,
        rtol = 5e-2,
    )
    @test multimode_check.pass
    multimode_fundamental_check = check_adjoint_gradient(
        multimode_model,
        multimode_control,
        fundamental_mode_objective(multimode_problem; log_cost = false),
        [0.01, -0.02, 0.02, -0.01, log(0.98)];
        coordinate_indices = [1, 5],
        step = 1e-5,
        atol = 1e-6,
        rtol = 5e-2,
    )
    @test multimode_fundamental_check.pass
    multimode_worst_check = check_adjoint_gradient(
        multimode_model,
        multimode_control,
        worst_mode_objective(multimode_problem; log_cost = false),
        [0.01, -0.02, 0.02, -0.01, log(0.98)];
        coordinate_indices = [1, 5],
        step = 1e-5,
        atol = 1e-6,
        rtol = 5e-2,
    )
    @test multimode_worst_check.pass

    multimode_bounded_phase = ControlMap(
        :phase;
        dimension = 2,
        decode = (x, context) -> 0.05 .* tanh.(basis * x),
        pullback = (physical_gradient, context) -> begin
            z = basis * context.coordinates
            0.05 .* (transpose(basis) * (Float64.(collect(physical_gradient)) .* (1 .- tanh.(z).^2)))
        end,
        figure_hooks = (:phase_profile, :group_delay),
    )
    multimode_bounded_amplitude = ControlMap(
        :amplitude;
        dimension = 2,
        decode = (x, context) -> 1.0 .+ 0.01 .* tanh.(basis * x),
        pullback = (physical_gradient, context) -> begin
            z = basis * context.coordinates
            0.01 .* (transpose(basis) * (Float64.(collect(physical_gradient)) .* (1 .- tanh.(z).^2)))
        end,
        figure_hooks = (:amplitude_profile,),
    )
    multimode_artifact_control = ControlSpace(
        :phase => multimode_bounded_phase,
        :amplitude => multimode_bounded_amplitude,
        :energy => PositiveScalar(:energy; figure_hooks = (:energy_scale,)),
    )
    multimode_artifact_result = solve(
        multimode_model,
        multimode_artifact_control,
        mode_sum_objective(multimode_problem; log_cost = false),
        [0.01, -0.02, 0.02, -0.01, log(0.98)];
        fiber = Fiber(
            regime = :multimode,
            preset = :test_two_mode,
            length_m = 1e-4,
            power_w = 1e-5,
        ),
        grid = grid,
        id = "native_multimode_physics_artifacts",
        max_iter = 1,
        write_artifacts = true,
        output_dir = mktempdir(),
        maturity = :supported,
        step_size = 1e-3,
        gradient_tolerance = 1e99,
    )
    multimode_artifacts = figure_paths(multimode_artifact_result)
    @test isfile(multimode_artifacts[:field_summary])
    @test isfile(multimode_artifacts[:mode_resolved_spectra])
    @test isfile(multimode_artifacts[:per_mode_leakage_table])
    @test isfile(multimode_artifacts[:convergence_trace])
    @test isfile(multimode_artifacts[:phase_profile])
    @test isfile(multimode_artifacts[:group_delay])
    @test isfile(multimode_artifacts[:amplitude_profile])
    @test isfile(multimode_artifacts[:energy_scale])
    @test FiberLab._native_png_passes_audit(multimode_artifacts[:field_summary])
    @test FiberLab._native_png_passes_audit(multimode_artifacts[:mode_resolved_spectra])
    @test FiberLab._native_png_passes_audit(multimode_artifacts[:phase_profile])
    @test FiberLab._native_png_passes_audit(multimode_artifacts[:group_delay])
    @test FiberLab._native_png_passes_audit(multimode_artifacts[:amplitude_profile])
    @test occursin("mode,total_power,peak_power",
                   read(multimode_artifacts[:per_mode_leakage_table], String))
    @test verify(multimode_artifact_result).artifact_complete

    result = solve(
        model,
        control,
        objective,
        coordinates;
        fiber = fiber,
        pulse = pulse,
        grid = grid,
        id = "direct_native_physics_phase_smoke",
        max_iter = 1,
        step_size = 1e-3,
        maturity = :supported,
    )
    @test result isa NativeAdjointResult
    @test result.plan.experiment.id == "direct_native_physics_phase_smoke"
    @test isfinite(result.cost_final)
    @test length(result.x_final) == problem.sim["Nt"]
    @test verify(result).finite_final_coordinates
    mutated_before_model = deepcopy(problem)
    mutated_before_model.uω0 .*= 2
    @test_throws ArgumentError fiber_model(mutated_before_model)
    @test_throws ArgumentError solve(
        mutated_before_model,
        control,
        raman_band_objective(mutated_before_model; log_cost = false),
        coordinates;
        max_iter = 1,
    )
    edited_explicit_problem = fiber_field_problem(
        mutated_before_model.uω0,
        mutated_before_model.fiber,
        mutated_before_model.sim;
        band_mask = mutated_before_model.band_mask,
        preset = :edited_explicit_problem,
    )
    @test edited_explicit_problem.metadata.construction_sha256 === nothing
    @test fiber_model(edited_explicit_problem).problem_source !== nothing
    mutated_before_solve = deepcopy(problem)
    stale_model = fiber_model(mutated_before_solve)
    mutated_before_solve.fiber["Dω"][1, 1] += 1
    @test_throws ArgumentError run_adjoint_step(
        stale_model,
        control,
        objective,
        coordinates,
    )
    @test_throws ArgumentError check_adjoint_gradient(
        stale_model,
        control,
        objective,
        coordinates;
        coordinate_indices = [1],
    )
    @test_throws FiberLabBackendError solve(
        stale_model,
        control,
        objective,
        coordinates;
        fiber = fiber,
        pulse = pulse,
        grid = grid,
        max_iter = 1,
    )
    @test_throws ArgumentError solve(
        model,
        control,
        objective,
        coordinates;
        fiber = Fiber(
            preset = :HNLF,
            length_m = fiber.length_m,
            power_w = fiber.power_w,
            beta_order = fiber.beta_order,
        ),
        pulse = pulse,
        grid = grid,
        max_iter = 1,
    )
    false_metadata_output = mktempdir()
    false_metadata_experiment = Experiment(
        Fiber(preset = :HNLF, length_m = fiber.length_m, power_w = 99.0),
        control,
        objective;
        id = "false_native_model_metadata",
        pulse = Pulse(fwhm_s = 999e-15),
        grid = Grid(nt = 32, time_window_ps = 7.0, policy = :exact),
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    false_metadata_backend = NativeAdjointBackend(
        model;
        initial_coordinates = coordinates,
        max_iter = 1,
        write_artifacts = true,
        output_dir = false_metadata_output,
    )
    @test_throws FiberLabBackendError solve(
        false_metadata_experiment;
        dry_run = true,
        backend = false_metadata_backend,
    )
    @test_throws FiberLabBackendError solve(
        false_metadata_experiment;
        backend = false_metadata_backend,
    )
    @test isempty(readdir(false_metadata_output))
    explicit_claim_experiment = Experiment(
        fiber,
        control,
        explicit_objective;
        id = "unlabeled_explicit_model_metadata",
        pulse = pulse,
        grid = Grid(nt = problem.sim["Nt"], time_window_ps = problem.sim["time_window"], policy = :exact),
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    @test_throws FiberLabBackendError solve(
        explicit_claim_experiment;
        backend = NativeAdjointBackend(
            explicit_model;
            initial_coordinates = coordinates,
            max_iter = 1,
        ),
    )
    @test_throws MethodError solve(
        model,
        control,
        objective,
        coordinates;
        fiber = fiber,
        pulse = pulse,
        grid = grid,
        source_problem = problem,
        max_iter = 1,
    )

    problem_result = solve(
        problem,
        control,
        objective,
        coordinates;
        id = "problem_native_physics_phase_smoke",
        max_iter = 1,
        step_size = 1e-3,
        maturity = :supported,
    )
    @test problem_result isa NativeAdjointResult
    @test problem_result.plan.experiment.id == "problem_native_physics_phase_smoke"
    @test problem_result.plan.experiment.fiber.regime == :single_mode
    @test problem_result.plan.experiment.fiber.power_w == fiber.power_w
    @test problem_result.plan.experiment.fiber.preset == problem.metadata.preset
    @test problem_result.plan.experiment.fiber.length_m == problem.fiber["L"]
    @test problem_result.plan.experiment.fiber.beta_order == problem.sim["β_order"]
    @test problem_result.plan.experiment.pulse == problem.metadata.requested_pulse
    @test problem_result.plan.experiment.grid.nt == problem.sim["Nt"]
    @test problem_result.plan.experiment.grid.time_window_ps == problem.sim["time_window"]
    @test problem_result.backend.run_source.metadata.requested_grid == grid
    @test problem_result.backend.run_source.metadata.resolved_grid ==
        Grid(nt = problem.sim["Nt"], time_window_ps = problem.sim["time_window"], policy = :exact)
    @test problem_result.backend.run_source.metadata.requested_pulse == pulse
    @test isfinite(problem_result.cost_final)
    @test length(problem_result.x_final) == sample_count(problem)

    other_band_problem = fiber_problem(
        fiber;
        pulse = pulse,
        grid = grid,
        raman_threshold_thz = -0.05,
    )
    other_band_objective = raman_band_objective(other_band_problem; log_cost = false)
    @test_throws ArgumentError run_adjoint_step(
        model,
        control,
        other_band_objective,
        coordinates,
    )
    @test_throws ArgumentError check_adjoint_gradient(
        model,
        control,
        other_band_objective,
        coordinates;
        coordinate_indices = [1],
    )
    @test_throws FiberLabBackendError solve(
        problem,
        control,
        other_band_objective,
        coordinates;
        max_iter = 1,
    )

    @test_throws ArgumentError solve(
        bandless_problem,
        basis_control,
        custom_objective,
        [0.01, -0.02];
        id = "problem_missing_power_metadata",
        max_iter = 1,
        maturity = :supported,
    )
    @test_throws ArgumentError solve(
        problem,
        control,
        objective,
        coordinates;
        fiber = Fiber(preset = :HNLF, length_m = fiber.length_m, power_w = 99.0),
        max_iter = 1,
    )
    @test_throws ArgumentError solve(
        problem,
        control,
        objective,
        coordinates;
        pulse = Pulse(fwhm_s = 999e-15),
        max_iter = 1,
    )
    @test_throws ArgumentError solve(
        problem,
        control,
        objective,
        coordinates;
        grid = Grid(nt = 32, time_window_ps = 5.0, policy = :exact),
        max_iter = 1,
    )
    @test_throws ArgumentError solve(
        bandless_problem,
        basis_control,
        custom_objective,
        [0.01, -0.02];
        reference_power_w = fiber.power_w,
        id = "problem_explicit_power_metadata",
        max_iter = 1,
        maturity = :supported,
    )

    multimode_problem_result = solve(
        multimode_problem,
        multimode_control,
        mode_sum_objective(multimode_problem; log_cost = false),
        [0.01, -0.02, 0.02, -0.01, log(0.98)];
        id = "problem_native_multimode_smoke",
        max_iter = 1,
        step_size = 1e-3,
        maturity = :supported,
        gradient_tolerance = 1e99,
    )
    @test multimode_problem_result isa NativeAdjointResult
    @test multimode_problem_result.plan.experiment.fiber.regime == :multimode
    @test size(multimode_problem_result.final_step.forward_state) == (16, 2)

    @test_throws ArgumentError single_mode_fiber_problem(
        Experiment(
            Fiber(regime = :multimode, preset = :SMF28, length_m = 1e-4, power_w = 1e-5),
            Control(),
            Objective();
            id = "bad_regime",
        ),
    )
    @test_throws ArgumentError field_objective(:unknown_field_metric, problem)
end

@testset "FiberLab result wrapper" begin
    sidecar_path = joinpath(mktempdir(), "opt_result.json")
    write_json_file(sidecar_path, Dict(
        "J_initial_dB" => -20.0,
        "J_final_dB" => -31.5,
        "n_iter" => 4,
        "converged" => true,
    ))

    standard_images = (
        paths = Dict(
            "phase_profile" => "/tmp/phase.png",
            "evolution" => "/tmp/evolution.png",
        ),
    )
    artifact_validation = (
        complete = true,
        standard_images = standard_images,
        extra_artifacts = (paths = Dict{Symbol,Tuple{String}}(),),
    )
    bundle = (
        spec = (id = "wrapped_run",),
        output_dir = "/tmp/run",
        artifact_path = "/tmp/run/opt_result.jld2",
        sidecar_path = sidecar_path,
        run_manifest_path = "/tmp/run/run_manifest.json",
        J_before = 1.0,
        J_after_lin = 0.1,
        ΔJ_dB = -10.0,
        artifact_validation = artifact_validation,
    )

    result = FiberLabResult(bundle)
    @test result.experiment_id == "wrapped_run"
    @test result.artifact_path == "/tmp/run/opt_result.jld2"
    @test result.metrics.J_before == 1.0
    @test result.metrics.ΔJ_dB == -10.0
    @test result.metrics.J_initial_dB == -20.0
    @test result.metrics.J_final_dB == -31.5
    @test result.metrics.delta_J_dB == -11.5
    @test result.metrics.iterations == 4
    @test figure_paths(result)[:phase_profile] == "/tmp/phase.png"
    @test verify(result).artifact_complete
end

@testset "FiberLab execution preflight" begin
    fiber = Fiber(regime = :single_mode, preset = :SMF28, length_m = 0.05, power_w = 0.001)
    experiment = Experiment(
        fiber,
        Control(variables = (:phase,)),
        Objective(kind = :raman_band);
        id = "preflight_smf28",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )

    experiment_plan = plan(experiment)
    @test experiment_plan.experiment === experiment
    @test experiment_plan.backend == :config_runner
    @test experiment_plan.requires_adjoint
    @test experiment_plan.variables == (:phase,)
    @test :phase_profile in experiment_plan.figure_hooks
    @test :raman_band_overlay in experiment_plan.figure_hooks
    @test occursin("id = \"preflight_smf28\"", experiment_plan.config_text)
    @test any(item -> item.key == :objective_kind &&
                      item.level == :scientific_target,
              experiment_plan.defaults)
    @test any(item -> item.key == :grid_policy && item.level == :auto,
              default_assumptions(experiment))

    report = check(experiment)
    @test report.pass
    @test isempty(report.blockers)
    @test :default_objective_kind in report.warnings
    @test :default_grid_policy in report.warnings
    @test :default_gradient_validation in report.warnings
    @test any(contains("benchmark target"), report.messages)

    dry_report = solve(experiment; dry_run = true)
    @test dry_report isa CheckReport
    @test dry_report.pass

    @test_throws FiberLabBackendError solve(experiment)
    @test_throws FiberLabBackendError solve(experiment; backend = NoExecutionBackend())
    backend = ConfigRunnerBackend()
    @test backend isa AbstractExecutionBackend
    @test isfile(backend.runner_path)

    invalid = Experiment(
        fiber,
        Control(variables = (:mystery_control,)),
        Objective(kind = :mystery_objective);
        id = "invalid_adjoint_preflight",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )

    invalid_report = check(invalid)
    @test !invalid_report.pass
    @test :missing_terminal_adjoint in invalid_report.blockers
    @test :missing_control_pullback in invalid_report.blockers
    @test_throws FiberLabCheckError solve(invalid; dry_run = true)
    @test_throws FiberLabCheckError solve(invalid; backend = backend)

    custom_control = ControlMap(
        :custom_executable_control;
        dimension = 2,
        decode = (x, ctx) -> x,
        pullback = (g, ctx) -> g,
        figure_hooks = (:custom_control_plot,),
    )
    custom_objective = ObjectiveMap(
        :custom_executable_objective;
        cost = field -> sum(abs2, field),
        terminal_adjoint = (field, ctx) -> 2 .* field,
        figure_hooks = (:custom_objective_plot,),
    )
    custom_experiment = Experiment(
        fiber,
        custom_control,
        custom_objective;
        id = "custom_object_experiment",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    custom_report = check(custom_experiment)
    @test custom_report.pass
    @test custom_report.plan.config_text == ""
    @test custom_report.plan.backend == :api_native
    @test custom_report.plan.variables == (:custom_executable_control,)
    @test custom_report.plan.objective == :custom_executable_objective
    custom_summary = summarize(custom_experiment)
    @test custom_summary.variables == (:custom_executable_control,)
    @test custom_summary.objective == :custom_executable_objective
    @test :custom_control_plot in custom_report.plan.figure_hooks
    @test :custom_objective_plot in custom_report.plan.figure_hooks
    @test any(item -> item.key == :control_map && item.level == :explicit,
              custom_report.plan.defaults)
    @test any(item -> item.key == :objective_map && item.level == :explicit,
              custom_report.plan.defaults)
    @test !(:default_objective_kind in custom_report.warnings)
    @test solve(custom_experiment; dry_run = true).pass
    @test_throws FiberLabBackendError solve(custom_experiment; backend = backend)

    missing_pullback_experiment = Experiment(
        fiber,
        ControlMap(:control_without_pullback; dimension = 1, decode = (x, ctx) -> x),
        custom_objective;
        id = "missing_pullback_object_experiment",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    missing_pullback_report = check(missing_pullback_experiment)
    @test !missing_pullback_report.pass
    @test :missing_control_pullback in missing_pullback_report.blockers

    missing_adjoint_experiment = Experiment(
        fiber,
        custom_control,
        ObjectiveMap(:objective_without_adjoint; cost = field -> sum(abs2, field));
        id = "missing_adjoint_object_experiment",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    missing_adjoint_report = check(missing_adjoint_experiment)
    @test !missing_adjoint_report.pass
    @test :missing_terminal_adjoint in missing_adjoint_report.blockers
end

@testset "FiberLab package contracts" begin
    @test :phase in FiberLab.registered_control_kinds()
    @test :raman_band in FiberLab.registered_objective_kinds()

    phase_contract = FiberLab.control_contract(:phase)
    @test phase_contract isa ControlContract
    @test phase_contract.has_pullback
    @test :phase_profile in phase_contract.figure_hooks

    raman_contract = FiberLab.objective_contract(:raman_band)
    @test raman_contract isa ObjectiveContract
    @test raman_contract.has_terminal_adjoint
    @test :raman_band_overlay in raman_contract.figure_hooks

    hooks = FiberLab.figure_hooks((:phase, :energy), :raman_band)
    @test :phase_profile in hooks
    @test :energy_throughput in hooks
    @test :raman_band_overlay in hooks
    @test FiberLab.control_contract(:unknown_control) === nothing
    @test FiberLab.objective_contract(:unknown_objective) === nothing

    custom_control = register_control!(
        :notebook_custom_control;
        units = "arb.",
        figure_hooks = (:custom_control_plot,),
    )
    custom_objective = register_objective!(
        :notebook_custom_objective;
        figure_hooks = (:custom_objective_plot, :convergence_trace),
    )
    @test custom_control isa ControlContract
    @test custom_objective isa ObjectiveContract
    @test has_control_pullback(:notebook_custom_control)
    @test has_objective_terminal_adjoint(:notebook_custom_objective)
    @test :notebook_custom_control in FiberLab.registered_control_kinds()
    @test :notebook_custom_objective in FiberLab.registered_objective_kinds()

    custom_experiment = Experiment(
        Fiber(regime = :single_mode, preset = :SMF28, length_m = 0.05, power_w = 0.001),
        Control(variables = (:notebook_custom_control,)),
        Objective(kind = :notebook_custom_objective);
        id = "custom_contract_preflight",
        solver = Solver(kind = :lbfgs, max_iter = 1),
        maturity = :supported,
    )
    custom_report = check(custom_experiment)
    @test custom_report.pass
    @test :custom_control_plot in custom_report.plan.figure_hooks
    @test :custom_objective_plot in custom_report.plan.figure_hooks
end
