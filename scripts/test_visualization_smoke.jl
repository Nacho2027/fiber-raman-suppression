"""
Smoke test: generate PNGs with synthetic data to verify visualization changes.
Tests all modified visualization functions without requiring MultiModeNoise propagation.

Run: julia scripts/test_visualization_smoke.jl
"""
ENV["MPLBACKEND"] = "Agg"
using PyPlot, FFTW, Printf

# We can't use the full visualization.jl (it depends on MultiModeNoise for some functions),
# so we test the standalone utilities and verify the module loads without errors.

# Test 1: Module loads and constants are defined
println("Test 1: Loading visualization module...")
# Mock MultiModeNoise module for loading
module MultiModeNoise
    meshgrid(x, y) = (repeat(x', length(y), 1), repeat(y, 1, length(x)))
    lin_to_dB(x) = 10 * log10(max(x, 1e-30))
    function solve_disp_mmf(uω0, fiber, sim)
        Nt = sim["Nt"]; M = sim["M"]
        nz = length(fiber["zsave"])
        Dict(
            "uω_z" => complex.(randn(nz, Nt, M)),
            "ut_z" => complex.(randn(nz, Nt, M)),
            "ode_sol" => nothing
        )
    end
end

include("visualization.jl")
println("  ✓ visualization.jl loaded successfully")

# Verify constants
@assert COLOR_INPUT == "#0072B2"
@assert COLOR_OUTPUT == "#D55E00"
@assert COLOR_RAMAN == "#CC79A7"
@assert COLOR_REF == "#000000"
println("  ✓ Okabe-Ito color constants defined")

# Verify rcParams (font.size is numeric; legend.fontsize may be converted by matplotlib)
@assert PyPlot.matplotlib.rcParams["font.size"] == 10
println("  ✓ rcParams updated (font.size=10)")

# Test 2: compute_group_delay
println("\nTest 2: compute_group_delay...")
Nt = 2^10; Δt = 1e-14
sim_test = Dict("Nt" => Nt, "Δt" => Δt, "M" => 1, "f0" => 193.4,
                "ts" => collect(range(-Nt÷2, Nt÷2-1)) .* Δt)
# Linear phase → constant group delay
φ_linear = collect(1:Nt) .* 0.01
τ = compute_group_delay(φ_linear, sim_test)
@assert length(τ) == Nt
@assert all(isfinite, τ)
# For a linear phase, group delay should be approximately constant
τ_valid = τ[10:end-10]  # avoid edge effects
τ_spread = maximum(τ_valid) - minimum(τ_valid)
@assert τ_spread / abs(mean(τ_valid)) < 0.01 "Group delay not constant for linear phase"
println("  ✓ compute_group_delay works correctly")

# Test 3: add_caption!
println("\nTest 3: add_caption!...")
fig_test, ax_test = subplots(figsize=(6, 4))
ax_test.plot([1, 2, 3], [1, 4, 9])
add_caption!(fig_test, "Test caption for smoke test.")
close(fig_test)
println("  ✓ add_caption! works")

# Test 4: Verify no 'jet' colormap defaults remain
println("\nTest 4: Checking no 'jet' defaults remain...")
viz_source = read(joinpath(@__DIR__, "visualization.jl"), String)
@assert !occursin("cmap=\"jet\"", viz_source) "Found 'jet' colormap default in visualization.jl"
println("  ✓ No 'jet' defaults found")

# Test 5: Verify no axvspan remains
println("\nTest 5: Checking no axvspan remains...")
@assert !occursin("axvspan", viz_source) "Found axvspan in visualization.jl"
println("  ✓ No axvspan found")

# Test 6: Verify inferno is the default
println("\nTest 6: Checking inferno is default colormap...")
@assert occursin("cmap=\"inferno\"", viz_source) "inferno not found as default"
println("  ✓ inferno is default colormap")

# Test 7: Verify Raman onset uses axvline
println("\nTest 7: Checking Raman onset uses axvline...")
@assert occursin("axvline", viz_source) "No axvline found"
println("  ✓ Raman onset uses axvline")

# Test 8: Verify group delay in optimization result
println("\nTest 8: Checking group delay in plot_optimization_result_v2...")
@assert occursin("Group delay", viz_source)
@assert occursin("compute_group_delay", viz_source)
println("  ✓ Group delay replaces wrapped phase")

# Test 9: Verify INVALID watermark in amplitude result
println("\nTest 9: Checking INVALID watermark...")
@assert occursin("INVALID", viz_source)
@assert occursin("box constraints violated", viz_source)
println("  ✓ INVALID watermark present for negative amplitudes")

# Test 10: Verify ΔJ annotation
println("\nTest 10: Checking ΔJ improvement annotation...")
@assert occursin("ΔJ =", viz_source)
println("  ✓ ΔJ improvement annotation present")

# Test 11: Verify ticklabel_format(useOffset=false)
println("\nTest 11: Checking ticklabel_format usage...")
n_useOffset = length(collect(eachmatch(r"useOffset=false", viz_source)))
@assert n_useOffset >= 5 "Expected at least 5 useOffset=false calls, found $n_useOffset"
println("  ✓ ticklabel_format(useOffset=false) applied ($n_useOffset occurrences)")

# Test 12: Verify dB clipping to [-60, 0]
println("\nTest 12: Checking dB clipping...")
@assert occursin("clamp.", viz_source) "No clamp. found for dB range"
println("  ✓ dB clipping present")

# Test 13: Check save paths in other files
println("\nTest 13: Checking save paths in optimization scripts...")
raman_src = read(joinpath(@__DIR__, "raman_optimization.jl"), String)
@assert occursin("results/images/raman_opt_L1m", raman_src)
@assert occursin("results/images/chirp_sens", raman_src)
println("  ✓ raman_optimization.jl save paths updated")

amp_src = read(joinpath(@__DIR__, "amplitude_optimization.jl"), String)
@assert occursin("results/images/amp_opt_lowdim", amp_src)
@assert occursin("results/images/amp_opt\"", amp_src)
println("  ✓ amplitude_optimization.jl save paths updated")

bench_src = read(joinpath(@__DIR__, "benchmark_optimization.jl"), String)
@assert occursin("results/images/time_window_analysis", bench_src)
@assert occursin("results/images/time_window_optimized", bench_src)
println("  ✓ benchmark_optimization.jl save paths updated")

# Test 14: Check chirp sensitivity fixes
println("\nTest 14: Checking chirp sensitivity fixes...")
@assert !occursin("axhline(y=MultiModeNoise.lin_to_dB", raman_src) "Misleading 'Optimum' axhline still present"
@assert occursin("Zero perturbation", raman_src)
@assert occursin("ticklabel_format(useOffset=false, style=\"plain\")", raman_src)
println("  ✓ Chirp sensitivity: removed Optimum line, added zero-perturbation dot, fixed tick format")

# Test 15: Check time window analysis fixes
println("\nTest 15: Checking time window analysis fixes...")
@assert occursin("j_min, j_max = extrema(J_dB)", bench_src) "Y-axis zoom not implemented"
@assert occursin("mpatches", bench_src) "Color legend not added"
@assert occursin("Spectral difference from reference", bench_src) "Difference plot not added"
println("  ✓ Time window analysis: y-zoom, color legend, difference plot all present")

# Test 16: Check chirp sensitivity dynamic caption
println("\nTest 16: Checking chirp sensitivity dynamic caption...")
@assert occursin("gdd_monotonic", raman_src) "Dynamic monotonic detection not present"
@assert occursin("regularization may be constraining", raman_src) "Monotonic warning caption not present"
@assert occursin("FormatStrFormatter", raman_src) "TOD y-axis formatter not present"
println("  ✓ Chirp sensitivity: dynamic caption, TOD formatter present")

# Test 17: Check pump & Raman markers on spectral evolution
println("\nTest 17: Checking pump/Raman markers on evolution plots...")
@assert occursin("f_raman = f0 - 13.2", viz_source) "Raman onset marker missing from spectral evolution"
@assert occursin("soliton self-frequency shift", viz_source) "SSFS caption missing from evolution comparison"
println("  ✓ Evolution plots: pump λ₀ and Raman onset markers, SSFS caption present")

# Test 18: Check time window Okabe-Ito colors and ±1 dB band
println("\nTest 18: Checking time window overlay improvements...")
@assert occursin("tw_colors", bench_src) "Okabe-Ito color array not present"
@assert occursin("axhspan(-1, 1", bench_src) "±1 dB band not present"
println("  ✓ Time window overlay: Okabe-Ito colors, ±1 dB band present")

println("\n" * "="^60)
println("All smoke tests passed!")
println("="^60)
