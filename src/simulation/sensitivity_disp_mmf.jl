"""
    adjoint_disp_mmf!(dλ̃ω, λ̃ω, p, z)

ODE right-hand side for the **adjoint** (backward) propagation, used to compute gradients
of a cost functional J with respect to the input field. Integrated backward from z=L to z=0.

The adjoint equation is derived from the forward GMMNLSE by linearizing the nonlinear
operator around the forward solution ũ(z) and taking the adjoint (transpose-conjugate).
This gives the sensitivity of J to perturbations at any z along the fiber.

The adjoint field λ̃(ω,z) satisfies:
    dλ̃/dz = -[∂f/∂ũ]† · λ̃

where f is the forward RHS (`disp_mmf!`) and † denotes the adjoint operator. The four
terms in the RHS correspond to:
- `λ_∂fKR1c∂uc`: combined Kerr+Raman contribution via δ_{KR1} contraction
- `λc_∂fK∂uc`: conjugate Kerr contribution via δ₂ (u² terms)
- `λ_∂fR2c∂uc`: Raman contribution via h_R convolution (forward path)
- `λc_∂fR∂uc`: Raman contribution via h_R convolution (conjugate path)

# Arguments
- `dλ̃ω`: output derivative, shape (Nt, M), mutated in-place
- `λ̃ω`: current adjoint state in interaction picture, shape (Nt, M)
- `p`: parameter tuple from `get_p_adjoint_disp_mmf` (nested as p_params, p_fft, p_prealloc, ...)
- `z`: current propagation position [m] (decreasing from L to 0)

# Note
The forward solution ũ(z) is accessed via continuous interpolation at each step
(line `ũω_z .= ũω(z)`), which means adjoint accuracy is bounded by the forward
solver's interpolant order (4th-order for Tsit5).
"""
function adjoint_disp_mmf!(dλ̃ω, λ̃ω, p, z)
    p_params, p_fft, p_prealloc, p_calc_δs, p_γ_a_b = p
    ũω, τω, Dω, hRω, hRωc, γ, one_m_fR, fR, Nt, σ1, σ2 = p_params
    fft_plan_M, ifft_plan_M, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM! = p_fft
    exp_D_p, exp_D_m, λω, λt, λωc, ũω_z, uω, ut, utc, δK1t, δK2t, δK1t_cplx, hRω_δRω, hR_conv_δR, δR1t, δKR1t, sum_res, γ_λt_utc, γ_λt_ut_ut, λ_∂fKR1c∂uc, λc_∂fK∂uc, λ_∂fR2c∂uc, λc_∂fR∂uc = p_prealloc

    # Interaction picture phase factors at current z
    @. exp_D_p = cis(Dω * z)
    @. exp_D_m = cis(-Dω * z)

    # Transform adjoint field to lab frame and compute time-domain versions
    @. λω = exp_D_p * λ̃ω
    λω .*= τω
    mul!(λt, fft_plan_M, λω)
    @. λωc = conj(λω)
    ifft_plan_M! * λωc

    # Retrieve forward solution at z via continuous interpolant
    ũω_z .= ũω(z)
    @. uω = exp_D_p * ũω_z
    mul!(ut, fft_plan_M, uω)
    @. utc = conj(ut)
    ifft_plan_M! * uω

    # Compute Kerr operators δ₁ (|u|² terms) and δ₂ (u² terms) from forward field
    calc_δs!(δK1t, δK2t, ut, p_calc_δs)

    # Raman convolution of δ₁ with h_R(ω)
    @. δK1t_cplx = ComplexF64(δK1t, 0.0)
    fft_plan_MM! * δK1t_cplx
    @. hRω_δRω = hRω * δK1t_cplx
    ifft_plan_MM! * hRω_δRω
    fftshift!(hR_conv_δR, hRω_δRω, 1)
    @. δR1t = real(hR_conv_δR)

    # Combined Kerr+Raman operator: 2(1-fR)·δ_K + δ_R
    # The factor 2 arises from d/du*(|u|²·u) = 2|u|²
    @tullio δKR1t[t, i, j] = 2 * one_m_fR * δK1t[t, i, j] + δR1t[t, i, j]

    # Four adjoint RHS contributions
    calc_λ_∂fKR1c∂uc!(λ_∂fKR1c∂uc, λt, δKR1t, ifft_plan_M!, exp_D_m, sum_res)
    calc_λc_∂fK∂uc!(λc_∂fK∂uc, λωc, δK2t, ifft_plan_M!, exp_D_m, sum_res, Nt)
    calc_λ_∂fR2c∂uc!(λ_∂fR2c∂uc, λt, utc, uω, γ, hRωc, σ1, fft_plan_M!, fft_plan_MM!, exp_D_m, γ_λt_utc, γ_λt_ut_ut, Nt, p_γ_a_b)
    calc_λc_∂fR∂uc!(λc_∂fR∂uc, λωc, ut, γ, hRω, σ1, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_m, γ_λt_utc, γ_λt_ut_ut, Nt,
        p_γ_a_b)

    @. dλ̃ω = λ_∂fKR1c∂uc + one_m_fR * λc_∂fK∂uc + λ_∂fR2c∂uc + λc_∂fR∂uc
