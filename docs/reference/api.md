# Public API

The high-level FiberLab API is implemented under `src/fiberlab/` and exported
from the Julia package. The constructors below are the maintained notebook
surface; config-backed commands are a reproducibility bridge, not a second API.

## Core Types

- `Fiber`
- `Pulse`
- `Grid`
- `Control`
- `AbstractFeasibilityMap`
- `ControlBlock`
- `ControlEvaluation`
- `ControlGradient`
- `ControlMap`
- `ControlSpace`
- `CoordinateBounds`
- `ControlContract`
- `FeasibilityMap`
- `FeasibilityEvaluation`
- `FullGridPhase`
- `AmplitudeBasis`
- `AdjointModel`
- `AdjointStepResult`
- `AdjointGradientCheckResult`
- `Objective`
- `ObjectiveMap`
- `ObjectiveContract`
- `PhaseBasis`
- `PositiveScalar`
- `ScalarControl`
- `AdjointObjective`
- `ScalarObjective`
- `ScenarioTerm`
- `ScenarioComposition`
- `Solver`
- `ArtifactPolicy`
- `Experiment`
- `FiberLabResult`
- `ExperimentPlan`
- `CheckReport`
- `AbstractExecutionBackend`
- `NoExecutionBackend`
- `ConfigRunnerBackend`
- `NativeAdjointBackend`
- `NativeAdjointResult`
- `NativeArtifactContext`
- `PropagationResult`
- `MeasuredSpectrum`
- `SpectrumComparison`
- `LabProfile`
- `TrustCheck`
- `TrustReport`
- `FiberProblem`
- `FiberFieldProblem`
- `SingleModeFiberProblem` (compatibility alias)
- `DefaultAssumption`
- `FiberLabCheckError`
- `FiberLabBackendError`

## Core Functions

