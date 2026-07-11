# Notebook API Quickstart

FiberLab notebooks are built from four explicit objects:

- `problem`: the fiber propagation setup
- `control`: how optimizer coordinates become physical controls
- `objective`: the scalar cost and terminal adjoint seed
- `model`: the forward and adjoint physics map

The same contract handles package-native helpers and researcher-defined
controls, objectives, and models.

## Forward Simulation

Forward propagation needs only a resolved problem—no objective or optimizer:

```julia
z_m = collect(range(0, fiber.length_m; length = 9))
forward = propagate(problem; saveat = z_m)

summarize(forward)  # source authority, hashes, grid, and solver facts
metrics(forward)    # energy, peak power, edges, modes, and photon drift
verify(forward)     # numerical checks; never a scientific-readiness claim
```

`forward.spectra` has shape `(Nt, modes, saved_positions)` in lab-frame raw
FFT order. `saveat` must be sorted, unique, and include both endpoints; omit it
to store only input and output. The result contains stored samples, not a live
solver object, so plots and analysis do not rerun the propagation.
Containment maxima cover the stored positions only; the endpoint-only default
does not certify unsaved intermediate states.
The propagation grid is periodic and has no hidden edge absorber. Increase the
time window until the raw temporal-edge check passes at every position that
matters to the experiment.

Package-built problems retain authoritative `Fiber`/`Pulse` metadata. Explicit
array problems record only resolved numerical identity and grid facts. A
different launch field requires a new explicit `fiber_field_problem`, avoiding
silent changes to the source contract. This method covers the passive
single-mode and multimode backend; gain propagation remains a separate
low-level capability until it has equivalent evidence and tests.

## Minimal Run

```julia
using FiberLab

fiber = Fiber(preset = :SMF28_beta2_only, length_m = 1e-4, power_w = 1e-5, beta_order = 2)
grid = Grid(nt = 512, time_window_ps = 5.0, policy = :exact)

problem = fiber_problem(fiber; grid = grid, raman_threshold_thz = -0.25)
summarize(problem)

control = FullGridPhase(problem)
objective = raman_band_objective(problem; log_cost = false)
model = fiber_model(problem)

x0 = zeros(dimension(control))

check_adjoint_gradient(
    model,
    control,
    objective,
    x0;
    coordinate_indices = [2, 9],
)

result = solve(
    problem,
    control,
    objective,
    x0;
    max_iter = 1,
    validate_gradient = true,
)

metrics(result)
verify(result)
decoded_final(result)
```

`solve(problem, ...)` is the shortest path when the problem was built from a
`Fiber`, `Pulse`, and `Grid`; those inputs and the resolved grid are recorded
without an override path. For explicit low-level arrays,
`solve(model, control, objective, x0)` records the resolved numerical grid
without inventing Fiber or Pulse metadata. You may pass `fiber`, `pulse`, and
`grid` together as descriptive metadata; FiberLab labels that complete set
`user_asserted` and keeps the numerical problem hash separate.
Researcher-defined models without a resolved numerical problem must provide all
three metadata objects.

`validate_gradient = true` runs a finite-difference adjoint check before the
optimizer starts. Keep it on for new controls, objectives, and physics models;
turn it off only after the contract is already trusted.

For lab-realizability checks, attach a hardware profile:

```julia
profile = LabProfile(
    phase_levels = 256,
    max_phase_step = 0.2,
    max_projected_cost_increase = 0.05,
)
report = trust_check(model, control, objective, x0; profile = profile)

result = solve(
    problem,
    control,
    objective,
    x0;
    trust_profile = profile,
    require_trust = true,
)
```

## Inspect Before Running

```julia
experiment = Experiment(fiber, control, objective; id = "notebook_run")
summary = summarize(experiment)
report = check(experiment)

summary
report.pass
report.warnings
default_assumptions(experiment)
```

`check` performs backend-independent preflight for missing pullbacks, terminal
adjoints, and solver constraints. When a backend matters, use
`solve(experiment; dry_run=true, backend=backend)` to also validate provenance,
coordinate dimensions, bounds, feasibility gradients, and artifact writers.

## Artifacts

Notebook artifact writing is opt-in:

```julia
result = solve(
    problem,
    control,
    objective,
    x0;
    write_artifacts = true,
    output_dir = "results/fiberlab/notebook_run",
)

figures = figure_paths(result)
verify(result).artifact_complete
verify(result).missing_artifact_hooks
```

FiberLab checks that requested artifact files exist, and PNG outputs are
readable and nonblank. That is only a guardrail. For real simulation work, open
the generated figures and inspect the axes, scales, overlays, and physical
story before treating the run as scientific evidence.
Native artifact runs also write a JSON trust report beside the convergence
trace so lab-realizability checks can be archived with the result.

Built-in writers cover hooks such as `:field_summary`, `:phase_profile`,
`:group_delay`, `:amplitude_profile`, `:mode_resolved_spectra`,
`:per_mode_leakage_table`, and scalar energy summaries. Custom writers can be
attached by hook:

```julia
result = solve(
    model,
    control,
    objective,
    x0;
    fiber = fiber,
    write_artifacts = true,
    artifact_writers = Dict(
        :my_summary => (ctx, result) -> begin
            path = joinpath(ctx.output_dir, string(ctx.tag, "_summary.txt"))
            write(path, string(metrics(result)))
            path
        end,
    ),
)
```

## Controls

Use built-in controls when their assumptions match the experiment:

```julia
control = FullGridPhase(problem)
control = PhaseBasis(B)
control = AmplitudeBasis(B; scale = 0.02)
control = PositiveScalar(:energy; units = "relative pulse energy")
```

