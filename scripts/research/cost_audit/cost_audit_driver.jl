# scripts/research/cost_audit/cost_audit_driver.jl
# ═══════════════════════════════════════════════════════════════════════════════
# Phase 16 Plan 01 — Cost-function audit driver (12-run orchestrator)
# ═══════════════════════════════════════════════════════════════════════════════
#
# CLI: julia -t auto --project=. scripts/research/cost_audit/cost_audit_driver.jl
#
# Orchestrates 3 configs (A, B, C) × 4 variants (linear, log_dB, sharp, curvature)
# with per-run JLD2 snapshots, gauge-projected Hessian top-32 eigenspectrum, and
# robustness probe at σ ∈ {0.01, 0.05, 0.1, 0.2}.
#
# Runs on the burst VM (CLAUDE.md Rule 1) under the `burst-run-heavy` wrapper,
# which manages `/tmp/burst-heavy-lock`. Per Rule P5 (2026-04-17 update), the
# in-Julia `touch(lock)` / `rm(lock)` pattern is DEPRECATED — invoke via
# `burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy H-audit \\
#  'julia -t auto --project=. scripts/research/cost_audit/cost_audit_driver.jl'"`.
# ═══════════════════════════════════════════════════════════════════════════════

ENV["MPLBACKEND"] = "Agg"

using Random, LinearAlgebra, FFTW, Printf, Logging, Statistics, Dates
using JLD2, CSV, DataFrames, Arpack
using Optim

include(joinpath(@__DIR__, "..", "..", "lib", "determinism.jl"))
ensure_deterministic_environment()

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "sharpness_optimization.jl"))
include(joinpath(@__DIR__, "..", "phases", "phase13", "primitives.jl"))
include(joinpath(@__DIR__, "..", "phases", "phase13", "hvp.jl"))
include(joinpath(@__DIR__, "..", "phases", "phase13", "hessian_eigspec.jl"))
include(joinpath(@__DIR__, "cost_audit_noise_aware.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "visualization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "standard_images.jl"))

# FFTW wisdom (D-09; belt-and-suspenders under Phase-15 ESTIMATE).
const CA_FFTW_WISDOM_PATH = joinpath(@__DIR__, "..", "..", "..", "results", "raman",
                                     "phase14", "fftw_wisdom.txt")
const CA_FFTW_WISDOM_IMPORTED = try
    if isfile(CA_FFTW_WISDOM_PATH)
        FFTW.import_wisdom(CA_FFTW_WISDOM_PATH)
        true
    else
        false
    end
catch
    false
end

# ─────────────────────────────────────────────────────────────────────────────
# Configs (CONTEXT D-11/D-12/D-13) and variants (CONTEXT D-01..D-04)
# ─────────────────────────────────────────────────────────────────────────────

const CA_CONFIGS = [
    (tag=:A, fiber_preset=:SMF28, L_fiber=0.5, P_cont=0.05, seed=42, time_window=5.0),
    # Config B: time_window 150 ps (> auto-sizer's 135 ps SPM requirement for
    # L=5m, P=0.2W at Nt=8192) so strict_nt can hold the grid constant across
    # all four variants. Original 45.0 triggered an Nt 8192→16384 auto-grow
    # that broke the fair-comparison protocol for the :sharp / :curvature runs.
    (tag=:B, fiber_preset=:SMF28, L_fiber=5.0, P_cont=0.2,  seed=43, time_window=150.0),
    (tag=:C, fiber_preset=:HNLF,  L_fiber=1.0, P_cont=0.5,  seed=44, time_window=15.0),
]
const CA_VARIANTS = [:linear, :log_dB, :sharp, :curvature]

const CA_SIGMAS         = [0.01, 0.05, 0.1, 0.2]
const CA_N_TRIALS       = 10
const CA_NEV            = parse(Int,   get(ENV, "CA_NEV",            "32"))
const CA_HESSIAN_EPS    = parse(Float64, get(ENV, "CA_HESSIAN_EPS",    "1e-4"))
const CA_ARPACK_TOL     = parse(Float64, get(ENV, "CA_ARPACK_TOL",     "1e-6"))
const CA_ARPACK_MAXITER = parse(Int,   get(ENV, "CA_ARPACK_MAXITER",  "500"))
const CA_SKIP_HESSIAN   = get(ENV, "CA_SKIP_HESSIAN",  "0") == "1"
const CA_RESULTS_ROOT   = joinpath(@__DIR__, "..", "..", "..", "results", "cost_audit")
# CA_HEAVY_LOCK removed per Rule P5 update (2026-04-17) — burst-run-heavy owns
# the lock now; in-Julia management would collide with the wrapper.

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

