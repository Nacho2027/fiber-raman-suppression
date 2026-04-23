"""
Benchmarking and Analysis Tools for Raman Suppression Optimization

Provides tools for:
1. Grid size benchmarking — find the optimal Nt for speed vs accuracy
2. Time window analysis — detect boundary artifacts from undersized windows
3. Continuation method — warm-start optimization across increasing fiber lengths
4. Multi-start L-BFGS — escape local minima with multiple random initial phases
5. Parallel gradient validation — fast finite-difference checks using threads

Depends on: raman_optimization.jl (must be included first for cost_and_gradient, etc.)
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

# Include the base optimization script for shared functions
# (raman_optimization.jl includes common.jl and visualization.jl)
include("raman_optimization.jl")

# ─────────────────────────────────────────────────────────────────────────────
# 1. Grid Size Benchmarking
# ─────────────────────────────────────────────────────────────────────────────

"""
    benchmark_grid_sizes(; L=1.0, P=0.05, Nt_values=[2^10, 2^11, 2^12, 2^13, 2^14],
        n_iters=3, kwargs...)

Benchmark the cost-and-gradient evaluation across different grid sizes Nt.
For each Nt, runs `n_iters` iterations and records wall time, cost J, and
gradient norm. Prints a comparison table and returns a Dict of results.

The largest Nt serves as the "reference" solution for accuracy comparison.

# Example
```julia
results = benchmark_grid_sizes(L=1.0, P=0.05, n_iters=3)
```
"""
function benchmark_grid_sizes(;
    L=1.0, P=0.05,
    Nt_values=[2^10, 2^11, 2^12, 2^13, 2^14],
    n_iters=3,
    time_window=10.0,
    kwargs...)

    @info "Grid Size Benchmark: Nt Scaling" L=L P_cont=P time_window=time_window n_iters=n_iters

    results = Dict{Int, Dict{String, Any}}()

    for Nt in Nt_values
        @debug @sprintf("  Nt = 2^%d = %d ...", Int(log2(Nt)), Nt)

        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            L_fiber=L, P_cont=P, Nt=Nt, time_window=time_window, kwargs...)

        φ_test = 0.1 .* randn(Nt, sim["M"])

        # Warmup run (JIT compilation for this Nt)
        cost_and_gradient(φ_test, uω0, fiber, sim, band_mask)

        # Timed runs
        times = Float64[]
        J_vals = Float64[]
        grad_norms = Float64[]

        for iter in 1:n_iters
            t0 = time()
            J, grad = cost_and_gradient(φ_test, uω0, fiber, sim, band_mask)
            dt = time() - t0
            push!(times, dt)
            push!(J_vals, J)
            push!(grad_norms, norm(grad))
        end

        avg_time = mean(times)
        results[Nt] = Dict(
            "avg_time" => avg_time,
            "std_time" => std(times),
            "J" => mean(J_vals),
            "grad_norm" => mean(grad_norms),
            "all_times" => times
        )

        @debug @sprintf("  → avg=%.3fs, J=%.6e, ‖∇J‖=%.4e", avg_time, mean(J_vals), mean(grad_norms))
    end

    # Summary table
    table = String[]
    push!(table, "╔═══════════╦════════════════╦════════════════╦════════════════╦═══════════╗")
    push!(table, "║    Nt     ║  time/iter [s] ║      J         ║    ‖∇J‖        ║  speedup  ║")
    push!(table, "╠═══════════╬════════════════╬════════════════╬════════════════╬═══════════╣")

    ref_time = results[maximum(Nt_values)]["avg_time"]
    for Nt in sort(Nt_values)
        r = results[Nt]
        speedup = ref_time / r["avg_time"]
        push!(table, @sprintf("║ 2^%-2d=%5d ║ %10.3f±%.2f ║ %14.6e ║ %14.4e ║ %7.1f×  ║",
                Int(log2(Nt)), Nt, r["avg_time"], r["std_time"], r["J"], r["grad_norm"], speedup))
    end
    push!(table, "╚═══════════╩════════════════╩════════════════╩════════════════╩═══════════╝")
    @info join(table, "\n")

    # Check J convergence relative to finest grid
    J_ref = results[maximum(Nt_values)]["J"]
    conv_lines = ["Cost convergence (relative to Nt=$(maximum(Nt_values))):"]
    for Nt in sort(Nt_values)
        J_err = abs(results[Nt]["J"] - J_ref) / max(abs(J_ref), 1e-15)
        status = J_err < 1e-3 ? "CONVERGED" : (J_err < 1e-2 ? "~OK" : "INACCURATE")
        push!(conv_lines, @sprintf("  Nt=%5d: |ΔJ/J| = %.2e  [%s]", Nt, J_err, status))
    end
    @info join(conv_lines, "\n")

    return results
end

# ─────────────────────────────────────────────────────────────────────────────
# 2. Time Window Analysis
# ─────────────────────────────────────────────────────────────────────────────

"""
    analyze_time_windows(; L=1.0, P=0.05,
        windows=[5.0, 10.0, 15.0, 20.0, 30.0, 40.0], kwargs...)

