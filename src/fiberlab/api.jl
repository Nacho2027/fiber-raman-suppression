"""
    Fiber(; preset=:SMF28, length_m, power_w, regime=:single_mode, beta_order=3)

Notebook-facing description of a fiber propagation setting.

`Fiber` is a high-level experiment object. It intentionally stores user-facing
choices, not the low-level propagation dictionaries consumed by the inherited
simulation backend. Most notebooks can omit `regime` and choose the number of
fields through `fiber_problem(...; modes=...)`; `regime` remains available for
compatibility specs and explicit metadata.
"""
Base.@kwdef struct Fiber
    regime::Symbol = :single_mode
    preset::Symbol = :SMF28
    length_m::Float64
    power_w::Float64
    beta_order::Int = 3
end

"""
    Pulse(; fwhm_s=185e-15, rep_rate_hz=80.5e6, shape=:sech_sq)

Notebook-facing pulse description used by FiberLab experiments.
"""
Base.@kwdef struct Pulse
    fwhm_s::Float64 = 185e-15
    rep_rate_hz::Float64 = 80.5e6
    shape::Symbol = :sech_sq
end

"""
    Grid(; nt=8192, time_window_ps=12.0, policy=:auto_if_undersized)

Simulation grid request for a FiberLab experiment.
"""
Base.@kwdef struct Grid
    nt::Int = 8192
    time_window_ps::Float64 = 12.0
    policy::Symbol = :auto_if_undersized
end

"""
    Control(; variables=(:phase,), parameterization=:full_grid, initialization=:zero, policy=:direct)

Symbolic pulse-shaping or launch-control choice for config-backed workflows.

Examples of `variables` are `(:phase,)`, `(:phase, :amplitude)`, or an
extension kind registered under `lab_extensions/variables/`.

For behavior-first native adjoint work, pass `ControlMap`, `ControlSpace`, or a
built-in map such as `FullGridPhase`, `PhaseBasis`, `AmplitudeBasis`, or
`PositiveScalar` directly to `Experiment`.
"""
Base.@kwdef struct Control
    variables::Tuple{Vararg{Symbol}} = (:phase,)
    parameterization::Symbol = :full_grid
    initialization::Symbol = :zero
    policy::Symbol = :direct
    options::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

"""
    Objective(; kind=:raman_band, log_cost=true, regularizers=Dict(:gdd => :auto, :boundary => 1.0))

Symbolic optimization target for config-backed workflows.

Objective kinds may be built in or registered through `lab_extensions/objectives/`.
For behavior-first native adjoint work, pass `ObjectiveMap`,
`AdjointObjective`, or `ScalarObjective` directly to `Experiment`.
"""
Base.@kwdef struct Objective
    kind::Symbol = :raman_band
    log_cost::Bool = true
    regularizers::Dict{Symbol,Any} = Dict{Symbol,Any}(:gdd => :auto, :boundary => 1.0)
end

"""
    Solver(; kind=:lbfgs, max_iter=30, validate_gradient=false, store_trace=true)

Optimizer request for a FiberLab experiment.
"""
Base.@kwdef struct Solver
    kind::Symbol = :lbfgs
    max_iter::Int = 30
    validate_gradient::Bool = false
    store_trace::Bool = true
end

"""
    ArtifactPolicy(; bundle=:standard, standard_images=true, export_phase=false)

Output policy for a FiberLab experiment.
"""
Base.@kwdef struct ArtifactPolicy
    bundle::Symbol = :standard
    save_payload::Bool = true
    save_sidecar::Bool = true
    update_manifest::Bool = true
    write_trust_report::Bool = true
    standard_images::Bool = true
    export_phase::Bool = false
end

"""
    Experiment(fiber, pulse, control, objective; grid=Grid(), solver=Solver(), artifacts=ArtifactPolicy())

High-level FiberLab experiment object.

This is the notebook and agent-facing container. It accepts either symbolic
config specs or direct adjoint behavior objects and only lowers into
backend-specific representations at the execution boundary.
"""
Base.@kwdef struct Experiment
    id::String
    description::String = id
    fiber::Fiber
    pulse::Pulse = Pulse()
    grid::Grid = Grid()
    control = Control()
    objective = Objective()
    solver::Solver = Solver()
    artifacts::ArtifactPolicy = ArtifactPolicy()
    output_root::String = joinpath("results", "fiberlab")
    output_tag::String = id
    maturity::Symbol = :experimental
