"""
Long-Fiber Propagation Reach — Phase 12.1

Characterizes the finite suppression reach of spectral phase shaping by
propagating existing phi_opt from short optimizations (L=0.5m and L=2m) through
long fibers (L=10m and L=30m) with 100 z-save points.

Key question: at 10x-60x the optimization length, does phi_opt still provide
any benefit over flat phase?

Configs tested:
  - SMF-28 (P=0.2W): phi_opt from L=0.5m propagated to 10m and 30m
  - SMF-28 (P=0.2W): best multi-start phi_opt from L=2m propagated to 10m and 30m
  - HNLF   (P=0.01W): phi_opt from L=1m propagated to 10m and 30m

Figures produced (all -> results/images/):
  physics_12_01_long_fiber_Jz.png          — J(z) shaped vs flat, all configs
  physics_12_02_spectral_evolution_long.png — Spectral heatmaps, SMF-28 L=30m
  physics_12_03_shaped_vs_flat_benefit.png  — Shaping benefit (dB) vs distance

Data saved to results/raman/phase12/ (JLD2 with J_z and metadata per config/condition).

Critical implementation notes:
  - NEVER let auto-sizing run at L=30m SMF-28 — always pass Nt=65536, time_window=500
  - phi_opt interpolation uses physical frequency axis via Interpolations.jl
  - deepcopy(fiber) before setting fiber["zsave"]
  - beta_order=3 always with fiber presets (2 betas: beta2 + beta3)
  - Use Interpolations.linear_interpolation (fully qualified) to avoid Optim.Flat() ambiguity
  - @sprintf single-literal format strings only (Julia 1.12 macroexpand issue)

Anti-patterns to avoid:
  - Never copy phi_opt by index when grids differ — interpolate in physical freq space
  - Never hold shaped + unshaped z-save arrays simultaneously — save and release each
  - Never call setup_raman_problem without explicit Nt/time_window for L>=10m SMF-28
"""

try using Revise catch end
using Printf
using LinearAlgebra
using FFTW
using Logging
using Statistics
using Dates
using Interpolations
ENV["MPLBACKEND"] = "Agg"
using PyPlot
using JLD2

