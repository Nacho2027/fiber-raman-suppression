# ═══════════════════════════════════════════════════════════════════════════════
# Phase 14 Plan 02 — A/B comparison: vanilla vs sharpness-aware optimization
# ═══════════════════════════════════════════════════════════════════════════════
#
# READ-ONLY consumer of:
#   scripts/common.jl              — setup_raman_problem (not modified)
#   scripts/raman_optimization.jl  — optimize_spectral_phase, cost_and_gradient
#   scripts/sharpness_optimization.jl — optimize_spectral_phase_sharp, etc.
#   scripts/phase13_hvp.jl         — fd_hvp (for saddle-point diagnostic at each optimum)
#   scripts/phase13_primitives.jl  — input_band_mask, omega_vector
#   scripts/determinism.jl         — ensure_deterministic_environment (called internally)
#
# Outputs: results/raman/phase14/ab_results.jld2
#
# Config grid (3 configs × 6 lambda_sharp values including 0 = vanilla):
#   smf28_canonical:  :SMF28, L=2.0 m,  P=0.2 W,    Nt=2^13
#   hnlf_canonical:   :HNLF,  L=0.5 m,  P=5e-3 W,   Nt=2^13
#   smf28_longfiber:  :SMF28, L=5.0 m,  P=0.2 W,    Nt auto-sized by setup
#
# For each (config, lambda_sharp) cell we store:
#   - phi_opt                           (Nt×1 matrix, gauge-fixed for comparison)
#   - J_final_dB                        scalar, computed post-hoc with log_cost=true
#   - S_at_opt                          scalar, Hutchinson tr(H_phys) at phi_opt, N_s=64 for low variance
#   - wall_time_s                       scalar, optimizer wall time
#   - iterations                        Int
#   - converged                         Bool
#   - saddle-point diagnostic via power iteration on H and on -H (10 steps each):
#       lambda_max_estimate, lambda_min_estimate  (both real scalars)
#       saddle_flag                     |lambda_min|/lambda_max > 1e-4
#
# Parallelism (threading directive from 14-CONTEXT.md):
#   - Julia threads enabled at startup via --threads=auto on burst VM (22 cores).
#   - FFTW.set_num_threads(1) inside each solve (already pinned by
#     ensure_deterministic_environment in sharpness_optimization.jl).
#   - We parallelize OVER config×lambda cells (18 total). Each cell is
#     independent: it sets up its own prob, runs its own optimizer. No shared
#     mutable state.
#
# Determinism: every run uses an explicit MersenneTwister(seed) per cell so
# Hutchinson sampling is reproducible. The SAME phi_0 is used across all lambda
# values within a config (fixed seed for initial phase noise per config).
# ═══════════════════════════════════════════════════════════════════════════════

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using LinearAlgebra
using Statistics
using Random
using FFTW
using JLD2
using Dates
using Base.Threads: @threads

# Load READ-ONLY production pipeline + new sharpness library.
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "sharpness_optimization.jl"))
include(joinpath(@__DIR__, "phase13_hvp.jl"))              # brings phase13_primitives
ensure_deterministic_environment(verbose=true)

# Load wisdom if it exists (reduces cross-process FFTW drift).
const P14AB_WISDOM_PATH = joinpath(@__DIR__, "..", "results", "raman", "phase14", "fftw_wisdom.txt")
if isfile(P14AB_WISDOM_PATH)
    try
        FFTW.import_wisdom(P14AB_WISDOM_PATH)
        @info "Imported FFTW wisdom" path=P14AB_WISDOM_PATH
    catch e
        @warn "Could not import FFTW wisdom; proceeding" exception=e
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Constants (P14AB_ = Phase 14 A/B)
# ─────────────────────────────────────────────────────────────────────────────

