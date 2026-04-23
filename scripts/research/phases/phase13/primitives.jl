# ═══════════════════════════════════════════════════════════════════════════════
# Phase 13 Primitives — gauge fix, polynomial projection, phase similarity
# ═══════════════════════════════════════════════════════════════════════════════
#
# READ-ONLY consumer of scripts/common.jl and scripts/raman_optimization.jl.
# This module DOES NOT modify any existing file. It only adds analysis helpers
# used by scripts/gauge_and_polynomial.jl and the Phase 13 test suite.
#
# Constants use the P13_ prefix per STATE.md's "Script Constant Prefixes"
# convention (common.jl uses none, run_comparison.jl uses RC_, etc.).
#
# Physics motivation (from .planning/notes/newton-exploration-summary.md):
#   The Raman-suppression cost J = E_band / E_total depends only on |uωf|².
#   The optimal input phase φ_opt is therefore defined only up to the gauge
#   family   φ_opt(ω) → φ_opt(ω) + C + α · ω.   Removing (C, α) collapses
#   the apparent "different starts give different phases" symptom whenever
#   the residual structure is identical. The residual is then projected onto
#   an orthonormalised polynomial basis (orders 2..6) so that (GDD, TOD, FOD,
#   …) coefficients can be tabulated across random starts and (L, P) sweeps.
#
# Library API:
#   gauge_fix(phi, band_mask, omega)                       -> (phi_fixed, (C, α))
#   polynomial_project(phi, omega, band_mask; orders=2:6)  -> NamedTuple
#   phase_similarity(phi_a, phi_b, band_mask)              -> NamedTuple
#   input_band_mask(uω0; energy_fraction=0.999)            -> BitVector
#   omega_vector(sim_omega0, sim_Dt, Nt)                   -> Vector{Float64}
#   determinism_check(; config, seed, max_iter)            -> NamedTuple
#
# All functions are pure and allocate their outputs. They do not mutate inputs.
# ═══════════════════════════════════════════════════════════════════════════════

# Module-level imports must live OUTSIDE any include guard so macros (@sprintf,
# @assert with string interpolation, etc.) are visible at compile time.
# Per STATE.md Include Guards convention.
using LinearAlgebra
using Statistics
using Printf
using Random
using FFTW

# NOTE: we intentionally include common.jl (read-only) to reuse setup_raman_problem
# and spectral_band_cost. We do not modify it. Its own include guard makes
# re-including cheap.
include(joinpath(@__DIR__, "..", "..", "..", "lib", "common.jl"))

if !(@isdefined _PHASE13_PRIMITIVES_LOADED)

const _PHASE13_PRIMITIVES_LOADED = true
const P13_VERSION = "1.0.0"
const P13_DEFAULT_POLY_ORDER = 2:6                   # which polynomial orders to project onto
const P13_INPUT_BAND_ENERGY_FRACTION = 0.999         # fraction of |uω0|² energy captured by band
const P13_DEFAULT_SEED = 42
const P13_DEFAULT_MAX_ITER = 30

# ─────────────────────────────────────────────────────────────────────────────
# Frequency grid utilities
# ─────────────────────────────────────────────────────────────────────────────

"""
    omega_vector(sim_omega0, sim_Dt, Nt)

Build the per-bin **angular-frequency offset** vector (rad/ps) in FFT order
from the scalar ω₀ and Δt stored inside the existing JLD2 files.

The convention in this codebase (see STATE.md Unit Conventions) is:
- `sim_omega0` stored in rad/ps (carrier ω₀)
- `sim_Dt` stored in picoseconds
- spectral arrays in FFT order (not fftshifted)

The returned vector is `2π · fftfreq(Nt, 1/Δt)` — i.e., the **offset** from ω₀,
which is the correct basis for the linear gauge fit (removing `α · ω` means
removing a group-delay-like translation of the pulse centered on ω₀).
"""
function omega_vector(sim_omega0::Real, sim_Dt::Real, Nt::Integer)
    @assert sim_Dt > 0 "sim_Dt must be positive, got $sim_Dt"
    @assert Nt > 0 && ispow2(Nt) "Nt must be a positive power of 2, got $Nt"
    # fftfreq returns THz (if Δt is in ps); multiply by 2π to get rad/ps offsets.
    Δf = fftfreq(Nt, 1 / sim_Dt)
    return 2π .* collect(Δf)
