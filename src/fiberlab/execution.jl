"""
Simulation-free execution facade for FiberLab experiments.

`solve(experiment)` is the intended public UX. It always plans and checks before
execution, then delegates to an explicit backend adapter.
"""

struct ExperimentPlan
    experiment::Union{Experiment,NativeExperiment}
    requested_grid::Union{Missing,Grid}
    initial_grid::Union{Missing,Grid}
    resolved_grid::Union{Missing,Grid}
    grid_authority::Symbol
    grid_error::String
    config_text::String
    backend::Symbol
    requires_adjoint::Bool
    variables::Tuple{Vararg{Symbol}}
    objective::Symbol
    solver::Symbol
    figure_hooks::Tuple{Vararg{Symbol}}
    output_root::String
    output_tag::String
    defaults::Tuple{Vararg{DefaultAssumption}}
end

struct CheckReport
    pass::Bool
    blockers::Tuple{Vararg{Symbol}}
    warnings::Tuple{Vararg{Symbol}}
    messages::Tuple{Vararg{String}}
    plan::ExperimentPlan
end

struct FiberLabCheckError <: Exception
    report::CheckReport
end

struct FiberLabBackendError <: Exception
    plan::ExperimentPlan
    backend
    message::String
end

Base.showerror(io::IO, err::FiberLabCheckError) = begin
    println(io, "FiberLab experiment check failed")
    for message in err.report.messages
        println(io, "  - ", message)
    end
end

Base.showerror(io::IO, err::FiberLabBackendError) = print(
    io,
    err.message,
)

abstract type AbstractExecutionBackend end

"""
    NoExecutionBackend()

Default backend used by `solve(experiment)`. It performs all preflight checks
and then refuses execution. This keeps the package API defensive until a real
backend adapter is explicitly selected and implemented.
"""
struct NoExecutionBackend <: AbstractExecutionBackend end

_fiberlab_repo_root() = normpath(joinpath(@__DIR__, "..", ".."))

"""
    ConfigRunnerBackend()

Backend adapter for the maintained canonical config runner. This keeps notebook
call sites on `solve(exp; backend=ConfigRunnerBackend())` while the actual
simulation execution remains behind the validated runner boundary.
"""
Base.@kwdef struct ConfigRunnerBackend <: AbstractExecutionBackend
    julia_cmd::Cmd = Base.julia_cmd()
    project_dir::String = _fiberlab_repo_root()
    runner_path::String = joinpath(project_dir, "scripts", "canonical", "run_experiment.jl")
    threads::String = "auto"
    keep_config::Bool = false
end

_gradient_solver(kind::Symbol) = kind in (:lbfgs,)

_control_kinds(control::Control) = control.variables
_control_kinds(control::ControlSpace) = Tuple(block.name for block in control.blocks)
_control_kinds(control::AbstractControlMap) = (control.name,)
_objective_kind(objective::Objective) = objective.kind
_objective_kind(objective::AbstractFiberObjective) = objective.name
_config_runner_supported(experiment::Experiment) =
    experiment.fiber.regime == :single_mode &&
    experiment.control isa Control && experiment.objective isa Objective

function _plan_grid_resolution(experiment::Experiment)
    requested = experiment.grid
    experiment.fiber.regime in (:single_mode, :long_fiber, :multimode) ||
        return requested, missing, missing, :invalid,
            "unsupported fiber regime `$(experiment.fiber.regime)`"
    single_mode_backend = experiment.fiber.regime in (:single_mode, :long_fiber)
    grid_fiber = experiment.fiber.regime == :long_fiber ? Fiber(
        regime=:single_mode,
        preset=experiment.fiber.preset,
        length_m=experiment.fiber.length_m,
        power_w=experiment.fiber.power_w,
        beta_order=experiment.fiber.beta_order,
    ) : experiment.fiber
    initial = try
        single_mode_backend ?
            resolve_grid(grid_fiber, experiment.pulse, requested) :
            resolve_sampling_grid(requested)
    catch err
        return requested, missing, missing, :invalid, sprint(showerror, err)
    end
    if single_mode_backend
        authority = experiment.fiber.regime == :long_fiber ?
            :long_fiber_analytic : :single_mode_analytic
        return requested, initial, initial, authority, ""
    elseif requested.policy in (:exact, :fixed)
        return requested, initial, initial, :user_exact, ""
    end
    return requested, initial, missing, :runtime_physics, ""
