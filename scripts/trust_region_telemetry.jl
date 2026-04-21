# ═══════════════════════════════════════════════════════════════════════════════
# Phase 33 Plan 01 — Trust-region telemetry schema
# ═══════════════════════════════════════════════════════════════════════════════
#
# Provides:
#   - `TRIterationRecord` — per-iteration row struct (19 fields)
#   - `to_csv_header()`, `to_csv_row(r)`, `read_telemetry_csv(path)`, and
#     `write_telemetry_csv(path, records)` — round-trip-stable CSV I/O
#     using `%.17g` for Float64 so every bit of every value is preserved
#     (NaN / Inf included).
#   - `append_trust_report_section(md_path, summary, records)` — extends a
#     Phase 28 trust-report markdown with an `## Optimizer (Trust-Region)`
#     section. Does NOT fork the Phase 28 schema; this is a strictly
#     ADDITIVE extension that shares schema version "28.0".
#
# Read-only consumer of Printf, Dates, Statistics. Does NOT include
# common.jl or the Raman oracle — telemetry is format-only.
# ═══════════════════════════════════════════════════════════════════════════════

using Printf
using Dates
using Statistics

if !(@isdefined _TRUST_REGION_TELEMETRY_JL_LOADED)
const _TRUST_REGION_TELEMETRY_JL_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# Per-iteration row
# ─────────────────────────────────────────────────────────────────────────────

"""
    TRIterationRecord

One row of the trust-region telemetry log. Field order matches the CSV
header exactly — do NOT reorder without bumping a schema version.

Fields:
- `iter::Int`                              — outer iteration number (1-based)
- `J::Float64`                             — cost at current iterate (physics or dB per caller)
- `grad_norm::Float64`                     — ‖g‖ after gauge projection
- `delta::Float64`                         — trust radius Δ entering this iter
- `rho::Float64`                           — actual/predicted ratio; NaN if step rejected pre-ρ
- `pred_reduction::Float64`                — `-m(p_k)`
- `actual_reduction::Float64`              — `J_k − J_{k+1}` (NaN if trial NaN'd)
- `step_norm::Float64`                     — ‖p_k‖
- `step_accepted::Bool`
- `cg_iters::Int`                          — Steihaug inner iterations this step
- `cg_exit::Symbol`                        — :INTERIOR_CONVERGED | :BOUNDARY_HIT | :NEGATIVE_CURVATURE | :MAX_ITER | :NO_DESCENT
- `lambda_min_est::Float64`                — leftmost Hessian eigenvalue (NaN if not probed)
- `lambda_max_est::Float64`                — rightmost Hessian eigenvalue (NaN if not probed)
- `kappa_eff::Float64`                     — λ_max / max(|λ_min_nonzero|, eps) (NaN if not probed)
- `hvps_this_iter::Int`
- `grad_calls_this_iter::Int`
- `forward_only_calls_this_iter::Int`
- `wall_time_s::Float64`                   — cumulative wall-clock seconds since opt start
- `eps_hvp_used::Float64`                  — last finite-difference ε used in H_op (pitfall P2 diagnostic)
"""
struct TRIterationRecord
    iter::Int
    J::Float64
    grad_norm::Float64
    delta::Float64
    rho::Float64
    pred_reduction::Float64
    actual_reduction::Float64
    step_norm::Float64
    step_accepted::Bool
    cg_iters::Int
    cg_exit::Symbol
    lambda_min_est::Float64
    lambda_max_est::Float64
    kappa_eff::Float64
    hvps_this_iter::Int
    grad_calls_this_iter::Int
    forward_only_calls_this_iter::Int
    wall_time_s::Float64
    eps_hvp_used::Float64
end

# ─────────────────────────────────────────────────────────────────────────────
# CSV I/O
# ─────────────────────────────────────────────────────────────────────────────

const _TR_CSV_FIELDS = (
    :iter, :J, :grad_norm, :delta, :rho, :pred_reduction, :actual_reduction,
    :step_norm, :step_accepted, :cg_iters, :cg_exit, :lambda_min_est,
    :lambda_max_est, :kappa_eff, :hvps_this_iter, :grad_calls_this_iter,
    :forward_only_calls_this_iter, :wall_time_s, :eps_hvp_used,
)

to_csv_header() = join(String.(_TR_CSV_FIELDS), ",")

