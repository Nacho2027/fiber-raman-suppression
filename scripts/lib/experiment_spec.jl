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
include(joinpath(@__DIR__, "variable_registry.jl"))
include(joinpath(@__DIR__, "control_layout.jl"))
include(joinpath(@__DIR__, "artifact_plan.jl"))

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

registered_experiment_regimes() = (:single_mode, :long_fiber, :multimode)

const EXPERIMENT_PROMOTION_STAGES = (:planning, :smoke, :validated, :lab_ready)

function _promoted_scalar_variable_tuples(regime::Symbol)
    regime == :single_mode || return ()
    tuples = Tuple{Symbol}[]
    for contract in registered_variable_extension_contracts(regime)
        row = validate_variable_extension_contract(contract)
        row.promotable && contract.backend in (:scalar_phase_extension, :vector_phase_extension, :vector_control_extension) &&
            push!(tuples, (contract.kind,))
    end
    return Tuple(tuples)
end

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

function _default_control_policy(regime::Symbol, controls)
    haskey(controls, "policy") && return _normalize_symbol(controls["policy"])
    regime == :long_fiber && return :fresh
    regime == :multimode && return :planning
    return :direct
end

function _policy_options_dict(controls)
    raw = get(controls, "policy_options", Dict{String,Any}())
    opts = Dict{Symbol,Any}()
    for (key, value) in raw
        opts[_normalize_symbol(key)] = value
    end
    return opts
end

function _normalize_lambda(x)
    if x isa AbstractString
        lower = lowercase(strip(String(x)))
        lower == "auto" && return :auto
        return parse(Float64, lower)
    end
    return Float64(x)
end

function _normalize_auto_float(x)
    if x isa AbstractString
        lower = lowercase(strip(String(x)))
        lower == "auto" && return :auto
        return parse(Float64, lower)
    end
    return Float64(x)
end

function _normalize_auto_float_pair(x)
    if x isa AbstractString
        lower = lowercase(strip(String(x)))
        lower == "auto" && return :auto
        throw(ArgumentError("auto-or-pair field must be \"auto\" or a two-element numeric array"))
    end
    x isa AbstractVector || throw(ArgumentError("auto-or-pair field must be \"auto\" or a two-element numeric array"))
    length(x) == 2 || throw(ArgumentError("auto-or-pair field must be \"auto\" or a two-element numeric array"))
    return (Float64(x[1]), Float64(x[2]))
end

function _normalize_auto_float_vector(x)
    if x isa AbstractString
        lower = lowercase(strip(String(x)))
        lower == "auto" && return :auto
        throw(ArgumentError("auto-or-vector field must be \"auto\" or a numeric array"))
    end
    x isa AbstractVector || throw(ArgumentError("auto-or-vector field must be \"auto\" or a numeric array"))
    return Tuple(Float64(item) for item in x)
end

function _require_auto_or_positive_finite(x, label::AbstractString)
    x === :auto && return nothing
    _require_positive_finite(Float64(x), label)
    return nothing
end

function _regularizer_dict(entries)
    regs = Dict{Symbol,Any}()
    for entry in entries
        name = _normalize_symbol(entry["name"])
        regs[name] = _normalize_lambda(entry["lambda"])
    end
    return regs
end

function _plot_contract_from_parsed(parsed)
    plots = get(parsed, "plots", Dict{String,Any}())
    temporal = get(plots, "temporal_pulse", Dict{String,Any}())
    spectrum = get(plots, "spectrum", Dict{String,Any}())
    return (
        temporal_pulse = (
            time_range = _normalize_auto_float_pair(get(temporal, "time_range", "auto")),
            normalize = Bool(get(temporal, "normalize", false)),
            energy_low = Float64(get(temporal, "energy_low", 0.001)),
            energy_high = Float64(get(temporal, "energy_high", 0.999)),
            margin_fraction = Float64(get(temporal, "margin_fraction", 0.20)),
        ),
        spectrum = (
            dynamic_range_dB = Float64(get(spectrum, "dynamic_range_dB", 70.0)),
        ),
    )
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

    regime = _normalize_symbol(problem["regime"])

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
            regime = regime,
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
            policy = _default_control_policy(regime, controls),
            policy_options = _policy_options_dict(controls),
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
            f_abstol = _normalize_auto_float(get(solver, "f_abstol", "auto")),
            g_abstol = _normalize_auto_float(get(solver, "g_abstol", "auto")),
            scalar_lower = _normalize_auto_float(get(solver, "scalar_lower", "auto")),
            scalar_upper = _normalize_auto_float(get(solver, "scalar_upper", "auto")),
            scalar_x_tol = _normalize_auto_float(get(solver, "scalar_x_tol", 1e-3)),
            vector_initial = _normalize_auto_float_vector(get(solver, "vector_initial", "auto")),
            vector_lower = _normalize_auto_float_vector(get(solver, "vector_lower", "auto")),
            vector_upper = _normalize_auto_float_vector(get(solver, "vector_upper", "auto")),
            vector_x_tol = _normalize_auto_float(get(solver, "vector_x_tol", 1e-3)),
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
        plots = _plot_contract_from_parsed(parsed),
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
            policy = :direct,
            policy_options = Dict{Symbol,Any}(),
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
            f_abstol = :auto,
            g_abstol = :auto,
            scalar_lower = :auto,
            scalar_upper = :auto,
            scalar_x_tol = :auto,
            vector_initial = :auto,
            vector_lower = :auto,
            vector_upper = :auto,
            vector_x_tol = :auto,
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
        plots = _plot_contract_from_parsed(Dict{String,Any}()),
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
                (:reduced_phase,),
                (:gain_tilt,),
                (:quadratic_phase,),
                (:phase, :gain_tilt),
                (:phase, :amplitude),
                (:phase, :energy),
                (:phase, :amplitude, :energy),
                _promoted_scalar_variable_tuples(regime)...,
            ),
            objectives = registered_objective_kinds(regime),
            solvers = (:lbfgs, :bounded_scalar, :nelder_mead),
            parameterizations = (:full_grid, :basis_coefficients, :vector_coefficients),
            initializations = (:zero,),
            policies = (:direct, :amp_on_phase),
            grid_policies = (:auto_if_undersized, :exact),
            artifact_bundles = (:standard, :experimental_multivar),
            export_profiles = Tuple(registered_export_profiles()),
        )
    end
    if regime == :long_fiber
        return (
            variables = ((:phase,),),
            objectives = registered_objective_kinds(regime),
            solvers = (:lbfgs,),
            parameterizations = (:full_grid,),
            initializations = (:zero,),
            policies = (:fresh, :resume, :resume_check),
            grid_policies = (:exact, :auto_if_undersized),
            artifact_bundles = (:standard,),
            export_profiles = Tuple(registered_export_profiles()),
        )
    end
    if regime == :multimode
        return (
            variables = ((:phase,),),
            objectives = registered_objective_kinds(regime),
            solvers = (:lbfgs,),
            parameterizations = (:shared_across_modes,),
            initializations = (:zero,),
            policies = (:planning, :direct),
            grid_policies = (:auto_if_undersized, :exact),
            artifact_bundles = (:mmf_planning,),
            export_profiles = Tuple(registered_export_profiles()),
        )
    end
    throw(ArgumentError("unknown experiment regime :$regime"))
