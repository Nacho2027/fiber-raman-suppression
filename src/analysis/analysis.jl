"""
    compute_noise_map(X, ∂Xkl∂u, U, ϕ, δF_in_ω) -> Vector{Float64}

Compute the noise variance map for a multimode measurement X across spatial
positions indexed by i.

The noise variance has three contributions:
1. **No-derivative term**: X[i]·(1 - Φ[i]) — intrinsic noise from imperfect mode overlap
2. **Shot noise**: Σ_{klmn} ϕ_{ik}·ϕ_{il}·ϕ_{im}·ϕ_{in} · |∂X_{kl}/∂u|²
3. **Excess noise**: same overlap weighting applied to input-field-dependent noise

where Φ[i] = Σ_k |ϕ_{ik}|² is the total overlap factor at position i.

# Arguments
- `X`: measurement observable, indexed by spatial position
- `∂Xkl∂u`: sensitivity of X to field, shape (modes, modes, freq, modes)
- `U`: input mode vector
- `ϕ`: spatial-to-mode projection matrix
- `δF_in_ω`: input noise spectral density
"""
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

"""
    compute_noise_map_modek(X, ∂Xkk∂u, U, ϕ, δF_in_ω) -> Vector{Float64}

Single-mode variant of `compute_noise_map`: computes noise variance when the
measurement is restricted to a single mode k (diagonal element X_{kk}).

Same three-term decomposition but with simplified overlap weighting using Φ⁴.
"""
function compute_noise_map_modek(X, ∂Xkk∂u, U, ϕ, δF_in_ω)
    @tullio Φ[i] := ϕ[i,k] * ϕ[i,k]
    @tullio no_derivative_term[i] := X[i] * (1 - Φ[i])
    @tullio Xkkkk := conj(∂Xkk∂u[ω,j]) * ∂Xkk∂u[ω,j]
    @tullio shot_noise[i] := ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * Xkkkk
    @tullio ∂Xkk∂u_U[ω] := ∂Xkk∂u[ω,j] * U[j]
    @tullio XUkkkk := δF_in_ω[ω] * conj(∂Xkk∂u_U[ω]) * ∂Xkk∂u_U[ω]
    @tullio excess_noise[i] := ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * XUkkkk
    var_X = real.(no_derivative_term + shot_noise + excess_noise)
    return var_X
end

# NOTE: compute_noise_map_modem is incomplete — the first @tullio has no operation,
# and `no_derivative_term` / `excess_noise` are referenced before definition.
# This function will error at runtime. It appears to be an abandoned refactoring.
# Kept for reference but should not be called.
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

"""
    compute_noise_map_modem_fsum(X, ∂Xmm∂u, U, δF_in_ω) -> Float64

Frequency-summed noise variance for a single-mode measurement (no spatial
projection). Returns a scalar: shot_noise + excess_noise summed over all
frequency bins.
"""
function compute_noise_map_modem_fsum(X, ∂Xmm∂u, U, δF_in_ω)
    @tullio shot_noise := conj(∂Xmm∂u[ω,j]) * ∂Xmm∂u[ω,j]
    @tullio ∂Xmm∂u_U[ω] := ∂Xmm∂u[ω,j] * U[j]
    @tullio excess_noise := δF_in_ω[ω] * conj(∂Xmm∂u_U[ω]) * ∂Xmm∂u_U[ω]
    var_X = real.(shot_noise + excess_noise)
    return var_X
end