_fmt_float(x::Float64) = @sprintf("%.17g", x)
_fmt_int(x::Integer) = string(x)
_fmt_bool(x::Bool) = string(x)
_fmt_symbol(x::Symbol) = String(x)

"""
    to_csv_row(r::TRIterationRecord) -> String

Format one record as a comma-separated row. Float fields use `%.17g` so
parsing back via `parse(Float64, ...)` reproduces the bit-identical value
(including NaN and Inf).
"""
function to_csv_row(r::TRIterationRecord)
    parts = String[]
    push!(parts, _fmt_int(r.iter))
    push!(parts, _fmt_float(r.J))
    push!(parts, _fmt_float(r.grad_norm))
    push!(parts, _fmt_float(r.delta))
    push!(parts, _fmt_float(r.rho))
    push!(parts, _fmt_float(r.pred_reduction))
    push!(parts, _fmt_float(r.actual_reduction))
    push!(parts, _fmt_float(r.step_norm))
    push!(parts, _fmt_bool(r.step_accepted))
    push!(parts, _fmt_int(r.cg_iters))
    push!(parts, _fmt_symbol(r.cg_exit))
    push!(parts, _fmt_float(r.lambda_min_est))
    push!(parts, _fmt_float(r.lambda_max_est))
    push!(parts, _fmt_float(r.kappa_eff))
    push!(parts, _fmt_int(r.hvps_this_iter))
    push!(parts, _fmt_int(r.grad_calls_this_iter))
    push!(parts, _fmt_int(r.forward_only_calls_this_iter))
    push!(parts, _fmt_float(r.wall_time_s))
    push!(parts, _fmt_float(r.eps_hvp_used))
    return join(parts, ",")
end

"""
    write_telemetry_csv(path, records)

Write `records` as CSV at `path`. Creates parent directory if needed.
Overwrites an existing file.
"""
function write_telemetry_csv(path::AbstractString, records::AbstractVector{TRIterationRecord})
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, to_csv_header())
        for r in records
            println(io, to_csv_row(r))
        end
    end
    return path
end

"""
    read_telemetry_csv(path) -> Vector{TRIterationRecord}

Round-trip reader: parse the CSV produced by `write_telemetry_csv` back into
`TRIterationRecord` values. Preserves NaN / Inf via `parse(Float64, "NaN")`.
"""
function read_telemetry_csv(path::AbstractString)
    records = TRIterationRecord[]
    lines = readlines(path)
    @assert length(lines) >= 1 "empty CSV at $path"
    header = split(lines[1], ",")
    @assert length(header) == length(_TR_CSV_FIELDS) "header width $(length(header)) ≠ $(length(_TR_CSV_FIELDS))"
    for ln in lines[2:end]
        isempty(strip(ln)) && continue
        fields = split(ln, ",")
        @assert length(fields) == length(_TR_CSV_FIELDS) "row width mismatch: $(length(fields)) vs $(length(_TR_CSV_FIELDS))"
        r = TRIterationRecord(
            parse(Int, fields[1]),
            parse(Float64, fields[2]),
            parse(Float64, fields[3]),
            parse(Float64, fields[4]),
            parse(Float64, fields[5]),
            parse(Float64, fields[6]),
            parse(Float64, fields[7]),
            parse(Float64, fields[8]),
            parse(Bool, fields[9]),
            parse(Int, fields[10]),
            Symbol(fields[11]),
            parse(Float64, fields[12]),
            parse(Float64, fields[13]),
            parse(Float64, fields[14]),
            parse(Int, fields[15]),
            parse(Int, fields[16]),
            parse(Int, fields[17]),
            parse(Float64, fields[18]),
            parse(Float64, fields[19]),
        )
        push!(records, r)
    end
    return records
end

# ─────────────────────────────────────────────────────────────────────────────
# Trust-report extension
# ─────────────────────────────────────────────────────────────────────────────

