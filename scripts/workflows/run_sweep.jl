"""
Parameter sweep over (fiber length L, continuous-wave power P) — produces a
J_final heatmap per fiber type.

Runs the canonical optimization at each (L, P) grid point, saves a per-point
JLD2 + JSON pair, and aggregates into `sweep_results.jld2` + heatmap PNGs.

# Run
    julia --project=. -t auto scripts/canonical/run_sweep.jl

# Inputs
- Approved sweep config from `configs/sweeps/*.toml`.
- `scripts/lib/common.jl` fiber presets and setup helpers.

# Outputs
- `results/raman/sweeps/<fiber>/<L>_<P>/opt_result.jld2` — per-point payload.
- `results/raman/sweeps/<fiber>/<L>_<P>/opt_result.json` — per-point sidecar.
- `results/raman/sweeps/sweep_results.jld2` — aggregated summary table.
- `results/raman/sweeps/<fiber>_heatmap.png` — J_final heatmap.

# Runtime
~2–3 hours for the default approved sweep on the burst VM
(22 cores). Much longer on `claude-code-host` — burst VM strongly recommended.

# Docs
Docs: docs/guides/supported-workflows.md
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Printf
using Dates
using Random
using Logging

# Include shared infrastructure (include guards prevent double-loading)
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "lib", "canonical_runs.jl"))
include(joinpath(@__DIR__, "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "lib", "run_artifacts.jl"))
include(joinpath(@__DIR__, "..", "lib", "visualization.jl"))
ensure_deterministic_environment()

using JLD2
using JSON3
using Optim

# ─────────────────────────────────────────────────────────────────────────────
# Section 1: Constants (SW_ prefix avoids Julia const redefinition in REPL)
# ─────────────────────────────────────────────────────────────────────────────

const SW_RUN_TAG = Dates.format(now(), "yyyymmdd_HHMMss")

# ─────────────────────────────────────────────────────────────────────────────
# Section 3: Helper functions
# ─────────────────────────────────────────────────────────────────────────────

"""
    compute_photon_drift(result, uω0, fiber, sim) -> Float64

Re-propagate the optimized input field through the fiber and compute the
fractional change in photon number [percent]. Values >5% indicate the time
window is too small (energy absorbed by the attenuator at the window edge).

# Arguments
- `result`: Optim result from run_optimization
- `uω0`: input spectral field (Nt, M)
- `fiber`: fiber parameter dict from run_optimization
- `sim`: simulation parameter dict from run_optimization

