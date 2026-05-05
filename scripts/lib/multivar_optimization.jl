"""
Experimental multi-variable spectral pulse-shaping optimizer.

Jointly optimizes any subset of {spectral phase φ(ω), spectral amplitude A(ω),
pulse energy E} for Raman suppression, through a SINGLE forward-adjoint solve
per iteration. Mode coefficients {c_m} are stubbed in the API for future
extension — they are stripped + warned at runtime.

Complements — does NOT replace — the existing single-variable paths:
  - `scripts/lib/raman_optimization.jl :: optimize_spectral_phase`   (phase-only)
  - `scripts/lib/amplitude_optimization.jl :: optimize_spectral_amplitude`  (amp-only)

Both remain usable for A/B comparison.

Status: see `agent-docs/current-agent-context/MULTIVAR.md`.
Historical derivations and schema notes are in the external cleanup archive.

Entry points:
  - `cost_and_gradient_multivar(x, uω0, fiber, sim, band_mask, cfg)`
  - `optimize_spectral_multivariable(uω0, fiber, sim, band_mask; kwargs...)`
  - `save_multivar_result(prefix, result_dict)`  /  `load_multivar_result(prefix)`
  - `run_multivar_optimization(; kwargs...)` — high-level end-to-end runner
"""

using Printf

try using Revise catch end
using LinearAlgebra
using FFTW
using Statistics
using Logging
using Dates
ENV["MPLBACKEND"] = "Agg"
using MultiModeNoise
using Optim
using JLD2
using JSON3

if !(@isdefined _MULTIVAR_OPT_LOADED)
const _MULTIVAR_OPT_LOADED = true

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "objective_surface.jl"))
include(joinpath(@__DIR__, "regularizers.jl"))
include(joinpath(@__DIR__, "run_artifacts.jl"))
ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Constants and config struct (Script Constant Prefix convention: MV_)
# ─────────────────────────────────────────────────────────────────────────────

const MV_LEGAL_VARS = (:phase, :amplitude, :energy, :gain_tilt, :mode_coeffs)
const MV_DEFAULT_DELTA_AMP = 0.10     # box half-width for A(ω)
const MV_DEFAULT_EPS_FD_PHASE  = 1e-5
const MV_DEFAULT_EPS_FD_AMP    = 1e-6
const MV_DEFAULT_EPS_FD_ENERGY = 1e-6  # log-energy coordinate step
const MV_DEFAULT_EPS_FD_GAIN_TILT = 1e-6

"""
    MVConfig

Container for all multi-variable optimizer settings.  Pass via `cfg` to
`cost_and_gradient_multivar` and the convenience wrappers.

Fields
  variables::Tuple{Vararg{Symbol}}  subset of (:phase, :amplitude, :energy, :gain_tilt)
  δ_bound::Float64                   box half-width for A and gain tilt
  s_φ::Float64                       phase preconditioning scale
  s_A::Float64                       amplitude preconditioning scale
  s_E::Float64                       energy preconditioning scale
  log_cost::Bool                     optimize J in dB (default true)
  # regularizers (phase-side, inherited from raman_optimization semantics)
  λ_gdd::Float64
  λ_boundary::Float64
  # regularizers (amplitude-side, inherited from amplitude_optimization semantics)
  λ_energy::Float64    # energy-preservation penalty λ_E·(E_shaped/E_ref − 1)²
  λ_tikhonov::Float64
  λ_tv::Float64
  λ_flat::Float64
"""
Base.@kwdef mutable struct MVConfig
    variables::Tuple{Vararg{Symbol}} = (:phase, :amplitude)
    δ_bound::Float64    = MV_DEFAULT_DELTA_AMP
    # Amplitude parameterization:
    #   :tanh    → A = 1 + δ_bound · tanh(ξ); optimizer works on ξ ∈ ℝ, plain LBFGS.
    #   :fminbox → A is the search variable directly; Fminbox(LBFGS) enforces bounds.
    # Default :tanh avoids the barrier-wrapper overhead that made :fminbox stall in
    # the 16-01 reference run (see SUMMARY.md "partial" section).
    amp_param::Symbol   = :tanh
    s_φ::Float64        = 1.0
    s_A::Float64        = 1.0   # set from δ_bound at construction if default
    s_E::Float64        = 1.0   # set from E_ref at construction
    log_cost::Bool      = true
    λ_gdd::Float64      = 0.0
    λ_boundary::Float64 = 0.0
    λ_energy::Float64   = 0.0
    λ_tikhonov::Float64 = 0.0
    λ_tv::Float64       = 0.0
    λ_flat::Float64     = 0.0
end

