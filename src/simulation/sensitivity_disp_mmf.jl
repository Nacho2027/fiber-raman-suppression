function adjoint_disp_mmf!(dλ̃ω, λ̃ω, p, z)
    """
        disp_mmf!(dũω, ũω, p, z)

    Right-hand side of the ODE governing the evolution of the adjoint field.

    # Arguments
    - `dλ̃ω`: 
    - `λ̃ω`: 
    - `p`: 
    - `z`:

    
    """
    p_params, p_fft, p_prealloc, p_calc_δs, p_γ_a_b = p
    ũω, τω, Dω, hRω, hRωc, γ, one_m_fR, fR, Nt, σ1, σ2 = p_params
    fft_plan_M, ifft_plan_M, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM! = p_fft
    exp_D_p, exp_D_m, λω, λt, λωc, ũω_z, uω, ut, utc, δK1t, δK2t, δK1t_cplx, hRω_δRω, hR_conv_δR, δR1t, δKR1t, sum_res, γ_λt_utc, γ_λt_ut_ut, λ_∂fKR1c∂uc, λc_∂fK∂uc, λ_∂fR2c∂uc, λc_∂fR∂uc = p_prealloc

    @. exp_D_p = exp(1im*Dω*z)
    @. exp_D_m = exp(-1im*Dω*z)

    @. λω = exp_D_p * λ̃ω
    λω .*= τω
    mul!(λt, fft_plan_M, λω)
    @. λωc = conj(λω)
    ifft_plan_M! * λωc

    ũω_z .= ũω(z)
    @. uω = exp_D_p * ũω_z
    mul!(ut, fft_plan_M, uω)
    @. utc = conj(ut)
    ifft_plan_M! * uω

    calc_δs!(δK1t, δK2t, ut, p_calc_δs)
    @. δK1t_cplx = ComplexF64(δK1t, 0.0)
    fft_plan_MM! * δK1t_cplx
    @. hRω_δRω = hRω * δK1t_cplx
    ifft_plan_MM! * hRω_δRω
    fftshift!(hR_conv_δR, hRω_δRω, 1)
    @. δR1t = real(hR_conv_δR)
    @tullio δKR1t[t,i,j] = 2 * one_m_fR * δK1t[t,i,j] + δR1t[t,i,j]

    calc_λ_∂fKR1c∂uc!(λ_∂fKR1c∂uc, λt, δKR1t, ifft_plan_M!, exp_D_m, sum_res)
    calc_λc_∂fK∂uc!(λc_∂fK∂uc, λωc, δK2t, ifft_plan_M!, exp_D_m, sum_res, Nt)
    calc_λ_∂fR2c∂uc!(λ_∂fR2c∂uc, λt, utc, uω, γ, hRωc, σ1, fft_plan_M!, fft_plan_MM!, exp_D_m, γ_λt_utc, γ_λt_ut_ut, Nt, p_γ_a_b)
    calc_λc_∂fR∂uc!(λc_∂fR∂uc, λωc, ut, γ, hRω, σ1, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_m, γ_λt_utc, γ_λt_ut_ut, Nt, 
        p_γ_a_b)

    @. dλ̃ω = λ_∂fKR1c∂uc + one_m_fR * λc_∂fK∂uc + λ_∂fR2c∂uc + λc_∂fR∂uc
end

### Helper functions to organize adjoint_disp_mmf! and make it more efficient

function calc_λ_∂fR2c∂uc!(dλω, λt, utc, ifft_uω, γ, hωc, σ, fft_plan_M!, fft_plan_MM!, exp_D_m, γ_λt_utc, γ_λt_ut_ut, Nt, p_γ_a_b)
    calc_γ_a_b!(γ_λt_utc, λt, utc, γ, p_γ_a_b)
    fft_plan_MM! * γ_λt_utc
    @. γ_λt_utc *= hωc * σ
    fft_plan_MM! * γ_λt_utc
    @tullio γ_λt_ut_ut[t,i] = γ_λt_utc[t,i,j] * ifft_uω[t,j]
    fft_plan_M! * γ_λt_ut_ut
    @. dλω = 1im / Nt * exp_D_m * γ_λt_ut_ut
end

