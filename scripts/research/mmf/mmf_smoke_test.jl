"""
Fast MMF smoke test — confirms that `setup_mmf_raman_problem`,
`cost_and_gradient_mmf`, and `solve_adjoint_disp_mmf` all import and run
without error at a small grid (Nt=2^10, L=0.1m, M=6). Total wall time
target ~30-60s after precompile.

Purpose: a saturation-friendly quick sanity check before spending burst-VM
compute on the full test suite in `test/test_phase16_mmf.jl`.

Run: `julia -t 2 --project=. scripts/research/mmf/mmf_smoke_test.jl`
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using Random
using FFTW
using LinearAlgebra

using MultiModeNoise

include(joinpath(@__DIR__, "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "src", "mmf_cost.jl"))
include(joinpath(@__DIR__, "mmf_raman_optimization.jl"))

function smoke()
    @info "=== MMF Smoke Test ==="
    @info @sprintf("Threads: %d", Threads.nthreads())
    t0 = time()

    # Very small grid for quick iteration
    setup = setup_mmf_raman_problem(;
        preset = :GRIN_50,
        L_fiber = 0.1,
        P_cont  = 0.05,
        Nt = 2^10,
        time_window = 8.0,
    )
    @info @sprintf("  setup OK (t=%.1fs)  Nt=%d M=%d  E_in=%.3e",
        time() - t0,
        size(setup.uω0, 1), size(setup.uω0, 2),
        sum(abs2, setup.uω0))

    t1 = time()
    Nt = size(setup.uω0, 1)
    φ0 = zeros(Float64, Nt)

    J, g = cost_and_gradient_mmf(
        φ0, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
        variant = :sum, log_cost = false,
    )
    @info @sprintf("  cost_and_gradient_mmf @ φ=0:  J=%.4e  |g|=%.4e  (t=%.1fs)",
        J, norm(g), time() - t1)

    @assert 0 ≤ J ≤ 1
    @assert length(g) == Nt
    @assert all(isfinite, g)

    # One random perturbation just to confirm gradient is responsive
    t2 = time()
    rng = MersenneTwister(17)
    φ1 = 0.05 .* randn(rng, Nt)
    J1, g1 = cost_and_gradient_mmf(
        φ1, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
        variant = :sum, log_cost = false,
    )
    @info @sprintf("  cost_and_gradient_mmf @ φ random: J=%.4e  |g|=%.4e  ΔJ=%.4e  (t=%.1fs)",
        J1, norm(g1), J1 - J, time() - t2)

    @info @sprintf("TOTAL: %.1fs", time() - t0)
    @info "Smoke test PASSED."
end

if abspath(PROGRAM_FILE) == @__FILE__
    smoke()
end