"""
    multivar_cost_surface_spec(cfg; objective_label="multivariable Raman spectral shaping optimization",
                               base_term="J_physics")

Machine-readable description of the scalar objective returned by
`cost_and_gradient_multivar`.
"""
function multivar_cost_surface_spec(
    cfg::MVConfig;
    objective_label::AbstractString="multivariable Raman spectral shaping optimization",
    base_term::AbstractString="J_physics")

    return build_objective_surface_spec(;
        objective_label = objective_label,
        log_cost = cfg.log_cost,
        linear_terms = active_linear_terms(
            [String(base_term)],
            [
                (cfg.λ_gdd > 0, "λ_gdd*R_gdd"),
                (cfg.λ_boundary > 0, "λ_boundary*R_boundary"),
                (cfg.λ_energy > 0, "λ_energy*R_energy"),
                (cfg.λ_tikhonov > 0, "λ_tikhonov*R_tikhonov"),
                (cfg.λ_tv > 0, "λ_tv*R_tv"),
                (cfg.λ_flat > 0, "λ_flat*R_flat"),
            ],
        ),
        trailing_fields = (
            lambda_gdd = cfg.λ_gdd,
            lambda_boundary = cfg.λ_boundary,
            lambda_energy = cfg.λ_energy,
            lambda_tikhonov = cfg.λ_tikhonov,
            lambda_tv = cfg.λ_tv,
            lambda_flat = cfg.λ_flat,
        ),
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Variable validation + stripping
# ─────────────────────────────────────────────────────────────────────────────

"""
    sanitize_variables(variables) -> Tuple{Vararg{Symbol}}

Enforce that `variables` is a non-empty subset of MV_LEGAL_VARS.
Strips `:mode_coeffs` with a @warn (deferred to Session C per Decision D4).
"""
function sanitize_variables(variables)
    vars = Symbol[]
    seen = Set{Symbol}()
    for v in variables
        if v ∉ MV_LEGAL_VARS
            throw(ArgumentError("Unknown variable $v. Legal: $(MV_LEGAL_VARS)"))
        end
        if v === :mode_coeffs
            @warn "Variable :mode_coeffs is out of Session A scope (deferred to Session C). Stripping."
            continue
        end
        if v in seen
            continue
        end
        push!(seen, v)
        push!(vars, v)
    end
    isempty(vars) && throw(ArgumentError("No variables enabled after sanitization."))
    return Tuple(vars)
end

# ─────────────────────────────────────────────────────────────────────────────
# Flat-vector ↔ block-field marshalling
# ─────────────────────────────────────────────────────────────────────────────

"""
    mv_block_offsets(cfg, Nt, M) -> NamedTuple

Compute start/stop offsets of each variable block in the flat search vector.
Returns `(ranges=..., n_total=N)` where ranges is a dict-like named tuple.
"""
function mv_block_offsets(cfg::MVConfig, Nt::Int, M::Int)
    offsets = Dict{Symbol,UnitRange{Int}}()
    cursor = 1
    if :phase in cfg.variables
        n = Nt * M
        offsets[:phase] = cursor:(cursor + n - 1)
        cursor += n
    end
    if :amplitude in cfg.variables
        n = Nt * M
        offsets[:amplitude] = cursor:(cursor + n - 1)
        cursor += n
    end
    if :energy in cfg.variables
        offsets[:energy] = cursor:cursor
        cursor += 1
    end
    if :gain_tilt in cfg.variables
        offsets[:gain_tilt] = cursor:cursor
        cursor += 1
    end
    return (ranges=offsets, n_total=cursor - 1)
end

"""
    mv_gain_tilt_basis(sim, Nt, M)

Return a dimensionless frequency-ramp basis in FFT storage order. The basis is
centered and normalized to `maximum(abs.(basis)) == 1`, so the scalar tilt
coefficient has an inspectable physical meaning independent of grid size.
"""
function mv_gain_tilt_basis(sim::Dict, Nt::Int, M::Int)
    Δf = collect(FFTW.fftfreq(Nt, 1 / sim["Δt"]))
    denom = max(maximum(abs.(Δf)), eps())
    q = Δf ./ denom
    q .-= mean(q)
    q ./= max(maximum(abs.(q)), eps())
    return repeat(reshape(Float64.(q), Nt, 1), 1, M)
end

function mv_gain_tilt_amplitude(search_scalar::Real, cfg::MVConfig, sim::Dict, Nt::Int, M::Int)
    basis = mv_gain_tilt_basis(sim, Nt, M)
    slope = cfg.δ_bound * tanh(Float64(search_scalar))
    d_slope_dξ = cfg.δ_bound * (1.0 - tanh(Float64(search_scalar))^2)
    A_tilt = @. 1.0 + slope * basis
    dA_dξ = @. d_slope_dξ * basis
    return A_tilt, dA_dξ, slope
end

"""
    mv_unpack(x, cfg, Nt, M, E_ref) -> NamedTuple

Decompose a flat vector `x` into (φ, A, E) fields, filling defaults
(zeros, ones, E_ref) for variables not in `cfg.variables`.
"""
function mv_unpack(x::AbstractVector{<:Real}, cfg::MVConfig, Nt::Int, M::Int, E_ref::Real)
    off = mv_block_offsets(cfg, Nt, M)
    φ = haskey(off.ranges, :phase)     ? reshape(copy(@view x[off.ranges[:phase]]),     Nt, M) : zeros(Nt, M)
    A = haskey(off.ranges, :amplitude) ? reshape(copy(@view x[off.ranges[:amplitude]]), Nt, M) : ones(Nt, M)
    # The scalar energy search coordinate is η = log(E), so line-search probes
    # remain positive without box constraints.
    E = haskey(off.ranges, :energy)    ? exp(x[first(off.ranges[:energy])])                    : Float64(E_ref)
    gain_tilt = haskey(off.ranges, :gain_tilt) ? Float64(x[first(off.ranges[:gain_tilt])]) : 0.0
    return (φ=φ, A=A, E=E, gain_tilt=gain_tilt, offsets=off)
end

"""
    mv_pack(φ, A, E, cfg, Nt, M) -> Vector{Float64}

Inverse of `mv_unpack`: assemble the flat vector from the enabled variable
blocks (discarding any block not in `cfg.variables`).
"""
function mv_pack(φ, A, E, cfg::MVConfig, Nt::Int, M::Int; gain_tilt::Real=0.0)
    off = mv_block_offsets(cfg, Nt, M)
    x = zeros(off.n_total)
    if haskey(off.ranges, :phase)
        x[off.ranges[:phase]] .= vec(φ)
    end
    if haskey(off.ranges, :amplitude)
        x[off.ranges[:amplitude]] .= vec(A)
    end
    if haskey(off.ranges, :energy)
        @assert isfinite(E) && E > 0 "energy must be finite positive to pack, got $E"
        x[first(off.ranges[:energy])] = log(Float64(E))
    end
    if haskey(off.ranges, :gain_tilt)
        x[first(off.ranges[:gain_tilt])] = Float64(gain_tilt)
    end
    return x
end

function mv_physical_amplitude(unpacked, cfg::MVConfig, sim::Dict, Nt::Int, M::Int)
    A_amp_raw = unpacked.A
    A_amp = if :amplitude in cfg.variables && cfg.amp_param === :tanh
        1.0 .+ cfg.δ_bound .* tanh.(A_amp_raw)
    else
        A_amp_raw
    end
    if :gain_tilt in cfg.variables
        A_tilt, dA_tilt_dξ, slope = mv_gain_tilt_amplitude(unpacked.gain_tilt, cfg, sim, Nt, M)
        return (A = A_amp .* A_tilt, A_amp = A_amp, A_tilt = A_tilt,
                dA_tilt_dξ = dA_tilt_dξ, slope = slope)
    end
    return (A = A_amp, A_amp = A_amp, A_tilt = ones(Nt, M),
            dA_tilt_dξ = zeros(Nt, M), slope = 0.0)
end

function _accumulate_A_space_gradient!(
    g::AbstractVector{<:Real},
    off,
    g_A_total,
    A_amp,
    A_tilt,
    dA_amp_dξ,
    dA_tilt_dξ,
)
    if haskey(off.ranges, :amplitude)
        g[off.ranges[:amplitude]] .+= vec(g_A_total .* A_tilt .* dA_amp_dξ)
    end
    if haskey(off.ranges, :gain_tilt)
        g[first(off.ranges[:gain_tilt])] += sum(g_A_total .* A_amp .* dA_tilt_dξ)
    end
    return g
end

# ─────────────────────────────────────────────────────────────────────────────
# Core forward-adjoint + unified gradient assembly
# ─────────────────────────────────────────────────────────────────────────────

"""
    cost_and_gradient_multivar(x, uω0, fiber, sim, band_mask, cfg; E_ref=nothing, Dω=nothing)

Forward-adjoint pipeline with multi-variable gradient assembly.

  1. Unpack `x` into (φ, A, E).
  2. Build α = √(E / E_ref), u_shaped(ω,m) = α·A(ω)·cis(φ(ω))·uω0(ω,m).
  3. Forward solve through fiber.
  4. Compute Raman-band cost J, terminal adjoint λ(L).
  5. Adjoint solve backward → λ₀.
  6. Assemble gradient blocks:
       ∂J/∂φ(ω) = 2 Σ_m Re[ conj(λ₀) · i · u_shaped ]
       ∂J/∂A(ω) = 2 Σ_m Re[ conj(λ₀) · (u_shaped / A) ]
       ∂J/∂η    = Σ_{ω,m} Re[ conj(λ₀) · u_shaped ], with η = log(E)
  7. Apply regularization + log-scale if configured.

Returns `(J_total, g, diagnostics::Dict)` where `g` has the same layout as `x`.
`diagnostics` contains: `J_raman`, `J_regs`, `A_extrema`, `E_shaped`, `alpha`.
"""
function cost_and_gradient_multivar(
    x::AbstractVector{<:Real},
    uω0::AbstractMatrix{<:Complex},
    fiber::Dict,
    sim::Dict,
    band_mask::AbstractVector{Bool},
    cfg::MVConfig;
    E_ref::Union{Nothing,Real}=nothing,
)
    Nt = sim["Nt"]
    M  = sim["M"]
    @assert length(x) > 0 "x is empty"
    @assert size(uω0) == (Nt, M) "uω0 shape $(size(uω0)) ≠ ($Nt, $M)"

    # Reference energy (from un-shaped input if not provided)
    _E_ref = isnothing(E_ref) ? sum(abs2, uω0) : Float64(E_ref)

    parts = mv_unpack(x, cfg, Nt, M, _E_ref)
    φ, A_raw, E = parts.φ, parts.A, parts.E

    # Amplitude parameterization transform (Decision D2 revisited — 2026-04-17):
    #   :tanh    → search variable is ξ; A = 1 + δ·tanh(ξ), bounded in (1-δ, 1+δ).
    #              ∂A/∂ξ = δ·(1 - tanh²(ξ)) = δ - (A-1)²/δ   (stable via (A-1))
    #   :fminbox → search variable IS A; no transform here (Fminbox enforces bounds).
    dA_amp_dξ = ones(Nt, M)
    if :amplitude in cfg.variables && cfg.amp_param === :tanh
        A_amp = 1.0 .+ cfg.δ_bound .* tanh.(A_raw)
        dA_amp_dξ = cfg.δ_bound .* (1.0 .- tanh.(A_raw) .^ 2)
    else
        A_amp = A_raw
    end
    physical_A = mv_physical_amplitude(parts, cfg, sim, Nt, M)
    A = physical_A.A
    A_tilt = physical_A.A_tilt
    dA_tilt_dξ = physical_A.dA_tilt_dξ

    # PRECONDITIONS
    @assert all(isfinite, φ) "phase has NaN/Inf"
    @assert all(isfinite, A) "amplitude has NaN/Inf"
    @assert A_min_ok(A) "amplitude must be strictly > 0 (min=$(minimum(A)))"
    @assert isfinite(E) && E > 0 "energy must be finite positive, got $E"

    α = sqrt(max(E, 0.0) / _E_ref)

    # Build shaped input: u_shaped(ω, m) = α · A(ω) · cis(φ(ω)) · uω0(ω, m)
    u_shaped = similar(uω0)
    @inbounds for i in eachindex(u_shaped)
        u_shaped[i] = α * A[i] * cis(φ[i]) * uω0[i]
    end

    # Forward solve
    fiber_local = fiber  # shared by reference — we do NOT mutate it
    # Ensure zsave=nothing is honored (caller sets it once per sweep)
    sol = MultiModeNoise.solve_disp_mmf(u_shaped, fiber_local, sim)
    ũω = sol["ode_sol"]

    # Lift to lab frame at L
    L   = fiber_local["L"]
    Dω  = fiber_local["Dω"]
    ũω_L = ũω(L)
    uωf = similar(uω0)
    @. uωf = cis(Dω * L) * ũω_L

    # Raman-band cost and adjoint terminal condition
    J_raman, λωL = spectral_band_cost(uωf, band_mask)

    # Adjoint backward solve
    sol_adj = MultiModeNoise.solve_adjoint_disp_mmf(λωL, ũω, fiber_local, sim)
    λ0 = sol_adj(0)

    # Gradient blocks (derivations §3–5)
    g = zeros(Float64, length(x))
    off = parts.offsets

    #   Phase gradient: 2 Re[ conj(λ₀) · i · u_shaped ]
    if haskey(off.ranges, :phase)
        g_phase = @. 2.0 * real(conj(λ0) * (1im * u_shaped))
        g[off.ranges[:phase]] .= vec(g_phase)
    end

    #   Amplitude gradient: 2 Re[ conj(λ₀) · u_shaped / A ]  =  2α Re[ conj(λ₀) · cis(φ) · uω0 ]
    #   For :tanh parameterization, multiply by dA/dξ (chain rule).
    if haskey(off.ranges, :amplitude)
        g_A = @. 2.0 * α * real(conj(λ0) * cis(φ) * uω0)
        _accumulate_A_space_gradient!(g, off, g_A, A_amp, A_tilt, dA_amp_dξ, dA_tilt_dξ)
    elseif haskey(off.ranges, :gain_tilt)
        g_A = @. 2.0 * α * real(conj(λ0) * cis(φ) * uω0)
        _accumulate_A_space_gradient!(g, off, g_A, A_amp, A_tilt, dA_amp_dξ, dA_tilt_dξ)
    end

    #   Energy uses η = log(E). The raw derivative is
    #   ∂J/∂E = (1/E) Σ Re[ conj(λ₀) · u_shaped ], hence ∂J/∂η is the sum.
    if haskey(off.ranges, :energy)
        g[first(off.ranges[:energy])] = real(sum(conj(λ0) .* u_shaped))
    end

    # POSTCONDITIONS on physics
    @assert isfinite(J_raman) "Raman cost not finite"
    @assert all(isfinite, g) "gradient contains NaN/Inf (post forward-adjoint)"

    diag = Dict{Symbol,Any}(
        :J_raman    => J_raman,
        :alpha      => α,
        :A_extrema  => extrema(A),
        :E          => E,
        :E_ref      => _E_ref,
    )

    # ── Regularizers ──────────────────────────────────────────────────────────
    J_total = J_raman
    g_raman_copy = haskey(off.ranges, :phase) ? reshape(copy(g[off.ranges[:phase]]), Nt, M) : zeros(Nt, M)

    reg_breakdown = Dict{String,Float64}("J_raman" => J_raman)

    # GDD penalty on φ (same discrete stencil as raman_optimization.jl)
    if cfg.λ_gdd > 0 && haskey(off.ranges, :phase)
        g_gdd = zeros(Nt, M)
        J_gdd = add_gdd_penalty!(g_gdd, φ, sim["Δt"], cfg.λ_gdd)
        J_total += J_gdd
        g[off.ranges[:phase]] .+= vec(g_gdd)
        reg_breakdown["J_gdd"] = J_gdd
    end

    # Boundary penalty on the shaped input pulse energy at FFT window edges.
    # Phase changes preserve total input energy, but amplitude changes do not;
    # therefore amplitude needs the full quotient-rule derivative of
    # edge_energy / total_energy. Global energy E only rescales u_shaped, so
    # this edge fraction is invariant to E and contributes no E-gradient.
    if cfg.λ_boundary > 0
        J_b = 0.0
        ut0 = ifft(u_shaped, 1)
        n_edge = max(1, Nt ÷ 20)
        mask_edge = zeros(Float64, Nt, M)
        mask_edge[1:n_edge, :] .= 1.0
        mask_edge[end - n_edge + 1:end, :] .= 1.0
        E_t_total = max(sum(abs2, ut0), eps())
        E_edges = sum(abs2.(ut0) .* mask_edge)
        edge_frac = E_edges / E_t_total

        if edge_frac > 1e-8
            J_b = cfg.λ_boundary * edge_frac
            coeff = 2.0 * cfg.λ_boundary / (Nt * E_t_total)
            fft_edge = fft(mask_edge .* ut0, 1)

            if haskey(off.ranges, :phase)
                g_boundary_phase = coeff .* imag.(conj.(u_shaped) .* fft_edge)
                g[off.ranges[:phase]] .+= vec(g_boundary_phase)
            end

            if haskey(off.ranges, :amplitude)
                # d(edge_frac)/dA includes the total-energy denominator term.
                # Since u_shaped = alpha * A * cis(phi) * u0 and A > 0:
                #   du/dA = u_shaped / A.
                g_boundary_A = coeff .* (
                    real.(conj.(fft_edge) .* u_shaped ./ A) .-
                    edge_frac .* abs2.(u_shaped) ./ A
                )
                _accumulate_A_space_gradient!(g, off, g_boundary_A, A_amp, A_tilt, dA_amp_dξ, dA_tilt_dξ)
            elseif haskey(off.ranges, :gain_tilt)
                g_boundary_A = coeff .* (
                    real.(conj.(fft_edge) .* u_shaped ./ A) .-
                    edge_frac .* abs2.(u_shaped) ./ A
                )
                _accumulate_A_space_gradient!(g, off, g_boundary_A, A_amp, A_tilt, dA_amp_dξ, dA_tilt_dξ)
            end
        end
        if J_b > 0
            J_total += J_b
            reg_breakdown["J_boundary"] = J_b
        end
    end

    # Amplitude regularizers (inherited from amplitude_optimization.jl)
    # Accumulate in A-space first, then chain-rule through dA/dξ at the end so
    # the :tanh path gets a consistent ∂J_total/∂ξ.
    if haskey(off.ranges, :amplitude) || haskey(off.ranges, :gain_tilt)
        uω0_abs2 = abs2.(uω0)
        E_original = sum(uω0_abs2)
        g_A_reg = zeros(Nt, M)

        # Energy-preservation penalty (soft): matches amplitude_cost semantics
        if cfg.λ_energy > 0
            S_A = sum((A .^ 2) .* uω0_abs2)
            E_shaped = (α^2) * S_A
            ratio = E_shaped / E_original
            J_E_pen = cfg.λ_energy * (ratio - 1.0)^2
            # ∂(ratio)/∂A = 2·α²·A·|uω0|² / E_original
            g_E_pen = @. 2.0 * cfg.λ_energy * (ratio - 1.0) * (2.0 * α^2 * A * uω0_abs2) / E_original
            g_A_reg .+= g_E_pen
            if haskey(off.ranges, :energy)
                # ratio is proportional to E, so d(ratio)/dη = ratio.
                g[first(off.ranges[:energy])] += 2.0 * cfg.λ_energy * (ratio - 1.0) * ratio
            end
            J_total += J_E_pen
            reg_breakdown["J_energy"] = J_E_pen
        end

        if cfg.λ_tikhonov > 0
            deviation = A .- 1.0
            N_elem = length(deviation)
            J_tik = cfg.λ_tikhonov * sum(deviation .^ 2) / N_elem
            g_tik = @. 2.0 * cfg.λ_tikhonov * deviation / N_elem
            g_A_reg .+= g_tik
            J_total += J_tik
            reg_breakdown["J_tikhonov"] = J_tik
        end

        if cfg.λ_tv > 0
            ε_tv = 1e-6
            J_tv = 0.0
            g_tv = zeros(Nt, M)
            @inbounds for m in 1:M
                for i in 2:Nt
                    d = A[i, m] - A[i-1, m]
                    s = sqrt(d^2 + ε_tv^2)
                    J_tv += s
                    ds = d / s
                    g_tv[i,   m] += ds
                    g_tv[i-1, m] -= ds
                end
            end
            J_tv *= cfg.λ_tv / Nt
            g_tv .*= cfg.λ_tv / Nt
            g_A_reg .+= g_tv
            J_total += J_tv
            reg_breakdown["J_tv"] = J_tv
        end

        # Chain-rule the accumulated A-space reg gradient into active controls.
        _accumulate_A_space_gradient!(g, off, g_A_reg, A_amp, A_tilt, dA_amp_dξ, dA_tilt_dξ)
    end

    # Log-cost transform of the full regularized scalar objective.
    if cfg.log_cost
        J_total = apply_log_surface!(g, J_total)
    end

    merge!(diag, Dict{Symbol,Any}(:breakdown => reg_breakdown))
    @assert isfinite(J_total) "regularized cost is not finite"
    @assert all(isfinite, g) "regularized gradient contains NaN/Inf"

    return J_total, g, diag
end

A_min_ok(A) = minimum(A) > 0   # exposed for @assert

# ─────────────────────────────────────────────────────────────────────────────
# Preconditioning: change of variables y = S·x
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_scaling_vector(cfg, Nt, M) -> Vector{Float64}

Returns per-entry scaling factors `s` such that the scaled search variable is
`y = S·x` (S = diag(s)). When the variable block is absent from `cfg.variables`
it contributes no entries.
"""
function build_scaling_vector(cfg::MVConfig, Nt::Int, M::Int)
    off = mv_block_offsets(cfg, Nt, M)
    s = ones(off.n_total)
    if haskey(off.ranges, :phase)
        s[off.ranges[:phase]] .= cfg.s_φ
    end
    if haskey(off.ranges, :amplitude)
        s[off.ranges[:amplitude]] .= cfg.s_A
    end
    if haskey(off.ranges, :energy)
        s[first(off.ranges[:energy])] = cfg.s_E
    end
    if haskey(off.ranges, :gain_tilt)
        s[first(off.ranges[:gain_tilt])] = 1.0
    end
    return s
end

# ─────────────────────────────────────────────────────────────────────────────
# High-level optimizer
# ─────────────────────────────────────────────────────────────────────────────

"""
    optimize_spectral_multivariable(uω0, fiber, sim, band_mask;
        variables=(:phase, :amplitude),
        max_iter=50,
        φ0=nothing, A0=nothing, E0=nothing,
        δ_bound=MV_DEFAULT_DELTA_AMP,
        λ_gdd=0.0, λ_boundary=0.0,
        λ_energy=0.0, λ_tikhonov=0.0, λ_tv=0.0, λ_flat=0.0,
        log_cost=true,
        store_trace=true)

Run L-BFGS over the unified variable vector. Returns a NamedTuple
    (result, cfg, x_opt, φ_opt, A_opt, E_opt, diagnostics)

`result` is the raw `Optim.OptimizationResults`. The fields `φ_opt`, `A_opt`,
`E_opt` are the unpacked solution (φ_opt zeros if :phase absent, etc.).

Box constraints are applied to A via `Fminbox(LBFGS(m=10))` when :amplitude is
enabled; otherwise plain `LBFGS()`.
"""
function optimize_spectral_multivariable(
    uω0::AbstractMatrix{<:Complex},
    fiber::Dict,
    sim::Dict,
    band_mask::AbstractVector{Bool};
    variables=(:phase, :amplitude),
    max_iter::Int=50,
    φ0=nothing, A0=nothing, E0=nothing,
    δ_bound::Real=MV_DEFAULT_DELTA_AMP,
    amp_param::Symbol=:tanh,
    λ_gdd::Real=0.0, λ_boundary::Real=0.0,
    λ_energy::Real=0.0, λ_tikhonov::Real=0.0, λ_tv::Real=0.0, λ_flat::Real=0.0,
    log_cost::Bool=true,
    store_trace::Bool=true,
)
    Nt = sim["Nt"]; M = sim["M"]
    vars = sanitize_variables(variables)
    @assert amp_param in (:tanh, :fminbox) "amp_param must be :tanh or :fminbox, got $amp_param"

    E_ref = sum(abs2, uω0)

    # Construct config and scaling (preconditioning per Decision D5).
    # For :tanh, the search variable ξ is already O(1); s_A = 1.0 is correct.
    # For :fminbox, search variable is raw A with perturbation scale δ_bound → s_A=1/δ.
    s_A_val = if :amplitude in vars
        amp_param === :tanh ? 1.0 : (1.0 / δ_bound)
    else
        1.0
    end
    cfg = MVConfig(
        variables = vars,
        δ_bound = Float64(δ_bound),
        amp_param = amp_param,
        s_φ = 1.0,
        s_A = s_A_val,
        s_E = 1.0,
        log_cost = log_cost,
        λ_gdd = λ_gdd,
        λ_boundary = λ_boundary,
        λ_energy = λ_energy,
        λ_tikhonov = λ_tikhonov,
        λ_tv = λ_tv,
        λ_flat = λ_flat,
    )
    scale = build_scaling_vector(cfg, Nt, M)

    # Initial guesses. When :tanh, the search variable is ξ such that
    # A = 1 + δ·tanh(ξ). Map A0 → ξ0 = atanh((A0 − 1) / δ).
    φ_init = isnothing(φ0) ? zeros(Nt, M) : Matrix{Float64}(φ0)
    A_init = isnothing(A0) ? ones(Nt, M)  : Matrix{Float64}(A0)
    E_init = isnothing(E0) ? E_ref        : Float64(E0)
    A_init_search = if amp_param === :tanh && :amplitude in vars
        # Invert A = 1 + δ·tanh(ξ) — clamp to avoid Inf at boundary.
        u = clamp.((A_init .- 1.0) ./ δ_bound, -1.0 + 1e-6, 1.0 - 1e-6)
        atanh.(u)
    else
        A_init
    end
    x0 = mv_pack(φ_init, A_init_search, E_init, cfg, Nt, M)
    y0 = scale .* x0   # scaled search variable (L-BFGS operates on y)

    # Fiber mutation guard: caller should set zsave = nothing but we enforce.
    # (Mutating once at the TOP is fine — amplitude_optimization.jl does the
    # deepcopy per call; here we save the GC pressure by enforcing up front.)
    fiber["zsave"] = nothing

    # Optim.jl interface in scaled space
    t_start = time()
    last_diag = Ref{Any}(nothing)
    iters_done = Ref(0)
    progress_every = parse(Int, get(ENV, "MV_PROGRESS_EVERY", "5"))
    eval_progress_every = parse(Int, get(ENV, "MV_EVAL_PROGRESS_EVERY", "10"))
    f_calls_limit = parse(Int, get(ENV, "MV_OPT_F_CALLS_LIMIT", "0"))
    time_limit_s = parse(Float64, get(ENV, "MV_OPT_TIME_LIMIT_S", "NaN"))
    evals_done = Ref(0)
    function callback(state)
        # Under Fminbox, `state` is the trace Vector{OptimizationState}; under
        # plain LBFGS it is a single OptimizationState. Handle both.
        s = state isa AbstractVector ? last(state) : state
        iters_done[] = s.iteration
        bd = last_diag[]
        if bd !== nothing && progress_every > 0 &&
           (s.iteration == 1 || s.iteration % progress_every == 0 || s.iteration == max_iter)
            @info Printf.@sprintf("multivar progress [%3d/%d] J=%.4e  J_ram=%.4e  α=%.3f  A∈[%.3f,%.3f]",
                s.iteration, max_iter, s.value,
                get(bd, :J_raman, NaN), get(bd, :alpha, NaN),
                get(bd, :A_extrema, (NaN, NaN))[1], get(bd, :A_extrema, (NaN, NaN))[2])
        end
        return false
    end

    # Fminbox path only for :fminbox; :tanh goes through plain LBFGS (the
    # tanh transform keeps A ∈ (1-δ, 1+δ) unconditionally so no box needed).
    use_box = (:amplitude in vars) && (amp_param === :fminbox)
    if use_box
        lower_x = fill(-Inf, length(x0))
        upper_x = fill(Inf, length(x0))
        off = mv_block_offsets(cfg, Nt, M)
        lower_x[off.ranges[:amplitude]] .= 1.0 - δ_bound
        upper_x[off.ranges[:amplitude]] .= 1.0 + δ_bound
        # Nudge inside
        for i in off.ranges[:amplitude]
            x0[i] = clamp(x0[i], 1.0 - δ_bound + 1e-8, 1.0 + δ_bound - 1e-8)
        end
        y0 = scale .* x0
        lower_y = scale .* lower_x
        upper_y = scale .* upper_x
    end

    # Closure in scaled space: unscale, evaluate, apply chain rule to gradient
    fg_closure = Optim.only_fg!() do F, G, y
        x = y ./ scale
        J, g_x, diag = cost_and_gradient_multivar(x, uω0, fiber, sim, band_mask, cfg; E_ref=E_ref)
        last_diag[] = diag
        evals_done[] += 1
        if eval_progress_every > 0 && evals_done[] % eval_progress_every == 0
            @info Printf.@sprintf("multivar eval [%4d] J=%.4e  J_ram=%.4e  α=%.3f  A∈[%.3f,%.3f]",
                evals_done[], J, get(diag, :J_raman, NaN), get(diag, :alpha, NaN),
                get(diag, :A_extrema, (NaN, NaN))[1], get(diag, :A_extrema, (NaN, NaN))[2])
        end
        if G !== nothing
            G .= g_x ./ scale      # dJ/dy = (1/s)·dJ/dx
        end
        if F !== nothing
            return J
        end
    end

    # Default linesearch (HagerZhang via Optim) — was replaced once with
    # BackTracking but that did no better (cold-start accepted zero-length
    # steps on the first attempt). Root cause of poor convergence is the
    # log_cost gradient scaling near an optimum, not the linesearch choice.
    # Reference runs use log_cost=false for multivar runs to avoid that pathology.
    method_lbfgs = LBFGS(m=10)

    opts = Optim.Options(
        iterations = max_iter,
        f_abstol   = log_cost ? 0.01 : 1e-10,
        f_calls_limit = f_calls_limit,
        time_limit = time_limit_s,
        callback   = callback,
        store_trace= store_trace,
        extended_trace = false,
    )

    result = if use_box
        optimize(fg_closure, lower_y, upper_y, y0, Fminbox(method_lbfgs),
                 Optim.Options(iterations=max_iter, outer_iterations=max_iter,
                               f_abstol=log_cost ? 0.01 : 1e-10,
                               f_calls_limit=f_calls_limit, time_limit=time_limit_s,
                               callback=callback, store_trace=store_trace))
    else
        optimize(fg_closure, y0, method_lbfgs, opts)
    end

    y_opt = result.minimizer
    x_opt = y_opt ./ scale
    unpacked = mv_unpack(x_opt, cfg, Nt, M, E_ref)

    # When :tanh, `unpacked.A` is ξ (search variable). Compute the physical A
    # for the return value; cost_and_gradient_multivar does this transform
    # internally each call, so the diagnostics below see the right A.
    physical_opt = mv_physical_amplitude(unpacked, cfg, sim, Nt, M)
    A_opt_physical = physical_opt.A

    elapsed = time() - t_start

    # Final re-evaluation for clean diagnostics (unscaled gradient)
    J_opt, g_opt, diag_opt = cost_and_gradient_multivar(x_opt, uω0, fiber, sim, band_mask, cfg; E_ref=E_ref)

    return (
        result = result,
        cfg = cfg,
        scale = scale,
        x_opt = x_opt,
        φ_opt = unpacked.φ,
        A_opt = A_opt_physical,
        E_opt = unpacked.E,
        gain_tilt_opt = physical_opt.slope,
        gain_tilt_search = unpacked.gain_tilt,
        E_ref = E_ref,
        J_opt = J_opt,
        g_norm = norm(g_opt),
        diagnostics = diag_opt,
        wall_time_s = elapsed,
        iterations = iters_done[],
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Persistence: JLD2 payload + JSON sidecar (Decision D6, schema doc)
# ─────────────────────────────────────────────────────────────────────────────

"""
    save_multivar_result(prefix, outcome; meta=Dict())

Write `<prefix>_result.jld2` and `<prefix>_slm.json`.  `outcome` is the
NamedTuple returned by `optimize_spectral_multivariable`.  `meta` can include
run-level fields like `fiber_name`, `L_m`, `P_cont_W`, `lambda0_nm`, `fwhm_fs`,
`gamma`, `betas`, `convergence_history`.
"""
_json_safe_value(x) = x
_json_safe_value(x::Bool) = x
_json_safe_value(x::Integer) = x
_json_safe_value(x::AbstractFloat) = isfinite(x) ? x : nothing
_json_safe_value(x::Real) = isfinite(Float64(x)) ? Float64(x) : nothing
_json_safe_value(x::AbstractVector) = [_json_safe_value(v) for v in x]
_json_safe_value(x::Tuple) = [_json_safe_value(v) for v in x]
_json_safe_value(x::AbstractDict) = Dict(string(k) => _json_safe_value(v) for (k, v) in x)

function save_multivar_result(prefix::AbstractString, outcome; meta::Dict=Dict{Symbol,Any}())
    artifact_paths = artifact_paths_for_prefix(prefix; sidecar_suffix="_slm.json")
    jld2_path = artifact_paths.jld2
    json_path = artifact_paths.json
    mkpath(dirname(abspath(jld2_path)))

    cfg = outcome.cfg
    Nt = size(outcome.φ_opt, 1)
    M  = size(outcome.φ_opt, 2)
    objective_kind = string(get(meta, :objective_kind, "multivariable"))
    objective_backend = string(get(meta, :objective_backend, "raman_optimization"))
    objective_label = String(get(meta, :objective_label, "multivariable Raman spectral shaping optimization"))
    objective_base_term = String(get(meta, :objective_base_term, "J_physics"))
    control_scalars = Dict{String,Float64}(
        String(key) => Float64(value)
        for (key, value) in get(meta, :control_scalars, Dict{String,Float64}())
    )
    objective_spec = multivar_cost_surface_spec(cfg;
        objective_label = objective_label,
        base_term = objective_base_term)
    cost_surface_payload = Dict{String,Any}(
        "objective_kind" => objective_kind,
        "objective_backend" => objective_backend,
        "objective_label" => objective_spec.objective_label,
        "log_cost" => objective_spec.log_cost,
        "scale" => objective_spec.scale,
        "surface" => objective_spec.scalar_surface,
        "pre_log_linear_surface" => objective_spec.pre_log_linear_surface,
        "regularizers_chained_into_surface" => objective_spec.regularizers_chained_into_surface,
    )

    # Baseline (unshaped) input energy
    E_ref = outcome.E_ref
    E_opt = outcome.E_opt

    convergence = get(meta, :convergence_history, Float64[])

    write_jld2_file(jld2_path;
        schema_version = "1.0",
        variables_enabled = [String(v) for v in cfg.variables],
        # fiber / pulse
        fiber_name = String(get(meta, :fiber_name, "unknown")),
        L_m = Float64(get(meta, :L_m, NaN)),
        P_cont_W = Float64(get(meta, :P_cont_W, NaN)),
        lambda0_nm = Float64(get(meta, :lambda0_nm, NaN)),
        fwhm_fs = Float64(get(meta, :fwhm_fs, NaN)),
        gamma = Float64(get(meta, :gamma, NaN)),
        betas = Vector{Float64}(get(meta, :betas, Float64[])),
        # grid
        Nt = Nt,
        M = M,
        time_window_ps = Float64(get(meta, :time_window_ps, NaN)),
        objective_kind = objective_kind,
        objective_backend = objective_backend,
        objective_label = objective_label,
        control_scalars = control_scalars,
        # shaping
        phi_opt = outcome.φ_opt,
        amp_opt = outcome.A_opt,
        gain_tilt_opt = Float64(get(outcome, :gain_tilt_opt, 0.0)),
        gain_tilt_search = Float64(get(outcome, :gain_tilt_search, 0.0)),
        E_opt = E_opt,
        E_ref = E_ref,
        c_opt = ComplexF64[1.0 + 0im for _ in 1:M],  # stub per Decision D4
        uomega0 = Matrix{ComplexF64}(get(meta, :uomega0, zeros(ComplexF64, Nt, M))),
        # metrics
        J_before = Float64(get(meta, :J_before, NaN)),
        J_after  = Float64(get(meta, :J_after_lin, outcome.J_opt)),
        delta_J_dB = Float64(get(meta, :delta_J_dB, NaN)),
        grad_norm = Float64(outcome.g_norm),
        converged = Optim.converged(outcome.result),
        iterations = outcome.iterations,
        wall_time_s = outcome.wall_time_s,
        convergence_history = convergence,
        band_mask = Bool.(get(meta, :band_mask, Bool[])),
        sim_Dt = Float64(get(meta, :sim_Dt, NaN)),
        sim_omega0 = Float64(get(meta, :sim_omega0, NaN)),
        regularizers = Dict{String,Float64}(
            "lambda_gdd"      => cfg.λ_gdd,
            "lambda_boundary" => cfg.λ_boundary,
            "lambda_energy"   => cfg.λ_energy,
            "lambda_tikhonov" => cfg.λ_tikhonov,
            "lambda_tv"       => cfg.λ_tv,
            "lambda_flat"     => cfg.λ_flat,
        ),
        cost_surface = cost_surface_payload,
        preconditioning_s = Dict{String,Float64}(
            "s_phi"       => cfg.s_φ,
            "s_amplitude" => cfg.s_A,
            "s_energy"    => cfg.s_E,
        ),
        run_tag = String(get(meta, :run_tag, Dates.format(now(), "yyyymmdd_HHMMss"))),
    )

    # JSON sidecar
    json_payload = Dict{String,Any}(
        "schema_version" => "1.0",
        "generator" => "scripts/lib/multivar_optimization.jl",
        "generated_at" => string(now()),
        "result_file" => basename(jld2_path),
        "fiber" => Dict(
            "name" => String(get(meta, :fiber_name, "unknown")),
            "L_m" => Float64(get(meta, :L_m, NaN)),
            "gamma_W_inv_m_inv" => Float64(get(meta, :gamma, NaN)),
            "betas" => Vector{Float64}(get(meta, :betas, Float64[])),
        ),
        "pulse" => Dict(
            "lambda0_nm" => Float64(get(meta, :lambda0_nm, NaN)),
            "P_cont_W"   => Float64(get(meta, :P_cont_W, NaN)),
            "fwhm_fs"    => Float64(get(meta, :fwhm_fs, NaN)),
            "rep_rate_Hz"=> Float64(get(meta, :rep_rate_Hz, NaN)),
        ),
        "grid" => Dict(
            "Nt" => Nt, "M" => M,
            "time_window_ps" => Float64(get(meta, :time_window_ps, NaN)),
            "omega_grid" => Dict(
                "units" => "rad/ps",
                "ordering" => "fftfreq",
                "storage_key" => "sim_omega0",
            ),
        ),
        "variables_enabled" => [String(v) for v in cfg.variables],
        "scalar_controls" => control_scalars,
        "cost_surface" => cost_surface_payload,
        "shaped_input_formula" =>
            "u_shaped(omega) = alpha * A(omega) * exp(i*phi(omega)) * c_m * uomega0(omega); " *
            "alpha = sqrt(E_opt / E_ref)",
        "outputs" => Dict(
            "phase"     => Dict("storage_key" => "phi_opt", "shape" => [Nt, M], "units" => "rad"),
            "amplitude" => Dict("storage_key" => "amp_opt", "shape" => [Nt, M], "units" => "dimensionless"),
            "gain_tilt" => Dict("storage_key" => "gain_tilt_opt", "units" => "dimensionless bounded slope"),
            "scalar_controls" => Dict("storage_key" => "control_scalars", "units" => "variable-specific"),
            "energy_E"  => Dict("storage_key" => "E_opt", "units" => "arb."),
            "energy_reference" => Dict("storage_key" => "E_ref", "units" => "arb."),
            "mode_coeffs" => Dict("storage_key" => "c_opt", "shape" => [M], "units" => "dimensionless complex"),
        ),
        "metrics" => Dict(
            "J_before" => Float64(get(meta, :J_before, NaN)),
            "J_after"  => Float64(get(meta, :J_after_lin, outcome.J_opt)),
            "delta_J_dB" => Float64(get(meta, :delta_J_dB, NaN)),
            "converged" => Optim.converged(outcome.result),
            "iterations" => outcome.iterations,
            "wall_time_s" => outcome.wall_time_s,
        ),
        "provenance" => Dict(
            "branch" => String(get(meta, :git_branch, "sessions/A-multivar")),
            "commit" => String(get(meta, :git_commit, "unknown")),
            "julia_version" => string(VERSION),
            "threads" => Threads.nthreads(),
        ),
    )
    write_json_file(json_path, _json_safe_value(json_payload))

    @info "multivar: saved" jld2_path json_path
    return (jld2=jld2_path, json=json_path)
end

"""
    load_multivar_result(prefix) -> NamedTuple

Read both `<prefix>_result.jld2` and `<prefix>_slm.json`. Returns a NamedTuple
mirroring the save format with a `.sidecar` field for the JSON contents.
"""
function load_multivar_result(prefix::AbstractString)
    jld2_path = "$(prefix)_result.jld2"
    json_path = "$(prefix)_slm.json"
    @assert isfile(jld2_path) "missing $jld2_path"
    @assert isfile(json_path) "missing $json_path"

    payload = jldopen(jld2_path, "r") do f
        Dict(k => read(f, k) for k in keys(f))
    end
    sidecar = JSON3.read(read(json_path, String))

    return (
        phi_opt = payload["phi_opt"],
        amp_opt = payload["amp_opt"],
        gain_tilt_opt = haskey(payload, "gain_tilt_opt") ? payload["gain_tilt_opt"] : 0.0,
        gain_tilt_search = haskey(payload, "gain_tilt_search") ? payload["gain_tilt_search"] : 0.0,
        E_opt = payload["E_opt"],
        E_ref = payload["E_ref"],
        c_opt = payload["c_opt"],
        J_after = payload["J_after"],
        J_before = payload["J_before"],
        delta_J_dB = payload["delta_J_dB"],
        converged = payload["converged"],
        iterations = payload["iterations"],
        wall_time_s = payload["wall_time_s"],
        convergence_history = payload["convergence_history"],
        regularizers = payload["regularizers"],
        cost_surface = payload["cost_surface"],
        preconditioning_s = payload["preconditioning_s"],
        variables_enabled = payload["variables_enabled"],
        payload = payload,
        sidecar = sidecar,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# High-level runner (analogous to run_optimization in raman_optimization.jl)
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_multivar_optimization(; save_prefix, variables, fiber_name, max_iter,
                                 validate, kwargs...)

End-to-end convenience wrapper. Sets up the problem via `setup_raman_problem`
(M=1 SMF by default), runs the optimizer, saves JLD2+JSON, returns the
outcome NamedTuple.

If `validate=true`, runs a mini finite-difference check before optimization.
"""
function run_multivar_optimization(;
    save_prefix::AbstractString="results/raman/multivar/mvopt",
    variables=(:phase, :amplitude),
    fiber_name::AbstractString="Custom",
    max_iter::Int=50,
    validate::Bool=true,
    δ_bound::Real=MV_DEFAULT_DELTA_AMP,
    amp_param::Symbol=:tanh,
    φ0=nothing, A0=nothing,
    λ_gdd::Real=1e-4, λ_boundary::Real=1.0,
    λ_energy::Real=1.0, λ_tikhonov::Real=0.0, λ_tv::Real=0.0, λ_flat::Real=0.0,
    log_cost::Bool=true,
    objective_kind::Symbol=:raman_band,
    solver_reltol::Real=1e-8,
    solver_f_abstol=:auto,
    solver_g_abstol=:auto,
    kwargs...,
)
    objective_kind == :raman_band || throw(ArgumentError(
        "multivar optimization currently supports objective_kind=:raman_band, got $(objective_kind)"))
    _ = (solver_reltol, solver_f_abstol, solver_g_abstol)
    t0 = time()
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(; kwargs...)

    _λ0 = get(kwargs, :λ0, 1550e-9)
    _P_cont = get(kwargs, :P_cont, 0.05)
    _pulse_fwhm = get(kwargs, :pulse_fwhm, 185e-15)
    _L_fiber = get(kwargs, :L_fiber, 1.0)
    _rep_rate = get(kwargs, :pulse_rep_rate, 80.5e6)

    Nt, M = sim["Nt"], sim["M"]
    E_ref = sum(abs2, uω0)

    if validate
        s_A_val = amp_param === :tanh ? 1.0 : (1.0 / δ_bound)
        cfg_val = MVConfig(
            variables = sanitize_variables(variables),
            δ_bound = Float64(δ_bound),
            amp_param = amp_param,
            s_φ = 1.0,
            s_A = s_A_val,
            s_E = 1.0 / E_ref,
            log_cost = false,   # validate on linear cost for clean FD
        )
        @info "multivar: validating gradient before optimization"
        mv_validate_gradient(uω0, fiber, sim, band_mask, cfg_val; n_checks=3, rel_tol=5e-2)
    end

    outcome = optimize_spectral_multivariable(
        uω0, fiber, sim, band_mask;
        variables = variables,
        max_iter = max_iter,
        δ_bound = δ_bound,
        amp_param = amp_param,
        φ0 = φ0, A0 = A0,
        λ_gdd = λ_gdd, λ_boundary = λ_boundary,
        λ_energy = λ_energy, λ_tikhonov = λ_tikhonov,
        λ_tv = λ_tv, λ_flat = λ_flat,
        log_cost = log_cost,
    )

    # Metrics for meta dict.
    # Un-shaped baseline means φ=0, A=1, E=E_ref. For :tanh parameterization
    # the search var ξ=0 corresponds to A=1; for :fminbox ξ==A==1 directly.
    A_baseline_search = outcome.cfg.amp_param === :tanh ? zeros(Nt, M) : ones(Nt, M)
    x_zero = mv_pack(zeros(Nt, M), A_baseline_search, E_ref, outcome.cfg, Nt, M)
    cfg_linear = deepcopy(outcome.cfg); cfg_linear.log_cost = false
    J_before, _, _ = cost_and_gradient_multivar(x_zero, uω0, fiber, sim, band_mask, cfg_linear; E_ref=E_ref)

    # Evaluate the optimum cost on linear scale for fair dB comparison
    cfg_linear2 = deepcopy(outcome.cfg); cfg_linear2.log_cost = false
    J_after_lin, _, _ = cost_and_gradient_multivar(outcome.x_opt, uω0, fiber, sim, band_mask, cfg_linear2; E_ref=E_ref)
    ΔJ_dB = MultiModeNoise.lin_to_dB(J_after_lin) - MultiModeNoise.lin_to_dB(J_before)

    # Convergence history
    conv = if outcome.cfg.log_cost
        try
            collect(Optim.f_trace(outcome.result))
        catch
            Float64[]
        end
    else
        try
            MultiModeNoise.lin_to_dB.(Optim.f_trace(outcome.result))
        catch
            Float64[]
        end
    end

    meta = Dict{Symbol,Any}(
        :fiber_name => fiber_name,
        :L_m => _L_fiber,
        :P_cont_W => _P_cont,
        :lambda0_nm => _λ0 * 1e9,
        :fwhm_fs => _pulse_fwhm * 1e15,
        :rep_rate_Hz => _rep_rate,
        :gamma => fiber["γ"][1],
        :betas => haskey(fiber, "betas") ? fiber["betas"] : Float64[],
        :time_window_ps => Nt * sim["Δt"],
        :sim_Dt => sim["Δt"],
        :sim_omega0 => sim["ω0"],
        :J_before => J_before,
        :J_after_lin => J_after_lin,
        :delta_J_dB => ΔJ_dB,
        :band_mask => band_mask,
        :uomega0 => uω0,
        :convergence_history => conv,
        :run_tag => Dates.format(now(), "yyyymmdd_HHMMss"),
    )
    objective_spec = multivar_cost_surface_spec(outcome.cfg)

    saved = save_multivar_result(save_prefix, outcome; meta=meta)

    elapsed = time() - t0
    @info Printf.@sprintf("""
    ┌──────────────────── MULTIVAR RUN SUMMARY ────────────────────┐
    │  Save prefix      %s
    │  Variables        %s
    │  Fiber            %s  L=%.2fm  γ=%.2e
    │  Grid             Nt=%d  window=%.1f ps
    │  Objective        %s
    │  Iterations       %d  (%.1f s total, %.1f s optim)
    │  J (before)       %.4e (%.1f dB)
    │  J (after)        %.4e (%.1f dB)
    │  ΔJ               %.2f dB
    │  ‖∇J‖ at opt      %.2e  | α=%.3f | A∈[%.3f, %.3f]
    └───────────────────────────────────────────────────────────────┘""",
        save_prefix,
        join(String.(outcome.cfg.variables), "+"),
        fiber_name, fiber["L"], fiber["γ"][1],
        Nt, Nt * sim["Δt"],
        objective_spec.scalar_surface,
        outcome.iterations, elapsed, outcome.wall_time_s,
        J_before, MultiModeNoise.lin_to_dB(J_before),
        J_after_lin, MultiModeNoise.lin_to_dB(J_after_lin),
        ΔJ_dB,
        outcome.g_norm, outcome.diagnostics[:alpha],
        outcome.diagnostics[:A_extrema][1], outcome.diagnostics[:A_extrema][2],
    )

    return (outcome=outcome, meta=meta, saved=saved,
            uω0=uω0, fiber=fiber, sim=sim, band_mask=band_mask,
            J_before=J_before, J_after_lin=J_after_lin, ΔJ_dB=ΔJ_dB)
end

# ─────────────────────────────────────────────────────────────────────────────
# Gradient validation
# ─────────────────────────────────────────────────────────────────────────────

"""
    mv_validate_gradient(uω0, fiber, sim, band_mask, cfg; n_checks=3, rel_tol=1e-6)

For each enabled variable block, pick random indices in the "significant-energy"
region of the spectrum (phase/amp) or just ±ε (energy), run symmetric finite
differences on the linear-cost evaluation, and compare to the adjoint gradient.

Returns `Dict{Symbol, Float64}` of the worst-case rel. error per block.  Throws
if any block exceeds `rel_tol`.
"""
function mv_validate_gradient(
    uω0::AbstractMatrix{<:Complex},
    fiber::Dict, sim::Dict, band_mask::AbstractVector{Bool},
    cfg::MVConfig;
    n_checks::Int=3, rel_tol::Real=1e-6,
)
    Nt = sim["Nt"]; M = sim["M"]
    E_ref = sum(abs2, uω0)

    # Base test point: small-random phase, near-unity amp, E ≈ E_ref.
    # When :tanh, the search variable is ξ; ξ ≈ 0.1·randn gives A very close to 1.
    φ_test = 0.1 .* randn(Nt, M)
    A_test = if cfg.amp_param === :tanh
        0.1 .* randn(Nt, M)          # ξ ∈ ℝ
    else
        1.0 .+ 0.02 .* randn(Nt, M)  # A in box
    end
    E_test = E_ref * (1.0 + 0.05 * randn())
    gain_tilt_test = 0.1 * randn()
    x0 = mv_pack(φ_test, A_test, E_test, cfg, Nt, M; gain_tilt=gain_tilt_test)

    # Linear-cost for clean FD comparison
    cfg_lin = deepcopy(cfg); cfg_lin.log_cost = false
    J0, g, _ = cost_and_gradient_multivar(x0, uω0, fiber, sim, band_mask, cfg_lin; E_ref=E_ref)

    worst = Dict{Symbol,Float64}()
    off = mv_block_offsets(cfg, Nt, M)

    spectral_power = vec(sum(abs2, uω0; dims=2))
    threshold = 0.01 * maximum(spectral_power)
    significant_cols = findall(spectral_power .> threshold)
    @assert !isempty(significant_cols) "no spectral energy? check uω0"

    for var in cfg.variables
        ε = var === :phase    ? MV_DEFAULT_EPS_FD_PHASE  :
            var === :amplitude ? MV_DEFAULT_EPS_FD_AMP    :
            var === :energy   ? MV_DEFAULT_EPS_FD_ENERGY :
            var === :gain_tilt ? MV_DEFAULT_EPS_FD_GAIN_TILT :
                                1e-6
        rng = off.ranges[var]
        # pick indices
        idxs = if var === :energy || var === :gain_tilt
            [first(rng)]
        else
            # first column is m=1; map (ω_sig, m=1) to flat index
            ωs = rand(significant_cols, min(n_checks, length(significant_cols)))
            [first(rng) + (1 - 1) * Nt + (i - 1) for i in ωs]
        end

        block_worst = 0.0
        for i in idxs
            xp = copy(x0); xp[i] += ε
            xm = copy(x0); xm[i] -= ε
            Jp, _, _ = cost_and_gradient_multivar(xp, uω0, fiber, sim, band_mask, cfg_lin; E_ref=E_ref)
            Jm, _, _ = cost_and_gradient_multivar(xm, uω0, fiber, sim, band_mask, cfg_lin; E_ref=E_ref)
            fd = (Jp - Jm) / (2ε)
            adj = g[i]
            rel_err = abs(adj - fd) / max(abs(adj), abs(fd), 1e-15)
            block_worst = max(block_worst, rel_err)
            @info Printf.@sprintf("  [%s] idx=%d  adj=%.4e  fd=%.4e  rel_err=%.2e  (ε=%.1e)",
                var, i, adj, fd, rel_err, ε)
        end
        worst[var] = block_worst
        if block_worst > rel_tol
            error("Gradient check FAILED for $var: worst rel_err=$(block_worst) > tol=$(rel_tol)")
        end
    end

    @info "multivar: gradient validation PASS" worst
    return worst
end

end # include guard
