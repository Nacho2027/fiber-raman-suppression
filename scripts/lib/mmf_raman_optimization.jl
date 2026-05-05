"""
Multimode Raman-suppression phase optimizer (Session C, Phase 16 Plan 01).

Mirror of `scripts/raman_optimization.jl` for the multimode (M>1) case:
- Spectral phase is SHARED across modes (physically realizable with a single
  pulse shaper): φ::Vector{Float64} of length Nt, broadcast to (Nt, M) inside
  `cost_and_gradient_mmf`.
- Input mode coefficients `c_m` are passed as a separate argument and held
  FIXED in Phase 16 plan 01. Phase 17 will optimize them jointly — see
  `.planning/seeds/mmf-joint-phase-mode-optimization.md`.
- Uses the existing `FiberLab.solve_disp_mmf` /
  `solve_adjoint_disp_mmf` machinery unchanged.

Protected files (no edits): `scripts/common.jl`, `scripts/raman_optimization.jl`,
`scripts/sharpness_optimization.jl`, `src/simulation/*.jl`,
`src/helpers/helpers.jl`, `src/FiberLab.jl`.

Used by the front-layer experiment runner for multimode phase searches.
"""

# Revise for dev loop
try
    using Revise
catch
end

# Headless matplotlib when plots are requested
ENV["MPLBACKEND"] = "Agg"

using LinearAlgebra
using FFTW
using Printf
using Logging
using Statistics
using Random
using Dates

using FiberLab
using Optim
using PyPlot

struct MMFOptimizationLimit <: Exception
    reason::Symbol
end

function Base.showerror(io::IO, err::MMFOptimizationLimit)
    print(io, "MMF optimization stopped by ", err.reason, " limit")
end

function _select_mmf_reported_optimum(
    candidate_φ::AbstractVector{<:Real},
    candidate_J::Real,
    best_φ::AbstractVector{<:Real},
    best_J::Real,
)
    if isfinite(best_J) && (!isfinite(candidate_J) || best_J < candidate_J)
        return copy(best_φ), Float64(best_J), true
    end
    return copy(candidate_φ), Float64(candidate_J), false
end

