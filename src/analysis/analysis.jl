function compute_noise_map(X, ∂Xkl∂u, U, ϕ, δF_in_ω)
    @tullio Φ[i] := ϕ[i,k] * ϕ[i,k]
    @tullio no_derivative_term[i] := X[i] * (1 - Φ[i])
    @tullio Xklmn[k,l,m,n] := conj(∂Xkl∂u[k,l,ω,j]) * ∂Xkl∂u[m,n,ω,j]
    @tullio shot_noise[i] := ϕ[i,k] * ϕ[i,l] * ϕ[i,m] * ϕ[i,n] * Xklmn[k,l,m,n]
    @tullio ∂Xkl∂u_U[k,l,ω] := ∂Xkl∂u[k,l,ω,j] * U[j]
    @tullio XUklmn[k,l,m,n] := δF_in_ω[ω] * conj(∂Xkl∂u_U[k,l,ω]) * ∂Xkl∂u_U[m,n,ω]
    @tullio excess_noise[i] := ϕ[i,k] * ϕ[i,l] * ϕ[i,m] * ϕ[i,n] * XUklmn[k,l,m,n]
    var_X = real.(no_derivative_term + shot_noise + excess_noise)
    return var_X
end

function compute_noise_map_modek(X, ∂Xkk∂u, U, ϕ, δF_in_ω)
    @tullio Φ[i] := ϕ[i,k] * ϕ[i,k]
    @tullio no_derivative_term[i] := X[i] * (1 - Φ[i])
    @tullio Xkkkk := conj(∂Xkk∂u[ω,j]) * ∂Xkk∂u[ω,j]
    @tullio shot_noise[i] := ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * Xkkkk # shot noise for only one mode as well?
    @tullio ∂Xkk∂u_U[ω] := ∂Xkk∂u[ω,j] * U[j]
    @tullio XUkkkk := δF_in_ω[ω] * conj(∂Xkk∂u_U[ω]) * ∂Xkk∂u_U[ω]
    @tullio excess_noise[i] := ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * XUkkkk
    var_X = real.(no_derivative_term + shot_noise + excess_noise)
    return var_X
end

function compute_noise_map_modem(X, ∂Xmm∂u, U, ϕ, δF_in_ω)
    @tullio 
    @tullio shot_noise[i] := ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * Xkkkk # shot noise for only one mode as well?
    var_X = real.(shot_noise + excess_noise)

    @tullio Xkkkk := conj(∂Xmm∂u[ω,j]) * ∂Xmm∂u[ω,j]
    @tullio ∂Xmm∂u_U[ω] := ∂Xmm∂u[ω,j] * U[j]
    @tullio XUkkkk := δF_in_ω[ω] * conj(∂Xmm∂u_U[ω]) * ∂Xmm∂u_U[ω]
    @tullio excess_noise[i] := ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * XUkkkk
    var_X = real.(no_derivative_term + shot_noise + excess_noise)
    return var_X
end

function compute_noise_map_modem_fsum(X, ∂Xmm∂u, U, δF_in_ω)
    @tullio shot_noise := conj(∂Xmm∂u[ω,j]) * ∂Xmm∂u[ω,j]
    @tullio ∂Xmm∂u_U[ω] := ∂Xmm∂u[ω,j] * U[j]
    @tullio excess_noise := δF_in_ω[ω] * conj(∂Xmm∂u_U[ω]) * ∂Xmm∂u_U[ω]
    var_X = real.(shot_noise + excess_noise)
    return var_X
end