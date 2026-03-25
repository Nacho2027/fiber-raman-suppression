# Feature Landscape: Scientific Visualization for Nonlinear Fiber Optics

**Domain:** Spectral phase optimization / Raman suppression in single-mode fibers
**Researched:** 2026-03-24
**Confidence overall:** HIGH for conventions (multiple sources), MEDIUM for some specific choices

---

## 1. Wrapped vs Unwrapped Spectral Phase — Definitive Recommendation

**Recommendation: Show group delay τ(ω) as the primary phase panel. Keep unwrapped φ(ω) in a secondary diagnostic panel. Never show wrapped phase [0, 2π] as a primary result.**

### Evidence

The rp-photonics spectral phase encyclopedia article confirms that **deviations from a flat spectral phase are the informative measure** — which requires seeing the full shape, not a series of 2π jumps. Wrapped phase destroys this information for readers.

The rp-photonics group delay article states explicitly: "Group delay calculation is an original alternative to spectral phase calculation and brings equivalent results with the advantage of being **more direct**." The derivative τ(ω) = dφ/dω has units of time (femtoseconds), which maps directly to how much each wavelength component is advanced or delayed. A reader can immediately answer "does this pulse have chirp here?" from group delay without doing mental integration.

Agrawal (NLFO, Ch. 3) plots group delay dispersion (GDD = d²φ/dω²) as the design parameter for fiber dispersion, treating phase only implicitly. He does not plot φ(ω) directly.

Dudley et al. 2006 (Rev. Mod. Phys. 78, 1135) — the canonical supercontinuum reference — does not include spectral phase plots at all in the main figures. The standard figure set (replicated in Matlab reference code at `jtravs/SCGBookCode`) is: spectral evolution 2D map + temporal evolution 2D map, 40 dB scale.

The gnlse-python package (WUST-FOG, one of the main community GNLSE implementations) shows no spectral phase panel whatsoever — intensity only.

### Decision Tree for Phase Representation

| Use Case | Recommended | Avoid |
|----------|-------------|-------|
| Main optimization comparison | Group delay τ(ω) [fs] vs wavelength | Wrapped phase (useless discontinuities) |
| Diagnosing oscillatory artifacts / GDD | Unwrapped φ(ω) [rad] masked where power < −30 dB | Full unwrapped over noise (wild oscillations) |
| Checking dispersion character (chirp) | GDD d²φ/dω² [fs²] | — |
| Communicating physical delay to audience | Group delay τ(ω) [fs] | Raw phase [rad] (requires mental differentiation) |

### When Unwrapped Phase is Appropriate

Include unwrapped φ(ω) in the **phase diagnostic panel** (not the main comparison) when:
- Debugging phase mask artifacts
- Verifying the optimization variable directly
- Checking for discontinuities or numerical issues

Always mask below −30 dB relative to spectral peak to prevent noise-floor phase (which is meaningless) from dominating the axis scale.

### Why the Code's Existing [0, 2π] Wrapped Display is Wrong

The current `wrap_phase()` and `set_phase_yticks!()` functions map phase to [0, 2π] and label axes with "0, π/2, π, 3π/2, 2π". This is the wrong representation because:
1. Optimization produces slowly varying phase profiles that typically span many × 2π — wrapping makes a smooth curve look like a sawtooth
2. The wrapped version tells you nothing about the shape of the applied phase mask
3. Group delay is what physically determines temporal redistribution of spectral components, which is the mechanism for Raman suppression

---

## 2. Table Stakes — Features Required for Professional Plots

Missing any of these makes plots look unprofessional or uninterpretable.

| Feature | Why Required | Current Status |
|---------|-------------|---------------|
| Perceptually uniform colormap for heatmaps | Jet creates false structure; community moved away from it | Bug: still using "jet" |
| Raman band marked as narrow shaded region, not full-width span | Readers need to know exactly which frequencies are the target | Bug: axvspan uses wrong bounds |
| dB scale for all spectral plots | Log scale required to see broadband features; linear hides sidelobes | Present |
| Wavelength axis [nm] for all spectral plots | Standard in fiber optics (not frequency offset) | Present |
| Time axis [ps] for all temporal plots | Standard unit for fs-ps pulse regime | Present |
| Shared axis ranges between before/after comparison panels | Mismatched ranges prevent visual comparison | Active issue |
| Cost function value J annotated on spectral panels | Reader needs to know the optimization metric without reading logs | Present (but see notes) |
| Fiber length L and center wavelength λ₀ as figure-level annotation | Without this, plots have no context at all; change L by 2× and everything shifts | Missing |
| Peak power P₀ annotated | Different power means different nonlinearity regime; context critical | Missing |
| dB range −40 dB floor on spectral evolution heatmaps | Dudley 2006 reference code uses 40 dB; standard in field; anything below is noise floor | Present; confirm |
| Colorbar with dB label on every heatmap | Every 2D plot must label its color axis | Present |
| Separate input and output curves in distinct colors, consistent across figures | Input always same color, output always same color — reader learns the code | Partially present; inconsistent |

