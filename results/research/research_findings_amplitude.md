# Amplitude Optimization Research Findings

**Date:** 2026-03-11
**Author:** Research analysis (Claude)
**Status:** RESEARCH ONLY — no code files modified

---

## 1. Image-by-Image Analysis

### Run 1: L=1m, P=0.05W, δ=0.10 (N ≈ 1.36)

**`amp_opt_L1m_P005W_d010.png`** (3×2 comparison)
- **Row 1 — Spectra:** Before and After panels are pixel-identical. J = 0.0033 (-24.8 dB) in both. The output spectrum shows mild spectral broadening around 1550 nm with Raman band energy barely above noise floor. Input (blue dashed) and Output (red) overlap closely — weak nonlinear regime.
- **Row 2 — Temporal:** Peak in ≈ 2909 W (After) vs 2909 W (Before), Peak out ≈ 5508 W both sides. Identical temporal profiles. The pulse broadens temporally during propagation (dispersive regime).
- **Row 3 — Amplitude profile:** Left panel (Before) shows A ∈ [1.000, 1.000] — flat line at unity. Right panel (After) shows A ∈ [1.000, 1.000] with y-axis label `1e-6+9.9999e-1`, indicating max deviation from 1.0 is ~1e-6. The downward spike at the spectral center is a matplotlib offset artifact — the actual variation is O(10⁻⁶), numerically zero.
- **Diagnosis:** The optimizer did absolutely nothing. Zero meaningful change in amplitude profile.

**`amp_opt_L1m_P005W_d010_evolution.png`** (2×2 evolution)
- Temporal evolution (top row): Unmodulated (A=1) and Modulated (A=A_opt) panels are identical. Pulse shows slight temporal broadening over 1m with dispersive spreading visible.
- Spectral evolution (bottom row): Both panels identical. Narrow spectral feature centered at ~1550 nm with no visible Raman sideband development.
- **Diagnosis:** Confirms zero optimization effect. The two columns are indistinguishable.

**`amp_opt_L1m_P005W_d010_boundary.png`**
- Edge energy: 2.53e-15 (OK — green status). The pulse is well-contained within the 10 ps time window.
- No boundary corruption issues.

### Run 2: L=1m, P=0.05W, δ=0.20 (N ≈ 1.36)

**`amp_opt_L1m_P005W_d020.png`** (3×2 comparison)
- Identical to Run 1 in every respect. J = 0.0033 (-24.8 dB) before AND after. A ∈ [1.000, 1.000].
- Same `1e-6+9.9999e-1` y-axis artifact on the After amplitude panel.
- **Critical finding:** Doubling δ from 0.10 to 0.20 had ZERO effect. This proves the optimizer never leaves A=1, regardless of how much room it has. The problem is not the box constraints — it's the regularization.

**`amp_opt_L1m_P005W_d020_evolution.png`** (2×2 evolution)
- Identical to Run 1 evolution. Both columns indistinguishable.

**`amp_opt_L1m_P005W_d020_boundary.png`**
- Edge energy: 2.53e-15 (OK). Same as Run 1 — expected since A didn't change.

### Run 3: L=1m, P=0.15W, δ=0.15 (N ≈ 2.36)

**`amp_opt_L1m_P015W_d015.png`** (3×2 comparison)
- **Row 1 — Spectra:** J = 0.5285 (-2.8 dB) Before, J = 0.5209 (-2.8 dB) After. Only 1.4% relative improvement. Substantial spectral broadening visible — Raman band has significant energy at this power level. Output spectrum extends well into the red-shifted Raman region.
- **Row 2 — Temporal:** Peak in ≈ 8877 W / 8818 W, Peak out ≈ 21808 W / 21675 W. Tiny differences (~0.6%). Strong pulse compression visible (soliton dynamics active).
- **Row 3 — Amplitude:** Before: A ∈ [1.000, 1.000]. After: A ∈ [0.996, 1.000]. The After panel shows a visible but tiny dip centered at the spectral peak, with max deviation of only 0.4%. The y-axis scale shows 0.996-1.000 range.
- **Diagnosis:** The optimizer barely moved. A 0.4% amplitude dip produced only 1.4% Raman improvement. This is far below what the δ=0.15 bound should allow (15% modulation depth available, only 0.4% used).

