"""
Sharpness-aware (Hessian-in-cost) optimization entry point (Phase 14).

Parallel path to the vanilla L-BFGS `raman_optimization.jl`: minimizes
`J(φ) + λ · sharpness(H(φ))` where the sharpness term penalizes flat-minimum
directions, producing optima that are more robust to shaper quantization and
fiber-parameter drift. The vanilla cost function and optimizer entry points
are untouched and remain available for A/B comparison.

# Run
    julia --project=. -t auto scripts/lib/sharpness_optimization.jl

# Inputs
- Sharpness measure + λ at top of file.
- `scripts/lib/common.jl` fiber presets.

# Outputs
- `results/raman/phase14/<run_id>/_result.jld2` + `.json` — sharpness-aware run.
- `results/raman/phase14/<run_id>/*.png` — robustness + Hessian-spectrum figures.

# Runtime
~10–20 minutes (Hessian eigensolve adds overhead vs vanilla L-BFGS). Burst VM
recommended.

# Docs
Docs: docs/notes/cost-function-physics.md
"""

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 14 — Sharpness-Aware (Hessian-in-Cost) Optimization
# ═══════════════════════════════════════════════════════════════════════════════
#
# Complement to `scripts/lib/raman_optimization.jl`. Both entry points coexist:
#   • optimize_spectral_phase       — original L-BFGS on J(φ) alone (unchanged)
#   • optimize_spectral_phase_sharp — L-BFGS on  J_sharp(φ) = J(φ) + λ·S(φ)
#
# where S(φ) is a gauge-projected, Hutchinson-style stochastic estimator of
# the local curvature of J excluding the two gauge directions (constant and
# linear-in-ω on the input band) that leave the physical cost invariant.
#
# Math (Plan 14-01):
#   S(φ)      ≈ (1/N_s) Σ_i [J(φ + ε·Pv_i) + J(φ − ε·Pv_i) − 2·J(φ)] / ε²
#   ∂S/∂φ     ≈ (1/N_s) Σ_i [∇J(φ + ε·Pv_i) + ∇J(φ − ε·Pv_i) − 2·∇J(φ)] / ε²
#   J_sharp    = J(φ) + λ·S(φ)
#   ∇J_sharp   = ∇J(φ) + λ·∇S(φ)
#   v_i        : Rademacher (±1) vectors
#   P          : orthogonal projector removing the constant and linear-in-ω
#                gauge modes over the INPUT spectral support.
#
# Why Hutchinson FD on J (not on ∇J / HVPs):
#   • No second-order adjoint required (that’s a multi-week project).
#   • Reuses the existing first-order adjoint (`cost_and_gradient`) unchanged —
#     i.e. this file does NOT modify `raman_optimization.jl` or `common.jl`.
#   • Embarrassingly parallel over the N_s samples (useful when we scale on
#     the burst VM in Plan 14-02).
#
# Design rules enforced by Plan 14-01:
#   1. Zero writes to scripts/lib/common.jl, scripts/lib/raman_optimization.jl, src/.
#      Verified at end of plan via `git diff --stat`.
#   2. SO_ constant prefix per STATE.md "Script Constant Prefixes" convention.
#   3. λ_sharp = 0 must reduce to the vanilla path byte-for-byte (tested).
#
# Library API:
#   build_gauge_projector(omega, band_mask_input)           -> function P(v)
#   sharpness_estimator(phi, oracle, P; eps, n_samples, rng) -> NamedTuple
#   cost_and_gradient_sharp(phi, uω0, fiber, sim, band_mask; ...) -> (J, grad)
#   optimize_spectral_phase_sharp(prob_or_args...; ...)    -> NamedTuple result
#
# Where `prob` here is a NamedTuple:
#   prob = (uω0=…, fiber=…, sim=…, band_mask=…)
# built by `make_sharp_problem(...)` which is a thin wrapper around
# `setup_raman_problem` from common.jl (READ-ONLY use).
# ═══════════════════════════════════════════════════════════════════════════════

# Module-level imports must live OUTSIDE the include guard so macros (@sprintf,
# etc.) are visible at compile time. Per STATE.md Include Guards convention.
using LinearAlgebra
using Statistics
using Printf
using Random
using FFTW
using Optim

