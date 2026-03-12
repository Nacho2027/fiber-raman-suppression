# Phase Optimization Research Findings

**Date:** 2026-03-11
**Scope:** Spectral phase optimization for Raman (SSFS) suppression in SMF-28
**Code analyzed:** `scripts/common.jl`, `visualization.jl`, `raman_optimization.jl`, `test_optimization.jl`, `benchmark_optimization.jl`

---

## 1. Image-by-Image Analysis

### Run 1: L=1m, P=0.05W, time_window=10ps (gentle, N~1.5)

#### `raman_opt_L1m_P005W.png` — 3x2 comparison
- **Row 1 (Spectra):** Before shows modest Raman shoulder at ~1650-1700nm (J=0.0033, -24.8 dB). After shows clean suppression (J=0.0000, -50.3 dB). Input (blue dashed) and output (red solid) spectra well-resolved. Raman band shading (red) covers right half of plot — visually dominant but not obscuring critical features here.
- **Row 2 (Temporal):** Before shows input ~2959W peak broadening to ~5508W output compressed soliton. After shows input ~2586W, output ~2139W — less compression. **Time axes appear shared** (both ±0.6ps range) — this case is not broken because the pulse widths are similar.
- **Row 3 (Phase):** Before shows flat phase (zero). After shows narrow phase features at ~1550nm spanning ~20nm — nearly invisible against 1300-2000nm axis. **Issue 5 confirmed**: phase detail unreadable.
- **Severity:** Low for axes (this run happens to have similar scales), Medium for phase readability.

#### `raman_opt_L1m_P005W_evolution.png` — 2x2 evolution
- **Row 1 (Temporal):** Unshaped shows soliton fission with slight SSFS redshift visible as curved trajectory. Optimized shows cleaner propagation with less temporal spreading. Axes appear shared at ±0.75ps — looks correct for this gentle regime.
- **Row 2 (Spectral):** Unshaped shows broadening into red wavelengths (Raman). Optimized shows spectrum remaining centered at ~1550nm. Wavelength axes properly shared.
- **Overall:** Physically reasonable. The optimization successfully suppresses Raman shifting.

#### `raman_opt_L1m_P005W_boundary.png`
- Edge energy: 1.09e-05 (WARNING). The normalized power at window edges is ~1e-6, indicating minor energy leakage. The pulse structure spans roughly ±2ps, well within the 10ps window. The flat pedestal at ~1e-6 extending to edges is the source of the warning.
- **Assessment:** Acceptable. The warning threshold (1e-6) is somewhat strict for this regime.

---

### Run 2: L=2m, P=0.15W, time_window=20ps (moderate, N~2.7)

#### `raman_opt_L2m_P015W.png` — 3x2 comparison
- **Row 1 (Spectra):** Before shows strong Raman with J=0.7851 (-1.1 dB) — nearly 80% of energy in Raman band! Broad red output spectrum extending to 1700nm+. **Issue 7 partially confirmed**: there is a red output line visible overlapping the blue input line, which is the red "Output" trace plotted first (line 473 plots red before blue on line 474). After shows excellent suppression (J=0.0001, -41.7 dB).
- **Row 2 (Temporal):** Before shows peak output ~18942W (soliton compression), After shows ~3104W. **Issue 1 confirmed**: Both columns share the same time axis range (approximately ±2.5ps) after the shared-limits code runs. Looking more carefully, both appear to span roughly -2.5 to +2.5ps. The code at lines 530-535 of visualization.jl does compute shared limits by taking the union (min of all mins, max of all maxes). This appears to work correctly here — the temporal structures in both cases span similar ranges due to the multi-peak structure.
- **Row 3 (Phase):** Before is flat. After shows dense phase structure around 1550nm — very narrow features, **Issue 5 confirmed again**.
- **Severity:** High for Raman band shading dominance, Medium for phase readability.

#### `raman_opt_L2m_P015W_evolution.png` — 2x2 evolution
- **Row 1 (Temporal):** **Issue 2 confirmed.** Unshaped shows ±0.75ps range. Optimized shows ±2ps range. These are clearly different x-axis scales. The `plot_temporal_evolution` function (lines 181-228 in visualization.jl) computes auto-limits independently per call via `_auto_time_limits` on the input pulse (P[1,:]) at z=0. Since the unshaped pulse and optimized (phase-shaped) pulse have different temporal profiles at z=0, they get different auto-ranges. **There is no shared-axis logic in `plot_evolution_comparison`** for the temporal row — only the 3x2 plot (`plot_optimization_result_v2`) has the post-hoc sharing code (lines 530-535).
- **Row 2 (Spectral):** Both columns appear to share the same wavelength range (~1200-2200nm) — this is hardcoded via the default `λ0_nm ± range` logic.
- **Severity:** High — temporal evolution comparison is misleading without shared axes.

#### `raman_opt_L2m_P015W_boundary.png`
- **Edge energy: 2.63e-03 (DANGER).** The boundary diagnostic shows normalized power at ~1e-3 across the entire window, with the main pulse structure in the center. The pedestal does NOT decay to negligible levels at the edges. This indicates the optimized phase is stretching the pulse temporally, pushing energy toward the window boundaries.
- **Issue 3 confirmed.** The 20ps window is insufficient for the optimized pulse at L=2m.

---

