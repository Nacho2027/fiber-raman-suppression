"""
Phase 22 shared library — sharpness-aware objective sweep on two operating
points (full-resolution canonical + reduced-basis Pareto point).

This file is session-owned (`scripts/sharpness_*`) and only consumes shared
project code read-only.
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using LinearAlgebra
using Statistics
using Random
using FFTW
using JLD2
using Dates
using Optim
using Arpack

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "sharpness_optimization.jl"))
include(joinpath(@__DIR__, "phase13_hvp.jl"))
include(joinpath(@__DIR__, "phase13_hessian_eigspec.jl"))
include(joinpath(@__DIR__, "sweep_simple_param.jl"))

if !(@isdefined _SHARPNESS_PHASE22_LIB_LOADED)
const _SHARPNESS_PHASE22_LIB_LOADED = true

const S22_VERSION = "1.0.0"
const S22_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase22")
const S22_RUNS_DIR = joinpath(S22_RESULTS_DIR, "runs")
const S22_IMAGES_DIR = joinpath(@__DIR__, "..", ".planning", "phases",
                                "22-sharpness-research", "images")

const S22_MAX_ITER = 60
const S22_SIGMA_SCAN = [0.01, 0.025, 0.05, 0.075, 0.10, 0.15, 0.20]
const S22_SIGMA_TRIALS = 12
const S22_TRACE_NSAMPLES = 4
const S22_TRACE_EPS = 1e-3
const S22_MC_PAIRS = 2                      # total K = 4 perturbations
const S22_HVP_EPS = 1e-4
const S22_EIG_K = 20

const S22_SAM_RHOS = [0.01, 0.025, 0.05, 0.10]
const S22_TRACE_LAMBDAS = [1e-4, 3e-4, 1e-3, 3e-3]
const S22_MC_SIGMAS = [0.01, 0.025, 0.05, 0.075]

const S22_OP_CANONICAL = (
    id = "smf28_canonical",
    label = "SMF-28 canonical (full)",
    kind = :full,
    fiber_name = "SMF28",
    fiber_preset = :SMF28,
    L_m = 0.5,
    P_W = 0.05,
    Nt = 2^13,
    time_window = 10.0,
    beta_order = 3,
    gamma_user = 1.1e-3,
    betas_user = [-2.17e-26, 1.2e-40],
    fR = 0.18,
    pulse_fwhm = 185e-15,
    pulse_rep_rate = 80.5e6,
    tag_prefix = "smf28_canonical",
)

const S22_OP_PARETO57 = (
    id = "smf28_pareto57",
    label = "SMF-28 Pareto Nphi=57",
    kind = :lowres,
    fiber_name = "SMF28",
    fiber_preset = :SMF28,
    L_m = 0.25,
    P_W = 0.10,
    Nt = 2^14,
    time_window = 10.0,
    beta_order = 3,
    N_phi = 57,
    basis_kind = :cubic,
    tag_prefix = "smf28_pareto57",
)

lin_to_dB_safe(x) = 10 * log10(max(x, 1e-15))

struct S22HVPOperator{F, V}
    n::Int
    oracle::F
    x0::V
    eps::Float64
end

Base.size(H::S22HVPOperator) = (H.n, H.n)
Base.size(H::S22HVPOperator, d::Integer) = d <= 2 ? H.n : 1
Base.eltype(::S22HVPOperator{F, V}) where {F, V} = Float64
LinearAlgebra.issymmetric(::S22HVPOperator) = true
LinearAlgebra.ishermitian(::S22HVPOperator) = true

function LinearAlgebra.mul!(y::AbstractVector, H::S22HVPOperator, v::AbstractVector)
    if norm(v) <= 1e-15
        fill!(y, 0.0)
    else
        y .= fd_hvp(H.x0, collect(v), H.oracle; eps=H.eps)
    end
    return y
end

function _mkdirs()
    mkpath(S22_RESULTS_DIR)
    mkpath(S22_RUNS_DIR)
    mkpath(S22_IMAGES_DIR)
    return nothing
end

"""
    build_problem(op_cfg) -> NamedTuple

