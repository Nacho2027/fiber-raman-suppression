"""
Small registry for front-layer optimization variable contracts.

Configs can select implemented variables, while lab-owned future controls can be
declared as planning-only extension contracts before they are promoted into a
real backend. This keeps the system open-ended without allowing unknown control
semantics to execute silently.
"""

if !(@isdefined _VARIABLE_REGISTRY_JL_LOADED)
const _VARIABLE_REGISTRY_JL_LOADED = true

using TOML

const VARIABLE_EXTENSION_DIR = normpath(joinpath(@__DIR__, "..", "..", "lab_extensions", "variables"))
const VARIABLE_REPO_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

_variable_normalize_symbol(x) = Symbol(replace(lowercase(String(x)), "-" => "_"))
_variable_safe_name(x) = replace(String(_variable_normalize_symbol(x)), r"[^A-Za-z0-9_]" => "_")

const VARIABLE_CONTRACTS = (
    (
        kind = :phase,
        regime = :single_mode,
        backend = :spectral_phase,
        description = "Spectral phase control on the simulation frequency grid.",
        maturity = "supported",
        units = "rad",
        bounds = "unbounded real phase values; plots show wrapped, unwrapped, and group-delay views",
        optimizer_representation = "full-grid real array with shape Nt x M",
        parameterizations = (:full_grid,),
        artifact_hooks = (:phase_profile, :group_delay),
        artifact_semantics = "Phase profile, group delay, standard images, and neutral phase handoff.",
    ),
    (
        kind = :amplitude,
        regime = :single_mode,
        backend = :spectral_amplitude,
        description = "Experimental spectral amplitude shaping control coupled to phase.",
        maturity = "experimental",
        units = "dimensionless transmission",
        bounds = "positive transmission; current multivar path uses a tanh box around unity",
        optimizer_representation = "full-grid real array or tanh search variable with shape Nt x M",
        parameterizations = (:full_grid,),
        artifact_hooks = (:amplitude_mask, :shaped_input_spectrum, :energy_throughput),
        artifact_semantics = "Experimental multivariable payload; no neutral handoff yet.",
    ),
    (
        kind = :energy,
        regime = :single_mode,
        backend = :pulse_energy,
        description = "Experimental pulse-energy control coupled to phase.",
        maturity = "experimental",
        units = "relative pulse energy",
        bounds = "positive scalar energy scale",
        optimizer_representation = "single positive scalar, preconditioned relative to input energy",
        parameterizations = (:full_grid,),
        artifact_hooks = (:energy_scale, :peak_power),
        artifact_semantics = "Experimental multivariable payload; no neutral handoff yet.",
    ),
    (
        kind = :gain_tilt,
        regime = :single_mode,
        backend = :spectral_gain_tilt,
        description = "Experimental one-parameter smooth spectral gain/attenuation tilt coupled to phase.",
        maturity = "experimental",
        units = "dimensionless bounded transmission slope",
        bounds = "bounded gain tilt around unity; current multivar path maps one scalar to A(omega)=1+delta*tanh(x)*normalized_frequency",
        optimizer_representation = "single unconstrained scalar mapped to a smooth bounded spectral transmission ramp",
        parameterizations = (:full_grid,),
        artifact_hooks = (:gain_tilt_profile, :energy_throughput),
        artifact_semantics = "Experimental gain-tilt profile plot and energy-throughput metrics; no neutral hardware handoff yet.",
    ),
    (
        kind = :quadratic_phase,
        regime = :single_mode,
        backend = :spectral_quadratic_phase,
        description = "Experimental one-parameter normalized quadratic spectral phase control for derivative-free exploratory searches.",
        maturity = "experimental",
        units = "rad on normalized quadratic frequency basis",
        bounds = "finite scalar coefficient; current bounded-scalar path maps coefficient to quadratic phi(omega)=q*basis(omega)",
        optimizer_representation = "single bounded scalar mapped to a normalized quadratic spectral phase profile",
        parameterizations = (:full_grid,),
        artifact_hooks = (:phase_profile, :group_delay),
        artifact_semantics = "Standard phase profile and group-delay diagnostics show the induced quadratic phase.",
    ),
    (
        kind = :phase,
        regime = :long_fiber,
        backend = :spectral_phase,
        description = "Spectral phase control for long-fiber planning and burst-only workflows.",
        maturity = "experimental",
        units = "rad",
        bounds = "unbounded real phase values; long-fiber execution remains workflow-specific",
        optimizer_representation = "full-grid real array with shape Nt x M",
        parameterizations = (:full_grid,),
        artifact_hooks = (:phase_profile, :group_delay),
        artifact_semantics = "Standard long-fiber artifacts after dedicated workflow promotion.",
    ),
    (
        kind = :phase,
        regime = :multimode,
        backend = :shared_spectral_phase,
        description = "Shared spectral phase applied across the multimode propagation basis.",
        maturity = "experimental",
        units = "rad",
        bounds = "unbounded real phase values shared across modes",
        optimizer_representation = "shared spectral phase array on the propagation grid",
        parameterizations = (:shared_across_modes,),
        artifact_hooks = (:phase_profile, :group_delay, :mode_resolved_spectra),
        artifact_semantics = "MMF planning artifacts until multimode execution is promoted.",
    ),
)

