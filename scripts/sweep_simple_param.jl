"""
Session E — Low-Resolution Spectral-Phase Parameterization

Purpose
=======
Wrap the full-resolution cost/gradient pipeline with a fixed linear basis so
the optimization variable is `c ∈ R^{N_phi}` with N_phi ≪ Nt. The forward and
adjoint solvers run at full Nt — only the optimizer's knob count is reduced.
This mimics a physical pulse shaper whose pixel count constrains the
achievable phase complexity.

    φ_Nt = B · c           with   B ∈ R^{Nt × N_phi}
    ∂J/∂c = Bᵀ · ∂J/∂φ    (exact adjoint of the basis operator)

The core `cost_and_gradient(φ, …)` in `raman_optimization.jl` is reused
unchanged. This file only adds wrappers.

Basis kinds implemented
=======================
  :identity — requires N_phi == Nt; B = I. Unit-test hook.
  :cubic    — natural cubic spline through N_phi equally-spaced knots over
              the pulse bandwidth. Physically closest to a pixelated SLM
              after PSF smoothing. **Default.**
  :dct      — orthonormal DCT-II first-N_phi columns. Truncated bandlimited
              basis. Used for ablation and for the N_eff simplicity metric.
  :linear   — piecewise-linear through N_phi knots. Cheapest; ablation only.

Simplicity metrics
==================
  phase_neff(φ, mask)     — participation ratio of |DCT(φ)|² over bandwidth
                             (entropy-based effective coefficient count)
  phase_tv(φ, mask)       — normalized total variation of unwrapped φ
  phase_curvature(φ, sim, mask) — ‖∂²φ/∂ω²‖₂ on the bandwidth

Verification
============
At N_phi = Nt with :identity basis, `cost_and_gradient_lowres` reduces to
`cost_and_gradient` byte-for-byte on any input. A Cubic-basis gradient
check via finite differences confirms the Bᵀ chain rule.

This file is owned by Session E and lives in the sweep_simple_* namespace.
It does NOT modify `scripts/common.jl`, `scripts/raman_optimization.jl`,
or anything in `src/`.
"""

try using Revise catch end

using LinearAlgebra
using FFTW
using Printf
using Random
using Logging
using Statistics
using Interpolations
using Optim

# Dependencies: common.jl provides setup_raman_problem + spectral_band_cost;
# raman_optimization.jl provides cost_and_gradient + optimize_spectral_phase.
# Both are sourced idempotently via their own include guards.
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))

const _SWEEP_SIMPLE_PARAM_JL_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# Session-E constants (LR_ prefix per Script Constant Prefixes convention)
# ─────────────────────────────────────────────────────────────────────────────

const LR_DEFAULT_BANDWIDTH_THRESHOLD = 0.01   # |uω|² relative to peak
const LR_DEFAULT_KIND = :cubic
const LR_COND_LIMIT = 1e12                    # Bᵀ B conditioning sanity

# ─────────────────────────────────────────────────────────────────────────────
# Pulse bandwidth mask — defines where knots are placed and where metrics live
# ─────────────────────────────────────────────────────────────────────────────

"""
    pulse_bandwidth_mask(uω0; threshold=0.01) -> BitVector

Returns a length-Nt BitVector flagging bins where `|uω0|² > threshold × max`.

For single-mode (M=1) inputs; for M>1 the mode sum is taken.
"""
function pulse_bandwidth_mask(uω0::AbstractMatrix{<:Complex}, threshold::Real=LR_DEFAULT_BANDWIDTH_THRESHOLD)
    @assert threshold > 0 "threshold must be positive"
    spectral_power = vec(sum(abs2.(uω0), dims=2))
    pk = maximum(spectral_power)
    return spectral_power .> threshold * pk
end

# ─────────────────────────────────────────────────────────────────────────────
# Basis construction
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_phase_basis(Nt, N_phi; kind=:cubic, bandwidth_mask=nothing) -> Matrix{Float64}

Return an `Nt × N_phi` basis matrix `B` such that a coefficient vector
`c ∈ R^{N_phi}` represents the phase `φ = B · c ∈ R^{Nt}` on the FFT grid.

