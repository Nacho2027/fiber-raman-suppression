"""
Create a complete notebook exploration bundle:

- executable scalar objective extension;
- executable variable/control extension;
- runnable experiment config wired to both.

This command is the real backend behind `Experiment(...).scaffold(...)`.
"""

include(joinpath(@__DIR__, "..", "lib", "objective_registry.jl"))
include(joinpath(@__DIR__, "..", "lib", "variable_registry.jl"))

const EXPLORATION_CONFIG_DIR = normpath(joinpath(@__DIR__, "..", "..", "configs", "experiments"))

function _pg_usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/scaffold_exploration.jl NAME [options]

Options:
    --mode scalar|vector|control
                           Scaffold scalar phase, vector phase, or vector field-control path.
    --objective KIND       Objective id, default: NAME_objective.
    --variable KIND        Variable/control id, default: NAME_control.
    --config-id ID         Config id, default: NAME_experiment.
    --dimension N          Vector/control dimension.
    --initial CSV          Initial optimizer values.
    --lower CSV|VALUE      Lower bounds.
    --upper CSV|VALUE      Upper bounds.
    --max-iter N           Solver iteration cap, default: 3.
    --preset NAME          Fiber preset, default: SMF28.
    --L VALUE              Fiber length in meters, default: 0.05.
    --P VALUE              Continuous power in W, default: 0.001.
    --nt N                 Time/frequency grid size, default: 1024.
    --time-window VALUE    Time window in ps, default: 5.0.
    --objective-dir PATH   Objective extension directory.
    --variable-dir PATH    Variable extension directory.
    --config-dir PATH      Config output directory.
    --force                Overwrite existing generated files.
