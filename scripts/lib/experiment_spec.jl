"""
Thin front-layer experiment spec loading and validation.

This file intentionally implements only the first honest supported slice:

- front-layer TOML loading from `configs/experiments/*.toml`
- legacy adaptation from `configs/runs/*.toml`
- capability validation for the supported single-mode phase-only surface

The goal is to let researchers control common choices from config without
editing optimizer internals, while keeping the physics/math in code.
"""

if !(@isdefined _EXPERIMENT_SPEC_JL_LOADED)
const _EXPERIMENT_SPEC_JL_LOADED = true

using TOML

include(joinpath(@__DIR__, "canonical_runs.jl"))
include(joinpath(@__DIR__, "objective_registry.jl"))

const EXPERIMENT_CONFIG_DIR = normpath(joinpath(@__DIR__, "..", "..", "configs", "experiments"))
const DEFAULT_EXPERIMENT_SPEC = DEFAULT_CANONICAL_RUN_ID

const EXPORT_PROFILE_CONTRACTS = Dict{Symbol,Any}(
    :neutral_csv_v1 => (
        profile = :neutral_csv_v1,
        maturity = :supported,
        description = "Neutral phase-only CSV handoff on the simulation frequency/wavelength grid.",
        required_files = (:phase_profile_csv, :metadata_json, :readme),
        columns = (
            :index,
            :frequency_offset_THz,
            :absolute_frequency_THz,
            :wavelength_nm,
            :phase_wrapped_rad,
            :phase_unwrapped_rad,
            :group_delay_fs,
        ),
    ),
)

registered_export_profiles() = sort!(collect(keys(EXPORT_PROFILE_CONTRACTS)); by=string)

function export_profile_contract(profile::Symbol)
    haskey(EXPORT_PROFILE_CONTRACTS, profile) || throw(ArgumentError(
        "unknown export profile `$(profile)`; registered profiles: $(registered_export_profiles())"))
    return EXPORT_PROFILE_CONTRACTS[profile]
end

function _approved_experiment_ids(dir::AbstractString)
    isdir(dir) || return String[]
    ids = String[]
    for entry in readdir(dir)
        endswith(entry, ".toml") || continue
        push!(ids, replace(entry, ".toml" => ""))
    end
    sort!(ids)
    return ids
end

approved_experiment_config_ids() = _approved_experiment_ids(EXPERIMENT_CONFIG_DIR)

function resolve_experiment_config_path(spec::AbstractString)
    if isfile(spec)
        return abspath(spec)
    end

    filename = endswith(spec, ".toml") ? spec : string(spec, ".toml")
    candidate = joinpath(EXPERIMENT_CONFIG_DIR, filename)
    isfile(candidate) && return candidate

    available = join(approved_experiment_config_ids(), ", ")
    throw(ArgumentError(
        "could not resolve experiment config `$spec` under `$EXPERIMENT_CONFIG_DIR`; available ids: [$available]"))
end

_normalize_symbol(x) = Symbol(replace(lowercase(String(x)), "-" => "_"))

function _normalize_lambda(x)
    if x isa AbstractString
        lower = lowercase(strip(String(x)))
        lower == "auto" && return :auto
        return parse(Float64, lower)
    end
    return Float64(x)
end

function _regularizer_dict(entries)
    regs = Dict{Symbol,Any}()
    for entry in entries
        name = _normalize_symbol(entry["name"])
        regs[name] = _normalize_lambda(entry["lambda"])
    end
    return regs
end