### Run 3: L=5m, P=0.15W, time_window=30ps (strong nonlinearity)

#### `raman_opt_L5m_P015W.png` — 3x2 comparison
- **Row 1 (Spectra):** Before shows J=0.8045 (-0.9 dB) — massive Raman with most energy redshifted. **Issue 7 confirmed**: there is a distinct red line cutting through the Before spectrum. This is the "Output" spectrum (plotted as `"r-"` on line 473) which extends broadly from ~1300-1800nm. The visual overlap with the Raman band shading makes it look like a single red artifact, but it is simply the output spectrum being plotted with a thin red line overlaid on the red axvspan shading. After shows strong suppression (J=0.0000, -47.1 dB).
- **Row 2 (Temporal):** **Issue 4 confirmed and Issue 1 confirmed.** Before shows the time axis spanning -20 to +45ps (!) while the input pulse is sub-picosecond — it's compressed to an invisible spike. The After column shows ±10ps or similar. The shared-axis code (lines 530-535) fires but makes things worse: it takes the union, so both columns end up with the enormous range dictated by the Before column's broadened output. The `_auto_time_limits` function (line 95-108) centers on the peak and uses FWHM×padding_factor. For the Before case, `P_combined = max.(P_in, P_out)` — the output pulse has been massively temporally broadened by Raman/fission, so the auto-range extends to tens of picoseconds. The input pulse at ~0.185ps FWHM becomes a 1-pixel line.
- **Row 3 (Phase):** Before is flat. After shows extremely dense/saturated black lines at 1550nm — unreadable. **Issue 5 strongly confirmed**.
- **Severity:** Critical for temporal axis (Issue 4), High for phase readability.

#### `raman_opt_L5m_P015W_evolution.png` — 2x2 evolution
- **Row 1 (Temporal):** **Issue 2 confirmed.** Unshaped column shows ±0.75ps range with beautiful soliton fission trajectory (curved red trace showing SSFS). Optimized column shows ±0.6ps range — different scale! Also, the optimized temporal plot shows a strange pattern: broad ~10dB variations across the field with no clear pulse structure, suggesting the phase-shaped pulse has been dispersed into a complex temporal pattern.
- **Row 2 (Spectral):** Both share wavelength range. Unshaped shows dramatic broadening toward 2000nm (Raman). Optimized shows spectrum remaining tighter around 1550nm. The optimized spectral evolution shows some interesting structure — narrow spectral lines appearing and disappearing during propagation.
- **Severity:** High for temporal axis mismatch.

#### `raman_opt_L5m_P015W_boundary.png`
- **Edge energy: 1.53e-03 (DANGER).** Similar to Run 2 — the normalized power at edges is ~1e-3, forming a pedestal. The pulse structure is more complex with multiple peaks.
- **Issue 3 confirmed.** 30ps window insufficient for L=5m optimized pulse.

---

## 2. Bug Analysis

### Issue 1: Time axes NOT shared between Before/After columns (3x2 plot)

**Status:** PARTIALLY CONFIRMED — the sharing code EXISTS but fails for extreme cases.

**Root cause:** File `visualization.jl`, function `plot_optimization_result_v2`, lines 505-508 and 530-535.

The code does attempt to share time limits:
```julia
# Lines 505-508: Per-column auto-centering
P_combined = max.(P_in, P_out)
t_lims = _auto_time_limits(P_combined, ts_ps; padding_factor=4.0)
axs[2, col].set_xlim(t_lims...)

# Lines 530-535: Post-hoc sharing
all_xlims_time = [axs[2, c].get_xlim() for c in 1:2]
shared_tmin = minimum(lim[1] for lim in all_xlims_time)
shared_tmax = maximum(lim[2] for lim in all_xlims_time)
for c in 1:2
    axs[2, c].set_xlim(shared_tmin, shared_tmax)
end
```

The problem is the **union logic** (min of mins, max of maxes). When one column has a very wide range (e.g., Before in L=5m: -20 to +45ps due to Raman-broadened output) and the other has a narrow range (After: ±5ps), the union extends both to the wide range, making the narrow pulse invisible.

**Proposed fix:** Use an **energy-based criterion** rather than simple union. Compute shared limits from the input pulses only (not the output, which may be massively broadened), or use an energy-containment approach:

```julia
# REPLACE lines 505-508 with energy-based auto-centering:
# Compute time limits based on INPUT pulse only (stable reference)
t_lims_in = _auto_time_limits(P_in, ts_ps; padding_factor=4.0)
t_lims_out = _auto_time_limits(P_out, ts_ps; padding_factor=4.0)
# Use the wider of input-only and output-only ranges
t_lims = (min(t_lims_in[1], t_lims_out[1]), max(t_lims_in[2], t_lims_out[2]))
# But cap at a maximum sensible range (e.g., 10x input FWHM)
input_fwhm = _estimate_fwhm(P_in, ts_ps)
max_range = max(20 * input_fwhm, 2.0)  # at least 2ps
center = ts_ps[argmax(P_combined)]
t_lims = (max(t_lims[1], center - max_range/2), min(t_lims[2], center + max_range/2))
axs[2, col].set_xlim(t_lims...)
```

Alternatively, a simpler fix — compute shared limits from **all four** pulse profiles (in and out, before and after) using an energy-containment threshold (e.g., 99% energy window):

