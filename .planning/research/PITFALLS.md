# Domain Pitfalls: Nonlinear Fiber Optics Visualization

**Domain:** Scientific visualization for nonlinear fiber propagation / Raman suppression optimization
**Project:** smf-gain-noise (MultiModeNoise.jl)
**Researched:** 2026-03-24
**Sources:** matplotlib docs, Crameri et al. 2021 (HESS), Moreland colormap advice, existing codebase audit

---

## Critical Pitfalls

Mistakes that produce misleading physics, force rewrites, or draw immediate reviewer rejection.

---

### Pitfall 1: Jet Colormap on dB-Scale Heatmaps

**What goes wrong:**
Jet is a non-perceptually-uniform colormap — its lightness (L*) varies non-monotonically. On a spectral or temporal evolution heatmap encoded in dB, this creates false banding: regions of equal dB power appear to have different levels of contrast, and the eye is drawn to artificial "edges" in the cyan and yellow regions that do not correspond to any physical boundary. The -30 dB and -10 dB contours are perceptually indistinguishable from each other but visually prominent compared to the -5 dB region, which is the inverse of what the physics demands.

**Why it happens in this codebase:**
`cmap="jet"` is set as a default argument in `plot_spectral_evolution`, `plot_temporal_evolution`, `plot_combined_evolution`, and `plot_spectrogram` (lines 335, 396, 453, 503). It was likely the matplotlib default prior to v2.0 and persisted.

**Consequences:**
- Advisor or collaborator misidentifies spectral features as physical when they are colormap artifacts
- Supercontinuum onset depth and Raman lobe intensity are visually exaggerated or suppressed relative to ground truth
- Grayscale printing (common for conference proceedings) reverses the ordering: high-intensity regions may appear the same shade as mid-range noise, making the plot unreadable
- Fails colorblind accessibility (confuses red-green channels)

**Quantified harm:** Research shows jet causes visual errors up to 7.5% of total displayed data variation (Crameri et al. 2021, HESS 25:4549). On a 40 dB range plot this translates to ~3 dB apparent error — enough to confuse signal from noise.

**Prevention:**
Replace `cmap="jet"` with `cmap="inferno"` for all dB heatmaps. Inferno is perceptually uniform (monotonically increasing L*), dark at the noise floor (black = -40 dB), and bright at peak power (yellow-white = 0 dB). This matches physical intuition: bright = powerful. Verified against matplotlib perceptually-uniform colormap documentation (HIGH confidence).

Alternative: `cmap="magma"` for temporal panels to visually distinguish them from spectral panels while maintaining perceptual uniformity. Both handle grayscale correctly.

Do NOT use `cmap="viridis"` for dB evolution plots: viridis starts in dark blue (low end), which makes the noise floor visually prominent and draws attention away from the pulse. Inferno's black-at-minimum is correct for dB data where the noise floor should recede.

**Warning signs:**
- Cyan or teal "halos" visible around the main spectral feature
- The region between -5 dB and -20 dB looks like a sharp boundary
- The plot looks qualitatively different depending on whether you're looking at it on a bright or dim monitor

**Phase:** Address in the colormap fix phase (first implementation phase).

---

### Pitfall 2: Spectral Phase Plotted Everywhere Including the Noise Floor

**What goes wrong:**
Unwrapped spectral phase is mathematically defined at every frequency bin, including those where spectral power is 40–100 dB below peak. Below the noise floor, the "phase" is dominated by numerical noise from the FFT — it is physically meaningless and visually catastrophic. Unwrapping propagates these noise-floor discontinuities across the entire spectrum, causing the plotted phase to look like random sawtooth oscillations over hundreds of radians. An advisor looking at this will assume the pulse has a terrible broadband chirp, when the actual shaped region is narrow and well-behaved.

**Why it happens in this codebase:**
The `_apply_dB_mask` function (lines 199–205) exists and is already being called for phase, group delay, and GDD plots. However, the threshold is `-30 dB`. For a well-optimized pulse with 60+ dB dynamic range, the region between -30 dB and -60 dB still contains noise-floor artifacts. Additionally, `plot_optimization_result_v2` uses the shaped input's power as the mask reference, which is correct; but the mask is applied AFTER unwrapping, meaning a single noisy bin before the masked region can corrupt the unwrapped values inside the valid region.

