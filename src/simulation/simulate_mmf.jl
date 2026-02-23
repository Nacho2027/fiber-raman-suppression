function mmf_u_μ_ν!(dΓ̃, Γ̃, p, z)

    δβ, γ, M, ũ, μ̃, ν̃, dũ, dμ̃, dν̃, exp_p, exp_m, u, v, w, μ, ν, γvv, γww, γvw, γ_abs2_u, γ_sq_u = p
    
    ũ .= view(Γ̃, :, 1)
    μ̃ .= view(Γ̃, :, 2:M+1)
    ν̃ .= view(Γ̃, :, M+2:2*M+1)

    @. exp_p = exp(1im * δβ * z)
    @. exp_m = exp(-1im * δβ * z)
    
    @. u = exp_p * ũ
    @. v = real(u)
    @. w = imag(u)

    @tullio γvv[i,j] = γ[l,k,j,i] * v[k] * v[l]
    @tullio γww[i,j] = γ[l,k,j,i] * w[k] * w[l]
    @tullio γvw[i,j] = γ[l,k,j,i] * v[k] * w[l]

    @. γ_abs2_u = γvv + γww
    @. γ_sq_u = γvv - γww + 2im*γvw

    mul!(dũ, γ_abs2_u, u)
    @. dũ *= 1im * exp_m

    @. μ = exp_p * μ̃
    @. ν = exp_p * ν̃
    
    dμ̃ .= 1im .* exp_m .* ( 2 .* γ_abs2_u * μ .+ γ_sq_u * conj.(ν))
    dν̃ .= 1im .* exp_m .* ( 2 .* γ_abs2_u * ν .+ γ_sq_u * conj.(μ))

    dΓ̃[:,1] .= dũ
    dΓ̃[:,2:M+1] .= dμ̃
    dΓ̃[:,M+2:2*M+1] .= dν̃
    
end

function get_p_mmf_u_μ_ν(δβ, γ, M)
    return (δβ, γ, M, zeros(ComplexF64, M), zeros(ComplexF64, M, M), zeros(ComplexF64, M, M), zeros(ComplexF64, M), zeros(ComplexF64, M, M), zeros(ComplexF64, M, M), zeros(ComplexF64, M), zeros(ComplexF64, M), zeros(ComplexF64, M), zeros(M), zeros(M), zeros(ComplexF64, M, M), zeros(ComplexF64, M, M), zeros(M, M), zeros(M, M), zeros(M, M), zeros(M, M), zeros(ComplexF64, M, M))
end

function solve_mmf(u0, δβ, γ, M, zspan, zsave)
    Γ0 = [u0 diagm(ones(M)) zeros(M,M)]
    p_mmf_u_μ_ν = get_p_mmf_u_μ_ν(δβ, γ, M)
    prob_mmf_u_μ_ν = ODEProblem(mmf_u_μ_ν!, Γ0, zspan, p_mmf_u_μ_ν)
    sol_ũ_μ̃_ν̃ = solve(prob_mmf_u_μ_ν, Tsit5(), reltol=1e-5, saveat=zsave)

    uz = zeros(ComplexF64, length(zsave), M)
    μz = zeros(ComplexF64, length(zsave), M, M)
    νz = zeros(ComplexF64, length(zsave), M, M)
    
    for i in 1:length(zsave)
        uz[i,:] = exp.(1im*δβ*sol_ũ_μ̃_ν̃.t[i]) .* sol_ũ_μ̃_ν̃.u[i][:,1]
        μz[i,:,:] = exp.(1im*δβ*sol_ũ_μ̃_ν̃.t[i]) .* sol_ũ_μ̃_ν̃.u[i][:,2:M+1]
        νz[i,:,:] = exp.(1im*δβ*sol_ũ_μ̃_ν̃.t[i]) .* sol_ũ_μ̃_ν̃.u[i][:,M+2:2*M+1]
    end

    return Dict("uz" => uz, "μz" => μz, "νz" => νz)
end