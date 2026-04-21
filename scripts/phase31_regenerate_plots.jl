# scripts/phase31_regenerate_plots.jl
#
# Regenerate the 4-image standard set for every Branch A + Branch B optimum
# in Phase 31. Uses tighter x-axis defaults (now in scripts/visualization.jl)
# plus denser z-sampling (200 frames vs default 32) so the waterfall plots
# read cleanly.
#
# No re-optimization — reads phi_opt from the saved JLD2 rows and calls
# save_standard_set with tighter settings.
#
# Invocation:
#   julia -t auto --project=. scripts/phase31_regenerate_plots.jl
# Optional: --only=A or --only=B to regenerate one branch.
# Optional: --n_z=N to override the 200-sample z-resolution.

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end

using Printf
using LinearAlgebra
using FFTW
using Random
using Statistics
using JLD2
using Dates
using PyPlot

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

const P31R_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase31")
const P31R_NT          = 2^14
const P31R_TIME_WINDOW = 10.0
const P31R_CANONICAL   = (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2)

function regenerate_branch(branch::String, rows::Vector, setup::Tuple;
                            n_z_samples::Int, images_dir::AbstractString,
                            fiber_name::AbstractString, L_m::Real, P_W::Real)
    (uω0, fiber, sim, band_mask, Δf, raman_threshold) = setup
    mkpath(images_dir)

    for (i, r) in enumerate(rows)
        phi_vec = Float64.(r["phi_opt"])
        @assert length(phi_vec) == sim["Nt"]
        phi_matrix = reshape(phi_vec, sim["Nt"], 1)

        tag = if branch == "A"
            @sprintf("p31A_%s_N%03d", String(r["kind"]), r["N_phi"])
        else
            @sprintf("p31B_%s_lam%.0e", String(r["penalty_name"]), Float64(r["lambda"]))
        end

        t0 = time()
        try
            save_standard_set(phi_matrix, uω0, fiber, sim,
                              band_mask, Δf, raman_threshold;
                              tag = tag,
                              fiber_name = fiber_name,
                              L_m = L_m, P_W = P_W,
                              output_dir = images_dir,
                              n_z_samples = n_z_samples,
                              also_unshaped = (i == 1))  # only emit unshaped once
        catch e
            @warn "save_standard_set failed" branch=branch tag=tag error=sprint(showerror, e)
        end
        wall = time() - t0
        @info @sprintf("[%s %d/%d] %s  wall=%.1fs",
                       branch, i, length(rows), tag, wall)

        # PyPlot/PyCall cleanup between rows to avoid the accumulating-handle
        # segfault observed in Branch A.
        try
            Base.invokelatest(PyPlot.close, "all")
        catch
        end
        GC.gc()
    end
end

function main()
    only_branch = ""
    n_z_samples = 200
    for arg in ARGS
        if startswith(arg, "--only=")
            only_branch = arg[length("--only=") + 1:end]
        elseif startswith(arg, "--n_z=")
            n_z_samples = parse(Int, arg[length("--n_z=") + 1:end])
        end
    end

    t_total = time()
    @info "Phase 31 regenerate plots" n_z_samples=n_z_samples only=only_branch threads=Threads.nthreads()

    # Canonical problem setup (both branches share this)
    setup = setup_raman_problem(;
        fiber_preset = P31R_CANONICAL.fiber_preset,
        β_order      = 3,
        L_fiber      = P31R_CANONICAL.L_fiber,
        P_cont       = P31R_CANONICAL.P_cont,
        Nt           = P31R_NT,
        time_window  = P31R_TIME_WINDOW,
    )

    if only_branch != "B"
        # Branch A — sweep_A_basis.jld2 → sweep_A/images/
        sweep_A = joinpath(P31R_RESULTS_DIR, "sweep_A_basis.jld2")
        if isfile(sweep_A)
            rows_A = JLD2.load(sweep_A, "rows")
            @info "Regenerating Branch A plots" rows=length(rows_A) file=sweep_A
            regenerate_branch("A", rows_A, setup;
                               n_z_samples = n_z_samples,
                               images_dir = joinpath(P31R_RESULTS_DIR, "sweep_A", "images"),
                               fiber_name = String(P31R_CANONICAL.fiber_preset),
                               L_m = P31R_CANONICAL.L_fiber,
                               P_W = P31R_CANONICAL.P_cont)
        else
            @warn "sweep_A_basis.jld2 missing — skipping Branch A" path=sweep_A
        end
    end

    if only_branch != "A"
        # Branch B — sweep_B_penalty.jld2 → sweep_B/images/
        sweep_B = joinpath(P31R_RESULTS_DIR, "sweep_B_penalty.jld2")
        if isfile(sweep_B)
            rows_B = JLD2.load(sweep_B, "rows")
            @info "Regenerating Branch B plots" rows=length(rows_B) file=sweep_B
            regenerate_branch("B", rows_B, setup;
                               n_z_samples = n_z_samples,
                               images_dir = joinpath(P31R_RESULTS_DIR, "sweep_B", "images"),
                               fiber_name = String(P31R_CANONICAL.fiber_preset),
                               L_m = P31R_CANONICAL.L_fiber,
                               P_W = P31R_CANONICAL.P_cont)
        else
            @warn "sweep_B_penalty.jld2 missing — skipping Branch B" path=sweep_B
        end
    end

    @info @sprintf("regenerate complete (%.1fs total)", time() - t_total)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
