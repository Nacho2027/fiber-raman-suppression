# ═══════════════════════════════════════════════════════════════════════════════
# Phase 14 Plan 02 — Robustness test (Gaussian phase perturbation)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Loads each (config, lambda_sharp) optimum from ab_results.jld2, applies
# Gaussian noise perturbations  φ ← φ + σ·n  with  σ ∈ {0.01, 0.05, 0.1, 0.2}
# radians and 10 trials each, and evaluates the PHYSICAL cost J at each
# perturbed phase via the unchanged `cost_and_gradient` (no optimization).
#
# The question: do sharpness-aware optima have wider, more robust basins that
# degrade more gracefully than the vanilla (λ=0) optimum?
#
# Outputs: results/raman/phase14/robustness_results.jld2
#   - per-(cell, σ, trial): J_perturbed_dB, delta_J_dB
#   - per-(cell, σ) aggregated: mean, max, stdev of delta_J_dB across trials
#
# Parallelism: @threads over the flattened (cell × σ × trial) list. Each
# task is one forward propagation — cheap. No per-task setup cost because we
# build the prob ONCE per unique config_id and share it (read-only access to
# uω0/fiber/sim/band_mask is thread-safe — no mutation happens during a
# forward-only J evaluation). The `fiber["zsave"]` key is set to `nothing`
# before any threaded work starts.
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

# Load READ-ONLY production pipeline.
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "sharpness_optimization.jl"))
ensure_deterministic_environment(verbose=true)

const P14RB_WISDOM_PATH = joinpath(@__DIR__, "..", "results", "raman", "phase14", "fftw_wisdom.txt")
if isfile(P14RB_WISDOM_PATH)
    try
        FFTW.import_wisdom(P14RB_WISDOM_PATH)
        @info "Imported FFTW wisdom" path=P14RB_WISDOM_PATH
    catch e
        @warn "Could not import FFTW wisdom" exception=e
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Constants (P14RB_ = Phase 14 RoBustness)
# ─────────────────────────────────────────────────────────────────────────────

const P14RB_VERSION = "1.0.0"
const P14RB_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase14")
const P14RB_SEED_BASE = 5202
const P14RB_N_TRIALS = 10
const P14RB_SIGMAS = [0.01, 0.05, 0.1, 0.2]

# Re-use the same config grid as the A/B script so we can rebuild prob objects
# (uω0, fiber, sim, band_mask) from the config_id strings saved in ab_results.jld2.
const P14RB_CONFIG_REGISTRY = Dict(
    "smf28_canonical" =>
        (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2,
         Nt = 2^13, time_window = 40.0, β_order = 3),
    "hnlf_canonical" =>
        (fiber_preset = :HNLF, L_fiber = 0.5, P_cont = 5e-3,
         Nt = 2^13, time_window = 5.0, β_order = 3),
    "smf28_longfiber" =>
        (fiber_preset = :SMF28, L_fiber = 5.0, P_cont = 0.2,
         Nt = 2^13, time_window = 100.0, β_order = 3),
    "smf28_canonical_smoke" =>
        (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2,
         Nt = 2^8, time_window = 10.0, β_order = 3),
)

const P14RB_SMOKE = any(a -> a == "--smoke", ARGS)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    compute_J_dB(phi, prob) -> Float64

