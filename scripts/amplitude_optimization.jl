"""
Raman Suppression via Spectral Amplitude Optimization (SMF version)

Optimizes the spectral AMPLITUDE A(ω) of an input pulse to minimize the fractional
energy in a Raman-shifted wavelength band after propagation through a single-mode fiber.

Unlike phase optimization (which is energy-neutral), amplitude modulation can trivially
reduce the cost by setting A→0. This script implements multiple anti-trivial-solution
strategies:
  1. Box constraints:      A ∈ [1-δ, 1+δ]
  2. Energy preservation:  λ_E · (E_shaped/E_original - 1)²
  3. Tikhonov penalty:     λ_T · ‖A - 1‖²
  4. Total variation:      λ_TV · Σ √((A[i+1]-A[i])² + ε²)
  5. Spectral flatness:    λ_flat · (1 - geomean(A)/mean(A))²  [optional]

Uses the adjoint method for efficient gradient computation.
"""

try using Revise catch end
using Printf
using LinearAlgebra
using FFTW
using Statistics
using Logging
ENV["MPLBACKEND"] = "Agg"
using PyPlot
using MultiModeNoise
using Optim

include("common.jl")
include("visualization.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Setup, cost, and utility functions are in common.jl:
#   setup_amplitude_problem, spectral_band_cost, recommended_time_window,
#   check_boundary_conditions
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# 5. Regularized cost function for amplitude optimization
# ─────────────────────────────────────────────────────────────────────────────

"""
    amplitude_cost(A, uω0, J_raman, grad_raman;
                   λ_energy=100.0, λ_tikhonov=1.0, λ_tv=0.1, λ_flat=0.0)

Compute regularized cost and gradient contributions for amplitude optimization.

Returns (J_total, grad_total, cost_breakdown::Dict) where cost_breakdown maps
component names to their individual cost values.
"""
function amplitude_cost(A, uω0, J_raman, grad_raman;
    λ_energy=100.0, λ_tikhonov=1.0, λ_tv=0.1, λ_flat=0.0)

    # PRECONDITIONS
    @assert all(A .> 0) "amplitude must be positive (min=$(minimum(A)))"
    @assert λ_energy ≥ 0 && λ_tikhonov ≥ 0 && λ_tv ≥ 0 && λ_flat ≥ 0 "regularization weights must be non-negative"
    @assert size(A) == size(uω0) "A shape $(size(A)) ≠ uω0 shape $(size(uω0))"

    J_total = J_raman
    grad_total = copy(grad_raman)
    breakdown = Dict{String,Float64}(
        "J_raman" => J_raman,
        "J_energy" => 0.0,
        "J_tikhonov" => 0.0,
        "J_tv" => 0.0,
        "J_flat" => 0.0,
    )

    uω0_abs2 = abs2.(uω0)
    E_original = sum(uω0_abs2)

    # --- Energy preservation penalty ---
    if λ_energy > 0
        E_shaped = sum(A .^ 2 .* uω0_abs2)
        ratio = E_shaped / E_original
        J_E = λ_energy * (ratio - 1.0)^2
        grad_E = 2.0 .* λ_energy .* (ratio - 1.0) .* (2.0 .* A .* uω0_abs2) ./ E_original
        J_total += J_E
        grad_total .+= grad_E
        breakdown["J_energy"] = J_E
    end

    # --- Tikhonov regularization ---
    if λ_tikhonov > 0
        deviation = A .- 1.0
        J_T = λ_tikhonov * sum(deviation .^ 2)
        grad_T = 2.0 .* λ_tikhonov .* deviation
        J_total += J_T
        grad_total .+= grad_T
        breakdown["J_tikhonov"] = J_T
    end

    # --- Total variation (smooth L1) ---
    if λ_tv > 0
        ε_tv = 1e-6
        Nt = size(A, 1)
        J_TV = 0.0
        grad_TV = zeros(size(A))
        for m in 1:size(A, 2)
            for i in 2:Nt
                diff_i = A[i, m] - A[i-1, m]
                s = sqrt(diff_i^2 + ε_tv^2)
                J_TV += s
                ds = diff_i / s
                grad_TV[i, m] += ds
                grad_TV[i-1, m] -= ds
            end
        end
        J_TV *= λ_tv
        grad_TV .*= λ_tv
        J_total += J_TV
        grad_total .+= grad_TV
        breakdown["J_tv"] = J_TV
    end

    # --- Spectral flatness penalty ---
    if λ_flat > 0
        A_pos = max.(A, 1e-10)  # avoid log(0)
        log_mean = mean(log.(A_pos))
        geo_mean = exp(log_mean)
        arith_mean = mean(A_pos)
        flatness = geo_mean / arith_mean
        J_F = λ_flat * (1.0 - flatness)^2
        N = length(A_pos)
        # d(flatness)/dA_i = flatness * (1/(N*A_i) - 1/(N*arith_mean))
        grad_F = zeros(size(A))
        for i in eachindex(A_pos)
            df_dAi = flatness * (1.0 / (N * A_pos[i]) - 1.0 / (N * arith_mean))
            grad_F[i] = -2.0 * λ_flat * (1.0 - flatness) * df_dAi
        end
        J_total += J_F
        grad_total .+= grad_F
        breakdown["J_flat"] = J_F
    end

    # POSTCONDITIONS
    @assert isfinite(J_total) "total cost is not finite"
    @assert all(isfinite, grad_total) "gradient contains NaN/Inf"

    return J_total, grad_total, breakdown
end

# ─────────────────────────────────────────────────────────────────────────────
# 6. Forward-adjoint pipeline for amplitude
# ─────────────────────────────────────────────────────────────────────────────

"""
    cost_and_gradient_amplitude(A, uω0, fiber, sim, band_mask; reg_kwargs...)

Full forward-adjoint pipeline for amplitude optimization:
1. Apply amplitude modulation: u₀(ω) = uω0(ω) · A(ω)
2. Forward solve through fiber
3. Compute Raman band cost J at output
4. Adjoint solve backward to get λ(0)
5. Chain rule: ∂J/∂A = 2·Re(conj(λ₀) · uω0)
6. Add regularization gradients

Returns (J_total, ∂J_total/∂A, cost_breakdown).
"""
function cost_and_gradient_amplitude(A, uω0, fiber, sim, band_mask;
    λ_energy=100.0, λ_tikhonov=1.0, λ_tv=0.1, λ_flat=0.0)

    # PRECONDITIONS
    @assert size(A) == size(uω0) "A shape $(size(A)) ≠ uω0 shape $(size(uω0))"
    @assert all(A .> 0) "amplitude must be positive (min=$(minimum(A)))"

    # Apply amplitude modulation
    uω0_shaped = uω0 .* A

    # Forward solve — deepcopy fiber to avoid mutation across calls
    fiber_local = deepcopy(fiber)
    fiber_local["zsave"] = nothing
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_local, sim)
    ũω = sol["ode_sol"]

    # Get output field in lab frame
    L = fiber_local["L"]
    Dω = fiber_local["Dω"]
    ũω_L = ũω(L)
    uωf = @. cis(Dω * L) * ũω_L

    # Raman band cost and adjoint terminal condition
    J_raman, λωL = spectral_band_cost(uωf, band_mask)

    # Adjoint solve: propagate λ backward from L to 0
    sol_adj = MultiModeNoise.solve_adjoint_disp_mmf(λωL, ũω, fiber_local, sim)
    λ0 = sol_adj(0)

    # Chain rule for amplitude: δu₀ = uω0 · δA
    # ∂J/∂A = 2 · Re(conj(λ₀) · uω0)
    grad_raman = 2.0 .* real.(conj.(λ0) .* uω0)

    # Add regularization terms
    J_total, grad_total, breakdown = amplitude_cost(
        A, uω0, J_raman, grad_raman;
        λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat
    )

    # POSTCONDITIONS
    @assert isfinite(J_total) "cost is not finite: $J_total"
    @assert all(isfinite, grad_total) "gradient contains NaN/Inf"

    return J_total, grad_total, breakdown
