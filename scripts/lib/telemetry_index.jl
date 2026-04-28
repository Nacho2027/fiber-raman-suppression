using JSON3
using Statistics

function _telemetry_files(root::AbstractString)
    isfile(root) && basename(root) == "telemetry.json" && return [root]
    isdir(root) || return String[]
    files = String[]
    for (dir, _, names) in walkdir(root)
        "telemetry.json" in names && push!(files, joinpath(dir, "telemetry.json"))
    end
    sort!(files)
    return files
end

function _telemetry_get(payload, name::Symbol, default=nothing)
    return hasproperty(payload, name) ? getproperty(payload, name) : default
end

function _telemetry_string(payload, name::Symbol; default::AbstractString="")
    value = _telemetry_get(payload, name, default)
    value === nothing && return String(default)
    value isa AbstractString && return String(value)
    return string(value)
end

function _telemetry_float(payload, name::Symbol; default::Float64=NaN)
    value = _telemetry_get(payload, name, nothing)
    value === nothing && return default
    value isa Number && return Float64(value)
    parsed = tryparse(Float64, String(value))
    return parsed === nothing ? default : parsed
end

function _telemetry_int(payload, name::Symbol; default::Int=-1)
    value = _telemetry_get(payload, name, nothing)
    value === nothing && return default
    value isa Integer && return Int(value)
    value isa Number && return Int(round(value))
    parsed = tryparse(Int, String(value))
    return parsed === nothing ? default : parsed
end

function _telemetry_gb_from_kb(value)
    !isfinite(value) && return NaN
    value < 0 && return NaN
    return value / 1024^2
end

function _read_telemetry_row(path::AbstractString)
    payload = JSON3.read(read(path, String))
    rss_kb = _telemetry_float(payload, :sampled_peak_rss_kb_sum)
    time_rss_kb = _telemetry_float(payload, :time_max_rss_kb)
    mem_total_kb = _telemetry_float(payload, :mem_total_kb)
    rc = _telemetry_int(payload, :return_code)
    return (
        id = basename(dirname(path)),
        label = _telemetry_string(payload, :label; default=basename(dirname(path))),
        started_at_utc = _telemetry_string(payload, :started_at_utc),
        finished_at_utc = _telemetry_string(payload, :finished_at_utc),
        elapsed_s = _telemetry_float(payload, :elapsed_s),
        return_code = rc,
        ok = rc == 0,
        hostname = _telemetry_string(payload, :hostname),
        cpu_model = _telemetry_string(payload, :cpu_model),
        cpu_threads_online = _telemetry_string(payload, :cpu_threads_online),
        julia_num_threads = _telemetry_string(payload, :julia_num_threads),
        mem_total_gb = _telemetry_gb_from_kb(mem_total_kb),
        sampled_peak_cpu_percent_sum = _telemetry_float(payload, :sampled_peak_cpu_percent_sum),
        sampled_peak_mem_percent_sum = _telemetry_float(payload, :sampled_peak_mem_percent_sum),
        sampled_peak_rss_gb = _telemetry_gb_from_kb(rss_kb),
        time_max_rss_gb = _telemetry_gb_from_kb(time_rss_kb),
        command = _telemetry_string(payload, :command),
        path = path,
        dir = dirname(path),
    )
end

function build_telemetry_index(roots::AbstractVector{<:AbstractString}=["results/telemetry"])
    rows = []
    errors = []
    for root in roots
        for path in _telemetry_files(root)
            try
                push!(rows, _read_telemetry_row(path))
            catch err
                push!(errors, (path = path, error = sprint(showerror, err)))
            end
        end
    end
    sort!(rows; by = row -> (row.started_at_utc, row.label, row.path))
    return (
        roots = collect(String.(roots)),
        rows = rows,
        errors = errors,
        total = length(rows),
        failed_to_parse = length(errors),
    )
end

function filter_telemetry_index(index; contains=nothing, label=nothing,
                                ok=nothing, failed::Bool=false)
    rows = index.rows
    if contains !== nothing
        needle = lowercase(String(contains))
        rows = filter(rows) do row
            occursin(needle, lowercase(row.id)) ||
            occursin(needle, lowercase(row.label)) ||
            occursin(needle, lowercase(row.hostname)) ||
            occursin(needle, lowercase(row.command)) ||
            occursin(needle, lowercase(row.path))
        end
    end
    if label !== nothing
        label_s = String(label)
        rows = filter(row -> row.label == label_s || row.id == label_s, rows)
    end
    if ok !== nothing
        rows = filter(row -> row.ok === ok, rows)
    elseif failed
        rows = filter(row -> !row.ok, rows)
    end
    return (; index..., rows = rows, total = length(rows))
end

function sort_telemetry_index(index; by::Symbol=:started, descending::Bool=false)
    key = if by == :elapsed
        row -> isfinite(row.elapsed_s) ? row.elapsed_s : -Inf
    elseif by == :rss
        row -> isfinite(row.sampled_peak_rss_gb) ? row.sampled_peak_rss_gb : -Inf
    elseif by == :cpu
        row -> isfinite(row.sampled_peak_cpu_percent_sum) ? row.sampled_peak_cpu_percent_sum : -Inf
    elseif by == :label
        row -> row.label
    elseif by == :started
        row -> row.started_at_utc
    else
        throw(ArgumentError("unknown telemetry sort key: $by"))
    end
    rows = sort(collect(index.rows); by=key, rev=descending)
    return (; index..., rows = rows)
end