end

function _plan_grid_resolution(experiment::NativeExperiment)
    ismissing(experiment.grid) &&
        return missing, missing, missing, :unavailable, ""
    grid = experiment.grid
    valid = grid.nt >= 4 && ispow2(grid.nt) && isfinite(grid.time_window_ps) &&
            grid.time_window_ps > 0
    return valid ? (grid, grid, grid, :resolved_numerical, "") :
        (grid, missing, missing, :invalid,
         "grid nt must be a power of two ≥ 4 and time_window_ps must be positive and finite")
end

function _experiment_config_text_or_empty(experiment::Experiment)
    _config_runner_supported(experiment) || return ""
    return experiment_config_text(experiment)
end

function figure_hooks(control::AbstractControlMap, objective::AbstractFiberObjective)
    hooks = Symbol[]
    if hasproperty(objective, :figure_hooks)
        append!(hooks, objective.figure_hooks)
    else
        append!(hooks, figure_hooks((), objective.name))
    end
    if hasproperty(control, :figure_hooks)
        append!(hooks, control.figure_hooks)
    else
        append!(hooks, figure_hooks((control.name,), :unknown_objective))
    end
    return Tuple(unique(hooks))
end

function figure_hooks(control::ControlSpace, objective::AbstractFiberObjective)
    hooks = Symbol[]
    if hasproperty(objective, :figure_hooks)
        append!(hooks, objective.figure_hooks)
    else
        append!(hooks, figure_hooks((), objective.name))
    end
    for block in control.blocks
        if hasproperty(block.map, :figure_hooks)
            append!(hooks, block.map.figure_hooks)
        else
            append!(hooks, figure_hooks((block.name,), :unknown_objective))
        end
    end
    return Tuple(unique(hooks))
end

function figure_hooks(control, objective)
    if control isa Control && objective isa Objective
        return figure_hooks(control.variables, objective.kind)
    end
    hooks = Symbol[]
    for kind in _control_kinds(control)
        append!(hooks, figure_hooks((kind,), :unknown_objective))
    end
    objective isa AbstractFiberObjective && hasproperty(objective, :figure_hooks) &&
        append!(hooks, objective.figure_hooks)
    objective isa Objective && append!(hooks, figure_hooks((), objective.kind))
    return Tuple(unique(hooks))
end

function _objective_has_terminal_adjoint(objective)
    objective isa Objective && return has_objective_terminal_adjoint(objective.kind)
    objective isa AbstractFiberObjective && return has_terminal_adjoint(objective)
    return false
end

function _control_has_pullback(control, variable::Symbol)
    control isa Control && return has_control_pullback(variable)
    control isa AbstractControlMap && return has_pullback(control)
    return false
end

"""
    plan(experiment) -> ExperimentPlan

Build a simulation-free execution plan from a FiberLab experiment.
"""
function plan(experiment::Experiment)
    requested_grid, initial_grid, resolved_grid, grid_authority, grid_error =
        _plan_grid_resolution(experiment)
    return ExperimentPlan(
        experiment,
        requested_grid,
        initial_grid,
        resolved_grid,
        grid_authority,
        grid_error,
        _experiment_config_text_or_empty(experiment),
        _config_runner_supported(experiment) ? :config_runner : :api_native,
        _gradient_solver(experiment.solver.kind),
        _control_kinds(experiment.control),
        _objective_kind(experiment.objective),
        experiment.solver.kind,
        figure_hooks(experiment.control, experiment.objective),
        experiment.output_root,
        experiment.output_tag,
        default_assumptions(experiment),
    )
end

function plan(experiment::NativeExperiment)
    requested_grid, initial_grid, resolved_grid, grid_authority, grid_error =
        _plan_grid_resolution(experiment)
    return ExperimentPlan(
        experiment,
        requested_grid,
        initial_grid,
        resolved_grid,
        grid_authority,
        grid_error,
        "",
        :api_native,
        _gradient_solver(experiment.solver.kind),
        _control_kinds(experiment.control),
        _objective_kind(experiment.objective),
        experiment.solver.kind,
        figure_hooks(experiment.control, experiment.objective),
        experiment.output_root,
        experiment.output_tag,
        default_assumptions(experiment),
    )
end

function _push_unique!(items::Vector{Symbol}, item::Symbol)
    item in items || push!(items, item)
    return items
