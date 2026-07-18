"""
Shared red-band phase-optimization library used by the maintained workflow
surface. Its masked objective is a numerical regression metric, not causal
evidence of Raman suppression.

This file provides `run_optimization`, cost/gradient helpers, result payload
assembly, and plotting glue for single-mode spectral-phase optimization.

Execution belongs to the experiment runtime under
`scripts/canonical/run_experiment.jl`; this file is library code only.

# Inputs
- Config constants at top of file (fiber preset, L, P, pulse FWHM, max_iter).
- `scripts/lib/common.jl` for `FIBER_PRESETS` and `setup_raman_problem`.
- `FiberLab.ensure_deterministic_environment()` pins FFTW/BLAS threads
  for bit-identity runs.

# Outputs
- `results/raman/<run_id>/_result.jld2` — full JLD2 payload (φ_opt, uω0, uωf,
  convergence history in dB, grid, fiber dict, metadata).
- `results/raman/<run_id>/_result.json` — JSON sidecar with scalar metadata.
- `results/raman/<run_id>/*.png` — three figures (spectral, phase, evolution).

# Runtime
~5 minutes on a 4-core laptop for the canonical SMF-28 config (L=2 m, P=0.2 W,
Nt=2^13, max_iter=30). Scale linearly with `max_iter`; super-linearly with Nt.

# Docs
Docs: docs/guides/supported-workflows.md
"""

try using Revise catch end
using Printf
using LinearAlgebra
using Statistics
using FFTW
using Logging
ENV["MPLBACKEND"] = "Agg"  # Non-interactive backend for headless execution
using FiberLab
using Optim
using JLD2
using JSON3

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "objective_surface.jl"))
include(joinpath(@__DIR__, "regularizers.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "numerical_trust.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Setup and cost functions are in common.jl:
#   setup_raman_problem, spectral_band_cost, recommended_time_window,
#   check_raw_temporal_edges
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
    objective_label::AbstractString=_single_mode_objective_label(objective_kind))

    physics_label = if objective_kind == :raman_peak
        "physics_peak"
    elseif objective_kind == :temporal_width
        "temporal_width"
    else
        "physics"
    end
    return build_objective_surface_spec(;
        objective_label = objective_label,
        log_cost = log_cost,
        linear_terms = [physics_label, "λ_gdd*R_gdd", "λ_boundary*R_boundary"],
        trailing_fields = (
            objective_kind = objective_kind,
            lambda_gdd = Float64(λ_gdd),
            lambda_boundary = Float64(λ_boundary),
            boundary_penalty_measurement = "raw temporal edge fraction of shaped input pulse",
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
    sol = FiberLab.solve_disp_mmf(uω0_shaped, fiber, sim)
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
    elseif objective_kind == :temporal_width
        J, λωL = temporal_width_cost(uωf, sim)
    else
        throw(ArgumentError("unknown single-mode phase objective kind `$(objective_kind)`"))
    end

    # Adjoint solve: propagate λ backward from L to 0
    sol_adj = FiberLab.solve_adjoint_disp_mmf(λωL, ũω, fiber, sim)
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
    log_cost::Bool=true, objective_kind::Symbol=:raman_band,
    solver_f_abstol=:auto, solver_g_abstol=:auto)

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
            state.iteration, state.value, FiberLab.lin_to_dB(state.value))
        return false
    end

    # Optim.jl interface: combined cost + gradient
    # NOTE: Both cost and gradient must be on the same scale for L-BFGS.
    # log_cost=true: cost in dB, gradient scaled by chain rule — keeps ∇J ~ O(1)
    # log_cost=false keeps both cost and gradient on the linear scale.
    default_f_tol = log_cost ? 0.01 : 1e-10  # 0.01 dB vs 1e-10 linear
    f_tol = solver_f_abstol === :auto ? default_f_tol : Float64(solver_f_abstol)
    options = if solver_g_abstol === :auto
        Optim.Options(iterations=max_iter, f_abstol=f_tol, callback=callback, store_trace=store_trace)
    else
        Optim.Options(iterations=max_iter, f_abstol=f_tol, g_abstol=Float64(solver_g_abstol),
            callback=callback, store_trace=store_trace)
    end
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
        options
    )

    return result
