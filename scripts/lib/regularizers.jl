"""
Shared objective-regularization helpers for Raman optimization scripts.

These helpers are intentionally small and mechanical. They encode the discrete
regularizer formulas already used by the SMF, MMF, and multivariable script
paths without changing objective semantics.
"""

if !(@isdefined _REGULARIZERS_JL_LOADED)
const _REGULARIZERS_JL_LOADED = true

using FFTW

"""
    add_gdd_penalty!(grad, φ, Δt, λ_gdd) -> Float64

Add the phase-GDD regularizer gradient to `grad` and return its scalar
contribution. The stencil is
`λ_gdd * (φ[i+1] - 2φ[i] + φ[i-1])^2 / Δω^3`, with
`Δω = 2π / (Nt * Δt)`.
"""
function add_gdd_penalty!(grad::AbstractMatrix, φ::AbstractMatrix,
                          Δt::Real, λ_gdd::Real)
    λ_gdd > 0 || return 0.0
    @assert size(grad) == size(φ) "grad shape $(size(grad)) must match φ shape $(size(φ))"
    Nt = size(φ, 1)
    Δω = 2π / (Nt * Δt)
    inv_Δω3 = 1.0 / Δω^3
    J_gdd = 0.0
    @inbounds for m in 1:size(φ, 2)
        for i in 2:(Nt - 1)
            d2 = φ[i + 1, m] - 2φ[i, m] + φ[i - 1, m]
            J_gdd += λ_gdd * inv_Δω3 * d2^2
            coeff = 2 * λ_gdd * inv_Δω3 * d2
            grad[i - 1, m] += coeff
            grad[i,     m] -= 2 * coeff
            grad[i + 1, m] += coeff
        end
    end
    return J_gdd
end

function add_gdd_penalty!(grad::AbstractVector, φ::AbstractVector,
                          Δt::Real, λ_gdd::Real)
    λ_gdd > 0 || return 0.0
    @assert length(grad) == length(φ) "grad length $(length(grad)) must match φ length $(length(φ))"
    Nt = length(φ)
    Δω = 2π / (Nt * Δt)
    inv_Δω3 = 1.0 / Δω^3
    J_gdd = 0.0
    @inbounds for i in 2:(Nt - 1)
        d2 = φ[i + 1] - 2φ[i] + φ[i - 1]
        J_gdd += λ_gdd * inv_Δω3 * d2^2
        coeff = 2 * λ_gdd * inv_Δω3 * d2
        grad[i - 1] += coeff
        grad[i]     -= 2 * coeff
        grad[i + 1] += coeff
    end
    return J_gdd
end

"""
    add_boundary_phase_penalty!(grad, uω_shaped, λ_boundary; edge_fraction_floor=1e-8)

Add the input temporal-window edge penalty gradient with respect to an
independent phase at every `(ω, mode)` element. Returns the scalar contribution.
"""
function add_boundary_phase_penalty!(grad::AbstractMatrix,
                                     uω_shaped::AbstractMatrix,
                                     λ_boundary::Real;
                                     edge_fraction_floor::Real = 1e-8)
    λ_boundary > 0 || return 0.0
    @assert size(grad) == size(uω_shaped) "grad shape $(size(grad)) must match shaped field $(size(uω_shaped))"
    Nt = size(uω_shaped, 1)
    n_edge = max(1, Nt ÷ 20)
    ut0 = ifft(uω_shaped, 1)
    mask_edge = zeros(Float64, size(uω_shaped))
    mask_edge[1:n_edge, :] .= 1.0
    mask_edge[end - n_edge + 1:end, :] .= 1.0

    E_total_input = max(sum(abs2, ut0), eps())
    E_edges = sum(abs2.(ut0) .* mask_edge)
    edge_frac = E_edges / E_total_input
    edge_frac > edge_fraction_floor || return 0.0

    coeff = 2 * λ_boundary / (Nt * E_total_input)
    grad_boundary_ω = coeff .* imag.(conj.(uω_shaped) .* fft(mask_edge .* ut0, 1))
    grad .+= grad_boundary_ω
    return λ_boundary * edge_frac
end

"""
    add_shared_boundary_phase_penalty!(grad, uω_shaped, λ_boundary)

MMF shared-phase version of [`add_boundary_phase_penalty!`](@ref). Adds the
mode-summed boundary gradient to the vector `grad`.
"""
function add_shared_boundary_phase_penalty!(grad::AbstractVector,
                                            uω_shaped::AbstractMatrix,
                                            λ_boundary::Real;
                                            edge_fraction_floor::Real = 1e-8)
    λ_boundary > 0 || return 0.0
    Nt = size(uω_shaped, 1)
    @assert length(grad) == Nt "grad length $(length(grad)) must equal Nt=$Nt"
    n_edge = max(1, Nt ÷ 20)
    ut0 = ifft(uω_shaped, 1)
    mask_edge = zeros(Float64, Nt)
    mask_edge[1:n_edge] .= 1.0
    mask_edge[end - n_edge + 1:end] .= 1.0

    E_total_input = max(sum(abs2, ut0), eps())
    E_edges = sum(abs2.(ut0) .* mask_edge)
    edge_frac = E_edges / E_total_input
    edge_frac > edge_fraction_floor || return 0.0

    coeff = 2 * λ_boundary / (Nt * E_total_input)
    fft_back = fft(ut0 .* mask_edge, 1)
    grad .+= coeff .* vec(sum(imag.(conj.(uω_shaped) .* fft_back), dims = 2))
    return λ_boundary * edge_frac
end

"""
    apply_log_surface!(grad, J_linear) -> Float64

Scale `grad` by the derivative of `10*log10(J_linear)` and return the dB-scale
scalar. The linear scalar is clamped at `1e-15`, matching the existing scripts.
"""
function apply_log_surface!(grad, J_linear::Real)
    J_clamped = max(J_linear, 1e-15)
    grad .*= 10.0 / (J_clamped * log(10.0))
    return 10.0 * log10(J_clamped)
end

end # include guard