end

# ─────────────────────────────────────────────────────────────────────────────
# 7. Box-constrained optimizer
# ─────────────────────────────────────────────────────────────────────────────

"""
    optimize_spectral_amplitude(uω0_base, fiber, sim, band_mask; kwargs...)

Optimize spectral amplitude A(ω) using LBFGS with projected gradient (manual clamping)
for box constraints A ∈ [1 - δ, 1 + δ]. Returns Optim result and the final cost breakdown.
"""
function optimize_spectral_amplitude(uω0_base, fiber, sim, band_mask;
    A0=nothing, max_iter=50, δ_bound=0.10,
    λ_energy=100.0, λ_tikhonov=1.0, λ_tv=0.1, λ_flat=0.0)

    # PRECONDITIONS
    @assert max_iter > 0 "max_iter must be positive"
    @assert 0 < δ_bound < 1 "δ_bound must be in (0, 1), got $δ_bound"
    @assert haskey(sim, "Nt") && haskey(sim, "M") "sim dict missing Nt or M"

    Nt = sim["Nt"]
    M = sim["M"]

    if isnothing(A0)
        A0 = ones(Nt, M)
    end

    lower_val = 1.0 - δ_bound
    upper_val = 1.0 + δ_bound
    reg_kwargs = (λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat)

    last_breakdown = Ref(Dict{String,Float64}())
    last_A_extrema = Ref((1.0, 1.0))

    t_start = time()
    function callback(state)
        elapsed = time() - t_start
        bd = last_breakdown[]
        J_r = get(bd, "J_raman", NaN)
        A_min, A_max = last_A_extrema[]
        @info @sprintf("  [%3d/%d] J=%.6f  J_ram=%.4e  A∈[%.3f,%.3f]  (%.1f s)",
                state.iteration, max_iter, state.value, J_r, A_min, A_max, elapsed)
        return false
    end

    # Use regular LBFGS with manual projection (clamping) instead of Fminbox
    result = optimize(
        Optim.only_fg!() do F, G, A_vec
            # Project back into box constraints
            clamp!(A_vec, lower_val, upper_val)

            A = reshape(A_vec, Nt, M)
            J, grad, breakdown = cost_and_gradient_amplitude(
                A, uω0_base, fiber, sim, band_mask; reg_kwargs...
            )
            last_breakdown[] = breakdown
            last_A_extrema[] = extrema(A)
            if G !== nothing
                G .= vec(grad)
            end
            if F !== nothing
                return J
            end
        end,
        vec(A0),
        LBFGS(m=10),
        Optim.Options(iterations=max_iter, f_abstol=1e-6, callback=callback)
    )

    return result, last_breakdown[]
