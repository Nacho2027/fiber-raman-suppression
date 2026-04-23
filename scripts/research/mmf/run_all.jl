"""
Phase 16 end-to-end runner: M=6 baseline (GRIN-50, L=1m, P=0.05W, 3 seeds)
+ M=1 reference (SMF28_beta2_only, same L,P, 3 seeds). Designed to run as
one tmux-detached job on the burst VM:

    julia -t auto --project=. scripts/research/mmf/run_all.jl

Outputs go to results/raman/phase16/:
- mmf_baseline_GRIN_50_L1_P0.05_seed{42,123,7}*.png
- mmf_baseline_GRIN_50_L1_P0.05_seed{42,123,7}.jld2
- baseline_M1_reference_seed{42,123,7}.jld2
- phase16_summary.jld2  (aggregate)

Protected files: none modified.
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using Dates
using LinearAlgebra
using JLD2

using MultiModeNoise
using Optim

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "src", "mmf_cost.jl"))
include(joinpath(@__DIR__, "mmf_raman_optimization.jl"))
include(joinpath(@__DIR__, "mmf_m1_limit_run.jl"))

const SAVE_DIR = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase16")
const SEEDS    = [42, 123, 7]

function run_all()
    mkpath(SAVE_DIR)
    @info "=== Phase 16 End-to-End Run ==="
    @info @sprintf("Threads: %d  Seeds: %s", Threads.nthreads(), SEEDS)
    total_t0 = time()

    # ── M=6 baseline ────────────────────────────────────────────────────────
    mmf_results = []
    for seed in SEEDS
        @info "-----"
        @info @sprintf("M=6 BASELINE  seed=%d", seed)
        t0 = time()
        r = run_mmf_baseline(; preset = :GRIN_50, L_fiber = 1.0, P_cont = 0.05,
                              Nt = 2^13, time_window = 10.0,
                              max_iter = 30, seed = seed,
                              tag = @sprintf("GRIN_50_L1_P0.05_seed%d", seed))
        push!(mmf_results, (seed = seed,
                            J_ref_dB = r.J_ref_dB,
                            J_final_dB = r.J_final_lin_dB,
                            improvement_dB = r.improvement_dB,
                            wall = r.wall_time))
        fname = joinpath(SAVE_DIR, @sprintf("baseline_M6_seed%d.jld2", seed))
        jldopen(fname, "w") do f
            f["seed"]           = seed
            f["phi_opt"]        = r.opt.φ_opt
            f["J_history"]      = r.opt.J_history
            f["J_ref_lin"]      = r.J_ref_lin
            f["J_ref_dB"]       = r.J_ref_dB
            f["J_final_lin_dB"] = r.J_final_lin_dB
            f["improvement_dB"] = r.improvement_dB
            f["wall_time"]      = r.wall_time
            f["preset"]         = "GRIN_50"
            f["L_fiber"]        = 1.0
            f["P_cont"]         = 0.05
            f["mode_weights"]   = r.setup.mode_weights
        end
        @info @sprintf("  seed=%d: J=%.2f dB (Δ=%.2f dB) wall=%.1fs  (saved %s)",
            seed, r.J_final_lin_dB, r.improvement_dB, r.wall_time, basename(fname))
    end

    # ── M=1 reference ───────────────────────────────────────────────────────
    @info "-----"
    @info "M=1 REFERENCE RUNS"
    m1_results = []
    for seed in SEEDS
        r = run_m1_reference(; seed = seed, max_iter = 30, save_dir = SAVE_DIR)
        push!(m1_results, (seed = r.seed,
                           J_ref_dB = r.J_ref_dB,
                           J_final_dB = r.J_lin_dB,
                           improvement_dB = r.improvement,
                           wall = r.wall))
    end

    # ── Aggregate summary ───────────────────────────────────────────────────
    total_wall = time() - total_t0
    @info "="^60
    @info @sprintf("PHASE 16 SUMMARY  (total wall: %.1f s)", total_wall)
    @info "="^60
    @info "M=6 baseline (GRIN_50, L=1m, P=0.05W):"
    for r in mmf_results
        @info @sprintf("  seed=%d: J_ref=%.2f dB → J_opt=%.2f dB (Δ=%.2f dB, wall=%.1fs)",
            r.seed, r.J_ref_dB, r.J_final_dB, r.improvement_dB, r.wall)
    end
    @info "M=1 reference (SMF28, L=1m, P=0.05W):"
    for r in m1_results
        @info @sprintf("  seed=%d: J_ref=%.2f dB → J_opt=%.2f dB (Δ=%.2f dB, wall=%.1fs)",
            r.seed, r.J_ref_dB, r.J_final_dB, r.improvement_dB, r.wall)
    end

    # Save combined JLD2
    combined = joinpath(SAVE_DIR, "phase16_summary.jld2")
    jldopen(combined, "w") do f
        f["mmf_results"] = [(seed = r.seed, J_ref_dB = r.J_ref_dB,
                             J_final_dB = r.J_final_dB,
                             improvement_dB = r.improvement_dB,
                             wall = r.wall) for r in mmf_results]
        f["m1_results"]  = [(seed = r.seed, J_ref_dB = r.J_ref_dB,
                             J_final_dB = r.J_final_dB,
                             improvement_dB = r.improvement_dB,
                             wall = r.wall) for r in m1_results]
        f["total_wall"]  = total_wall
        f["n_threads"]   = Threads.nthreads()
        f["run_date"]    = string(now())
    end
    @info "Saved $combined"

    return mmf_results, m1_results
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_all()
end
