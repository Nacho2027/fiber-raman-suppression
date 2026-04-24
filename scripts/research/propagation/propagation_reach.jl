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

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "visualization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "raman_optimization.jl"))

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

# ─────────────────────────────────────────────────────────────────────────────
# Horizon sweep configs (D-06): 4 power levels per fiber type
# ─────────────────────────────────────────────────────────────────────────────

const PR_SMF28_POWERS = [0.05, 0.1, 0.2, 0.5]    # Watts (D-06)
const PR_HNLF_POWERS  = [0.005, 0.01, 0.02, 0.05] # Watts (D-06)
const PR_HORIZON_L_TARGETS = [2.0, 5.0]            # Optimization target lengths (m)

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
# Horizon sweep: optimize at L_target, propagate through 2*L_target (D-05 to D-07)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_find_horizon(J_z_dB, zsave, threshold_dB)

Find the z-position at which J(z) in dB first exceeds threshold_dB.
Uses linear interpolation between adjacent z-points for sub-grid precision.
Returns NaN if the threshold is never crossed within zsave.

# Arguments
- `J_z_dB`: J(z) values in dB (negative means suppression)
- `zsave`:  z positions (m), same length as J_z_dB
- `threshold_dB`: threshold in dB (e.g. -50.0 for L_50dB, -30.0 for L_30dB)
                  NOTE: threshold is a dB value (typically negative for suppression)
                  We look for the z where J first becomes WORSE than this threshold
                  i.e., where J_z_dB > threshold_dB (less suppression)
"""
function pr_find_horizon(J_z_dB, zsave, threshold_dB)
    n = length(J_z_dB)
    @assert length(zsave) == n "zsave and J_z_dB must have same length"

    for i in 2:n
        if J_z_dB[i] > threshold_dB
            # Crossed above threshold between i-1 and i — interpolate
            dJ = J_z_dB[i] - J_z_dB[i-1]
            if abs(dJ) < 1e-15
                return zsave[i]
            end
            frac = (threshold_dB - J_z_dB[i-1]) / dJ
            return zsave[i-1] + frac * (zsave[i] - zsave[i-1])
        end
    end
    return NaN  # threshold never crossed
end

"""
    pr_optimize_and_propagate(preset, P_cont, L_target;
                               max_iter=50, n_zsave=PR_N_ZSAVE)

Optimize spectral phase at L_target, then propagate through 2*L_target (D-07).
Both shaped (phi_opt) and flat (unshaped) cases are propagated.

CRITICAL: For L_target >= 5m SMF-28, uses Nt=65536, tw=500ps to bypass auto-sizing.
For L_target <= 2m, lets setup_raman_problem auto-size (small fiber, safe).