For each time window, run a forward propagation and check boundary energy.
This detects whether the pulse wraps around the periodic FFT boundary
(a sign that the window is too small for the given fiber length).

Prints a diagnostic table and optionally plots overlaid output spectra.

# Returns
Dict mapping window size → (boundary_fraction, J, output_spectrum)
"""
function analyze_time_windows(;
    L=1.0, P=0.05,
    windows=[5.0, 10.0, 15.0, 20.0, 30.0, 40.0],
    Nt=2^13,
    plot_spectra=true,
    kwargs...)

    @info "Time Window Analysis: Boundary Check" L=L P_cont=P Nt=Nt

    results = Dict{Float64, Dict{String, Any}}()
    all_spectra = []
    all_Δf = []

    for tw in windows
        @debug @sprintf("  time_window = %5.1f ps ...", tw)

        uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(;
            L_fiber=L, P_cont=P, Nt=Nt, time_window=tw, kwargs...)

        # Forward propagation with zsave for boundary check
        fiber_fwd = deepcopy(fiber)
        fiber_fwd["zsave"] = [fiber["L"]]
        sol = MultiModeNoise.solve_disp_mmf(uω0, fiber_fwd, sim)
        uωf = sol["uω_z"][end, :, :]
        utf = sol["ut_z"][end, :, :]

        # Boundary energy check (first and last 5% of time grid)
        n_edge = max(1, Nt ÷ 20)
        E_total = sum(abs2.(utf))
        E_edges = sum(abs2.(utf[1:n_edge, :])) + sum(abs2.(utf[end-n_edge+1:end, :]))
        edge_frac = E_edges / max(E_total, eps())

        # Cost at output
        J, _ = spectral_band_cost(uωf, band_mask)

        status = if edge_frac < 1e-6
            "OK"
        elseif edge_frac < 1e-3
            "WARNING"
        else
            "DANGER"
        end

        results[tw] = Dict(
            "edge_frac" => edge_frac,
            "J" => J,
            "status" => status,
            "spectrum" => Nt .* sum(abs2.(fftshift(uωf, 1)), dims=2)[:, 1],
            "Δf" => Δf
        )

        push!(all_spectra, results[tw]["spectrum"])
        push!(all_Δf, Δf)

        @debug @sprintf("  → edge=%.2e  J=%.4e  [%s]", edge_frac, J, status)
    end

    # Summary table
    table = String[]
    push!(table, "╔═════════════╦════════════════╦════════════════╦══════════╗")
    push!(table, "║  window [ps] ║  edge_energy   ║      J         ║  status  ║")
    push!(table, "╠═════════════╬════════════════╬════════════════╬══════════╣")
    for tw in sort(collect(keys(results)))
        r = results[tw]
        push!(table, @sprintf("║  %8.1f    ║  %12.2e  ║  %12.4e  ║  %-7s ║",
                tw, r["edge_frac"], r["J"], r["status"]))
    end
    push!(table, "╚═════════════╩════════════════╩════════════════╩══════════╝")
    @info join(table, "\n")

    # Plot spectral difference from largest-window reference
    if plot_spectra && !isempty(all_spectra)
        sorted_windows = sort(collect(keys(results)))
        ref_tw = sorted_windows[end]
        ref_spec = results[ref_tw]["spectrum"]
        ref_spec_dB = 10 .* log10.(max.(ref_spec ./ maximum(ref_spec), 1e-30))

        fig, (ax1, ax2) = subplots(1, 2, figsize=(12, 5))

        # Okabe-Ito derived colors for time window curves
        tw_colors = ["#0072B2", "#D55E00", "#009E73", "#CC79A7", "#F0E442", "#56B4E9"]

        # Left: overlaid spectra
        for (i, tw) in enumerate(sorted_windows)
            r = results[tw]
            spec = r["spectrum"]
            Δf_tw = r["Δf"]
            spec_norm = spec ./ maximum(spec)
            label_str = @sprintf("%.0f ps [%s]", tw, r["status"])
            color_i = tw_colors[mod1(i, length(tw_colors))]
            is_ref = (tw == ref_tw)
            ax1.plot(Δf_tw, 10 .* log10.(max.(spec_norm, 1e-30)),
                label=label_str, alpha=is_ref ? 0.9 : 0.5,
                lw=is_ref ? 2.0 : 1.0, color=color_i)
        end
        ax1.set_xlabel("Δf [THz]")
        ax1.set_ylabel("Normalized power [dB]")
        ax1.set_title("Output spectrum vs time window (L=$(L)m)")
        ax1.set_xlim(-30, 30)
        ax1.set_ylim(-40, 0)
        ax1.ticklabel_format(useOffset=false)
        ax1.legend(fontsize=8)

        # Right: difference from reference (largest window)
        ax2.axhspan(-1, 1, color="green", alpha=0.1, label="±1 dB")
        for (i, tw) in enumerate(sorted_windows[1:end-1])
            r = results[tw]
            spec = r["spectrum"]
            Δf_tw = r["Δf"]
            spec_dB = 10 .* log10.(max.(spec ./ maximum(spec), 1e-30))
            # Interpolate reference onto this grid if needed (different Δf grids)
            if length(spec_dB) == length(ref_spec_dB)
                diff_dB = spec_dB .- ref_spec_dB
            else
                diff_dB = spec_dB  # fallback: just show spectrum
            end
            label_str = @sprintf("%.0f ps", tw)
            color_i = tw_colors[mod1(i, length(tw_colors))]
            ax2.plot(Δf_tw, diff_dB, label=label_str, alpha=0.7, color=color_i)
        end
        ax2.set_xlabel("Δf [THz]")
        ax2.set_ylabel("ΔPower [dB] (vs $(Int(ref_tw)) ps ref)")
        ax2.set_title("Spectral difference from reference")
        ax2.set_xlim(-30, 30)
        ax2.ticklabel_format(useOffset=false)
        ax2.legend(fontsize=8)
        ax2.axhline(y=0, color="black", ls="--", alpha=0.3)

        fig.text(0.5, 0.01, "Left: output spectra for each time window. Right: difference from largest-window reference.",
                 ha="center", va="bottom", fontsize=9, style="italic")
        fig.tight_layout(rect=[0, 0.05, 1, 1])
        savefig("results/images/time_window_analysis_L$(L)m.png", dpi=150)
        @info "Saved spectrum overlay to results/images/time_window_analysis_L$(L)m.png"
    end

    return results
end

# ─────────────────────────────────────────────────────────────────────────────
# 2b. Time Window Analysis with Optimized Phase
# ─────────────────────────────────────────────────────────────────────────────

"""
    analyze_time_windows_optimized(φ_opt, uω0_ref, fiber_ref, sim_ref, band_mask_ref;
        windows=[5.0, 10.0, 15.0, 20.0, 30.0, 40.0], kwargs...)

