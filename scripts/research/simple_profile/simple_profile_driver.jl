# ═══════════════════════════════════════════════════════════════════════════════
# Phase 17 Plan 01 — Simple Phase Profile Stability Study — Driver
# ═══════════════════════════════════════════════════════════════════════════════
#
# Single entry point for the three compute stages of Phase 17:
#
#   julia -t auto --project=. scripts/research/simple_profile/simple_profile_driver.jl --stage=baseline
#   julia -t auto --project=. scripts/research/simple_profile/simple_profile_driver.jl --stage=perturbation
#   julia -t auto --project=. scripts/research/simple_profile/simple_profile_driver.jl --stage=transferability
#
# Stages are independent so each can be committed separately. Each stage emits
# a single self-describing JLD2 under results/raman/phase17/.
#
# Physics / research question:
#   Is the SMF-28 L=0.5m P=0.05W J=-77.6 dB optimum a flat robust basin or a
#   coincidental sharp minimum? See .planning/sessions/D-simple-decisions.md.
#
# Shared-file discipline (CLAUDE.md Rule P1): this script NEVER mutates
# scripts/common.jl, scripts/raman_optimization.jl, scripts/visualization.jl,
# or anything in src/. It only includes them read-only.
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

using MultiModeNoise
using Optim
using Interpolations

# READ-ONLY includes of the production pipeline.
include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "determinism.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "standard_images.jl"))
ensure_deterministic_environment(verbose=true)

# ─────────────────────────────────────────────────────────────────────────────
# Constants (SP_ = Simple Profile)
# ─────────────────────────────────────────────────────────────────────────────

const SP_VERSION = "1.0.0"
const SP_RESULTS_DIR = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase17")
const SP_SEED_BASE = 16042026
const SP_N_SAMPLES = 20
const SP_SIGMAS = [0.01, 0.05, 0.2, 0.5, 1.0]

const SP_BASELINE = (
    fiber_name    = "SMF-28",
    fiber_preset  = :SMF28,
    L             = 0.5,
    P             = 0.05,
    gamma         = 1.1e-3,
    betas         = [-2.17e-26, 1.2e-40],
    fR            = 0.18,
    pulse_fwhm    = 185e-15,
    pulse_rep     = 80.5e6,
    β_order       = 3,
)
const SP_BASELINE_NT        = 8192
const SP_BASELINE_TIME_WIN  = 10.0      # ps — setup_raman_problem auto-sizes if too small
const SP_BASELINE_MAXITER   = 60
const SP_TRANSFER_MAXITER   = 40
const SP_BASELINE_J_EXPECT  = -77.6
const SP_BASELINE_J_TOL     = 1.0       # dB

# HNLF preset used in transferability grid (kept local so Session D never
# touches FIBER_PRESETS in common.jl).
const SP_HNLF = (
    fiber_name   = "HNLF",
    fiber_preset = :HNLF,
    gamma        = 10.0e-3,
    betas        = [-0.5e-26, 1.0e-40],
    fR           = 0.18,
)

# ─────────────────────────────────────────────────────────────────────────────
# Utility helpers
# ─────────────────────────────────────────────────────────────────────────────

lin_to_dB_safe(x) = 10 * log10(max(x, 1e-15))

"""
    parse_stage(args) -> Symbol

Parse the `--stage=...` CLI argument. Returns one of
:baseline, :perturbation, :transferability.
"""
function parse_stage(args::Vector{String})
    for a in args
        if startswith(a, "--stage=")
            s = Symbol(split(a, "=")[2])
            @assert s in (:baseline, :perturbation, :transferability) "unknown stage $s"
            return s
        end
    end
    # Default: baseline (safest — fast, self-contained).
    return :baseline
end

