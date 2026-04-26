"""
Lightweight read-only index for run artifacts and sweep summaries.

This is intentionally not a database. It scans output roots and renders a
compact table so lab users can find and compare completed runs/campaigns.
"""

if !(@isdefined _RESULTS_INDEX_JL_LOADED)
const _RESULTS_INDEX_JL_LOADED = true

using Printf

include(joinpath(@__DIR__, "run_artifacts.jl"))

function _index_float_cell(value)
    if value isa AbstractFloat
        isfinite(value) || return ""
        format = 0 < abs(value) < 0.01 ? "%.4g" : "%.2f"
        return Printf.format(Printf.Format(format), value)
    end
    return string(value)
end

function _csv_cell(value)
    text = if ismissing(value)
        ""
    elseif value isa AbstractFloat
        isfinite(value) ? string(value) : ""
    else
        string(value)
    end
    needs_quotes = any(ch -> ch in (',', '"', '\n', '\r'), text)
    escaped = replace(text, "\"" => "\"\"")
    return needs_quotes ? "\"$escaped\"" : escaped
end

function _sweep_summary_title(path::AbstractString)
    try
        for line in eachline(path)
            if startswith(line, "# ")
                return strip(replace(line, "# Experiment Sweep Summary:" => ""))
            end
        end
    catch
    end
    return basename(dirname(path))
end

function _safe_run_index_row(path::AbstractString)
    try
        summary = canonical_run_summary(path)
        images = standard_image_set_status(path)
        return (
            kind = :run,
            id = basename(dirname(summary.artifact)),
            fiber = summary.fiber_name,
            L_m = summary.L_m,
            P_cont_W = summary.P_cont_W,
            J_before_dB = summary.J_before_dB,
            J_after_dB = summary.J_after_dB,
            delta_J_dB = summary.delta_J_dB,
            quality = summary.quality,
            converged = summary.converged,
            iterations = summary.iterations,
            standard_images_complete = images.complete,
            path = String(summary.artifact),
            error = "",
        )
    catch err
        return (
            kind = :run,
            id = basename(dirname(path)),
            fiber = "",
            L_m = NaN,
            P_cont_W = NaN,
            J_before_dB = NaN,
            J_after_dB = NaN,
            delta_J_dB = NaN,
            quality = "ERROR",
            converged = missing,
            iterations = missing,
            standard_images_complete = false,
            path = abspath(path),
            error = sprint(showerror, err),
        )
    end
end

function _sweep_index_row(path::AbstractString)
    return (
        kind = :sweep,
        id = _sweep_summary_title(path),
        fiber = "",
        L_m = NaN,
        P_cont_W = NaN,
        J_before_dB = NaN,
        J_after_dB = NaN,
        delta_J_dB = NaN,
        quality = "",
        converged = missing,
        iterations = missing,
        standard_images_complete = missing,
        path = abspath(path),
        error = "",
    )
end

function _walk_files(root::AbstractString)
    isdir(root) || return String[]
    files = String[]
    for (dir, _, names) in walkdir(root)
        for name in names
            push!(files, joinpath(dir, name))
        end
    end
    sort!(files)
    return files
end

function build_results_index(roots::Vector{<:AbstractString}=["results/raman"])
    rows = []
    seen = Set{String}()
    for root in roots
        for path in _walk_files(root)
            if endswith(path, "_result.jld2")
                apath = abspath(path)
                apath in seen && continue
                push!(seen, apath)
                push!(rows, _safe_run_index_row(path))
            elseif basename(path) == "SWEEP_SUMMARY.md"
                apath = abspath(path)
                apath in seen && continue
                push!(seen, apath)
                push!(rows, _sweep_index_row(path))
            end
        end
    end

    sort!(rows; by = row -> (string(row.kind), row.id, row.path))
    return (
        roots = Tuple(String.(roots)),
        total = length(rows),
        rows = Tuple(rows),
    )
end

function _row_contains(row, needle::AbstractString)
    query = lowercase(needle)
    fields = (
        string(row.kind),
        row.id,
        row.fiber,
        row.quality,
        row.path,
        row.error,
    )
    return any(field -> occursin(query, lowercase(String(field))), fields)
end

function filter_results_index(
    index;
    kind::Union{Nothing,Symbol}=nothing,
    fiber::Union{Nothing,AbstractString}=nothing,
    complete_images::Bool=false,
    contains::Union{Nothing,AbstractString}=nothing,
)
    rows = collect(index.rows)
    if !isnothing(kind)
        rows = filter(row -> row.kind == kind, rows)
    end
    if !isnothing(fiber)
        rows = filter(row -> lowercase(row.fiber) == lowercase(String(fiber)), rows)
    end
    if complete_images
        rows = filter(row -> row.standard_images_complete === true, rows)
    end
    if !isnothing(contains) && !isempty(contains)
        rows = filter(row -> _row_contains(row, contains), rows)
    end
    return (
        roots = index.roots,
        total = length(rows),
        rows = Tuple(rows),
    )
end

function render_results_index(index; io::Union{Nothing,IO}=nothing)
    lines = String[
        "# Results Index",
        "",
        "- Roots: `$(join(index.roots, "`, `"))`",
        "- Entries: `$(index.total)`",
        "",
        "| Kind | ID | Fiber | L [m] | P [W] | J_before [dB] | J_after [dB] | ΔJ [dB] | Quality | Converged | Std Images | Path |",
        "|---|---|---|---:|---:|---:|---:|---:|---|---|---|---|",
    ]

    for row in index.rows
        push!(lines, string(
            "| ", row.kind,
            " | ", row.id,
            " | ", row.fiber,
            " | ", _index_float_cell(row.L_m),
            " | ", _index_float_cell(row.P_cont_W),
            " | ", _index_float_cell(row.J_before_dB),
            " | ", _index_float_cell(row.J_after_dB),
            " | ", _index_float_cell(row.delta_J_dB),
            " | ", row.quality,
            " | ", ismissing(row.converged) ? "" : string(row.converged),
            " | ", ismissing(row.standard_images_complete) ? "" : string(row.standard_images_complete),
            " | ", isempty(row.error) ? row.path : row.error,
            " |"))
    end

    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function render_results_index_csv(index; io::Union{Nothing,IO}=nothing)
    columns = (
        :kind,
        :id,
        :fiber,
        :L_m,
        :P_cont_W,
        :J_before_dB,
        :J_after_dB,
        :delta_J_dB,
        :quality,
        :converged,
        :iterations,
        :standard_images_complete,
        :path,
        :error,
    )
    lines = [join(string.(columns), ",")]
    for row in index.rows
        push!(lines, join((_csv_cell(getproperty(row, col)) for col in columns), ","))
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

end # include guard
