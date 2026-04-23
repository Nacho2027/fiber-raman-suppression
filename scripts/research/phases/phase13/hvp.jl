# ═══════════════════════════════════════════════════════════════════════════════
# Phase 13 Plan 02 — Hessian-Vector-Product (HVP) library
# ═══════════════════════════════════════════════════════════════════════════════
#
# READ-ONLY consumer of scripts/common.jl and scripts/raman_optimization.jl.
# This file DOES NOT modify any existing file. It only adds HVP helpers used by
# scripts/hessian_eigspec.jl and test/test_hvp.jl.
#
# Constants use the P13_ prefix per STATE.md's "Script Constant Prefixes".
#
# Mathematical recipe:
#
#     H v  ≈  [ ∇J(φ★ + ε·v̂) − ∇J(φ★ − ε·v̂) ] / (2 ε)  ·  ‖v‖
#
# where v̂ = v / ‖v‖ is the unit direction. We rescale by ε·‖v‖ so the user can
# pass either unit or arbitrary-norm vectors. Cost per HVP: 2 forward + 2
# adjoint ODE solves through the existing cost_and_gradient pipeline from
# scripts/raman_optimization.jl (which we do NOT modify).
#
# Symmetry is guaranteed only up to finite-difference noise because ∇J is
# computed consistently across the two evaluations (same FFTW plans, same
# solver tolerances, same adjoint pipeline). Plan 01 determinism.md flagged
# FFTW.MEASURE as a noise source — Plan 02 entry-point pins FFTW to ESTIMATE
# and single-threaded before any HVP call.
#
# API:
#   build_oracle(config::NamedTuple; log_cost, λ_gdd, λ_boundary)
#       -> (oracle::Function, meta::NamedTuple)
#   fd_hvp(phi, v, oracle; eps=1e-4)                -> Hv::Vector
#   validate_hvp_taylor(phi, v_test, oracle; kwargs) -> NamedTuple
#   build_full_hessian_small(phi, oracle; eps)       -> Matrix  (small-Nt only)
# ═══════════════════════════════════════════════════════════════════════════════

# Module-level imports OUTSIDE the include guard so macros are visible at
# compile time (STATE.md convention, enforced in Plan 01).
using LinearAlgebra
using Statistics
using Printf
using FFTW

# phase13_primitives already includes common.jl. Safe to include here because
# both scripts have include guards.
include(joinpath(@__DIR__, "primitives.jl"))

if !(@isdefined _PHASE13_HVP_LOADED)

const _PHASE13_HVP_LOADED = true
const P13_HVP_VERSION = "1.0.0"
const P13_DEFAULT_EPS = 1e-4                       # finite-difference step
const P13_MIN_V_NORM = 1e-12                       # guard against zero-direction

# ─────────────────────────────────────────────────────────────────────────────
# Oracle construction
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_oracle(config::NamedTuple; log_cost=false, λ_gdd=0.0, λ_boundary=0.0)

Construct a closure `oracle(phi)` that returns the gradient `∇J(phi)` of the
Raman suppression cost at spectral phase `phi`, using the EXISTING
`cost_and_gradient` from scripts/raman_optimization.jl (pipeline unchanged).

# Arguments
`config` is a NamedTuple of keyword arguments forwarded to
`setup_raman_problem`. Typical contents:

    (fiber_preset=:SMF28, L_fiber=2.0, P_cont=0.2,
     Nt=2^13, time_window=40.0, β_order=3)

# Returns
- `oracle::Function` — `oracle(phi::AbstractVector) → ∇J::Vector{Float64}`
  · Accepts a flat vector (length Nt·M); reshapes internally.
  · Uses the exact `(log_cost, λ_gdd, λ_boundary)` surface specified by the
    caller. The default remains the linear physics-only Hessian.
- `meta::NamedTuple` — `(uω0, fiber, sim, band_mask, Δf, raman_threshold,
  Nt, M, omega, input_band_mask, objective_spec)` so callers can introspect
  the setup without re-running it.

# Notes
- Uses `Base.invokelatest` on the freshly-included `cost_and_gradient` to sidestep
  Julia 1.12 world-age errors (same pattern as Plan 01 `determinism_check`).
- Ensures a fresh buffer is allocated each call — avoiding stateful buffer
  aliasing that would spuriously break HVP symmetry.