include(joinpath(@__DIR__, "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "src", "mmf_cost.jl"))

# save_standard_set expects visualization helpers (plot_optimization_result_v2,
# plot_spectral_evolution, plot_phase_diagnostic) which live in scripts/visualization.jl.
# That file is in the protected set — we include it read-only. standard_images.jl is
# the new mandatory wrapper; every driver MUST call save_standard_set after phi_opt.
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "objective_surface.jl"))
include(joinpath(@__DIR__, "regularizers.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Cost variant dispatch
# ─────────────────────────────────────────────────────────────────────────────

"""
    _mmf_cost_call(variant::Symbol, uωf, band_mask)

Dispatch to the chosen cost variant from `src/mmf_cost.jl`.
"""
function _mmf_cost_call(variant::Symbol, uωf, band_mask)
    if variant === :sum
        return mmf_cost_sum(uωf, band_mask)
    elseif variant === :fundamental
        return mmf_cost_fundamental(uωf, band_mask)
    elseif variant === :worst_mode
        return mmf_cost_worst_mode(uωf, band_mask)
    else
        throw(ArgumentError("unknown cost variant :$variant"))
    end
end

function mmf_forward_output(
    φ::AbstractVector{<:Real},
    uω0_base::AbstractMatrix,
    fiber::Dict,
    sim::Dict,
)
    phase_factor = cis.(φ)
    uω0_shaped = uω0_base .* phase_factor
    sol = FiberLab.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω = sol["ode_sol"]
    L = fiber["L"]
    uωf = cis.(fiber["Dω"] .* L) .* ũω(L)
    return (; uω0_shaped, sol, uωf)
end

"""
    mmf_output_time_field(uωf) -> Matrix{ComplexF64}

Recover the time-domain output field from the repository's frequency-domain
MMF field convention. `get_initial_state` stores `uω = ifft(ut)`, and the
forward solver records saved time-domain fields with `fft(uω, 1)`.
"""
function mmf_output_time_field(uωf::AbstractMatrix)
    return fft(uωf, 1)
end

"""
    mmf_trust_metrics(φ, setup; boundary_threshold=1e-3, τ=50.0) -> NamedTuple

Forward-only trust summary for a multimode phase profile. This is used for run
reporting, not for optimization itself.
"""
function mmf_trust_metrics(
    φ::AbstractVector{<:Real},
    setup::NamedTuple;
    boundary_threshold::Real = 1e-3,
    τ::Real = 50.0,
)
    prop = mmf_forward_output(φ, setup.uω0, setup.fiber, setup.sim)
    cost_report = mmf_cost_report(prop.uωf, setup.band_mask; τ = τ)
    # Project convention is `uω = ifft(ut)` and `ut = fft(uω)`. Measure
    # optimization trust on the raw output field; the legacy attenuator-recovery
    # check can amplify harmless edge roundoff into false boundary failures.
    ut_in = mmf_output_time_field(prop.uω0_shaped)
    ut_out = mmf_output_time_field(prop.uωf)
    input_boundary_ok, input_boundary_edge_fraction = check_raw_temporal_edges(
        ut_in; threshold = boundary_threshold
    )
    output_boundary_ok, output_boundary_edge_fraction = check_raw_temporal_edges(
        ut_out; threshold = boundary_threshold
    )
    boundary_ok = input_boundary_ok && output_boundary_ok
    boundary_edge_fraction = max(input_boundary_edge_fraction, output_boundary_edge_fraction)
    return (
        cost_report = cost_report,
        boundary_ok = boundary_ok,
        boundary_edge_fraction = boundary_edge_fraction,
        input_boundary_ok = input_boundary_ok,
        input_boundary_edge_fraction = input_boundary_edge_fraction,
        output_boundary_ok = output_boundary_ok,
        output_boundary_edge_fraction = output_boundary_edge_fraction,
        boundary_threshold = Float64(boundary_threshold),
        uωf = prop.uωf,
    )
end

"""
    mmf_cost_surface_spec(; variant=:sum, log_cost=true, λ_gdd=0.0, λ_boundary=0.0,
                           objective_label="MMF Raman shared-phase optimization")

Machine-readable description of the scalar objective returned by
`cost_and_gradient_mmf`.
"""
function mmf_cost_surface_spec(;
    variant::Symbol = :sum,
    log_cost::Bool = true,
    λ_gdd::Real = 0.0,
    λ_boundary::Real = 0.0,
    objective_label::AbstractString = "MMF Raman shared-phase optimization",
)
    base_cost = variant === :sum ? "J_mmf_sum" :
                variant === :fundamental ? "J_mmf_fundamental" :
                variant === :worst_mode ? "J_mmf_worst_mode" :
                throw(ArgumentError("unknown MMF cost variant :$variant"))
    return build_objective_surface_spec(;
        objective_label = objective_label,
        log_cost = log_cost,
        linear_terms = active_linear_terms(
            [base_cost],
            [(λ_gdd > 0, "λ_gdd*R_gdd"), (λ_boundary > 0, "λ_boundary*R_boundary")],
        ),
        leading_fields = (variant = String(variant),),
        trailing_fields = (
            lambda_gdd = Float64(λ_gdd),
            lambda_boundary = Float64(λ_boundary),
        ),
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# cost_and_gradient_mmf
# ─────────────────────────────────────────────────────────────────────────────

"""
    cost_and_gradient_mmf(φ, c_m, uω0_base, fiber, sim, band_mask; kwargs...)
        -> (J_total, grad::Vector{Float64})

Forward-adjoint cost + gradient for the multimode Raman problem, with a
**shared-across-modes** spectral phase.

# Arguments
- `φ::AbstractVector{<:Real}`  length Nt — spectral phase on the shaper
- `c_m::AbstractVector`        length M  — input mode coefficients (held fixed)
- `uω0_base::AbstractMatrix`   shape (Nt, M) — pre-shaped input field
  (with `c_m` already baked in via `setup_mmf_raman_problem`)
- `fiber`, `sim`, `band_mask`  as returned by `setup_mmf_raman_problem`

# Keyword arguments
- `variant::Symbol = :sum`             — `:sum | :fundamental | :worst_mode`
- `λ_gdd = 0.0`                        — penalty on ∫(d²φ/dω²)² (regularizer)
- `λ_boundary = 0.0`                   — penalty on input-pulse energy at FFT edges
- `log_cost::Bool = true`              — optimize 10·log₁₀(J) instead of J
- `φ_grad_workspace = nothing`         — pre-allocated grad buffer (optional)

# Returns
- `J_total::Float64`
- `grad::Vector{Float64}`              same length as φ
"""
function cost_and_gradient_mmf(
    φ::AbstractVector{<:Real},
    c_m::AbstractVector,
    uω0_base::AbstractMatrix,
    fiber::Dict,
    sim::Dict,
    band_mask::AbstractVector{Bool};
    variant::Symbol = :sum,
    λ_gdd::Real = 0.0,
    λ_boundary::Real = 0.0,
    log_cost::Bool = true,
)
    Nt = size(uω0_base, 1)
    M  = size(uω0_base, 2)

    # PRECONDITIONS
    @assert length(φ)   == Nt  "φ length $(length(φ)) ≠ Nt=$Nt"
    @assert length(c_m) == M   "c_m length $(length(c_m)) ≠ M=$M"
    @assert all(isfinite, φ)   "φ contains NaN/Inf"

    # Apply shared phase — broadcast φ (Nt,) across modes
    # uω0_base already has c_m baked in (set up by setup_mmf_raman_problem)
    phase_factor = cis.(φ)                         # (Nt,)
    uω0_shaped   = uω0_base .* phase_factor        # (Nt, M)

    # Forward solve
    sol = FiberLab.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω  = sol["ode_sol"]

    # Lab-frame output at z=L
    L     = fiber["L"]
    Dω    = fiber["Dω"]
    ũω_L  = ũω(L)
    uωf   = cis.(Dω .* L) .* ũω_L                  # (Nt, M)

    # Cost and adjoint terminal condition
    J, λωL = _mmf_cost_call(variant, uωf, band_mask)

    # Adjoint backward solve
    sol_adj = FiberLab.solve_adjoint_disp_mmf(λωL, ũω, fiber, sim)
    λ0      = sol_adj(0)                           # (Nt, M)

    # Chain rule: ∂J/∂φ_expanded[t,m] = 2 · Re(conj(λ₀[t,m]) · i · uω0_shaped[t,m])
    # Physical constraint: φ shared across modes ⇒ reduce by summing over m
    ∂J_∂φ_expanded = 2.0 .* real.(conj.(λ0) .* (1im .* uω0_shaped))   # (Nt, M)
    ∂J_∂φ          = vec(sum(∂J_∂φ_expanded, dims = 2))               # (Nt,)

    # POSTCONDITIONS
    @assert isfinite(J)           "cost non-finite: $J"
    @assert all(isfinite, ∂J_∂φ)  "gradient non-finite"

    J_total = J
    grad_total = copy(∂J_∂φ)

    # GDD regularizer on the shared phase
    J_total += add_gdd_penalty!(grad_total, φ, sim["Δt"], λ_gdd)

    # Boundary energy penalty on the time-domain input
    J_total += add_shared_boundary_phase_penalty!(
        grad_total, uω0_base .* phase_factor, λ_boundary)

    if log_cost
        J_total = apply_log_surface!(grad_total, J_total)
    end

    @assert isfinite(J_total)         "regularized cost non-finite: $J_total"
    @assert all(isfinite, grad_total) "regularized gradient non-finite"

    return J_total, grad_total
end

# ─────────────────────────────────────────────────────────────────────────────
# optimize_mmf_phase — L-BFGS on shared φ
# ─────────────────────────────────────────────────────────────────────────────

"""
    optimize_mmf_phase(uω0_base, c_m, fiber, sim, band_mask; kwargs...)
        -> NamedTuple(φ_opt, J_final, J_history, result)

L-BFGS driver for the MMF Raman-phase optimization.

# Keyword arguments
- `φ0::Union{Nothing, Vector{Float64}} = nothing`  initial guess (default zeros)
- `max_iter::Int = 30`
- `variant::Symbol = :sum`
- `λ_gdd = 0.0`, `λ_boundary = 0.0`
- `log_cost::Bool = true`
- `store_trace::Bool = true`
- `seed::Int = 42`
- `f_calls_limit::Int = 0`, `time_limit::Real = NaN`: hard driver-side
  pre-evaluation limits. Optim.jl only checks some limits after an iteration,
  which can include many expensive line-search evaluations; these guards stop
  before the next propagation call and return the best observed phase.
- `verbose::Bool = true`
"""
function optimize_mmf_phase(
    uω0_base::AbstractMatrix,
    c_m::AbstractVector,
    fiber::Dict,
    sim::Dict,
    band_mask::AbstractVector{Bool};
    φ0::Union{Nothing, AbstractVector{<:Real}} = nothing,
    max_iter::Int = 30,
    variant::Symbol = :sum,
    λ_gdd::Real = 0.0,
    λ_boundary::Real = 0.0,
    log_cost::Bool = true,
    store_trace::Bool = true,
    seed::Int = 42,
    f_calls_limit::Int = 0,
    time_limit::Real = NaN,
    verbose::Bool = true,
)
    Nt = size(uω0_base, 1)
    rng = MersenneTwister(seed)
    φ_init = isnothing(φ0) ? zeros(Float64, Nt) : copy(φ0)
    @assert length(φ_init) == Nt

    J_history = Float64[]
    best_J = Inf
    best_φ = copy(φ_init)
    hard_time_limit = Float64(time_limit)
    t_start = time()

    function fg!(F, G, φ)
        if f_calls_limit > 0 && length(J_history) >= f_calls_limit
            throw(MMFOptimizationLimit(:f_calls_limit))
        end
        if isfinite(hard_time_limit) && hard_time_limit > 0 && time() - t_start >= hard_time_limit
            throw(MMFOptimizationLimit(:time_limit))
        end
        J, g = cost_and_gradient_mmf(
            φ, c_m, uω0_base, fiber, sim, band_mask;
            variant = variant,
            λ_gdd = λ_gdd, λ_boundary = λ_boundary,
            log_cost = log_cost,
        )
        if G !== nothing
            G .= g
        end
        push!(J_history, J)
        if J < best_J
            best_J = J
            best_φ = copy(φ)
        end
        if verbose && length(J_history) % 1 == 0
            @info @sprintf("  iter %3d: J = %.6e (%s)",
                length(J_history), J, log_cost ? "dB" : "linear")
        end
        return J
    end

    result = nothing
    stopped_by = nothing
    φ_opt = best_φ
    J_final = best_J
    try
        result = Optim.optimize(
            Optim.only_fg!(fg!),
            φ_init,
            Optim.LBFGS(),
            Optim.Options(
                iterations = max_iter,
                f_calls_limit = f_calls_limit,
                store_trace = store_trace,
                show_trace = false,
                allow_f_increases = true,
                time_limit = hard_time_limit,
            ),
        )

        φ_candidate = Optim.minimizer(result)
        J_candidate = Optim.minimum(result)
        φ_opt, J_final, used_best_observed = _select_mmf_reported_optimum(
            φ_candidate, J_candidate, best_φ, best_J,
        )
        if verbose && used_best_observed
            @info "MMF optimizer returned a worse/non-finite minimum; using best observed phase" J_candidate best_J evaluations=length(J_history)
        end
    catch err
        if err isa MMFOptimizationLimit
            stopped_by = err.reason
            J_final = best_J
            φ_opt = best_φ
            if verbose
                @info "MMF optimization stopped by driver-side limit; returning best observed phase" reason=stopped_by evaluations=length(J_history)
            end
        else
            rethrow()
        end
    end

    # Also report linear-scale J at φ_opt for logging
    J_lin, _ = cost_and_gradient_mmf(
        φ_opt, c_m, uω0_base, fiber, sim, band_mask;
        variant = variant, log_cost = false,
    )

    if verbose
        @info @sprintf("MMF optimization done: J_final = %.6e (%s), J_lin = %.3e (-%.2f dB), iters = %d",
            J_final, log_cost ? "dB" : "linear",
            J_lin, -10 * log10(max(J_lin, 1e-15)), length(J_history))
    end

    return (
        φ_opt     = φ_opt,
        J_final   = J_final,
        J_lin     = J_lin,
        J_history = J_history,
        result    = result,
        stopped_by = stopped_by,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Plotting
# ─────────────────────────────────────────────────────────────────────────────

"""
    plot_mmf_result(φ_before, φ_after, setup, opt_result; save_prefix, title_suffix)

Produce four PNG figures for an MMF Raman optimization run:
- `<prefix>_total_spectrum.png`
- `<prefix>_per_mode_spectrum.png`
- `<prefix>_phase.png`
- `<prefix>_convergence.png`
"""
function plot_mmf_result(
    φ_before::AbstractVector,
    φ_after::AbstractVector,
    setup::NamedTuple,
    opt_result::NamedTuple;
    save_prefix::String = "mmf_opt",
    title_suffix::String = "",
    variant::Symbol = :sum,
    log_cost::Bool = true,
    λ_gdd::Real = 0.0,
    λ_boundary::Real = 0.0,
)
    uω0_base = setup.uω0
    fiber    = setup.fiber
    sim      = setup.sim
    band_mask = setup.band_mask
    objective_spec = mmf_cost_surface_spec(
        variant = variant,
        log_cost = log_cost,
        λ_gdd = λ_gdd,
        λ_boundary = λ_boundary,
    )
    Δf       = setup.Δf
    rth      = setup.raman_threshold
    Nt, M    = size(uω0_base)

    # Output spectra before/after
    function _spectrum_at(φ)
        phase_factor = cis.(φ)
        uω0_shaped   = uω0_base .* phase_factor
        sol          = FiberLab.solve_disp_mmf(uω0_shaped, fiber, sim)
        ũω           = sol["ode_sol"]
        L            = fiber["L"]
        uωf          = cis.(fiber["Dω"] .* L) .* ũω(L)
        return uωf
    end

    uωf_before = _spectrum_at(φ_before)
    uωf_after  = _spectrum_at(φ_after)

    Δf_shifted = Δf  # fftshifted frequency grid (THz)
    # For plotting, shift the spectrum too
    shifted(x) = fftshift(x, 1)
    S_before_total = sum(abs2.(shifted(uωf_before)); dims = 2)[:, 1]
    S_after_total  = sum(abs2.(shifted(uωf_after));  dims = 2)[:, 1]

    mkpath(dirname(save_prefix * "_x") == "" ? "." : dirname(save_prefix * "_x"))

    # (1) Total spectrum
    fig, ax = subplots(figsize = (8, 5))
    ax.semilogy(Δf_shifted, max.(S_before_total, 1e-20), label = "before opt", lw = 1, alpha = 0.7, color = "gray")
    ax.semilogy(Δf_shifted, max.(S_after_total, 1e-20), label = "after opt", lw = 1.5, color = "C0")
    ax.axvspan(minimum(Δf_shifted), rth, alpha = 0.15, color = "red", label = "Raman band")
    ax.set_xlabel("Δf [THz]")
    ax.set_ylabel("|u(ω)|² summed over modes [arb.]")
    ax.set_title("MMF Raman suppression — total spectrum " * title_suffix)
    ax.set_xlim(-30, 15)
    ax.legend(loc = "upper right")
    ax.grid(true, which = "both", alpha = 0.3)
    fig.tight_layout()
    fig.savefig(save_prefix * "_total_spectrum.png", dpi = 300)
    close(fig)

    # (2) Per-mode spectrum (grid of M subplots)
    ncols = min(M, 3)
    nrows = ceil(Int, M / ncols)
    fig, axs = subplots(nrows, ncols, figsize = (4.5 * ncols, 3.0 * nrows))
    axs_flat = nrows * ncols == 1 ? [axs] : collect(axs)
    for m in 1:M
        ax = axs_flat[m]
        ax.semilogy(Δf_shifted, max.(shifted(abs2.(uωf_before[:, m])), 1e-20), lw = 1, alpha = 0.7, color = "gray", label = "before")
        ax.semilogy(Δf_shifted, max.(shifted(abs2.(uωf_after[:, m])), 1e-20),  lw = 1.5, color = "C$(m-1)", label = "after")
        ax.axvspan(minimum(Δf_shifted), rth, alpha = 0.12, color = "red")
        ax.set_xlim(-30, 15)
        ax.set_title(@sprintf("mode %d (%.1f%% input)", m, 100 * abs2(setup.mode_weights[m])))
        ax.grid(true, which = "both", alpha = 0.3)
        if m == 1
            ax.legend(loc = "upper right", fontsize = 8)
        end
    end
    for m in (M + 1):(nrows * ncols)
        axs_flat[m].axis("off")
    end
    fig.suptitle("Per-mode output spectra " * title_suffix)
    fig.tight_layout()
    fig.savefig(save_prefix * "_per_mode_spectrum.png", dpi = 300)
    close(fig)

    # (3) Phase (gauge-fixed: remove mean and linear-in-ω slope)
    function _gauge_fix(φ)
        Nt_φ = length(φ)
        Ω    = collect(0:(Nt_φ - 1)) .- Nt_φ ÷ 2
        mean_φ = mean(φ)
        # slope from least-squares: φ_lin = a·Ω + b  on the Ω scale
        a = sum(Ω .* (φ .- mean_φ)) / sum(Ω .^ 2)
        return φ .- mean_φ .- a .* Ω
    end
    φ_before_gf = _gauge_fix(φ_before)
    φ_after_gf  = _gauge_fix(φ_after)
    φ_before_shifted = fftshift(φ_before_gf)
    φ_after_shifted  = fftshift(φ_after_gf)

    fig, ax = subplots(figsize = (8, 4))
    ax.plot(Δf_shifted, φ_before_shifted, lw = 1, color = "gray", alpha = 0.7, label = "before (gauge-fixed)")
    ax.plot(Δf_shifted, φ_after_shifted,  lw = 1.5, color = "C2", label = "after (gauge-fixed)")
    ax.set_xlabel("Δf [THz]")
    ax.set_ylabel("φ(ω) [rad, mean+slope removed]")
    ax.set_title("Spectral phase " * title_suffix)
    ax.set_xlim(-30, 15)
    ax.legend()
    ax.grid(true, alpha = 0.3)
    fig.tight_layout()
    fig.savefig(save_prefix * "_phase.png", dpi = 300)
    close(fig)

    # (4) Convergence
    fig, ax = subplots(figsize = (7, 4))
    ax.plot(1:length(opt_result.J_history), opt_result.J_history, lw = 1.3, marker = "o", markersize = 3)
    ax.set_xlabel("L-BFGS iteration")
    ax.set_ylabel("J (10·log₁₀ if log_cost=true)")
    ax.set_title("Convergence trace " * title_suffix)
    ax.grid(true, alpha = 0.3)
    fig.tight_layout()
    fig.savefig(save_prefix * "_convergence.png", dpi = 300)
    close(fig)

    return nothing
end

# ─────────────────────────────────────────────────────────────────────────────
# Main entry point
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_mmf_baseline(; kwargs...) -> NamedTuple

Convenience wrapper: build the MMF setup, run L-BFGS for `max_iter` iterations,
produce figures, return the result.

The front-layer multimode execution path runs this
at the canonical Phase 16 baseline (GRIN-50, L=1m, P=0.05W).
"""
function run_mmf_baseline(;
    preset::Symbol = :GRIN_50,
    L_fiber::Real = 1.0,
    P_cont::Real = 0.05,
    Nt::Int = 2^13,
    time_window::Real = 10.0,
    max_iter::Int = 30,
    variant::Symbol = :sum,
    log_cost::Bool = true,
    λ_gdd::Real = 0.0,
    λ_boundary::Real = 0.0,
    f_calls_limit::Int = 0,
    time_limit::Real = NaN,
    seed::Int = 42,
    save_dir::String = joinpath(@__DIR__, "..", "..", "results", "raman", "phase16"),
    tag::String = "",
)
    mkpath(save_dir)
    setup = setup_mmf_raman_problem(;
        preset = preset,
        L_fiber = L_fiber,
        P_cont = P_cont,
        Nt = Nt,
        time_window = time_window,
    )

    uω0      = setup.uω0
    c_m      = setup.mode_weights
    fiber    = setup.fiber
    sim      = setup.sim
    band_mask = setup.band_mask

    # Reference J at φ=0 (unoptimized)
    Nt_setup = size(uω0, 1)
    φ0 = zeros(Float64, Nt_setup)
    trust_ref = mmf_trust_metrics(φ0, setup)
    J_ref = trust_ref.cost_report.sum_lin
    J_ref_dB = trust_ref.cost_report.sum_dB
    objective_spec = mmf_cost_surface_spec(
        variant = variant,
        log_cost = log_cost,
        λ_gdd = λ_gdd,
        λ_boundary = λ_boundary,
    )
    @info @sprintf("Reference (φ=0): J_lin = %.4e (%.2f dB)", J_ref, J_ref_dB)
    @info "MMF objective surface: $(objective_spec.scalar_surface)"

    # Optimize
    t0 = time()
    opt = optimize_mmf_phase(
        uω0, c_m, fiber, sim, band_mask;
        φ0 = φ0,
        max_iter = max_iter,
        variant = variant,
        log_cost = log_cost,
        λ_gdd = λ_gdd,
        λ_boundary = λ_boundary,
        f_calls_limit = f_calls_limit,
        time_limit = time_limit,
        seed = seed,
    )
    wall_time = time() - t0

    trust_opt = mmf_trust_metrics(opt.φ_opt, setup)
    J_final_lin_dB = trust_opt.cost_report.sum_dB
    improvement_dB = J_ref_dB - J_final_lin_dB
    @info @sprintf(
        "Baseline done in %.1f s. J_sum: %.2f→%.2f dB (Δ=%.2f dB); J_fund=%.2f dB; J_worst=%.2f dB; edge=%.2e",
        wall_time,
        J_ref_dB,
        J_final_lin_dB,
        improvement_dB,
        trust_opt.cost_report.fundamental_dB,
        trust_opt.cost_report.worst_mode_true_dB,
        trust_opt.boundary_edge_fraction,
    )

    # Figures
    tag_s = isempty(tag) ? @sprintf("%s_L%g_P%g_seed%d", String(preset), L_fiber, P_cont, seed) : tag
    save_prefix = joinpath(save_dir, "mmf_baseline_" * tag_s)
    plot_mmf_result(
        φ0, opt.φ_opt, setup, opt;
        save_prefix = save_prefix,
        title_suffix = @sprintf("[%s, L=%gm, P=%gW]", String(preset), L_fiber, P_cont),
        variant = variant,
        log_cost = log_cost,
        λ_gdd = λ_gdd,
        λ_boundary = λ_boundary,
    )

    # ── MANDATORY standard image set (AGENTS.md rule, 2026-04-17) ─────────
    # Every driver producing phi_opt MUST call save_standard_set. Uses the
    # fundamental-mode slice internally (mode_idx=1) — appropriate for MMF
    # since LP01 is the dominant detected mode. phi_opt is a Vector{Float64}
    # (shared across modes); save_standard_set handles Vector input cleanly
    # (it uses phi[:, 1] indexing which returns the whole vector for 1D inputs).
    save_standard_set(
        opt.φ_opt, uω0, fiber, sim,
        band_mask, setup.Δf, setup.raman_threshold;
        tag         = lowercase(replace(@sprintf("mmf_%s_l%gm_p%gw_seed%d",
                                                 String(preset), L_fiber, P_cont, seed),
                                        "." => "p")),
        fiber_name  = String(preset),
        L_m         = L_fiber,
        P_W         = P_cont,
        output_dir  = save_dir,
    )

    return (
        setup          = setup,
        opt            = opt,
        J_ref_lin      = J_ref,
        J_ref_dB       = J_ref_dB,
        J_final_lin_dB = J_final_lin_dB,
        improvement_dB = improvement_dB,
        wall_time      = wall_time,
        save_prefix    = save_prefix,
        trust_ref      = trust_ref,
        trust_opt      = trust_opt,
    )
end

# CLI guard — only execute when run as a script
if abspath(PROGRAM_FILE) == @__FILE__
    @info "MMF Raman optimization — Phase 16 baseline"
    @info "Threads: $(Threads.nthreads())"
    result = run_mmf_baseline()
    @info "All figures saved under results/raman/phase16/"
end
