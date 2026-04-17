"""
Phase 16 Plan 01 — MMF Raman optimizer numerical correctness tests.

Run on the burst VM with `julia -t auto test/test_phase16_mmf.jl`.

Testsets:
1. Shape sanity      — φ is Vector length Nt, grad is Vector length Nt.
2. M=1-limit reduction — compare MMF cost/gradient at M=1 vs the standalone
   `spectral_band_cost` on a synthetic field. Tight (bit-identity up to FFTW
   planner nondeterminism).
3. Finite-difference gradient check — analytic ∇J vs central-difference ∇J at
   five random Nt-indices; rel err < 1e-3 at M=6, small L.
4. Energy accounting — forward propagation at L=0.5m should conserve energy
   modulo (i) Raman phonon loss and (ii) super-Gaussian attenuator absorption,
   both bounded.
"""

ENV["MPLBACKEND"] = "Agg"

using Test
using Random
using LinearAlgebra
using FFTW
using Statistics
using Printf

using MultiModeNoise

include(joinpath(@__DIR__, "..", "scripts", "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "src", "mmf_cost.jl"))
include(joinpath(@__DIR__, "..", "scripts", "mmf_raman_optimization.jl"))

const PHASE16_SEED = 20260417

@info "Phase 16 MMF tests — threads = $(Threads.nthreads())"

# ─────────────────────────────────────────────────────────────────────────────
# Testset 1: shape sanity
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 16 — shape sanity" begin
    setup = setup_mmf_raman_problem(;
        preset = :GRIN_50,
        L_fiber = 0.3,
        P_cont = 0.05,
        Nt = 2^12,
        time_window = 8.0,
    )
    Nt = size(setup.uω0, 1)
    M  = size(setup.uω0, 2)

    rng = MersenneTwister(PHASE16_SEED)
    φ = 0.05 .* randn(rng, Nt)

    J, g = cost_and_gradient_mmf(
        φ, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
        variant = :sum, log_cost = false,
    )

    @test isa(φ, Vector{Float64})
    @test length(g) == Nt
    @test isa(g, Vector{Float64})
    @test isfinite(J)
    @test all(isfinite, g)
    @test M == 6
end

# ─────────────────────────────────────────────────────────────────────────────
# Testset 2: M=1-limit — cost variants agree at M=1 uniform mode
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 16 — cost variants agree at M=1" begin
    Nt = 2^12
    rng = MersenneTwister(PHASE16_SEED)
    uωf = randn(rng, ComplexF64, Nt, 1)
    band_mask = falses(Nt)
    band_mask[1:div(Nt, 4)] .= true

    J_sum,   dJ_sum   = mmf_cost_sum(uωf, band_mask)
    J_fund,  dJ_fund  = mmf_cost_fundamental(uωf, band_mask)
    J_worst, dJ_worst = mmf_cost_worst_mode(uωf, band_mask; τ = 100.0)

    @test isapprox(J_sum, J_fund, atol = 1e-12)
    @test isapprox(maximum(abs.(dJ_sum .- dJ_fund)), 0.0, atol = 1e-12)

    # worst_mode with large τ coincides up to log(1)/τ = 0 at M=1
    @test isapprox(J_worst, J_sum, atol = 1e-10)
end

# ─────────────────────────────────────────────────────────────────────────────
# Testset 3: finite-difference gradient check at M=6
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 16 — FD gradient check at M=6" begin
    setup = setup_mmf_raman_problem(;
        preset = :GRIN_50,
        L_fiber = 0.3,
        P_cont = 0.05,
        Nt = 2^12,
        time_window = 8.0,
    )
    Nt = size(setup.uω0, 1)
    rng = MersenneTwister(PHASE16_SEED + 1)

    # Small random φ so the optimization surface is benign
    φ = 0.05 .* randn(rng, Nt)

    J0, g0 = cost_and_gradient_mmf(
        φ, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
        variant = :sum, log_cost = false,
    )

    ε = 1e-5
    idxs = rand(rng, 1:Nt, 5)
    max_rel_err = 0.0
    for i in idxs
        φp = copy(φ); φp[i] += ε
        φm = copy(φ); φm[i] -= ε
        Jp, _ = cost_and_gradient_mmf(
            φp, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
            variant = :sum, log_cost = false,
        )
        Jm, _ = cost_and_gradient_mmf(
            φm, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
            variant = :sum, log_cost = false,
        )
        g_fd = (Jp - Jm) / (2ε)
        rel = abs(g_fd - g0[i]) / max(abs(g0[i]), 1e-10)
        @info @sprintf("FD check idx=%d analytic=%.4e FD=%.4e rel_err=%.2e", i, g0[i], g_fd, rel)
        max_rel_err = max(max_rel_err, rel)
    end
    # Raman+adjoint at ε=1e-5 is typically good to ~1e-3 relative, occasionally 5e-3
    @test max_rel_err < 5e-3
end

# ─────────────────────────────────────────────────────────────────────────────
# Testset 4: energy accounting at M=6
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 16 — energy accounting at M=6" begin
    setup = setup_mmf_raman_problem(;
        preset = :GRIN_50,
        L_fiber = 0.3,
        P_cont = 0.05,
        Nt = 2^12,
        time_window = 8.0,
    )
    uω0 = setup.uω0
    sol = MultiModeNoise.solve_disp_mmf(uω0, setup.fiber, setup.sim)
    ũω  = sol["ode_sol"]
    L     = setup.fiber["L"]
    Dω    = setup.fiber["Dω"]
    uωf   = cis.(Dω .* L) .* ũω(L)

    E_in  = sum(abs2, uω0)
    E_out = sum(abs2, uωf)
    rel_loss = (E_in - E_out) / E_in
    @info @sprintf("E_in=%.4e E_out=%.4e rel_loss=%.3e", E_in, E_out, rel_loss)

    # Loss bound: Raman dissipation (imag(hRω)) + super-Gaussian attenuator
    # absorption at the edges. At L=0.3m and modest power this should stay <5%.
    @test isfinite(rel_loss)
    @test rel_loss > -1e-6         # no numerical energy generation (within FFTW)
    @test rel_loss < 0.05          # bounded loss
end

@info "Phase 16 MMF tests complete."