end

function experiment_execution_mode(spec)
    if spec.problem.regime == :single_mode
        if spec.controls.policy == :amp_on_phase
            spec.controls.variables == (:phase, :amplitude) || throw(ArgumentError(
                "amp_on_phase policy requires controls.variables=[\"phase\", \"amplitude\"]"))
            return :amp_on_phase
        end
        if spec.controls.variables == (:phase,)
            return :phase_only
        end
        if spec.controls.variables == (:reduced_phase,) && spec.solver.kind == :lbfgs
            return :reduced_phase
        end
        if spec.controls.variables in ((:gain_tilt,), (:quadratic_phase,)) && spec.solver.kind == :bounded_scalar
            return :scalar_search
        end
        if length(spec.controls.variables) == 1 && spec.solver.kind == :bounded_scalar
            contract = variable_contract(only(spec.controls.variables), spec.problem.regime)
            contract.backend == :scalar_phase_extension && return :scalar_search
        end
        if length(spec.controls.variables) == 1 && spec.solver.kind == :nelder_mead
            contract = variable_contract(only(spec.controls.variables), spec.problem.regime)
            contract.backend in (:vector_phase_extension, :vector_control_extension) && return :vector_search
        end
        return :multivar
    elseif spec.problem.regime == :long_fiber
        spec.controls.variables == (:phase,) || throw(ArgumentError(
            "long_fiber currently supports phase-only controls"))
        return :long_fiber_phase
    elseif spec.problem.regime == :multimode
        spec.controls.variables == (:phase,) || throw(ArgumentError(
            "multimode currently supports phase-only controls"))
        return :multimode_phase
    end
    throw(ArgumentError("no execution mode implemented for regime `$(spec.problem.regime)`"))
end

experiment_export_requested(spec) =
    Bool(spec.export_plan.enabled || spec.artifacts.export_phase_handoff)

function _push_blocker!(blockers::Vector{Symbol}, blocker::Symbol)
    blocker in blockers || push!(blockers, blocker)
    return blockers
end

function experiment_promotion_status(spec)
    mode = experiment_execution_mode(spec)
    artifact_plan = experiment_artifact_plan(spec)
    blockers = Symbol[]

    artifact_plan.implemented || _push_blocker!(blockers, :unimplemented_artifacts)
    spec.maturity == "supported" || _push_blocker!(blockers, :experimental_maturity)
    spec.verification.mode == :burst_required && _push_blocker!(blockers, :burst_required)

    front_layer_executable = mode in (:phase_only, :reduced_phase, :multivar, :scalar_search, :vector_search) ||
        (mode == :long_fiber_phase && spec.verification.mode != :burst_required) ||
        (mode == :multimode_phase && spec.verification.mode != :burst_required)
    if !front_layer_executable
        _push_blocker!(blockers, mode == :amp_on_phase ? :dedicated_workflow_only : :front_layer_execution_blocked)
    end

    if mode == :multivar || mode == :scalar_search || mode == :vector_search
        spec.artifacts.write_trust_report || _push_blocker!(blockers, :no_trust_report)
        spec.artifacts.update_manifest || _push_blocker!(blockers, :no_manifest_update)
        experiment_export_requested(spec) || _push_blocker!(blockers, :no_export_handoff)
    elseif mode == :amp_on_phase
        _push_blocker!(blockers, :no_front_layer_execution)
        spec.artifacts.write_trust_report || _push_blocker!(blockers, :no_trust_report)
        spec.artifacts.update_manifest || _push_blocker!(blockers, :no_manifest_update)
        experiment_export_requested(spec) || _push_blocker!(blockers, :no_export_handoff)
    elseif (mode == :long_fiber_phase && spec.verification.mode == :burst_required) ||
            (mode == :multimode_phase && spec.verification.mode == :burst_required)
        _push_blocker!(blockers, :no_local_smoke)
        experiment_export_requested(spec) || _push_blocker!(blockers, :no_export_handoff)
    elseif mode == :long_fiber_phase
        experiment_export_requested(spec) || _push_blocker!(blockers, :no_export_handoff)
    elseif mode == :multimode_phase
        experiment_export_requested(spec) || _push_blocker!(blockers, :no_export_handoff)
    end

    stage =
        mode == :long_fiber_phase && front_layer_executable && artifact_plan.implemented ? :smoke :
        mode in (:long_fiber_phase, :amp_on_phase) ? :planning :
        mode == :multimode_phase && front_layer_executable && artifact_plan.implemented ? :smoke :
        mode == :multimode_phase ? :planning :
        mode == :phase_only && spec.maturity == "supported" && artifact_plan.implemented ? :lab_ready :
        mode in (:phase_only, :reduced_phase, :multivar, :scalar_search, :vector_search) && artifact_plan.implemented ? :smoke :
        :planning

    requirements = stage == :lab_ready ? Symbol[] : Symbol[
        :passing_config_validation,
        :passing_executable_smoke,
        :complete_artifact_set,
        :visual_artifact_inspection,
        :documented_scientific_scope,
        :representative_real_size_validation,
    ]

    return (
        stage = stage,
        mode = mode,
        executable = front_layer_executable,
        local_execution_allowed = front_layer_executable && spec.verification.mode != :burst_required,
        artifact_plan_implemented = artifact_plan.implemented,
        blockers = Tuple(blockers),
        requirements = Tuple(requirements),
    )
