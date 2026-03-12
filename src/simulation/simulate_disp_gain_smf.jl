"""
    disp_gain_smf!(dũω, ũω, p, z)

Right-hand side of the ODE governing the evolution of pulses in multimode fibers,
including Kerr and Raman nonlinearities as well as self-steepening, plus a spectral
linear gain term `gω`.

The equation is written in the interaction picture to separate the fast linear
(disperive) and slow nonlinear dynamics.
"""
function disp_gain_smf!(dũω, ũω, p, z)
    selfsteep, Dω, γ, hRω, one_m_fR, attenuator, gain_template, gω, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_p, exp_D_m, uω, ut, v, w, δKt, δKt_cplx, αK, βK, ηKt, hRω_δRω, hR_conv_δR, δRt, αR, βR, ηRt, ηt = p
    @. exp_D_p = cis(Dω * z)
    @. exp_D_m = cis(-Dω * z)

    @. uω = exp_D_p * ũω  #  dispersion applied

    compute_gain!(gω, uω, gain_template)  # update gain profile based on current uω

    fft_plan_M! * uω
    @. ut = attenuator * uω
    @. v = real(ut)
    @. w = imag(ut)

    @tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])
    @tullio αK[t, i] = δKt[t, i, j] * v[t, j]
    @tullio βK[t, i] = δKt[t, i, j] * w[t, j]
    @. ηKt = αK + 1im * βK
    @. ηKt *= one_m_fR

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

    # applied gain as well 
    @. dũω = 1im * exp_D_m * ηt + 0.5 * gω * ũω
end

"""
    compute_gain!(gω, uω, gain_template)

Placeholder gain model.

Currently returns a constant (or provided template) gain for every frequency and mode.
Replace this function body with a spectrum-dependent model, e.g. `compute_gain(uω)`.
"""
function compute_gain!(gω, uω, gain_template)
    if gain_template isa Number
        @. gω = gain_template
    else
        @. gω = gain_template
    end
    return nothing
end


"""
    get_p_disp_gain_smf(ωs, ω0, Dω, γ, hRω, one_m_fR, gω, Nt, M, attenuator)

Create the tuple of parameters necessary to call `disp_gain_smf!`.
"""
function get_p_disp_gain_smf(ωs, ω0, Dω, γ, hRω, one_m_fR, gain_template, Nt, M, attenuator)
    selfsteep = fftshift(ωs / ω0)
    fft_plan_M! = plan_fft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.MEASURE)
    ifft_plan_M! = plan_ifft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.MEASURE)
    fft_plan_MM! = plan_fft!(zeros(ComplexF64, Nt, M, M), 1; flags=FFTW.MEASURE)
    ifft_plan_MM! = plan_ifft!(zeros(ComplexF64, Nt, M, M), 1; flags=FFTW.MEASURE)
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

    p = (selfsteep, Dω, γ, hRω, one_m_fR, attenuator, gain_template, gω, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_p, exp_D_m, uω, ut, v, w, δKt, δKt_cplx, αK, βK, ηKt, hRω_δRω, hR_conv_δR, δRt, αR, βR, ηRt, ηt)
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
function solve_disp_gain_smf(uω0, fiber, sim)
    # gω = haskey(fiber, "gω") ? fiber["gω"] : zeros(sim["Nt"], sim["M"])
    gain_template = haskey(fiber, "gω") && !isnothing(fiber["gω"]) ? fiber["gω"] : 0.0

    p_disp_gain_smf = get_p_disp_gain_smf(sim["ωs"], sim["ω0"], fiber["Dω"], fiber["γ"], fiber["hRω"], fiber["one_m_fR"],
        gain_template, sim["Nt"], sim["M"], sim["attenuator"])
    prob_disp_gain_smf = ODEProblem(disp_gain_smf!, uω0, (0, fiber["L"]), p_disp_gain_smf)

    if isnothing(fiber["zsave"])
        sol_disp_gain_smf = solve(prob_disp_gain_smf, Tsit5(), reltol=1e-5)

        return Dict("ode_sol" => sol_disp_gain_smf)
    else
        sol_disp_gain_smf = solve(prob_disp_gain_smf, Tsit5(), reltol=1e-5, saveat=fiber["zsave"])

        uω_z = zeros(ComplexF64, length(fiber["zsave"]), sim["Nt"], sim["M"])
        ut_z = zeros(ComplexF64, length(fiber["zsave"]), sim["Nt"], sim["M"])

        for i in 1:length(fiber["zsave"])
            uω_z[i, :, :] = cis.(fiber["Dω"] * fiber["zsave"][i]) .* sol_disp_gain_smf(fiber["zsave"][i])
            ut_z[i, :, :] = fft(uω_z[i, :, :], 1)
        end

        return Dict("ode_sol" => sol_disp_gain_smf, "uω_z" => uω_z, "ut_z" => ut_z)
    end
end