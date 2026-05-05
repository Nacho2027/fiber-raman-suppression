using JSON3
using JLD2

"""
    artifact_paths_for_prefix(prefix; sidecar_suffix="_result.json")

Return the canonical result artifact paths associated with a save prefix.
"""
function artifact_paths_for_prefix(prefix::AbstractString; sidecar_suffix::AbstractString="_result.json")
    prefix_text = String(prefix)
    return (
        prefix = prefix_text,
        jld2 = string(prefix_text, "_result.jld2"),
        json = string(prefix_text, sidecar_suffix),
    )
end

"""
    write_json_file(path, payload)

Write a pretty JSON file, creating the parent directory when needed.
"""
function write_json_file(path::AbstractString, payload)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        JSON3.pretty(io, payload)
    end
    return path
end

"""
    write_jld2_file(path; kwargs...)

Write a JLD2 artifact from keyword payload fields, creating the parent directory
when needed.
"""
function write_jld2_file(path::AbstractString; kwargs...)
    mkpath(dirname(abspath(path)))
    JLD2.jldopen(path, "w") do file
        for (key, value) in pairs(kwargs)
            file[string(key)] = value
        end
    end
    return path
end