# Returns
Photon number drift in percent: |N_out/N_in - 1| × 100
"""
function compute_photon_drift(result, uω0, fiber, sim)
    φ_after = reshape(result.minimizer, sim["Nt"], sim["M"])
    uω0_opt = @. uω0 * cis(φ_after)
    fiber_prop = deepcopy(fiber)
    fiber_prop["zsave"] = [fiber["L"]]
    sol = FiberLab.solve_disp_mmf(uω0_opt, fiber_prop, sim)
    uωf = sol["uω_z"][end, :, :]
    return photon_number_drift(uω0_opt, uωf, sim) * 100.0
end

# ─────────────────────────────────────────────────────────────────────────────
# Section 4: run_fiber_sweep — main sweep loop per fiber type
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_fiber_sweep(fiber_label, fiber_gamma, fiber_betas, L_vals, P_vals) -> Vector

Run Raman suppression optimization over every (L, P) grid point for one fiber type.
Each point:
  1. Computes SPM-aware time window via recommended_time_window()
  2. Computes Nt via nt_for_window()
  3. Calls run_optimization(do_plots=false, validate=false, max_iter=30)
  4. Computes photon number drift (D-01) and flags window_limited if >5%
  5. Records full scalar summary as a NamedTuple

Any ODE crash is caught and recorded with NaN J_after (sweep continues).

# Returns
Vector of NamedTuples with fields:
  L_m, P_cont_W, J_after, converged, iterations, window_limited,
  photon_drift_pct, N_sol, time_window_ps, Nt, grad_norm, result_file
"""
function run_fiber_sweep(fiber_spec, sweep_spec)
    sweep_results = []
    n_total = length(fiber_spec.lengths_m) * length(fiber_spec.powers_W)
    point_idx = 0

    for L in fiber_spec.lengths_m
        for P_cont in fiber_spec.powers_W
            point_idx += 1
            P_peak = peak_power_from_average_power(
                P_cont, sweep_spec.pulse_fwhm, sweep_spec.pulse_rep_rate)

            # Compute phi_NL to decide safety factor
            phi_NL = fiber_spec.gamma * P_peak * L
            safety = phi_NL > 20.0 ? 3.0 : 2.0

            # SPM-corrected time window
            time_window = recommended_time_window(L;
                beta2=abs(fiber_spec.betas[1]),
                gamma=fiber_spec.gamma,
                P_peak=P_peak,
                safety_factor=safety)
            Nt = max(nt_for_window(time_window), sweep_spec.Nt_floor)

            # Soliton number (does NOT depend on L — Pitfall 1)
            N_sol = compute_soliton_number(
                fiber_spec.gamma, P_peak, sweep_spec.pulse_fwhm_fs, fiber_spec.betas[1])

            # Per-point directory: results/raman/sweeps/<fiber>/<Lxm_PxW>/
            dir_path = joinpath(canonical_sweep_output_dir(sweep_spec), fiber_spec.slug,
                                @sprintf("L%gm_P%gW", L, P_cont))
            mkpath(dir_path)
            save_prefix = joinpath(dir_path, "opt")

            @info @sprintf("[%d/%d] %s L=%.1fm P=%.3fW (N=%.1f, φ_NL=%.1f, tw=%dps, Nt=%d)",
                point_idx, n_total, fiber_spec.name, L, P_cont, N_sol, phi_NL, time_window, Nt)

            try
                result, uω0, fiber_out, sim, band_mask, _ = run_optimization(
                    L_fiber        = L,
                    P_cont         = P_cont,
                    Nt             = Nt,
                    time_window    = Float64(time_window),
                    max_iter       = fiber_spec.max_iter,
                    validate       = false,
                    do_plots       = false,
                    fiber_name     = fiber_spec.name,
                    gamma_user     = fiber_spec.gamma,
                    betas_user     = fiber_spec.betas,
                    save_prefix    = save_prefix,
                    β_order        = fiber_spec.β_order,
                )

                # D-01: post-run photon number drift check
                drift_pct = compute_photon_drift(result, uω0, fiber_out, sim)
                window_limited = drift_pct > 5.0

                converged  = Optim.converged(result)
                iterations = Optim.iterations(result)
                # Read back the persisted canonical payload so sweep summaries are
                # derived from the same saved artifact other workflows consume.
                saved_run = canonical_run_summary(save_prefix * "_result.jld2")
                J_after   = saved_run.J_after
                grad_norm = saved_run.grad_norm

                J_dB = FiberLab.lin_to_dB(J_after)
                quality = suppression_quality_label(J_after)
                @info @sprintf("    → J_after=%.1f dB [%s], converged=%s, drift=%.1f%%, wlim=%s",
                    J_dB, quality, converged, drift_pct, window_limited)

                push!(sweep_results, (
                    L_m             = L,
                    P_cont_W        = P_cont,
                    J_after         = J_after,
                    converged       = converged,
                    iterations      = iterations,
                    window_limited  = window_limited,
                    photon_drift_pct= drift_pct,
                    N_sol           = N_sol,
                    time_window_ps  = Float64(time_window),
                    Nt              = Nt,
                    grad_norm       = Float64(Optim.g_residual(result)),
                    result_file     = save_prefix * "_result.jld2",
                ))

            catch e
                @warn "Sweep point FAILED" L=L P=P_cont exception=e
                push!(sweep_results, (
                    L_m             = L,
                    P_cont_W        = P_cont,
                    J_after         = NaN,
                    converged       = false,
                    iterations      = 0,
                    window_limited  = true,
                    photon_drift_pct= NaN,
                    N_sol           = N_sol,
                    time_window_ps  = Float64(time_window),
                    Nt              = Nt,
                    grad_norm       = NaN,
                    result_file     = "",
                ))
            end

            GC.gc()
        end
    end

    return sweep_results
end

# ─────────────────────────────────────────────────────────────────────────────
# Section 5: save_sweep_aggregate — aggregate JLD2 save
# ─────────────────────────────────────────────────────────────────────────────

