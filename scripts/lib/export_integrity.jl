"""Content-integrity helpers for portable experiment handoff bundles."""

if !(@isdefined _EXPORT_INTEGRITY_JL_LOADED)
const _EXPORT_INTEGRITY_JL_LOADED = true

using JSON3
using SHA

export_file_sha256(path::AbstractString) = bytes2hex(SHA.sha256(read(path)))

function _export_value(container, key::AbstractString, default=nothing)
    if container isa AbstractDict
        haskey(container, key) && return container[key]
        symbol = Symbol(key)
        haskey(container, symbol) && return container[symbol]
        return default
    end
    symbol = Symbol(key)
    return hasproperty(container, symbol) ? getproperty(container, symbol) : default
end

function _export_bundle_path(output_dir::AbstractString, relative_path::AbstractString)
    isabspath(relative_path) && throw(ArgumentError(
        "handoff integrity paths must be relative, got `$relative_path`"))
    root = abspath(output_dir)
    target = normpath(joinpath(root, relative_path))
    relative = relpath(target, root)
    (relative == ".." || startswith(relative, string("..", Base.Filesystem.path_separator))) &&
        throw(ArgumentError("handoff integrity path escapes the bundle: `$relative_path`"))
    return target
end

function export_integrity_entry(output_dir::AbstractString, path::AbstractString)
    target = abspath(path)
    relative = relpath(target, abspath(output_dir))
    _export_bundle_path(output_dir, relative) == target || throw(ArgumentError(
        "handoff integrity file must be inside the bundle: `$path`"))
    return Dict{String,Any}(
        "path" => relative,
        "sha256" => export_file_sha256(target),
    )
end

"""
    validate_export_handoff_integrity(output_dir; source_artifact=nothing)

Recompute every SHA-256 listed in `metadata.json`. Bundle files must use safe
relative paths. When the external source artifact is available, its digest is
checked too; the digest remains useful provenance after the handoff is moved.
"""
function validate_export_handoff_integrity(output_dir::AbstractString;
                                           source_artifact=nothing)
    errors = String[]
    checked = String[]
    metadata_path = joinpath(output_dir, "metadata.json")
    metadata = try
        JSON3.read(read(metadata_path, String))
    catch err
        return (
            complete = false,
            errors = ("metadata_parse:$(sprint(showerror, err))",),
            checked = (),
            source_artifact_checked = false,
        )
    end

    integrity = _export_value(metadata, "integrity")
    if integrity === nothing
        push!(errors, "missing_integrity_manifest")
    else
        required_labels = String["phase_profile"]
        amplitude = _export_value(metadata, "amplitude")
        amplitude !== nothing && Bool(_export_value(amplitude, "present", false)) &&
            push!(required_labels, "amplitude_profile")
        provenance = _export_value(metadata, "provenance")
        provenance !== nothing && append!(required_labels, String.(collect(keys(provenance))))
        for label in unique(required_labels)
            _export_value(integrity, label) === nothing &&
                push!(errors, "$(label):missing_integrity_entry")
        end
        for (raw_label, entry) in pairs(integrity)
            label = String(raw_label)
            relative = _export_value(entry, "path")
            expected = lowercase(String(_export_value(entry, "sha256", "")))
            if relative === nothing
                push!(errors, "$(label):missing_path")
                continue
            end
            if !occursin(r"^[0-9a-f]{64}$", expected)
                push!(errors, "$(label):invalid_sha256")
                continue
            end
            target = try
                _export_bundle_path(output_dir, String(relative))
            catch err
                push!(errors, "$(label):$(sprint(showerror, err))")
                continue
            end
            push!(checked, label)
            if !isfile(target)
                push!(errors, "$(label):missing_file")
            elseif export_file_sha256(target) != expected
                push!(errors, "$(label):sha256_mismatch")
            end
        end
    end

    source_checked = source_artifact !== nothing
    source_expected = lowercase(String(_export_value(metadata, "source_artifact_sha256", "")))
    if !occursin(r"^[0-9a-f]{64}$", source_expected)
        push!(errors, "source_artifact:invalid_sha256")
    elseif source_checked
        source_path = String(source_artifact)
        if !isfile(source_path)
            push!(errors, "source_artifact:missing_file")
        elseif export_file_sha256(source_path) != source_expected
            push!(errors, "source_artifact:sha256_mismatch")
        end
    end

    return (
        complete = isempty(errors),
        errors = Tuple(errors),
        checked = Tuple(sort!(checked)),
        source_artifact_checked = source_checked,
    )
end

end # include guard