```julia
# NEW FUNCTION to add to visualization.jl:
"""Compute time window containing `frac` of total energy, centered on peak."""
function _energy_window(P, ts_ps; frac=0.99, min_width=0.5)
    E_total = sum(P)
    peak_idx = argmax(P)
    # Expand symmetrically from peak until frac of energy captured
    lo, hi = peak_idx, peak_idx
    E_captured = P[peak_idx]
    while E_captured / E_total < frac && (lo > 1 || hi < length(P))
        if lo > 1
            lo -= 1
            E_captured += P[lo]
        end
        if hi < length(P)
            hi += 1
            E_captured += P[hi]
        end
    end
    t_lo = ts_ps[lo]
    t_hi = ts_ps[hi]
    width = t_hi - t_lo
    if width < min_width
        center = (t_lo + t_hi) / 2
        t_lo = center - min_width / 2
        t_hi = center + min_width / 2
    end
    # Add 20% padding
    pad = 0.2 * (t_hi - t_lo)
    return (t_lo - pad, t_hi + pad)
end
```

Then in `plot_optimization_result_v2`, replace lines 505-535 with:
```julia
# Inside the column loop (replace lines 505-508):
# Collect all pulse profiles for shared axis computation
# (defer xlim setting to after both columns computed)

# After the column loop (replace lines 530-535):
# Collect all temporal profiles from both columns
all_P_temporal = []  # store during loop
# ... then compute energy-based shared limits:
all_t_lims = [_energy_window(P, ts_ps; frac=0.995) for P in all_P_temporal]
shared_tmin = minimum(lim[1] for lim in all_t_lims)
shared_tmax = maximum(lim[2] for lim in all_t_lims)
for c in 1:2
    axs[2, c].set_xlim(shared_tmin, shared_tmax)
end
```

**Expected impact:** L=5m Before temporal pulse will be visible (not compressed to 1 pixel). L=2m columns will have identical, physically meaningful time ranges.

---

### Issue 2: Evolution comparison axes not shared

**Status:** CONFIRMED

**Root cause:** File `visualization.jl`, function `plot_evolution_comparison`, lines 807-858.

The function calls `plot_temporal_evolution` independently for each column (lines 821-829). Each call to `plot_temporal_evolution` independently computes auto-limits via `_auto_time_limits(P0, ts_ps)` on the z=0 temporal profile (line 223). Since the unshaped and optimized input pulses have different temporal profiles (the optimized pulse has phase shaping that broadens it temporally after IFFT), they get different auto-ranges.

**There is NO shared-axis code** in `plot_evolution_comparison` — unlike `plot_optimization_result_v2` which has lines 530-535.

**Proposed fix:** Add shared-axis logic after both temporal evolution plots are created, mirroring the pattern from `plot_optimization_result_v2`. Add after line 839 (before the colorbar code):

```julia
# ── Shared time axis across temporal columns ──
all_tlims = [axs[1, c].get_xlim() for c in 1:2]
shared_tmin = minimum(lim[1] for lim in all_tlims)
shared_tmax = maximum(lim[2] for lim in all_tlims)
for c in 1:2
    axs[1, c].set_xlim(shared_tmin, shared_tmax)
end
```

However, this has the same union-range problem as Issue 1. A better approach: pass explicit `time_limits` to both calls:

```julia
# Before the plotting calls, compute shared time limits:
# Forward-propagate both to get z=0 profiles
P0_before = abs2.(fft(uω0_before, 1)[:, 1])
P0_after = abs2.(fft(uω0_after, 1)[:, 1])
ts_ps = sim["ts"] .* 1e12

t_lims_before = _auto_time_limits(P0_before, ts_ps; padding_factor=5.0)
t_lims_after = _auto_time_limits(P0_after, ts_ps; padding_factor=5.0)

# Also check output profiles for the unshaped case (may have Raman walk-off)
sol_before_end = sol_before["ut_z"][end, :, 1]
P_end_before = abs2.(sol_before_end)
t_lims_end = _auto_time_limits(P_end_before, ts_ps; padding_factor=3.0)

# Use energy-based window encompassing all relevant profiles
shared_time = (
    min(t_lims_before[1], t_lims_after[1], t_lims_end[1]),
    max(t_lims_before[2], t_lims_after[2], t_lims_end[2])
)

# Then pass time_limits=shared_time to both plot_temporal_evolution calls
```

**Expected impact:** L=2m evolution will show both temporal columns at the same ~±2ps scale. L=5m will show both at the same wider range.

---

### Issue 3: Boundary DANGER for L=2m and L=5m

**Status:** CONFIRMED

**Root cause:** The phase regularization penalties (λ_phase_smooth=1e-4, λ_phase_tikhonov=1e-5) are too weak relative to the Raman cost gradient, and the adjacent-difference penalty is ineffective against slowly-varying quadratic phase (GDD).

**Detailed analysis:**

1. **Adjacent-difference penalty** (lines 97-108 of `raman_optimization.jl`): Penalizes Σ(φ[i]-φ[i-1])². This penalizes high-frequency phase oscillations but is weak against smooth quadratic phase (GDD), because for φ(ω) = ½·GDD·ω², the adjacent differences Δφ = GDD·Δω·ω_i are small when Δω is small (fine grid). With Nt=8192 and time_window=20ps, Δω is tiny, so the per-element penalty is negligible even for large GDD. The total penalty scales as ~GDD²·Δω²·Σω_i² which for fixed bandwidth is proportional to Δω² ∝ 1/Nt² — meaning the penalty gets WEAKER as the grid gets finer.