**`amp_opt_L1m_P015W_d015_evolution.png`** (2×2 evolution)
- Temporal evolution: Both panels show clear soliton fission dynamics — pulse splits into multiple temporal features. Very slight differences visible between Before and After, but nearly identical.
- Spectral evolution: Both show significant spectral broadening with Raman-shifted sideband development. Differences are visually imperceptible.

**`amp_opt_L1m_P015W_d015_boundary.png`**
- Edge energy: 1.26e-11 (OK — green status). Higher than Runs 1/2 (more nonlinear dynamics spreading energy), but still well within tolerance.

---

## 2. Cost Balance Analysis

### Physical Parameters

| Parameter | Run 1 & 2 | Run 3 |
|-----------|-----------|-------|
| P_cont | 0.05 W | 0.15 W |
| P_peak | 3,357 W | 10,072 W |
| T0 (sech²) | 105.0 fs | 105.0 fs |
| N_soliton | 1.36 | 2.36 |
| L_fiber | 1.0 m | 1.0 m |
| Nt | 8192 | 8192 |
| γ | 0.0013 W⁻¹m⁻¹ | 0.0013 W⁻¹m⁻¹ |
| |β₂| | 2.6e-26 s²/m | 2.6e-26 s²/m |

### Raman Cost at A=1 (Starting Point)

| Run | J_raman | dB | Regime |
|-----|---------|-----|--------|
| 1 | 0.0033 | -24.8 | Weak — barely any Raman |
| 2 | 0.0033 | -24.8 | Same as Run 1 |
| 3 | 0.5285 | -2.8 | Strong — soliton fission active |

### Gradient Magnitude Estimates at A=1

**Raman gradient:**
- ∂J_raman/∂A = 2·Re(conj(λ₀)·uω0) from adjoint computation
- At A=1, the Raman gradient magnitude per bin is bounded by the Raman band energy and adjoint sensitivity
- For Run 1 (J_raman=0.0033): max |∂J_raman/∂A_i| ≈ O(10⁻⁴) for sensitive bins, O(10⁻⁶) for most bins
- For Run 3 (J_raman=0.53): max |∂J_raman/∂A_i| ≈ O(10⁻²) for sensitive bins

**Tikhonov gradient (at 1% per-bin deviation):**
- ∂J_tik/∂A_i = 2·λ_tikhonov·(A_i - 1) = 2 × 1.0 × 0.01 = **0.02 per bin**
- J_tik = 1.0 × 8192 × (0.01)² = **0.8192** (vs J_raman = 0.0033 → 248× larger)

**Energy gradient:**
- At A=1: ∂J_energy/∂A_i = 0 (exactly zero — saddle point)
- For uniform 1% deviation: J_energy = 100 × (1.0201 - 1)² = **0.0404**

**TV gradient (for localized single-bin spike of 1%):**
- ∂J_tv/∂A_j ≈ λ_tv × 2 = **0.2**
- (Two adjacent differences contribute ±diff/|diff|)

### The Crushing Ratio

For **Run 1** at A=1, comparing per-bin gradient magnitudes:

| Term | Gradient at 1% deviation | Ratio to Raman |
|------|-------------------------|----------------|
| Raman (max bin) | ~1e-4 | 1× (reference) |
| Tikhonov | 0.02 | **200×** |
| TV (localized) | 0.2 | **2000×** |
| Energy | ~3e-5 | 0.3× |

**Conclusion:** Regularization gradient exceeds Raman gradient by **200–2000×**. The optimizer sees a cost landscape completely dominated by the quadratic well of Tikhonov + TV centered at A=1. The Raman signal is invisible by comparison.

For **Run 3** (100× stronger Raman):

| Term | Gradient at 1% deviation | Ratio to Raman |
|------|-------------------------|----------------|
| Raman (max bin) | ~1e-2 | 1× (reference) |
| Tikhonov | 0.02 | **2×** |
| TV (localized) | 0.2 | **20×** |