function registered_variable_contracts(regime::Union{Nothing,Symbol}=nothing)
    contracts = isnothing(regime) ? VARIABLE_CONTRACTS :
        Tuple(contract for contract in VARIABLE_CONTRACTS if contract.regime == regime)
    return contracts
end

function registered_variable_kinds(regime::Symbol)
    return Tuple(unique(contract.kind for contract in registered_variable_contracts(regime)))
end

function variable_contract(kind::Symbol, regime::Symbol)
    matches = Tuple(
        contract for contract in VARIABLE_CONTRACTS
        if contract.kind == kind && contract.regime == regime
    )
    isempty(matches) && throw(ArgumentError(
        "variable `$(kind)` is not registered for regime `$(regime)`; registered variables: $(collect(registered_variable_kinds(regime)))"))
    return only(matches)
end

function experiment_variable_contracts(spec)
    return Tuple(variable_contract(variable, spec.problem.regime) for variable in spec.controls.variables)
end

function _variable_string_array(values)
    return "[" * join(("\"" * replace(String(value), "\"" => "\\\"") * "\"" for value in values), ", ") * "]"
end

function _parse_variable_extension_contract(path::AbstractString)
    parsed = TOML.parsefile(path)
    objectives = haskey(parsed, "compatible_objectives") ?
        Tuple(Symbol(String(item)) for item in parsed["compatible_objectives"]) :
        Symbol[]
    parameterizations = haskey(parsed, "parameterizations") ?
        Tuple(Symbol(String(item)) for item in parsed["parameterizations"]) :
        Symbol[]

    return (
        kind = _variable_normalize_symbol(parsed["kind"]),
        regime = _variable_normalize_symbol(parsed["regime"]),
        backend = _variable_normalize_symbol(get(parsed, "backend", "lab_extension")),
        description = String(get(parsed, "description", parsed["kind"])),
        maturity = lowercase(String(get(parsed, "maturity", "research"))),
        execution = _variable_normalize_symbol(get(parsed, "execution", "planning_only")),
        source = String(get(parsed, "source", "")),
        build_function = String(get(parsed, "build_function", "")),
        projection_function = String(get(parsed, "projection_function", "")),
        units = String(get(parsed, "units", "")),
        bounds = String(get(parsed, "bounds", "")),
        optimizer_representation = String(get(parsed, "optimizer_representation", "")),
        parameterizations = parameterizations,
        artifact_hooks = haskey(parsed, "artifact_hooks") ?
            Tuple(Symbol(String(item)) for item in parsed["artifact_hooks"]) :
            Symbol[],
        compatible_objectives = objectives,
        artifact_semantics = String(get(parsed, "artifact_semantics", "")),
        validation = String(get(parsed, "validation", "")),
        config_path = abspath(path),
    )
end

function registered_variable_extension_contracts(regime::Union{Nothing,Symbol}=nothing)
    isdir(VARIABLE_EXTENSION_DIR) || return ()
    contracts = []
    for entry in readdir(VARIABLE_EXTENSION_DIR; join=true)
        isfile(entry) || continue
        endswith(entry, ".toml") || continue
        contract = _parse_variable_extension_contract(entry)
        if isnothing(regime) || contract.regime == regime
            push!(contracts, contract)
        end
    end
    sort!(contracts; by = contract -> string(contract.kind))
    return Tuple(contracts)
end

function registered_variable_extension_kinds(regime::Symbol)
    return Tuple(contract.kind for contract in registered_variable_extension_contracts(regime))
end

