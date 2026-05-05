"""
Create a runnable Nelder-Mead vector playground experiment config.

The generated config is for explicit research-extension variables. It is useful
for notebook demos and smoke tests where the objective is scalar and
derivative-free while adjoint contracts are still being derived.
"""

const DEFAULT_CONFIG_DIR = normpath(joinpath(@__DIR__, "..", "..", "configs", "experiments"))

function _usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/scaffold_vector_config.jl CONFIG_ID [options]

Options:
    --objective KIND      Objective kind, default: temporal_peak_scalar.
    --variable KIND       Vector variable kind, default: poly_phase_vector.
    --initial CSV         Initial vector, default: 0,0.
    --lower CSV           Lower bounds, default: -1,-1.
    --upper CSV           Upper bounds, default: 1,1.
    --max-iter N          Solver iteration cap, default: 3.
    --dir PATH            Output directory, default: configs/experiments.
    --force               Overwrite an existing config.
"""
end

function _toml_escape(value)
    return replace(String(value), "\\" => "\\\\", "\"" => "\\\"")
end

function _parse_float_csv(value::AbstractString)
    items = [strip(item) for item in split(value, ",")]
    values = [parse(Float64, item) for item in items if !isempty(item)]
    isempty(values) && error("CSV vector cannot be empty")
    return values
end

function _toml_float_vector(values)
    return "[" * join((repr(Float64(value)) for value in values), ", ") * "]"
end

function _parse_vector_config_args(args)
    isempty(args) && error(_usage())
    args[1] in ("--help", "-h") && return (help=true,)

    parsed = Dict{Symbol,Any}(
        :help => false,
        :config_id => args[1],
        :objective => "temporal_peak_scalar",
        :variable => "poly_phase_vector",
        :initial => [0.0, 0.0],
        :lower => [-1.0, -1.0],
        :upper => [1.0, 1.0],
        :max_iter => 3,
        :dir => DEFAULT_CONFIG_DIR,
        :force => false,
    )

    i = 2
    while i <= length(args)
        arg = args[i]
        if arg == "--force"
            parsed[:force] = true
        elseif arg == "--objective"
            i += 1; i <= length(args) || error("--objective requires a value")
            parsed[:objective] = args[i]
        elseif arg == "--variable"
            i += 1; i <= length(args) || error("--variable requires a value")
            parsed[:variable] = args[i]
        elseif arg == "--initial"
            i += 1; i <= length(args) || error("--initial requires a CSV value")
            parsed[:initial] = _parse_float_csv(args[i])
        elseif arg == "--lower"
            i += 1; i <= length(args) || error("--lower requires a CSV value")
            parsed[:lower] = _parse_float_csv(args[i])
        elseif arg == "--upper"
            i += 1; i <= length(args) || error("--upper requires a CSV value")
            parsed[:upper] = _parse_float_csv(args[i])
        elseif arg == "--max-iter"
            i += 1; i <= length(args) || error("--max-iter requires a value")
            parsed[:max_iter] = parse(Int, args[i])
        elseif arg == "--dir"
            i += 1; i <= length(args) || error("--dir requires a value")
            parsed[:dir] = args[i]
        elseif arg in ("--help", "-h")
            return (help=true,)
        else
            error("Unknown vector-config option: $arg")
        end
        i += 1
    end

    length(parsed[:initial]) == length(parsed[:lower]) == length(parsed[:upper]) ||
        error("--initial, --lower, and --upper must have matching lengths")
    all(parsed[:lower] .< parsed[:upper]) || error("each lower bound must be less than its upper bound")
    all(lo <= x <= hi for (lo, x, hi) in zip(parsed[:lower], parsed[:initial], parsed[:upper])) ||
        error("--initial must lie inside --lower/--upper")
    parsed[:max_iter] >= 0 || error("--max-iter must be nonnegative")
    return (; parsed...)
end

function _vector_config_text(p)
    id = _toml_escape(p.config_id)
    variable = _toml_escape(p.variable)
    objective = _toml_escape(p.objective)
    return """
id = "$id"
description = "Notebook playground vector experiment: $id"
maturity = "experimental"
output_root = "results/raman/smoke"
output_tag = "$id"
save_prefix_basename = "opt"

[problem]
regime = "single_mode"
preset = "SMF28"
L_fiber = 0.05
P_cont = 0.001
beta_order = 3
Nt = 1024
time_window = 5.0
grid_policy = "auto_if_undersized"
pulse_fwhm = 1.85e-13
pulse_rep_rate = 8.05e7
pulse_shape = "sech_sq"
raman_threshold = -5.0

[controls]
variables = ["$variable"]
parameterization = "vector_coefficients"
initialization = "zero"
policy = "direct"

[objective]
kind = "$objective"
log_cost = false

[[objective.regularizer]]
name = "energy"
lambda = 0.0

[solver]
kind = "nelder_mead"
max_iter = $(p.max_iter)
validate_gradient = false
store_trace = true
vector_initial = $(_toml_float_vector(p.initial))
vector_lower = $(_toml_float_vector(p.lower))
vector_upper = $(_toml_float_vector(p.upper))
vector_x_tol = 1.0e-3

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

function scaffold_vector_config_main(args=ARGS)
    parsed = _parse_vector_config_args(String.(args))
    if parsed.help
        println(_usage())
        return nothing
    end
    mkpath(parsed.dir)
    path = joinpath(parsed.dir, "$(parsed.config_id).toml")
    if isfile(path) && !parsed.force
        throw(ArgumentError("config already exists: $path; pass --force to overwrite"))
    end
    write(path, _vector_config_text(parsed))
    println("Vector playground config created:")
    println("  config: ", abspath(path))
    println()
    println("Next checks:")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --playground-check ", abspath(path), " --local-smoke")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --explore-run ", abspath(path), " --local-smoke")
    return abspath(path)
end

if abspath(PROGRAM_FILE) == @__FILE__
    scaffold_vector_config_main(ARGS)
end
