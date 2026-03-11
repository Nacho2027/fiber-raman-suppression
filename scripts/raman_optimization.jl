"""
Raman Suppression via Spectral Phase Optimization (SMF version)

Optimizes the spectral phase of an input pulse to minimize the fractional energy
in a Raman-shifted wavelength band after propagation through a single-mode fiber.

Uses user-defined fiber parameters (γ, β₂, β₃, ...) via
`get_disp_fiber_params_user_defined` — no pre-computed NPZ eigenmode files needed.

Uses the adjoint method (already in MultiModeNoise) to compute gradients efficiently.
"""

try using Revise catch end
using Printf
using LinearAlgebra
using FFTW
using Logging
ENV["MPLBACKEND"] = "Agg"  # Non-interactive backend for headless execution
using PyPlot
using MultiModeNoise
using Optim

include("common.jl")
include("visualization.jl")

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
function cost_and_gradient(φ, uω0, fiber, sim, band_mask;
    uω0_shaped::Union{Nothing,AbstractMatrix}=nothing,
    uωf_buffer::Union{Nothing,AbstractMatrix}=nothing)

    # PRECONDITIONS
    @assert size(φ) == size(uω0) "φ shape $(size(φ)) ≠ uω0 shape $(size(uω0))"
    @assert all(isfinite, φ) "phase contains NaN/Inf"

    # Apply spectral phase: cis(x) = cos(x) + i·sin(x), avoids exp() overhead
    if isnothing(uω0_shaped)
        uω0_shaped = @. uω0 * cis(φ)
    else
        @. uω0_shaped = uω0 * cis(φ)
    end

    # Forward solve (deepcopy avoids zsave mutation across calls)
    fiber_local = deepcopy(fiber)
    fiber_local["zsave"] = nothing
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_local, sim)
    ũω = sol["ode_sol"]

    # Get output field in lab frame using cis() for the dispersion phase
    L = fiber_local["L"]
    Dω = fiber_local["Dω"]
    ũω_L = ũω(L)
    if isnothing(uωf_buffer)
        uωf = @. cis(Dω * L) * ũω_L
    else
        @. uωf_buffer = cis(Dω * L) * ũω_L
        uωf = uωf_buffer
    end

    # Cost and adjoint terminal condition
    J, λωL = spectral_band_cost(uωf, band_mask)

    # Adjoint solve: propagate λ backward from L to 0
    sol_adj = MultiModeNoise.solve_adjoint_disp_mmf(λωL, ũω, fiber_local, sim)
    λ0 = sol_adj(0)

    # Chain rule: ∂J/∂φ(ω) = 2 · Re(λ₀*(ω) · i · u₀(ω))
    # Because δu₀ = i·u₀·δφ, and the adjoint gives δJ = 2·Re(λ₀* · δu₀)
    ∂J_∂φ = 2.0 .* real.(conj.(λ0) .* (1im .* uω0_shaped))

    # POSTCONDITIONS
    @assert isfinite(J) "cost is not finite: $J"
    @assert all(isfinite, ∂J_∂φ) "gradient contains NaN/Inf"

    return J, ∂J_∂φ
end

# ─────────────────────────────────────────────────────────────────────────────
# 6. Optimization with L-BFGS
# ─────────────────────────────────────────────────────────────────────────────

