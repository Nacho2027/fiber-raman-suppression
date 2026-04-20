#!/usr/bin/env julia
"""
Phase 21 — opportunistic MMF aggressive-regime run.
"""

ENV["MPLBACKEND"] = "Agg"

using JLD2
using Printf
using Logging

include(joinpath(@__DIR__, "recovery_common.jl"))
include(joinpath(@__DIR__, "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "src", "mmf_cost.jl"))
include(joinpath(@__DIR__, "mmf_raman_optimization.jl"))

const MMF_RESULTS_DIR = recovery_result_path("mmf")

function main()
    mkpath(MMF_RESULTS_DIR)
    setup = setup_mmf_raman_problem(;
        preset=:GRIN_50,
        L_fiber=2.0,
        P_cont=0.5,
        Nt=2^13,
        time_window=20.0,
    )
    opt = optimize_mmf_phase(
        setup.uω0,
        setup.mode_weights,
        deepcopy(setup.fiber),
        setup.sim,
        setup.band_mask;
        max_iter=25,
        variant=:sum,
        log_cost=true,
        store_trace=true,
    )
    phi_opt = reshape(opt.φ_opt, setup.sim["Nt"], 1)
    metrics = recovery_forward_metrics(setup.uω0, phi_opt, deepcopy(setup.fiber), setup.sim, setup.band_mask)

    tag = "phase21_mmf_aggressive_grin50_l2m_p0p5w"
    images = recovery_save_standard_set(phi_opt, setup.uω0, deepcopy(setup.fiber), setup.sim, setup.band_mask, setup.Δf, setup.raman_threshold;
        tag=tag, fiber_name="GRIN-50 MMF", L_m=2.0, P_W=0.5)

    out_path = joinpath(MMF_RESULTS_DIR, "mmf_aggressive.jld2")
    JLD2.jldsave(out_path;
        phi_opt=phi_opt,
        J_honest_lin=metrics.J_lin,
        J_honest_dB=metrics.J_dB,
        edge_frac=metrics.edge_frac,
        energy_drift=metrics.energy_drift,
        iterations=length(opt.J_history),
    )

    recovery_write_markdown(joinpath(MMF_RESULTS_DIR, "mmf_aggressive.md"), [
        "# MMF aggressive recovery",
        "",
        @sprintf("Honest J: %.2f dB", metrics.J_dB),
        @sprintf("Edge fraction: %.3e", metrics.edge_frac),
        @sprintf("Energy drift: %.3e", metrics.energy_drift),
        @sprintf("Iterations: %d", length(opt.J_history)),
        "",
        "Interpretation: this is the first aggressive-regime MMF check, not a full multimode campaign.",
    ])
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
