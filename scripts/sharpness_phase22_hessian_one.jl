"""
Compute the Hessian eigenspectrum for a single Phase 22 run record in an
isolated Julia process. This keeps Arpack crashes from taking down the threaded
optimization sweep.

Usage:
  julia -t 1 --project=. scripts/sharpness_phase22_hessian_one.jl <record.jld2>
"""

ENV["MPLBACKEND"] = "Agg"

using JLD2

include(joinpath(@__DIR__, "sharpness_phase22_lib.jl"))

function _resolve_op(record)
    ops = build_operating_points()
    if record["op_id"] == ops[:canonical].id
        return ops[:canonical]
    elseif record["op_id"] == ops[:pareto57].id
        return ops[:pareto57]
    else
        error("Unknown op_id $(record["op_id"])")
    end
end

function main()
    isempty(ARGS) && error("usage: sharpness_phase22_hessian_one.jl <record.jld2>")
    path = ARGS[1]
    record = JLD2.load(path)["record"]
    get(record, "failed", false) && return path
    record["record_path"] = path
    op = _resolve_op(record)
    attach_hessian!(record, op)
    return path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