Test how an optimized spectral phase transfers across different time window sizes.

Unlike `analyze_time_windows` (which propagates an unshaped pulse), this function:
1. Takes an optimized phase `φ_opt` from a reference grid.
2. For each target window size, sets up a new grid and interpolates the phase
   onto the new frequency axis via linear interpolation.
3. Propagates the shaped pulse and reports J + boundary status.

This detects whether the optimization result is robust to grid changes and
whether boundary artifacts appear at different window sizes.

# Returns
Dict mapping window size → Dict("J", "edge_frac", "status", "J_dB")
"""
function analyze_time_windows_optimized(φ_opt, uω0_ref, fiber_ref, sim_ref, band_mask_ref;
    windows=[5.0, 10.0, 15.0, 20.0, 30.0, 40.0],
    Nt=sim_ref["Nt"],
    P_cont=0.05,
    plot_results=true,
    save_prefix="results/images/time_window_optimized",
    kwargs...)

    # PRECONDITIONS
    @assert size(φ_opt) == size(uω0_ref) "φ_opt shape must match uω0_ref"
    @assert length(windows) > 0 "windows must not be empty"

    @info "Time Window Analysis (Optimized Phase)" Nt=Nt n_windows=length(windows) P_cont=P_cont

    # Reference frequency axis for interpolation
    Δf_ref = fftfreq(sim_ref["Nt"], 1 / sim_ref["Δt"])

    results = Dict{Float64, Dict{String, Any}}()

    for tw in windows
        @debug @sprintf("  time_window = %5.1f ps ...", tw)

        # Setup new grid at this window size
        uω0_tw, fiber_tw, sim_tw, band_mask_tw, _, _ = setup_raman_problem(;
            L_fiber=fiber_ref["L"],
            P_cont=P_cont,
            Nt=Nt, time_window=tw, kwargs...)

        # Interpolate phase from reference grid to new grid
        Δf_tw = fftfreq(Nt, 1 / sim_tw["Δt"])
        M = sim_tw["M"]
        φ_interp = zeros(Nt, M)
        for m in 1:M
            # Linear interpolation: find nearest reference frequency for each target frequency
            for j in 1:Nt
                f_target = Δf_tw[j]
                # Find bracketing indices in reference grid
                dists = abs.(Δf_ref .- f_target)
                idx_near = argmin(dists)
                φ_interp[j, m] = φ_opt[idx_near, m]
            end
        end

        # Propagate shaped pulse
        uω0_shaped = @. uω0_tw * cis(φ_interp)
        fiber_fwd = deepcopy(fiber_tw)
        fiber_fwd["zsave"] = [fiber_tw["L"]]
        sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_fwd, sim_tw)
        uωf = sol["uω_z"][end, :, :]
        utf = sol["ut_z"][end, :, :]

        # Cost
        J, _ = spectral_band_cost(uωf, band_mask_tw)
        J_dB = MultiModeNoise.lin_to_dB(J)

        # Boundary check
        bc_ok, edge_frac = check_boundary_conditions(utf, sim_tw)

        status = if edge_frac < 1e-6
            "OK"
        elseif edge_frac < 1e-3
            "WARNING"
        else
            "DANGER"
        end

        results[tw] = Dict(
            "J" => J,
            "J_dB" => J_dB,
            "edge_frac" => edge_frac,
            "status" => status
        )

        @debug @sprintf("  → J=%.4e (%.1f dB), edge=%.2e [%s]", J, J_dB, edge_frac, status)
    end

    # Summary table
    table = String[]
    push!(table, "╔═════════════╦════════════════╦══════════╦════════════════╦══════════╗")
    push!(table, "║  window [ps] ║      J [dB]    ║  J [lin] ║  edge_energy   ║  status  ║")
    push!(table, "╠═════════════╬════════════════╬══════════╬════════════════╬══════════╣")
    for tw in sort(collect(keys(results)))
        r = results[tw]
        push!(table, @sprintf("║  %8.1f    ║  %12.2f  ║ %8.2e ║  %12.2e  ║  %-7s ║",
                tw, r["J_dB"], r["J"], r["edge_frac"], r["status"]))
    end
    push!(table, "╚═════════════╩════════════════╩══════════╩════════════════╩══════════╝")
    @info join(table, "\n")

    if plot_results
        plot_time_window_analysis_v2(results; save_prefix=save_prefix)
    end

    return results
end

"""
    plot_time_window_analysis_v2(results; save_prefix="time_window_optimized")

