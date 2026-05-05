"""
Small registry for front-layer objective/cost contracts.

This is intentionally not a plugin system. It is a code-defined allowlist that
lets configs name an objective while keeping the actual physics and adjoint
implementation explicit in Julia.
"""

if !(@isdefined _OBJECTIVE_REGISTRY_JL_LOADED)
const _OBJECTIVE_REGISTRY_JL_LOADED = true

using TOML

const OBJECTIVE_EXTENSION_DIR = normpath(joinpath(@__DIR__, "..", "..", "lab_extensions", "objectives"))
const OBJECTIVE_REPO_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const OBJECTIVE_EXTENSION_DIRS_ENV = "FIBER_OBJECTIVE_EXTENSION_DIRS"

_objective_normalize_symbol(x) = Symbol(replace(lowercase(String(x)), "-" => "_"))
_objective_safe_name(x) = replace(String(_objective_normalize_symbol(x)), r"[^A-Za-z0-9_]" => "_")

const OBJECTIVE_CONTRACTS = (
    (
        kind = :raman_band,
        regime = :single_mode,
        backend = :raman_optimization,
        description = "Integrated Raman-band spectral power with optional regularization.",
        maturity = "supported",
        supported_variables = (
            (:phase,),
            (:reduced_phase,),
            (:gain_tilt,),
            (:phase, :gain_tilt),
            (:phase, :amplitude),
            (:phase, :energy),
            (:phase, :amplitude, :energy),
        ),
        metrics = (:J_before_dB, :J_after_dB, :delta_J_dB, :raman_band_fraction),
        artifact_hooks = (:spectrum_before_after, :raman_band_overlay, :convergence_trace),
        allowed_regularizers = (
            :gdd,
            :boundary,
            :energy,
            :tikhonov,
            :tv,
            :flat,
        ),
    ),
    (
        kind = :raman_peak,
        regime = :single_mode,
        backend = :raman_optimization,
        description = "Maximum single-bin Raman-band fractional leakage with optional phase regularization.",
        maturity = "experimental",
        supported_variables = ((:phase,), (:reduced_phase,)),
        metrics = (:J_before_dB, :J_after_dB, :delta_J_dB, :raman_peak_fraction),
        artifact_hooks = (:spectrum_before_after, :raman_peak_marker, :convergence_trace),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
    (
        kind = :temporal_width,
        regime = :single_mode,
        backend = :raman_optimization,
        description = "Non-Raman temporal second-moment pulse-width objective for phase-only pulse shaping.",
        maturity = "experimental",
        supported_variables = ((:phase,), (:reduced_phase,)),
        metrics = (:J_before_dB, :J_after_dB, :delta_J_dB, :temporal_width_fraction),
        artifact_hooks = (:spectrum_before_after, :convergence_trace),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
    (
        kind = :raman_band,
        regime = :long_fiber,
        backend = :raman_optimization,
        description = "Integrated Raman-band spectral power for long-fiber single-mode planning.",
        maturity = "experimental",
        supported_variables = ((:phase,),),
        metrics = (:J_before_dB, :J_after_dB, :delta_J_dB, :raman_band_fraction),
        artifact_hooks = (:spectrum_before_after, :raman_band_overlay, :longfiber_reach_diagnostic),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
    (
        kind = :mmf_sum,
        regime = :multimode,
        backend = :mmf_raman_optimization,
        description = "Mode-summed multimode Raman leakage for shared spectral-phase planning.",
        maturity = "experimental",
        supported_variables = ((:phase,),),
        metrics = (:J_before_dB, :J_after_dB, :delta_J_dB, :mode_summed_leakage),
        artifact_hooks = (:mode_resolved_spectra, :per_mode_leakage_table, :convergence_trace),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
    (
        kind = :mmf_fundamental,
        regime = :multimode,
        backend = :mmf_raman_optimization,
        description = "Fundamental-mode multimode Raman leakage diagnostic objective.",
        maturity = "experimental",
        supported_variables = ((:phase,),),
        metrics = (:J_before_dB, :J_after_dB, :delta_J_dB, :fundamental_mode_leakage),
        artifact_hooks = (:mode_resolved_spectra, :fundamental_mode_overlay, :convergence_trace),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
    (
        kind = :mmf_worst_mode,
        regime = :multimode,
        backend = :mmf_raman_optimization,
        description = "Worst-mode multimode Raman leakage diagnostic objective.",
        maturity = "experimental",
        supported_variables = ((:phase,),),
        metrics = (:J_before_dB, :J_after_dB, :delta_J_dB, :worst_mode_leakage),
        artifact_hooks = (:mode_resolved_spectra, :worst_mode_table, :convergence_trace),
        allowed_regularizers = (
            :gdd,
            :boundary,
        ),
    ),
)

function registered_objective_contracts(regime::Symbol)
    return Tuple(contract for contract in OBJECTIVE_CONTRACTS if contract.regime == regime)
end

function registered_objective_kinds(regime::Symbol)
    builtins = Symbol[contract.kind for contract in registered_objective_contracts(regime)]
    for contract in registered_objective_extension_contracts(regime)
        row = validate_objective_extension_contract(contract)
        if row.promotable
            push!(builtins, contract.kind)
        end
    end
    return Tuple(unique(builtins))
end

function objective_contract(kind::Symbol, regime::Symbol)
    matches = Tuple(
        contract for contract in OBJECTIVE_CONTRACTS
        if contract.kind == kind && contract.regime == regime
    )
    if isempty(matches)
        extension_matches = Tuple(
            contract for contract in registered_objective_extension_contracts(regime)
            if contract.kind == kind
        )
        if !isempty(extension_matches)
            contract = only(extension_matches)
            row = validate_objective_extension_contract(contract)
            row.promotable && return contract
            blockers = isempty(row.blockers) ? "none" : join(row.blockers, ",")
            errors = isempty(row.errors) ? "none" : join(row.errors, ",")
            throw(ArgumentError(
                "objective `$(kind)` is a research extension for regime `$(regime)`, but it is not promoted for execution; blockers: $(blockers); errors: $(errors)"))
        end
    end
    isempty(matches) && throw(ArgumentError(
        "objective `$(kind)` is not registered for regime `$(regime)`; registered objectives: $(collect(registered_objective_kinds(regime)))"))
    return only(matches)
end

function _parse_variable_tuple(raw)
    return Tuple(Symbol(String(item)) for item in raw)
end

function _parse_extension_contract(path::AbstractString)
    parsed = TOML.parsefile(path)
    variables = haskey(parsed, "supported_variables") ?
        Tuple(_parse_variable_tuple(item) for item in parsed["supported_variables"]) :
        ((:phase,),)
    regularizers = haskey(parsed, "allowed_regularizers") ?
        Tuple(Symbol(String(item)) for item in parsed["allowed_regularizers"]) :
        Symbol[]

    return (
        kind = _objective_normalize_symbol(parsed["kind"]),
        regime = _objective_normalize_symbol(parsed["regime"]),
        backend = _objective_normalize_symbol(get(parsed, "backend", "lab_extension")),
        description = String(get(parsed, "description", parsed["kind"])),
        maturity = lowercase(String(get(parsed, "maturity", "research"))),
        execution = _objective_normalize_symbol(get(parsed, "execution", "planning_only")),
        source = String(get(parsed, "source", "")),
        function_name = String(get(parsed, "function", "")),
        gradient_name = String(get(parsed, "gradient", "")),
        validation = String(get(parsed, "validation", "")),
        supported_variables = variables,
        metrics = haskey(parsed, "metrics") ?
            Tuple(Symbol(String(item)) for item in parsed["metrics"]) :
            Symbol[],
        artifact_hooks = haskey(parsed, "artifact_hooks") ?
            Tuple(Symbol(String(item)) for item in parsed["artifact_hooks"]) :
            Symbol[],
        allowed_regularizers = Tuple(regularizers),
        config_path = abspath(path),
    )
end

function _objective_extension_dirs()
    dirs = String[OBJECTIVE_EXTENSION_DIR]
    raw = get(ENV, OBJECTIVE_EXTENSION_DIRS_ENV, "")
    if !isempty(strip(raw))
        append!(dirs, [normpath(path) for path in split(raw, Sys.iswindows() ? ';' : ':') if !isempty(strip(path))])
    end
    return unique(dirs)
end

function registered_objective_extension_contracts(regime::Union{Nothing,Symbol}=nothing)
    contracts = []
    for dir in _objective_extension_dirs()
        isdir(dir) || continue
        for entry in readdir(dir; join=true)
            isfile(entry) || continue
            endswith(entry, ".toml") || continue
            contract = _parse_extension_contract(entry)
            if isnothing(regime) || contract.regime == regime
                push!(contracts, contract)
            end
        end
    end
    sort!(contracts; by = contract -> string(contract.kind))
    return Tuple(contracts)
end

function registered_objective_extension_kinds(regime::Symbol)
    return Tuple(contract.kind for contract in registered_objective_extension_contracts(regime))
end

function objective_extension_contract(kind::Symbol, regime::Symbol)
    matches = Tuple(
        contract for contract in registered_objective_extension_contracts(regime)
        if contract.kind == kind
    )
    isempty(matches) && throw(ArgumentError(
        "objective extension `$(kind)` is not registered for regime `$(regime)`; registered extensions: $(collect(registered_objective_extension_kinds(regime)))"))
    return only(matches)
end

function _extension_source_path(contract)
    isempty(contract.source) && return ""
    isabspath(contract.source) ? contract.source : normpath(joinpath(@__DIR__, "..", "..", contract.source))
end

function _source_mentions_function(source_text::AbstractString, function_name::AbstractString)
    isempty(function_name) && return false
    return occursin(Regex("\\b" * Base.escape_string(function_name) * "\\b"), source_text)
end

function validate_objective_extension_contract(contract)
    errors = String[]
    blockers = String[]

    contract.kind == Symbol("") && push!(errors, "missing_kind")
    contract.regime == Symbol("") && push!(errors, "missing_regime")
    isempty(contract.description) && push!(errors, "missing_description")
    isempty(contract.source) && push!(errors, "missing_source")
    isempty(contract.function_name) && push!(errors, "missing_function")
    isempty(contract.gradient_name) && push!(errors, "missing_gradient")
    isempty(contract.validation) && push!(errors, "missing_validation")
    isempty(contract.supported_variables) && push!(errors, "missing_supported_variables")

    source_path = _extension_source_path(contract)
    source_exists = !isempty(source_path) && isfile(source_path)
    source_text = source_exists ? read(source_path, String) : ""
    source_exists || push!(errors, "source_missing")
    source_exists && _source_mentions_function(source_text, contract.function_name) ||
        push!(errors, "function_missing_in_source")
    source_exists && _source_mentions_function(source_text, contract.gradient_name) ||
        push!(errors, "gradient_missing_in_source")

    contract.execution == :planning_only && push!(blockers, "execution_planning_only")
    contract.execution == :executable || contract.execution == :planning_only ||
        push!(errors, "unknown_execution")
    contract.backend in (:lab_extension, :scalar_extension) || push!(errors, "unknown_backend")
    contract.backend == :lab_extension && push!(blockers, "backend_not_promoted")
    if contract.backend == :scalar_extension && contract.execution != :executable
        push!(blockers, "scalar_extension_not_executable")
    end
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
        function_name = contract.function_name,
        gradient_name = contract.gradient_name,
        valid = valid,
        promotable = promotable,
        errors = Tuple(errors),
        blockers = Tuple(blockers),
    )
end

function validate_objective_extension_contracts(; regime::Union{Nothing,Symbol}=nothing)
    rows = Tuple(validate_objective_extension_contract(contract)
        for contract in registered_objective_extension_contracts(regime))
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

function render_objective_extension_validation_report(report; io::IO=stdout)
    println(io, "# Objective extension validation")
    println(io)
    println(io, "- Total: `", report.total, "`")
    println(io, "- Valid metadata: `", report.valid, "`")
    println(io, "- Invalid metadata: `", report.invalid, "`")
    println(io, "- Promotion-ready: `", report.promotable, "`")
    println(io)
    println(io, "| Objective | Regime | Execution | Maturity | Backend | Valid | Promotable | Errors | Blockers | Source |")
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

function _objective_source_field(path::AbstractString)
    apath = abspath(path)
    root = abspath(OBJECTIVE_REPO_ROOT)
    prefix = root * Base.Filesystem.path_separator
    return startswith(apath, prefix) ? relpath(apath, root) : apath
end

function _toml_string_array(values)
    return "[" * join(("\"" * replace(String(value), "\"" => "\\\"") * "\"" for value in values), ", ") * "]"
end

function _toml_nested_variables(variables)
    return "[" * join((_toml_string_array(vars) for vars in variables), ", ") * "]"
end

function _objective_stub_text(kind_name::AbstractString, cost_name::AbstractString, gradient_name::AbstractString)
    return """
\"\"\"
Planning-only objective extension stub for `$kind_name`.

Replace these stubs with the objective definition, units/normalization notes,
and derivative strategy before promoting this contract to executable status.
\"\"\"

function $cost_name(args...)
    throw(ArgumentError(
        "$kind_name is a planning-only objective contract; implement and promote this objective before execution"))
end

function $gradient_name(args...)
    throw(ArgumentError(
        "$kind_name is a planning-only objective contract; implement and promote this gradient before execution"))
end
"""
end

function _objective_executable_scalar_text(kind_name::AbstractString, cost_name::AbstractString, gradient_name::AbstractString)
    return """
\"\"\"
Executable scalar objective extension scaffold for `$kind_name`.

This default template minimizes `1 - peak_fraction`, where peak_fraction is the
largest temporal power sample divided by total temporal energy at the fiber
output. Replace this body with your physics metric while keeping the same
`context -> Float64` contract.
\"\"\"

using FFTW

function $cost_name(context)
    ut = ifft(context.uωf, 1)
    power = vec(sum(abs2.(ut), dims = 2))
    total = sum(power)
    total > 0 || throw(ArgumentError("$kind_name requires nonzero output energy"))
    peak_fraction = maximum(power) / total
    return 1.0 - Float64(peak_fraction)
end

function $gradient_name(args...)
    throw(ArgumentError(
        "$kind_name is executable only with derivative-free bounded_scalar search"))
end
"""
end

function scaffold_objective_extension(
    kind;
    regime=:single_mode,
    dir::AbstractString=OBJECTIVE_EXTENSION_DIR,
    description::AbstractString="Research objective contract. Replace with physical quantity, units, and normalization.",
    variables=(("phase",),),
    regularizers=("gdd", "boundary"),
    backend::Symbol=:lab_extension,
    maturity::AbstractString="research",
    execution::Symbol=:planning_only,
    validation::AbstractString="Requires units, gradient check, artifact metrics, and a promoted backend before execution.",
    force::Bool=false,
)
    kind_name = _objective_safe_name(kind)
    isempty(kind_name) && throw(ArgumentError("objective kind cannot be empty"))
    regime_name = String(_objective_normalize_symbol(regime))
    mkpath(dir)

    toml_path = joinpath(dir, "$(kind_name).toml")
    source_path = joinpath(dir, "$(kind_name).jl")
    if !force && (isfile(toml_path) || isfile(source_path))
        throw(ArgumentError(
            "objective scaffold for `$(kind_name)` already exists under `$(dir)`; pass force=true to overwrite"))
    end

    cost_name = "$(kind_name)_cost"
    gradient_name = "$(kind_name)_gradient"
    variable_tuples = Tuple(Tuple(String(item) for item in vars) for vars in variables)
    source_field = _objective_source_field(source_path)
    toml_text = """
kind = "$(kind_name)"
regime = "$(regime_name)"
backend = "$(String(backend))"
description = "$(replace(String(description), "\"" => "\\\""))"
maturity = "$(replace(String(maturity), "\"" => "\\\""))"
execution = "$(String(execution))"
source = "$(replace(source_field, "\\" => "/"))"
function = "$(cost_name)"
gradient = "$(gradient_name)"
validation = "$(replace(String(validation), "\"" => "\\\""))"
supported_variables = $(_toml_nested_variables(variable_tuples))
metrics = ["objective_value"]
artifact_hooks = $(backend == :scalar_extension && execution == :executable ?
    "[\"exploratory_summary\", \"exploratory_overview\"]" :
    "[\"objective_metric\", \"objective_diagnostic\"]")
allowed_regularizers = $(_toml_string_array(regularizers))
"""

    write(toml_path, toml_text)
    source_text = backend == :scalar_extension && execution == :executable ?
        _objective_executable_scalar_text(kind_name, cost_name, gradient_name) :
        _objective_stub_text(kind_name, cost_name, gradient_name)
    write(source_path, source_text)
    return (
        kind = Symbol(kind_name),
        regime = Symbol(regime_name),
        toml_path = abspath(toml_path),
        source_path = abspath(source_path),
        function_name = cost_name,
        gradient_name = gradient_name,
    )
end

function experiment_objective_contract(spec)
    contract = objective_contract(spec.objective.kind, spec.problem.regime)

    variables_supported = spec.controls.variables in contract.supported_variables
    if !variables_supported && contract.backend == :scalar_extension && length(spec.controls.variables) == 1
        if @isdefined(variable_contract)
            variable = variable_contract(only(spec.controls.variables), spec.problem.regime)
            variables_supported =
                get(variable, :backend, nothing) in (:scalar_phase_extension, :vector_phase_extension, :vector_control_extension) &&
                spec.objective.kind in get(variable, :compatible_objectives, ())
        end
    end
    variables_supported || throw(ArgumentError(
        "objective `$(spec.objective.kind)` does not support variables $(spec.controls.variables); supported tuples: $(collect(contract.supported_variables))"))

    for name in keys(spec.objective.regularizers)
        name in contract.allowed_regularizers || throw(ArgumentError(
            "regularizer `$(name)` is not registered for objective `$(spec.objective.kind)`; allowed regularizers: $(collect(contract.allowed_regularizers))"))
    end

    return contract
end

function _objective_tuple_summary(tuples)
    return join((join(string.(vars), "+") for vars in tuples), "; ")
end

function render_objective_registry(; io::IO=stdout, regime::Union{Nothing,Symbol}=nothing)
    contracts = isnothing(regime) ? OBJECTIVE_CONTRACTS : registered_objective_contracts(regime)
    println(io, "Built-in objective contracts:")
    for contract in contracts
        println(io,
            "  ", contract.kind,
            "  regime=", contract.regime,
            "  backend=", contract.backend,
            "  maturity=", contract.maturity)
        println(io, "    variables=", _objective_tuple_summary(contract.supported_variables))
        println(io, "    metrics=", join(string.(contract.metrics), ", "))
        println(io, "    artifacts=", join(string.(contract.artifact_hooks), ", "))
        println(io, "    regularizers=", join(string.(contract.allowed_regularizers), ", "))
        println(io, "    ", contract.description)
    end
    extension_contracts = registered_objective_extension_contracts(regime)
    println(io)
    println(io, "Research extension objective contracts:")
    if isempty(extension_contracts)
        println(io, "  none")
    else
        for contract in extension_contracts
            println(io,
                "  ", contract.kind,
                "  regime=", contract.regime,
                "  backend=", contract.backend,
                "  maturity=", contract.maturity,
                "  execution=", contract.execution)
            println(io, "    variables=", _objective_tuple_summary(contract.supported_variables))
            if !isempty(contract.metrics)
                println(io, "    metrics=", join(string.(contract.metrics), ", "))
            end
            if !isempty(contract.artifact_hooks)
                println(io, "    artifacts=", join(string.(contract.artifact_hooks), ", "))
            end
            println(io, "    regularizers=", join(string.(contract.allowed_regularizers), ", "))
            if !isempty(contract.source)
                println(io, "    source=", contract.source)
            end
            println(io, "    ", contract.description)
        end
    end
    return nothing
end

end # include guard
