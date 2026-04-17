# ═══════════════════════════════════════════════════════════════════════════════
# Session G — Slim sharpness-aware vs vanilla A/B
# ═══════════════════════════════════════════════════════════════════════════════
#
# Trimmed rerun of Phase 14 Plan 02's central A/B question after Session D
# confirmed the vanilla optimum is razor-sharp (SHARP_LUCKY, σ_3dB = 0.025 rad).
#
# Question: does a sharpness-aware cost produce wider basins at the cost of
# some J_final depth? Single canonical config, 3 λ values, reduced convergence
# budget.
#
# Config:                   SMF-28 canonical (L=2 m, P=0.2 W, Nt=2^13)
# λ_sharp values:           {0.0, 0.1, 1.0}
# max_iter:                 20 (reduced from 30)
# N_s (Hutchinson samples): 4 (reduced from 8)
#
# Outputs: results/raman/sharp_ab_slim/ab_results.jld2
# READ-ONLY consumer of existing scripts/{common,raman_optimization,
# sharpness_optimization,determinism}.jl — shared files unchanged.

using LinearAlgebra, Statistics, Random, Printf, FFTW, JLD2, Dates
using Base.Threads: @threads

if !(@isdefined _SHARP_AB_SLIM_LOADED)

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "sharpness_optimization.jl"))

ensure_deterministic_environment()

const _SHARP_AB_SLIM_LOADED = true
const SAS_VERSION       = "1.0.0"
const SAS_LAMBDAS       = [0.0, 0.1, 1.0]
const SAS_MAX_ITER      = 20
const SAS_N_SAMPLES     = 4
const SAS_EPS_SHARP     = 1e-3
const SAS_SEED_BASE     = 1234
const SAS_OUT_DIR       = joinpath(@__DIR__, "..", "results", "raman", "sharp_ab_slim")
const SAS_WISDOM_PATH   = joinpath(SAS_OUT_DIR, "fftw_wisdom.txt")

if isfile(SAS_WISDOM_PATH)
    try FFTW.import_wisdom(SAS_WISDOM_PATH) catch _ end
end

# ─────────────────────────────────────────────────────────────────────────────
# Config (single canonical SMF-28 point)
# ─────────────────────────────────────────────────────────────────────────────
const SAS_CONFIG = (
    id = "smf28_canonical",
    label = "SMF-28 L=2 m P=0.2 W",
    kwargs = (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2, Nt = 2^13,
              pulse_fwhm = 185e-15, β_order = 3),
)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    make_sharp_problem(; kwargs...)

Thin wrapper around `setup_raman_problem` that returns a struct-like NamedTuple
suitable for `optimize_spectral_phase_sharp`. `uω0`, `fiber`, `sim`, `band_mask`
are passed through unchanged.
"""
function make_sharp_problem(; kwargs...)
    uω0, fiber, sim, band_mask, Δf, raman_threshold =
        setup_raman_problem(; kwargs...)
    # `optimize_spectral_phase_sharp` in sharpness_optimization.jl destructures
    # `prob.uω0, prob.fiber, prob.sim, prob.band_mask`, so a NamedTuple works.
    return (uω0 = uω0, fiber = fiber, sim = sim, band_mask = band_mask,
            Δf = Δf, raman_threshold = raman_threshold)
end

"""
    compute_J_dB(phi, prob)

