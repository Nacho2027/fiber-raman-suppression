"""
Common utilities shared across fiber optimization scripts.

Shared functions (single source of truth):
- `recommended_time_window` — safe time window from dispersive walk-off
- `spectral_band_cost` — fractional spectral energy in a frequency band
- `check_boundary_conditions` — detect energy leakage at temporal window edges
- `setup_raman_problem` — setup for phase optimization
- `setup_amplitude_problem` — setup for amplitude optimization

Include guard: safe to include multiple times.
"""

if !(@isdefined _COMMON_JL_LOADED)
const _COMMON_JL_LOADED = true

using LinearAlgebra
using FFTW
using Logging
using MultiModeNoise

# ─────────────────────────────────────────────────────────────────────────────
# Time window safety
# ─────────────────────────────────────────────────────────────────────────────

"""
    recommended_time_window(L_fiber; safety_factor=2.0)

Compute safe time window [ps] from dispersive walk-off.
Uses SMF-28 parameters: |β₂| = 20e-27 s²/m, Raman shift ≈ 13 THz.
Returns at least 5 ps to avoid degenerate grids for short fibers.
"""
function recommended_time_window(L_fiber; safety_factor=2.0)
    @assert L_fiber > 0 "fiber length must be positive, got $L_fiber"
    @assert safety_factor > 0 "safety factor must be positive"

    β2_abs = 20e-27
    Δω_raman = 2π * 13e12
    walk_off_ps = β2_abs * L_fiber * Δω_raman * 1e12
    pulse_extent = 0.5
    return max(5, ceil(Int, (walk_off_ps + pulse_extent) * safety_factor))
end

# ─────────────────────────────────────────────────────────────────────────────
# Spectral band cost (single definition — was duplicated across files)
# ─────────────────────────────────────────────────────────────────────────────

"""
    spectral_band_cost(uωf, band_mask)

Fractional spectral energy in a frequency band and its gradient.

# Arguments
- `uωf`: Output field in frequency domain, shape (Nt, M).
- `band_mask`: Boolean vector of length Nt, true for frequencies in the band.

# Returns
- `J`: Scalar cost = E_band / E_total ∈ [0, 1].
- `dJ`: Gradient w.r.t. conj(uωf), adjoint terminal condition λ(L).
"""
function spectral_band_cost(uωf, band_mask)
    # PRECONDITIONS
    @assert size(uωf, 1) == length(band_mask) "uωf rows ($(size(uωf,1))) must match band_mask length ($(length(band_mask)))"
    @assert any(band_mask) "band_mask must have at least one true element"
    @assert sum(abs2.(uωf)) > 0 "field must have nonzero energy"

    E_band = sum(abs2.(uωf[band_mask, :]))
    E_total = sum(abs2.(uωf))
    J = E_band / E_total
    dJ = uωf .* (band_mask .- J) ./ E_total

    # POSTCONDITIONS
    @assert 0 ≤ J ≤ 1 "fractional energy J=$J out of [0,1]"
    @assert all(isfinite, dJ) "gradient contains non-finite values"

    return J, dJ
end

# ─────────────────────────────────────────────────────────────────────────────
# Boundary condition check
# ─────────────────────────────────────────────────────────────────────────────

"""
    check_boundary_conditions(ut_z, sim; threshold=1e-6)

Check that field energy at temporal window edges is negligible.
Returns (is_ok, edge_fraction) where edge_fraction is the fraction of
total energy within the first and last 5% of the time grid.
"""
function check_boundary_conditions(ut_z, sim; threshold=1e-6)
    @assert threshold > 0 "threshold must be positive"

    Nt = sim["Nt"]
    n_edge = max(1, Nt ÷ 20)  # 5% of grid on each side
    E_total = sum(abs2.(ut_z))
    E_edges = sum(abs2.(ut_z[1:n_edge, :])) + sum(abs2.(ut_z[end-n_edge+1:end, :]))
    edge_frac = E_edges / max(E_total, eps())
    return edge_frac < threshold, edge_frac
end

# ─────────────────────────────────────────────────────────────────────────────
# Setup: phase optimization (was `setup_problem` in raman_optimization.jl)
# ─────────────────────────────────────────────────────────────────────────────