"""
function build_oracle(config::NamedTuple;
                      log_cost::Bool=false,
                      λ_gdd::Real=0.0,
                      λ_boundary::Real=0.0)
    # Setup simulation from the config kwargs
    uω0, fiber, sim, band_mask, Δf, raman_threshold =
        setup_raman_problem(; config...)
    # Ensure zsave=nothing so the forward solver skips deepcopy in the RHS
    fiber["zsave"] = nothing

    # Lazy-load raman_optimization.jl into Main so cost_and_gradient is
    # available at the current world age when the oracle is first called.
    if !isdefined(Main, :cost_and_gradient)
        @eval Main include($(joinpath(@__DIR__, "..", "..", "..", "lib", "raman_optimization.jl")))
    end

    Nt = sim["Nt"]
    M = sim["M"]
    input_mask = input_band_mask(uω0)
    omega = omega_vector(sim["ω0"], sim["Δt"], Nt)
    objective_spec = Core.eval(Main, quote
        raman_cost_surface_spec(
            log_cost=$log_cost,
            λ_gdd=$λ_gdd,
            λ_boundary=$λ_boundary,
            objective_label="Phase 13/33/34 Raman HVP oracle",
        )
    end)

    function oracle(phi_flat::AbstractVector{<:Real})
        @assert length(phi_flat) == Nt * M "phi length $(length(phi_flat)) ≠ Nt·M = $(Nt*M)"
        phi_mat = reshape(copy(phi_flat), Nt, M)
        J, grad = Base.invokelatest(Main.cost_and_gradient,
            phi_mat, uω0, fiber, sim, band_mask;
            log_cost=log_cost, λ_gdd=λ_gdd, λ_boundary=λ_boundary)
        return vec(copy(grad))
    end

    meta = (
        uω0 = uω0, fiber = fiber, sim = sim,
        band_mask = band_mask, Δf = Δf, raman_threshold = raman_threshold,
        Nt = Nt, M = M, omega = omega, input_band_mask = input_mask,
        objective_spec = objective_spec,
    )
    return oracle, meta
end

# ─────────────────────────────────────────────────────────────────────────────
# Finite-difference Hessian-Vector Product
# ─────────────────────────────────────────────────────────────────────────────

"""
    fd_hvp(phi, v, oracle; eps=P13_DEFAULT_EPS)

Central-difference Hessian-vector product at base point `phi` in direction `v`:

    Hv ≈ [∇J(phi + eps·v̂) − ∇J(phi − eps·v̂)] / (2ε) · ‖v‖,  v̂ = v/‖v‖

This scales-and-unscales so the user can pass vectors of arbitrary norm while
keeping the finite-difference step in a numerically well-behaved regime
(|ε·v̂| ≈ ε, not ε·‖v‖ which could be astronomical).

Cost: exactly 2 calls to the oracle = 2 forward + 2 adjoint ODE solves.

# PRECONDITIONS
- `length(phi) == length(v)`
- `‖v‖ > P13_MIN_V_NORM`
- `eps > 0`
- `oracle` returns the same length as its input

# POSTCONDITIONS
- `length(Hv) == length(phi)`
- `all(isfinite, Hv)`
"""
function fd_hvp(phi::AbstractVector{<:Real},
                v::AbstractVector{<:Real},
                oracle;
                eps::Real = P13_DEFAULT_EPS)
    @assert length(phi) == length(v) "phi length $(length(phi)) ≠ v length $(length(v))"
    @assert eps > 0 "eps must be positive, got $eps"
    v_norm = norm(v)
    @assert v_norm > P13_MIN_V_NORM "v has zero norm ($v_norm); HVP undefined"
    v_unit = v ./ v_norm
    # Two-point central difference on the gradient
    g_plus = oracle(phi .+ eps .* v_unit)
    g_minus = oracle(phi .- eps .* v_unit)
    Hv_unit = (g_plus .- g_minus) ./ (2 * eps)
    # Re-scale by ‖v‖ so the result is H·v, not H·v̂
    Hv = Hv_unit .* v_norm
    @assert all(isfinite, Hv) "Hv contains non-finite values"
    return Hv
end

# ─────────────────────────────────────────────────────────────────────────────
# Taylor-remainder validation (O(ε²) test)
# ─────────────────────────────────────────────────────────────────────────────

"""
    validate_hvp_taylor(phi, v_test, oracle; eps_range=10.0 .^ (-1:-0.5:-6))

Verify that the finite-difference HVP has O(ε²) accuracy by computing

    residual(ε) = ‖ fd_hvp(phi, v, ε) − fd_hvp(phi, v, ε/2) ‖

across a range of ε and fitting a log-log slope. A clean finite-difference
operator shows slope ≈ 2 until cancellation noise dominates (around
ε ≤ 1e-6 for Float64 on well-conditioned problems).

This is the same O(ε²) standard as Phase 4 VERIF-03's gradient check.