const P14AB_VERSION = "1.0.0"
const P14AB_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase14")
const P14AB_SEED_BASE = 4202   # per-cell seed offsets from this base for RNG
const P14AB_MAX_ITER = 60      # consistent with STATE.md dB/linear fix notes (30→60 preferred)
const P14AB_LAMBDA_GDD = 1e-4
const P14AB_LAMBDA_BOUNDARY = 1.0
const P14AB_LOG_COST = true
const P14AB_N_SAMPLES_OPT = 8  # Hutchinson samples DURING optimization (fast)
const P14AB_N_SAMPLES_EVAL = 64 # post-hoc evaluation of S (low variance)
const P14AB_EPS_SHARP = 1e-3
const P14AB_POWER_ITER_STEPS = 10   # for saddle-point diagnostic
const P14AB_HVP_EPS = 1e-4          # FD step for HVP in power iteration
const P14AB_SADDLE_RATIO_THRESHOLD = 1e-4

# Integration-smoke-test mode (used locally to verify the script runs before
# wasting burst minutes). Trigger with --smoke CLI flag. In smoke mode we use
# Nt=2^8, max_iter=3, and only the first config × 2 lambda values.
const P14AB_SMOKE = any(a -> a == "--smoke", ARGS)

# Lambda grid (including 0 as the "vanilla" marker).
const P14AB_LAMBDAS = [0.0, 0.01, 0.1, 1.0, 10.0, 100.0]

# Config grid — one row per optimization run, plus its sub-configs.
function build_config_grid()
    if P14AB_SMOKE
        return [
            (id = "smf28_canonical_smoke",
             label = "SMF-28 smoke",
             kwargs = (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2,
                       Nt = 2^8, time_window = 10.0, β_order = 3)),
        ]
    end
    return [
        (id = "smf28_canonical",
         label = "SMF-28 canonical (L=2m, P=0.2W)",
         kwargs = (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2,
                   Nt = 2^13, time_window = 40.0, β_order = 3)),
        (id = "hnlf_canonical",
         label = "HNLF canonical (L=0.5m, P=5e-3W)",
         kwargs = (fiber_preset = :HNLF, L_fiber = 0.5, P_cont = 5e-3,
                   Nt = 2^13, time_window = 5.0, β_order = 3)),
        (id = "smf28_longfiber",
         label = "SMF-28 long (L=5m, P=0.2W)",
         kwargs = (fiber_preset = :SMF28, L_fiber = 5.0, P_cont = 0.2,
                   Nt = 2^13, time_window = 100.0, β_order = 3)),
    ]
end

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    compute_J_dB(phi_opt, prob) -> Float64

Re-evaluate the PURE physical cost J at phi_opt (no regularisation, no
sharpness) and return it in dB. Uses the unchanged `cost_and_gradient`.
"""
function compute_J_dB(phi_opt, prob)
    J_lin, _ = cost_and_gradient(phi_opt, prob.uω0, prob.fiber, prob.sim, prob.band_mask;
                                  log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
    J_clamped = max(J_lin, 1e-15)
    return 10 * log10(J_clamped)
end

"""
    compute_S(phi_opt, prob; n_samples, eps, rng) -> Float64

Low-variance post-hoc sharpness estimate at phi_opt. Uses the
`sharpness_estimator` primitive from Phase 14-01 with its pre-built
gauge projector (avoids per-call reconstruction).

Discards the gradient component (we only need the scalar S).
"""
function compute_S(phi_opt, prob; n_samples::Int = P14AB_N_SAMPLES_EVAL,
                   eps::Real = P14AB_EPS_SHARP, rng::AbstractRNG)
    oracle = let uω0 = prob.uω0, fiber = prob.fiber, sim = prob.sim, band_mask = prob.band_mask
        phi_in -> cost_and_gradient(phi_in, uω0, fiber, sim, band_mask;
                                     log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
    end
    result = sharpness_estimator(phi_opt, oracle, prob.gauge_projector;
                                  eps=eps, n_samples=n_samples, rng=rng)
    return result.S
end

"""
    build_grad_oracle_vec(prob) -> Function