end

# ─────────────────────────────────────────────────────────────────────────────
# Input-band mask construction
# ─────────────────────────────────────────────────────────────────────────────

"""
    input_band_mask(uω0; energy_fraction=P13_INPUT_BAND_ENERGY_FRACTION)

Return the Boolean mask of FFT bins that carry the input pulse energy.

This is what PITFALLS.md calls `band_mask_input`. The JLD2 files store
`band_mask` = the **output** Raman-band mask (`Δf < raman_threshold`), NOT
the input mask. We reconstruct the input mask from the stored input
spectrum `uomega0` so the gauge fix can be applied over the correct support.

The default threshold of 99.9% of cumulative |uω0|² energy captures the
sech² pulse's frequency extent while rejecting bins that are numerically
zero. Results are robust to ±0.1% changes in `energy_fraction`.

# Arguments
- `uω0`: Complex spectrum of shape (Nt, M) or length Nt; only |·|² matters

# Keyword arguments
- `energy_fraction`: cumulative energy cutoff (default 0.999)
"""
function input_band_mask(uω0::AbstractArray{<:Complex};
                         energy_fraction::Real=P13_INPUT_BAND_ENERGY_FRACTION)
    @assert 0 < energy_fraction ≤ 1 "energy_fraction must be in (0, 1], got $energy_fraction"
    # Collapse M modes if present (2D); else treat as vector.
    power = ndims(uω0) == 1 ? abs2.(uω0) : vec(sum(abs2.(uω0), dims=2))
    Nt = length(power)
    @assert Nt >= 2 "need at least 2 bins"
    E_total = sum(power)
    @assert E_total > 0 "input spectrum has zero energy"
    # Sort bins by power descending, accumulate until we reach energy_fraction of total,
    # then unmark those bins. This gives a minimal mask covering the requested fraction.
    order = sortperm(power; rev=true)
    mask = falses(Nt)
    E_cum = 0.0
    cutoff = energy_fraction * E_total
    for idx in order
        mask[idx] = true
        E_cum += power[idx]
        E_cum >= cutoff && break
    end
    return mask
end

# ─────────────────────────────────────────────────────────────────────────────
# gauge_fix
# ─────────────────────────────────────────────────────────────────────────────