end

function _promotion_blocker_summary(status)
    isempty(status.blockers) && return "none"
    return join(string.(status.blockers), ", ")
end

function _symbol_tuple_summary(items)
    isempty(items) && return "none"
    return join(string.(items), ", ")
end

function experiment_explore_run_policy(spec; local_smoke::Bool=false, heavy_ok::Bool=false)
    validate_experiment_spec(spec)
    mode = experiment_execution_mode(spec)
    status = experiment_promotion_status(spec)
    blockers = Symbol[]
    warnings = Symbol[]

    action = mode == :amp_on_phase ? :dedicated_workflow : :front_layer

    spec.maturity != "supported" && _push_blocker!(warnings, :experimental_run)
    status.stage != :lab_ready && _push_blocker!(warnings, Symbol(string("stage_", status.stage)))

    if action == :front_layer
        if spec.verification.mode == :burst_required && !heavy_ok
            _push_blocker!(blockers, :requires_heavy_ok)
        end
        if spec.maturity != "supported" && !local_smoke && !heavy_ok
            _push_blocker!(blockers, :requires_local_smoke)
        end
        spec.verification.mode == :burst_required && _push_blocker!(warnings, :heavy_compute)
    else
        if !heavy_ok
            _push_blocker!(blockers, :requires_heavy_ok)
        end
        _push_blocker!(warnings, :heavy_compute)
        mode == :amp_on_phase && _push_blocker!(warnings, :dedicated_staged_multivar_workflow)
        mode == :long_fiber_phase && _push_blocker!(warnings, :dedicated_long_fiber_workflow)
        mode == :multimode_phase && _push_blocker!(warnings, :dedicated_multimode_workflow)
    end

    return (
        allowed = isempty(blockers),
        action = action,
        mode = mode,
        stage = status.stage,
        blockers = Tuple(blockers),
        warnings = Tuple(warnings),
    )
end

function render_explore_run_policy(spec; local_smoke::Bool=false, heavy_ok::Bool=false, io::IO=stdout)
    policy = experiment_explore_run_policy(spec; local_smoke=local_smoke, heavy_ok=heavy_ok)
    println(io, "Explore run policy:")
    println(io, "  allowed=", policy.allowed)
    println(io, "  action=", policy.action)
    println(io, "  mode=", policy.mode)
    println(io, "  promotion_stage=", policy.stage)
    println(io, "  blockers=", _symbol_tuple_summary(policy.blockers))
    println(io, "  warnings=", _symbol_tuple_summary(policy.warnings))
    return policy
end

function _push_unique_symbol!(items::Vector{Symbol}, item::Symbol)
    item in items || push!(items, item)
    return items
end

function _research_run_path(spec, mode::Symbol, status)
    spec_hint = experiment_cli_spec_hint(spec)
    if mode == :phase_only && spec.maturity == "supported" && status.stage == :lab_ready
        return (
            kind = :run,
            command = "./fiberlab run $(spec_hint)",
        )
    elseif mode in (:phase_only, :reduced_phase, :multivar, :scalar_search, :vector_search, :long_fiber_phase, :multimode_phase) && status.local_execution_allowed
        return (
            kind = :explore_local_smoke,
            command = "./fiberlab explore run $(spec_hint) --local-smoke",
        )
    end
    return (
        kind = :explore_heavy_dry_run,
        command = "./fiberlab explore run $(spec_hint) --heavy-ok --dry-run",
    )
end

