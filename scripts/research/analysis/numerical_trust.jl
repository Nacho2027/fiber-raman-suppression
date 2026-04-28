using Dates
using Printf

include(joinpath(@__DIR__, "..", "..", "lib", "objective_surface.jl"))

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
    objective_spec=nothing,
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

    spec = isnothing(objective_spec) ? build_objective_surface_spec(;
        objective_label = objective_label,
        log_cost = log_cost,
        linear_terms = ["physics", "λ_gdd*R_gdd", "λ_boundary*R_boundary"],
        trailing_fields = (
            lambda_gdd = Float64(λ_gdd),
            lambda_boundary = Float64(λ_boundary),
            boundary_penalty_measurement = "pre-attenuator temporal edge fraction of shaped input pulse",
            hvp_safe_for_same_surface = true,
        ),
    ) : objective_spec

    cost_surface_block = Dict{String,Any}(
        "objective_label" => String(spec.objective_label),
        "log_cost" => Bool(spec.log_cost),
        "scale" => String(spec.scale),
        "surface" => String(spec.scalar_surface),
        "pre_log_linear_surface" => String(spec.pre_log_linear_surface),
        "regularizers_chained_into_surface" => Bool(spec.regularizers_chained_into_surface),
        "lambda_gdd" => Float64(spec.lambda_gdd),
        "lambda_boundary" => Float64(spec.lambda_boundary),
        "boundary_penalty_measurement" => String(spec.boundary_penalty_measurement),
        "hvp_safe_for_same_surface" => Bool(spec.hvp_safe_for_same_surface),
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
            "metric" => "photon_number_drift",
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
        println(io, "## Photon Number Conservation")
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
        println(io, @sprintf("- Scale: `%s`", surf["scale"]))
        println(io, @sprintf("- Pre-log linear surface: `%s`", surf["pre_log_linear_surface"]))
        println(io, @sprintf("- λ_gdd: `%.3e`", surf["lambda_gdd"]))
        println(io, @sprintf("- λ_boundary: `%.3e`", surf["lambda_boundary"]))
        println(io, @sprintf("- Boundary penalty measurement: `%s`", surf["boundary_penalty_measurement"]))
        # Phase 30 additive: if the report carries continuation metadata, emit
        # a `## Continuation` section. Pre-Phase-30 reports render unchanged.
        if haskey(report, "continuation")
            cont = report["continuation"]
            println(io)
            println(io, "## Continuation")
            println(io, @sprintf("- ID: `%s`", get(cont, "continuation_id", "")))
            println(io, @sprintf("- Ladder: `%s` step=`%d` value=`%s`",
                                 get(cont, "ladder_var", ""),
                                 get(cont, "step_index", -1),
                                 string(get(cont, "ladder_value", ""))))
            println(io, @sprintf("- Predictor / corrector: `%s` / `%s`",
                                 get(cont, "predictor", ""),
                                 get(cont, "corrector", "")))
            println(io, @sprintf("- Path status: **%s**",
                                 uppercase(get(cont, "path_status", "unknown"))))
            println(io, @sprintf("- Cold-start baseline: `%s`",
                                 string(get(cont, "is_cold_start_baseline", false))))
            if haskey(cont, "detectors")
                for (k, v) in cont["detectors"]
                    println(io, @sprintf("- Detector %s: `%s`", k, string(v)))
                end
            end
        end
        # Phase 32 additive: if the report carries acceleration metadata, emit
        # a `## Acceleration` section. Ordering: Continuation before Acceleration
        # so log diffs stay stable. Pre-Phase-32 reports render unchanged.
        if haskey(report, "acceleration")
            accel = report["acceleration"]
            println(io)
            println(io, "## Acceleration")
            println(io, @sprintf("- Accelerator: `%s`",
                                 get(accel, "accelerator", "unknown")))
            if haskey(accel, "verdict")
                println(io, @sprintf("- Verdict: **%s**", accel["verdict"]))
            end
            for key in ("prediction_norm", "prediction_vs_prev_norm",
                        "coefficient_max", "corrector_iters",
                        "corrector_iters_saved", "j_opt_db_delta",
                        "trust_gap_vs_naive")
                if haskey(accel, key)
                    println(io, @sprintf("- %s: `%s`", key, string(accel[key])))
                end
            end
            if haskey(accel, "safeguard_passed")
                println(io, @sprintf("- Safeguard: `%s` (%s)",
                    accel["safeguard_passed"] ? "PASS" : "FAIL",
                    get(accel, "safeguard_reason", "—")))
            end
        end
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
    "continuation_id" => "p30_reference_smf28_L",
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

# ─────────────────────────────────────────────────────────────────────────────
# Phase 32 additive extension — acceleration metadata
# ─────────────────────────────────────────────────────────────────────────────
# Strictly ADDITIVE: the Phase 28 schema version string remains "28.0". A
# pre-Phase-32 consumer reading one of these reports sees the same existing
# fields; the new `acceleration` sub-dict is optional and always under a
# separate top-level key. Mirrors Phase 30's attach_continuation_metadata!
# pattern exactly. See scripts/acceleration.jl for the Phase 32 caller.

const _ACCELERATION_ACCELERATORS = Set([
    "trivial", "polynomial_d1", "polynomial_d2", "polynomial_d3",
    "mpe", "rre", "aitken_diagnostic", "richardson",
])

"""
    attach_acceleration_metadata!(report::Dict{String,Any}, meta::Dict{String,Any})
        -> Dict{String,Any}

Additive Phase 32 extension — schema version remains 28.0. Merges
acceleration metadata under `report["acceleration"]` without modifying any
existing field. Multiple calls accumulate via `merge()` (later values win
for overlapping keys).

# Required keys in `meta`
- `accelerator::String` ∈ one of `{"trivial", "polynomial_d1", "polynomial_d2",
  "polynomial_d3", "mpe", "rre", "aitken_diagnostic", "richardson"}`

# Optional keys (from RESEARCH §4 — acceleration-specific metrics)
- `prediction_norm::Float64`
- `prediction_vs_prev_norm::Float64`
- `coefficient_max::Float64`          # max|γ| or max|c_j|; safeguard sentry
- `corrector_iters::Int`
- `corrector_iters_saved::Int`
- `j_opt_db_delta::Float64`
- `trust_gap_vs_naive::Int`
- `safeguard_passed::Bool`
- `safeguard_reason::String`
- `verdict::String` ∈ `{"WORTH_IT", "NOT_WORTH_IT", "INCONCLUSIVE"}`

# Raises
`ArgumentError` if `accelerator` is absent, not a String, or not a member of
the accepted enum.

# Example
```julia
attach_acceleration_metadata!(report, Dict{String,Any}(
    "accelerator"           => "polynomial_d2",
    "prediction_norm"       => 0.23,
    "coefficient_max"       => 1.4,
    "corrector_iters_saved" => 4,
    "j_opt_db_delta"        => 0.05,
    "verdict"               => "WORTH_IT",
))
```
"""
function attach_acceleration_metadata!(report::Dict{String,Any},
                                       meta::Dict{String,Any})
    haskey(meta, "accelerator") || throw(ArgumentError(
        "attach_acceleration_metadata!: missing required key `accelerator`"))
    accel = meta["accelerator"]
    accel isa AbstractString || throw(ArgumentError(
        "attach_acceleration_metadata!: `accelerator` must be a String, got $(typeof(accel))"))
    String(accel) in _ACCELERATION_ACCELERATORS || throw(ArgumentError(
        "attach_acceleration_metadata!: invalid accelerator `$(accel)`; expected one of $(collect(_ACCELERATION_ACCELERATORS))"))

    existing = get(report, "acceleration", Dict{String,Any}())
    report["acceleration"] = merge(existing, meta)
    return report
end

end  # include guard