end

### Helper functions for adjoint_disp_mmf!
### These break the adjoint RHS into manageable pieces and avoid redundant computation.

"""
    calc_λ_∂fR2c∂uc!(...)

Raman adjoint contribution (forward path): computes the term arising from
∂(h_R * (γ·u·u*))/∂u* contracted with the adjoint field λ.

Involves: γ-tensor contraction of λ with u*, Raman convolution with conj(h_R),
then contraction with forward field in frequency domain.
"""
function calc_λ_∂fR2c∂uc!(dλω, λt, utc, ifft_uω, γ, hωc, σ, fft_plan_M!, fft_plan_MM!, exp_D_m, γ_λt_utc, γ_λt_ut_ut, Nt, p_γ_a_b)
    calc_γ_a_b!(γ_λt_utc, λt, utc, γ, p_γ_a_b)
    fft_plan_MM! * γ_λt_utc
    @. γ_λt_utc *= hωc * σ
    fft_plan_MM! * γ_λt_utc
    @tullio γ_λt_ut_ut[t, i] = γ_λt_utc[t, i, j] * ifft_uω[t, j]
    fft_plan_M! * γ_λt_ut_ut
    @. dλω = 1im / Nt * exp_D_m * γ_λt_ut_ut
end

"""
    calc_λc_∂fR∂uc!(...)

Raman adjoint contribution (conjugate path): computes the term arising from
∂(h_R * (γ·u·u*))/∂u contracted with conj(λ).

Similar structure to `calc_λ_∂fR2c∂uc!` but operates on the conjugate adjoint field
and uses h_R (not conj(h_R)).
"""
function calc_λc_∂fR∂uc!(dλω, ifft_λωc, ut, γ, hω, σ, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!, exp_D_m, γ_ifftλωc_ut,
    γ_ifftλωc_ut_ut, Nt, p_γ_a_b)
    calc_γ_a_b!(γ_ifftλωc_ut, ifft_λωc, ut, γ, p_γ_a_b)
    ifft_plan_MM! * γ_ifftλωc_ut
    @. γ_ifftλωc_ut *= hω * σ
    fft_plan_MM! * γ_ifftλωc_ut
    @tullio γ_ifftλωc_ut_ut[t, i] = γ_ifftλωc_ut[t, i, j] * ut[t, j]
    ifft_plan_M! * γ_ifftλωc_ut_ut
    @. dλω = -1im * Nt * exp_D_m * γ_ifftλωc_ut_ut
end

"""
    calc_λ_∂fKR1c∂uc!(dλω, λt, δ, ifft_plan!, exp_D_m, sum_res)

Kerr+Raman adjoint contribution: contracts the time-domain adjoint field λ(t)
with the combined operator δ_{KR1}[t,i,j] = 2(1-fR)·δ_K + δ_R, then transforms
back to interaction picture.
"""
function calc_λ_∂fKR1c∂uc!(dλω, λt, δ, ifft_plan!, exp_D_m, sum_res)
    @tullio sum_res[t, j] = λt[t, i] * δ[t, i, j]
    ifft_plan! * sum_res
    @. dλω = 1im * exp_D_m * sum_res
end

"""
    calc_λc_∂fK∂uc!(dλω, ifft_λωc, δ, ifft_plan!, exp_D_m, sum_res, Nt)

Conjugate Kerr adjoint contribution: contracts IFFT(conj(λ)) with Kerr operator δ₂
(the u² part, which couples u and u* derivatives).
"""
function calc_λc_∂fK∂uc!(dλω, ifft_λωc, δ, ifft_plan!, exp_D_m, sum_res, Nt)
    @tullio sum_res[t, j] = ifft_λωc[t, i] * δ[t, i, j]
    ifft_plan! * sum_res
    @. dλω = -1im * Nt * exp_D_m * sum_res
end

