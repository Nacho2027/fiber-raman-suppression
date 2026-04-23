# ═══════════════════════════════════════════════════════════════════════════════
# Phase 15 Plan 01 — Deterministic Environment Regression Test
# ═══════════════════════════════════════════════════════════════════════════════
#
# Run:   julia --project=. test/test_determinism.jl
#
# Runs a small-grid Raman phase optimization TWICE in the same Julia process,
# with identical Random.seed! between runs. Asserts BIT-IDENTICAL phi_opt:
#
#     maximum(abs.(phi_opt_a .- phi_opt_b)) == 0.0
#
# This locks the fix from Phase 15 Plan 01:
#   1. scripts/determinism.jl pins FFTW + BLAS threads to 1
#   2. Task 1.5 swapped flags=FFTW.MEASURE -> flags=FFTW.ESTIMATE in
#      src/simulation/*.jl (16 occurrences across 4 files)
#
# Why the test passes bit-identity (unlike Phase 14-01's regression which
# used a calibrated tolerance):
#   - Same Julia process → no cross-process FFTW plan-selection noise.
#   - ESTIMATE uses a DETERMINISTIC heuristic for plan choice → no timing
#     microbenchmarks → no noise source.
#   - FFTW single-threaded → deterministic reduction order.
#   - BLAS single-threaded → deterministic reduction order in Optim/L-BFGS.
#
# Small grid (Nt=2^10, max_iter=5) keeps wall time ≤ 30 s so this is safe
# to run on every commit.
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using Random
using FFTW
using LinearAlgebra
using Printf
using Optim

# Apply determinism BEFORE loading the pipeline. The include below triggers
# the pipeline which also calls ensure_deterministic_environment(); this early
# call makes the effect unambiguous and matches the end-user pattern.
include(joinpath(@__DIR__, "..", "scripts", "lib", "determinism.jl"))
ensure_deterministic_environment(verbose=true)

include(joinpath(@__DIR__, "..", "scripts", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "scripts", "lib", "raman_optimization.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Shared config — small-grid Raman suppression
# ─────────────────────────────────────────────────────────────────────────────

const DT_SEED      = 42
const DT_MAX_ITER  = 5
const DT_NT        = 2^10
const DT_L_FIBER   = 0.5
const DT_P_CONT    = 0.05
const DT_TW_PS     = 10.0
const DT_PRESET    = :SMF28
const DT_BETA_ORD  = 3
const DT_LOG_COST  = true

"""
Run one optimisation and return (phi_opt_matrix, J_final_linear, iterations,
convergence_history, elapsed_seconds).
"""
function _run_once(label::String)
    Random.seed!(DT_SEED)

    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
        fiber_preset = DT_PRESET,
        Nt           = DT_NT,
        time_window  = DT_TW_PS,
        L_fiber      = DT_L_FIBER,
        P_cont       = DT_P_CONT,
        β_order      = DT_BETA_ORD,
    )
    Nt_actual = sim["Nt"]
    M_actual  = sim["M"]
    φ0 = zeros(Nt_actual, M_actual)

    t0 = time()
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0         = φ0,
        max_iter   = DT_MAX_ITER,
        λ_gdd      = 0.0,
        λ_boundary = 0.0,
        store_trace = true,
        log_cost   = DT_LOG_COST,
    )
    elapsed = time() - t0
    phi_opt = reshape(Optim.minimizer(result), Nt_actual, M_actual)
    J_linear, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask;
                                    log_cost=false)
    iters = Optim.iterations(result)
    # Optim.f_trace returns whatever scale the optimiser saw (log if log_cost=true)
    ftrace = collect(Optim.f_trace(result))
    @info @sprintf("[%s] iters=%d  J=%.6e  elapsed=%.2fs", label, iters, J_linear, elapsed)
    return (phi_opt = phi_opt, J = J_linear, iters = iters,
            ftrace = ftrace, elapsed = elapsed, Nt = Nt_actual, M = M_actual)
end

# ─────────────────────────────────────────────────────────────────────────────
# Two identical runs → bit-identity assertion
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 15 — Deterministic Optimization (bit-identity)" begin

    runA = _run_once("A")
    runB = _run_once("B")

    @test size(runA.phi_opt) == size(runB.phi_opt)
    @test runA.Nt == runB.Nt
    @test runA.M  == runB.M

    max_abs_dphi = maximum(abs.(runA.phi_opt .- runB.phi_opt))
    J_diff       = abs(runA.J - runB.J)
    iter_diff    = abs(runA.iters - runB.iters)
    trace_equal  = length(runA.ftrace) == length(runB.ftrace) &&
                   all(runA.ftrace .== runB.ftrace)

    @info @sprintf("max(|Δφ|)   = %.3e rad (must be 0.0)", max_abs_dphi)
    @info @sprintf("|ΔJ_linear| = %.3e",                   J_diff)
    @info @sprintf("|Δiters|    = %d",                     iter_diff)
    @info @sprintf("ftrace eq   = %s (lenA=%d lenB=%d)",   trace_equal,
                    length(runA.ftrace), length(runB.ftrace))

    # HARD bit-identity — the whole point of Phase 15.
    @test max_abs_dphi == 0.0
    @test runA.J == runB.J
    @test runA.iters == runB.iters
    @test trace_equal
end

@info "Phase 15 determinism test PASSED — phi_opt is BIT-IDENTICAL across repeat runs."