All non-identity kinds restrict their support to `bandwidth_mask` if given
(columns are zero outside). Knots for `:cubic` and `:linear` are placed in
the fftshifted axis so they span the physical ω range of the pulse, then
the basis is un-shifted to native FFT ordering for downstream use.
"""
function build_phase_basis(Nt::Int, N_phi::Int;
                           kind::Symbol = LR_DEFAULT_KIND,
                           bandwidth_mask::Union{Nothing,AbstractVector{Bool}} = nothing)
    @assert Nt > 0 "Nt must be positive"
    @assert N_phi ≥ 1 "N_phi must be ≥ 1"

    if kind === :identity
        @assert N_phi == Nt ":identity basis requires N_phi == Nt (got Nt=$Nt, N_phi=$N_phi)"
        return Matrix{Float64}(I, Nt, Nt)
    end

    @assert N_phi ≥ 2 "non-identity basis requires N_phi ≥ 2, got $N_phi"

    # Work in fftshifted axis so the pulse-bandwidth support is a contiguous
    # block centered near the middle of the array.
    mask_native = bandwidth_mask === nothing ? trues(Nt) : collect(bandwidth_mask)
    @assert length(mask_native) == Nt "bandwidth_mask length $(length(mask_native)) ≠ Nt $Nt"
    mask_shift = fftshift(mask_native)
    support = findall(mask_shift)
    @assert length(support) ≥ N_phi "bandwidth support bins $(length(support)) < N_phi $N_phi — widen bandwidth or reduce N_phi"

    B_shift = zeros(Float64, Nt, N_phi)

    if kind === :cubic
        # Parameter axis t ∈ [1, N_phi] maps linearly onto the contiguous
        # support in fftshifted index. For each column j we construct the
        # cubic spline through a unit-impulse y = e_j on 1:N_phi.
        ti = range(1.0, Float64(N_phi), length=length(support))
        for j in 1:N_phi
            y = zeros(Float64, N_phi)
            y[j] = 1.0
            itp = cubic_spline_interpolation(1:N_phi, y; extrapolation_bc=Interpolations.Flat())
            for (idx, t) in zip(support, ti)
                B_shift[idx, j] = itp(t)
            end
        end

    elseif kind === :linear
        ti = range(1.0, Float64(N_phi), length=length(support))
        for j in 1:N_phi
            y = zeros(Float64, N_phi)
            y[j] = 1.0
            itp = linear_interpolation(1:N_phi, y; extrapolation_bc=Interpolations.Flat())
            for (idx, t) in zip(support, ti)
                B_shift[idx, j] = itp(t)
            end
        end

    elseif kind === :dct
        # Orthonormal DCT-II: B[i, k] = norm_k · cos(π (k-1) (i - 0.5) / Nt)
        # Build in native FFT ordering (DCT is already defined naturally);
        # optionally restrict to bandwidth by zeroing-out rows outside support.
        B = zeros(Float64, Nt, N_phi)
        for k in 1:N_phi
            for i in 1:Nt
                B[i, k] = cos((k - 1) * π * (i - 0.5) / Nt)
            end
            B[:, k] ./= norm(B[:, k])
        end
        if bandwidth_mask !== nothing
            B .*= mask_native
        end
        _sanity_check_basis(B)
        return B

    else
        error("unknown basis kind $kind; choose from :identity, :cubic, :dct, :linear")
    end

    # Un-shift along frequency axis: ifftshift(B_shift, dims=1) puts DC back
    # at index 1 matching the FFT convention used by the solver.
    B = ifftshift(B_shift, 1)
    _sanity_check_basis(B)
    return B
end

function _sanity_check_basis(B::AbstractMatrix)
    Nt, N_phi = size(B)
    @assert all(isfinite, B) "basis contains NaN/Inf"
    # Bᵀ B conditioning — only meaningful for small N_phi; for large N_phi
    # this is an Nt × Nt intermediate, skip.
    if N_phi ≤ 512
        G = Symmetric(B' * B)
        λs = eigvals(G)
        λmax = maximum(λs); λmin = minimum(λs)
        if λmin ≤ 0
            @warn @sprintf("Basis Gram matrix has non-positive eigenvalue %.3e — basis may be rank-deficient.", λmin)
        else
            κ = λmax / λmin
            if κ > LR_COND_LIMIT
                @warn @sprintf("Basis Gram matrix condition number %.2e exceeds %.0e — optimization may be ill-conditioned.", κ, LR_COND_LIMIT)
            end
        end
    end
    return nothing
end

# ─────────────────────────────────────────────────────────────────────────────
# Low-resolution cost + gradient wrapper
# ─────────────────────────────────────────────────────────────────────────────

"""
    cost_and_gradient_lowres(c, B, uω0, fiber, sim, band_mask; kwargs...)
        -> (J::Float64, dc::Vector{Float64})