"""
    save_sweep_aggregate(sweep_results, fiber_label)

Build grid matrices from the sweep results vector and save an aggregate JLD2
to results/raman/sweeps/sweep_results_<fiber_label>.jld2.

Matrices are indexed [i_L, j_P] where i_L is the L-axis index and j_P is
the P-axis index, matching the heatmap coordinate convention.
"""
function save_sweep_aggregate(sweep_results, fiber_label; output_dir::AbstractString)
    L_vals = sort(unique([r.L_m for r in sweep_results]))
    P_vals = sort(unique([r.P_cont_W for r in sweep_results]))
    nL, nP = length(L_vals), length(P_vals)

    J_after_grid       = fill(NaN,   nL, nP)
    N_sol_grid         = fill(NaN,   nL, nP)
    converged_grid     = fill(false, nL, nP)
    window_limited_grid= fill(false, nL, nP)
    drift_pct_grid     = fill(NaN,   nL, nP)
    time_window_grid   = fill(NaN,   nL, nP)
    Nt_grid            = fill(0,     nL, nP)

    for r in sweep_results
        i = findfirst(==(r.L_m), L_vals)
        j = findfirst(==(r.P_cont_W), P_vals)
        J_after_grid[i, j]        = r.J_after
        N_sol_grid[i, j]          = r.N_sol
        converged_grid[i, j]      = r.converged
        window_limited_grid[i, j] = r.window_limited
        drift_pct_grid[i, j]      = r.photon_drift_pct
        time_window_grid[i, j]    = r.time_window_ps
        Nt_grid[i, j]             = r.Nt
    end

    mkpath(output_dir)
    out_path = joinpath(output_dir,
        "sweep_results_$(lowercase(replace(fiber_label, "-" => ""))).jld2")
    jldsave(out_path;
        fiber_label        = fiber_label,
        run_tag            = SW_RUN_TAG,
        L_vals             = L_vals,
        P_vals             = P_vals,
        J_after_grid       = J_after_grid,
        N_sol_grid         = N_sol_grid,
        converged_grid     = converged_grid,
        window_limited_grid= window_limited_grid,
        drift_pct_grid     = drift_pct_grid,
        time_window_grid   = time_window_grid,
        Nt_grid            = Nt_grid,
        sweep_results      = sweep_results,
    )
    @info "Saved aggregate sweep results to $out_path"
    return out_path
end

# ─────────────────────────────────────────────────────────────────────────────
# Section 6: run_multistart — 10 starts on SMF-28 L=2m P=0.30W (D-04)
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_multistart(; n_starts=10, max_iter=100) -> Vector