Two-panel bar chart for optimized time window analysis:
- Left panel: J in dB per window size, bars color-coded by boundary status
- Right panel: Edge energy fraction per window size, with DANGER threshold line

Status colors: OK=green, WARNING=orange, DANGER=red.
"""
function plot_time_window_analysis_v2(results; save_prefix="results/images/time_window_optimized")
    windows = sort(collect(keys(results)))
    n = length(windows)

    J_dB = [results[tw]["J_dB"] for tw in windows]
    edge_fracs = [results[tw]["edge_frac"] for tw in windows]
    statuses = [results[tw]["status"] for tw in windows]

    # Color map by status
    status_colors = Dict("OK" => "#2ecc71", "WARNING" => "#f39c12", "DANGER" => "#e74c3c")
    colors = [get(status_colors, s, "#95a5a6") for s in statuses]

    fig, (ax1, ax2) = subplots(1, 2, figsize=(12, 5))

    # Left panel: J in dB — zoom y-axis to actual data range
    x = 1:n
    labels = [@sprintf("%.0f", tw) for tw in windows]
    ax1.bar(x, J_dB, color=colors, edgecolor="black", linewidth=0.5)
    ax1.set_xticks(x)
    ax1.set_xticklabels(labels)
    ax1.set_xlabel("Time window [ps]")
    ax1.set_ylabel("J [dB]")
    ax1.set_title("Raman cost vs time window (optimized phase)")
    ax1.ticklabel_format(useOffset=false, axis="y")
    # Zoom y-axis to show actual variation (±0.5 dB padding)
    if length(J_dB) > 0
        j_min, j_max = extrema(J_dB)
        j_pad = max(0.5, (j_max - j_min) * 0.15)
        ax1.set_ylim(j_min - j_pad, j_max + j_pad)
    end
    # Add value labels on bars
    for (i, v) in enumerate(J_dB)
        ax1.text(i, v + 0.1, @sprintf("%.1f", v), ha="center", va="bottom", fontsize=7)
    end

    # Right panel: Edge energy fraction (log scale)
    ax2.bar(x, max.(edge_fracs, 1e-20), color=colors, edgecolor="black", linewidth=0.5)
    ax2.set_yscale("log")
    ax2.set_xticks(x)
    ax2.set_xticklabels(labels)
    ax2.set_xlabel("Time window [ps]")
    ax2.set_ylabel("Edge energy fraction")
    ax2.set_title("Boundary condition check")
    ax2.axhline(y=1e-6, color="red", ls="--", alpha=0.7, label="DANGER threshold")
    ax2.axhline(y=1e-3, color="orange", ls="--", alpha=0.7, label="WARNING threshold")
    ax2.legend(fontsize=8)

    # Color legend using matplotlib patches
    mpatches = PyPlot.matplotlib.patches
    legend_patches = [
        mpatches.Patch(color="#2ecc71", label="OK (edge < 1e-6)"),
        mpatches.Patch(color="#f39c12", label="WARNING (edge < 1e-3)"),
        mpatches.Patch(color="#e74c3c", label="DANGER (edge ≥ 1e-3)")
    ]
    fig.legend(handles=legend_patches, loc="lower center", ncol=3, fontsize=8,
               bbox_to_anchor=(0.5, -0.02))

    fig.text(0.5, -0.06,
             "Time window analysis: how the simulation time window size affects results. " *
             "Left: Raman suppression cost J (dB) — should converge as window grows; large changes indicate the window is too small. " *
             "Right: fraction of pulse energy at the window edges (log scale) — high edge energy means pulse power is " *
             "hitting the boundaries, corrupting the simulation. Green = safe, yellow = marginal, red = unreliable results.",
             ha="center", va="bottom", fontsize=8, style="italic", wrap=true)
    fig.tight_layout(rect=[0, 0.06, 1, 1])
    savefig("$(save_prefix).png", dpi=150, bbox_inches="tight")
    @info "Saved time window analysis plot to $(save_prefix).png"
    return fig
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. Continuation Method with Adaptive Time Window
# ─────────────────────────────────────────────────────────────────────────────

# recommended_time_window is now in common.jl (included via raman_optimization.jl)

"""
    run_continuation(;
        L_ladder=[0.1, 0.2, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0],
        P_cont=0.05, max_iter_per_step=20, Nt=2^13, kwargs...)

