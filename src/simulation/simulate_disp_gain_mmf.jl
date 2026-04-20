"""
    disp_gain_smf!(dũ, ũ, p, z)

ODE right-hand side for fiber propagation with pump-dependent gain (co-propagating
pump model). The state vector ũ = [Pp; ũω] concatenates the pump power Pp (scalar)
with the signal field ũω (shape Nt×M) in the interaction picture.

Extends `disp_mmf!` with:
- Pump evolution: dPp/dz = gP · Pp (exponential pump growth/depletion)
- Signal gain: 0.5·gω·ũω added to the nonlinear signal equation

The gain profile gω and pump gain gP are computed at each z-step by `compute_gain`,
which dispatches on the gain model type (constant or YDFA rate equations).

# Arguments
- `dũ`: output derivative, length 1+Nt*M (first element is pump, rest is signal)
- `ũ`: current state [Pp; ũω]
- `p`: parameter tuple from `get_p_disp_gain_smf` (MMF version)
- `z`: propagation position [m]
"""
function disp_gain_smf!(dũ, ũ, p, z)

    selfsteep, Dω, γ, hRω, one_m_fR, attenuator, pGain, gω, gP, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_p, exp_D_m, uω, ut, v, w, δKt, δKt_cplx, αK, βK, ηKt, hRω_δRω, hR_conv_δR, δRt, αR, βR, ηRt, ηt = p

    Pp = ũ[1]  # Pump power (scalar, co-propagating)
    ũω = ũ[2:end]  # Signal field in interaction picture

    @. exp_D_p = cis(Dω * z)
    @. exp_D_m = cis(-Dω * z)

    @. uω = exp_D_p * ũω

    # Update gain profile based on current field and pump power
    gω, gP = compute_gain(uω, pGain, Pp)

    fft_plan_M! * uω
    @. ut = attenuator * uω
    @. v = real(ut)
    @. w = imag(ut)

    # Kerr nonlinearity
    @tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])
    @tullio αK[t, i] = δKt[t, i, j] * v[t, j]
    @tullio βK[t, i] = δKt[t, i, j] * w[t, j]
    @. ηKt = αK + 1im * βK
    @. ηKt *= one_m_fR

    # Raman nonlinearity
    @. δKt_cplx = ComplexF64(δKt, 0.0)
    fft_plan_MM! * δKt_cplx
    @. hRω_δRω = hRω * δKt_cplx
    ifft_plan_MM! * hRω_δRω
    fftshift!(hR_conv_δR, hRω_δRω, 1)
    @. δRt = real(hR_conv_δR)
    @tullio αR[t, i] = δRt[t, i, j] * v[t, j]
    @tullio βR[t, i] = δRt[t, i, j] * w[t, j]
    @. ηRt = αR + 1im * βR

    @. ηt = ηKt + ηRt
    ifft_plan_M! * ηt
    ηt .*= selfsteep

    # Pump equation and signal equation with gain
    dũ[1] = gP * Pp  # Pump: exponential growth/depletion
    @. dũ[2:end] = 1im * exp_D_m * ηt + 0.5 * gω * ũω  # Signal: nonlinearity + gain

end

"""
    compute_gain(uω, pGain::Number, Pp) -> (gω, gP)

Constant gain model (placeholder): returns uniform gain `pGain` at all frequencies
and gP=-1 as a placeholder pump gain. Used when `fiber["gain_parameters"]` is a number.
"""
function compute_gain(uω, pGain::Number, Pp)
    gω = fill(pGain, size(uω))  # Linear Gain
    gP = -1  # Placeholder for pump power
    return gω, gP
end

"""
    compute_gain(uω, pGain::YDFAParams, Pp) -> (gω, gP)

YDFA gain model: computes spectral gain from Yb-doped fiber rate equations.
Converts the FFT-convention field to physical PSD [W/Hz], calls `calculate_gain_YDFA`
for the population inversion and spectral gain, then reshapes back to FFT order
via `ifftshift`.

# Returns
- `gω`: spectral gain profile [1/m], shape matching uω
- `gP`: pump power gain [1/m] (negative = pump absorption)
"""
function compute_gain(uω, pGain::YDFAParams, Pp)

    Ps_vec = psd_from_uω(uω, pGain)  # W/Hz on fs grid
    gω_vec, gP = calculate_gain_YDFA(Pp, Ps_vec, pGain)

    gω_shifted = ifftshift(gω_vec)  # Shift back to FFT convention (DC at index 1)

    gω = reshape(gω_shifted, size(uω))

    return gω, gP
