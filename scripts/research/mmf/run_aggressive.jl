"""
Phase 16 Plan 01 — aggressive-config baseline.

The mild config (L=1m, P=0.05W, GRIN-50) that matches the SMF canonical
produces N_sol ≈ 0.9 — sub-soliton regime with no Raman to suppress and
zero-headroom convergence. For a meaningful MMF Raman validation we
need to push into the soliton regime. This driver runs:

  - M=6 baseline @ GRIN_50, L=2m, P=0.5W, 1 seed (42), 25 iters
  - M=1 reference @ SMF28_beta2_only, same L,P, 1 seed (42), 25 iters

Both configs land at P_peak ≈ 30 kW, N_sol ≈ 3-4 in SMF-28 and ≈ 2-3 in
GRIN_50 — solidly in the Raman-dominated regime.

save_standard_set is emitted per run (CLAUDE.md 2026-04-17 rule).
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using Dates
using LinearAlgebra
using JLD2
using FFTW
using Random

using MultiModeNoise
using Optim

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "src", "mmf_cost.jl"))
include(joinpath(@__DIR__, "mmf_raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "visualization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "standard_images.jl"))

const SAVE_DIR = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase16", "aggressive")

# ─────────────────────────────────────────────────────────────────────────────
# Aggressive config
# ─────────────────────────────────────────────────────────────────────────────

const AGG_L   = 2.0    # m
const AGG_P   = 0.5    # W (avg) — 10× baseline
const AGG_SEED = 42
const AGG_MAX_ITER = 25

function run_m6()
    @info "="^66
    @info @sprintf("M=6 BASELINE (AGGRESSIVE) — GRIN_50, L=%gm, P=%gW, seed=%d",
        AGG_L, AGG_P, AGG_SEED)
    @info "="^66

    mkpath(SAVE_DIR)
    t0 = time()
    r = run_mmf_baseline(;
        preset = :GRIN_50,
        L_fiber = AGG_L,
        P_cont  = AGG_P,
        Nt      = 2^13,
        time_window = 20.0,           # wider window for the more nonlinear pulse
        max_iter = AGG_MAX_ITER,
        seed = AGG_SEED,
        save_dir = SAVE_DIR,
        tag = @sprintf("GRIN_50_L%gm_P%gW_seed%d", AGG_L, AGG_P, AGG_SEED),
    )
    wall = time() - t0

    fname = joinpath(SAVE_DIR, @sprintf("aggressive_M6_seed%d.jld2", AGG_SEED))
    jldopen(fname, "w") do f
        f["preset"]         = "GRIN_50"
        f["variant"]        = "sum"
        f["L_fiber"]        = AGG_L
        f["P_cont"]         = AGG_P
        f["seed"]           = AGG_SEED
        f["phi_opt"]        = r.opt.φ_opt
        f["J_history"]      = r.opt.J_history
        f["J_ref_lin"]      = r.J_ref_lin
        f["J_ref_dB"]       = r.J_ref_dB
        f["J_final_lin_dB"] = r.J_final_lin_dB
        f["improvement_dB"] = r.improvement_dB
        f["wall_time"]      = r.wall_time
        f["mode_weights"]   = r.setup.mode_weights
        f["Nt_used"]        = r.setup.sim["Nt"]
        f["time_window_used_ps"] = r.setup.sim["time_window"]
        f["time_window_recommended_ps"] = r.setup.window_recommendation.time_window_ps
        f["ref_sum_dB"]     = r.trust_ref.cost_report.sum_dB
        f["ref_fundamental_dB"] = r.trust_ref.cost_report.fundamental_dB
        f["ref_worst_mode_true_dB"] = r.trust_ref.cost_report.worst_mode_true_dB
        f["ref_per_mode_dB"] = r.trust_ref.cost_report.per_mode_dB
        f["ref_boundary_edge_fraction"] = r.trust_ref.boundary_edge_fraction
        f["ref_boundary_ok"] = r.trust_ref.boundary_ok
        f["opt_sum_dB"]     = r.trust_opt.cost_report.sum_dB
        f["opt_fundamental_dB"] = r.trust_opt.cost_report.fundamental_dB
        f["opt_worst_mode_true_dB"] = r.trust_opt.cost_report.worst_mode_true_dB
        f["opt_per_mode_dB"] = r.trust_opt.cost_report.per_mode_dB
        f["opt_boundary_edge_fraction"] = r.trust_opt.boundary_edge_fraction
        f["opt_boundary_ok"] = r.trust_opt.boundary_ok
    end
    @info @sprintf("M=6 aggressive: J_ref=%.2f dB → J_opt=%.2f dB (Δ=%.2f dB, wall=%.1fs)",
        r.J_ref_dB, r.J_final_lin_dB, r.improvement_dB, wall)
    @info "Saved $fname"
    return r
end

function run_m1()
    @info "="^66
    @info @sprintf("M=1 REFERENCE (AGGRESSIVE) — SMF28, L=%gm, P=%gW, seed=%d",
        AGG_L, AGG_P, AGG_SEED)
    @info "="^66

    mkpath(SAVE_DIR)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
        fiber_preset = :SMF28_beta2_only,
        L_fiber = AGG_L,
        P_cont  = AGG_P,
        Nt      = 2^13,
        time_window = 20.0,
        pulse_fwhm = 185e-15,
    )
    Nt = size(uω0, 1)
    φ0 = zeros(Float64, Nt, 1)

    J_ref, _ = cost_and_gradient(φ0, uω0, fiber, sim, band_mask; log_cost = false)
    J_ref_dB = 10 * log10(max(J_ref, 1e-15))
    @info @sprintf("Reference (φ=0): J_lin = %.3e (%.2f dB)", J_ref, J_ref_dB)

    t0 = time()
    res = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0 = φ0, max_iter = AGG_MAX_ITER, log_cost = true, store_trace = true)
    wall = time() - t0

    φ_opt_vec = Optim.minimizer(res)
    φ_opt = reshape(φ_opt_vec, Nt, 1)
    J_trace = [t.value for t in Optim.trace(res)]
    J_lin, _ = cost_and_gradient(φ_opt, uω0, fiber, sim, band_mask; log_cost = false)
    J_lin_dB = 10 * log10(max(J_lin, 1e-15))
    @info @sprintf("M=1 aggressive: J_opt = %.3e (%.2f dB), Δ = %.2f dB, wall = %.1f s",
        J_lin, J_lin_dB, J_ref_dB - J_lin_dB, wall)

    fname = joinpath(SAVE_DIR, @sprintf("aggressive_M1_seed%d.jld2", AGG_SEED))
    jldopen(fname, "w") do f
        f["preset"]         = "SMF28_beta2_only"
        f["L_fiber"]        = AGG_L
        f["P_cont"]         = AGG_P
        f["seed"]           = AGG_SEED
        f["phi_opt"]        = φ_opt
        f["J_trace"]        = J_trace
        f["J_ref"]          = J_ref
        f["J_ref_dB"]       = J_ref_dB
        f["J_lin"]          = J_lin
        f["J_lin_dB"]       = J_lin_dB
        f["wall"]           = wall
    end
    @info "Saved $fname"

    save_standard_set(
        φ_opt, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        tag = lowercase(@sprintf("m1_agg_smf28_l%gm_p%gw_seed%d", AGG_L, AGG_P, AGG_SEED)),
        fiber_name = "SMF28",
        L_m = AGG_L,
        P_W = AGG_P,
        output_dir = SAVE_DIR,
    )

    return (J_ref_dB = J_ref_dB, J_lin_dB = J_lin_dB,
            improvement_dB = J_ref_dB - J_lin_dB, wall = wall)
end

function run_all_aggressive()
    @info "Phase 16 aggressive-config baseline — single seed, two fiber types"
    @info @sprintf("Threads: %d", Threads.nthreads())
    total_t0 = time()

    m6 = run_m6()
    m1 = run_m1()

    total = time() - total_t0
    @info "="^66
    @info "AGGRESSIVE SUMMARY"
    @info "="^66
    @info @sprintf("M=6 GRIN_50:        J_ref=%.2f dB → J_opt=%.2f dB  (Δ=%.2f dB)",
        m6.J_ref_dB, m6.J_final_lin_dB, m6.improvement_dB)
    @info @sprintf("M=1 SMF28:          J_ref=%.2f dB → J_opt=%.2f dB  (Δ=%.2f dB)",
        m1.J_ref_dB, m1.J_lin_dB, m1.improvement_dB)
    @info @sprintf("Total wall: %.1f s", total)
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_all_aggressive()
end