### Raman Band Shading — Correct Specification

The Raman gain peak in silica fiber is at ~13.2 THz downshift from pump. For pump at 1550 nm (193.4 THz), the Raman peak is at ~1660 nm. The band that matters spans roughly 10–15 THz downshift (~100 nm wide at 1550 nm).

Correct `axvspan` bounds: compute `λ_raman_start = C/(f0 - 10.0)` and `λ_raman_end = C/(f0 - 15.0)` in nm. The current code computes `λ_raman = λ_nm[raman_λ_idx]` where `raman_λ_idx = Δf_shifted .< raman_threshold`, which likely spans from the onset to the negative-frequency edge of the FFT grid — wrong.

---

## 3. Differentiators — Features That Mark High-Quality Plots

These separate "a plot that runs" from "a plot that communicates."

| Feature | Value | Complexity |
|---------|-------|------------|
| Metadata annotation block per figure | Every plot self-documenting without filename context | Low |
| −30 dB mask on phase panels | Phase below noise floor is meaningless — masking prevents wild oscillations dominating the axis | Low (present in code, verify applied) |
| GDD trace in phase diagnostic | Shows what dispersion the optimization is applying — directly maps to pulse compressor physics | Low |
| Cost function expressed in dB alongside linear: "J = 0.0012 (−29.2 dB)" | dB is intuitive for suppression ratios; linear alone is not | Trivial (already in code — keep) |
| Evolution colorbar normalized to input peak, not frame maximum | Allows comparison of input vs output evolution on same scale | Medium |
| Raman onset vertical dashed line on spectra | Shows readers the critical threshold frequency — context for the optimization goal | Low (present) |
| Inset zoom on temporal panel when pulse disperses heavily | Long fibers produce spread-out pulses; zoom shows peak structure | Present (conditional) |
| Fiber type label in plot title or annotation (e.g., "SMF-28", "HNLF") | Identical plots from different fibers look the same without this | Missing |
| Optimization iteration count and initial J₀ on convergence plot | Context: did it converge? How much room was there? | Missing |
| Pulse width FWHM in annotation (not just "Peak in: X W") | FWHM maps to transform-limited duration concept | Missing |
| Energy fraction table: pump band / Raman band / other | Shows where energy went, not just Raman fraction | Medium |
| Before/after Raman fraction improvement as ΔdB annotation | E.g., "−8.3 dB suppression" directly labels the result | Low |

### Metadata Annotation Block — Recommended Format

Every figure should carry (either in suptitle or as axes-fraction text):

```
SMF-28 | L = 2.0 m | λ₀ = 1550 nm | P₀ = 30 W | T_FWHM = 185 fs | J_before → J_after
```

This can be placed as `fig.suptitle(...)` or as a text annotation in a top-of-figure stripe. Audience is the research group, so dense annotation is appropriate — there is no journal page limit constraint here.

---

