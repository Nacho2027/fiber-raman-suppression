# scripts/trust_region_preconditioner.jl — Phase 34 preconditioner factories.
#
# Preconditioner factories for PreconditionedCGSolver.
#
# Zero-HVP:
#   build_diagonal_precond(uω0)     — physics power-profile diagonal
#   build_dispersion_precond(sim)   — dispersion-kernel diagonal
#
# K-HVP (reduced-basis, Plan 03):
#   build_dct_precond(H_op, Nt, K)  — DCT-II reduced Hessian + Tikhonov shift
#
# Private helper:
#   _build_dct_basis(Nt, K)         — DCT-II basis, inlined copy of
#                                     amplitude_optimization.jl::build_dct_basis
#                                     (see header comment at top for rationale)
#
# READ-ONLY consumer of LinearAlgebra and Statistics. Does NOT include
# common.jl, ODE solvers, or trust_region_core.jl.
#
# Apply-function contract (what PreconditionedCGSolver expects):
#   M_inv(v::AbstractVector{<:Real}) -> Vector{Float64}
# where M is SPD (so M_inv is well-defined) and M ≈ H (so M_inv ≈ H⁻¹).

using LinearAlgebra
using Statistics

# Private DCT-II basis helper. MATHEMATICALLY identical to
# `scripts/amplitude_optimization.jl::build_dct_basis` (Phase 31, lines 180-192).
# Inlined here to keep `trust_region_preconditioner.jl` at the utility tier (no
# dependency on the heavy amplitude-optimization driver, which activates Pkg at
# module level). If `build_dct_basis` is ever extracted to a shared utility
# module, replace this private helper with an `include` + call.
function _build_dct_basis(Nt::Int, K::Int; bandwidth_mask = nothing)
    B = zeros(Nt, K)
    @inbounds for k in 0:K-1
        for i in 1:Nt
            B[i, k+1] = cos(k * π * (i - 0.5) / Nt)
        end
        B[:, k+1] ./= norm(B[:, k+1])
    end
    if bandwidth_mask !== nothing
        B .*= bandwidth_mask
    end
    return B
end

if !(@isdefined _TRUST_REGION_PRECONDITIONER_JL_LOADED)
const _TRUST_REGION_PRECONDITIONER_JL_LOADED = true

"""
    build_diagonal_precond(uω0; normalize=true, floor=1e-6) -> Function

Physics-informed diagonal preconditioner based on the input pulse power spectrum.

# Math
Constructs a diagonal vector `d` from the mean spectral power across spatial modes:

    d_i = max(|uω0_i|² / mean(|uω0|²), floor · max_power)

The preconditioner returns `M_inv(v) = v ./ d` — pointwise division.

# Arguments
- `uω0::AbstractMatrix{<:Complex}`: input spectrum, shape `(Nt, M)`, where `M` is
  the number of spatial modes. For SMF28 (single-mode fiber), `M=1`.
- `normalize::Bool=true`: if true, divide the power profile by its mean so the
  preconditioner has unit mean (prevents global step rescaling).
- `floor::Float64=1e-6`: minimum fraction of `maximum(power)` below which entries
  are clamped. Prevents division by ≈0 at frequencies with no pulse energy
  (where the preconditioner is physically undefined).

# Cost
0 HVPs — purely a function of the input field at setup time.

# Return
A closure `M_inv::Function` such that `M_inv(v) = v ./ d` for `v::Vector{Float64}`.

# Mode replication
For M > 1, the length-Nt power profile is repeated M times to match the gradient
dimension `n = Nt * M`. Each mode sees the same frequency-dependent preconditioner
(all modes share the same spectral envelope by this approximation).

# Gauge safety note
The output vector `v ./ d` lives in the same space as `v`; if `v` is gauge-projected,
the output is NOT guaranteed gauge-projected because pointwise division does not
commute with the gauge projector in general. PCG must project the output if strict
gauge safety is required.
"""
function build_diagonal_precond(uω0::AbstractMatrix{<:Complex};
                                normalize::Bool = true,
                                floor::Float64 = 1e-6)
    Nt, M = size(uω0)
    # Average power across spatial modes: length-Nt vector
    power = vec(mean(abs2.(uω0), dims=2))

    # Normalize so preconditioner has unit mean (prevents global scale drift)
    if normalize
        μ = mean(power)
        if μ > 0
            power = power ./ μ
        end
    end

    # Clamp to floor * max to prevent division by ≈0
    max_power = maximum(power)
    floor_val = floor * max_power
    d_nt = map(x -> max(x, floor_val), power)

    # Replicate across M modes so d has length Nt*M (matching gradient dimension)
    d = repeat(d_nt, M)

    n_expected = Nt * M
    return v -> begin
        n_v = length(v)
        @assert n_v == n_expected "build_diagonal_precond closure: expected length $n_expected got $n_v"
        out = similar(Vector{Float64}, n_v)
        @inbounds for i in 1:n_v
            out[i] = v[i] / d[i]
        end
        return out
    end
end