function research_config_check_report(spec)
    missing = Symbol[]
    validation_ok = true
    validation_error = ""
    mode = :unknown
    status = nothing
    artifact_plan = nothing

    try
        validate_experiment_spec(spec)
        mode = experiment_execution_mode(spec)
        status = experiment_promotion_status(spec)
        artifact_plan = experiment_artifact_plan(spec)
    catch err
        validation_ok = false
        validation_error = sprint(showerror, err)
        _push_unique_symbol!(missing, :config_validation_failed)
    end

    if validation_ok
        for blocker in status.blockers
            _push_unique_symbol!(missing, blocker)
        end
        artifact_plan.implemented || _push_unique_symbol!(missing, :artifact_plan_not_implemented)
        spec.verification.artifact_validation || _push_unique_symbol!(missing, :artifact_validation_disabled)
        spec.verification.block_on_failed_checks || _push_unique_symbol!(missing, :failed_checks_do_not_block)
        spec.artifacts.save_payload || _push_unique_symbol!(missing, :payload_disabled)
        spec.artifacts.save_sidecar || _push_unique_symbol!(missing, :json_sidecar_disabled)
        mode in (:phase_only, :reduced_phase, :multivar, :scalar_search, :vector_search, :long_fiber_phase, :multimode_phase) &&
            status.local_execution_allowed || _push_unique_symbol!(missing, :requires_dedicated_workflow)
    end

    compare_ready = validation_ok &&
        spec.artifacts.save_payload &&
        spec.artifacts.save_sidecar &&
        spec.artifacts.update_manifest
    run_path = validation_ok ?
        _research_run_path(spec, mode, status) :
        (kind = :blocked, command = "fix config validation errors before running")
    hooks = validation_ok ? Tuple(request.hook for request in artifact_plan.hooks) : Symbol[]
    stage = validation_ok ? status.stage : :invalid
    inspect_command = validation_ok ?
        "./fiberlab explore plan $(experiment_cli_spec_hint(spec))" :
        "fix config validation errors before inspection"
    compare_command = validation_ok ?
        "./fiberlab explore compare $(spec.output_root) --contains $(spec.output_tag)" :
        "fix config validation errors before comparison"

    return (
        kind = :config,
        target = validation_ok ? spec.id : "invalid",
        config_path = spec.config_path,
        validation_ok = validation_ok,
        validation_error = validation_error,
        stage = stage,
        mode = mode,
        regime = spec.problem.regime,
        maturity = spec.maturity,
        variables = spec.controls.variables,
        objective = spec.objective.kind,
        artifact_plan_implemented = validation_ok ? artifact_plan.implemented : false,
        artifact_hooks = Tuple(hooks),
        compare_ready = compare_ready,
        run_path = run_path.kind,
        run_command = run_path.command,
        inspect_command = inspect_command,
        compare_command = compare_command,
        missing = Tuple(missing),
        pass = validation_ok && isempty(missing),
    )
end

research_config_check_report(spec::AbstractString) =
    research_config_check_report(load_experiment_spec(spec))

function render_research_config_check(report; io::IO=stdout)
    println(io, "# Research Config Check")
    println(io)
    println(io, "- Scope: `", report.kind, "`")
    println(io, "- Target: `", report.target, "`")
    println(io, "- Status: `", report.pass ? "PASS" : "NEEDS_WORK", "`")
    println(io, "- Current confidence: `", report.stage, "`")
    println(io, "- Mode: `", report.mode, "`")
    println(io, "- Regime: `", report.regime, "`")
    println(io, "- Variables: `", join(string.(report.variables), ","), "`")
    println(io, "- Objective: `", report.objective, "`")
    println(io, "- Config validation: `", report.validation_ok, "`")
    if !report.validation_ok
        println(io, "- Validation error: `", report.validation_error, "`")
    end
    println(io, "- Artifact plan implemented: `", report.artifact_plan_implemented, "`")
    println(io, "- Artifact hooks: `", isempty(report.artifact_hooks) ? "none" : join(string.(report.artifact_hooks), ","), "`")
    println(io, "- Compare-ready metadata: `", report.compare_ready, "`")
    println(io, "- Run path: `", report.run_command, "`")
    println(io, "- Inspect first: `", report.inspect_command, "`")
    println(io, "- Compare after runs: `", report.compare_command, "`")
    println(io, "- Missing pieces: `", isempty(report.missing) ? "none" : join(string.(report.missing), ","), "`")
    return nothing
end

function _require_positive_finite(value, label::AbstractString)
    numeric = Float64(value)
    isfinite(numeric) && numeric > 0 || throw(ArgumentError("$label must be positive and finite"))
    return nothing
end

function _validate_objective_regularizers(spec, objective_contract)
    allowed = Set(objective_contract.allowed_regularizers)
    for (name, lambda) in spec.objective.regularizers
        name in allowed || throw(ArgumentError(
            "regularizer `$(name)` is not allowed for objective `$(spec.objective.kind)`; allowed regularizers: $(collect(objective_contract.allowed_regularizers))"))
        lambda == :auto && continue
        lambda isa Real || throw(ArgumentError(
            "regularizer `$(name)` lambda must be numeric or \"auto\""))
        numeric = Float64(lambda)
        isfinite(numeric) && numeric >= 0 || throw(ArgumentError(
            "regularizer `$(name)` lambda must be nonnegative and finite"))
    end
    return nothing
end

function _validate_plot_contract(spec)
    temporal = spec.plots.temporal_pulse
    if temporal.time_range !== :auto
        lo, hi = temporal.time_range
        (isfinite(lo) && isfinite(hi) && lo < hi) || throw(ArgumentError(
            "plots.temporal_pulse.time_range must be [low, high] with low < high"))
    end
    (isfinite(temporal.energy_low) && isfinite(temporal.energy_high) &&
     0 <= temporal.energy_low < temporal.energy_high <= 1) || throw(ArgumentError(
        "plots.temporal_pulse energy_low/energy_high must satisfy 0 <= low < high <= 1"))
    isfinite(temporal.margin_fraction) && temporal.margin_fraction >= 0 || throw(ArgumentError(
        "plots.temporal_pulse.margin_fraction must be nonnegative and finite"))
    _require_positive_finite(spec.plots.spectrum.dynamic_range_dB, "plots.spectrum.dynamic_range_dB")
    return nothing
end