end

function _single_mode_objective_label(objective_kind::Symbol)
    if objective_kind == :temporal_width
        return "single-mode temporal pulse-width phase optimization"
    elseif objective_kind == :raman_peak
        return "single-mode Raman peak-bin spectral phase optimization"
    end
    return "single-mode Raman spectral phase optimization"
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
    build_raman_result_payload(; kwargs...) -> NamedTuple

Assemble the canonical JLD2 payload written by `run_optimization`. This keeps
the output schema in one testable place while preserving the stable key
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
    physical_grad_norm::Real=grad_norm,
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
    raman_response,
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
        physical_grad_norm = Float64(physical_grad_norm),
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
        raman_response = raman_response,
        # Simulation context
        band_mask = band_mask,
        sim_Dt = sim["Δt"],
        sim_omega0 = sim["ω0"],
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# 9. Run a single optimization for given parameters
# ─────────────────────────────────────────────────────────────────────────────

function run_optimization(; max_iter=20, validate=true, save_prefix="raman_opt", φ0=nothing,
    λ_gdd=:auto, λ_boundary=1.0, fiber_name="Custom", do_plots=true,
    log_cost::Bool=true, objective_kind::Symbol=:raman_band, store_trace::Bool=true,
    solver_reltol=1e-8,
    solver_f_abstol=:auto, solver_g_abstol=:auto, problem_setup=setup_raman_problem, kwargs...)
    t_start = time()
    uω0, fiber, sim, band_mask, Δf, raman_threshold = problem_setup(; kwargs...)
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

    λ_gdd_val = resolve_regularizer_lambda(:gdd, λ_gdd)
    objective_spec = raman_cost_surface_spec(
        log_cost=log_cost,
        λ_gdd=λ_gdd_val,
        λ_boundary=λ_boundary,
        objective_kind=objective_kind,
        objective_label=_single_mode_objective_label(objective_kind))

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
        store_trace=store_trace, log_cost=log_cost,
        solver_f_abstol=solver_f_abstol, solver_g_abstol=solver_g_abstol)

    φ_before = zeros(Nt, M)
    φ_after = reshape(result.minimizer, Nt, M)

    # ── Run summary table ──
    J_before, _ = cost_and_gradient(φ_before, uω0, fiber, sim, band_mask;
        objective_kind=objective_kind, log_cost=false)
    J_after, physical_grad_after = cost_and_gradient(φ_after, uω0, fiber, sim, band_mask;
        objective_kind=objective_kind, log_cost=false)
    _, optimization_grad_after = cost_and_gradient(φ_after, uω0, fiber, sim, band_mask;
        objective_kind=objective_kind, λ_gdd=λ_gdd_val, λ_boundary=λ_boundary,
        log_cost=log_cost)
    ΔJ_dB = FiberLab.lin_to_dB(J_after) - FiberLab.lin_to_dB(J_before)

    # Boundary check on the optimized input pulse in the periodic FFT window.
    uω0_opt = @. uω0 * cis(φ_after)
    ut0_opt = fft(uω0_opt, 1)
    bc_input_ok, bc_input_frac = check_raw_temporal_edges(ut0_opt;
        threshold=TRUST_THRESHOLDS.edge_frac_pass)

    # Boundary check on output pulse
    fiber_bc = deepcopy(fiber)
    fiber_bc["zsave"] = [fiber["L"]]
    sol_bc = FiberLab.solve_disp_mmf(uω0_opt, fiber_bc, sim)
    bc_output_ok, bc_output_frac = check_raw_temporal_edges(sol_bc["ut_z"][end, :, :];
        threshold=TRUST_THRESHOLDS.edge_frac_pass)

    # Photon-number conservation. For Raman/self-steepening GNLSE, photon
    # number is the physical invariant; raw field energy can drift.
    uωf = sol_bc["uω_z"][end, :, :]
    photon_drift = photon_number_drift(uω0_opt, uωf, sim)

    # Gradient norm (convergence quality)
    grad_norm = norm(optimization_grad_after)
    physical_grad_norm = norm(physical_grad_after)

    # Peak power
    P_peak_in = maximum(abs2.(ut0_opt))
    P_peak_out = maximum(abs2.(sol_bc["ut_z"][end, :, :]))

    elapsed = time() - t_start
    tw_ps = Nt * sim["Δt"]

    @info @sprintf("""
    ┌─────────────────────────────────────────────────┐
    │  RUN SUMMARY: %s
    ├─────────────────────────────────────────────────┤
    │  Fiber        L = %s, γ = %.2e W⁻¹m⁻¹
    │  Grid         Nt = %d, time_window = %.1f ps
    │  Regulariz.   λ_gdd = %.2e, λ_boundary = %.1f
    │  Objective    %s
    │  Iterations   %d (%.1f s)
    ├─────────────────────────────────────────────────┤
    │  J (before)   %.4e  (%.1f dB)
    │  J (after)    %.4e  (%.1f dB)
    │  ΔJ           %s
    │  ‖∇J‖         %.2e
    ├─────────────────────────────────────────────────┤
    │  Peak power   in: %s → out: %s
    │  Photon drift %.2e (%.1f%%)
    ├─────────────────────────────────────────────────┤
    │  Boundary (input)   %.2e  %s
    │  Boundary (output)  %.2e  %s
    └─────────────────────────────────────────────────┘""",
        save_prefix,
        FiberLab._format_length_m(fiber["L"]), fiber["γ"][1],
        Nt, tw_ps,
        λ_gdd_val, λ_boundary,
        objective_spec.scalar_surface,
        Optim.iterations(result), elapsed,
        J_before, FiberLab.lin_to_dB(J_before),
        J_after, FiberLab.lin_to_dB(J_after),
        FiberLab._format_delta_db(ΔJ_dB),
        grad_norm,
        _format_power_watts(P_peak_in), _format_power_watts(P_peak_out),
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
        gradient_required=validate,
        log_cost=log_cost,
        λ_gdd=λ_gdd_val,
        λ_boundary=λ_boundary,
        objective_spec=objective_spec,
        objective_label=_single_mode_objective_label(objective_kind))
    trust_md_path = write_numerical_trust_report("$(save_prefix)_trust.md", trust_report)
    @info "Saved numerical trust report to $trust_md_path"

    # ── Result serialization (XRUN-01) ──
    jld2_path = "$(save_prefix)_result.jld2"
    # Store convergence history in dB. If log_cost=true, f_trace is already dB.
    if log_cost
        convergence_history = collect(Optim.f_trace(result))
    else
        convergence_history = FiberLab.lin_to_dB.(Optim.f_trace(result))
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
        physical_grad_norm = physical_grad_norm,
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
        raman_response = raman_response_identity(
            get(kwargs, :raman_fraction, nothing), fiber),
    )
    sidecar_path = FiberLab.save_run(jld2_path, result_payload)
    @info "Saved JSON sidecar to $sidecar_path"

    if do_plots
        # ── Plots ──
        @info "Plotting"

        # 3×2 optimization comparison (spectra, temporal, group delay)
        plot_optimization_result_v2(φ_before, φ_after, uω0, fiber, sim,
            band_mask, Δf, raman_threshold;
            save_path="$(save_prefix).png", metadata=run_meta,
            objective_kind=objective_kind,
            objective_values=(J_before, J_after),
            objective_label=_single_mode_objective_label(objective_kind))

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
            save_path="$(save_prefix)_phase.png", metadata=run_meta,
            objective_kind=objective_kind,
            raman_threshold_thz=raman_threshold)
        close("all")
    end # do_plots

    # Mandatory standard image set (AGENTS.md project rule).
    save_standard_set(φ_after, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        tag = basename(save_prefix),
        fiber_name = run_meta.fiber_name,
        L_m = run_meta.L_m,
        P_W = run_meta.P_cont_W,
        output_dir = dirname(save_prefix) == "" ? "." : dirname(save_prefix),
        lambda0_nm = run_meta.lambda0_nm,
        fwhm_fs = run_meta.fwhm_fs,
        objective_kind = objective_kind,
        objective_values = (J_before, J_after),
        objective_label = _single_mode_objective_label(objective_kind))

    return result, uω0, fiber, sim, band_mask, Δf
end
