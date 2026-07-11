"""
    disp_mmf!(dũω, ũω, p, z)

ODE right-hand side for nonlinear pulse propagation in multimode fibers, formulated
in the **interaction picture** to separate fast linear dispersion from slow nonlinear
dynamics. The ODE solver (Tsit5) advances this equation from z=0 to z=L.

Implements the generalized multimode nonlinear Schrodinger equation (GMMNLSE):

    dũ/dz = i · exp(-iDz) · [selfsteep ⊙ IFFT((1-fR)·η_Kerr + η_Raman)]

The computation per ODE step proceeds as:
1. Transform to lab frame: u(ω) = exp(iDz) · ũ(ω)
2. FFT to the periodic time-domain grid
3. **Kerr**: δ_K[t,i,j] = Σ_{kl} γ_{ijkl}·(v_k·v_l + w_k·w_l), then η_K = (1-fR)·δ_K·u
4. **Raman**: convolve δ_K with h_R(ω) in frequency domain, contract with u in time domain
5. Sum Kerr + Raman, IFFT back, apply self-steepening (ω/ω₀), transform to interaction picture

# Arguments
- `dũω`: output derivative array, shape (Nt, M), mutated in-place
- `ũω`: current state in interaction picture, shape (Nt, M)
- `p`: pre-allocated parameter tuple from `get_p_disp_mmf`
- `z`: current propagation position [m]
"""
function disp_mmf!(dũω, ũω, p, z)
    selfsteep, Dω, γ, hRω, one_m_fR, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_p, exp_D_m, uω, v, w, δKt, δKt_cplx, αK, βK, ηKt, hRω_δRω, hR_conv_δR, δRt, αR, βR, ηRt, ηt = p

    @. exp_D_p = cis(Dω * z)
    @. exp_D_m = cis(-Dω * z)

    @. uω = exp_D_p * ũω

    fft_plan_M! * uω
    @. v = real(uω)
    @. w = imag(uω)

    # Kerr nonlinearity: contract γ tensor with field real/imag parts
    @tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])
    @tullio αK[t, i] = δKt[t, i, j] * v[t, j]
    @tullio βK[t, i] = δKt[t, i, j] * w[t, j]
    @. ηKt = αK + 1im * βK
    @. ηKt *= one_m_fR

    # Raman nonlinearity: convolution h_R * δ_K in frequency domain
    @. δKt_cplx = ComplexF64(δKt, 0.0)
    fft_plan_MM! * δKt_cplx
    @. hRω_δRω = hRω * δKt_cplx
    ifft_plan_MM! * hRω_δRω
    fftshift!(hR_conv_δR, hRω_δRω, 1)
    @. δRt = real(hR_conv_δR)
    @tullio αR[t, i] = δRt[t, i, j] * v[t, j]
    @tullio βR[t, i] = δRt[t, i, j] * w[t, j]
    @. ηRt = αR + 1im * βR

    # Combine and transform back to interaction picture
    @. ηt = ηKt + ηRt
    ifft_plan_M! * ηt
    ηt .*= selfsteep
    @. dũω = 1im * exp_D_m * ηt
end

function _validate_real_gamma_storage(γ)
    eltype(γ) <: Real || throw(ArgumentError(
        "gamma tensor must use real-valued storage"))
    all(isfinite, γ) || throw(ArgumentError("gamma tensor must be finite"))
    return nothing
end

"""
    get_p_disp_mmf(ωs, ω0, Dω, γ, hRω, one_m_fR, Nt, M) -> Tuple

Pre-allocate all working arrays and FFTW plans for `disp_mmf!`. Returns a single
tuple `p` passed to the ODE solver as the parameter argument. Pre-allocation avoids
garbage collection pressure during integration — critical for performance since the
ODE solver calls `disp_mmf!` hundreds of times per propagation.

# Arguments
- `ωs`: angular frequency grid [rad/ps], length Nt
- `ω0`: center angular frequency [rad/ps]
- `Dω`: dispersion operator, shape (Nt, M) [rad/m]
- `γ`: nonlinear coefficient tensor, shape (M, M, M, M) [W⁻¹m⁻¹]
- `hRω`: Raman response in frequency domain
- `one_m_fR`: (1 - fR), Kerr fraction of the nonlinearity
- `Nt`: number of temporal grid points
- `M`: number of spatial modes
"""
function get_p_disp_mmf(ωs, ω0, Dω, γ, hRω, one_m_fR, Nt, M)
    _validate_real_gamma_storage(γ)
    selfsteep = fftshift(ωs / ω0)
    fft_plan_M! = plan_fft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.ESTIMATE)
    ifft_plan_M! = plan_ifft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.ESTIMATE)
    fft_plan_MM! = plan_fft!(zeros(ComplexF64, Nt, M, M), 1; flags=FFTW.ESTIMATE)
    ifft_plan_MM! = plan_ifft!(zeros(ComplexF64, Nt, M, M), 1; flags=FFTW.ESTIMATE)
    exp_D_p = zeros(ComplexF64, Nt, M)
    exp_D_m = zeros(ComplexF64, Nt, M)
    uω = zeros(ComplexF64, Nt, M)
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

    p = (selfsteep, Dω, γ, hRω, one_m_fR, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_p, exp_D_m, uω, v, w, δKt, δKt_cplx, αK, βK, ηKt, hRω_δRω, hR_conv_δR, δRt, αR, βR, ηRt, ηt)
    return p