function _reject_planning_variable_extensions(spec)
    for variable in spec.controls.variables
        variable in registered_variable_extension_kinds(spec.problem.regime) || continue
        contract = variable_extension_contract(variable, spec.problem.regime)
        row = validate_variable_extension_contract(contract)
        blockers = isempty(row.blockers) ? "none" : join(row.blockers, ",")
        errors = isempty(row.errors) ? "none" : join(row.errors, ",")
        throw(ArgumentError(
            "variable `$(variable)` is a research extension for regime `$(spec.problem.regime)`, but it is not promoted for execution; blockers: $(blockers); errors: $(errors)"))
    end
    return nothing
end

function validate_experiment_spec(spec)
    spec.maturity in ("supported", "experimental") || throw(ArgumentError(
        "experiment maturity must be `supported` or `experimental`, got `$(spec.maturity)`"))

    caps = experiment_capability_profile(spec.problem.regime)

    if !(spec.controls.variables in caps.variables)
        _reject_planning_variable_extensions(spec)
        throw(ArgumentError(
            "variables $(spec.controls.variables) are not currently supported for regime `$(spec.problem.regime)`; supported tuples: $(collect(caps.variables))"))
    end
    variable_contracts = experiment_variable_contracts(spec)
    spec.controls.parameterization in caps.parameterizations || throw(ArgumentError(
        "parameterization `$(spec.controls.parameterization)` is not supported for regime `$(spec.problem.regime)`"))
    spec.controls.initialization in caps.initializations || throw(ArgumentError(
        "initialization `$(spec.controls.initialization)` is not supported for regime `$(spec.problem.regime)`"))
    spec.controls.policy in caps.policies || throw(ArgumentError(
        "policy `$(spec.controls.policy)` is not supported for regime `$(spec.problem.regime)`; supported policies: $(collect(caps.policies))"))
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
    _require_positive_finite(spec.problem.time_window, "problem.time_window")
    _require_positive_finite(spec.problem.L_fiber, "problem.L_fiber")
    _require_positive_finite(spec.problem.P_cont, "problem.P_cont")
    _require_positive_finite(spec.problem.pulse_fwhm, "problem.pulse_fwhm")
    _require_positive_finite(spec.problem.pulse_rep_rate, "problem.pulse_rep_rate")
    spec.problem.β_order > 0 || throw(ArgumentError("problem.beta_order must be positive"))
    spec.solver.max_iter > 0 || throw(ArgumentError("solver.max_iter must be positive"))
    _require_positive_finite(spec.solver.reltol, "solver.reltol")
    _require_auto_or_positive_finite(spec.solver.f_abstol, "solver.f_abstol")
    _require_auto_or_positive_finite(spec.solver.g_abstol, "solver.g_abstol")
    _require_auto_or_positive_finite(spec.solver.scalar_x_tol, "solver.scalar_x_tol")
    _require_auto_or_positive_finite(spec.solver.vector_x_tol, "solver.vector_x_tol")
    _validate_objective_regularizers(spec, objective_contract)
    if objective_contract.backend == :scalar_extension && spec.objective.log_cost
        throw(ArgumentError(
            "scalar extension objective `$(spec.objective.kind)` must set objective.log_cost=false; extension costs own their scaling"))
    end
    _validate_plot_contract(spec)

    mode = experiment_execution_mode(spec)
    if spec.solver.kind == :bounded_scalar
        scalar_extension_ok = length(spec.controls.variables) == 1 &&
            variable_contract(only(spec.controls.variables), spec.problem.regime).backend == :scalar_phase_extension
        spec.controls.variables in ((:gain_tilt,), (:quadratic_phase,)) || scalar_extension_ok || throw(ArgumentError(
            "bounded_scalar currently supports controls.variables=[\"gain_tilt\"], [\"quadratic_phase\"], or one promoted scalar variable extension"))
        spec.solver.scalar_lower === :auto && throw(ArgumentError(
            "bounded_scalar requires numeric solver.scalar_lower"))
        spec.solver.scalar_upper === :auto && throw(ArgumentError(
            "bounded_scalar requires numeric solver.scalar_upper"))
        isfinite(Float64(spec.solver.scalar_lower)) || throw(ArgumentError(
            "solver.scalar_lower must be finite"))
        isfinite(Float64(spec.solver.scalar_upper)) || throw(ArgumentError(
            "solver.scalar_upper must be finite"))
        Float64(spec.solver.scalar_lower) < Float64(spec.solver.scalar_upper) || throw(ArgumentError(
            "solver.scalar_lower must be less than solver.scalar_upper"))
        spec.solver.vector_initial === :auto || throw(ArgumentError(
            "solver.vector_initial is only valid for solver.kind=\"nelder_mead\""))
        spec.solver.vector_lower === :auto || throw(ArgumentError(
            "solver.vector_lower is only valid for solver.kind=\"nelder_mead\""))
        spec.solver.vector_upper === :auto || throw(ArgumentError(
            "solver.vector_upper is only valid for solver.kind=\"nelder_mead\""))
    elseif spec.solver.kind == :nelder_mead
        length(spec.controls.variables) == 1 || throw(ArgumentError(
            "nelder_mead currently supports exactly one promoted vector variable extension"))
        variable = variable_contract(only(spec.controls.variables), spec.problem.regime)
        variable.backend in (:vector_phase_extension, :vector_control_extension) || throw(ArgumentError(
            "nelder_mead currently supports one promoted vector_phase_extension or vector_control_extension variable"))
        objective_contract.backend == :scalar_extension || throw(ArgumentError(
            "nelder_mead playground execution currently requires a scalar_extension objective"))
        dim = get(variable, :dimension, 0)
        spec.solver.vector_initial === :auto && throw(ArgumentError(
            "nelder_mead requires numeric solver.vector_initial"))
        spec.solver.vector_lower === :auto && throw(ArgumentError(
            "nelder_mead requires numeric solver.vector_lower"))
        spec.solver.vector_upper === :auto && throw(ArgumentError(
            "nelder_mead requires numeric solver.vector_upper"))
        length(spec.solver.vector_initial) == dim || throw(ArgumentError(
            "solver.vector_initial length must match variable dimension $dim"))
        length(spec.solver.vector_lower) == dim || throw(ArgumentError(
            "solver.vector_lower length must match variable dimension $dim"))
        length(spec.solver.vector_upper) == dim || throw(ArgumentError(
            "solver.vector_upper length must match variable dimension $dim"))
        all(isfinite, spec.solver.vector_initial) || throw(ArgumentError(
            "solver.vector_initial entries must be finite"))
        all(isfinite, spec.solver.vector_lower) || throw(ArgumentError(
            "solver.vector_lower entries must be finite"))
        all(isfinite, spec.solver.vector_upper) || throw(ArgumentError(
            "solver.vector_upper entries must be finite"))
        all(spec.solver.vector_lower .< spec.solver.vector_upper) || throw(ArgumentError(
            "solver.vector_lower entries must be less than solver.vector_upper entries"))
        all(lo <= x <= hi for (lo, x, hi) in zip(spec.solver.vector_lower, spec.solver.vector_initial, spec.solver.vector_upper)) || throw(ArgumentError(
            "solver.vector_initial must lie inside vector bounds"))
        (spec.solver.scalar_lower === :auto && spec.solver.scalar_upper === :auto) || throw(ArgumentError(
            "solver.scalar_lower/scalar_upper are only valid for solver.kind=\"bounded_scalar\""))
    else
        (spec.solver.scalar_lower === :auto && spec.solver.scalar_upper === :auto) || throw(ArgumentError(
            "solver.scalar_lower/scalar_upper are only valid for solver.kind=\"bounded_scalar\""))
        spec.solver.vector_initial === :auto || throw(ArgumentError(
            "solver.vector_initial is only valid for solver.kind=\"nelder_mead\""))
        spec.solver.vector_lower === :auto || throw(ArgumentError(
            "solver.vector_lower is only valid for solver.kind=\"nelder_mead\""))
        spec.solver.vector_upper === :auto || throw(ArgumentError(
            "solver.vector_upper is only valid for solver.kind=\"nelder_mead\""))
    end
    for contract in variable_contracts
        spec.controls.parameterization in contract.parameterizations || throw(ArgumentError(
            "variable `$(contract.kind)` does not support parameterization `$(spec.controls.parameterization)`; supported parameterizations: $(collect(contract.parameterizations))"))
    end
    if mode == :phase_only || mode == :reduced_phase
        if !(spec.artifacts.bundle == :standard &&
             spec.artifacts.save_payload && spec.artifacts.save_sidecar &&
             spec.artifacts.update_manifest && spec.artifacts.write_trust_report &&
             spec.artifacts.write_standard_images)
            throw(ArgumentError(
                "phase-like adjoint execution currently requires the full standard artifact bundle"))
        end
    elseif mode == :multivar || mode == :scalar_search || mode == :vector_search || mode == :amp_on_phase
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
    elseif mode == :long_fiber_phase
        spec.maturity == "experimental" || throw(ArgumentError(
            "long_fiber front-layer configs must be marked experimental"))
        spec.verification.mode in (:standard, :burst_required) || throw(ArgumentError(
            "long_fiber front-layer configs must use verification.mode=\"standard\" or \"burst_required\""))
        if spec.verification.mode == :standard
            spec.problem.Nt <= 4096 || throw(ArgumentError(
                "standard long_fiber front-layer smoke requires Nt <= 4096; mark larger grids verification.mode=\"burst_required\" and use the provider-neutral compute plan"))
            spec.problem.L_fiber <= 10.0 || throw(ArgumentError(
                "standard long_fiber front-layer smoke requires L_fiber <= 10 m; mark longer studies verification.mode=\"burst_required\" and use the provider-neutral compute plan"))
            spec.solver.max_iter <= 5 || throw(ArgumentError(
                "standard long_fiber front-layer smoke requires solver.max_iter <= 5; mark larger studies verification.mode=\"burst_required\" and use the provider-neutral compute plan"))
        end
        if experiment_export_requested(spec)
            throw(ArgumentError(
                "long_fiber front-layer execution does not yet support phase export handoff"))
        end
        if !(spec.artifacts.bundle == :standard &&
             spec.artifacts.save_payload && spec.artifacts.save_sidecar &&
             spec.artifacts.update_manifest && spec.artifacts.write_trust_report &&
             spec.artifacts.write_standard_images)
            throw(ArgumentError(
                "long_fiber execution currently requires the full standard artifact bundle"))
        end
    elseif mode == :multimode_phase
        spec.maturity == "experimental" || throw(ArgumentError(
            "multimode front-layer configs must be marked experimental"))
        if experiment_export_requested(spec)
            throw(ArgumentError(
                "multimode front-layer execution does not yet support phase export handoff"))
        end
        if !(spec.artifacts.bundle == :mmf_planning &&
             spec.artifacts.save_payload && spec.artifacts.save_sidecar &&
             spec.artifacts.write_standard_images)
            throw(ArgumentError(
                "multimode planning currently requires the mmf_planning artifact bundle with standard images"))
        end
        if spec.artifacts.update_manifest || spec.artifacts.write_trust_report
            throw(ArgumentError(
                "multimode front-layer execution does not yet support manifest updates or trust-report writing"))
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
    burst_required = spec.verification.mode == :burst_required
    objective_contract = experiment_objective_contract(spec)
    export_contract = export_profile_contract(spec.export_plan.profile)
    layout = control_layout_plan(spec)
    artifact_plan = experiment_artifact_plan(spec)
    promotion_status = experiment_promotion_status(spec)
    layout_summary = join((string(block.name, ":", block.shape, ":", block.units)
        for block in layout.blocks), "; ")
    artifact_hook_summary = isempty(artifact_plan.hooks) ?
        "none" :
        join(string.(Tuple(request.hook for request in artifact_plan.hooks)), ", ")
    policy_option_parts = String[]
    for name in sort!(collect(keys(spec.controls.policy_options)); by=string)
        push!(policy_option_parts, string(name, "=", spec.controls.policy_options[name]))
    end
    policy_option_summary = isempty(policy_option_parts) ? "none" : join(policy_option_parts, ", ")

    solver_suffix =
        spec.solver.kind == :bounded_scalar ?
            " scalar_lower=$(spec.solver.scalar_lower) scalar_upper=$(spec.solver.scalar_upper) scalar_x_tol=$(spec.solver.scalar_x_tol)" :
        spec.solver.kind == :nelder_mead ?
            " vector_initial=$(collect(spec.solver.vector_initial)) vector_lower=$(collect(spec.solver.vector_lower)) vector_upper=$(collect(spec.solver.vector_upper)) vector_x_tol=$(spec.solver.vector_x_tol)" :
            ""

    return [
        "Experiment spec: $(spec.id)",
        "Description: $(spec.description)",
        "Maturity: $(spec.maturity)",
        "Schema: $(spec.schema)",
        "Config path: $(spec.config_path)",
        "Execution: mode=$(mode) export_supported=$(export_supported) export_requested=$(export_requested) burst_required=$(burst_required)",
        "Promotion stage: $(promotion_status.stage)",
        "Promotion blockers: $(_promotion_blocker_summary(promotion_status))",
        "Problem: regime=$(spec.problem.regime) preset=$(spec.problem.preset) L=$(spec.problem.L_fiber)m P=$(spec.problem.P_cont)W Nt=$(spec.problem.Nt) tw=$(spec.problem.time_window)ps grid=$(spec.problem.grid_policy)",
        "Controls: variables=$(collect(spec.controls.variables)) parameterization=$(spec.controls.parameterization) initialization=$(spec.controls.initialization) policy=$(spec.controls.policy) policy_options=$(policy_option_summary)",
        "Control layout: optimizer_length=$(layout.total_length) blocks=$(layout_summary)",
        "Objective: kind=$(spec.objective.kind) backend=$(objective_contract.backend) log_cost=$(spec.objective.log_cost) regularizers=$(reg_summary)",
        "Solver: kind=$(spec.solver.kind) max_iter=$(spec.solver.max_iter) validate_gradient=$(spec.solver.validate_gradient)$(solver_suffix)",
        "Artifacts: bundle=$(spec.artifacts.bundle) export_enabled=$(spec.export_plan.enabled) export_profile=$(export_contract.profile)",
        "Artifact plan: implemented_now=$(artifact_plan.implemented) hooks=$(artifact_hook_summary)",
        "Verification: mode=$(spec.verification.mode) gradient_check=$(spec.verification.gradient_check) artifact_validation=$(spec.verification.artifact_validation)",
    ]