# Bring the production pipeline into Main as READ-ONLY consumers.
# Their own include guards keep this cheap on re-inclusion.
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
ensure_deterministic_environment()

if !(@isdefined _SHARPNESS_OPTIMIZATION_LOADED)
const _SHARPNESS_OPTIMIZATION_LOADED = true

const SO_VERSION = "1.0.0"
const SO_DEFAULT_NSAMPLES = 8
const SO_DEFAULT_EPS = 1e-3
const SO_DEFAULT_LAMBDA = 0.1
const SO_DEFAULT_INPUT_BAND_ENERGY_FRACTION = 0.999

# ─────────────────────────────────────────────────────────────────────────────
# Input-band mask (local helper, to avoid depending on primitives.jl
# being loaded — the two files are developed in parallel and we keep this
# library free-standing for determinism-of-test-isolation purposes).
# ─────────────────────────────────────────────────────────────────────────────

"""
    SO_input_band_mask(uω0; energy_fraction=SO_DEFAULT_INPUT_BAND_ENERGY_FRACTION)

Return the Boolean FFT-order mask of bins that carry `energy_fraction` of the
input spectrum |uω0|² energy. Accepts 1D or 2D (multi-mode) spectra.

This is the `band_mask_input` mask required by the gauge projector (NOT the
OUTPUT Raman-band mask returned by `setup_raman_problem`). Semantics match
`scripts/primitives.jl :: input_band_mask`; we re-derive it here to
keep Plan 14 artifacts independent of Phase 13's file layout.
"""
function SO_input_band_mask(uω0::AbstractArray{<:Complex};
                            energy_fraction::Real = SO_DEFAULT_INPUT_BAND_ENERGY_FRACTION)
    @assert 0 < energy_fraction ≤ 1 "energy_fraction must be in (0, 1]"
    power = ndims(uω0) == 1 ? abs2.(uω0) : vec(sum(abs2.(uω0), dims=2))
    Nt = length(power)
    @assert Nt ≥ 2 "spectrum must have at least 2 bins"
    E_total = sum(power)
    @assert E_total > 0 "input spectrum has zero energy"
    order = sortperm(power; rev=true)
    mask = falses(Nt)
    E_cum = 0.0
    cutoff = energy_fraction * E_total
    @inbounds for idx in order
        mask[idx] = true
        E_cum += power[idx]
        E_cum ≥ cutoff && break
    end
    return mask
end

# ─────────────────────────────────────────────────────────────────────────────
# build_gauge_projector
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_gauge_projector(omega, band_mask_input) -> P(v)

Return a closure `P(v)` that projects a length-`Nt` real vector onto the
subspace orthogonal to the two gauge modes of J:

    1. u_const   : indicator of the input band, L²-normalised
    2. u_linear  : centered-ω over the input band, orthogonalised vs u_const

These two directions generate the gauge symmetry  φ → φ + C + α·ω  which
leaves the Raman-suppression cost functional invariant on the input spectral
support. Subtracting them from a perturbation vector `v_i` guarantees the
Hutchinson sharpness estimator `S(φ)` measures curvature in directions that
actually change J (and therefore physically matter).

# Math
Let u1 = mask_input / ||mask_input||,
    û2 = (ω − mean_band(ω)) ⊙ mask_input,
    u2 = (û2 − (u1·û2)·u1) / ||·||.
Then  P(v) = v − (u1·v) u1 − (u2·v) u2  is the orthogonal projector onto
the complement of span{u1, u2}.

# Arguments
- `omega`        : real vector, angular frequency offsets (any units), FFT order
- `band_mask_input`: Vector{Bool}/BitVector, input-band support