Multi-start robustness analysis: 10 independent L-BFGS runs on
SMF-28 L=2m P=0.30W (N=3.1, the config that didn't converge in Phase 6).

Initial phases (per D-04, Random.seed!(42) for reproducibility):
  - Start 1: φ₀ = zeros (zero-phase baseline)
  - Starts 2-4: φ₀ ~ N(0, 0.1²) (small perturbations)
  - Starts 5-7: φ₀ ~ N(0, 0.5²) (moderate random)
  - Starts 8-10: φ₀ ~ N(0, 1.0²) (large random, σ=1.0 rad)

Each start saves its own JLD2 to results/raman/sweeps/multistart/start_NN/opt_result.jld2.
Aggregate saved to results/raman/sweeps/multistart_L2m_P030W.jld2.

# Returns
Vector of NamedTuples with fields:
  start_idx, sigma, J_final, converged, iterations, result_file
"""
function run_multistart(sweep_spec)
    multistart_spec = sweep_spec.multistart
    multistart_spec.enabled || return NamedTuple[]

    n_starts = multistart_spec.n_starts
    max_iter = multistart_spec.max_iter
    L_fiber  = multistart_spec.L_fiber
    P_cont   = multistart_spec.P_cont
    P_peak   = peak_power_from_average_power(
        P_cont, sweep_spec.pulse_fwhm, sweep_spec.pulse_rep_rate)

    # SPM-corrected time window for this config (phi_NL ~ 39 → safety_factor=3)
    time_window = recommended_time_window(L_fiber;
        beta2       = abs(multistart_spec.betas[1]),
        gamma       = multistart_spec.gamma,
        P_peak      = P_peak,
        safety_factor = 3.0)
    Nt = max(nt_for_window(time_window), sweep_spec.Nt_floor)

    @info @sprintf("Multi-start config: SMF-28 L=%.1fm P=%.2fW, tw=%dps, Nt=%d",
        L_fiber, P_cont, time_window, Nt)

    # Reproducible initial phase generation (D-04)
    Random.seed!(42)
    sigmas = [0.1, 0.5, 1.0]
    phi0_list = Vector{Matrix{Float64}}(undef, n_starts)
    phi0_list[1] = zeros(Nt, 1)          # Start 1: zero phase
    k = 2
    for σ in sigmas
        for _ in 1:3
            if k <= n_starts
                phi0_list[k] = σ .* randn(Nt, 1)
                k += 1
            end
        end
    end
    # Fill any remaining starts with sigma=1.0 random
    while k <= n_starts
        phi0_list[k] = 1.0 .* randn(Nt, 1)
        k += 1
    end

    sigma_labels = vcat([0.0], repeat(sigmas, inner=3))
    if length(sigma_labels) < n_starts
        append!(sigma_labels, fill(1.0, n_starts - length(sigma_labels)))
    end

    ms_results = []
    for i in 1:n_starts
        sigma_i = sigma_labels[i]
        dir_path = joinpath(canonical_sweep_output_dir(sweep_spec), "multistart",
            @sprintf("start_%02d", i))
        mkpath(dir_path)
        save_prefix = joinpath(dir_path, "opt")

        @info @sprintf("[Multi-start %d/%d] σ=%.1f, tw=%dps, Nt=%d",
            i, n_starts, sigma_i, time_window, Nt)

        try
            result, uω0, fiber_out, sim, band_mask, _ = run_optimization(
                L_fiber     = L_fiber,
                P_cont      = P_cont,
                Nt          = Nt,
                time_window = Float64(time_window),
                max_iter    = max_iter,
                validate    = false,
                do_plots    = false,
                fiber_name  = multistart_spec.fiber_name,
                gamma_user  = multistart_spec.gamma,
                betas_user  = multistart_spec.betas,
                save_prefix = save_prefix,
                β_order     = multistart_spec.β_order,
                φ0          = phi0_list[i],
            )

            converged  = Optim.converged(result)
            iterations = Optim.iterations(result)
            saved_run = canonical_run_summary(save_prefix * "_result.jld2")
            J_final   = saved_run.J_after

            @info @sprintf("    → J_final=%.1f dB, converged=%s, iters=%d",
                FiberLab.lin_to_dB(J_final), converged, iterations)

            push!(ms_results, (
                start_idx  = i,
                sigma      = sigma_i,
                J_final    = J_final,
                converged  = converged,
                iterations = iterations,
                result_file= save_prefix * "_result.jld2",
            ))

        catch e
            @warn "Multi-start $i FAILED" exception=e
            push!(ms_results, (
                start_idx  = i,
                sigma      = sigma_i,
                J_final    = NaN,
                converged  = false,
                iterations = 0,
                result_file= "",
            ))
        end

        GC.gc()
    end

    # Save aggregate
    agg_path = joinpath(canonical_sweep_output_dir(sweep_spec), "multistart_L2m_P030W.jld2")
    jldsave(agg_path;
        fiber_name    = multistart_spec.fiber_name,
        L_m           = L_fiber,
        P_cont_W      = P_cont,
        run_tag       = SW_RUN_TAG,
        time_window_ps= Float64(time_window),
        Nt            = Nt,
        ms_results    = ms_results,
        Random_seed   = 42,
        n_starts      = n_starts,
        max_iter      = max_iter,
    )
    @info "Saved multi-start aggregate to $agg_path"

    return ms_results
end

function _print_sweep_summary(label, results)
    n_total = length(results)
    n_conv  = count(r -> r.converged, results)
    n_wlim  = count(r -> r.window_limited, results)
    valid   = filter(r -> !isnan(r.J_after), results)
    n_exc   = count(r -> suppression_quality_label(r.J_after) == "excellent", valid)
    n_good  = count(r -> suppression_quality_label(r.J_after) in ("excellent", "good"), valid)
    n_poor  = count(r -> suppression_quality_label(r.J_after) == "poor", valid)
    best_dB = isempty(valid) ? NaN : minimum(r -> FiberLab.lin_to_dB(r.J_after), valid)
    worst_dB= isempty(valid) ? NaN : maximum(r -> FiberLab.lin_to_dB(r.J_after), valid)

    @info @sprintf("""
    ┌─── %s (%d points) ────────────────────────────┐
    │  Converged:    %2d/%2d (formal gradient criterion)   │
    │  Suppression:  %2d/%2d ≤ -30 dB  (%d excellent)      │
    │  Poor (>-20dB): %2d/%2d                              │
    │  Window-limited: %2d/%2d                             │
    │  Best: %.1f dB   Worst: %.1f dB                     │
    └───────────────────────────────────────────────────┘""",
        label, n_total,
        n_conv, n_total,
        n_good, n_total, n_exc,
        n_poor, n_total,
        n_wlim, n_total,
        best_dB, worst_dB)
end

function _print_multistart_summary(ms_results)
    isempty(ms_results) && return nothing
    n_ms_converged = count(r -> r.converged, ms_results)
    ms_valid = filter(r -> !isnan(r.J_final), ms_results)
    ms_good  = count(r -> FiberLab.lin_to_dB(r.J_final) < -30, ms_valid)
    @info @sprintf("""
    ┌─── Multi-start (%d starts) ───────────────────────┐
    │  Converged: %2d/%2d   Suppression ≤-30dB: %2d/%2d     │
    └───────────────────────────────────────────────────┘""",
        length(ms_results),
        n_ms_converged, length(ms_results),
        ms_good, length(ms_valid))
    return nothing
end

function _print_approved_sweep_configs()
    println("Approved sweep configs:")
    for id in approved_sweep_config_ids()
        spec = load_canonical_sweep_config(id)
        println("  ", spec.id, "  —  ", spec.description)
    end
end

function run_sweep_main(args=ARGS)
    if length(args) > 1
        error("usage: scripts/canonical/run_sweep.jl [sweep-config-id-or-path | --list]")
    end

    if !isempty(args) && args[1] == "--list"
        _print_approved_sweep_configs()
        return nothing
    end

    config_spec = isempty(args) ? DEFAULT_CANONICAL_SWEEP_ID : args[1]
    sweep_spec = load_canonical_sweep_config(config_spec)
    sweep_dir = canonical_sweep_output_dir(sweep_spec)
    images_dir = canonical_sweep_images_dir(sweep_spec)
    cp(sweep_spec.config_path, joinpath(sweep_dir, "sweep_config.toml"); force=true)

    @info @sprintf("""
    ╔═══════════════════════════════════════════════════════╗
    ║  Phase 7: Parameter Sweep                            ║
    ║  Run tag: %s                                ║
    ╚═══════════════════════════════════════════════════════╝""",
        SW_RUN_TAG)
    @info "Sweep config loaded" config=sweep_spec.id config_path=sweep_spec.config_path

    per_fiber_results = Dict{String,Any}()
    for fiber_spec in sweep_spec.fibers
        n_points = length(fiber_spec.lengths_m) * length(fiber_spec.powers_W)
        @info "=== $(fiber_spec.name) Sweep ($(n_points) points) ==="
        results = run_fiber_sweep(fiber_spec, sweep_spec)
        save_sweep_aggregate(results, fiber_spec.name; output_dir=sweep_dir)
        per_fiber_results[fiber_spec.name] = results
    end

    ms_results = run_multistart(sweep_spec)

    @info "=== Generating Heatmaps and Histogram ==="
    for fiber_spec in sweep_spec.fibers
        results = per_fiber_results[fiber_spec.name]
        plot_sweep_heatmap(results, fiber_spec.name;
            save_path=joinpath(images_dir, "sweep_heatmap_$(fiber_spec.slug).png"))
    end
    if !isempty(ms_results)
        plot_multistart_histogram(ms_results;
            save_path=joinpath(images_dir, "multistart_histogram.png"))
    end
    PyPlot.close("all")

    for fiber_spec in sweep_spec.fibers
        _print_sweep_summary(fiber_spec.name, per_fiber_results[fiber_spec.name])
    end
    _print_multistart_summary(ms_results)

    return (
        sweep_spec = sweep_spec,
        per_fiber_results = per_fiber_results,
        multistart_results = ms_results,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_sweep_main(ARGS)
end