function calc_λc_∂fR∂uc!(dλω, ifft_λωc, ut, γ, hω, σ, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_m, γ_ifftλωc_ut, 
        γ_ifftλωc_ut_ut, Nt, p_γ_a_b)
    calc_γ_a_b!(γ_ifftλωc_ut, ifft_λωc, ut, γ, p_γ_a_b)
    ifft_plan_MM! * γ_ifftλωc_ut
    @. γ_ifftλωc_ut *= hω * σ
    fft_plan_MM! * γ_ifftλωc_ut
    @tullio γ_ifftλωc_ut_ut[t,i] = γ_ifftλωc_ut[t,i,j] * ut[t,j]
    ifft_plan_M! * γ_ifftλωc_ut_ut
    @. dλω = -1im * Nt * exp_D_m * γ_ifftλωc_ut_ut
end

function calc_λ_∂fKR1c∂uc!(dλω, λt, δ, ifft_plan!, exp_D_m, sum_res)
    @tullio sum_res[t,j] = λt[t,i] * δ[t,i,j]
    ifft_plan! * sum_res
    @. dλω = 1im * exp_D_m * sum_res
end

function calc_λc_∂fK∂uc!(dλω, ifft_λωc, δ, ifft_plan!, exp_D_m, sum_res, Nt)
    @tullio sum_res[t,j] = ifft_λωc[t,i] * δ[t,i,j]
    ifft_plan! * sum_res
    @. dλω = -1im * Nt * exp_D_m * sum_res
end

function calc_γ_a_b!(γ_a_b, a, b, γ, p)
    a_re, a_im, b_re, b_im, a_b_re, a_b_im, γ_a_b_re, γ_a_b_im = p
    
    @. a_re = real(a)
    @. a_im = imag(a)
    @. b_re = real(b)
    @. b_im = imag(b)
    
    @tullio a_b_re[t,i,j] = a_re[t,i] * b_re[t,j] - a_im[t,i] * b_im[t,j]
    @tullio a_b_im[t,i,j] = a_re[t,i] * b_im[t,j] + a_im[t,i] * b_re[t,j]
    
    @tullio γ_a_b_re[t,i,j] = a_b_re[t,l,k] * γ[l,k,i,j]
    @tullio γ_a_b_im[t,i,j] = a_b_im[t,l,k] * γ[l,k,i,j]

    @. γ_a_b = γ_a_b_re + 1im*γ_a_b_im
end

function calc_δs!(δ_1, δ_2, u_z, p)
    v_z, w_z, abs2_u_z_re, sq_u_z_re, sq_u_z_im, δ_1_, δ_2_re, δ_2_im, γ = p

    @. v_z = real(u_z)
    @. w_z = imag(u_z)

    @tullio abs2_u_z_re[t,i,j] = v_z[t,i] * v_z[t,j] + w_z[t,i] * w_z[t,j]
    @tullio sq_u_z_re[t,i,j] = v_z[t,i] * v_z[t,j] - w_z[t,i] * w_z[t,j]
    @tullio sq_u_z_im[t,i,j] = 2 * v_z[t,i] * w_z[t,j]

    @tullio δ_1_[t,i,j] = abs2_u_z_re[t,k,l] * γ[l,k,i,j]
    @tullio δ_2_re[t,i,j] = sq_u_z_re[t,k,l] * γ[l,k,i,j]
    @tullio δ_2_im[t,i,j] = sq_u_z_im[t,k,l] * γ[l,k,i,j]

    @. δ_1 = δ_1_
    @. δ_2 = δ_2_re + 1im*δ_2_im
end

