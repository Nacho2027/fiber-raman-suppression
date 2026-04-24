"""
Shared Raman suppression optimization library used by the maintained workflow
surface.

This file provides `run_optimization`, cost/gradient helpers, result payload
assembly, and plotting glue for single-mode spectral-phase optimization.

When executed directly it still runs the historical five-run comparison suite,
but the supported public single-run entry point is now
`scripts/canonical/optimize_raman.jl`.

# Inputs
- Config constants at top of file (fiber preset, L, P, pulse FWHM, max_iter).
- `scripts/lib/common.jl` for `FIBER_PRESETS` and `setup_raman_problem`.
- `MultiModeNoise.ensure_deterministic_environment()` pins FFTW/BLAS threads
  for bit-identity runs.

# Outputs
- `results/raman/<run_id>/_result.jld2` — full JLD2 payload (φ_opt, uω0, uωf,
  convergence history in dB, grid, fiber dict, metadata).
- `results/raman/<run_id>/_result.json` — JSON sidecar with scalar metadata.
- `results/raman/<run_id>/*.png` — three figures (spectral, phase, evolution).
- `results/raman/manifest.json` — append-safe index of all runs.

# Runtime
~5 minutes on a 4-core laptop for the canonical SMF-28 config (L=2 m, P=0.2 W,
Nt=2^13, max_iter=30). Scale linearly with `max_iter`; super-linearly with Nt.

# Docs
Docs: docs/guides/quickstart-optimization.md
"""