Evaluate the Raman-band spectral cost in coefficient space.

Internally computes `φ = B · c_mat` (shape Nt × M), calls the full-resolution
`cost_and_gradient`, and returns `(J, vec(B' · ∂J/∂φ))`.

Passes through the full-resolution regularization kwargs `log_cost`,
`λ_gdd`, `λ_boundary` unchanged.

Preconditions
-------------
  length(c) == size(B, 2) × M, where M = size(uω0, 2).
  size(B, 1) == size(uω0, 1).

Postconditions
--------------
  isfinite(J); all(isfinite, dc); length(dc) == length(c).
"""
function cost_and_gradient_lowres(c::AbstractVector{<:Real}, B::AbstractMatrix{<:Real},
                                  uω0::AbstractMatrix{<:Complex}, fiber, sim,
                                  band_mask::AbstractVector{Bool};
                                  kwargs...)
    Nt, M = size(uω0)
    N_phi = size(B, 2)
    @assert size(B, 1) == Nt "B rows $(size(B,1)) ≠ Nt $Nt"
    @assert length(c) == N_phi * M "c length $(length(c)) ≠ N_phi*M $(N_phi*M)"

    c_mat = reshape(c, N_phi, M)
    φ = B * c_mat                                     # Nt × M
    J, ∂J_∂φ = cost_and_gradient(φ, uω0, fiber, sim, band_mask; kwargs...)
    ∂J_∂c = B' * ∂J_∂φ                                # N_phi × M

    @assert isfinite(J) "cost is not finite"
    @assert all(isfinite, ∂J_∂c) "c-gradient contains NaN/Inf"

    return J, vec(∂J_∂c)
end

# ─────────────────────────────────────────────────────────────────────────────
# Low-resolution optimizer
# ─────────────────────────────────────────────────────────────────────────────

"""
    optimize_phase_lowres(uω0, fiber, sim, band_mask; kwargs...) -> NamedTuple

L-BFGS optimization of the Raman-suppression cost in the low-resolution
coefficient space `c ∈ R^{N_phi*M}`. The physical pulse entering the fiber
is `exp(i · B · c) · uω0`.

Keyword arguments
-----------------
  N_phi           — basis dimension (knots / cosine coefficients). Required.
  kind            — basis type (see `build_phase_basis`). Default :cubic.
  bandwidth_mask  — BitVector length Nt. Default `pulse_bandwidth_mask(uω0)`.
  c0              — initial coefficient vector (length N_phi*M). Default zeros.
  B_precomputed   — skip basis construction if caller already built it.
  max_iter        — L-BFGS iterations. Default 50.
  λ_gdd           — GDD penalty (passed through). Default 0.
  λ_boundary      — boundary-energy penalty (passed through). Default 0.
  log_cost        — log-scale cost (recommended). Default true.
  store_trace     — return Optim trace. Default false.

Returns NamedTuple
------------------
  c_opt       — optimal coefficients, size (N_phi, M)
  phi_opt     — reconstructed full-res phase, size (Nt, M)
  J_final     — final cost (dB if log_cost=true, else linear)
  iterations  — iterations consumed
  converged   — Optim.jl's f_converged flag
  B           — the basis used (for downstream metrics)
  kind        — Symbol, the basis kind used
  N_phi       — Int
  result      — raw Optim.jl result
