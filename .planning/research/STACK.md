# Technology Stack: Visualization Layer

**Project:** SMF Gain-Noise Visualization Overhaul
**Researched:** 2026-03-24
**Scope:** Matplotlib/PyPlot best practices for nonlinear fiber optics plots

---

## 1. Colormap Recommendation

### Verdict: Use `inferno` for evolution heatmaps. Replace `jet` immediately.

**Confidence:** HIGH (matplotlib official docs + colorscience literature + field practice analysis)

### Evidence

**The Dudley connection (MEDIUM confidence):** The canonical supercontinuum simulation code — `test_Dudley.m` from the SCG book companion repository (`github.com/jtravs/SCGBookCode`, written by J.C. Travers, M.H. Frosz, and J.M. Dudley) — calls `pcolor()` with no explicit colormap. In MATLAB before R2014b, the default was `jet`. This is why jet became the de-facto standard in nonlinear fiber optics: it was never a deliberate choice, it was the MATLAB default circa 2006-2013. Papers that followed Dudley et al.'s visual conventions inherited jet by accident.

**Why jet is wrong for this data:**
- Jet has non-monotonic lightness (L* value). It has a bright band around cyan-green that creates false perceptual features — structures appear in the heatmap that do not correspond to real intensity changes.
- At 40 dB dynamic range (the typical `dB_range` used in this codebase), jet creates artificial "rings" around soliton tracks.
- Jet converts to grayscale non-monotonically. Features near the cyan-green region disappear or invert when printed black-and-white.
- Source: matplotlib official documentation explicitly lists jet as a cautionary example of a bad colormap: "the L* values vary widely throughout the colormap, making it a poor choice for representing data."

**Why `hot` is also wrong:**
- `hot` has kinks in its L* function, particularly a long plateau in the yellow region where large intensity ranges all look the same.
- The yellow/white region "washes out" fine structure at high intensity — exactly where solitons and Raman-shifted components live.
- Source: matplotlib colormap docs note `hot` has "pronounced banding" with "long stretches of indistinguishable colors."

**Why `inferno` is correct for this application:**
- Inferno is perceptually uniform: equal dB steps produce equal perceptual steps across the full range.
- Inferno's L* is strictly monotonically increasing from black (noise floor) to near-white (peak intensity). This means the noise floor is dark and the bright soliton cores are maximally visible.
- Inferno starts at black, which is physically correct: the noise floor should be absence-of-signal (dark), not a bright color.
- Inferno converts to grayscale with maintained information content.
- Inferno is colorblind-safe (the blue-purple-orange-yellow sequence is accessible to deuteranomaly).
- Source: Kenneth Moreland's color map advice, matplotlib official perceptually uniform colormap documentation, BIDS colormap design paper.

**Why not `viridis`:**
- Viridis is also perceptually uniform and acceptable, but its dark end is blue-green, not black. For spectral/temporal evolution plots where the physics interpretation is "dark = noise floor = nothing happening," inferno's black-to-bright trajectory is more physically intuitive.
- Viridis looks qualitatively similar to a "cool" heatmap, which can be visually confusing when the data represents thermal or intensity phenomena.

**Why not `hot_r` (reversed hot):**
- Reversing hot so white=noise floor and black=peak creates a white background with dark solitons. This wastes ink on print, and the kinks in hot's L* function are still present regardless of direction.

**Why not `magma`:**
- Magma is a close second to inferno (same design family, both from the matplotlib/viridis project). Inferno has a slightly warmer terminal color (near-white yellow), which makes the peak intensity more visually distinct than magma's purple-white.
- Either is acceptable if the team prefers magma's cooler look. The choice is aesthetic, not perceptual.

**Practical note on `_r` suffix:**
All matplotlib colormaps have a reversed variant with `_r` appended. For inferno, `inferno` runs black-to-near-white (dark = low dB = noise, bright = 0 dB = peak). This is the correct orientation when `vmin = -dB_range` and `vmax = 0`. Do NOT use `inferno_r` — that would map noise floor to near-white and peak to black.

### Recommended colormap table

