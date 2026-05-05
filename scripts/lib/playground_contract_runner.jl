"""
Generic executable playground contract runner.

This is the freeform escape hatch for notebook/API research. A contract bundle
can define any optimizer variables and any physics, as long as it exposes:

    loss_gradient(x, context) -> (cost, gradient[, diagnostics])

The loss/gradient function may use the existing fiber adjoint machinery,
closed-form math, automatic differentiation, finite differences, or another
backend. This runner intentionally does not force variables into predefined
phase/amplitude choices.
"""

if !(@isdefined _PLAYGROUND_CONTRACT_RUNNER_JL_LOADED)
const _PLAYGROUND_CONTRACT_RUNNER_JL_LOADED = true

ENV["MPLBACKEND"] = get(ENV, "MPLBACKEND", "Agg")

using Dates
using JLD2
using JSON3
using LinearAlgebra
using FiberLab
using Optim
using Printf
using PyPlot
using SHA

function _playground_manifest_path(path::AbstractString)
    candidate = abspath(path)
    if isdir(candidate)
        candidate = joinpath(candidate, "contract.json")
    end
    isfile(candidate) || throw(ArgumentError("playground contract manifest not found: $candidate"))
    return candidate
end

function _playground_read_manifest(path::AbstractString)
    manifest_path = _playground_manifest_path(path)
    manifest = JSON3.read(read(manifest_path, String), Dict{String,Any})
    return manifest_path, manifest
end

function _playground_get(dict, key::AbstractString, default=nothing)
    dict === nothing && return default
    haskey(dict, key) && return dict[key]
    sym = Symbol(key)
    haskey(dict, sym) && return dict[sym]
    return default
end

function _playground_vector(value, label::AbstractString)
    value === nothing && throw(ArgumentError("missing playground contract field `$label`"))
    value isa AbstractVector || throw(ArgumentError("playground contract field `$label` must be a vector"))
    values = Float64.(collect(value))
    isempty(values) && throw(ArgumentError("playground contract field `$label` cannot be empty"))
    all(isfinite, values) || throw(ArgumentError("playground contract field `$label` contains non-finite values"))
    return values
end

function _playground_optional_vector(value, label::AbstractString, n::Int)
    value === nothing && return nothing
    values = _playground_vector(value, label)
    length(values) == n || throw(ArgumentError(
        "playground contract field `$label` length $(length(values)) does not match initial length $n"))
    return values
end

function _playground_parameter_names(value, n::Int)
    value === nothing && return Tuple("x$i" for i in 1:n)
    value isa AbstractVector || throw(ArgumentError("execution.parameter_names must be a vector"))
    names = Tuple(String(name) for name in value)
    length(names) == n || throw(ArgumentError(
        "execution.parameter_names length $(length(names)) does not match initial length $n"))
    any(name -> isempty(strip(name)), names) && throw(ArgumentError(
        "execution.parameter_names cannot contain empty names"))
    length(unique(names)) == length(names) || throw(ArgumentError(
        "execution.parameter_names must be unique"))
    return names
end

function _playground_named_values(names, values)
    return Dict(String(name) => Float64(value) for (name, value) in zip(names, values))
end

function _playground_parameter_metadata(value, names)
    value === nothing && return Dict{String,Any}()
    value isa AbstractDict || throw(ArgumentError("execution.parameter_metadata must be a dictionary"))
    allowed = Set(String.(names))
    metadata = Dict{String,Any}()
    for (key, entry) in value
        name = String(key)
        name in allowed || throw(ArgumentError("execution.parameter_metadata has unknown parameter `$name`"))
        entry isa AbstractDict || throw(ArgumentError("metadata for parameter `$name` must be a dictionary"))
        metadata[name] = Dict(String(k) => v for (k, v) in pairs(entry))
        if haskey(metadata[name], "scale")
            scale = Float64(metadata[name]["scale"])
            scale > 0 || throw(ArgumentError("metadata scale for parameter `$name` must be positive"))
            metadata[name]["scale"] = scale
        end
    end
    return metadata
end

function _playground_parameter_dict(x, context)
    names = if hasproperty(context, :parameter_names)
        getproperty(context, :parameter_names)
    elseif context isa AbstractDict && haskey(context, "parameter_names")
        context["parameter_names"]
    elseif context isa AbstractDict && haskey(context, :parameter_names)
        context[:parameter_names]
    else
        Tuple("x$i" for i in eachindex(x))
    end
    return _playground_named_values(names, x)
end

function _playground_attach_parameter_context(context, names, metadata, lower, upper)
    bounds = Dict(
        String(name) => Dict(
            "lower" => lower === nothing ? nothing : Float64(lower[i]),
            "upper" => upper === nothing ? nothing : Float64(upper[i]),
        )
        for (i, name) in enumerate(names)
    )
    if context isa NamedTuple
        enriched = context
        haskey(enriched, :parameter_names) || (enriched = merge(enriched, (parameter_names = names,)))
        haskey(enriched, :parameter_metadata) || (enriched = merge(enriched, (parameter_metadata = metadata,)))
        haskey(enriched, :parameter_bounds) || (enriched = merge(enriched, (parameter_bounds = bounds,)))
        return enriched
    elseif context isa AbstractDict
        enriched = Dict{Any,Any}(context)
        haskey(enriched, "parameter_names") || (enriched["parameter_names"] = names)
        haskey(enriched, :parameter_names) || (enriched[:parameter_names] = names)
        haskey(enriched, "parameter_metadata") || (enriched["parameter_metadata"] = metadata)
        haskey(enriched, :parameter_metadata) || (enriched[:parameter_metadata] = metadata)
        haskey(enriched, "parameter_bounds") || (enriched["parameter_bounds"] = bounds)
        haskey(enriched, :parameter_bounds) || (enriched[:parameter_bounds] = bounds)
        return enriched
    else
        return (
            user_context = context,
            parameter_names = names,
            parameter_metadata = metadata,
            parameter_bounds = bounds,
        )
    end
