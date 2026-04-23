# scripts/pcg_smoke.jl — Phase 34 Plan 04 Task 2.
# Conditioning-hypothesis smoke script. Bypasses the frozen outer loop
# (optimize_spectral_phase_tr) to directly call solve_subproblem with M wired.
#
# SCIENTIFIC PURPOSE: optimize_spectral_phase_tr does NOT forward the M
# preconditioner kwarg into solve_subproblem (the "M-kwarg wiring gap" —
# see benchmark_run.jl header and 34-03-SUMMARY.md §Decisions #2).
# This script answers the question the benchmark sweep cannot: does any
# preconditioner produce ρ > η₁=0.25 on a cold-start Raman oracle where
# the Steihaug path produced RADIUS_COLLAPSE?
#
# Answers: does any preconditioner produce ρ > η₁=0.25 on a cold-start oracle
# where the frozen Steihaug path produced RADIUS_COLLAPSE?
#
# Nt=128 small enough to run on claude-code-host per CLAUDE.md Rule 1 carve-out
# (integration tests at Nt=128 have historical precedent in
# test/test_trust_region_integration.jl and test/test_trust_region_pcg_integration.jl).
#
# Physics params: L=0.5m / P=0.05W / Nt=128 / time_window=5.0ps
# (same as the Phase 33/34 integration test precedent — the L=2m/P=0.2W/40ps
# config places the Raman band outside the Nt=128 spectral grid,
# per 34-03-SUMMARY.md §Deviations #2).
#
# Results saved to results/raman/phase34/pcg_smoke/smoke.jld2.

try using Revise catch end
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using LinearAlgebra
using JLD2
using Printf
using Dates

# Pin deterministic numerical environment BEFORE any simulation call.
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()
include(joinpath(@__DIR__, "hvp.jl"))
ensure_deterministic_fftw()

# Core libraries.
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "trust_region_core.jl"))
include(joinpath(@__DIR__, "trust_region_telemetry.jl"))
include(joinpath(@__DIR__, "trust_region_optimize.jl"))  # for build_raman_oracle + RamanOracle
include(joinpath(@__DIR__, "trust_region_preconditioner.jl"))
include(joinpath(@__DIR__, "trust_region_pcg.jl"))

