"""
Collect per-run Phase 22 records into a consolidated bundle.

Usage:
  julia --project=. scripts/research/sharpness/collect.jl
"""

ENV["MPLBACKEND"] = "Agg"

using Dates
using JLD2

include(joinpath(@__DIR__, "lib.jl"))

function _load_run_records()
    paths = sort(filter(p -> endswith(p, ".jld2"), readdir(S22_RUNS_DIR; join=true)))
    return [JLD2.load(path)["record"] for path in paths]
end

function main()
    mkpath(S22_RESULTS_DIR)
    records = _load_run_records()
    out_path = joinpath(S22_RESULTS_DIR, "phase22_results.jld2")
    jldsave(out_path;
        version = S22_VERSION,
        created_at = string(Dates.now()),
        smoke_mode = false,
        records = records,
        image_dir = S22_IMAGES_DIR,
        julia_nthreads = Threads.nthreads(),
        fftw_nthreads = FFTW.get_num_threads(),
        blas_nthreads = BLAS.get_num_threads(),
    )
    @info "Phase 22 bundle collected" path=out_path n_records=length(records)
    return out_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