end

function _playground_load_module(root::AbstractString, execution)
    mod = Module(gensym(:PlaygroundContract))
    Core.eval(mod, :(using LinearAlgebra))
    Core.eval(mod, :(using Optim))
    Core.eval(mod, :(using JLD2))
    Core.eval(mod, :(using JSON3))
    Core.eval(mod, :(playground_parameter_dict(x, context) = Main._playground_parameter_dict(x, context)))

    for filename in ("problem.jl", "variable.jl", "objective.jl")
        path = joinpath(root, filename)
        isfile(path) && Base.include(mod, path)
    end

    source_path = String(_playground_get(execution, "source_path", "execution.jl"))
    source_abs = isabspath(source_path) ? source_path : joinpath(root, source_path)
    isfile(source_abs) || throw(ArgumentError("playground execution source not found: $source_abs"))
    Base.include(mod, source_abs)
    return mod, source_abs
end

function _playground_required_function(mod::Module, name, label::AbstractString)
    name === nothing && throw(ArgumentError("missing playground function `$label`"))
    symbol = Symbol(String(name))
    isdefined(mod, symbol) || throw(ArgumentError(
        "playground function `$symbol` was not defined by the contract source"))
    fn = Base.invokelatest(() -> getfield(mod, symbol))
    fn isa Function || throw(ArgumentError("playground field `$symbol` is not callable"))
    return fn
end

function _playground_optional_function(mod::Module, name)
    name === nothing && return nothing
    name_str = String(name)
    isempty(strip(name_str)) && return nothing
    symbol = Symbol(name_str)
    isdefined(mod, symbol) || return nothing
    fn = Base.invokelatest(() -> getfield(mod, symbol))
    fn isa Function || throw(ArgumentError("playground field `$symbol` is not callable"))
    return fn
end

function _playground_normalize_eval(result, n::Int; parameter_names=nothing)
    if result isa NamedTuple
        haskey(result, :cost) || throw(ArgumentError("loss_gradient NamedTuple must contain `cost`"))
        haskey(result, :gradient) || throw(ArgumentError("loss_gradient NamedTuple must contain `gradient`"))
        J = Float64(result.cost)
        grad = Float64.(collect(result.gradient))
        diagnostics = haskey(result, :diagnostics) ? result.diagnostics : (;)
    elseif result isa Tuple && length(result) in (2, 3)
        J = Float64(result[1])
        grad = Float64.(collect(result[2]))
        diagnostics = length(result) == 3 ? result[3] : (;)
    else
        throw(ArgumentError(
            "loss_gradient must return `(cost, gradient)`, `(cost, gradient, diagnostics)`, or a NamedTuple"))
    end
    isfinite(J) || throw(ArgumentError("loss_gradient returned non-finite cost $J"))
    if length(grad) != n
        names_msg = parameter_names === nothing ? "" : " for parameters [$(join(parameter_names, ", "))]"
        throw(ArgumentError(
            "loss_gradient returned gradient length $(length(grad)); expected $n$(names_msg)"))
    end
    all(isfinite, grad) || throw(ArgumentError("loss_gradient returned non-finite gradient values"))
    return J, grad, diagnostics
end

function _playground_json_safe(value)
    value === nothing && return nothing
    value isa Missing && return nothing
    value isa Symbol && return String(value)
    value isa AbstractString && return String(value)
    value isa Bool && return value
    value isa Integer && return Int(value)
    value isa AbstractFloat && return isfinite(value) ? Float64(value) : string(value)
    value isa Complex && return Dict("real" => real(value), "imag" => imag(value))
    if value isa NamedTuple
        return Dict(String(k) => _playground_json_safe(v) for (k, v) in pairs(value))
    end
    if value isa AbstractDict
        return Dict(String(k) => _playground_json_safe(v) for (k, v) in pairs(value))
    end
    if value isa AbstractArray
        return _playground_json_safe.(collect(value))
    end
    return string(value)
end

function _playground_slug(value)
    value === nothing && return nothing
    raw = lowercase(String(value))
    chars = Char[]
    last_underscore = false
    for ch in raw
        keep = isletter(ch) || isdigit(ch)
        out = keep ? ch : '_'
        if out == '_'
            last_underscore && continue
            last_underscore = true
        else
            last_underscore = false
        end
        push!(chars, out)
    end
    slug = strip(String(chars), ['_'])
    return isempty(slug) ? nothing : slug
end

function _playground_source_snapshot(source_abs::AbstractString, output_dir::AbstractString)
    snapshot = joinpath(output_dir, "execution_source.jl")
    cp(source_abs, snapshot; force=true)
    digest = bytes2hex(sha256(read(source_abs)))
    return snapshot, digest
end

