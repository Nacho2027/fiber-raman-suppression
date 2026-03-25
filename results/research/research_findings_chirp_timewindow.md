# Chirp Sensitivity & Time Window Research Findings

## 1. Image Analysis

### 1.1 chirp_sens_L1m_P005W.png — GDD and TOD Sensitivity

**Left panel (GDD sensitivity):**
The plot shows J (dB) vs GDD perturbation, with axis labels indicating a range of -50 to +50 "fs²" and 21 data points (5 fs² step in displayed units). Key features:

- **Negative GDD region (displayed -50 to 0 fs²):** J is flat at approximately -45 dB. This is ~5 dB above the red dashed "Optimum" reference line at -50 dB.
- **Near zero (displayed 0 to +5 fs²):** J dips down to -50 dB matching the optimum line, then immediately jumps discontinuously to approximately -35 dB.
- **Positive GDD region (displayed +5 to +50 fs²):** J rises steeply to a peak of approximately -22 dB around +35 fs², then falls slightly to -25 dB at +50 fs².
- **Optimum reference line:** The red dashed line is at -50 dB, corresponding to J at zero perturbation.

The behavior is strongly asymmetric: negative GDD perturbations cause only ~5 dB degradation while positive GDD perturbations cause up to 28 dB degradation.

**Right panel (TOD sensitivity):**
The plot shows J (dB) vs TOD perturbation over a displayed range of -5000 to +5000 "fs³". Key features:

- J bounces erratically between approximately -36 dB and -50 dB with no smooth trend.
- The curve is extremely noisy — adjacent points can differ by >10 dB.
- The blue dashed "Optimum" line sits near -50 dB. Only a couple of points near TOD=0 reach this value.
- There is no discernible smooth sensitivity basin around the optimum.
- Negative TOD values tend to produce worse J (~-37 dB) than positive TOD values (~-42 dB), but this is obscured by noise.

### 1.2 time_window_analysis_L5.0m.png — Time Window Convergence

The plot shows normalized output spectrum (dB) vs frequency offset Δf (THz) for six time windows: 5, 10, 15, 20, 30, and 40 ps. All six curves are **completely identical** — they overlay exactly on top of each other. The spectrum spans roughly -8 to +5 THz with a peak near 0 THz and a slight asymmetric shoulder on the positive side (likely Raman-induced red-shift). The 5 ps window is labeled "[WARNING]" while all others are "[OK]".

This identical overlay confirms that the analysis is running **unoptimized forward propagation only**, so the unshaped 185 fs pulse (which fits easily in even a 5 ps window) produces the same output regardless of window size.

---

## 2. Chirp Sensitivity Diagnosis

### 2.1 Critical Unit Conversion Bug in Plotting

**Root cause identified:** The `plot_chirp_sensitivity` function contains a unit conversion error that affects the axis labels but NOT the underlying physics.

The code defines:
```julia
gdd_range = range(-0.05, 0.05, length=21)  # internal units: ps²
tod_range = range(-0.005, 0.005, length=21) # internal units: ps³
```

Since `sim["Δt"]` is in ps (time_window=10 ps / Nt=2^14 ≈ 6.1e-4 ps), the FFT frequencies are in THz and angular frequencies ω are in rad/ps. Therefore the GDD values are in ps² and TOD values are in ps³.

The plotting code converts:
```julia
ax1.plot(gdd_range .* 1e3, ...)   # labeled "fs²"
ax2.plot(tod_range .* 1e6, ...)   # labeled "fs³"
```

**The correct conversion factors are:**
- 1 ps² = 10⁶ fs² → should multiply by **1e6**, not 1e3
- 1 ps³ = 10⁹ fs³ → should multiply by **1e9**, not 1e6

**Both axes are off by a factor of 1000.** The true sweep ranges are:
- **GDD: ±50,000 fs²** (not ±50 fs² as displayed)
- **TOD: ±5,000,000 fs³** (not ±5,000 fs³ as displayed)

This explains much of the observed behavior. For a 185 fs sech² pulse with T₀ ≈ 105 fs (T₀² ≈ 11,000 fs²), a perturbation of ±50,000 fs² is ±4.5 × T₀² — an enormous perturbation that would dominate the pulse dynamics.