2. **Tikhonov penalty** (lines 112-115): Penalizes Σφ². This does penalize GDD (since Σ(½·GDD·ω²)² grows with GDD), but at λ=1e-5 it's too weak to compete with the strong Raman gradient at high N.

3. **Why the optimizer adds GDD:** Large positive GDD temporally stretches the pulse, reducing peak power and thus reducing Raman scattering. This is the "trivial" solution — just chirp the pulse to lower its peak power. But this causes the temporal extent to grow beyond the FFT window.

**Proposed fixes (in order of effectiveness):**

**(a) Direct GDD penalty (recommended):** Penalize the second moment of the phase profile:
```julia
# Add to cost_and_gradient, after the existing regularization:
if λ_gdd > 0
    Δf_fft = fftfreq(Nt, 1 / sim["Δt"])
    ω_fft = 2π .* Δf_fft
    for m in 1:size(φ, 2)
        # GDD ≈ Σ φ(ω) · ω² / Σ ω⁴ (least-squares estimate)
        # Penalty: Σ (φ(ω) · ω²)² — penalizes quadratic phase content
        gdd_content = sum(φ[:, m] .* ω_fft.^2)
        J_total += λ_gdd * gdd_content^2
        grad_total[:, m] .+= 2 * λ_gdd * gdd_content .* ω_fft.^2
    end
end
```

**(b) Increase existing penalties significantly:** λ_phase_smooth=1e-1, λ_phase_tikhonov=1e-2. But this may over-constrain and prevent useful phase optimization.

**(c) Larger time windows:** The `recommended_time_window` function (common.jl line 33-42) computes walk-off from dispersion only:
```
walk_off_ps = β2_abs * L_fiber * Δω_raman * 1e12
```
This gives ~3.3ps for L=2m, ~8.2ps for L=5m (with safety_factor=2). The 20ps and 30ps windows should be sufficient for the *unshaped* pulse, but the optimizer is adding large GDD that stretches the pulse far beyond the dispersive walk-off estimate. The fix should account for the *maximum allowed chirp*:
```julia
function recommended_time_window(L_fiber; safety_factor=2.0, max_gdd_ps2=0.0)
    # ... existing walk-off calculation ...
    chirp_extent = max_gdd_ps2 > 0 ? max_gdd_ps2 * Δω_raman : 0.0
    return max(5, ceil(Int, (walk_off_ps + pulse_extent + chirp_extent) * safety_factor))
end
```

**(d) Super-Gaussian absorbing window:** Apply a soft absorbing boundary in the time domain after each split-step:
```julia
# Window function: W(t) = exp(-(t/t_edge)^2n) for |t| > t_boundary
# Applied as u(t) *= W(t) at each step
```
This requires modification of the MultiModeNoise solver and is the most invasive fix.

**Recommendation:** Implement fix (a) — direct GDD penalty — as the primary solution, supplemented by (c) — larger recommended windows. This addresses the root cause (optimizer exploiting GDD) without requiring solver changes.

**Expected impact:** Boundary DANGER will be eliminated. The optimizer will be forced to find phase profiles that suppress Raman without excessive temporal stretching.

---

### Issue 4: L=5m temporal shows invisible 1-pixel spike

**Status:** CONFIRMED

**Root cause:** Same as Issue 1. In `plot_optimization_result_v2`, the `_auto_time_limits` function (visualization.jl lines 95-108) uses `P_combined = max.(P_in, P_out)`. For the Before column of L=5m, the output pulse has been Raman-shifted and temporally broadened to ~45ps, so the auto-range covers -20 to +50ps. The input sech² pulse at 185fs FWHM occupies ~0.2ps — which at 300 DPI on a 12-inch-wide figure is literally <1 pixel.

**Proposed fix:** Use the `_energy_window` function proposed in Issue 1, or add a dual-scale approach:

```julia
# Option A: Plot input and output on separate y-axes or with inset
# Option B: Use energy-containment window (see Issue 1 fix)
# Option C: Add a zoom inset for the input pulse when the range ratio > 10:
fwhm_in = _estimate_fwhm(P_in, ts_ps)
full_range = t_lims[2] - t_lims[1]
if full_range / max(fwhm_in, 0.01) > 20
    # Add inset axes zoomed on input pulse
    ax_inset = axs[2, col].inset_axes([0.6, 0.5, 0.35, 0.4])
    ax_inset.plot(ts_ps, P_in, "b--", linewidth=1.0)
    ax_inset.plot(ts_ps, P_out, "r-", linewidth=0.8)
    t_zoom = _auto_time_limits(P_in, ts_ps; padding_factor=3.0)
    ax_inset.set_xlim(t_zoom...)
    ax_inset.set_title("Zoom", fontsize=7)
    ax_inset.tick_params(labelsize=7)
end
```

**Expected impact:** The input pulse will always be visible, either through better auto-ranging or an inset zoom.

---

### Issue 5: Phase plots show unreadably narrow features

**Status:** CONFIRMED (all three runs)

