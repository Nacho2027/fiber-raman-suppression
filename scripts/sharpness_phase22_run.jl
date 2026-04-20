"""
Phase 22 production runner.

Usage:
  julia -t 8 --project=. scripts/sharpness_phase22_run.jl
  julia -t 8 --project=. scripts/sharpness_phase22_run.jl --smoke
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using Dates
using JLD2
using Base.Threads: @threads

include(joinpath(@__DIR__, "sharpness_phase22_lib.jl"))

const S22R_SMOKE = any(==("--smoke"), ARGS)

function _smoke_subset(tasks)
    keep = NamedTuple[]
    seen_plain = Set{Symbol}()
    for task in tasks
        if task.flavor === :plain && !(task.op_key in seen_plain)
            push!(keep, task)
            push!(seen_plain, task.op_key)
        elseif task.op_key === :canonical && task.flavor === :trace && task.strength == S22_TRACE_LAMBDAS[1]
            push!(keep, task)
        elseif task.op_key === :pareto57 && task.flavor === :mc && task.strength == S22_MC_SIGMAS[1]
            push!(keep, task)
        end
    end
    return keep
end

function _run_baselines(ops, tasks)
    base = Dict{Symbol, Dict{String, Any}}()
    for task in tasks
        task.flavor === :plain || continue
        op = ops[task.op_key]
        @info "Running baseline" op=op.id seed=task.seed
        rec = run_record(op, task.flavor, task.strength, op.x_seed, task.seed;
                         max_iter = S22R_SMOKE ? 8 : S22_MAX_ITER,
                         log_cost = true)
        base[task.op_key] = rec
    end
    return base
end

function _run_flavors(ops, tasks, baselines)
    prod = [t for t in tasks if t.flavor != :plain]
    records = Vector{Union{Nothing, Dict{String, Any}}}(undef, length(prod))
    @info "Launching threaded sweep" n_tasks=length(prod) nthreads=Threads.nthreads()
    @threads for i in 1:length(prod)
        task = prod[i]
        op = ops[task.op_key]
        x0 = baselines[task.op_key]["x_opt"]
        try
            @info "Task start" idx=i op=op.id flavor=String(task.flavor) strength=task.strength
            records[i] = run_record(op, task.flavor, task.strength, x0, task.seed;
                                    max_iter = S22R_SMOKE ? 8 : S22_MAX_ITER,
                                    log_cost = true)
            @info "Task done" idx=i tag=records[i]["tag"] J_plain_dB=records[i]["J_plain_dB"] sigma_3dB=records[i]["sigma_3dB"]
        catch e
            bt = sprint(showerror, e, catch_backtrace())
            @warn "Task failed" idx=i op=op.id flavor=String(task.flavor) strength=task.strength exception=(e, catch_backtrace())
            tag = run_tag(op, task.flavor, task.strength)
            fail = Dict{String, Any}(
                "version" => S22_VERSION,
                "created_at" => string(Dates.now()),
                "tag" => tag,
                "op_id" => op.id,
                "op_label" => op.label,
                "flavor" => String(task.flavor),
                "strength" => task.strength,
                "seed" => task.seed,
                "failed" => true,
                "error" => bt,
            )
            out_path = joinpath(S22_RUNS_DIR, "$(tag).jld2")
            jldsave(out_path; record=fail)
            fail["record_path"] = out_path
            records[i] = fail
        end
    end
    return [r for r in records if r !== nothing]
end

function _emit_images(records, ops)
    for rec in records
        get(rec, "failed", false) && continue
        op_key = rec["op_id"] == ops[:canonical].id ? :canonical : :pareto57
        try
            emit_standard_images(rec, ops[op_key])
            @info "Standard images saved" tag=rec["tag"] dir=S22_IMAGES_DIR
        catch e
            @warn "save_standard_set failed" tag=rec["tag"] exception=(e, catch_backtrace())
        end
    end
    return nothing
end

function main()
    ops, tasks = build_task_grid()
    if S22R_SMOKE
        tasks = _smoke_subset(tasks)
        @info "Smoke mode enabled" n_tasks=length(tasks)
    end

    baselines = _run_baselines(ops, tasks)
    records = vcat(collect(values(baselines)), _run_flavors(ops, tasks, baselines))
    _emit_images(records, ops)

    out_path = joinpath(S22_RESULTS_DIR, S22R_SMOKE ? "phase22_results_smoke.jld2" : "phase22_results.jld2")
    jldsave(out_path;
        version = S22_VERSION,
        created_at = string(Dates.now()),
        smoke_mode = S22R_SMOKE,
        records = records,
        image_dir = S22_IMAGES_DIR,
        julia_nthreads = Threads.nthreads(),
        fftw_nthreads = FFTW.get_num_threads(),
        blas_nthreads = BLAS.get_num_threads(),
    )
    @info "Phase 22 results written" path=out_path n_records=length(records)
    return out_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
