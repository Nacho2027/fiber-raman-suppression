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

const _LEGACY_JLD2_REQUIRED_KEYS = (
    :phi_opt, :uω0, :uωf, :convergence_history, :grid, :fiber, :metadata,
)

const _SIDECAR_REQUIRED_SCALARS = (
    :schema_version, :payload_file, :run_id, :git_sha, :julia_version,
    :timestamp_utc, :fiber_preset, :L_m, :P_W, :lambda0_nm, :pulse_fwhm_fs,
    :Nt, :time_window_ps, :J_final_dB, :J_initial_dB, :n_iter, :converged,
    :seed,
)

function _result_pairs(result)
    return Pair{Symbol,Any}[name => getproperty(result, name) for name in propertynames(result)]
end

function _result_namedtuple(result)
    pairs = _result_pairs(result)
    return (; pairs...)
end

function _symbolize_dict(dict_like)
    return Dict{Symbol,Any}(Symbol(k) => v for (k, v) in pairs(dict_like))
end

function _legacy_result_shape(result)
    return all(name -> hasproperty(result, name), _LEGACY_JLD2_REQUIRED_KEYS)
end

function _canonical_sidecar_metadata(result, jld2_path::AbstractString;
                                     schema_version::AbstractString=OUTPUT_FORMAT_SCHEMA_VERSION)
    if _legacy_result_shape(result)
        meta = _symbolize_dict(getproperty(result, :metadata))
    else
        payload = _result_namedtuple(result)
        run_id = splitext(basename(String(jld2_path)))[1]
        meta = Dict{Symbol,Any}(
            :run_id => run_id,
            :git_sha => get(payload, :git_sha, "unknown"),
            :julia_version => string(VERSION),
            :timestamp_utc => get(payload, :timestamp_utc,
                Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ")),
            :fiber_preset => get(payload, :fiber_name, "unknown"),
            :L_m => get(payload, :L_m, nothing),
            :P_W => get(payload, :P_cont_W, nothing),
            :lambda0_nm => get(payload, :lambda0_nm, nothing),
            :pulse_fwhm_fs => get(payload, :fwhm_fs, nothing),
            :Nt => get(payload, :Nt, nothing),
            :time_window_ps => get(payload, :time_window_ps, nothing),
            :J_final_dB => haskey(payload, :J_after) ? lin_to_dB(payload.J_after) : nothing,
            :J_initial_dB => haskey(payload, :J_before) ? lin_to_dB(payload.J_before) : nothing,
            :n_iter => get(payload, :iterations, nothing),
            :converged => get(payload, :converged, nothing),
            :seed => get(payload, :seed, 0),
        )
    end

    meta[:schema_version] = schema_version
    meta[:payload_file] = basename(String(jld2_path))

    n = if hasproperty(result, :phi_opt)
        length(getproperty(result, :phi_opt))
    elseif hasproperty(result, :phi_opt_rad)
        length(getproperty(result, :phi_opt_rad))
    else
        0
    end

    if hasproperty(result, :phi_opt)
        if n < PHI_OPT_INLINE_LIMIT
            meta[:phi_opt_rad] = collect(Float64, vec(getproperty(result, :phi_opt)))
        else
            meta[:phi_opt_rad_note] = "omitted: length ≥ $PHI_OPT_INLINE_LIMIT; read from payload_file"
        end
    end

    return meta
end

function _payload_pairs(result, meta::Dict{Symbol,Any})
    pairs = _result_pairs(result)
    if !any(first(pair) == :metadata for pair in pairs)
        push!(pairs, :metadata => Dict{String,Any}(String(k) => v for (k, v) in meta))
    end
    return pairs
end

function _dict_to_namedtuple(dict::AbstractDict{<:Any,<:Any})
    entries = Pair{Symbol,Any}[Symbol(k) => v for (k, v) in Base.pairs(dict)]
    return (; entries...)
end

"""
    read_run_manifest(path) -> Vector{Dict{String,Any}}

Read a JSON manifest containing a vector of dictionaries. Malformed or missing
files return an empty manifest.
"""
function read_run_manifest(path::AbstractString)
    if isfile(path)
        try
            return JSON3.read(read(path, String), Vector{Dict{String,Any}})
        catch e
            @warn "Could not parse manifest, starting fresh" path exception=e
        end
    end
    return Dict{String,Any}[]
end

"""
    upsert_run_manifest_entry!(manifest, entry; key="result_file") -> manifest

Replace the first manifest entry whose `key` matches `entry[key]`, or append
`entry` if no match exists.
"""
function upsert_run_manifest_entry!(manifest::Vector{Dict{String,Any}},
                                   entry::Dict{String,Any};
                                   key::AbstractString="result_file")
    haskey(entry, key) || throw(ArgumentError("manifest entry missing key `$key`"))
    needle = entry[key]
    idx = findfirst(e -> get(e, key, nothing) == needle, manifest)
    if idx === nothing
        push!(manifest, entry)
    else
        manifest[idx] = entry
    end
    return manifest
end

"""
    write_run_manifest(path, manifest) -> path
"""
function write_run_manifest(path::AbstractString, manifest::Vector{Dict{String,Any}})
    mkpath(dirname(path) == "" ? "." : dirname(path))
    open(path, "w") do io
        JSON3.pretty(io, manifest)
    end
    return path
end

"""
    update_run_manifest_entry(path, entry; key="result_file") -> Int

Read `path`, upsert `entry`, write the manifest, and return the new row count.
"""
function update_run_manifest_entry(path::AbstractString,
                                  entry::Dict{String,Any};
                                  key::AbstractString="result_file")
    manifest = read_run_manifest(path)
    upsert_run_manifest_entry!(manifest, entry; key=key)
    write_run_manifest(path, manifest)
    return length(manifest)
end

"""
    load_canonical_runs(manifest_path) -> Vector{Dict{String,Any}}

Load the canonical Raman run manifest and merge each manifest row with the
corresponding JLD2 payload fields. Missing payload files are skipped with a
warning.
"""
function load_canonical_runs(manifest_path::AbstractString)
    manifest = read_run_manifest(manifest_path)
    runs = Dict{String,Any}[]
    for entry in manifest
        jld2_path = get(entry, "result_file", nothing)
        if !(jld2_path isa AbstractString) || !isfile(jld2_path)
            @warn "Missing JLD2 file, skipping manifest entry" path=jld2_path
            continue
        end
        payload = JLD2.load(jld2_path)
        merged = merge(Dict{String,Any}(entry), Dict{String,Any}(payload))
        push!(runs, merged)
    end
    return runs
end

"""
    save_run(path, result; schema_version=OUTPUT_FORMAT_SCHEMA_VERSION)

Write a Raman-suppression optimization run to the canonical two-file format.

For historical compatibility, this accepts both:

- the legacy package payload shape (`phi_opt`, `uω0`, `uωf`, `grid`, `fiber`, `metadata`, ...)
- the current canonical Raman payload shape written by `run_optimization`
"""
function save_run(path::AbstractString, result; schema_version::AbstractString=OUTPUT_FORMAT_SCHEMA_VERSION)
    jld2_path = String(path)
    mkpath(dirname(jld2_path) == "" ? "." : dirname(jld2_path))

    meta = _canonical_sidecar_metadata(result, jld2_path; schema_version=schema_version)
    payload_pairs = _payload_pairs(result, meta)

    JLD2.jldopen(jld2_path, "w") do f
        for (key, value) in payload_pairs
            f[String(key)] = value
        end
    end

    sidecar_path = _sidecar_path_for(jld2_path)
    for k in _SIDECAR_REQUIRED_SCALARS
        haskey(meta, k) || @warn "save_run: sidecar field :$k missing from metadata (writing anyway)"
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

Returns the JLD2 top-level fields plus `sidecar`.
"""
function load_run(path::AbstractString)
    jld2_path, sidecar_path = _resolve_pair(String(path))
    sidecar = JSON3.read(read(sidecar_path, String))

    if !haskey(sidecar, :schema_version)
        @warn "load_run: sidecar has no schema_version field (pre-Phase-16 run?)"
    elseif String(sidecar.schema_version) != OUTPUT_FORMAT_SCHEMA_VERSION
        @warn "load_run: schema_version mismatch" found=sidecar.schema_version expected=OUTPUT_FORMAT_SCHEMA_VERSION
    end

    payload = JLD2.load(jld2_path)
    named = _dict_to_namedtuple(payload)
    pairs = Pair{Symbol,Any}[name => getproperty(named, name) for name in propertynames(named)]
    push!(pairs, :sidecar => sidecar)
    return (; pairs...)
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
        jld2 = path
        sidecar = string(stem, ".json")
    end
    isfile(jld2) || throw(ArgumentError("load_run: JLD2 payload not found: $jld2"))
    isfile(sidecar) || throw(ArgumentError("load_run: JSON sidecar not found: $sidecar"))
    return (jld2, sidecar)
end