**Root cause:** File `visualization.jl`, function `plot_optimization_result_v2`, line 525:
```julia
axs[3, col].set_xlim(λ0_nm - 300, λ0_nm + 500)
```
This sets a fixed wavelength range of 1250-2050nm regardless of where the phase structure actually is. The phase mask (lines 518-521) correctly hides phase where spectral power < -30dB, but the resulting visible phase structure spans only ~20-40nm around 1550nm.

**Proposed fix:** Add a zoom inset or auto-detect the phase structure region:

```julia
# After plotting the full-range phase (line 522), add zoom inset:
# Find wavelength range where phase is not NaN
valid_phase = findall(.!isnan.(φ_display))
if length(valid_phase) > 3
    λ_valid = λ_nm[valid_phase]
    λ_center = (minimum(λ_valid) + maximum(λ_valid)) / 2
    λ_span = maximum(λ_valid) - minimum(λ_valid)
    λ_pad = max(λ_span * 0.3, 10.0)  # at least 10nm padding

    ax_inset = axs[3, col].inset_axes([0.55, 0.1, 0.4, 0.85])
    ax_inset.plot(λ_nm, φ_display, "k-", linewidth=0.8)
    set_phase_yticks!(ax_inset)
    ax_inset.set_xlim(λ_center - λ_span/2 - λ_pad, λ_center + λ_span/2 + λ_pad)
    ax_inset.set_title("Zoom", fontsize=8)
    ax_inset.tick_params(labelsize=7)

    # Draw rectangle on main axis showing zoom region
    from matplotlib.patches import Rectangle
    rect = Rectangle((λ_center - λ_span/2 - λ_pad, 0),
                      λ_span + 2*λ_pad, 2π, fill=false, edgecolor="blue", linewidth=0.5)
    axs[3, col].add_patch(rect)
end
```

**Expected impact:** Phase structure will be clearly visible at ~20nm scale within the inset.

---

### Issue 6: Raman band shading too visually dominant

**Status:** CONFIRMED

**Root cause:** File `visualization.jl`, line 481-482:
```julia
axs[1, col].axvspan(λ_raman_onset, λ0_nm + 500,
    alpha=0.12, color="red", label="Raman band")
```

The alpha=0.12 is relatively subtle, but the shading covers roughly 1600-2050nm — about 55% of the visible x-axis range. Combined with the red output spectrum line, it creates visual confusion.

**Proposed fix:** Reduce alpha and use a different visual indicator:

```julia
# Option A: Much lower alpha
axs[1, col].axvspan(λ_raman_onset, λ0_nm + 500,
    alpha=0.05, color="red", label="Raman band")

# Option B: Vertical line at Raman onset instead of shaded region
axs[1, col].axvline(x=λ_raman_onset, color="red", ls="--",
    alpha=0.5, linewidth=0.8, label="Raman onset")

# Option C: Narrow band shading (just near onset) + label
λ_raman_end = min(λ_raman_onset + 50, λ0_nm + 500)
axs[1, col].axvspan(λ_raman_onset, λ_raman_end,
    alpha=0.08, color="red", label="Raman band")
axs[1, col].annotate("Raman →", xy=(λ_raman_onset + 5, -5),
    fontsize=8, color="red", alpha=0.7)
```

**Recommendation:** Option B (vertical line) is clearest and least visually intrusive.

**Expected impact:** Spectral features in the Raman region (1600-2000nm) will be clearly visible without pink overlay.

---

### Issue 7: L=5m spectral plot has overlapping red line

**Status:** CONFIRMED — it is the Output spectrum.

**Root cause:** File `visualization.jl`, function `plot_optimization_result_v2`, lines 473-474:
```julia
axs[1, col].plot(λ_nm, spec_out_dB, "r-", label="Output", alpha=0.8, linewidth=1.0)
axs[1, col].plot(λ_nm, spec_in_dB, "b--", label=input_label, alpha=0.7, linewidth=1.5)
```

The output (red) is plotted FIRST, then the input (blue dashed) on top. For L=5m, the output spectrum is broadly spread across 1300-1800nm at -10 to -20 dB, and the Raman band shading (alpha=0.12, red) overlays it. The combined effect makes the red output line look like an artifact or boundary marker.

**Proposed fix:** Change plot order and use a different color for output:

```julia
# Plot input first (background), then output on top
axs[1, col].plot(λ_nm, spec_in_dB, "b--", label=input_label, alpha=0.7, linewidth=1.5)
axs[1, col].plot(λ_nm, spec_out_dB, color="darkgreen", ls="-",
    label="Output", alpha=0.85, linewidth=1.2)
```

Or keep red but make the Raman shading a different color:
```julia
axs[1, col].axvspan(λ_raman_onset, λ0_nm + 500,
    alpha=0.08, color="orange", label="Raman band")
```

**Expected impact:** The output spectrum will be clearly distinguishable from the Raman band shading.

---

## 3. Physics Assessment

### R1: Expected GNLSE outputs for SMF-28 parameters

**Parameters:** 185fs sech² pulses at 1550nm, P_avg=0.05-0.15W, rep_rate=80.5MHz, γ=0.0013 W⁻¹m⁻¹, β₂=-2.6e-26 s²/m in SMF-28.

