#!/usr/bin/env julia
"""
Phase 21 — recover Sweep-1 on an honest grid.
"""

ENV["MPLBACKEND"] = "Agg"

using Dates
using JLD2
using Printf
using Logging
using Base.Threads

include(joinpath(@__DIR__, "recovery_common.jl"))
include(joinpath(@__DIR__, "sweep_simple_param.jl"))

const SWEEP1_SOURCE = joinpath(@__DIR__, "..", "results", "raman", "phase_sweep_simple", "sweep1_Nphi.jld2")
const SWEEP1_RESULTS_DIR = recovery_result_path("sweep1")
const SWEEP1_BASE_LEVELS = [4, 8, 16, 32, 64, 128]
const SWEEP1_OLD_NT = 16384
const SWEEP1_OLD_TW_PS = 27.0
const SWEEP1_FIBER = :SMF28
const SWEEP1_L = 2.0
const SWEEP1_P = 0.2
const SWEEP1_BETA_ORDER = 3
const SWEEP1_MAX_ITER = 50

function sweep1_load_rows()
    results = JLD2.load(SWEEP1_SOURCE, "results")
    rows = Dict{Int,Any}()
    for row in results
        nphi = Int(row["N_phi"])
        if nphi in [SWEEP1_BASE_LEVELS; 16384]
            rows[nphi] = row
        end
    end
    missing = setdiff([SWEEP1_BASE_LEVELS; 16384], collect(keys(rows)))
    isempty(missing) || error("missing Sweep-1 rows for N_phi=$(missing)")
    return rows
end

function sweep1_run_level(nphi::Int, row, honest)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_longfiber_problem(;
        fiber_preset=SWEEP1_FIBER,
        L_fiber=SWEEP1_L,
        P_cont=SWEEP1_P,
        Nt=honest.Nt,
        time_window=honest.time_window_ps,
        β_order=SWEEP1_BETA_ORDER,
    )

    phi_seed = recovery_seed_to_grid(row["phi_opt"], SWEEP1_OLD_NT, SWEEP1_OLD_TW_PS, honest.Nt, honest.time_window_ps)
    phi_seed = recovery_remove_linear_phase(phi_seed, uω0, sim)
    started = time()

    if nphi == honest.Nt
        result = optimize_spectral_phase(uω0, deepcopy(fiber), sim, band_mask;
            φ0=phi_seed, max_iter=SWEEP1_MAX_ITER, store_trace=true, log_cost=true)
        phi_opt = reshape(Optim.minimizer(result), honest.Nt, 1)
        J_report = Optim.minimum(result)
        iterations = Optim.iterations(result)
        converged = Optim.f_converged(result)
    else
        bw_mask = pulse_bandwidth_mask(uω0)
        B = build_phase_basis(honest.Nt, nphi; kind=:cubic, bandwidth_mask=bw_mask)
        c0 = vec(B \ vec(phi_seed))
        low = optimize_phase_lowres(uω0, deepcopy(fiber), sim, band_mask;
            N_phi=nphi, kind=:cubic, bandwidth_mask=bw_mask,
            c0=c0, max_iter=SWEEP1_MAX_ITER, log_cost=true,
            B_precomputed=B)
        phi_opt = low.phi_opt
        J_report = low.J_final
        iterations = low.iterations
        converged = low.converged
    end

    metrics = recovery_forward_metrics(uω0, phi_opt, deepcopy(fiber), sim, band_mask)
    tag = lowercase(@sprintf("phase21_sweep1_smf28_l2p00m_p0p200w_nphi%d", nphi))
    images = recovery_save_standard_set(phi_opt, uω0, deepcopy(fiber), sim, band_mask, Δf, raman_threshold;
        tag=tag, fiber_name="SMF-28", L_m=SWEEP1_L, P_W=SWEEP1_P)

    out_path = joinpath(SWEEP1_RESULTS_DIR, @sprintf("nphi_%05d.jld2", nphi))
    JLD2.jldsave(out_path;
        nphi=nphi,
        phi_opt=phi_opt,
        J_report=J_report,
        J_honest_lin=metrics.J_lin,
        J_honest_dB=metrics.J_dB,
        edge_frac=metrics.edge_frac,
        energy_drift=metrics.energy_drift,
        iterations=iterations,
        converged=converged,
        Nt=honest.Nt,
        time_window_ps=honest.time_window_ps,
        wall_s=time() - started,
    )

    return Dict(
        "nphi" => nphi,
        "J_honest_dB" => metrics.J_dB,
        "edge_frac" => metrics.edge_frac,
        "energy_drift" => metrics.energy_drift,
        "iterations" => iterations,
        "converged" => converged,
        "jld2" => out_path,
        "images" => images,
    )
end

function write_sweep1_summary(results, honest)
    ordered = sort(results, by = r -> r["nphi"])
    best = ordered[argmin([r["J_honest_dB"] for r in ordered])]
    lines = String[
        "# Phase 21 Sweep-1 Recovery",
        "",
        @sprintf("Generated: %s", recovery_timestamp()),
        "",
        @sprintf("Honest grid: Nt=%d, time_window=%.1f ps, flat-edge=%.3e, max-seed-edge=%.3e",
            honest.Nt, honest.time_window_ps, honest.flat_edge_frac, honest.max_seed_edge_frac),
        "",
        "| N_phi | J_honest (dB) | edge frac | energy drift | iters | converged |",
        "|---|---|---|---|---|---|",
    ]
    for r in ordered
        push!(lines, @sprintf("| %d | %.2f | %.3e | %.3e | %d | %s |",
            r["nphi"], r["J_honest_dB"], r["edge_frac"], r["energy_drift"], r["iterations"], string(r["converged"])))
    end
    push!(lines, "")
    push!(lines, @sprintf("Best honest point: N_phi=%d at %.2f dB.", best["nphi"], best["J_honest_dB"]))
    push!(lines, "Verdict note: compare this ordered curve against the original Sweep-1 claim before calling the knee recovered.")
    recovery_write_markdown(joinpath(PH21_ROOT, "sweep1_recovery.md"), lines)
end

function main()
    mkpath(SWEEP1_RESULTS_DIR)
    rows = sweep1_load_rows()
    attempt_windows = [108.0, 216.0]
    final_results = nothing
    final_honest = nothing

    for tw_floor in attempt_windows
        honest = recovery_find_honest_grid(;
            fiber_preset=SWEEP1_FIBER,
            L_fiber=SWEEP1_L,
            P_cont=SWEEP1_P,
            β_order=SWEEP1_BETA_ORDER,
            phi_seeds=Any[],
            old_Nt=SWEEP1_OLD_NT,
            old_tw_ps=SWEEP1_OLD_TW_PS,
            min_time_window_ps=tw_floor,
        )

        sweep_levels = [SWEEP1_BASE_LEVELS; honest.Nt]
        results = Vector{Any}(undef, length(sweep_levels))
        @threads for i in eachindex(sweep_levels)
            nphi = sweep_levels[i]
            seed_row = nphi == honest.Nt ? rows[16384] : rows[nphi]
            results[i] = sweep1_run_level(nphi, seed_row, honest)
        end

        max_edge = maximum([r["edge_frac"] for r in results])
        @info @sprintf("Sweep-1 attempt tw_floor=%.1f ps completed with max recovered edge=%.3e",
            tw_floor, max_edge)

        final_results = results
        final_honest = honest
        if max_edge < 1e-3
            break
        end
    end

    write_sweep1_summary(final_results, final_honest)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