function _setup_config(cfg::NamedTuple; Nt::Int=8192, strict_nt::Bool=true)
    # Phase 10 lesson: 2-beta presets need β_order=3.
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
        Nt=Nt, time_window=cfg.time_window, β_order=3,
        fiber_preset=cfg.fiber_preset, L_fiber=cfg.L_fiber, P_cont=cfg.P_cont)
    if sim["Nt"] != Nt
        msg = "Config $(cfg.tag): Nt auto-grew from $Nt to $(sim["Nt"]) — " *
              "time_window=$(cfg.time_window) was insufficient."
        if strict_nt
            error(msg * " Fair-comparison broken (strict_nt=true).")
        else
            @warn msg * " Continuing (strict_nt=false, integration-test mode)."
        end
    end
    return uω0, fiber, sim, band_mask, Δf, raman_threshold
end

function _iter_to_90pct_dB(f_trace_linear::AbstractVector)
    isempty(f_trace_linear) && return 0
    dB = [10 * log10(max(v, 1e-15)) for v in f_trace_linear]
    ΔdB = dB[1] - dB[end]
    ΔdB ≤ 0 && return length(dB)
    threshold = 0.9 * ΔdB
    for (k, v) in enumerate(dB)
        if (dB[1] - v) ≥ threshold
            return k
        end
    end
    return length(dB)
end