"""
    gauge_fix(phi, band_mask, omega)

Apply the PITFALLS.md Pitfall 4 gauge removal to a spectral phase profile.
Removes the two-parameter gauge symmetry `φ → φ + C + α·ω` of the Raman
suppression cost functional.

# Algorithm
1. Restrict to the input spectral band `band_mask` where the pulse has energy.
2. `C = mean(φ[band_mask])` — remove the constant (global phase).
3. Fit `α` by least squares so that `α · (ω - mean(ω[band_mask]))`
   best explains `(φ - C)[band_mask]` over the input band.
4. `φ_fixed = φ - C - α · (ω - mean(ω[band_mask]))` evaluated on the
   full grid; gauge removal is well-defined outside the band because
   the transformation is linear in ω.

We center `ω` on `mean(ω[band_mask])` before the linear fit so that
(C, α) are numerically decoupled (otherwise the matrix `[1, ω]` is
ill-conditioned whenever the band is far from ω=0).

# Arguments
- `phi`: Real vector of length Nt (or (Nt, 1) matrix) — spectral phase in radians
- `band_mask`: Vector{Bool}/BitVector of length Nt — input spectral support
- `omega`: Real vector of length Nt — angular frequency offsets (rad/ps), FFT order

# Returns
- `phi_fixed`: Vector{Float64} of length Nt, gauge-fixed phase
- `(C, alpha)`: the removed constant and linear coefficient

# PRECONDITIONS
- length(phi) == length(band_mask) == length(omega)
- sum(band_mask) >= 2 (need at least 2 points for a linear fit)

# POSTCONDITIONS (verified by tests)
- mean(phi_fixed[band_mask]) ≈ 0 to within 1e-12
- linear least-squares fit of phi_fixed[band_mask] over omega[band_mask]
  has slope ≈ 0 to within 1e-12
- The cost J is invariant under gauge removal (tested empirically)
"""
function gauge_fix(phi::AbstractArray{<:Real},
                   band_mask::AbstractVector{Bool},
                   omega::AbstractVector{<:Real})
    phi_vec = vec(phi)
    @assert length(phi_vec) == length(band_mask) == length(omega) "size mismatch: $(length(phi_vec)), $(length(band_mask)), $(length(omega))"
    @assert sum(band_mask) >= 2 "need at least 2 input-band bins for linear fit, got $(sum(band_mask))"
    @assert all(isfinite, phi_vec) "phi contains non-finite values"
    @assert all(isfinite, omega) "omega contains non-finite values"

    phi_b = phi_vec[band_mask]
    omega_b = omega[band_mask]
    ω_mean = mean(omega_b)
    omega_c = omega_b .- ω_mean
    # Constant offset
    C = mean(phi_b)
    # Linear slope, fit with intercept removed (centered regression)
    denom = sum(omega_c .^ 2)
    @assert denom > 0 "degenerate omega within band_mask (zero variance)"
    alpha = sum(omega_c .* (phi_b .- C)) / denom
    # Apply gauge removal globally: linear transformation in ω is well-defined everywhere
    phi_fixed = phi_vec .- C .- alpha .* (omega .- ω_mean)
    # Restore original shape (Nt, 1) if input was a matrix
    if ndims(phi) == 2
        phi_fixed = reshape(phi_fixed, size(phi))
    end
    return phi_fixed, (C, alpha)
end

# ─────────────────────────────────────────────────────────────────────────────
# polynomial_project
# ─────────────────────────────────────────────────────────────────────────────

"""
    polynomial_project(phi, omega, band_mask; orders=2:6)

Project `phi` (assumed already gauge-fixed) onto a polynomial basis
`{x^n : n ∈ orders}` over the input band, where `x = 2·(ω − ω_mean)/ω_range`
is the scaled variable (∈ [-1, 1] on the band). QR-orthonormalisation of the
design matrix is used so the monomial fit stays well-conditioned at orders 5-6.

# Returns a NamedTuple with fields:
- `coeffs`: NamedTuple `(a2=…, a3=…, a4=…, a5=…, a6=…)` — the coefficients
  in the **scaled** monomial basis `x^n`; `omega_mean` and `omega_range`
  are also attached so callers can reconstruct without ambiguity
- `phi_poly`: Vector{Float64} of length Nt, polynomial reconstruction
  over the FULL frequency grid (extrapolates outside the band, which is
  meaningful for scaled monomials)
- `residual_fraction`: `‖phi − phi_poly‖²_band / max(‖phi‖²_band, eps)`, ∈ [0, ∞)
  but typically in [0, 1]. A value near 0 means the low-order polynomial
  fully explains the gauge-fixed phase.

# PRECONDITIONS
- phi has been gauge-fixed (mean ≈ 0, slope ≈ 0 over band). Not enforced here
  — caller's responsibility.
- `orders` is an increasing subset of {1, 2, 3, …}. Typical use: 2:6.
"""
function polynomial_project(phi::AbstractArray{<:Real},
                            omega::AbstractVector{<:Real},
                            band_mask::AbstractVector{Bool};
                            orders::AbstractRange=P13_DEFAULT_POLY_ORDER)
    phi_vec = vec(phi)
    @assert length(phi_vec) == length(omega) == length(band_mask) "size mismatch"
    @assert sum(band_mask) >= length(orders) + 1 "need more band bins than polynomial orders ($(sum(band_mask)) vs $(length(orders)))"
    @assert all(isfinite, phi_vec) "phi contains non-finite values"
    @assert step(orders) == 1 "orders range must have step=1"

    omega_b = omega[band_mask]
    phi_b = phi_vec[band_mask]
    ω_mean = mean(omega_b)
    ω_range = maximum(omega_b) - minimum(omega_b)
    @assert ω_range > 0 "degenerate omega range within band_mask"

    x_b = 2 .* (omega_b .- ω_mean) ./ ω_range   # ∈ [-1, 1]
    # Design matrix with one column per requested order
    A = zeros(length(x_b), length(orders))
    for (k, n) in enumerate(orders)
        A[:, k] = x_b .^ n
    end
    # QR with pivoting for stability; solve in two steps so we end up with
    # coefficients in the raw x^n basis (matches the user-visible `a_n` names).
    Q, R = qr(A)
    Qfull = Matrix(Q)
    c_ortho = Qfull' * phi_b           # coefficients in the Q basis
    c_mono = R \ c_ortho                # coefficients in the x^n basis

    # Reconstruct over the full grid
    x_full = 2 .* (omega .- ω_mean) ./ ω_range
    phi_poly = zeros(length(omega))
    for (k, n) in enumerate(orders)
        phi_poly .+= c_mono[k] .* x_full .^ n
    end

    # Residual over the input band (this is the unexplained-variance fraction)
    resid_b = phi_b .- phi_poly[band_mask]
    denom = sum(phi_b .^ 2)
    residual_fraction = denom > eps() ? sum(resid_b .^ 2) / denom : 0.0

    # Package coefficients into a NamedTuple by order
    pairs = Pair{Symbol, Float64}[]
    for (k, n) in enumerate(orders)
        push!(pairs, Symbol("a$n") => c_mono[k])
    end
    push!(pairs, :omega_mean => ω_mean)
    push!(pairs, :omega_range => ω_range)
    coeffs = NamedTuple(pairs)

    return (coeffs = coeffs, phi_poly = phi_poly, residual_fraction = residual_fraction)