# Returns
- A callable `P::Function` — `P(v)` returns a fresh projected vector.
"""
function build_gauge_projector(omega::AbstractVector{<:Real},
                               band_mask_input::AbstractVector{Bool})
    Nt = length(omega)
    @assert length(band_mask_input) == Nt "omega ($Nt) vs band_mask_input ($(length(band_mask_input))) length mismatch"
    @assert sum(band_mask_input) ≥ 2 "need ≥2 band bins for a linear gauge fit, got $(sum(band_mask_input))"

    # u1: indicator of the input band (so the gauge "constant-on-band" mode
    # gets picked up; zero outside).
    u1 = zeros(Float64, Nt)
    @inbounds for i in 1:Nt
        band_mask_input[i] && (u1[i] = 1.0)
    end
    n1 = norm(u1)
    @assert n1 > 0 "input band mask has no true elements"
    u1 ./= n1

    # u2: (ω − mean) on band, then Gram-Schmidt vs u1 to guarantee orthogonality.
    ω_band = omega[band_mask_input]
    ω_mean = mean(ω_band)
    u2 = zeros(Float64, Nt)
    @inbounds for i in 1:Nt
        band_mask_input[i] && (u2[i] = omega[i] - ω_mean)
    end
    # Remove any residual component along u1 (numerically should already be 0
    # because u2 is zero off-band and mean-zero on-band, but we enforce it).
    u2 .-= dot(u1, u2) .* u1
    n2 = norm(u2)
    if n2 > 0
        u2 ./= n2
    else
        # Degenerate: only one band bin or omega is constant on band.
        @warn "gauge direction u2 has zero norm — linear gauge is degenerate"
    end

    # Return a closure. We snapshot u1, u2 in the closure's captured vars.
    return function P(v::AbstractVector{<:Real})
        @assert length(v) == Nt "input vector length $(length(v)) ≠ Nt=$Nt"
        out = Vector{Float64}(undef, Nt)
        @inbounds @simd for i in 1:Nt
            out[i] = v[i]
        end
        c1 = dot(u1, out)
        @inbounds @simd for i in 1:Nt
            out[i] -= c1 * u1[i]
        end
        c2 = dot(u2, out)
        @inbounds @simd for i in 1:Nt
            out[i] -= c2 * u2[i]
        end
        return out
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# sharpness_estimator
# ─────────────────────────────────────────────────────────────────────────────

"""
    sharpness_estimator(phi, oracle, P; eps, n_samples, rng) -> NamedTuple

Hutchinson-style stochastic estimator of tr(H_physical), restricted to the
non-gauge subspace via the projector `P`:

    S(φ) ≈ (1/N_s) Σ_i [J(φ + ε·Pv_i) + J(φ − ε·Pv_i) − 2·J(φ)] / ε²

and its gradient w.r.t. φ (via the same Hutchinson-style symmetric FD applied
to the gradient instead of the scalar cost):

    ∂S/∂φ ≈ (1/N_s) Σ_i [∇J(φ + ε·Pv_i) + ∇J(φ − ε·Pv_i) − 2·∇J(φ)] / ε²

# Arguments
- `phi`       : current parameter vector (real, length Nt·M; 2D is flattened)
- `oracle`    : callable `(phi) -> (J, grad)` matching `cost_and_gradient`
                signature (returns scalar J, array grad of same shape as phi)
- `P`         : gauge projector from `build_gauge_projector`

# Keyword arguments
- `eps`       : finite-difference step (default SO_DEFAULT_EPS = 1e-3)
- `n_samples` : Hutchinson sample count (default SO_DEFAULT_NSAMPLES = 8)
- `rng`       : RNG for Rademacher sampling (default Random.default_rng())

# Returns
- `(S, grad_S)` : scalar S and array grad_S matching `phi` shape

