# scripts/trust_region_preconditioner.jl — Phase 34 preconditioner factories.
#
# Zero-HVP preconditioners for PreconditionedCGSolver. DCT/reduced-basis variant
# is deferred to Plan 03 because it requires K HVPs to build; this file only
# holds the physics-motivated preconditioners that are free at setup time.
#
# READ-ONLY consumer of LinearAlgebra and Statistics. Does NOT include
# common.jl, ODE solvers, or trust_region_core.jl.
#
# Apply-function contract (what PreconditionedCGSolver expects):
#   M_inv(v::AbstractVector{<:Real}) -> Vector{Float64}
# where M is SPD (so M_inv is well-defined) and M ≈ H (so M_inv ≈ H⁻¹).

using LinearAlgebra
using Statistics

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

end  # include guard