end

# ─────────────────────────────────────────────────────────────────────────────
# phase_similarity
# ─────────────────────────────────────────────────────────────────────────────

"""
    phase_similarity(phi_a, phi_b, band_mask)

Similarity metrics between two gauge-fixed phase profiles, restricted to the
input band so that out-of-band bin noise doesn't dominate.

Returns a NamedTuple:
- `rms_diff`: RMS pointwise difference over the band (radians)
- `cosine_sim`: dot(a,b) / (‖a‖·‖b‖), invariant under positive scaling; ∈ [-1, 1]

Both metrics are symmetric in (a, b). The cosine similarity reaches 1 iff
phi_a and phi_b are identical up to a positive scalar multiple over the band.
"""
function phase_similarity(phi_a::AbstractArray{<:Real},
                          phi_b::AbstractArray{<:Real},
                          band_mask::AbstractVector{Bool})
    a = vec(phi_a)[band_mask]
    b = vec(phi_b)[band_mask]
    @assert length(a) == length(b) "phi vectors must have the same length"
    @assert length(a) >= 2 "need at least 2 band bins"
    rms_diff = sqrt(mean((a .- b) .^ 2))
    na = norm(a); nb = norm(b)
    cos_sim = (na > 0 && nb > 0) ? dot(a, b) / (na * nb) : 0.0
    return (rms_diff = rms_diff, cosine_sim = cos_sim)
end

# ─────────────────────────────────────────────────────────────────────────────
# determinism_check
# ─────────────────────────────────────────────────────────────────────────────