function _playground_write_parameter_summary(path, names, x0, x_opt, lower, upper, metadata)
    open(path, "w") do io
        println(io, "name,initial,optimum,lower,upper,unit,scale,group,description")
        for (i, name) in enumerate(names)
            entry = get(metadata, String(name), Dict{String,Any}())
            lower_value = lower === nothing ? "" : string(lower[i])
            upper_value = upper === nothing ? "" : string(upper[i])
            unit = get(entry, "unit", "")
            scale = get(entry, "scale", "")
            group = get(entry, "group", "")
            description = get(entry, "description", "")
            fields = (
                String(name),
                string(x0[i]),
                string(x_opt[i]),
                lower_value,
                upper_value,
                string(unit),
                string(scale),
                string(group),
                string(description),
            )
            println(io, join((_playground_csv_escape(field) for field in fields), ","))
        end
    end
    return path
end

function _playground_csv_escape(value)
    text = String(value)
    needs_quotes = occursin(",", text) || occursin("\"", text) || occursin("\n", text)
    escaped = replace(text, "\"" => "\"\"")
    return needs_quotes ? string("\"", escaped, "\"") : escaped
end

function _playground_write_trace_csv(path::AbstractString, trace)
    open(path, "w") do io
        println(io, "evaluation,cost,grad_norm")
        for row in trace
            println(io, row.evaluation, ",", row.cost, ",", row.grad_norm)
        end
    end
    return path
end

function _playground_plot_title(manifest, artifacts, suffix::AbstractString)
    name = String(_playground_get(manifest, "name", "playground_contract"))
    tag = _playground_get(artifacts, "run_tag", nothing)
    tag_text = tag === nothing ? "" : " [$(String(tag))]"
    return string(name, tag_text, "\n", suffix)
end

function _playground_short_number(value)
    value isa Real || return string(value)
    x = Float64(value)
    isfinite(x) || return string(x)
    return string(round(x; sigdigits=4))
end

function _playground_write_trace_plot(path::AbstractString, trace, manifest, artifacts)
    try
        fig, ax = PyPlot.subplots(figsize=(6, 4))
        xs = [row.evaluation for row in trace]
        ys = [row.cost for row in trace]
        ax.plot(xs, ys, marker="o", linewidth=1.5)
        ax.set_xlabel("loss/gradient evaluation")
        ax.set_ylabel("cost")
        final = isempty(ys) ? "n/a" : _playground_short_number(ys[end])
        ax.set_title(_playground_plot_title(manifest, artifacts, "objective trace, final cost = $final"))
        ax.grid(true, alpha=0.25)
        fig.tight_layout()
        fig.savefig(path, dpi=160)
        PyPlot.close(fig)
        return path
    catch err
        open(string(path, ".error.txt"), "w") do io
            showerror(io, err)
        end
        return nothing
    end
end

function _playground_write_gradient_trace_plot(path::AbstractString, trace, manifest, artifacts)
    try
        fig, ax = PyPlot.subplots(figsize=(6, 4))
        xs = [row.evaluation for row in trace]
        ys = [row.grad_norm for row in trace]
        ax.plot(xs, ys, marker="o", linewidth=1.5, color="tab:orange")
        ax.set_xlabel("loss/gradient evaluation")
        ax.set_ylabel("gradient norm")
        if all(y -> y > 0 && isfinite(y), ys)
            ax.set_yscale("log")
        end
        final = isempty(ys) ? "n/a" : _playground_short_number(ys[end])
        ax.set_title(_playground_plot_title(manifest, artifacts, "gradient norm trace, final = $final"))
        ax.grid(true, alpha=0.25)
        fig.tight_layout()
        fig.savefig(path, dpi=160)
        PyPlot.close(fig)
        return path
    catch err
        open(string(path, ".error.txt"), "w") do io
            showerror(io, err)
        end
        return nothing
    end
end

function _playground_write_parameter_plot(path, names, x0, x_opt, metadata, manifest, artifacts)
    try
        n = length(names)
        height = max(4.0, min(14.0, 0.32 * n + 2.2))
        fig, ax = PyPlot.subplots(figsize=(8, height))
        y = collect(1:n)
        labels = _playground_parameter_labels(names, metadata)
        deltas = Float64.(x_opt .- x0)
        ax.hlines(y, x0, x_opt, color="0.72", linewidth=1.5)
        ax.scatter(x0, y, label="initial", color="tab:gray", s=22)
        ax.scatter(x_opt, y, label="optimum", color="tab:blue", s=24)
        for (yi, xi, delta) in zip(y, x_opt, deltas)
            ax.text(xi, yi, string("  Δ=", _playground_short_number(delta)), va="center", fontsize=7)
        end
        ax.set_yticks(y)
        ax.set_yticklabels(labels, fontsize=n > 20 ? 6 : 8)
        ax.invert_yaxis()
        ax.set_xlabel("optimizer coordinate value")
        ax.set_title(_playground_plot_title(manifest, artifacts, "parameter before/after"))
        ax.legend(loc="best", fontsize=8)
        _playground_add_group_separators!(ax, names, metadata)
        ax.grid(true, axis="x", alpha=0.25)
        fig.tight_layout()
        fig.savefig(path, dpi=170)
        PyPlot.close(fig)
        return path
    catch err
        open(string(path, ".error.txt"), "w") do io
            showerror(io, err)
        end
        return nothing
    end
end

function _playground_parameter_labels(names, metadata)
    return [begin
        entry = get(metadata, String(name), Dict{String,Any}())
        unit = get(entry, "unit", "")
        group = get(entry, "group", "")
        unit_text = isempty(String(unit)) ? "" : string(" [", unit, "]")
        group_text = isempty(String(group)) ? "" : string(group, ": ")
        string(group_text, name, unit_text)
    end for name in names]