Continuation optimization: solve easy (short fiber) problems first,
then use the optimized phase as a warm start for progressively longer fibers.

At each step, the time window is automatically chosen based on the walk-off
formula. If the grid size changes between steps (due to window growth), the
phase is interpolated via zero-padding in the frequency domain.

# Returns
Vector of NamedTuples: (L, time_window, J_init, J_opt, φ_opt, wall_time)
"""
function run_continuation(;
    L_ladder=[0.1, 0.2, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0],
    P_cont=0.05,
    max_iter_per_step=20,
    Nt=2^13,
    kwargs...)

    @info "Continuation Method: Warm-Start Across Lengths" P_cont=P_cont Nt=Nt steps=length(L_ladder)

    all_results = NamedTuple[]
    φ_prev = nothing

    for (step, L) in enumerate(L_ladder)
        tw = recommended_time_window(L)
        @debug @sprintf("Step %d/%d: L=%.2fm, time_window=%dps", step, length(L_ladder), L, tw)

        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            L_fiber=L, P_cont=P_cont, Nt=Nt, time_window=Float64(tw), kwargs...)
        M = sim["M"]

        # Warm start: use previous phase if available (same Nt assumed)
        φ0 = if isnothing(φ_prev)
            zeros(Nt, M)
        else
            copy(φ_prev)
        end

        # Compute initial cost
        J_init, _ = cost_and_gradient(φ0, uω0, fiber, sim, band_mask)

        # Optimize
        t0 = time()
        result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
            φ0=φ0, max_iter=max_iter_per_step)
        wall_time = time() - t0

        φ_opt = reshape(result.minimizer, Nt, M)
        J_opt = result.minimum  # optimize_spectral_phase now returns linear J

        # Check boundaries
        uω0_shaped = @. uω0 * cis(φ_opt)
        fiber_check = deepcopy(fiber)
        fiber_check["zsave"] = [fiber["L"]]
        sol_check = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_check, sim)
        utf = sol_check["ut_z"][end, :, :]
        n_edge = max(1, Nt ÷ 20)
        E_total = sum(abs2.(utf))
        E_edges = sum(abs2.(utf[1:n_edge, :])) + sum(abs2.(utf[end-n_edge+1:end, :]))
        bc_frac = E_edges / max(E_total, eps())
        bc_ok = bc_frac < 1e-6

        bc_str = bc_ok ? "OK" : "WARNING ($(round(bc_frac, sigdigits=2)))"
        @debug @sprintf("  → J: %.4e → %.4e (%.1f dB), time=%.1fs, BC=%s",
                J_init, J_opt, MultiModeNoise.lin_to_dB(J_opt), wall_time, bc_str)

        φ_prev = φ_opt

        push!(all_results, (
            L=L, time_window=tw, J_init=J_init, J_opt=J_opt,
            φ_opt=φ_opt, wall_time=wall_time, bc_frac=bc_frac
        ))
    end

    # Summary table
    table = String[]
    push!(table, "╔═══════╦════════════╦═══════════════╦═══════════════╦═════════╦═══════════╗")
    push!(table, "║  L[m] ║ window[ps] ║    J_init     ║    J_opt      ║ time[s] ║ boundary  ║")
    push!(table, "╠═══════╬════════════╬═══════════════╬═══════════════╬═════════╬═══════════╣")
    for r in all_results
        bc_str = r.bc_frac < 1e-6 ? "OK" : @sprintf("%.1e", r.bc_frac)
        push!(table, @sprintf("║ %5.2f ║ %8d   ║ %13.4e ║ %13.4e ║ %7.1f ║ %-9s ║",
                r.L, r.time_window, r.J_init, r.J_opt, r.wall_time, bc_str))
    end
    push!(table, "╚═══════╩════════════╩═══════════════╩═══════════════╩═════════╩═══════════╝")
    @info join(table, "\n")

    return all_results
end

# ─────────────────────────────────────────────────────────────────────────────
# 4. Multi-Start L-BFGS
# ─────────────────────────────────────────────────────────────────────────────

"""
    multistart_optimization(uω0, fiber, sim, band_mask;
        n_starts=20, max_iter=50, bandwidth_limit=3.0, kwargs...)