# Note on shape handling
The projector `P` operates on 1D vectors (`length(phi) == Nt`). For 2D phase
arrays (Nt, M), we flatten, project, and reshape. Plan 14-01 restricts M=1
via the setup_raman_problem default, but this code is written to generalise.
"""
function sharpness_estimator(phi::AbstractArray{<:Real}, oracle, P;
                             eps::Real = SO_DEFAULT_EPS,
                             n_samples::Int = SO_DEFAULT_NSAMPLES,
                             rng::AbstractRNG = Random.default_rng())
    @assert eps > 0 "eps must be positive, got $eps"
    @assert n_samples ≥ 1 "n_samples must be ≥ 1, got $n_samples"

    phi_shape = size(phi)
    phi_flat = vec(phi)
    N = length(phi_flat)

    J0, g0 = oracle(phi)
    @assert isfinite(J0) "oracle returned non-finite J: $J0"
    g0_flat = vec(g0)
    @assert length(g0_flat) == N "oracle gradient size $(length(g0_flat)) ≠ phi size $N"

    S_sum = 0.0
    gS_sum = zeros(Float64, N)
    inv_eps2 = 1.0 / (eps^2)

    for _ in 1:n_samples
        # Rademacher: ±1 uniform. Generate in 1D, project, then reshape.
        v = 2 .* rand(rng, Bool, N) .- 1   # Vector{Int} in {-1, 1}
        Pv_flat = P(Float64.(v))
        Pv = reshape(Pv_flat, phi_shape)

        phi_plus = phi .+ eps .* Pv
        phi_minus = phi .- eps .* Pv
        J_plus, g_plus = oracle(phi_plus)
        J_minus, g_minus = oracle(phi_minus)

        @assert isfinite(J_plus) && isfinite(J_minus) "oracle returned non-finite at perturbed φ"

        S_sum += (J_plus + J_minus - 2 * J0) * inv_eps2
        @inbounds @simd for k in 1:N
            gS_sum[k] += (vec(g_plus)[k] + vec(g_minus)[k] - 2 * g0_flat[k]) * inv_eps2
        end
    end

    S = S_sum / n_samples
    grad_S = reshape(gS_sum ./ n_samples, phi_shape)

    return (S = S, grad_S = grad_S)
end

# ─────────────────────────────────────────────────────────────────────────────
# cost_and_gradient_sharp
# ─────────────────────────────────────────────────────────────────────────────

"""
    cost_and_gradient_sharp(phi, uω0, fiber, sim, band_mask;
                             lambda_sharp, n_samples, eps, rng,
                             log_cost, λ_gdd, λ_boundary,
                             gauge_projector=nothing) -> (J_sharp, grad_sharp)

Compose the regularised physical cost and its gauge-projected Hutchinson
sharpness term:

    J_sharp   = J_reg(φ) + λ_sharp · S(φ)
    ∇J_sharp  = ∇J_reg(φ) + λ_sharp · ∇S(φ)

where `J_reg` is the OUTPUT of the unchanged `cost_and_gradient` from
`scripts/lib/raman_optimization.jl`, optionally with log-scaling (`log_cost`)
and GDD/boundary regularisation applied.

`gauge_projector=nothing` causes the projector to be built on-the-fly from
`sim["ωs"]` + an input-band mask reconstructed from |uω0|² (99.9% energy
cutoff). Pass an already-built projector to skip that per-call allocation.

# Degenerate case
`lambda_sharp == 0` is detected and short-circuits to a single call of
`cost_and_gradient`, ensuring byte-identical behaviour vs the vanilla path.
"""
function cost_and_gradient_sharp(phi, uω0, fiber, sim, band_mask;
                                 lambda_sharp::Real = SO_DEFAULT_LAMBDA,
                                 n_samples::Int = SO_DEFAULT_NSAMPLES,
                                 eps::Real = SO_DEFAULT_EPS,
                                 rng::AbstractRNG = Random.default_rng(),
                                 log_cost::Bool = true,
                                 λ_gdd::Real = 0.0,
                                 λ_boundary::Real = 0.0,
                                 gauge_projector = nothing)
    # Reg-only oracle: wraps the EXISTING cost_and_gradient exactly.
    oracle = let uω0 = uω0, fiber = fiber, sim = sim, band_mask = band_mask,
                 log_cost = log_cost, λ_gdd = λ_gdd, λ_boundary = λ_boundary
        phi_in -> cost_and_gradient(phi_in, uω0, fiber, sim, band_mask;
                                    log_cost = log_cost,
                                    λ_gdd = λ_gdd,
                                    λ_boundary = λ_boundary)
    end

    J_reg, grad_J_reg = oracle(phi)

    if lambda_sharp == 0
        return (J_reg, grad_J_reg)
    end

    # Build / reuse the gauge projector.
    P = if gauge_projector === nothing
        # sim["ωs"] is the angular-frequency offset vector in rad/ps, FFT order
        # (see src/helpers/helpers.jl :: get_disp_sim_params).
        @assert haskey(sim, "ωs") "sim dict is missing \"ωs\" (angular frequency offsets)"
        omega = sim["ωs"]
        mask_in = SO_input_band_mask(uω0)
        build_gauge_projector(omega, mask_in)
    else
        gauge_projector
    end

    sharp = sharpness_estimator(phi, oracle, P;
                                eps = eps, n_samples = n_samples, rng = rng)

    J_sharp = J_reg + lambda_sharp * sharp.S
    grad_sharp = grad_J_reg .+ lambda_sharp .* sharp.grad_S

    @assert isfinite(J_sharp) "J_sharp is non-finite: $J_sharp"
    @assert all(isfinite, grad_sharp) "grad_sharp contains non-finite values"

    return (J_sharp, grad_sharp)
end

# ─────────────────────────────────────────────────────────────────────────────
# Problem wrapper (NamedTuple) and helper constructor
# ─────────────────────────────────────────────────────────────────────────────

"""
    make_sharp_problem(; kwargs...) -> NamedTuple