end

function _playground_parameter_groups(names, metadata)
    return [String(get(get(metadata, String(name), Dict{String,Any}()), "group", "")) for name in names]
end

function _playground_add_group_separators!(ax, names, metadata)
    groups = _playground_parameter_groups(names, metadata)
    length(groups) <= 1 && return nothing
    for i in 2:length(groups)
        if groups[i] != groups[i - 1]
            ax.axhline(i - 0.5, color="0.82", linewidth=0.9, linestyle="--", zorder=0)
        end
    end
    return nothing
end

function _playground_parameter_scale(name, i::Int, x0, x_opt, lower, upper, metadata)
    entry = get(metadata, String(name), Dict{String,Any}())
    if haskey(entry, "scale")
        scale = abs(Float64(entry["scale"]))
        scale > 0 && isfinite(scale) && return scale
    end
    if lower !== nothing && upper !== nothing
        width = abs(Float64(upper[i]) - Float64(lower[i]))
        width > 0 && isfinite(width) && return width
    end
    return max(abs(Float64(x0[i])), abs(Float64(x_opt[i])), 1.0)
end

function _playground_write_parameter_delta_plot(path, names, x0, x_opt, lower, upper, metadata, manifest, artifacts)
    try
        n = length(names)
        height = max(4.0, min(14.0, 0.32 * n + 2.2))
        fig, ax = PyPlot.subplots(figsize=(8, height))
        y = collect(1:n)
        labels = _playground_parameter_labels(names, metadata)
        scaled_deltas = [
            (Float64(x_opt[i]) - Float64(x0[i])) /
            _playground_parameter_scale(name, i, x0, x_opt, lower, upper, metadata)
            for (i, name) in enumerate(names)
        ]
        colors = [delta >= 0 ? "tab:blue" : "tab:red" for delta in scaled_deltas]
        ax.barh(y, scaled_deltas, color=colors, alpha=0.82)
        ax.axvline(0.0, color="0.25", linewidth=0.9)
        for (yi, delta) in zip(y, scaled_deltas)
            ax.text(delta, yi, string("  ", _playground_short_number(delta)), va="center", fontsize=7)
        end
        ax.set_yticks(y)
        ax.set_yticklabels(labels, fontsize=n > 20 ? 6 : 8)
        ax.invert_yaxis()
        ax.set_xlabel("normalized parameter change, Δ / scale")
        ax.set_title(_playground_plot_title(manifest, artifacts, "normalized parameter changes"))
        _playground_add_group_separators!(ax, names, metadata)
        ax.grid(true, axis="x", alpha=0.25)
        fig.tight_layout()
        fig.savefig(path, dpi=170)
        PyPlot.close(fig)
        return path
    catch err
        open(string(path, ".error.txt"), "w") do io
            showerror(io, err)
        end
        return nothing
    end
end

function _playground_numeric_diagnostics(value; prefix="")
    rows = Pair{String,Float64}[]
    value === nothing && return rows
    value isa Missing && return rows
    if value isa NamedTuple
        for (k, v) in pairs(value)
            append!(rows, _playground_numeric_diagnostics(v; prefix=isempty(prefix) ? String(k) : string(prefix, ".", k)))
        end
    elseif value isa AbstractDict
        for (k, v) in pairs(value)
            append!(rows, _playground_numeric_diagnostics(v; prefix=isempty(prefix) ? String(k) : string(prefix, ".", k)))
        end
    elseif value isa Real && isfinite(Float64(value)) && !isempty(prefix)
        push!(rows, prefix => Float64(value))
    end
    return rows
end

function _playground_write_diagnostics_plot(path, diagnostics, manifest, artifacts)
    rows = _playground_numeric_diagnostics(diagnostics)
    isempty(rows) && return nothing
    try
        labels = first.(rows)
        values = last.(rows)
        n = length(rows)
        height = max(3.5, min(12.0, 0.32 * n + 2.0))
        fig, ax = PyPlot.subplots(figsize=(8, height))
        y = collect(1:n)
        ax.barh(y, values, color="tab:green", alpha=0.82)
        for (yi, value) in zip(y, values)
            ax.text(value, yi, string("  ", _playground_short_number(value)), va="center", fontsize=8)
        end
        ax.set_yticks(y)
        ax.set_yticklabels(labels, fontsize=n > 20 ? 6 : 8)
        ax.invert_yaxis()
        ax.set_xlabel("diagnostic value")
        ax.set_title(_playground_plot_title(manifest, artifacts, "final numeric diagnostics"))
        ax.grid(true, axis="x", alpha=0.25)
        fig.tight_layout()
        fig.savefig(path, dpi=170)
        PyPlot.close(fig)
        return path
    catch err
        open(string(path, ".error.txt"), "w") do io
            showerror(io, err)
        end
        return nothing
    end
end

function _playground_diagnostics_dict(diagnostics)
    return Dict(String(k) => Float64(v) for (k, v) in _playground_numeric_diagnostics(diagnostics))
end

function _playground_diagnostic_names(trace)
    names = String[]
    seen = Set{String}()
    for row in trace
        for name in keys(_playground_diagnostics_dict(row.diagnostics))
            if !(name in seen)
                push!(names, name)
                push!(seen, name)
            end
        end
    end
    return names
end