function top_telemetry_index(index, n)
    n === nothing && return index
    n >= 0 || throw(ArgumentError("top must be nonnegative"))
    rows = collect(index.rows)[1:min(n, length(index.rows))]
    return (; index..., rows = rows, total = length(rows))
end

function telemetry_summary(index)
    elapsed = [row.elapsed_s for row in index.rows if isfinite(row.elapsed_s)]
    rss = [row.sampled_peak_rss_gb for row in index.rows if isfinite(row.sampled_peak_rss_gb)]
    cpu = [row.sampled_peak_cpu_percent_sum for row in index.rows
           if isfinite(row.sampled_peak_cpu_percent_sum)]
    failed = count(row -> !row.ok, index.rows)
    return (
        total = length(index.rows),
        ok = length(index.rows) - failed,
        failed = failed,
        median_elapsed_s = isempty(elapsed) ? NaN : median(elapsed),
        max_elapsed_s = isempty(elapsed) ? NaN : maximum(elapsed),
        max_sampled_rss_gb = isempty(rss) ? NaN : maximum(rss),
        max_sampled_cpu_percent_sum = isempty(cpu) ? NaN : maximum(cpu),
        parse_errors = length(index.errors),
    )
end

_telemetry_fmt_float(x; digits=2) = isfinite(x) ? string(round(x; digits=digits)) : ""

function telemetry_format_duration(seconds)
    isfinite(seconds) || return ""
    total = max(0, round(Int, seconds))
    h = total ÷ 3600
    m = (total % 3600) ÷ 60
    s = total % 60
    h > 0 && return string(h, "h", lpad(m, 2, "0"), "m", lpad(s, 2, "0"), "s")
    m > 0 && return string(m, "m", lpad(s, 2, "0"), "s")
    return string(s, "s")
end

function _telemetry_clip(s::AbstractString, n::Int)
    length(s) <= n && return String(s)
    n <= 3 && return first(s, n)
    return string(first(s, n - 3), "...")
end

function _telemetry_md_escape(s::AbstractString)
    return replace(String(s), "|" => "\\|", "\n" => " ")
end

function render_telemetry_index(index)
    summary = telemetry_summary(index)
    io = IOBuffer()
    println(io, "# Compute Telemetry Index")
    println(io)
    println(io, "- Total: `", summary.total, "`")
    println(io, "- OK: `", summary.ok, "`")
    println(io, "- Failed: `", summary.failed, "`")
    println(io, "- Parse errors: `", summary.parse_errors, "`")
    println(io, "- Median elapsed: `", telemetry_format_duration(summary.median_elapsed_s), "`")
    println(io, "- Max elapsed: `", telemetry_format_duration(summary.max_elapsed_s), "`")
    println(io, "- Max sampled RSS GB: `", _telemetry_fmt_float(summary.max_sampled_rss_gb), "`")
    println(io, "- Max sampled CPU% sum: `", _telemetry_fmt_float(summary.max_sampled_cpu_percent_sum), "`")
    println(io)
    println(io, "| Start UTC | Label | RC | Elapsed | Host | Threads | Peak CPU% | Peak RSS GB | Command |")
    println(io, "|---|---|---:|---:|---|---:|---:|---:|---|")
    for row in index.rows
        threads = isempty(row.julia_num_threads) ? row.cpu_threads_online : row.julia_num_threads
        println(io, "| ",
            _telemetry_md_escape(row.started_at_utc), " | ",
            _telemetry_md_escape(row.label), " | ",
            row.return_code, " | ",
            telemetry_format_duration(row.elapsed_s), " | ",
            _telemetry_md_escape(row.hostname), " | ",
            _telemetry_md_escape(threads), " | ",
            _telemetry_fmt_float(row.sampled_peak_cpu_percent_sum), " | ",
            _telemetry_fmt_float(row.sampled_peak_rss_gb), " | ",
            _telemetry_md_escape(_telemetry_clip(row.command, 96)), " |")
    end
    if !isempty(index.errors)
        println(io)
        println(io, "## Parse Errors")
        for err in index.errors
            println(io, "- `", err.path, "`: ", err.error)
        end
    end
    return String(take!(io))
end

function _telemetry_csv_escape(value)
    s = string(value)
    if occursin(',', s) || occursin('"', s) || occursin('\n', s)
        return string('"', replace(s, "\"" => "\"\""), '"')
    end
    return s
end

function render_telemetry_index_csv(index)
    io = IOBuffer()
    header = [
        "id", "label", "started_at_utc", "finished_at_utc", "elapsed_s",
        "return_code", "ok", "hostname", "cpu_model", "cpu_threads_online",
        "julia_num_threads", "mem_total_gb", "sampled_peak_cpu_percent_sum",
        "sampled_peak_mem_percent_sum", "sampled_peak_rss_gb",
        "time_max_rss_gb", "command", "dir", "path",
    ]
    println(io, join(header, ","))
    for row in index.rows
        values = [
            row.id,
            row.label,
            row.started_at_utc,
            row.finished_at_utc,
            string(row.elapsed_s),
            string(row.return_code),
            string(row.ok),
            row.hostname,
            row.cpu_model,
            row.cpu_threads_online,
            row.julia_num_threads,
            string(row.mem_total_gb),
            string(row.sampled_peak_cpu_percent_sum),
            string(row.sampled_peak_mem_percent_sum),
            string(row.sampled_peak_rss_gb),
            string(row.time_max_rss_gb),
            row.command,
            row.dir,
            row.path,
        ]
        println(io, join(_telemetry_csv_escape.(values), ","))
    end
    return String(take!(io))
end
