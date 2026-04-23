"""
Spectral amplitude shaping (alternative to phase optimization).

Optimizes the input spectral *amplitude* profile to suppress Raman transfer,
subject to regularization that controls how aggressively the shaper can carve
the pulse. Provided as an A/B point of comparison against phase-only
optimization; phase is the default production path.

# Run
    julia --project=. -t auto scripts/lib/amplitude_optimization.jl

# Inputs
- Config constants at top of file (regularization strategy, λ values).
- `scripts/lib/common.jl` fiber presets.

# Outputs
- `results/raman/amplitude/<run_id>/_result.jld2` — JLD2 payload.
- `results/raman/amplitude/<run_id>/_result.json` — JSON sidecar.
- `results/raman/amplitude/<run_id>/*.png` — comparison figures.

# Runtime
~5–10 minutes per regularization strategy on a 4-core laptop.

# Docs
Docs: docs/architecture/cost-function-physics.md
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
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
ensure_deterministic_environment()

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
                   λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0)

Compute regularized cost and gradient contributions for amplitude optimization.

Returns (J_total, grad_total, cost_breakdown::Dict) where cost_breakdown maps
component names to their individual cost values.
"""
function amplitude_cost(A, uω0, J_raman, grad_raman;
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0)

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

    # --- Tikhonov regularization (normalized by number of elements) ---
    if λ_tikhonov > 0
        deviation = A .- 1.0
        N_elem = length(deviation)
        J_T = λ_tikhonov * sum(deviation .^ 2) / N_elem
        grad_T = 2.0 .* λ_tikhonov .* deviation ./ N_elem
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
        J_TV *= λ_tv / Nt
        grad_TV .*= λ_tv / Nt
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

"""
    project_energy!(A, uω0)

Rescale amplitude profile A so that the shaped pulse has the same energy as the
original: E_shaped = Σ A² |uω0|² → E_original = Σ |uω0|².
Modifies A in place and returns it.
"""
function project_energy!(A, uω0)
    E_original = sum(abs2.(uω0))
    E_shaped = sum(A .^ 2 .* abs2.(uω0))
    if E_shaped > 0
        A .*= sqrt(E_original / E_shaped)
    end
    return A
end

"""
    build_dct_basis(Nt, K; bandwidth_mask=nothing)

Build an orthonormal DCT-II basis matrix of size (Nt, K).
If `bandwidth_mask` is provided (a vector of length Nt), each column is
element-wise multiplied by the mask (useful for restricting to pulse bandwidth).
"""
function build_dct_basis(Nt, K; bandwidth_mask=nothing)
    B = zeros(Nt, K)
    for k in 0:K-1
        for i in 1:Nt
            B[i, k+1] = cos(k * π * (i - 0.5) / Nt)
        end
        B[:, k+1] ./= norm(B[:, k+1])
    end
    if bandwidth_mask !== nothing
        B .*= bandwidth_mask
    end
    return B
end