function _playground_write_diagnostics_trace_csv(path, trace)
    names = _playground_diagnostic_names(trace)
    isempty(names) && return nothing
    open(path, "w") do io
        println(io, join(["evaluation"; names], ","))
        for row in trace
            values = _playground_diagnostics_dict(row.diagnostics)
            fields = [string(row.evaluation)]
            append!(fields, [haskey(values, name) ? string(values[name]) : "" for name in names])
            println(io, join((_playground_csv_escape(field) for field in fields), ","))
        end
    end
    return path
end

function _playground_write_diagnostics_delta_csv(path, diagnostics_initial, diagnostics_final)
    initial = _playground_diagnostics_dict(diagnostics_initial)
    final = _playground_diagnostics_dict(diagnostics_final)
    names = sort!(collect(union(Set(keys(initial)), Set(keys(final)))))
    isempty(names) && return nothing
    open(path, "w") do io
        println(io, "diagnostic,initial,final,delta,status")
        for name in names
            has_initial = haskey(initial, name)
            has_final = haskey(final, name)
            initial_value = has_initial ? initial[name] : NaN
            final_value = has_final ? final[name] : NaN
            delta = (has_initial && has_final) ? final_value - initial_value : NaN
            status = if !(has_initial && has_final)
                "missing"
            elseif abs(delta) <= max(1e-12, 1e-9 * max(abs(initial_value), abs(final_value), 1.0))
                "unchanged"
            elseif delta < 0
                "decreased"
            else
                "increased"
            end
            fields = (
                name,
                has_initial ? string(initial_value) : "",
                has_final ? string(final_value) : "",
                isfinite(delta) ? string(delta) : "",
                status,
            )
            println(io, join((_playground_csv_escape(field) for field in fields), ","))
        end
    end
    return path
end

function _playground_top_diagnostic_names(trace, max_count::Int=12)
    names = _playground_diagnostic_names(trace)
    length(names) <= max_count && return names
    first_values = Dict{String,Float64}()
    last_values = Dict{String,Float64}()
    for row in trace
        values = _playground_diagnostics_dict(row.diagnostics)
        for (name, value) in values
            haskey(first_values, name) || (first_values[name] = value)
            last_values[name] = value
        end
    end
    scored = [
        (name = name, score = abs(get(last_values, name, 0.0) - get(first_values, name, 0.0)))
        for name in names
    ]
    sort!(scored; by=row -> row.score, rev=true)
    return [row.name for row in scored[1:max_count]]
end

function _playground_write_diagnostics_trace_plot(path, trace, manifest, artifacts)
    names = _playground_top_diagnostic_names(trace)
    isempty(names) && return nothing
    try
        fig, ax = PyPlot.subplots(figsize=(8, 5))
        xs = [row.evaluation for row in trace]
        for name in names
            ys = [get(_playground_diagnostics_dict(row.diagnostics), name, NaN) for row in trace]
            ax.plot(xs, ys, marker="o", linewidth=1.3, label=name)
        end
        ax.set_xlabel("loss/gradient evaluation")
        ax.set_ylabel("diagnostic value")
        suffix = length(_playground_diagnostic_names(trace)) > length(names) ?
            "diagnostic traces, top changed terms" :
            "diagnostic traces"
        ax.set_title(_playground_plot_title(manifest, artifacts, suffix))
        ax.legend(loc="best", fontsize=7)
        ax.grid(true, alpha=0.25)
        fig.tight_layout()
        fig.savefig(path, dpi=170)
        PyPlot.close(fig)
        return path
    catch err
        open(string(path, ".error.txt"), "w") do io
            showerror(io, err)
        end
        return nothing
    end
end

function _playground_write_diagnostics_delta_plot(path, diagnostics_initial, diagnostics_final, manifest, artifacts)
    initial = _playground_diagnostics_dict(diagnostics_initial)
    final = _playground_diagnostics_dict(diagnostics_final)
    names = sort!(collect(intersect(Set(keys(initial)), Set(keys(final)))))
    isempty(names) && return nothing
    deltas = [final[name] - initial[name] for name in names]
    if length(names) > 16
        order = sortperm(abs.(deltas); rev=true)[1:16]
        names = names[order]
        deltas = deltas[order]
    end
    try
        n = length(names)
        height = max(4.0, min(12.0, 0.32 * n + 2.0))
        fig, ax = PyPlot.subplots(figsize=(8, height))
        y = collect(1:n)
        colors = [delta <= 0 ? "tab:blue" : "tab:red" for delta in deltas]
        ax.barh(y, deltas, color=colors, alpha=0.82)
        ax.axvline(0.0, color="0.25", linewidth=0.9)
        for (yi, delta) in zip(y, deltas)
            ax.text(delta, yi, string("  Δ=", _playground_short_number(delta)), va="center", fontsize=7)
        end
        ax.set_yticks(y)
        ax.set_yticklabels(names, fontsize=n > 20 ? 6 : 8)
        ax.invert_yaxis()
        ax.set_xlabel("final - initial diagnostic value")
        ax.set_title(_playground_plot_title(manifest, artifacts, "diagnostic initial/final deltas"))
        ax.grid(true, axis="x", alpha=0.25)
        fig.tight_layout()
        fig.savefig(path, dpi=170)
        PyPlot.close(fig)
        return path
    catch err
        open(string(path, ".error.txt"), "w") do io
            showerror(io, err)
        end
        return nothing
    end
end