Build the read-only simulation/problem tuple for one operating point.
"""
function build_problem(op_cfg)
    if op_cfg.kind === :full
        return make_sharp_problem(
            fiber_preset = op_cfg.fiber_preset,
            L_fiber = op_cfg.L_m,
            P_cont = op_cfg.P_W,
            Nt = op_cfg.Nt,
            time_window = op_cfg.time_window,
            β_order = op_cfg.beta_order,
            gamma_user = op_cfg.gamma_user,
            betas_user = op_cfg.betas_user,
            fR = op_cfg.fR,
            pulse_fwhm = op_cfg.pulse_fwhm,
            pulse_rep_rate = op_cfg.pulse_rep_rate,
        )
    else
        return make_sharp_problem(
            fiber_preset = op_cfg.fiber_preset,
            L_fiber = op_cfg.L_m,
            P_cont = op_cfg.P_W,
            Nt = op_cfg.Nt,
            time_window = op_cfg.time_window,
            β_order = op_cfg.beta_order,
        )
    end
end

function _lift_phase(op, x::AbstractVector{<:Real})
    if op.kind === :full
        @assert length(x) == op.Nt "full-control length mismatch"
        return reshape(copy(x), op.Nt, 1)
    else
        @assert length(x) == op.N_phi "low-res control length mismatch"
        return reshape(op.B * x, op.Nt, 1)
    end
end

function _pullback_grad(op, grad_phi::AbstractMatrix{<:Real})
    if op.kind === :full
        return vec(copy(grad_phi))
    else
        return vec(op.B' * grad_phi)
    end
end

function _copy_prob(prob)
    fiber_local = deepcopy(prob.fiber)
    fiber_local["zsave"] = nothing
    return (
        uω0 = prob.uω0,
        fiber = fiber_local,
        sim = prob.sim,
        band_mask = prob.band_mask,
        Δf = prob.Δf,
        raman_threshold = prob.raman_threshold,
        band_mask_input = prob.band_mask_input,
        omega = prob.omega,
        gauge_projector = prob.gauge_projector,
    )
end

function _eval_costgrad_phi(phi, prob; log_cost::Bool=true)
    return cost_and_gradient(phi, prob.uω0, prob.fiber, prob.sim, prob.band_mask;
                             log_cost = log_cost, λ_gdd = 0.0, λ_boundary = 0.0)
end

function _eval_plain_J_dB(phi, prob)
    J_lin, _ = _eval_costgrad_phi(phi, prob; log_cost=false)
    return lin_to_dB_safe(J_lin)
end

function _normalize_projected_direction(grad_phi, prob)
    d = prob.gauge_projector(vec(grad_phi))
    nrm = norm(d)
    if nrm <= 1e-12
        return zeros(length(d))
    end
    return d ./ nrm
end

function _antithetic_noise_bank(seed::Integer, shape::Tuple{Int, Int}, σ::Real; npairs::Int=S22_MC_PAIRS)
    rng = MersenneTwister(seed)
    bank = Matrix{Float64}[]
    for _ in 1:npairs
        z = σ .* randn(rng, shape...)
        push!(bank, z)
        push!(bank, -z)
    end
    return bank
end

function _plain_lossgrad_x(x, op, prob; log_cost::Bool=true)
    phi = _lift_phase(op, x)
    J, grad_phi = _eval_costgrad_phi(phi, prob; log_cost=log_cost)
    return J, _pullback_grad(op, grad_phi), phi
end

function _sam_lossgrad_x(x, op, prob, ρ::Real; log_cost::Bool=true)
    phi = _lift_phase(op, x)
    _, grad_phi = _eval_costgrad_phi(phi, prob; log_cost=log_cost)
    d_hat = reshape(_normalize_projected_direction(grad_phi, prob), size(phi))
    phi_adv = phi .+ ρ .* d_hat
    J_adv, grad_adv = _eval_costgrad_phi(phi_adv, prob; log_cost=log_cost)
    return J_adv, _pullback_grad(op, grad_adv), phi
end

function _trace_lossgrad_x(x, op, prob, λ::Real, seed::Integer; log_cost::Bool=true)
    phi = _lift_phase(op, x)
    J_sharp, grad_sharp = cost_and_gradient_sharp(
        phi, prob.uω0, prob.fiber, prob.sim, prob.band_mask;
        lambda_sharp = λ,
        n_samples = S22_TRACE_NSAMPLES,
        eps = S22_TRACE_EPS,
        rng = MersenneTwister(seed),
        log_cost = log_cost,
        λ_gdd = 0.0,
        λ_boundary = 0.0,
        gauge_projector = prob.gauge_projector,
    )
    return J_sharp, _pullback_grad(op, grad_sharp), phi
end

function _mc_lossgrad_x(x, op, prob, σ::Real, seed::Integer; log_cost::Bool=true)
    phi = _lift_phase(op, x)
    bank = _antithetic_noise_bank(seed, size(phi), σ)
    J_sum = 0.0
    grad_sum = zeros(Float64, length(x))
    for noise in bank
        Jk, grad_phi = _eval_costgrad_phi(phi .+ noise, prob; log_cost=log_cost)
        J_sum += Jk
        grad_sum .+= _pullback_grad(op, grad_phi)
    end
    K = length(bank)
    return J_sum / K, grad_sum ./ K, phi
end

function _objective_dispatch(x, op, prob, flavor::Symbol, strength::Real, seed::Integer; log_cost::Bool=true)
    if flavor === :plain
        return _plain_lossgrad_x(x, op, prob; log_cost=log_cost)
    elseif flavor === :sam
        return _sam_lossgrad_x(x, op, prob, strength; log_cost=log_cost)
    elseif flavor === :trace
        return _trace_lossgrad_x(x, op, prob, strength, seed; log_cost=log_cost)
    elseif flavor === :mc
        return _mc_lossgrad_x(x, op, prob, strength, seed; log_cost=log_cost)
    else
        error("unknown flavor $flavor")
    end
end

function _sigma_at_threshold(sigmas::AbstractVector, median_dJ::AbstractVector, thr::Real)
    n = length(sigmas)
    @assert length(median_dJ) == n
    if median_dJ[1] >= thr
        return sigmas[1]
    end
    for i in 2:n
        if median_dJ[i] >= thr
            x0, y0 = sigmas[i-1], median_dJ[i-1]
            x1, y1 = sigmas[i], median_dJ[i]
            if y1 > y0
                return x0 + (thr - y0) * (x1 - x0) / (y1 - y0)
            else
                return x1
            end
        end
    end
    return NaN
end

function sigma_scan(phi_opt::AbstractMatrix, prob; seed::Integer,
                    sigmas::AbstractVector=S22_SIGMA_SCAN,
                    n_trials::Int=S22_SIGMA_TRIALS)
    base_J_dB = _eval_plain_J_dB(phi_opt, prob)
    n_sig = length(sigmas)
    delta = fill(NaN, n_sig, n_trials)
    for (j, σ) in enumerate(sigmas)
        for t in 1:n_trials
            rng = MersenneTwister(seed + 1000*j + t)
            noise = σ .* randn(rng, size(phi_opt)...)
            Jp = _eval_plain_J_dB(phi_opt .+ noise, prob)
            delta[j, t] = Jp - base_J_dB
        end
    end
    median_dJ = [median(view(delta, j, :)) for j in 1:n_sig]
    mean_dJ = [mean(view(delta, j, :)) for j in 1:n_sig]
    sigma_3dB = _sigma_at_threshold(sigmas, median_dJ, 3.0)
    return (
        base_J_dB = base_J_dB,
        sigmas = collect(sigmas),
        delta_J_dB = delta,
        median_delta_J_dB = median_dJ,
        mean_delta_J_dB = mean_dJ,
        sigma_3dB = sigma_3dB,
        n_trials = n_trials,
    )
end

function build_hessian_oracle(op, prob)
    return function oracle(x::AbstractVector{<:Real})
        phi = _lift_phase(op, x)
        _, grad_phi = _eval_costgrad_phi(phi, prob; log_cost=false)
        return _pullback_grad(op, grad_phi)
    end
end

function hessian_eigspectrum(x_opt::AbstractVector, op, prob;
                             eps::Real=S22_HVP_EPS, nev::Int=S22_EIG_K)
    oracle = build_hessian_oracle(op, prob)
    N = length(x_opt)

    if N <= 1024
        H, max_asym = build_full_hessian_small(collect(x_opt), oracle; eps=eps)
        @assert max_asym < 1e-4 "dense low-res Hessian is too asymmetric: $max_asym"
        F = eigen(Symmetric(H))
        λs = collect(F.values)
        V = Matrix(F.vectors)
        k = min(nev, length(λs))
        top = λs[end-k+1:end]
        bot = λs[1:k]
        V_top = V[:, end-k+1:end]
        V_bot = V[:, 1:k]
        λmax = maximum(top)
        λmin = minimum(bot)
        ratio = λmax > 0 ? abs(λmin) / λmax : NaN
        return (
            lambda_top = top,
            lambda_bottom = bot,
            lambda_max = λmax,
            lambda_min = λmin,
            ratio_absmin_to_max = ratio,
            indefinite = λmin < 0 < λmax,
            niter_top = 0,
            niter_bottom = 0,
            V_top = V_top,
            V_bottom = V_bot,
        )
    else
        nev_eff = min(nev, 10)
        H_op = S22HVPOperator(length(x_opt), oracle, collect(x_opt), Float64(eps))
        λ_top, V_top, niter_top = try
            Arpack.eigs(H_op; nev=nev_eff, which=:LR, maxiter=500, tol=1e-7)
        catch e
            @warn "Arpack top wing failed; retrying with reduced nev / looser tol" exception=(e, catch_backtrace())
            Arpack.eigs(H_op; nev=max(6, min(8, nev_eff)), which=:LR, maxiter=1500, tol=1e-6)
        end
        λ_bot, V_bot, niter_bot = try
            Arpack.eigs(H_op; nev=nev_eff, which=:SR, maxiter=500, tol=1e-7)
        catch e
            @warn "Arpack bottom wing failed; retrying with reduced nev / looser tol" exception=(e, catch_backtrace())
            Arpack.eigs(H_op; nev=max(6, min(8, nev_eff)), which=:SR, maxiter=1500, tol=1e-6)
        end

        top = real.(collect(λ_top))
        bot = real.(collect(λ_bot))
        λmax = maximum(top)
        λmin = minimum(bot)
        ratio = λmax > 0 ? abs(λmin) / λmax : NaN

        return (
            lambda_top = top,
            lambda_bottom = bot,
            lambda_max = λmax,
            lambda_min = λmin,
            ratio_absmin_to_max = ratio,
            indefinite = λmin < 0 < λmax,
            niter_top = niter_top,
            niter_bottom = niter_bot,
            V_top = Array(V_top),
            V_bottom = Array(V_bot),
        )
    end
end

function _tag_value_string(x::Real)
    s = lowercase(@sprintf("%.3e", Float64(x)))
    s = replace(s, "+" => "")
    s = replace(s, "." => "p")
    return s
end

function run_tag(op, flavor::Symbol, strength)
    if flavor === :plain
        return "$(op.tag_prefix)_plain"
    elseif flavor === :sam
        return "$(op.tag_prefix)_sam_rho$(_tag_value_string(strength))"
    elseif flavor === :trace
        return "$(op.tag_prefix)_trH_lambda$(_tag_value_string(strength))"
    elseif flavor === :mc
        return "$(op.tag_prefix)_mc_sigma$(_tag_value_string(strength))"
    else
        error("unknown flavor $flavor")
    end
end

function flavor_label(flavor::Symbol)
    flavor === :plain && return "plain"
    flavor === :sam && return "sam"
    flavor === :trace && return "trH"
    flavor === :mc && return "mc"
    return string(flavor)
end

function run_record(op, flavor::Symbol, strength::Real, x0::AbstractVector, seed::Integer;
                    max_iter::Int=S22_MAX_ITER, log_cost::Bool=true)
    prob = _copy_prob(op.prob)
    tag = run_tag(op, flavor, strength)
    t0 = time()

    if flavor === :plain && op.kind === :full
        result = optimize_spectral_phase(prob.uω0, prob.fiber, prob.sim, prob.band_mask;
                                         φ0 = _lift_phase(op, x0),
                                         max_iter = max_iter,
                                         λ_gdd = 0.0,
                                         λ_boundary = 0.0,
                                         store_trace = true,
                                         log_cost = log_cost)
        x_opt = vec(Optim.minimizer(result))
        phi_opt = reshape(x_opt, op.Nt, 1)
        J_obj = Optim.minimum(result)
        iterations = Optim.iterations(result)
        converged = Optim.converged(result)
        history = collect(Optim.f_trace(result))
    elseif flavor === :plain && op.kind === :lowres
        result = optimize_phase_lowres(prob.uω0, prob.fiber, prob.sim, prob.band_mask;
                                       N_phi = op.N_phi,
                                       kind = op.basis_kind,
                                       bandwidth_mask = op.bandwidth_mask,
                                       c0 = x0,
                                       B_precomputed = op.B,
                                       max_iter = max_iter,
                                       λ_gdd = 0.0,
                                       λ_boundary = 0.0,
                                       log_cost = log_cost,
                                       store_trace = true)
        x_opt = vec(result.c_opt)
        phi_opt = result.phi_opt
        J_obj = result.J_final
        iterations = result.iterations
        converged = result.converged
        history = collect(Optim.f_trace(result.result))
    else
        fg! = Optim.only_fg!() do F, G, x
            J, gx, _ = _objective_dispatch(x, op, prob, flavor, strength, seed; log_cost=log_cost)
            if G !== nothing
                G .= gx
            end
            if F !== nothing
                return J
            end
        end
        result = optimize(fg!, collect(x0), LBFGS(),
                          Optim.Options(iterations=max_iter, f_abstol=0.01,
                                        store_trace=true))
        x_opt = collect(Optim.minimizer(result))
        phi_opt = _lift_phase(op, x_opt)
        J_obj = Optim.minimum(result)
        iterations = Optim.iterations(result)
        converged = Optim.converged(result)
        history = collect(Optim.f_trace(result))
    end

    wall_s = time() - t0
    sigma = sigma_scan(phi_opt, prob; seed=seed + 200_000)
    J_plain_dB = _eval_plain_J_dB(phi_opt, prob)
    hess_valid = true
    hess_error = ""
    hess = (
        lambda_top = Float64[],
        lambda_bottom = Float64[],
        lambda_max = NaN,
        lambda_min = NaN,
        ratio_absmin_to_max = NaN,
        indefinite = false,
        niter_top = -1,
        niter_bottom = -1,
        V_top = zeros(Float64, length(x_opt), 0),
        V_bottom = zeros(Float64, length(x_opt), 0),
    )
    try
        hess = hessian_eigspectrum(x_opt, op, prob)
    catch e
        hess_valid = false
        hess_error = string(typeof(e), ": ", e)
        @warn "Hessian eigenspectrum failed; preserving optimization record without geometry fields" tag=tag exception=(e, catch_backtrace())
    end

    record = Dict{String, Any}(
        "version" => S22_VERSION,
        "created_at" => string(Dates.now()),
        "tag" => tag,
        "op_id" => op.id,
        "op_label" => op.label,
        "op_kind" => String(op.kind),
        "fiber_name" => op.fiber_name,
        "L_m" => op.L_m,
        "P_W" => op.P_W,
        "Nt" => op.Nt,
        "flavor" => String(flavor),
        "flavor_label" => flavor_label(flavor),
        "strength" => strength,
        "seed" => seed,
        "max_iter" => max_iter,
        "log_cost" => log_cost,
        "converged" => converged,
        "iterations" => iterations,
        "wall_s" => wall_s,
        "objective_final" => J_obj,
        "J_plain_dB" => J_plain_dB,
        "x_opt" => x_opt,
        "phi_opt" => phi_opt,
        "history" => history,
        "sigma_scan_sigmas" => sigma.sigmas,
        "sigma_scan_delta_J_dB" => sigma.delta_J_dB,
        "sigma_scan_median_delta_J_dB" => sigma.median_delta_J_dB,
        "sigma_scan_mean_delta_J_dB" => sigma.mean_delta_J_dB,
        "sigma_3dB" => sigma.sigma_3dB,
        "hessian_valid" => hess_valid,
        "hessian_error" => hess_error,
        "hessian_lambda_top" => hess.lambda_top,
        "hessian_lambda_bottom" => hess.lambda_bottom,
        "hessian_lambda_max" => hess.lambda_max,
        "hessian_lambda_min" => hess.lambda_min,
        "hessian_ratio_absmin_to_max" => hess.ratio_absmin_to_max,
        "hessian_indefinite" => hess.indefinite,
        "hessian_niter_top" => hess.niter_top,
        "hessian_niter_bottom" => hess.niter_bottom,
        "basis_kind" => hasproperty(op, :basis_kind) ? String(op.basis_kind) : "identity",
        "N_phi" => hasproperty(op, :N_phi) ? op.N_phi : op.Nt,
        "standard_image_dir" => S22_IMAGES_DIR,
        "julia_nthreads" => Threads.nthreads(),
        "fftw_nthreads" => FFTW.get_num_threads(),
        "blas_nthreads" => BLAS.get_num_threads(),
    )

    out_path = joinpath(S22_RUNS_DIR, "$(tag).jld2")
    jldsave(out_path; record)
    record["record_path"] = out_path
    return record
end

function emit_standard_images(record, op)
    prob = _copy_prob(op.prob)
    tag = record["tag"]
    phi_opt = record["phi_opt"]
    save_standard_set(phi_opt, prob.uω0, prob.fiber, prob.sim,
                      prob.band_mask, prob.Δf, prob.raman_threshold;
                      tag = tag,
                      fiber_name = op.fiber_name,
                      L_m = op.L_m,
                      P_W = op.P_W,
                      output_dir = S22_IMAGES_DIR)
    return nothing
end

function _load_pareto_seed()
    d = JLD2.load(joinpath(@__DIR__, "..", "results", "raman",
                           "phase_sweep_simple", "sweep2_LP_fiber.jld2"))
    results = d["results"]
    for r in results
        cfg = r["config"]
        fp = get(cfg, :fiber_preset, :UNKNOWN)
        L = get(cfg, :L_fiber, -1.0)
        P = get(cfg, :P_cont, -1.0)
        Nφ = get(r, "N_phi", -1)
        if fp == :SMF28 && L == 0.25 && P == 0.1 && Nφ == 57
            return (
                c_opt = Vector{Float64}(r["c_opt"]),
                phi_opt = reshape(Vector{Float64}(r["phi_opt"]), :, 1),
                J_final = Float64(r["J_final"]),
            )
        end
    end
    error("Could not find SMF28 L=0.25 P=0.10 N_phi=57 row in sweep2_LP_fiber.jld2")
end

function build_operating_points()
    _mkdirs()
    ensure_deterministic_environment(verbose=true)

    prob_a = build_problem(S22_OP_CANONICAL)
    op_a = merge(S22_OP_CANONICAL, (
        prob = prob_a,
        Nt = prob_a.sim["Nt"],
        x_seed = zeros(Float64, prob_a.sim["Nt"]),
    ))

    prob_b = build_problem(S22_OP_PARETO57)
    bw_mask = pulse_bandwidth_mask(prob_b.uω0)
    B = build_phase_basis(prob_b.sim["Nt"], S22_OP_PARETO57.N_phi;
                          kind = S22_OP_PARETO57.basis_kind,
                          bandwidth_mask = bw_mask)
    pareto_seed = _load_pareto_seed()
    @assert size(B, 1) == prob_b.sim["Nt"]
    @assert size(B, 2) == S22_OP_PARETO57.N_phi
    op_b = merge(S22_OP_PARETO57, (
        prob = prob_b,
        Nt = prob_b.sim["Nt"],
        B = B,
        bandwidth_mask = bw_mask,
        x_seed = pareto_seed.c_opt,
        phi_seed = pareto_seed.phi_opt,
        J_seed = pareto_seed.J_final,
    ))

    return Dict(:canonical => op_a, :pareto57 => op_b)
end

function build_task_grid()
    ops = build_operating_points()
    tasks = NamedTuple[]
    seed_base = 22_040_001

    push!(tasks, (op_key=:canonical, flavor=:plain, strength=0.0, seed=seed_base + 1))
    push!(tasks, (op_key=:pareto57, flavor=:plain, strength=0.0, seed=seed_base + 2))

    counter = 10
    for op_key in (:canonical, :pareto57)
        for ρ in S22_SAM_RHOS
            counter += 1
            push!(tasks, (op_key=op_key, flavor=:sam, strength=ρ, seed=seed_base + counter))
        end
        for λ in S22_TRACE_LAMBDAS
            counter += 1
            push!(tasks, (op_key=op_key, flavor=:trace, strength=λ, seed=seed_base + counter))
        end
        for σ in S22_MC_SIGMAS
            counter += 1
            push!(tasks, (op_key=op_key, flavor=:mc, strength=σ, seed=seed_base + counter))
        end
    end

    return ops, tasks
end

end # include guard