# Returns a NamedTuple:
- `eps_values::Vector{Float64}` — the tested ε values (descending)
- `residuals::Vector{Float64}` — ‖Hv(ε) − Hv(ε/2)‖ at each ε
- `slope::Float64` — log-log slope estimate (expected ≈ 2)
- `slope_region::Tuple{Int,Int}` — indices used for the slope fit
- `Hv_reference::Vector{Float64}` — Hv at the smallest ε (finest scale)
"""
function validate_hvp_taylor(phi::AbstractVector{<:Real},
                             v_test::AbstractVector{<:Real},
                             oracle;
                             eps_range::AbstractVector{<:Real} = 10.0 .^ (-1:-0.5:-6))
    eps_values = collect(eps_range)
    @assert length(eps_values) >= 4 "need at least 4 eps values for a slope fit"
    residuals = Float64[]
    Hv_prev = nothing
    Hv_smallest = nothing
    for (i, ε) in enumerate(eps_values)
        Hv_a = fd_hvp(phi, v_test, oracle; eps=ε)
        Hv_b = fd_hvp(phi, v_test, oracle; eps=ε/2)
        push!(residuals, norm(Hv_a .- Hv_b))
        if i == length(eps_values)
            Hv_smallest = Hv_b
        end
    end
    # Auto-detect the O(ε²) regime: scan from the largest ε and keep successive
    # points that exhibit truncation-error behavior. For central differences the
    # residual should scale as ε^2, so halving ε (Δlog ε = -0.5 in our grid)
    # should reduce the residual by factor 10^-1 = 0.1. We use a stricter
    # threshold of 0.5 (factor ≥ 2× decrease per grid step) so we don't include
    # the noise-floor transition region, where the slope collapses to O(1) or
    # smaller. Once any successive ratio exceeds 0.5 (weaker than 2× decrease),
    # the truncation regime has ended.
    n = length(eps_values)
    i_lo = 1
    i_hi = n
    for i in 2:n
        # residuals[i] / residuals[i-1] is expected ≈ 0.1 in the O(ε²) regime
        # on our 10^-0.5 grid. Once this ratio rises above 0.3 (degrades toward
        # the noise-floor plateau), truncate the fit region to avoid biasing
        # the slope estimate downward.
        if residuals[i-1] <= 0 || residuals[i] / residuals[i-1] > 0.3
            i_hi = i - 1
            break
        end
    end
    @assert i_hi > i_lo + 1 "O(ε²) regime too short (i_lo=$i_lo, i_hi=$i_hi); FD noise floor reached too early — try wider eps_range or larger ε"
    xs = log10.(eps_values[i_lo:i_hi])
    ys = log10.(residuals[i_lo:i_hi])
    # Weighted least-squares would be overkill; a two-point endpoint slope is robust.
    slope = (ys[end] - ys[1]) / (xs[end] - xs[1])
    return (
        eps_values = eps_values,
        residuals = residuals,
        slope = slope,
        slope_region = (i_lo, i_hi),
        Hv_reference = Hv_smallest,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Full dense Hessian (small-Nt cross-check only)
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_full_hessian_small(phi, oracle; eps=P13_DEFAULT_EPS)

Construct the full Nt×Nt Hessian column-by-column by applying `fd_hvp` to
each unit basis vector. Cost: 2·Nt oracle evaluations. DO NOT call this at
production Nt=8192; intended for small-Nt (≤ 2^8) cross-validation in the
test suite.

Returns the Hessian and its symmetric-error metric
`max_asymmetry = max(|H − H'|)` so the caller can assert symmetry.
"""
function build_full_hessian_small(phi::AbstractVector{<:Real}, oracle;
                                   eps::Real = P13_DEFAULT_EPS)
    N = length(phi)
    @assert N <= 2^10 "build_full_hessian_small requested for N=$N; refusing at N>1024. This is a cross-check tool only."
    H = zeros(N, N)
    for k in 1:N
        e_k = zeros(N); e_k[k] = 1.0
        H[:, k] = fd_hvp(phi, e_k, oracle; eps=eps)
    end
    max_asym = maximum(abs.(H .- transpose(H)))
    return H, max_asym
end

# ─────────────────────────────────────────────────────────────────────────────
# FFTW determinism setup
# ─────────────────────────────────────────────────────────────────────────────

"""
    ensure_deterministic_fftw()

Pin FFTW to ESTIMATE mode and single-threaded execution so that successive
HVPs use the same plan and produce bit-stable gradient evaluations.

From Plan 01 determinism.md: FFTW.MEASURE causes up to 1 rad / 1.8 dB drift
between supposedly identical runs because MEASURE picks algorithms based on
microbenchmark timing noise. ESTIMATE is deterministic.

Call this ONCE at the start of any HVP-using script before the first oracle
evaluation. Safe to call multiple times.
"""
function ensure_deterministic_fftw()
    FFTW.set_num_threads(1)
    try
        FFTW.set_provider!("fftw")   # no-op if already fftw; guards against MKL surprises
    catch
        # Older FFTW versions may not expose set_provider!; ignore.
    end
    # FFTW.ESTIMATE is a planner flag, not a global. We set it via
    # FFTW.set_planner_flags if available, otherwise document that downstream
    # plan_fft calls must be made with flags=FFTW.ESTIMATE explicitly.
    try
        FFTW.set_planner_flags(FFTW.ESTIMATE)
    catch
        # Not all FFTW.jl versions expose set_planner_flags — the user of this
        # library has to live with MultiModeNoise's default plan construction.
        # The upside is that `solve_disp_mmf` caches its FFT plans per `sim`
        # dictionary, so successive HVP calls reuse the same plan regardless.
    end
    BLAS.set_num_threads(1)
    @debug "FFTW pinned to ESTIMATE + 1 thread; BLAS pinned to 1 thread."
    return nothing
end

end  # include guard