end

render_experiment_plan(spec) = join(experiment_plan_lines(spec), "\n")

function render_experiment_capabilities(; io::IO=stdout)
    println(io, "Experiment capabilities:")
    println(io, "  promotion_stages=", join(string.(EXPERIMENT_PROMOTION_STAGES), ", "))
    for regime in registered_experiment_regimes()
        caps = experiment_capability_profile(regime)
        println(io, "  regime=", regime)
        stage_summary =
            regime == :single_mode ? "lab_ready for supported phase-only; smoke for experimental multivariable" :
            regime == :multimode ? "smoke for standard-verification shared-phase MMF; high-resource configs use dedicated workflows" :
            "planning/dedicated workflow until long-fiber execution is merged into the core single-mode path"
        println(io, "    current_stage=", stage_summary)
        println(io, "    variables=", _objective_tuple_summary(caps.variables))
        println(io, "    objectives=", join(string.(caps.objectives), ", "))
        println(io, "    solvers=", join(string.(caps.solvers), ", "))
        println(io, "    parameterizations=", join(string.(caps.parameterizations), ", "))
        println(io, "    initializations=", join(string.(caps.initializations), ", "))
        println(io, "    policies=", join(string.(caps.policies), ", "))
        println(io, "    grid_policies=", join(string.(caps.grid_policies), ", "))
        println(io, "    artifact_bundles=", join(string.(caps.artifact_bundles), ", "))
        println(io, "    export_profiles=", join(string.(caps.export_profiles), ", "))
    end
    println(io)
    println(io, "Execution notes:")
    println(io, "  single_mode phase-only is the supported local execution path.")
    println(io, "  single_mode multivariable controls are experimental.")
    println(io, "  use `fiberlab explore` for intentional experimental playground runs.")
    println(io, "  multimode shared-phase smoke configs can execute through the front layer.")
    println(io, "  long_fiber should converge toward the core single-mode path with explicit length-scaling checks.")
    println(io, "  Configs select from these contracts; new physics and new controls still belong in code first.")
    return nothing
