"""
Helpers for resolving saved run artifacts and standard image bundles.
"""

if !(@isdefined _RUN_ARTIFACTS_JL_LOADED)
const _RUN_ARTIFACTS_JL_LOADED = true

using MultiModeNoise

const REQUIRED_STANDARD_IMAGE_SUFFIXES = (
    "_phase_profile.png",
    "_evolution.png",
    "_phase_diagnostic.png",
    "_evolution_unshaped.png",
)

function resolve_run_artifact_path(path::AbstractString)
    isfile(path) && return abspath(path)

    if isdir(path)
        entries = sort(readdir(path; join=true))
        jld2_matches = filter(p -> isfile(p) && endswith(p, "_result.jld2"), entries)
        json_matches = filter(p -> isfile(p) && endswith(p, "_result.json"), entries)
        isempty(jld2_matches) && isempty(json_matches) && throw(ArgumentError(
            "no *_result.jld2 or *_result.json artifact found under `$path`"))
        if !isempty(jld2_matches)
            length(jld2_matches) == 1 || throw(ArgumentError(
                "multiple *_result.jld2 artifacts found under `$path`; pass one explicitly"))
            return abspath(first(jld2_matches))
        end
        length(json_matches) == 1 || throw(ArgumentError(
            "multiple *_result.json artifacts found under `$path`; pass one explicitly"))
        return abspath(first(json_matches))
    end

    throw(ArgumentError("run artifact path does not exist: `$path`"))
end

function run_artifact_dir(path::AbstractString)
    return dirname(resolve_run_artifact_path(path))
end

function standard_image_set_status(path::AbstractString)
    dir = run_artifact_dir(path)
    available = Dict{String,String}()
    names = readdir(dir)

    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        match_idx = findfirst(name -> endswith(name, suffix), names)
        if !(match_idx === nothing)
            available[suffix] = joinpath(dir, names[match_idx])
        end
    end

    present = sort!(collect(keys(available)))
    missing = sort!(String[s for s in REQUIRED_STANDARD_IMAGE_SUFFIXES if !haskey(available, s)])
    return (
        dir = dir,
        present = present,
        missing = missing,
        paths = available,
        complete = isempty(missing),
    )
end

function _artifact_loaded_field(loaded, field::Symbol, default)
    return hasproperty(loaded, field) ? getproperty(loaded, field) : default
end

function suppression_quality_label(J_lin; uppercase::Bool=false)
    base = if ismissing(J_lin) || isnan(Float64(J_lin))
        "crashed"
    else
        J_dB = MultiModeNoise.lin_to_dB(Float64(J_lin))
        J_dB < -40 ? "excellent" : J_dB < -30 ? "good" : J_dB < -20 ? "acceptable" : "poor"
    end
    return uppercase ? Base.uppercase(base) : base
end

"""
    canonical_run_summary(path)
    canonical_run_summary(loaded; artifact=nothing)

Normalize one saved canonical run artifact into the small report-facing field
set used by maintained inspection and reporting workflows.
"""
function canonical_run_summary(path::AbstractString)
    artifact = resolve_run_artifact_path(path)
    loaded = MultiModeNoise.load_run(artifact)
    return canonical_run_summary(loaded; artifact=artifact)
end