"""
    rejection_breakdown(records) -> Dict{Symbol,Int}

Count iterations by rejection cause. Causes are mutually exclusive per row:
- `:accepted`            — step was accepted
- `:rho_too_small`       — ρ < η₁ and not otherwise classified
- `:negative_curvature`  — Steihaug exited :NEGATIVE_CURVATURE
- `:boundary_hit`        — Steihaug exited :BOUNDARY_HIT and step was rejected
- `:cg_max_iter`         — Steihaug exited :MAX_ITER and step was rejected
- `:nan_at_trial_point`  — ρ = NaN (J(φ+p) NaN'd)
"""
function rejection_breakdown(records::AbstractVector{TRIterationRecord})
    counts = Dict{Symbol,Int}(
        :accepted => 0,
        :rho_too_small => 0,
        :negative_curvature => 0,
        :boundary_hit => 0,
        :cg_max_iter => 0,
        :nan_at_trial_point => 0,
    )
    for r in records
        if r.step_accepted
            counts[:accepted] += 1
        elseif !isfinite(r.rho)
            counts[:nan_at_trial_point] += 1
        elseif r.cg_exit == :NEGATIVE_CURVATURE
            counts[:negative_curvature] += 1
        elseif r.cg_exit == :BOUNDARY_HIT
            counts[:boundary_hit] += 1
        elseif r.cg_exit == :MAX_ITER
            counts[:cg_max_iter] += 1
        else
            counts[:rho_too_small] += 1
        end
    end
    return counts
end

"""
    append_trust_report_section(md_path, summary, records)

Append an `## Optimizer (Trust-Region)` section to `md_path`. Creates the
file if missing. `summary` is a Dict with keys:
- `"exit_code"`                  — String or TRExitCode
- `"iterations"`                 — Int
- `"hvps_total"`                 — Int
- `"grad_calls_total"`           — Int
- `"forward_only_calls_total"`   — Int
- `"wall_time_s"`                — Float64
- `"J_final"`                    — Float64
- `"lambda_min_final"`           — Float64 (NaN if never probed)
- `"lambda_max_final"`           — Float64 (NaN if never probed)

This is strictly additive to Phase 28's schema — the existing sections in
`md_path` are left untouched.
"""
function append_trust_report_section(md_path::AbstractString,
                                     summary::Dict{String,<:Any},
                                     records::AbstractVector{TRIterationRecord})
    mkpath(dirname(md_path))
    accepted = [r for r in records if r.step_accepted]
    accepted_rho = Float64[r.rho for r in accepted if isfinite(r.rho)]
    rej = rejection_breakdown(records)
    open(md_path, "a") do io
        println(io)
        println(io, "## Optimizer (Trust-Region)")
        println(io)
        println(io, @sprintf("- Exit code: **`%s`**", string(summary["exit_code"])))
        println(io, @sprintf("- Iterations: `%d`", summary["iterations"]))
        println(io, @sprintf("- J final: `%.6e`", summary["J_final"]))
        println(io, @sprintf("- ‖g‖ final: `%.3e`",
            isempty(records) ? NaN : last(records).grad_norm))
        println(io, @sprintf("- λ_min final: `%.3e`", summary["lambda_min_final"]))
        println(io, @sprintf("- λ_max final: `%.3e`", summary["lambda_max_final"]))
        println(io)
        println(io, "### Budget")
        println(io, @sprintf("- HVPs: `%d`", summary["hvps_total"]))
        println(io, @sprintf("- Gradient calls: `%d`", summary["grad_calls_total"]))
        println(io, @sprintf("- Forward-only calls: `%d`", summary["forward_only_calls_total"]))
        println(io, @sprintf("- Wall time: `%.2f s`", summary["wall_time_s"]))
        println(io)
        println(io, "### ρ statistics (accepted iterations)")
        if !isempty(accepted_rho)
            println(io, @sprintf("- N accepted: `%d`", length(accepted_rho)))
            println(io, @sprintf("- ρ mean:   `%.3f`", mean(accepted_rho)))
            println(io, @sprintf("- ρ median: `%.3f`", median(accepted_rho)))
            println(io, @sprintf("- ρ min:    `%.3f`", minimum(accepted_rho)))
            println(io, @sprintf("- ρ max:    `%.3f`", maximum(accepted_rho)))
        else
            println(io, "- No accepted iterations.")
        end
        println(io)
        println(io, "### Rejection breakdown")
        for k in (:accepted, :rho_too_small, :negative_curvature, :boundary_hit,
                  :cg_max_iter, :nan_at_trial_point)
            println(io, @sprintf("- `%s`: `%d`", String(k), get(rej, k, 0)))
        end
        println(io)
    end
    return md_path
end

end  # include guard