include("common.jl")
include("visualization.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Include guard + constants (PR_ prefix per D-15)
# ─────────────────────────────────────────────────────────────────────────────

if !(@isdefined _PR_SCRIPT_LOADED)
const _PR_SCRIPT_LOADED = true

const PR_N_ZSAVE = 100                              # D-01: 100 z-save points
const PR_RESULTS_DIR = joinpath("results", "raman", "phase12")
const PR_FIGURE_DIR  = joinpath("results", "images")

# Fiber betas lookup (betas field is empty in sweep JLD2 files; recover by fiber name)
const PR_FIBER_BETAS = Dict(
    "SMF-28" => [-2.17e-26, 1.2e-40],
    "HNLF"   => [-0.5e-26, 1.0e-40],
)
const PR_REP_RATE    = 80.5e6
const PR_SECH2_FACTOR = 0.881374

# ─────────────────────────────────────────────────────────────────────────────
# Long-fiber propagation configurations (D-01, D-02, D-04)
# ─────────────────────────────────────────────────────────────────────────────

const PR_LONG_CONFIGS = [
    # SMF-28: phi_opt from L=0.5m (no multi-start available for 0.5m)
    (
        source_dir    = "smf28",
        source_config = "L0.5m_P0.2W",
        label         = "SMF-28 phi@0.5m",
        preset        = :SMF28,
        fiber_type    = "SMF-28",
        L_targets     = [10.0, 30.0],
        P_cont        = 0.2,
        use_multistart = false,
    ),
    # SMF-28: best multi-start phi_opt from L=2m (D-04)
    (
        source_dir    = "smf28",
        source_config = "L2m_P0.2W",
        label         = "SMF-28 phi@2m (best multi-start)",
        preset        = :SMF28,
        fiber_type    = "SMF-28",
        L_targets     = [10.0, 30.0],
        P_cont        = 0.2,
        use_multistart = true,
    ),
    # HNLF: phi_opt from L=1m propagated to long distances (D-02)
    (
        source_dir    = "hnlf",
        source_config = "L1m_P0.01W",
        label         = "HNLF phi@1m",
        preset        = :HNLF,
        fiber_type    = "HNLF",
        L_targets     = [10.0, 30.0],
        P_cont        = 0.01,
        use_multistart = false,
    ),
]

end  # include guard

# ─────────────────────────────────────────────────────────────────────────────
# phi_opt interpolation: stored grid → target grid via physical frequency axis
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_interpolate_phi_to_new_grid(phi_stored, Nt_old, tw_old_ps, Nt_new, tw_new_ps)

Interpolate stored phi_opt from its original frequency grid to a new frequency grid.

Critical: phi_opt index i corresponds to physical frequency fftfreq(Nt, 1/dt)[i].
When switching grids (e.g., Nt=8192/tw=5ps → Nt=65536/tw=500ps) the physical
frequencies are different. Never copy by index — always map by physical frequency.

Outside the stored frequency range, phi is set to zero (optimizer had no spectral
information there — the pulse spectrum is negligible outside ±few THz from carrier).

# Arguments
- `phi_stored`: Stored phi_opt, Vector or Matrix{Float64} of length Nt_old
- `Nt_old`: Grid size of stored phi
- `tw_old_ps`: Time window of stored grid (picoseconds)
- `Nt_new`: Target grid size
- `tw_new_ps`: Target time window (picoseconds)

# Returns
- `phi_new`: Matrix{Float64}(Nt_new, 1) in FFT order for the new grid
"""
function pr_interpolate_phi_to_new_grid(phi_stored, Nt_old, tw_old_ps, Nt_new, tw_new_ps)
    # Build physical frequency axes (Hz) in FFT order
    dt_old = tw_old_ps * 1e-12 / Nt_old
    dt_new = tw_new_ps * 1e-12 / Nt_new
    freqs_old = fftfreq(Nt_old, 1.0 / dt_old)   # Hz, FFT order
    freqs_new = fftfreq(Nt_new, 1.0 / dt_new)   # Hz, FFT order

    phi_1d = vec(phi_stored)

    # Sort by frequency for monotone axis (required by Interpolations.jl)
    sort_idx = sortperm(freqs_old)
    freqs_sorted = freqs_old[sort_idx]
    phi_sorted   = phi_1d[sort_idx]

    # Build interpolant; extrapolation_bc=0.0 sets phi=0 outside stored range
    # (outside pulse bandwidth, phi_opt has no physical meaning — zero is correct)
    # Fully qualify to avoid any ambiguity with Optim.Flat()
    itp = Interpolations.linear_interpolation(freqs_sorted, phi_sorted;
        extrapolation_bc = 0.0)

    phi_new = Matrix{Float64}(undef, Nt_new, 1)
    f_lo = freqs_sorted[1]
    f_hi = freqs_sorted[end]
    for i in 1:Nt_new
        f = freqs_new[i]
        phi_new[i, 1] = (f_lo <= f <= f_hi) ? itp(f) : 0.0
    end
    return phi_new
end

# ─────────────────────────────────────────────────────────────────────────────
# Load best multi-start phi_opt (D-04)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_load_best_multistart_phi(; n_starts=10)

Load all 10 multi-start phi_opt profiles from results/raman/sweeps/multistart/
and return the one with the lowest J_after value (best Raman suppression).

Falls back to single sweep result at L2m_P0.2W if multi-start files not found.

# Returns
Named tuple: (phi_opt, Nt, time_window_ps, P_cont, L, J_after, source_path)
"""
function pr_load_best_multistart_phi(; n_starts=10)
    base_dir = joinpath("results", "raman", "sweeps", "multistart")
    @assert isdir(base_dir) "Multi-start directory not found: $base_dir"

    best_J    = Inf
    best_data = nothing
    best_path = ""

    for i in 1:n_starts
        start_dir = joinpath(base_dir, @sprintf("start_%02d", i))
        jld2_path = joinpath(start_dir, "opt_result.jld2")
        if !isfile(jld2_path)
            @warn @sprintf("Multi-start file missing: %s", jld2_path)
            continue
        end
        d = JLD2.load(jld2_path)
        J = Float64(d["J_after"])
        if J < best_J
            best_J    = J
            best_data = d
            best_path = jld2_path
        end
    end

    if isnothing(best_data)
        # Fallback to single sweep result
        fallback = joinpath("results", "raman", "sweeps", "smf28", "L2m_P0.2W", "opt_result.jld2")
        @warn @sprintf("No multi-start data found; falling back to %s", fallback)
        best_data = JLD2.load(fallback)
        best_path = fallback
    end

    @info @sprintf("Best multi-start: %s", best_path)
    @info @sprintf("  J_after = %.2e (%.2f dB)", best_J, 10*log10(max(best_J, 1e-20)))

    return (
        phi_opt       = Matrix{Float64}(best_data["phi_opt"]),
        Nt            = Int(best_data["Nt"]),
        time_window_ps = Float64(best_data["time_window_ps"]),
        P_cont        = Float64(best_data["P_cont_W"]),
        L             = Float64(best_data["L_m"]),
        J_after       = Float64(best_data["J_after"]),
        source_path   = best_path,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Core: re-propagate phi_opt at long fiber length
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_repropagate_at_length(phi_stored, Nt_stored, tw_stored, P_cont, preset,
                             fiber_type, L_target;
                             Nt_override=nothing, tw_override=nothing,
                             n_zsave=PR_N_ZSAVE)

Propagate stored phi_opt through a fiber of length L_target with n_zsave z-saves.
Compares shaped (phi_opt applied) vs unshaped (flat phase) propagation.

CRITICAL: For SMF-28 at L>=10m, always pass Nt_override=65536, tw_override=500.0.
The auto-sizing formula breaks at L=30m (φ_NL=γPL formula is O(L) but physics
saturates at L ~ L_NL = 0.077m; auto-sizing gives Nt=524288, 1.6 GB memory).

Memory management: J(z) is computed BEFORE sol is released. uω_z is NOT saved to
JLD2 for long-fiber runs (200 MB per file × 16 files = 3.2 GB — impractical).

# Arguments
- `phi_stored`: phi_opt as Matrix{Float64}(Nt_stored, 1) in FFT order
- `Nt_stored`, `tw_stored`: grid parameters of stored phi
- `P_cont`: average continuum power (W)
- `preset`: fiber preset symbol (:SMF28 or :HNLF)
- `fiber_type`: "SMF-28" or "HNLF" (for logging)
- `L_target`: target fiber length (m)
- `Nt_override`, `tw_override`: explicit grid overrides (required for long fibers)
- `n_zsave`: number of z-save points

# Returns
Named tuple with J_z_shaped, J_z_unshaped, zsave, sim, band_mask, Nt, tw,
bc_frac_shaped, bc_frac_unshaped, uω_z_shaped (for spectral figure), uω_z_unshaped
"""
function pr_repropagate_at_length(
    phi_stored, Nt_stored, tw_stored, P_cont, preset, fiber_type, L_target;
    Nt_override   = nothing,
    tw_override   = nothing,
    n_zsave       = PR_N_ZSAVE,
    save_uω_z     = false,     # set true for spectral figure run only
)
    # Determine target grid (with explicit overrides for long SMF-28 fibers)
    if !isnothing(Nt_override) && !isnothing(tw_override)
        Nt_target = Nt_override
        tw_target = tw_override
    elseif L_target >= 10.0 && preset == :SMF28
        # CRITICAL: prevent auto-sizing blowup at L=30m SMF-28
        # φ_NL=γPL formula gives Nt=524288 at L=30m — physically wrong, allocates 1.6 GB
        Nt_target = 65536
        tw_target = 500.0
        @info @sprintf("SMF-28 L>=10m: forcing Nt=%d, time_window=%.0fps (prevents auto-sizing blowup)", Nt_target, tw_target)
    elseif L_target >= 10.0 && preset == :HNLF
        # HNLF at L=30m: auto-sizing gives ~463ps which is reasonable; cap anyway
        Nt_target = 65536
        tw_target = 463.0
        @info @sprintf("HNLF L>=10m: forcing Nt=%d, time_window=%.0fps", Nt_target, tw_target)
    else
        # Short fibers: use stored parameters for consistency
        Nt_target = Nt_stored
        tw_target = tw_stored
    end

    # Safety assertion: Nt cap (T-12-02 mitigation)
    @assert Nt_target <= 65536 "Nt=$Nt_target exceeds cap 65536 — memory blowup risk"

    @info @sprintf("Setting up %s L=%.0fm: Nt=%d, time_window=%.0fps, P=%.3fW",
        fiber_type, L_target, Nt_target, tw_target, P_cont)

    # Build target grid directly via MultiModeNoise internals to bypass auto-sizing.
    # setup_raman_problem auto-sizes when time_window < recommended_time_window(L).
    # At L=30m SMF-28, recommended=4276ps > 500ps cap, so we cannot use the wrapper.
    # We replicate the wrapper logic here with explicit, fixed parameters.
    fp = FIBER_PRESETS[preset]
    β_order = 3    # required: presets have 2 betas (β₂ + β₃)
    M = 1
    λ0 = 1550e-9
    pulse_fwhm     = 185e-15
    pulse_rep_rate = PR_REP_RATE
    pulse_shape    = "sech_sq"
    raman_threshold = -5.0

    sim      = MultiModeNoise.get_disp_sim_params(λ0, M, Nt_target, tw_target, β_order)
    fiber    = MultiModeNoise.get_disp_fiber_params_user_defined(
        L_target, sim; fR=fp.fR, gamma_user=fp.gamma, betas_user=fp.betas
    )
    u0_modes = ones(M) / √M
    _, uω0   = MultiModeNoise.get_initial_state(
        u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim
    )
    Δf_fft   = fftfreq(Nt_target, 1.0 / sim["Δt"])
    band_mask = Δf_fft .< raman_threshold

    @info @sprintf("Grid: sim[Nt]=%d, sim[Δt]=%.4eps", sim["Nt"], sim["Δt"])

    # Interpolate phi_opt to new frequency grid (T-12-01 mitigation: physical freq axis)
    if Nt_target == Nt_stored && tw_target == tw_stored
        # Identical grid — no interpolation needed
        phi_new = reshape(vec(phi_stored), Nt_target, 1)
        @info "phi_opt: no interpolation needed (identical grid)"
    else
        @info @sprintf("phi_opt: interpolating from Nt=%d/tw=%.0fps → Nt=%d/tw=%.0fps",
            Nt_stored, tw_stored, Nt_target, tw_target)
        phi_new = pr_interpolate_phi_to_new_grid(phi_stored, Nt_stored, tw_stored, Nt_target, tw_target)
    end

    uω0_shaped = uω0 .* exp.(1im .* phi_new)

    # Z-save points: n_zsave evenly-spaced positions from 0 to L_target
    zsave_vec = collect(LinRange(0.0, L_target, n_zsave))

    # ── Shaped propagation ──────────────────────────────────────────────────
    fiber_shaped = deepcopy(fiber)   # CRITICAL: deepcopy before setting zsave
    fiber_shaped["zsave"] = zsave_vec

    @info @sprintf("Propagating SHAPED: %s L=%.0fm (Nt=%d)", fiber_type, L_target, Nt_target)
    sol_shaped = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_shaped, sim)

    # Validate boundary conditions BEFORE releasing sol (T-12-03 mitigation)
    ok_shaped, bc_frac_shaped = check_boundary_conditions(sol_shaped["uω_z"][end, :, :], sim)
    if !ok_shaped || bc_frac_shaped > 1e-4
        @warn @sprintf("Shaped BC frac=%.2e at L=%.0fm — time window may be too narrow", bc_frac_shaped, L_target)
    else
        @info @sprintf("Shaped BC ok: frac=%.2e", bc_frac_shaped)
    end

    # Compute J(z) BEFORE releasing sol
    J_z_shaped = Float64[spectral_band_cost(sol_shaped["uω_z"][i, :, :], band_mask)[1] for i in 1:n_zsave]

    # Save uω_z only when requested (spectral figure for one representative config)
    uω_z_shaped_save = save_uω_z ? copy(sol_shaped["uω_z"]) : nothing

    # Release shaped solution to free memory before unshaped run
    sol_shaped = nothing
    GC.gc()

    # ── Unshaped propagation ─────────────────────────────────────────────────
    fiber_unshaped = deepcopy(fiber)   # CRITICAL: deepcopy before setting zsave
    fiber_unshaped["zsave"] = zsave_vec

    @info @sprintf("Propagating UNSHAPED: %s L=%.0fm (Nt=%d)", fiber_type, L_target, Nt_target)
    sol_unshaped = MultiModeNoise.solve_disp_mmf(uω0, fiber_unshaped, sim)

    # Validate boundary conditions
    ok_unshaped, bc_frac_unshaped = check_boundary_conditions(sol_unshaped["uω_z"][end, :, :], sim)
    if !ok_unshaped || bc_frac_unshaped > 1e-4
        @warn @sprintf("Unshaped BC frac=%.2e at L=%.0fm — time window may be too narrow", bc_frac_unshaped, L_target)
    else
        @info @sprintf("Unshaped BC ok: frac=%.2e", bc_frac_unshaped)
    end

    # Compute J(z) BEFORE releasing sol
    J_z_unshaped = Float64[spectral_band_cost(sol_unshaped["uω_z"][i, :, :], band_mask)[1] for i in 1:n_zsave]

    uω_z_unshaped_save = save_uω_z ? copy(sol_unshaped["uω_z"]) : nothing

    # Release unshaped solution
    sol_unshaped = nothing
    GC.gc()

    # Log J(z) summary
    @info @sprintf("J(z) summary at L=%.0fm:", L_target)
    @info @sprintf("  Shaped:   J[1]=%.2e  J[end]=%.2e  (%.1f → %.1f dB)",
        J_z_shaped[1], J_z_shaped[end],
        10*log10(max(J_z_shaped[1], 1e-20)), 10*log10(max(J_z_shaped[end], 1e-20)))
    @info @sprintf("  Unshaped: J[1]=%.2e  J[end]=%.2e  (%.1f → %.1f dB)",
        J_z_unshaped[1], J_z_unshaped[end],
        10*log10(max(J_z_unshaped[1], 1e-20)), 10*log10(max(J_z_unshaped[end], 1e-20)))

    return (
        J_z_shaped      = J_z_shaped,
        J_z_unshaped    = J_z_unshaped,
        zsave           = zsave_vec,
        sim             = sim,
        band_mask       = band_mask,
        Nt              = Nt_target,
        tw              = tw_target,
        bc_frac_shaped  = bc_frac_shaped,
        bc_frac_unshaped = bc_frac_unshaped,
        phi_opt         = phi_new,
        uω_z_shaped     = uω_z_shaped_save,
        uω_z_unshaped   = uω_z_unshaped_save,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Save J(z) data to JLD2
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_save_to_jld2(result, config_label, condition; phi_source=nothing,
                    P_cont=nothing, L_m=nothing, fiber_name=nothing)

Save J(z) results to JLD2 in PR_RESULTS_DIR.

Note: uω_z is NOT saved for long-fiber runs to avoid 200MB-per-file JLD2 files.
At Nt=65536 and 100 z-saves, uω_z alone = 100 MB per file; 16 files = 1.6 GB.
The J(z) curve is what matters for suppression reach analysis.

File naming: {config_label}_{condition}_zsolved.jld2
"""
function pr_save_to_jld2(result, config_label, condition;
                          phi_source = nothing,
                          P_cont     = nothing,
                          L_m        = nothing,
                          fiber_name = nothing)
    mkpath(PR_RESULTS_DIR)
    fname = "$(config_label)_$(condition)_zsolved.jld2"
    fpath = joinpath(PR_RESULTS_DIR, fname)

    J_z = (condition == "shaped") ? result.J_z_shaped : result.J_z_unshaped

    JLD2.jldsave(fpath;
        J_z           = J_z,
        zsave         = result.zsave,
        phi_opt       = result.phi_opt,
        L_m           = isnothing(L_m) ? result.zsave[end] : L_m,
        P_cont_W      = isnothing(P_cont) ? NaN : P_cont,
        fiber_name    = isnothing(fiber_name) ? "unknown" : fiber_name,
        Nt            = result.Nt,
        time_window_ps = result.tw,
        sim_Dt        = result.sim["Δt"],
        band_mask     = result.band_mask,
        J_first       = J_z[1],
        J_last        = J_z[end],
        bc_frac       = (condition == "shaped") ? result.bc_frac_shaped : result.bc_frac_unshaped,
        phi_source    = isnothing(phi_source) ? "unknown" : phi_source,
    )
    @info @sprintf("Saved %s", fpath)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 1: J(z) evolution for all long-fiber configs (physics_12_01)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_fig01_long_fiber_Jz(all_results)

Figure 12_01: 2×2 grid (rows: SMF-28 / HNLF; columns: phi source length).
Each panel: J(z) shaped vs flat for L=10m and L=30m propagations in dB.
Marks the optimization horizon with a vertical dashed line.
"""
function pr_fig01_long_fiber_Jz(all_results)
    fig, axes = subplots(2, 2, figsize=(14, 10))
    fig.suptitle("Raman Fraction J(z) Beyond Optimization Horizon", fontsize=14, fontweight="bold")

    # Layout: row 0=SMF-28, row 1=HNLF; col 0=short phi source, col 1=longer phi source
    panel_configs = [
        (key="SMF-28_phi@0.5m",                  opt_L=0.5,  row=0, col=0, title="SMF-28  |  φ optimized at L=0.5 m"),
        (key="SMF-28_phi@2m_(best_multi-start)",  opt_L=2.0,  row=0, col=1, title="SMF-28  |  φ optimized at L=2 m (best multi-start)"),
        (key="HNLF_phi@1m",                       opt_L=1.0,  row=1, col=0, title="HNLF    |  φ optimized at L=1 m"),
    ]

    # Colors for L=10m vs L=30m
    color_10m = "#0072B2"   # blue
    color_30m = "#D55E00"   # vermillion

    for pc in panel_configs
        haskey(all_results, pc.key) || continue
        ax = axes[pc.row + 1, pc.col + 1]

        for (L_tgt, color, lw) in [(10.0, color_10m, 2.0), (30.0, color_30m, 2.0)]
            sub_key = @sprintf("%s_L%.0fm", pc.key, L_tgt)
            haskey(all_results, sub_key) || continue
            r = all_results[sub_key]
            zsave = r.zsave

            J_s = max.(r.J_z_shaped,   1e-15)
            J_u = max.(r.J_z_unshaped, 1e-15)

            lbl_s = @sprintf("L=%.0fm shaped",   L_tgt)
            lbl_u = @sprintf("L=%.0fm unshaped", L_tgt)
            ax.plot(zsave, 10 .* log10.(J_s), color=color, linestyle="-",
                linewidth=lw, label=lbl_s, zorder=4)
            ax.plot(zsave, 10 .* log10.(J_u), color=color, linestyle="--",
                linewidth=lw, alpha=0.65, label=lbl_u, zorder=3)
        end

        # Optimization horizon vertical line
        ax.axvline(x=pc.opt_L, color="gray", linestyle=":", linewidth=1.5,
            alpha=0.85, zorder=2, label=@sprintf("Opt. horizon (%.1fm)", pc.opt_L))
        ax.text(pc.opt_L + 0.05, 0.98,
            @sprintf("opt. horizon\n(%.1fm)", pc.opt_L),
            transform=ax.get_xaxis_transform(), fontsize=7, va="top",
            color="gray")

        ax.set_title(pc.title, fontsize=10, fontweight="bold")
        ax.set_xlabel("z  [m]", fontsize=10)
        ax.set_ylabel("J(z)  [dB]", fontsize=10)
        ax.grid(true, alpha=0.3)
        ax.legend(fontsize=7.5, loc="upper left", ncol=1)
    end

    # Hide unused panel (row 1, col 1 — HNLF only has 1 phi source)
    axes[2, 2].set_visible(false)

    fig.tight_layout()
    fpath = joinpath(PR_FIGURE_DIR, "physics_12_01_long_fiber_Jz.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info @sprintf("Saved %s", fpath)
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 2: Spectral evolution for SMF-28 L=30m shaped vs unshaped (physics_12_02)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_fig02_spectral_evolution(all_results, sim_30m, uω_z_shaped, uω_z_unshaped)

Figure 12_02: 1×2 spectral evolution heatmaps for SMF-28 L=30m.
Left = unshaped, Right = shaped. Shows how shaping affects spectral broadening
and Raman peak formation over 30m of fiber.

If uω_z arrays are not available (memory-saving mode), uses placeholder.
"""
function pr_fig02_spectral_evolution(all_results, sim_30m, uω_z_shaped, uω_z_unshaped)
    if isnothing(uω_z_shaped) || isnothing(uω_z_unshaped)
        # Memory saving mode — create informational placeholder
        fig, ax = subplots(1, 1, figsize=(8, 4))
        ax.text(0.5, 0.5,
            "Spectral evolution data not saved\n(memory-saving mode for long-fiber runs)\n\nSee physics_12_01 for J(z) evolution",
            ha="center", va="center", fontsize=12, transform=ax.transAxes,
            bbox=Dict("boxstyle"=>"round", "fc"=>"lightyellow", "alpha"=>0.8))
        ax.set_axis_off()
        fig.suptitle("SMF-28 L=30m Spectral Evolution — Data Not Available", fontsize=12)
        fig.tight_layout()
        fpath = joinpath(PR_FIGURE_DIR, "physics_12_02_spectral_evolution_long.png")
        fig.savefig(fpath, dpi=300, bbox_inches="tight")
        @info @sprintf("Saved placeholder %s", fpath)
        close(fig)
        return fpath
    end

    Nt = sim_30m["Nt"]
    Δt = sim_30m["Δt"]
    fs = fftfreq(Nt, 1.0 / Δt)    # THz (Δt in ps → fs in THz)
    fs_shifted = fftshift(fs)

    n_zsave = size(uω_z_shaped, 1)
    zsave = collect(LinRange(0.0, 30.0, n_zsave))

    fig, axes = subplots(1, 2, figsize=(14, 7))
    fig.suptitle("Spectral Evolution — SMF-28  L=30 m  (P=0.2 W)", fontsize=13, fontweight="bold")

    for (col_idx, (uω_z, title)) in enumerate([
            (uω_z_unshaped, "Unshaped (flat phase)"),
            (uω_z_shaped,   "Shaped (phi_opt from L=2m)"),
        ])
        ax = axes[col_idx]

        # Build spectral intensity heatmap: [Nz × Nt] in fftshift order
        psd = zeros(n_zsave, Nt)
        for iz in 1:n_zsave
            slice = fftshift(vec(abs2.(uω_z[iz, :, :])))
            psd[iz, :] = slice
        end
        psd_dB = 10 .* log10.(max.(psd ./ maximum(psd), 1e-10))

        im = ax.pcolormesh(fs_shifted, zsave, psd_dB,
            cmap="inferno", vmin=-40.0, vmax=0.0,
            shading="auto", rasterized=true)

        # Raman band shading (~-13 THz from carrier = Stokes band)
        ax.axvspan(-16.0, -10.0, color=COLOR_RAMAN, alpha=0.20, label="Raman band")

        cb = fig.colorbar(im, ax=ax, shrink=0.85)
        cb.set_label("Power  [dB re peak]", fontsize=9)

        ax.set_xlabel("Frequency  [THz]", fontsize=10)
        ax.set_ylabel("z  [m]", fontsize=10)
        ax.set_title(title, fontsize=11, fontweight="bold")
        ax.set_xlim(-30.0, 30.0)
        ax.legend(fontsize=8, loc="lower right")
    end

    fig.tight_layout()
    fpath = joinpath(PR_FIGURE_DIR, "physics_12_02_spectral_evolution_long.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info @sprintf("Saved %s", fpath)
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 3: Shaping benefit (delta_J_dB) vs distance (physics_12_03)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_fig03_shaped_vs_flat_benefit(all_results)

Figure 12_03: 1×2 panels (left: SMF-28, right: HNLF).
Plot delta_J_dB(z) = J_dB_flat(z) - J_dB_shaped(z) for each (source, L_target).
A positive value means shaping is BETTER than flat phase at that z position.
Reference lines at 0 dB (no benefit) and 3 dB (marginal benefit).
"""
function pr_fig03_shaped_vs_flat_benefit(all_results)
    fig, axes = subplots(1, 2, figsize=(14, 6))
    fig.suptitle("Shaping Benefit: J_flat(z) − J_shaped(z)  [dB]", fontsize=13, fontweight="bold")

    panel_specs = [
        (fiber_type="SMF-28", ax_idx=1, title="SMF-28  (P = 0.2 W)",
         phi_sources=[("phi@0.5m", "#0072B2"), ("phi@2m_(best_multi-start)", "#56B4E9")]),
        (fiber_type="HNLF",   ax_idx=2, title="HNLF    (P = 0.01 W)",
         phi_sources=[("phi@1m", "#D55E00")]),
    ]

    l_targets = [10.0, 30.0]

    for spec in panel_specs
        ax = axes[spec.ax_idx]

        # Reference lines
        ax.axhline(y=0.0, color="black", linewidth=1.0, linestyle="--",
            alpha=0.6, label="0 dB (no benefit)")
        ax.axhline(y=3.0, color="gray",  linewidth=1.0, linestyle=":",
            alpha=0.6, label="3 dB")

        for (phi_src, base_color) in spec.phi_sources
            fiber_key_base = @sprintf("%s_%s", spec.fiber_type, phi_src)

            for (L_tgt, alpha_val) in zip(l_targets, [1.0, 0.65])
                sub_key = @sprintf("%s_L%.0fm", fiber_key_base, L_tgt)
                haskey(all_results, sub_key) || continue
                r = all_results[sub_key]

                J_s = max.(r.J_z_shaped,   1e-15)
                J_u = max.(r.J_z_unshaped, 1e-15)
                delta_dB = 10 .* log10.(J_u) .- 10 .* log10.(J_s)

                lbl = @sprintf("%s → L=%.0fm", phi_src, L_tgt)
                ax.plot(r.zsave, delta_dB, color=base_color, linewidth=2.0,
                    alpha=alpha_val, label=lbl, zorder=3)
            end
        end

        ax.set_title(spec.title, fontsize=11, fontweight="bold")
        ax.set_xlabel("z  [m]", fontsize=10)
        ax.set_ylabel("Shaping benefit  [dB]", fontsize=10)
        ax.grid(true, alpha=0.3)
        ax.legend(fontsize=8, loc="upper right")
    end

    fig.tight_layout()
    fpath = joinpath(PR_FIGURE_DIR, "physics_12_03_shaped_vs_flat_benefit.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info @sprintf("Saved %s", fpath)
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# Main execution block
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__

    run_start = now()
    @info "═══════════════════════════════════════════════════════════════"
    @info "Phase 12 — Long-Fiber Propagation Reach"
    @info @sprintf("Started: %s", run_start)
    @info "═══════════════════════════════════════════════════════════════"

    mkpath(PR_RESULTS_DIR)
    mkpath(PR_FIGURE_DIR)

    local all_results  = Dict{String, Any}()
    # For spectral figure: track one SMF-28 L=30m result with uω_z saved
    local sim_for_fig02 = nothing
    local uω_z_shaped_fig02   = nothing
    local uω_z_unshaped_fig02 = nothing

    for cfg in PR_LONG_CONFIGS
        @info "─────────────────────────────────────────────────────────────────────"
        @info @sprintf("Config: %s", cfg.label)
        @info @sprintf("  Fiber: %s | P_cont=%.3fW | Source: %s/%s",
            cfg.fiber_type, cfg.P_cont, cfg.source_dir, cfg.source_config)

        # ── Load phi_opt (multi-start best or single sweep) ──────────────────
        if cfg.use_multistart
            ms = pr_load_best_multistart_phi()
            phi_stored     = ms.phi_opt
            Nt_stored      = ms.Nt
            tw_stored      = ms.time_window_ps
            phi_source_str = ms.source_path
        else
            jld2_path = joinpath("results", "raman", "sweeps",
                cfg.source_dir, cfg.source_config, "opt_result.jld2")
            @assert isfile(jld2_path) "JLD2 not found: $jld2_path"
            data = JLD2.load(jld2_path)
            phi_stored     = Matrix{Float64}(data["phi_opt"])
            Nt_stored      = Int(data["Nt"])
            tw_stored      = Float64(data["time_window_ps"])
            phi_source_str = jld2_path
            @info @sprintf("Loaded phi_opt from %s", jld2_path)
            @info @sprintf("  Nt=%d, tw=%.1fps, J_after=%.2e (%.1f dB)",
                Nt_stored, tw_stored,
                Float64(data["J_after"]),
                Float64(data["delta_J_dB"]))
        end

        # ── Propagate at each L_target ────────────────────────────────────────
        for L_tgt in cfg.L_targets
            @info @sprintf(">>> Propagating to L=%.0fm", L_tgt)

            # For spectral figure: save uω_z for one representative config
            # (SMF-28 L=2m phi_opt propagated to L=30m — most physically interesting)
            want_uω_z = (cfg.fiber_type == "SMF-28" &&
                         cfg.use_multistart &&
                         L_tgt == 30.0)

            result = pr_repropagate_at_length(
                phi_stored, Nt_stored, tw_stored,
                cfg.P_cont, cfg.preset, cfg.fiber_type, L_tgt;
                save_uω_z = want_uω_z,
            )

            # Store in all_results with compound key
            # Key format: "{fiber_type}_{phi_source_label}_L{L}m"
            # Convert spaces to underscores in label for key
            label_key = replace(cfg.label, " " => "_")
            sub_key  = @sprintf("%s_L%.0fm", label_key, L_tgt)
            parent_key = label_key
            all_results[sub_key] = result

            # Save parent key entry (for figure function lookups)
            all_results[parent_key] = (
                fiber_type = cfg.fiber_type,
                phi_source = cfg.source_config,
            )

            # Save J(z) data to JLD2
            config_label = @sprintf("%s_L%.0fm", replace(cfg.label, " "=>"_", "("=>"", ")"=>""), L_tgt)
            pr_save_to_jld2(result, config_label, "shaped";
                phi_source = phi_source_str,
                P_cont     = cfg.P_cont,
                L_m        = L_tgt,
                fiber_name = cfg.fiber_type)
            pr_save_to_jld2(result, config_label, "unshaped";
                phi_source = phi_source_str,
                P_cont     = cfg.P_cont,
                L_m        = L_tgt,
                fiber_name = cfg.fiber_type)

            # Capture for spectral figure
            if want_uω_z
                sim_for_fig02       = result.sim
                uω_z_shaped_fig02   = result.uω_z_shaped
                uω_z_unshaped_fig02 = result.uω_z_unshaped
            end
        end
    end

    @info "═══════════════════════════════════════════════════════════════"
    @info "All propagations complete — generating figures"
    @info "═══════════════════════════════════════════════════════════════"

    # Figure 1: J(z) evolution for all configs
    pr_fig01_long_fiber_Jz(all_results)

    # Figure 2: Spectral evolution for SMF-28 L=30m shaped vs unshaped
    pr_fig02_spectral_evolution(all_results, sim_for_fig02, uω_z_shaped_fig02, uω_z_unshaped_fig02)

    # Figure 3: Shaping benefit (dB) vs distance
    pr_fig03_shaped_vs_flat_benefit(all_results)

    run_end  = now()
    duration = Millisecond(run_end - run_start).value / 1000.0
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Phase 12 complete. Duration: %.0f s", duration)
    @info @sprintf("JLD2 files: %s", PR_RESULTS_DIR)
    @info @sprintf("Figures:    %s", PR_FIGURE_DIR)
    @info "═══════════════════════════════════════════════════════════════"

end  # main execution guard
