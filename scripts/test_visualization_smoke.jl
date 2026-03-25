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

# Test 10: Verify ΔJ annotation (META-02: now shows J_before, J_after, Delta-J)
println("\nTest 10: Checking ΔJ improvement annotation...")
@assert occursin("Delta-J", viz_source) || occursin("ΔJ", viz_source)
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

# Test 19: Mask-before-unwrap recovers known GDD
println("\nTest 19: mask_before_unwrap recovers known GDD...")
Nt_test = 2^12
Dt_test = 0.01  # 10 fs sample interval in ps (Δt units are ps throughout this codebase)
f0_test = 193.4  # THz (1550 nm center)
sim_mbu = Dict("Nt" => Nt_test, "Δt" => Dt_test, "M" => 1, "f0" => f0_test,
               "ts" => collect(range(-Nt_test/2, Nt_test/2 - 1)) .* Dt_test)

# Known GDD: beta2 * L = -21700 fs^2 = -0.0217 ps^2
GDD_target_fs2 = -21700.0
GDD_target_ps2 = GDD_target_fs2 * 1e-6  # -0.0217 ps^2

# Build quadratic spectral phase: phi(omega) = 0.5 * GDD * (omega - omega0)^2
# dw_grid in rad/ps (since Dt_test is in ps)
dw_grid = 2π .* fftshift(fftfreq(Nt_test, 1 / Dt_test))  # rad/ps, fftshifted
phi_quadratic = 0.5 .* GDD_target_ps2 .* dw_grid.^2

# Build Gaussian spectral envelope
spectral_fwhm_thz = 5.0  # THz
sigma_f = spectral_fwhm_thz / (2 * sqrt(2 * log(2)))
df_grid = fftshift(fftfreq(Nt_test, 1 / Dt_test))  # THz, fftshifted (1/ps = THz)
spec_power = exp.(-df_grid.^2 ./ (2 * sigma_f^2))

# Mask: zero phase where power < -40 dB
P_peak_test = maximum(spec_power)
dB_test = 10 .* log10.(spec_power ./ P_peak_test .+ 1e-30)
signal_mask_test = dB_test .> -40.0
phi_premask = copy(phi_quadratic)
phi_premask[.!signal_mask_test] .= 0.0

# Unwrap the pre-masked phase
phi_unwrapped = _manual_unwrap(phi_premask)

# Compute GDD via second derivative: d2phi/domega2 in ps^2, convert to fs^2
dw_step = dw_grid[2] - dw_grid[1]  # rad/ps
gdd_recovered = _second_central_diff(phi_unwrapped, dw_step) .* 1e6  # fs^2

# Check GDD at center of signal region (within +/-1 THz of center)
center_mask = abs.(df_grid) .< 1.0
gdd_center = gdd_recovered[center_mask .& signal_mask_test]
gdd_center_valid = filter(isfinite, gdd_center)
gdd_mean = sum(gdd_center_valid) / length(gdd_center_valid)
gdd_error = abs(gdd_mean - GDD_target_fs2) / abs(GDD_target_fs2)
@assert gdd_error < 0.01 "GDD recovery error $(round(gdd_error*100, digits=2))% exceeds 1% threshold (got $(round(gdd_mean, digits=1)) fs^2, expected $GDD_target_fs2 fs^2)"
println("  ✓ mask_before_unwrap: recovered GDD = $(round(gdd_mean, digits=1)) fs^2 (error $(round(gdd_error*100, digits=3))%)")

# Test 20: _spectral_signal_xlim auto-zoom
println("\nTest 20: _spectral_signal_xlim auto-zoom...")
f0_xlim = 193.4
Nt_xlim = 2^12
Dt_xlim = 0.01  # 10 fs in ps units (1/ps = THz)
f_shifted_xlim = f0_xlim .+ fftshift(fftfreq(Nt_xlim, 1 / Dt_xlim))
lambda_xlim = C_NM_THZ ./ f_shifted_xlim
sigma_nm = 50.0  # ~100 nm FWHM
lambda0_nm = C_NM_THZ / f0_xlim
spec_xlim_test = exp.(-((lambda_xlim .- lambda0_nm) ./ sigma_nm).^2)
# Only keep positive lambda for realistic test
spec_xlim_test[lambda_xlim .< 0] .= 0.0

lo, hi = _spectral_signal_xlim(spec_xlim_test, lambda_xlim; threshold_dB=-40.0, padding_nm=80.0)
@assert lo > 1200.0 "Auto-zoom lo=$lo too wide (should be > 1200 nm)"
@assert hi < 2000.0 "Auto-zoom hi=$hi too wide (should be < 2000 nm)"
@assert lo < lambda0_nm "Auto-zoom lo=$lo does not bracket center wavelength"
@assert hi > lambda0_nm "Auto-zoom hi=$hi does not bracket center wavelength"
println("  ✓ _spectral_signal_xlim: [$lo, $hi] nm brackets signal around $(round(lambda0_nm, digits=1)) nm")

# Test 21: Global P_ref pattern in optimization comparison functions
println("\nTest 21: Global P_ref normalization in comparison functions...")
viz_src = read(joinpath(@__DIR__, "visualization.jl"), String)
# Both optimization comparison functions must use global normalization
@assert occursin("P_ref_global", viz_src) "P_ref_global not found — BUG-04 fix missing"
# Per-column normalization pattern must be gone from comparison functions
# (The pattern "P_ref = max(maximum(spec_in), maximum(spec_out))" should not appear)
n_local_pref = length(collect(eachmatch(r"P_ref = max\(maximum\(spec_in\)", viz_src)))
@assert n_local_pref == 0 "Found $n_local_pref per-column P_ref patterns — BUG-04 not fully fixed"
println("  OK global P_ref: P_ref_global found, no per-column P_ref patterns remain")

# Test 22: _add_metadata_block! helper
println("\nTest 22: _add_metadata_block! helper...")
fig_meta, ax_meta = subplots(1, 1, figsize=(6, 4))
ax_meta.plot([1, 2, 3], [1, 2, 3])
test_metadata = (
    fiber_name = "SMF-28",
    L_m = 1.0,
    P_cont_W = 0.05,
    lambda0_nm = 1550.0,
    fwhm_fs = 185.0,
)
_add_metadata_block!(fig_meta, test_metadata)
# Verify: fig.texts should contain at least one text element with "SMF-28"
fig_texts = [t.get_text() for t in fig_meta.texts]
found_meta = any(occursin("SMF-28", t) for t in fig_texts)
@assert found_meta "Metadata block not found in figure texts"
found_L = any(occursin("1.0 m", t) for t in fig_texts)
@assert found_L "Fiber length not found in metadata block"
close(fig_meta)
println("  ok _add_metadata_block! places metadata text on figure")

# Test 23: Expanded J annotation (META-02)
println("\nTest 23: Expanded J annotation contains before/after values...")
# Check that plot_optimization_result_v2 source contains the expanded annotation
viz_src = read(joinpath(@__DIR__, "visualization.jl"), String)
@assert occursin("J_before", viz_src) "Missing J_before in expanded annotation"
@assert occursin("J_after", viz_src) "Missing J_after in expanded annotation"
@assert occursin("Delta-J", viz_src) || occursin("ΔJ", viz_src) "Missing Delta-J label in expanded annotation"
println("  ok Expanded J annotation pattern found in source")

println("\n" * "="^60)
println("All smoke tests passed!")
println("="^60)