function _front_layer_spec_from_parsed(parsed::AbstractDict{<:Any,<:Any}, path::AbstractString)
    problem = parsed["problem"]
    controls = parsed["controls"]
    objective = parsed["objective"]
    solver = parsed["solver"]
    artifacts = get(parsed, "artifacts", Dict{String,Any}())
    verification = get(parsed, "verification", Dict{String,Any}())
    export_cfg = get(parsed, "export", Dict{String,Any}())

    regularizers = haskey(objective, "regularizer") ?
        _regularizer_dict(objective["regularizer"]) :
        Dict{Symbol,Any}()

    return (
        schema = :experiment_v1,
        id = String(parsed["id"]),
        description = String(get(parsed, "description", parsed["id"])),
        maturity = lowercase(String(get(parsed, "maturity", "experimental"))),
        config_path = abspath(path),
        output_root = String(get(parsed, "output_root", joinpath("results", "raman"))),
        output_tag = String(get(parsed, "output_tag", parsed["id"])),
        save_prefix_basename = String(get(parsed, "save_prefix_basename", "opt")),
        problem = (
            regime = _normalize_symbol(problem["regime"]),
            preset = Symbol(String(problem["preset"])),
            L_fiber = Float64(problem["L_fiber"]),
            P_cont = Float64(problem["P_cont"]),
            β_order = Int(get(problem, "beta_order", 3)),
            Nt = Int(problem["Nt"]),
            time_window = Float64(problem["time_window"]),
            grid_policy = _normalize_symbol(get(problem, "grid_policy", "auto_if_undersized")),
            pulse_fwhm = Float64(get(problem, "pulse_fwhm", 185e-15)),
            pulse_rep_rate = Float64(get(problem, "pulse_rep_rate", 80.5e6)),
            pulse_shape = String(get(problem, "pulse_shape", "sech_sq")),
            raman_threshold = Float64(get(problem, "raman_threshold", -5.0)),
        ),
        controls = (
            variables = Tuple(_normalize_symbol(v) for v in get(controls, "variables", ["phase"])),
            parameterization = _normalize_symbol(get(controls, "parameterization", "full_grid")),
            initialization = _normalize_symbol(get(controls, "initialization", "zero")),
        ),
        objective = (
            kind = _normalize_symbol(objective["kind"]),
            log_cost = Bool(get(objective, "log_cost", true)),
            regularizers = regularizers,
        ),
        solver = (
            kind = _normalize_symbol(solver["kind"]),
            max_iter = Int(get(solver, "max_iter", 30)),
            validate_gradient = Bool(get(solver, "validate_gradient", false)),
            store_trace = Bool(get(solver, "store_trace", true)),
            reltol = Float64(get(solver, "reltol", 1e-8)),
        ),
        artifacts = (
            bundle = _normalize_symbol(get(artifacts, "bundle", "standard")),
            save_payload = Bool(get(artifacts, "save_payload", true)),
            save_sidecar = Bool(get(artifacts, "save_sidecar", true)),
            update_manifest = Bool(get(artifacts, "update_manifest", true)),
            write_trust_report = Bool(get(artifacts, "write_trust_report", true)),
            write_standard_images = Bool(get(artifacts, "write_standard_images", true)),
            export_phase_handoff = Bool(get(artifacts, "export_phase_handoff", false)),
        ),
        verification = (
            mode = _normalize_symbol(get(verification, "mode", "standard")),
            block_on_failed_checks = Bool(get(verification, "block_on_failed_checks", true)),
            gradient_check = Bool(get(verification, "gradient_check", false)),
            taylor_check = Bool(get(verification, "taylor_check", false)),
            exact_grid_replay = Bool(get(verification, "exact_grid_replay", false)),
            artifact_validation = Bool(get(verification, "artifact_validation", true)),
        ),
        export_plan = (
            enabled = Bool(get(export_cfg, "enabled", false)),
            profile = _normalize_symbol(get(export_cfg, "profile", "neutral_csv_v1")),
            include_unwrapped_phase = Bool(get(export_cfg, "include_unwrapped_phase", true)),
            include_group_delay = Bool(get(export_cfg, "include_group_delay", true)),
        ),
    )
end

function experiment_spec_from_canonical_run(spec::AbstractString=DEFAULT_CANONICAL_RUN_ID)
    path = resolve_run_config_path(spec)
    parsed = TOML.parsefile(path)
    run_table = parsed["run"]
    run_spec = load_canonical_run_config(spec)

    regularizers = Dict{Symbol,Any}()
    regularizers[:gdd] = get(run_spec.kwargs, :λ_gdd, :auto)
    regularizers[:boundary] = get(run_spec.kwargs, :λ_boundary, 1.0)

    return (
        schema = :canonical_run_adapter,
        id = String(run_spec.id),
        description = String(run_spec.description),
        maturity = "supported",
        config_path = path,
        output_root = String(run_spec.output_root),
        output_tag = String(run_spec.output_tag),
        save_prefix_basename = String(run_spec.save_prefix_basename),
        problem = (
            regime = :single_mode,
            preset = Symbol(String(run_table["fiber_preset"])),
            L_fiber = Float64(run_spec.kwargs.L_fiber),
            P_cont = Float64(run_spec.kwargs.P_cont),
            β_order = Int(run_spec.kwargs.β_order),
            Nt = Int(run_spec.kwargs.Nt),
            time_window = Float64(run_spec.kwargs.time_window),
            grid_policy = :auto_if_undersized,
            pulse_fwhm = Float64(run_spec.kwargs.pulse_fwhm),
            pulse_rep_rate = Float64(run_spec.kwargs.pulse_rep_rate),
            pulse_shape = String(run_spec.kwargs.pulse_shape),
            raman_threshold = Float64(run_spec.kwargs.raman_threshold),
        ),
        controls = (
            variables = (:phase,),
            parameterization = :full_grid,
            initialization = :zero,
        ),
        objective = (
            kind = :raman_band,
            log_cost = Bool(run_spec.kwargs.log_cost),
            regularizers = regularizers,
        ),
        solver = (
            kind = :lbfgs,
            max_iter = Int(run_spec.kwargs.max_iter),
            validate_gradient = Bool(run_spec.kwargs.validate),
            store_trace = true,
            reltol = Float64(run_spec.kwargs.solver_reltol),
        ),
        artifacts = (
            bundle = :standard,
            save_payload = true,
            save_sidecar = true,
            update_manifest = true,
            write_trust_report = true,
            write_standard_images = true,
            export_phase_handoff = false,
        ),
        verification = (
            mode = :standard,
            block_on_failed_checks = true,
            gradient_check = Bool(run_spec.kwargs.validate),
            taylor_check = false,
            exact_grid_replay = false,
            artifact_validation = true,
        ),
        export_plan = (
            enabled = false,
            profile = :neutral_csv_v1,
            include_unwrapped_phase = true,
            include_group_delay = true,
        ),
    )