"""
end

function _pg_safe_name(value)
    cleaned = replace(lowercase(String(value)), "-" => "_")
    cleaned = replace(cleaned, r"[^A-Za-z0-9_]" => "_")
    isempty(cleaned) && error("name cannot be empty")
    return cleaned
end

function _pg_escape(value)
    return replace(String(value), "\\" => "\\\\", "\"" => "\\\"")
end

function _pg_parse_csv(value::AbstractString)
    items = [strip(item) for item in split(value, ",")]
    parsed = [parse(Float64, item) for item in items if !isempty(item)]
    isempty(parsed) && error("CSV vector cannot be empty")
    return parsed
end

function _pg_vector(raw, dim::Int, default::Float64)
    if raw === nothing
        return fill(default, dim)
    end
    values = _pg_parse_csv(String(raw))
    length(values) == 1 && dim > 1 && return fill(first(values), dim)
    length(values) == dim || error("expected $dim values; got $(length(values))")
    return values
end

function _pg_toml_vector(values)
    return "[" * join((repr(Float64(value)) for value in values), ", ") * "]"
end

function _pg_parse_args(args)
    isempty(args) && error(_pg_usage())
    args[1] in ("--help", "-h") && return (help=true,)

    name = _pg_safe_name(args[1])
    parsed = Dict{Symbol,Any}(
        :help => false,
        :name => name,
        :mode => "control",
        :objective => "$(name)_objective",
        :variable => "$(name)_control",
        :config_id => "$(name)_experiment",
        :dimension => nothing,
        :initial_raw => nothing,
        :lower_raw => nothing,
        :upper_raw => nothing,
        :max_iter => 3,
        :preset => "SMF28",
        :L => 0.05,
        :P => 0.001,
        :nt => 1024,
        :time_window => 5.0,
        :objective_dir => OBJECTIVE_EXTENSION_DIR,
        :variable_dir => VARIABLE_EXTENSION_DIR,
        :config_dir => EXPLORATION_CONFIG_DIR,
        :force => false,
    )

    i = 2
    while i <= length(args)
        arg = args[i]
        if arg == "--force"
            parsed[:force] = true
        elseif arg == "--mode"
            i += 1; i <= length(args) || error("--mode requires a value")
            parsed[:mode] = args[i]
        elseif arg == "--objective"
            i += 1; i <= length(args) || error("--objective requires a value")
            parsed[:objective] = _pg_safe_name(args[i])
        elseif arg == "--variable"
            i += 1; i <= length(args) || error("--variable requires a value")
            parsed[:variable] = _pg_safe_name(args[i])
        elseif arg == "--config-id"
            i += 1; i <= length(args) || error("--config-id requires a value")
            parsed[:config_id] = _pg_safe_name(args[i])
        elseif arg == "--dimension"
            i += 1; i <= length(args) || error("--dimension requires a value")
            parsed[:dimension] = parse(Int, args[i])
        elseif arg == "--initial"
            i += 1; i <= length(args) || error("--initial requires a CSV value")
            parsed[:initial_raw] = args[i]
        elseif arg == "--lower"
            i += 1; i <= length(args) || error("--lower requires a CSV value")
            parsed[:lower_raw] = args[i]
        elseif arg == "--upper"
            i += 1; i <= length(args) || error("--upper requires a CSV value")
            parsed[:upper_raw] = args[i]
        elseif arg == "--max-iter"
            i += 1; i <= length(args) || error("--max-iter requires a value")
            parsed[:max_iter] = parse(Int, args[i])
        elseif arg == "--preset"
            i += 1; i <= length(args) || error("--preset requires a value")
            parsed[:preset] = args[i]
        elseif arg == "--L"
            i += 1; i <= length(args) || error("--L requires a value")
            parsed[:L] = parse(Float64, args[i])
        elseif arg == "--P"
            i += 1; i <= length(args) || error("--P requires a value")
            parsed[:P] = parse(Float64, args[i])
        elseif arg == "--nt"
            i += 1; i <= length(args) || error("--nt requires a value")
            parsed[:nt] = parse(Int, args[i])
        elseif arg == "--time-window"
            i += 1; i <= length(args) || error("--time-window requires a value")
            parsed[:time_window] = parse(Float64, args[i])
        elseif arg == "--objective-dir"
            i += 1; i <= length(args) || error("--objective-dir requires a value")
            parsed[:objective_dir] = args[i]
        elseif arg == "--variable-dir"
            i += 1; i <= length(args) || error("--variable-dir requires a value")
            parsed[:variable_dir] = args[i]
        elseif arg == "--config-dir"
            i += 1; i <= length(args) || error("--config-dir requires a value")
            parsed[:config_dir] = args[i]
        elseif arg in ("--help", "-h")
            return (help=true,)
        else
            error("Unknown exploration option: $arg")
        end
        i += 1
    end

    mode = String(parsed[:mode])
    mode in ("scalar", "vector", "control") || error("--mode must be scalar, vector, or control")
    dim = parsed[:dimension] === nothing ?
        (mode == "scalar" ? 1 : mode == "vector" ? 2 : 3) :
        Int(parsed[:dimension])
    dim >= 1 || error("--dimension must be positive")
    mode == "scalar" || dim > 1 || error("--mode=$mode requires dimension > 1")
    parsed[:dimension] = dim
    parsed[:initial] = _pg_vector(parsed[:initial_raw], dim, 0.0)
    parsed[:lower] = _pg_vector(parsed[:lower_raw], dim, -1.0)
    parsed[:upper] = _pg_vector(parsed[:upper_raw], dim, 1.0)
    all(parsed[:lower] .< parsed[:upper]) || error("each lower bound must be less than its upper bound")
    all(lo <= x <= hi for (lo, x, hi) in zip(parsed[:lower], parsed[:initial], parsed[:upper])) ||
        error("initial values must lie inside lower/upper bounds")
    parsed[:max_iter] >= 0 || error("--max-iter must be nonnegative")
    return (; parsed...)
end

function _pg_config_text(p)
    id = _pg_escape(p.config_id)
    objective = _pg_escape(p.objective)
    variable = _pg_escape(p.variable)
    preset = _pg_escape(p.preset)
    scalar = p.mode == "scalar"
    solver_body = scalar ? """
kind = "bounded_scalar"
max_iter = $(p.max_iter)
validate_gradient = false
store_trace = true
scalar_lower = $(first(p.lower))
scalar_upper = $(first(p.upper))
scalar_x_tol = 1.0e-3
""" : """
kind = "nelder_mead"
max_iter = $(p.max_iter)
validate_gradient = false
store_trace = true
vector_initial = $(_pg_toml_vector(p.initial))
vector_lower = $(_pg_toml_vector(p.lower))
vector_upper = $(_pg_toml_vector(p.upper))
vector_x_tol = 1.0e-3
"""
    parameterization = scalar ? "full_grid" : "vector_coefficients"
    return """