end

function _valid_control_spec(control)
    control isa Control && return true
    isdefined(@__MODULE__, :AbstractControlMap) && control isa AbstractControlMap && return true
    return false
end

function _valid_objective_spec(objective)
    objective isa Objective && return true
    isdefined(@__MODULE__, :AbstractFiberObjective) && objective isa AbstractFiberObjective && return true
    return false
end

function Experiment(fiber::Fiber, control=Control(), objective=Objective();
                    id::AbstractString="notebook_experiment",
                    description::AbstractString=String(id),
                    pulse::Pulse=Pulse(),
                    grid::Grid=Grid(),
                    solver::Solver=Solver(),
                    artifacts::ArtifactPolicy=ArtifactPolicy(),
                    output_root::AbstractString=joinpath("results", "fiberlab"),
                    output_tag::AbstractString=String(id),
                    maturity::Symbol=:experimental)
    _valid_control_spec(control) || throw(ArgumentError(
        "control must be a FiberLab Control or AbstractControlMap"))
    _valid_objective_spec(objective) || throw(ArgumentError(
        "objective must be a FiberLab Objective or AbstractFiberObjective"))
    return Experiment(;
        id = String(id),
        description = String(description),
        fiber = fiber,
        pulse = pulse,
        grid = grid,
        control = control,
        objective = objective,
        solver = solver,
        artifacts = artifacts,
        output_root = String(output_root),
        output_tag = String(output_tag),
        maturity = maturity,
    )
end

_toml_value(value::AbstractString) = repr(String(value))
_toml_value(value::Symbol) = repr(String(value))
_toml_value(value::Bool) = string(value)
_toml_value(value::Integer) = string(value)
_toml_value(value::AbstractFloat) = string(value)
_toml_value(value::Tuple) = "[" * join((_toml_value(v) for v in value), ", ") * "]"
_toml_value(value::AbstractVector) = "[" * join((_toml_value(v) for v in value), ", ") * "]"

function _push_kv!(lines::Vector{String}, key::AbstractString, value)
    push!(lines, string(key, " = ", _toml_value(value)))
    return lines
end