Re-evaluate the PURE physical cost J at phi (no regularisation) and return
it in dB. `prob` is a NamedTuple with uω0, fiber, sim, band_mask.
"""
function compute_J_dB(phi, prob)
    J_lin, _ = cost_and_gradient(phi, prob.uω0, prob.fiber, prob.sim, prob.band_mask;
                                  log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
    J_clamped = max(J_lin, 1e-15)
    return 10 * log10(J_clamped)
end

# ─────────────────────────────────────────────────────────────────────────────
# Main driver
# ─────────────────────────────────────────────────────────────────────────────

function main()
    # Input file from Task 1.
    ab_path = joinpath(P14RB_RESULTS_DIR, P14RB_SMOKE ? "ab_results_smoke.jld2" : "ab_results.jld2")
    @assert isfile(ab_path) "A/B results not found at $ab_path — run ab_comparison.jl first"
    out_path = joinpath(P14RB_RESULTS_DIR, P14RB_SMOKE ? "robustness_results_smoke.jld2" : "robustness_results.jld2")

    ab = JLD2.load(ab_path)

    config_ids    = ab["config_id"]::Vector{String}
    config_labels = ab["config_label"]::Vector{String}
    lambdas       = ab["lambda_sharp"]::Vector{Float64}
    phi_opts      = ab["phi_opt"]::Vector{Matrix{Float64}}
    J_finals_dB   = ab["J_final_dB"]::Vector{Float64}
    failed_flags  = ab["failed"]::Vector{Bool}
    n_cells = length(config_ids)
    @info "Loaded A/B results" path=ab_path n_cells=n_cells failed=sum(failed_flags)

    # Build a prob per unique config_id ONCE (read-only across threads).
    unique_cfg_ids = unique(config_ids)
    probs = Dict{String, Any}()
    for cid in unique_cfg_ids
        @assert haskey(P14RB_CONFIG_REGISTRY, cid) "unknown config_id $cid — update P14RB_CONFIG_REGISTRY"
        kwargs = P14RB_CONFIG_REGISTRY[cid]
        prob = make_sharp_problem(; kwargs...)
        # Make sure zsave is cleared so forward solver skips deepcopy.
        prob.fiber["zsave"] = nothing
        probs[cid] = prob
        @info "Built prob" config_id=cid Nt=prob.sim["Nt"] M=prob.sim["M"]
    end

    sigmas = P14RB_SMOKE ? [0.05, 0.1] : P14RB_SIGMAS
    n_trials = P14RB_SMOKE ? 3 : P14RB_N_TRIALS

    # Flat task list: (cell_idx, sigma_idx, trial_idx) → one forward eval.
    tasks = Tuple{Int, Int, Int}[]
    for i in 1:n_cells
        if failed_flags[i]
            continue
        end
        for (j, σ) in enumerate(sigmas)
            for t in 1:n_trials
                push!(tasks, (i, j, t))
            end
        end
    end
    n_tasks = length(tasks)
    @info "Robustness grid" n_cells=n_cells n_sigmas=length(sigmas) n_trials=n_trials total_tasks=n_tasks

    # Storage: parallel arrays, same length as tasks.
    cell_idx_arr  = fill(0, n_tasks)
    sigma_idx_arr = fill(0, n_tasks)
    trial_idx_arr = fill(0, n_tasks)
    cfg_id_arr    = fill("", n_tasks)
    lambda_arr    = fill(NaN, n_tasks)
    sigma_arr     = fill(NaN, n_tasks)
    J_perturbed_dB_arr = fill(NaN, n_tasks)
    delta_J_dB_arr = fill(NaN, n_tasks)

    t_start = time()
    @threads for k in 1:n_tasks
        i, j, t = tasks[k]
        cfg_id = config_ids[i]
        λ = lambdas[i]
        σ = sigmas[j]
        prob = probs[cfg_id]
        phi_opt = phi_opts[i]
        Nt, M = size(phi_opt)

        # Deterministic per-(cell, sigma, trial) seed.
        seed = P14RB_SEED_BASE + 1000 * i + 100 * j + t
        rng = MersenneTwister(seed)
        noise = σ .* randn(rng, Nt, M)
        phi_perturbed = phi_opt .+ noise

        J_dB = compute_J_dB(phi_perturbed, prob)

        cell_idx_arr[k]  = i
        sigma_idx_arr[k] = j
        trial_idx_arr[k] = t
        cfg_id_arr[k]    = cfg_id
        lambda_arr[k]    = λ
        sigma_arr[k]     = σ
        J_perturbed_dB_arr[k] = J_dB
        delta_J_dB_arr[k] = J_dB - J_finals_dB[i]
    end
    total_wall = time() - t_start
    @info @sprintf("All %d robustness trials done in %.1f s", n_tasks, total_wall)

    # Aggregated statistics per (cell, sigma).
    # Shape: (n_cells, n_sigmas) for each stat.
    mean_dJ_dB  = fill(NaN, n_cells, length(sigmas))
    max_dJ_dB   = fill(NaN, n_cells, length(sigmas))
    std_dJ_dB   = fill(NaN, n_cells, length(sigmas))
    for i in 1:n_cells
        failed_flags[i] && continue
        for (j, σ) in enumerate(sigmas)
            selector = (cell_idx_arr .== i) .& (sigma_idx_arr .== j)
            trials = delta_J_dB_arr[selector]
            if !isempty(trials)
                mean_dJ_dB[i, j] = mean(trials)
                max_dJ_dB[i, j]  = maximum(trials)
                std_dJ_dB[i, j]  = n_trials > 1 ? std(trials) : 0.0
            end
        end
    end

    # ── Serialise ──
    jldsave(out_path;
        # Identification
        phase = "14", plan = "02", script = "robustness_test",
        version = P14RB_VERSION,
        created_at = string(Dates.now()),
        smoke_mode = P14RB_SMOKE,
        # Sigmas + trials
        sigmas = sigmas,
        n_trials = n_trials,
        # Mapping from robustness cell index back to A/B cell
        cell_config_id = config_ids,
        cell_config_label = config_labels,
        cell_lambda_sharp = lambdas,
        cell_J_final_dB = J_finals_dB,
        cell_failed = failed_flags,
        # Flat per-trial arrays
        task_cell_idx = cell_idx_arr,
        task_sigma_idx = sigma_idx_arr,
        task_trial_idx = trial_idx_arr,
        task_config_id = cfg_id_arr,
        task_lambda_sharp = lambda_arr,
        task_sigma = sigma_arr,
        task_J_perturbed_dB = J_perturbed_dB_arr,
        task_delta_J_dB = delta_J_dB_arr,
        # Aggregated (n_cells, n_sigmas) matrices
        mean_delta_J_dB = mean_dJ_dB,
        max_delta_J_dB = max_dJ_dB,
        std_delta_J_dB = std_dJ_dB,
        # Threading metadata
        julia_nthreads = Threads.nthreads(),
        fftw_nthreads = FFTW.get_num_threads(),
        blas_nthreads = BLAS.get_num_threads(),
        total_wall_s = total_wall,
    )
    @info "Robustness results written" path=out_path
    return out_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
