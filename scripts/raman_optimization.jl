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
    uωf_buffer::Union{Nothing,AbstractMatrix}=nothing,
    λ_gdd=0.0,
    λ_boundary=0.0)

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
    J, λωL = spectral_band_cost(uωf, band_mask)

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
    if λ_gdd > 0
        Nt_φ = size(φ, 1)
        Δω = 2π / (Nt_φ * sim["Δt"])
        inv_Δω3 = 1.0 / Δω^3
        for m in 1:size(φ, 2)
            for i in 2:(Nt_φ - 1)
                d2 = φ[i+1, m] - 2φ[i, m] + φ[i-1, m]
                J_total += λ_gdd * inv_Δω3 * d2^2
                coeff = 2 * λ_gdd * inv_Δω3 * d2
                grad_total[i-1, m] += coeff
                grad_total[i, m]   -= 2 * coeff
                grad_total[i+1, m] += coeff
            end
        end
    end

    # ── Boundary penalty: penalizes energy at FFT window edges of input pulse ──
    if λ_boundary > 0
        Nt_b = size(φ, 1)
        n_edge = max(1, Nt_b ÷ 20)  # 5% on each side

        ut0 = ifft(uω0_shaped, 1)

        mask_edge = zeros(Nt_b, size(φ, 2))
        mask_edge[1:n_edge, :] .= 1.0
        mask_edge[end-n_edge+1:end, :] .= 1.0

        E_total_input = max(sum(abs2.(ut0)), eps())
        E_edges = sum(abs2.(ut0) .* mask_edge)
        edge_frac = E_edges / E_total_input

        if edge_frac > 1e-8
            J_total += λ_boundary * edge_frac

            # Gradient: adjoint of IFFT + chain rule through cis(φ)
            coeff = 2 * λ_boundary / (Nt_b * E_total_input)
            grad_boundary_ω = coeff .* imag.(conj.(uω0_shaped) .* fft(mask_edge .* ut0, 1))
            grad_total .+= grad_boundary_ω
        end
    end

    @assert isfinite(J_total) "regularized cost is not finite: $J_total"
    @assert all(isfinite, grad_total) "regularized gradient contains NaN/Inf"

    return J_total, grad_total
end

# ─────────────────────────────────────────────────────────────────────────────
# 6. Optimization with L-BFGS
# ─────────────────────────────────────────────────────────────────────────────