Thin wrapper that calls the unchanged `setup_raman_problem` and packages the
returned tuple into a NamedTuple with convenient field access:

    prob = (uω0=…, fiber=…, sim=…, band_mask=…, Δf=…, raman_threshold=…,
            band_mask_input=…, omega=…, gauge_projector=…)

where `band_mask_input` and `omega` are pre-computed for reuse by the
sharpness estimator (avoids per-iteration re-allocation).

All kwargs are forwarded to `setup_raman_problem`.
"""
function make_sharp_problem(; kwargs...)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(; kwargs...)
    omega = sim["ωs"]
    band_mask_input = SO_input_band_mask(uω0)
    gauge_projector = build_gauge_projector(omega, band_mask_input)
    return (
        uω0 = uω0, fiber = fiber, sim = sim,
        band_mask = band_mask, Δf = Δf, raman_threshold = raman_threshold,
        band_mask_input = band_mask_input, omega = omega,
        gauge_projector = gauge_projector,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# optimize_spectral_phase_sharp
# ─────────────────────────────────────────────────────────────────────────────

"""
    optimize_spectral_phase_sharp(prob, phi0; lambda_sharp, n_samples, eps, rng,
                                   max_iter, log_cost, λ_gdd, λ_boundary,
                                   strategy, store_trace, f_tol) -> NamedTuple

Mirror of `optimize_spectral_phase` that uses `cost_and_gradient_sharp` as the
inner oracle. The existing L-BFGS wrapper structure is reproduced here, not
inherited, so that the vanilla path in `raman_optimization.jl` is never
invoked with a modified cost.

# Arguments
- `prob` : NamedTuple from `make_sharp_problem` or equivalent (needs
          `uω0`, `fiber`, `sim`, `band_mask`; optional `gauge_projector`).
- `phi0` : initial phase (Nt, M) matrix or length-Nt·M vector.

# Keyword arguments
- `lambda_sharp`  : sharpness weight (default SO_DEFAULT_LAMBDA = 0.1)
- `n_samples`     : Hutchinson samples (default SO_DEFAULT_NSAMPLES = 8)
- `eps`           : FD step for sharpness (default SO_DEFAULT_EPS = 1e-3)
- `rng`           : RNG for Rademacher sampling (default Random.default_rng())
- `max_iter`      : L-BFGS iterations (default 50)
- `log_cost`      : pass-through to cost_and_gradient (default true)
- `λ_gdd`         : GDD penalty (default 1e-4)
- `λ_boundary`    : boundary penalty (default 1.0)
- `strategy`      : :lbfgs (default) or :newton (experimental; may be fragile)
- `store_trace`   : save Optim trace (default true)
- `f_tol`         : Optim.Options f_abstol (default: 0.01 if log_cost else 1e-10)

