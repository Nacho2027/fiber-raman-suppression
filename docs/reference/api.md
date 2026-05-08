# Public API

The high-level FiberLab API is defined in `src/fiberlab/api.jl` and exported
from the Julia package.

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
- `solve(model, control, objective, initial_coordinates; fiber, kwargs...)`
- `solve(experiment; backend=NativeAdjointBackend(model; initial_coordinates=x0))`
- `NativeAdjointBackend(model; initial_coordinates=x0, bounds=nothing, artifact_writers=Dict(...))`
- `fiber_problem(fiber; modes=1, pulse=Pulse(), grid=Grid(), kwargs...)`
- `fiber_problem(experiment; kwargs...)`
- `fiber_problem(uω0, fiber, sim; kwargs...)`
- `FullGridPhase(problem; kwargs...)`
- `fiber_model(problem)`
- `sample_count(problem)`
- `mode_count(problem)`
- `frequency_offsets(problem)`
- `raman_band_objective(problem; log_cost=false)`
- `mode_sum_objective(problem; log_cost=false)`
- `fundamental_mode_objective(problem; log_cost=false)`
- `worst_mode_objective(problem; log_cost=false, worst_mode_tau=50.0)`
- `raman_peak_objective(problem; log_cost=false)`
- `temporal_width_objective(problem; log_cost=false)`
- `decoded_final(result)`
- `metrics(result)`
- `gradient_vector(control_gradient)`
- `control_slices(control_space)`
- `control_contract(kind)`
- `control_bounds(control; lower=nothing, upper=nothing)`
- `control_bounds(control_space, :block => (lower, upper), ...)`
- `objective_contract(kind)`
- `registered_control_kinds()`
- `registered_objective_kinds()`
- `register_control!(kind; has_pullback=true, units="", figure_hooks=())`
- `register_objective!(kind; has_terminal_adjoint=true, figure_hooks=())`
- `figure_hooks(control_kinds, objective_kind)`
- `terminal_adjoint(objective, final_state, context)`
- `assert_adjoint_ready(objective, control_map, solver)`
- `figure_paths(result)`
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