"""
    calc_γ_a_b!(γ_a_b, a, b, γ, p)

Compute the γ-tensor contraction of two complex fields a and b:
    (γ·a·b)[t,i,j] = Σ_{kl} γ[k,l,i,j] · (a[t,k]·b[t,l])

Splits into real/imaginary parts for efficient computation with Tullio, since
Tullio works best with real-valued contractions. The result is:
    γ_a_b = γ_a_b_re + i·γ_a_b_im
"""
function calc_γ_a_b!(γ_a_b, a, b, γ, p)
    a_re, a_im, b_re, b_im, a_b_re, a_b_im, γ_a_b_re, γ_a_b_im = p

    @. a_re = real(a)
    @. a_im = imag(a)
    @. b_re = real(b)
    @. b_im = imag(b)

    @tullio a_b_re[t, i, j] = a_re[t, i] * b_re[t, j] - a_im[t, i] * b_im[t, j]
    @tullio a_b_im[t, i, j] = a_re[t, i] * b_im[t, j] + a_im[t, i] * b_re[t, j]

    @tullio γ_a_b_re[t, i, j] = a_b_re[t, l, k] * γ[l, k, i, j]
    @tullio γ_a_b_im[t, i, j] = a_b_im[t, l, k] * γ[l, k, i, j]

    @. γ_a_b = γ_a_b_re + 1im * γ_a_b_im
end

"""
    calc_δs!(δ_1, δ_2, u_z, p)

Compute the two Kerr operator tensors from the forward field u(t) at position z:

- `δ₁[t,i,j]` = Σ_{kl} γ[l,k,i,j] · (v_k·v_l + w_k·w_l)  — the |u|² part
- `δ₂[t,i,j]` = Σ_{kl} γ[l,k,i,j] · (v_k·v_l - w_k·w_l + 2i·v_k·w_l)  — the u² part

where v = Re(u), w = Im(u). The distinction matters because the nonlinear term
|u|²·u has derivatives with respect to both u and u*, and these two operators
capture those two contributions separately. δ₁ appears in the Kerr+Raman term,
δ₂ appears in the conjugate Kerr term of the adjoint equation.
"""
function calc_δs!(δ_1, δ_2, u_z, p)
    v_z, w_z, abs2_u_z_re, sq_u_z_re, sq_u_z_im, δ_1_, δ_2_re, δ_2_im, γ = p

    @. v_z = real(u_z)
    @. w_z = imag(u_z)

    @tullio abs2_u_z_re[t, i, j] = v_z[t, i] * v_z[t, j] + w_z[t, i] * w_z[t, j]
    @tullio sq_u_z_re[t, i, j] = v_z[t, i] * v_z[t, j] - w_z[t, i] * w_z[t, j]
    @tullio sq_u_z_im[t, i, j] = 2 * v_z[t, i] * w_z[t, j]

    @tullio δ_1_[t, i, j] = abs2_u_z_re[t, k, l] * γ[l, k, i, j]
    @tullio δ_2_re[t, i, j] = sq_u_z_re[t, k, l] * γ[l, k, i, j]
    @tullio δ_2_im[t, i, j] = sq_u_z_im[t, k, l] * γ[l, k, i, j]

    @. δ_1 = δ_1_
    @. δ_2 = δ_2_re + 1im * δ_2_im
end

