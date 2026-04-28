"""
Validate a completed live-demo run without pretending it is a canonical final run.

Usage:
    julia -t auto --project=. scripts/canonical/demo_run_check.jl --latest [spec]
    julia -t auto --project=. scripts/canonical/demo_run_check.jl --run RUN_DIR_OR_ARTIFACT

Options:
    --min-delta-db VALUE    Require delta_J_dB <= VALUE. Default: -20.0
    --no-export             Do not require export_handoff completeness.
    --help                  Show this message.
"""

include(joinpath(@__DIR__, "..", "lib", "experiment_runner.jl"))
include(joinpath(@__DIR__, "inspect_run.jl"))

const DEFAULT_DEMO_SPEC = "research_engine_live_demo"
const DEFAULT_DEMO_MIN_DELTA_DB = -20.0

function _demo_run_check_usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/demo_run_check.jl --latest [spec]
    julia -t auto --project=. scripts/canonical/demo_run_check.jl --run RUN_DIR_OR_ARTIFACT

Options:
    --min-delta-db VALUE    Require delta_J_dB <= VALUE. Default: -20.0
    --no-export             Do not require export_handoff completeness.
    --help                  Show this message.
"""
end

function parse_demo_run_check_args(args)
    mode = :latest
    target = DEFAULT_DEMO_SPEC
    min_delta_db = DEFAULT_DEMO_MIN_DELTA_DB
    require_export = true

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            return (help = true,)
        elseif arg == "--latest"
            mode = :latest
            if i < length(args) && !startswith(args[i + 1], "-")
                i += 1
                target = args[i]
            end
        elseif arg == "--run"
            i += 1
            i <= length(args) || error("--run requires a run directory or artifact")
            mode = :run
            target = args[i]
        elseif arg == "--min-delta-db"
            i += 1
            i <= length(args) || error("--min-delta-db requires a value")
            parsed = tryparse(Float64, args[i])
            parsed === nothing && error("--min-delta-db must be numeric")
            min_delta_db = parsed
        elseif arg == "--no-export"
            require_export = false
        else
            error("unknown demo_run_check option: $arg")
        end
        i += 1
    end

    return (
        help = false,
        mode = mode,
        target = target,
        min_delta_db = min_delta_db,
        require_export = require_export,
    )
end

function _push_demo_blocker!(blockers, condition::Bool, label::AbstractString)
    condition || push!(blockers, String(label))
    return blockers
end

function _demo_run_target(parsed)
    if parsed.mode == :run
        return parsed.target
    elseif parsed.mode == :latest
        spec = load_experiment_spec(parsed.target)
        return latest_experiment_output_dir(spec)
    end
    error("unknown demo run check mode: $(parsed.mode)")
end

function demo_run_check_report(path::AbstractString;
                               min_delta_db::Real=DEFAULT_DEMO_MIN_DELTA_DB,
                               require_export::Bool=true)
    summary = inspect_run_summary(path)
    blockers = String[]

    _push_demo_blocker!(blockers, !ismissing(summary.run_config), "missing_run_config")
    _push_demo_blocker!(blockers, !isempty(summary.trust_reports), "missing_trust_report")
    _push_demo_blocker!(blockers, summary.standard_images.complete, "missing_standard_images")
    _push_demo_blocker!(blockers, isfinite(Float64(summary.J_after_dB)), "missing_objective_metric")
    _push_demo_blocker!(
        blockers,
        isfinite(Float64(summary.delta_J_dB)) && Float64(summary.delta_J_dB) <= Float64(min_delta_db),
        "insufficient_suppression_delta",
    )
    _push_demo_blocker!(blockers, summary.quality in ("GOOD", "EXCELLENT"), "weak_suppression_quality")

    if require_export
        if !summary.export_handoff.files_complete
            push!(blockers, "missing_export_handoff")
        elseif !summary.export_handoff.phase_csv_valid
            push!(blockers, "invalid_export_phase_csv")
        end
    end

    return (
        status = isempty(blockers) ? :pass : :fail,
        blockers = Tuple(blockers),
        artifact = summary.artifact,
        artifact_dir = summary.artifact_dir,
        run_config = summary.run_config,
        trust_reports = Tuple(summary.trust_reports),
        standard_images_complete = summary.standard_images.complete,
        export_handoff_complete = summary.export_handoff.complete,
        export_phase_csv_valid = summary.export_handoff.phase_csv_valid,
        export_phase_csv_rows = summary.export_handoff.phase_csv_rows,
        converged = summary.converged,
        iterations = summary.iterations,
        quality = summary.quality,
        J_before_dB = summary.J_before_dB,
        J_after_dB = summary.J_after_dB,
        delta_J_dB = summary.delta_J_dB,
        min_delta_db = Float64(min_delta_db),
    )
end

function render_demo_run_check_report(report; io::IO=stdout)
    println(io, "# Live Demo Run Check")
    println(io)
    println(io, "- Status: `", report.status == :pass ? "PASS" : "FAIL", "`")
    println(io, "- Blockers: `", isempty(report.blockers) ? "none" : join(report.blockers, ", "), "`")
    println(io, "- Artifact dir: `", report.artifact_dir, "`")
    println(io, "- Artifact: `", report.artifact, "`")
    println(io, "- Run config: `", report.run_config, "`")
    println(io, "- Trust reports: `", isempty(report.trust_reports) ? "none" : join(report.trust_reports, ", "), "`")
    println(io, "- Standard images complete: `", report.standard_images_complete, "`")
    println(io, "- Export handoff complete: `", report.export_handoff_complete, "`")
    println(io, "- Export phase CSV valid: `", report.export_phase_csv_valid, "`")
    println(io, "- Export phase CSV rows: `", report.export_phase_csv_rows, "`")
    println(io, "- Quality: `", report.quality, "`")
    println(io, "- J_before_dB: `", report.J_before_dB, "`")
    println(io, "- J_after_dB: `", report.J_after_dB, "`")
    println(io, "- Delta_J_dB: `", report.delta_J_dB, "`")
    println(io, "- Required delta_J_dB <= `", report.min_delta_db, "`")
    println(io, "- Optimizer converged: `", report.converged, "`")
    println(io, "- Optimizer iterations: `", report.iterations, "`")
    println(io)
    println(io, "Note: this demo check requires a meaningful short-run result and complete handoff artifacts.")
    println(io, "Use `lab_ready --latest ...` when you need strict canonical convergence certification.")
    return nothing
end

function demo_run_check_main(args=ARGS)
    parsed = parse_demo_run_check_args(args)
    if parsed.help
        print(_demo_run_check_usage())
        return nothing
    end

    path = _demo_run_target(parsed)
    report = demo_run_check_report(
        path;
        min_delta_db=parsed.min_delta_db,
        require_export=parsed.require_export,
    )
    render_demo_run_check_report(report)
    report.status == :pass || error("live demo run check failed: $(join(report.blockers, ", "))")
    return report
end

if abspath(PROGRAM_FILE) == @__FILE__
    demo_run_check_main(ARGS)
end
