"""
Notebook-facing result wrapper for FiberLab runs.

The current execution layer still returns runner-specific named tuples. This
wrapper gives the public API a stable result shape without copying backend
payloads or duplicating artifact validation logic.
"""

struct FiberLabResult
    experiment_id::String
    output_dir::String
    artifact_path::String
    sidecar_path::Union{Nothing,String}
    run_manifest_path::Union{Nothing,String}
    metrics::NamedTuple
    figures::Dict{Symbol,String}
    verification::NamedTuple
end

function _maybe_string_property(value, name::Symbol)
    hasproperty(value, name) || return nothing
    raw = getproperty(value, name)
    raw === nothing && return nothing
    return String(raw)
end

function _push_metric!(pairs::Vector{Pair{Symbol,Any}}, name::Symbol, value)
    value === nothing && return pairs
    any(first(pair) == name for pair in pairs) || push!(pairs, name => value)
    return pairs
end

function _sidecar_metrics(sidecar_path::Union{Nothing,String})
    pairs = Pair{Symbol,Any}[]
    (sidecar_path === nothing || !isfile(sidecar_path)) && return pairs

    sidecar = try
        JSON3.read(read(sidecar_path, String), Dict{String,Any})
    catch
        return pairs
    end

    _push_metric!(pairs, :J_initial_dB, get(sidecar, "J_initial_dB", nothing))
    _push_metric!(pairs, :J_final_dB, get(sidecar, "J_final_dB", nothing))
    _push_metric!(pairs, :iterations, get(sidecar, "n_iter", get(sidecar, "iterations", nothing)))
    _push_metric!(pairs, :converged, get(sidecar, "converged", nothing))
    _push_metric!(pairs, :Nt, get(sidecar, "Nt", nothing))
    _push_metric!(pairs, :time_window_ps, get(sidecar, "time_window_ps", nothing))

    if haskey(sidecar, "J_initial_dB") && haskey(sidecar, "J_final_dB")
        _push_metric!(pairs, :delta_J_dB,
            Float64(sidecar["J_final_dB"]) - Float64(sidecar["J_initial_dB"]))
    end

    return pairs
end

function _result_metrics(value, sidecar_path::Union{Nothing,String})
    pairs = Pair{Symbol,Any}[]
    for name in (:J_before, :J_after, :J_after_lin, :ΔJ_dB, :delta_J_dB, :wall_time_s)
        hasproperty(value, name) && push!(pairs, name => getproperty(value, name))
    end
    for pair in _sidecar_metrics(sidecar_path)
        _push_metric!(pairs, first(pair), last(pair))
    end
    return (; pairs...)
end

function _result_figures(value)
    figures = Dict{Symbol,String}()
    if hasproperty(value, :artifact_validation)
        report = getproperty(value, :artifact_validation)
        if hasproperty(report, :standard_images)
            for (key, path) in pairs(report.standard_images.paths)
                figures[Symbol(key)] = String(path)
            end
        end
        if hasproperty(report, :extra_artifacts) && hasproperty(report.extra_artifacts, :paths)
            for (hook, paths) in pairs(report.extra_artifacts.paths)
                isempty(paths) || (figures[Symbol(hook)] = String(first(paths)))
            end
        end
    end
    return figures
end

function _result_verification(value)
    artifact_complete = if hasproperty(value, :artifact_validation)
        Bool(value.artifact_validation.complete)
    else
        missing
    end
    export_complete = if hasproperty(value, :export_validation)
        Bool(value.export_validation.complete)
    else
        missing
    end
    return (
        artifact_complete = artifact_complete,
        export_complete = export_complete,
    )
end

"""
    FiberLabResult(run_bundle)

Wrap a current runner return bundle in a stable notebook-facing result object.
"""
function FiberLabResult(run_bundle)
    spec = hasproperty(run_bundle, :spec) ? run_bundle.spec : nothing
    experiment_id = spec === nothing ? "" : String(spec.id)
    artifact_path = _maybe_string_property(run_bundle, :artifact_path)
    artifact_path === nothing && throw(ArgumentError("run bundle has no artifact_path"))
    output_dir = _maybe_string_property(run_bundle, :output_dir)
    output_dir === nothing && (output_dir = dirname(artifact_path))
    sidecar_path = _maybe_string_property(run_bundle, :sidecar_path)

    return FiberLabResult(
        experiment_id,
        output_dir,
        artifact_path,
        sidecar_path,
        _maybe_string_property(run_bundle, :run_manifest_path),
        _result_metrics(run_bundle, sidecar_path),
        _result_figures(run_bundle),
        _result_verification(run_bundle),
    )
end

figure_paths(result::FiberLabResult) = copy(result.figures)
verify(result::FiberLabResult) = result.verification
