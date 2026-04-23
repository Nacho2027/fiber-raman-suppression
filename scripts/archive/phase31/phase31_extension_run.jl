#!/usr/bin/env julia
# scripts/extension_run.jl — Phase 31 follow-up continuation/refinement
#
# Compare a small set of reduced-basis continuation paths extended with a
# final full-grid refinement. This is the direct follow-up to Phase 31's main
# positive result: continuation through a reduced basis reaches a much deeper
# basin than zero-init full-grid L-BFGS.
#
# Invocation:
#   julia -t auto --project=. scripts/extension_run.jl
#   julia -t auto --project=. scripts/extension_run.jl --dry-run

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end

using Printf
using LinearAlgebra
using JLD2
using Dates
using JSON3
using Optim

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "sweep_simple_param.jl"))
include(joinpath(@__DIR__, "basis_lib.jl"))
include(joinpath(@__DIR__, "penalty_lib.jl"))
include(joinpath(@__DIR__, "transfer.jl"))
include(joinpath(@__DIR__, "run.jl"))
include(joinpath(@__DIR__, "extension_lib.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

const P31X_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase31", "followup")
const P31X_IMAGES_DIR  = joinpath(P31X_RESULTS_DIR, "images")
const P31X_RUN_TAG     = Dates.format(now(), "yyyymmdd_HHMMSS")
const P31X_PATHS       = p31x_default_path_program()
const P31X_MAX_ITER_BASIS = 80
const P31X_MAX_ITER_FULL  = 80

mkpath(P31X_RESULTS_DIR)
mkpath(P31X_IMAGES_DIR)

function p31x_setup_canonical()
    return setup_raman_problem(;
        fiber_preset = P31_CANONICAL.fiber_preset,
        β_order      = 3,
        L_fiber      = P31_CANONICAL.L_fiber,
        P_cont       = P31_CANONICAL.P_cont,
        Nt           = P31_NT,
        time_window  = P31_TIME_WINDOW,
    )
end

function p31x_emit_standard_images(phi_vec::AbstractVector{<:Real},
                                    uω0, fiber, sim, band_mask, Δf, raman_threshold;
                                    tag::AbstractString,
                                    dry_run::Bool)
    dry_run && return
    try
        save_standard_set(reshape(phi_vec, sim["Nt"], 1), uω0, fiber, sim,
                          band_mask, Δf, raman_threshold;
                          tag = tag,
                          fiber_name = String(P31_CANONICAL.fiber_preset),
                          L_m = P31_CANONICAL.L_fiber,
                          P_W = P31_CANONICAL.P_cont,
                          output_dir = P31X_IMAGES_DIR)
    catch e
        @warn "standard image emission failed" tag=tag error=sprint(showerror, e)
    end
    try
        if isdefined(Main, :PyPlot)
            Base.invokelatest(Main.PyPlot.close, "all")
        end
    catch
    end
    GC.gc()
end

function p31x_run_basis_step(phi_init::AbstractVector{<:Real},
                              step::NamedTuple,
                              uω0, fiber, sim, band_mask, bw_mask;
                              dry_run::Bool)
    Nt = sim["Nt"]
    B = build_basis_dispatch(step.kind, Nt, step.N_phi, bw_mask, sim)
    c0 = p31x_project_phi_to_basis(phi_init, B)
    if dry_run
        return Dict{String,Any}(
            "mode" => "basis",
            "kind" => String(step.kind),
            "N_phi" => step.N_phi,
            "phi_opt" => collect(phi_init),
            "J_final" => NaN,
            "iterations" => 0,
            "converged" => true,
            "wall_time_s" => 0.0,
        )
    end

    fiber_local = deepcopy(fiber)
    t0 = time()
    r = optimize_phase_lowres(uω0, fiber_local, sim, band_mask;
                              N_phi = step.N_phi,
                              kind = step.kind,
                              bandwidth_mask = bw_mask,
                              c0 = c0,
                              B_precomputed = B,
                              max_iter = P31X_MAX_ITER_BASIS,
                              log_cost = true)
    wall = time() - t0
    return Dict{String,Any}(
        "mode" => "basis",
        "kind" => String(step.kind),
        "N_phi" => step.N_phi,
        "phi_opt" => collect(vec(r.phi_opt)),
        "c_opt" => collect(vec(r.c_opt)),
        "J_final" => r.J_final,
        "iterations" => r.iterations,
        "converged" => r.converged,
        "wall_time_s" => wall,
    )
end

function p31x_run_full_step(phi_init::AbstractVector{<:Real},
                             uω0, fiber, sim, band_mask, bw_mask;
                             dry_run::Bool)
    Nt = sim["Nt"]
    if dry_run
        return Dict{String,Any}(
            "mode" => "full",
            "kind" => "identity",
            "N_phi" => Nt,
            "phi_opt" => collect(phi_init),
            "J_final" => NaN,
            "J_raman_linear" => NaN,
            "J_penalty_linear" => 0.0,
            "iterations" => 0,
            "converged" => true,
            "wall_time_s" => 0.0,
        )
    end

    fiber_local = deepcopy(fiber)
    fiber_local["zsave"] = nothing
    phi0 = collect(phi_init)

    f_g! = Optim.only_fg!() do F, G, φ_vec
        J_dB, grad_vec, _, _ = phase31_b_cost_and_gradient(
            φ_vec, uω0, fiber_local, sim, band_mask, bw_mask;
            penalty_name = :none, λ = 0.0, B_dct_cache = nothing)
        if G !== nothing
            copyto!(G, grad_vec)
        end
        return J_dB
    end

    t0 = time()
    opt_res = Optim.optimize(f_g!, phi0, LBFGS(),
                             Optim.Options(f_abstol = 0.01,
                                           iterations = P31X_MAX_ITER_FULL,
                                           show_trace = false))
    wall = time() - t0
    phi_opt = collect(Optim.minimizer(opt_res))
    _, _, J_raman_linear, J_penalty_linear = phase31_b_cost_and_gradient(
        phi_opt, uω0, fiber_local, sim, band_mask, bw_mask;
        penalty_name = :none, λ = 0.0, B_dct_cache = nothing)

    return Dict{String,Any}(
        "mode" => "full",
        "kind" => "identity",
        "N_phi" => Nt,
        "phi_opt" => phi_opt,
        "J_final" => Optim.minimum(opt_res),
        "J_raman_linear" => J_raman_linear,
        "J_penalty_linear" => J_penalty_linear,
        "iterations" => Optim.iterations(opt_res),
        "converged" => Optim.converged(opt_res),
        "wall_time_s" => wall,
    )
end

function p31x_transfer_summary(phi_vec::AbstractVector{<:Real},
                                J_canonical_dB::Real,
                                canonical_setup,
                                hnlf_setup,
                                perturb_setups)
    (uω0_can, fiber_can, sim_can, bm_can, _, _) = canonical_setup
    (uω0_hn, fiber_hn, sim_hn, bm_hn, _, _) = hnlf_setup

    fiber_hn_local = deepcopy(fiber_hn)
    fiber_hn_local["zsave"] = nothing
    J_hnlf = 10.0 * log10(max(
        evaluate_J_linear(phi_vec, uω0_hn, fiber_hn_local, sim_hn, bm_hn), 1e-15))

    J_perturb = Dict{String,Float64}()
    for (label, (setup_tup, _status)) in perturb_setups
        (uω0_p, fiber_p, sim_p, bm_p, _, _) = setup_tup
        fiber_p_local = deepcopy(fiber_p)
        fiber_p_local["zsave"] = nothing
        J_lin = evaluate_J_linear(phi_vec, uω0_p, fiber_p_local, sim_p, bm_p)
        J_perturb[label] = 10.0 * log10(max(J_lin, 1e-15))
    end

    fiber_can_local = deepcopy(fiber_can)
    fiber_can_local["zsave"] = nothing
    sigma_3dB = estimate_sigma_3dB(phi_vec, J_canonical_dB,
                                   uω0_can, fiber_can_local, sim_can, bm_can)

    return Dict{String,Any}(
        "J_transfer_HNLF" => J_hnlf,
        "J_transfer_perturb" => J_perturb,
        "sigma_3dB" => sigma_3dB,
    )
end

function p31x_path_seed_phi(path::NamedTuple, sweep_A_rows::AbstractVector)
    seed = path.seed
    if seed.mode == :zero
        return nothing, Dict{String,Any}(
            "seed_source" => "zero",
            "seed_kind" => "zero",
            "seed_N_phi" => 0,
            "seed_J_final" => NaN,
        )
    elseif seed.mode == :phase31_row
        row = p31x_find_basis_row(sweep_A_rows, seed.branch, seed.kind, seed.N_phi)
        return Float64.(row["phi_opt"]), Dict{String,Any}(
            "seed_source" => "phase31_row",
            "seed_kind" => String(seed.kind),
            "seed_N_phi" => Int(seed.N_phi),
            "seed_J_final" => Float64(row["J_final"]),
        )
    else
        error("unknown seed mode $(seed.mode)")
    end
end

function p31x_run_path(path::NamedTuple,
                        sweep_A_rows::AbstractVector,
                        canonical_setup,
                        hnlf_setup,
                        perturb_setups;
                        dry_run::Bool)
    (uω0, fiber, sim, band_mask, Δf, raman_threshold) = canonical_setup
    bw_mask = pulse_bandwidth_mask(uω0)

    phi_curr, seed_meta = p31x_path_seed_phi(path, sweep_A_rows)
    if phi_curr === nothing
        phi_curr = zeros(Float64, sim["Nt"])
    end

    step_rows = Dict{String,Any}[]
    for (idx, step) in enumerate(path.steps)
        label = p31x_step_label(step)
        if step.mode == :basis
            row = p31x_run_basis_step(phi_curr, step, uω0, fiber, sim, band_mask, bw_mask;
                                      dry_run = dry_run)
        elseif step.mode == :full
            row = p31x_run_full_step(phi_curr, uω0, fiber, sim, band_mask, bw_mask;
                                     dry_run = dry_run)
        else
            error("unknown step mode $(step.mode)")
        end
        row["step_index"] = idx
        row["step_label"] = label
        push!(step_rows, row)
        phi_curr = Float64.(row["phi_opt"])
        p31x_emit_standard_images(phi_curr, uω0, fiber, sim, band_mask, Δf, raman_threshold;
                                  tag = "p31x_$(path.name)_step$(idx)_$(label)",
                                  dry_run = dry_run)
    end

    final_row = step_rows[end]
    transfer = dry_run ? Dict{String,Any}(
        "J_transfer_HNLF" => NaN,
        "J_transfer_perturb" => Dict{String,Float64}(),
        "sigma_3dB" => NaN,
    ) : p31x_transfer_summary(phi_curr, Float64(final_row["J_final"]),
                              canonical_setup, hnlf_setup, perturb_setups)

    return Dict{String,Any}(
        "run_tag" => P31X_RUN_TAG,
        "path_name" => path.name,
        "description" => path.description,
        "seed_meta" => seed_meta,
        "steps" => step_rows,
        "final_phi_opt" => collect(phi_curr),
        "final_J_dB" => final_row["J_final"],
        "final_iterations" => final_row["iterations"],
        "final_converged" => final_row["converged"],
        "sigma_3dB" => transfer["sigma_3dB"],
        "J_transfer_HNLF" => transfer["J_transfer_HNLF"],
        "J_transfer_perturb" => transfer["J_transfer_perturb"],
        "depth_gain_vs_seed_dB" => isnan(seed_meta["seed_J_final"]) ? NaN :
            Float64(seed_meta["seed_J_final"]) - Float64(final_row["J_final"]),
    )
end

function run_phase31_extension(; dry_run::Bool = false)
    t0 = time()
    @info "Phase 31 extension — continuation/refinement paths" dry_run=dry_run paths=length(P31X_PATHS)

    sweep_A_path = joinpath(P31_RESULTS_DIR, "sweep_A_basis.jld2")
    sweep_A_rows = p31x_load_rows(sweep_A_path)
    isempty(sweep_A_rows) && error("missing Phase 31 Branch A results at $sweep_A_path")

    canonical_setup = p31x_setup_canonical()
    hnlf_setup = setup_raman_problem_hnlf()
    perturb_setups = Dict{String,Any}()
    for label in keys(P31T_PERTURB_CONFIGS)
        perturb_setups[label] = setup_raman_problem_perturbed(label)
    end

    save_path = dry_run ?
        joinpath(P31X_RESULTS_DIR, "path_comparison_dryrun.jld2") :
        joinpath(P31X_RESULTS_DIR, "path_comparison.jld2")
    completed = Dict{String,Any}[]
    done_names = Set{String}()
    if !dry_run && isfile(save_path)
        try
            completed = JLD2.load(save_path, "rows")
            for row in completed
                push!(done_names, row["path_name"])
            end
            @info "resume loaded" rows=length(completed) path=save_path
        catch e
            @warn "resume load failed; starting fresh" error=sprint(showerror, e)
        end
    end

    rows = copy(completed)
    for path in P31X_PATHS
        if path.name in done_names
            @info "resume skip" path=path.name
            continue
        end
        @info "running path" path=path.name description=path.description
        row = p31x_run_path(path, sweep_A_rows, canonical_setup, hnlf_setup, perturb_setups;
                            dry_run = dry_run)
        push!(rows, row)
        JLD2.jldsave(save_path; rows = rows, run_tag = P31X_RUN_TAG)
        @info "path complete" path=path.name J_final=row["final_J_dB"] sigma_3dB=row["sigma_3dB"] J_HNLF=row["J_transfer_HNLF"]
        dry_run && break
    end

    manifest = Dict(
        "run_tag" => P31X_RUN_TAG,
        "julia_version" => string(VERSION),
        "threads" => Threads.nthreads(),
        "dry_run" => dry_run,
        "paths" => [Dict("name" => p.name, "description" => p.description) for p in P31X_PATHS],
        "rows_saved" => length(rows),
        "wall_time_s" => time() - t0,
    )
    manifest_path = joinpath(P31X_RESULTS_DIR, "manifest_followup_$(P31X_RUN_TAG).json")
    open(manifest_path, "w") do io
        JSON3.pretty(io, manifest)
    end
    @info "manifest written" path=manifest_path
    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    dry_run = any(a -> a == "--dry-run", ARGS)
    run_phase31_extension(; dry_run = dry_run)
end
