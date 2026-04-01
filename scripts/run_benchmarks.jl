"""
run_benchmarks.jl: Execute the full benchmark and advanced optimization suite

Calls every function exported by benchmark_optimization.jl with production
parameters on SMF-28 fiber (gamma=0.0013, beta2=-2.6e-26). Each section
runs independently with GC between stages to keep memory in check.

Contents:
  - 3a: Grid size benchmark (Nt = 2^10..2^14, 3 iters each)
  - 3b: Reference optimization (15 iters) + time window analysis (5..30 ps)
  - 3c: Continuation method (L ladder 0.1..5.0 m)
  - 3d: Multi-start optimization (10 starts, 30 iters)
  - 3e: Parallel gradient validation (10 finite-difference checks)
  - 3f: Performance notes summary

Usage:
  julia --project scripts/run_benchmarks.jl

Depends on:
  - scripts/benchmark_optimization.jl (benchmark_grid_sizes, run_optimization,
    analyze_time_windows_optimized, run_continuation, multistart_optimization,
    validate_gradient_parallel, print_performance_notes)
  - scripts/common.jl (setup_raman_problem, FIBER_PRESETS)
  - scripts/visualization.jl (plot_time_window_analysis_v2)
"""

include("benchmark_optimization.jl")

@info "═══════════════════════════════════════════"
@info "  Benchmark & Advanced Optimization Runs"
@info "═══════════════════════════════════════════"

# --- 3a: Grid Size Benchmark ---
@info "\n▶ 3a: Grid Size Benchmark"
results_grid = benchmark_grid_sizes(
    L=1.0, P=0.05, time_window=10.0,
    Nt_values=[2^10, 2^11, 2^12, 2^13, 2^14],
    n_iters=3,
    gamma_user=0.0013, betas_user=[-2.6e-26]
)
GC.gc()

# --- 3b: Run optimization + time window analysis ---
@info "\n▶ 3b: Reference optimization (15 iters) + time window analysis"
result_ref, uω0_ref, fiber_ref, sim_ref, band_mask_ref, Δf_ref = run_optimization(
    L_fiber=1.0, P_cont=0.05, max_iter=15,
    Nt=2^13, β_order=3, time_window=10.0,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40],
    λ_boundary=10.0, λ_gdd=0.0, λ_tod=0.0,
    λ_phase_tikhonov=0.0,
    save_prefix="results/images/tw_reference"
)
φ_opt_ref = reshape(result_ref.minimizer, sim_ref["Nt"], sim_ref["M"])

tw_results = analyze_time_windows_optimized(
    φ_opt_ref, uω0_ref, fiber_ref, sim_ref, band_mask_ref;
    windows=[5.0, 10.0, 15.0, 20.0, 30.0],
    L_fiber=1.0, P_cont=0.05, Nt=2^13, β_order=3,
    gamma_user=0.0013, betas_user=[-2.6e-26, 1.2e-40]
)
plot_time_window_analysis_v2(tw_results;
    save_prefix="results/images/time_window_optimized_L1m")
GC.gc()

# --- 3c: Continuation Method ---
@info "\n▶ 3c: Continuation Method"
cont_results = run_continuation(
    L_ladder=[0.1, 0.2, 0.5, 1.0, 2.0, 5.0],
    P_cont=0.05, max_iter_per_step=15, Nt=2^13,
    gamma_user=0.0013, betas_user=[-2.6e-26]
)
GC.gc()

# --- 3d: Multi-Start Optimization ---
@info "\n▶ 3d: Multi-Start Optimization"
uω0_ms, fiber_ms, sim_ms, band_mask_ms, Δf_ms, _ = setup_raman_problem(
    L_fiber=1.0, P_cont=0.05, time_window=10.0, Nt=2^13,
    gamma_user=0.0013, betas_user=[-2.6e-26]
)
ms_result = multistart_optimization(uω0_ms, fiber_ms, sim_ms, band_mask_ms;
    n_starts=10, max_iter=30, bandwidth_limit=3.0)
GC.gc()

# --- 3e: Parallel Gradient Validation ---
@info "\n▶ 3e: Parallel Gradient Validation"
uω0_gv, fiber_gv, sim_gv, band_mask_gv, _, _ = setup_raman_problem(
    L_fiber=1.0, P_cont=0.05, time_window=10.0, Nt=2^13,
    gamma_user=0.0013, betas_user=[-2.6e-26]
)
max_err, errors = validate_gradient_parallel(uω0_gv, fiber_gv, sim_gv, band_mask_gv;
    n_checks=10, ε=1e-5)
@info "Gradient validation: max_rel_error = $max_err"
GC.gc()

# --- 3f: Performance Notes ---
@info "\n▶ 3f: Performance Notes"
print_performance_notes()

@info "═══ All benchmark runs complete ═══"
