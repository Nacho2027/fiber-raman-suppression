"""
Optional two-stage amplitude-on-phase refinement workflow.

Usage:
    julia -t auto --project=. scripts/canonical/refine_amp_on_phase.jl --dry-run
    julia -t auto --project=. scripts/canonical/refine_amp_on_phase.jl --tag my_run --L 2.0 --P 0.30 --export

This is an experimental second-stage workflow. It keeps phase-only optimization
as the canonical baseline, then runs bounded amplitude shaping on top of the
fixed phase solution and can export the amplitude-aware handoff bundle.
"""

using Dates
using Printf

include(joinpath(@__DIR__, "export_run.jl"))
include(joinpath(@__DIR__, "..", "lib", "amp_on_phase_refinement.jl"))

const REFINE_DEFAULT_TAG = Dates.format(now(UTC), "yyyymmddTHHMMSSZ")
const REFINE_API = "scripts/lib/amp_on_phase_refinement.jl"

function _refine_usage()
    return """
    usage: scripts/canonical/refine_amp_on_phase.jl [options]

    Options:
      --dry-run              Print the plan and command without running compute.
      --export               Export amp_on_phase_result.jld2 after a successful run.
      --tag TAG              Result tag suffix. Output goes to results/raman/multivar/amp_on_phase_TAG.
      --L METERS             Fiber length in meters. Default: 2.0.
      --P WATTS              Continuous-wave power in watts. Default: 0.30.
      --phase-iter N         Phase-only stage iteration cap. Default: 50.
      --amp-iter N           Amplitude stage iteration cap. Default: 60.
      --delta-bound X        Amplitude tanh bound. Default: 0.10.
      --threshold-db X       Pass/fail improvement threshold in dB. Default: 3.0.
      --help                 Show this help text.
    """
end

function parse_refine_amp_on_phase_args(args=ARGS)
    opts = Dict{Symbol,Any}(
        :dry_run => false,
        :export => false,
        :tag => REFINE_DEFAULT_TAG,
        :L => 2.0,
        :P => 0.30,
        :phase_iter => 50,
        :amp_iter => 60,
        :delta_bound => 0.10,
        :threshold_db => 3.0,
    )

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            opts[:help] = true
            i += 1
        elseif arg == "--dry-run"
            opts[:dry_run] = true
            i += 1
        elseif arg == "--export"
            opts[:export] = true
            i += 1
        elseif arg in ("--tag", "--L", "--P", "--phase-iter", "--amp-iter", "--delta-bound", "--threshold-db")
            i == length(args) && throw(ArgumentError("missing value for $arg"))
            value = args[i + 1]
            if arg == "--tag"
                opts[:tag] = value
            elseif arg == "--L"
                opts[:L] = parse(Float64, value)
            elseif arg == "--P"
                opts[:P] = parse(Float64, value)
            elseif arg == "--phase-iter"
                opts[:phase_iter] = parse(Int, value)
            elseif arg == "--amp-iter"
                opts[:amp_iter] = parse(Int, value)
            elseif arg == "--delta-bound"
                opts[:delta_bound] = parse(Float64, value)
            elseif arg == "--threshold-db"
                opts[:threshold_db] = parse(Float64, value)
            end
            i += 2
        else
            throw(ArgumentError("unknown argument `$arg`\n$(_refine_usage())"))
        end
    end

    return (; pairs(opts)...)
end

function refine_amp_on_phase_output_dir(opts)
    return joinpath("results", "raman", "multivar", string("amp_on_phase_", opts.tag))
end

function refine_amp_on_phase_plan(opts)
    output_dir = refine_amp_on_phase_output_dir(opts)
    artifact = joinpath(output_dir, "amp_on_phase_result.jld2")
    export_dir = joinpath(output_dir, "export_handoff")
    return (
        tag = String(opts.tag),
        L_m = Float64(opts.L),
        P_cont_W = Float64(opts.P),
        phase_iter = Int(opts.phase_iter),
        amp_iter = Int(opts.amp_iter),
        delta_bound = Float64(opts.delta_bound),
        threshold_db = Float64(opts.threshold_db),
        output_dir = output_dir,
        summary = joinpath(output_dir, "amp_on_phase_summary.md"),
        artifact = artifact,
        export_dir = export_dir,
        export_requested = Bool(opts.export),
        command = "run_amp_on_phase_refinement(...) via $REFINE_API",
    )
end

function render_refine_amp_on_phase_plan(plan; io::IO=stdout)
    println(io, "Amp-on-phase second-stage refinement")
    println(io, "Status: experimental optional workflow, not the canonical lab default")
    println(io, "Point: SMF-28 L=", @sprintf("%.3g", plan.L_m), " m P=", @sprintf("%.3g", plan.P_cont_W), " W")
    println(io, "Amplitude bound: delta=", @sprintf("%.3g", plan.delta_bound),
        " threshold=", @sprintf("%.3g", plan.threshold_db), " dB")
    println(io, "Iterations: phase=", plan.phase_iter, " amp=", plan.amp_iter)
    println(io, "Output directory: ", plan.output_dir)
    println(io, "Summary: ", plan.summary)
    println(io, "Amp artifact: ", plan.artifact)
    println(io, "Command: ", plan.command)
    if plan.export_requested
        println(io, "Export after run: ", plan.export_dir)
    else
        println(io, "Export after run: disabled; pass --export to generate export_handoff")
    end
    println(io, "Required closeout: inspect standard images before lab handoff.")
end

function refine_amp_on_phase_main(args=ARGS)
    opts = parse_refine_amp_on_phase_args(args)
    if hasproperty(opts, :help) && opts.help
        print(_refine_usage())
        return nothing
    end

    plan = refine_amp_on_phase_plan(opts)
    render_refine_amp_on_phase_plan(plan)
    opts.dry_run && return plan

    run_result = run_amp_on_phase_refinement(
        tag = opts.tag,
        output_dir = plan.output_dir,
        phase_iter = opts.phase_iter,
        amp_iter = opts.amp_iter,
        threshold_db = opts.threshold_db,
        delta_bound = opts.delta_bound,
        L_fiber = opts.L,
        P_cont = opts.P,
    )

    isfile(plan.summary) || throw(ArgumentError("refinement summary missing: $(plan.summary)"))
    isfile(plan.artifact) || throw(ArgumentError("refinement artifact missing: $(plan.artifact)"))

    exported = nothing
    if opts.export
        exported = export_run_bundle(plan.artifact, plan.export_dir)
        @info "Exported amp-on-phase handoff bundle" output_dir=exported.output_dir
    end

    println()
    println("Refinement complete")
    println("Review summary: ", plan.summary)
    println("Inspect images under: ", plan.output_dir)
    if exported !== nothing
        println("Export handoff: ", exported.output_dir)
    else
        println("Optional export command:")
        println("  julia --project=. scripts/canonical/export_run.jl ", plan.artifact, " ", plan.export_dir)
    end
    return exported === nothing ? (; plan..., result=run_result) : (; plan..., result=run_result, exported=exported)
end

if abspath(PROGRAM_FILE) == @__FILE__
    refine_amp_on_phase_main(ARGS)
end