"""
    build_baseline_problem()

Build the baseline (uω0, fiber, sim, band_mask, Δf, threshold) tuple via
`setup_raman_problem` with Phase 17 baseline parameters. Deterministic and
idempotent: calling it twice on the same machine produces identical arrays.
"""
function build_baseline_problem()
    return setup_raman_problem(
        fiber_preset = SP_BASELINE.fiber_preset,
        L_fiber      = SP_BASELINE.L,
        P_cont       = SP_BASELINE.P,
        Nt           = SP_BASELINE_NT,
        time_window  = SP_BASELINE_TIME_WIN,
        β_order      = SP_BASELINE.β_order,
        gamma_user   = SP_BASELINE.gamma,
        betas_user   = SP_BASELINE.betas,
        fR           = SP_BASELINE.fR,
        pulse_fwhm   = SP_BASELINE.pulse_fwhm,
        pulse_rep_rate = SP_BASELINE.pulse_rep,
    )
end

"""
    eval_J_dB(phi, uω0, fiber, sim, band_mask) -> Float64

Forward-only evaluation of the pure physical cost J at `phi`, returned in dB.
Uses `log_cost=false` so the output is a LINEAR J which we convert via
`lin_to_dB_safe`. Matches the baseline's reported J_final units.
"""
function eval_J_dB(phi, uω0, fiber, sim, band_mask)
    J_lin, _ = cost_and_gradient(phi, uω0, fiber, sim, band_mask;
        log_cost=false, λ_gdd=0.0, λ_boundary=0.0)
    return lin_to_dB_safe(J_lin)
end

"""
    interpolate_phi(phi_src, src_sim, tgt_sim) -> Matrix{Float64}

Transfer a spectral phase profile from one frequency grid to another.
Both grids are in FFT order; the interpolation happens in fftshifted order
where the frequency vector is monotonic. Out-of-range target bins get the
Flat() extrapolation value (safe: those bins carry negligible pulse energy).

Returns a (Nt_tgt, M) matrix.
"""
function interpolate_phi(phi_src::AbstractMatrix, src_sim::Dict, tgt_sim::Dict)
    Nt_src = src_sim["Nt"]
    Nt_tgt = tgt_sim["Nt"]
    M = src_sim["M"]
    @assert tgt_sim["M"] == M "mode count mismatch: src=$M tgt=$(tgt_sim["M"])"
    @assert size(phi_src) == (Nt_src, M) "phi_src shape mismatch"

    # Frequency axes in THz (monotonic after fftshift).
    fs_src = fftshift(fftfreq(Nt_src, 1 / src_sim["Δt"]))
    fs_tgt = fftshift(fftfreq(Nt_tgt, 1 / tgt_sim["Δt"]))

    phi_tgt = zeros(Nt_tgt, M)
    for m in 1:M
        phi_sorted = fftshift(phi_src[:, m])
        itp = linear_interpolation(fs_src, phi_sorted;
            extrapolation_bc=Interpolations.Flat())
        phi_tgt_sorted = itp.(fs_tgt)
        phi_tgt[:, m] = ifftshift(phi_tgt_sorted)
    end
    return phi_tgt
end

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Baseline reproduction
# ─────────────────────────────────────────────────────────────────────────────