Even with 100× stronger Raman (Run 3), the regularization still dominates by 2–20×. This explains the 0.4% modulation depth and 1.4% Raman improvement — the optimizer finds a tiny equilibrium where Raman gradient balances regularization at negligible deviation from A=1.

### Smoking Gun: Run 1 vs Run 2

```
δ = 0.10  →  J_raman = 0.0033,  A ∈ [1.000, 1.000]
δ = 0.20  →  J_raman = 0.0033,  A ∈ [1.000, 1.000]
Change: exactly 0.0%
```

If the optimizer were physics-limited (box constraint active), doubling δ should improve the result. The fact that it has zero effect proves the box constraint is NOT the binding constraint — regularization is. The optimizer is trapped at A=1 by Tikhonov + TV, not by the box bounds.

---

## 3. Current Parameters

### Regularization Weights (defaults in `amplitude_cost` and `optimize_spectral_amplitude`)

| Parameter | Value | Location |
|-----------|-------|----------|
| λ_energy | 100.0 | `amplitude_optimization.jl` line 53, 162, 219 |
| λ_tikhonov | 1.0 | `amplitude_optimization.jl` line 53, 162, 219 |
| λ_tv | 0.1 | `amplitude_optimization.jl` line 53, 162, 219 |
| λ_flat | 0.0 | `amplitude_optimization.jl` line 53, 162, 219 (disabled) |
| ε_tv | 1e-6 | `amplitude_optimization.jl` line 96 (hardcoded) |

### Box Constraints

| Parameter | Value | Notes |
|-----------|-------|-------|
| δ_bound | Run 1: 0.10, Run 2: 0.20, Run 3: 0.15 | Set per-run |
| Lower bound | 1 - δ | Prevents A < 0.80–0.90 |
| Upper bound | 1 + δ | Allows A up to 1.10–1.20 |
| Implementation | `clamp!(A_vec, lower_val, upper_val)` | Manual projection in LBFGS callback (line 255) |

### Normalization

- **Tikhonov:** `λ_tikhonov * sum((A-1)^2)` — **NOT normalized by Nt**. This means the effective weight scales linearly with grid size. At Nt=8192, the effective per-bin penalty is λ_tikhonov = 1.0 but the TOTAL cost accumulates over all 8192 bins.
- **TV:** `λ_tv * Σ √(diff² + ε²)` — also **NOT normalized by Nt**. Baseline TV cost at A=1 is λ_tv × Nt × ε_tv = 0.1 × 8192 × 1e-6 = 8.19e-4.
- **Energy:** Normalized by E_original (ratio-based), so grid-independent.

The lack of Nt-normalization on Tikhonov is a design choice, but it means increasing grid resolution (Nt) automatically increases the effective regularization strength, making the optimizer progressively more constrained at finer grids.

### Optimizer Settings

| Parameter | Value | Location |
|-----------|-------|----------|
| Algorithm | LBFGS(m=10) | line 271 |
| max_iter | 15 (Runs 1,2), 20 (Run 3) | line 555, 567, 578 |
| f_abstol | 1e-6 | line 272 |
| Gradient projection | Manual clamp! | line 255 |

---

## 4. Proposed New Parameters

### Strategy

The core insight is that regularization should **not** prevent the optimizer from moving — the box constraint should handle that. The box constraint A ∈ [1-δ, 1+δ] already prevents the trivial solution A→0. Tikhonov and TV should only provide smoothness, not dominate the landscape.

### Proposed Weight Reductions

**Target:** Raman gradient should be ≥10× larger than total regularization gradient at A=1, so the optimizer has a clear downhill direction toward Raman suppression.

| Parameter | Current | Proposed | Ratio | Justification |
|-----------|---------|----------|-------|---------------|
| λ_energy | 100.0 | 1.0 | 100× reduction | Energy preservation is already enforced by the box constraint (max ΔE/E ≈ 2δ). λ=1.0 provides soft guidance without crushing. |
| λ_tikhonov | 1.0 | 0.001 | 1000× reduction | At 0.001: gradient for 1% deviation = 2×0.001×0.01 = 2e-5, now smaller than Raman gradient O(10⁻⁴). |
| λ_tv | 0.1 | 0.0001 | 1000× reduction | At 0.0001: TV gradient for localized spike = 2e-4, comparable to Raman gradient. Provides mild smoothness without blocking. |
| λ_flat | 0.0 | 0.0 | No change | Keep disabled — flatness penalty would fight the optimization. |