end

# ─────────────────────────────────────────────────────────────────────────────
# 8. Gradient validation via finite differences
# ─────────────────────────────────────────────────────────────────────────────

"""
Validate the adjoint-based amplitude gradient against finite differences.
"""
function validate_amplitude_gradient(uω0, fiber, sim, band_mask;
    n_checks=5, ε=1e-5,
    λ_energy=100.0, λ_tikhonov=1.0, λ_tv=0.1, λ_flat=0.0)

    Nt = sim["Nt"]
    M = sim["M"]
    # Start near unity with small perturbations
    A_test = 1.0 .+ 0.02 .* randn(Nt, M)

    reg_kwargs = (λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat)
    J0, grad, _ = cost_and_gradient_amplitude(A_test, uω0, fiber, sim, band_mask; reg_kwargs...)

    # Pick indices where the pulse has significant spectral energy
    spectral_power = vec(sum(abs2.(uω0), dims=2))
    significant = findall(spectral_power .> 0.01 * maximum(spectral_power))
    indices = significant[rand(1:length(significant), min(n_checks, length(significant)))]

    @info "Amplitude gradient validation (ε = $ε)"
    lines = [@sprintf("  %5s  %12s  %12s  %10s", "index", "adjoint", "fin. diff.", "rel. error")]

    max_rel_err = 0.0
    for idx in indices
        A_plus = copy(A_test)
        A_plus[idx, 1] += ε
        J_plus, _, _ = cost_and_gradient_amplitude(A_plus, uω0, fiber, sim, band_mask; reg_kwargs...)

        A_minus = copy(A_test)
        A_minus[idx, 1] -= ε
        J_minus, _, _ = cost_and_gradient_amplitude(A_minus, uω0, fiber, sim, band_mask; reg_kwargs...)

        fd_grad = (J_plus - J_minus) / (2ε)
        adj_grad = grad[idx, 1]
        rel_err = abs(adj_grad - fd_grad) / max(abs(adj_grad), abs(fd_grad), 1e-15)
        max_rel_err = max(max_rel_err, rel_err)

        push!(lines, @sprintf("  %5d  %12.6e  %12.6e  %10.2e", idx, adj_grad, fd_grad, rel_err))
    end
    @info join(lines, "\n")
    if max_rel_err < 1e-3
        @info "Gradient validation PASSED (max rel. error = $(round(max_rel_err, sigdigits=2)))"
    else
        @warn "Gradient validation may have issues (max rel. error = $(round(max_rel_err, sigdigits=2)))"
    end
    return max_rel_err