"""
    setup_raman_problem(; kwargs...)

Create all objects needed for phase optimization from physical parameters.
Uses `get_disp_fiber_params_user_defined` for direct fiber specification.

Defaults: Nt=2^14, time_window=5.0, β_order=2, P_cont=0.25, betas_user=[-2.6e-26].

Returns (uω0, fiber, sim, band_mask, Δf, raman_threshold).
"""
function setup_raman_problem(;
    λ0 = 1550e-9,
    M = 1,
    Nt = 2^14,
    time_window = 5.0,
    β_order = 2,
    L_fiber = 1.0,
    P_cont = 0.25,
    pulse_fwhm = 185e-15,
    pulse_rep_rate = 80.5e6,
    pulse_shape = "sech_sq",
    raman_threshold = -5.0,
    gamma_user = 0.0013,
    betas_user = [-2.6e-26],
    fR = 0.18
)
    # PRECONDITIONS
    @assert λ0 > 0 "wavelength must be positive, got $λ0"
    @assert M ≥ 1 "need at least 1 mode"
    @assert ispow2(Nt) "Nt must be power of 2, got $Nt"
    @assert time_window > 0 "time_window must be positive"
    @assert L_fiber > 0 "fiber length must be positive, got $L_fiber"
    @assert P_cont > 0 "power must be positive"
    @assert pulse_fwhm > 0 "pulse FWHM must be positive"
    @assert gamma_user > 0 "nonlinear coefficient must be positive"
    @assert length(betas_user) ≥ 1 "need at least β₂"

    tw_rec = recommended_time_window(L_fiber)
    if time_window < tw_rec
        @warn "time_window=$time_window ps may be too small for L=$L_fiber m (recommend ≥ $tw_rec ps)"
    end

    sim = MultiModeNoise.get_disp_sim_params(λ0, M, Nt, time_window, β_order)
    fiber = MultiModeNoise.get_disp_fiber_params_user_defined(
        L_fiber, sim; fR=fR, gamma_user=gamma_user, betas_user=betas_user
    )
    u0_modes = ones(M) / √M
    _, uω0 = MultiModeNoise.get_initial_state(
        u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim
    )

    Δf_fft = fftfreq(Nt, 1 / sim["Δt"])
    Δf = fftshift(Δf_fft)
    band_mask = Δf_fft .< raman_threshold

    @debug "Setup (raman)" L=L_fiber P_cont=P_cont pulse=pulse_shape fwhm_fs=pulse_fwhm*1e15 γ=gamma_user β₂=betas_user[1] raman_bins=sum(band_mask) total_bins=Nt

    return uω0, fiber, sim, band_mask, Δf, raman_threshold
end

# ─────────────────────────────────────────────────────────────────────────────
# Setup: amplitude optimization (was `setup_problem` in amplitude_optimization.jl)
# ─────────────────────────────────────────────────────────────────────────────

"""
    setup_amplitude_problem(; kwargs...)

Create all objects needed for amplitude optimization from physical parameters.

Defaults: Nt=2^13, time_window=10.0, β_order=3, P_cont=0.05,
          betas_user=[-2.6e-26, 1.2e-40].

Returns (uω0, fiber, sim, band_mask, Δf, raman_threshold).
"""
function setup_amplitude_problem(;
    λ0 = 1550e-9,
    M = 1,
    Nt = 2^13,
    time_window = 10.0,
    β_order = 3,
    L_fiber = 1.0,
    P_cont = 0.05,
    pulse_fwhm = 185e-15,
    pulse_rep_rate = 80.5e6,
    pulse_shape = "sech_sq",
    raman_threshold = -5.0,
    gamma_user = 0.0013,
    betas_user = [-2.6e-26, 1.2e-40],
    fR = 0.18
)
    # PRECONDITIONS
    @assert λ0 > 0 "wavelength must be positive, got $λ0"
    @assert M ≥ 1 "need at least 1 mode"
    @assert ispow2(Nt) "Nt must be power of 2, got $Nt"
    @assert time_window > 0 "time_window must be positive"
    @assert L_fiber > 0 "fiber length must be positive, got $L_fiber"
    @assert P_cont > 0 "power must be positive"
    @assert pulse_fwhm > 0 "pulse FWHM must be positive"
    @assert gamma_user > 0 "nonlinear coefficient must be positive"
    @assert length(betas_user) ≥ 1 "need at least β₂"

    tw_rec = recommended_time_window(L_fiber)
    if time_window < tw_rec
        @warn "time_window=$time_window ps may be too small for L=$L_fiber m (recommend ≥ $tw_rec ps)"
    end

    sim = MultiModeNoise.get_disp_sim_params(λ0, M, Nt, time_window, β_order)
    fiber = MultiModeNoise.get_disp_fiber_params_user_defined(
        L_fiber, sim; fR=fR, gamma_user=gamma_user, betas_user=betas_user
    )
    u0_modes = ones(M) / √M
    _, uω0 = MultiModeNoise.get_initial_state(
        u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim
    )

    Δf_fft = fftfreq(Nt, 1 / sim["Δt"])
    Δf = fftshift(Δf_fft)
    band_mask = Δf_fft .< raman_threshold

    # Soliton order for diagnostics
    β2 = betas_user[1]
    T0 = pulse_fwhm / (2 * acosh(sqrt(2)))
    P_peak = P_cont / (pulse_fwhm * pulse_rep_rate)
    N_sol = sqrt(gamma_user * P_peak * T0^2 / abs(β2))

    @debug "Setup (amplitude)" L=L_fiber P_cont=P_cont pulse=pulse_shape fwhm_fs=pulse_fwhm*1e15 γ=gamma_user β₂=betas_user[1] N_soliton=round(N_sol, digits=2) raman_bins=sum(band_mask) total_bins=Nt time_window=time_window tw_recommended=tw_rec

    return uω0, fiber, sim, band_mask, Δf, raman_threshold
end

end # include guard