function _playground_artifact_error_path(output_dir::AbstractString, message::AbstractString)
    path = joinpath(output_dir, "artifact_error.txt")
    open(path, "w") do io
        println(io, "playground_artifacts failed after optimization completed.")
        println(io)
        println(io, message)
        println(io)
        println(io, "Fix playground_artifacts(...) or disable it, then rerun if you need the custom artifact.")
        println(io, "The optimizer result, manifest, trace, source snapshot, and parameter summary were still saved.")
    end
    return path
end

function _playground_append_run_index(output_root::AbstractString, manifest_out, manifest_json::AbstractString)
    mkpath(output_root)
    index_path = joinpath(output_root, "playground_runs.jsonl")
    row = Dict{String,Any}(
        "created_at_utc" => string(Dates.format(now(UTC), "yyyy-mm-ddTHH:MM:SS"), "Z"),
        "contract_name" => _playground_get(manifest_out, "contract_name", ""),
        "run_tag" => _playground_get(manifest_out, "run_tag", nothing),
        "run_note" => _playground_get(manifest_out, "run_note", nothing),
        "output_dir" => _playground_get(manifest_out, "output_dir", ""),
        "manifest_json" => manifest_json,
        "cost_final" => _playground_get(manifest_out, "cost_final", nothing),
        "converged" => _playground_get(manifest_out, "converged", nothing),
        "source_sha256" => _playground_get(manifest_out, "source_sha256", nothing),
        "artifact_error" => _playground_get(manifest_out, "artifact_error", nothing),
        "parameters_opt" => _playground_get(manifest_out, "parameters_opt", Dict{String,Any}()),
    )
    open(index_path, "a") do io
        JSON3.write(io, _playground_json_safe(row))
        println(io)
    end
    return index_path
end

function check_playground_contract_bundle(path::AbstractString)
    manifest_path, manifest = _playground_read_manifest(path)
    root = dirname(manifest_path)
    execution = _playground_get(manifest, "execution")
    execution === nothing && throw(ArgumentError("contract manifest has no executable `execution` section"))
    mod, source_abs = _playground_load_module(root, execution)
    x0 = _playground_vector(_playground_get(execution, "initial"), "execution.initial")
    lower = _playground_optional_vector(_playground_get(execution, "lower"), "execution.lower", length(x0))
    upper = _playground_optional_vector(_playground_get(execution, "upper"), "execution.upper", length(x0))
    parameter_names = _playground_parameter_names(_playground_get(execution, "parameter_names"), length(x0))
    parameter_metadata = _playground_parameter_metadata(_playground_get(execution, "parameter_metadata"), parameter_names)
    if lower !== nothing || upper !== nothing
        lower !== nothing && upper !== nothing || throw(ArgumentError("execution.lower and execution.upper must be supplied together"))
        all(lower .<= x0 .<= upper) || throw(ArgumentError("execution.initial is outside execution bounds"))
    end

    context_fn = _playground_optional_function(mod, _playground_get(execution, "context_function", "playground_context"))
    context = context_fn === nothing ? (;) : Base.invokelatest(context_fn)
    context = _playground_attach_parameter_context(context, parameter_names, parameter_metadata, lower, upper)
    loss_gradient = _playground_required_function(mod, _playground_get(execution, "loss_gradient"), "execution.loss_gradient")
    J0, grad0, diagnostics0 = _playground_normalize_eval(
        Base.invokelatest(loss_gradient, copy(x0), context),
        length(x0),
        parameter_names=parameter_names,
    )
    return (
        complete = true,
        manifest_path = manifest_path,
        source_path = source_abs,
        dimension = length(x0),
        parameter_names = parameter_names,
        parameter_metadata = parameter_metadata,
        parameter_bounds = Dict(
            String(name) => Dict(
                "lower" => lower === nothing ? nothing : Float64(lower[i]),
                "upper" => upper === nothing ? nothing : Float64(upper[i]),
            )
            for (i, name) in enumerate(parameter_names)
        ),
        parameters_initial = _playground_named_values(parameter_names, x0),
        initial_cost = J0,
        initial_grad_norm = norm(grad0),
        diagnostics = diagnostics0,
    )
end

function _playground_output_dir(manifest, artifacts, execution; output_root=nothing, timestamp=nothing)
    root = output_root === nothing ?
        String(_playground_get(artifacts, "output_root", joinpath("results", "playground"))) :
        String(output_root)
    name = String(_playground_get(manifest, "name", "playground_contract"))
    stamp = timestamp === nothing ? Dates.format(now(UTC), "yyyymmdd_HHMMss") : String(timestamp)
    run_tag = _playground_slug(_playground_get(artifacts, "run_tag", nothing))
    suffix = run_tag === nothing ? stamp : string(stamp, "_", run_tag)
    dir = joinpath(root, string(name, "_", suffix))
    mkpath(dir)
    return dir
end

