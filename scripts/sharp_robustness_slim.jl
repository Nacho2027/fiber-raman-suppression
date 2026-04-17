# ═══════════════════════════════════════════════════════════════════════════════
# Session G — σ_3dB robustness measurement on A/B optima
# ═══════════════════════════════════════════════════════════════════════════════
#
# For each (λ_sharp, phi_opt) produced by sharp_ab_slim.jl, measure how much
# Gaussian phase perturbation (σ ∈ {0.01, 0.02, 0.05, 0.1, 0.2}) degrades J.
# Same methodology as Session D's Phase 17 perturbation study.
#
# Output: `results/raman/sharp_ab_slim/robustness.jld2` (per-σ means + stdevs,
# interpolated σ_3dB per lambda) + a single summary figure written by
# sharp_ab_figures.jl.

if !(@isdefined _SHARP_ROBUSTNESS_SLIM_LOADED)

using LinearAlgebra, Statistics, Random, Printf, FFTW, JLD2
using Base.Threads: @threads

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "sharpness_optimization.jl"))

ensure_deterministic_environment()

const _SHARP_ROBUSTNESS_SLIM_LOADED = true
const SRS_VERSION     = "1.0.0"
const SRS_SIGMAS      = [0.01, 0.02, 0.05, 0.10, 0.20]
const SRS_N_TRIALS    = 20
const SRS_SEED_BASE   = 9100
const SRS_IN_PATH     = joinpath(@__DIR__, "..", "results", "raman", "sharp_ab_slim", "ab_results.jld2")
const SRS_OUT_PATH    = joinpath(@__DIR__, "..", "results", "raman", "sharp_ab_slim", "robustness.jld2")

# ─────────────────────────────────────────────────────────────────────────────
# Measure J(phi + σ·n) for fixed phi over N_TRIALS random n
# ─────────────────────────────────────────────────────────────────────────────

function perturbation_J(phi_opt_vec::AbstractVector, prob; sigma::Real,
                        n_trials::Int, rng_base::Int)
    Nt = prob.sim["Nt"]; M = prob.sim["M"]
    J_dB = Vector{Float64}(undef, n_trials)
    for t in 1:n_trials
        rng = MersenneTwister(rng_base + t)
        n = randn(rng, Nt * M)
        phi_pert = phi_opt_vec .+ sigma .* n
        phi_mat = reshape(phi_pert, Nt, M)
        uω0_shaped = prob.uω0 .* cis.(phi_mat)
        J_lin, _ = cost_and_gradient(uω0_shaped, prob.uω0, prob.fiber,
                                      prob.sim, prob.band_mask;
                                      log_cost = false,
                                      λ_gdd = 0.0, λ_boundary = 0.0)
        J_dB[t] = 10 * log10(max(J_lin, 1e-30))
    end
    return J_dB
end

"""
    sigma_3dB(sigmas, J_pert_dB, J_base_dB)

Linearly interpolate the σ at which mean(J_pert_dB) exceeds J_base_dB + 3.
Returns `+Inf` if no σ degrades by ≥ 3 dB across the scan (flat basin), and
`0.0` if even the smallest σ degrades ≥ 3 dB (very sharp).
"""
function sigma_3dB(sigmas::AbstractVector, mean_J_pert_dB::AbstractVector,
                   J_base_dB::Real)
    target = J_base_dB + 3.0
    # we want first σ index where mean_J_pert_dB[i] >= target
    for i in 1:length(sigmas)
        if mean_J_pert_dB[i] >= target
            if i == 1; return sigmas[1]; end
            # linear interp in σ between i-1 and i on J
            x1, x2 = sigmas[i-1], sigmas[i]
            y1, y2 = mean_J_pert_dB[i-1], mean_J_pert_dB[i]
            return x1 + (target - y1) / (y2 - y1) * (x2 - x1)
        end
    end
    return Inf
end

# Shared prob built once (config identical across all cells in slim A/B).
function main()
    @assert isfile(SRS_IN_PATH) "Missing input: $SRS_IN_PATH. Run sharp_ab_slim.jl first."
    ab = JLD2.load(SRS_IN_PATH)
    results = ab["results"]
    lambdas = ab["lambdas"]
    config_kwargs = ab["config"].kwargs

    @info @sprintf("robustness: %d lambdas × %d sigmas × %d trials",
                    length(lambdas), length(SRS_SIGMAS), SRS_N_TRIALS)
    @info @sprintf("threads=%d", Threads.nthreads())

    prob = let
        uω0, fiber, sim, band_mask, Δf, raman_threshold =
            setup_raman_problem(; config_kwargs...)
        (uω0 = uω0, fiber = fiber, sim = sim, band_mask = band_mask,
         Δf = Δf, raman_threshold = raman_threshold)
    end

    # per-lambda: matrix J[sigma_idx, trial]
    J_grid = Array{Float64,3}(undef, length(lambdas), length(SRS_SIGMAS), SRS_N_TRIALS)

    tasks = [(li, si) for li in 1:length(lambdas), si in 1:length(SRS_SIGMAS)]
    tasks = vec(tasks)

    # Thread across (lambda, sigma) pairs. Each task builds its own prob copy
    # to avoid zsave mutation races.
    t0 = time()
    @threads for k in 1:length(tasks)
        li, si = tasks[k]
        phi_opt = results[li].phi_opt
        λ = lambdas[li]
        σ = SRS_SIGMAS[si]
        uω0_l, fiber_l, sim_l, band_mask_l, Δf_l, rt_l =
            setup_raman_problem(; config_kwargs...)
        prob_l = (uω0 = uω0_l, fiber = fiber_l, sim = sim_l,
                  band_mask = band_mask_l, Δf = Δf_l, raman_threshold = rt_l)
        rng_base = SRS_SEED_BASE + 1000*li + 100*si
        Js = perturbation_J(phi_opt, prob_l; sigma = σ,
                             n_trials = SRS_N_TRIALS, rng_base = rng_base)
        J_grid[li, si, :] = Js
        @info @sprintf("λ=%s σ=%.3f  mean ΔJ=%+.2f dB",
                        string(λ), σ, mean(Js) - results[li].J_final_dB)
        flush(stdout)
    end

    mean_J = dropdims(mean(J_grid; dims=3); dims=3)  # [lambda, sigma]
    std_J  = dropdims(std(J_grid;  dims=3); dims=3)

    sigma_3dB_per_lambda = [sigma_3dB(SRS_SIGMAS, view(mean_J, li, :),
                                      results[li].J_final_dB)
                            for li in 1:length(lambdas)]

    JLD2.jldsave(SRS_OUT_PATH;
        version          = SRS_VERSION,
        lambdas          = lambdas,
        sigmas           = SRS_SIGMAS,
        n_trials         = SRS_N_TRIALS,
        J_grid           = J_grid,
        mean_J           = mean_J,
        std_J            = std_J,
        J_base_per_lambda = [r.J_final_dB for r in results],
        sigma_3dB_per_lambda = sigma_3dB_per_lambda,
        total_wall_s     = time() - t0,
    )
    @info "wrote $SRS_OUT_PATH"

    @info "σ_3dB per lambda:"
    for (λ, σ3) in zip(lambdas, sigma_3dB_per_lambda)
        @info @sprintf("  λ=%s  σ_3dB=%.4f rad", string(λ), σ3)
    end
end

end  # include guard

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