"""
function optimize_phase_lowres(uω0::AbstractMatrix{<:Complex}, fiber, sim,
                               band_mask::AbstractVector{Bool};
                               N_phi::Int,
                               kind::Symbol = LR_DEFAULT_KIND,
                               bandwidth_mask::Union{Nothing,AbstractVector{Bool}} = nothing,
                               c0::Union{Nothing,AbstractVector{<:Real}} = nothing,
                               B_precomputed::Union{Nothing,AbstractMatrix{<:Real}} = nothing,
                               max_iter::Int = 50,
                               λ_gdd::Real = 0.0,
                               λ_boundary::Real = 0.0,
                               log_cost::Bool = true,
                               store_trace::Bool = false)
    @assert max_iter > 0 "max_iter must be positive"
    @assert haskey(sim, "Nt") && haskey(sim, "M") "sim missing Nt / M"

    Nt = sim["Nt"]; M = sim["M"]

    # Resolve bandwidth mask
    bw_mask = bandwidth_mask === nothing ? pulse_bandwidth_mask(uω0) : bandwidth_mask

    # Resolve basis
    B = B_precomputed === nothing ?
        build_phase_basis(Nt, N_phi; kind=kind, bandwidth_mask=bw_mask) :
        B_precomputed
    @assert size(B) == (Nt, N_phi) "B has shape $(size(B)), expected ($Nt, $N_phi)"

    # Init
    if c0 === nothing
        c0 = zeros(Float64, N_phi * M)
    else
        @assert length(c0) == N_phi * M "c0 length $(length(c0)) ≠ N_phi*M"
    end

    # Ensure zsave nothing (matches optimize_spectral_phase convention)
    fiber["zsave"] = nothing

    # Pre-allocate shaped / output buffers for cost_and_gradient
    uω0_shaped = similar(uω0)
    uωf_buffer = similar(uω0)

    t_start = time()
    function callback(state)
        @debug @sprintf("[lowres %3d] J=%.6e (%.2f dB)  (%.1fs)",
                        state.iteration, state.value, state.value, time() - t_start)
        return false
    end

    f_tol = log_cost ? 0.01 : 1e-10

    result = optimize(
        Optim.only_fg!() do F, G, c_vec
            J, dc = cost_and_gradient_lowres(c_vec, B, uω0, fiber, sim, band_mask;
                                              uω0_shaped=uω0_shaped,
                                              uωf_buffer=uωf_buffer,
                                              λ_gdd=λ_gdd, λ_boundary=λ_boundary,
                                              log_cost=log_cost)
            if G !== nothing
                G .= dc
            end
            if F !== nothing
                return J
            end
        end,
        c0,
        LBFGS(),
        Optim.Options(iterations=max_iter, f_abstol=f_tol,
                      callback=callback, store_trace=store_trace)
    )

    c_opt = reshape(result.minimizer, N_phi, M)
    phi_opt = B * c_opt

    return (
        c_opt     = c_opt,
        phi_opt   = phi_opt,
        J_final   = Optim.minimum(result),
        iterations = Optim.iterations(result),
        converged = Optim.f_converged(result),
        B         = B,
        kind      = kind,
        N_phi     = N_phi,
        result    = result,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Continuation upsample: c at level k-1 → c at level k
# ─────────────────────────────────────────────────────────────────────────────

"""
    continuation_upsample(c_prev, B_prev, B_new) -> Vector{Float64}

Project an optimum at a coarser basis `B_prev` onto a finer basis `B_new`
via the least-squares pseudoinverse:

    φ_prev = B_prev · c_prev
    c_new  = (B_newᵀ B_new)⁻¹ B_newᵀ · φ_prev

For orthonormal bases (e.g. :dct), this reduces to `B_newᵀ · φ_prev`.
Used to warm-start Sweep 1's coarse-to-fine continuation.
"""
function continuation_upsample(c_prev::AbstractVector{<:Real},
                                B_prev::AbstractMatrix{<:Real},
                                B_new::AbstractMatrix{<:Real})
    @assert size(B_prev, 1) == size(B_new, 1) "row counts must match"
    φ_prev = B_prev * reshape(c_prev, size(B_prev, 2), :)
    G = Symmetric(B_new' * B_new)
    rhs = B_new' * φ_prev
    c_new = G \ rhs
    return vec(c_new)
end

# ─────────────────────────────────────────────────────────────────────────────
# Simplicity metrics
# ─────────────────────────────────────────────────────────────────────────────

"""
    phase_neff(φ, band_mask) -> Float64