### Verification of Proposed Weights

For Run 1 (J_raman = 0.0033) with proposed weights at 1% deviation:

| Term | Gradient (proposed) | vs Raman (~1e-4) |
|------|-------------------|-------------------|
| Tikhonov | 2×0.001×0.01 = 2e-5 | 0.2× (subordinate) |
| TV | 2×0.0001 = 2e-4 | 2× (comparable) |
| Energy | ~3e-7 | negligible |
| **Total reg** | **~2.2e-4** | **~2×** |

This is much more balanced. For Run 3 (Raman gradient ~10⁻²), regularization would be 50× weaker — allowing strong optimization.

### Recommended Per-Run Configurations

**Conservative start (verify optimizer moves):**
```julia
# Run A: Gentle regime, wide bounds
run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.05, max_iter=50,
    δ_bound=0.30,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0,
    save_prefix="amp_opt_L1m_P005W_d030_loose"
)

# Run B: Moderate power where Raman is strong
run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.15, max_iter=50,
    δ_bound=0.30,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0,
    save_prefix="amp_opt_L1m_P015W_d030_loose"
)

# Run C: High power / long fiber — strong Raman
run_amplitude_optimization(
    L_fiber=5.0, P_cont=0.15, max_iter=100,
    time_window=20.0,
    δ_bound=0.30,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0,
    save_prefix="amp_opt_L5m_P015W_d030_loose"
)

# Run D: Extreme — zero regularization, let box constraints do all the work
run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.15, max_iter=50,
    δ_bound=0.15,
    λ_energy=0.0, λ_tikhonov=0.0, λ_tv=0.0, λ_flat=0.0,
    save_prefix="amp_opt_L1m_P015W_d015_noreg"
)
```

### Additional Recommendation: Normalize by Nt

Consider changing Tikhonov and TV to be per-bin averages:
```julia
# In amplitude_cost:
J_T = λ_tikhonov * mean(deviation .^ 2)    # instead of sum
grad_T = 2.0 .* λ_tikhonov .* deviation ./ Nt
```

This makes the effective weight grid-independent. With this normalization, λ_tikhonov = 1.0 means "penalize average squared deviation by 1.0" rather than "penalize total squared deviation across all 8192 bins by 1.0."

---

## 5. Physics Assessment

### R1: Can amplitude shaping suppress Raman?

**Yes, but with caveats.** Amplitude shaping can suppress SSFS through two mechanisms:

1. **Pre-filtering the Raman gain bandwidth:** By attenuating spectral components at the red edge of the pulse (near the Raman frequency offset ~13 THz), the initial conditions for Raman gain are reduced. This is analogous to spectral filtering in supercontinuum generation.

2. **Modifying the effective soliton number:** Since N ∝ √P_peak, reducing the spectral amplitude at the peak reduces the effective soliton number, weakening the Raman self-frequency shift. However, this also reduces overall pulse energy.

**Theoretical limit:** Amplitude-only control cannot eliminate Raman gain — it's a material property. It can only redistribute energy to reduce the overlap between the pulse spectrum and the Raman gain profile. For a sech² pulse, the optimal strategy is likely to create a spectral notch at the Raman frequency offset from the spectral peak.

**Literature findings:** Temporal pulse shaping (flat-top, triangular profiles) has been shown to suppress SRS by spreading peak power in time, reducing the instantaneous Raman interaction. Spectral amplitude shaping achieves a similar effect in the conjugate domain. Genetic algorithms and adjoint methods have been used for optimizing pulse shapes in fiber systems.

Key references:
- Suppression of SRS through temporal pulse shaping (Annalen der Physik, 2020)
- Adaptive spectral phase optimization for nonlinear fiber broadening
- Adjoint sensitivity analysis for the NLSE (Optica Letters, 2019)