function optimize_spectral_phase(uω0_base, fiber, sim, band_mask;
    φ0=nothing, max_iter=50)

    # PRECONDITIONS
    @assert max_iter > 0 "max_iter must be positive"
    @assert haskey(sim, "Nt") && haskey(sim, "M") "sim dict missing Nt or M"

    Nt = sim["Nt"]
    M = sim["M"]

    # Initial phase: zero (unshaped pulse) or user-provided
    if isnothing(φ0)
        φ0 = zeros(Nt, M)
    end

    # Pre-allocate buffers reused every iteration (avoids GC pressure)
    uω0_shaped = similar(uω0_base)
    uωf_buffer = similar(uω0_base)

    # Callback for monitoring
    function callback(state)
        @debug @sprintf("Iter %3d: J = %.6f (%.2f dB)",
            state.iteration, 10^(state.value / 10), state.value)
        return false
    end

    # Optim.jl interface: combined cost + gradient
    result = optimize(
        Optim.only_fg!() do F, G, φ_vec
            φ = reshape(φ_vec, Nt, M)
            J, ∂J_∂φ = cost_and_gradient(φ, uω0_base, fiber, sim, band_mask;
                uω0_shaped=uω0_shaped, uωf_buffer=uωf_buffer)
            if G !== nothing
                G .= vec(∂J_∂φ)
            end
            if F !== nothing
                return MultiModeNoise.lin_to_dB(J)
            end
        end,
        vec(φ0),
        LBFGS(),
        Optim.Options(iterations=max_iter, f_abstol=1e-6, callback=callback)
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
function validate_gradient(uω0_base, fiber, sim, band_mask; n_checks=5, ε=1e-5)
    Nt = sim["Nt"]
    M = sim["M"]
    φ_test = 0.1 * randn(Nt, M)

    J0, grad = cost_and_gradient(φ_test, uω0_base, fiber, sim, band_mask)

    # Pick indices where the pulse has significant amplitude (near center of spectrum)
    # The pulse energy is concentrated in the middle of the FFT grid
    spectral_power = vec(sum(abs2.(uω0_base), dims=2))
    significant = findall(spectral_power .> 0.01 * maximum(spectral_power))
    indices = significant[rand(1:length(significant), min(n_checks, length(significant)))]
    @info "Gradient validation (ε = $ε)"
    lines = [@sprintf("  %5s  %12s  %12s  %10s", "index", "adjoint", "fin. diff.", "rel. error")]

    for idx in indices
        φ_plus = copy(φ_test)
        φ_plus[idx, 1] += ε
        J_plus, _ = cost_and_gradient(φ_plus, uω0_base, fiber, sim, band_mask)

        φ_minus = copy(φ_test)
        φ_minus[idx, 1] -= ε
        J_minus, _ = cost_and_gradient(φ_minus, uω0_base, fiber, sim, band_mask)

        fd_grad = (J_plus - J_minus) / (2ε)
        adj_grad = grad[idx, 1]
        rel_err = abs(adj_grad - fd_grad) / max(abs(adj_grad), abs(fd_grad), 1e-15)

        push!(lines, @sprintf("  %5d  %12.6e  %12.6e  %10.2e", idx, adj_grad, fd_grad, rel_err))
    end
    @debug join(lines, "\n")
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
        J_gdd[i], _ = cost_and_gradient(φ_perturbed, uω0, fiber, sim, band_mask)
    end

    # TOD sweep: φ_chirp(ω) = ⅙ · TOD · ω³
    ω3 = ω_fft .^ 3
    J_tod = zeros(length(tod_range))
    for (i, tod) in enumerate(tod_range)
        φ_perturbed = φ_opt .+ (tod / 6.0) .* ω3 .* ones(1, M)
        J_tod[i], _ = cost_and_gradient(φ_perturbed, uω0, fiber, sim, band_mask)
    end

    return gdd_range, J_gdd, tod_range, J_tod
end

"""Plot chirp sensitivity curves."""
function plot_chirp_sensitivity(gdd_range, J_gdd, tod_range, J_tod; save_prefix="chirp_sensitivity")
    fig, (ax1, ax2) = subplots(1, 2, figsize=(10, 4))

    ax1.plot(gdd_range .* 1e3, MultiModeNoise.lin_to_dB.(J_gdd), "b.-")
    ax1.set_xlabel("GDD perturbation [fs²]")
    ax1.set_ylabel("J [dB]")
    ax1.set_title("Sensitivity to quadratic chirp (GDD)")
    ax1.axhline(y=MultiModeNoise.lin_to_dB(J_gdd[div(length(J_gdd)+1, 2)]), color="r", ls="--", alpha=0.5, label="Optimum")
    ax1.legend()

    ax2.plot(tod_range .* 1e6, MultiModeNoise.lin_to_dB.(J_tod), "r.-")
    ax2.set_xlabel("TOD perturbation [fs³]")
    ax2.set_ylabel("J [dB]")
    ax2.set_title("Sensitivity to cubic chirp (TOD)")
    ax2.axhline(y=MultiModeNoise.lin_to_dB(J_tod[div(length(J_tod)+1, 2)]), color="b", ls="--", alpha=0.5, label="Optimum")
    ax2.legend()

    fig.tight_layout()
    savefig("$(save_prefix).png", dpi=150)
    @info "Saved chirp sensitivity plot to $(save_prefix).png"
    return fig
end

# ─────────────────────────────────────────────────────────────────────────────
# 9. Run a single optimization for given parameters
# ─────────────────────────────────────────────────────────────────────────────

function run_optimization(; max_iter=20, validate=true, save_prefix="raman_opt", φ0=nothing, kwargs...)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(; kwargs...)
    Nt = sim["Nt"]; M = sim["M"]

    if validate
        @info "Gradient Validation"
        validate_gradient(uω0, fiber, sim, band_mask; n_checks=3)
    end

    @info "Optimization"
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask; max_iter=max_iter, φ0=φ0)
    @debug "$(result)"

    @info "Plotting"
    φ_before = zeros(Nt, M)
    φ_after = reshape(result.minimizer, Nt, M)

    # Optimization comparison (3×2 panel)
    plot_optimization_result_v2(φ_before, φ_after, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        save_path="$(save_prefix).png")

    # Evolution plot: re-run with fine z-sampling
    @info "Evolution Plot"
    uω0_opt = @. uω0 * cis(φ_after)
    propagate_and_plot_evolution(uω0_opt, fiber, sim;
        title="Optimized pulse evolution (L=$(fiber["L"])m)",
        save_path="$(save_prefix)_evolution.png")

    # Boundary diagnostic
    fiber_bc = deepcopy(fiber)
    fiber_bc["zsave"] = [fiber["L"]]
    sol_bc = MultiModeNoise.solve_disp_mmf(uω0_opt, fiber_bc, sim)
    plot_boundary_diagnostic(sol_bc, sim, fiber_bc)
    savefig("$(save_prefix)_boundary.png", dpi=300)
    @info "Saved boundary diagnostic to $(save_prefix)_boundary.png"

    return result, uω0, fiber, sim, band_mask, Δf