Run L-BFGS optimization from `n_starts` random initial spectral phases.
Each initial phase is band-limited to `bandwidth_limit × pulse_bandwidth`
to focus the search on physically relevant phase profiles.

Uses `Threads.@threads` for parallelism when Julia is started with multiple
threads (e.g., `julia -t 4`).

# Returns
NamedTuple: (best_result, best_φ, best_J, all_J, all_results)
"""
function multistart_optimization(uω0, fiber, sim, band_mask;
    n_starts=20, max_iter=50, bandwidth_limit=3.0)

    Nt = sim["Nt"]
    M = sim["M"]
    Δt = sim["Δt"]

    @info "Multi-Start Optimization" n_starts=n_starts max_iter=max_iter bandwidth_limit=bandwidth_limit threads=Threads.nthreads()

    # Estimate pulse spectral bandwidth for low-pass filtering initial phases
    spectral_power = vec(sum(abs2.(uω0), dims=2))
    peak_power = maximum(spectral_power)
    bw_indices = findall(spectral_power .> 0.01 * peak_power)
    pulse_bw_bins = length(bw_indices)
    filter_bw = min(Nt ÷ 2, round(Int, bandwidth_limit * pulse_bw_bins))

    @debug "Pulse bandwidth: $(pulse_bw_bins) bins, filter cutoff: $(filter_bw) bins"

    # Generate band-limited random phases
    function random_bandlimited_phase()
        φ_raw = π .* (2 .* rand(Nt, M) .- 1)  # uniform [-π, π]
        # Low-pass filter: zero out high-frequency components
        φ_fft = fft(φ_raw, 1)
        mask = zeros(Nt)
        half_bw = filter_bw ÷ 2
        mask[1:half_bw] .= 1.0
        mask[end-half_bw+1:end] .= 1.0
        φ_filtered = real.(ifft(φ_fft .* mask, 1))
        return φ_filtered
    end

    # Pre-generate all initial phases
    φ0_all = [random_bandlimited_phase() for _ in 1:n_starts]
    # Include zero phase as one of the starts
    φ0_all[1] = zeros(Nt, M)

    # Run optimizations (threaded)
    results_lock = ReentrantLock()
    all_results = Vector{Any}(undef, n_starts)
    all_J = zeros(n_starts)

    Threads.@threads for i in 1:n_starts
        # Each thread needs its own fiber copy
        fiber_local = deepcopy(fiber)
        uω0_local = copy(uω0)

        result_i = optimize_spectral_phase(uω0_local, fiber_local, sim, band_mask;
            φ0=φ0_all[i], max_iter=max_iter)

        J_i = result_i.minimum  # optimize_spectral_phase now returns linear J
        all_results[i] = result_i
        all_J[i] = J_i

        lock(results_lock) do
            @debug @sprintf("  Start %2d/%d: J = %.4e (%.1f dB)", i, n_starts, J_i,
                    MultiModeNoise.lin_to_dB(J_i))
        end
    end

    # Find best
    best_idx = argmin(all_J)
    best_result = all_results[best_idx]
    best_φ = reshape(best_result.minimizer, Nt, M)
    best_J = all_J[best_idx]

    # Boundary check on best result
    uω0_shaped = @. uω0 * cis(best_φ)
    fiber_bc = deepcopy(fiber)
    fiber_bc["zsave"] = [fiber["L"]]
    sol_bc = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_bc, sim)
    bc_ok, bc_frac = check_boundary_conditions(sol_bc["ut_z"][end, :, :], sim)

    # Statistics
    summary = String[]
    push!(summary, "── Multi-Start Summary ──────────────────────────")
    push!(summary, @sprintf("  Best:   start #%d, J = %.4e (%.1f dB)",
            best_idx, best_J, MultiModeNoise.lin_to_dB(best_J)))
    push!(summary, @sprintf("  Worst:  J = %.4e (%.1f dB)",
            maximum(all_J), MultiModeNoise.lin_to_dB(maximum(all_J))))
    push!(summary, @sprintf("  Median: J = %.4e (%.1f dB)",
            median(all_J), MultiModeNoise.lin_to_dB(median(all_J))))
    push!(summary, @sprintf("  Std:    %.4e", std(all_J)))
    push!(summary, @sprintf("  Spread: %.1f dB (worst - best)",
            MultiModeNoise.lin_to_dB(maximum(all_J)) - MultiModeNoise.lin_to_dB(best_J)))
    bc_str = bc_ok ? "OK ($(round(bc_frac, sigdigits=2)))" :
                     "DANGER ($(round(bc_frac, sigdigits=2)))"
    push!(summary, @sprintf("  Boundary: %s", bc_str))
    push!(summary, "─────────────────────────────────────────────────")
    @info join(summary, "\n")

    return (best_result=best_result, best_φ=best_φ, best_J=best_J,
            all_J=all_J, all_results=all_results, bc_frac=bc_frac)
end

# ─────────────────────────────────────────────────────────────────────────────
# 5. Parallel Gradient Validation
# ─────────────────────────────────────────────────────────────────────────────

"""
    validate_gradient_parallel(uω0, fiber, sim, band_mask;
        n_checks=10, ε=1e-5)