function _robustness_probe(φ_opt, uω0, fiber, sim, band_mask;
                           rng::AbstractRNG,
                           sigmas=CA_SIGMAS, n_trials=CA_N_TRIALS)
    J_opt, _ = cost_and_gradient(φ_opt, uω0, fiber, sim, band_mask;
        log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
    J_opt_dB = 10 * log10(max(J_opt, 1e-15))
    out = Dict{Symbol, Float64}()
    for σ in sigmas
        dJs = Float64[]
        for _ in 1:n_trials
            φ_p = φ_opt .+ σ .* randn(rng, size(φ_opt)...)
            J_p, _ = cost_and_gradient(φ_p, uω0, fiber, sim, band_mask;
                log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
            push!(dJs, 10 * log10(max(J_p, 1e-15)) - J_opt_dB)
        end
        out[Symbol("robust_sigma_$(σ)_mean_dB")] = mean(dJs)
        out[Symbol("robust_sigma_$(σ)_max_dB")]  = maximum(dJs)
    end
    return out
end

function _hessian_top_k(setup_kwargs::NamedTuple, φ_opt::AbstractMatrix;
                        nev::Int=CA_NEV, eps::Real=CA_HESSIAN_EPS,
                        tol::Real=CA_ARPACK_TOL, maxiter::Int=CA_ARPACK_MAXITER)
    if CA_SKIP_HESSIAN
        @info "CA_SKIP_HESSIAN=1 → returning NaN eigenspectrum (nev=$nev)"
        return (lambda_top=fill(NaN, nev), cond_proxy=NaN,
                lambda_max=NaN, dnf=false)
    end
    oracle, meta = build_oracle(setup_kwargs)
    P = build_gauge_projector(meta.omega, meta.input_band_mask)
    proj_oracle = phi_flat -> P(oracle(phi_flat))
    φ_opt_flat = vec(copy(φ_opt))
    H_op = HVPOperator(length(φ_opt_flat), proj_oracle, φ_opt_flat, eps)
    local λ_top
    try
        λ_top, _, _ = Arpack.eigs(H_op; nev=nev, which=:LR,
                                   maxiter=maxiter, tol=tol)
    catch e
        @warn "Arpack :LR failed with default settings; retrying" exception=e
        try
            λ_top, _, _ = Arpack.eigs(H_op; nev=nev, which=:LR,
                                       maxiter=2*maxiter, tol=1e-5)
        catch e2
            @warn "Arpack retry also failed; returning NaNs" exception=e2
            return (lambda_top=fill(NaN, nev), cond_proxy=NaN,
                    lambda_max=NaN, dnf=true)
        end
    end
    λ_real = real.(λ_top)
    lambda_max = maximum(λ_real)
    lambda_min_in_top = minimum(λ_real)
    cond_proxy = lambda_max / max(abs(lambda_min_in_top), Base.eps())
    return (lambda_top=λ_real, cond_proxy=cond_proxy,
            lambda_max=lambda_max, dnf=false)
end

function _atomic_jld2_save(path::AbstractString; kwargs...)
    tmp = path * ".tmp"
    jldsave(tmp; kwargs...)
    mv(tmp, path; force=true)
    return path
end

# ─────────────────────────────────────────────────────────────────────────────
# Per-run orchestration
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_one(variant::Symbol, config_tag::Symbol; max_iter=100, Nt=8192,
            save::Bool=true, strict_nt::Bool=true,
            results_root=CA_RESULTS_ROOT) -> NamedTuple

Execute a single (variant, config) pair end-to-end: setup → optimize →
gauge-projected Hessian top-$(CA_NEV) eigenspectrum → robustness probe.
"""
function run_one(variant::Symbol, config_tag::Symbol;
                 max_iter::Int=100, Nt::Int=8192, save::Bool=true,
                 strict_nt::Bool=true,
                 results_root::AbstractString=CA_RESULTS_ROOT)
    variant in CA_VARIANTS ||
        error("unknown variant :$variant (expected $CA_VARIANTS)")
    cfg_idx = findfirst(c -> c.tag == config_tag, CA_CONFIGS)
    isnothing(cfg_idx) &&
        error("unknown config tag :$config_tag (expected :A :B :C)")
    cfg = CA_CONFIGS[cfg_idx]

    uω0, fiber, sim, band_mask, Δf, raman_threshold = _setup_config(cfg; Nt=Nt, strict_nt=strict_nt)
    setup_kwargs = (Nt=Nt, time_window=cfg.time_window, β_order=3,
        fiber_preset=cfg.fiber_preset, L_fiber=cfg.L_fiber, P_cont=cfg.P_cont)

    # Dual-RNG discipline (threat T-16-02).
    rng_start  = MersenneTwister(cfg.seed)
    rng_robust = MersenneTwister(cfg.seed + 1000)
    φ0 = 0.1 .* randn(rng_start, sim["Nt"], sim["M"])

    J_start, _ = cost_and_gradient(φ0, uω0, fiber, sim, band_mask;
        log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
    J_start_dB = 10 * log10(max(J_start, 1e-15))

    log_cost_used = false
    t0 = time()
    # I-6 (D-15): sharp-only decomposition — NaN for non-sharp variants.
    S_final = NaN
    lambda_times_S_final = NaN
    lambda_sharp_used = NaN
    local φ_opt, J_final, iterations, converged, f_trace

    if variant == :linear
        # D-08: linear cost → f_abstol=1e-10 (set internally by
        # optimize_spectral_phase when log_cost=false).
        result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
            φ0=copy(φ0), max_iter=max_iter, log_cost=false, store_trace=true)
        φ_opt      = reshape(Optim.minimizer(result), sim["Nt"], sim["M"])
        J_final    = Optim.minimum(result)
        iterations = Optim.iterations(result)
        converged  = Optim.converged(result)
        # Optim.f_trace returns Vector{Float64} directly (function values per iter)
        f_trace    = Vector{Float64}(Optim.f_trace(result))

    elseif variant == :log_dB
        # D-08: log_dB cost → f_abstol=0.01 dB (set internally when log_cost=true).
        result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
            φ0=copy(φ0), max_iter=max_iter, log_cost=true, store_trace=true)
        φ_opt       = reshape(Optim.minimizer(result), sim["Nt"], sim["M"])
        J_final_dB_ = Optim.minimum(result)
        J_final     = 10^(J_final_dB_/10)
        iterations  = Optim.iterations(result)
        converged   = Optim.converged(result)
        f_trace_dB  = Vector{Float64}(Optim.f_trace(result))
        f_trace     = [10^(v/10) for v in f_trace_dB]
        log_cost_used = true

    elseif variant == :sharp
        prob = make_sharp_problem(; Nt=Nt, time_window=cfg.time_window, β_order=3,
            fiber_preset=cfg.fiber_preset, L_fiber=cfg.L_fiber, P_cont=cfg.P_cont)
        rng_sharp = MersenneTwister(cfg.seed + 2000)
        sharp_out = optimize_spectral_phase_sharp(prob, copy(φ0);
            lambda_sharp=0.1, n_samples=8, eps=1e-3, rng=rng_sharp,
            max_iter=max_iter, log_cost=true, λ_gdd=0.0, λ_boundary=0.0,
            strategy=:lbfgs, store_trace=true, f_tol=0.01)
        φ_opt       = sharp_out.phi_opt
        J_final_dB_ = sharp_out.J_final
        J_final     = 10^(J_final_dB_/10)
        iterations  = sharp_out.iterations
        converged   = sharp_out.converged
        f_trace     = [10^(v/10) for v in sharp_out.history]
        log_cost_used = true
        # I-6 (D-15): decompose into (J_band, S, lambda*S).
        lambda_sharp_used = 0.1
        J_band_sharp, _ = cost_and_gradient(φ_opt, uω0, fiber, sim, band_mask;
            log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
        J_band_sharp_dB = 10 * log10(max(J_band_sharp, 1e-15))
        S_final = lambda_sharp_used > 0 ?
            (J_final_dB_ - J_band_sharp_dB) / lambda_sharp_used : NaN
        lambda_times_S_final = lambda_sharp_used * S_final

    elseif variant == :curvature
        γ_curv = calibrate_gamma_curv(φ0, uω0, fiber, sim, band_mask;
            target_fraction=0.1, fallback=CA_DEFAULT_GAMMA_CURV)
        fiber["zsave"] = nothing
        uω0_shaped = similar(uω0)
        uωf_buffer = similar(uω0)
        Nt_sim = sim["Nt"]; M_sim = sim["M"]
        trace_vals = Float64[]
        # Optim.jl with store_trace=true passes the whole trace vector, not
        # a single state. Access tr[end].value to record the latest iteration.
        cb = tr -> (isempty(tr) || push!(trace_vals, tr[end].value); false)
        fg! = Optim.only_fg!() do F, G, φ_vec
            φ = reshape(φ_vec, Nt_sim, M_sim)
            J, ∂J = cost_and_gradient_curvature(φ, uω0, fiber, sim, band_mask;
                γ_curv=γ_curv, log_cost=false, λ_gdd=0.0, λ_boundary=0.0,
                uω0_shaped=uω0_shaped, uωf_buffer=uωf_buffer)
            G !== nothing && (G .= vec(∂J))
            F !== nothing && return J
        end
        # D-08: linear-scale curvature wrapper → use linear tol (1e-10).
        result = optimize(fg!, vec(copy(φ0)), LBFGS(),
            Optim.Options(iterations=max_iter, f_abstol=1e-10,
                          callback=cb, store_trace=true))
        φ_opt      = reshape(Optim.minimizer(result), Nt_sim, M_sim)
        J_final    = Optim.minimum(result)
        iterations = Optim.iterations(result)
        converged  = Optim.converged(result)
        f_trace    = isempty(trace_vals) ?
            [t.value for t in Optim.f_trace(result)] : trace_vals
    end

    wall_s = time() - t0
    J_final_dB = 10 * log10(max(J_final, 1e-15))
    iter_to_90pct = _iter_to_90pct_dB(f_trace)

    robust = _robustness_probe(φ_opt, uω0, fiber, sim, band_mask;
                                rng=rng_robust)

    hess = _hessian_top_k(setup_kwargs, φ_opt)

    result_nt = (
        variant = variant, config = config_tag,
        J_final = J_final, J_final_linear = J_final, J_final_dB = J_final_dB,
        J_start_dB = J_start_dB, delta_J_dB = J_final_dB - J_start_dB,
        phi_opt = φ_opt,
        iterations = iterations, iter_to_90pct = iter_to_90pct,
        wall_s = wall_s, converged = converged,
        lambda_top = hess.lambda_top, lambda_max = hess.lambda_max,
        cond_proxy = hess.cond_proxy,
        robust = robust, dnf = hess.dnf,
        hostname = gethostname(),
        fftw_wisdom_imported = CA_FFTW_WISDOM_IMPORTED,
        log_cost_used = log_cost_used, seed_phi0 = cfg.seed,
        seed_robust = cfg.seed + 1000, f_trace_linear = f_trace,
        # I-6 (D-15) sharp-only decomposition — NaN for non-sharp variants.
        S_final = S_final, lambda_times_S_final = lambda_times_S_final,
        lambda_sharp = lambda_sharp_used,
    )

    if save
        dir = joinpath(results_root, String(config_tag))
        isdir(dir) || mkpath(dir)
        path = joinpath(dir, "$(variant)_result.jld2")
        _atomic_jld2_save(path;
            variant=String(variant), config=String(config_tag),
            phi_opt=φ_opt, J_final=J_final, J_final_dB=J_final_dB,
            J_start_dB=J_start_dB, delta_J_dB=J_final_dB - J_start_dB,
            iterations=iterations, iter_to_90pct=iter_to_90pct,
            wall_s=wall_s, converged=converged,
            lambda_top=hess.lambda_top, lambda_max=hess.lambda_max,
            cond_proxy=hess.cond_proxy, dnf=hess.dnf,
            robust=robust, hostname=gethostname(),
            fftw_wisdom_imported=CA_FFTW_WISDOM_IMPORTED,
            log_cost_used=log_cost_used,
            seed_phi0=cfg.seed, seed_robust=cfg.seed + 1000,
            f_trace_linear=f_trace,
            S_final=S_final, lambda_times_S_final=lambda_times_S_final,
            lambda_sharp=lambda_sharp_used,
            Nt=sim["Nt"], M=sim["M"], time_window=cfg.time_window,
            L_fiber=cfg.L_fiber, P_cont=cfg.P_cont,
            fiber_preset=String(cfg.fiber_preset))
        # Companion meta.txt (D-20 verification).
        open(joinpath(dir, "$(variant)_meta.txt"), "w") do io
            println(io, "hostname=", gethostname())
            println(io, "timestamp=", Dates.format(now(), "yyyymmdd_HHMMss"))
            println(io, "julia_version=", VERSION)
            println(io, "threads=", Threads.nthreads())
            println(io, "fftw_threads=", FFTW.get_num_threads())
            println(io, "blas_threads=", BLAS.get_num_threads())
        end

        # Mandatory standard image set (Project-level rule, 2026-04-17 update).
        # Every driver producing phi_opt MUST call save_standard_set().
        # phi_opt is (Nt, M); standard_images expects a Vector{Float64}. M=1 here.
        try
            M_local = sim["M"]
            phi_vec = M_local > 1 ? vec(φ_opt) : φ_opt[:, 1]
            L_disp_cm = round(Int, cfg.L_fiber * 100)
            P_mW = round(Int, cfg.P_cont * 1000)
            tag = @sprintf("cost_audit_%s_%s_%s_L%dcm_P%dmW",
                           String(config_tag), String(cfg.fiber_preset),
                           String(variant), L_disp_cm, P_mW)
            save_standard_set(phi_vec, uω0, fiber, sim,
                              band_mask, Δf, raman_threshold;
                              tag = tag,
                              fiber_name = String(cfg.fiber_preset),
                              L_m = cfg.L_fiber, P_W = cfg.P_cont,
                              output_dir = dir)
        catch e
            @warn "save_standard_set failed — continuing" variant=variant config=config_tag exception=(e, catch_backtrace())
        end
    end
    return result_nt
end

"""
    run_all(; max_iter=100, Nt=8192, results_root=CA_RESULTS_ROOT) -> Nothing

Execute all 12 (variant, config) pairs serially. The heavy lock
(`/tmp/burst-heavy-lock`) is owned by `burst-run-heavy` — this function does
NOT manage the lock itself. Appends per-run row to
`results/cost_audit/wall_log.csv`.
"""
function run_all(; max_iter::Int=100, Nt::Int=8192,
                 results_root::AbstractString=CA_RESULTS_ROOT)
    isdir(results_root) || mkpath(results_root)
    wall_log_path = joinpath(results_root, "wall_log.csv")
    if !isfile(wall_log_path)
        open(wall_log_path, "w") do io
            println(io, "config,variant,wall_s,J_final_dB,iterations," *
                         "iter_to_90pct,converged,dnf,hostname,timestamp")
        end
    end
    for cfg in CA_CONFIGS, variant in CA_VARIANTS
        @info @sprintf("═══ run %s/%s ═══", cfg.tag, variant)
        try
            r = run_one(variant, cfg.tag;
                        max_iter=max_iter, Nt=Nt, save=true,
                        results_root=results_root)
            open(wall_log_path, "a") do io
                println(io, join((String(cfg.tag), String(variant),
                    r.wall_s, r.J_final_dB, r.iterations, r.iter_to_90pct,
                    r.converged, r.dnf, r.hostname,
                    Dates.format(now(), "yyyymmdd_HHMMss")), ","))
            end
        catch e
            @error "run FAILED — marking DNF" config=cfg.tag variant=variant exception=(e, catch_backtrace())
            open(wall_log_path, "a") do io
                println(io, join((String(cfg.tag), String(variant),
                    NaN, NaN, 0, 0, false, true, gethostname(),
                    Dates.format(now(), "yyyymmdd_HHMMss")), ","))
            end
        end
    end
    return nothing
end

# CLI entry.
if abspath(PROGRAM_FILE) == @__FILE__
    run_all()
end