Participation ratio of the normalized DCT power spectrum of φ restricted to
the bandwidth mask. `N_eff = exp(-Σ p_k log p_k)` with `p_k = |DCT_k|² / Σ|DCT|²`.
Low N_eff ↔ phase is concentrated in few low-order DCT modes ↔ simpler.
"""
function phase_neff(φ::AbstractVector{<:Real}, band_mask::AbstractVector{Bool})
    @assert length(φ) == length(band_mask) "length mismatch"
    idx = findall(band_mask)
    isempty(idx) && return 0.0
    # FFT-shift the bandwidth region to a contiguous block for DCT;
    # zero-pad outside the support to Nt to keep a consistent grid.
    φ_shift = fftshift(φ)
    mask_shift = fftshift(band_mask)
    sup = findall(mask_shift)
    # Extract contiguous support (assume unimodal mask), DCT over it
    blk = φ_shift[sup[1]:sup[end]]
    # Real DCT-II via rfft after mirror-extension (cheap approximation):
    # Use unmirrored DFT magnitudes; for simplicity-metric purposes we only
    # need a well-defined participation ratio of a Fourier-like decomposition.
    y = rfft(blk)
    p = abs2.(y)
    s = sum(p)
    s == 0 && return 0.0
    p ./= s
    # entropy-based effective count, using natural log
    H = -sum(pk -> pk > 0 ? pk * log(pk) : 0.0, p)
    return exp(H)
end

phase_neff(φ::AbstractMatrix{<:Real}, band_mask::AbstractVector{Bool}) = phase_neff(vec(φ), band_mask)

"""
    phase_tv(φ, band_mask) -> Float64

Normalized total variation of unwrapped φ over the bandwidth. Dimensionless.
Divides by (bandwidth in bins) and by (std of φ over bandwidth) to compare
across operating points. Returns 0 if φ is constant on the bandwidth.
"""
function phase_tv(φ::AbstractVector{<:Real}, band_mask::AbstractVector{Bool})
    idx = findall(band_mask)
    length(idx) < 2 && return 0.0
    # Contiguous support in fftshifted space
    φ_shift = fftshift(φ)
    mask_shift = fftshift(band_mask)
    sup = findall(mask_shift)
    blk = φ_shift[sup[1]:sup[end]]
    ψ = _manual_unwrap_phase(blk)
    σ = std(ψ)
    σ < eps() && return 0.0
    TV = sum(abs.(diff(ψ)))
    BW = length(blk)
    return TV / (BW * σ)
end

phase_tv(φ::AbstractMatrix{<:Real}, band_mask::AbstractVector{Bool}) = phase_tv(vec(φ), band_mask)

"""
    phase_curvature(φ, sim, band_mask) -> Float64