## 4. Anti-Features — What to Deliberately NOT Do

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Wrapped phase [0, 2π] as primary display | Sawtooth pattern tells reader nothing about phase shape | Group delay τ(ω) [fs] |
| Jet colormap | Non-perceptually-uniform; creates false spectral features; field has moved on | Magma or inferno (see below) |
| Raman shading spanning from onset to plot edge | Covers most of the spectral plot; obscures the data being compared | Narrow band marking: onset line + shaded 10–15 THz window only |
| Mismatched x-axis ranges between before/after panels | Comparison impossible if ranges differ | Shared xlim determined before creating subplots |
| Phase panels over full grid including noise floor | Noise floor phase is numerically random, oscillates wildly, dominates axis scale | Always apply −30 dB mask before plotting phase quantities |
| Separate figures per run that require external filenames to interpret | Breaks "self-documenting" principle | Embed fiber/pulse params in every figure |
| Plotting temporal evolution with initial pulse auto-centering on z=0 but final pulse dispersed off-frame | Reader loses the output pulse | Use energy-window method to span both input and output, with zoom inset |
| Cost function J without dB conversion | J = 0.001 is meaningless without context; dB scale gives intuition | Always show both: "J = 0.001 (−30.0 dB)" |
| Evolution colorbar labeled just "dB" without normalization reference | Is this normalized to input? To frame maximum? Ambiguous | Label as "Power [dB, re peak]" |
| Showing evolution only for optimized run without baseline run | Optimization result is uninterpretable without the unshaped reference | Both runs must appear side by side or in labeled pairs |

---

## 5. Colormap Recommendation — Evidence-Based

**Recommendation: Use `magma` for all spectral and temporal evolution heatmaps.**

### Evidence

The gnlse-python community package (WUST-FOG, actively maintained, used in Dudley group tradition) uses `magma` as its default colormap — found directly in `gnlse/visualization.py`.

Luna.jl (Julia nonlinear optics package) uses a −40 dB floor with perceptually uniform colormaps.

Matplotlib official documentation (matplotlib 3.10) classifies `magma`, `inferno`, `viridis`, `plasma` as the "Perceptually Uniform Sequential" category, explicitly recommended for sequential intensity data. `jet` is in the "Miscellaneous" category with explicit warnings about non-uniformity.

Kenneth Moreland's color advice (referenced by matplotlib): "Do not use rainbow colormaps. The perception of color is not monotonic, causing false perceptual boundaries in the data."

**Why magma over inferno/viridis for this application:**
- `magma` starts near-black (dark background = zero/noise), transitions through purple and orange to near-white at peak — this creates a natural "dark is background, bright is signal" mapping that matches dB power displays intuitively
- `inferno` is very similar; either works. Magma has slightly warmer mid-tones, more legible in print
- `viridis` (blue-green-yellow) is excellent for general scientific use but the green midrange blends with many journal figure annotation colors
- `hot` (black-red-yellow-white) is not perceptually uniform but has a long tradition in the field; acceptable if the group has strong prior preference, but magma is strictly better

**For temporal and spectral 2D evolution: `magma`**
**For spectrogram (STFT, time-frequency): `inferno` or `magma` (either)**
**Never: `jet`, `hot`, `rainbow`, `hsv`**

---

## 6. Standard Plot Set Per Run

Based on: Dudley 2006 canonical set + pulse shaping literature + current project structure.

**Recommended output per optimization run: 4 files (matches current structure, fix contents)**

### File 1: `opt.png` — The Primary Result (3×2 layout)

The main deliverable showing what the optimization achieved.

| Panel | Content | Notes |
|-------|---------|-------|
| (1,1) Input spectrum before opt | Wavelength [nm], dB scale, Raman band shaded | Reference |
| (1,2) Output spectrum after opt | Same scale, same xlim, J annotated | Comparison |
| (2,1) Temporal pulse before opt | Time [ps], energy-window limits | Temporal context |
| (2,2) Temporal pulse after opt | Same shared xlim as (2,1) | Must match |
| (3,1) Group delay before opt | τ(ω) [fs], −30 dB masked, Raman onset line | Phase result |
| (3,2) Group delay after opt | Same range as (3,1) | Phase comparison |

**Suptitle**: "SMF-28 | L=2.0 m | P₀=30 W | λ₀=1550 nm | FWHM=185 fs | J: 0.0234 → 0.0012 (−13.1 dB)"

### File 2: `opt_phase.png` — Phase Diagnostic Panel (2×2 layout)

Diagnostic for understanding what the optimizer did, not for presenting to external audiences.

| Panel | Content | Notes |
|-------|---------|-------|
| (1,1) Unwrapped φ(ω) [rad] vs wavelength | After optimization; −30 dB masked | Shows raw optimization variable |
| (1,2) Group delay τ(ω) [fs] vs wavelength | After optimization; −30 dB masked | Human-readable phase |
| (2,1) GDD d²φ/dω² [fs²] vs wavelength | After optimization; masked | Dispersion character |
| (2,2) Instantaneous frequency Δf(t) [THz] vs time | Of shaped input pulse | Time-domain frequency sweep |