**Key calculations:**
- T₀ = FWHM / (2·acosh(√2)) = 185fs / 1.763 ≈ 105fs
- P_peak = P_avg / (FWHM × rep_rate) = 0.05 / (185e-15 × 80.5e6) ≈ 3356 W (for P=0.05W), ≈ 10068 W (for P=0.15W)
- L_D = T₀² / |β₂| = (105e-15)² / 2.6e-26 ≈ 0.42m
- L_NL = 1 / (γ × P_peak) = 1 / (0.0013 × 3356) ≈ 0.23m (P=0.05W), ≈ 0.077m (P=0.15W)
- N = √(L_D / L_NL) ≈ 1.35 (P=0.05W), ≈ 2.34 (P=0.15W)

**Expected behavior based on Dudley et al. (2006, Rev. Mod. Phys. 78, 1135-1184):**

For **N ≈ 1.35 (Run 1):** Near-fundamental soliton. Expect minor spectral broadening via SPM and weak SSFS. The Raman frequency shift follows ΔωR ∝ |β₂|/(T₀⁴) × z, approximately 0.5-1 THz over 1m. Temporal profile should remain approximately sech² with modest compression/breathing. **Our results match**: J=0.0033 indicates ~0.3% Raman energy — consistent with mild SSFS.

For **N ≈ 2.34 (Run 2, L=2m):** Soliton fission should occur around z ≈ L_D/N ≈ 0.18m. The input N~2.3 soliton breaks into ~2 fundamental solitons plus dispersive radiation. The most energetic ejected soliton undergoes SSFS. Over 2m, significant redshift (several THz) expected. **Our results match**: J=0.79 indicates massive Raman transfer — consistent with strong soliton fission and SSFS at this soliton order.

For **N ≈ 2.34 (Run 3, L=5m):** Even stronger SSFS over longer propagation. The ejected soliton may shift by 10+ THz (>100nm). Complex temporal structure from multiple soliton components and dispersive waves. **Our results match**: J=0.80, broad spectral output, complex temporal structure.

**Key reference:** Dudley, Genty & Coen, "Supercontinuum generation in photonic crystal fiber," Rev. Mod. Phys. 78, 1135-1184 (2006). Figures 4-8 show the characteristic spectral and temporal evolution for various soliton orders, with N>1.5 showing clear fission and SSFS.

**Secondary references:**
- Mitschke & Mollenauer, "Discovery of the soliton self-frequency shift," Opt. Lett. 11, 659-661 (1986).
- Gordon, "Theory of the soliton self-frequency shift," Opt. Lett. 11, 662-664 (1986).
- Hori et al., "Experimental and numerical analysis of widely broadened supercontinuum generation in highly nonlinear dispersion-shifted fiber with a femtosecond pulse," JOSA B 21, 1969-1980 (2004).

### R2: Phase optimization effectiveness at high soliton order

**Finding:** Spectral phase shaping can suppress SSFS, but effectiveness decreases with increasing soliton order N.

For **N < 2:** Phase-only control is highly effective because the nonlinear dynamics are perturbative. Pre-chirping can adjust the soliton fission point or prevent fission entirely. Our Run 1 (N~1.35) confirms this: J drops from -24.8 dB to -50.3 dB.

For **N ≈ 2-3:** Phase shaping can still significantly reduce Raman energy but requires larger phase excursions. The optimizer tends to add GDD to reduce peak power (trivial solution) rather than finding more subtle phase profiles. Our Run 2 confirms partial effectiveness (J: -1.1 dB → -41.7 dB) but with boundary issues suggesting the optimizer is relying on GDD.

For **N > 3:** Soliton fission becomes violent and chaotic. Phase-only control becomes insufficient because amplitude redistribution is needed — the soliton number is too high for any phase profile to prevent energy transfer to Raman wavelengths without dramatically reducing peak power. Combined amplitude+phase shaping or fiber design changes become necessary.

**Key references:**
- Omenetto et al., "Adaptive control of femtosecond soliton self-frequency shift in fibers," Opt. Lett. 29, 271-273 (2004). Demonstrated SLM-based spectral phase control of SSFS.
- Efimov & Taylor, "Spectral-temporal-spatial customization via modulating multimodal nonlinear pulse propagation," Nature Communications (2024). Reviews modern approaches to pulse control.
- Spectral optimization of supercontinuum shaping using metaheuristic algorithms (PSO, GA, SA), Scientific Reports (2024). Shows that high-dimensional spectral phase optimization for SC control is feasible but requires sophisticated algorithms.

### R3: Boundary condition requirements

**Finding:** The time windows used (10ps, 20ps, 30ps) are marginal for the optimized pulses, though adequate for unshaped propagation.

**Typical published values:**
- Dudley et al. (2006) use time windows of 4-8ps for 50fs pulses in 15cm PCF (N~7-10). Scaled to our parameters: longer pulses and longer fibers require proportionally larger windows.
- The gnlse-python package documentation uses 12.5ps for 50fs pulses in 15cm fiber at 835nm.
- Hagen & Magnusson (JLT 27, 3984, 2009) discuss adaptive step size but note that the temporal window must accommodate dispersive wave walk-off: Δt_walkoff = |β₂| × L × Δω.

**For our parameters:**
- Dispersive walk-off: Δt = |β₂| × L × Δω_Raman = 2.6e-26 × L × 2π×13e12
  - L=1m: ~2.1ps
  - L=2m: ~4.2ps
  - L=5m: ~10.6ps
- With safety factor 2× and pulse extent: 5ps, 10ps, 22ps respectively.