Return `oracle(phi_flat::Vector) -> Vector` that computes the gradient of the
PURE physical cost (no regularization) at the given phase, flattened. Matches
the signature phase13_hvp.jl :: fd_hvp expects.
"""
function build_grad_oracle_vec(prob)
    uω0 = prob.uω0
    fiber = prob.fiber
    sim = prob.sim
    band_mask = prob.band_mask
    phi_shape = size(uω0)
    # ensure zsave=nothing (avoids internal deepcopy path)
    fiber["zsave"] = nothing
    return function grad_oracle(phi_flat::AbstractVector{<:Real})
        phi_mat = reshape(copy(phi_flat), phi_shape)
        _, grad = cost_and_gradient(phi_mat, uω0, fiber, sim, band_mask;
                                     log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
        return vec(copy(grad))
    end
end

"""
    power_iteration_hessian(phi_opt, prob; which, steps, eps, rng) -> Float64

Power iteration on the Hessian (for `which = :max`) or on -H (for `which = :min`)
using the symmetric-FD HVP from `scripts/phase13_hvp.jl :: fd_hvp`. Returns
the Rayleigh-quotient estimate of the extreme eigenvalue.

For `:min` we power-iterate `v ← -(H v) + shift*v` but simpler: iterate on
(σI - H) for a large σ = lambda_max_estimate, then lambda_min = σ - top_eig(σI−H).
However to keep this modular and well-understood, we use the standard trick:

    - For :max, iterate  v ← Hv / ||Hv||  ; λ = v' H v.
    - For :min, shift: pick σ = 2 * lambda_max_estimate and iterate
      v ← (σ·v - Hv) / ||·||; the top eigval of (σI-H) is σ - λ_min, so
      λ_min = σ - top_eig_of(σI-H). 10 steps gives a reasonable estimate
      on a well-conditioned problem at an optimum; deeper accuracy is
      not needed for the saddle_flag test (|λ_min|/λ_max > 1e-4).