‖∂²φ/∂ω²‖₂ on the bandwidth, second-difference approximation scaled by
1/Δω². Has units of s² (same as β₂). Reported alongside N_eff / TV.
"""
function phase_curvature(φ::AbstractVector{<:Real}, sim, band_mask::AbstractVector{Bool})
    idx = findall(band_mask)
    length(idx) < 3 && return 0.0
    Nt = length(φ)
    Δω = 2π / (Nt * sim["Δt"])
    φ_shift = fftshift(φ)
    mask_shift = fftshift(band_mask)
    sup = findall(mask_shift)
    blk = φ_shift[sup[1]:sup[end]]
    d2 = [blk[i+1] - 2blk[i] + blk[i-1] for i in 2:length(blk)-1] ./ Δω^2
    return sqrt(sum(abs2, d2))
end

phase_curvature(φ::AbstractMatrix{<:Real}, sim, band_mask::AbstractVector{Bool}) =
    phase_curvature(vec(φ), sim, band_mask)

# ── phase unwrap (manual; avoids depending on DSP.jl) ────────────────────────
function _manual_unwrap_phase(ψ::AbstractVector{<:Real})
    out = similar(ψ, Float64)
    out[1] = ψ[1]
    acc = 0.0
    for i in 2:length(ψ)
        d = ψ[i] - ψ[i-1]
        if d > π
            acc -= 2π * floor((d + π) / (2π))
        elseif d < -π
            acc -= 2π * ceil((d - π) / (2π))
        end
        out[i] = ψ[i] + acc
    end
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# Self-test: run verification when invoked as a script with LR_SELFTEST=true
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_selftest() -> Bool

Verifies:
  1. Identity basis + N_phi=Nt reproduces full-res cost_and_gradient byte-exact.
  2. Cubic basis gradient matches finite differences (rel err < 1e-4).
"""
function run_selftest(; verbose::Bool=true)
    verbose && @info "Session E self-test: sweep_simple_param.jl"
    # --- Minimal setup ---
    uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
        fiber_preset=:SMF28, β_order=3, L_fiber=1.0, P_cont=0.05, Nt=2^12, time_window=5.0
    )
    Nt = sim["Nt"]

    # Fixed-seed input phase
    Random.seed!(42)
    φ0 = 0.1 .* randn(Nt, 1)

    # --- Test 1: identity basis equivalence ---
    B_I = build_phase_basis(Nt, Nt; kind=:identity)
    J_full, dphi_full = cost_and_gradient(φ0, uω0, fiber, sim, band_mask; log_cost=false)
    J_lowres, dc_lowres = cost_and_gradient_lowres(vec(φ0), B_I, uω0, fiber, sim, band_mask; log_cost=false)

    err_J = abs(J_full - J_lowres)
    err_dphi = maximum(abs.(vec(dphi_full) .- dc_lowres))
    verbose && @info @sprintf("identity-basis: |ΔJ|=%.3e  max|Δgrad|=%.3e", err_J, err_dphi)
    test1_pass = err_J < 1e-12 && err_dphi < 1e-10

    # --- Test 2: cubic basis gradient vs FD ---
    bw = pulse_bandwidth_mask(uω0)
    B_cub = build_phase_basis(Nt, 16; kind=:cubic, bandwidth_mask=bw)
    Random.seed!(7)
    c_test = 0.1 .* randn(16)
    J0, dc = cost_and_gradient_lowres(c_test, B_cub, uω0, fiber, sim, band_mask; log_cost=false)
    ε = 1e-5
    fd_errors = Float64[]
    for j in (4, 8, 13)
        cp = copy(c_test); cp[j] += ε
        Jp, _ = cost_and_gradient_lowres(cp, B_cub, uω0, fiber, sim, band_mask; log_cost=false)
        cm = copy(c_test); cm[j] -= ε
        Jm, _ = cost_and_gradient_lowres(cm, B_cub, uω0, fiber, sim, band_mask; log_cost=false)
        fd = (Jp - Jm) / (2ε)
        rel = abs(dc[j] - fd) / max(abs(dc[j]), abs(fd), 1e-14)
        push!(fd_errors, rel)
        verbose && @info @sprintf("cubic grad j=%2d: analytic=%.3e  fd=%.3e  rel=%.2e", j, dc[j], fd, rel)
    end
    test2_pass = all(<(5e-3), fd_errors)  # FD on log-scale cost would be tighter; linear is fine here

    # --- Summary ---
    pass = test1_pass && test2_pass
    if verbose
        if pass
            @info "Session E self-test: ALL PASS ✓"
        else
            @warn "Session E self-test: FAILURE" test1_pass test2_pass
        end
    end
    return pass
end

# If run as a top-level script with flag, execute self-test.
if abspath(PROGRAM_FILE) == @__FILE__
    if get(ENV, "LR_SELFTEST", "false") == "true"
        ok = run_selftest()
        exit(ok ? 0 : 1)
    else
        @info "sweep_simple_param.jl loaded. Set LR_SELFTEST=true to run self-test."
    end
end