# Returns
Named tuple: phi_opt, J_z_shaped, J_z_unshaped, zsave, J_at_target, J_at_2x,
J_flat_at_target, J_flat_at_2x, Nt, tw, converged, n_iter, grad_norm, L_target
"""
function pr_optimize_and_propagate(preset, P_cont, L_target;
                                    max_iter=50, n_zsave=PR_N_ZSAVE)
    fiber_type = (preset == :SMF28) ? "SMF-28" : "HNLF"
    @info @sprintf("pr_optimize_and_propagate: %s P=%.4fW L_target=%.1fm",
        fiber_type, P_cont, L_target)

    # ── Build grid: bypass setup_raman_problem auto-sizing for long fibers ────
    fp = FIBER_PRESETS[preset]
    β_order = 3    # required: presets have 2 betas (β₂ + β₃)
    M = 1
    λ0 = 1550e-9
    pulse_fwhm     = 185e-15
    pulse_rep_rate = PR_REP_RATE
    pulse_shape    = "sech_sq"
    raman_threshold = -5.0

    # Select Nt/tw: for L_target >= 5m, cap to prevent auto-sizing blowup
    if L_target >= 5.0 && preset == :SMF28
        Nt_use = 65536
        tw_use = 500.0
        @info @sprintf("SMF-28 L_target>=5m: using Nt=%d, tw=%.0fps", Nt_use, tw_use)
    elseif L_target >= 5.0 && preset == :HNLF
        Nt_use = 65536
        tw_use = 463.0
        @info @sprintf("HNLF L_target>=5m: using Nt=%d, tw=%.0fps", Nt_use, tw_use)
    else
        # Short fibers: use setup_raman_problem auto-sizing (safe at L<=2m)
        # But still use direct calls to be consistent and avoid any surprises
        Nt_use = preset == :SMF28 ? 8192 : 8192
        tw_use = preset == :SMF28 ? 40.0 : 20.0
        @info @sprintf("Short fiber: using Nt=%d, tw=%.0fps", Nt_use, tw_use)
    end

    sim   = MultiModeNoise.get_disp_sim_params(λ0, M, Nt_use, tw_use, β_order)
    fiber = MultiModeNoise.get_disp_fiber_params_user_defined(
        L_target, sim; fR=fp.fR, gamma_user=fp.gamma, betas_user=fp.betas
    )
    u0_modes = ones(M) / √M
    _, uω0   = MultiModeNoise.get_initial_state(
        u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim
    )
    Δf_fft   = fftfreq(Nt_use, 1.0 / sim["Δt"])
    band_mask = Δf_fft .< raman_threshold

    # ── Optimize spectral phase at L_target ──────────────────────────────────
    t_opt_start = time()
    fiber_opt = deepcopy(fiber)   # optimize_spectral_phase sets fiber["zsave"]=nothing
    result_opt = optimize_spectral_phase(uω0, fiber_opt, sim, band_mask;
        max_iter=max_iter, log_cost=true)
    t_opt_end = time()

    phi_opt  = reshape(Optim.minimizer(result_opt), sim["Nt"], sim["M"])
    converged = Optim.converged(result_opt)
    n_iter    = Optim.iterations(result_opt)
    grad_norm = Optim.g_residual(result_opt)

    @info @sprintf("Optimization: converged=%s, %d iter, wall=%.1fs, grad_norm=%.2e",
        string(converged), n_iter, t_opt_end - t_opt_start, grad_norm)

    # ── Propagate shaped through 2*L_target with z-saves ─────────────────────
    L_2x = 2.0 * L_target
    zsave_2x = collect(LinRange(0.0, L_2x, n_zsave))

    # Rebuild fiber for 2x length (same betas, different L)
    fiber_2x = MultiModeNoise.get_disp_fiber_params_user_defined(
        L_2x, sim; fR=fp.fR, gamma_user=fp.gamma, betas_user=fp.betas
    )

    uω0_shaped = uω0 .* exp.(1im .* phi_opt)

    fiber_shaped_2x = deepcopy(fiber_2x)
    fiber_shaped_2x["zsave"] = zsave_2x

    @info @sprintf("Propagating SHAPED through 2x L_target = %.1fm", L_2x)
    sol_shaped = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_shaped_2x, sim)

    J_z_shaped = Float64[spectral_band_cost(sol_shaped["uω_z"][i,:,:], band_mask)[1]
                         for i in 1:n_zsave]
    sol_shaped = nothing
    GC.gc()

    # ── Propagate flat through 2*L_target ────────────────────────────────────
    fiber_flat_2x = deepcopy(fiber_2x)
    fiber_flat_2x["zsave"] = zsave_2x

    @info @sprintf("Propagating FLAT (unshaped) through 2x L_target = %.1fm", L_2x)
    sol_flat = MultiModeNoise.solve_disp_mmf(uω0, fiber_flat_2x, sim)

    J_z_flat = Float64[spectral_band_cost(sol_flat["uω_z"][i,:,:], band_mask)[1]
                       for i in 1:n_zsave]
    sol_flat = nothing
    GC.gc()

    # ── Find J at L_target and 2*L_target ────────────────────────────────────
    # Interpolate to exactly L_target (midpoint of zsave)
    mid_idx = argmin(abs.(zsave_2x .- L_target))
    J_at_target      = J_z_shaped[mid_idx]
    J_at_2x          = J_z_shaped[end]
    J_flat_at_target = J_z_flat[mid_idx]
    J_flat_at_2x     = J_z_flat[end]

    @info @sprintf("Shaped: J@L=%.2f dB, J@2L=%.2f dB",
        10*log10(max(J_at_target, 1e-20)), 10*log10(max(J_at_2x, 1e-20)))
    @info @sprintf("Flat:   J@L=%.2f dB, J@2L=%.2f dB",
        10*log10(max(J_flat_at_target, 1e-20)), 10*log10(max(J_flat_at_2x, 1e-20)))

    return (
        phi_opt           = phi_opt,
        J_z_shaped        = J_z_shaped,
        J_z_flat          = J_z_flat,
        zsave             = zsave_2x,
        J_at_target       = J_at_target,
        J_at_2x           = J_at_2x,
        J_flat_at_target  = J_flat_at_target,
        J_flat_at_2x      = J_flat_at_2x,
        Nt                = Nt_use,
        tw                = tw_use,
        converged         = converged,
        n_iter            = n_iter,
        grad_norm         = grad_norm,
        L_target          = L_target,
    )
end

"""
    pr_run_horizon_sweep()

Run suppression horizon sweep: optimize at L=2m and L=5m for both fiber types
at 4 power levels each (D-05, D-06, D-07). For each point, compute L_50dB and L_30dB
from the J(z) propagated through 2*L_target.