Physical J in dB (no regularisation) from a phase vector on the problem grid.
"""
function compute_J_dB(phi, prob)
    Nt = prob.sim["Nt"]; M = prob.sim["M"]
    φ_shaped = reshape(phi, Nt, M)
    uω0_shaped = prob.uω0 .* cis.(φ_shaped)
    J_lin, _ = cost_and_gradient(uω0_shaped, prob.uω0, prob.fiber, prob.sim,
                                 prob.band_mask; log_cost = false,
                                 λ_gdd = 0.0, λ_boundary = 0.0)
    return 10 * log10(max(J_lin, 1e-30))
end

# ─────────────────────────────────────────────────────────────────────────────
# Run one (λ_sharp) cell
# ─────────────────────────────────────────────────────────────────────────────

function run_cell(λ::Real, seed::Int)
    t0 = time()
    prob = make_sharp_problem(; SAS_CONFIG.kwargs...)
    Nt = prob.sim["Nt"]; M = prob.sim["M"]
    phi0 = zeros(Nt, M)
    rng = MersenneTwister(seed)

    opt = optimize_spectral_phase_sharp(prob, phi0;
                                        lambda_sharp = λ,
                                        n_samples    = SAS_N_SAMPLES,
                                        eps          = SAS_EPS_SHARP,
                                        rng          = rng,
                                        max_iter     = SAS_MAX_ITER,
                                        log_cost     = true,
                                        λ_gdd        = 1e-4,
                                        λ_boundary   = 1.0,
                                        store_trace  = false)

    phi_opt_vec = vec(opt.phi_opt)
    J_final_dB  = compute_J_dB(phi_opt_vec, prob)

    return (
        config_id    = SAS_CONFIG.id,
        lambda_sharp = λ,
        phi_opt      = phi_opt_vec,
        J_final_dB   = J_final_dB,
        iterations   = opt.iterations,
        converged    = opt.converged,
        wall_time_s  = time() - t0,
        seed         = seed,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Driver
# ─────────────────────────────────────────────────────────────────────────────

function main()
    mkpath(SAS_OUT_DIR)
    @info "Session G slim A/B" version=SAS_VERSION lambdas=SAS_LAMBDAS max_iter=SAS_MAX_ITER n_samples=SAS_N_SAMPLES
    @info @sprintf("threads=%d fftw=%d blas=%d",
                    Threads.nthreads(),
                    FFTW.get_num_threads(),
                    LinearAlgebra.BLAS.get_num_threads())
    flush(stdout); flush(stderr)

    results = Vector{Any}(undef, length(SAS_LAMBDAS))

    # Parallelise across the 3 lambdas. Each run_cell does its own
    # setup_raman_problem → thread-safe by construction (each thread owns its
    # fiber dict).
    t_total = time()
    @threads for i in 1:length(SAS_LAMBDAS)
        λ = SAS_LAMBDAS[i]
        seed = SAS_SEED_BASE + i
        t_start = time()
        @info @sprintf("start cell λ=%s seed=%d", string(λ), seed)
        flush(stdout)
        results[i] = run_cell(λ, seed)
        @info @sprintf("done cell λ=%s in %.1f s: J=%.3f dB iters=%d",
                        string(λ), time() - t_start,
                        results[i].J_final_dB, results[i].iterations)
        flush(stdout)
    end
    total_wall = time() - t_total
    @info @sprintf("A/B complete in %.1f s", total_wall)

    # Persist.
    out_path = joinpath(SAS_OUT_DIR, "ab_results.jld2")
    JLD2.jldsave(out_path;
        version        = SAS_VERSION,
        config         = SAS_CONFIG,
        lambdas        = SAS_LAMBDAS,
        results        = results,
        max_iter       = SAS_MAX_ITER,
        n_samples      = SAS_N_SAMPLES,
        eps_sharp      = SAS_EPS_SHARP,
        julia_nthreads = Threads.nthreads(),
        total_wall_s   = total_wall,
        timestamp      = string(now()),
    )
    @info "wrote $(out_path)"
    try FFTW.export_wisdom(SAS_WISDOM_PATH) catch _ end

    # ── Standard output images (Project rule, 2026-04-17) ────────────────
    # save_standard_set uses visualization.jl which runs its own forward
    # solves; serialize to avoid FFTW/BLAS thrash.
    include(joinpath(@__DIR__, "visualization.jl"))
    include(joinpath(@__DIR__, "standard_images.jl"))
    for (i, r) in enumerate(results)
        λ = SAS_LAMBDAS[i]
        λtag = replace(@sprintf("%.3f", λ), "." => "p")
        tag = "sharp_ab_smf28_L2m_P0p2W_lambda$(λtag)"
        # Rebuild the problem for this cell so we have the grid fiber/sim
        # matching phi_opt (threadsafe — a fresh setup).
        prob = make_sharp_problem(; SAS_CONFIG.kwargs...)
        phi_mat = reshape(r.phi_opt, prob.sim["Nt"], prob.sim["M"])
        try
            save_standard_set(phi_mat, prob.uω0, prob.fiber, prob.sim,
                              prob.band_mask, prob.Δf, prob.raman_threshold;
                              tag        = tag,
                              fiber_name = "SMF28",
                              L_m        = 2.0,
                              P_W        = 0.2,
                              output_dir = SAS_OUT_DIR)
        catch e
            @warn "save_standard_set failed for λ=$(λ)" exception=(e, catch_backtrace())
        end
    end

    return out_path
end

end  # include guard

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
