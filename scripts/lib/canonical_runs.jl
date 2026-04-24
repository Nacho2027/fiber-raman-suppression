"""
Shared maintained run/sweep configuration helpers for the public lab-facing
workflow surface plus the historical five-run comparison suite.

This is intentionally workflow-shaped script infrastructure rather than package
API. It provides:

- approved single-run config loading from `configs/runs/*.toml`
- approved sweep config loading from `configs/sweeps/*.toml`
- result-directory helpers for the supported surface
- the historical five-run comparison-suite registry used by
  `scripts/workflows/run_comparison.jl`
"""

if !(@isdefined _CANONICAL_RUNS_JL_LOADED)
const _CANONICAL_RUNS_JL_LOADED = true

using Dates
using TOML

const CANONICAL_RUN_CONFIG_DIR = normpath(joinpath(@__DIR__, "..", "..", "configs", "runs"))
const CANONICAL_SWEEP_CONFIG_DIR = normpath(joinpath(@__DIR__, "..", "..", "configs", "sweeps"))
const DEFAULT_CANONICAL_RUN_ID = "smf28_L2m_P0p2W"
const DEFAULT_CANONICAL_SWEEP_ID = "smf28_hnlf_default"

function _approved_config_ids(dir::AbstractString)
    isdir(dir) || return String[]
    ids = String[]
    for entry in readdir(dir)
        endswith(entry, ".toml") || continue
        push!(ids, replace(entry, ".toml" => ""))
    end
    sort!(ids)
    return ids
end

approved_run_config_ids() = _approved_config_ids(CANONICAL_RUN_CONFIG_DIR)
approved_sweep_config_ids() = _approved_config_ids(CANONICAL_SWEEP_CONFIG_DIR)

function _resolve_config_path(spec::AbstractString, dir::AbstractString)
    if isfile(spec)
        return abspath(spec)
    end

    filename = endswith(spec, ".toml") ? spec : string(spec, ".toml")
    candidate = joinpath(dir, filename)
    isfile(candidate) && return candidate

    available = join(_approved_config_ids(dir), ", ")
    throw(ArgumentError(
        "could not resolve config `$spec` under `$dir`; available ids: [$available]"))
end

resolve_run_config_path(spec::AbstractString=DEFAULT_CANONICAL_RUN_ID) =
    _resolve_config_path(spec, CANONICAL_RUN_CONFIG_DIR)

resolve_sweep_config_path(spec::AbstractString=DEFAULT_CANONICAL_SWEEP_ID) =
    _resolve_config_path(spec, CANONICAL_SWEEP_CONFIG_DIR)

function _normalize_run_kwargs(run_table::AbstractDict{<:Any,<:Any})
    preset_name = Symbol(String(run_table["fiber_preset"]))
    preset = get_fiber_preset(preset_name)

    kwargs = (
        L_fiber = Float64(run_table["L_fiber"]),
        P_cont = Float64(run_table["P_cont"]),
        max_iter = Int(get(run_table, "max_iter", 30)),
        validate = Bool(get(run_table, "validate", false)),
        do_plots = Bool(get(run_table, "do_plots", true)),
        Nt = Int(get(run_table, "Nt", 2^13)),
        β_order = Int(get(run_table, "beta_order", length(preset.betas) + 1)),
        time_window = Float64(get(run_table, "time_window", 10.0)),
        gamma_user = Float64(get(run_table, "gamma_user", preset.gamma)),
        betas_user = Float64.(collect(get(run_table, "betas_user", preset.betas))),
        fiber_name = String(get(run_table, "fiber_name", preset.name)),
        λ_gdd = get(run_table, "lambda_gdd", :auto),
        λ_boundary = Float64(get(run_table, "lambda_boundary", 1.0)),
        log_cost = Bool(get(run_table, "log_cost", true)),
        pulse_fwhm = Float64(get(run_table, "pulse_fwhm", 185e-15)),
        pulse_rep_rate = Float64(get(run_table, "pulse_rep_rate", 80.5e6)),
        pulse_shape = String(get(run_table, "pulse_shape", "sech_sq")),
        raman_threshold = Float64(get(run_table, "raman_threshold", -5.0)),
    )

    return kwargs
end