end

# ─────────────────────────────────────────────────────────────────────────────
# 9. Visualization
# ─────────────────────────────────────────────────────────────────────────────

"""
Plot spectra, temporal pulse shapes, and amplitude profile before/after optimization.
DEPRECATED: Use plot_amplitude_result_v2 from visualization.jl instead.
"""
function plot_amplitude_result(A_before, A_after, uω0_base, fiber, sim,
    band_mask, Δf, raman_threshold)
    return plot_amplitude_result_v2(A_before, A_after, uω0_base, fiber, sim,
        band_mask, Δf, raman_threshold)
end

# ─────────────────────────────────────────────────────────────────────────────
# 10. Sweep δ bounds
# ─────────────────────────────────────────────────────────────────────────────

"""
    sweep_amplitude_bounds(uω0, fiber, sim, band_mask; kwargs...)

Sweep amplitude bound δ to explore the trade-off between modulation depth
and Raman suppression. Returns Dict mapping δ → (J_opt, A_opt, cost_breakdown).
"""
function sweep_amplitude_bounds(uω0, fiber, sim, band_mask;
    δ_values=[0.05, 0.10, 0.15, 0.20, 0.30], max_iter=30,
    λ_energy=100.0, λ_tikhonov=1.0, λ_tv=0.1, λ_flat=0.0)

    reg_kwargs = (λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat)
    results = Dict{Float64,Tuple{Float64,Matrix{Float64},Dict{String,Float64}}}()

    @info "Amplitude Bound Sweep: δ Trade-off"

    for (k, δ) in enumerate(δ_values)
        t_sweep = time()
        @info @sprintf("  Sweep [%d/%d]: δ = %.2f ...", k, length(δ_values), δ)

        result, breakdown = optimize_spectral_amplitude(
            uω0, fiber, sim, band_mask;
            max_iter=max_iter, δ_bound=δ, reg_kwargs...
        )

        Nt = sim["Nt"]; M = sim["M"]
        A_opt = reshape(result.minimizer, Nt, M)
        J_opt = result.minimum

        results[δ] = (J_opt, A_opt, breakdown)
        @info @sprintf("  Sweep [%d/%d]: δ=%.2f → J=%.6f  J_ram=%.4e  (%.1f s)",
            k, length(δ_values), δ, J_opt, breakdown["J_raman"], time() - t_sweep)
    end

    # Summary table
    table = String[]
    push!(table, "╔═══════╦═══════════════╦═══════════════╦═══════════════╦═══════════════╗")
    push!(table, "║   δ   ║   J_total     ║   J_raman     ║   J_energy    ║   J_tikhonov  ║")
    push!(table, "╠═══════╬═══════════════╬═══════════════╬═══════════════╬═══════════════╣")
    for δ in sort(collect(keys(results)))
        J_opt, _, bd = results[δ]
        push!(table, @sprintf("║ %5.2f ║ %13.6f ║ %13.4e ║ %13.4e ║ %13.4e ║",
                δ, J_opt, bd["J_raman"], bd["J_energy"], bd["J_tikhonov"]))
    end
    push!(table, "╚═══════╩═══════════════╩═══════════════╩═══════════════╩═══════════════╝")
    @info join(table, "\n")

    return results
end

# ─────────────────────────────────────────────────────────────────────────────
# 11. Solution quality report
# ─────────────────────────────────────────────────────────────────────────────

