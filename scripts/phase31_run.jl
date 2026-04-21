# scripts/phase31_run.jl — Phase 31 driver (Branch A / B / C)
#
# Invocation (production, burst VM):
#   burst-run-heavy A-phase31 'julia -t auto --project=. scripts/phase31_run.jl --branch=A'
# Plan 02 runs --branch=B after filling run_branch_B; --branch=C is optional.
#
# Branch A: reduced-basis sweep. 21 optimization runs at the canonical
# SMF-28 L=2m P=0.2W point across the BASIS_PROGRAM ladder, with
# continuation warm-start across N_phi levels per basis family, multi-
# start at the coarsest N_phi, deepcopy(fiber) per thread, mandatory
# save_standard_set after every optimum, incremental JLD2 save, and
# coefficient-space Hessian diagnostics (skipped for N_phi > 512).
#
# Output layout (under `results/raman/phase31/`):
#   sweep_A_basis.jld2            — 21 rows (Vector{Dict{String,Any}})
#   sweep_A/images/*_phase_profile.png (and _evolution.png, etc.)
#   manifest_A_<RUN_TAG>.json     — provenance manifest
#
# Contracts (enforced by acceptance checks, see 31-01-PLAN.md §truths):
# - Every row has phi_opt::Vector{Float64} of length sim["Nt"] (never a
#   Matrix{Float64}(Nt, 1)).
# - Every row has c_opt::Vector{Float64} of length N_phi.
# - Every row carries the full 17-key schema; see `package_phase31_row`.
# - No mutations to shared files (see 31-01-PLAN.md truth 7).

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end