end

function load_experiment_spec(spec::AbstractString=DEFAULT_EXPERIMENT_SPEC)
    if isfile(spec)
        path = abspath(spec)
        parsed = TOML.parsefile(path)
        if haskey(parsed, "problem")
            return _front_layer_spec_from_parsed(parsed, path)
        elseif haskey(parsed, "run")
            return experiment_spec_from_canonical_run(path)
        end
        throw(ArgumentError("config `$path` is neither a front-layer experiment spec nor a canonical run config"))
    end

    if spec in approved_experiment_config_ids()
        path = resolve_experiment_config_path(spec)
        return _front_layer_spec_from_parsed(TOML.parsefile(path), path)
    end

    return experiment_spec_from_canonical_run(spec)
end

function experiment_capability_profile(regime::Symbol)
    if regime == :single_mode
        return (
            variables = (
                (:phase,),
                (:phase, :amplitude),
                (:phase, :energy),
                (:phase, :amplitude, :energy),
            ),
            objectives = registered_objective_kinds(regime),
            solvers = (:lbfgs,),
            parameterizations = (:full_grid,),
            initializations = (:zero,),
            grid_policies = (:auto_if_undersized, :exact),
            artifact_bundles = (:standard, :experimental_multivar),
            export_profiles = Tuple(registered_export_profiles()),
        )
    end
    throw(ArgumentError("unknown experiment regime :$regime"))
end

function experiment_execution_mode(spec)
    spec.problem.regime == :single_mode || throw(ArgumentError(
        "no execution mode implemented for regime `$(spec.problem.regime)`"))

    if spec.controls.variables == (:phase,)
        return :phase_only
    end
    return :multivar
end

experiment_export_requested(spec) =
    Bool(spec.export_plan.enabled || spec.artifacts.export_phase_handoff)