"""
    print_solution_report(A_opt, uω0, fiber, sim, band_mask, cost_breakdown)

Print a comprehensive quality report for the optimized amplitude profile.
"""
function print_solution_report(A_opt, uω0, fiber, sim, band_mask, cost_breakdown)
    # Cost breakdown
    A_min, A_max = extrema(A_opt)
    A_mean = mean(A_opt)

    # Energy deviation
    uω0_abs2 = abs2.(uω0)
    E_original = sum(uω0_abs2)
    E_shaped = sum(A_opt .^ 2 .* uω0_abs2)
    energy_dev_pct = (E_shaped / E_original - 1.0) * 100.0

    # Total variation of A
    tv_val = sum(abs.(diff(A_opt[:, 1])))

    # Boundary condition check (forward propagate shaped pulse)
    uω0_shaped = uω0 .* A_opt
    fiber_check = deepcopy(fiber)
    fiber_check["zsave"] = [fiber["L"]]
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_check, sim)
    utf = sol["ut_z"][end, :, :]
    bc_ok, edge_frac = check_boundary_conditions(utf, sim)
    status = bc_ok ? "OK" : "WARNING"

    # Peak power ratio
    P_peak_shaped = maximum(sum(abs2.(fft(uω0_shaped, 1)), dims=2))
    P_peak_orig = maximum(sum(abs2.(fft(uω0, 1)), dims=2))
    N_ratio = sqrt(P_peak_shaped / P_peak_orig)

    report = String[]
    push!(report, "╔══════════════════════════════════════════════════════════════╗")
    push!(report, "║                  Solution Quality Report                    ║")
    push!(report, "╠══════════════════════════════════════════════════════════════╣")
    push!(report, @sprintf("║  Raman cost (J_raman):    %12.6e                     ║", cost_breakdown["J_raman"]))
    push!(report, @sprintf("║  Raman cost (dB):         %12.2f                     ║", MultiModeNoise.lin_to_dB(cost_breakdown["J_raman"])))
    push!(report, @sprintf("║  Energy penalty:          %12.6e                     ║", cost_breakdown["J_energy"]))
    push!(report, @sprintf("║  Tikhonov penalty:        %12.6e                     ║", cost_breakdown["J_tikhonov"]))
    push!(report, @sprintf("║  TV penalty:              %12.6e                     ║", cost_breakdown["J_tv"]))
    push!(report, @sprintf("║  Flatness penalty:        %12.6e                     ║", cost_breakdown["J_flat"]))
    push!(report, @sprintf("║  A range:         [%.4f, %.4f]                        ║", A_min, A_max))
    push!(report, @sprintf("║  A mean:                  %8.4f                        ║", A_mean))
    push!(report, @sprintf("║  Energy deviation:        %+7.3f%%                        ║", energy_dev_pct))
    push!(report, @sprintf("║  Total variation of A:    %8.4f                        ║", tv_val))
    push!(report, @sprintf("║  Boundary check:  %s (edge energy = %.2e)          ║", status, edge_frac))
    push!(report, @sprintf("║  Peak power ratio:        %8.4f (N_ratio = %.3f)     ║", P_peak_shaped / P_peak_orig, N_ratio))
    push!(report, "╚══════════════════════════════════════════════════════════════╝")
    @info join(report, "\n")
end

# ─────────────────────────────────────────────────────────────────────────────
# 12. Main runner
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_amplitude_optimization(; kwargs...)