"""
    run_smoke() -> Dict{Symbol, Dict{String, Any}}

Run the conditioning-hypothesis smoke at Nt=128. Calls solve_subproblem
directly with M wired, computing ρ_smoke = actual_reduction / pred_reduction
for each preconditioner variant. Returns the rows dict (also saved to JLD2).
"""
function run_smoke()
    t_smoke_start = time()
    @info "phase34_pcg_smoke: building oracle at Nt=128"

    # L=0.5m / P=0.05W / Nt=128 / time_window=5.0ps — integration-test params.
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset  = :SMF28,
        L_fiber       = 0.5,
        P_cont        = 0.05,
        Nt            = 128,
        time_window   = 5.0,
        β_order       = 3,
    )
    n = length(uω0)  # Nt * M (= 128 × 1 = 128 for SMF28 single-mode)
    φ0 = zeros(Float64, n)

    @info "oracle params" Nt=sim["Nt"] n φ0_norm=norm(φ0)

    # Build oracle via the same function the outer loop uses.
    oracle = build_raman_oracle(uω0, deepcopy(fiber), sim, band_mask;
                                log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
    J0 = oracle.cost_fn(φ0)
    g  = oracle.grad_fn(φ0)
    @info "baseline cost and gradient" J0 g_norm=norm(g)

    # H_op closure: adaptive FD-HVP using the same formula as optimize_spectral_phase_tr.
    function H_op(v::AbstractVector{<:Real})
        g_norm = norm(g)
        v_norm = norm(v)
        eps_hvp = sqrt(eps(Float64) * max(1.0, g_norm)) / max(1.0, v_norm)
        return fd_hvp(φ0, v, oracle.grad_fn; eps = eps_hvp)
    end

    Δ = 0.5  # Same as the outer loop's default Δ0.

    # Preconditioners. :dct_K64 at Nt=128 would require K=64 HVPs (half the grid);
    # use K=16 as a practical DCT analog at this scale.
    M_builders = Dict{Symbol, Union{Nothing, Function}}(
        :none       => nothing,
        :diagonal   => build_diagonal_precond(uω0),
        :dispersion => build_dispersion_precond(sim),
        :dct_K16    => build_dct_precond(H_op, n, 16; σ_shift=:auto),
    )

    rows = Dict{Symbol, Dict{String, Any}}()

    # 1. Steihaug baseline — what the frozen outer loop does (no M).
    @info "running Steihaug (baseline)"
    steih = SteihaugSolver(max_iter=50)
    res_s = solve_subproblem(steih, g, H_op, Δ)
    J_after_s = oracle.cost_fn(φ0 .+ res_s.p)
    actual_s = J0 - J_after_s
    rho_s = actual_s / max(abs(res_s.pred_reduction), eps(Float64))
    rows[:steihaug] = Dict{String, Any}(
        "pred_reduction" => res_s.pred_reduction,
        "actual_reduction" => actual_s,
        "rho" => rho_s,
        "p_norm" => norm(res_s.p),
        "exit_code" => string(res_s.exit_code),
        "inner_iters" => res_s.inner_iters,
        "hvps_used" => res_s.hvps_used,
        "J_after" => J_after_s,
    )

    # 2. PCG variants — M wired directly.
    # Each iteration calls: solve_subproblem(PreconditionedCGSolver(...), g, H_op, Δ; M=M)
    for (sym, M) in sort(collect(M_builders), by=x->string(x[1]))
        @info "running PCG" preconditioner=sym M_is_nothing=(M===nothing)
        pcg = PreconditionedCGSolver(preconditioner=sym, max_iter=50)
        res = solve_subproblem(pcg, g, H_op, Δ; M=M)
        J_after = oracle.cost_fn(φ0 .+ res.p)
        actual = J0 - J_after
        rho = actual / max(abs(res.pred_reduction), eps(Float64))
        rows[sym] = Dict{String, Any}(
            "pred_reduction" => res.pred_reduction,
            "actual_reduction" => actual,
            "rho" => rho,
            "p_norm" => norm(res.p),
            "exit_code" => string(res.exit_code),
            "inner_iters" => res.inner_iters,
            "hvps_used" => res.hvps_used,
            "J_after" => J_after,
        )
    end

    wall_s = time() - t_smoke_start

    # Save results.
    out_dir = joinpath(@__DIR__, "..", "results", "raman", "phase34", "pcg_smoke")
    mkpath(out_dir)
    out_path = joinpath(out_dir, "smoke.jld2")
    jldsave(out_path;
        rows     = rows,
        J0       = J0,
        g_norm   = norm(g),
        Δ        = Δ,
        Nt       = sim["Nt"],
        fiber    = "SMF28",
        L_m      = 0.5,
        P_W      = 0.05,
        wall_s   = wall_s,
        timestamp = string(now()),
    )

    @info "smoke done" out_path wall_s

    # Print summary table.
    println("\n=== Phase 34 Smoke: ρ-distribution at Nt=128 ===")
    @printf("  %-12s  %-28s  %-14s  %-14s  %-14s  %s\n",
            "solver", "exit_code", "rho", "pred_reduction", "actual_reduction", "p_norm")
    for (k, v) in sort(collect(rows), by=x->string(x[1]))
        @printf("  %-12s  %-28s  %+14.4e  %+14.4e  %+14.4e  %+.4e\n",
                string(k), v["exit_code"],
                v["rho"], v["pred_reduction"], v["actual_reduction"], v["p_norm"])
    end
    println("=== end smoke ===\n")

    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_smoke()
end
