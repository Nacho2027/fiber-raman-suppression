#!/usr/bin/env julia
# scripts/validation_inventory.jl
#
# Metadata-only inventory of JLD2 files under results/raman/**.
# Opens each file read-only, inspects top-level keys (and one level of
# Dict nesting), and records whether a useful optimized-phase array
# (phi_opt / φ_opt / phi_after / phi) is present, plus small scalar
# metadata we'd need to re-run the corresponding optimization.
#
# Does NOT run any simulation. Does NOT materialize large arrays.
#
# Usage:
#   julia --project=. scripts/validation_inventory.jl
# Output:
#   /tmp/jld2_inventory.md

using JLD2
using Printf
using Dates

const ROOT = joinpath(@__DIR__, "..", "results", "raman")
const OUT  = "/tmp/jld2_inventory.md"

const PHI_KEYS = ("phi_opt", "φ_opt", "phi_after", "phi")

# Metadata scalar keys we'd want for a re-run. Listed in probe order.
const META_KEYS = (
    "L", "L_m", "L_fiber", "length_m",
    "P_cont_W", "P0", "P0_W", "peak_power_W", "P_W",
    "pulse_fwhm", "fwhm_fs", "pulse_fwhm_fs", "fwhm_s",
    "gamma", "γ",
    "betas", "beta", "β",
    "fR", "f_R",
    "Nt", "N_t",
    "time_window_ps", "time_window",
    "fiber_name", "fiber", "fiber_preset",
    "lambda0_nm", "λ0", "lambda0",
    "M", "n_modes", "Nmodes",
)

const J_KEYS = ("J", "J_after", "J_final", "J_opt", "J_before", "cost_after", "cost_final")

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

"""Return a short type/shape summary without materializing large arrays."""
function short_descr(x)
    try
        if x isa AbstractArray
            return string(typeof(x).name.name, eltype(x), " ", size(x))
        elseif x isa Dict
            ks = collect(keys(x))
            return "Dict{…}(" * string(length(ks)) * " keys)"
        elseif x isa Number
            return @sprintf("%.6g", x)
        elseif x isa AbstractString
            return "\"" * String(x) * "\""
        elseif x isa Tuple
            return "Tuple(len=$(length(x)))"
        else
            return string(typeof(x))
        end
    catch e
        return "<unreadable: $(typeof(e))>"
    end
end

"""Does `x` look like an optimized-phase array? (1D or 2D real, length > 1)"""
function looks_like_phi(x)
    x isa AbstractArray || return false
    eltype(x) <: Real || return false
    length(x) > 1 || return false
    return true
end

"""Probe one container (top-level file group or a nested Dict) for phi / meta / J.
Returns NamedTuple of findings for that level."""
function probe_container(container, keylist)
    phi_key = nothing
    phi_shape = nothing
    meta = Dict{String,String}()
    jvals = Dict{String,String}()

    for k in keylist
        ks = String(k)
        # phi candidates
        if ks in PHI_KEYS
            try
                v = container[ks]
                if looks_like_phi(v)
                    phi_key = ks
                    phi_shape = size(v)
                end
            catch
            end
        end
        # scalar metadata
        if ks in META_KEYS
            try
                v = container[ks]
                meta[ks] = short_descr(v)
            catch
                meta[ks] = "<err>"
            end
        end
        # J-like scalars
        if ks in J_KEYS
            try
                v = container[ks]
                jvals[ks] = short_descr(v)
            catch
                jvals[ks] = "<err>"
            end
        end
    end
    return (; phi_key, phi_shape, meta, jvals)
end

"""Merge inner-level findings into outer findings, preferring outer hits."""
function merge_findings!(outer, inner, inner_label)
    if outer.phi_key === nothing && inner.phi_key !== nothing
        outer = (; phi_key = "$(inner_label).$(inner.phi_key)",
                   phi_shape = inner.phi_shape,
                   meta = outer.meta,
                   jvals = outer.jvals)
    end
    for (k, v) in inner.meta
        get!(outer.meta, "$(inner_label).$(k)", v)
    end
    for (k, v) in inner.jvals
        get!(outer.jvals, "$(inner_label).$(k)", v)
    end
    return outer
end

"""Inspect a single JLD2 file and return a row dict."""
function inspect_file(path::AbstractString)
    row = Dict{String,Any}(
        "path"       => path,
        "top_keys"   => String[],
        "phi_key"    => nothing,
        "phi_shape"  => nothing,
        "meta"       => Dict{String,String}(),
        "jvals"      => Dict{String,String}(),
        "error"      => nothing,
    )
    try
        jldopen(path, "r") do io
            top = collect(keys(io))
            row["top_keys"] = String.(top)

            findings = probe_container(io, top)

            # Recurse one level into Dict-valued keys (e.g. `results`) AND
            # Vector{Dict} entries (sweep files store per-config Dicts this way).
            # For Vector{Dict}, we only probe the FIRST entry to discover schema —
            # the full set of phi_opts is reported via the n_entries count.
            n_entries_by_key = Dict{String,Int}()
            for k in top
                ks = String(k)
                try
                    v = io[ks]
                    if v isa Dict
                        # Dict values may use String OR Symbol keys
                        inner_keys = String.(collect(keys(v)))
                        # String-keyed Dict: probe_container works directly
                        if keytype(v) == String
                            inner = probe_container(v, inner_keys)
                        else
                            # Symbol-keyed — adapt: rebuild a String-keyed view on demand
                            inner = probe_container(Dict(String(k2) => v[k2] for k2 in keys(v)),
                                                    inner_keys)
                        end
                        findings = merge_findings!(findings, inner, ks)
                    elseif v isa AbstractVector && !isempty(v) && first(v) isa Dict
                        n_entries_by_key[ks] = length(v)
                        entry = first(v)
                        inner_keys = String.(collect(keys(entry)))
                        if keytype(entry) == String
                            inner = probe_container(entry, inner_keys)
                        else
                            inner = probe_container(
                                Dict(String(k2) => entry[k2] for k2 in keys(entry)),
                                inner_keys)
                        end
                        # Label with index suffix so downstream readers see it's Vector
                        findings = merge_findings!(findings, inner, "$(ks)[1]")
                    end
                catch
                    # key unreadable as whole — skip
                end
            end
            row["n_entries_by_key"] = n_entries_by_key

            row["phi_key"]   = findings.phi_key
            row["phi_shape"] = findings.phi_shape
            row["meta"]      = findings.meta
            row["jvals"]     = findings.jvals
        end
    catch e
        row["error"] = sprint(showerror, e)
    end
    return row