function get_p_adjoint_disp_mmf(ũω, τω, Dω, hRω, γ, one_m_fR, fR, Nt, M)
    p_params = (ũω, τω, Dω, hRω, conj.(hRω), γ, one_m_fR, fR, Nt, exp.(1im*π*repeat([0,1], Int(Nt/2))), exp.(1im*π*repeat([1,0], Int(Nt/2))))
    fft_plan_M = plan_fft(zeros(ComplexF64, Nt, M), 1)
    ifft_plan_M = plan_ifft(zeros(ComplexF64, Nt, M), 1)
    fft_plan_M! = plan_fft!(zeros(ComplexF64, Nt, M), 1)
    ifft_plan_M! = plan_ifft!(zeros(ComplexF64, Nt, M), 1)
    fft_plan_MM! = plan_fft!(zeros(ComplexF64, Nt, M, M), 1)
    ifft_plan_MM! = plan_ifft!(zeros(ComplexF64, Nt, M, M), 1)
    p_fft = (fft_plan_M, ifft_plan_M, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!)

    exp_D_p = zeros(ComplexF64, Nt, M)
    exp_D_m = zeros(ComplexF64, Nt, M) 
    λω = zeros(ComplexF64, Nt, M)
    λt = zeros(ComplexF64, Nt, M)
    λωc = zeros(ComplexF64, Nt, M)
    ũω_z = zeros(ComplexF64, Nt, M)
    uω = zeros(ComplexF64, Nt, M)
    ut = zeros(ComplexF64, Nt, M)
    utc = zeros(ComplexF64, Nt, M)
    δK1t = zeros(Nt, M, M)
    δK2t = zeros(ComplexF64, Nt, M, M)
    δK1t_cplx = zeros(ComplexF64, Nt, M, M)
    hRω_δRω = zeros(ComplexF64, Nt, M, M)
    hR_conv_δR = zeros(ComplexF64, Nt, M, M)
    δR1t = zeros(Nt, M, M)
    δKR1t = zeros(Nt, M, M)
    sum_res = zeros(ComplexF64, Nt, M)
    γ_λt_utc = zeros(ComplexF64, Nt, M, M)
    γ_λt_ut_ut = zeros(ComplexF64, Nt, M)
    λ_∂fKR1c∂uc = zeros(ComplexF64, Nt, M)
    λc_∂fK∂uc = zeros(ComplexF64, Nt, M)
    λ_∂fR2c∂uc = zeros(ComplexF64, Nt, M)
    λc_∂fR∂uc = zeros(ComplexF64, Nt, M)
    p_prealloc = (exp_D_p, exp_D_m, λω, λt, λωc, ũω_z, uω, ut, utc, δK1t, δK2t, δK1t_cplx, hRω_δRω, hR_conv_δR, δR1t, δKR1t, sum_res, 
        γ_λt_utc, γ_λt_ut_ut, λ_∂fKR1c∂uc, λc_∂fK∂uc, λ_∂fR2c∂uc, λc_∂fR∂uc)

    p_calc_δs = (zeros(Nt, M), zeros(Nt, M), zeros(Nt, M, M), zeros(Nt, M, M), zeros(Nt, M, M), zeros(Nt, M, M), zeros(Nt, M, M), 
        zeros(Nt, M, M), γ)

    p_γ_a_b = (zeros(Nt,M), zeros(Nt,M), zeros(Nt,M), zeros(Nt,M), zeros(Nt,M,M), zeros(Nt,M,M), zeros(Nt,M,M), zeros(Nt,M,M))

    return (p_params, p_fft, p_prealloc, p_calc_δs, p_γ_a_b)
end

function solve_adjoint_disp_mmf(λωL, ũω, fiber, sim; dt=1e-3)
    λ̃ωL = exp.(-1im*fiber["Dω"]*fiber["L"]) .* λωL # possibly an initial condition of λ̃ωL at z=L in the adjoint (back-propagation) case
    
    p_adjoint_disp_mmf = get_p_adjoint_disp_mmf(ũω, fftshift(sim["ωs"]/sim["ω0"]), fiber["Dω"], fiber["hRω"], fiber["γ"], 
        fiber["one_m_fR"], 1-fiber["one_m_fR"], sim["Nt"], sim["M"])
    prob_adjoint_disp_mmf = ODEProblem(adjoint_disp_mmf!, λ̃ωL, (fiber["L"], 0), p_adjoint_disp_mmf) # ODEProblem(f,u0,tspan,p); u0 = initial cond., tspan = t range (t=z=domain), p = optional parameter
    sol_adjoint_disp_mmf = solve(prob_adjoint_disp_mmf, Vern9(), dt=dt, adaptive=false, saveat=(0, fiber["L"])) # solves for λωL with fixed interval t = dt, and saves the results at z = 0, L

    return sol_adjoint_disp_mmf
end