end

function _check_plan(plan::ExperimentPlan)
    blockers = Symbol[]
    warnings = Symbol[]
    messages = String[]
    experiment = plan.experiment

    isempty(experiment.id) && (_push_unique!(blockers, :missing_id);
        push!(messages, "experiment id cannot be empty"))
    isempty(plan.variables) && (_push_unique!(blockers, :missing_controls);
        push!(messages, "at least one control variable is required"))
    if !isempty(plan.grid_error)
        _push_unique!(blockers, :invalid_grid)
        push!(messages, plan.grid_error)
    end
    if !ismissing(experiment.fiber) &&
            (!isfinite(experiment.fiber.length_m) || experiment.fiber.length_m <= 0 ||
             !isfinite(experiment.fiber.power_w) || experiment.fiber.power_w <= 0 ||
             experiment.fiber.beta_order < 2)
        _push_unique!(blockers, :invalid_fiber)
        push!(messages, "fiber length and power must be positive and finite; beta order must be at least 2")
    end
    if !ismissing(experiment.pulse) &&
            (!isfinite(experiment.pulse.fwhm_s) || experiment.pulse.fwhm_s <= 0 ||
             !isfinite(experiment.pulse.rep_rate_hz) || experiment.pulse.rep_rate_hz <= 0)
        _push_unique!(blockers, :invalid_pulse)
        push!(messages, "pulse width and repetition rate must be positive and finite")
    end
    experiment.solver.max_iter > 0 || (_push_unique!(blockers, :invalid_solver);
        push!(messages, "solver.max_iter must be positive"))
    if experiment isa Experiment && experiment.fiber.regime != :single_mode &&
            experiment.control isa Control && experiment.objective isa Objective
        _push_unique!(blockers, :unsupported_symbolic_regime)
        push!(messages,
            "symbolic package Experiments currently support single_mode only; use a validated front-layer config for long_fiber/multimode runs or a NativeExperiment with explicit behavior maps")
    end

    for assumption in plan.defaults
        if assumption.level in (:auto, :review, :scientific_target)
            _push_unique!(warnings, Symbol(:default_, assumption.key))
            push!(messages, assumption.message)
        end
    end

    if plan.requires_adjoint
        if !_objective_has_terminal_adjoint(experiment.objective)
            _push_unique!(blockers, :missing_terminal_adjoint)
            push!(messages,
                "solver `$(plan.solver)` requires a terminal adjoint, but objective `$(plan.objective)` is not known to the package-level adjoint contract")
        end
        for variable in plan.variables
            if !_control_has_pullback(experiment.control, variable)
                _push_unique!(blockers, :missing_control_pullback)
                push!(messages,
                    "solver `$(plan.solver)` requires a control pullback, but variable `$(variable)` is not known to the package-level adjoint contract")
            end
        end
    end

    if experiment.maturity != :supported
        _push_unique!(warnings, :experimental_maturity)
        push!(messages, "experiment maturity is `$(experiment.maturity)`")
    end

    return CheckReport(
        isempty(blockers),
        Tuple(blockers),
        Tuple(warnings),
        Tuple(messages),
        plan,
    )
end

"""
    check(experiment_or_plan) -> CheckReport

Run FiberLab's simulation-free defensive checks. `solve(experiment)` calls this
automatically; users call it when they want to inspect blockers without
launching a run.
"""
check(experiment::Union{Experiment,NativeExperiment}) = _check_plan(plan(experiment))
check(plan::ExperimentPlan) = _check_plan(plan)

execute(plan::ExperimentPlan, backend::NoExecutionBackend) =
    throw(FiberLabBackendError(
        plan,
        backend,
        "FiberLab solve backend `NoExecutionBackend` refuses execution after preflight; select an execution backend or call `solve(exp; dry_run=true)`.",
    ))

_preflight_backend(plan::ExperimentPlan, backend::AbstractExecutionBackend) = nothing
_preflight_in_execute(::AbstractExecutionBackend) = false

function _runner_command(backend::ConfigRunnerBackend, config_path::AbstractString)
    return Cmd(
        `$(backend.julia_cmd) -t $(backend.threads) --project=$(backend.project_dir) $(backend.runner_path) $(String(config_path))`;
        dir = backend.project_dir,
    )
end