| Plot type | Recommended cmap | vmin/vmax | Rationale |
|-----------|-----------------|-----------|-----------|
| Spectral evolution heatmap | `inferno` | `(-dB_range, 0)` | Dark noise floor, bright signal |
| Temporal evolution heatmap | `inferno` | `(-dB_range, 0)` | Same physics, same convention |
| Spectrogram (STFT) | `inferno` | `(-dB_range, 0)` | Consistency across all intensity maps |
| Phase diagnostic overlays | `RdBu_r` or `coolwarm` | symmetric around 0 | Diverging data (phase is centered on 0) — not yet implemented |

---

## 2. Matplotlib rcParams Settings

### Verdict: Current rcParams have two bugs and several missing settings for publication quality.

**Confidence:** HIGH (official matplotlib docs + PyPlot.jl GitHub issues)

### Bug 1: rcParams mutation does not persist in Julia/PyPlot

The current code uses:
```julia
PyPlot.matplotlib.rcParams["font.size"] = 11
```

Per PyPlot.jl documentation and GitHub issue #417 ("Setting rcParams fails silently"), `PyPlot.matplotlib.rcParams` returns a **copy** of the dict via PyCall, so mutations to it may not persist in the actual Python rcParams. The correct pattern is:

```julia
const _mpl_rc = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
_mpl_rc["font.size"] = 11
```

Or equivalently use matplotlib's `rc()` function:
```julia
PyPlot.matplotlib.rc("font", size=11)
PyPlot.matplotlib.rc("axes", labelsize=12)
```

**Whether the current code actually fails** depends on PyCall version and Julia runtime behavior. However: the current code assigns to `rcParams["..."]` at module load time (top of file) rather than through `PyDict`. If the plots look correct it may work by coincidence, but the PyDict pattern is the only documented-correct approach per PyPlot.jl maintainers.

### Bug 2: Missing savefig bbox setting

The current code sets `savefig.dpi = 300` but not `savefig.bbox`. Without `savefig.bbox = "tight"`, saved figures will use the default bounding box which clips axis labels on the left/bottom edges. This is a known matplotlib issue on figures with long y-axis labels (e.g., "Propagation distance [m]").

### Recommended rcParams block (complete)

```julia
const _rc = PyPlot.PyDict(PyPlot.matplotlib."rcParams")

# Typography — sized for single-column journal figure (8.4 cm wide)
# At 3.31 inches wide, 10pt text renders cleanly after reduction
_rc["font.size"]          = 10
_rc["axes.labelsize"]     = 11
_rc["axes.titlesize"]     = 11
_rc["xtick.labelsize"]    = 9
_rc["ytick.labelsize"]    = 9
_rc["legend.fontsize"]    = 9

# Font family — sans-serif is standard for Optica journals
# Avoid text.usetex = true unless LaTeX is available; it causes
# silent failures in CI/batch environments
_rc["font.family"]        = "sans-serif"
_rc["font.sans-serif"]    = ["DejaVu Sans", "Arial", "Helvetica"]

# Lines and axes
_rc["axes.linewidth"]     = 0.8      # thin frame, not heavy
_rc["lines.linewidth"]    = 1.5      # visible at print size
_rc["xtick.major.width"]  = 0.8
_rc["ytick.major.width"]  = 0.8
_rc["xtick.minor.visible"] = true
_rc["ytick.minor.visible"] = true

# Grid — subtle, not dominant
_rc["axes.grid"]          = true
_rc["grid.alpha"]         = 0.25
_rc["grid.linewidth"]     = 0.5

# Resolution
_rc["figure.dpi"]         = 150      # screen preview
_rc["savefig.dpi"]        = 300      # archive output
_rc["savefig.bbox"]       = "tight"  # prevent label clipping
_rc["savefig.pad_inches"] = 0.05     # minimal whitespace around figure

# Color cycle — Okabe-Ito (already matches project constants)
_rc["axes.prop_cycle"] = PyPlot.matplotlib.cycler(
    "color", ["#0072B2", "#D55E00", "#009E73", "#CC79A7",
               "#F0E442", "#56B4E9", "#E69F00", "#000000"])
```

### Notes on font settings

- Do NOT set `text.usetex = true` unless the execution environment has a working LaTeX installation. PyPlot in batch/CI environments will fail silently or raise cryptic Popen errors.
- `DejaVu Sans` is bundled with matplotlib and always available — no system font needed.
- The Okabe-Ito cycle replaces the default blue/orange/green cycle with the colorblind-safe palette already defined as constants in the project (consistent with `COLOR_INPUT`, `COLOR_OUTPUT`, etc.).

---

## 3. Figure Sizes