try using Revise catch end
using Printf
using LinearAlgebra
using Statistics
using FFTW
using Logging
ENV["MPLBACKEND"] = "Agg"  # Non-interactive backend for headless execution
using PyPlot
using MultiModeNoise
using Optim
using JLD2
using JSON3

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "canonical_runs.jl"))
include(joinpath(@__DIR__, "manifest_io.jl"))
include(joinpath(@__DIR__, "objective_surface.jl"))
include(joinpath(@__DIR__, "regularizers.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "..", "research", "analysis", "numerical_trust.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Setup and cost functions are in common.jl:
#   setup_raman_problem, spectral_band_cost, recommended_time_window,
#   check_boundary_conditions
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# 5. Full optimization pipeline: spectral phase → cost → gradient
# ─────────────────────────────────────────────────────────────────────────────

"""
    cost_and_gradient(φ, uω0, fiber, sim, band_mask)

Full forward-adjoint pipeline:
1. Apply additional spectral phase: u₀(ω) = uω0(ω) · exp(iφ(ω))
2. Forward solve through fiber
3. Compute cost J at output
4. Adjoint solve backward to get λ(0)
5. Chain rule to get ∂J/∂φ

Returns (J, ∂J/∂φ).
"""
function raman_cost_surface_spec(;
    log_cost::Bool=true,
    λ_gdd::Real=0.0,
    λ_boundary::Real=0.0,
    objective_kind::Symbol=:raman_band,
    objective_label::AbstractString="single-mode Raman spectral phase optimization")

    physics_label = objective_kind == :raman_peak ? "physics_peak" : "physics"
    return build_objective_surface_spec(;
        objective_label = objective_label,
        log_cost = log_cost,
        linear_terms = [physics_label, "λ_gdd*R_gdd", "λ_boundary*R_boundary"],
        trailing_fields = (
            objective_kind = objective_kind,
            lambda_gdd = Float64(λ_gdd),
            lambda_boundary = Float64(λ_boundary),
            boundary_penalty_measurement = "pre-attenuator temporal edge fraction of shaped input pulse",
            hvp_safe_for_same_surface = true,
        ),
    )
end

function cost_and_gradient(φ, uω0, fiber, sim, band_mask;
    uω0_shaped::Union{Nothing,AbstractMatrix}=nothing,
    uωf_buffer::Union{Nothing,AbstractMatrix}=nothing,
    objective_kind::Symbol=:raman_band,
    λ_gdd=0.0,
    λ_boundary=0.0,
    log_cost::Bool=true)

    # PRECONDITIONS
    @assert size(φ) == size(uω0) "φ shape $(size(φ)) ≠ uω0 shape $(size(uω0))"
    @assert all(isfinite, φ) "phase contains NaN/Inf"

    # Apply spectral phase: cis(x) = cos(x) + i·sin(x), avoids exp() overhead
    if isnothing(uω0_shaped)
        uω0_shaped = @. uω0 * cis(φ)
    else
        @. uω0_shaped = uω0 * cis(φ)
    end

    # Forward solve
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω = sol["ode_sol"]

    # Get output field in lab frame using cis() for the dispersion phase
    L = fiber["L"]
    Dω = fiber["Dω"]
    ũω_L = ũω(L)
    if isnothing(uωf_buffer)
        uωf = @. cis(Dω * L) * ũω_L
    else
        @. uωf_buffer = cis(Dω * L) * ũω_L
        uωf = uωf_buffer
    end

    # Cost and adjoint terminal condition
    if objective_kind == :raman_band
        J, λωL = spectral_band_cost(uωf, band_mask)
    elseif objective_kind == :raman_peak
        J, λωL = spectral_peak_band_cost(uωf, band_mask)
    else
        throw(ArgumentError("unknown Raman objective kind `$(objective_kind)`"))
    end

    # Adjoint solve: propagate λ backward from L to 0
    sol_adj = MultiModeNoise.solve_adjoint_disp_mmf(λωL, ũω, fiber, sim)
    λ0 = sol_adj(0)

    # Chain rule: ∂J/∂φ(ω) = 2 · Re(λ₀*(ω) · i · u₀(ω))
    ∂J_∂φ = 2.0 .* real.(conj.(λ0) .* (1im .* uω0_shaped))

    # POSTCONDITIONS on physics cost (before regularization)
    @assert isfinite(J) "cost is not finite: $J"
    @assert all(isfinite, ∂J_∂φ) "gradient contains NaN/Inf"

    J_total = J
    grad_total = copy(∂J_∂φ)

    # ── GDD penalty: ∫(d²φ/dω²)² dω, scaled by Δω⁻³ for N-independence ──
    J_total += add_gdd_penalty!(grad_total, φ, sim["Δt"], λ_gdd)

    # ── Boundary penalty: penalizes energy at FFT window edges of input pulse ──
    J_total += add_boundary_phase_penalty!(grad_total, uω0_shaped, λ_boundary)

    # Log-scale the entire regularized objective so the returned gradient matches
    # the scalar objective seen by L-BFGS.
    if log_cost
        J_total = apply_log_surface!(grad_total, J_total)
    end

    @assert isfinite(J_total) "regularized cost is not finite: $J_total"
    @assert all(isfinite, grad_total) "regularized gradient contains NaN/Inf"

    return J_total, grad_total
end

# ─────────────────────────────────────────────────────────────────────────────
# 6. Optimization with L-BFGS
# ─────────────────────────────────────────────────────────────────────────────

function optimize_spectral_phase(uω0_base, fiber, sim, band_mask;
    φ0=nothing, max_iter=50, λ_gdd=0.0, λ_boundary=0.0, store_trace::Bool=false,
    log_cost::Bool=true, objective_kind::Symbol=:raman_band)

    # PRECONDITIONS
    @assert max_iter > 0 "max_iter must be positive"
    @assert haskey(sim, "Nt") && haskey(sim, "M") "sim dict missing Nt or M"

    Nt = sim["Nt"]
    M = sim["M"]

    # Initial phase: zero (unshaped pulse) or user-provided
    if isnothing(φ0)
        φ0 = zeros(Nt, M)
    end

    # Ensure zsave=nothing for optimization (avoids deepcopy in cost_and_gradient)
    fiber["zsave"] = nothing

    # Pre-allocate buffers reused every iteration (avoids GC pressure)
    uω0_shaped = similar(uω0_base)
    uωf_buffer = similar(uω0_base)

    # Callback for monitoring
    function callback(state)
        @debug @sprintf("Iter %3d: J = %.6e (%.2f dB)",
            state.iteration, state.value, MultiModeNoise.lin_to_dB(state.value))
        return false
    end

    # Optim.jl interface: combined cost + gradient
    # NOTE: Both cost and gradient must be on the same scale for L-BFGS.
    # log_cost=true: cost in dB, gradient scaled by chain rule — keeps ∇J ~ O(1)
    # log_cost=false: cost and gradient both linear (legacy behavior)
    f_tol = log_cost ? 0.01 : 1e-10  # 0.01 dB vs 1e-10 linear
    result = optimize(
        Optim.only_fg!() do F, G, φ_vec
            φ = reshape(φ_vec, Nt, M)
            J, ∂J_∂φ = cost_and_gradient(φ, uω0_base, fiber, sim, band_mask;
                uω0_shaped=uω0_shaped, uωf_buffer=uωf_buffer,
                objective_kind=objective_kind,
                λ_gdd=λ_gdd, λ_boundary=λ_boundary, log_cost=log_cost)
            if G !== nothing
                G .= vec(∂J_∂φ)
            end
            if F !== nothing
                return J
            end
        end,
        vec(φ0),
        LBFGS(),
        Optim.Options(iterations=max_iter, f_abstol=f_tol, callback=callback, store_trace=store_trace)
    )

    return result
end

# ─────────────────────────────────────────────────────────────────────────────
# 7. Visualization helpers
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# 7a. Gradient validation via finite differences
# ─────────────────────────────────────────────────────────────────────────────

"""
Validate the adjoint gradient against finite differences.
Tests a few random phase components to make sure they agree.
"""
function validate_gradient(uω0_base, fiber, sim, band_mask;
    n_checks=5, ε=1e-5, objective_kind::Symbol=:raman_band,
    λ_gdd=0.0, λ_boundary=0.0, log_cost::Bool=true)
    Nt = sim["Nt"]
    M = sim["M"]
    φ_test = 0.1 * randn(Nt, M)

    J0, grad = cost_and_gradient(φ_test, uω0_base, fiber, sim, band_mask;
        objective_kind=objective_kind,
        λ_gdd=λ_gdd, λ_boundary=λ_boundary, log_cost=log_cost)

    # Pick indices where the pulse has significant amplitude (near center of spectrum)
    # The pulse energy is concentrated in the middle of the FFT grid
    spectral_power = vec(sum(abs2.(uω0_base), dims=2))
    significant = findall(spectral_power .> 0.01 * maximum(spectral_power))
    indices = significant[rand(1:length(significant), min(n_checks, length(significant)))]
    @info "Gradient validation (ε = $ε)"
    lines = [@sprintf("  %5s  %12s  %12s  %10s", "index", "adjoint", "fin. diff.", "rel. error")]
    rel_errors = Float64[]

    for idx in indices
        φ_plus = copy(φ_test)
        φ_plus[idx, 1] += ε
        J_plus, _ = cost_and_gradient(φ_plus, uω0_base, fiber, sim, band_mask;
            objective_kind=objective_kind,
            λ_gdd=λ_gdd, λ_boundary=λ_boundary, log_cost=log_cost)

        φ_minus = copy(φ_test)
        φ_minus[idx, 1] -= ε
        J_minus, _ = cost_and_gradient(φ_minus, uω0_base, fiber, sim, band_mask;
            objective_kind=objective_kind,
            λ_gdd=λ_gdd, λ_boundary=λ_boundary, log_cost=log_cost)

        fd_grad = (J_plus - J_minus) / (2ε)
        adj_grad = grad[idx, 1]
        rel_err = abs(adj_grad - fd_grad) / max(abs(adj_grad), abs(fd_grad), 1e-15)
        push!(rel_errors, rel_err)

        push!(lines, @sprintf("  %5d  %12.6e  %12.6e  %10.2e", idx, adj_grad, fd_grad, rel_err))
    end
    @debug join(lines, "\n")
    return (
        max_rel_err = isempty(rel_errors) ? NaN : maximum(rel_errors),
        mean_rel_err = isempty(rel_errors) ? NaN : mean(rel_errors),
        n_checks = length(rel_errors),
        epsilon = ε,
    )
end

"""
    validate_gradient_taylor(φ, v, uω0, fiber, sim, band_mask;
                             λ_gdd=0.0, λ_boundary=0.0, log_cost=true,
                             eps_range=10.0 .^ (-2:-0.5:-6))

Directional Taylor-remainder check for the exact scalar objective returned by
`cost_and_gradient`. For a consistent `(J, ∇J)` pair, the remainder

    |J(φ + εv) - J(φ) - ε ∇J(φ)⋅v|

should decay like `O(ε²)` over the truncation-error regime.
"""
function validate_gradient_taylor(φ, v, uω0, fiber, sim, band_mask;
    objective_kind::Symbol=:raman_band,
    λ_gdd::Real=0.0,
    λ_boundary::Real=0.0,
    log_cost::Bool=true,
    eps_range::AbstractVector{<:Real}=10.0 .^ (-2:-0.5:-6))

    @assert size(φ) == size(v) "φ and v must have the same shape"
    @assert any(abs.(v) .> 0) "v must be nonzero"

    J0, grad0 = cost_and_gradient(φ, uω0, fiber, sim, band_mask;
        objective_kind=objective_kind,
        λ_gdd=λ_gdd, λ_boundary=λ_boundary, log_cost=log_cost)
    dir0 = sum(grad0 .* v)

    eps_values = collect(Float64.(eps_range))
    remainders = Float64[]
    for ε in eps_values
        Jp, _ = cost_and_gradient(φ .+ ε .* v, uω0, fiber, sim, band_mask;
            objective_kind=objective_kind,
            λ_gdd=λ_gdd, λ_boundary=λ_boundary, log_cost=log_cost)
        push!(remainders, abs(Jp - J0 - ε * dir0))
    end

    valid = findall(>(0.0), remainders)
    @assert length(valid) >= 3 "Need at least 3 positive Taylor remainders to fit a slope"
    fit_idx = valid[1:min(end, 4)]
    xs = log10.(eps_values[fit_idx])
    ys = log10.(remainders[fit_idx])
    slope = (ys[end] - ys[1]) / (xs[end] - xs[1])

    return (
        eps_values = eps_values,
        remainders = remainders,
        slope = slope,
        slope_region = (first(fit_idx), last(fit_idx)),
        base_cost = J0,
        base_directional_derivative = dir0,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# 7b. Visualization helpers
# ─────────────────────────────────────────────────────────────────────────────

"""Plot spectra, temporal pulse shapes, and spectral phase before and after optimization.
DEPRECATED: Use plot_optimization_result_v2 from visualization.jl instead.
"""
function plot_optimization_result(φ_before, φ_after, uω0_base, fiber, sim, band_mask, Δf, raman_threshold)
    return plot_optimization_result_v2(φ_before, φ_after, uω0_base, fiber, sim,
        band_mask, Δf, raman_threshold)
end

# ─────────────────────────────────────────────────────────────────────────────
# 8. Chirp sensitivity analysis
# ─────────────────────────────────────────────────────────────────────────────

"""
    chirp_sensitivity(φ_opt, uω0, fiber, sim, band_mask;
                      gdd_range, tod_range)

Evaluate how the optimized cost J degrades when the input pulse acquires
additional quadratic chirp (GDD) or cubic chirp (TOD) on top of the
optimized spectral phase.

GDD adds φ_chirp(ω) = ½ · GDD · (2π·Δf)², TOD adds ⅙ · TOD · (2π·Δf)³.
Units: GDD in [ps²], TOD in [ps³].
"""
function chirp_sensitivity(φ_opt, uω0, fiber, sim, band_mask;
    gdd_range = range(-0.05, 0.05, length=21),
    tod_range = range(-0.005, 0.005, length=21))

    # PRECONDITIONS
    @assert size(φ_opt) == size(uω0) "φ_opt shape must match uω0"
    @assert length(gdd_range) > 0 "gdd_range must not be empty"
    @assert length(tod_range) > 0 "tod_range must not be empty"

    Δf_fft = fftfreq(sim["Nt"], 1 / sim["Δt"])
    ω_fft = 2π .* Δf_fft  # angular frequency offset [rad/ps]
    M = sim["M"]

    # GDD sweep: φ_chirp(ω) = ½ · GDD · ω²
    ω2 = ω_fft .^ 2
    J_gdd = zeros(length(gdd_range))
    for (i, gdd) in enumerate(gdd_range)
        φ_perturbed = φ_opt .+ 0.5 .* gdd .* ω2 .* ones(1, M)
        J_gdd[i], _ = cost_and_gradient(φ_perturbed, uω0, fiber, sim, band_mask; log_cost=false)
    end

    # TOD sweep: φ_chirp(ω) = ⅙ · TOD · ω³
    ω3 = ω_fft .^ 3
    J_tod = zeros(length(tod_range))
    for (i, tod) in enumerate(tod_range)
        φ_perturbed = φ_opt .+ (tod / 6.0) .* ω3 .* ones(1, M)
        J_tod[i], _ = cost_and_gradient(φ_perturbed, uω0, fiber, sim, band_mask; log_cost=false)
    end

    return gdd_range, J_gdd, tod_range, J_tod
end

"""
    plot_chirp_sensitivity(gdd_range, J_gdd, tod_range, J_tod; save_prefix)

Plot chirp sensitivity curves for GDD and TOD perturbations.

Shows J(GDD) and J(TOD) vs perturbation magnitude, with a dot at the zero-perturbation
point (not an axhline — which would imply a constant 'optimum' value).
If GDD curve is monotonic, warns that regularization may be constraining phase freedom.
"""
function plot_chirp_sensitivity(gdd_range, J_gdd, tod_range, J_tod; save_prefix="chirp_sensitivity")
    PyPlot.matplotlib.ticker.FormatStrFormatter  # ensure FormatStrFormatter is accessible

    fig, (ax1, ax2) = subplots(1, 2, figsize=(10, 4))

    gdd_fs2 = gdd_range .* 1e3  # convert ps² → fs²
    J_gdd_dB = MultiModeNoise.lin_to_dB.(J_gdd)
    J_tod_dB = MultiModeNoise.lin_to_dB.(J_tod)

    # Center index for zero-perturbation point
    center_idx_gdd = div(length(gdd_range) + 1, 2)
    center_idx_tod = div(length(tod_range) + 1, 2)

    # GDD panel
    ax1.plot(gdd_fs2, J_gdd_dB, "b.-", linewidth=1.2, markersize=4)
    # Zero perturbation marker — avoids misleading horizontal 'Optimum' line
    ax1.plot([gdd_fs2[center_idx_gdd]], [J_gdd_dB[center_idx_gdd]],
        "ro", markersize=8, label="Zero perturbation")
    ax1.set_xlabel("GDD perturbation [fs²]")
    ax1.set_ylabel("J [dB]")
    ax1.set_title("Sensitivity to quadratic chirp (GDD)")
    ax1.ticklabel_format(useOffset=false, style="plain")
    ax1.legend()

    # Detect if GDD curve is monotonic (suggests regularization may be constraining phase freedom)
    gdd_monotonic = issorted(J_gdd_dB) || issorted(J_gdd_dB, rev=true)
    if gdd_monotonic
        @warn "GDD sensitivity curve is monotonic — regularization may be constraining phase freedom"
        ax1.set_title("GDD sensitivity (monotonic — regularization may be constraining)")
    end

    # TOD panel with FormatStrFormatter for large-exponent axis labels
    tod_fs3 = tod_range .* 1e6  # convert ps³ → fs³
    fmt = PyPlot.matplotlib.ticker.FormatStrFormatter("%.1e")
    ax2.xaxis.set_major_formatter(fmt)
    ax2.plot(tod_fs3, J_tod_dB, "r.-", linewidth=1.2, markersize=4)
    ax2.plot([tod_fs3[center_idx_tod]], [J_tod_dB[center_idx_tod]],
        "bo", markersize=8, label="Zero perturbation")
    ax2.set_xlabel("TOD perturbation [fs³]")
    ax2.set_ylabel("J [dB]")
    ax2.set_title("Sensitivity to cubic chirp (TOD)")
    # Note: ticklabel_format requires ScalarFormatter, but ax2 uses FormatStrFormatter (line 347)
    # so we skip it here — the FormatStrFormatter already handles display correctly
    ax2.legend()

    fig.tight_layout()
    savefig("$(save_prefix).png", dpi=150)
    @info "Saved chirp sensitivity plot to $(save_prefix).png"
    return fig
end

"""
    build_raman_result_payload(; kwargs...) -> NamedTuple

Assemble the canonical JLD2 payload written by `run_optimization`. This keeps
the output schema in one testable place while preserving the historical key
names consumed by downstream analysis scripts.
"""
function build_raman_result_payload(;
    run_meta,
    run_tag::AbstractString,
    fiber::Dict,
    sim::Dict,
    Nt::Integer,
    time_window_ps::Real,
    J_before::Real,
    J_after::Real,
    delta_J_dB::Real,
    grad_norm::Real,
    converged::Bool,
    iterations::Integer,
    wall_time_s::Real,
    convergence_history,
    phi_opt,
    uω0,
    E_conservation::Real,
    photon_number_drift::Real=E_conservation,
    bc_input_frac::Real,
    bc_output_frac::Real,
    bc_input_ok::Bool,
    bc_output_ok::Bool,
    trust_report,
    trust_report_md::AbstractString,
    band_mask,
)
    return (
        # Run identification
        fiber_name = run_meta.fiber_name,
        run_tag = String(run_tag),
        # Fiber parameters
        L_m = fiber["L"],
        P_cont_W = run_meta.P_cont_W,
        lambda0_nm = run_meta.lambda0_nm,
        fwhm_fs = run_meta.fwhm_fs,
        gamma = fiber["γ"][1],
        betas = haskey(fiber, "betas") ? fiber["betas"] : Float64[],
        # Grid parameters
        Nt = Int(Nt),
        time_window_ps = Float64(time_window_ps),
        # Optimization results
        J_before = Float64(J_before),
        J_after = Float64(J_after),
        delta_J_dB = Float64(delta_J_dB),
        grad_norm = Float64(grad_norm),
        converged = converged,
        iterations = Int(iterations),
        wall_time_s = Float64(wall_time_s),
        convergence_history = convergence_history,
        # Fields for re-propagation
        phi_opt = phi_opt,
        uomega0 = uω0,
        # Diagnostics
        E_conservation = Float64(E_conservation),
        photon_number_drift = Float64(photon_number_drift),
        bc_input_frac = Float64(bc_input_frac),
        bc_output_frac = Float64(bc_output_frac),
        bc_input_ok = bc_input_ok,
        bc_output_ok = bc_output_ok,
        trust_report = trust_report,
        trust_report_md = String(trust_report_md),
        # Simulation context
        band_mask = band_mask,
        sim_Dt = sim["Δt"],
        sim_omega0 = sim["ω0"],
    )
end

"""
    build_raman_manifest_entry(payload, jld2_path) -> Dict{String,Any}

Create the canonical manifest row corresponding to a Raman result payload.
"""
function build_raman_manifest_entry(payload::NamedTuple, jld2_path::AbstractString)
    return Dict{String,Any}(
        "fiber_name" => payload.fiber_name,
        "L_m" => payload.L_m,
        "P_cont_W" => payload.P_cont_W,
        "lambda0_nm" => payload.lambda0_nm,
        "J_before" => payload.J_before,
        "J_before_dB" => MultiModeNoise.lin_to_dB(payload.J_before),
        "J_after" => payload.J_after,
        "J_after_dB" => MultiModeNoise.lin_to_dB(payload.J_after),
        "delta_J_dB" => payload.delta_J_dB,
        "converged" => payload.converged,
        "iterations" => payload.iterations,
        "wall_time_s" => payload.wall_time_s,
        "Nt" => payload.Nt,
        "time_window_ps" => payload.time_window_ps,
        "grad_norm" => payload.grad_norm,
        "E_conservation" => payload.E_conservation,
        "photon_number_drift" => payload.photon_number_drift,
        "bc_ok" => payload.bc_input_ok && payload.bc_output_ok,
        "trust_overall" => payload.trust_report["overall_verdict"],
        "trust_report_md" => payload.trust_report_md,
        "result_file" => String(jld2_path),
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# 9. Run a single optimization for given parameters
# ─────────────────────────────────────────────────────────────────────────────

function run_optimization(; max_iter=20, validate=true, save_prefix="raman_opt", φ0=nothing,
    λ_gdd=:auto, λ_boundary=1.0, fiber_name="Custom", do_plots=true,
    log_cost::Bool=true, objective_kind::Symbol=:raman_band, solver_reltol=1e-8, kwargs...)
    t_start = time()
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(; kwargs...)
    fiber["reltol"] = Float64(solver_reltol)

    # Construct metadata for figure annotations (META-01)
    _λ0 = get(kwargs, :λ0, 1550e-9)
    _P_cont = get(kwargs, :P_cont, 0.05)
    _pulse_fwhm = get(kwargs, :pulse_fwhm, 185e-15)
    _L_fiber = get(kwargs, :L_fiber, 1.0)
    run_meta = (
        fiber_name = fiber_name,
        L_m = _L_fiber,
        P_cont_W = _P_cont,
        lambda0_nm = _λ0 * 1e9,
        fwhm_fs = _pulse_fwhm * 1e15,
    )
    Nt = sim["Nt"]; M = sim["M"]

    # GDD penalty weight: use a light default that prevents the dominant
    # temporal broadening without constraining useful phase structure.
    # λ_gdd = 1e-4 was validated in prior runs (annealing Stage 1).
    if λ_gdd === :auto
        λ_gdd_val = 1e-4
    else
        λ_gdd_val = Float64(λ_gdd)
    end
    objective_spec = raman_cost_surface_spec(
        log_cost=log_cost,
        λ_gdd=λ_gdd_val,
        λ_boundary=λ_boundary,
        objective_kind=objective_kind,
        objective_label="single-mode Raman spectral phase optimization")

    if validate
        @info "Gradient Validation"
        grad_validation = validate_gradient(uω0, fiber, sim, band_mask;
            n_checks=3, objective_kind=objective_kind,
            λ_gdd=λ_gdd_val, λ_boundary=λ_boundary,
            log_cost=log_cost)
    else
        grad_validation = nothing
    end

    @info "Optimization" λ_gdd=λ_gdd_val λ_boundary=λ_boundary
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        max_iter=max_iter, φ0=φ0, objective_kind=objective_kind,
        λ_gdd=λ_gdd_val, λ_boundary=λ_boundary,
        store_trace=true, log_cost=log_cost)

    φ_before = zeros(Nt, M)
    φ_after = reshape(result.minimizer, Nt, M)

    # ── Run summary table ──
    J_before, _ = cost_and_gradient(φ_before, uω0, fiber, sim, band_mask;
        objective_kind=objective_kind, log_cost=false)
    J_after, grad_after = cost_and_gradient(φ_after, uω0, fiber, sim, band_mask;
        objective_kind=objective_kind, log_cost=false)
    ΔJ_dB = MultiModeNoise.lin_to_dB(J_after) - MultiModeNoise.lin_to_dB(J_before)

    # Boundary check on optimized input pulse. Use the raw time-domain field:
    # `check_boundary_conditions` divides by the attenuator for legacy callers,
    # which falsely inflates near-zero edge noise in this trust path.
    uω0_opt = @. uω0 * cis(φ_after)
    ut0_opt = ifft(uω0_opt, 1)
    bc_input_ok, bc_input_frac = check_raw_temporal_edges(ut0_opt;
        threshold=TRUST_THRESHOLDS.edge_frac_pass)

    # Boundary check on output pulse
    fiber_bc = deepcopy(fiber)
    fiber_bc["zsave"] = [fiber["L"]]
    sol_bc = MultiModeNoise.solve_disp_mmf(uω0_opt, fiber_bc, sim)
    bc_output_ok, bc_output_frac = check_raw_temporal_edges(sol_bc["ut_z"][end, :, :];
        threshold=TRUST_THRESHOLDS.edge_frac_pass)

    # Photon-number conservation. For Raman/self-steepening GNLSE, photon
    # number is the physical invariant; raw field energy can drift.
    uωf = sol_bc["uω_z"][end, :, :]
    photon_drift = photon_number_drift(uω0_opt, uωf, sim)

    # Gradient norm (convergence quality)
    grad_norm = norm(grad_after)

    # Peak power
    P_peak_in = maximum(abs2.(ut0_opt))
    P_peak_out = maximum(abs2.(sol_bc["ut_z"][end, :, :]))

    elapsed = time() - t_start
    tw_ps = Nt * sim["Δt"]

    @info @sprintf("""
    ┌─────────────────────────────────────────────────┐
    │  RUN SUMMARY: %s
    ├─────────────────────────────────────────────────┤
    │  Fiber        L = %.1f m, γ = %.2e W⁻¹m⁻¹
    │  Grid         Nt = %d, time_window = %.1f ps
    │  Regulariz.   λ_gdd = %.2e, λ_boundary = %.1f
    │  Objective    %s
    │  Iterations   %d (%.1f s)
    ├─────────────────────────────────────────────────┤
    │  J (before)   %.4e  (%.1f dB)
    │  J (after)    %.4e  (%.1f dB)
    │  ΔJ           %.1f dB
    │  ‖∇J‖         %.2e
    ├─────────────────────────────────────────────────┤
    │  Peak power   in: %.0f W → out: %.0f W
    │  Photon drift %.2e (%.1f%%)
    ├─────────────────────────────────────────────────┤
    │  Boundary (input)   %.2e  %s
    │  Boundary (output)  %.2e  %s
    └─────────────────────────────────────────────────┘""",
        save_prefix,
        fiber["L"], fiber["γ"][1],
        Nt, tw_ps,
        λ_gdd_val, λ_boundary,
        objective_spec.scalar_surface,
        Optim.iterations(result), elapsed,
        J_before, MultiModeNoise.lin_to_dB(J_before),
        J_after, MultiModeNoise.lin_to_dB(J_after),
        ΔJ_dB,
        grad_norm,
        P_peak_in, P_peak_out,
        photon_drift, photon_drift * 100,
        bc_input_frac, bc_input_ok ? "OK" : "⚠ DANGER",
        bc_output_frac, bc_output_ok ? "OK" : "⚠ DANGER")

    if !bc_input_ok || !bc_output_ok
        @warn "Boundary energy is too high — increase time_window or Nt"
    end

    det_status = deterministic_environment_status()
    trust_report = build_numerical_trust_report(
        det_status=det_status,
        edge_input_frac=bc_input_frac,
        edge_output_frac=bc_output_frac,
        energy_drift=photon_drift,
        gradient_validation=grad_validation,
        log_cost=log_cost,
        λ_gdd=λ_gdd_val,
        λ_boundary=λ_boundary,
        objective_spec=objective_spec,
        objective_label="single-mode Raman spectral phase optimization")
    trust_md_path = write_numerical_trust_report("$(save_prefix)_trust.md", trust_report)
    @info "Saved numerical trust report to $trust_md_path"

    # ── Result serialization (XRUN-01) ──
    jld2_path = "$(save_prefix)_result.jld2"
    # Store convergence history in dB. If log_cost=true, f_trace is already dB.
    if log_cost
        convergence_history = collect(Optim.f_trace(result))
    else
        convergence_history = MultiModeNoise.lin_to_dB.(Optim.f_trace(result))
    end
    @info "Saving results to $jld2_path"
    result_payload = build_raman_result_payload(;
        run_meta = run_meta,
        run_tag = (@isdefined(RUN_TAG) ? RUN_TAG : "interactive"),
        fiber = fiber,
        sim = sim,
        Nt = Nt,
        time_window_ps = tw_ps,
        J_before = J_before,
        J_after = J_after,
        delta_J_dB = ΔJ_dB,
        grad_norm = grad_norm,
        converged = Optim.converged(result),
        iterations = Optim.iterations(result),
        wall_time_s = elapsed,
        convergence_history = convergence_history,
        phi_opt = φ_after,
        uω0 = uω0,
        E_conservation = photon_drift,
        photon_number_drift = photon_drift,
        bc_input_frac = bc_input_frac,
        bc_output_frac = bc_output_frac,
        bc_input_ok = bc_input_ok,
        bc_output_ok = bc_output_ok,
        trust_report = trust_report,
        trust_report_md = trust_md_path,
        band_mask = band_mask,
    )
    sidecar_path = MultiModeNoise.save_run(jld2_path, result_payload)
    @info "Saved JSON sidecar to $sidecar_path"

    # ── Manifest update (XRUN-01) ──
    manifest_path = joinpath("results", "raman", "manifest.json")
    manifest_entry = build_raman_manifest_entry(result_payload, jld2_path)
    manifest_count = update_manifest_entry(manifest_path, manifest_entry)
    @info "Updated manifest at $manifest_path ($(manifest_count) runs)"

    if do_plots
        # ── Plots ──
        @info "Plotting"

        # 3×2 optimization comparison (spectra, temporal, group delay)
        plot_optimization_result_v2(φ_before, φ_after, uω0, fiber, sim,
            band_mask, Δf, raman_threshold;
            save_path="$(save_prefix).png", metadata=run_meta)

        # Evolution: solve both via propagate_and_plot_evolution (handles deepcopy + zsave),
        # then merge into a single 2×2 figure (ORG-01, ORG-02)
        @info "Evolution Plots"
        sol_unshaped, fig_tmp1, _ = propagate_and_plot_evolution(uω0, fiber, sim)
        close(fig_tmp1)
        sol_opt_evo, fig_tmp2, _ = propagate_and_plot_evolution(uω0_opt, fiber, sim)
        close(fig_tmp2)

        # Merged 2×2 evolution comparison (replaces two separate _unshaped/_optimized PNGs)
        fiber_evo = deepcopy(fiber)
        fiber_evo["zsave"] = collect(LinRange(0, fiber["L"], 101))
        plot_merged_evolution(sol_opt_evo, sol_unshaped, sim, fiber_evo;
            metadata=run_meta,
            save_path="$(save_prefix)_evolution.png")

        # Phase diagnostic: spectral phase, group delay, GDD, instantaneous frequency
        @info "Phase Diagnostic"
        plot_phase_diagnostic(φ_after, uω0, sim;
            save_path="$(save_prefix)_phase.png", metadata=run_meta)
        close("all")
    end # do_plots

    # Mandatory standard image set (CLAUDE.md project rule, post-2026-04-17).
    save_standard_set(φ_after, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        tag = basename(save_prefix),
        fiber_name = run_meta.fiber_name,
        L_m = run_meta.L_m,
        P_W = run_meta.P_cont_W,
        output_dir = dirname(save_prefix) == "" ? "." : dirname(save_prefix),
        lambda0_nm = run_meta.lambda0_nm,
        fwhm_fs = run_meta.fwhm_fs)

    return result, uω0, fiber, sim, band_mask, Δf
end

# ─────────────────────────────────────────────────────────────────────────────
# 10. Historical comparison-suite runs (only when script is executed directly)
#
# Five configurations spanning moderate to extreme Raman shifting:
#   Run 1: SMF-28 baseline       (L=1m,  P=0.05W, N~2.3)
#   Run 2: SMF-28 high power     (L=2m,  P=0.30W, N~5.6)
#   Run 3: HNLF short fiber      (L=1m,  P=0.05W, N~6.9 from high gamma)
#   Run 4: HNLF moderate fiber   (L=2m,  P=0.05W, strong Raman)
#   Run 5: SMF-28 long fiber     (L=5m,  P=0.15W, cold start)
# Chirp sensitivity analysis on the strongest maintained HNLF run (Run 4).
# ─────────────────────────────────────────────────────────────────────────────

using Interpolations
using Dates

function main()

@info "═══════════════════════════════════════════"
@info "  Raman Phase Optimization — Heavy-Duty Runs"
@info "═══════════════════════════════════════════"

RUN_TAG = Dates.format(now(), "yyyymmdd_HHMMss")
mkpath("results/images")  # ensure summary output directory exists
# ── Output directories ──
# Primary: results/raman/<fiber>/<params>/ (per-run detailed output)
# Summary: results/images/ (flat directory for quick-access plots)
suite_results = Dict{Symbol,Any}()
for spec in canonical_raman_run_specs()
    dir = canonical_run_output_dir(spec.fiber_slug, spec.params_slug)
    @info "\n▶ $(spec.label) → $dir"
    suite_results[spec.id] = run_optimization(;
        spec.kwargs...,
        save_prefix=joinpath(dir, "opt"),
    )

    if spec.id == :smf28_L1m_P005W
        cp(joinpath(dir, "opt.png"), "results/images/raman_opt_L1m_SMF28.png", force=true)
    end
    GC.gc()
end

result4, uω0_4, fiber_4, sim_4, band_mask_4, Δf_4 = suite_results[:hnlf_L2m_P005W]
φ_opt_4 = reshape(result4.minimizer, sim_4["Nt"], sim_4["M"])

# ─── Chirp sensitivity on the strongest maintained HNLF run (Run 4: L=2m) ──
@info "\n▶ Chirp Sensitivity (Run 4: HNLF L=2m)"
gdd_r, J_gdd, tod_r, J_tod = chirp_sensitivity(
    φ_opt_4, uω0_4, fiber_4, sim_4, band_mask_4;
    gdd_range=range(-2e-2, 2e-2, length=101)
)
plot_chirp_sensitivity(gdd_r, J_gdd, tod_r, J_tod;
    save_prefix="results/images/chirp_sens_HNLF_L2m")

# Phase diagnostics are now generated per-run inside run_optimization

@info "═══ All runs complete ═══"
@info "Output directory structure:"
for spec in canonical_raman_run_specs()
    @info "  $(joinpath("results", "raman", spec.fiber_slug, spec.params_slug))/   — $(spec.label)"
end

end # function main

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