function _extract_runner_path(output::AbstractString, label::AbstractString)
    prefix = string(label, ": ")
    for line in split(output, '\n')
        startswith(line, prefix) && return strip(line[length(prefix)+1:end])
    end
    return nothing
end

function _sidecar_for_artifact(path::AbstractString)
    stem, ext = splitext(String(path))
    lowercase(ext) == ".jld2" && return string(stem, ".json")
    return nothing
end

function _standard_image_paths(artifact_path::AbstractString)
    stem, _ = splitext(String(artifact_path))
    prefix = endswith(stem, "_result") ? stem[1:end-length("_result")] : stem
    return Dict(
        "phase_profile" => string(prefix, "_phase_profile.png"),
        "evolution" => string(prefix, "_evolution.png"),
        "phase_diagnostic" => string(prefix, "_phase_diagnostic.png"),
        "evolution_unshaped" => string(prefix, "_evolution_unshaped.png"),
    )
end

function _artifact_validation_from_paths(artifact_path::AbstractString)
    sidecar_path = _sidecar_for_artifact(artifact_path)
    standard_images = _standard_image_paths(artifact_path)
    required_paths = collect(values(standard_images))
    push!(required_paths, String(artifact_path))
    sidecar_path !== nothing && push!(required_paths, sidecar_path)
    return (
        complete = all(isfile, required_paths),
        standard_images = (paths = standard_images,),
        extra_artifacts = (paths = Dict{Symbol,Tuple{String}}(),),
    )
end

function _execute_config_runner(plan::ExperimentPlan, backend::ConfigRunnerBackend, config_path::AbstractString)
    _config_runner_supported(plan.experiment) || throw(FiberLabBackendError(
        plan,
        backend,
        "ConfigRunnerBackend only supports symbolic Control and Objective experiments; custom control/objective maps require an API-native execution backend.",
    ))
    isfile(backend.runner_path) || throw(FiberLabBackendError(
        plan,
        backend,
        "ConfigRunnerBackend runner path does not exist: $(backend.runner_path)",
    ))

    output = try
        read(_runner_command(backend, config_path), String)
    catch err
        throw(FiberLabBackendError(
            plan,
            backend,
            "ConfigRunnerBackend failed while executing the canonical runner: $(sprint(showerror, err))",
        ))
    end

    output_dir = _extract_runner_path(output, "Output directory")
    artifact_path = _extract_runner_path(output, "Artifact")
    if output_dir === nothing || artifact_path === nothing
        throw(FiberLabBackendError(
            plan,
            backend,
            "ConfigRunnerBackend could not parse runner output for result paths.",
        ))
    end

    run_manifest = joinpath(output_dir, "run_manifest.json")
    bundle = (
        spec = (id = plan.experiment.id,),
        output_dir = output_dir,
        artifact_path = artifact_path,
        sidecar_path = _sidecar_for_artifact(artifact_path),
        run_manifest_path = isfile(run_manifest) ? run_manifest : nothing,
        artifact_validation = _artifact_validation_from_paths(artifact_path),
    )
    return FiberLabResult(bundle)
end

function execute(plan::ExperimentPlan, backend::ConfigRunnerBackend)
    if backend.keep_config
        config_path = joinpath(mktempdir(), string(plan.experiment.id, ".toml"))
        write(config_path, plan.config_text)
        return _execute_config_runner(plan, backend, config_path)
    end

    return mktempdir() do dir
        config_path = joinpath(dir, string(plan.experiment.id, ".toml"))
        write(config_path, plan.config_text)
        _execute_config_runner(plan, backend, config_path)
    end
end

"""
    solve(experiment; dry_run=false, backend=NoExecutionBackend())

Primary notebook-facing execution entry point. It always runs `plan` and
`check` first. `dry_run=true` returns the `CheckReport` without executing.
Use `ConfigRunnerBackend()` to execute through the maintained canonical runner.
"""
function solve(experiment::Union{Experiment,NativeExperiment}; dry_run::Bool=false,
               backend::AbstractExecutionBackend=NoExecutionBackend())
    experiment_plan = plan(experiment)
    report = check(experiment_plan)
    report.pass || throw(FiberLabCheckError(report))
    if dry_run
        _preflight_backend(experiment_plan, backend)
        return report
    end
    _preflight_in_execute(backend) || _preflight_backend(experiment_plan, backend)
    return execute(experiment_plan, backend)
end