end


"""
    get_p_disp_gain_smf(ωs, ω0, Dω, γ, hRω, one_m_fR, pGain, Nt, M, attenuator) -> Tuple

Pre-allocate parameters for the pump+signal `disp_gain_smf!` ODE. Extends the
standard `get_p_disp_mmf` tuple with gain model `pGain`, gain work array `gω`,
and pump gain scalar `gP`.

# Arguments
- `ωs`: angular frequency grid [rad/s], length Nt
- `ω0`: center angular frequency [rad/s]
- `Dω`: dispersion operator, shape (Nt, M)
- `γ`: nonlinearity tensor, shape (M, M, M, M) [W⁻¹ m⁻¹]
- `hRω`: Raman response in frequency domain, shape (Nt, M, M)
- `one_m_fR`: (1 - fR), fractional Kerr weight
- `pGain`: gain model -- a `Number` for constant gain or `YDFAParams` for rate-equation gain
- `Nt`: number of temporal grid points
- `M`: number of spatial modes
- `attenuator`: time-domain window to suppress boundary artifacts, shape (Nt, M)
"""
function get_p_disp_gain_smf(ωs, ω0, Dω, γ, hRω, one_m_fR, pGain, Nt, M, attenuator)
    selfsteep = fftshift(ωs / ω0)
    fft_plan_M! = plan_fft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.ESTIMATE)
    ifft_plan_M! = plan_ifft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.ESTIMATE)
    fft_plan_MM! = plan_fft!(zeros(ComplexF64, Nt, M, M), 1; flags=FFTW.ESTIMATE)
    ifft_plan_MM! = plan_ifft!(zeros(ComplexF64, Nt, M, M), 1; flags=FFTW.ESTIMATE)
    exp_D_p = zeros(ComplexF64, Nt, M)
    exp_D_m = zeros(ComplexF64, Nt, M)
    uω = zeros(ComplexF64, Nt, M)
    ut = zeros(ComplexF64, Nt, M)
    v = zeros(Nt, M)
    w = zeros(Nt, M)
    δKt = zeros(Nt, M, M)
    δKt_cplx = zeros(ComplexF64, Nt, M, M)
    αK = zeros(Nt, M)
    βK = zeros(Nt, M)
    ηKt = zeros(ComplexF64, Nt, M)
    hRω_δRω = zeros(ComplexF64, Nt, M, M)
    hR_conv_δR = zeros(ComplexF64, Nt, M, M)
    δRt = zeros(Nt, M, M)
    αR = zeros(Nt, M)
    βR = zeros(Nt, M)
    ηRt = zeros(ComplexF64, Nt, M)
    ηt = zeros(ComplexF64, Nt, M)
    gω = zeros(Nt, M)
    gP = 0.0

    p = (selfsteep, Dω, γ, hRω, one_m_fR, attenuator, pGain, gω, gP, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_p, exp_D_m, uω, ut, v, w, δKt, δKt_cplx, αK, βK, ηKt, hRω_δRω, hR_conv_δR, δRt, αR, βR, ηRt, ηt)
    return p
end