Validate adjoint gradient against central finite differences, using
`Threads.@threads` to parallelize the 2·n_checks forward-adjoint solves.

Each thread gets its own deepcopy of fiber to avoid zsave mutation conflicts.

# Returns
(max_rel_error, errors::Vector{Float64})
"""
function validate_gradient_parallel(uω0, fiber, sim, band_mask;
    n_checks=10, ε=1e-5)

    Nt = sim["Nt"]
    M = sim["M"]
    φ_test = 0.1 .* randn(Nt, M)

    # Compute reference gradient
    J0, grad = cost_and_gradient(φ_test, uω0, fiber, sim, band_mask)

    # Select indices with significant spectral energy
    spectral_power = vec(sum(abs2.(uω0), dims=2))
    significant = findall(spectral_power .> 0.01 * maximum(spectral_power))
    indices = significant[rand(1:length(significant), min(n_checks, length(significant)))]

    @info "Parallel gradient validation" ε=ε threads=Threads.nthreads()

    # Parallel finite differences
    fd_grads = zeros(length(indices))
    adj_grads = [grad[idx, 1] for idx in indices]

    Threads.@threads for k in 1:length(indices)
        idx = indices[k]

        # +ε perturbation (each thread gets its own fiber)
        φ_plus = copy(φ_test)
        φ_plus[idx, 1] += ε
        J_plus, _ = cost_and_gradient(φ_plus, uω0, fiber, sim, band_mask)

        # -ε perturbation
        φ_minus = copy(φ_test)
        φ_minus[idx, 1] -= ε
        J_minus, _ = cost_and_gradient(φ_minus, uω0, fiber, sim, band_mask)

        fd_grads[k] = (J_plus - J_minus) / (2ε)
    end

    # Collect results (sequential for ordering)
    max_rel_err = 0.0
    rel_errors = Float64[]
    lines = [@sprintf("  %5s  %12s  %12s  %10s", "index", "adjoint", "fin. diff.", "rel. error")]
    for k in 1:length(indices)
        idx = indices[k]
        rel_err = abs(adj_grads[k] - fd_grads[k]) / max(abs(adj_grads[k]), abs(fd_grads[k]), 1e-15)
        max_rel_err = max(max_rel_err, rel_err)
        push!(rel_errors, rel_err)
        push!(lines, @sprintf("  %5d  %12.6e  %12.6e  %10.2e", idx, adj_grads[k], fd_grads[k], rel_err))
    end
    @debug join(lines, "\n")

    if max_rel_err < 1e-3
        @info "PASSED (max rel. error = $(round(max_rel_err, sigdigits=2)))"
    else
        @warn "Gradient validation may have issues (max rel. error = $(round(max_rel_err, sigdigits=2)))"
    end

    return max_rel_err, rel_errors
end

# ─────────────────────────────────────────────────────────────────────────────
# 6. Performance Notes (for discussion with advisor)
# ─────────────────────────────────────────────────────────────────────────────

"""
    print_performance_notes()