End-to-end amplitude optimization:
1. Check time_window adequacy
2. Setup problem
3. Validate gradient (optional)
4. Optimize with box constraints + regularization
5. Print solution report
6. Plot and save
"""
function run_amplitude_optimization(;
    max_iter=20, validate=true, save_prefix="amp_opt",
    A0=nothing, δ_bound=0.10,
    λ_energy=100.0, λ_tikhonov=1.0, λ_tv=0.1, λ_flat=0.0,
    kwargs...)

    t_total = time()
    # Step 1–2: Setup (includes time_window check)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_amplitude_problem(; kwargs...)
    Nt = sim["Nt"]; M = sim["M"]

    @info "═══ Amplitude Optimization ═══" L=fiber["L"] Nt=Nt δ=δ_bound max_iter=max_iter λ_E=λ_energy λ_T=λ_tikhonov λ_TV=λ_tv

    # Step 3: Gradient validation
    if validate
        @info "Step 1: Gradient Validation"
        validate_amplitude_gradient(uω0, fiber, sim, band_mask;
            n_checks=3, λ_energy=λ_energy, λ_tikhonov=λ_tikhonov,
            λ_tv=λ_tv, λ_flat=λ_flat)
    end

    # Step 4: Optimize
    @info "Step 2: Optimization (δ = $δ_bound)"
    result, breakdown = optimize_spectral_amplitude(
        uω0, fiber, sim, band_mask;
        A0=A0, max_iter=max_iter, δ_bound=δ_bound,
        λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat
    )
    @debug "$(result)"

    A_opt = reshape(result.minimizer, Nt, M)

    # Step 5: Solution report
    print_solution_report(A_opt, uω0, fiber, sim, band_mask, breakdown)

    # Step 6: Plot
    @info "Step 3: Plotting"
    A_before = ones(Nt, M)

    # Optimization comparison (3×2 panel)
    plot_amplitude_result_v2(A_before, A_opt, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        save_path="$(save_prefix).png")

    # Evolution comparison (2×2 grid: temporal/spectral × before/after)
    @info "Step 4: Evolution Comparison"
    uω0_opt = uω0 .* A_opt
    plot_evolution_comparison(uω0, uω0_opt, fiber, sim;
        label_before="Unmodulated (A=1)", label_after="Modulated (A=A_opt)",
        title="Pulse evolution comparison (L=$(fiber["L"])m)",
        save_path="$(save_prefix)_evolution.png")

    # Boundary diagnostic
    fiber_bc = deepcopy(fiber)
    fiber_bc["zsave"] = [fiber["L"]]
    sol_bc = MultiModeNoise.solve_disp_mmf(uω0_opt, fiber_bc, sim)
    plot_boundary_diagnostic(sol_bc, sim, fiber_bc)
    savefig("$(save_prefix)_boundary.png", dpi=300)
    @info "Saved boundary diagnostic to $(save_prefix)_boundary.png"

    bc_ok, edge_frac = check_boundary_conditions(sol_bc["ut_z"][end, :, :], sim)
    if !bc_ok
        @warn @sprintf("Boundary corruption detected (edge energy = %.2e). Consider increasing time_window.", edge_frac)
    end

    elapsed = time() - t_total
    A_opt_final = reshape(result.minimizer, Nt, M)
    A_min, A_max = extrema(A_opt_final)
    @info @sprintf("═══ Done (%s, %.1f s) — J_final=%.6f, A∈[%.4f,%.4f] ═══", save_prefix, elapsed, result.minimum, A_min, A_max)

    return result, uω0, fiber, sim, band_mask, Δf
end

# ─────────────────────────────────────────────────────────────────────────────
# 13. Example runs (only when script is executed directly)
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__

@info "═══════════════════════════════════════════"
@info "  Amplitude Optimization — Example Runs"
@info "═══════════════════════════════════════════"

# Run 1: Gentle regime — single fission (N ≈ 1.5)
@info "\n▶ Run 1: Gentle regime (L=1m, P=0.05W, δ=0.10)"
result1, uω0_1, fiber_1, sim_1, band_mask_1, Δf_1 = run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.05, max_iter=15,
    time_window=10.0, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40],
    δ_bound=0.10,
    save_prefix="amp_opt_L1m_P005W_d010"
)
GC.gc()

# Run 2: Same fiber, wider amplitude bounds
@info "\n▶ Run 2: Wider bounds (L=1m, P=0.05W, δ=0.20)"
result2, uω0_2, fiber_2, sim_2, band_mask_2, Δf_2 = run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.05, max_iter=15,
    time_window=10.0, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40],
    δ_bound=0.20,
    save_prefix="amp_opt_L1m_P005W_d020"
)
GC.gc()

# Run 3: Moderate power (N ≈ 2.7) — harder landscape
@info "\n▶ Run 3: Moderate power (L=1m, P=0.15W, δ=0.15)"
result3, uω0_3, fiber_3, sim_3, band_mask_3, Δf_3 = run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.15, max_iter=20,
    time_window=10.0, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40],
    δ_bound=0.15,
    save_prefix="amp_opt_L1m_P015W_d015"
)
GC.gc()

# Sweep: explore the δ trade-off at the gentle regime
@info "\n▶ Sweep: δ trade-off at gentle regime"
uω0_sw, fiber_sw, sim_sw, band_mask_sw, Δf_sw, _ = setup_amplitude_problem(
    L_fiber=1.0, P_cont=0.05, time_window=10.0, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40]
)
sweep_results = sweep_amplitude_bounds(uω0_sw, fiber_sw, sim_sw, band_mask_sw;
    δ_values=[0.05, 0.10, 0.15, 0.20, 0.30], max_iter=15)

@info "═══ All runs complete ═══"

end # if main script
