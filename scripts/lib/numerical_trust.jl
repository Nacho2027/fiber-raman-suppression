using Dates
using Printf

include(joinpath(@__DIR__, "objective_surface.jl"))

if !(@isdefined _NUMERICAL_TRUST_JL_LOADED)
const _NUMERICAL_TRUST_JL_LOADED = true

const NUMERICAL_TRUST_SCHEMA_VERSION = "1.0"

const TRUST_THRESHOLDS = (
    energy_drift_pass = 1e-4,
    energy_drift_marginal = 1e-3,
    edge_frac_pass = 1e-3,
    edge_frac_marginal = 1e-2,
    gradcheck_pass = 5e-2,
    gradcheck_marginal = 1e-1,
)

const _TRUST_RANK = Dict("PASS" => 0, "MARGINAL" => 1, "SUSPECT" => 2, "NOT_RUN" => 3)
const _TRUST_VERDICTS = Tuple(keys(_TRUST_RANK))

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

function _trust_report_verdict(report)
    value = if report isa AbstractDict
        haskey(report, "overall_verdict") ? report["overall_verdict"] :
            haskey(report, :overall_verdict) ? report[:overall_verdict] : nothing
    elseif hasproperty(report, :overall_verdict)
        getproperty(report, :overall_verdict)
    else
        nothing
    end
    isnothing(value) && return nothing
    verdict = uppercase(String(value))
    return verdict in _TRUST_VERDICTS ? verdict : nothing
end

function _trust_markdown_verdict(path::AbstractString)
    isfile(path) || return nothing
    for line in eachline(path)
        match_result = match(r"Overall verdict:\s*\*{0,2}([A-Za-z_]+)", line)
        isnothing(match_result) || return _trust_report_verdict(
            Dict("overall_verdict" => match_result.captures[1]))
    end
    return nothing
end

"""
    trust_readiness(source; required=true)

Evaluate one numerical-trust report, or a collection of report paths. Only a
valid `PASS` verdict is comparison-ready. Missing optional evidence is neutral;
missing required evidence and all non-pass or malformed verdicts fail closed.
"""
function trust_readiness(source; required::Bool=true)
    items = if isnothing(source) || ismissing(source)
        Any[]
    elseif source isa AbstractVector || source isa Tuple
        collect(source)
    else
        Any[source]
    end

    isempty(items) && return required ?
        (pass=false, verdict="NOT_RUN", blocker="missing_trust_report", report_paths=String[]) :
        (pass=true, verdict="NOT_REQUIRED", blocker="", report_paths=String[])

    verdicts = String[]
    report_paths = String[]
    for item in items
        verdict = if item isa AbstractString
            path = String(item)
            push!(report_paths, path)
            _trust_markdown_verdict(path)
        else
            _trust_report_verdict(item)
        end
        isnothing(verdict) && return (
            pass=false,
            verdict="INVALID",
            blocker="invalid_trust_report",
            report_paths=report_paths,
        )
        push!(verdicts, verdict)
    end

    verdict = worst_trust_verdict(verdicts)
    return (
        pass = verdict == "PASS",
        verdict = verdict,
        blocker = verdict == "PASS" ? "" : string("trust_verdict_", lowercase(verdict)),
        report_paths = report_paths,
    )
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
    gradient_required::Bool=false,
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
            "included_in_overall" => gradient_required,
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
            "included_in_overall" => true,
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
            boundary_penalty_measurement = "raw temporal edge fraction of shaped input pulse",
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

    overall_verdicts = String[
        det_block["verdict"],
        boundary_verdict,
        energy_verdict,
        cost_surface_block["verdict"],
    ]
    grad_block["included_in_overall"] && push!(overall_verdicts, grad_block["verdict"])
    report["overall_verdict"] = worst_trust_verdict(overall_verdicts)
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
        println(io, @sprintf("- Included in overall verdict: `%s`", string(grad["included_in_overall"])))
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
    end
    return path
end

end  # include guard