function variable_extension_contract(kind::Symbol, regime::Symbol)
    matches = Tuple(
        contract for contract in registered_variable_extension_contracts(regime)
        if contract.kind == kind
    )
    isempty(matches) && throw(ArgumentError(
        "variable extension `$(kind)` is not registered for regime `$(regime)`; registered extensions: $(collect(registered_variable_extension_kinds(regime)))"))
    return only(matches)
end

function _variable_extension_source_path(contract)
    isempty(contract.source) && return ""
    isabspath(contract.source) ? contract.source : normpath(joinpath(VARIABLE_REPO_ROOT, contract.source))
end

function _variable_source_mentions_function(source_text::AbstractString, function_name::AbstractString)
    isempty(function_name) && return false
    return occursin(Regex("\\b" * Base.escape_string(function_name) * "\\b"), source_text)
end

function validate_variable_extension_contract(contract)
    errors = String[]
    blockers = String[]

    contract.kind == Symbol("") && push!(errors, "missing_kind")
    contract.regime == Symbol("") && push!(errors, "missing_regime")
    isempty(contract.description) && push!(errors, "missing_description")
    isempty(contract.source) && push!(errors, "missing_source")
    isempty(contract.build_function) && push!(errors, "missing_build_function")
    isempty(contract.projection_function) && push!(errors, "missing_projection_function")
    isempty(contract.units) && push!(errors, "missing_units")
    isempty(contract.bounds) && push!(errors, "missing_bounds")
    isempty(contract.parameterizations) && push!(errors, "missing_parameterizations")
    isempty(contract.artifact_semantics) && push!(errors, "missing_artifact_semantics")
    isempty(contract.validation) && push!(errors, "missing_validation")

    source_path = _variable_extension_source_path(contract)
    source_exists = !isempty(source_path) && isfile(source_path)
    source_text = source_exists ? read(source_path, String) : ""
    source_exists || push!(errors, "source_missing")
    source_exists && _variable_source_mentions_function(source_text, contract.build_function) ||
        push!(errors, "build_function_missing_in_source")
    source_exists && _variable_source_mentions_function(source_text, contract.projection_function) ||
        push!(errors, "projection_function_missing_in_source")

    contract.execution == :planning_only && push!(blockers, "execution_planning_only")
    contract.execution == :executable || contract.execution == :planning_only ||
        push!(errors, "unknown_execution")
    contract.backend == :lab_extension && push!(blockers, "backend_not_promoted")
    contract.maturity in ("supported", "experimental") || push!(blockers, "maturity_$(contract.maturity)")
    isempty(contract.validation) || occursin("Requires", contract.validation) &&
        push!(blockers, "validation_requirements_unmet")

    valid = isempty(errors)
    promotable = valid && isempty(blockers)
    return (
        kind = contract.kind,
        regime = contract.regime,
        execution = contract.execution,
        maturity = contract.maturity,
        backend = contract.backend,
        source = source_path,
        source_exists = source_exists,
        build_function = contract.build_function,
        projection_function = contract.projection_function,
        valid = valid,
        promotable = promotable,
        errors = Tuple(errors),
        blockers = Tuple(blockers),
    )
end

function validate_variable_extension_contracts(; regime::Union{Nothing,Symbol}=nothing)
    rows = Tuple(validate_variable_extension_contract(contract)
        for contract in registered_variable_extension_contracts(regime))
    valid = count(row -> row.valid, rows)
    promotable = count(row -> row.promotable, rows)
    return (
        total = length(rows),
        valid = valid,
        invalid = length(rows) - valid,
        promotable = promotable,
        rows = rows,
    )
end

function render_variable_extension_validation_report(report; io::IO=stdout)
    println(io, "# Variable extension validation")
    println(io)
    println(io, "- Total: `", report.total, "`")
    println(io, "- Valid metadata: `", report.valid, "`")
    println(io, "- Invalid metadata: `", report.invalid, "`")
    println(io, "- Promotion-ready: `", report.promotable, "`")
    println(io)
    println(io, "| Variable | Regime | Execution | Maturity | Backend | Valid | Promotable | Errors | Blockers | Source |")
    println(io, "|---|---|---|---|---|---|---|---|---|---|")
    for row in report.rows
        println(io,
            "| ", row.kind,
            " | ", row.regime,
            " | ", row.execution,
            " | ", row.maturity,
            " | ", row.backend,
            " | ", row.valid,
            " | ", row.promotable,
            " | ", join(row.errors, ","),
            " | ", join(row.blockers, ","),
            " | ", row.source,
            " |")
    end
    return nothing
end