Print findings from performance analysis for discussion with the research group.
"""
function print_performance_notes()
    @info """Performance Analysis Notes:
    1. FFT Plans: MultiModeNoise already caches FFT plans via plan_fft!.
    2. Interaction picture exp(±iDω·z): computed at EVERY ODE step. Changing to cis() requires modifying MultiModeNoise.
    3. Adjoint solver: Vern9() with fixed dt=1e-3 and adaptive=false. For L=5m → 5000 steps.
    4. Script-level cis() applied in cost_and_gradient. Expected ~2× speedup on exp(im*φ) calls.
    5. Buffer pre-allocation: uω0_shaped and uωf_buffer allocated once, reused across L-BFGS iterations.
    6. Time window sizing: critical for L≥2m. Use recommended_time_window(L) or analyze_time_windows()."""
end

# ─────────────────────────────────────────────────────────────────────────────
# Example usage (uncomment to run)
# ─────────────────────────────────────────────────────────────────────────────

# --- Grid Size Benchmark ---
# results_grid = benchmark_grid_sizes(
#     L=1.0, P=0.05, time_window=10.0,
#     Nt_values=[2^10, 2^11, 2^12, 2^13, 2^14],
#     n_iters=3,
#     gamma_user=0.0013, betas_user=[-2.6e-26]
# )

# --- Time Window Analysis ---
# results_tw = analyze_time_windows(
#     L=5.0, P=0.05,
#     windows=[5.0, 10.0, 15.0, 20.0, 30.0, 40.0],
#     Nt=2^13,
#     gamma_user=0.0013, betas_user=[-2.6e-26]
# )

# --- Continuation Method ---
# cont_results = run_continuation(
#     L_ladder=[0.1, 0.2, 0.5, 1.0, 2.0, 5.0],
#     P_cont=0.05, max_iter_per_step=15, Nt=2^13,
#     gamma_user=0.0013, betas_user=[-2.6e-26]
# )

# --- Multi-Start Optimization ---
# uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
#     L_fiber=1.0, P_cont=0.05, time_window=10.0, Nt=2^13,
#     gamma_user=0.0013, betas_user=[-2.6e-26]
# )
# ms_result = multistart_optimization(uω0, fiber, sim, band_mask;
#     n_starts=10, max_iter=30, bandwidth_limit=3.0)

# --- Parallel Gradient Validation ---
# uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(
#     L_fiber=1.0, P_cont=0.05, time_window=10.0, Nt=2^13,
#     gamma_user=0.0013, betas_user=[-2.6e-26]
# )
# max_err, errors = validate_gradient_parallel(uω0, fiber, sim, band_mask;
#     n_checks=10, ε=1e-5)

# --- Print performance notes ---
# print_performance_notes()