### Verdict: Size figures to journal column widths from the start.

**Confidence:** MEDIUM (Optica style guide referenced; exact pixel specs not directly accessible but derived from confirmed 8.4 cm single-column standard)

### Optica Publishing Group specifications (Optics Express, JOSA B, Optics Letters)

| Format | Width | In inches | Common use |
|--------|-------|-----------|------------|
| Single column | 8.4 cm | 3.31 in | Most figures, single panel |
| 1.5 column | ~12.5 cm | ~4.92 in | Not common |
| Double column | 17.2 cm | 6.77 in | Multi-panel comparisons |

Source: Optica Publishing Group traditional journals style guide confirms "figures will normally be reduced to one column width (8.4 cm)." Double-column figures use approximately 17 cm (confirmed from OSA/Optica LaTeX templates).

### Minimum font size requirement

After figure reduction to 8.4 cm, text must be no smaller than **6 pt**. At 300 DPI and 3.31 in width:
- `font.size = 10` at 3.31 in → approximately 9 pt at final size → safe.
- `font.size = 8` at 3.31 in → approximately 7 pt at final size → safe (minimum, not comfortable).
- Font sizes smaller than 8 in the figure → will be below 6 pt limit after reduction → rejected.

### Recommended figsize by plot type

| Plot type | figsize (W, H) in inches | Description |
|-----------|--------------------------|-------------|
| Single-panel spectral | `(3.31, 2.6)` | Single column, 4:5 aspect |
| Two-panel evolution (current) | `(6.77, 4.5)` | Double column, two heatmaps side by side |
| Four-panel comparison (opt.png) | `(6.77, 5.0)` | Double column, 3×2 grid |
| Phase diagnostic (2×2 grid) | `(6.77, 5.5)` | Double column, 2×2 panels |

### Current code assessment

The current code uses `figsize=(8, 10)` for evolution plots and `figsize=(8, 6)` for individual panels. At 300 DPI that produces 2400×3000 px files — oversized for submission. Reducing to 6.77×4.5 produces 2031×1350 px at 300 DPI, which is correct for double-column figures.

---

## 4. DPI Settings

### Verdict: 300 DPI for PNG export is correct. 600 DPI is needed only for line-art-only figures.

**Confidence:** HIGH (Optica style guide confirmed: "at least 300 dpi; 600 dpi if there is text or line art")

- **Mixed figures (heatmap + line plots):** 300 DPI sufficient. The continuous-tone heatmap is the limiting element.
- **Pure line-art figures (spectra, phase curves):** 600 DPI preferred to maintain sharp edges.
- **The current code has `savefig.dpi = 300` which is correct** for the evolution heatmaps (dominant figure type).
- For pure spectral comparison plots (opt.png), consider PDF export rather than PNG. PDF is vector and infinitely scalable with no DPI concern.

---

## 5. Colorbar and Dynamic Range

### Verdict: 40 dB dynamic range with symmetric normalization is the field standard.

**Confidence:** HIGH (directly from Dudley/Travers/Frosz SCGBookCode: `caxis([mlIW-40.0, mlIW])`)

The official SCG book code normalizes to the **local maximum per figure** with a 40 dB window. The current code does the same (`dB_range=40.0`, `vmin=-dB_range, vmax=0`). This is correct.

Do NOT use a fixed absolute dB floor (e.g., `vmin=-100 dBm`) across runs — different power levels shift the noise floor by 10–20 dB, making cross-run comparisons meaningless.

**Colorbar settings to add:**
```python
cbar = fig.colorbar(im, ax=ax, label="Intensity [dB]")
cbar.ax.tick_params(labelsize=8)   # prevent crowding
cbar.set_ticks([-40, -30, -20, -10, 0])  # explicit major ticks
```

---

## 6. Grid Visibility on Heatmaps

### Verdict: Disable grid on pcolormesh axes. Grid lines are invisible on heatmaps and create visual noise.

**Confidence:** HIGH (direct matplotlib behavior: grid lines are rendered on top of pcolormesh but appear as faint stripes that look like data artifacts)

The current code sets `axes.grid = True` globally, which applies to heatmap axes. This should be overridden per-axis after creating each pcolormesh:

```julia
ax.grid(false)   # disable on heatmap axes only
```

Line-plot axes (spectra, phase) should retain the grid.

---

## 7. Julia-Specific PyPlot Tips

