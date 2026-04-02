"""
    mmf_u_μ_ν!(dΓ̃, Γ̃, p, z)

ODE right-hand side for simultaneous propagation of the field u and its sensitivities
μ = ∂u/∂u₀ and ν = ∂u/∂u₀* in a multimode fiber (Kerr-only, no Raman).

The state Γ̃ is a matrix [ũ  μ̃  ν̃] of shape (M, 1+2M) in the interaction picture,
where columns 1 are the field, columns 2:M+1 are μ̃, and columns M+2:2M+1 are ν̃.

The forward equation is:
    dũ/dz = i · exp(-iδβz) · γ_{|u|²} · u

The sensitivity equations (linearized around the forward solution) are:
    dμ̃/dz = i · exp(-iδβz) · [2·γ_{|u|²}·μ + γ_{u²}·conj(ν)]
    dν̃/dz = i · exp(-iδβz) · [2·γ_{|u|²}·ν + γ_{u²}·conj(μ)]

where γ_{|u|²}[i,j] = Σ_{kl} γ[l,k,j,i]·(v_k·v_l + w_k·w_l)  and
      γ_{u²}[i,j]   = Σ_{kl} γ[l,k,j,i]·(v_k·v_l - w_k·w_l + 2i·v_k·w_l).

# Arguments
- `dΓ̃`: output derivative, shape (M, 1+2M), mutated in-place
- `Γ̃`: current state [ũ  μ̃  ν̃], shape (M, 1+2M)
- `p`: pre-allocated parameter tuple from `get_p_mmf_u_μ_ν`
- `z`: propagation position [m]
"""
function mmf_u_μ_ν!(dΓ̃, Γ̃, p, z)

    δβ, γ, M, ũ, μ̃, ν̃, dũ, dμ̃, dν̃, exp_p, exp_m, u, v, w, μ, ν, γvv, γww, γvw, γ_abs2_u, γ_sq_u = p

    ũ .= view(Γ̃, :, 1)
    μ̃ .= view(Γ̃, :, 2:M+1)
    ν̃ .= view(Γ̃, :, M+2:2*M+1)

    @. exp_p = exp(1im * δβ * z)
    @. exp_m = exp(-1im * δβ * z)

    @. u = exp_p * ũ
    @. v = real(u)
    @. w = imag(u)

    # Kerr operators via γ-tensor contraction
    @tullio γvv[i,j] = γ[l,k,j,i] * v[k] * v[l]
    @tullio γww[i,j] = γ[l,k,j,i] * w[k] * w[l]
    @tullio γvw[i,j] = γ[l,k,j,i] * v[k] * w[l]

    @. γ_abs2_u = γvv + γww       # |u|² operator
    @. γ_sq_u = γvv - γww + 2im*γvw  # u² operator

    # Forward equation
    mul!(dũ, γ_abs2_u, u)
    @. dũ *= 1im * exp_m

    # Sensitivity equations
    @. μ = exp_p * μ̃
    @. ν = exp_p * ν̃

    dμ̃ .= 1im .* exp_m .* ( 2 .* γ_abs2_u * μ .+ γ_sq_u * conj.(ν))
    dν̃ .= 1im .* exp_m .* ( 2 .* γ_abs2_u * ν .+ γ_sq_u * conj.(μ))

    dΓ̃[:,1] .= dũ
    dΓ̃[:,2:M+1] .= dμ̃
    dΓ̃[:,M+2:2*M+1] .= dν̃

end

"""
    get_p_mmf_u_μ_ν(δβ, γ, M) -> Tuple

Pre-allocate working arrays for `mmf_u_μ_ν!`.

# Arguments
- `δβ`: differential propagation constants relative to mode 1, length M
- `γ`: Kerr nonlinearity tensor, shape (M, M, M, M)
- `M`: number of spatial modes
"""
function get_p_mmf_u_μ_ν(δβ, γ, M)
    return (δβ, γ, M, zeros(ComplexF64, M), zeros(ComplexF64, M, M), zeros(ComplexF64, M, M), zeros(ComplexF64, M), zeros(ComplexF64, M, M), zeros(ComplexF64, M, M), zeros(ComplexF64, M), zeros(ComplexF64, M), zeros(ComplexF64, M), zeros(M), zeros(M), zeros(ComplexF64, M, M), zeros(ComplexF64, M, M), zeros(M, M), zeros(M, M), zeros(M, M), zeros(M, M), zeros(ComplexF64, M, M))
end

"""
    solve_mmf(u0, δβ, γ, M, zspan, zsave) -> Dict

Solve the multimode propagation + sensitivity ODE system from z=zspan[1] to z=zspan[2].

The initial state Γ₀ = [u₀  I  0] where I is the M×M identity (∂u/∂u₀ = I at z=0)
and 0 is the M×M zero matrix (∂u/∂u₀* = 0 at z=0).

Uses Tsit5 at reltol=1e-5. Returns fields and sensitivities in the lab frame
(interaction picture undone by multiplying with exp(iδβz)).

# Arguments
- `u0`: initial mode amplitudes, length M
- `δβ`: differential propagation constants, length M
- `γ`: nonlinearity tensor, shape (M, M, M, M)
- `M`: number of modes
- `zspan`: (z_start, z_end) propagation range [m]
- `zsave`: vector of z positions at which to save output

# Returns
Dict with keys:
- `"uz"`: field u(z) in lab frame, shape (Nz, M)
- `"μz"`: sensitivity ∂u/∂u₀ in lab frame, shape (Nz, M, M)
- `"νz"`: sensitivity ∂u/∂u₀* in lab frame, shape (Nz, M, M)
"""
function solve_mmf(u0, δβ, γ, M, zspan, zsave)
    Γ0 = [u0 diagm(ones(M)) zeros(M,M)]
    p_mmf_u_μ_ν = get_p_mmf_u_μ_ν(δβ, γ, M)
    prob_mmf_u_μ_ν = ODEProblem(mmf_u_μ_ν!, Γ0, zspan, p_mmf_u_μ_ν)
    sol_ũ_μ̃_ν̃ = solve(prob_mmf_u_μ_ν, Tsit5(), reltol=1e-5, saveat=zsave)

    uz = zeros(ComplexF64, length(zsave), M)
    μz = zeros(ComplexF64, length(zsave), M, M)
    νz = zeros(ComplexF64, length(zsave), M, M)

    for i in 1:length(zsave)
        uz[i,:] = exp.(1im*δβ*sol_ũ_μ̃_ν̃.t[i]) .* sol_ũ_μ̃_ν̃.u[i][:,1]
        μz[i,:,:] = exp.(1im*δβ*sol_ũ_μ̃_ν̃.t[i]) .* sol_ũ_μ̃_ν̃.u[i][:,2:M+1]
        νz[i,:,:] = exp.(1im*δβ*sol_ũ_μ̃_ν̃.t[i]) .* sol_ũ_μ̃_ν̃.u[i][:,M+2:2*M+1]
    end

    return Dict("uz" => uz, "μz" => μz, "νz" => νz)
end