- `summarize(experiment)`
- `summarize(problem)`
- `experiment_config_text(experiment)`
- `write_experiment_config(path, experiment)`
- `plan(experiment)`
- `check(experiment_or_plan)`
- `default_assumptions(experiment)`
- `solve(experiment; dry_run=false, backend=NoExecutionBackend())`
- `execute(plan, backend)`
- `decode(control_map, values, context)`
- `evaluate_control(control_map, values; context=nothing)`
- `evaluate_feasibility(feasibility, decoded, forward_state=nothing; context=nothing)`
- `feasibility_penalty(feasibility, decoded, forward_state=nothing; context=nothing)`
- `feasibility_physical_gradient(feasibility, decoded, forward_state=nothing; context=nothing)`
- `project(feasibility, decoded; context=nothing)`
- `feasibility_check(feasibility, decoded, forward_state=nothing; context=nothing)`
- `pullback(control_map, physical_gradient, context)`
- `pullback_gradient(evaluation, physical_gradient)`
- `run_adjoint_step(model, control, objective, coordinates; context=nothing)`
- `check_adjoint_gradient(model, control, objective, coordinates; context=nothing)`
- `solve(problem, control, objective, initial_coordinates; kwargs...)`
- `solve(model, control, objective, initial_coordinates; fiber=nothing, pulse=nothing, grid=nothing, kwargs...)`
- `solve(experiment; backend=NativeAdjointBackend(model; initial_coordinates=x0))`
- `NativeAdjointBackend(model; initial_coordinates=x0, bounds=nothing, artifact_writers=Dict(...))`
- `fiber_problem(fiber; modes=1, pulse=Pulse(), grid=Grid(), kwargs...)`
- `resolve_grid(fiber, pulse=Pulse(), grid=Grid(); wavelength_m=1550e-9)`
- `resolve_sampling_grid(grid; wavelength_m=1550e-9, minimum_time_window_ps=0, max_time_step_ps=0.0105, minimum_frequency_fraction=0.1)`
- `fiber_problem(experiment; kwargs...)`
- `fiber_problem(uω0, fiber, sim; kwargs...)`
- `with_launch(problem, launch)`
- `with_raman_fraction(problem, fraction)`
- `propagate(problem; saveat=nothing)`
- `spectral_density(result::PropagationResult)`
- `load_osa_spectrum(path; wavelength_column, value_column, ...)`
- `compare_spectrum(result, measurement; evaluation_band_nm=nothing)`
- `write_spectrum_report(comparison; output_dir, tag="spectrum_comparison")`
- `FullGridPhase(problem; kwargs...)`
- `polynomial_basis(problem, powers=0:3)`
- `taylor_phase_basis(problem, orders=2:4; coefficient_scales_fs=nothing)`
- `fourier_basis(problem, harmonics=8)`
- `phase_control(problem; basis=nothing, bounds=nothing, name=:phase)`
- `amplitude_control(problem; basis=polynomial_basis(problem, 0:2), bounds=(0.8, 1.2), name=:amplitude)`
- `energy_control(; name=:energy)`
- `bounded_profile_control(name, basis; lower, upper, units="", figure_hooks=())`
- `controls(control_maps...)`
- `initial_coordinates(control)`
- `fiber_model(problem)`
- `compose_scenarios(terms...; aggregate=weighted_scenario_aggregate())`
- `weighted_scenario_aggregate([weights])`
- `squared_difference_aggregate(minuend, subtrahend)`
- `component_costs(composition, states)`
- `component_costs(composition, coordinates; control, context=nothing)`
- `sample_count(problem)`
- `mode_count(problem)`
- `frequency_offsets(problem)`
- `raman_band_objective(problem; log_cost=false)`
- `mode_sum_objective(problem; log_cost=false)`
- `fundamental_mode_objective(problem; log_cost=false)`
- `worst_mode_objective(problem; log_cost=false, worst_mode_tau=50.0)`
- `raman_peak_objective(problem; log_cost=false)`
- `temporal_width_objective(problem; log_cost=false)`
- `spectral_band_energy_objective(problem, band)`
- `spectral_asymmetry_objective(problem, red_band, blue_band)`
- `spectral_centroid_objective(problem)`
- `pulse_quality_metrics(reference, candidate, sim)`
- `pulse_quality_check(metrics; thresholds...)`
- `frequency_band_mask(problem, interval)`
- `counterfactual_band_metrics(on, off, launch; red_mask, blue_mask)`
- `counterfactual_spectrum_metrics(on, off, launch, problem)`
- `raman_counterfactual_contract(on, off; allow_response_shape_change=false)`
- `decoded_final(result)`
- `metrics(result)`
- `summarize(result::PropagationResult)`
- `gradient_vector(control_gradient)`
- `control_slices(control_space)`
- `control_contract(kind)`
- `control_bounds(control; lower=nothing, upper=nothing)`
- `control_bounds(control_space, :block => (lower, upper), ...)`
- `objective_contract(kind)`
- `registered_control_kinds()`
- `registered_objective_kinds()`
- `ObjectiveMap(name; cost, terminal_adjoint=nothing, figure_hooks=(), cost_scale=:linear)`
- `register_control!(kind; has_pullback=true, units="", figure_hooks=())`
- `register_objective!(kind; has_terminal_adjoint=true, figure_hooks=())`
- `figure_hooks(control_kinds, objective_kind)`
- `terminal_adjoint(objective, final_state, context)`
- `assert_adjoint_ready(objective, control_map, solver)`
- `figure_paths(result)`
- `standard_figures(problem, result; output_dir=nothing, tag=nothing, n_z_samples=32, also_unshaped=true)`
- `standard_report(problem, result; kwargs...)`
- `display_report(report)`
- `verify(result)`
- `trust_check(model, control, objective, coordinates; profile=nothing, gradient_check=false)`
- `trust_check(result; profile=nothing)`

## Compatibility Functions

- `fiber_field_problem(uω0, fiber, sim; band_mask=nothing, raman_threshold_thz=nothing, preset=:custom)`
- `single_mode_fiber_problem(fiber; pulse=Pulse(), grid=Grid(), wavelength_m=1550e-9, raman_threshold_thz=-5.0)`
- `spectral_shaper_model(problem)`
- `single_mode_phase_model(problem)`
- `single_mode_shaper_model(problem)`
- `field_objective(kind, problem; kwargs...)`

## Current Boundary

The API layer is intentionally small. The primary path is behavior-first:
researchers pass explicit `ControlMap`, `ControlSpace`, `ObjectiveMap`, and
`AdjointModel` objects to the native adjoint path. Built-in constructors return
the same object types as user code, so they are conveniences rather than a
separate privileged workflow.

Symbolic `Control`, `Objective`, registered contracts, and `field_objective`
exist for compatibility with reproducible config-backed runs and concise
notebooks. They are not required for custom adjoint work.

`fiber_problem` is the preferred direct physics constructor. It supports
package-built single-mode problems, explicit multimode package setup with
researcher-supplied modal physics, and fully explicit low-level propagation
objects. `fiber_field_problem` and `single_mode_fiber_problem` remain
compatibility helpers.