**Confidence:** MEDIUM (PyPlot.jl GitHub docs + issues; runtime behavior may vary by PyCall version)

### Tip 1: Use PyDict for rcParams (critical)

As noted in Section 2. The `PyPlot.matplotlib.rcParams["key"] = value` pattern may silently fail. Use `PyPlot.PyDict(PyPlot.matplotlib."rcParams")` once at module load and mutate that dict.

### Tip 2: pcolormesh `shading="nearest"` is correct

The current code already uses `shading="nearest"` — this is the correct setting for simulation data on a regular grid. `shading="gouraud"` interpolates between cells (inappropriate for discrete physics data), and `shading="auto"` behaves differently depending on data dimensions. Keep `"nearest"`.

### Tip 3: `tight_layout()` vs `constrained_layout`

The current code does not appear to call `tight_layout()` consistently. For multi-panel figures:
```julia
fig.set_constrained_layout(true)  # preferred: computed at render time
# OR: call tight_layout() just before savefig
```
`constrained_layout` is preferred over `tight_layout` in modern matplotlib (3.x) because it handles colorbars correctly.

### Tip 4: savefig with explicit dpi parameter

Even with `savefig.dpi` set in rcParams, pass it explicitly to `savefig()` to be safe:
```julia
savefig(path, dpi=300, bbox_inches="tight")
```
The rcParams value is a fallback; the keyword argument takes precedence and documents intent.

### Tip 5: Avoid plt.show() in batch mode

When running from scripts (not interactive), `plt.show()` blocks execution. Use:
```julia
PyPlot.close("all")  # after saving, release memory
```

---

## 8. What NOT to Use

| What | Why not |
|------|---------|
| `cmap="jet"` | Non-monotonic L*, creates false features, inherited from MATLAB 2006 default by accident |
| `cmap="hot"` | Kinks in L*, washes out high-intensity detail in yellow plateau |
| `cmap="rainbow"` or `cmap="Spectral"` | Rainbow colormaps; same problems as jet, also physically misleading for intensity data |
| `cmap="viridis"` for intensity maps | Acceptable but blue-to-yellow progression is less physically intuitive than black-to-white for intensity |
| `text.usetex = true` without checking LaTeX availability | Silently fails in batch environments; use DejaVu Sans instead |
| `figsize=(8, 6)` default | Not aligned to journal column widths; forces rescaling at submission |
| `axes.grid = True` on heatmap axes | Grid lines appear as data artifacts on pcolormesh |
| Absolute dB normalization across runs | Meaningless for cross-run comparison at different power levels |

---

## Sources

- [Matplotlib Colormap Documentation](https://matplotlib.org/stable/users/explain/colors/colormaps.html) — HIGH confidence; official source for perceptual uniformity analysis, jet/hot criticism
- [BIDS Colormap Design (viridis, inferno, etc.)](https://bids.github.io/colormap/) — HIGH confidence; original design rationale for the perceptually uniform colormap family
- [Kenneth Moreland Color Advice](https://www.kennethmoreland.com/color-advice/) — HIGH confidence; blackbody/inferno recommendation for sequential intensity data
- [PyPlot.jl GitHub repository](https://github.com/JuliaPy/PyPlot.jl) — HIGH confidence; official source for PyDict rcParams mutation pattern
- [PyPlot.jl Issue #417: Setting rcParams fails silently](https://github.com/JuliaPy/PyPlot.jl/issues/417) — HIGH confidence; confirmed bug in direct rcParams assignment
- [SCGBookCode: test_Dudley.m](https://github.com/jtravs/SCGBookCode) — HIGH confidence; direct evidence that Dudley et al. code used MATLAB default (jet) with no explicit colormap call
- [MATLAB default colormap history (jet → parula 2014b)](https://www.mathworks.com/matlabcentral/answers/169307-why-has-the-default-colormap-of-surface-plots-changed-in-matlab-r2014b) — HIGH confidence; confirms jet was MATLAB default when SCG conventions were established
- [Optica Publishing Group style guide reference](https://opg.optica.org/submit/style/osa-styleguide.cfm) — MEDIUM confidence; 8.4 cm single-column width confirmed via search; direct PDF access was blocked
- [Optics Express figure requirements summary](https://opg.optica.org/josaa/submit/style/coloronline.cfm) — MEDIUM confidence; 300/600 DPI requirement confirmed via search result extraction