id = "$id"
description = "Notebook exploration experiment: $id"
maturity = "experimental"
output_root = "results/raman/smoke"
output_tag = "$id"
save_prefix_basename = "opt"

[problem]
regime = "single_mode"
preset = "$preset"
L_fiber = $(p.L)
P_cont = $(p.P)
beta_order = 3
Nt = $(p.nt)
time_window = $(p.time_window)
grid_policy = "auto_if_undersized"
pulse_fwhm = 1.85e-13
pulse_rep_rate = 8.05e7
pulse_shape = "sech_sq"
raman_threshold = -5.0

[controls]
variables = ["$variable"]
parameterization = "$parameterization"
initialization = "zero"
policy = "direct"

[objective]
kind = "$objective"
log_cost = false

[[objective.regularizer]]
name = "energy"
lambda = 0.0

[solver]
$solver_body
[artifacts]
bundle = "experimental_multivar"
save_payload = true
save_sidecar = true
update_manifest = false
write_trust_report = false
write_standard_images = true
export_phase_handoff = false

[verification]
mode = "standard"
block_on_failed_checks = true
gradient_check = false
taylor_check = false
exact_grid_replay = false
artifact_validation = true

[export]
enabled = false
profile = "neutral_csv_v1"
include_unwrapped_phase = true
include_group_delay = true

[plots.temporal_pulse]
time_range = [-0.75, 0.75]
normalize = true
"""
end

function scaffold_exploration_main(args=ARGS)
    parsed = _pg_parse_args(String.(args))
    if parsed.help
        println(_pg_usage())
        return nothing
    end

    mode = String(parsed.mode)
    objective = scaffold_objective_extension(
        parsed.objective;
        dir=String(parsed.objective_dir),
        description="Executable notebook exploration objective. Replace this template with the scalar metric for the experiment.",
        variables=((parsed.variable,),),
        regularizers=("energy",),
        backend=:scalar_extension,
        maturity="experimental",
        execution=:executable,
        validation="Runtime-checked by exploration doctor; replace template physics and add science validation before promotion.",
        force=parsed.force,
    )

    variable_backend = mode == "scalar" ? :scalar_phase_extension :
        mode == "vector" ? :vector_phase_extension :
        :vector_control_extension
    variable = scaffold_variable_extension(
        parsed.variable;
        dir=String(parsed.variable_dir),
        description="Executable notebook exploration control. Replace this template with the physical control map for the experiment.",
        units="dimensionless optimizer coordinates mapped by the Julia control builder",
        bounds="box bounds declared in the experiment config; projection function must enforce any stricter physical constraints",
        parameterizations=(mode == "scalar" ? "full_grid" : "vector_coefficients",),
        compatible_objectives=(parsed.objective,),
        backend=variable_backend,
        maturity="experimental",
        execution=:executable,
        validation="Runtime-checked by exploration doctor; replace template physics and add science validation before promotion.",
        dimension=mode == "scalar" ? 1 : parsed.dimension,
        force=parsed.force,
    )

    mkpath(String(parsed.config_dir))
    config_path = joinpath(String(parsed.config_dir), "$(parsed.config_id).toml")
    if isfile(config_path) && !parsed.force
        throw(ArgumentError("config already exists: $config_path; pass --force to overwrite"))
    end
    write(config_path, _pg_config_text(parsed))

    println("Exploration bundle created:")
    println("  objective: ", objective.toml_path)
    println("  objective source: ", objective.source_path)
    println("  variable: ", variable.toml_path)
    println("  variable source: ", variable.source_path)
    println("  config: ", abspath(config_path))
    println()
    println("Next checks:")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --exploration-check ", abspath(config_path), " --local-smoke")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --explore-run ", abspath(config_path), " --local-smoke")
    return (
        objective=objective,
        variable=variable,
        config_path=abspath(config_path),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    scaffold_exploration_main(ARGS)
end