function stage_baseline(; verbose::Bool=true)
    verbose && @info "───── Phase 17 — Stage: BASELINE ─────"
    mkpath(SP_RESULTS_DIR)
    out_path = joinpath(SP_RESULTS_DIR, "baseline.jld2")

    Random.seed!(SP_SEED_BASE)

    uω0, fiber, sim, band_mask, Δf, raman_threshold = build_baseline_problem()
    Nt = sim["Nt"]; M = sim["M"]
    time_window_ps = Nt * sim["Δt"]

    P_peak = 0.881374 * SP_BASELINE.P / (SP_BASELINE.pulse_fwhm * SP_BASELINE.pulse_rep)
    Φ_NL   = SP_BASELINE.gamma * P_peak * SP_BASELINE.L
    verbose && @info @sprintf("Baseline grid: Nt=%d, Δt=%.4f ps, time_window=%.1f ps", Nt, sim["Δt"], time_window_ps)
    verbose && @info @sprintf("Nonlinearity: P_peak=%.1f W, Φ_NL=%.2f rad", P_peak, Φ_NL)

    φ0 = zeros(Nt, M)
    J_initial_lin, _ = cost_and_gradient(φ0, uω0, fiber, sim, band_mask; log_cost=false)
    J_initial_dB = lin_to_dB_safe(J_initial_lin)
    verbose && @info @sprintf("Initial J (φ₀=0): %.3f dB", J_initial_dB)

    t_wall = @elapsed result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0=φ0, max_iter=SP_BASELINE_MAXITER, log_cost=true, store_trace=true)

    # `result.minimum` is in dB because log_cost=true. Re-evaluate linearly to
    # cross-check against J_initial.
    phi_opt = reshape(Optim.minimizer(result), Nt, M)
    J_final_dB_crosscheck = eval_J_dB(phi_opt, uω0, fiber, sim, band_mask)
    J_final_dB = Optim.minimum(result)
    verbose && @info @sprintf("Optimised J: %.3f dB (cross-check %.3f dB) in %.2f s, iterations=%d",
        J_final_dB, J_final_dB_crosscheck, t_wall, Optim.iterations(result))

    # Collect trace values (already in dB when log_cost=true).
    trace_values_dB = Float64[]
    try
        if !isempty(result.trace)
            trace_values_dB = [tr.value for tr in result.trace]
        end
    catch _
        # store_trace failed — leave empty
    end

    # ── Tolerance gate ──
    ΔJ = J_final_dB - SP_BASELINE_J_EXPECT
    tolerance_ok = abs(ΔJ) <= SP_BASELINE_J_TOL
    if !tolerance_ok
        @error @sprintf("BASELINE REPRODUCTION FAILED: J_final=%.3f dB (expected %.1f ± %.1f)",
            J_final_dB, SP_BASELINE_J_EXPECT, SP_BASELINE_J_TOL)
        @error "This is a Phase 13-class determinism finding. STOPPING."
        error("baseline reproduction out of tolerance — escalate per decision 5")
    end

    jldsave(out_path;
        # Identification
        phase        = "16",
        plan         = "01",
        script       = "simple_profile_driver",
        stage        = "baseline",
        version      = SP_VERSION,
        created_at   = string(Dates.now()),
        # Config
        fiber_name   = SP_BASELINE.fiber_name,
        fiber_preset = String(SP_BASELINE.fiber_preset),
        L_m          = SP_BASELINE.L,
        P_cont_W     = SP_BASELINE.P,
        gamma        = SP_BASELINE.gamma,
        betas        = SP_BASELINE.betas,
        fR           = SP_BASELINE.fR,
        pulse_fwhm_s = SP_BASELINE.pulse_fwhm,
        pulse_rep_Hz = SP_BASELINE.pulse_rep,
        Nt           = Nt,
        M            = M,
        time_window_ps = time_window_ps,
        β_order      = SP_BASELINE.β_order,
        max_iter     = SP_BASELINE_MAXITER,
        P_peak_W     = P_peak,
        Phi_NL_rad   = Φ_NL,
        # Results
        phi_opt_initial = φ0,
        phi_opt         = phi_opt,
        J_initial_dB    = J_initial_dB,
        J_final_dB      = J_final_dB,
        J_final_dB_crosscheck = J_final_dB_crosscheck,
        J_expected_dB   = SP_BASELINE_J_EXPECT,
        wall_s          = t_wall,
        converged       = Optim.converged(result),
        iterations      = Optim.iterations(result),
        trace_values_dB = trace_values_dB,
        tolerance_ok    = tolerance_ok,
        # Grid / sim metadata (needed by downstream stages)
        uomega0         = uω0,
        band_mask       = band_mask,
        fftfreq_THz     = collect(fftfreq(Nt, 1 / sim["Δt"])),
        sim_omega0      = sim["ω0"],
        sim_Dt          = sim["Δt"],
        # Threading record
        julia_nthreads  = Threads.nthreads(),
        fftw_nthreads   = FFTW.get_num_threads(),
        blas_nthreads   = BLAS.get_num_threads(),
    )
    verbose && @info "BASELINE SUCCESS — written $(out_path)"
    verbose && println(repeat("━", 72))
    verbose && println(@sprintf("  J_final_dB = %.3f dB  |  wall = %.2f s  |  tolerance OK", J_final_dB, t_wall))
    verbose && println(repeat("━", 72))

    # Rule 2: mandatory standard-image set
    try
        save_standard_set(
            phi_opt, uω0, fiber, sim, band_mask, Δf, raman_threshold;
            tag        = "smf28_L0p50m_P0p050W_baseline",
            fiber_name = "SMF28",
            L_m        = SP_BASELINE.L,
            P_W        = SP_BASELINE.P,
            output_dir = joinpath(SP_RESULTS_DIR, "standard_images"),
        )
    catch e
        @warn "save_standard_set failed (Rule 2 non-compliance)" exception=e
    end
    return out_path