"""
    get_p_adjoint_disp_mmf(ũω, τω, Dω, hRω, γ, one_m_fR, fR, Nt, M) -> Tuple

Pre-allocate all working arrays and FFT plans for `adjoint_disp_mmf!`. Returns a
nested tuple structure: (p_params, p_fft, p_prealloc, p_calc_δs, p_γ_a_b).

# Arguments
- `ũω`: forward ODE solution object (callable as `ũω(z)` for continuous interpolation)
- `τω`: self-steepening factor fftshift(ωs/ω0), shape (Nt,)
- `Dω`: dispersion operator, shape (Nt, M)
- `hRω`: Raman response in frequency domain
- `γ`: nonlinear coefficient tensor, shape (M, M, M, M)
- `one_m_fR`: (1 - fR)
- `fR`: fractional Raman contribution
- `Nt`: number of grid points
- `M`: number of spatial modes

# Note on σ1, σ2 in p_params
These are alternating sign vectors exp(iπ·[0,1,0,1,...]) and exp(iπ·[1,0,1,0,...])
used for frequency-domain shift operations (equivalent to fftshift for even-length arrays).
"""
function get_p_adjoint_disp_mmf(ũω, τω, Dω, hRω, γ, one_m_fR, fR, Nt, M)
    p_params = (ũω, τω, Dω, hRω, conj.(hRω), γ, one_m_fR, fR, Nt, exp.(1im * π * repeat([0, 1], Int(Nt / 2))), exp.(1im * π * repeat([1, 0], Int(Nt / 2))))
    fft_plan_M = plan_fft(zeros(ComplexF64, Nt, M), 1; flags=FFTW.MEASURE)
    ifft_plan_M = plan_ifft(zeros(ComplexF64, Nt, M), 1; flags=FFTW.MEASURE)
    fft_plan_M! = plan_fft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.MEASURE)
    ifft_plan_M! = plan_ifft!(zeros(ComplexF64, Nt, M), 1; flags=FFTW.MEASURE)
    fft_plan_MM! = plan_fft!(zeros(ComplexF64, Nt, M, M), 1; flags=FFTW.MEASURE)
    ifft_plan_MM! = plan_ifft!(zeros(ComplexF64, Nt, M, M), 1; flags=FFTW.MEASURE)
    p_fft = (fft_plan_M, ifft_plan_M, fft_plan_M!, ifft_plan_M!, fft_plan_MM!, ifft_plan_MM!)

    exp_D_p = zeros(ComplexF64, Nt, M)
    exp_D_m = zeros(ComplexF64, Nt, M)
    λω = zeros(ComplexF64, Nt, M)
    λt = zeros(ComplexF64, Nt, M)
    λωc = zeros(ComplexF64, Nt, M)
    ũω_z = zeros(ComplexF64, Nt, M)
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
    p_prealloc = (exp_D_p, exp_D_m, λω, λt, λωc, ũω_z, uω, ut, utc, δK1t, δK2t, δK1t_cplx, hRω_δRω, hR_conv_δR, δR1t, δKR1t, sum_res,
        γ_λt_utc, γ_λt_ut_ut, λ_∂fKR1c∂uc, λc_∂fK∂uc, λ_∂fR2c∂uc, λc_∂fR∂uc)

    p_calc_δs = (zeros(Nt, M), zeros(Nt, M), zeros(Nt, M, M), zeros(Nt, M, M), zeros(Nt, M, M), zeros(Nt, M, M), zeros(Nt, M, M),
        zeros(Nt, M, M), γ)

    p_γ_a_b = (zeros(Nt, M), zeros(Nt, M), zeros(Nt, M), zeros(Nt, M), zeros(Nt, M, M), zeros(Nt, M, M), zeros(Nt, M, M), zeros(Nt, M, M))

    return (p_params, p_fft, p_prealloc, p_calc_δs, p_γ_a_b)
end

"""
    solve_adjoint_disp_mmf(λωL, ũω, fiber, sim) -> ODESolution

Solve the adjoint ODE backward from z=L to z=0 to obtain the gradient of the cost
functional with respect to the input field.

# Arguments
- `λωL`: adjoint terminal condition at z=L (gradient of cost w.r.t. output field),
         shape (Nt, M). Typically comes from `spectral_band_cost`.
- `ũω`: forward ODE solution object (from `solve_disp_mmf`), accessed via `ũω(z)`
- `fiber`: fiber parameter dict
- `sim`: simulation parameter dict

# Returns
ODESolution object. The adjoint field at z=0 is obtained via `sol(0)`, which gives
λ̃(ω,0) — the sensitivity of the cost to perturbations in the input field.

# Solver choice
Uses Tsit5 at reltol=1e-8, matching the forward solver. The adjoint accuracy is
bounded by Tsit5's 4th-order interpolant regardless of adjoint solver order, so
using a higher-order solver (Vern9) or tighter tolerance (1e-10) provides no benefit.
L-BFGS requires only ~1e-4 relative gradient accuracy (Xie, Byrd, Nocedal 2020).
"""
function solve_adjoint_disp_mmf(λωL, ũω, fiber, sim)
    # Transform terminal condition to interaction picture at z=L
    λ̃ωL = exp.(-1im * fiber["Dω"] * fiber["L"]) .* λωL

    p_adjoint_disp_mmf = get_p_adjoint_disp_mmf(ũω, fftshift(sim["ωs"] / sim["ω0"]), fiber["Dω"], fiber["hRω"], fiber["γ"],
        fiber["one_m_fR"], 1 - fiber["one_m_fR"], sim["Nt"], sim["M"])
    prob_adjoint_disp_mmf = ODEProblem(adjoint_disp_mmf!, λ̃ωL, (fiber["L"], 0), p_adjoint_disp_mmf)
    sol_adjoint_disp_mmf = solve(prob_adjoint_disp_mmf, Tsit5(), reltol=1e-8, saveat=(0, fiber["L"]))

    return sol_adjoint_disp_mmf
end