"""
    cost_and_gradient_lowdim(c, δ, B, uω0, fiber, sim, band_mask; kwargs...)

Evaluate cost and gradient in the low-dimensional DCT coefficient space.
A(ω) = 1 + δ · B · c, where B is (Nt, K) and c is (K·M,).
Returns (J, grad_c, breakdown).
"""
function cost_and_gradient_lowdim(c, δ, B, uω0, fiber, sim, band_mask; kwargs...)
    Nt = sim["Nt"]; M = sim["M"]
    K = size(B, 2)
    c_mat = reshape(c, K, M)
    A = 1.0 .+ δ .* (B * c_mat)
    clamp!(A, 1e-6, Inf)  # safety: ensure positivity
    J, grad_A, breakdown = cost_and_gradient_amplitude(A, uω0, fiber, sim, band_mask; kwargs...)
    grad_c = δ .* (B' * grad_A)
    return J, vec(grad_c), breakdown
end

"""
    optimize_spectral_amplitude_lowdim(uω0_base, fiber, sim, band_mask; kwargs...)

Optimize spectral amplitude using a low-dimensional DCT parameterization:
A(ω) = 1 + δ · Σ c_k · B_k(ω), with c_k ∈ [-1, 1].

Uses Fminbox(LBFGS) on the K·M coefficient vector.
Returns (Optim result, cost_breakdown). The minimizer contains the optimal c vector.
"""
function optimize_spectral_amplitude_lowdim(uω0_base, fiber, sim, band_mask;
    K=10, max_iter=50, δ_bound=0.10,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0,
    bandwidth_mask=nothing)

    # PRECONDITIONS
    @assert max_iter > 0 "max_iter must be positive"
    @assert 0 < δ_bound < 1 "δ_bound must be in (0, 1), got $δ_bound"
    @assert K > 0 "K must be positive"

    Nt = sim["Nt"]; M = sim["M"]
    B = build_dct_basis(Nt, K; bandwidth_mask=bandwidth_mask)

    # Coefficient bounds: c_k ∈ [-1, 1] ensures A ∈ [1-δ, 1+δ] approximately
    c0 = zeros(K * M)
    lower_c = fill(-1.0, K * M)
    upper_c = fill(1.0, K * M)

    # Nudge strictly inside bounds
    c0_vec = clamp.(c0, -1.0 + 1e-8, 1.0 - 1e-8)

    reg_kwargs = (λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat)

    last_breakdown = Ref(Dict{String,Float64}())

    t_start = time()
    function callback(state)
        elapsed = time() - t_start
        bd = last_breakdown[]
        J_r = get(bd, "J_raman", NaN)
        J_e = get(bd, "J_energy", NaN)
        @info @sprintf("  [lowdim %3d/%d] J=%.6f  J_ram=%.4e  J_E=%.4e  (%.1f s)",
                state.iteration, max_iter, state.value, J_r, J_e, elapsed)
        return false
    end

    result = optimize(
        Optim.only_fg!() do F, G, c_vec
            J, grad_c, breakdown = cost_and_gradient_lowdim(
                c_vec, δ_bound, B, uω0_base, fiber, sim, band_mask; reg_kwargs...
            )
            last_breakdown[] = breakdown
            if G !== nothing
                G .= grad_c
            end
            if F !== nothing
                return J
            end
        end,
        lower_c,
        upper_c,
        c0_vec,
        Fminbox(LBFGS(m=10)),
        Optim.Options(iterations=max_iter, outer_iterations=max_iter,
                      f_abstol=1e-6, callback=callback)
    )

    # Reconstruct final A for energy projection
    c_opt = reshape(result.minimizer, K, M)
    A_final = 1.0 .+ δ_bound .* (B * c_opt)
    project_energy!(A_final, uω0_base)

    return result, last_breakdown[]
end

"""
    run_amplitude_optimization_lowdim(; kwargs...)

End-to-end low-dimensional amplitude optimization using DCT parameterization.
"""
function run_amplitude_optimization_lowdim(;
    K=10, max_iter=20, validate=true, save_prefix="results/images/amp_opt_lowdim",
    δ_bound=0.10,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0,
    fiber_name="Custom",
    kwargs...)

    t_total = time()
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_amplitude_problem(; kwargs...)

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

    @info "═══ Low-Dim Amplitude Optimization ═══" L=fiber["L"] Nt=Nt K=K δ=δ_bound max_iter=max_iter

    # Optional gradient validation in coefficient space
    if validate
        @info "Step 1: Low-dim Gradient Validation"
        B = build_dct_basis(Nt, K)
        c_test = 0.1 .* randn(K * M)
        J, grad_c, _ = cost_and_gradient_lowdim(c_test, δ_bound, B, uω0, fiber, sim, band_mask;
            λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat)
        ε = 1e-5; n_checks = min(3, K * M)
        max_err = 0.0
        for idx in rand(1:K*M, n_checks)
            cp = copy(c_test); cp[idx] += ε
            cm = copy(c_test); cm[idx] -= ε
            Jp, _, _ = cost_and_gradient_lowdim(cp, δ_bound, B, uω0, fiber, sim, band_mask;
                λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat)
            Jm, _, _ = cost_and_gradient_lowdim(cm, δ_bound, B, uω0, fiber, sim, band_mask;
                λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat)
            fd = (Jp - Jm) / (2ε)
            rel_err = abs(grad_c[idx] - fd) / max(abs(grad_c[idx]), abs(fd), 1e-15)
            max_err = max(max_err, rel_err)
            @info @sprintf("  c[%d]: adj=%.4e  fd=%.4e  err=%.2e", idx, grad_c[idx], fd, rel_err)
        end
        @info @sprintf("  Max relative error: %.2e", max_err)
    end

    # Optimize
    @info "Step 2: Low-dim Optimization (K=$K, δ=$δ_bound)"
    result, breakdown = optimize_spectral_amplitude_lowdim(
        uω0, fiber, sim, band_mask;
        K=K, max_iter=max_iter, δ_bound=δ_bound,
        λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat
    )

    # Reconstruct A_opt
    B = build_dct_basis(Nt, K)
    c_opt = reshape(result.minimizer, K, M)
    A_opt = 1.0 .+ δ_bound .* (B * c_opt)
    project_energy!(A_opt, uω0)

    # Solution report
    print_solution_report(A_opt, uω0, fiber, sim, band_mask, breakdown)

    # Plot
    @info "Step 3: Plotting"
    A_before = ones(Nt, M)
    plot_amplitude_result_v2(A_before, A_opt, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        save_path="$(save_prefix).png", metadata=run_meta)

    # Evolution: solve both, merge into single 2×2 figure (ORG-01, ORG-02)
    @info "Step 4: Evolution Comparison"
    uω0_opt = uω0 .* A_opt
    sol_unshaped, fig_tmp1, _ = propagate_and_plot_evolution(uω0, fiber, sim)
    close(fig_tmp1)
    sol_opt_evo, fig_tmp2, _ = propagate_and_plot_evolution(uω0_opt, fiber, sim)
    close(fig_tmp2)

    fiber_evo = deepcopy(fiber)
    fiber_evo["zsave"] = collect(LinRange(0, fiber["L"], 101))
    plot_merged_evolution(sol_opt_evo, sol_unshaped, sim, fiber_evo;
        metadata=run_meta,
        save_path="$(save_prefix)_evolution.png")

    elapsed = time() - t_total
    @info @sprintf("═══ Done (%s, %.1f s) — J_final=%.6f ═══", save_prefix, elapsed, result.minimum)

    return result, uω0, fiber, sim, band_mask, Δf
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
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0)

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