end

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Perturbation study
# ─────────────────────────────────────────────────────────────────────────────

function stage_perturbation(; verbose::Bool=true)
    verbose && @info "───── Phase 17 — Stage: PERTURBATION ─────"
    baseline_path = joinpath(SP_RESULTS_DIR, "baseline.jld2")
    @assert isfile(baseline_path) "baseline.jld2 not found — run --stage=baseline first"
    out_path = joinpath(SP_RESULTS_DIR, "perturbation.jld2")

    base = JLD2.load(baseline_path)
    phi_opt = base["phi_opt"]::Matrix{Float64}
    J_baseline_dB = base["J_final_dB"]::Float64
    Nt = base["Nt"]::Int
    M  = Int(size(phi_opt, 2))
    @assert size(phi_opt, 1) == Nt "phi_opt Nt mismatch"

    # Rebuild deterministically — avoids re-reading large arrays from JLD2
    # (also ensures the interaction-picture buffers match).
    uω0, fiber, sim, band_mask, _, _ = build_baseline_problem()
    @assert sim["Nt"] == Nt "Nt mismatch between rebuild and stored baseline"

    # Pre-clear zsave to avoid the solver copying it per task.
    fiber["zsave"] = nothing

    n_sigmas = length(SP_SIGMAS)
    tasks = Tuple{Int, Int}[]
    for j in 1:n_sigmas, t in 1:SP_N_SAMPLES
        push!(tasks, (j, t))
    end
    n_tasks = length(tasks)
    verbose && @info @sprintf("Perturbation grid: %d σ × %d samples = %d tasks on %d threads",
        n_sigmas, SP_N_SAMPLES, n_tasks, Threads.nthreads())

    sigma_idx_arr  = fill(0, n_tasks)
    sample_idx_arr = fill(0, n_tasks)
    sigma_arr      = fill(NaN, n_tasks)
    J_pert_dB_arr  = fill(NaN, n_tasks)
    delta_J_dB_arr = fill(NaN, n_tasks)

    # Preview samples: keep phi for 3 samples per σ to enable later inspection.
    preview_keep = 3
    preview_phi = zeros(Nt, M, n_sigmas, preview_keep)

    t_start = time()
    @threads for k in 1:n_tasks
        j, t = tasks[k]
        σ = SP_SIGMAS[j]
        fiber_local = deepcopy(fiber)
        fiber_local["zsave"] = nothing

        seed = SP_SEED_BASE + 1000 * j + t
        rng = MersenneTwister(seed)
        noise = σ .* randn(rng, Nt, M)
        phi_pert = phi_opt .+ noise

        J_dB = eval_J_dB(phi_pert, uω0, fiber_local, sim, band_mask)

        sigma_idx_arr[k]  = j
        sample_idx_arr[k] = t
        sigma_arr[k]      = σ
        J_pert_dB_arr[k]  = J_dB
        delta_J_dB_arr[k] = J_dB - J_baseline_dB

        if t <= preview_keep
            preview_phi[:, :, j, t] = phi_pert
        end
    end
    total_wall = time() - t_start
    verbose && @info @sprintf("Perturbation done in %.1f s (%.2f s/sample)", total_wall, total_wall / n_tasks)

    # Aggregates per σ
    median_dJ = fill(NaN, n_sigmas)
    mean_dJ   = fill(NaN, n_sigmas)
    max_dJ    = fill(NaN, n_sigmas)
    std_dJ    = fill(NaN, n_sigmas)
    q25_dJ    = fill(NaN, n_sigmas)
    q75_dJ    = fill(NaN, n_sigmas)
    for j in 1:n_sigmas
        sel = sigma_idx_arr .== j
        d = delta_J_dB_arr[sel]
        if !isempty(d)
            median_dJ[j] = median(d)
            mean_dJ[j]   = mean(d)
            max_dJ[j]    = maximum(d)
            std_dJ[j]    = length(d) > 1 ? std(d) : 0.0
            q25_dJ[j]    = quantile(d, 0.25)
            q75_dJ[j]    = quantile(d, 0.75)
        end
    end

    # σ_3dB by linear interpolation on the median curve.
    sigma_3dB = _sigma_at_threshold(SP_SIGMAS, median_dJ, 3.0)

    jldsave(out_path;
        phase = "16", plan = "01", script = "simple_profile_driver",
        stage = "perturbation",
        version = SP_VERSION,
        created_at = string(Dates.now()),
        # Inputs
        baseline_path = baseline_path,
        J_baseline_dB = J_baseline_dB,
        Nt = Nt, M = M,
        sigmas = SP_SIGMAS,
        n_samples = SP_N_SAMPLES,
        seed_base = SP_SEED_BASE,
        # Per-sample flat arrays
        task_sigma_idx  = sigma_idx_arr,
        task_sample_idx = sample_idx_arr,
        task_sigma      = sigma_arr,
        task_J_pert_dB  = J_pert_dB_arr,
        task_delta_J_dB = delta_J_dB_arr,
        preview_phi     = preview_phi,
        preview_n       = preview_keep,
        # Aggregates
        median_delta_J_dB = median_dJ,
        mean_delta_J_dB   = mean_dJ,
        max_delta_J_dB    = max_dJ,
        std_delta_J_dB    = std_dJ,
        q25_delta_J_dB    = q25_dJ,
        q75_delta_J_dB    = q75_dJ,
        sigma_3dB_interp  = sigma_3dB,
        # Threading
        julia_nthreads = Threads.nthreads(),
        fftw_nthreads  = FFTW.get_num_threads(),
        blas_nthreads  = BLAS.get_num_threads(),
        total_wall_s   = total_wall,
    )
    verbose && @info @sprintf("σ_3dB = %s rad (median-based)", isnan(sigma_3dB) ? "not reached" : @sprintf("%.3f", sigma_3dB))
    verbose && @info "PERTURBATION written $(out_path)"
    return out_path