**But** the optimizer adds large GDD that extends the pulse far beyond the dispersive walk-off estimate. The windows need to accommodate the chirped pulse extent.

**Alternatives to larger windows:**
1. **Absorbing boundaries:** Apply a super-Gaussian temporal window W(t) = exp(-(2t/T_w)^2n) with n=4-8 near the edges. This prevents energy from wrapping around. Kosloff (J. Comput. Phys. 63, 363, 1986) describes the approach for FFT-based methods.
2. **GDD constraint:** Directly limit the maximum allowed GDD in the optimizer (see Issue 3 fix).
3. **Dynamic window:** Monitor boundary energy during optimization and increase window size if needed.

**Recommendation:** Use GDD penalty (Issue 3 fix a) as primary solution. For safety, also increase windows: 15ps for L=1m, 30ps for L=2m, 60ps for L=5m (based on 3× the walk-off estimate plus chirp margin).

### R4: Phase regularization strategies

**Finding:** The current adjacent-difference penalty is mathematically inadequate for preventing GDD accumulation.

**Analysis of Σ(φ[i]-φ[i-1])² penalty:**
For a quadratic phase φ(ω) = ½·GDD·ω², the penalty becomes:
```
Σ(φ[i]-φ[i-1])² = Σ(GDD·Δω·ω_i)² = GDD²·Δω²·Σω_i²
```
With Nt grid points and bandwidth B: Δω = B/Nt, so the penalty ∝ GDD²·B²/Nt² × Nt·B²/3 = GDD²·B⁴/(3Nt).

This means the penalty **decreases with increasing Nt**. At Nt=8192, the penalty per unit GDD is ~8000× weaker than at Nt=1. This is why the regularization "fails" — it was designed for a fine grid where adjacent differences are inherently small.

**Better alternatives:**

**(1) Direct moment penalties (recommended):**
```julia
# Penalize GDD content: ∫ φ(ω)·ω² dω
# Penalize TOD content: ∫ φ(ω)·ω³ dω
ω = 2π .* fftfreq(Nt, 1/Δt)
gdd_moment = sum(φ .* ω.^2) / Nt
tod_moment = sum(φ .* ω.^3) / Nt
J_gdd_penalty = λ_gdd * gdd_moment^2
J_tod_penalty = λ_tod * tod_moment^2
```
This is Nt-independent and directly targets the physical quantity causing boundary overflow.

**(2) Frequency-domain smoothness (Sobolev penalty):**
```julia
# Penalize the "roughness" in Fourier space of φ(ω)
# This is Σ |k² · F[φ]_k|² where F is the DFT of φ
φ_ft = fft(φ, 1)
k = fftfreq(Nt)
J_sobolev = λ_sobolev * sum(abs2.(k.^2 .* φ_ft)) / Nt
```
This penalizes rapidly-varying phase while allowing slow variations — the opposite of what we want.

**(3) Spectral-power-weighted phase variance:**
```julia
# Weight the phase penalty by spectral power — only penalize
# phase where the pulse has energy
S = abs2.(uω0[:, m])
S_norm = S / sum(S)
J_weighted = λ_wpv * sum(S_norm .* φ[:, m].^2)
```
This prevents large phase excursions where they matter (on the pulse bandwidth) while allowing arbitrary phase where there's no energy.

**Recommendation from optimization literature:**
- Weiner's tutorial review (Opt. Commun. 284, 3669, 2011) discusses phase parameterization as Taylor coefficients (GDD, TOD, FOD) rather than point-by-point phase values. This naturally constrains the optimization to low-order phase profiles.
- Omenetto et al. (2004) parameterized the SLM phase as a 4th-order polynomial, avoiding the over-parameterization problem entirely.

**Proposed implementation:** Add Taylor-coefficient penalties to `cost_and_gradient`:

```julia
# Add keyword arguments:
# λ_gdd=0.0, λ_tod=0.0

if λ_gdd > 0 || λ_tod > 0
    ω = 2π .* fftfreq(Nt, 1 / sim["Δt"])
    # Weight by spectral power to focus on pulse bandwidth
    S = abs2.(uω0[:, 1]) ./ sum(abs2.(uω0[:, 1]))
    for m in 1:size(φ, 2)
        if λ_gdd > 0
            gdd_proj = sum(S .* φ[:, m] .* ω.^2)
            J_total += λ_gdd * gdd_proj^2
            grad_total[:, m] .+= 2 * λ_gdd * gdd_proj .* S .* ω.^2
        end
        if λ_tod > 0
            tod_proj = sum(S .* φ[:, m] .* ω.^3)
            J_total += λ_tod * tod_proj^2
            grad_total[:, m] .+= 2 * λ_tod * tod_proj .* S .* ω.^3
        end
    end
end
```

---

## 4. Recommended Changes (Priority Ordered)

### Priority 1 (Critical): Fix boundary overflow — add GDD/TOD penalty
- **File:** `scripts/raman_optimization.jl`, function `cost_and_gradient` (after line 115)
- **Also:** `scripts/raman_optimization.jl`, function `optimize_spectral_phase` — add `λ_gdd`, `λ_tod` kwargs
- **Also:** `scripts/raman_optimization.jl`, function `run_optimization` — add and pass through kwargs
- **Code:** See Issue 3 proposed fix (a) and R4 proposed implementation
- **Suggested values:** λ_gdd=1e-2, λ_tod=1e-3 (tune empirically)
- **Impact:** Eliminates DANGER boundary conditions in Runs 2 and 3