"""
    determinism_check(; config, seed=42, max_iter=30)

Run the L-BFGS + adjoint pipeline twice with identical `Random.seed!(seed)`
and identical configuration, and compare the resulting `phi_opt` arrays
bit-for-bit (`phi_a == phi_b`) and by max-absolute difference.

The same forward-adjoint machinery used in `scripts/raman_optimization.jl`
is invoked here (via `optimize_spectral_phase`). We do NOT modify that
script; we only call the public entry point.

# Keyword arguments
- `config`: NamedTuple of setup_raman_problem kwargs
  (e.g. `(fiber_preset=:SMF28, P_cont=0.2, L_fiber=2.0, Nt=2^13, time_window=40.0, β_order=3)`)
- `seed`: Random seed set immediately before each run
- `max_iter`: L-BFGS iterations (short, this is just a determinism probe)

# Returns a NamedTuple:
- `identical`::Bool    — `phi_a == phi_b` bit-for-bit
- `max_abs_diff`::Float64 — max(abs(phi_a - phi_b))
- `J_a`, `J_b`::Float64   — final linear J for each run
- `notes`::String         — short summary (threading, tolerances)
"""
function determinism_check(;
        config::NamedTuple,
        seed::Integer=P13_DEFAULT_SEED,
        max_iter::Integer=P13_DEFAULT_MAX_ITER)
    # Lazy-load raman_optimization.jl so callers that only need gauge_fix don't
    # pay the PyPlot startup cost. Must use Base.invokelatest when calling
    # the newly-included optimiser because Julia 1.12 enforces stricter
    # world-age semantics on global bindings.
    if !isdefined(Main, :optimize_spectral_phase)
        @eval Main include($(joinpath(@__DIR__, "..", "..", "..", "lib", "raman_optimization.jl")))
    end

    function _one_run()
        Random.seed!(seed)
        # Pin FFTW and BLAS to single-threaded execution so plan creation and
        # reductions are bit-deterministic across runs.
        FFTW.set_num_threads(1)
        BLAS.set_num_threads(1)
        uω0, fiber, sim, band_mask, _Δf, _rt = setup_raman_problem(; config...)
        result = Base.invokelatest(Main.optimize_spectral_phase,
            uω0, fiber, sim, band_mask;
            max_iter=max_iter, log_cost=true)
        Nt = sim["Nt"]; M = sim["M"]
        φ = reshape(copy(result.minimizer), Nt, M)
        J_final, _ = Base.invokelatest(Main.cost_and_gradient,
            φ, uω0, fiber, sim, band_mask)
        return φ, J_final
    end

    phi_a, J_a = _one_run()
    phi_b, J_b = _one_run()
    identical = (phi_a == phi_b)
    max_abs_diff = maximum(abs.(phi_a .- phi_b))
    notes = @sprintf("seed=%d, max_iter=%d, FFTW threads=1, BLAS threads=1, Nt=%d",
        seed, max_iter, length(phi_a))
    return (identical = identical,
            max_abs_diff = max_abs_diff,
            J_a = J_a,
            J_b = J_b,
            notes = notes)
end

# ─────────────────────────────────────────────────────────────────────────────
# cost_invariance_under_gauge (test helper, exported for completeness)
# ─────────────────────────────────────────────────────────────────────────────

"""
    cost_invariance_under_gauge(phi, uω0, fiber, sim, band_mask, omega)

Verify numerically that applying `gauge_fix` to `phi` does not change the
cost J. Used by the test suite; returns `(J_raw, J_fixed, rel_diff)`.
"""
function cost_invariance_under_gauge(phi::AbstractArray{<:Real},
        uω0, fiber, sim, band_mask_input::AbstractVector{Bool},
        omega::AbstractVector{<:Real},
        band_mask_output::AbstractVector{Bool})
    if !isdefined(Main, :cost_and_gradient)
        @eval Main include($(joinpath(@__DIR__, "..", "..", "..", "lib", "raman_optimization.jl")))
    end
    J_raw, _ = Base.invokelatest(Main.cost_and_gradient,
        phi, uω0, fiber, sim, band_mask_output)
    phi_g, _ = gauge_fix(phi, band_mask_input, omega)
    J_fixed, _ = Base.invokelatest(Main.cost_and_gradient,
        phi_g, uω0, fiber, sim, band_mask_output)
    rel_diff = abs(J_raw - J_fixed) / max(abs(J_raw), eps())
    return (J_raw = J_raw, J_fixed = J_fixed, rel_diff = rel_diff)
end

end  # include guard