end

# ──────────────────────────────────────────────────────────────────────────────
# Walk results/raman/** for *.jld2
# ──────────────────────────────────────────────────────────────────────────────

function walk_jld2(root)
    files = String[]
    for (dirpath, _, filenames) in walkdir(root)
        for fn in filenames
            endswith(fn, ".jld2") || continue
            push!(files, joinpath(dirpath, fn))
        end
    end
    sort!(files)
    return files
end

# ──────────────────────────────────────────────────────────────────────────────
# Markdown rendering
# ──────────────────────────────────────────────────────────────────────────────

function compact_dict(d::Dict{String,String}; max_items=8)
    isempty(d) && return "—"
    keys_sorted = sort(collect(keys(d)))
    items = String[]
    for k in keys_sorted[1:min(end, max_items)]
        push!(items, "`$(k)`=$(d[k])")
    end
    if length(keys_sorted) > max_items
        push!(items, "…(+$(length(keys_sorted)-max_items))")
    end
    return join(items, ", ")
end

function render_markdown(rows, outpath)
    open(outpath, "w") do io
        println(io, "# JLD2 Inventory — results/raman/**")
        println(io)
        println(io, "Generated: ", now_str())
        println(io, "Total files: ", length(rows))
        println(io)
        println(io, "| # | Path | Top-level keys | phi key | phi shape | Scalar metadata (key=val) | J-like |")
        println(io, "|---|------|----------------|---------|-----------|---------------------------|--------|")
        for (i, r) in enumerate(rows)
            path_short = replace(r["path"], joinpath(@__DIR__, "..") => "")
            if r["error"] !== nothing
                println(io, "| $(i) | `$(path_short)` | **ERROR**: $(r["error"]) | — | — | — | — |")
                continue
            end
            topk = join(("`" .* r["top_keys"] .* "`"), ", ")
            phik = r["phi_key"] === nothing ? "—" : "`$(r["phi_key"])`"
            phis = r["phi_shape"] === nothing ? "—" : string(r["phi_shape"])
            # Annotate with per-key Vector{Dict} entry counts if the phi lives inside one
            nents = get(r, "n_entries_by_key", Dict{String,Int}())
            if !isempty(nents)
                suffix_parts = ["$(k)[×$(v)]" for (k,v) in nents]
                phis = phis * " [" * join(suffix_parts, ",") * "]"
            end
            meta = compact_dict(r["meta"])
            jv   = compact_dict(r["jvals"])
            # Escape pipes in content so markdown table survives
            topk = replace(topk, "|" => "\\|")
            meta = replace(meta, "|" => "\\|")
            jv   = replace(jv,   "|" => "\\|")
            println(io, "| $(i) | `$(path_short)` | $(topk) | $(phik) | $(phis) | $(meta) | $(jv) |")
        end

        println(io)
        println(io, "## In-scope (phi_opt / equivalent present)")
        println(io)
        in_scope = filter(r -> r["error"] === nothing && r["phi_key"] !== nothing, rows)
        if isempty(in_scope)
            println(io, "_(none)_")
        else
            for r in in_scope
                path_short = replace(r["path"], joinpath(@__DIR__, "..") => "")
                println(io, "- `$(path_short)` — phi @ `$(r["phi_key"])`, shape $(r["phi_shape"])")
            end
        end

        println(io)
        println(io, "## Out-of-scope (no usable phi array)")
        println(io)
        out_scope = filter(r -> r["error"] !== nothing || r["phi_key"] === nothing, rows)
        if isempty(out_scope)
            println(io, "_(none)_")
        else
            for r in out_scope
                path_short = replace(r["path"], joinpath(@__DIR__, "..") => "")
                reason = if r["error"] !== nothing
                    "error: $(r["error"])"
                else
                    "no phi_opt-like key among top keys=$(r["top_keys"])"
                end
                println(io, "- `$(path_short)` — $(reason)")
            end
        end
    end
end

now_str() = string(Dates.now())

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

function main()
    files = walk_jld2(ROOT)
    @info "Found $(length(files)) JLD2 files under $(ROOT)"
    rows = Vector{Dict{String,Any}}(undef, length(files))
    for (i, f) in enumerate(files)
        @info "[$(i)/$(length(files))] $(f)"
        rows[i] = inspect_file(f)
    end
    render_markdown(rows, OUT)
    @info "Wrote inventory to $(OUT)"
end

main()