### Priority 2 (High): Add shared time axes to evolution comparison
- **File:** `scripts/visualization.jl`, function `plot_evolution_comparison` (after line 839)
- **Code:** See Issue 2 proposed fix
- **Impact:** Fixes misleading temporal evolution comparison for all runs

### Priority 3 (High): Fix temporal auto-ranging for extreme cases
- **File:** `scripts/visualization.jl`
- **Add:** New function `_energy_window(P, ts_ps; frac=0.99, min_width=0.5)`
- **Modify:** `plot_optimization_result_v2` lines 505-508 and 530-535 — use energy-based windowing
- **Code:** See Issue 1 proposed fix
- **Impact:** Fixes invisible pulse in L=5m Before temporal, improves all temporal plots

### Priority 4 (Medium): Add phase zoom inset
- **File:** `scripts/visualization.jl`, function `plot_optimization_result_v2` (after line 526)
- **Code:** See Issue 5 proposed fix
- **Impact:** Phase structure becomes readable in all runs

### Priority 5 (Medium): Reduce Raman band visual dominance
- **File:** `scripts/visualization.jl`, function `plot_optimization_result_v2` (lines 480-482)
- **Change:** Replace `axvspan` with `axvline` at Raman onset wavelength
- **Code:** See Issue 6 proposed fix (Option B)
- **Impact:** Spectral features in Raman region visible

### Priority 6 (Low): Fix output spectrum visibility / color conflict
- **File:** `scripts/visualization.jl`, function `plot_optimization_result_v2` (lines 473-474)
- **Change:** Plot order and/or output color to dark green
- **Code:** See Issue 7 proposed fix
- **Impact:** Eliminates visual confusion in L=5m spectral plot

### Priority 7 (Low): Increase recommended time windows
- **File:** `scripts/common.jl`, function `recommended_time_window` (lines 33-42)
- **Change:** Add `max_gdd_ps2` parameter; increase safety_factor default to 3.0
- **Code:** See Issue 3 proposed fix (c)
- **Impact:** Prevents future boundary issues for new parameter combinations

---

## 5. Open Questions

1. **Is the adjoint gradient correct for regularized cost?** The gradient validation in `test_optimization.jl` tests with regularization (lines 396-420), but only at small phase values (0.1×randn). At the large phase values the optimizer converges to for L=2m and L=5m, the gradient may have numerical issues due to the interaction between the adjoint gradient and the regularization gradient. **Test needed:** Run gradient validation at the optimized phase values (not just near zero).

2. **What is the optimal λ_gdd value?** Too small and the boundary overflow persists; too large and the optimizer can't apply any useful phase. This needs to be tuned empirically, possibly via a sweep: λ_gdd ∈ {1e-4, 1e-3, 1e-2, 1e-1} with boundary energy and Raman cost both tracked.

3. **Is the L=5m warm-start from L=2m result appropriate?** Run 3 uses φ_warm from Run 2 (line 415-422 of `raman_optimization.jl`). But the time_window changes from 20ps to 30ps, meaning the frequency grid spacing Δω changes. The phase values φ[i] correspond to different physical frequencies in the two simulations. The warm-start is applying the L=2m phase (optimized for Δω_1) at the L=5m frequencies (Δω_2). If Nt is the same but time_window differs, the frequency grid is different, so the warm-start phase is physically misaligned. **Fix needed:** Interpolate the phase from the old frequency grid to the new one, or verify that the grids are compatible.

4. **Is β₃ = 1.2e-40 s³/m correct for SMF-28?** The typical value for SMF-28 at 1550nm is β₃ ≈ 1.2e-40 s³/m, which corresponds to a dispersion slope S ≈ 0.086 ps/(nm²·km). This seems physically correct. However, β₃ only matters significantly for very broadband spectra or very long fibers. For Runs 2-3 where the spectrum extends to 1800nm+, β₃ will affect the dispersive wave positions.

5. **Should the optimizer be constrained to low-order phase?** Rather than penalizing GDD/TOD, an alternative approach is to parameterize the phase as a low-order polynomial (GDD, TOD, FOD, QOD — 4 parameters) rather than point-by-point (Nt=8192 parameters). This reduces the optimization from 8192D to 4D, making L-BFGS trivial but limiting the expressiveness. Testing both approaches would reveal whether high-order phase features provide additional Raman suppression beyond what low-order chirp alone achieves.

6. **Is the Raman cost function (fractional energy in band) the right objective?** The current cost J = E_Raman / E_total is bounded [0,1] and measures fractional energy transfer. An alternative is to use the absolute Raman energy E_Raman, or the spectral peak in the Raman band, or the soliton frequency shift ΔωR. These different objectives may lead to different optimal phase profiles.

7. **Does the `lin_to_dB` conversion in the optimizer objective cause issues?** In `optimize_spectral_phase` (line 173), the cost passed to Optim.jl is `lin_to_dB(J) = 10*log10(J)`, not J itself. This changes the optimization landscape — the gradient of 10*log10(J) is 10/(J*ln(10)) × ∇J, which amplifies the gradient when J is small (near the optimum). This can cause L-BFGS to take very small steps near the minimum. Testing with linear J as the objective may improve convergence speed.