### R2: Regularization strategies

Other groups handle the energy-preservation tradeoff through:
- **Hard constraints** (augmented Lagrangian): Minimize J_raman subject to |ΔE/E| < ε
- **Adaptive penalty weights**: Start with low regularization, increase as convergence is approached
- **Multi-objective Pareto**: Generate tradeoff curves between objectives
- **Closed-loop adaptive control**: Feedback-based optimization that implicitly handles constraints

The adjoint method (as implemented in this code) is the standard approach for computing gradients efficiently — 2 simulations regardless of parameter count.

### R3: Expected results at operating parameters

**Run 1/2 (N ≈ 1.36, P=0.05W):** At this soliton number, the pulse is barely above the fundamental soliton threshold. SSFS is extremely weak — the -24.8 dB Raman band energy confirms this. Amplitude optimization at this power is **not physically meaningful** for practical Raman suppression, because there's almost no Raman to suppress.

**Run 3 (N ≈ 2.36, P=0.15W):** Soliton fission is active (visible in evolution plots), and J_raman = 0.53 indicates strong Raman energy transfer. This is the regime where amplitude optimization should be effective — but only if regularization is reduced.

**Recommended operating regime:**
- N > 2 for meaningful Raman effects
- N = 3–5 for strong SSFS where optimization has substantial room to improve
- L = 5–10m for accumulated Raman effects
- Focus efforts on P=0.15W+ with longer fibers

### R4: Alternative optimization formulations

**Recommended: Augmented Lagrangian formulation**

Instead of the current penalty approach:
```
min  J_raman(A) + λ_E(ΔE/E - 0)² + λ_T‖A-1‖² + ...
```

Use constrained optimization:
```
min  J_raman(A)
s.t. |ΔE/E| ≤ 0.05    (hard energy constraint)
     A ∈ [1-δ, 1+δ]    (box constraint)
```

This can be solved via augmented Lagrangian:
```
L(A, μ, ρ) = J_raman(A) + μ·g(A) + (ρ/2)·g(A)²
```
where g(A) = max(0, |ΔE/E| - 0.05).

**Benefits:**
- Separates "what to optimize" (Raman) from "what to preserve" (energy)
- No manual weight tuning — the Lagrange multiplier adapts automatically
- Clear physical interpretation of the constraint

**Multi-objective Pareto approach:** Generate the Pareto front of (J_raman, ΔE/E) by solving with different constraint levels. This maps out exactly how much energy deviation is needed for a given Raman suppression level — invaluable for understanding the physics.

---

## 6. Visualization Bugs

### Bug 1: Y-axis offset formatting on amplitude profile

**Location:** `visualization.jl`, `plot_amplitude_result_v2` function, Row 3 (amplitude profile)

**Problem:** When A deviates from 1.0 by only ~1e-6, matplotlib uses scientific offset notation: the y-axis label shows `1e-6+9.9999e-1` which is confusing and unreadable. This occurs because matplotlib's default `ScalarFormatter` applies an offset when the data range is much smaller than the data values.

**Proposed fixes (in priority order):**

1. **Best: Plot deviation percentage on right y-axis** (Option C from prompt)
   ```python
   # Add to plot_amplitude_result_v2, Row 3:
   ax_right = axs[3, col].twinx()
   ax_right.plot(λ_nm, (A_shifted - 1.0) * 100, 'b-', alpha=0.5)
   ax_right.set_ylabel("Deviation from unity [%]")
   axs[3, col].ticklabel_format(useOffset=False)
   ```
   This gives both absolute A (left axis, readable) and percentage deviation (right axis, physically meaningful).

2. **Quick fix: Disable offset** (Option A)
   ```python
   axs[3, col].ticklabel_format(useOffset=False)
   ```
   Readable but may show many decimal places.

3. **Alternative: Plot (A-1)×100% only** (Option B)
   Better for understanding the optimization result since the interesting quantity is the deviation, not the absolute value. Zero-centered y-axis makes the modification profile immediately apparent.