**Suptitle**: "Phase diagnostic — [same params]"

### File 3: `opt_evolution_unshaped.png` — Baseline Evolution (2-panel)

The unshaped pulse propagation. Shows what happens without optimization — the Raman problem.

| Panel | Content | Notes |
|-------|---------|-------|
| Top | Temporal evolution heatmap, magma, −40 dB, time axis centered | |
| Bottom | Spectral evolution heatmap, magma, −40 dB, wavelength axis | Raman onset line overlaid |

**Suptitle**: "Baseline (unshaped) — [params]"

### File 4: `opt_evolution_optimized.png` — Optimized Evolution (2-panel)

Identical layout to File 3. Side-by-side with File 3, reader can compare directly.

**Suptitle**: "Optimized — [params] | J = 0.0012 (−29.2 dB)"

### Optional File 5: `opt_convergence.png`

Convergence J vs iteration, log scale. Include:
- Horizontal dashed line at J_initial
- Annotation "J₀ = X, J_final = Y, ΔdB = Z"
- Only needed for reports or debugging; current code already handles this

---

## 7. Spectral Evolution Heatmap — Detailed Specification

Based on Dudley 2006 code reference (`jtravs/SCGBookCode`) and gnlse-python conventions.

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Color floor | −40 dB | Industry standard; gnlse-python and Luna.jl both use this |
| Color ceiling | 0 dB | Normalized to peak |
| Normalization reference | Global peak across all z-steps | Not per-row; evolution should show energy redistribution |
| Wavelength window | λ₀ ± [400, 700] nm or physics-driven | Cover Raman soliton (~100 nm red) + dispersive wave (~200 nm blue), but exclude noise floor edges |
| Colormap | magma | Per community standard above |
| Raman band | Vertical dashed line at onset (13 THz shift) | Do not shade the heatmap — too visually noisy on a dark background |
| Colorbar label | "Power [dB, re peak]" | Specifies normalization |
| z-axis label | "Length [m]" or "Length [mm]" depending on scale | Auto-select based on max(zsave) |
| Shared colorbar | Both panels (temporal + spectral) share one colorbar | Saves space; same scale |

### Axis Range Selection — Anti-Noise-Floor Rule

The spectral window must be determined from the 0 dB region, not from the simulation grid edges. Strategy:

1. Find the spectral range where peak power (over all z) exceeds −35 dB
2. Add 50 nm margin on each side
3. Never let the window be smaller than λ₀ ± 300 nm

For temporal evolution, use the energy-window method (99.9% energy) with padding, not FWHM of initial pulse. Dispersed pulses at long fiber can spread 10× the input duration.

---

## 8. Before/After Comparison — Layout Principles

Based on pulse shaping literature and visual communication research.

**Use side-by-side columns, not sequential rows.** The brain compares features at the same vertical position more easily than top-to-bottom. The existing 3×2 layout (3 rows, 2 columns = before/after) is correct.

**Axis locking is mandatory.** If before and after spectral panels have different ylim, the reader cannot see whether suppression occurred or whether it was just autoscaling. All paired panels must share xlim AND ylim. Compute both datasets first, then set limits.

**Annotation of the key metric directly on the figure.** Do not require readers to compute J_before - J_after in dB. State it: "Raman suppression: −13.1 dB" in a prominent annotation on the comparison spectra.

**Color convention must be consistent across all figures:**
- Input / unshaped / before → COLOR_INPUT (`#0072B2`, Okabe-Ito blue)
- Output / optimized / after → COLOR_OUTPUT (`#D55E00`, Okabe-Ito vermillion)
- Raman band / reference → `#CC79A7` (Okabe-Ito reddish purple)
- Raman onset line → same purple, dashed
- Black for neutral traces (phase, diagnostic)

This convention is already defined in the code but inconsistently applied — the optimization result function uses hardcoded `"b--"`, `"r-"`, `"darkgreen"` instead of the named constants.

---

## 9. Self-Documenting Annotation Standard

Every figure needs a **run parameter block** that makes the figure interpretable without the filename or external context. Audience is research group at lab meetings.

### Minimum Required Annotations

```
Fiber type:       SMF-28  [or HNLF]
Fiber length:     2.0 m
Center wavelength: 1550 nm
Peak power:       30 W
Pulse FWHM:       185 fs
Optimization type: Phase [or Amplitude]
Cost J:           0.0234 → 0.0012  (−13.1 dB improvement)
```