Optimize spectral amplitude A(ω) using Fminbox(LBFGS) with proper box constraints
A ∈ [1 - δ, 1 + δ]. After optimization, projects energy to enforce conservation.
Returns Optim result and the final cost breakdown.
"""
function optimize_spectral_amplitude(uω0_base, fiber, sim, band_mask;
    A0=nothing, max_iter=50, δ_bound=0.10,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0)

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

    # Fminbox bound vectors
    lower = fill(lower_val, Nt * M)
    upper = fill(upper_val, Nt * M)

    # Fminbox requires initial point strictly inside bounds
    A0_vec = clamp.(vec(A0), lower_val + 1e-8, upper_val - 1e-8)

    reg_kwargs = (λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat)

    last_breakdown = Ref(Dict{String,Float64}())
    last_A_extrema = Ref((1.0, 1.0))

    t_start = time()
    function callback(state)
        elapsed = time() - t_start
        bd = last_breakdown[]
        J_r = get(bd, "J_raman", NaN)
        J_e = get(bd, "J_energy", NaN)
        J_t = get(bd, "J_tikhonov", NaN)
        J_tv = get(bd, "J_tv", NaN)
        A_min, A_max = last_A_extrema[]
        @info @sprintf("  [%3d/%d] J=%.6f  J_ram=%.4e  J_E=%.4e  J_T=%.4e  J_TV=%.4e  A∈[%.3f,%.3f]  (%.1f s)",
                state.iteration, max_iter, state.value, J_r, J_e, J_t, J_tv, A_min, A_max, elapsed)
        return false
    end

    # Fminbox handles box constraints properly — no manual clamping needed
    result = optimize(
        Optim.only_fg!() do F, G, A_vec
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
        lower,
        upper,
        A0_vec,
        Fminbox(LBFGS(m=10)),
        Optim.Options(iterations=max_iter, outer_iterations=max_iter,
                      f_abstol=1e-6, callback=callback)
    )

    # Post-optimization: project energy and re-clamp
    A_final = reshape(copy(result.minimizer), Nt, M)
    project_energy!(A_final, uω0_base)
    clamp!(A_final, lower_val, upper_val)
    result.minimizer .= vec(A_final)

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
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0)

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
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0)

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
    max_iter=20, validate=true, save_prefix="results/images/amp_opt",
    A0=nothing, δ_bound=0.10,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0,
    fiber_name="Custom",
    kwargs...)

    t_total = time()
    # Step 1–2: Setup (includes time_window check)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_amplitude_problem(; kwargs...)

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

    # Post-optimization validation
    lower_val = 1.0 - δ_bound
    upper_val = 1.0 + δ_bound
    @assert all(A_opt .>= lower_val - 1e-6) "Box violated: min(A) = $(minimum(A_opt))"
    @assert all(A_opt .<= upper_val + 1e-6) "Box violated: max(A) = $(maximum(A_opt))"
    E_dev = abs(sum(A_opt.^2 .* abs2.(uω0)) / sum(abs2.(uω0)) - 1.0)
    @assert E_dev < 0.05 "Energy deviation $(round(E_dev*100, digits=1))% exceeds 5%"

    # Step 5: Solution report
    print_solution_report(A_opt, uω0, fiber, sim, band_mask, breakdown)

    # Step 6: Plot
    @info "Step 3: Plotting"
    A_before = ones(Nt, M)

    # Optimization comparison (3×2 panel)
    plot_amplitude_result_v2(A_before, A_opt, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        save_path="$(save_prefix).png", metadata=run_meta)

    # Evolution: solve both, merge into single 2×2 figure (ORG-01, ORG-02)
    @info "Step 4: Evolution Comparison"
    uω0_opt = uω0 .* A_opt
    sol_unshaped, fig_tmp1, _ = propagate_and_plot_evolution(uω0, fiber, sim)
    close(fig_tmp1)
    sol_opt_evo, fig_tmp2, _ = propagate_and_plot_evolution(uω0_opt, fiber, sim)
    close(fig_tmp2)

    fiber_evo = deepcopy(fiber)
    fiber_evo["zsave"] = collect(LinRange(0, fiber["L"], 101))
    plot_merged_evolution(sol_opt_evo, sol_unshaped, sim, fiber_evo;
        metadata=run_meta,
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

    # Mandatory standard image set for the amplitude-shaped pulse.
    # phi_opt = 0 because this driver shapes amplitude only; the shaping is
    # carried by `uω0_amp_shaped` so the evolution + spectral plots reflect
    # the optimized field.
    uω0_amp_shaped = uω0 .* A_opt_final
    save_standard_set(zeros(Nt, M), uω0_amp_shaped, fiber, sim,
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
# 13. Example runs (only when script is executed directly)
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__

@info "═══════════════════════════════════════════"
@info "  Amplitude Optimization — Example Runs"
@info "═══════════════════════════════════════════"

# Run 1: Moderate power, medium bounds (Fminbox + energy projection)
@info "\n▶ Run 1: L=1m, P=0.15W, δ=0.15 (Fminbox)"
result1, uω0_1, fiber_1, sim_1, band_mask_1, Δf_1 = run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.15, max_iter=100,
    time_window=10.0, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40],
    δ_bound=0.15,
    fiber_name="SMF-28",
    save_prefix="results/images/amp_opt_L1m_P015W_d015"
)
GC.gc()

# Run 2: Smaller bounds comparison
@info "\n▶ Run 2: L=1m, P=0.15W, δ=0.10 (Fminbox, tighter bounds)"
result2, uω0_2, fiber_2, sim_2, band_mask_2, Δf_2 = run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.15, max_iter=100,
    time_window=10.0, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40],
    δ_bound=0.10,
    fiber_name="SMF-28",
    save_prefix="results/images/amp_opt_L1m_P015W_d010"
)
GC.gc()

# Sweep: explore the δ trade-off at moderate power
@info "\n▶ Sweep: δ trade-off at moderate power"
uω0_sw, fiber_sw, sim_sw, band_mask_sw, Δf_sw, _ = setup_amplitude_problem(
    L_fiber=1.0, P_cont=0.15, time_window=10.0, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40]
)
sweep_results = sweep_amplitude_bounds(uω0_sw, fiber_sw, sim_sw, band_mask_sw;
    δ_values=[0.05, 0.10, 0.15, 0.20], max_iter=50)

# Low-dimensional DCT parameterization runs
@info "\n▶ Run 3 (lowdim): L=1m, K=10, δ=0.15"
result3, uω0_3, fiber_3, sim_3, band_mask_3, Δf_3 = run_amplitude_optimization_lowdim(
    L_fiber=1.0, P_cont=0.15, max_iter=100,
    time_window=10.0, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40],
    K=10, δ_bound=0.15,
    fiber_name="SMF-28",
    save_prefix="results/images/amp_opt_lowdim_L1m_K10_d015"
)
GC.gc()

@info "\n▶ Run 4 (lowdim): L=2m, K=10, δ=0.15"
result4, uω0_4, fiber_4, sim_4, band_mask_4, Δf_4 = run_amplitude_optimization_lowdim(
    L_fiber=2.0, P_cont=0.15, max_iter=100,
    time_window=15.0, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40],
    K=10, δ_bound=0.15,
    fiber_name="SMF-28",
    save_prefix="results/images/amp_opt_lowdim_L2m_K10_d015"
)
GC.gc()

# K-sweep: explore DCT truncation order
@info "\n▶ K-sweep: K ∈ {5, 10, 15, 20} at L=1m, δ=0.15"
for K_val in [5, 10, 15, 20]
    @info "  K=$K_val"
    run_amplitude_optimization_lowdim(
        L_fiber=1.0, P_cont=0.15, max_iter=50,
        time_window=10.0, Nt=2^13, β_order=3,
        gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40],
        K=K_val, δ_bound=0.15, validate=false,
        fiber_name="SMF-28",
        save_prefix="results/images/amp_opt_lowdim_L1m_K$(K_val)_d015"
    )
    GC.gc()
end

@info "═══ All runs complete ═══"

end # if main script