"""
    load_canonical_run_config(spec=DEFAULT_CANONICAL_RUN_ID)

Load an approved single-run config from `configs/runs/` or from an explicit
TOML path.
"""
function load_canonical_run_config(spec::AbstractString=DEFAULT_CANONICAL_RUN_ID)
    path = resolve_run_config_path(spec)
    parsed = TOML.parsefile(path)
    run_table = parsed["run"]

    return (
        id = String(parsed["id"]),
        description = String(get(parsed, "description", parsed["id"])),
        config_path = path,
        output_root = String(get(parsed, "output_root", joinpath("results", "raman"))),
        output_tag = String(get(parsed, "output_tag", parsed["id"])),
        save_prefix_basename = String(get(parsed, "save_prefix_basename", "opt")),
        kwargs = _normalize_run_kwargs(run_table),
    )
end

function _normalize_sweep_fiber_config(fiber_table::AbstractDict{<:Any,<:Any})
    preset_name = Symbol(String(fiber_table["fiber_preset"]))
    preset = get_fiber_preset(preset_name)

    return (
        fiber_preset = preset_name,
        name = String(get(fiber_table, "name", preset.name)),
        slug = String(get(fiber_table, "slug", lowercase(replace(preset.name, "-" => "")))),
        gamma = Float64(get(fiber_table, "gamma_user", preset.gamma)),
        betas = Float64.(collect(get(fiber_table, "betas_user", preset.betas))),
        lengths_m = Float64.(collect(fiber_table["lengths_m"])),
        powers_W = Float64.(collect(fiber_table["powers_W"])),
        max_iter = Int(get(fiber_table, "max_iter", 60)),
        β_order = Int(get(fiber_table, "beta_order", length(preset.betas) + 1)),
    )
end

function _normalize_multistart_config(table::AbstractDict{<:Any,<:Any})
    preset_name = Symbol(String(get(table, "fiber_preset", "SMF28")))
    preset = get_fiber_preset(preset_name)

    return (
        enabled = Bool(get(table, "enabled", false)),
        fiber_preset = preset_name,
        fiber_name = String(get(table, "fiber_name", preset.name)),
        slug = String(get(table, "slug", lowercase(replace(preset.name, "-" => "")))),
        gamma = Float64(get(table, "gamma_user", preset.gamma)),
        betas = Float64.(collect(get(table, "betas_user", preset.betas))),
        L_fiber = Float64(get(table, "L_fiber", 2.0)),
        P_cont = Float64(get(table, "P_cont", 0.20)),
        max_iter = Int(get(table, "max_iter", 60)),
        n_starts = Int(get(table, "n_starts", 10)),
        β_order = Int(get(table, "beta_order", length(preset.betas) + 1)),
    )
end

"""
    load_canonical_sweep_config(spec=DEFAULT_CANONICAL_SWEEP_ID)

Load an approved sweep config from `configs/sweeps/` or from an explicit TOML
path.
"""
function load_canonical_sweep_config(spec::AbstractString=DEFAULT_CANONICAL_SWEEP_ID)
    path = resolve_sweep_config_path(spec)
    parsed = TOML.parsefile(path)

    fibers = [_normalize_sweep_fiber_config(item) for item in parsed["fiber"]]
    multistart = haskey(parsed, "multistart") ?
        _normalize_multistart_config(parsed["multistart"]) :
        (enabled = false,)

    return (
        id = String(parsed["id"]),
        description = String(get(parsed, "description", parsed["id"])),
        config_path = path,
        output_dir = String(get(parsed, "output_dir", joinpath("results", "raman", "sweeps"))),
        images_dir = String(get(parsed, "images_dir", joinpath("results", "images"))),
        Nt_floor = Int(get(parsed, "Nt_floor", 2^13)),
        pulse_fwhm = Float64(get(parsed, "pulse_fwhm", 185e-15)),
        pulse_fwhm_fs = Float64(get(parsed, "pulse_fwhm_fs", 185.0)),
        pulse_rep_rate = Float64(get(parsed, "pulse_rep_rate", 80.5e6)),
        fibers = fibers,
        multistart = multistart,
    )
end

"""
    canonical_run_result_dir(run_spec; timestamp=..., create=true)

Return the timestamped output directory for a supported single canonical run.
"""
function canonical_run_result_dir(run_spec;
                                  timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"),
                                  create::Bool=true)
    dir = joinpath(run_spec.output_root, string(run_spec.output_tag, "_", timestamp))
    create && mkpath(dir)
    return dir