function run_playground_contract_bundle(
    path::AbstractString;
    output_root=nothing,
    max_iter=nothing,
    dry_run::Bool=false,
    timestamp=nothing,
)
    manifest_path, manifest = _playground_read_manifest(path)
    root = dirname(manifest_path)
    execution = _playground_get(manifest, "execution")
    execution === nothing && throw(ArgumentError("contract manifest has no executable `execution` section"))
    solver = _playground_get(manifest, "solver", Dict{String,Any}())
    artifacts = _playground_get(manifest, "artifacts", Dict{String,Any}())

    check = check_playground_contract_bundle(path)
    dry_run && return (; dry_run = true, check...)

    mod, _ = _playground_load_module(root, execution)
    x0 = _playground_vector(_playground_get(execution, "initial"), "execution.initial")
    n = length(x0)
    lower = _playground_optional_vector(_playground_get(execution, "lower"), "execution.lower", n)
    upper = _playground_optional_vector(_playground_get(execution, "upper"), "execution.upper", n)
    parameter_names = _playground_parameter_names(_playground_get(execution, "parameter_names"), n)
    parameter_metadata = _playground_parameter_metadata(_playground_get(execution, "parameter_metadata"), parameter_names)
    loss_gradient = _playground_required_function(mod, _playground_get(execution, "loss_gradient"), "execution.loss_gradient")
    context_fn = _playground_optional_function(mod, _playground_get(execution, "context_function", "playground_context"))
    artifact_fn = _playground_optional_function(mod, _playground_get(execution, "artifact_function", "playground_artifacts"))
    context = context_fn === nothing ? (;) : Base.invokelatest(context_fn)
    context = _playground_attach_parameter_context(context, parameter_names, parameter_metadata, lower, upper)
    iterations = max_iter === nothing ? Int(_playground_get(solver, "max_iter", 20)) : Int(max_iter)
    iterations > 0 || throw(ArgumentError("solver.max_iter must be positive"))

    trace = NamedTuple[]
    last_diagnostics = Ref{Any}((;))
    fg! = Optim.only_fg!() do F, G, x
        J, grad, diagnostics = _playground_normalize_eval(
            Base.invokelatest(loss_gradient, copy(Float64.(x)), context),
            n,
            parameter_names=parameter_names,
        )
        last_diagnostics[] = diagnostics
        push!(trace, (evaluation = length(trace) + 1, cost = J, grad_norm = norm(grad), diagnostics = diagnostics))
        G !== nothing && (G .= grad)
        F !== nothing && return J
        return nothing
    end

    options = Optim.Options(iterations=iterations, store_trace=false)
    result = if lower !== nothing && upper !== nothing
        Optim.optimize(fg!, lower, upper, x0, Optim.Fminbox(Optim.LBFGS()), options)
    else
        Optim.optimize(fg!, x0, Optim.LBFGS(), options)
    end

    x_opt = Float64.(Optim.minimizer(result))
    J_final, grad_final, diagnostics_final = _playground_normalize_eval(
        Base.invokelatest(loss_gradient, copy(x_opt), context),
        n,
        parameter_names=parameter_names,
    )
    trace_out = copy(trace)
    push!(trace_out, (
        evaluation = length(trace_out) + 1,
        cost = J_final,
        grad_norm = norm(grad_final),
        diagnostics = diagnostics_final,
    ))
    output_dir = _playground_output_dir(manifest, artifacts, execution; output_root=output_root, timestamp=timestamp)
    source_path = check.source_path
    source_snapshot, source_sha256 = _playground_source_snapshot(source_path, output_dir)
    trace_csv = _playground_write_trace_csv(joinpath(output_dir, "objective_trace.csv"), trace_out)
    trace_png = _playground_write_trace_plot(joinpath(output_dir, "objective_trace.png"), trace_out, manifest, artifacts)
    gradient_trace_png = _playground_write_gradient_trace_plot(joinpath(output_dir, "gradient_norm_trace.png"), trace_out, manifest, artifacts)
    parameter_bounds = Dict(
        String(name) => Dict(
            "lower" => lower === nothing ? nothing : Float64(lower[i]),
            "upper" => upper === nothing ? nothing : Float64(upper[i]),
        )
        for (i, name) in enumerate(parameter_names)
    )
    parameter_summary_csv = _playground_write_parameter_summary(
        joinpath(output_dir, "parameter_summary.csv"),
        parameter_names,
        x0,
        x_opt,
        lower,
        upper,
        parameter_metadata,
    )
    parameter_before_after_png = _playground_write_parameter_plot(
        joinpath(output_dir, "parameter_before_after.png"),
        parameter_names,
        x0,
        x_opt,
        parameter_metadata,
        manifest,
        artifacts,
    )
    diagnostics_final_png = _playground_write_diagnostics_plot(
        joinpath(output_dir, "diagnostics_final.png"),
        diagnostics_final,
        manifest,
        artifacts,
    )
    diagnostics_trace_csv = _playground_write_diagnostics_trace_csv(
        joinpath(output_dir, "diagnostics_trace.csv"),
        trace_out,
    )
    diagnostics_trace_png = _playground_write_diagnostics_trace_plot(
        joinpath(output_dir, "diagnostics_trace.png"),
        trace_out,
        manifest,
        artifacts,
    )
    diagnostics_delta_csv = _playground_write_diagnostics_delta_csv(
        joinpath(output_dir, "diagnostics_delta.csv"),
        check.diagnostics,
        diagnostics_final,
    )
    diagnostics_delta_png = _playground_write_diagnostics_delta_plot(
        joinpath(output_dir, "diagnostics_delta.png"),
        check.diagnostics,
        diagnostics_final,
        manifest,
        artifacts,
    )
    parameter_delta_png = _playground_write_parameter_delta_plot(
        joinpath(output_dir, "parameter_delta_normalized.png"),
        parameter_names,
        x0,
        x_opt,
        lower,
        upper,
        parameter_metadata,
        manifest,
        artifacts,
    )
    artifact_paths = Dict{String,String}()
    artifact_error = nothing
    artifact_error_path = nothing
    if artifact_fn !== nothing
        produced = try
            Base.invokelatest(
                artifact_fn,
                (
                    x0 = x0,
                    x_opt = x_opt,
                    parameter_names = parameter_names,
                    parameter_metadata = parameter_metadata,
                    parameter_bounds = parameter_bounds,
                    parameters_initial = _playground_named_values(parameter_names, x0),
                    parameters_opt = _playground_named_values(parameter_names, x_opt),
                    cost_final = J_final,
                    gradient_final = grad_final,
                    trace = trace_out,
                    diagnostics_initial = check.diagnostics,
                    diagnostics_final = diagnostics_final,
                    diagnostics_trace_csv = diagnostics_trace_csv,
                    diagnostics_delta_csv = diagnostics_delta_csv,
                    optimizer_result = result,
                ),
                context,
                output_dir,
            )
        catch err
            message = "playground_artifacts failed: $(sprint(showerror, err))"
            artifact_error = message
            artifact_error_path = _playground_artifact_error_path(output_dir, message)
            nothing
        end
        if produced isa AbstractDict
            for (key, value) in produced
                artifact_paths[String(key)] = String(value)
            end
        end
    end

    payload = (
        schema = "fiber_playground_freeform_result_v1",
        contract_manifest = manifest_path,
        contract_name = String(_playground_get(manifest, "name", "playground_contract")),
        x0 = x0,
        x_opt = x_opt,
        parameter_names = parameter_names,
        parameter_metadata = parameter_metadata,
        parameter_bounds = parameter_bounds,
        parameters_initial = _playground_named_values(parameter_names, x0),
        parameters_opt = _playground_named_values(parameter_names, x_opt),
        cost_initial = check.initial_cost,
        cost_final = J_final,
        gradient_final = grad_final,
        grad_norm_final = norm(grad_final),
        iterations = Optim.iterations(result),
        converged = Optim.converged(result),
        trace = trace_out,
        parameter_summary_csv = parameter_summary_csv,
        parameter_before_after_png = parameter_before_after_png,
        parameter_delta_png = parameter_delta_png,
        diagnostics_final_png = diagnostics_final_png,
        diagnostics_trace_csv = diagnostics_trace_csv,
        diagnostics_trace_png = diagnostics_trace_png,
        diagnostics_delta_csv = diagnostics_delta_csv,
        diagnostics_delta_png = diagnostics_delta_png,
        source_snapshot = source_snapshot,
        source_sha256 = source_sha256,
        artifact_error = artifact_error,
        artifact_error_path = artifact_error_path,
        diagnostics_initial = check.diagnostics,
        diagnostics_final = diagnostics_final,
    )
    artifact_path = joinpath(output_dir, "opt_result.jld2")
    write_jld2_file(artifact_path; payload...)

    manifest_out = Dict{String,Any}(
        "schema" => "fiber_playground_freeform_manifest_v1",
        "contract_manifest" => manifest_path,
        "contract_name" => payload.contract_name,
        "run_tag" => _playground_get(artifacts, "run_tag", nothing),
        "run_note" => _playground_get(artifacts, "run_note", nothing),
        "artifact_path" => artifact_path,
        "output_dir" => output_dir,
        "cost_initial" => payload.cost_initial,
        "cost_final" => payload.cost_final,
        "parameter_names" => collect(parameter_names),
        "parameters_initial" => payload.parameters_initial,
        "parameters_opt" => payload.parameters_opt,
        "grad_norm_final" => payload.grad_norm_final,
        "iterations" => payload.iterations,
        "converged" => payload.converged,
        "trace_csv" => trace_csv,
        "trace_png" => trace_png,
        "gradient_trace_png" => gradient_trace_png,
        "parameter_metadata" => parameter_metadata,
        "parameter_bounds" => parameter_bounds,
        "parameter_summary_csv" => parameter_summary_csv,
        "parameter_before_after_png" => parameter_before_after_png,
        "parameter_delta_png" => parameter_delta_png,
        "diagnostics_final_png" => diagnostics_final_png,
        "diagnostics_trace_csv" => diagnostics_trace_csv,
        "diagnostics_trace_png" => diagnostics_trace_png,
        "diagnostics_delta_csv" => diagnostics_delta_csv,
        "diagnostics_delta_png" => diagnostics_delta_png,
        "source_snapshot" => source_snapshot,
        "source_sha256" => source_sha256,
        "custom_artifacts" => artifact_paths,
        "artifact_error" => artifact_error,
        "artifact_error_path" => artifact_error_path,
        "diagnostics_final" => _playground_json_safe(diagnostics_final),
    )
    manifest_json = joinpath(output_dir, "run_manifest.json")
    write_json_file(manifest_json, _playground_json_safe(manifest_out))
    run_index = _playground_append_run_index(dirname(output_dir), manifest_out, manifest_json)

    return (
        output_dir = output_dir,
        artifact_path = artifact_path,
        manifest_json = manifest_json,
        trace_csv = trace_csv,
        trace_png = trace_png,
        gradient_trace_png = gradient_trace_png,
        custom_artifacts = artifact_paths,
        parameter_before_after_png = parameter_before_after_png,
        parameter_delta_png = parameter_delta_png,
        diagnostics_final_png = diagnostics_final_png,
        diagnostics_trace_csv = diagnostics_trace_csv,
        diagnostics_trace_png = diagnostics_trace_png,
        diagnostics_delta_csv = diagnostics_delta_csv,
        diagnostics_delta_png = diagnostics_delta_png,
        artifact_error = artifact_error,
        artifact_error_path = artifact_error_path,
        run_index = run_index,
        result = result,
        payload = payload,
    )
end

end # include guard