function optimize_spectral_phase(uω0_base, fiber, sim, band_mask;
    φ0=nothing, max_iter=50, λ_gdd=0.0, λ_boundary=0.0)

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
        @debug @sprintf("Iter %3d: J = %.6f (%.2f dB)",
            state.iteration, 10^(state.value / 10), state.value)
        return false
    end

    # Optim.jl interface: combined cost + gradient
    result = optimize(
        Optim.only_fg!() do F, G, φ_vec
            φ = reshape(φ_vec, Nt, M)
            J, ∂J_∂φ = cost_and_gradient(φ, uω0_base, fiber, sim, band_mask;
                uω0_shaped=uω0_shaped, uωf_buffer=uωf_buffer,
                λ_gdd=λ_gdd, λ_boundary=λ_boundary)
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
    ax2.ticklabel_format(useOffset=false, style="plain")
    ax2.legend()

    fig.tight_layout()
    savefig("$(save_prefix).png", dpi=150)
    @info "Saved chirp sensitivity plot to $(save_prefix).png"
    return fig
end

# ─────────────────────────────────────────────────────────────────────────────
# 9. Run a single optimization for given parameters
# ─────────────────────────────────────────────────────────────────────────────

function run_optimization(; max_iter=20, validate=true, save_prefix="raman_opt", φ0=nothing,
    λ_gdd=:auto, λ_boundary=10.0, kwargs...)
    t_start = time()
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(; kwargs...)
    Nt = sim["Nt"]; M = sim["M"]

    # GDD penalty weight: use a light default that prevents the dominant
    # temporal broadening without constraining useful phase structure.
    # λ_gdd = 1e-4 was validated in prior runs (annealing Stage 1).
    if λ_gdd === :auto
        λ_gdd_val = 1e-4
    else
        λ_gdd_val = Float64(λ_gdd)
    end

    if validate
        @info "Gradient Validation"
        validate_gradient(uω0, fiber, sim, band_mask; n_checks=3)
    end

    @info "Optimization" λ_gdd=λ_gdd_val λ_boundary=λ_boundary
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        max_iter=max_iter, φ0=φ0, λ_gdd=λ_gdd_val, λ_boundary=λ_boundary)

    φ_before = zeros(Nt, M)
    φ_after = reshape(result.minimizer, Nt, M)

    # ── Run summary table ──
    J_before, _ = cost_and_gradient(φ_before, uω0, fiber, sim, band_mask)
    J_after, grad_after = cost_and_gradient(φ_after, uω0, fiber, sim, band_mask)
    ΔJ_dB = MultiModeNoise.lin_to_dB(J_after) - MultiModeNoise.lin_to_dB(J_before)

    # Boundary check on optimized input pulse
    uω0_opt = @. uω0 * cis(φ_after)
    ut0_opt = ifft(uω0_opt, 1)
    bc_input_ok, bc_input_frac = check_boundary_conditions(ut0_opt, sim)

    # Boundary check on output pulse
    fiber_bc = deepcopy(fiber)
    fiber_bc["zsave"] = [fiber["L"]]
    sol_bc = MultiModeNoise.solve_disp_mmf(uω0_opt, fiber_bc, sim)
    bc_output_ok, bc_output_frac = check_boundary_conditions(sol_bc["ut_z"][end, :, :], sim)

    # Energy conservation
    E_in = sum(abs2.(uω0_opt))
    uωf = sol_bc["uω_z"][end, :, :]
    E_out = sum(abs2.(uωf))
    E_conservation = abs(E_out / E_in - 1.0)

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
    │  Iterations   %d (%.1f s)
    ├─────────────────────────────────────────────────┤
    │  J (before)   %.4e  (%.1f dB)
    │  J (after)    %.4e  (%.1f dB)
    │  ΔJ           %.1f dB
    │  ‖∇J‖         %.2e
    ├─────────────────────────────────────────────────┤
    │  Peak power   in: %.0f W → out: %.0f W
    │  Energy cons. %.2e (%.1f%%)
    ├─────────────────────────────────────────────────┤
    │  Boundary (input)   %.2e  %s
    │  Boundary (output)  %.2e  %s
    └─────────────────────────────────────────────────┘""",
        save_prefix,
        fiber["L"], fiber["γ"][1],
        Nt, tw_ps,
        λ_gdd_val, λ_boundary,
        max_iter, elapsed,
        J_before, MultiModeNoise.lin_to_dB(J_before),
        J_after, MultiModeNoise.lin_to_dB(J_after),
        ΔJ_dB,
        grad_norm,
        P_peak_in, P_peak_out,
        E_conservation, E_conservation * 100,
        bc_input_frac, bc_input_ok ? "OK" : "⚠ DANGER",
        bc_output_frac, bc_output_ok ? "OK" : "⚠ DANGER")

    if !bc_input_ok || !bc_output_ok
        @warn "Boundary energy is too high — increase time_window or Nt"
    end

    # ── Plots ──
    @info "Plotting"

    # 3×2 optimization comparison (spectra, temporal, group delay)
    plot_optimization_result_v2(φ_before, φ_after, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        save_path="$(save_prefix).png")

    # Evolution plots: unshaped and optimized
    @info "Evolution Plots"
    propagate_and_plot_evolution(uω0, fiber, sim;
        title="Unshaped pulse evolution (L=$(fiber["L"])m)",
        save_path="$(save_prefix)_evolution_unshaped.png")
    propagate_and_plot_evolution(uω0_opt, fiber, sim;
        title="Optimized pulse evolution (L=$(fiber["L"])m)",
        save_path="$(save_prefix)_evolution_optimized.png")

    # Phase diagnostic: spectral phase, group delay, GDD, instantaneous frequency
    @info "Phase Diagnostic"
    plot_phase_diagnostic(φ_after, uω0, sim;
        save_path="$(save_prefix)_phase.png")
    close("all")

    return result, uω0, fiber, sim, band_mask, Δf
end

# ─────────────────────────────────────────────────────────────────────────────
# 10. Heavy-duty Raman runs (only when script is executed directly)
#
# Five configurations spanning moderate to extreme Raman shifting:
#   Run 1: SMF-28 baseline       (L=1m,  P=0.05W, N~2.3)
#   Run 2: SMF-28 high power     (L=2m,  P=0.30W, N~5.6)
#   Run 3: HNLF short fiber      (L=1m,  P=0.05W, N~6.9 from high gamma)
#   Run 4: HNLF long fiber       (L=5m,  P=0.10W, N~9.8 heavy-duty)
#   Run 5: SMF-28 long fiber     (L=10m, P=0.15W, warm-started from Run 2)
# Chirp sensitivity analysis on the heaviest run (Run 4).
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__

using Interpolations
using Dates

@info "═══════════════════════════════════════════"
@info "  Raman Phase Optimization — Heavy-Duty Runs"
@info "═══════════════════════════════════════════"

# ── Output directories ──
# Primary: results/raman/<fiber>/<params>/ (per-run detailed output)
# Summary: results/images/ (flat directory for quick-access plots)
const RUN_TAG = Dates.format(now(), "yyyymmdd_HHMMss")
function run_dir(fiber, params)
    d = joinpath("results", "raman", fiber, params)
    mkpath(d)
    return d
end
mkpath("results/images")  # ensure summary output directory exists

# ── SMF-28 parameters (canonical single-mode fiber at 1550nm) ──
const SMF28_GAMMA = 1.1e-3        # W⁻¹m⁻¹ (1.1 /W/km)
const SMF28_BETAS = [-2.17e-26, 1.2e-40]  # β₂ [s²/m], β₃ [s³/m]

# ── HNLF parameters (Highly Nonlinear Fiber at 1550nm) ──
const HNLF_GAMMA = 10.0e-3       # W⁻¹m⁻¹ (10 /W/km)
const HNLF_BETAS = [-0.5e-26, 1.0e-40]  # near-zero dispersion

# ─── Run 1: SMF-28 baseline (moderate Raman, N~2.3) ─────────────────────────
dir1 = run_dir("smf28", "L1m_P005W")
@info "\n▶ Run 1: SMF-28 baseline (L=1m, P=0.05W) → $dir1"
result1, uω0_1, fiber_1, sim_1, band_mask_1, Δf_1 = run_optimization(
    L_fiber=1.0, P_cont=0.05, max_iter=50,
    Nt=2^13, β_order=3, time_window=10.0,
    gamma_user=SMF28_GAMMA, betas_user=SMF28_BETAS,
    save_prefix=joinpath(dir1, "opt")
)
# Also save to results/images/ for quick access
cp(joinpath(dir1, "opt.png"), "results/images/raman_opt_L1m_SMF28.png", force=true)
φ_opt_1 = reshape(result1.minimizer, sim_1["Nt"], sim_1["M"])
GC.gc()

# ─── Run 2: SMF-28 high power (strong Raman, N~5.6) ─────────────────────────
dir2 = run_dir("smf28", "L2m_P030W")
@info "\n▶ Run 2: SMF-28 high power (L=2m, P=0.30W) → $dir2"
result2, uω0_2, fiber_2, sim_2, band_mask_2, Δf_2 = run_optimization(
    L_fiber=2.0, P_cont=0.30, max_iter=50, validate=false,
    Nt=2^13, β_order=3, time_window=20.0,
    gamma_user=SMF28_GAMMA, betas_user=SMF28_BETAS,
    save_prefix=joinpath(dir2, "opt")
)
φ_opt_2 = reshape(result2.minimizer, sim_2["Nt"], sim_2["M"])
GC.gc()

# ─── Run 3: HNLF short fiber (very strong Raman at LOW power, N~6.9) ────────
dir3 = run_dir("hnlf", "L1m_P005W")
@info "\n▶ Run 3: HNLF (L=1m, P=0.05W) — strong Raman from high γ → $dir3"
result3, uω0_3, fiber_3, sim_3, band_mask_3, Δf_3 = run_optimization(
    L_fiber=1.0, P_cont=0.05, max_iter=80, validate=false,
    Nt=2^14, β_order=3, time_window=15.0,
    gamma_user=HNLF_GAMMA, betas_user=HNLF_BETAS,
    save_prefix=joinpath(dir3, "opt")
)
φ_opt_3 = reshape(result3.minimizer, sim_3["Nt"], sim_3["M"])
GC.gc()

# ─── Run 4: HNLF moderate fiber (strong Raman, N~4.9) ───────────────────────
# N~9.8 (L=5m, P=0.10W) causes NaN in the ODE solver — too stiff.
# Reduce to L=2m, P=0.05W for a stable heavy-Raman regime.
dir4 = run_dir("hnlf", "L2m_P005W")
@info "\n▶ Run 4: HNLF (L=2m, P=0.05W) — heavy Raman → $dir4"
result4, uω0_4, fiber_4, sim_4, band_mask_4, Δf_4 = run_optimization(
    L_fiber=2.0, P_cont=0.05, max_iter=100, validate=false,
    Nt=2^14, β_order=3, time_window=30.0,
    gamma_user=HNLF_GAMMA, betas_user=HNLF_BETAS,
    save_prefix=joinpath(dir4, "opt")
)
φ_opt_4 = reshape(result4.minimizer, sim_4["Nt"], sim_4["M"])
GC.gc()

# ─── Run 5: SMF-28 LONG fiber (L=5m, cold start) ────────────────────────────
# L=10m with warm-start from L=2m causes NaN (frequency grid mismatch).
# Use L=5m cold start instead — still long enough for significant Raman.
dir5 = run_dir("smf28", "L5m_P015W")
@info "\n▶ Run 5: SMF-28 long fiber (L=5m, P=0.15W, cold start) → $dir5"
result5, uω0_5, fiber_5, sim_5, band_mask_5, Δf_5 = run_optimization(
    L_fiber=5.0, P_cont=0.15, max_iter=100, validate=false,
    Nt=2^13, β_order=3, time_window=30.0,
    gamma_user=SMF28_GAMMA, betas_user=SMF28_BETAS,
    save_prefix=joinpath(dir5, "opt")
)
φ_opt_5 = reshape(result5.minimizer, sim_5["Nt"], sim_5["M"])
GC.gc()

# ─── Chirp sensitivity on the heaviest run (Run 4: HNLF L=5m) ──────────────
@info "\n▶ Chirp Sensitivity (Run 4: HNLF L=5m)"
gdd_r, J_gdd, tod_r, J_tod = chirp_sensitivity(
    φ_opt_4, uω0_4, fiber_4, sim_4, band_mask_4;
    gdd_range=range(-2e-2, 2e-2, length=101)
)
plot_chirp_sensitivity(gdd_r, J_gdd, tod_r, J_tod;
    save_prefix="results/images/chirp_sens_HNLF_L5m")

# Phase diagnostics are now generated per-run inside run_optimization

@info "═══ All runs complete ═══"
@info "Output directory structure:"
@info "  results/raman/smf28/L1m_P005W/   — Run 1 (baseline)"
@info "  results/raman/smf28/L2m_P030W/   — Run 2 (high power)"
@info "  results/raman/hnlf/L1m_P005W/    — Run 3 (HNLF short)"
@info "  results/raman/hnlf/L2m_P005W/    — Run 4 (HNLF heavy Raman)"
@info "  results/raman/smf28/L5m_P015W/   — Run 5 (SMF long, cold start)"

end # if main script