**Consequences:**
- Phase panel looks oscillatory and unreadable even when the optimizer has produced a smooth, physically reasonable solution
- Group delay and GDD panels inherit the same noise — both show spikes at the edges of the signal band
- "Empty" panels (all NaN after masking) occur if the threshold is set too aggressively

**Prevention:**
1. Mask BEFORE unwrapping: apply a low-pass smoothing or zero-out sub-threshold bins in the wrapped phase prior to calling `_manual_unwrap`. This prevents noise-floor phase jumps from propagating.
2. Use a threshold of `-40 dB` (matching the heatmap's display range) rather than `-30 dB`.
3. After masking, clip the plotted y-range to the signal-bearing region rather than letting NaN segments dominate the axis scale.
4. In group delay and GDD plots, use `ylim` to exclude outlier values at the spectrum edges even after masking — a single edge bin can set the y-axis to ±10⁶ fs.

**Warning signs:**
- Phase plots show oscillations with amplitude >> the expected GDD × bandwidth²
- Group delay jumps by >1000 fs in one wavelength step
- Phase panel appears mostly flat but with large-amplitude noise at wavelength extremes

**Phase:** Address in the phase diagnostic fix phase.

---

### Pitfall 3: Raman Band Shading With Incorrect Wavelength Bounds

**What goes wrong (confirmed bug in this codebase):**
The `axvspan` that marks the Raman band uses `Δf_shifted .< raman_threshold` to select wavelengths. For a pump at 1064 nm with a -13 THz Raman shift, the Stokes band is centered at ~1117 nm with ~10 nm width. However, if `raman_threshold` is negative (frequency convention: downshifted = negative offset), then `Δf_shifted .< raman_threshold` selects ALL frequency bins more negative than the threshold, which includes the entire long-wavelength half of the spectrum, not just the Raman gain band window. This causes the shading to cover from the Raman onset wavelength all the way to the right edge of the plot.

**Why it happens:**
The frequency grid `Δf_shifted` contains offsets from the pump in both positive and negative directions. A threshold like `raman_threshold = -13.0` THz selects ALL offsets below -13 THz — the entire long-wavelength half from the Raman onset outward, not a ±bandwidth window around the gain peak.

**Consequences:**
- The entire right half of every spectrum plot is covered in a red band
- The Raman gain peak and the spectral region of interest are obscured
- The "before" and "after" panels are unreadable

**Prevention:**
Use a two-sided frequency filter: `abs.(Δf_shifted .- raman_center) .< raman_half_bandwidth` where `raman_center ≈ -13.2 THz` and `raman_half_bandwidth ≈ 5–6 THz`. For SMF-28 at 1064 nm, this gives a band from roughly 1100 nm to 1135 nm. Alternatively, define the band directly in wavelength: annotate with `axvspan(λ_raman_start, λ_raman_end)` computed from the known physics (13.2 THz downshift, ~10 THz FWHM bandwidth for silica Raman).

**Warning signs:**
- More than one-third of the spectral plot x-range is shaded
- The shaded region's left boundary coincides with the Raman onset line marker (they should be the same left edge)
- The shaded region has no visible right boundary within the plot range

**Phase:** First fix — this is a confirmed bug that must be resolved before any other plot work.

---

### Pitfall 4: Inconsistent Normalization Between Comparison Panels

**What goes wrong:**
In the 3×2 optimization result figure (`plot_optimization_result_v2`), each column runs its own `P_ref = max(maximum(spec_in), maximum(spec_out))` — normalized separately per column. This means the "Before" panel and the "After" panel have different 0 dB reference levels if the shaped input has different power than the unshaped input. A 3 dB difference in reference level between panels makes the output spectrum appear 3 dB more suppressed in one column than the other, purely from normalization, not physics.

**Consequences:**
- The J-function improvement appears visually exaggerated or underestimated
- Reviewer/advisor cannot directly compare the two columns as they appear to show data on different scales
- The annotation `J = 0.xxxx (-xx.x dB)` is in absolute power units but the plot reference has shifted

**Prevention:**
Normalize all comparison columns to a single `P_ref_global = max(all column peaks)` computed before the column loop. Both "Before" and "After" panels then share the same 0 dB reference. This is the standard practice for multi-panel comparison figures: identical axes are required to make any visual comparison meaningful.

Additionally, explicitly set identical `ylim` and `xlim` for all panels in the same row. Add a comment in code marking which reference is intentionally global.

**Warning signs:**
- The input spectrum (blue dashed line) appears at different dB levels in different columns
- The y-axis ticks do not align at the same physical values across columns

**Phase:** Normalization unification phase.

---

### Pitfall 5: Time-Domain Comparison Panels With Mismatched Axis Ranges

**What goes wrong:**
In `plot_optimization_result_v2`, the temporal panel auto-ranges independently for "Before" and "After" using `_energy_window`. If the shaped pulse is significantly more compressed than the unshaped pulse (which is the intended result of optimization), the two panels will show vastly different time ranges. A dispersed 10 ps window vs a compressed 1 ps window look dramatically different even if plotted side by side, making it impossible to compare pulse evolution visually.

**Consequences:**
- The pulse compression improvement is visually misleading — a narrower axis range makes a pulse look the same width even when it is 10× shorter
- Dispersed pedestals are invisible in the compressed-pulse panel if auto-ranging excludes them

**Prevention:**
1. Compute `t_lims_before` and `t_lims_after` for both columns first, then use `t_lims_shared = (min(both_lo), max(both_hi))` for both panels.
2. Use a shared time axis. If one pulse is 10 ps and the other is 1 ps, show both on a 10 ps window so the compression is visually apparent.
3. If the dispersed pulse occupies >20× more time than the compressed pulse, use separate panels with a clear note that axes are not matched (this is the only acceptable exception).

**Warning signs:**
- Before panel shows ±5 ps and after panel shows ±0.3 ps
- Compressed pulse and dispersed pulse look the same "width" in their respective panels

**Phase:** Axis normalization phase.

---

## Moderate Pitfalls

Problems that produce suboptimal plots but don't actively mislead about physics.

---

### Pitfall 6: tight_layout and Colorbar Interaction

**What goes wrong:**
`fig.tight_layout()` is called throughout the codebase (lines 310, 564, 633, 767, 884). In `plot_combined_evolution`, a colorbar is added via `fig.add_axes([0.90, 0.15, 0.025, 0.7])` with a manual `fig.subplots_adjust(right=0.88)` BEFORE tight_layout would be called. However, tight_layout and subplots_adjust conflict: calling one after the other overrides the layout adjustments of the first. The combined_evolution function avoids this by NOT calling tight_layout, but other functions do both, resulting in colorbars that overlap axis labels or float disconnected from their axes.

**Consequences:**
- At 300 DPI output, axis labels are clipped by the colorbar
- Colorbar height does not match the subplot height it belongs to
- Multi-panel figures with per-panel colorbars have unequal panel sizes

**Prevention:**
Use `layout="constrained"` in `subplots()` calls: `fig, axs = subplots(2, 2, figsize=..., layout="constrained")`. This replaces both `tight_layout` and `subplots_adjust`, handles colorbars correctly, and does not conflict with itself. Do NOT mix `tight_layout()` with `constrained_layout`. For the shared colorbar in `plot_combined_evolution`, pass `layout="constrained"` and use `fig.colorbar(im, ax=axes)` — constrained layout will handle the space allocation automatically.

Note: `constrained_layout` must be set at figure creation time in modern matplotlib. The `tight_layout()` calls in save: `savefig(..., bbox_inches="tight")` are correct and should be kept regardless.

**Warning signs:**
- Colorbar partially overlaps the rightmost subplot's title or y-axis labels
- The two subplots in a 2×1 figure have different widths

**Phase:** Layout fix — apply when refactoring each plot function.

---

### Pitfall 7: pcolormesh With Non-Monotonic Wavelength Grid

**What goes wrong (confirmed warning in run logs):**
The run log for v7 contains:
```
UserWarning: The input coordinates to pcolormesh are interpreted as cell centers,
but are not monotonically increasing or decreasing.
```
This occurs because `_freq_to_wavelength` converts the fftshifted frequency grid to wavelengths via `C/f`. The conversion `λ = C/f` is monotonically decreasing (higher frequency = shorter wavelength), but the full grid from `fftshift` goes from large negative offsets through zero to large positive offsets. The resulting wavelength array has the DC component (at center) corresponding to `λ = C/f0`, while the edges have large offsets and thus short OR very long wavelengths — the array is not monotonic. Additionally, negative frequencies produce negative wavelengths that pass through the positive-frequency filter intermittently.

**Consequences:**
- pcolormesh interpolates cell edges incorrectly, potentially misplacing spectral features by 1 cell width
- The UserWarning is printed for every evolution plot, cluttering the log
- In edge cases, spectral features appear shifted by a few nm from their true wavelength

**Prevention:**
After converting to wavelength, always sort by ascending wavelength using the `sort_idx` already computed in `_freq_to_wavelength`. Apply this sorting to the data array before passing to `pcolormesh`. Verify that `sort_idx` is being applied to the 2D data matrix (not just the axis array) in `plot_spectral_evolution`.

**Warning signs:**
- The UserWarning in the run log
- Spectral features appear to shift depending on the frequency resolution used

**Phase:** Address in the pcolormesh grid fix — can be a small targeted fix.

---

### Pitfall 8: dB Floor Choice That Hides Real Signal

**What goes wrong:**
`dB_range=40.0` is the default for evolution heatmaps (lines 332, 391, 450). With a 40 dB range, any spectral feature more than 40 dB below the peak is clipped to the noise color. For Raman-suppression optimization results where the Raman lobe is being pushed down by 36–42 dB (per the run summary: J drops from -24.9 dB to -61.8 dB), the Raman lobe at the fiber output may be entirely within the noise floor of a 40 dB display. The optimization improvement is invisible in the evolution plot.

A second problem: `P_max = maximum(P)` computes the global maximum over all z positions and all wavelengths. If there is a brief spike near the input (where peak power is highest), this sets the reference too high, pushing the far-end spectrum down by 10–20 dB relative to what an advisor would expect.

**Consequences:**
- The Raman lobe suppression — the entire scientific result — is not visible in the evolution heatmap
- The spectral broadening at the output appears weaker than it is

**Prevention:**
1. Increase default `dB_range=60.0` for spectral evolution (the comparison spectrum already uses 60 dB).
2. Optionally normalize to the output power (`P_max = maximum(P[end, :])`) or provide a `normalize_to=:output/:input/:global` kwarg.
3. Document clearly in the colorbar label which reference is used: "Power [dB re: peak at z=0]" vs "Power [dB re: global max]".

**Warning signs:**
- J-function shows 40+ dB improvement but the evolution heatmap looks unchanged between optimized and unshaped
- The Raman lobe is not visible in the heatmap at any z position

**Phase:** Address in the dB normalization standardization phase.

---

### Pitfall 9: Hard-Coded Colors Inconsistent With the Okabe-Ito Palette

**What goes wrong:**
The global constants `COLOR_INPUT = "#0072B2"` and `COLOR_OUTPUT = "#D55E00"` (Okabe-Ito, lines 47–50) are defined but not consistently used. In `plot_optimization_result_v2`, input is plotted as `"b--"` (matplotlib blue, not Okabe-Ito blue) and output as `"darkgreen"`. In `plot_spectrum_comparison`, input is `"b-"` and output is `"r-"`. In the amplitude result, both panels use `"b-"` for input and `"r-"` for output.

The inconsistency means:
- Input is sometimes Okabe-Ito blue (#0072B2), sometimes matplotlib blue (#1f77b4), sometimes pure blue (rgb 0,0,1)
- Output is sometimes vermillion (#D55E00), sometimes dark green, sometimes pure red

**Consequences:**
- When two plots from the same run are shown side by side (lab meeting), the colors imply different physical meaning
- Audience builds incorrect mental model: "blue = input" in one figure, but "blue = shaped" in another

**Prevention:**
Use `COLOR_INPUT` and `COLOR_OUTPUT` everywhere. Grep the file for `"b-"`, `"r-"`, `"b--"`, `"k-"` and replace with the appropriate constant. Reserve `COLOR_REF` (black) for derived quantities (phase, group delay) that are neither input nor output.

**Warning signs:**
- Running a side-by-side comparison and noticing the colors don't match
- A new team member asks "why is input sometimes blue and sometimes a different blue?"

**Phase:** Color standardization pass — low effort, high consistency payoff.

---

### Pitfall 10: Missing Fiber and Pulse Parameter Annotations

**What goes wrong:**
Plots saved to disk have filenames like `opt.png` and `opt_phase.png`. The figures themselves contain no annotation identifying which fiber configuration (SMF-28 vs HNLF), fiber length, peak power, or pulse width they represent. If multiple runs are compared in a lab meeting presentation, every figure looks identical in structure and the only way to tell them apart is the filename or external context.

**Consequences:**
- Advisor asks "which fiber is this?" during a meeting
- A figure saved to a results folder six months later is ambiguous
- When preparing a paper, figures cannot be self-consistently referenced

**Prevention:**
Add a `fig.suptitle()` or an `ax.set_title()` annotation block to every output figure. Minimally include: fiber type, L [m], peak power P [W], λ₀ [nm]. Ideally: pulse width (FWHM), J before/after, run timestamp. This is already partially done for `plot_optimization_result_v2` (J annotation exists) but the fiber parameters are missing. Pass a `metadata` dict to each plot function.

**Warning signs:**
- You need to open the log file to identify what a saved plot shows
- Two plots from different runs look identical in structure and cannot be distinguished by their content alone

**Phase:** Annotation pass — must coincide with the metadata infrastructure phase.

---

## Minor Pitfalls

Small issues that reduce professional quality but do not mislead.

---

### Pitfall 11: Instantaneous Frequency Without Time Axis Masking

**What goes wrong:**
`compute_instantaneous_frequency` computes `dφ/dt / 2π` from the full time-domain field including the simulation window edges. At the edges of the time window, the field approaches zero and phase derivatives become numerically unstable. The auto-limit function `_auto_time_limits` clips the x-axis, but the y-axis of the instantaneous frequency panel is not clipped. Edge values can be ±10 THz even when the physical chirp in the pulse region is ±0.1 THz, making the useful portion of the plot occupy <10% of the y-axis range.

**Prevention:**
Apply a power mask in the time domain: set `Δf_inst` values to `NaN` where `abs2(ut) < threshold * maximum(abs2(ut))`. Use a threshold of 1e-3 (−30 dB) in the temporal domain.

**Phase:** Phase diagnostic fix pass.

---

### Pitfall 12: GDD Panel Y-Axis Scaling

**What goes wrong:**
`_second_central_diff` sets boundary values to `NaN` (line 176), which is correct. However, the finite differences amplify noise quadratically. Even with the -30 dB mask, the GDD values at the edges of the signal band (where the mask transitions from valid to NaN) are large. These boundary-adjacent samples can be ±10⁶ fs² even when the physical GDD throughout the pulse bandwidth is ~1000 fs². The result is a nearly flat line at 0 with two enormous spikes on either side, effectively showing nothing.

**Prevention:**
After computing GDD, apply a percentile clip: set values outside the 2nd–98th percentile of the valid (non-NaN) samples to NaN. This is standard practice for derivative-based quantities. Alternatively, explicitly set `ylim` to `(-5 * median_GDD, +5 * median_GDD)`.

**Phase:** Phase diagnostic fix pass.

---

### Pitfall 13: Legend Proliferation on Dense Spectral Plots

**What goes wrong:**
The spectral comparison rows in `plot_optimization_result_v2` include legends with entries for "Input", "Output", "Raman band", and "Raman onset" — four legend entries in a panel that is typically 6×4 inches. On the evolved spectral plots, the legend occupies the upper-right corner, which is exactly where spectral broadening features appear.

**Prevention:**
Move the Raman band and onset entries out of the legend — they are visually obvious from the shading and dashed line. Use a text annotation (`ax.text()`) for the Raman label positioned outside the data region. Reduce the legend to "Input" and "Output" only.

**Phase:** Polish pass.

---

### Pitfall 14: Saving to PNG Without Specifying Backend Resolution Profile

**What goes wrong:**
PyPlot (Julia's matplotlib wrapper) inherits whatever `figure.dpi` is set in rcParams at figure creation time. The codebase sets `figure.dpi=150` and `savefig.dpi=300`. However, when `plot_combined_evolution` calls `fig.subplots_adjust` and then saves with `bbox_inches="tight"`, the saved figure dimensions depend on the display DPI, not the save DPI. The result is that colorbars and manually-positioned axes (via `fig.add_axes(...)`) can appear displaced between screen preview and saved PNG.

**Prevention:**
Do not mix manually-positioned axes (via `fig.add_axes`) with `bbox_inches="tight"`. If using `constrained_layout`, remove the manual colorbar axes and use matplotlib's built-in colorbar allocation. Verify output dimensions by checking the pixel count of the saved file on first run.

**Phase:** Layout fix pass.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Colormap replacement | Replacing jet globally without checking each plot's data type (diverging vs sequential) | Verify each heatmap is sequential dB data before applying inferno; use a diverging map only if data has a meaningful zero |
| Phase diagnostic fix | Masking NaN propagation breaking unwrap | Apply mask before unwrapping, not after |
| Raman shading bug | Over-correcting produces shading too narrow to see | Use explicitly computed wavelength bounds from Raman physics (13.2 THz shift, ~10 nm FWHM for silica) |
| Normalization unification | Cross-column normalization changes the J-function dB annotation meaning | Recompute J annotation relative to the global reference, not per-column |
| Axis sharing | Sharing time axis between before/after hides compression | Check whether shared axis enhances or obscures the scientific result; provide both |
| Annotation metadata | Adding too many annotations clutters the plot | Restrict per-figure annotations to fiber type, L, P, λ₀; put full parameters in figure caption/suptitle |
| constrained_layout migration | Constrained layout changes subplot spacing | Audit figsize after switching — may need to increase height by ~15% |
| pcolormesh grid fix | Sorting wavelength grid also sorts color data incorrectly if sort_idx not applied to 2D data | Apply sort_idx along the wavelength axis (axis=1) of the 2D power matrix, not axis=0 |

---

## Sources

- [Matplotlib: Choosing Colormaps](https://matplotlib.org/stable/users/explain/colors/colormaps.html) — HIGH confidence, official docs
- [Crameri et al. 2021, HESS 25:4549](https://hess.copernicus.org/articles/25/4549/2021/hess-25-4549-2021.html) — HIGH confidence, peer-reviewed quantitative analysis of rainbow colormap harm
- [Joseph Long: Fix your matplotlib colorbars](https://joseph-long.com/writing/colorbars/) — MEDIUM confidence, widely-cited practical guide
- [Matplotlib: Constrained layout guide](https://matplotlib.org/stable/users/explain/axes/constrainedlayout_guide.html) — HIGH confidence, official docs
- [Wilke: Fundamentals of Data Visualization, Ch. 21](https://clauswilke.com/dataviz/multi-panel-figures.html) — HIGH confidence, canonical data visualization reference
- [rp-photonics: Group Delay Dispersion](https://www.rp-photonics.com/group_delay_dispersion.html) — HIGH confidence, authoritative optics reference
- Codebase audit: `scripts/visualization.jl` lines 199–205, 335, 396, 453, 503, 610–618, 664–699 — direct observation, HIGH confidence
- Run log: `results/raman/raman_run_20260324_v7.log` line 35 — direct observation of pcolormesh warning