end

"""
    _sigma_at_threshold(sigmas, median_dJ, threshold_dB) -> Float64

Linearly interpolate the smallest σ at which median ΔJ ≥ threshold_dB.
Returns `NaN` if the curve never reaches the threshold, or the smallest σ
if it is already ≥ threshold at σ[1].
"""
function _sigma_at_threshold(sigmas::AbstractVector, median_dJ::AbstractVector, thr::Real)
    n = length(sigmas)
    @assert length(median_dJ) == n "length mismatch"
    if median_dJ[1] >= thr
        return sigmas[1]
    end
    for i in 2:n
        if median_dJ[i] >= thr
            # Linear interp between (sigmas[i-1], dJ[i-1]) and (sigmas[i], dJ[i])
            x0, y0 = sigmas[i-1], median_dJ[i-1]
            x1, y1 = sigmas[i],   median_dJ[i]
            if y1 > y0
                return x0 + (thr - y0) * (x1 - x0) / (y1 - y0)
            else
                return x1
            end
        end
    end
    return NaN
end

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3: Transferability
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_transfer_grid() -> Vector{NamedTuple}

Build the 11 distinct transferability targets per D-simple-decisions.md §3.
Tags `is_baseline=true` for the (L=0.5, P=0.05) SMF-28 point so the
synthesis stage can render it with special markup.
"""
function build_transfer_grid()
    grid = NamedTuple[]
    # SMF-28 L axis (P fixed at baseline power)
    for L in [0.25, 0.5, 1.0, 2.0, 5.0]
        push!(grid, (
            fiber_name   = SP_BASELINE.fiber_name,
            fiber_preset = SP_BASELINE.fiber_preset,
            L            = L,
            P            = SP_BASELINE.P,
            gamma        = SP_BASELINE.gamma,
            betas        = SP_BASELINE.betas,
            fR           = SP_BASELINE.fR,
            axis         = "L",
            is_baseline  = (L == SP_BASELINE.L),
        ))
    end
    # SMF-28 P axis (L fixed at baseline, skip duplicate P=0.05)
    for P in [0.02, 0.1, 0.2]
        push!(grid, (
            fiber_name   = SP_BASELINE.fiber_name,
            fiber_preset = SP_BASELINE.fiber_preset,
            L            = SP_BASELINE.L,
            P            = P,
            gamma        = SP_BASELINE.gamma,
            betas        = SP_BASELINE.betas,
            fR           = SP_BASELINE.fR,
            axis         = "P",
            is_baseline  = false,
        ))
    end
    # HNLF cross-fiber
    for (L, P) in [(0.25, 0.005), (0.5, 0.005), (0.5, 0.01)]
        push!(grid, (
            fiber_name   = SP_HNLF.fiber_name,
            fiber_preset = SP_HNLF.fiber_preset,
            L            = L,
            P            = P,
            gamma        = SP_HNLF.gamma,
            betas        = SP_HNLF.betas,
            fR           = SP_HNLF.fR,
            axis         = "fiber",
            is_baseline  = false,
        ))
    end
    @assert length(grid) == 11 "transfer grid should have 11 entries, got $(length(grid))"
    return grid
end

"""
    build_target_problem(target)

