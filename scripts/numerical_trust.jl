using Dates
using Printf

if !(@isdefined _NUMERICAL_TRUST_JL_LOADED)
const _NUMERICAL_TRUST_JL_LOADED = true

const NUMERICAL_TRUST_SCHEMA_VERSION = "28.0"

const TRUST_THRESHOLDS = (
    energy_drift_pass = 1e-4,
    energy_drift_marginal = 1e-3,
    edge_frac_pass = 1e-3,
    edge_frac_marginal = 1e-2,
    gradcheck_pass = 5e-2,
    gradcheck_marginal = 1e-1,
)

const _TRUST_RANK = Dict("PASS" => 0, "MARGINAL" => 1, "SUSPECT" => 2, "NOT_RUN" => 3)

function trust_verdict(value::Real, pass::Real, marginal::Real)
    !isfinite(value) && return "NOT_RUN"
    value <= pass && return "PASS"
    value <= marginal && return "MARGINAL"
    return "SUSPECT"
end

function worst_trust_verdict(verdicts)
    isempty(verdicts) && return "NOT_RUN"
    worst = "PASS"
    for verdict in verdicts
        rank = get(_TRUST_RANK, verdict, 3)
        if rank > get(_TRUST_RANK, worst, 3)
            worst = verdict
        end
    end
    return worst
end

function determinism_verdict(det_status)
    if det_status.applied && det_status.fftw_threads == 1 && det_status.blas_threads == 1
        return "PASS"
    end
    return "SUSPECT"
end

function build_numerical_trust_report(;
    det_status,
    edge_input_frac::Real,
    edge_output_frac::Real,
    energy_drift::Real,
    gradient_validation=nothing,
    log_cost::Bool,
    λ_gdd::Real,
    λ_boundary::Real,
    objective_label::AbstractString="spectral phase optimization")

    boundary_max = max(edge_input_frac, edge_output_frac)
    boundary_verdict = trust_verdict(boundary_max,
        TRUST_THRESHOLDS.edge_frac_pass, TRUST_THRESHOLDS.edge_frac_marginal)
    energy_verdict = trust_verdict(energy_drift,
        TRUST_THRESHOLDS.energy_drift_pass, TRUST_THRESHOLDS.energy_drift_marginal)

    grad_block = if isnothing(gradient_validation)
        Dict{String,Any}(
            "status" => "not_run",
            "verdict" => "NOT_RUN",
            "max_rel_err" => NaN,
            "mean_rel_err" => NaN,
            "n_checks" => 0,
            "epsilon" => NaN,
        )
    else
        max_rel_err = gradient_validation.max_rel_err
        Dict{String,Any}(
            "status" => "ran",
            "verdict" => trust_verdict(max_rel_err,
                TRUST_THRESHOLDS.gradcheck_pass, TRUST_THRESHOLDS.gradcheck_marginal),
            "max_rel_err" => max_rel_err,
            "mean_rel_err" => gradient_validation.mean_rel_err,
            "n_checks" => gradient_validation.n_checks,
            "epsilon" => gradient_validation.epsilon,
        )
    end

    det_block = Dict{String,Any}(
        "applied" => det_status.applied,
        "fftw_threads" => det_status.fftw_threads,
        "blas_threads" => det_status.blas_threads,
        "version" => String(det_status.version),
        "phase" => String(det_status.phase),
        "verdict" => determinism_verdict(det_status),
    )

    cost_surface_block = Dict{String,Any}(
        "objective_label" => String(objective_label),
        "log_cost" => log_cost,
        "surface" => log_cost ? "10*log10(physics + regularizers)" : "physics + regularizers",
        "regularizers_chained_into_surface" => true,
        "lambda_gdd" => λ_gdd,
        "lambda_boundary" => λ_boundary,
        "boundary_penalty_measurement" => "pre-attenuator temporal edge fraction of shaped input pulse",
        "verdict" => "PASS",
    )

    report = Dict{String,Any}(
        "schema_version" => NUMERICAL_TRUST_SCHEMA_VERSION,
        "timestamp_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
        "thresholds" => Dict(
            "energy_drift_pass" => TRUST_THRESHOLDS.energy_drift_pass,
            "energy_drift_marginal" => TRUST_THRESHOLDS.energy_drift_marginal,
            "edge_frac_pass" => TRUST_THRESHOLDS.edge_frac_pass,
            "edge_frac_marginal" => TRUST_THRESHOLDS.edge_frac_marginal,
            "gradcheck_pass" => TRUST_THRESHOLDS.gradcheck_pass,
            "gradcheck_marginal" => TRUST_THRESHOLDS.gradcheck_marginal,
        ),
        "determinism" => det_block,
        "boundary" => Dict(
            "input_edge_frac" => edge_input_frac,
            "output_edge_frac" => edge_output_frac,
            "max_edge_frac" => boundary_max,
            "verdict" => boundary_verdict,
        ),
        "energy" => Dict(
            "drift" => energy_drift,
            "verdict" => energy_verdict,
        ),
        "gradient_validation" => grad_block,
        "cost_surface" => cost_surface_block,
    )

    report["overall_verdict"] = worst_trust_verdict(String[
        det_block["verdict"],
        boundary_verdict,
        energy_verdict,
        grad_block["verdict"],
        cost_surface_block["verdict"],
    ])
    return report