end

"""
    get_initial_state(u0_modes, P_cont, fwhm, rep_rate, pulse_form, sim) -> (ut0, uω0)

Generate the initial pulse field in both time and frequency domains.

# Arguments
- `u0_modes`: mode excitation vector, length M (normalized amplitudes per mode)
- `P_cont`: continuous (average) power [W]
- `fwhm`: pulse full-width at half-maximum [s]
- `rep_rate`: pulse repetition rate [Hz]
- `pulse_form`: `"gauss"` or `"sech_sq"`
- `sim`: simulation parameter dict from `get_disp_sim_params`

# Pulse shapes and peak power conversion
- **Gaussian**: P_peak = 0.939437 · P_cont / (FWHM · rep_rate), σ = FWHM / 1.66511
- **sech²**: P_peak = 0.881374 · P_cont / (FWHM · rep_rate), τ = FWHM / 1.7627

The numerical factors convert average power to peak power accounting for the
pulse shape integral: P_peak = P_avg / (duty_cycle · shape_factor).

# Returns
- `ut0`: time-domain field [√W], shape (Nt, M)
- `uω0`: frequency-domain field (via IFFT along time axis), shape (Nt, M)
"""
function get_initial_state(u0_modes, P_cont, fwhm, rep_rate, pulse_form, sim)
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
    solve_disp_mmf(uω0, fiber, sim) -> Dict

Solve the forward nonlinear propagation ODE from z=0 to z=L using Tsit5 (5th-order
Runge-Kutta, reltol=1e-8).

# Arguments
- `uω0`: initial field in frequency domain, shape (Nt, M)
- `fiber`: fiber parameter dict (keys: `"L"`, `"Dω"`, `"γ"`, `"hRω"`, etc.)
- `sim`: simulation parameter dict

# Returns
Dict with key `"ode_sol"` (the DifferentialEquations solution object, which supports
continuous interpolation via `sol(z)` for arbitrary z in [0, L]).

If `fiber["zsave"]` is not nothing, also returns:
- `"uω_z"`: field in lab frame at saved z positions, shape (Nz, Nt, M)
- `"ut_z"`: time-domain field at saved z positions, shape (Nz, Nt, M)

The lab-frame field is recovered by undoing the interaction picture transform:
  u(ω,z) = exp(iD(ω)z) · ũ(ω,z)
"""
function solve_disp_mmf(uω0, fiber, sim)
    p_disp_mmf = get_p_disp_mmf(sim["ωs"], sim["ω0"], fiber["Dω"], fiber["γ"], fiber["hRω"], fiber["one_m_fR"], sim["Nt"], sim["M"])
    prob_disp_mmf = ODEProblem(disp_mmf!, uω0, (0, fiber["L"]), p_disp_mmf)
    reltol = Float64(get(fiber, "reltol", 1e-8))
    abstol = Float64(get(fiber, "abstol", 1e-6))

    if isnothing(fiber["zsave"])
        sol_disp_mmf = solve(prob_disp_mmf, Tsit5(), reltol=reltol, abstol=abstol)

        return Dict("ode_sol" => sol_disp_mmf)
    else
        sol_disp_mmf = solve(prob_disp_mmf, Tsit5(), reltol=reltol, abstol=abstol,
            saveat=fiber["zsave"])

        uω_z = zeros(ComplexF64, length(fiber["zsave"]), sim["Nt"], sim["M"])
        ut_z = zeros(ComplexF64, length(fiber["zsave"]), sim["Nt"], sim["M"])

        for i in 1:length(fiber["zsave"])
            uω_z[i, :, :] = cis.(fiber["Dω"] * fiber["zsave"][i]) .* sol_disp_mmf(fiber["zsave"][i])
            ut_z[i, :, :] = fft(uω_z[i, :, :], 1)
        end

        return Dict("ode_sol" => sol_disp_mmf, "uω_z" => uω_z, "ut_z" => ut_z)
    end
end