end

function validate_all_experiment_configs(; ids=approved_experiment_config_ids())
    reports = []
    for id in ids
        try
            spec = load_experiment_spec(id)
            validate_experiment_spec(spec)
            push!(reports, (
                id = id,
                ok = true,
                spec_id = spec.id,
                regime = spec.problem.regime,
                mode = experiment_execution_mode(spec),
                maturity = spec.maturity,
                config_path = spec.config_path,
                error = "",
            ))
        catch err
            push!(reports, (
                id = id,
                ok = false,
                spec_id = id,
                regime = :unknown,
                mode = :unknown,
                maturity = "unknown",
                config_path = "",
                error = sprint(showerror, err),
            ))
        end
    end

    passed = count(report -> report.ok, reports)
    failed = length(reports) - passed
    return (
        complete = failed == 0,
        total = length(reports),
        passed = passed,
        failed = failed,
        reports = Tuple(reports),
    )
end

function render_experiment_validation_report(report; io::IO=stdout)
    println(io, "Experiment config validation: complete=$(report.complete) passed=$(report.passed) failed=$(report.failed) total=$(report.total)")
    for item in report.reports
        if item.ok
            println(io,
                "  [ok] ",
                item.id,
                "  spec_id=", item.spec_id,
                "  regime=", item.regime,
                "  mode=", item.mode,
                "  maturity=", item.maturity)
        else
            println(io, "  [fail] ", item.id, "  ", item.error)
        end
    end
    return nothing
