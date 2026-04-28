"""
Phase 32 — Acceleration primitives for Raman-suppression optimization.

Pure-library layer. NO heavy compute here (no burst VM, no simulation calls).
Downstream drivers (Phase 32 Plan 02, the three Section 6 experiments) call
the public surface defined here:

- `aitken`                       — Δ² scalar stop-rule diagnostic (RESEARCH §3.2)
- `polynomial_predict`           — linear/quadratic warm-start prediction in a
                                   user-chosen ladder variable (RESEARCH §3.5,
                                   §9 Q3 degree-cap D = min(k-1, max_degree))
- `mpe_combine`                  — Minimal Polynomial Extrapolation (RESEARCH §3.4)
- `rre_combine`                  — Reduced Rank Extrapolation   (RESEARCH §3.4)
- `safeguard_gamma`              — Walker-Ni safeguard on combination weights
- `project_gauge_phi`            — Phase 13 gauge fix (remove exact Hessian
                                   null-modes: mean shift + ω-linear slope)
- `classify_acceleration_verdict`— stop-rule classifier; pre-registered
                                   thresholds (ACCEL_STOP_*) locked in code

Also re-exports a delegating `attach_acceleration_metadata!` wrapper so callers
can `include("scripts/acceleration.jl")` and get the trust-schema attacher
without a second include.

Include-guard safe (double-include does not re-define constants).
"""

using LinearAlgebra
using Statistics

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "numerical_trust.jl"))

if !(@isdefined _ACCELERATION_JL_LOADED)
const _ACCELERATION_JL_LOADED = true

const ACCELERATION_VERSION = "32.0"

# Pre-registered stop-rule thresholds (RESEARCH §5). Locked — do not tune
# these at execution time; re-planning is the only path to change them.
const ACCEL_STOP_SAVINGS_FRAC       = 0.15   # min iters-saved fraction
const ACCEL_STOP_DB_REGRESSION      = 1.0    # max allowed J_dB endpoint loss
const ACCEL_SAFEGUARD_GAMMA_MAX     = 1e3    # Walker-Ni safeguard threshold
const ACCEL_MAX_DEGREE_DEFAULT      = 2      # RESEARCH §9 Q3 — D = min(k-1, 2)


# ──────────────────────────────────────────────────────────────────────────────
# Aitken Δ² (scalar, stop-rule diagnostic)
# ──────────────────────────────────────────────────────────────────────────────

"""
    aitken(seq::AbstractVector{<:Real}) -> Real

Return the Aitken Δ² extrapolated limit using the last three entries of `seq`,
or `NaN` when the denominator `Δ²a = c - 2b + a` is too close to zero.

Used as a scalar stop-rule diagnostic — does the cost sequence `J_dB[k]`
already look converged? If `|a∞ - seq[end]|` is small, further L-BFGS work is
likely wasted.

# Example
```julia
julia> aitken([1.0, 1.5, 1.75, 1.875, 1.9375])
2.0
```
"""
function aitken(seq::AbstractVector{<:Real})
    length(seq) >= 3 || return NaN
    a, b, c = seq[end-2], seq[end-1], seq[end]
    Δa  = b - a
    Δ²a = c - 2b + a
    abs(Δ²a) < 1e-14 && return NaN
    return a - Δa^2 / Δ²a
end


# ──────────────────────────────────────────────────────────────────────────────
# Polynomial warm-start prediction — the main lever
# ──────────────────────────────────────────────────────────────────────────────

"""
    _vandermonde(s::AbstractVector{<:Real}, D::Integer) -> Matrix{Float64}

Internal helper: build the `k × (D+1)` Vandermonde matrix with columns
`[1, s, s^2, …, s^D]`. Exposed (unexported) for test inspection.
"""
function _vandermonde(s::AbstractVector{<:Real}, D::Integer)
    k = length(s)
    V = Matrix{Float64}(undef, k, D + 1)
    @inbounds for i in 1:k, d in 0:D
        V[i, d + 1] = Float64(s[i])^d
    end
    return V
end

