"""
Manifest read/update helpers for script workflows.

These keep append-or-replace behavior out of individual drivers while preserving
the existing JSON manifest shape.
"""

if !(@isdefined _MANIFEST_IO_JL_LOADED)
const _MANIFEST_IO_JL_LOADED = true

using JSON3
using Logging

"""
    read_manifest(path) -> Vector{Dict{String,Any}}

Read a JSON manifest containing a vector of dictionaries. Malformed or missing
files return an empty manifest, matching the previous canonical driver behavior.
"""
function read_manifest(path::AbstractString)
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
    upsert_manifest_entry!(manifest, entry; key="result_file") -> manifest

Replace the first manifest entry whose `key` matches `entry[key]`, or append
`entry` if no match exists.
"""
function upsert_manifest_entry!(manifest::Vector{Dict{String,Any}},
                                entry::Dict{String,Any};
                                key::AbstractString = "result_file")
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
    write_manifest(path, manifest) -> path
"""
function write_manifest(path::AbstractString, manifest::Vector{Dict{String,Any}})
    mkpath(dirname(path) == "" ? "." : dirname(path))
    open(path, "w") do io
        JSON3.pretty(io, manifest)
    end
    return path
end

"""
    update_manifest_entry(path, entry; key="result_file") -> Int

Read `path`, upsert `entry`, write the manifest, and return the new row count.
"""
function update_manifest_entry(path::AbstractString,
                               entry::Dict{String,Any};
                               key::AbstractString = "result_file")
    manifest = read_manifest(path)
    upsert_manifest_entry!(manifest, entry; key=key)
    write_manifest(path, manifest)
    return length(manifest)
end

end # include guard
