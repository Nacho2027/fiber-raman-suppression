# Visualization Research Report: Complete Overhaul for Readability

**Project:** Fiber Optics Raman Suppression Optimization — SMF Gain/Noise
**Date:** 2026-03-12
**Scope:** Every PNG output in `smf-gain-noise/`, all plotting code in `visualization.jl`

---

## Table of Contents

1. [Published Best Practices Summary](#1-published-best-practices-summary)
2. [Figure-by-Figure Problem Catalog](#2-figure-by-figure-problem-catalog)
3. [Caption Text for Every Figure Type](#3-caption-text-for-every-figure-type)
4. [Recommended Figure Architecture](#4-recommended-figure-architecture)
5. [Phase Display Recommendation](#5-phase-display-recommendation)
6. [Color Palette Specification](#6-color-palette-specification)
7. [Font Size and Figure Size Table](#7-font-size-and-figure-size-table)
8. [Physics Glossary for Annotations](#8-physics-glossary-for-annotations)

---

## 1. Published Best Practices Summary

### 1.1 Rougier, Droettboom & Bourne — "Ten Simple Rules for Better Figures" (PLOS Comp Bio, 2014)

The canonical reference for scientific figure design. Key rules adapted to this project:

**Rule 1 — Know Your Audience.** Our reader is a fiber optics researcher seeing these optimization results for the first time. They understand β₂, GDD, and Raman scattering but have NO context for what "J = −36.3 dB" means or why a particular spectral phase shape is beneficial. Every figure must bridge this gap.

**Rule 2 — Identify the Message.** Each figure should answer ONE question. Currently, the 3×2 optimization panels try to answer three questions simultaneously (spectral change, temporal change, phase profile) crammed into a single figure. Split them.

**Rule 3 — Adapt the Figure to the Medium.** At 300 DPI on a 12×12-inch canvas, the current 3×2 panels produce subplots of roughly 5×3.5 inches each—adequate for print but the zoom insets shrink usable area to ~2×1.5 inches, which is unreadable.

**Rule 4 — Captions Are Not Optional.** NONE of the 30+ figures in the repository have captions. Every figure MUST have a descriptive caption (2–3 sentences) below the plot area explaining what is shown, how to read it, and the key takeaway.

**Rule 5 — Do Not Mislead the Reader.** The chirp sensitivity TOD panel uses matplotlib's scientific offset notation (`−3.631e1`) which makes a 0.05 dB variation look like it spans the full axis range. This is actively misleading.

**Rule 6 — Avoid Chartjunk.** The massive pink `axvspan` Raman band shading in amplitude plots consumes >50% of the spectral subplot area and obscures the actual data.

**Rule 7 — Use Color Effectively.** The `jet` colormap is used for all evolution plots. Jet is perceptually non-uniform, misleading under colorblind conditions, and has known luminance reversals. Replace with `inferno`, `viridis`, or `cividis`.

### 1.2 Rougier — "Scientific Visualization: Python + Matplotlib" (2021)

Key recommendations from this open-access book:

- **Figure sizing:** Size figures for their final use. A two-column journal figure is ~7 inches wide; a single-column is ~3.5 inches. Design at final size, never shrink.
- **Font hierarchy:** Title 14pt → axis labels 12pt → tick labels 10pt → annotations 9pt → inset labels 8pt. Current code (11/12/13/10/10/10) is too compressed.
- **Whitespace:** Use `constrained_layout` or generous `subplots_adjust` rather than `tight_layout`, which often clips labels.
- **Colormaps:** Perceptually uniform colormaps (viridis, magma, inferno) ensure that equal data differences produce equal visual differences. Jet fails this test.
- **Annotations:** Place annotations OUTSIDE the data area when possible. Use leader lines sparingly. Current annotations (white boxes with text) obscure data underneath.

### 1.3 Ultrafast Optics Visualization Conventions

**Dudley et al. (Rev. Mod. Phys. 2006) — The standard for supercontinuum figures:**

- Spectral evolution: wavelength (nm) on x-axis, propagation distance on y-axis, power (dB, 40 dB range) as color
- Temporal evolution: delay (ps) on x-axis, distance on y-axis, power (dB) as color
- Single-line spectra: wavelength on x-axis, power spectral density in dB on y-axis
- Pump wavelength always marked with a dashed vertical line

**Agrawal "Nonlinear Fiber Optics" (6th ed., 2019):**

- Temporal pulses shown normalized (P/P₀) rather than absolute watts
- Evolution plots use linear or dB color scale depending on dynamic range
- Phase shown as unwrapped spectral phase or group delay, never wrapped [0, 2π]

**Modern Optica/Optics Letters conventions (2020–2025):**

- Colorblind-safe palettes required by many journals
- Phase displayed as group delay τ(ω) in femtoseconds, or as deviation from transform-limited
- Dual-axis plots (intensity + phase on same wavelength axis) are the standard for pulse characterization

---

## 2. Figure-by-Figure Problem Catalog

### 2.1 Phase Optimization Comparison — `raman_opt_L1m_P005W.png`

**What it shows:** 3×2 grid comparing unshaped (left) vs. optimized (right) pulse propagation through 1 m of SMF at P = 0.05 W. Row 1: spectra. Row 2: temporal pulse. Row 3: spectral phase.

**Problems identified:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | No caption anywhere on the figure | Critical | Add `fig.text()` caption below plot |
| 2 | Phase row (Row 3) shows 2π-wrapped phase — completely uninterpretable staircase pattern | Critical | Replace with group delay τ(ω) in fs |
| 3 | "Phase detail" inset in Row 3 is ~2×1.5 inches, axes unreadable | High | Remove inset; make group delay its own full-width plot |
| 4 | "Before optimization" / "After optimization" titles are vague | Medium | Retitle: "Unshaped pulse (φ = 0)" / "Optimized spectral phase" |
| 5 | J annotation uses both linear and dB: "J = 0.0033 (−24.8 dB)" — redundant and cluttered | Medium | Show only dB value with brief label: "Raman band energy: −24.8 dB" |
| 6 | Green output line hard to distinguish from blue input on shared axis | Medium | Use Okabe-Ito palette: input = `#0072B2` (blue), output = `#D55E00` (vermillion) |
| 7 | Peak power annotation "Peak in: 2959 W / Peak out: 5508 W" — raw watts are jarring without context | Low | Add parenthetical: "(~185 fs sech² pulse)" |
| 8 | No pump wavelength marker on spectral plots | Low | Add λ₀ ≈ 1550 nm dashed line |

### 2.2 Phase Optimization — `raman_opt_L2m_P015W.png`

**What it shows:** Same 3×2 layout for L = 2 m, P = 0.15 W. Stronger nonlinear regime.

**Additional problems beyond §2.1:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | Temporal zoom inset appears (pulse is more dispersed) — axes completely unreadable at this size | Critical | Remove inset; create separate zoomed temporal plot |
| 2 | Output spectrum shows clear Raman shoulder at 1600–1700 nm but no annotation pointing it out | Medium | Add arrow annotation: "Raman shoulder" |
| 3 | Phase staircase (bottom-right) shows ~5 narrow notches — these are the phase features doing the optimization work, but they're invisible at this scale | High | Group delay plot would reveal these as sharp delay features |

### 2.3 Phase Optimization — `raman_opt_L5m_P015W.png`

**What it shows:** 3×2 layout for L = 5 m, P = 0.15 W. Most nonlinear case.

**Critical additional problems:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | "Before" temporal output extends from −2 to +10 ps with huge sidelobes — this is soliton fission + SSFS but there is NO explanation | Critical | Caption must explain: "Temporal broadening due to soliton fission and self-frequency shift" |
| 2 | "After" temporal output shows two distinct peaks — is this physical or a boundary artifact? No way to tell from the figure | Critical | Add boundary status annotation; caption must address this |
| 3 | Zoom insets in temporal row show the input pulse peak (−0.3 to +0.3 ps range) but the interesting physics is the dispersed output (−2 to +10 ps) — wrong zoom target | High | If zooming, zoom on the OUTPUT structure, not the input |
| 4 | Phase row bottom-right shows extreme staircase with many narrow notches — the most complex phase profile, yet completely unreadable | Critical | Group delay representation essential here |
| 5 | J improved from −0.9 dB to −11.9 dB — a 10× improvement — but the figure doesn't emphasize this | Medium | Add improvement annotation: "ΔJ = −11.0 dB (12.6× reduction)" |

### 2.4 Amplitude Optimization — `amp_opt_L1m_P015W_d030.png`

**What it shows:** 3×2 grid for amplitude optimization at L = 1 m, P = 0.15 W, δ = 0.30. Row 1: spectra. Row 2: temporal. Row 3: amplitude profile A(ω).

**Problems identified:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | **MASSIVE pink Raman band shading** fills >50% of spectral area (Row 1) | Critical | Replace with thin dashed vertical line at Raman onset (matching phase optimization style) |
| 2 | Red output line nearly invisible against pink background | Critical | Consequence of #1; fixing shading fixes this |
| 3 | No caption | Critical | Add caption |
| 4 | Amplitude profile (Row 3) — the "After" panel shows a sharp dip at ~1550 nm with A dropping to 0.70 — this is the key result but needs explanation | High | Caption: "Optimizer reduces amplitude near pump center to minimize Raman energy transfer" |
| 5 | "Before" amplitude panel is completely flat (A = 1 everywhere) — wastes an entire subplot showing nothing | Medium | Remove "before" amplitude panel or make it a thin reference line on the "after" panel |

### 2.5 Amplitude Optimization No-Reg — `amp_opt_L1m_P015W_d030_noreg.png`

**What it shows:** Amplitude optimization WITHOUT regularization. δ = 0.30.

**Critical problems:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | "After" amplitude profile shows A ranging from −13 to +2 — **negative amplitudes are unphysical** and indicate the optimizer broke box constraints | Critical | This is a CODE BUG, not just a viz issue. Box constraints not enforced properly. Figure must flag this clearly |
| 2 | "After" temporal output: "Peak out: 197268.4 W" — nearly 200 kW peak power, which is 10× the input and physically nonsensical | Critical | Caption must warn: "Unregularized solution produces unphysical amplitude profile" |
| 3 | Pink Raman band shading same issue as §2.4 | Critical | Same fix |
| 4 | "After" spectral plot shows noisy horizontal artifacts across Raman band | High | These are numerical artifacts from the unphysical amplitude — annotate as such |

### 2.6 Amplitude Optimization L=5m — `amp_opt_L5m_P015W_d030.png`

**What it shows:** Amplitude optimization at L = 5 m, δ = 0.30.

**Critical problems:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | "After" amplitude ranges from −26000 to +1 — CATASTROPHICALLY unphysical | Critical | Same box constraint bug as §2.5. `A ∈ [-26035, 1.451], max|A-1| = 26036.0959` — the annotation says it all |
| 2 | "After" temporal: "Peak out: 1.9e12 W / Peak in: 7.0e11 W" — TERAWATT peak powers from a 0.15 W CW-equivalent pulse | Critical | These results must be flagged as INVALID, not displayed as normal |
| 3 | "After" spectrum is completely blank (all energy removed) | Critical | J = −117.8 dB is meaningless — optimizer found trivial zero solution |
| 4 | Y-axis on amplitude profile goes to −25000 — vertical scale makes the A=1 reference line invisible | High | Clamp display to physically reasonable range |

### 2.7 Chirp Sensitivity — `chirp_sens_L1m_P005W.png`

**What it shows:** Two panels showing how the optimized Raman cost J degrades when extra GDD (left) or TOD (right) is added to the optimized spectral phase.

**Problems identified:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | **GDD panel is monotonically decreasing** from left to right (−44 dB at −5000 fs² to −32 dB at +5000 fs²) — there is NO minimum near zero GDD perturbation | Critical | This means the "optimum" is NOT at zero perturbation. The optimizer converged to a local minimum or the regularization biased the solution. MUST be flagged in caption |
| 2 | **TOD panel y-axis uses scientific offset**: `−3.631e1` with ticks showing `−0.0005` to `−0.0025` | Critical | The actual values are −36.31 to −36.06 dB, a 0.25 dB range. Display directly: `ylim=(-36.35, -36.05)`, remove offset |
| 3 | "Optimum" dashed line on GDD panel is at ~−36.3 dB (the zero-perturbation value), but the curve goes BELOW this at negative GDD — the line is misleading | High | Either: (a) mark actual minimum with a different symbol, or (b) remove line and add annotation explaining monotonic behavior |
| 4 | No caption explaining what GDD/TOD perturbation means physically | Critical | Add caption |
| 5 | No context for what "robust" vs "fragile" means — is 0.25 dB variation over ±5000 fs³ good or bad? | High | Add context annotation: "TOD sensitivity: 0.25 dB over ±5000 fs³ — robust" |
| 6 | GDD perturbation range ±5000 fs² may be physically unreasonable — what GDD does a typical SLM impart? | Medium | Add reference annotation or adjust range to physically relevant values |

### 2.8 Time Window Analysis (Optimized) — `time_window_optimized.png`

**What it shows:** Two bar charts. Left: Raman cost J (dB) for different computational time windows. Right: Edge energy fraction (log scale) showing boundary condition health.

**Problems identified:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | No caption | Critical | Add caption explaining what "time window" means |
| 2 | Left panel: All bars look identical height (−36.3 to −35.9 dB) because y-axis goes 0 to −35 dB | High | Zoom y-axis to show the 0.4 dB variation: `ylim=(-36.5, -35.5)` |
| 3 | Green/orange color coding never explained ON the figure | High | Add legend: "Green = OK (edge energy < 10⁻⁶), Orange = WARNING (10⁻⁶ to 10⁻³)" |
| 4 | "DANGER threshold" and "WARNING threshold" on right panel — no explanation of physical meaning | Medium | Caption must explain: energy at edges = numerical artifact from periodic FFT boundary |
| 5 | The key insight (10 ps window is sufficient for L=1m) is not stated anywhere | Medium | Add annotation on optimal window |

### 2.9 Time Window Analysis (Unshaped) — `time_window_analysis_L5.0m.png`

**What it shows:** Overlaid output spectra at L = 5 m for different time windows.

**Problems identified:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | All 6 curves are nearly identical and overlap completely — the figure shows NOTHING useful | Critical | Either: (a) show the DIFFERENCE from the converged spectrum, or (b) replace with a bar chart of boundary energy vs. window size |
| 2 | X-axis is "Δf [THz]" (frequency offset) — inconsistent with all other spectral plots which use wavelength | High | Convert to wavelength [nm] for consistency |
| 3 | Legend colors are indistinguishable where curves overlap | Medium | Use different line styles (solid, dashed, dotted, dash-dot) in addition to colors |
| 4 | No caption | Critical | Add caption |

### 2.10 Evolution Comparisons — `raman_opt_L1m_P005W_evolution.png`, `raman_opt_L2m_P015W_evolution.png`, `raman_opt_L5m_P015W_evolution.png`

**What they show:** 2×2 grids. Row 1: temporal evolution (unshaped vs optimized). Row 2: spectral evolution. Color = power in dB (40 dB range).

**These are the best figures in the set**, but still need improvements:

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | **Jet colormap** — perceptually non-uniform, colorblind-unfriendly | High | Replace with `inferno` (dark background, sequential) or `magma` |
| 2 | No pump wavelength marker (λ₀ ≈ 1550 nm) on spectral panels | Medium | Add white dashed horizontal line at λ₀ |
| 3 | No Raman onset wavelength marker | Medium | Add white dashed line at λ_Raman ≈ 1620 nm |
| 4 | Colorbar label "Power [dB]" doesn't specify normalization | Medium | Change to "Power [dB rel. peak]" |
| 5 | No caption | Critical | Add caption explaining what the diagonal red streak is (SSFS) |
| 6 | L=5m unshaped temporal shows spectacular soliton fission — the most visually striking result — but no annotations point out the features | High | Annotate: soliton fission point, dispersive wave, SSFS trajectory |
| 7 | L=5m optimized temporal evolution shows complex multi-lobed structure — is this physical? | Medium | Caption must address whether optimization-induced structure is physically reasonable |

### 2.11 Evolution Comparisons — Amplitude Optimization

**`amp_opt_L1m_P015W_d030_evolution.png`**: Looks reasonable; similar issues to §2.10 (jet, no markers, no caption).

**`amp_opt_L1m_P015W_d030_noreg_evolution.png`**: The "Modulated (A=A_opt)" panels show chaotic horizontal striping across the entire time-wavelength domain. This is the visual manifestation of the unphysical amplitude profile from §2.5. The figure should either: (a) not be generated for failed optimizations, or (b) carry a prominent "INVALID RESULT" watermark.

**`amp_opt_L5m_P015W_d030_evolution.png`**: Similar to above but even more extreme. The "modulated" panels are essentially noise.

### 2.12 Boundary Diagnostics — All `*_boundary.png` files

**What they show:** Log-scale temporal power profile at the fiber output, with pink "edge zone" shading at the boundaries.

**Shared problems across all boundary plots:**

| # | Problem | Severity | Fix |
|---|---------|----------|-----|
| 1 | No caption explaining what "normalized power" is normalized to | Medium | "Power normalized to peak output power" |
| 2 | Edge zones are tiny pink slivers at the far edges — nearly invisible | Low | Extend edge zone or add arrows pointing to them |
| 3 | No guidance on what a healthy boundary looks like | Medium | Add reference annotation: "Power at edges should be < 10⁻⁶ of peak" |
| 4 | Green "OK" text is bold and large — fine for status, but alarming orange "WARNING" text at L=5m needs explanation | Medium | Add: "WARNING indicates edge energy between 10⁻⁶ and 10⁻³ — may need wider time window" |
| 5 | Figure is very wide (10×4) and mostly empty space at the edges | Low | Reduce width or add a zoomed edge-region inset |

### 2.13 Standalone Evolution Plots — `raman_opt_L1m_P005W_evolution_before.png`, `raman_opt_L1m_P005W_evolution_after.png`

**What they show:** Individual 2-panel (temporal + spectral) evolution plots, one for unshaped pulse, one for optimized.

**Problems:** Same as §2.10 (jet, no markers, no caption), plus these are redundant with the combined 2×2 evolution comparison. Consider removing or consolidating.

### 2.14 `tw_reference_boundary.png` and `tw_reference_evolution.png`

These appear to be reference/baseline versions of the boundary diagnostic and evolution plots. Same issues as §2.10 and §2.12. The `tw_reference_evolution.png` is nearly identical to `raman_opt_L1m_P005W_evolution.png` — consider whether both are needed.

---

## 3. Caption Text for Every Figure Type

### 3.1 Phase Optimization Comparison (3×2 → Split into separate figures)

**Spectral comparison caption:**
> "Spectral power density (dB, normalized to global peak) before and after spectral phase optimization. Left: unshaped input pulse (φ = 0) propagated through L m of SMF-28 fiber. Right: pulse with optimized spectral phase. The vertical dashed line marks the Raman onset wavelength (~1620 nm); energy red-shifted beyond this line constitutes the Raman cost J. Optimization reduced J from −X.X dB to −Y.Y dB, a Z.Z× reduction in Raman band energy."

**Temporal comparison caption:**
> "Temporal pulse intensity before and after propagation. Input (dashed) is a ~185 fs sech² pulse at 1550 nm; output (solid) shows temporal reshaping due to nonlinear propagation. Peak powers are instantaneous values typical of femtosecond pulses (high peak power, low average power). The optimized phase pre-shapes the pulse to minimize energy transfer to the Raman band during propagation."

**Group delay caption (replacing phase row):**
> "Group delay τ(ω) = −dφ/dω of the optimized spectral phase, showing how much each frequency component is advanced or delayed (in femtoseconds) relative to the unshaped pulse. Negative group delay means that frequency arrives earlier. The sharp features near the pump wavelength are the spectral phase structures responsible for Raman suppression."

### 3.2 Amplitude Optimization Comparison

**Spectral comparison caption:**
> "Spectral power density before and after amplitude optimization with bound δ = X.XX. The vertical dashed line marks the Raman onset wavelength. Unlike phase optimization (which is energy-neutral), amplitude modulation directly reshapes the input spectrum. J reduced from −X.X dB to −Y.Y dB."

**Amplitude profile caption:**
> "Optimized spectral amplitude profile A(ω). Values represent the multiplicative factor applied to each frequency component of the input pulse. A = 1 (gray dashed line) means no modification. The optimizer reduces amplitude near the pump center to X.XX, redistributing energy away from frequencies that would generate Raman scattering during propagation. Amplitude constrained to [1−δ, 1+δ] = [X.XX, X.XX]."

### 3.3 Chirp Sensitivity

> "Sensitivity of the optimized Raman cost J to additional quadratic chirp (GDD, left) and cubic chirp (TOD, right) applied on top of the optimized spectral phase. GDD spreads the pulse temporally (positive GDD = red-before-blue); TOD introduces asymmetric temporal broadening. The dashed line marks J at zero perturbation. A bowl-shaped curve centered at zero indicates a robust optimum; a monotonic curve indicates the optimum may not have converged or that regularization has shifted the minimum away from zero additional chirp. GDD sensitivity: X.X dB over ±5000 fs². TOD sensitivity: X.X dB over ±5000 fs³."

### 3.4 Time Window Analysis

> "Effect of computational time window width on optimization results. Left: Raman cost J (dB) for each window size. Right: fractional energy in the boundary edge zones (5% of window on each side). Green bars indicate safe boundaries (edge energy < 10⁻⁶); orange indicates WARNING levels where numerical artifacts may affect results. The time window is the periodic computational domain in the split-step Fourier method; windows too narrow cause pulse energy to 'wrap around' the boundary, corrupting the simulation."

### 3.5 Evolution Comparison

> "Pulse evolution along the fiber showing temporal power (top row, dB relative to peak) and spectral power (bottom row, dB relative to peak). Left column: unshaped pulse. Right column: optimized pulse. The diagonal red streak in the unshaped temporal evolution (visible at L ≥ 2 m) is the soliton self-frequency shift (SSFS) — stimulated Raman scattering continuously red-shifts the soliton, which also shifts in time due to group velocity dispersion. The optimized pulse suppresses this effect."

### 3.6 Boundary Diagnostic

> "Output temporal field power (normalized to peak) on a log scale, showing the full computational time window. Pink shaded regions mark the boundary edge zones (outermost 5% on each side). If significant power reaches these edges, the periodic FFT boundary introduces numerical artifacts. Status: OK = edge energy < 10⁻⁶ of total, WARNING = 10⁻⁶ to 10⁻³, DANGER = > 10⁻³. WARNING or DANGER status requires increasing the time window."

---

## 4. Recommended Figure Architecture

### 4.1 Per-Optimization-Run Figure Set

Replace the current single cramped 3×2 (or 4×2) panel with **4–5 separate figures**:

| Figure | Size (inches) | Content | Filename suffix |
|--------|--------------|---------|-----------------|
| **Fig. 1: Spectral comparison** | 8 × 4 | Input/output spectra, before and after, on wavelength axis (dB). Two subplots side-by-side. Raman onset marked. J values annotated. | `_spectra.png` |
| **Fig. 2: Temporal comparison** | 8 × 4 | Input/output temporal power, before and after. Shared time axis. Peak power annotated. | `_temporal.png` |
| **Fig. 3: Phase/Amplitude profile** | 8 × 3.5 | Single panel: group delay τ(ω) for phase optimization, or A(ω) for amplitude optimization. Wavelength axis. | `_phase.png` or `_amplitude.png` |
| **Fig. 4: Evolution comparison** | 10 × 8 | 2×2 grid (temporal/spectral × before/after). Shared colorbar. Annotated with physical features. | `_evolution.png` |
| **Fig. 5: Boundary diagnostic** | 8 × 3 | Log-scale temporal power with edge zones. | `_boundary.png` |

### 4.2 Analysis Figure Set

| Figure | Size (inches) | Content |
|--------|--------------|---------|
| **Chirp sensitivity** | 10 × 4.5 | Two panels (GDD, TOD). Explicit dB values on y-axis (no offset). Annotated with sensitivity summary. |
| **Time window analysis** | 10 × 4.5 | Two panels (J vs window, edge energy vs window). Y-axis zoomed to show variation. Legend explaining color code. |
| **Convergence plot** | 6 × 4 | J vs iteration, log scale. Component breakdown if available. |

### 4.3 Summary Dashboard (Optional)

For presentations: a single 12 × 8 figure with 4 panels showing: (a) best-case spectral comparison, (b) evolution comparison, (c) chirp sensitivity, (d) convergence. This should be an ADDITIONAL figure, not a replacement.

---

## 5. Phase Display Recommendation

### Recommendation: **Group Delay τ(ω) = −dφ/dω, displayed in femtoseconds**

### Justification

**The current display (2π-wrapped phase) is fundamentally unreadable.** The `wrap_phase()` function maps all phase values to [0, 2π], producing a staircase pattern where every 2π wrap creates a sharp discontinuity. For complex phase profiles (like the L=5m optimization), this creates dozens of narrow notches that convey zero physical information.

**Literature consensus:** In every major ultrafast optics textbook and pulse characterization reference (Trebino's FROG book, Walmsley's SPIDER papers, Weiner's "Ultrafast Optics"), spectral phase is displayed as EITHER:

1. **Group delay τ(ω) = −dφ/dω** — the most common choice in pulse shaping papers
2. **Unwrapped phase φ(ω)** — sometimes used but harder to interpret physically
3. **GDD d²φ/dω²** — used when second-order dispersion is the primary interest

Wrapped phase [0, 2π] is ONLY shown when discussing SLM hardware limitations (where the SLM physically wraps the phase). It is never used for displaying optimization results.

**Group delay is preferred because:**

- It has direct physical meaning: τ(ω) tells you how much each frequency is delayed (in fs)
- It maps naturally to the concept of "pre-chirping" — if τ(ω) slopes downward, blue arrives before red
- Features that suppress Raman scattering appear as sharp temporal delay features near the pump wavelength — visually intuitive
- Units (femtoseconds) are immediately meaningful to the audience
- No wrapping artifacts — continuous curve even for large accumulated phase

**Implementation:** Replace `wrap_phase(φ)` and `set_phase_yticks!()` with:

```julia
function compute_group_delay(φ, sim)
    Δω = 2π / (sim["Nt"] * sim["Δt"])  # angular frequency spacing
    dφ_dω = diff(φ[:, 1]) ./ Δω
    τ_fs = -dφ_dω .* 1e3  # convert ps to fs (if Δt in ps)
    return τ_fs
end
```

Display with: y-axis label "Group delay [fs]", no π-ticks, standard numerical ticks.

---

## 6. Color Palette Specification

### 6.1 Line Plot Colors — Okabe-Ito Palette (Colorblind-Safe)

All line plots should use colors from the Okabe-Ito palette (recommended by Nature Methods):

| Role | Color Name | Hex Code | Matplotlib Name | Usage |
|------|-----------|----------|-----------------|-------|
| Input/Before | Blue | `#0072B2` | — | Input pulse, unshaped, A=1 |
| Output/After | Vermillion | `#D55E00` | — | Output pulse, optimized |
| Reference line | Black | `#000000` | `"k"` | A=1 reference, transform-limited |
| Raman onset | Reddish Purple | `#CC79A7` | — | Vertical dashed line at λ_Raman |
| Secondary data | Sky Blue | `#56B4E9` | — | Shaped input (when different from unshaped) |
| Tertiary data | Bluish Green | `#009E73` | — | Third curve if needed |

### 6.2 Colormap for Evolution Plots

| Current | Replacement | Rationale |
|---------|-------------|-----------|
| `jet` | `inferno` | Perceptually uniform, good contrast, dark-to-bright. Standard in recent Optica papers. |
| — | `magma` | Alternative: similar to inferno but slightly warmer. |
| — | `cividis` | Most colorblind-safe option (blue-yellow only). Use if accessibility is paramount. |

### 6.3 Status Colors (Time Window, Boundary)

| Status | Current | Recommended | Hex |
|--------|---------|-------------|-----|
| OK | `"green"` / `#2ecc71` | Keep `#2ecc71` | Emerald green |
| WARNING | `"orange"` / `#f39c12` | Keep `#f39c12` | Amber |
| DANGER | `"red"` / `#e74c3c` | Keep `#e74c3c` | Red |

### 6.4 Shading and Annotations

| Element | Current | Recommended |
|---------|---------|-------------|
| Raman band (amplitude plots) | `axvspan` with `alpha=0.12, color="red"` filling >50% of plot area | **Remove `axvspan`**. Use single `axvline` at Raman onset with `color="#CC79A7"`, `ls="--"`, `alpha=0.7` |
| Edge zones (boundary plots) | `axvspan` with `alpha=0.2, color="red"` | Fine, but reduce alpha to 0.15 |
| Annotation boxes | White background, `alpha=0.8` | Fine, keep |

---

## 7. Font Size and Figure Size Table

### 7.1 Recommended Font Sizes (for `rcParams`)

| Element | Current (pt) | Recommended (pt) | rcParams Key |
|---------|-------------|-------------------|--------------|
| General font | 11 | 10 | `font.size` |
| Axis labels | 12 | 12 | `axes.labelsize` |
| Axis titles | 13 | 13 | `axes.titlesize` |
| Tick labels | 10 | 10 | `xtick.labelsize`, `ytick.labelsize` |
| Legend | 10 | 9 | `legend.fontsize` |
| Figure suptitle | 14 | 14 | (set per-figure) |
| **Caption text** | — (none) | **10, italic** | (set via `fig.text()`) |
| Annotation boxes | 9–10 | 9 | (set per-annotation) |

### 7.2 Recommended Figure Sizes

| Figure Type | Current (inches) | Recommended (inches) | Aspect |
|-------------|-----------------|---------------------|--------|
| Spectral comparison (1×2) | part of 12×12 | **8 × 4** | 2:1 |
| Temporal comparison (1×2) | part of 12×12 | **8 × 4** | 2:1 |
| Phase/Group delay (single) | part of 12×12 | **8 × 3.5** | ~2.3:1 |
| Amplitude profile (single) | part of 12×14 | **8 × 3.5** | ~2.3:1 |
| Evolution comparison (2×2) | 12 × 10 | **10 × 8** | 5:4 |
| Chirp sensitivity (1×2) | 10 × 4 | **10 × 4.5** | ~2.2:1 |
| Time window analysis (1×2) | 12 × 5 | **10 × 4.5** | ~2.2:1 |
| Boundary diagnostic (single) | 10 × 4 | **8 × 3** | ~2.7:1 |
| Convergence (single) | 8 × 4 | **6 × 4** | 3:2 |

### 7.3 DPI Settings

| Use | DPI |
|-----|-----|
| Screen preview / iteration | 150 |
| Publication quality save | 300 |
| Poster / large format | 600 |

Current settings (150 screen / 300 save) are fine.

---

## 8. Physics Glossary for Annotations

These brief explanations are suitable for figure captions and annotations:

### Core Quantities

| Term | Symbol | Definition for Annotations |
|------|--------|---------------------------|
| **Raman cost** | J | Fraction of output pulse energy in the Raman-shifted spectral band, in dB. Lower (more negative) = less Raman scattering. J = −36 dB means 0.025% of energy is Raman-shifted. |
| **Group delay dispersion** | GDD | How much the pulse's colors spread out in time during propagation. Units: fs². Positive GDD = red arrives before blue. A 185 fs pulse broadens noticeably with ±1000 fs² of GDD. |
| **Third-order dispersion** | TOD | Asymmetric temporal spreading caused by the third derivative of spectral phase. Units: fs³. Causes oscillatory structure on one side of the pulse. |
| **Spectral phase** | φ(ω) | The phase applied to each frequency component of the pulse before propagation. Optimization finds the φ(ω) that minimizes Raman scattering at the output. |
| **Group delay** | τ(ω) | Time delay of each frequency component: τ = −dφ/dω. Negative τ means that frequency arrives earlier. Units: fs. |
| **Spectral amplitude** | A(ω) | Multiplicative factor applied to each frequency component. A = 1 means unmodified; A < 1 means power reduction at that frequency. |

### Physical Phenomena

| Term | Definition for Annotations |
|------|---------------------------|
| **Stimulated Raman scattering (SRS)** | Nonlinear process where pump photons scatter off molecular vibrations in the glass fiber, producing red-shifted (lower frequency) photons. The dominant parasitic effect in high-power fiber systems. |
| **Soliton self-frequency shift (SSFS)** | Intrapulse Raman scattering causes a soliton to continuously shift to longer wavelengths as it propagates. Visible as a diagonal red streak in temporal evolution plots (the soliton moves in time due to its changing group velocity). |
| **Soliton fission** | At high power or long fiber lengths, a higher-order soliton breaks apart into multiple fundamental solitons plus dispersive radiation. Visible as the point where a single bright temporal feature splits into multiple diverging trajectories. |
| **Transform-limited pulse** | A pulse with zero spectral phase (φ = 0) — the shortest possible pulse for a given spectrum. The "before optimization" condition. |
| **Edge energy fraction** | Fraction of total pulse energy in the outermost 5% of the computational time window. High values (> 10⁻⁶) indicate energy leaking to the periodic FFT boundary, corrupting the simulation. |

### Computational Terms

| Term | Definition for Annotations |
|------|---------------------------|
| **Time window** | Width of the periodic computational domain in picoseconds. Must be large enough that no significant pulse energy reaches the edges. Wider windows require more grid points and slower computation. |
| **Nt** | Number of grid points in the time/frequency domain. Typical: 2¹³ = 8192. Larger Nt improves spectral resolution but increases computation time roughly linearly. |
| **L-BFGS** | Limited-memory Broyden–Fletcher–Goldfarb–Shanno algorithm. A quasi-Newton optimization method that uses gradient information to find the spectral phase minimizing J. |
| **Adjoint method** | Efficient technique for computing the gradient ∂J/∂φ in one backward pass through the fiber, regardless of the number of optimization variables. Enables gradient-based optimization with Nt = 8192 phase parameters. |

---

## Appendix A: Complete PNG File Inventory

30 PNG files examined, organized by type:

### Phase Optimization (3 runs × 3–4 files each = 11 files)

| File | L | P | Type | Key Issues |
|------|---|---|------|------------|
| `raman_opt_L1m_P005W.png` | 1m | 0.05W | 3×2 comparison | Phase row unreadable, no caption |
| `raman_opt_L1m_P005W_evolution.png` | 1m | 0.05W | 2×2 evolution | Jet colormap, no markers |
| `raman_opt_L1m_P005W_boundary.png` | 1m | 0.05W | Boundary | OK status, minimal issues |
| `raman_opt_L1m_P005W_evolution_before.png` | 1m | 0.05W | 2-panel before | Redundant with combined |
| `raman_opt_L1m_P005W_evolution_after.png` | 1m | 0.05W | 2-panel after | Redundant with combined |
| `raman_opt_L2m_P015W.png` | 2m | 0.15W | 3×2 comparison | Zoom inset unreadable, phase staircase |
| `raman_opt_L2m_P015W_evolution.png` | 2m | 0.15W | 2×2 evolution | Jet, no annotations on SSFS |
| `raman_opt_L5m_P015W.png` | 5m | 0.15W | 3×2 comparison | Extreme phase staircase, suspicious physics |
| `raman_opt_L5m_P015W_evolution.png` | 5m | 0.15W | 2×2 evolution | Spectacular SSFS — best visual, needs annotations |
| `raman_opt_L5m_P015W_boundary.png` | 5m | 0.15W | Boundary | WARNING status at 1.74e-5 |

### Amplitude Optimization (5 runs × 2–3 files each = 15 files)

| File | L | P | δ | Reg | Key Issues |
|------|---|---|---|-----|------------|
| `amp_opt_L1m_P005W_d010.png` | 1m | 0.05W | 0.10 | yes | Pink shading, no caption |
| `amp_opt_L1m_P005W_d010_evolution.png` | 1m | 0.05W | 0.10 | yes | Jet colormap |
| `amp_opt_L1m_P005W_d010_boundary.png` | 1m | 0.05W | 0.10 | yes | OK |
| `amp_opt_L1m_P005W_d020.png` | 1m | 0.05W | 0.20 | yes | Same as d010 |
| `amp_opt_L1m_P005W_d020_evolution.png` | 1m | 0.05W | 0.20 | yes | Jet |
| `amp_opt_L1m_P015W_d015.png` | 1m | 0.15W | 0.15 | yes | Pink shading |
| `amp_opt_L1m_P015W_d015_evolution.png` | 1m | 0.15W | 0.15 | yes | Jet |
| `amp_opt_L1m_P015W_d015_boundary.png` | 1m | 0.15W | 0.15 | yes | OK |
| `amp_opt_L1m_P015W_d030.png` | 1m | 0.15W | 0.30 | yes | Pink shading dominant |
| `amp_opt_L1m_P015W_d030_evolution.png` | 1m | 0.15W | 0.30 | yes | Jet |
| `amp_opt_L1m_P015W_d030_boundary.png` | 1m | 0.15W | 0.30 | yes | OK |
| `amp_opt_L1m_P015W_d030_noreg.png` | 1m | 0.15W | 0.30 | NO | **BROKEN**: A goes to −13, 200 kW peak |
| `amp_opt_L1m_P015W_d030_noreg_evolution.png` | 1m | 0.15W | 0.30 | NO | **BROKEN**: chaotic stripes |
| `amp_opt_L1m_P015W_d030_noreg_boundary.png` | 1m | 0.15W | 0.30 | NO | May show artifacts |
| `amp_opt_L5m_P015W_d030.png` | 5m | 0.15W | 0.30 | yes | **BROKEN**: A to −26000, TW power |
| `amp_opt_L5m_P015W_d030_evolution.png` | 5m | 0.15W | 0.30 | yes | Likely artifacts |
| `amp_opt_L5m_P015W_d030_boundary.png` | 5m | 0.15W | 0.30 | yes | Needs checking |

### Analysis Plots (4 files)

| File | Key Issues |
|------|------------|
| `chirp_sens_L1m_P005W.png` | Monotonic GDD, scientific offset on TOD, no caption |
| `time_window_optimized.png` | Bars all same height, no caption, color code unexplained |
| `time_window_analysis_L5.0m.png` | All curves overlap — figure shows nothing |
| `tw_reference_boundary.png` | Duplicate of `raman_opt_L1m_P005W_boundary.png` |
| `tw_reference_evolution.png` | Duplicate of `raman_opt_L1m_P005W_evolution.png` |

---

## Appendix B: Priority-Ordered Action Items

### P0 — Must Fix (Figures are misleading or broken)

1. Replace 2π-wrapped phase display with group delay τ(ω) in all `plot_optimization_result_v2` calls
2. Remove massive pink `axvspan` Raman shading from amplitude plots; use dashed line
3. Fix TOD y-axis scientific offset in `plot_chirp_sensitivity` — use explicit dB values
4. Flag or suppress broken amplitude optimization results (no-reg, L=5m) — A going to −26000 is a code bug
5. Address monotonic GDD sensitivity curve — add caption warning that optimum may not have converged

### P1 — Should Fix (Figures are hard to read)

6. Remove all zoom insets from temporal and phase subplots; replace with separate full-size figures
7. Add captions to ALL figures via `fig.text()`
8. Replace `jet` colormap with `inferno` in all evolution plots
9. Switch line colors to Okabe-Ito palette
10. Zoom y-axis on time window bar chart to show the actual 0.4 dB variation
11. Convert `time_window_analysis_L5.0m.png` from frequency to wavelength axis, or replace with difference plot

### P2 — Nice to Have (Polish and context)

12. Add pump wavelength and Raman onset markers to evolution plots
13. Add SSFS / soliton fission annotations to L=5m evolution
14. Add physics context annotations (peak power parenthetical, improvement ΔJ)
15. Consolidate redundant files (remove standalone before/after evolution PNGs, tw_reference duplicates)
16. Add colorbar normalization text ("dB rel. peak")

---

*End of report.*