Saves aggregate results to results/raman/phase12/horizon_sweep.jld2.
"""
function pr_run_horizon_sweep()
    @info "═══════════════════════════════════════════════════════════════"
    @info "Horizon Sweep — D-05 through D-07"
    @info "═══════════════════════════════════════════════════════════════"

    mkpath(PR_RESULTS_DIR)

    sweep_results = Dict{String, Any}()

    for (preset, powers, fiber_name) in [
            (:SMF28, PR_SMF28_POWERS, "SMF-28"),
            (:HNLF,  PR_HNLF_POWERS,  "HNLF"),
        ]
        for P_cont in powers
            for L_target in PR_HORIZON_L_TARGETS
                point_key = @sprintf("%s_P%.4fW_L%.1fm", fiber_name, P_cont, L_target)
                @info @sprintf("─── Sweep point: %s ─────────────────────────────", point_key)

                # T-12-05 mitigation: cap wall time per point
                t_point_start = time()

                local res
                try
                    res = pr_optimize_and_propagate(preset, P_cont, L_target;
                        max_iter=50)
                catch e
                    @warn @sprintf("FAILED: %s — %s", point_key, string(e))
                    continue
                end

                t_point_elapsed = time() - t_point_start
                @info @sprintf("Sweep point %s: %.1f s", point_key, t_point_elapsed)

                # Compute L_50dB and L_30dB from J(z) in dB
                J_z_dB = 10 .* log10.(max.(res.J_z_shaped, 1e-20))
                L_50dB = pr_find_horizon(J_z_dB, res.zsave, -50.0)
                L_30dB = pr_find_horizon(J_z_dB, res.zsave, -30.0)

                @info @sprintf("  L_50dB = %.3f m, L_30dB = %.3f m",
                    isnan(L_50dB) ? -1.0 : L_50dB,
                    isnan(L_30dB) ? -1.0 : L_30dB)

                sweep_results[point_key] = Dict(
                    "P_cont"           => P_cont,
                    "L_target"         => L_target,
                    "fiber_name"       => fiber_name,
                    "J_at_target_dB"   => 10*log10(max(res.J_at_target, 1e-20)),
                    "J_at_2x_dB"       => 10*log10(max(res.J_at_2x, 1e-20)),
                    "J_flat_at_target_dB" => 10*log10(max(res.J_flat_at_target, 1e-20)),
                    "L_50dB"           => L_50dB,
                    "L_30dB"           => L_30dB,
                    "phi_opt"          => res.phi_opt,
                    "J_z_shaped"       => res.J_z_shaped,
                    "J_z_flat"         => res.J_z_flat,
                    "zsave"            => res.zsave,
                    "Nt"               => res.Nt,
                    "time_window"      => res.tw,
                    "n_iter"           => res.n_iter,
                    "converged"        => res.converged,
                )
            end
        end
    end

    # Save aggregate JLD2
    jld2_path = joinpath(PR_RESULTS_DIR, "horizon_sweep.jld2")
    JLD2.jldsave(jld2_path; sweep_results = sweep_results)
    @info @sprintf("Saved horizon sweep: %s (%d points)", jld2_path, length(sweep_results))

    return sweep_results
end

# ─────────────────────────────────────────────────────────────────────────────
# Segmented optimization: 4 segments of 2m each, three-way comparison (D-09 to D-11)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_run_segmented_optimization(preset, P_cont;
                                   n_segments=4, L_segment=2.0, max_iter=50)

Run segmented optimization: optimize phi for L_segment, propagate, take output field,
re-optimize for next segment, repeat n_segments times (D-09, D-10).

Also runs single-shot optimization at total length n_segments*L_segment and flat phase
for three-way comparison (D-11).

Lab-frame field extraction between segments:
    current_field = cis.(Dω .* L) .* sol["ode_sol"](L)
where sol["ode_sol"] is the dense ODE solution in interaction picture.

# Returns
Named tuple with segmented/singleshot/flat J(z) data plus metadata.
"""
function pr_run_segmented_optimization(preset, P_cont;
                                        n_segments=4, L_segment=2.0, max_iter=50)
    fiber_type = (preset == :SMF28) ? "SMF-28" : "HNLF"
    L_total = n_segments * L_segment
    @info @sprintf("Segmented optimization: %s P=%.3fW, %d segments × %.1fm = %.1fm total",
        fiber_type, P_cont, n_segments, L_segment, L_total)

    # ── Single grid sized for one segment ────────────────────────────────────
    fp = FIBER_PRESETS[preset]
    β_order = 3
    M = 1
    λ0 = 1550e-9
    pulse_fwhm     = 185e-15
    pulse_rep_rate = PR_REP_RATE
    pulse_shape    = "sech_sq"
    raman_threshold = -5.0

    # Time window sized for 2x segment to accommodate dispersed field (Pitfall 3)
    Nt_seg = 8192
    tw_seg = preset == :SMF28 ? 80.0 : 40.0  # 2x typical segment window

    sim       = MultiModeNoise.get_disp_sim_params(λ0, M, Nt_seg, tw_seg, β_order)
    fiber_base = MultiModeNoise.get_disp_fiber_params_user_defined(
        L_segment, sim; fR=fp.fR, gamma_user=fp.gamma, betas_user=fp.betas
    )
    u0_modes  = ones(M) / √M
    _, uω0    = MultiModeNoise.get_initial_state(
        u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim
    )
    Δf_fft    = fftfreq(Nt_seg, 1.0 / sim["Δt"])
    band_mask = Δf_fft .< raman_threshold

    # ── Segmented optimization ────────────────────────────────────────────────
    phi_each_segment = Vector{Matrix{Float64}}()
    J_z_segmented    = Float64[]
    z_offsets        = Float64[]    # cumulative z for each segment
    bc_fracs         = Float64[]

    current_field = copy(uω0)   # fresh sech^2 pulse

    for seg in 1:n_segments
        z_offset = (seg - 1) * L_segment
        @info @sprintf("Segment %d/%d (z = %.1f → %.1f m)", seg, n_segments,
            z_offset, z_offset + L_segment)

        # Optimize for this segment
        fiber_opt = deepcopy(fiber_base)   # deepcopy: optimize_spectral_phase sets zsave=nothing
        result_opt = optimize_spectral_phase(copy(current_field), fiber_opt, sim, band_mask;
            max_iter=max_iter, log_cost=true)

        phi_seg = reshape(Optim.minimizer(result_opt), sim["Nt"], sim["M"])
        push!(phi_each_segment, copy(phi_seg))

        @info @sprintf("  Seg %d: converged=%s, %d iter, J_final=%.2f dB",
            seg, string(Optim.converged(result_opt)), Optim.iterations(result_opt),
            Optim.minimum(result_opt))

        # Propagate shaped segment with z-saves (25 points per segment)
        fiber_zsave = deepcopy(fiber_base)
        fiber_zsave["zsave"] = collect(LinRange(0.0, L_segment, 25))

        uω0_shaped = current_field .* exp.(1im .* phi_seg)
        sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_zsave, sim)

        # Compute J(z) for this segment
        J_z_seg = Float64[spectral_band_cost(sol["uω_z"][i,:,:], band_mask)[1]
                          for i in 1:25]
        append!(J_z_segmented, J_z_seg)

        # Build z-axis for this segment with correct offset
        z_seg = collect(LinRange(z_offset, z_offset + L_segment, 25))
        append!(z_offsets, z_seg)

        # Extract lab-frame field for next segment (T-12-04 mitigation)
        # ODE state is in interaction picture: lab-frame = cis(Dω * L) * sol_interaction
        Dω_vec = fiber_base["Dω"]
        L_seg  = fiber_base["L"]
        current_field = cis.(Dω_vec .* L_seg) .* sol["ode_sol"](L_seg)

        # Verify shape matches (Nt, M)
        @assert size(current_field) == size(uω0) "Lab-frame field shape mismatch: $(size(current_field)) vs $(size(uω0))"

        # T-12-07 mitigation: check boundary conditions
        ok_bc, bc_frac = check_boundary_conditions(current_field, sim)
        push!(bc_fracs, bc_frac)
        if bc_frac > 0.01
            @warn @sprintf("Seg %d BC frac=%.4f > 0.01 — field dispersed beyond time window", seg, bc_frac)
        else
            @info @sprintf("  Seg %d BC ok: frac=%.4f", seg, bc_frac)
        end

        # Energy conservation check (T-12-04 mitigation)
        E_in  = sum(abs2.(uω0_shaped))
        E_out = sum(abs2.(current_field))
        @info @sprintf("  Seg %d energy: in=%.4f, out=%.4f, ratio=%.4f",
            seg, E_in, E_out, E_out / E_in)

        sol = nothing
        GC.gc()
    end

    # ── Single-shot comparison: optimize full L_total in one call ─────────────
    @info @sprintf("Single-shot comparison: optimizing L_total=%.1fm", L_total)

    if L_total >= 5.0 && preset == :SMF28
        Nt_ss = 65536; tw_ss = 500.0
    elseif L_total >= 5.0 && preset == :HNLF
        Nt_ss = 65536; tw_ss = 463.0
    else
        Nt_ss = 8192; tw_ss = preset == :SMF28 ? 80.0 : 40.0
    end

    sim_ss   = MultiModeNoise.get_disp_sim_params(λ0, M, Nt_ss, tw_ss, β_order)
    fiber_ss = MultiModeNoise.get_disp_fiber_params_user_defined(
        L_total, sim_ss; fR=fp.fR, gamma_user=fp.gamma, betas_user=fp.betas
    )
    _, uω0_ss = MultiModeNoise.get_initial_state(
        u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim_ss
    )
    Δf_ss     = fftfreq(Nt_ss, 1.0 / sim_ss["Δt"])
    band_ss   = Δf_ss .< raman_threshold

    fiber_opt_ss = deepcopy(fiber_ss)
    result_ss    = optimize_spectral_phase(uω0_ss, fiber_opt_ss, sim_ss, band_ss;
        max_iter=max_iter, log_cost=true)

    phi_ss   = reshape(Optim.minimizer(result_ss), sim_ss["Nt"], sim_ss["M"])
    @info @sprintf("Single-shot: converged=%s, %d iter", string(Optim.converged(result_ss)),
        Optim.iterations(result_ss))

    # Propagate single-shot shaped with 100 z-saves
    fiber_ss_prop = deepcopy(fiber_ss)
    fiber_ss_prop["zsave"] = collect(LinRange(0.0, L_total, PR_N_ZSAVE))
    sol_ss = MultiModeNoise.solve_disp_mmf(uω0_ss .* exp.(1im .* phi_ss), fiber_ss_prop, sim_ss)
    J_z_singleshot = Float64[spectral_band_cost(sol_ss["uω_z"][i,:,:], band_ss)[1]
                              for i in 1:PR_N_ZSAVE]
    zsave_ss = fiber_ss_prop["zsave"]
    sol_ss = nothing; GC.gc()

    # ── Flat phase (no optimization) through full L_total ────────────────────
    fiber_flat_prop = deepcopy(fiber_ss)
    fiber_flat_prop["zsave"] = collect(LinRange(0.0, L_total, PR_N_ZSAVE))
    sol_flat = MultiModeNoise.solve_disp_mmf(uω0_ss, fiber_flat_prop, sim_ss)
    J_z_flat = Float64[spectral_band_cost(sol_flat["uω_z"][i,:,:], band_ss)[1]
                       for i in 1:PR_N_ZSAVE]
    sol_flat = nothing; GC.gc()

    # ── Save results ─────────────────────────────────────────────────────────
    jld2_path = joinpath(PR_RESULTS_DIR, "segmented_optimization.jld2")
    JLD2.jldsave(jld2_path;
        # Segmented
        J_z_segmented   = J_z_segmented,
        z_offsets        = z_offsets,
        phi_each_segment = phi_each_segment,
        bc_fracs         = bc_fracs,
        n_segments       = n_segments,
        L_segment        = L_segment,
        L_total          = L_total,
        Nt_segment       = Nt_seg,
        tw_segment       = tw_seg,
        # Single-shot
        J_z_singleshot   = J_z_singleshot,
        phi_singleshot   = phi_ss,
        zsave_singleshot = zsave_ss,
        Nt_singleshot    = Nt_ss,
        tw_singleshot    = tw_ss,
        # Flat
        J_z_flat         = J_z_flat,
        zsave_flat       = zsave_ss,
        # Metadata
        P_cont           = P_cont,
        fiber_name       = fiber_type,
        preset           = string(preset),
    )
    @info @sprintf("Saved segmented optimization: %s", jld2_path)

    return (
        J_z_segmented    = J_z_segmented,
        z_offsets         = z_offsets,
        phi_each_segment  = phi_each_segment,
        bc_fracs          = bc_fracs,
        J_z_singleshot    = J_z_singleshot,
        zsave_singleshot  = zsave_ss,
        J_z_flat          = J_z_flat,
        n_segments        = n_segments,
        L_segment         = L_segment,
        L_total           = L_total,
        Nt_segment        = Nt_seg,
        Nt_singleshot     = Nt_ss,
    )
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
# Figure 4: Horizon L_50dB and L_30dB vs power for both fiber types (physics_12_04)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_fig04_horizon_vs_power(sweep_results)