function validate_experiment_spec(spec)
    spec.maturity in ("supported", "experimental") || throw(ArgumentError(
        "experiment maturity must be `supported` or `experimental`, got `$(spec.maturity)`"))

    caps = experiment_capability_profile(spec.problem.regime)

    spec.controls.variables in caps.variables || throw(ArgumentError(
        "variables $(spec.controls.variables) are not currently supported for regime `$(spec.problem.regime)`; supported tuples: $(collect(caps.variables))"))
    spec.controls.parameterization in caps.parameterizations || throw(ArgumentError(
        "parameterization `$(spec.controls.parameterization)` is not supported for regime `$(spec.problem.regime)`"))
    spec.controls.initialization in caps.initializations || throw(ArgumentError(
        "initialization `$(spec.controls.initialization)` is not supported for regime `$(spec.problem.regime)`"))
    objective_contract = experiment_objective_contract(spec)
    spec.solver.kind in caps.solvers || throw(ArgumentError(
        "solver `$(spec.solver.kind)` is not supported for regime `$(spec.problem.regime)`"))
    spec.problem.grid_policy in caps.grid_policies || throw(ArgumentError(
        "grid_policy `$(spec.problem.grid_policy)` is not supported for regime `$(spec.problem.regime)`"))
    spec.artifacts.bundle in caps.artifact_bundles || throw(ArgumentError(
        "artifact bundle `$(spec.artifacts.bundle)` is not supported for regime `$(spec.problem.regime)`"))
    export_contract = export_profile_contract(spec.export_plan.profile)
    spec.export_plan.profile in caps.export_profiles || throw(ArgumentError(
        "export profile `$(spec.export_plan.profile)` is not supported for regime `$(spec.problem.regime)`"))
    if :phase_unwrapped_rad in export_contract.columns && !spec.export_plan.include_unwrapped_phase
        throw(ArgumentError(
            "export profile `$(spec.export_plan.profile)` requires include_unwrapped_phase=true"))
    end
    if :group_delay_fs in export_contract.columns && !spec.export_plan.include_group_delay
        throw(ArgumentError(
            "export profile `$(spec.export_plan.profile)` requires include_group_delay=true"))
    end

    spec.problem.Nt > 0 || throw(ArgumentError("problem.Nt must be positive"))
    spec.problem.time_window > 0 || throw(ArgumentError("problem.time_window must be positive"))
    spec.problem.L_fiber > 0 || throw(ArgumentError("problem.L_fiber must be positive"))
    spec.problem.P_cont > 0 || throw(ArgumentError("problem.P_cont must be positive"))
    spec.solver.max_iter > 0 || throw(ArgumentError("solver.max_iter must be positive"))

    mode = experiment_execution_mode(spec)
    spec.controls.variables in objective_contract.supported_variables || throw(ArgumentError(
        "variables $(spec.controls.variables) are not supported by objective `$(spec.objective.kind)`"))
    if mode == :phase_only
        if !(spec.artifacts.bundle == :standard &&
             spec.artifacts.save_payload && spec.artifacts.save_sidecar &&
             spec.artifacts.update_manifest && spec.artifacts.write_trust_report &&
             spec.artifacts.write_standard_images)
            throw(ArgumentError(
                "phase-only execution currently requires the full standard artifact bundle"))
        end
    elseif mode == :multivar
        if !(spec.artifacts.bundle == :experimental_multivar &&
             spec.artifacts.save_payload && spec.artifacts.save_sidecar &&
             spec.artifacts.write_standard_images)
            throw(ArgumentError(
                "multivar execution currently requires the experimental multivar artifact bundle with standard images"))
        end
        if spec.artifacts.update_manifest || spec.artifacts.write_trust_report
            throw(ArgumentError(
                "multivar front-layer execution does not yet support manifest updates or trust-report writing"))
        end
        if experiment_export_requested(spec)
            throw(ArgumentError(
                "multivar front-layer execution does not yet support phase/SLM export handoff"))
        end
    end

    return caps
end

function experiment_plan_lines(spec)
    regs = spec.objective.regularizers
    reg_parts = String[]
    for name in sort!(collect(keys(regs)); by=string)
        push!(reg_parts, string(name, "=", regs[name]))
    end
    reg_summary = isempty(reg_parts) ? "none" : join(reg_parts, ", ")
    mode = experiment_execution_mode(spec)
    export_supported = mode == :phase_only
    export_requested = experiment_export_requested(spec)
    objective_contract = experiment_objective_contract(spec)
    export_contract = export_profile_contract(spec.export_plan.profile)

    return [
        "Experiment spec: $(spec.id)",
        "Description: $(spec.description)",
        "Maturity: $(spec.maturity)",
        "Schema: $(spec.schema)",
        "Config path: $(spec.config_path)",
        "Execution: mode=$(mode) export_supported=$(export_supported) export_requested=$(export_requested)",
        "Problem: regime=$(spec.problem.regime) preset=$(spec.problem.preset) L=$(spec.problem.L_fiber)m P=$(spec.problem.P_cont)W Nt=$(spec.problem.Nt) tw=$(spec.problem.time_window)ps grid=$(spec.problem.grid_policy)",
        "Controls: variables=$(collect(spec.controls.variables)) parameterization=$(spec.controls.parameterization) initialization=$(spec.controls.initialization)",
        "Objective: kind=$(spec.objective.kind) backend=$(objective_contract.backend) log_cost=$(spec.objective.log_cost) regularizers=$(reg_summary)",
        "Solver: kind=$(spec.solver.kind) max_iter=$(spec.solver.max_iter) validate_gradient=$(spec.solver.validate_gradient)",
        "Artifacts: bundle=$(spec.artifacts.bundle) export_enabled=$(spec.export_plan.enabled) export_profile=$(export_contract.profile)",
        "Verification: mode=$(spec.verification.mode) gradient_check=$(spec.verification.gradient_check) artifact_validation=$(spec.verification.artifact_validation)",
    ]
end

render_experiment_plan(spec) = join(experiment_plan_lines(spec), "\n")

end # include guard