end

function write_numerical_trust_report(path::AbstractString, report::Dict{String,Any})
    mkpath(dirname(path))
    det = report["determinism"]
    bc = report["boundary"]
    en = report["energy"]
    grad = report["gradient_validation"]
    surf = report["cost_surface"]
    open(path, "w") do io
        println(io, "# Numerical Trust Report")
        println(io)
        println(io, @sprintf("- Schema version: `%s`", report["schema_version"]))
        println(io, @sprintf("- Timestamp (UTC): `%s`", report["timestamp_utc"]))
        println(io, @sprintf("- Overall verdict: **%s**", report["overall_verdict"]))
        println(io)
        println(io, "## Determinism")
        println(io, @sprintf("- Verdict: **%s**", det["verdict"]))
        println(io, @sprintf("- Applied: `%s`", string(det["applied"])))
        println(io, @sprintf("- FFTW threads: `%d`", det["fftw_threads"]))
        println(io, @sprintf("- BLAS threads: `%d`", det["blas_threads"]))
        println(io)
        println(io, "## Boundary")
        println(io, @sprintf("- Verdict: **%s**", bc["verdict"]))
        println(io, @sprintf("- Input edge fraction: `%.3e`", bc["input_edge_frac"]))
        println(io, @sprintf("- Output edge fraction: `%.3e`", bc["output_edge_frac"]))
        println(io, @sprintf("- Max edge fraction: `%.3e`", bc["max_edge_frac"]))
        println(io)
        println(io, "## Energy")
        println(io, @sprintf("- Verdict: **%s**", en["verdict"]))
        println(io, @sprintf("- Relative drift: `%.3e`", en["drift"]))
        println(io)
        println(io, "## Gradient Validation")
        println(io, @sprintf("- Verdict: **%s**", grad["verdict"]))
        println(io, @sprintf("- Status: `%s`", grad["status"]))
        if grad["status"] == "ran"
            println(io, @sprintf("- Max relative error: `%.3e`", grad["max_rel_err"]))
            println(io, @sprintf("- Mean relative error: `%.3e`", grad["mean_rel_err"]))
            println(io, @sprintf("- Checks: `%d` at ε=`%.1e`", grad["n_checks"], grad["epsilon"]))
        end
        println(io)
        println(io, "## Cost Surface")
        println(io, @sprintf("- Verdict: **%s**", surf["verdict"]))
        println(io, @sprintf("- Surface: `%s`", surf["surface"]))
        println(io, @sprintf("- λ_gdd: `%.3e`", surf["lambda_gdd"]))
        println(io, @sprintf("- λ_boundary: `%.3e`", surf["lambda_boundary"]))
        println(io, @sprintf("- Boundary penalty measurement: `%s`", surf["boundary_penalty_measurement"]))
    end
    return path
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 30 additive extension — continuation metadata
# ─────────────────────────────────────────────────────────────────────────────
# Strictly ADDITIVE: the Phase 28 schema version string remains "28.0". A
# pre-Phase-30 consumer reading one of these reports sees the same existing
# fields; the new `continuation` sub-dict is optional and always under a
# separate top-level key. See scripts/continuation.jl for the caller.

