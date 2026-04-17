"""
Session E — Sweep driver for low-resolution phase optimization

Runs two sweeps:

  Sweep 1 (J vs N_phi knee-finder)
    N_phi ∈ {4, 8, 16, 32, 64, 128, 256, 512, Nt} at one canonical config
    (SMF-28 L=2m P=0.2W). Continuation warm-start from the coarser level.
    3-seed multi-start at the coarsest level; subsequent levels single-start
    from the upsampled previous optimum.

  Sweep 2 (robust-candidate hunter)
    (L, P) ∈ {0.25, 0.5, 1.0, 2.0}m × {0.02, 0.05, 0.1, 0.2}W (16 configs)
    Fibers: :SMF28, :HNLF
    N_phi ∈ {16, 64}
    Total: 16 × 2 × 2 = 64 optimization runs.
    Parallel via Threads.@threads with per-thread deepcopy(fiber).
    3-seed multi-start at N_phi=16; warm-start at N_phi=64 from N_phi=16
    optimum per config.

Results saved to results/raman/phase_sweep_simple/*.jld2.

Usage
=====
  julia -t auto --project=. scripts/sweep_simple_run.jl [--sweep1|--sweep2|--both] [--dry-run]

Defaults to `--both`. `--dry-run` builds basis and prints the sweep plan but
skips optimization (for wall-time estimation).
"""

ENV["MPLBACKEND"] = "Agg"

try using Revise catch end

using LinearAlgebra
using FFTW
using Printf
using Random
using Logging
using Statistics
using JLD2
using Dates