"""
    get_initial_state_gain_smf(u0_modes, P_cont, fwhm, rep_rate, pulse_form, sim) -> (ut0, uω0)

Create the initial signal pulse for gain-enabled propagation. Identical to
`get_initial_state` in `simulate_disp_mmf.jl`.

# Arguments
- `u0_modes`: relative mode amplitudes, length M
- `P_cont`: continuous-wave (average) power [W]
- `fwhm`: pulse full-width at half-maximum [s]
- `rep_rate`: laser repetition rate [Hz]
- `pulse_form`: `"gauss"` or `"sech_sq"`
- `sim`: simulation parameter dict (uses `"M"`, `"Nt"`, `"ts"`)

# Returns
- `ut0`: initial field in time domain, shape (Nt, M)
- `uω0`: initial field in frequency domain (via `ifft`), shape (Nt, M)
"""
function get_initial_state_gain_smf(u0_modes, P_cont, fwhm, rep_rate, pulse_form, sim)
    M, Nt, ts = sim["M"], sim["Nt"], sim["ts"]
    u0_norm = zeros(ComplexF64, Nt, M)
    if pulse_form == "gauss"
        σ = fwhm / 1.66511
        u0_norm .= exp.(-ts .^ 2 / 2 / σ^2)
        P_peak = 0.939437 * P_cont / fwhm / rep_rate
    elseif pulse_form == "sech_sq"
        τ = fwhm / 1.7627
        u0_norm .= sech.(-ts / τ)
        P_peak = 0.881374 * P_cont / fwhm / rep_rate
    else
        throw(ArgumentError("unsupported pulse_form=$(repr(pulse_form)); expected \"gauss\" or \"sech_sq\""))
    end
    u0_norm .*= u0_modes'
    u0_norm /= √maximum(sum(abs2.(u0_norm), dims=2))
    ut0 = u0_norm * √P_peak
    uω0 = ifft(ut0, 1)
    return ut0, uω0
end

"""
    solve_disp_gain_smf(uω0, fiber, sim; pump_power=0.0) -> Dict

Solve pump+signal propagation from z=0 to z=L. Enforces M=1 (single-mode only in
this version — the pump coupling model assumes a single signal mode).

# Arguments
- `uω0`: initial signal field, shape (Nt, 1)
- `fiber`: fiber parameter dict (uses `fiber["gain_parameters"]` for gain model)
- `sim`: simulation parameter dict
- `pump_power`: initial co-propagating pump power [W] (default 0.0)

# Returns
Dict with `"ode_sol"`, and optionally `"uω_z"`, `"ut_z"`, `"Ppz"` (pump power along z).
"""
function solve_disp_gain_smf(uω0, fiber, sim; pump_power=0.0)

    if sim["M"] != 1
        throw(ArgumentError("disp_gain_smf is single mode only, requires M = 1 (got M = $(sim["M"]))"))
    end

    pGain = haskey(fiber, "gain_parameters") ? fiber["gain_parameters"] : 0.0

    p_disp_gain_smf = get_p_disp_gain_smf(sim["ωs"], sim["ω0"], fiber["Dω"], fiber["γ"], fiber["hRω"], fiber["one_m_fR"],
        pGain, sim["Nt"], sim["M"], sim["attenuator"])

    Pp0 = pump_power
    u0 = vcat(Pp0, uω0)

    prob_disp_gain_smf = ODEProblem(disp_gain_smf!, u0, (0, fiber["L"]), p_disp_gain_smf)

    if isnothing(fiber["zsave"])
        sol_disp_gain_smf = solve(prob_disp_gain_smf, Tsit5(), reltol=1e-5)

        return Dict("ode_sol" => sol_disp_gain_smf)
    else
        sol_disp_gain_smf = solve(prob_disp_gain_smf, Tsit5(), reltol=1e-5, saveat=fiber["zsave"])

        uω_z = zeros(ComplexF64, length(fiber["zsave"]), sim["Nt"], sim["M"])
        ut_z = zeros(ComplexF64, length(fiber["zsave"]), sim["Nt"], sim["M"])
        Ppz = zeros(length(fiber["zsave"]), sim["M"])

        for i in 1:length(fiber["zsave"])
            uω_z[i, :, :] = cis.(fiber["Dω"] .* fiber["zsave"][i]) .* sol_disp_gain_smf(fiber["zsave"][i])[2:end]
            ut_z[i, :, :] = fft(uω_z[i, :, :], 1)
            Ppz[i, :] .= sol_disp_gain_smf(fiber["zsave"][i])[1]
        end

        return Dict("ode_sol" => sol_disp_gain_smf, "uω_z" => uω_z, "ut_z" => ut_z, "Ppz" => Ppz)
    end
end
