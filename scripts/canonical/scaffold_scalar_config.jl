"""
Create a runnable bounded-scalar exploration experiment config.

This is intentionally a file generator, not a physics backend. The generated
config still goes through the normal experiment preflight and runtime doctor.
"""

const DEFAULT_CONFIG_DIR = normpath(joinpath(@__DIR__, "..", "..", "configs", "experiments"))

function _usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/scaffold_scalar_config.jl CONFIG_ID [options]

Options:
    --objective KIND      Objective kind, default: temporal_peak_scalar.
    --variable KIND       Scalar variable kind, default: gain_tilt.
    --preset NAME         Fiber preset, default: SMF28.
    --L VALUE             Fiber length in meters, default: 0.05.
    --P VALUE             Continuous power in W, default: 0.001.
    --nt N                Time/frequency grid size, default: 1024.
    --time-window VALUE   Time window in ps, default: 5.0.
    --lower VALUE         Scalar lower bound, default: -1.0.
    --upper VALUE         Scalar upper bound, default: 1.0.
    --max-iter N          Solver iteration cap, default: 3.
    --dir PATH            Output directory, default: configs/experiments.
    --force               Overwrite an existing config.
"""
end

function _toml_escape(value)
    return replace(String(value), "\\" => "\\\\", "\"" => "\\\"")
end

function _parse_scalar_config_args(args)
    isempty(args) && error(_usage())
    args[1] in ("--help", "-h") && return (help=true,)

    parsed = Dict{Symbol,Any}(
        :help => false,
        :config_id => args[1],
        :objective => "temporal_peak_scalar",
        :variable => "gain_tilt",
        :preset => "SMF28",
        :L => 0.05,
        :P => 0.001,
        :nt => 1024,
        :time_window => 5.0,
        :lower => -1.0,
        :upper => 1.0,
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
        elseif arg == "--lower"
            i += 1; i <= length(args) || error("--lower requires a value")
            parsed[:lower] = parse(Float64, args[i])
        elseif arg == "--upper"
            i += 1; i <= length(args) || error("--upper requires a value")
            parsed[:upper] = parse(Float64, args[i])
        elseif arg == "--max-iter"
            i += 1; i <= length(args) || error("--max-iter requires a value")
            parsed[:max_iter] = parse(Int, args[i])
        elseif arg == "--dir"
            i += 1; i <= length(args) || error("--dir requires a value")
            parsed[:dir] = args[i]
        elseif arg in ("--help", "-h")
            return (help=true,)
        else
            error("Unknown scalar-config option: $arg")
        end
        i += 1
    end

    parsed[:lower] < parsed[:upper] || error("--lower must be less than --upper")
    parsed[:max_iter] >= 0 || error("--max-iter must be nonnegative")
    return (; parsed...)
end

function _scalar_config_text(p)
    id = _toml_escape(p.config_id)
    variable = _toml_escape(p.variable)
    objective = _toml_escape(p.objective)
    preset = _toml_escape(p.preset)
    return """
id = "$id"
description = "Notebook exploration scalar experiment: $id"
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
parameterization = "full_grid"
initialization = "zero"
policy = "direct"

[objective]
kind = "$objective"
log_cost = false

[[objective.regularizer]]
name = "energy"
lambda = 0.0

[solver]
kind = "bounded_scalar"
max_iter = $(p.max_iter)
validate_gradient = false
store_trace = true
scalar_lower = $(p.lower)
scalar_upper = $(p.upper)
scalar_x_tol = 1.0e-3

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

function scaffold_scalar_config_main(args=ARGS)
    parsed = _parse_scalar_config_args(String.(args))
    if parsed.help
        println(_usage())
        return nothing
    end
    mkpath(parsed.dir)
    path = joinpath(parsed.dir, "$(parsed.config_id).toml")
    if isfile(path) && !parsed.force
        throw(ArgumentError("config already exists: $path; pass --force to overwrite"))
    end
    write(path, _scalar_config_text(parsed))
    println("Scalar exploration config created:")
    println("  config: ", abspath(path))
    println()
    println("Next checks:")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --exploration-check ", abspath(path), " --local-smoke")
    println("  julia -t auto --project=. scripts/canonical/run_experiment.jl --explore-run ", abspath(path), " --local-smoke")
    return abspath(path)
end

if abspath(PROGRAM_FILE) == @__FILE__
    scaffold_scalar_config_main(ARGS)
end