include(joinpath(@__DIR__, "sweep_simple_param.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Session-E run constants
# ─────────────────────────────────────────────────────────────────────────────

const LR_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase_sweep_simple")
const LR_RUN_TAG = Dates.format(now(), "yyyymmdd_HHMMSS")

const LR_SWEEP1_NPHI = [4, 8, 16, 32, 64, 128, 256, 512]   # + Nt added at runtime
const LR_SWEEP1_CONFIG = (fiber_preset=:SMF28, L_fiber=2.0, P_cont=0.2)

const LR_SWEEP2_LS  = [0.25, 0.5, 1.0, 2.0]
const LR_SWEEP2_PS  = [0.02, 0.05, 0.1, 0.2]
const LR_SWEEP2_FIBERS = [:SMF28, :HNLF]
const LR_SWEEP2_NPHI = [16, 64]

const LR_MAX_ITER = 50
const LR_BASELINE_NT = 2^14
const LR_BASELINE_TW = 10.0
const LR_LOG_COST = true
const LR_N_MULTISTART = 3

mkpath(LR_RESULTS_DIR)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
Build a canonical multi-start seed set (3 seeds): flat phase, ±linear chirp
sized so the quadratic phase produces a modest pulse broadening.
"""
function multistart_seeds(N_phi::Int, Nt::Int)
    # Flat seed
    seed_flat = zeros(Float64, N_phi)
    # Linear chirp ~ π rad variation across knots (N_phi values 0..π)
    ω_axis = range(-1.0, 1.0, length=N_phi)
    seed_plus  = Float64.(1.0π .* ω_axis.^2)
    seed_minus = -seed_plus
    return [seed_flat, seed_plus, seed_minus]
end

function run_one_optimization(uω0, fiber, sim, band_mask;
                               N_phi::Int, kind::Symbol,
                               bw_mask::Union{Nothing,AbstractVector{Bool}},
                               c0::AbstractVector{<:Real},
                               max_iter::Int=LR_MAX_ITER,
                               log_cost::Bool=LR_LOG_COST,
                               B_precomputed::Union{Nothing,AbstractMatrix{<:Real}}=nothing)
    return optimize_phase_lowres(uω0, fiber, sim, band_mask;
                                 N_phi=N_phi, kind=kind, bandwidth_mask=bw_mask,
                                 c0=collect(c0), B_precomputed=B_precomputed,
                                 max_iter=max_iter, log_cost=log_cost)
end

"""
Package a result row for the JLD2 dictionary.
"""
function package_result(r, uω0, sim, band_mask, bw_mask; config::NamedTuple)
    phi_vec = vec(r.phi_opt)
    return Dict(
        "config"        => Dict(pairs(config)),
        "N_phi"         => r.N_phi,
        "kind"          => String(r.kind),
        "c_opt"         => vec(r.c_opt),
        "phi_opt"       => phi_vec,
        "J_final"       => r.J_final,
        "iterations"    => r.iterations,
        "converged"     => r.converged,
        "N_eff"         => phase_neff(phi_vec, bw_mask),
        "TV"            => phase_tv(phi_vec, bw_mask),
        "curvature"     => phase_curvature(phi_vec, sim, bw_mask),
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Sweep 1 — J vs N_phi at a canonical config
# ─────────────────────────────────────────────────────────────────────────────

function run_sweep1(; dry_run::Bool=false)
    @info "Sweep 1 (J vs N_phi knee) at $(LR_SWEEP1_CONFIG)"
    uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
        fiber_preset = LR_SWEEP1_CONFIG.fiber_preset,
        β_order      = 3,
        L_fiber      = LR_SWEEP1_CONFIG.L_fiber,
        P_cont       = LR_SWEEP1_CONFIG.P_cont,
        Nt           = LR_BASELINE_NT,
        time_window  = LR_BASELINE_TW,
    )
    Nt = sim["Nt"]
    bw_mask = pulse_bandwidth_mask(uω0)
    bw_bins = sum(bw_mask)
    @info @sprintf("  Nt=%d  bandwidth bins=%d  (%.1f%% of grid)", Nt, bw_bins, 100*bw_bins/Nt)

    N_phi_levels = copy(LR_SWEEP1_NPHI)
    push!(N_phi_levels, Nt)

    results = Vector{Dict{String, Any}}()
    c_prev = nothing
    B_prev = nothing

    bw_bins_count = sum(bw_mask)
    for (lvl, N_phi) in enumerate(N_phi_levels)
        is_baseline = (N_phi == Nt)
        if !is_baseline && N_phi > bw_bins_count
            @info @sprintf("[sweep1 level %d/%d] N_phi=%d exceeds bandwidth bins=%d — skipping (physically meaningless: cannot have more shaper pixels than spectral bins)",
                           lvl, length(N_phi_levels), N_phi, bw_bins_count)
            continue
        end
        kind = is_baseline ? :identity : :cubic
        @info @sprintf("[sweep1 level %d/%d] N_phi=%d kind=:%s", lvl, length(N_phi_levels), N_phi, kind)

        if is_baseline
            # Full-resolution baseline — bypass the low-res wrapper (an explicit
            # Nt×Nt identity would be 2 GB for Nt=2^14). Route directly to the
            # canonical optimizer.
            if dry_run
                @info "  (dry-run) would run full-res optimize_spectral_phase"
                continue
            end
            # Upsample previous-level optimum into the Nt-long phase as φ0
            if c_prev !== nothing
                φ0 = reshape(B_prev * c_prev, Nt, 1)
            else
                φ0 = zeros(Nt, 1)
            end
            t0 = time()
            result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
                                              φ0=φ0, max_iter=LR_MAX_ITER,
                                              log_cost=LR_LOG_COST)
            phi_full = reshape(Optim.minimizer(result), Nt, 1)
            elapsed = time() - t0
            @info @sprintf("  baseline: J=%.3f dB  iters=%d  (%.1fs)",
                           Optim.minimum(result), Optim.iterations(result), elapsed)
            row = Dict(
                "config"     => Dict("N_phi"=>N_phi, "kind"=>"identity",
                                     "fiber_preset"=>String(LR_SWEEP1_CONFIG.fiber_preset),
                                     "L_fiber"=>LR_SWEEP1_CONFIG.L_fiber,
                                     "P_cont"=>LR_SWEEP1_CONFIG.P_cont),
                "N_phi"      => N_phi,
                "kind"       => "identity",
                "c_opt"      => vec(phi_full),
                "phi_opt"    => vec(phi_full),
                "J_final"    => Optim.minimum(result),
                "iterations" => Optim.iterations(result),
                "converged"  => Optim.f_converged(result),
                "N_eff"      => phase_neff(vec(phi_full), bw_mask),
                "TV"         => phase_tv(vec(phi_full), bw_mask),
                "curvature"  => phase_curvature(vec(phi_full), sim, bw_mask),
            )
            push!(results, row)
            save_path = joinpath(LR_RESULTS_DIR, "sweep1_Nphi.jld2")
            JLD2.jldsave(save_path; results, run_tag=LR_RUN_TAG)
            @info "  saved $(save_path) ($(length(results)) rows)"
            continue
        end

        # Low-resolution levels: build a small (Nt × N_phi) basis
        B = build_phase_basis(Nt, N_phi; kind=kind, bandwidth_mask=bw_mask)

        # Seeds: coarsest level → multi-start; finer levels → warm-start from prev optimum.
        if lvl == 1
            seeds = multistart_seeds(N_phi, Nt)
        else
            c_upsampled = continuation_upsample(c_prev, B_prev, B)
            seeds = [c_upsampled]
        end

        if dry_run
            @info "  (dry-run) would run $(length(seeds)) opts"
            c_prev = zeros(N_phi); B_prev = B
            continue
        end

        best = nothing
        for (si, s) in enumerate(seeds)
            r = run_one_optimization(uω0, fiber, sim, band_mask;
                                      N_phi=N_phi, kind=kind, bw_mask=bw_mask,
                                      c0=s, B_precomputed=B)
            @info @sprintf("  seed %d: J=%.3f dB  iters=%d  conv=%s",
                           si, r.J_final, r.iterations, r.converged)
            if best === nothing || r.J_final < best.J_final
                best = r
            end
        end

        row = package_result(best, uω0, sim, band_mask, bw_mask;
                             config=(N_phi=N_phi, kind=kind,
                                     fiber_preset=LR_SWEEP1_CONFIG.fiber_preset,
                                     L_fiber=LR_SWEEP1_CONFIG.L_fiber,
                                     P_cont=LR_SWEEP1_CONFIG.P_cont))
        push!(results, row)

        # Save incrementally after every level so we never lose progress
        save_path = joinpath(LR_RESULTS_DIR, "sweep1_Nphi.jld2")
        JLD2.jldsave(save_path; results, run_tag=LR_RUN_TAG)
        @info "  saved $(save_path) ($(length(results)) rows)"

        # Propagate best c_opt + basis for next-level warm-start
        c_prev = vec(best.c_opt)
        B_prev = B
    end

    @info "Sweep 1 complete ($(length(results)) levels)"
    # Rule 2 (project-level): emit the standard 4-image set for every phi_opt.
    finalize_standard_images(results;
                              uω0=uω0, fiber=fiber, sim=sim,
                              band_mask=band_mask, bw_mask=bw_mask,
                              subdir="sweep1_canonical",
                              fiber_name=String(LR_SWEEP1_CONFIG.fiber_preset),
                              L_m=LR_SWEEP1_CONFIG.L_fiber,
                              P_W=LR_SWEEP1_CONFIG.P_cont)
    return results
end

"""
Emit `save_standard_set` for every successful row. Skips rows missing phi_opt.
Required by project Rule 2 (standard output images).
"""
function finalize_standard_images(results::Vector{<:Dict};
                                   uω0=nothing, fiber=nothing, sim=nothing,
                                   band_mask=nothing, bw_mask=nothing,
                                   subdir::AbstractString,
                                   fiber_name::AbstractString="",
                                   L_m::Real=0.0, P_W::Real=0.0,
                                   rebuild_per_config::Bool=false)
    out_dir = joinpath(LR_RESULTS_DIR, subdir)
    mkpath(out_dir)
    Nt = sim === nothing ? nothing : sim["Nt"]
    _get_Δf(sim) = fftshift(fftfreq(sim["Nt"], 1/sim["Δt"]))
    for (i, r) in enumerate(results)
        haskey(r, "phi_opt") || continue
        phi_vec = r["phi_opt"]
        cfg = get(r, "config", Dict())
        _cg(k) = haskey(cfg, Symbol(k)) ? cfg[Symbol(k)] : get(cfg, k, nothing)
        fiber_name_row = String(something(_cg("fiber_preset"), fiber_name))
        L_row = Float64(something(_cg("L_fiber"), L_m))
        P_row = Float64(something(_cg("P_cont"), P_W))
        N_phi_row = Int(get(r, "N_phi", -1))
        tag = @sprintf("%s_L%.2fm_P%.3fW_Nphi%d",
                       replace(fiber_name_row, "-" => ""),
                       L_row, P_row, N_phi_row)

        if rebuild_per_config || Nt === nothing || length(phi_vec) != Nt
            # Rebuild per-row setup — configs differ
            local uω0_r, fiber_r, sim_r, band_mask_r, Δf_r, raman_thr_r
            uω0_r, fiber_r, sim_r, band_mask_r, Δf_r, raman_thr_r = setup_raman_problem(;
                fiber_preset = Symbol(fiber_name_row),
                β_order      = 3,
                L_fiber      = L_row,
                P_cont       = P_row,
                Nt           = LR_BASELINE_NT,
                time_window  = LR_BASELINE_TW,
            )
            phi_mat = length(phi_vec) == sim_r["Nt"] ? reshape(phi_vec, sim_r["Nt"], 1) : phi_vec
            try
                save_standard_set(phi_mat, uω0_r, fiber_r, sim_r,
                                  band_mask_r, Δf_r, raman_thr_r;
                                  tag=tag, fiber_name=fiber_name_row,
                                  L_m=L_row, P_W=P_row, output_dir=out_dir)
            catch e
                @warn "standard image failed" row=i tag=tag error=sprint(showerror, e)
            end
        else
            Δf = _get_Δf(sim)
            raman_thr = -5.0
            phi_mat = reshape(phi_vec, Nt, 1)
            try
                save_standard_set(phi_mat, uω0, fiber, sim,
                                  band_mask, Δf, raman_thr;
                                  tag=tag, fiber_name=fiber_name_row,
                                  L_m=L_row, P_W=P_row, output_dir=out_dir)
            catch e
                @warn "standard image failed" row=i tag=tag error=sprint(showerror, e)
            end
        end
        flush(stderr)
    end
    @info "Standard images written to $(out_dir) ($(length(results)) rows)"
    return nothing
end

# ─────────────────────────────────────────────────────────────────────────────
# Sweep 2 — (L, P, fiber) grid at low N_phi, parallel over configs
# ─────────────────────────────────────────────────────────────────────────────

"""
Run one (L, P, fiber) config at N_phi=16 (multi-start) then N_phi=64
(warm-started from N_phi=16). Returns a Vector of two result dicts.

Each thread MUST run with its own deepcopy(fiber) — see CLAUDE.md.
"""
function run_one_config_sweep2(; fiber_preset::Symbol, L_fiber::Real, P_cont::Real)
    tid = Threads.threadid()
    println(stderr, "[thr $tid] enter setup $(fiber_preset) L=$(L_fiber) P=$(P_cont)"); flush(stderr)
    uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
        fiber_preset = fiber_preset,
        β_order      = 3,
        L_fiber      = L_fiber,
        P_cont       = P_cont,
        Nt           = LR_BASELINE_NT,
        time_window  = LR_BASELINE_TW,
    )
    bw_mask = pulse_bandwidth_mask(uω0)
    bw_bins = sum(bw_mask)
    Nt = sim["Nt"]
    println(stderr, "[thr $tid] setup done Nt=$(Nt) bw_bins=$(bw_bins) $(fiber_preset) L=$(L_fiber) P=$(P_cont)"); flush(stderr)

    out = Vector{Dict{String,Any}}()

    # ---- level 1: N_phi=16, 3-seed multi-start ----
    best16 = nothing
    if bw_bins < 16
        err = Dict(
            "config" => Dict("fiber_preset"=>String(fiber_preset),
                             "L_fiber"=>L_fiber, "P_cont"=>P_cont, "N_phi"=>16),
            "N_phi" => 16,
            "error" => "bandwidth bins $bw_bins < N_phi 16 — pulse too narrow",
        )
        push!(out, err)
    else
        try
            B16 = build_phase_basis(Nt, 16; kind=:cubic, bandwidth_mask=bw_mask)
            seeds16 = multistart_seeds(16, Nt)
            for s in seeds16
                r = run_one_optimization(uω0, fiber, sim, band_mask;
                                         N_phi=16, kind=:cubic, bw_mask=bw_mask,
                                         c0=s, B_precomputed=B16,
                                         max_iter=30)  # trimmed from 50 to bound tail latency
                if best16 === nothing || r.J_final < best16.J_final
                    best16 = r
                end
            end
            push!(out, package_result(best16, uω0, sim, band_mask, bw_mask;
                                      config=(N_phi=16, kind=:cubic,
                                              fiber_preset=fiber_preset,
                                              L_fiber=L_fiber, P_cont=P_cont)))
        catch e
            push!(out, Dict(
                "config" => Dict("fiber_preset"=>String(fiber_preset),
                                 "L_fiber"=>L_fiber, "P_cont"=>P_cont, "N_phi"=>16),
                "N_phi" => 16,
                "error" => sprint(showerror, e),
            ))
        end
    end

    # ---- level 2: N_phi=64 (or clamped), warm-started from level 1 ----
    N_phi_2 = min(64, bw_bins)   # clamp to physical ceiling
    if best16 === nothing || N_phi_2 < 8
        push!(out, Dict(
            "config" => Dict("fiber_preset"=>String(fiber_preset),
                             "L_fiber"=>L_fiber, "P_cont"=>P_cont, "N_phi"=>N_phi_2),
            "N_phi" => N_phi_2,
            "error" => "level 1 failed or bandwidth too narrow ($(bw_bins) bins)",
        ))
    else
        try
            B2 = build_phase_basis(Nt, N_phi_2; kind=:cubic, bandwidth_mask=bw_mask)
            B16 = build_phase_basis(Nt, 16; kind=:cubic, bandwidth_mask=bw_mask)
            c2_0 = continuation_upsample(vec(best16.c_opt), B16, B2)
            r2 = run_one_optimization(uω0, fiber, sim, band_mask;
                                       N_phi=N_phi_2, kind=:cubic, bw_mask=bw_mask,
                                       c0=c2_0, B_precomputed=B2,
                                       max_iter=30)
            push!(out, package_result(r2, uω0, sim, band_mask, bw_mask;
                                      config=(N_phi=N_phi_2, kind=:cubic,
                                              fiber_preset=fiber_preset,
                                              L_fiber=L_fiber, P_cont=P_cont)))
        catch e
            push!(out, Dict(
                "config" => Dict("fiber_preset"=>String(fiber_preset),
                                 "L_fiber"=>L_fiber, "P_cont"=>P_cont, "N_phi"=>N_phi_2),
                "N_phi" => N_phi_2,
                "error" => sprint(showerror, e),
            ))
        end
    end
    return out
end

function run_sweep2(; dry_run::Bool=false)
    println(stderr, "Sweep 2 ((L, P, fiber) × N_phi={16, 64})"); flush(stderr)
    # Build the config list
    configs = [(fiber, L, P) for fiber in LR_SWEEP2_FIBERS,
                                  L in LR_SWEEP2_LS,
                                  P in LR_SWEEP2_PS] |> vec
    println(stderr, "  total configs = $(length(configs))"); flush(stderr)
    dry_run && return configs

    save_path = joinpath(LR_RESULTS_DIR, "sweep2_LP_fiber.jld2")
    mkpath(LR_RESULTS_DIR)

    results = Vector{Dict{String,Any}}(undef, 2 * length(configs))
    done = Threads.Atomic{Int}(0)
    save_lock = ReentrantLock()
    t0 = time()

    Threads.@threads for ci in eachindex(configs)
        (fiber_preset, L, P) = configs[ci]
        try
            pair = run_one_config_sweep2(; fiber_preset=fiber_preset,
                                          L_fiber=L, P_cont=P)
            results[2ci - 1] = pair[1]
            results[2ci]     = pair[2]
        catch e
            # Record a failure row rather than aborting the whole sweep
            err = Dict(
                "config" => Dict("fiber_preset"=>String(fiber_preset),
                                 "L_fiber"=>L, "P_cont"=>P),
                "error" => sprint(showerror, e),
            )
            results[2ci - 1] = err
            results[2ci]     = err
        end
        Threads.atomic_add!(done, 1)
        pct = 100 * done[] / length(configs)
        msg = @sprintf("  [%3.1f%%  %d/%d]  %s L=%.2fm P=%.3fW elapsed=%.1fmin",
                       pct, done[], length(configs),
                       String(fiber_preset), L, P, (time()-t0)/60)
        lock(save_lock) do
            println(stderr, msg); flush(stderr)
            # Snapshot incremental save — drop unfilled slots for safety.
            filled = [isassigned(results, i) for i in eachindex(results)]
            safe_results = results[filled]
            try
                JLD2.jldsave(save_path; results=safe_results, run_tag=LR_RUN_TAG,
                             configs=[Dict("fiber_preset"=>String(f), "L_fiber"=>L, "P_cont"=>P)
                                      for (f, L, P) in configs])
            catch e
                println(stderr, "  (snapshot save failed: $e)"); flush(stderr)
            end
        end
    end

    # Final full save
    JLD2.jldsave(save_path; results, run_tag=LR_RUN_TAG,
                 configs=[Dict("fiber_preset"=>String(f), "L_fiber"=>L, "P_cont"=>P)
                          for (f, L, P) in configs])
    println(stderr, "Sweep 2 complete. Saved $(save_path) ($(length(results)) rows)."); flush(stderr)

    # Rule 2: emit the 4-image standard set for every phi_opt produced.
    # Each row has its own (fiber, L, P) so rebuild per config.
    filled = [isassigned(results, i) for i in eachindex(results)]
    safe_results = results[filled]
    try
        finalize_standard_images(safe_results;
                                  subdir="sweep2_LP_fiber",
                                  rebuild_per_config=true)
    catch e
        @warn "finalize_standard_images failed" error=sprint(showerror, e)
    end
    return results
end

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

function main(args::Vector{String})
    do_sweep1 = "--sweep1" in args || "--both" in args || isempty(args)
    do_sweep2 = "--sweep2" in args || "--both" in args || isempty(args)
    dry_run = "--dry-run" in args

    println(stderr, "Session E sweep driver  tag=$LR_RUN_TAG  threads=$(Threads.nthreads())  dry_run=$dry_run")
    flush(stderr)

    if do_sweep1
        run_sweep1(; dry_run=dry_run)
    end
    if do_sweep2
        run_sweep2(; dry_run=dry_run)
    end
    println(stderr, "Session E sweep driver complete."); flush(stderr)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