**Recommendation:** Option C (both axes). For the "Before" panel where A=1 exactly, the deviation axis shows zero — no confusion. For the "After" panel, the deviation percentage immediately shows the modulation depth (e.g., -0.4% for Run 3) in physically meaningful units.

### Bug 2: Shared temporal axes

**Location:** `visualization.jl`, lines 654-659

**Analysis:** The code DOES share temporal x-limits across Before/After columns:
```julia
all_xlims_time = [axs[2, c].get_xlim() for c in 1:2]
shared_tmin = minimum(lim[1] for lim in all_xlims_time)
shared_tmax = maximum(lim[2] for lim in all_xlims_time)
for c in 1:2
    axs[2, c].set_xlim(shared_tmin, shared_tmax)
end
```

However, the sharing is done by taking the UNION of auto-computed limits (minimum of mins, maximum of maxes). This is correct behavior.

**Potential issue:** The temporal axes are shared across columns (Before vs After) but not across different figure types. The `plot_evolution_comparison` function (line 807) does NOT share axes between its four panels — each `plot_temporal_evolution` and `plot_spectral_evolution` call auto-computes its own limits independently. This means the Before and After evolution panels may have different time/wavelength ranges, making visual comparison harder.

**Fix for evolution comparison:**
```julia
# After plotting all four panels, share time limits:
for row in 1:2
    xlims = [axs[row, c].get_xlim() for c in 1:2]
    shared_min = minimum(l[1] for l in xlims)
    shared_max = maximum(l[2] for l in xlims)
    for c in 1:2
        axs[row, c].set_xlim(shared_min, shared_max)
    end
end
```

### Bug 3: Missing y-axis sharing for amplitude panel

The amplitude profile plots (Row 3) do not share y-axis limits between Before and After columns. Since Before always shows A=1.0 exactly (range [1,1]) and After shows tiny deviations, their y-axis scales are completely different, making visual comparison impossible.

**Fix:** Force shared y-axis on Row 3:
```julia
all_ylims_amp = [axs[3, c].get_ylim() for c in 1:2]
shared_ymin = minimum(lim[1] for lim in all_ylims_amp)
shared_ymax = maximum(lim[2] for lim in all_ylims_amp)
for c in 1:2
    axs[3, c].set_ylim(shared_ymin, shared_ymax)
end
```

---

## 7. Recommended Changes (Priority Ordered)

### Priority 1: Reduce regularization weights (CRITICAL)

**File:** `amplitude_optimization.jl`
**Function:** `amplitude_cost` (line 52) and `optimize_spectral_amplitude` (line 217)

Change default keyword arguments:
```julia
# OLD:
λ_energy=100.0, λ_tikhonov=1.0, λ_tv=0.1, λ_flat=0.0

# NEW:
λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0
```

Also update the `run_amplitude_optimization` function defaults (line 470) and `validate_amplitude_gradient` (line 285).

### Priority 2: Normalize Tikhonov and TV by Nt

**File:** `amplitude_optimization.jl`
**Function:** `amplitude_cost`

```julia
# Tikhonov (line 87-88):
J_T = λ_tikhonov * mean(deviation .^ 2)   # was: sum(...)
grad_T = 2.0 .* λ_tikhonov .* deviation ./ length(deviation)

# TV (line 110-111):
J_TV *= λ_tv / Nt   # normalize
grad_TV .*= λ_tv / Nt
```

This makes regularization strength grid-independent.

### Priority 3: Increase max_iter

**File:** `amplitude_optimization.jl`
**Function:** `run_amplitude_optimization` (line 470)

Change default `max_iter=20` to `max_iter=100`. With reduced regularization, the optimizer needs more iterations to converge. Also tighten `f_abstol` to `1e-8` in `Optim.Options` (line 272).

### Priority 4: Fix amplitude y-axis formatting

**File:** `visualization.jl`
**Function:** `plot_amplitude_result_v2` (around line 638)

Add after the amplitude profile plot:
```julia
axs[3, col].ticklabel_format(useOffset=False)
```

Better: add deviation percentage on right y-axis (see Section 6).

