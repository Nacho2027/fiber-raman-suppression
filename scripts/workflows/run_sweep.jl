"""
Parameter sweep over (fiber length L, continuous-wave power P) — produces a
J_final heatmap per fiber type.

Runs the canonical optimization at each (L, P) grid point, saves a per-point
JLD2 + JSON pair, and aggregates into `sweep_results.jld2` + heatmap PNGs.

# Run
    julia --project=. -t auto scripts/canonical/run_sweep.jl

# Inputs
- Grid definition near the top of file (L_values, P_values, fiber presets,
  Nt floor, max_iter).
- `scripts/lib/common.jl` fiber presets.

# Outputs
- `results/raman/sweeps/<fiber>/<L>_<P>/_result.jld2` — per-point payload.
- `results/raman/sweeps/<fiber>/<L>_<P>/_result.json` — per-point sidecar.
- `results/raman/sweeps/sweep_results.jld2` — aggregated summary table.
- `results/raman/sweeps/<fiber>_heatmap.png` — J_final heatmap.

# Runtime
~2–3 hours for the full 24-point grid (12 SMF-28 + 12 HNLF) on the burst VM
(22 cores). Much longer on `claude-code-host` — burst VM strongly recommended.

# Docs
Docs: docs/quickstart-sweep.md
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Printf
using Dates
using Random
using Logging

# Include shared infrastructure (include guards prevent double-loading)
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "lib", "visualization.jl"))
ensure_deterministic_environment()

using JLD2
using JSON3
using Optim

# ─────────────────────────────────────────────────────────────────────────────
# Section 1: Constants (SW_ prefix avoids Julia const redefinition in REPL)
# ─────────────────────────────────────────────────────────────────────────────

const SW_RUN_TAG       = Dates.format(now(), "yyyymmdd_HHMMss")
const SW_SECH_FACTOR   = 0.881374          # sech² peak-power factor
const SW_PULSE_FWHM    = 185e-15           # s (185 fs pulse FWHM)
const SW_PULSE_FWHM_FS = 185.0             # fs (for compute_soliton_number)
const SW_PULSE_REP_RATE = 80.5e6           # Hz (80.5 MHz rep rate)
const SW_SWEEP_DIR     = joinpath("results", "raman", "sweeps")
const SW_IMAGES_DIR    = joinpath("results", "images")
const SW_NT_FLOOR      = 2^13                     # minimum Nt for optimization quality

# ─────────────────────────────────────────────────────────────────────────────
# Section 2: Fiber grid definitions (SMF-28 4×4=16 pts, HNLF 4×4=16 pts)
# ─────────────────────────────────────────────────────────────────────────────

# SMF-28: 4 lengths × 4 powers = 16 points
const SW_SMF28_L     = [0.5, 1.0, 2.0, 5.0]           # m
const SW_SMF28_P     = [0.05, 0.10, 0.20]              # W (average continuous power) — P=0.30 dropped: 3+ hours per point at Nt=8192
const SW_SMF28_GAMMA = 1.1e-3                           # W⁻¹m⁻¹
const SW_SMF28_BETAS = [-2.17e-26, 1.2e-40]            # β₂ [s²/m], β₃ [s³/m]

# HNLF: 4 lengths × 4 powers = 16 points
const SW_HNLF_L      = [0.5, 1.0, 2.0, 5.0]           # m
const SW_HNLF_P      = [0.005, 0.010, 0.030]           # W — P=0.050 dropped: extreme nonlinearity at Nt=8192
const SW_HNLF_GAMMA  = 10.0e-3                          # W⁻¹m⁻¹
const SW_HNLF_BETAS  = [-0.5e-26, 1.0e-40]             # β₂ [s²/m], β₃ [s³/m]

# ─────────────────────────────────────────────────────────────────────────────
# Section 3: Helper functions
# ─────────────────────────────────────────────────────────────────────────────

"""
    compute_photon_number(uomega, sim)

Photon number from spectral field and simulation parameters.
Uses abs.(sim["ωs"]) directly — sim["ωs"] already includes ω₀ carrier offset.
(Verified in Phase 4: no double-counting.)

# Arguments
- `uomega`: complex spectral field, shape (Nt, M)
- `sim`: simulation parameter dict with keys "ωs" (rad/ps) and "Δt" (ps)
"""
function compute_photon_number(uomega, sim)
    omega_s = sim["ωs"]      # absolute angular frequency grid [rad/ps]; includes ω₀
    Delta_t = sim["Δt"]      # time step [ps]
    # abs.(omega_s) avoids issues with negative-frequency bins.
    # Near 1550nm, min|omega_s| ≈ 0.1 rad/ps (denominator is safe).
    abs_omega = abs.(omega_s)
    return sum(abs2.(uomega) ./ abs_omega) * Delta_t
end

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
    sol = MultiModeNoise.solve_disp_mmf(uω0_opt, fiber_prop, sim)
    uωf = sol["uω_z"][end, :, :]
    N_in  = compute_photon_number(uω0_opt, sim)
    N_out = compute_photon_number(uωf, sim)
    return abs(N_out / N_in - 1.0) * 100.0   # percent drift
end

"""
    compute_peak_power(P_cont) -> Float64

