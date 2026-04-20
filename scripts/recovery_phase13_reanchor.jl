#!/usr/bin/env julia
"""
Phase 21 — re-anchor the two Phase 13 Hessian study configs on honest grids.
"""

ENV["MPLBACKEND"] = "Agg"

using JLD2
using Printf
using Logging
using Base.Threads

include(joinpath(@__DIR__, "recovery_common.jl"))

const PH13_RESULTS_DIR = recovery_result_path("phase13")
const PH13_CONFIGS = [
    (
        key = "smf28",
        source = joinpath(@__DIR__, "..", "results", "raman", "phase13", "hessian_smf28_canonical.jld2"),
        fiber_preset = :SMF28,
        fiber_name = "SMF-28",
        L_fiber = 2.0,
        P_cont = 0.2,
        old_Nt = 8192,
        old_tw_ps = 27.0,
        β_order = 3,
        min_time_window_ps = 48.0,
    ),
    (
        key = "hnlf",
        source = joinpath(@__DIR__, "..", "results", "raman", "phase13", "hessian_hnlf_canonical.jld2"),
        fiber_preset = :HNLF,
        fiber_name = "HNLF",
        L_fiber = 0.5,
        P_cont = 0.01,
        old_Nt = 8192,
        old_tw_ps = 10.0,
        β_order = 3,
        min_time_window_ps = 20.0,
    ),
]

function phase13_run_one(cfg)
    old = JLD2.load(cfg.source)
    phi_seed_old = recovery_key_or_nothing(old, ["phi_opt", "phi"])
    phi_seed_old === nothing && error("no phi_opt found in $(cfg.source)")

    chosen = nothing
    result = nothing
    phi_opt = nothing
    metrics = nothing
    uω0 = nothing
    fiber = nothing
    sim = nothing
    band_mask = nothing
    Δf = nothing
    raman_threshold = nothing
    started = time()

    honest = recovery_find_honest_grid(;
        fiber_preset=cfg.fiber_preset,
        L_fiber=cfg.L_fiber,
        P_cont=cfg.P_cont,
        β_order=cfg.β_order,
        phi_seeds=[phi_seed_old],
        old_Nt=cfg.old_Nt,
        old_tw_ps=cfg.old_tw_ps,
        min_time_window_ps=cfg.min_time_window_ps,
    )

    for _attempt in 1:2
        uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_longfiber_problem(;
            fiber_preset=cfg.fiber_preset,
            L_fiber=cfg.L_fiber,
            P_cont=cfg.P_cont,
            Nt=honest.Nt,
            time_window=honest.time_window_ps,
            β_order=cfg.β_order,
        )
        phi0 = recovery_seed_to_grid(phi_seed_old, cfg.old_Nt, cfg.old_tw_ps, honest.Nt, honest.time_window_ps)
        phi0 = recovery_remove_linear_phase(phi0, uω0, sim)

        result = optimize_spectral_phase(uω0, deepcopy(fiber), sim, band_mask;
            φ0=phi0, max_iter=50, store_trace=true, log_cost=true)
        phi_opt = reshape(Optim.minimizer(result), honest.Nt, 1)
        metrics = recovery_forward_metrics(uω0, phi_opt, deepcopy(fiber), sim, band_mask)
        chosen = honest
        metrics.edge_frac < 1e-3 && break

        honest = (
            Nt = recovery_nt_for_window(2 * honest.time_window_ps),
            time_window_ps = 2 * honest.time_window_ps,
        )
    end

    tag = lowercase(@sprintf("phase21_phase13_%s_l%0.2fm_p%0.3fw", cfg.key, cfg.L_fiber, cfg.P_cont))
    jld2_path = joinpath(PH13_RESULTS_DIR, @sprintf("%s_reanchor.jld2", cfg.key))
    JLD2.jldsave(jld2_path;
        phi_opt=phi_opt,
        J_honest_lin=metrics.J_lin,
        J_honest_dB=metrics.J_dB,
        edge_frac=metrics.edge_frac,
        energy_drift=metrics.energy_drift,
        iterations=Optim.iterations(result),
        converged=Optim.f_converged(result),
        Nt=chosen.Nt,
        time_window_ps=chosen.time_window_ps,
        wall_s=time() - started,
        tag=tag,
    )

    md_path = joinpath(PH13_RESULTS_DIR, @sprintf("%s_reanchor.md", cfg.key))
    recovery_write_markdown(md_path, [
        @sprintf("# Phase 13 re-anchor — %s", cfg.fiber_name),
        "",
        @sprintf("Honest grid attempt: Nt=%d, time_window=%.1f ps", chosen.Nt, chosen.time_window_ps),
        @sprintf("Recovered J: %.2f dB", metrics.J_dB),
        @sprintf("Edge fraction: %.3e", metrics.edge_frac),
        @sprintf("Energy drift: %.3e", metrics.energy_drift),
        @sprintf("Iterations: %d", Optim.iterations(result)),
        @sprintf("Converged: %s", string(Optim.f_converged(result))),
        "",
        "Interpretation: this re-anchors the dB number only. Compare against the old Hessian-study value to decide whether the stationary point survived materially unchanged.",
    ])

    return Dict(
        "key" => cfg.key,
        "J_honest_dB" => metrics.J_dB,
        "edge_frac" => metrics.edge_frac,
        "iterations" => Optim.iterations(result),
        "converged" => Optim.f_converged(result),
        "jld2" => jld2_path,
        "tag" => tag,
    )
end

function phase13_generate_images(results)
    for cfg in PH13_CONFIGS
        d = JLD2.load(joinpath(PH13_RESULTS_DIR, @sprintf("%s_reanchor.jld2", cfg.key)))
        uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_longfiber_problem(;
            fiber_preset=cfg.fiber_preset,
            L_fiber=cfg.L_fiber,
            P_cont=cfg.P_cont,
            Nt=Int(d["Nt"]),
            time_window=Float64(d["time_window_ps"]),
            β_order=cfg.β_order,
        )
        recovery_save_standard_set(d["phi_opt"], uω0, deepcopy(fiber), sim, band_mask, Δf, raman_threshold;
            tag=String(d["tag"]), fiber_name=cfg.fiber_name, L_m=cfg.L_fiber, P_W=cfg.P_cont)
    end
end

function main()
    mkpath(PH13_RESULTS_DIR)
    results = Vector{Any}(undef, length(PH13_CONFIGS))
    @threads for i in eachindex(PH13_CONFIGS)
        results[i] = phase13_run_one(PH13_CONFIGS[i])
    end
    phase13_generate_images(results)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