Build (uω0, fiber, sim, band_mask) for a target configuration NamedTuple.
"""
function build_target_problem(target::NamedTuple)
    return setup_raman_problem(
        fiber_preset = target.fiber_preset,
        L_fiber      = target.L,
        P_cont       = target.P,
        Nt           = SP_BASELINE_NT,
        time_window  = SP_BASELINE_TIME_WIN,
        β_order      = SP_BASELINE.β_order,
        gamma_user   = target.gamma,
        betas_user   = target.betas,
        fR           = target.fR,
        pulse_fwhm   = SP_BASELINE.pulse_fwhm,
        pulse_rep_rate = SP_BASELINE.pulse_rep,
    )
end

function stage_transferability(; verbose::Bool=true)
    verbose && @info "───── Phase 17 — Stage: TRANSFERABILITY ─────"
    baseline_path = joinpath(SP_RESULTS_DIR, "baseline.jld2")
    @assert isfile(baseline_path) "baseline.jld2 not found — run --stage=baseline first"
    out_path = joinpath(SP_RESULTS_DIR, "transferability.jld2")

    base = JLD2.load(baseline_path)
    phi_opt_baseline = base["phi_opt"]::Matrix{Float64}
    J_baseline_dB    = base["J_final_dB"]::Float64
    baseline_sim_Dt  = base["sim_Dt"]::Float64
    baseline_Nt      = base["Nt"]::Int

    # Reconstruct a minimal src_sim dict used only for interpolate_phi.
    src_sim = Dict{String, Any}(
        "Nt" => baseline_Nt,
        "M"  => Int(size(phi_opt_baseline, 2)),
        "Δt" => baseline_sim_Dt,
    )

    targets = build_transfer_grid()
    n = length(targets)

    J_eval_dB      = fill(NaN, n)
    J_warm_dB      = fill(NaN, n)
    wall_warm_s    = fill(NaN, n)
    warm_iter      = fill(0, n)
    warm_converged = fill(false, n)
    axis_arr       = fill("", n)
    fiber_arr      = fill("", n)
    L_arr          = fill(NaN, n)
    P_arr          = fill(NaN, n)
    Phi_NL_arr     = fill(NaN, n)
    is_baseline    = fill(false, n)

    # Store warm phi_opt for three representative targets — baseline point has no
    # warm reopt (continue'd) so we keep: shortest-L SMF-28, mid-range SMF-28,
    # HNLF-matched.
    phi_warm_samples = zeros(baseline_Nt, src_sim["M"], 3)
    phi_warm_sample_labels = ["short_SMF28_L0.25", "mid_SMF28_L1.0", "HNLF_L0.5_P5mW"]
    phi_warm_sample_idx = fill(-1, 3)

    # Serial outer loop — each target uses multi-threaded ODE/FFT internally.
    t_start = time()
    for i in 1:n
        tgt = targets[i]
        axis_arr[i]    = tgt.axis
        fiber_arr[i]   = tgt.fiber_name
        L_arr[i]       = tgt.L
        P_arr[i]       = tgt.P
        is_baseline[i] = tgt.is_baseline

        P_peak_i = 0.881374 * tgt.P / (SP_BASELINE.pulse_fwhm * SP_BASELINE.pulse_rep)
        Phi_NL_arr[i] = tgt.gamma * P_peak_i * tgt.L

        if tgt.is_baseline
            # Re-applying the baseline optimum to itself — analytically identical.
            J_eval_dB[i]      = J_baseline_dB
            J_warm_dB[i]      = J_baseline_dB
            wall_warm_s[i]    = 0.0
            warm_iter[i]      = 0
            warm_converged[i] = true
            verbose && @info @sprintf("[%2d/%d] BASELINE point (%s, L=%.2f, P=%.3f) — J=%.3f dB (no-op)",
                i, n, tgt.fiber_name, tgt.L, tgt.P, J_baseline_dB)
            continue
        end

        tgt_uω0, tgt_fiber, tgt_sim, tgt_band, _, _ = build_target_problem(tgt)
        tgt_fiber["zsave"] = nothing

        phi_interp = interpolate_phi(phi_opt_baseline, src_sim, tgt_sim)

        J_eval_dB[i] = eval_J_dB(phi_interp, tgt_uω0, tgt_fiber, tgt_sim, tgt_band)

        # Warm-start re-opt — fresh fiber copy because optimiser also toggles zsave.
        tgt_fiber_copy = deepcopy(tgt_fiber)
        tgt_fiber_copy["zsave"] = nothing
        t_wall = @elapsed warm_result = optimize_spectral_phase(
            tgt_uω0, tgt_fiber_copy, tgt_sim, tgt_band;
            φ0=phi_interp, max_iter=SP_TRANSFER_MAXITER, log_cost=true, store_trace=false)
        wall_warm_s[i]    = t_wall
        warm_iter[i]      = Optim.iterations(warm_result)
        warm_converged[i] = Optim.converged(warm_result)
        phi_warm = reshape(Optim.minimizer(warm_result), tgt_sim["Nt"], tgt_sim["M"])
        J_warm_dB[i] = eval_J_dB(phi_warm, tgt_uω0, tgt_fiber_copy, tgt_sim, tgt_band)

        # Keep a few warm phi samples (baseline point is a no-op; skipped above).
        if phi_warm_sample_idx[1] < 0 && tgt.fiber_name == "SMF-28" && tgt.L == 0.25
            phi_warm_samples[:, :, 1] = phi_warm
            phi_warm_sample_idx[1] = i
        end
        if phi_warm_sample_idx[2] < 0 && tgt.fiber_name == "SMF-28" && tgt.L == 1.0
            phi_warm_samples[:, :, 2] = phi_warm
            phi_warm_sample_idx[2] = i
        end
        if phi_warm_sample_idx[3] < 0 && tgt.fiber_name == "HNLF" && tgt.L == 0.5 && tgt.P == 0.005
            phi_warm_samples[:, :, 3] = phi_warm
            phi_warm_sample_idx[3] = i
        end

        # Rule 2: mandatory standard-image set for every phi_opt produced
        try
            fname_canonical = replace(String(tgt.fiber_name), "-" => "")
            tag = lowercase(@sprintf("%s_L%.2fm_P%.3fW_warm", fname_canonical, tgt.L, tgt.P))
            tag = replace(tag, "." => "p")
            save_standard_set(
                phi_warm, tgt_uω0, tgt_fiber_copy, tgt_sim, tgt_band,
                fftshift(fftfreq(tgt_sim["Nt"], 1 / tgt_sim["Δt"])), -5.0;
                tag        = tag,
                fiber_name = fname_canonical,
                L_m        = Float64(tgt.L),
                P_W        = Float64(tgt.P),
                output_dir = joinpath(SP_RESULTS_DIR, "standard_images"),
            )
        catch e
            @warn "save_standard_set failed for target $(i) (Rule 2 non-compliance)" exception=e
        end

        verbose && @info @sprintf("[%2d/%d] %s L=%.2fm P=%.3fW Φ_NL=%.2f: J_eval=%.2f dB → J_warm=%.2f dB (%.1fs, %d iter)",
            i, n, tgt.fiber_name, tgt.L, tgt.P, Phi_NL_arr[i],
            J_eval_dB[i], J_warm_dB[i], t_wall, warm_iter[i])
    end
    total_wall = time() - t_start
    verbose && @info @sprintf("TRANSFERABILITY done in %.1f s (%d points)", total_wall, n)

    jldsave(out_path;
        phase = "16", plan = "01", script = "simple_profile_driver",
        stage = "transferability",
        version = SP_VERSION,
        created_at = string(Dates.now()),
        baseline_path = baseline_path,
        J_baseline_dB = J_baseline_dB,
        n_targets = n,
        fiber_name_arr = fiber_arr,
        axis_arr = axis_arr,
        L_m_arr = L_arr,
        P_cont_W_arr = P_arr,
        Phi_NL_arr = Phi_NL_arr,
        is_baseline_arr = is_baseline,
        J_eval_dB_arr = J_eval_dB,
        J_warm_dB_arr = J_warm_dB,
        wall_warm_s_arr = wall_warm_s,
        warm_iter_arr = warm_iter,
        warm_converged_arr = warm_converged,
        phi_warm_samples = phi_warm_samples,
        phi_warm_sample_labels = phi_warm_sample_labels,
        phi_warm_sample_idx = phi_warm_sample_idx,
        julia_nthreads = Threads.nthreads(),
        fftw_nthreads  = FFTW.get_num_threads(),
        blas_nthreads  = BLAS.get_num_threads(),
        total_wall_s   = total_wall,
    )
    verbose && @info "TRANSFERABILITY written $(out_path)"
    return out_path
end

# ─────────────────────────────────────────────────────────────────────────────
# Main dispatch
# ─────────────────────────────────────────────────────────────────────────────

function main()
    stage = parse_stage(ARGS)
    @info "simple_profile_driver starting" stage=stage nthreads=Threads.nthreads()
    if stage == :baseline
        return stage_baseline()
    elseif stage == :perturbation
        return stage_perturbation()
    elseif stage == :transferability
        return stage_transferability()
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
