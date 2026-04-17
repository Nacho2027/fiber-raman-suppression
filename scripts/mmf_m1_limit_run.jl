"""
M=1-limit reference run for Session C Phase 16.

Runs the EXISTING SMF Raman optimizer (`scripts/raman_optimization.jl`) at the
canonical SMF-28 config that mirrors Phase 16's MMF baseline: L=1m, P=0.05W,
185 fs sech², 30 L-BFGS iters. Saves the result and serves as the reference
for the `mmf_cost_sum` ≈ `spectral_band_cost` limit comparison.

Protected-file rule: this script INCLUDES `scripts/raman_optimization.jl` via
`include` but does NOT modify it. Only the `run_optimization` entry point is
called.

Output: results/raman/phase16/baseline_M1_reference_seed<N>.jld2
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using Random
using FFTW
using JLD2
using LinearAlgebra

using MultiModeNoise
using Optim

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))

function run_m1_reference(; seed::Int = 42, max_iter::Int = 30,
                           save_dir::String = joinpath(@__DIR__, "..", "results", "raman", "phase16"))

    mkpath(save_dir)
    @info @sprintf("M=1 reference run — seed=%d, max_iter=%d", seed, max_iter)

    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
        fiber_preset = :SMF28_beta2_only,
        L_fiber = 1.0,
        P_cont  = 0.05,
        Nt      = 2^13,
        time_window = 10.0,
        pulse_fwhm = 185e-15,
    )

    Nt = size(uω0, 1)
    rng = MersenneTwister(seed)
    φ0  = zeros(Float64, Nt, 1)   # (Nt, 1) matches the SMF optimizer's shape

    # Reference J at φ=0
    J_ref, _ = cost_and_gradient(φ0, uω0, fiber, sim, band_mask; log_cost = false)
    J_ref_dB = 10 * log10(max(J_ref, 1e-15))
    @info @sprintf("M=1 reference J(φ=0) = %.3e (%.2f dB)", J_ref, J_ref_dB)

    # Optimize (returns an Optim.jl result object)
    t0 = time()
    res = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0 = φ0, max_iter = max_iter, log_cost = true, store_trace = true)
    wall = time() - t0

    φ_opt_vec = Optim.minimizer(res)
    φ_opt = reshape(φ_opt_vec, Nt, 1)
    J_trace = [t.value for t in Optim.trace(res)]
    J_lin, _ = cost_and_gradient(φ_opt, uω0, fiber, sim, band_mask; log_cost = false)
    J_lin_dB = 10 * log10(max(J_lin, 1e-15))
    @info @sprintf("M=1 reference: J_opt = %.3e (%.2f dB), improvement = %.2f dB, wall = %.1f s",
        J_lin, J_lin_dB, J_ref_dB - J_lin_dB, wall)

    fname = joinpath(save_dir, @sprintf("baseline_M1_reference_seed%d.jld2", seed))
    jldopen(fname, "w") do f
        f["seed"]      = seed
        f["J_ref"]     = J_ref
        f["J_ref_dB"]  = J_ref_dB
        f["J_lin"]     = J_lin
        f["J_lin_dB"]  = J_lin_dB
        f["phi_opt"]   = φ_opt
        f["J_trace"]   = J_trace
        f["wall"]      = wall
        f["max_iter"]  = max_iter
    end
    @info "Saved $fname"

    return (; seed, J_ref_dB, J_lin_dB, improvement = J_ref_dB - J_lin_dB, wall, fname)
end

if abspath(PROGRAM_FILE) == @__FILE__
    @info "Phase 16 — M=1 reference run"
    @info "Threads: $(Threads.nthreads())"
    seeds = [42, 123, 7]
    results = [run_m1_reference(; seed = s) for s in seeds]
    @info "All M=1 reference seeds done"
    for r in results
        @info @sprintf("  seed=%d J_opt=%.2f dB (Δ=%.2f dB, wall=%.1fs)",
            r.seed, r.J_lin_dB, r.improvement, r.wall)
    end
end