end

function experiment_cli_spec_hint(spec)
    return spec.schema == :experiment_v1 ? basename(splitext(spec.config_path)[1]) : spec.id
end

function experiment_compute_plan_lines(spec)
    validate_experiment_spec(spec)

    mode = experiment_execution_mode(spec)
    promotion_status = experiment_promotion_status(spec)
    spec_hint = experiment_cli_spec_hint(spec)
    dry_run_cmd = "julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run $(spec_hint)"
    local_cmd = "julia -t auto --project=. scripts/canonical/run_experiment.jl $(spec_hint)"

    lines = String[
        "Compute plan: $(spec.id)",
        "Regime: $(spec.problem.regime)",
        "Execution mode: $(mode)",
        "Promotion status:",
        "  Promotion stage: $(promotion_status.stage)",
        "  Promotion blockers: $(_promotion_blocker_summary(promotion_status))",
        "No command in this plan is launched automatically.",
        "Inspect first:",
        "  $(dry_run_cmd)",
    ]

    if mode == :long_fiber_phase
        if promotion_status.local_execution_allowed
            append!(lines, [
                "Front-layer command:",
                "  $(local_cmd)",
                "Provider-neutral path:",
                "  This long-fiber smoke config runs through the same front-layer CLI as other executable experiments.",
                "  It uses exact-grid single-mode propagation plus a long-fiber reach diagnostic.",
                "  Increase L_fiber, Nt, time_window, or max_iter only when you are prepared for the added CPU/memory cost.",
            ])
        else
            lf_cmd = "julia -t auto --project=. scripts/canonical/run_experiment.jl --heavy-ok $(spec_hint)"
            append!(lines, [
                "Provider-neutral path:",
                "  1. Use any machine or cluster environment with enough CPU time and memory for the configured grid.",
                "  2. Clone/sync this repository and instantiate the Julia project.",
                "  3. Run the dry-run command above to confirm the config on that machine.",
                "  4. Launch through the canonical front-layer CLI after explicitly acknowledging heavy compute:",
                "     $(lf_cmd)",
                "  5. Copy result artifacts back under the declared output root: $(spec.output_root)",
            ])
        end
    elseif mode == :multimode_phase
        if promotion_status.local_execution_allowed
            append!(lines, [
                "Front-layer command:",
                "  $(local_cmd)",
                "Provider-neutral path:",
                "  This MMF config runs through the same front-layer CLI as other executable experiments.",
                "  Run the same command on any machine with the Julia environment installed.",
                "  Increase Nt, fiber length, power, or max_iter only when you are prepared for the added CPU/memory cost.",
            ])
        else
            append!(lines, [
                "Provider-neutral path:",
                "  1. Use any machine or cluster environment with enough CPU time and memory for the configured grid.",
                "  2. Clone/sync this repository and instantiate the Julia project.",
                "  3. Run the dry-run command above to confirm the config on that machine.",
                "  4. Launch through the canonical front-layer CLI after explicitly acknowledging heavy compute:",
                "     julia -t auto --project=. scripts/canonical/run_experiment.jl --heavy-ok $(spec_hint)",
                "  5. Copy result artifacts back under the declared output root: $(spec.output_root)",
            ])
        end
    elseif mode == :amp_on_phase
        opts = spec.controls.policy_options
        phase_iter = Int(get(opts, :phase_iter, spec.solver.max_iter))
        amp_iter = Int(get(opts, :amp_iter, spec.solver.max_iter))
        delta_bound = Float64(get(opts, :delta_bound, 0.10))
        threshold_db = Float64(get(opts, :threshold_db, 3.0))
        refine_cmd = "julia -t auto --project=. scripts/canonical/refine_amp_on_phase.jl --tag $(spec.output_tag) --L $(spec.problem.L_fiber) --P $(spec.problem.P_cont) --phase-iter $(phase_iter) --amp-iter $(amp_iter) --delta-bound $(delta_bound) --threshold-db $(threshold_db)"
        append!(lines, [
            "Staged multivar command:",
            "  $(refine_cmd)",
            "Provider-neutral path:",
            "  This config selects the staged amp-on-phase policy, not naive joint optimization.",
            "  Run the dedicated refinement workflow on a workstation, burst VM, or cluster node with the Julia environment installed.",
            "  Inspect the generated phase-only and amp-on-phase standard images before treating the result as complete.",
        ])
    else
        append!(lines, [
            "Local command:",
            "  $(local_cmd)",
            "Provider-neutral path:",
            "  This config is allowed to run through the front-layer CLI on any machine with the Julia environment installed.",
            "  For larger parameter choices, run the same command on your own workstation, cluster, or cloud VM.",
        ])
    end

    return lines
end

render_experiment_compute_plan(spec) = join(experiment_compute_plan_lines(spec), "\n")

end # include guard