### Placement

Use `fig.suptitle()` with the first three fields (fiber type, L, λ₀) as a compact single-line header. For individual panels that show optimization results, add a small text box (axes fraction coordinates) with J value and improvement.

The existing bbox annotation pattern in the code (`Dict("boxstyle"=>"round,pad=0.3", ...)`) is correct — keep it.

### What Annotations Are NOT Needed in Research Group Context

- Author name (this is internal)
- Date (filenames have timestamps)
- Simulation parameters that don't vary run-to-run (dt, Nt, solver tolerances)
- Intermediate numerical values (β₂, β₃, γ) — these are fiber-type-determined

---

## 10. Phase Plot Readability — Specific Fixes

The existing phase diagnostic panel has known issues: "oscillatory artifacts, empty panels." Here is the root cause and fix.

### Oscillatory Artifacts (Root Cause)

Phase derivative on noise floor oscillates wildly. A 1 dB fluctuation in spectral power corresponds to a random phase change of up to 2π between adjacent frequency samples. When you differentiate this, you get Δf-scale oscillations in group delay that can be ±10⁶ fs.

**Fix already in code:** `_apply_dB_mask()` with `threshold_dB=-30`. Verify it is applied to τ_masked and gdd_masked before plotting. The axis autoscale then only shows the meaningful region.

### Empty Panels

If a panel appears empty, the masked data is all NaN. This happens when:
1. The spectral window is outside the signal region (wrong xlim)
2. The −30 dB threshold is too aggressive for the power level

**Fix:** Set xlim to the wavelength range where the spectrum is strong (±200 nm from λ₀ for normal propagation), not ±800 nm. Current xlim `λ0_nm - 300, λ0_nm + 500` may be too wide for short fibers where broadening is minimal.

### GDD Panel Wild Excursions

GDD is a second derivative — noise is amplified twice. Even with masking, edge effects near the 30 dB boundary cause spikes.

**Fix:** Clip GDD display to physically reasonable range: `±10000 fs²` for SMF-28. GDD of silica fiber is ~−21700 fs²/m at 1550 nm, so a 2m fiber accumulates ~−43000 fs² of dispersion. Any GDD values beyond ±50000 fs² are numerical artifacts — clip them.

---

## Sources

- Dudley, Genty, Coen. "Supercontinuum generation in photonic crystal fiber." Rev. Mod. Phys. 78, 1135 (2006) — [link](https://link.aps.org/doi/10.1103/RevModPhys.78.1135)
- Reference MATLAB code for Dudley 2006 figures: [jtravs/SCGBookCode](https://github.com/jtravs/SCGBookCode/blob/master/test_Dudley.m) — confirmed 40 dB range, wavelength [nm] axis, distance [m] axis
- gnlse-python WUST-FOG visualization module (verified directly from source): [github.com/WUST-FOG/gnlse-python](https://github.com/WUST-FOG/gnlse-python) — confirmed `magma` default, −40 dB floor, "Wavelength [nm]", "Distance [m]"
- Luna.jl documentation: [github.com/LupoLab/Luna.jl](https://github.com/LupoLab/Luna.jl) — confirmed `dBmin=-40`, wavelength range parameter
- Matplotlib colormap documentation: [matplotlib.org/stable/users/explain/colors/colormaps.html](https://matplotlib.org/stable/users/explain/colors/colormaps.html) — confirmed magma/inferno/viridis as perceptually uniform; jet explicitly deprecated for scientific use
- rp-photonics group delay: [rp-photonics.com/group_delay.html](https://www.rp-photonics.com/group_delay.html) — group delay as derivative of spectral phase; direct quantity for temporal characterization
- rp-photonics spectral phase: [rp-photonics.com/spectral_phase.html](https://www.rp-photonics.com/spectral_phase.html) — deviations from flat phase as the informative measure; pulse compression quality
- Kenneth Moreland color advice: [kennethmoreland.com/color-advice/](https://www.kennethmoreland.com/color-advice/) — do not use rainbow colormaps; perceptual uniformity requirement
- Raman gain peak in silica: ~13.2 THz downshift from pump — [rp-photonics.com/raman_scattering.html](https://www.rp-photonics.com/raman_scattering.html)