**Proposed fix for `plot_chirp_sensitivity`:**
```julia
# Replace:
ax1.plot(gdd_range .* 1e3, ...)    # WRONG: gives ps² × 1e3
ax2.plot(tod_range .* 1e6, ...)    # WRONG: gives ps³ × 1e6
# With:
ax1.plot(gdd_range .* 1e6, ...)    # CORRECT: ps² → fs²
ax2.plot(tod_range .* 1e9, ...)    # CORRECT: ps³ → fs³
```

### 2.2 GDD Discontinuity Analysis

**True sweep range:** ±50,000 fs² = ±0.05 ps² (about ±2× the fiber's own GDD of 26,000 fs²).

At this scale, the discontinuous jump is **physically expected**:

1. **Negative GDD perturbation (adds to anomalous dispersion):** The optimized phase likely contains negative GDD to pre-compensate fiber dispersion. Adding more negative GDD pushes further into anomalous territory. Since the soliton (N ≈ 1.36) already balances dispersion and nonlinearity, extra negative GDD creates a mild mismatch — the soliton self-heals by shedding dispersive radiation. The result: J degrades mildly from -50 to -45 dB. The flat response is characteristic of soliton robustness to additional anomalous chirp.

2. **Positive GDD perturbation (cancels anomalous dispersion):** Adding positive GDD first cancels the optimized negative GDD, then pushes toward normal dispersion. At ~+26,000 fs² the net dispersion crosses zero — the soliton cannot exist. Beyond this, the pulse broadens rapidly, peak power drops, Raman scattering dynamics change completely, and the cost function degrades catastrophically (up to -22 dB).

3. **The discontinuity itself:** With only 21 points over ±50,000 fs², the step size is 5,000 fs². The transition from soliton-supported to dispersion-dominated propagation occurs over a narrow GDD range near zero net dispersion, which the coarse grid under-resolves. This creates an apparent discontinuity.

**Diagnosis:** The asymmetry is physical (expected for soliton + anomalous dispersion), but the discontinuous appearance is a **sampling artifact** from coarse grid resolution near the critical GDD value.

**Does the optimum reference match J at zero perturbation?** Yes — the red dashed line at -50 dB corresponds to `J_gdd[div(length(J_gdd)+1,2)]` = J_gdd[11], the center point (zero perturbation). The curve correctly touches -50 dB at GDD=0.

**Proposed fix:**
```julia
# Increase resolution and adjust range to physically meaningful scale:
gdd_range = range(-5e-5, 5e-5, length=101)  # 101 points for smooth curve
# OR for narrower, more informative range:
gdd_range = range(-1e-5, 3e-5, length=101)  # focus on transition region
```

### 2.3 TOD Noise Analysis

**True sweep range:** ±5,000,000 fs³ = ±0.005 ps³

**Physical scale assessment:** For the 185 fs sech² pulse:
- Pulse spectral half-width: Δω ≈ 9.5 rad/ps
- Phase from TOD at pulse edge: φ = (TOD/6) × Δω³ = (0.005/6) × 865 ≈ 0.72 rad
- TOD for π phase shift at pulse edge: ~0.022 ps³ = 22,000 fs³ (true units)

So the sweep range (±5,000,000 fs³ true) is **±230× the π-phase TOD**. This is astronomically large. At these extreme TOD values, the spectral phase oscillates wildly at high frequencies, causing:

1. **Temporal pulse breakup** — the pulse develops complex sub-structure
2. **Energy leakage to window boundaries** — temporally extended features wrap around the FFT window
3. **Boundary violations** — the cost function becomes dominated by edge artifacts rather than Raman physics
4. **Non-smooth landscape** — small changes in TOD shift which sub-pulses hit the boundaries, creating erratic J variations

**Why the noise is NOT physical:** A smooth underlying sensitivity curve exists but is buried under boundary-violation artifacts. The erratic bouncing between -36 and -50 dB is characteristic of wrap-around aliasing contaminating the cost function evaluation.

**Resolution issue:** 21 points over ±0.005 ps³ gives a step of 0.0005 ps³ = 500,000 fs³ (true). At the pulse bandwidth edge, this changes the phase by 0.072 rad per step — fine resolution in phase terms. The noise is therefore NOT a resolution issue but a consequence of the absurdly large sweep range.

**Proposed fix:**
```julia
# Reduce range to physically meaningful scale (± a few π at pulse edge):
tod_range = range(-0.05e-3, 0.05e-3, length=51)  # ±50 fs³ (true), 51 points
# Or slightly wider:
tod_range = range(-0.5e-3, 0.5e-3, length=51)    # ±500 fs³ (true), 51 points
```

### 2.4 Sweep Parameters Summary

| Parameter | Current Value | Current Range (true units) | Recommended Range | Recommended Points |
|-----------|--------------|---------------------------|-------------------|--------------------|
| GDD | range(-0.05, 0.05, 21) ps² | ±50,000 fs² | ±5,000 fs² (range(-5e-3, 5e-3, 101)) | 101 |
| TOD | range(-0.005, 0.005, 21) ps³ | ±5,000,000 fs³ | ±5,000 fs³ (range(-5e-6, 5e-6, 101)) | 101 |

**Rationale for recommended ranges:**
- GDD ±5,000 fs² ≈ ±0.5 × T₀²: captures the physically interesting region where chirp meaningfully broadens the pulse without dominating the dynamics. This is also roughly ±20% of the fiber GDD.
- TOD ±5,000 fs³: approximately ±0.23 × the π-phase TOD. This range probes meaningful perturbations without causing catastrophic pulse breakup.

---

## 3. Time Window Analysis Diagnosis

### 3.1 Confirmed: Analysis Runs Unoptimized Propagation

Reading `analyze_time_windows` (benchmark_optimization.jl, lines 142–235) confirms:

1. **No optimization is performed.** The function calls `setup_raman_problem` to create the initial field `uω0`, then immediately runs forward propagation via `MultiModeNoise.solve_disp_mmf(uω0, fiber_fwd, sim)` with no phase shaping applied.
2. **The input pulse is transform-limited.** Without any spectral phase (`φ = 0`), the input sech² pulse has T_FWHM = 185 fs, occupying about ±0.3 ps in the time domain. Even with nonlinear broadening over L=5m, the unshaped pulse stays compact enough for any window ≥5 ps.
3. **The 5 ps "[WARNING]" label** comes from the edge-energy check (lines 177–183) finding edge_frac between 1e-6 and 1e-3, indicating mild boundary effects at the tightest window.
4. **All curves overlay exactly** because the same physics produces the same spectrum at all window sizes — the only difference would be if the window were small enough to cause aliasing, which it isn't for any of these sizes with an unshaped pulse.

**Conclusion:** This analysis answers the wrong question. It validates that the *unshaped* pulse doesn't need a large window (trivially true), but says nothing about what the *optimized* pulse needs. Phase-shaped pulses can have significant chirp, temporal broadening, and dispersive wave generation that requires much larger windows.

### 3.2 Proposed Redesign

The time window analysis should answer: "At what window size does the optimized solution become compromised by boundary effects?" Two approaches, in order of preference:

**Option A: Propagate the already-optimized phase at different windows (cheap, most informative)**
```julia
function analyze_time_windows_v2(φ_opt_ref, ref_sim;
    L, P, windows=[5.0, 10.0, 15.0, 20.0, 30.0, 40.0], Nt=2^13)

    for tw in windows
        # Setup problem at this window size
        uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(;
            L_fiber=L, P_cont=P, Nt=Nt, time_window=tw)

        # Interpolate reference phase to this grid (zero-pad or truncate in freq domain)
        φ_interp = interpolate_phase(φ_opt_ref, ref_sim, sim)

        # Apply optimized phase and propagate
        uω0_shaped = @. uω0 * cis(φ_interp)
        sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)

        # Check boundary conditions and cost
        # ... (same boundary check as current code)
    end
end
```
This is cheap (no optimization, just forward propagation) but tests the actual question: does the optimized pulse fit in the window?

**Option B: Run short optimization at each window (expensive, definitive)**
```julia
function analyze_time_windows_v3(; L, P, windows, max_iter=5)
    for tw in windows
        result = run_optimization(; L_fiber=L, P_cont=P,
            time_window=tw, max_iter=max_iter)  # short optimization
        # Compare J_opt across windows — convergence indicates sufficient window
    end
end
```
More expensive but shows whether the optimizer finds the same (or similar) solution at each window size. If J_opt degrades sharply below some window threshold, that's the minimum viable window.

### 3.3 Efficient Implementation for Window Sufficiency

The cheapest way to test window sufficiency without full optimization:

1. **Take the reference optimized phase** (from the best/largest-window optimization).
2. **For each candidate window size:**
   - Interpolate the phase to the new grid.
   - Run a single forward propagation with the shaped pulse.
   - Measure both the cost J and the edge energy fraction.
3. **Convergence criterion:** The window is sufficient when:
   - Edge energy fraction < 1e-6 (no boundary contamination)
   - J at this window matches J at the largest window to within 0.5 dB

This requires N_windows forward propagations (~seconds each) rather than N_windows × N_iterations optimizations.

---

## 4. Physics Assessment

### R1: Expected Chirp Sensitivity for Phase-Optimized Soliton Pulses

For soliton-order N ≈ 1.36 (our computed value) pulses in L = 1m of anomalous-dispersion fiber:

- **Fundamental solitons (N=1)** exhibit remarkable robustness to perturbations. A perturbed soliton sheds excess energy as dispersive radiation and self-heals to the nearest stable soliton. This "soliton area theorem" behavior means moderate GDD/TOD perturbations cause only gradual cost degradation.

- **Higher-order solitons (N > 1)** undergo periodic compression/expansion and can fission under perturbation. At N = 1.36, the pulse is between fundamental and second-order soliton regimes. It will propagate quasi-stably but is more sensitive to perturbations than N=1.

- **Expected GDD tolerance:** For a 185 fs pulse with T₀² ≈ 11,000 fs², perturbations of ±10% of T₀² (±1,100 fs²) should cause measurable but not catastrophic degradation. The ±10 fs² tolerance mentioned in the prompt (interpreted as the displayed axis value) is actually ±10,000 fs² in true units due to the plotting bug, which is ~±T₀² — roughly consistent with expectations for mild soliton degradation.

- **Key references:** Soliton perturbation theory (Kaup 1990), higher-order soliton fission dynamics (Husakou & Herrmann 2001), and pre-chirp management for soliton compression (Travers et al., Photonics 2021).

### R2: Physical Meaning of GDD Asymmetry

The observed asymmetric GDD sensitivity curve **matches expected soliton physics**:

- **Negative GDD direction (enhancing anomalous chirp):** The pulse accumulates additional anomalous pre-chirp. For a soliton in anomalous-dispersion fiber, this creates initial compression followed by quasi-periodic evolution. The soliton mechanism provides self-correction — the nonlinear phase shift compensates the excess dispersion. Result: mild degradation (flat at -45 dB).

- **Positive GDD direction (opposing anomalous dispersion):** The added normal-dispersion chirp cancels the native anomalous dispersion. When the net GDD approaches zero, the nonlinear length becomes the only relevant length scale, and SPM without dispersion balancing causes spectral broadening and temporal breakup. Beyond zero net GDD (normal dispersion regime), the soliton cannot form at all. Result: catastrophic degradation (up to -22 dB).

- **The asymmetry magnitude** (5 dB negative vs 28 dB positive) is physically reasonable. Solitons are much more robust to perturbations that preserve the anomalous-dispersion regime than to perturbations that destroy it.

- **The hump near +35,000 fs² (true):** This corresponds to roughly +1.3× the fiber GDD (26,000 fs²). At this point the net chirp is strongly normal, the pulse is maximally broadened, and the Raman sideband generation is most different from the optimized case. Beyond this, even more normal chirp actually reduces peak power enough that nonlinear effects (including Raman) are suppressed, causing J to partially recover.

### R3: Time Window Requirements for GNLSE with Phase Shaping

Published GNLSE simulations typically use:

- **Time window / T_FWHM ratio:** 50–200× is common for supercontinuum and soliton simulations. For T_FWHM = 185 fs, this suggests 10–40 ps windows.

- **Specific guidelines from literature:**
  - The window must accommodate the full temporal extent of all generated features (dispersive waves, Raman solitons, etc.)
  - For Raman-active propagation, walk-off between the pump and Raman-shifted components sets a lower bound: Δt_walk = |β₂| × L × Δω_Raman
  - For our parameters: walk-off at 1m ≈ 1.6 ps, at 5m ≈ 8.2 ps
  - Safety factor of 2–4× the walk-off is recommended → 3–7 ps for 1m, 16–33 ps for 5m

- **For phase-shaped pulses:** The optimized phase can introduce significant chirp, broadening the pulse by 2–10× in the time domain. The window must accommodate this broadened pulse plus any nonlinearly generated features. A conservative rule: window ≥ 4 × (walk-off + chirped pulse duration).

- **Grid resolution:** 2^13 to 2^14 points is standard. The Nyquist frequency should be at least 10× the pulse bandwidth to capture all generated spectral features.

### R4: Absorbing Boundary Alternatives

Three main approaches exist for handling finite-window artifacts in GNLSE simulations:

1. **Super-Gaussian temporal absorber:** Apply a soft damping function at each propagation step:
   ```
   W(t) = exp(-(t/t_edge)^(2n))  where n = 4–8 (super-Gaussian order)
   ```
   Applied as `u(t) → u(t) × W(t)` after each split-step. This is the most common approach in published GNLSE codes (e.g., gnlse-python, PyNLO). Advantages: simple, no reflections. Disadvantage: energy is not conserved (absorbed energy is lost).

2. **Perfectly Matched Layer (PML):** Adds a complex-valued coordinate stretch near boundaries. Well-established for FDTD/FEM methods but harder to integrate with split-step Fourier due to the inherent periodicity of the FFT. Few published GNLSE implementations use PML.

3. **Sufficiently large window:** The simplest approach — just make the window large enough that boundary effects are negligible. Combined with the edge-energy check already implemented in the code (first/last 5% of grid), this is reliable but computationally expensive for long fibers with large walk-off.

**Recommendation for this project:** Implement a super-Gaussian absorber as an option in the propagation solver. This would allow using moderate window sizes (2× walk-off instead of 4×) while preventing wrap-around artifacts. The absorber should be applied in the time domain at each split-step, with the absorption region covering the outer 10% of the grid on each side.

---

## 5. Recommended Changes (Priority Ordered)

### Priority 1: Fix unit conversion in plot_chirp_sensitivity (Critical)

**Impact:** The axis labels are wrong by 1000×, making the plots misleading. All quantitative interpretation of the sensitivity curves depends on correct units.

**Change in `plot_chirp_sensitivity` (raman_optimization.jl, line 298 and 305):**
```julia
# Line 298: Change 1e3 → 1e6
ax1.plot(gdd_range .* 1e6, MultiModeNoise.lin_to_dB.(J_gdd), "b.-")

# Line 305: Change 1e6 → 1e9
ax2.plot(tod_range .* 1e9, MultiModeNoise.lin_to_dB.(J_tod), "r.-")
```

### Priority 2: Reduce sweep ranges to physically meaningful scales (High)

**Impact:** Current ranges are 2–230× the physically meaningful scale, producing boundary artifacts and misleading results.

**Change in `chirp_sensitivity` defaults (raman_optimization.jl, lines 263–264):**
```julia
# From:
gdd_range = range(-0.05, 0.05, length=21)
tod_range = range(-0.005, 0.005, length=21)

# To:
gdd_range = range(-5e-3, 5e-3, length=101)    # ±5,000 fs² ≈ ±0.5 T₀²
tod_range = range(-5e-6, 5e-6, length=101)     # ±5,000 fs³, meaningful TOD perturbation
```

### Priority 3: Redesign time window analysis to test optimized pulses (High)

**Impact:** Current analysis is useless — it tests unshaped pulses that trivially fit any window.

**Change:** Add a new function `analyze_time_windows_optimized` that:
1. Accepts a reference optimized phase φ_opt and its grid parameters
2. Interpolates the phase to each candidate window's grid
3. Runs forward propagation with the shaped pulse
4. Reports edge energy and J at each window size

### Priority 4: Increase sweep point count (Medium)

**Impact:** Even with corrected ranges, 21 points is insufficient to resolve the GDD transition region. 101 points gives 50× better resolution with negligible additional runtime (each point is one forward propagation ≈ 0.1–1 s).

### Priority 5: Add super-Gaussian absorbing boundary option (Low)

**Impact:** Would reduce required time windows by ~2× and eliminate edge artifacts in sensitivity sweeps and optimization. Lower priority because correct window sizing (Priority 3) mostly addresses the problem.

**Implementation sketch:** In the split-step propagation loop, add an optional damping step:
```julia
if use_absorber
    t_grid = range(-tw/2, tw/2, length=Nt)
    W = @. exp(-(t_grid / (0.45 * tw))^16)  # super-Gaussian, order 8
    ut .= ut .* W  # apply after each time-domain step
end
```

### Priority 6: Add asymmetric GDD sweep option (Low)

**Impact:** Since the sensitivity is inherently asymmetric, an asymmetric sweep range would be more informative: e.g., GDD from -2,000 fs² to +10,000 fs² with denser sampling near the transition.