"""
    experiment_config_text(experiment) -> String

Render a FiberLab `Experiment` as the current front-layer TOML schema.

This keeps notebooks centered on the abstract API while preserving the existing
config-backed execution path for reproducible compatibility runs.
"""
function experiment_config_text(experiment::Experiment)
    experiment.control isa Control || throw(ArgumentError(
        "experiment_config_text only supports symbolic Control objects; custom control maps require an API execution backend"))
    experiment.objective isa Objective || throw(ArgumentError(
        "experiment_config_text only supports symbolic Objective objects; custom objective maps require an API execution backend"))

    lines = String[]
    _push_kv!(lines, "id", experiment.id)
    _push_kv!(lines, "description", experiment.description)
    _push_kv!(lines, "maturity", experiment.maturity)
    _push_kv!(lines, "output_root", experiment.output_root)
    _push_kv!(lines, "output_tag", experiment.output_tag)
    _push_kv!(lines, "save_prefix_basename", "opt")

    push!(lines, "", "[problem]")
    _push_kv!(lines, "regime", experiment.fiber.regime)
    _push_kv!(lines, "preset", experiment.fiber.preset)
    _push_kv!(lines, "L_fiber", experiment.fiber.length_m)
    _push_kv!(lines, "P_cont", experiment.fiber.power_w)
    _push_kv!(lines, "beta_order", experiment.fiber.beta_order)
    _push_kv!(lines, "Nt", experiment.grid.nt)
    _push_kv!(lines, "time_window", experiment.grid.time_window_ps)
    _push_kv!(lines, "grid_policy", experiment.grid.policy)
    _push_kv!(lines, "pulse_fwhm", experiment.pulse.fwhm_s)
    _push_kv!(lines, "pulse_rep_rate", experiment.pulse.rep_rate_hz)
    _push_kv!(lines, "pulse_shape", experiment.pulse.shape)
    _push_kv!(lines, "raman_threshold", -5.0)

    push!(lines, "", "[controls]")
    _push_kv!(lines, "variables", experiment.control.variables)
    _push_kv!(lines, "parameterization", experiment.control.parameterization)
    _push_kv!(lines, "initialization", experiment.control.initialization)
    _push_kv!(lines, "policy", experiment.control.policy)

    push!(lines, "", "[objective]")
    _push_kv!(lines, "kind", experiment.objective.kind)
    _push_kv!(lines, "log_cost", experiment.objective.log_cost)
    for (name, lambda) in sort!(collect(experiment.objective.regularizers); by=x -> string(first(x)))
        push!(lines, "")
        push!(lines, "[[objective.regularizer]]")
        _push_kv!(lines, "name", name)
        _push_kv!(lines, "lambda", lambda)
    end

    push!(lines, "", "[solver]")
    _push_kv!(lines, "kind", experiment.solver.kind)
    _push_kv!(lines, "max_iter", experiment.solver.max_iter)
    _push_kv!(lines, "validate_gradient", experiment.solver.validate_gradient)
    _push_kv!(lines, "store_trace", experiment.solver.store_trace)

    push!(lines, "", "[artifacts]")
    _push_kv!(lines, "bundle", experiment.artifacts.bundle)
    _push_kv!(lines, "save_payload", experiment.artifacts.save_payload)
    _push_kv!(lines, "save_sidecar", experiment.artifacts.save_sidecar)
    _push_kv!(lines, "update_manifest", experiment.artifacts.update_manifest)
    _push_kv!(lines, "write_trust_report", experiment.artifacts.write_trust_report)
    _push_kv!(lines, "write_standard_images", experiment.artifacts.standard_images)
    _push_kv!(lines, "export_phase_handoff", experiment.artifacts.export_phase)

    push!(lines, "", "[verification]")
    _push_kv!(lines, "mode", "standard")
    _push_kv!(lines, "block_on_failed_checks", true)
    _push_kv!(lines, "gradient_check", experiment.solver.validate_gradient)
    _push_kv!(lines, "taylor_check", false)
    _push_kv!(lines, "exact_grid_replay", false)
    _push_kv!(lines, "artifact_validation", true)

    push!(lines, "", "[export]")
    _push_kv!(lines, "enabled", experiment.artifacts.export_phase)
    _push_kv!(lines, "profile", "neutral_csv_v1")
    _push_kv!(lines, "include_unwrapped_phase", true)
    _push_kv!(lines, "include_group_delay", true)

    return string(join(lines, "\n"), "\n")
end

"""
    write_experiment_config(path, experiment)

Write a FiberLab `Experiment` to the current TOML-backed execution format.
"""
function write_experiment_config(path::AbstractString, experiment::Experiment)
    mkpath(dirname(path))
    write(path, experiment_config_text(experiment))
    return abspath(path)
end

"""
    summarize(experiment) -> NamedTuple

Compact machine-readable summary for notebooks, docs, and agent inspection.
"""
function _summary_control_variables(control::Control)
    return control.variables
end

function _summary_control_variables(control)
    if isdefined(@__MODULE__, :ControlSpace) && control isa ControlSpace
        return Tuple(block.name for block in control.blocks)
    end
    if isdefined(@__MODULE__, :AbstractControlMap) && control isa AbstractControlMap
        return (control.name,)
    end
    return (:unknown_control,)
end

function _summary_objective_kind(objective::Objective)
    return objective.kind
end

function _summary_objective_kind(objective)
    if isdefined(@__MODULE__, :AbstractFiberObjective) && objective isa AbstractFiberObjective
        return objective.name
    end
    return :unknown_objective
end

function summarize(experiment::Experiment)
    return (
        id = experiment.id,
        regime = experiment.fiber.regime,
        preset = experiment.fiber.preset,
        length_m = experiment.fiber.length_m,
        power_w = experiment.fiber.power_w,
        variables = _summary_control_variables(experiment.control),
        objective = _summary_objective_kind(experiment.objective),
        solver = experiment.solver.kind,
        max_iter = experiment.solver.max_iter,
        output_root = experiment.output_root,
    )
end