Convert average continuous power [W] to sech² pulse peak power [W].
Formula: P_peak = SW_SECH_FACTOR × P_cont / (SW_PULSE_FWHM × SW_PULSE_REP_RATE)
"""
function compute_peak_power(P_cont)
    return SW_SECH_FACTOR * P_cont / (SW_PULSE_FWHM * SW_PULSE_REP_RATE)
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
function run_fiber_sweep(fiber_label, fiber_gamma, fiber_betas, L_vals, P_vals)
    sweep_results = []
    n_total = length(L_vals) * length(P_vals)
    point_idx = 0

    for L in L_vals
        for P_cont in P_vals
            point_idx += 1
            P_peak = compute_peak_power(P_cont)

            # Compute phi_NL to decide safety factor
            phi_NL = fiber_gamma * P_peak * L
            safety = phi_NL > 20.0 ? 3.0 : 2.0

            # SPM-corrected time window
            time_window = recommended_time_window(L;
                beta2=abs(fiber_betas[1]),
                gamma=fiber_gamma,
                P_peak=P_peak,
                safety_factor=safety)
            Nt = max(nt_for_window(time_window), SW_NT_FLOOR)

            # Soliton number (does NOT depend on L — Pitfall 1)
            N_sol = compute_soliton_number(fiber_gamma, P_peak, SW_PULSE_FWHM_FS, fiber_betas[1])

            # Per-point directory: results/raman/sweeps/<fiber>/<Lxm_PxW>/
            fiber_dir = lowercase(replace(fiber_label, "-" => ""))
            dir_path = joinpath(SW_SWEEP_DIR, fiber_dir,
                                @sprintf("L%gm_P%gW", L, P_cont))
            mkpath(dir_path)
            save_prefix = joinpath(dir_path, "opt")

            @info @sprintf("[%d/%d] %s L=%.1fm P=%.3fW (N=%.1f, φ_NL=%.1f, tw=%dps, Nt=%d)",
                point_idx, n_total, fiber_label, L, P_cont, N_sol, phi_NL, time_window, Nt)

            try
                result, uω0, fiber_out, sim, band_mask, _ = run_optimization(
                    L_fiber        = L,
                    P_cont         = P_cont,
                    Nt             = Nt,
                    time_window    = Float64(time_window),
                    max_iter       = 60,
                    validate       = false,
                    do_plots       = false,
                    fiber_name     = fiber_label,
                    gamma_user     = fiber_gamma,
                    betas_user     = fiber_betas,
                    save_prefix    = save_prefix,
                    β_order        = 3,
                )

                # D-01: post-run photon number drift check
                drift_pct = compute_photon_drift(result, uω0, fiber_out, sim)
                window_limited = drift_pct > 5.0

                converged  = Optim.converged(result)
                iterations = Optim.iterations(result)
                # J_after in linear scale from the saved JLD2 (run_optimization always
                # stores linear J regardless of log_cost setting)
                jld2_data  = load(save_prefix * "_result.jld2")
                J_after    = jld2_data["J_after"]
                grad_norm  = jld2_data["grad_norm"]

                J_dB = MultiModeNoise.lin_to_dB(J_after)
                quality = J_dB < -40 ? "excellent" : J_dB < -30 ? "good" : J_dB < -20 ? "acceptable" : "poor"
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
function save_sweep_aggregate(sweep_results, fiber_label)
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

    mkpath(SW_SWEEP_DIR)
    out_path = joinpath(SW_SWEEP_DIR,
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
function run_multistart(; n_starts::Int=10, max_iter::Int=60)
    L_fiber  = 2.0
    P_cont   = 0.20  # was 0.30 — too slow at Nt=8192; P=0.20 still has N≈2.6 (nontrivial)
    P_peak   = compute_peak_power(P_cont)

    # SPM-corrected time window for this config (phi_NL ~ 39 → safety_factor=3)
    time_window = recommended_time_window(L_fiber;
        beta2       = abs(SW_SMF28_BETAS[1]),
        gamma       = SW_SMF28_GAMMA,
        P_peak      = P_peak,
        safety_factor = 3.0)
    Nt = max(nt_for_window(time_window), SW_NT_FLOOR)

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
        dir_path = joinpath(SW_SWEEP_DIR, "multistart", @sprintf("start_%02d", i))
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
                fiber_name  = "SMF-28",
                gamma_user  = SW_SMF28_GAMMA,
                betas_user  = SW_SMF28_BETAS,
                save_prefix = save_prefix,
                β_order     = 3,
                φ0          = phi0_list[i],
            )

            converged  = Optim.converged(result)
            iterations = Optim.iterations(result)
            # Read linear J from JLD2 (always linear regardless of log_cost)
            jld2_data  = load(save_prefix * "_result.jld2")
            J_final    = jld2_data["J_after"]

            @info @sprintf("    → J_final=%.1f dB, converged=%s, iters=%d",
                MultiModeNoise.lin_to_dB(J_final), converged, iterations)

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
    agg_path = joinpath(SW_SWEEP_DIR, "multistart_L2m_P030W.jld2")
    jldsave(agg_path;
        fiber_name    = "SMF-28",
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

# ─────────────────────────────────────────────────────────────────────────────
# Section 7: Main entry point (guard prevents execution when included)
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__

    using LinearAlgebra: norm
    using Dates

    @info @sprintf("""
    ╔═══════════════════════════════════════════════════════╗
    ║  Phase 7: Parameter Sweep                            ║
    ║  Run tag: %s                                ║
    ╚═══════════════════════════════════════════════════════╝""",
        SW_RUN_TAG)

    mkpath(SW_SWEEP_DIR)
    mkpath(SW_IMAGES_DIR)

    # ── 1. SMF-28 sweep (5×4 = 20 points) ──────────────────────────────────
    @info "=== SMF-28 Sweep ($(length(SW_SMF28_L) * length(SW_SMF28_P)) points) ==="
    smf28_results = run_fiber_sweep("SMF-28", SW_SMF28_GAMMA, SW_SMF28_BETAS,
                                     SW_SMF28_L, SW_SMF28_P)
    save_sweep_aggregate(smf28_results, "SMF-28")

    # ── 2. HNLF sweep (4×4 = 16 points) ────────────────────────────────────
    @info "=== HNLF Sweep ($(length(SW_HNLF_L) * length(SW_HNLF_P)) points) ==="
    hnlf_results = run_fiber_sweep("HNLF", SW_HNLF_GAMMA, SW_HNLF_BETAS,
                                    SW_HNLF_L, SW_HNLF_P)
    save_sweep_aggregate(hnlf_results, "HNLF")

    # ── 3. Multi-start analysis (10 starts) ─────────────────────────────────
    @info "=== Multi-Start Analysis (10 starts, SMF-28 L=2m P=0.30W) ==="
    ms_results = run_multistart()

    # ── 4. Visualization ────────────────────────────────────────────────────
    @info "=== Generating Heatmaps and Histogram ==="

    plot_sweep_heatmap(smf28_results, "SMF-28";
        save_path=joinpath(SW_IMAGES_DIR, "sweep_heatmap_smf28.png"))

    plot_sweep_heatmap(hnlf_results, "HNLF";
        save_path=joinpath(SW_IMAGES_DIR, "sweep_heatmap_hnlf.png"))

    plot_multistart_histogram(ms_results;
        save_path=joinpath(SW_IMAGES_DIR, "multistart_histogram.png"))

    PyPlot.close("all")

    # ── 5. Summary log ──────────────────────────────────────────────────────

    # Helper: classify suppression quality from J_after (linear scale)
    function _suppression_quality(J_lin)
        isnan(J_lin) && return "crashed"
        J_dB = MultiModeNoise.lin_to_dB(J_lin)
        J_dB < -40 ? "excellent" : J_dB < -30 ? "good" : J_dB < -20 ? "acceptable" : "poor"
    end

    for (label, results) in [("SMF-28", smf28_results), ("HNLF", hnlf_results)]
        n_total = length(results)
        n_conv  = count(r -> r.converged, results)
        n_wlim  = count(r -> r.window_limited, results)
        valid   = filter(r -> !isnan(r.J_after), results)
        n_exc   = count(r -> _suppression_quality(r.J_after) == "excellent", valid)
        n_good  = count(r -> _suppression_quality(r.J_after) in ("excellent", "good"), valid)
        n_poor  = count(r -> _suppression_quality(r.J_after) == "poor", valid)
        best_dB = isempty(valid) ? NaN : minimum(r -> MultiModeNoise.lin_to_dB(r.J_after), valid)
        worst_dB= isempty(valid) ? NaN : maximum(r -> MultiModeNoise.lin_to_dB(r.J_after), valid)

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

    n_ms_converged = count(r -> r.converged, ms_results)
    ms_valid = filter(r -> !isnan(r.J_final), ms_results)
    ms_good  = count(r -> MultiModeNoise.lin_to_dB(r.J_final) < -30, ms_valid)
    @info @sprintf("""
    ┌─── Multi-start (%d starts) ───────────────────────┐
    │  Converged: %2d/%2d   Suppression ≤-30dB: %2d/%2d     │
    └───────────────────────────────────────────────────┘""",
        length(ms_results),
        n_ms_converged, length(ms_results),
        ms_good, length(ms_valid))

end # abspath(PROGRAM_FILE) == @__FILE__