"""
    build_dispersion_precond(sim; α_shift=1.0, floor=1e-6) -> Function

Dispersion-kernel diagonal preconditioner.

# Math
Approximates the diagonal of the Hessian using the angular frequency grid:

    d_i = 1 + α_shift · (ω_i / max|ω|)²

The preconditioner returns `M_inv(v) = v ./ d` — pointwise division.

# Physics rationale
The Hessian of the linear-dispersion phase-to-field mapping is approximately
diagonal in frequency with entries ∝ β₂·ω². Without an explicit β₂, this
approximation uses the normalized ω² profile; the overall scale is absorbed
into α_shift. The +1 ensures the preconditioner is SPD (d ≥ 1 always).

# Arguments
- `sim::Dict{String,Any}`: simulation parameter dict with keys `"Nt"`, `"ωs"`,
  and optionally `"M"` (defaults to 1 if missing).
- `α_shift::Float64=1.0`: weight for the ω² term. Larger values emphasize
  the dispersion correction; setting to 0 gives the identity preconditioner.
- `floor::Float64=1e-6`: minimum allowed `d` value (avoids division by 0 if
  α_shift=0 is used; effectively unused for the default parameters since d ≥ 1).

# Cost
0 HVPs — purely a function of the frequency grid.

# Return
A closure `M_inv::Function` such that `M_inv(v) = v ./ d` for `v::Vector{Float64}`.

# Mode replication
For M > 1, the length-Nt dispersion vector is repeated M times to match `n = Nt*M`.

# Gauge safety note
Same as `build_diagonal_precond`: pointwise division does not guarantee gauge
projection is preserved. PCG must re-project if strict gauge safety is required.
"""
function build_dispersion_precond(sim::Dict;
                                  α_shift::Float64 = 1.0,
                                  floor::Float64 = 1e-6)
    Nt = sim["Nt"]
    M  = get(sim, "M", 1)
    ω  = sim["ωs"]  # rad/ps, fftfreq convention

    # Normalized ω² profile: dimensionless, O(0–1)
    ω_max = maximum(abs.(ω))
    ω_norm = ω ./ (ω_max > 0 ? ω_max : 1.0)
    d_nt = 1.0 .+ α_shift .* (ω_norm .^ 2)

    # Floor to guard against pathological α_shift = 0 edge case
    d_nt = map(x -> max(x, floor), d_nt)

    # Replicate across M modes
    d = repeat(d_nt, M)

    n_expected = Nt * M
    return v -> begin
        n_v = length(v)
        @assert n_v == n_expected "build_dispersion_precond closure: expected length $n_expected got $n_v"
        out = similar(Vector{Float64}, n_v)
        @inbounds for i in 1:n_v
            out[i] = v[i] / d[i]
        end
        return out
    end
end

"""
    build_dct_precond(H_op, Nt, K; σ_shift=:auto, bandwidth_mask=nothing) -> Function

Reduced-basis DCT preconditioner (RESEARCH.md §Preconditioner 2).

Builds the K×K reduced Hessian `H_r = B' * H * B` by K calls to `H_op`, where
`B ∈ ℝ^{Nt×K}` is the DCT-II basis from `scripts/amplitude_optimization.jl`.
Adds Tikhonov shift σ to make `H_r + σI` SPD (H itself is typically indefinite
— see Phase 22 spectra). When `σ_shift == :auto`, uses
    σ = max(0, -eigmin(H_r)) + eps() * tr(H_r) / K.

Returns a closure `M_inv::Function` such that
    M_inv(v) = B * ((H_r + σI) \\ (B' * v)) + (v - B * (B' * v))
i.e. the reduced solve on the DCT subspace + identity on the complement.

# Cost
- Build: K HVPs. At Nt=2^13 on the burst VM (≈5s/HVP), K=64 is ~320s.
- Apply: O(K·Nt) mat-vec + K×K triangular solve via pre-factored Cholesky.

# Arguments
- `H_op`          : callable `v::Vector -> H*v::Vector` (1 HVP each call)
- `Nt`, `K`       : grid size and reduced-basis size (K ≤ Nt)
- `σ_shift`       : :auto for eigmin-based shift, or a positive Real
- `bandwidth_mask`: optional Nt-length mask passed to `_build_dct_basis`

# Returns
A `Function` `M_inv(v)` with length assertion `length(v) == Nt`.
"""
function build_dct_precond(H_op::Function, Nt::Int, K::Int;
                            σ_shift = :auto,
                            bandwidth_mask = nothing)
    @assert K >= 1 "build_dct_precond: K must be ≥ 1"
    @assert K <= Nt "build_dct_precond: K=$K must be ≤ Nt=$Nt"

    B = _build_dct_basis(Nt, K; bandwidth_mask = bandwidth_mask)

    # Reduced Hessian: H_r[:,i] = B' * (H * B[:,i])
    H_r = zeros(Float64, K, K)
    for i in 1:K
        bi = B[:, i]
        Hbi = H_op(bi)
        @assert length(Hbi) == Nt "build_dct_precond: H_op returned wrong-size output ($(length(Hbi)) != $Nt)"
        H_r[:, i] = B' * Hbi
    end
    H_r = 0.5 .* (H_r .+ H_r')   # symmetrize against FD-HVP noise

    σ = if σ_shift === :auto
        lam_min = eigmin(Symmetric(H_r))
        max(0.0, -lam_min) + eps(Float64) * max(1.0, abs(tr(H_r))) / K
    elseif σ_shift isa Real
        Float64(σ_shift)
    else
        error("build_dct_precond: σ_shift must be :auto or a Real; got $(σ_shift)")
    end

    H_shifted = Symmetric(H_r + σ * I)
    chol = cholesky(H_shifted)    # SPD by construction after shift

    return v -> begin
        @assert length(v) == Nt "build_dct_precond closure: expected length $Nt got $(length(v))"
        Btv = B' * v
        y = chol \ Btv           # K-dim reduced solve
        B_times_y = B * y
        complement = v .- B * Btv  # (I - BB') v : identity on complement
        return B_times_y .+ complement
    end
end

end  # include guard