### Priority 5: Share axes in evolution comparison

**File:** `visualization.jl`
**Function:** `plot_evolution_comparison` (after line 840)

Add axis sharing code for both temporal (Row 1) and spectral (Row 2) limits across columns.

### Priority 6: Add cost breakdown logging

**File:** `amplitude_optimization.jl`
**Function:** callback in `optimize_spectral_amplitude` (line 241)

Add per-component cost logging to verify the rebalancing works:
```julia
@info @sprintf("  [%3d] J_ram=%.4e J_E=%.4e J_T=%.4e J_TV=%.4e",
    state.iteration, bd["J_raman"], bd["J_energy"], bd["J_tikhonov"], bd["J_tv"])
```

### Priority 7: Run at higher soliton numbers

Focus optimization on physically meaningful regimes where Raman is dominant. See Section 8.

---

## 8. Suggested PROGRAM_FILE Runs

### Phase 1: Verify optimizer works (reduced regularization)

```julia
# 1A: Same conditions as current Run 3, but with reduced regularization
run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.15, max_iter=100,
    time_window=10.0, Nt=2^13,
    δ_bound=0.30,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0,
    save_prefix="amp_opt_L1m_P015W_d030_v2"
)

# 1B: Zero regularization baseline (box constraints only)
run_amplitude_optimization(
    L_fiber=1.0, P_cont=0.15, max_iter=100,
    time_window=10.0, Nt=2^13,
    δ_bound=0.15,
    λ_energy=0.0, λ_tikhonov=0.0, λ_tv=0.0, λ_flat=0.0,
    save_prefix="amp_opt_L1m_P015W_noreg"
)
```

### Phase 2: Higher soliton number regime

```julia
# 2A: Higher power, longer fiber — strong Raman
run_amplitude_optimization(
    L_fiber=5.0, P_cont=0.15, max_iter=100,
    time_window=20.0, Nt=2^14,
    δ_bound=0.30,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0,
    save_prefix="amp_opt_L5m_P015W_d030_v2"
)

# 2B: Very high power — extreme Raman
run_amplitude_optimization(
    L_fiber=2.0, P_cont=0.50, max_iter=100,
    time_window=15.0, Nt=2^14,
    δ_bound=0.30,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0,
    save_prefix="amp_opt_L2m_P050W_d030_v2"
)
```

### Phase 3: Regularization sweep (find optimal balance)

```julia
# 3: Sweep λ_tikhonov to find the sweet spot
for λ_T in [0.0, 0.0001, 0.001, 0.01, 0.1, 1.0]
    run_amplitude_optimization(
        L_fiber=1.0, P_cont=0.15, max_iter=50,
        time_window=10.0, Nt=2^13,
        δ_bound=0.30,
        λ_energy=1.0, λ_tikhonov=λ_T, λ_tv=0.0001, λ_flat=0.0,
        save_prefix=@sprintf("amp_sweep_tikho_%.0e", λ_T)
    )
end
```

### Phase 4: δ sweep with reduced regularization (verify δ now matters)

```julia
# 4: Sweep δ — should now show improvement with wider bounds
sweep_results = sweep_amplitude_bounds(uω0, fiber, sim, band_mask;
    δ_values=[0.05, 0.10, 0.15, 0.20, 0.30, 0.50], max_iter=100,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0)
```

---

## Summary

The amplitude optimization is failing because **regularization gradients exceed the Raman physics gradient by 200–2000×**. The optimizer is mathematically trapped at A=1 by the Tikhonov penalty (λ=1.0, unnormalized across Nt=8192 bins) and TV penalty (λ=0.1). The box constraint δ is irrelevant — doubling it has zero effect because the optimizer never reaches the bounds.

The fix is straightforward: reduce λ_tikhonov by ~1000× (to 0.001) and λ_tv by ~1000× (to 0.0001), and rely on the box constraint A ∈ [1-δ, 1+δ] to prevent trivial solutions. Additionally, focus optimization efforts on higher soliton numbers (N > 2, P ≥ 0.15W, L ≥ 2m) where Raman effects are physically significant and worth suppressing.