Use `ControlMap` when the parameterization is yours. The `decode` function maps
optimizer coordinates to physical controls. The `pullback` maps physical
adjoint gradients back to optimizer coordinates.

```julia
bounded_phase = ControlMap(
    :phase;
    dimension = 2,
    decode = (x, ctx) -> 0.05 .* tanh.(B * x),
    pullback = (physical_gradient, ctx) -> begin
        z = B * ctx.coordinates
        0.05 .* (transpose(B) * (physical_gradient .* (1 .- tanh.(z).^2)))
    end,
    figure_hooks = (:phase_profile, :group_delay),
)
```

Multiple controls are packed with `ControlSpace`:

```julia
control = ControlSpace(
    :phase => bounded_phase,
    :amplitude => AmplitudeBasis(B; scale = 0.01),
    :energy => PositiveScalar(:energy; figure_hooks = (:energy_scale,)),
)

x0 = zeros(dimension(control))
```

## Bounds

Use coordinate bounds when a limit belongs to the optimizer variables
themselves. This uses Optim.jl's bounded LBFGS path under the hood.

```julia
bounds = control_bounds(
    control,
    :amplitude => (lower = -0.05, upper = 0.05),
    :energy => (lower = log(0.8), upper = log(1.2)),
)

result = solve(
    problem,
    control,
    objective,
    x0;
    bounds = bounds,
)
```

For arbitrary controls, `control_bounds(my_control; lower = ..., upper = ...)`
builds bounds over the full optimizer coordinate vector. Use `FeasibilityMap`
instead when the constraint is a physical or lab-realizability rule that should
add a penalty, projection, or diagnostic check.

## Feasibility

Use `FeasibilityMap` when a run needs researcher-defined feasibility behavior
in addition to the objective. The callbacks are ordinary Julia functions.

```julia
feasibility = FeasibilityMap(
    :lab_feasibility;
    penalty = (decoded, ctx) -> begin
        amplitude = decoded.amplitude
        sum(abs2, min.(amplitude .- 0.2, 0.0))
    end,
    physical_gradient = (decoded, ctx) -> begin
        amplitude = decoded.amplitude
        (
            amplitude = 2 .* min.(amplitude .- 0.2, 0.0),
        )
    end,
    project = (decoded, ctx) -> (
        phase = decoded.phase,
        amplitude = max.(decoded.amplitude, 0.2),
        energy = decoded.energy,
    ),
    check = (decoded, ctx) -> (
        min_amplitude = minimum(decoded.amplitude),
    ),
)

result = solve(
    problem,
    control,
    objective,
    x0;
    feasibility = feasibility,
)
```

FiberLab does not interpret the scientific meaning of these callbacks. If
`penalty` is supplied for an adjoint solve, `physical_gradient` must also be
supplied so the penalty can flow through the same control pullbacks as the
physics gradient. `project` and `check` are optional diagnostics/projection
hooks for notebook and lab workflows.

## Objectives

Built-in objective constructors return ordinary `ObjectiveMap` objects:

```julia
objective = raman_band_objective(problem)
objective = raman_peak_objective(problem)
objective = temporal_width_objective(problem)
```

Custom objectives are ordinary behavior objects and do not need registration:

```julia
objective = ObjectiveMap(
    :my_detector_metric;
    cost = field -> my_cost(field, problem),
    terminal_adjoint = (field, ctx) -> my_terminal_seed(field, problem),
    figure_hooks = (:my_detector_plot,),
)
```

The terminal adjoint is required for gradient-based adjoint optimization.

## Multimode

Use the same API shape for multimode problems. Package-built multimode setup
requires explicit modal physics rather than guessed defaults:

```julia
problem = fiber_problem(
    Fiber(regime = :multimode, preset = :two_mode_setup, length_m = L, power_w = P);
    modes = 2,
    grid = grid,
    initial_modes = [1 / sqrt(2), im / sqrt(2)],
    dispersion = Dω,
    gamma_tensor = γ,
    band_mask = band_mask,
)

model = fiber_model(problem)
objective = mode_sum_objective(problem)

control = ControlSpace(
    :phase => PhaseBasis(B),
    :amplitude => AmplitudeBasis(B; scale = 0.01),
    :energy => PositiveScalar(:energy),
)
```

Other multimode objectives use the same contract:

```julia
objective = fundamental_mode_objective(problem)
objective = worst_mode_objective(problem; worst_mode_tau = 50.0)
```

A vector phase or amplitude is shared across modes. A matrix-valued custom
control can target mode-resolved shaping when the model and pullback agree on
that representation.

## Low-Level Inputs

Fully explicit propagation inputs are also supported:

```julia
problem = fiber_problem(uω0, fiber_dict, sim; band_mask = band_mask)
```

Use `fiber_model(problem)` with the model-first `solve` overload for these
low-level problems. The problem-first convenience method intentionally refuses
to invent a `Fiber` or `Pulse` from numerical arrays.

Band-based objectives need a band definition:

```julia
problem = fiber_problem(
    uω0,
    fiber_dict,
    sim;
    band_mask = FFTW.fftfreq(sim["Nt"], 1 / sim["Δt"]) .< -5.0,
)
```

## Compatibility Path

Symbolic `Control(...)`, symbolic `Objective(...)`, checked TOML configs, and
`ConfigRunnerBackend()` remain available for existing reproducible workflows.
They are compatibility tools, not the center of new notebook work.

```julia
compat_experiment = Experiment(
    fiber,
    Control(variables = (:phase,)),
    Objective(kind = :raman_band);
    id = "config_backed_run",
)

result = solve(compat_experiment; backend = ConfigRunnerBackend())
verify(result)
```