"""
    polynomial_predict(; s_history, phi_history, s_target, max_degree=2) -> Vector{Float64}

Fit a degree-`D` polynomial in the ladder variable `s` to each component of
`phi`, using the `k = length(s_history)` past converged optima, then evaluate
at `s_target`.

The degree is capped at `D = min(k - 1, max_degree)` (RESEARCH §9 Q3). When
`k = 1` the function is the identity fallback (returns `phi_history[end]`).

# Arguments
- `s_history::AbstractVector{<:Real}`: past ladder values (e.g., fiber lengths).
- `phi_history::AbstractVector{<:AbstractVector{<:Real}}`: past converged
  phases, same length as `s_history`, each of common length `Nt`.
- `s_target::Real`: ladder value at which to predict.
- `max_degree::Integer = 2`: hard cap on the polynomial degree.

# Returns
Predicted phase at `s_target` as a `Vector{Float64}` of length `Nt`.
"""
function polynomial_predict(;
        s_history::AbstractVector{<:Real},
        phi_history::AbstractVector{<:AbstractVector{<:Real}},
        s_target::Real,
        max_degree::Integer = ACCEL_MAX_DEGREE_DEFAULT)
    k = length(s_history)
    @assert k == length(phi_history) "s_history / phi_history length mismatch"
    k >= 1 || throw(ArgumentError("polynomial_predict: need ≥ 1 past iterate"))
    D = min(k - 1, Int(max_degree))
    D == 0 && return Vector{Float64}(phi_history[end])
    Nt = length(phi_history[1])
    @assert all(length(p) == Nt for p in phi_history) "inconsistent phi length"
    V = _vandermonde(s_history, D)                 # k × (D+1)
    # Phi: k × Nt
    Phi = Matrix{Float64}(undef, k, Nt)
    @inbounds for i in 1:k
        Phi[i, :] = Float64.(phi_history[i])
    end
    C = V \ Phi                                     # (D+1) × Nt
    v_target = [Float64(s_target)^d for d in 0:D]
    return vec(v_target' * C)
end


# ──────────────────────────────────────────────────────────────────────────────
# MPE — Minimal Polynomial Extrapolation
# ──────────────────────────────────────────────────────────────────────────────

"""
    mpe_combine(phi_hist) -> NamedTuple{(:combined, :gamma)}

Combine `k ≥ 2` past iterates of a fixed-point-like sequence into a predicted
fixed point via Minimal Polynomial Extrapolation (RESEARCH §3.4).

Returns the combined vector and the MPE weights `γ` on the iterates
(`sum(γ) == 1`). On degenerate denominators falls back to the last iterate
with `γ = [NaN, …]`.
"""
function mpe_combine(phi_hist::AbstractVector{<:AbstractVector{<:Real}})
    k = length(phi_hist)
    k >= 2 || throw(ArgumentError("mpe_combine: need ≥ 2 iterates"))
    Nt = length(phi_hist[1])
    # Differences U[:, i] = phi_{i+1} - phi_i, i = 1..k-1
    U = Matrix{Float64}(undef, Nt, k - 1)
    @inbounds for i in 1:(k - 1)
        U[:, i] .= Float64.(phi_hist[i + 1]) .- Float64.(phi_hist[i])
    end

    if k == 2
        γ = [0.5, 0.5]
        combined = 0.5 .* Float64.(phi_hist[1]) .+ 0.5 .* Float64.(phi_hist[2])
        return (combined = combined, gamma = γ)
    end

    # MPE normal equations: solve U[:, 1:end-1] * c = -U[:, end], then
    # γ_unnorm = (c..., 1), γ = γ_unnorm / sum(γ_unnorm).
    A = U[:, 1:end - 1]
    b = -U[:, end]
    c = A \ b
    γ_unnorm = vcat(c, 1.0)
    s = sum(γ_unnorm)
    if abs(s) < 1e-14
        return (combined = Vector{Float64}(phi_hist[end]),
                gamma    = fill(NaN, k))
    end
    γ = γ_unnorm ./ s
    combined = zeros(Float64, Nt)
    @inbounds for i in 1:k
        combined .+= γ[i] .* Float64.(phi_hist[i])
    end
    return (combined = combined, gamma = γ)
end


# ──────────────────────────────────────────────────────────────────────────────
# RRE — Reduced Rank Extrapolation
# ──────────────────────────────────────────────────────────────────────────────

"""
    rre_combine(phi_hist) -> NamedTuple{(:combined, :gamma)}

Combine `k ≥ 2` past iterates via Reduced Rank Extrapolation (RESEARCH §3.4).

For `k = 2` this reduces to a simple 1/2–1/2 average (matches MPE). For
`k ≥ 3` we solve `(F^T F) η = 1`, normalize `η`, and convert per-difference
weights to per-iterate weights `γ` with `sum(γ) == 1`.
"""
function rre_combine(phi_hist::AbstractVector{<:AbstractVector{<:Real}})
    k = length(phi_hist)
    k >= 2 || throw(ArgumentError("rre_combine: need ≥ 2 iterates"))
    Nt = length(phi_hist[1])

    if k == 2
        γ = [0.5, 0.5]
        combined = 0.5 .* Float64.(phi_hist[1]) .+ 0.5 .* Float64.(phi_hist[2])
        return (combined = combined, gamma = γ)
    end

    # Build first-differences F (Nt × k-1).
    F = Matrix{Float64}(undef, Nt, k - 1)
    @inbounds for i in 1:(k - 1)
        F[:, i] .= Float64.(phi_hist[i + 1]) .- Float64.(phi_hist[i])
    end
    # RRE (Eddy 1979 / Mesina 1977, iterate-weight form): solve the
    # least-squares problem   min_{c} ‖F[:, 1:end-1] * c + F[:, end]‖
    # and set γ_unnorm = [c; 1], then γ = γ_unnorm / sum(γ_unnorm).
    # This is algebraically identical to MPE on the k-iterate sequence but
    # is solved via SVD-pseudoinverse so that rank-deficient F (the generic
    # case for iterates from a linear fixed-point iteration) is handled
    # without blowing up. For ill-conditioned but non-degenerate F, the
    # pinv solution is the minimum-norm least-squares solution, which
    # matches the Walker-Ni safeguard philosophy.
    A = F[:, 1:end - 1]
    b = -F[:, end]
    local c::Vector{Float64}
    try
        c = pinv(A) * b
    catch
        return (combined = Vector{Float64}(phi_hist[end]),
                gamma    = fill(NaN, k))
    end
    γ_unnorm = vcat(c, 1.0)
    if any(!isfinite, γ_unnorm)
        return (combined = Vector{Float64}(phi_hist[end]),
                gamma    = fill(NaN, k))
    end
    s = sum(γ_unnorm)
    if abs(s) < 1e-14
        return (combined = Vector{Float64}(phi_hist[end]),
                gamma    = fill(NaN, k))
    end
    γ = γ_unnorm ./ s
    combined = zeros(Float64, Nt)
    @inbounds for i in 1:k
        combined .+= γ[i] .* Float64.(phi_hist[i])
    end
    return (combined = combined, gamma = γ)
end


# ──────────────────────────────────────────────────────────────────────────────
# Walker-Ni safeguard
# ──────────────────────────────────────────────────────────────────────────────

"""
    safeguard_gamma(γ; threshold=ACCEL_SAFEGUARD_GAMMA_MAX) -> (passed::Bool, reason::String)

Reject an extrapolation combination whose weights blow up beyond `threshold`
(default `1e3`). Also rejects non-finite entries. This is the pre-registered
gate used by Plan 02's reference driver before committing an accelerated prediction.

# Returns
- `(true,  "ok")`                                       if `max|γ| ≤ threshold`.
- `(false, "max|γ| exceeded threshold … (got …)")`      if exceeded.
- `(false, "γ contains non-finite entries")`            if any entry is `NaN`/`Inf`.
"""
function safeguard_gamma(γ::AbstractVector{<:Real};
                         threshold::Real = ACCEL_SAFEGUARD_GAMMA_MAX)
    any(!isfinite, γ) && return (false, "γ contains non-finite entries")
    m = maximum(abs, γ)
    m > threshold && return (false,
        "max|γ| exceeded threshold $threshold (got $m)")
    return (true, "ok")
end


# ──────────────────────────────────────────────────────────────────────────────
# Phase 13 gauge projection
# ──────────────────────────────────────────────────────────────────────────────

"""
    project_gauge_phi(phi, ω, band_mask) -> Vector{Float64}

Remove the two exact Hessian null-modes Phase 13 identified:

1. The constant shift (adding `c` to every φ leaves the cost invariant).
2. The ω-linear slope on the input band (adding `α·ω` leaves the cost
   invariant when evaluated on band-masked frequencies).

Subtract the band-masked mean, then the band-masked ω-linear slope, from
`phi`. Both subtractions are applied globally (not just on the band) — the
gauge modes are global, but they are *measured* on the band.

Called before combining iterates (MPE/RRE) so weight blowup along the null
directions is prevented.

# Returns
A new phase vector with `mean(result[band]) ≈ 0` and the band-restricted
ω-linear slope ≈ 0.
"""
function project_gauge_phi(phi::AbstractVector{<:Real},
                           ω::AbstractVector{<:Real},
                           band_mask::AbstractVector{Bool})
    @assert length(phi) == length(ω) == length(band_mask) "length mismatch"
    inds = findall(band_mask)
    isempty(inds) && return Vector{Float64}(phi)
    φ = Float64.(phi)
    ω_f = Float64.(ω)

    # 1) Subtract band-mean (global).
    μ = mean(view(φ, inds))
    φ .-= μ

    # 2) Subtract band-linear slope (global).
    ωb = view(ω_f, inds)
    yb = view(φ,   inds)
    ω_mean = mean(ωb)
    y_mean = mean(yb)
    ωb_c = ωb .- ω_mean
    yb_c = yb .- y_mean
    denom = dot(ωb_c, ωb_c)
    slope = denom < 1e-30 ? 0.0 : dot(ωb_c, yb_c) / denom
    # Remove slope * (ω - ω_mean_band) so the band-mean stays at 0 after
    # this subtraction (ωb - ω_mean integrates to zero over the band).
    φ .-= slope .* (ω_f .- ω_mean)
    return φ
end


# ──────────────────────────────────────────────────────────────────────────────
# Stop-rule classifier
# ──────────────────────────────────────────────────────────────────────────────

"""
    classify_acceleration_verdict(metrics::Dict) -> String ∈ {"WORTH_IT", "NOT_WORTH_IT", "INCONCLUSIVE"}

Return the pre-registered Phase 32 verdict given a metrics dict.

Expected keys (all optional with safe defaults):
- `"savings_frac"::Float64`   — `(total_naive_iters - total_accel_iters) / total_naive_iters`
- `"worst_verdict_delta"::Int`— `rank(accel) - rank(naive)` over PASS<MARGINAL<SUSPECT;
                                values `> 0` mean the accelerated path regressed trust.
- `"db_delta"::Float64`       — `J_dB_accel[K] - J_dB_naive[K]`; positive = worse.
- `"new_hard_halt"::Bool`     — `true` if the accelerated run triggered a hard
                                halt (e.g., `path_status == "broken"`) that the
                                naive run did not.

# Decision
1. `new_hard_halt == true` ⇒ `"NOT_WORTH_IT"`.
2. `worst_verdict_delta > 0` ⇒ `"NOT_WORTH_IT"` (trust regression).
3. `savings_frac < ACCEL_STOP_SAVINGS_FRAC` (0.15) ⇒ `"NOT_WORTH_IT"`.
4. `db_delta > ACCEL_STOP_DB_REGRESSION` (1.0 dB) ⇒ `"INCONCLUSIVE"`.
5. Otherwise ⇒ `"WORTH_IT"`.
"""
function classify_acceleration_verdict(metrics::Dict)::String
    s   = Float64(get(metrics, "savings_frac", 0.0))
    vΔ  = Int(get(metrics, "worst_verdict_delta", 0))
    dbΔ = Float64(get(metrics, "db_delta", 0.0))
    hh  = Bool(get(metrics, "new_hard_halt", false))
    hh                             && return "NOT_WORTH_IT"
    vΔ > 0                         && return "NOT_WORTH_IT"
    s < ACCEL_STOP_SAVINGS_FRAC    && return "NOT_WORTH_IT"
    dbΔ > ACCEL_STOP_DB_REGRESSION && return "INCONCLUSIVE"
    return "WORTH_IT"
end

end  # include guard