Figure 12_04: 1×2 panels. Left = SMF-28, Right = HNLF.
Each panel: L_50dB (solid, filled markers) and L_30dB (dashed, open markers) vs power.
X-axis: power (W) log scale. Y-axis: horizon length (m) log scale.
"""
function pr_fig04_horizon_vs_power(sweep_results)
    fig, axes = subplots(1, 2, figsize=(13, 6))
    fig.suptitle("Suppression Horizon vs Input Power", fontsize=14, fontweight="bold")

    panel_specs = [
        (fiber_name="SMF-28", powers=PR_SMF28_POWERS, ax_idx=1, title="SMF-28"),
        (fiber_name="HNLF",   powers=PR_HNLF_POWERS,  ax_idx=2, title="HNLF"),
    ]

    color_50 = "#0072B2"   # blue
    color_30 = "#D55E00"   # vermillion

    for spec in panel_specs
        ax = axes[spec.ax_idx]

        L50_vals = Float64[]
        L30_vals = Float64[]
        valid_50_powers = Float64[]
        valid_30_powers = Float64[]

        for P_cont in spec.powers
            # Use L_target=2m results (primary sweep point)
            key = @sprintf("%s_P%.4fW_L%.1fm", spec.fiber_name, P_cont, 2.0)
            if !haskey(sweep_results, key)
                continue
            end
            d = sweep_results[key]
            L50 = isa(d["L_50dB"], Number) ? Float64(d["L_50dB"]) : NaN
            L30 = isa(d["L_30dB"], Number) ? Float64(d["L_30dB"]) : NaN

            if !isnan(L50)
                push!(L50_vals, L50)
                push!(valid_50_powers, P_cont)
            else
                # Mark with upward arrow: horizon > 2*L_target
                ax.annotate("",
                    xy=(P_cont, 0.95), xycoords="axes fraction",
                    xytext=(P_cont, 0.85), textcoords="axes fraction",
                    arrowprops=Dict("arrowstyle"=>"-|>", "color"=>color_50))
                ax.text(P_cont, 2.0, @sprintf("P=%.3fW\nL₅₀>%.0fm", P_cont, 4.0),
                    ha="center", va="bottom", fontsize=7, color=color_50)
            end
            if !isnan(L30)
                push!(L30_vals, L30)
                push!(valid_30_powers, P_cont)
            end
        end

        if length(valid_50_powers) > 0
            ax.semilogy(valid_50_powers, L50_vals, "o-",
                color=color_50, linewidth=2, markersize=8, markerfacecolor=color_50,
                label="L₅₀dB")
        end
        if length(valid_30_powers) > 0
            ax.semilogy(valid_30_powers, L30_vals, "s--",
                color=color_30, linewidth=2, markersize=8, markerfacecolor="none",
                markeredgecolor=color_30, markeredgewidth=1.5,
                label="L₃₀dB")
        end

        # Phase 11 reference: L_50dB ≈ 3.33m at P=0.2W for SMF-28
        if spec.fiber_name == "SMF-28"
            ax.axhline(y=3.33, color="gray", linestyle=":", linewidth=1.5,
                alpha=0.8, label="L₅₀dB baseline ≈ 3.33m (Phase 11)")
            ax.axvline(x=0.2, color="gray", linestyle=":", linewidth=1.0, alpha=0.5)
        end

        ax.set_xscale("log")
        ax.set_xlabel("Input power  [W]", fontsize=11)
        ax.set_ylabel("Horizon length  [m]", fontsize=11)
        ax.set_title(spec.title, fontsize=12, fontweight="bold")
        ax.grid(true, which="both", alpha=0.3)
        ax.legend(fontsize=9, loc="best")
    end

    fig.tight_layout()
    fpath = joinpath(PR_FIGURE_DIR, "physics_12_04_horizon_vs_power.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info @sprintf("Saved %s", fpath)
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 5: Segmented vs single-shot vs flat J(z) comparison (physics_12_05)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_fig05_segmented_vs_singleshot(seg_result)

Figure 12_05: Single panel. J(z) for segmented, single-shot, and flat phase.
Segment boundaries marked with vertical dashed lines.
"""
function pr_fig05_segmented_vs_singleshot(seg_result)
    fig, ax = subplots(1, 1, figsize=(10, 6))

    # Three-way comparison
    J_seg = 10 .* log10.(max.(seg_result["J_z_segmented"], 1e-20))
    J_ss  = 10 .* log10.(max.(seg_result["J_z_singleshot"], 1e-20))
    J_flat = 10 .* log10.(max.(seg_result["J_z_flat"], 1e-20))

    ax.plot(seg_result["z_offsets"], J_seg,
        color="#0072B2", linestyle="-", linewidth=2.5,
        label=@sprintf("Segmented (%d×%.0fm)", seg_result["n_segments"], seg_result["L_segment"]),
        zorder=4)
    ax.plot(seg_result["zsave_singleshot"], J_ss,
        color="#E69F00", linestyle="--", linewidth=2.0,
        label=@sprintf("Single-shot (%.0fm)", seg_result["L_total"]), zorder=3)
    ax.plot(seg_result["zsave_singleshot"], J_flat,
        color="#999999", linestyle=":", linewidth=1.8,
        label="Flat phase (no optimization)", zorder=2)

    # Segment boundary markers
    for seg in 1:(seg_result["n_segments"] - 1)
        z_boundary = seg * seg_result["L_segment"]
        ax.axvline(x=z_boundary, color="#0072B2", linestyle="--",
            linewidth=1.0, alpha=0.6, zorder=1)
        ax.text(z_boundary + 0.05, ax.get_ylim()[2] * 0.98,
            "re-opt", fontsize=7.5, va="top", color="#0072B2", alpha=0.8)
    end

    # Annotate J at z=L_total for each condition
    J_seg_end  = J_seg[end]
    J_ss_end   = J_ss[end]
    J_flat_end = J_flat[end]
    ax.annotate(@sprintf("%.1f dB", J_seg_end),
        xy=(seg_result["z_offsets"][end], J_seg_end),
        xytext=(seg_result["z_offsets"][end] - 1.5, J_seg_end - 3),
        fontsize=8.5, color="#0072B2",
        arrowprops=Dict("arrowstyle"=>"-", "color"=>"#0072B2", "alpha"=>0.7))
    ax.annotate(@sprintf("%.1f dB", J_ss_end),
        xy=(seg_result["zsave_singleshot"][end], J_ss_end),
        xytext=(seg_result["zsave_singleshot"][end] - 1.5, J_ss_end + 4),
        fontsize=8.5, color="#E69F00",
        arrowprops=Dict("arrowstyle"=>"-", "color"=>"#E69F00", "alpha"=>0.7))

    ax.set_xlabel("z  [m]", fontsize=12)
    ax.set_ylabel("J(z)  [dB]", fontsize=12)
    ax.set_title("Segmented vs Single-Shot vs Flat Phase  —  Raman Fraction J(z)",
        fontsize=12, fontweight="bold")
    ax.grid(true, alpha=0.3)
    ax.legend(fontsize=10, loc="upper left")

    fig.tight_layout()
    fpath = joinpath(PR_FIGURE_DIR, "physics_12_05_segmented_vs_singleshot.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info @sprintf("Saved %s", fpath)
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 6: Scaling law L_50dB vs P (log-log) with power-law fit (physics_12_06)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_fig06_scaling_law(sweep_results)

Figure 12_06: 1×2 log-log panels. Left = L_50dB vs P, Right = L_30dB vs P.
Both fiber types on each panel. Power-law fit L_XdB = A * P^alpha reported.
"""
function pr_fig06_scaling_law(sweep_results)
    fig, axes = subplots(1, 2, figsize=(13, 6))
    fig.suptitle("Suppression Horizon Scaling: L_XdB ∼ P^α", fontsize=14, fontweight="bold")

    panel_specs = [
        (threshold="50", ax_idx=1, key_suffix="L_50dB"),
        (threshold="30", ax_idx=2, key_suffix="L_30dB"),
    ]

    fiber_specs = [
        (fiber_name="SMF-28", powers=PR_SMF28_POWERS, color="#0072B2", marker="o"),
        (fiber_name="HNLF",   powers=PR_HNLF_POWERS,  color="#D55E00", marker="s"),
    ]

    for spec in panel_specs
        ax = axes[spec.ax_idx]

        # Reference lines: alpha = -1 and alpha = -0.5
        P_ref = [1e-3, 1.0]
        ax.loglog(P_ref, 0.5 .* (P_ref ./ 0.1).^(-1.0), "k:", linewidth=1.2,
            alpha=0.5, label="α = −1 reference")
        ax.loglog(P_ref, 0.5 .* (P_ref ./ 0.1).^(-0.5), "k--", linewidth=1.2,
            alpha=0.5, label="α = −0.5 reference")

        for fspec in fiber_specs
            L_vals = Float64[]
            P_vals = Float64[]

            for P_cont in fspec.powers
                key = @sprintf("%s_P%.4fW_L%.1fm", fspec.fiber_name, P_cont, 2.0)
                haskey(sweep_results, key) || continue
                d = sweep_results[key]
                L_val = isa(d[spec.key_suffix], Number) ? Float64(d[spec.key_suffix]) : NaN
                if !isnan(L_val) && L_val > 0
                    push!(L_vals, L_val)
                    push!(P_vals, P_cont)
                end
            end

            length(P_vals) < 2 && continue

            ax.loglog(P_vals, L_vals, string(fspec.marker, "-"),
                color=fspec.color, linewidth=2, markersize=8,
                label=fspec.fiber_name)

            # Power-law fit in log-log space
            log_P = log10.(P_vals)
            log_L = log10.(L_vals)
            # Linear fit: log_L = alpha*log_P + log_A
            n_fit = length(log_P)
            mean_P = sum(log_P) / n_fit
            mean_L = sum(log_L) / n_fit
            alpha_fit = sum((log_P .- mean_P) .* (log_L .- mean_L)) /
                        sum((log_P .- mean_P).^2)
            A_fit = 10^(mean_L - alpha_fit * mean_P)

            @info @sprintf("%s L_%sdB fit: alpha=%.2f, A=%.4f",
                fspec.fiber_name, spec.threshold, alpha_fit, A_fit)

            # Overlay fit line
            P_fit = 10 .^ range(log10(minimum(P_vals)), log10(maximum(P_vals)), length=30)
            L_fit = A_fit .* P_fit .^ alpha_fit
            ax.loglog(P_fit, L_fit, "--",
                color=fspec.color, linewidth=1.5, alpha=0.7,
                label=@sprintf("%s fit: α = %.2f", fspec.fiber_name, alpha_fit))
        end

        ax.set_xlabel("Input power  [W]", fontsize=11)
        ax.set_ylabel(@sprintf("L_%sdB  [m]", spec.threshold), fontsize=11)
        ax.set_title(@sprintf("L_%sdB Scaling", spec.threshold), fontsize=12, fontweight="bold")
        ax.grid(true, which="both", alpha=0.3)
        ax.legend(fontsize=8, loc="best")
    end

    fig.tight_layout()
    fpath = joinpath(PR_FIGURE_DIR, "physics_12_06_scaling_law.png")
    fig.savefig(fpath, dpi=300, bbox_inches="tight")
    @info @sprintf("Saved %s", fpath)
    close(fig)
    return fpath
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure 7: Phase 12 reach summary dashboard (physics_12_07)
# ─────────────────────────────────────────────────────────────────────────────

"""
    pr_fig07_reach_summary_dashboard(sweep_results, seg_result)

Figure 12_07: 2×2 dashboard summarizing all Phase 12 findings.
  (a) Long-fiber J(z) — SMF-28 best multi-start at L=30m (from Plan 01 data)
  (b) Horizon L_50dB vs P — both fibers
  (c) Segmented J(z) vs z — three-way comparison
  (d) Scaling summary text (alpha values)
"""
function pr_fig07_reach_summary_dashboard(sweep_results, seg_result)
    fig, axes = subplots(2, 2, figsize=(14, 11))
    fig.suptitle("Finite Reach of Spectral Phase Raman Suppression  —  Phase 12 Summary",
        fontsize=13, fontweight="bold")

    # ── Panel (a): Long-fiber J(z) from Plan 01 data ─────────────────────────
    ax_a = axes[1, 1]
    ax_a.set_title("(a) Long-Fiber Propagation  (Plan 01)", fontsize=10, fontweight="bold")

    # Load Plan 01 JLD2 files: SMF-28 phi@2m multi-start at L=30m
    for (fname, lbl, color, ls) in [
            ("SMF-28_phi@2m_(best_multi-start)_L30m_shaped_zsolved.jld2",
             "SMF-28 shaped (phi@2m, L=30m)", "#0072B2", "-"),
            ("SMF-28_phi@2m_(best_multi-start)_L30m_unshaped_zsolved.jld2",
             "SMF-28 unshaped (L=30m)", "#56B4E9", "--"),
        ]
        fpath_jld2 = joinpath(PR_RESULTS_DIR, fname)
        if isfile(fpath_jld2)
            d = JLD2.load(fpath_jld2)
            J_z_dB = 10 .* log10.(max.(d["J_z"], 1e-20))
            ax_a.plot(d["zsave"], J_z_dB, color=color, linestyle=ls,
                linewidth=2.0, label=lbl)
        end
    end
    ax_a.axvline(x=2.0, color="gray", linestyle=":", linewidth=1.5, alpha=0.7,
        label="Opt. horizon (2m)")
    ax_a.set_xlabel("z  [m]", fontsize=9)
    ax_a.set_ylabel("J(z)  [dB]", fontsize=9)
    ax_a.legend(fontsize=7, loc="upper left")
    ax_a.grid(true, alpha=0.3)

    # ── Panel (b): Horizon L_50dB vs P — both fibers ─────────────────────────
    ax_b = axes[1, 2]
    ax_b.set_title("(b) Suppression Horizon vs Power", fontsize=10, fontweight="bold")

    for (fiber_name, powers, color, marker) in [
            ("SMF-28", PR_SMF28_POWERS, "#0072B2", "o"),
            ("HNLF",   PR_HNLF_POWERS,  "#D55E00", "s"),
        ]
        L50_vals = Float64[]
        P_vals   = Float64[]
        for P_cont in powers
            key = @sprintf("%s_P%.4fW_L%.1fm", fiber_name, P_cont, 2.0)
            haskey(sweep_results, key) || continue
            d = sweep_results[key]
            L50 = isa(d["L_50dB"], Number) ? Float64(d["L_50dB"]) : NaN
            if !isnan(L50)
                push!(L50_vals, L50)
                push!(P_vals, P_cont)
            end
        end
        length(P_vals) > 0 && ax_b.semilogy(P_vals, L50_vals, string(marker, "-"),
            color=color, linewidth=2, markersize=7, label=fiber_name)
    end
    ax_b.set_xscale("log")
    ax_b.set_xlabel("Input power  [W]", fontsize=9)
    ax_b.set_ylabel("L_50dB  [m]", fontsize=9)
    ax_b.legend(fontsize=8)
    ax_b.grid(true, which="both", alpha=0.3)

    # ── Panel (c): Segmented J(z) — three-way comparison ─────────────────────
    ax_c = axes[2, 1]
    ax_c.set_title("(c) Segmented vs Single-Shot vs Flat", fontsize=10, fontweight="bold")

    J_seg  = 10 .* log10.(max.(seg_result["J_z_segmented"], 1e-20))
    J_ss   = 10 .* log10.(max.(seg_result["J_z_singleshot"], 1e-20))
    J_flat = 10 .* log10.(max.(seg_result["J_z_flat"], 1e-20))

    ax_c.plot(seg_result["z_offsets"], J_seg, color="#0072B2", linestyle="-",
        linewidth=2.0, label="Segmented")
    ax_c.plot(seg_result["zsave_singleshot"], J_ss, color="#E69F00", linestyle="--",
        linewidth=2.0, label="Single-shot")
    ax_c.plot(seg_result["zsave_singleshot"], J_flat, color="#999999", linestyle=":",
        linewidth=1.8, label="Flat phase")

    for seg in 1:(seg_result["n_segments"] - 1)
        ax_c.axvline(x=seg * seg_result["L_segment"], color="#0072B2",
            linestyle="--", linewidth=0.8, alpha=0.5)
    end
    ax_c.set_xlabel("z  [m]", fontsize=9)
    ax_c.set_ylabel("J(z)  [dB]", fontsize=9)
    ax_c.legend(fontsize=8)
    ax_c.grid(true, alpha=0.3)

    # ── Panel (d): Scaling law summary text ──────────────────────────────────
    ax_d = axes[2, 2]
    ax_d.set_axis_off()
    ax_d.set_title("(d) Key Findings Summary", fontsize=10, fontweight="bold")

    # Compute alpha for both fibers
    summary_lines = String[]
    push!(summary_lines, "Suppression Horizon Scaling")
    push!(summary_lines, "L_50dB ~ A × P^α")
    push!(summary_lines, "")

    for (fiber_name, powers) in [("SMF-28", PR_SMF28_POWERS), ("HNLF", PR_HNLF_POWERS)]
        P_vals = Float64[]; L_vals = Float64[]
        for P in powers
            key = @sprintf("%s_P%.4fW_L%.1fm", fiber_name, P, 2.0)
            haskey(sweep_results, key) || continue
            d = sweep_results[key]
            L50 = isa(d["L_50dB"], Number) ? Float64(d["L_50dB"]) : NaN
            if !isnan(L50) && L50 > 0
                push!(P_vals, P); push!(L_vals, L50)
            end
        end
        if length(P_vals) >= 2
            log_P = log10.(P_vals); log_L = log10.(L_vals)
            mean_P = sum(log_P) / length(log_P); mean_L = sum(log_L) / length(log_L)
            alpha = sum((log_P .- mean_P) .* (log_L .- mean_L)) / sum((log_P .- mean_P).^2)
            push!(summary_lines, @sprintf("%s: α = %.2f", fiber_name, alpha))
        else
            push!(summary_lines, @sprintf("%s: insufficient points", fiber_name))
        end
    end
    push!(summary_lines, "")
    push!(summary_lines, "Segmented optimization:")
    J_seg_final  = J_seg[end]
    J_ss_final   = J_ss[end]
    J_flat_final = J_flat[end]
    push!(summary_lines, @sprintf("  Segmented J(L): %.1f dB", J_seg_final))
    push!(summary_lines, @sprintf("  Single-shot J(L): %.1f dB", J_ss_final))
    push!(summary_lines, @sprintf("  Flat J(L): %.1f dB", J_flat_final))
    push!(summary_lines, @sprintf("  Benefit over flat: %.1f dB", J_flat_final - J_seg_final))

    ax_d.text(0.05, 0.95, join(summary_lines, "\n"),
        transform=ax_d.transAxes, fontsize=9.5, va="top", fontfamily="monospace",
        bbox=Dict("boxstyle"=>"round", "fc"=>"lightyellow", "alpha"=>0.8))

    fig.tight_layout()
    fpath = joinpath(PR_FIGURE_DIR, "physics_12_07_reach_summary_dashboard.png")
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

    # ═══════════════════════════════════════════════════════════════
    # PLAN 02 — Task 1: Suppression horizon sweep
    # ═══════════════════════════════════════════════════════════════
    @info "═══════════════════════════════════════════════════════════════"
    @info "Phase 12 Plan 02 — Task 1: Horizon sweep"
    @info "═══════════════════════════════════════════════════════════════"

    # Check if sweep already done (allow restart without re-running ~60min sweep)
    horizon_jld2 = joinpath(PR_RESULTS_DIR, "horizon_sweep.jld2")
    local sweep_results
    if isfile(horizon_jld2)
        @info "Loading existing horizon_sweep.jld2 (skipping re-run)"
        d_sweep = JLD2.load(horizon_jld2)
        sweep_results = d_sweep["sweep_results"]
        @info @sprintf("Loaded %d sweep points", length(sweep_results))
    else
        sweep_results = pr_run_horizon_sweep()
    end

    # ═══════════════════════════════════════════════════════════════
    # PLAN 02 — Task 2: Segmented optimization
    # ═══════════════════════════════════════════════════════════════
    @info "═══════════════════════════════════════════════════════════════"
    @info "Phase 12 Plan 02 — Task 2: Segmented optimization (SMF-28, P=0.2W)"
    @info "═══════════════════════════════════════════════════════════════"

    seg_jld2 = joinpath(PR_RESULTS_DIR, "segmented_optimization.jld2")
    local seg_result
    if isfile(seg_jld2)
        @info "Loading existing segmented_optimization.jld2 (skipping re-run)"
        d_seg = JLD2.load(seg_jld2)
        seg_result = (
            J_z_segmented    = d_seg["J_z_segmented"],
            z_offsets         = d_seg["z_offsets"],
            phi_each_segment  = d_seg["phi_each_segment"],
            bc_fracs          = d_seg["bc_fracs"],
            J_z_singleshot    = d_seg["J_z_singleshot"],
            zsave_singleshot  = d_seg["zsave_singleshot"],
            J_z_flat          = d_seg["J_z_flat"],
            n_segments        = Int(d_seg["n_segments"]),
            L_segment         = Float64(d_seg["L_segment"]),
            L_total           = Float64(d_seg["L_total"]),
            Nt_segment        = Int(d_seg["Nt_segment"]),
            Nt_singleshot     = Int(d_seg["Nt_singleshot"]),
        )
        @info "Segmented optimization loaded from JLD2"
    else
        seg_result = pr_run_segmented_optimization(:SMF28, 0.2;
            n_segments=4, L_segment=2.0, max_iter=50)
    end

    # ═══════════════════════════════════════════════════════════════
    # PLAN 02 — Task 3: Figures 04-07
    # ═══════════════════════════════════════════════════════════════
    @info "═══════════════════════════════════════════════════════════════"
    @info "Phase 12 Plan 02 — Task 3: Generating figures 04-07"
    @info "═══════════════════════════════════════════════════════════════"

    pr_fig04_horizon_vs_power(sweep_results)
    pr_fig05_segmented_vs_singleshot(seg_result)
    pr_fig06_scaling_law(sweep_results)
    pr_fig07_reach_summary_dashboard(sweep_results, seg_result)

    run_end  = now()
    duration = Millisecond(run_end - run_start).value / 1000.0
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Phase 12 complete. Duration: %.0f s", duration)
    @info @sprintf("JLD2 files: %s", PR_RESULTS_DIR)
    @info @sprintf("Figures:    %s", PR_FIGURE_DIR)
    @info "═══════════════════════════════════════════════════════════════"

end  # main execution guard