end

"""
    canonical_run_save_prefix(run_spec; timestamp=...)

Return the save-prefix path passed to `run_optimization`.
"""
function canonical_run_save_prefix(run_spec;
                                   timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"),
                                   create::Bool=true)
    dir = canonical_run_result_dir(run_spec; timestamp=timestamp, create=create)
    return joinpath(dir, run_spec.save_prefix_basename)
end

function canonical_run_output_dir(fiber_slug::AbstractString, params_slug::AbstractString;
                                  create::Bool=true)
    dir = joinpath("results", "raman", fiber_slug, params_slug)
    create && mkpath(dir)
    return dir
end

function canonical_sweep_output_dir(sweep_spec; create::Bool=true)
    dir = sweep_spec.output_dir
    create && mkpath(dir)
    return dir
end

function canonical_sweep_images_dir(sweep_spec; create::Bool=true)
    dir = sweep_spec.images_dir
    create && mkpath(dir)
    return dir
end

function canonical_raman_run_specs()
    smf28 = get_fiber_preset(:SMF28)
    hnlf = get_fiber_preset(:HNLF)

    return [
        (
            id = :smf28_L1m_P005W,
            fiber_preset = :SMF28,
            fiber_slug = "smf28",
            params_slug = "L1m_P005W",
            label = "Run 1: SMF-28 baseline (L=1m, P=0.05W)",
            kwargs = (
                L_fiber = 1.0,
                P_cont = 0.05,
                max_iter = 50,
                Nt = 2^13,
                β_order = 3,
                time_window = 10.0,
                gamma_user = smf28.gamma,
                betas_user = smf28.betas,
                fiber_name = smf28.name,
            ),
        ),
        (
            id = :smf28_L2m_P030W,
            fiber_preset = :SMF28,
            fiber_slug = "smf28",
            params_slug = "L2m_P030W",
            label = "Run 2: SMF-28 high power (L=2m, P=0.30W)",
            kwargs = (
                L_fiber = 2.0,
                P_cont = 0.30,
                max_iter = 50,
                validate = false,
                Nt = 2^13,
                β_order = 3,
                time_window = 20.0,
                gamma_user = smf28.gamma,
                betas_user = smf28.betas,
                fiber_name = smf28.name,
            ),
        ),
        (
            id = :hnlf_L1m_P005W,
            fiber_preset = :HNLF,
            fiber_slug = "hnlf",
            params_slug = "L1m_P005W",
            label = "Run 3: HNLF short fiber (L=1m, P=0.05W)",
            kwargs = (
                L_fiber = 1.0,
                P_cont = 0.05,
                max_iter = 80,
                validate = false,
                Nt = 2^14,
                β_order = 3,
                time_window = 15.0,
                gamma_user = hnlf.gamma,
                betas_user = hnlf.betas,
                fiber_name = hnlf.name,
            ),
        ),
        (
            id = :hnlf_L2m_P005W,
            fiber_preset = :HNLF,
            fiber_slug = "hnlf",
            params_slug = "L2m_P005W",
            label = "Run 4: HNLF moderate fiber (L=2m, P=0.05W)",
            kwargs = (
                L_fiber = 2.0,
                P_cont = 0.05,
                max_iter = 100,
                validate = false,
                Nt = 2^14,
                β_order = 3,
                time_window = 30.0,
                gamma_user = hnlf.gamma,
                betas_user = hnlf.betas,
                fiber_name = hnlf.name,
            ),
        ),
        (
            id = :smf28_L5m_P015W,
            fiber_preset = :SMF28,
            fiber_slug = "smf28",
            params_slug = "L5m_P015W",
            label = "Run 5: SMF-28 long fiber (L=5m, P=0.15W, cold start)",
            kwargs = (
                L_fiber = 5.0,
                P_cont = 0.15,
                max_iter = 100,
                validate = false,
                Nt = 2^13,
                β_order = 3,
                time_window = 30.0,
                gamma_user = smf28.gamma,
                betas_user = smf28.betas,
                fiber_name = smf28.name,
            ),
        ),
    ]
end

end # include guard