end

# ─────────────────────────────────────────────────────────────────────────────
# 10. Example runs (only when script is executed directly)
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__

# Run 1: Baseline (L=1m, P=0.25W)
result1, uω0_1, fiber_1, sim_1, band_mask_1, Δf_1 = run_optimization(
    L_fiber=1.0, P_cont=0.25, max_iter=10,
    gamma_user=0.0013, betas_user=[-2.6e-26],
    save_prefix="raman_opt_L1m_P025W"
)

# Run 2: Moderate regime (L=2m, P=0.5W)
result2, uω0_2, fiber_2, sim_2, band_mask_2, Δf_2 = run_optimization(
    L_fiber=2.0, P_cont=0.5, max_iter=15, validate=false,
    gamma_user=0.0013, betas_user=[-2.6e-26],
    save_prefix="raman_opt_L2m_P05W"
)

# Run 3: Stronger nonlinearity (L=5m, P=1W), warm-started from Run 2 solution
Nt_2 = sim_2["Nt"]; M_2 = sim_2["M"]
φ_warm = reshape(result2.minimizer, Nt_2, M_2)
result3, uω0_3, fiber_3, sim_3, band_mask_3, Δf_3 = run_optimization(
    L_fiber=5.0, P_cont=1.0, max_iter=15, validate=false,
    gamma_user=0.0013, betas_user=[-2.6e-26],
    save_prefix="raman_opt_L5m_P1W", φ0=φ_warm
)

# Chirp sensitivity (uncomment after implementing TODO(human) in chirp_sensitivity)
# println("\n=== Chirp Sensitivity (L=1m, P=0.25W) ===\n")
# Nt_1 = sim_1["Nt"]; M_1 = sim_1["M"]
# φ_opt_1 = reshape(result1.minimizer, Nt_1, M_1)
# gdd_r, J_gdd, tod_r, J_tod = chirp_sensitivity(
#     φ_opt_1, uω0_1, fiber_1, sim_1, band_mask_1
# )
# plot_chirp_sensitivity(gdd_r, J_gdd, tod_r, J_tod; save_prefix="chirp_sens_L1m_P025W")

end # if main script