using Printf
using LinearAlgebra
using FFTW
using Logging
using Random
using Statistics
using JLD2
using Dates
using JSON3
using Arpack
using Optim

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "sweep_simple_param.jl"))
include(joinpath(@__DIR__, "phase13_primitives.jl"))
include(joinpath(@__DIR__, "phase13_hvp.jl"))
include(joinpath(@__DIR__, "phase31_basis_lib.jl"))
include(joinpath(@__DIR__, "phase31_penalty_lib.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Module constants (P31_ prefix per Script Constant Prefixes convention)
# ─────────────────────────────────────────────────────────────────────────────

const P31_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase31")
const P31_RUN_TAG     = Dates.format(now(), "yyyymmdd_HHMMSS")
const P31_NT          = 2^14
const P31_TIME_WINDOW = 10.0
const P31_MAX_ITER    = 80
const P31_CANONICAL   = (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2)

# Branch A basis program: 5 + 1 + 7 + 6 + 2 = 21 runs
const P31_BASIS_PROGRAM = [
    (:polynomial, [3, 4, 5, 6, 8]),
    (:chirp_ladder, [4]),
    (:dct, [4, 8, 16, 32, 64, 128, 256]),
    (:cubic, [4, 8, 16, 32, 64, 128]),
    (:linear, [16, 64]),
]

# Branch B penalty program: 5 + 4 + 4 + 4 + 4 = 21 runs (Plan 02 uses this)
const P31_PENALTY_PROGRAM = [
    (:tikhonov, [0.0, 1e-6, 1e-4, 1e-2, 1e0]),
    (:gdd,      [0.0, 1e-6, 1e-4, 1e-2]),
    (:tod,      [0.0, 1e-8, 1e-6, 1e-4]),
    (:tv,       [0.0, 1e-4, 1e-2, 1e0]),
    (:dct_l1,   [0.0, 1e-4, 1e-2, 1e0]),
]

const P31_HVP_MAX_NPHI = 16    # dense coefficient-space Hessian probe cap
                                # (dense needs 2*N_phi forward+adjoint solves per run;
                                #  at Nt=16384 each solve is ~10s → ~320s at N_phi=16.
                                #  Beyond 16, the probe dominates the run and the
                                #  saddle-masking signal is most relevant at small
                                #  N_phi anyway — Phase 35 showed the :chirp_ladder
                                #  N_phi=4 branch is where the indef_ratio artifact
                                #  is most dramatic. Plan 02 will re-do this for
                                #  larger N_phi using Arpack nev=10.)
const P31_HVP_EPS_BASE = 1e-4   # fallback ε if adaptive estimate is not available

mkpath(P31_RESULTS_DIR)
mkpath(joinpath(P31_RESULTS_DIR, "sweep_A", "images"))
mkpath(joinpath(P31_RESULTS_DIR, "sweep_B", "images"))

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
Return a 3-seed multi-start for a coefficient vector of length N_phi:
flat zero + ±quadratic chirp sized to produce modest phase variation.
Mirrors `multistart_seeds` from sweep_simple_run.jl (identical signature).
"""
function p31_multistart_seeds(N_phi::Int, Nt::Int)
    flat = zeros(Float64, N_phi)
    axis = range(-1.0, 1.0, length=N_phi)
    plus  = Float64.(1.0π .* axis .^ 2)
    minus = -plus
    return [flat, plus, minus]
end

"""
Safe lookup on the phase13 polynomial_project return — it returns a
NamedTuple with `residual_fraction`, which is (1 - R²). Some callers
expect `.r2`; provide a uniform accessor.
"""
function polynomial_r2_from_gauged(phi_gauged::AbstractVector{<:Real},
                                    omega::AbstractVector{<:Real},
                                    bw_mask::AbstractVector{Bool})
    sum(bw_mask) < 5 && return NaN
    try
        proj = polynomial_project(phi_gauged, omega, bw_mask; orders=2:4)
        return 1.0 - proj.residual_fraction
    catch e
        @warn "polynomial_project failed" error=sprint(showerror, e)
        return NaN
    end
end

"""
Run the coefficient-space Hessian diagnostic at the optimum c_opt.

Builds an FD HVP oracle on `cost_and_gradient_lowres`. Uses Arpack to
extract the top and bottom of the spectrum; reports
`hess_indef_ratio = |λ_min_bot| / λ_max_top` and
`kappa_H_restricted = λ_max_top / max(|λ_min_pos|, eps)`.

Returns `(; hess_indef_ratio, kappa_H_restricted, reason)`. `reason`
is non-empty when the probe is skipped (e.g., N_phi too large).
"""
function compute_hessian_diagnostics(c_opt::AbstractVector{<:Real},
                                      B::AbstractMatrix{<:Real},
                                      uω0, fiber, sim,
                                      band_mask::AbstractVector{Bool};
                                      eps_fd::Real = P31_HVP_EPS_BASE)
    N_c = length(c_opt)
    if N_c < 4
        return (hess_indef_ratio = NaN, kappa_H_restricted = NaN,
                reason = "N_phi=$(N_c) < 4 (too small for Arpack)")
    end
    if N_c > P31_HVP_MAX_NPHI
        return (hess_indef_ratio = NaN, kappa_H_restricted = NaN,
                reason = "N_phi=$(N_c) > $(P31_HVP_MAX_NPHI) (HVP skipped for cost)")
    end

    # Coefficient-space oracle: returns ∂J/∂c at log_cost=false (probe
    # landscape, not log-scaled). `fiber` must be exclusively held by
    # this thread — caller ensures that via deepcopy upstream.
    function coeff_oracle(c_vec)
        _, dc = cost_and_gradient_lowres(c_vec, B, uω0, fiber, sim, band_mask;
                                          log_cost=false)
        return dc
    end

    # HVP via central difference on the oracle
    hvp_fn = (x, v) -> fd_hvp(x, v, coeff_oracle; eps=eps_fd)

    # Build a small symmetric linear operator for eigs (matrix-free)
    try
        # Form a dense small Hessian since N_c ≤ 512 is affordable:
        # 2·N_c gradient evaluations total.
        H = zeros(Float64, N_c, N_c)
        for k in 1:N_c
            e_k = zeros(Float64, N_c); e_k[k] = 1.0
            H[:, k] = hvp_fn(Vector{Float64}(c_opt), e_k)
        end
        # Symmetrize (central-diff HVP is symmetric up to FD noise)
        Hs = 0.5 .* (H .+ H')
        eigs_vals = eigvals(Symmetric(Hs))
        λ_max = maximum(eigs_vals)
        λ_min = minimum(eigs_vals)
        # indefiniteness ratio: if Hessian is PSD, λ_min ≥ 0 and ratio = 0.
        # We define indef_ratio = max(-λ_min, 0) / max(|λ_max|, eps)
        neg_part = max(-λ_min, 0.0)
        hess_indef_ratio = neg_part / max(abs(λ_max), eps())
        # conditioning: λ_max / |smallest positive eigenvalue|. If there are
        # no positive eigenvalues, report Inf.
        pos_vals = filter(>(0.0), eigs_vals)
        kappa_H_restricted = isempty(pos_vals) ? Inf :
            abs(λ_max) / minimum(pos_vals)
        return (hess_indef_ratio = hess_indef_ratio,
                kappa_H_restricted = kappa_H_restricted,
                reason = "")
    catch e
        return (hess_indef_ratio = NaN, kappa_H_restricted = NaN,
                reason = "HVP failed: $(sprint(showerror, e))")
    end
end

"""
    package_phase31_row(r, uω0, fiber, sim, band_mask, bw_mask, omega;
                         config, branch, kind, N_phi, penalties, B,
                         wall_time_s, hess_diag) -> Dict{String,Any}

Extend sweep_simple_run's `package_result` with Phase-31-specific fields.

Shape contract (Plan 02 depends):
  - "phi_opt" = vec(r.phi_opt) — always a 1D Vector{Float64} of length Nt.
  - "c_opt"   = collect(r.c_opt) — length N_phi (or Nt for :identity).

Any caller that wants a matrix reshapes at the call site.
"""
function package_phase31_row(r, uω0, fiber, sim, band_mask, bw_mask, omega;
                              config::NamedTuple,
                              branch::AbstractString,
                              kind::Symbol,
                              N_phi::Int,
                              penalties::Dict{Symbol,Float64},
                              B::AbstractMatrix{<:Real},
                              wall_time_s::Real,
                              hess_diag::NamedTuple,
                              seed_count::Int = 1)

    phi_vec_raw  = vec(r.phi_opt)
    c_vec        = vec(r.c_opt)          # reshape(Nphi, M) → length Nphi when M=1
    # Gauge-fix for simplicity metrics
    phi_gauged, (C_gauge, α_gauge) = gauge_fix(phi_vec_raw, bw_mask, omega)
    phi_gauged_vec = vec(phi_gauged)

    # Basis conditioning (Gram matrix on full Nt grid)
    cond_info = basis_conditioning(B, bw_mask)

    # J_raman_linear: r.J_final is in dB (log_cost=true). Convert back.
    J_raman_linear = 10.0 ^ (r.J_final / 10.0)

    # polynomial R² on the gauge-fixed phase
    poly_r2 = polynomial_r2_from_gauged(phi_gauged_vec, omega, bw_mask)

    regularization_mode =
        branch == "A" ? "basis" :
        branch == "B" ? "penalty" : "hybrid"

    return Dict{String,Any}(
        # Provenance
        "run_tag"             => P31_RUN_TAG,
        "branch"              => branch,
        "regularization_mode" => regularization_mode,
        # Config
        "config"              => Dict(String(k) => v for (k, v) in pairs(config)),
        # Basis identity
        "kind"                => String(kind),
        "N_phi"               => N_phi,
        "kappa_B"             => cond_info.kappa_B,
        "kappa_B_warned"      => cond_info.kappa_warning,
        # Penalties (Branch A → all zeros; Branch B fills its vector)
        "penalties"           => Dict(String(k) => v for (k, v) in pairs(penalties)),
        # Optimum
        "c_opt"               => collect(c_vec),
        "phi_opt"             => collect(phi_vec_raw),
        "phi_opt_gauged"      => collect(phi_gauged_vec),
        "gauge_C"             => C_gauge,
        "gauge_alpha"         => α_gauge,
        "J_final"             => r.J_final,
        "J_raman_linear"      => J_raman_linear,
        "iterations"          => r.iterations,
        "converged"           => r.converged,
        "wall_time_s"         => wall_time_s,
        "seed_count"          => seed_count,
        # Simplicity metrics
        "N_eff"               => phase_neff(phi_gauged_vec, bw_mask),
        "TV"                  => phase_tv(phi_gauged_vec, bw_mask),
        "curvature"           => phase_curvature(phi_gauged_vec, sim, bw_mask),
        # Interpretability
        "polynomial_R2"       => poly_r2,
        # Conditioning / saddle diagnostics
        "hess_indef_ratio"    => hess_diag.hess_indef_ratio,
        "kappa_H_restricted"  => hess_diag.kappa_H_restricted,
        "hess_probe_skipped_reason" => hess_diag.reason,
    )
end

"""
Write the provenance manifest alongside the JLD2.
"""
function write_manifest(save_path::AbstractString,
                         branch::AbstractString,
                         program::AbstractVector,
                         row_count::Int,
                         total_wall_time::Real;
                         dry_run::Bool = false)
    git_sha = try
        readchomp(`git -C $(@__DIR__) rev-parse HEAD`)
    catch
        "unknown"
    end
    manifest = Dict(
        "run_tag"          => P31_RUN_TAG,
        "branch"           => branch,
        "git_commit"       => git_sha,
        "julia_version"    => string(VERSION),
        "threads"          => Threads.nthreads(),
        "basis_program"    => [(String(k), v) for (k, v) in program],
        "canonical_config" => Dict(String(k) => v for (k, v) in pairs(P31_CANONICAL)),
        "P31_NT"           => P31_NT,
        "P31_TIME_WINDOW"  => P31_TIME_WINDOW,
        "P31_MAX_ITER"     => P31_MAX_ITER,
        "jld2_path"        => save_path,
        "image_dir"        => joinpath(P31_RESULTS_DIR, "sweep_$(branch)", "images"),
        "total_rows"       => row_count,
        "total_wall_time_s"=> total_wall_time,
        "dry_run"          => dry_run,
    )
    manifest_path = joinpath(P31_RESULTS_DIR,
                              "manifest_$(branch)_$(P31_RUN_TAG).json")
    open(manifest_path, "w") do io
        JSON3.pretty(io, manifest)
    end
    @info "manifest written" path=manifest_path
    return manifest_path
end

# ─────────────────────────────────────────────────────────────────────────────
# run_branch_A — basis sweep at the canonical SMF-28 point
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_branch_A(; dry_run=false) -> Vector{Dict{String,Any}}

Execute the 21-run basis sweep. On `dry_run=true`, the function builds
bases, prints the plan, and writes a dry-run manifest, but skips the
optimizations themselves.
"""
function run_branch_A(; dry_run::Bool = false)
    t_branch_start = time()

    @info "Phase 31 Branch A — basis sweep" canonical=P31_CANONICAL Nt=P31_NT threads=Threads.nthreads() dry_run=dry_run

    # ── Setup canonical problem once ─────────────────────────────────────
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
        fiber_preset = P31_CANONICAL.fiber_preset,
        β_order      = 3,
        L_fiber      = P31_CANONICAL.L_fiber,
        P_cont       = P31_CANONICAL.P_cont,
        Nt           = P31_NT,
        time_window  = P31_TIME_WINDOW,
    )
    Nt = sim["Nt"]
    bw_mask = pulse_bandwidth_mask(uω0)
    omega = omega_vector(sim["ω0"], sim["Δt"], Nt)
    bw_bins = sum(bw_mask)
    @info @sprintf("  Nt=%d  bandwidth bins=%d (%.1f%% of grid)", Nt, bw_bins, 100 * bw_bins / Nt)

    empty_penalties = Dict(k => 0.0 for k in
        (:tikhonov, :gdd, :tod, :tv, :dct_l1))

    rows = Dict{String,Any}[]
    save_path = joinpath(P31_RESULTS_DIR, "sweep_A_basis.jld2")
    images_dir = joinpath(P31_RESULTS_DIR, "sweep_A", "images")
    mkpath(images_dir)

    # Resume support: load previously completed rows so an interrupted sweep
    # can be re-launched without redoing work. Keyed on (kind_string, N_phi).
    completed_keys = Set{Tuple{String,Int}}()
    if !dry_run && isfile(save_path)
        try
            prev = JLD2.load(save_path, "rows")
            append!(rows, prev)
            for r in prev
                push!(completed_keys, (String(r["kind"]), r["N_phi"]))
            end
            @info @sprintf("  resume: loaded %d completed rows from %s",
                           length(prev), save_path)
        catch e
            @warn "resume: failed to load existing rows, starting fresh" error=sprint(showerror, e)
        end
    end

    run_counter = 0
    total_expected = sum(length(nl) for (_, nl) in P31_BASIS_PROGRAM)

    for (kind, nphi_list) in P31_BASIS_PROGRAM
        c_prev = nothing
        B_prev = nothing
        for N_phi in nphi_list
            run_counter += 1

            # Skip physically meaningless configs where N_phi exceeds bandwidth
            if N_phi > bw_bins
                @info @sprintf("[%d/%d] skip kind=:%s N_phi=%d > bw_bins=%d (physically meaningless)",
                               run_counter, total_expected, kind, N_phi, bw_bins)
                continue
            end

            # Resume: skip configs already completed in a previous run
            if (String(kind), N_phi) in completed_keys
                @info @sprintf("[%d/%d] resume: skip kind=:%s N_phi=%d (already in sweep_A_basis.jld2)",
                               run_counter, total_expected, kind, N_phi)
                continue
            end

            t_run_start = time()
            B = build_basis_dispatch(kind, Nt, N_phi, bw_mask, sim)

            # Seed selection: multi-start at level 1, otherwise continuation
            # upsample from the previous best.
            seeds = if c_prev === nothing
                p31_multistart_seeds(N_phi, Nt)
            else
                [continuation_upsample(c_prev, B_prev, B)]
            end

            @info @sprintf("[%d/%d] kind=:%s N_phi=%d seeds=%d",
                           run_counter, total_expected, kind, N_phi, length(seeds))

            if dry_run
                @info "  (dry-run) would optimize"
                c_prev = zeros(N_phi); B_prev = B
                continue
            end

            # Parallel multi-start with per-thread deepcopy(fiber). We only
            # parallelize when there are ≥2 seeds — else just run sequentially
            # and save the thread-management overhead.
            best = nothing
            best_lock = ReentrantLock()

            function _one_opt(c0)
                fiber_local = deepcopy(fiber)
                r = optimize_phase_lowres(uω0, fiber_local, sim, band_mask;
                                          N_phi = size(B, 2),
                                          kind  = kind,
                                          bandwidth_mask = bw_mask,
                                          c0 = collect(c0),
                                          B_precomputed = B,
                                          max_iter = P31_MAX_ITER,
                                          log_cost = true)
                lock(best_lock) do
                    if best === nothing || r.J_final < best.J_final
                        best = r
                    end
                end
                return nothing
            end

            if length(seeds) ≥ 2
                Threads.@threads for s in seeds
                    _one_opt(s)
                end
            else
                _one_opt(seeds[1])
            end

            @assert best !== nothing "no optimization succeeded for kind=$kind N_phi=$N_phi"

            wall_time_s = time() - t_run_start

            # Hessian diagnostics — use deepcopy(fiber) to isolate from any
            # other threads that might pick this up later.
            hess_diag = compute_hessian_diagnostics(vec(best.c_opt),
                                                     best.B, uω0,
                                                     deepcopy(fiber), sim,
                                                     band_mask)

            # Build row dict and persist incrementally
            row = package_phase31_row(
                best, uω0, fiber, sim, band_mask, bw_mask, omega;
                config = (fiber_preset = String(P31_CANONICAL.fiber_preset),
                          L_fiber = P31_CANONICAL.L_fiber,
                          P_cont  = P31_CANONICAL.P_cont),
                branch = "A",
                kind = kind,
                N_phi = N_phi,
                penalties = empty_penalties,
                B = best.B,
                wall_time_s = wall_time_s,
                hess_diag = hess_diag,
                seed_count = length(seeds),
            )
            push!(rows, row)
            JLD2.jldsave(save_path; rows = rows, run_tag = P31_RUN_TAG)
            @info @sprintf("  -> J=%.3f dB  iters=%d  conv=%s  κ_B=%.2e  wall=%.1fs  saved %d rows",
                           best.J_final, best.iterations, best.converged,
                           row["kappa_B"], wall_time_s, length(rows))

            # Mandatory standard image set — emit one per optimum.
            tag = @sprintf("p31A_%s_N%03d", String(kind), N_phi)
            phi_matrix = reshape(vec(best.phi_opt), Nt, 1)
            try
                save_standard_set(phi_matrix, uω0, fiber, sim,
                                  band_mask, Δf, raman_threshold;
                                  tag = tag,
                                  fiber_name = String(P31_CANONICAL.fiber_preset),
                                  L_m = P31_CANONICAL.L_fiber,
                                  P_W = P31_CANONICAL.P_cont,
                                  output_dir = images_dir)
            catch e
                @warn "standard image emission failed" tag=tag error=sprint(showerror, e)
            end

            # Force matplotlib/PyCall cleanup. Observed 2026-04-21 on Mac:
            # PyPlot figure handles accumulate across save_standard_set calls
            # and fire a PyObject finalizer segfault on GC or process shutdown
            # (_PyObject_Free → unicode_dealloc → pydecref_). Explicit close
            # + GC between runs prevents the crash.
            try
                if isdefined(Main, :PyPlot)
                    Base.invokelatest(Main.PyPlot.close, "all")
                end
            catch
            end
            GC.gc()

            # Propagate for continuation warm-start
            c_prev = vec(best.c_opt)
            B_prev = best.B
        end
    end

    total_wall_time = time() - t_branch_start
    @info @sprintf("Branch A complete: %d rows saved to %s (%.1fs)",
                   length(rows), save_path, total_wall_time)

    # Manifest
    write_manifest(save_path, "A", P31_BASIS_PROGRAM, length(rows),
                    total_wall_time; dry_run = dry_run)

    @info "Reminder: run `burst-stop` when this VM is no longer needed."
    return rows
end

# ─────────────────────────────────────────────────────────────────────────────
# run_branch_B — stub; implemented in Plan 02
# ─────────────────────────────────────────────────────────────────────────────

function run_branch_B(; dry_run::Bool = false)
    error("run_branch_B is implemented in Plan 02 Task 1 — invoke scripts/phase31_run.jl --branch=B only after Plan 02 is complete")
end

# ─────────────────────────────────────────────────────────────────────────────
# Main dispatch
# ─────────────────────────────────────────────────────────────────────────────

function _p31_main()
    branch = "A"
    dry_run = false
    for arg in ARGS
        if startswith(arg, "--branch=")
            branch = arg[length("--branch=") + 1:end]
        elseif arg == "--dry-run"
            dry_run = true
        end
    end
    if branch == "A"
        run_branch_A(; dry_run = dry_run)
    elseif branch == "B"
        run_branch_B(; dry_run = dry_run)
    else
        error("Unknown branch: $branch (expected A or B)")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    _p31_main()
end
