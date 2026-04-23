using Dates
using JLD2
using JSON3

"""
Current output-format schema version for Raman optimization payloads.
"""
const OUTPUT_FORMAT_SCHEMA_VERSION = "1.0"

"""
Threshold above which `phi_opt_rad` is omitted from the JSON sidecar.
"""
const PHI_OPT_INLINE_LIMIT = 8192

const _JLD2_REQUIRED_KEYS = (
    :phi_opt, :uω0, :uωf, :convergence_history, :grid, :fiber, :metadata,
)

const _SIDECAR_REQUIRED_SCALARS = (
    :schema_version, :payload_file, :run_id, :git_sha, :julia_version,
    :timestamp_utc, :fiber_preset, :L_m, :P_W, :lambda0_nm, :pulse_fwhm_fs,
    :Nt, :time_window_ps, :J_final_dB, :J_initial_dB, :n_iter, :converged,
    :seed,
)

"""
    save_run(path, result; schema_version=OUTPUT_FORMAT_SCHEMA_VERSION)

Write a Raman-suppression optimization run to the canonical two-file format.
"""
function save_run(path::AbstractString, result; schema_version::AbstractString=OUTPUT_FORMAT_SCHEMA_VERSION)
    for k in _JLD2_REQUIRED_KEYS
        hasproperty(result, k) || throw(ArgumentError("save_run: result missing required field :$k"))
    end

    jld2_path = String(path)
    mkpath(dirname(jld2_path) == "" ? "." : dirname(jld2_path))
    JLD2.jldopen(jld2_path, "w") do f
        f["phi_opt"]             = collect(result.phi_opt)
        f["uω0"]                 = collect(result.uω0)
        f["uωf"]                 = collect(result.uωf)
        f["convergence_history"] = collect(result.convergence_history)
        f["grid"]                = result.grid
        f["fiber"]               = result.fiber
        f["metadata"]            = result.metadata
    end

    sidecar_path = _sidecar_path_for(jld2_path)
    meta = Dict{Symbol, Any}(Symbol(k) => v for (k, v) in result.metadata)
    meta[:schema_version] = schema_version
    meta[:payload_file]   = basename(jld2_path)

    for k in _SIDECAR_REQUIRED_SCALARS
        haskey(meta, k) || @warn "save_run: sidecar field :$k missing from result.metadata (writing anyway)"
    end

    n = length(result.phi_opt)
    if n < PHI_OPT_INLINE_LIMIT
        meta[:phi_opt_rad] = collect(Float64, result.phi_opt)
    else
        meta[:phi_opt_rad_note] = "omitted: length ≥ $PHI_OPT_INLINE_LIMIT; read from payload_file"
    end

    open(sidecar_path, "w") do io
        JSON3.pretty(io, meta)
    end

    return sidecar_path
end

"""
    load_run(path) -> NamedTuple

Load a run saved by [`save_run`](@ref). The input may be either the JLD2 payload
path or the JSON sidecar path.
"""
function load_run(path::AbstractString)
    jld2_path, sidecar_path = _resolve_pair(String(path))
    sidecar = JSON3.read(read(sidecar_path, String))

    if !haskey(sidecar, :schema_version)
        @warn "load_run: sidecar has no schema_version field (pre-Phase-16 run?)"
    elseif String(sidecar.schema_version) != OUTPUT_FORMAT_SCHEMA_VERSION
        @warn "load_run: schema_version mismatch" found=sidecar.schema_version expected=OUTPUT_FORMAT_SCHEMA_VERSION
    end

    payload = JLD2.jldopen(jld2_path, "r") do f
        (
            phi_opt             = read(f, "phi_opt"),
            uω0                 = read(f, "uω0"),
            uωf                 = read(f, "uωf"),
            convergence_history = read(f, "convergence_history"),
            grid                = read(f, "grid"),
            fiber               = read(f, "fiber"),
            metadata            = read(f, "metadata"),
        )
    end

    return (
        phi_opt             = payload.phi_opt,
        uω0                 = payload.uω0,
        uωf                 = payload.uωf,
        convergence_history = payload.convergence_history,
        grid                = payload.grid,
        fiber               = payload.fiber,
        metadata            = payload.metadata,
        sidecar             = sidecar,
    )
end

function _sidecar_path_for(jld2_path::String)::String
    stem, _ = splitext(jld2_path)
    return string(stem, ".json")
end

function _resolve_pair(path::String)::Tuple{String, String}
    stem, ext = splitext(path)
    if lowercase(ext) == ".json"
        sidecar = path
        sidecar_data = JSON3.read(read(sidecar, String))
        jld2 = if haskey(sidecar_data, :payload_file)
            joinpath(dirname(path), String(sidecar_data.payload_file))
        else
            string(stem, ".jld2")
        end
    else
        jld2    = path
        sidecar = string(stem, ".json")
    end
    isfile(jld2)    || throw(ArgumentError("load_run: JLD2 payload not found: $jld2"))
    isfile(sidecar) || throw(ArgumentError("load_run: JSON sidecar not found: $sidecar"))
    return (jld2, sidecar)
end