# Returns NamedTuple
- `phi_opt`       : optimised phase, same shape as `phi0`
- `J_final`       : Optim minimum (dB if log_cost=true; includes sharpness λ·S)
- `history`       : trace of cost values
- `iterations`    : Optim iterations
- `converged`     : Optim.converged
- `wall_time`     : seconds
- `lambda_sharp`, `n_samples`, `eps_sharpness` : hyperparameters used
- `result`        : raw Optim.OptimizationResult for debugging
"""
function optimize_spectral_phase_sharp(prob, phi0;
                                       lambda_sharp::Real = SO_DEFAULT_LAMBDA,
                                       n_samples::Int = SO_DEFAULT_NSAMPLES,
                                       eps::Real = SO_DEFAULT_EPS,
                                       rng::AbstractRNG = Random.default_rng(),
                                       max_iter::Int = 50,
                                       log_cost::Bool = true,
                                       λ_gdd::Real = 1e-4,
                                       λ_boundary::Real = 1.0,
                                       strategy::Symbol = :lbfgs,
                                       store_trace::Bool = true,
                                       f_tol::Real = log_cost ? 0.01 : 1e-10)
    @assert max_iter > 0 "max_iter must be positive"
    @assert strategy in (:lbfgs, :newton) "strategy must be :lbfgs or :newton, got :$strategy"

    uω0 = prob.uω0
    fiber = prob.fiber
    sim = prob.sim
    band_mask = prob.band_mask
    P = hasproperty(prob, :gauge_projector) ? prob.gauge_projector : nothing

    # Ensure zsave is nothing for optimization (avoids internal deepcopy)
    fiber["zsave"] = nothing

    phi_shape = size(phi0)
    phi0_vec = vec(Float64.(phi0))

    # Wall-time clock starts before the first optimisation call.
    t0 = time()

    fg! = Optim.only_fg!() do F, G, phi_vec
        phi_mat = reshape(phi_vec, phi_shape)
        J, grad = cost_and_gradient_sharp(phi_mat, uω0, fiber, sim, band_mask;
                                          lambda_sharp = lambda_sharp,
                                          n_samples = n_samples,
                                          eps = eps,
                                          rng = rng,
                                          log_cost = log_cost,
                                          λ_gdd = λ_gdd,
                                          λ_boundary = λ_boundary,
                                          gauge_projector = P)
        if G !== nothing
            G .= vec(grad)
        end
        if F !== nothing
            return J
        end
    end

    opt_alg = strategy === :newton ? Optim.Newton() : Optim.LBFGS()
    opts = Optim.Options(iterations = max_iter, f_abstol = f_tol,
                         store_trace = store_trace)

    result = optimize(fg!, phi0_vec, opt_alg, opts)
    wall_time = time() - t0

    phi_opt = reshape(Optim.minimizer(result), phi_shape)
    history = store_trace ? collect(Optim.f_trace(result)) : Float64[]

    return (
        phi_opt = phi_opt,
        J_final = Optim.minimum(result),
        history = history,
        iterations = Optim.iterations(result),
        converged = Optim.converged(result),
        wall_time = wall_time,
        lambda_sharp = lambda_sharp,
        n_samples = n_samples,
        eps_sharpness = eps,
        result = result,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Mandatory standard-image emit for sharp drivers (CLAUDE.md project rule).
# Drivers that call `optimize_spectral_phase_sharp(prob, phi0)` MUST follow up
# with this helper so the four canonical PNGs land on disk.
# ─────────────────────────────────────────────────────────────────────────────
function emit_sharp_standard_set(sharp_result, prob;
                                  tag::String,
                                  fiber_name::String,
                                  L_m::Real,
                                  P_W::Real,
                                  output_dir::String,
                                  lambda0_nm::Real = 1550.0,
                                  fwhm_fs::Real = 185.0)
    Δf            = prob.Δf
    raman_thresh  = prob.raman_threshold
    save_standard_set(sharp_result.phi_opt, prob.uω0, prob.fiber, prob.sim,
        prob.band_mask, Δf, raman_thresh;
        tag = tag,
        fiber_name = fiber_name,
        L_m = L_m,
        P_W = P_W,
        output_dir = output_dir,
        lambda0_nm = lambda0_nm,
        fwhm_fs = fwhm_fs)
end

end  # include guard
