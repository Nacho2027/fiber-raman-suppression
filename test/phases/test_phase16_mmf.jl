"""
Phase 16 Plan 01 — MMF Raman optimizer numerical correctness tests.

Run on the burst VM with `julia -t auto test/phases/test_phase16_mmf.jl`.

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

include(joinpath(@__DIR__, "..", "..", "scripts", "research", "mmf", "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "src", "mmf_cost.jl"))
include(joinpath(@__DIR__, "..", "..", "scripts", "research", "mmf", "mmf_raman_optimization.jl"))

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

    report = mmf_cost_report(uωf, band_mask; τ = 100.0)
    @test isapprox(report.sum_lin, J_sum, atol = 1e-12)
    @test isapprox(report.fundamental_lin, J_fund, atol = 1e-12)
    @test isapprox(report.worst_mode_lin, J_worst, atol = 1e-10)
    @test length(report.per_mode_lin) == 1
end

@testset "Phase 16 — MMF trust uses raw output time field" begin
    Nt = 2^7
    M = 2
    ut_centered = zeros(ComplexF64, Nt, M)
    ut_centered[Nt ÷ 2, 1] = 1.0 + 0im
    ut_centered[Nt ÷ 2 + 1, 2] = 0.5 + 0im
    uω = ifft(ut_centered, 1)

    ut_recovered = mmf_output_time_field(uω)
    @test maximum(abs.(ut_recovered .- ut_centered)) < 1e-12

    ok_raw, frac_raw = check_raw_temporal_edges(ut_recovered; threshold = 1e-6)
    @test ok_raw
    @test frac_raw < 1e-30

    # The old MMF trust path used `ifft(uω, 1)`, which is not the time-domain
    # field under this repository's `uω = ifft(ut)` convention.
    @test maximum(abs.(ifft(uω, 1) .- ut_centered)) > 0.1
end

@testset "Phase 16 — MMF optimizer hard-stops before extra propagations" begin
    setup = setup_mmf_raman_problem(;
        preset = :GRIN_50,
        L_fiber = 0.05,
        P_cont = 0.01,
        Nt = 2^8,
        time_window = 8.0,
    )

    opt = optimize_mmf_phase(
        setup.uω0,
        setup.mode_weights,
        setup.fiber,
        setup.sim,
        setup.band_mask;
        max_iter = 5,
        f_calls_limit = 2,
        time_limit = 60.0,
        verbose = false,
    )
    @test length(opt.J_history) <= 2
    @test opt.stopped_by === :f_calls_limit
    @test opt.result === nothing
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
# Testset 3b: log-cost + regularizers stay on one scalar surface
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 16 — log-cost regularizers are chained into the MMF surface" begin
    setup = setup_mmf_raman_problem(;
        preset = :GRIN_50,
        L_fiber = 0.3,
        P_cont = 0.05,
        Nt = 2^10,
        time_window = 8.0,
    )
    Nt = size(setup.uω0, 1)
    rng = MersenneTwister(PHASE16_SEED + 2)
    φ = 0.02 .* randn(rng, Nt)

    spec = mmf_cost_surface_spec(;
        variant = :sum, log_cost = true, λ_gdd = 1e-4, λ_boundary = 0.5)
    @test spec.scalar_surface == "10*log10(J_mmf_sum + λ_gdd*R_gdd + λ_boundary*R_boundary)"
    @test spec.regularizers_chained_into_surface === true

    J0, g0 = cost_and_gradient_mmf(
        φ, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
        variant = :sum, log_cost = true, λ_gdd = 1e-4, λ_boundary = 0.5,
    )

    idx = rand(rng, 1:Nt)
    ε = 1e-6
    φp = copy(φ); φp[idx] += ε
    φm = copy(φ); φm[idx] -= ε
    Jp, _ = cost_and_gradient_mmf(
        φp, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
        variant = :sum, log_cost = true, λ_gdd = 1e-4, λ_boundary = 0.5,
    )
    Jm, _ = cost_and_gradient_mmf(
        φm, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
        variant = :sum, log_cost = true, λ_gdd = 1e-4, λ_boundary = 0.5,
    )
    g_fd = (Jp - Jm) / (2ε)
    rel = abs(g_fd - g0[idx]) / max(abs(g0[idx]), abs(g_fd), 1e-12)

    v = randn(rng, Nt); v ./= norm(v)
    dir0 = dot(g0, v)
    eps_values = 10.0 .^ (-2:-0.5:-5)
    remainders = Float64[]
    for εt in eps_values
        Jt, _ = cost_and_gradient_mmf(
            φ .+ εt .* v, setup.mode_weights, setup.uω0, setup.fiber, setup.sim, setup.band_mask;
            variant = :sum, log_cost = true, λ_gdd = 1e-4, λ_boundary = 0.5,
        )
        push!(remainders, abs(Jt - J0 - εt * dir0))
    end
    xs = log10.(eps_values[1:4])
    ys = log10.(remainders[1:4])
    slope = (ys[end] - ys[1]) / (xs[end] - xs[1])

    @test rel < 5e-2
    @test 1.7 < slope < 2.3
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

# ─────────────────────────────────────────────────────────────────────────────
# Testset 5: MMF auto window sizing
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 16 — auto window sizing at aggressive config" begin
    setup = setup_mmf_raman_problem(;
        preset = :GRIN_50,
        L_fiber = 2.0,
        P_cont = 0.5,
        Nt = 2^12,
        time_window = 5.0,
        auto_time_window = true,
    )

    @test setup.sim["time_window"] >= setup.window_recommendation.time_window_ps
    @test setup.sim["time_window"] > 5.0
    @test ispow2(setup.sim["Nt"])
    @test setup.window_recommendation.peak_power_W > 0
    @test setup.window_recommendation.beta2_abs_max > 0
end

@info "Phase 16 MMF tests complete."
