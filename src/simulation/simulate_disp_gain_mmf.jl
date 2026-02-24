mutable struct DispGainSMFParams{
    Tself,TD,Tγ,ThRω,Tone_m_fR,Tatt,Tgm,Tgω,TgP,
    TF1,TF2,TF3,TF4,
    TexpDp,TexpDm,Tuω,Tut,Tv,Tw,
    TδKt,TδKt_cplx,TαK,TβK,TηKt,
    ThRω_δRω,ThR_conv_δR,TδRt,TαR,TβR,TηRt,Tηt
}
    selfsteep::Tself
    Dω::TD
    γ::Tγ
    hRω::ThRω
    one_m_fR::Tone_m_fR
    attenuator::Tatt
    pGain::Tgm
    gω::Tgω
    gP::TgP
    fft_plan_M!::TF1
    ifft_plan_M!::TF2
    fft_plan_MM!::TF3
    ifft_plan_MM!::TF4
    exp_D_p::TexpDp
    exp_D_m::TexpDm
    uω::Tuω
    ut::Tut
    v::Tv
    w::Tw
    δKt::TδKt
    δKt_cplx::TδKt_cplx
    αK::TαK
    βK::TβK
    ηKt::TηKt
    hRω_δRω::ThRω_δRω
    hR_conv_δR::ThR_conv_δR
    δRt::TδRt
    αR::TαR
    βR::TβR
    ηRt::TηRt
    ηt::Tηt
end


"""
    disp_gain_smf!(dũω, ũω, p, z)

Right-hand side of the ODE governing the evolution of pulses in multimode fibers,
including Kerr and Raman nonlinearities as well as self-steepening, plus a spectral
linear gain term `gω`.

The equation is written in the interaction picture to separate the fast linear
(disperive) and slow nonlinear dynamics.
"""
function disp_gain_smf!(dũ, ũ, p, z)

    Pp = ũ[1]  # Pump
    ũω = ũ[2:end]  # Signal modes

    @. p.exp_D_p = exp(1im * p.Dω * z)
    @. p.exp_D_m = exp(-1im * p.Dω * z)

    @. p.uω = p.exp_D_p * ũω  #  dispersion applied

    p.gω, p.gP = compute_gain(p.uω, p.pGain)  # gω is updated in place, gP is returned since float

    p.fft_plan_M! * p.uω
    @. p.ut = p.attenuator * p.uω
    @. p.v = real(p.ut)
    @. p.w = imag(p.ut)

    @tullio p.δKt[t, i, j] = p.γ[i, j, k, l] * (p.v[t, k] * p.v[t, l] + p.w[t, k] * p.w[t, l])
    @tullio p.αK[t, i] = p.δKt[t, i, j] * p.v[t, j]
    @tullio p.βK[t, i] = p.δKt[t, i, j] * p.w[t, j]
    @. p.ηKt = p.αK + 1im * p.βK
    @. p.ηKt *= p.one_m_fR

    @. p.δKt_cplx = ComplexF64(p.δKt, 0.0)
    p.fft_plan_MM! * p.δKt_cplx
    @. p.hRω_δRω = p.hRω * p.δKt_cplx
    p.ifft_plan_MM! * p.hRω_δRω
    fftshift!(p.hR_conv_δR, p.hRω_δRω, 1)
    @. p.δRt = real(p.hR_conv_δR)
    @tullio p.αR[t, i] = p.δRt[t, i, j] * p.v[t, j]
    @tullio p.βR[t, i] = p.δRt[t, i, j] * p.w[t, j]
    @. p.ηRt = p.αR + 1im * p.βR

    @. p.ηt = p.ηKt + p.ηRt
    p.ifft_plan_M! * p.ηt
    p.ηt .*= p.selfsteep

    # @. dũω = 1im * p.exp_D_m * p.ηt + 0.5 * p.gω * ũω

    dũ[1] = p.gP * Pp  # Pump is undepleted in this model
    @. dũ[2:end] = 1im * p.exp_D_m * p.ηt + 0.5 * p.gω * ũω

end

"""
    compute_gain!(gω, uω, pGain)

Placeholder gain model.

Currently returns a constant (or provided template) gain for every frequency and mode.
Replace this function body with a spectrum-dependent model, e.g. `compute_gain(uω)`.
"""
function compute_gain(uω, pGain::Number)
    gω = fill(pGain, size(uω))  # Linear Gain
    gP = -1  # Placeholder for pump power
    return gω, gP
end

function compute_gain(uω, pGain::YDFAParams)
    gω = fill(5.0, size(uω))  # temporary
    gP = -1  # Placeholder for pump power
    return gω, gP
end


"""
    get_p_disp_gain_smf(ωs, ω0, Dω, γ, hRω, one_m_fR, gω, Nt, M, attenuator)

Create the tuple of parameters necessary to call `disp_gain_smf!`.
"""
function get_p_disp_gain_smf(ωs, ω0, Dω, γ, hRω, one_m_fR, pGain, Nt, M, attenuator)
    selfsteep = fftshift(ωs / ω0)
    fft_plan_M! = plan_fft!(zeros(ComplexF64, Nt, M), 1)
    ifft_plan_M! = plan_ifft!(zeros(ComplexF64, Nt, M), 1)
    fft_plan_MM! = plan_fft!(zeros(ComplexF64, Nt, M, M), 1)
    ifft_plan_MM! = plan_ifft!(zeros(ComplexF64, Nt, M, M), 1)
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

    p = DispGainSMFParams(selfsteep, Dω, γ, hRω, one_m_fR, attenuator, pGain, gω, gP, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_p, exp_D_m, uω, ut, v, w, δKt, δKt_cplx, αK, βK, ηKt, hRω_δRω, hR_conv_δR, δRt, αR, βR, ηRt, ηt)
    return p
end

"""
    get_initial_state_gain_smf(u0_modes, P_cont, fwhm, rep_rate, pulse_form, sim)

Create the initial pulse for gain-enabled propagation.
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
    end
    u0_norm .*= u0_modes'
    u0_norm /= √maximum(sum(abs2.(u0_norm), dims=2))
    ut0 = u0_norm * √P_peak
    uω0 = ifft(ut0, 1)
    return ut0, uω0
end

"""
    solve_disp_gain_smf(uω0, fiber, sim)

Solve the gain-augmented dispersive smf propagation problem.

If `fiber["gω"]` is not provided, a zero gain profile is used by default.
Gain is applied as exp(±0.5*gω*z), separate from Dω.
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
            uω_z[i, :, :] = exp.(1im .* fiber["Dω"] .* fiber["zsave"][i]) .* sol_disp_gain_smf(fiber["zsave"][i])[2:end]
            ut_z[i, :, :] = fft(uω_z[i, :, :], 1)
            Ppz[i, :] .= sol_disp_gain_smf(fiber["zsave"][i])[1]
        end

        return Dict("ode_sol" => sol_disp_gain_smf, "uω_z" => uω_z, "ut_z" => ut_z, "Ppz" => Ppz)
    end
end