function canonical_run_summary(loaded; artifact::Union{Nothing,AbstractString}=nothing)
    J_before = Float64(_artifact_loaded_field(loaded, :J_before, NaN))
    J_after = Float64(_artifact_loaded_field(loaded, :J_after, NaN))
    delta_J_dB = if hasproperty(loaded, :delta_J_dB)
        Float64(getproperty(loaded, :delta_J_dB))
    elseif isfinite(J_before) && isfinite(J_after)
        MultiModeNoise.lin_to_dB(J_after) - MultiModeNoise.lin_to_dB(J_before)
    else
        NaN
    end
    artifact_path = isnothing(artifact) ? missing : abspath(String(artifact))

    return (
        artifact = artifact_path,
        artifact_dir = artifact_path === missing ? missing : dirname(artifact_path),
        result_file = artifact_path,
        run_tag = _artifact_loaded_field(loaded, :run_tag, missing),
        fiber_name = String(_artifact_loaded_field(loaded, :fiber_name, "unknown")),
        L_m = Float64(_artifact_loaded_field(loaded, :L_m, NaN)),
        P_cont_W = Float64(_artifact_loaded_field(loaded, :P_cont_W, NaN)),
        Nt = Int(_artifact_loaded_field(loaded, :Nt, 0)),
        time_window_ps = Float64(_artifact_loaded_field(loaded, :time_window_ps, NaN)),
        fwhm_fs = Float64(_artifact_loaded_field(loaded, :fwhm_fs, NaN)),
        gamma = Float64(_artifact_loaded_field(loaded, :gamma, NaN)),
        betas = collect(_artifact_loaded_field(loaded, :betas, Float64[])),
        J_before = J_before,
        J_after = J_after,
        J_before_dB = isfinite(J_before) ? MultiModeNoise.lin_to_dB(J_before) : NaN,
        J_after_dB = isfinite(J_after) ? MultiModeNoise.lin_to_dB(J_after) : NaN,
        delta_J_dB = delta_J_dB,
        grad_norm = Float64(_artifact_loaded_field(loaded, :grad_norm, NaN)),
        converged = _artifact_loaded_field(loaded, :converged, missing),
        iterations = _artifact_loaded_field(loaded, :iterations, missing),
        wall_time_s = Float64(_artifact_loaded_field(loaded, :wall_time_s, NaN)),
        E_conservation = Float64(_artifact_loaded_field(loaded, :E_conservation, NaN)),
        bc_input_frac = Float64(_artifact_loaded_field(loaded, :bc_input_frac, NaN)),
        bc_output_frac = Float64(_artifact_loaded_field(loaded, :bc_output_frac, NaN)),
        quality = suppression_quality_label(J_after; uppercase=true),
        schema_version = hasproperty(loaded, :sidecar) && haskey(loaded.sidecar, :schema_version) ?
            String(loaded.sidecar.schema_version) : "unknown",
    )
end

"""
    sweep_aggregate_points(agg)

Flatten a saved sweep aggregate dictionary into report-facing point rows. The
aggregate schema stores metrics as aligned L x P grids; this adapter is the
single maintained place that interprets those grids for reports.
"""
function sweep_aggregate_points(agg)
    L_vals = agg["L_vals"]
    P_vals = agg["P_vals"]
    J_grid = agg["J_after_grid"]
    conv_grid = agg["converged_grid"]
    drift_grid = agg["drift_pct_grid"]
    N_grid = agg["N_sol_grid"]
    Nt_grid = agg["Nt_grid"]
    tw_grid = agg["time_window_grid"]
    window_limited_grid = haskey(agg, "window_limited_grid") ?
        agg["window_limited_grid"] : fill(false, size(J_grid))

    points = NamedTuple[]
    for (i, L) in enumerate(L_vals), (j, P) in enumerate(P_vals)
        J_lin = J_grid[i, j]
        J_dB = isnan(J_lin) ? NaN : MultiModeNoise.lin_to_dB(J_lin)
        push!(points, (
            L = L,
            P = P,
            J_after = J_lin,
            J_dB = J_dB,
            quality = suppression_quality_label(J_lin; uppercase=true),
            converged = conv_grid[i, j],
            window_limited = window_limited_grid[i, j],
            drift = drift_grid[i, j],
            N_sol = N_grid[i, j],
            Nt = Nt_grid[i, j],
            tw = tw_grid[i, j],
        ))
    end

    return points
end

function sort_sweep_points_by_suppression!(points)
    sort!(points, by=p -> isnan(p.J_dB) ? Inf : p.J_dB)
    return points
end

end # include guard