const _CONTINUATION_LADDER_VARS = Set(["L", "P", "Nphi", "lambda"])
const _CONTINUATION_PATH_STATUS = Set(["ok", "degraded", "broken"])

"""
    attach_continuation_metadata!(report::Dict{String,Any}, meta::Dict{String,Any})
        -> Dict{String,Any}

Additive Phase 30 extension — schema version remains 28.0. Merges continuation
metadata under `report["continuation"]` without modifying any existing field.
Multiple calls accumulate via `merge()`.

# Required keys in `meta`
- `continuation_id::String`
- `ladder_var::String`   ∈ `{"L", "P", "Nphi", "lambda"}`
- `step_index::Int`
- `path_status::String`  ∈ `{"ok", "degraded", "broken"}`

# Optional keys
- `ladder_value::Float64`
- `predictor::String`    (e.g., `"trivial"`, `"secant"`, `"scaled"`)
- `corrector::String`    (e.g., `"lbfgs_warm_restart"`)
- `is_cold_start_baseline::Bool`
- `detectors::Dict`      with optional float keys
                         `cost_discontinuity_dB`, `corrector_iters`,
                         `phase_jump_ratio`, `edge_fraction_delta`

# Raises
`ArgumentError` if `ladder_var` or `path_status` is not in the known enum sets,
or if any of the required keys is absent.

# Example
```julia
attach_continuation_metadata!(report, Dict{String,Any}(
    "continuation_id" => "p30_demo_smf28_L",
    "ladder_var"      => "L",
    "step_index"      => 2,
    "ladder_value"    => 10.0,
    "predictor"       => "trivial",
    "corrector"       => "lbfgs_warm_restart",
    "path_status"     => "ok",
    "is_cold_start_baseline" => false,
))
```
"""
function attach_continuation_metadata!(report::Dict{String,Any},
                                       meta::Dict{String,Any})
    # Required keys
    for k in ("continuation_id", "ladder_var", "step_index", "path_status")
        haskey(meta, k) || throw(ArgumentError(
            "attach_continuation_metadata!: missing required key `$k`"))
    end
    ladder_var = meta["ladder_var"]
    path_status = meta["path_status"]
    ladder_var isa AbstractString || throw(ArgumentError(
        "attach_continuation_metadata!: `ladder_var` must be a String, got $(typeof(ladder_var))"))
    path_status isa AbstractString || throw(ArgumentError(
        "attach_continuation_metadata!: `path_status` must be a String, got $(typeof(path_status))"))
    String(ladder_var) in _CONTINUATION_LADDER_VARS || throw(ArgumentError(
        "attach_continuation_metadata!: invalid ladder_var `$(ladder_var)`; expected one of $(collect(_CONTINUATION_LADDER_VARS))"))
    String(path_status) in _CONTINUATION_PATH_STATUS || throw(ArgumentError(
        "attach_continuation_metadata!: invalid path_status `$(path_status)`; expected one of $(collect(_CONTINUATION_PATH_STATUS))"))

    existing = get(report, "continuation", Dict{String,Any}())
    report["continuation"] = merge(existing, meta)
    return report
end

end  # include guard