function _variable_source_field(path::AbstractString)
    abs_path = abspath(path)
    rel = relpath(abs_path, VARIABLE_REPO_ROOT)
    startswith(rel, "..") ? abs_path : rel
end

function _variable_stub_text(kind_name, build_name, projection_name)
    return """
\"\"\"
Planning-only optimization variable stub for `$kind_name`.

Replace these stubs with control construction, projection/bounds behavior,
units, and artifact semantics before promoting this variable to executable
status.
\"\"\"

function $build_name(args...)
    throw(ArgumentError(
        "$kind_name is a planning-only variable contract; implement and promote this variable before execution"))
end

function $projection_name(args...)
    throw(ArgumentError(
        "$kind_name is a planning-only variable contract; implement projection/bounds behavior before execution"))
end
"""
end

function scaffold_variable_extension(
    kind;
    regime=:single_mode,
    dir::AbstractString=VARIABLE_EXTENSION_DIR,
    description::AbstractString="Research variable contract. Replace with control semantics, units, and bounds.",
    units::AbstractString="document units",
    bounds::AbstractString="document bounds/projection behavior",
    parameterizations=("full_grid",),
    compatible_objectives=("raman_band",),
    force::Bool=false,
)
    kind_name = _variable_safe_name(kind)
    isempty(kind_name) && throw(ArgumentError("variable kind cannot be empty"))
    regime_name = String(_variable_normalize_symbol(regime))
    mkpath(dir)

    toml_path = joinpath(dir, "$(kind_name).toml")
    source_path = joinpath(dir, "$(kind_name).jl")
    if !force && (isfile(toml_path) || isfile(source_path))
        throw(ArgumentError(
            "variable scaffold for `$(kind_name)` already exists under `$(dir)`; pass force=true to overwrite"))
    end

    build_name = "build_$(kind_name)_control"
    projection_name = "project_$(kind_name)_control"
    source_field = _variable_source_field(source_path)
    toml_text = """
kind = "$(kind_name)"
regime = "$(regime_name)"
backend = "lab_extension"
description = "$(replace(String(description), "\"" => "\\\""))"
maturity = "research"
execution = "planning_only"
source = "$(replace(source_field, "\\" => "/"))"
build_function = "$(build_name)"
projection_function = "$(projection_name)"
units = "$(replace(String(units), "\"" => "\\\""))"
bounds = "$(replace(String(bounds), "\"" => "\\\""))"
parameterizations = $(_variable_string_array(parameterizations))
compatible_objectives = $(_variable_string_array(compatible_objectives))
artifact_hooks = ["control_profile", "control_diagnostic"]
artifact_semantics = "Requires output metrics, plots, and handoff semantics before execution."
validation = "Requires units, bounds/projection tests, gradient compatibility, artifact metrics, and a promoted backend before execution."
"""

    write(toml_path, toml_text)
    write(source_path, _variable_stub_text(kind_name, build_name, projection_name))
    return (
        kind = Symbol(kind_name),
        regime = Symbol(regime_name),
        toml_path = abspath(toml_path),
        source_path = abspath(source_path),
        build_function = build_name,
        projection_function = projection_name,
    )
end

function render_variable_registry(; io::IO=stdout, regime::Union{Nothing,Symbol}=nothing)
    contracts = registered_variable_contracts(regime)
    println(io, "Built-in optimization variable contracts:")
    for contract in contracts
        println(io,
            "  - ", contract.kind,
            " [", contract.regime, "]",
            " backend=", contract.backend,
            " maturity=", contract.maturity,
            " units=", contract.units,
            " bounds=", contract.bounds,
            " parameterizations=", join(string.(contract.parameterizations), ", "),
            " artifacts=", join(string.(contract.artifact_hooks), ", "),
            " — ", contract.description)
    end

    extensions = registered_variable_extension_contracts(regime)
    println(io)
    println(io, "Research extension variable contracts:")
    if isempty(extensions)
        println(io, "  (none)")
    else
        for contract in extensions
            println(io,
                "  - ", contract.kind,
                " [", contract.regime, "]",
                " execution=", contract.execution,
                " maturity=", contract.maturity,
                " units=", contract.units,
                " parameterizations=", join(string.(contract.parameterizations), ", "),
                " artifacts=", join(string.(contract.artifact_hooks), ", "),
                " source=", contract.source,
                " — ", contract.description)
        end
    end
    return nothing
end

end # _VARIABLE_REGISTRY_JL_LOADED