"""
function power_iteration_max(phi_flat::AbstractVector{<:Real}, grad_oracle;
                              steps::Int = P14AB_POWER_ITER_STEPS,
                              eps::Real = P14AB_HVP_EPS,
                              rng::AbstractRNG)
    N = length(phi_flat)
    v = randn(rng, N)
    v ./= norm(v)
    λ = 0.0
    for _ in 1:steps
        Hv = fd_hvp(phi_flat, v, grad_oracle; eps=eps)
        nHv = norm(Hv)
        if nHv <= 0
            break
        end
        # Rayleigh quotient BEFORE renormalizing v — uses the current iterate.
        λ = dot(v, Hv)
        v = Hv ./ nHv
    end
    # One final Rayleigh quotient at the converged v (one extra HVP).
    Hv_final = fd_hvp(phi_flat, v, grad_oracle; eps=eps)
    λ = dot(v, Hv_final)
    return λ, v
end

function power_iteration_min(phi_flat::AbstractVector{<:Real}, grad_oracle,
                              lambda_max_est::Real;
                              steps::Int = P14AB_POWER_ITER_STEPS,
                              eps::Real = P14AB_HVP_EPS,
                              rng::AbstractRNG)
    # Shift by σ = 2|λ_max|+1 so (σI - H) is positive definite and its top
    # eigenvalue is σ - λ_min. We then recover λ_min = σ - top_eig(σI-H).
    σ = 2 * abs(lambda_max_est) + 1.0
    N = length(phi_flat)
    v = randn(rng, N)
    v ./= norm(v)
    λ_shifted = 0.0
    for _ in 1:steps
        Hv = fd_hvp(phi_flat, v, grad_oracle; eps=eps)
        Av = σ .* v .- Hv            # (σI - H)v
        nAv = norm(Av)
        if nAv <= 0
            break
        end
        λ_shifted = dot(v, Av)       # Rayleigh of shifted operator at current v
        v = Av ./ nAv
    end
    # Final Rayleigh at converged v.
    Hv_final = fd_hvp(phi_flat, v, grad_oracle; eps=eps)
    Av_final = σ .* v .- Hv_final
    λ_shifted = dot(v, Av_final)
    λ_min_est = σ - λ_shifted
    return λ_min_est, v
end

# ─────────────────────────────────────────────────────────────────────────────
# Per-cell run: one (config, lambda_sharp) combination
# ─────────────────────────────────────────────────────────────────────────────

function run_cell(config, lambda_sharp::Real, cell_idx::Int; max_iter::Int,
                  n_samples_opt::Int, eps_sharp::Real)
    t0 = time()

    # Seed derived from cell index + base; gives identical Rademacher sequences
    # across re-runs but different across cells.
    rng = MersenneTwister(P14AB_SEED_BASE + cell_idx)

    # Build problem + gauge projector (same setup for all lambdas within a config;
    # but we rebuild here because prob.fiber's "zsave" is mutated inside the
    # optimizer and we want each cell fully isolated for --threads=auto safety).
    prob = make_sharp_problem(; config.kwargs...)
    Nt = prob.sim["Nt"]
    M = prob.sim["M"]

    # Initial phase: zero (uniform across cells so A/B is apples-to-apples).
    phi0 = zeros(Nt, M)

    # Run optimizer ----------------------------------------------------------
    #
    # lambda_sharp == 0 short-circuits `cost_and_gradient_sharp` to the vanilla
    # oracle — this is why 14-01 Test 1 holds byte-identity at lambda=0. We
    # still go through `optimize_spectral_phase_sharp` for a uniform code path,
    # but the numerics are identical to `optimize_spectral_phase` + unchanged
    # regularization.
    opt = optimize_spectral_phase_sharp(prob, phi0;
                                         lambda_sharp = lambda_sharp,
                                         n_samples = n_samples_opt,
                                         eps = eps_sharp,
                                         rng = rng,
                                         max_iter = max_iter,
                                         log_cost = P14AB_LOG_COST,
                                         λ_gdd = P14AB_LAMBDA_GDD,
                                         λ_boundary = P14AB_LAMBDA_BOUNDARY,
                                         store_trace = false)

    phi_opt = opt.phi_opt

    # Physical J (dB) at phi_opt, with NO regularization (pure J physics).
    J_final_dB = compute_J_dB(phi_opt, prob)

    # Low-variance S post-hoc. Use a fresh RNG so the value is independent
    # of whatever the optimizer drew during its iterations.
    rng_eval = MersenneTwister(P14AB_SEED_BASE + 7919 + cell_idx)
    S_at_opt = compute_S(phi_opt, prob; n_samples = P14AB_N_SAMPLES_EVAL,
                          eps = eps_sharp, rng = rng_eval)

    # ── Saddle-point diagnostic (power iteration on H and on -H) ────────────
    #
    # Per Phase 13 FINDINGS.md the vanilla L-BFGS optima are saddle points.
    # We want to know: for lambda_sharp > 0 does the sharpness penalty push
    # the optimizer to points with smaller |lambda_min|/lambda_max?
    grad_oracle = build_grad_oracle_vec(prob)
    phi_opt_flat = vec(phi_opt)
    rng_pi_max = MersenneTwister(P14AB_SEED_BASE + 11117 + cell_idx)
    rng_pi_min = MersenneTwister(P14AB_SEED_BASE + 22229 + cell_idx)
    λ_max_est, _ = power_iteration_max(phi_opt_flat, grad_oracle;
                                        steps = P14AB_POWER_ITER_STEPS,
                                        eps = P14AB_HVP_EPS, rng = rng_pi_max)
    λ_min_est, _ = power_iteration_min(phi_opt_flat, grad_oracle, λ_max_est;
                                        steps = P14AB_POWER_ITER_STEPS,
                                        eps = P14AB_HVP_EPS, rng = rng_pi_min)
    saddle_ratio = (λ_max_est != 0) ? abs(λ_min_est) / abs(λ_max_est) : 0.0
    saddle_flag = saddle_ratio > P14AB_SADDLE_RATIO_THRESHOLD && (λ_min_est < 0)

    cell_wall = time() - t0

    # Log one-liner for this cell (safe for @threads: @info is thread-safe).
    @info @sprintf("[cell %d] config=%s λ=%g  J=%.3f dB  S=%.3e  saddle=%s  (λmax=%.3e λmin=%.3e ratio=%.2e)  %.1fs",
                   cell_idx, config.id, lambda_sharp, J_final_dB, S_at_opt,
                   saddle_flag ? "Y" : "N", λ_max_est, λ_min_est, saddle_ratio,
                   cell_wall)

    return (
        config_id = config.id,
        config_label = config.label,
        lambda_sharp = lambda_sharp,
        phi_opt = phi_opt,
        J_final_dB = J_final_dB,
        S_at_opt = S_at_opt,
        lambda_max_estimate = λ_max_est,
        lambda_min_estimate = λ_min_est,
        saddle_ratio = saddle_ratio,
        saddle_flag = saddle_flag,
        wall_time_s = opt.wall_time,
        cell_wall_s = cell_wall,
        iterations = opt.iterations,
        converged = opt.converged,
        n_samples = opt.n_samples,
        eps_sharpness = opt.eps_sharpness,
        Nt = Nt,
        M = M,
        seed_cell = P14AB_SEED_BASE + cell_idx,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Main driver
# ─────────────────────────────────────────────────────────────────────────────

function main()
    mkpath(P14AB_RESULTS_DIR)
    out_path = joinpath(P14AB_RESULTS_DIR, P14AB_SMOKE ? "ab_results_smoke.jld2" : "ab_results.jld2")

    configs = build_config_grid()
    lambdas = P14AB_SMOKE ? [0.0, 0.1] : P14AB_LAMBDAS
    max_iter = P14AB_SMOKE ? 3 : P14AB_MAX_ITER

    @info "Phase 14 Plan 02 A/B comparison" version=P14AB_VERSION configs=length(configs) lambdas=length(lambdas) cells=length(configs)*length(lambdas) max_iter=max_iter smoke=P14AB_SMOKE
    @info @sprintf("Julia threads: %d, FFTW threads: %d, BLAS threads: %d",
                    Threads.nthreads(), FFTW.get_num_threads(), BLAS.get_num_threads())

    # Build the flat cell list so @threads can chew through it.
    cells = Tuple{Int, Any, Float64}[]
    idx = 0
    for cfg in configs
        for λ in lambdas
            idx += 1
            push!(cells, (idx, cfg, λ))
        end
    end

    results = Vector{Any}(undef, length(cells))
    t_start = time()

    @threads for i in 1:length(cells)
        cell_idx, cfg, λ = cells[i]
        try
            results[i] = run_cell(cfg, λ, cell_idx;
                                  max_iter = max_iter,
                                  n_samples_opt = P14AB_N_SAMPLES_OPT,
                                  eps_sharp = P14AB_EPS_SHARP)
        catch e
            @error "Cell $cell_idx (config=$(cfg.id), λ=$λ) failed" exception=(e, catch_backtrace())
            # Store a failure sentinel so downstream consumers can skip cleanly.
            results[i] = (
                config_id = cfg.id,
                config_label = cfg.label,
                lambda_sharp = λ,
                error = string(e),
                failed = true,
            )
        end
    end
    total_wall = time() - t_start
    @info @sprintf("All cells completed in %.1f s (wall)", total_wall)

    # ── Serialise ────────────────────────────────────────────────────────────
    # JLD2 cannot store NamedTuples with arbitrary field types directly in
    # every version; dump each field into a per-key dict of vectors/matrices
    # so the file reads back trivially.

    n = length(results)
    config_ids    = fill("", n)
    config_labels = fill("", n)
    lambdas_out   = fill(0.0, n)
    phi_opts      = Vector{Matrix{Float64}}(undef, n)
    J_finals_dB   = fill(NaN, n)
    S_at_opts     = fill(NaN, n)
    lambda_maxs   = fill(NaN, n)
    lambda_mins   = fill(NaN, n)
    saddle_ratios = fill(NaN, n)
    saddle_flags  = fill(false, n)
    wall_times    = fill(NaN, n)
    cell_walls    = fill(NaN, n)
    iterations    = fill(0, n)
    converged     = fill(false, n)
    failed_flags  = fill(false, n)
    seeds_cell    = fill(0, n)
    Nts           = fill(0, n)
    Ms            = fill(0, n)

    for i in 1:n
        r = results[i]
        # r is a NamedTuple; hasproperty returns true only for the error sentinel path.
        if hasproperty(r, :failed) && r.failed
            config_ids[i] = r.config_id
            config_labels[i] = r.config_label
            lambdas_out[i] = r.lambda_sharp
            failed_flags[i] = true
            phi_opts[i] = zeros(0, 0)
            continue
        end
        config_ids[i] = r.config_id
        config_labels[i] = r.config_label
        lambdas_out[i] = r.lambda_sharp
        phi_opts[i] = r.phi_opt
        J_finals_dB[i] = r.J_final_dB
        S_at_opts[i] = r.S_at_opt
        lambda_maxs[i] = r.lambda_max_estimate
        lambda_mins[i] = r.lambda_min_estimate
        saddle_ratios[i] = r.saddle_ratio
        saddle_flags[i] = r.saddle_flag
        wall_times[i] = r.wall_time_s
        cell_walls[i] = r.cell_wall_s
        iterations[i] = r.iterations
        converged[i] = r.converged
        seeds_cell[i] = r.seed_cell
        Nts[i] = r.Nt
        Ms[i] = r.M
    end

    jldsave(out_path;
        # Identification
        phase = "14", plan = "02", script = "ab_comparison",
        version = P14AB_VERSION,
        created_at = string(Dates.now()),
        smoke_mode = P14AB_SMOKE,
        # Grid metadata
        config_ids_unique = unique(config_ids),
        lambdas_unique = unique(lambdas_out),
        n_configs = length(configs),
        n_lambdas = length(lambdas),
        # Per-cell rows (parallel arrays)
        config_id = config_ids,
        config_label = config_labels,
        lambda_sharp = lambdas_out,
        phi_opt = phi_opts,
        J_final_dB = J_finals_dB,
        S_at_opt = S_at_opts,
        lambda_max_estimate = lambda_maxs,
        lambda_min_estimate = lambda_mins,
        saddle_ratio = saddle_ratios,
        saddle_flag = saddle_flags,
        wall_time_s = wall_times,
        cell_wall_s = cell_walls,
        iterations = iterations,
        converged = converged,
        failed = failed_flags,
        seed_cell = seeds_cell,
        Nt = Nts,
        M = Ms,
        # Hyperparameters
        max_iter = max_iter,
        n_samples_opt = P14AB_N_SAMPLES_OPT,
        n_samples_eval = P14AB_N_SAMPLES_EVAL,
        eps_sharpness = P14AB_EPS_SHARP,
        lambda_gdd = P14AB_LAMBDA_GDD,
        lambda_boundary = P14AB_LAMBDA_BOUNDARY,
        log_cost = P14AB_LOG_COST,
        hvp_eps = P14AB_HVP_EPS,
        power_iter_steps = P14AB_POWER_ITER_STEPS,
        saddle_ratio_threshold = P14AB_SADDLE_RATIO_THRESHOLD,
        # Threading metadata
        julia_nthreads = Threads.nthreads(),
        fftw_nthreads = FFTW.get_num_threads(),
        blas_nthreads = BLAS.get_num_threads(),
        total_wall_s = total_wall,
    )
    @info "Results written" path=out_path

    # Export wisdom for regression / downstream reuse.
    try
        FFTW.export_wisdom(P14AB_WISDOM_PATH)
        @info "Exported FFTW wisdom" path=P14AB_WISDOM_PATH
    catch e
        @warn "Could not export FFTW wisdom" exception=e
    end

    return out_path
end

# Entry-point guard for when this file is `include`d.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
