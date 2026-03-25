# Project Research Summary

**Project:** SMF Gain-Noise Visualization Overhaul
**Domain:** Scientific visualization for nonlinear fiber optics (Julia + PyPlot/Matplotlib)
**Researched:** 2026-03-24
**Confidence:** HIGH (stack and pitfalls from direct codebase audit + authoritative sources; architecture HIGH from direct code observation)

---

## Executive Summary

This project is a visualization refactor of a working nonlinear fiber optics simulation codebase. The simulation core (`MultiModeNoise.jl`) and optimization loop are correct and should not be touched. The problem is entirely in `scripts/visualization.jl` (~1016 lines, ~12 public functions): the current code contains at least five confirmed bugs that actively mislead physics interpretation, plus structural debt that makes fixes hard to apply consistently. The refactoring goal is not new functionality — it is making the existing results readable, self-consistent, and publication-quality.

The research unanimously converges on a three-phase refactoring order driven by dependency: fix foundational utilities first (colormap, Raman shading bounds, axis helpers), extract panel builders second (so fixes apply in exactly one place), and assemble corrected output figures last. Every cross-cutting theme — colormap, color identity, Raman band bounds, axis normalization, annotation — is blocked from being fixed cleanly until the structural foundation is in place. Attempting to patch individual figure functions before extracting shared panel builders guarantees that each bug must be fixed in multiple places independently.

The key risks are: (1) the Raman axvspan bug is confirmed and makes comparison panels unreadable — it must be the absolute first fix; (2) jet colormap creates false perceptual features and should be replaced with `inferno` or `magma` in the same pass; (3) the phase panel masking must happen before unwrapping (not after), or noise-floor artifacts corrupt the unwrapped result even in the valid signal region. These three issues are the difference between plots that look broken and plots that communicate science. The remaining issues (annotation infrastructure, constrained layout migration, merged evolution figure) are correctness and quality improvements that require the foundation to be stable first.

---

## Key Findings

### Recommended Stack

The project is already correctly committed to Julia + PyPlot (Python matplotlib via PyCall). No stack changes are needed. Two specific Julia/PyPlot integration issues require fixes: (1) `rcParams` must be mutated via `PyPlot.PyDict(PyPlot.matplotlib."rcParams")`, not by direct assignment — direct assignment may silently fail per PyPlot.jl issue #417; (2) `constrained_layout` must replace the mix of `tight_layout()` and `subplots_adjust()` calls that currently conflict with each other on colorbar-containing figures.

**Core technologies:**
- `PyPlot.jl` / matplotlib 3.x: all plot output — already in place, needs rcParams fix
- `inferno` colormap: all dB-scale intensity heatmaps — replaces `jet` (confirmed field standard per Dudley SCGBookCode, gnlse-python, matplotlib docs)
- `magma` colormap: acceptable alternative to `inferno`; gnlse-python community default; either is correct
- `constrained_layout`: figure layout — replaces conflicting `tight_layout` + `subplots_adjust` mix
- Okabe-Ito palette (`COLOR_INPUT`, `COLOR_OUTPUT`, etc.): already defined in code, not consistently used
- 300 DPI PNG for heatmap figures, 600 DPI for pure line-art — Optica Publishing Group confirmed standard
- `figsize=(6.77, 4.5)` for double-column, `(3.31, 2.6)` for single-column — sized to Optica journal column widths

**Colormap consensus:** Both STACK.md and FEATURES.md recommend the inferno/magma family. STACK.md marginally favors `inferno` (physical argument: black noise floor); FEATURES.md cites gnlse-python community using `magma`. This is not a conflict — both are perceptually uniform and either is correct. The decision is: use `inferno` as the project default and document it in `STYLE[:evolution_cmap]`. The critical point is replacing `jet`, not the choice between inferno and magma.

### Expected Features

**Must have (table stakes) — confirmed bugs to fix:**
- Perceptually uniform colormap (`inferno`) on all dB heatmaps — `jet` is confirmed present in 4 function defaults
- Raman band marked as a narrow 10–15 THz window, not full-width span — confirmed axvspan bug in codebase
- Shared xlim and ylim between before/after comparison panels — currently computed independently per column
- Global normalization reference across both comparison columns — currently per-column, produces misleading dB offsets
- Fiber/pulse parameter annotation on every figure (fiber type, L, P₀, λ₀) — completely absent from saved figures
- Group delay τ(ω) as primary phase display — wrapped [0, 2π] phase currently shown, which is scientifically wrong
- Phase masking applied before unwrapping (at −40 dB, not −30 dB) — prevents noise-floor artifacts from corrupting unwrapped result
- Color identity consistency — `COLOR_INPUT`/`COLOR_OUTPUT` constants defined but overridden with `"b--"`, `"darkgreen"`, `"r-"` literals in 4+ functions

**Should have (quality differentiators):**
- Merged 4-panel evolution figure (`opt_evolution.png`) replacing two separate PNG files — enables direct side-by-side comparison
- `run_meta` NamedTuple passed to all assemblers — enables self-documenting annotation without per-function parameter sprawl
- `_spectral_xlim(sim)` utility replacing 7+ hardcoded `λ0_nm ± 300/500 nm` literals — required for HNLF runs with wider spectra
- GDD panel with percentile clip (`ylim` bounded to 2nd–98th percentile of valid samples) — currently shows ±10⁶ fs² spikes
- `STYLE` dict in Layer 0 — single change point for colormap, line styles, annotation boxes
- dB floor increased to 60 dB for spectral evolution (from 40 dB default) — Raman suppression of 40+ dB is invisible at 40 dB floor
- Colorbar label "Power [dB, re peak]" explicitly stating normalization reference

**Defer (not essential for this milestone):**
- Decoupling solver calls from `plot_optimization_result_v2` — currently calls `solve_disp_mmf` twice internally; architecturally wrong but works; defer to a later phase
- Spectrogram / STFT figure (`plot_spectrogram`) — unused in current runs
- Amplitude optimization result path (`plot_amplitude_result_v2`) — share the panel builder refactor but not a primary fix target
- PDF export for pure line-art figures — PNG at 300 DPI is sufficient for current use

### Architecture Approach

The file should remain a single `visualization.jl` — splitting into multiple files would require converting to a proper Julia module/package, which is out of scope. The correct fix is internal layering: reorganize the 1016 lines into four explicit sections (Layer 0: config/constants, Layer 1: pure math primitives, Layer 2: panel builders that draw into a provided `ax`, Layer 3: figure assemblers that create figures and call `savefig`). The key discipline is that panel builders never call `savefig` and never create figures; figure assemblers never duplicate panel-level drawing logic. This allows any bug to be fixed in exactly one place.

**Major components:**
1. **Layer 0 — Config**: `STYLE` dict, `COLOR_*` constants, physical constants, rcParams block — defines everything used by all layers
2. **Layer 1 — Math Primitives**: `_manual_unwrap`, `_central_diff`, `_apply_dB_mask`, `_energy_window`, `_spectral_xlim`, `compute_group_delay`, `compute_gdd`, `compute_instantaneous_frequency` — no PyPlot calls allowed
3. **Layer 2 — Panel Builders**: `_panel_spectrum!`, `_panel_temporal!`, `_panel_group_delay!`, `_panel_evolution_heatmap!`, `_add_raman_markers!`, `_add_metadata_annotation!` — draw into a provided `ax`, return nothing
4. **Layer 3 — Figure Assemblers**: `plot_optimization_result_v2`, `plot_phase_diagnostic`, `plot_evolution_comparison` (new merged), `plot_convergence` — create figures, call panel builders, call `savefig`

**Data flow change:** The before/after solver calls must be lifted out of `plot_optimization_result_v2` and into the `run_optimization` caller. The assembler should accept pre-computed `sol_before, sol_after` dicts. This is prerequisite for computing shared axis limits before any drawing occurs.

### Critical Pitfalls

1. **Jet colormap on dB heatmaps** — Replace with `inferno` in `STYLE[:evolution_cmap]` and propagate to all 4 function defaults. Jet creates ~3 dB apparent error in perceptual intensity (Crameri et al. 2021 quantified). Present in `plot_spectral_evolution`, `plot_temporal_evolution`, `plot_combined_evolution`, `plot_spectrogram`.

2. **Raman axvspan uses wrong frequency selection logic** — The `Δf_shifted .< raman_threshold` condition selects the entire long-wavelength half of the spectrum, not the gain band. Fix by computing `λ_raman_start` and `λ_raman_end` directly from physics (13.2 THz downshift, ~10 nm FWHM). This is a confirmed bug with visible consequences — the before/after comparison panels are partially obscured.

3. **Phase masking after unwrapping, not before** — `_apply_dB_mask` at −30 dB is called after `_manual_unwrap`. A single noise-floor phase jump before the mask threshold propagates across the entire unwrapped result. Fix: zero out or smooth sub-threshold bins in wrapped phase before unwrapping, then mask again after at −40 dB. Also applies the GDD wild-excursion problem (second derivative amplifies noise twice).

4. **Independent normalization per comparison column** — Each column in the 3×2 figure computes its own `P_ref`. Fix: compute `P_ref_global` from both solutions before the column loop. This is also required to make the J-function dB annotation consistent with the plotted scale.

5. **Mismatched time-axis ranges between before/after temporal panels** — `_energy_window` is called independently for each column. Fix: compute `t_lims_shared = (min(lo_before, lo_after), max(hi_before, hi_after))` before drawing. This requires solver calls to be lifted out of the plotting function (see Architecture).

---

## Implications for Roadmap

Based on research, the refactoring must follow a strict bottom-up dependency order. Attempting to fix figure assemblers before stabilizing the panel builders produces multiple-fix situations for every bug.

### Phase 1: Foundation — Stop Actively Misleading (highest priority)

**Rationale:** Three confirmed bugs make current plots scientifically unreadable: wrong colormap, wrong Raman shading, and mismatched axes. These must be fixed before anything else because every subsequent fix builds on them, and because they are the bugs most visible to an advisor or collaborator.

**Delivers:** Plots that are not actively misleading. Correct colormap, correct Raman band marking, consistent color identity across all figures.

**Addresses:**
- Replace `cmap="jet"` with `cmap="inferno"` in all 4 function defaults (Pitfall 1)
- Fix `axvspan` Raman band bounds using physics-derived wavelength computation (Pitfall 3)
- Replace all `"b--"`, `"darkgreen"`, `"r-"` literals with `COLOR_INPUT`/`COLOR_OUTPUT` (Pitfall 9)
- Add `STYLE` dict to Layer 0 as single change point for colormap and line styles
- Fix rcParams mutation via `PyPlot.PyDict` (STACK.md Bug 1)
- Add `savefig.bbox = "tight"` to rcParams (STACK.md Bug 2)

**Avoids:**
- False perceptual features from jet (Crameri et al. 2021: ~3 dB apparent error)
- Partially obscured comparison panels from incorrect Raman shading
- Color identity confusion across figures

**Research flag:** Standard patterns — no additional research needed. All fixes are direct code changes with confirmed correct behavior.

---

### Phase 2: Axis and Normalization Correctness

**Rationale:** Shared axis limits and global normalization are prerequisites for meaningful before/after visual comparison. They also require lifting solver calls out of the plotting function, which is a structural change that must happen before panel builders are extracted.

**Delivers:** Before/after panels that can actually be compared visually. The J-function improvement will be visible in the figure, not just in the log.

**Addresses:**
- Lift `solve_disp_mmf` calls out of `plot_optimization_result_v2` and into `run_optimization` caller (ARCHITECTURE.md anti-pattern 1)
- Global `P_ref_global` computed from both solutions before column loop (Pitfall 4)
- Shared time axis: `t_lims_shared` computed from union of both energy windows (Pitfall 5)
- Consolidate `λ0_nm ± 300/500 nm` hardcodings into `_spectral_xlim(sim)` — fixes 7+ occurrences (ARCHITECTURE.md anti-pattern 2)
- Disable grid on pcolormesh axes (`ax.grid(false)` after each `pcolormesh` call) (STACK.md section 6)
- Fix pcolormesh non-monotonic wavelength grid warning (confirmed in v7 run log; apply `sort_idx` to 2D power matrix) (Pitfall 7)

**Avoids:**
- Misleading visual suppression artifacts from mismatched normalization
- Axis range discrepancies that make pulse compression invisible
- pcolormesh UserWarning in run logs (potential cell-position misalignment)

**Research flag:** Standard patterns — data-flow change is mechanical; `_spectral_xlim` is a simple extraction.

---

### Phase 3: Phase Diagnostic Correctness

**Rationale:** The phase diagnostic figure (`opt_phase.png`) is the most technically complex output and has the most failure modes (oscillatory artifacts, empty panels, GDD spikes). Fixing it correctly requires the utility layer from Phase 1 and the masking threshold decisions from Phase 2 to be stable.

**Delivers:** A readable phase diagnostic showing the actual optimization result: smooth group delay, bounded GDD, meaningful instantaneous frequency sweep.

**Addresses:**
- Apply dB mask before unwrapping (not after) at −40 dB threshold (Pitfall 2, Pitfall 3 mitigation)
- Clip GDD panel to physically reasonable range (percentile clip: 2nd–98th percentile of valid samples) (FEATURES.md section 10; Pitfall 12)
- Apply temporal power mask to instantaneous frequency panel (Pitfall 11)
- Replace wrapped phase [0, 2π] primary display with group delay τ(ω) [fs] as primary display (FEATURES.md section 1) — this is the scientifically correct representation
- Fix `xlim` for phase panels: use signal-bearing region (±200 nm from λ₀ for normal propagation) not ±800 nm (FEATURES.md section 10)
- Migrate phase diagnostic figure to `constrained_layout` — replaces `tight_layout` conflict (Pitfall 6)

**Avoids:**
- "Phase looks broken" conclusion when optimizer produced a correct solution
- GDD spikes from unclipped boundary values
- Wrapped phase sawtooth pattern that obscures phase mask shape

**Research flag:** Needs attention during implementation — the masking-before-unwrapping change requires verifying `_manual_unwrap` behavior on partially zeroed arrays. Test with a synthetic known-phase pulse.

---

### Phase 4: Panel Builder Extraction and Annotation Infrastructure

**Rationale:** Once all individual bugs are fixed in their current locations (Phases 1–3), extract the repeated drawing logic into reusable panel builders. This is the structural refactor that prevents future regressions and enables the merged evolution figure. Doing this before fixing the bugs would mean fixing each bug in 3–4 places.

**Delivers:** A maintainable codebase where any future fix touches one function. Plus: every saved figure is self-documenting with fiber/pulse parameters.

**Addresses:**
- Extract `_panel_spectrum!`, `_panel_temporal!`, `_panel_group_delay!` from `plot_optimization_result_v2` loop (ARCHITECTURE.md Phase 2 refactoring)
- Extract `_panel_evolution_heatmap!` from spectral and temporal evolution functions
- Add `_add_raman_markers!(ax, sim)` as single function for all 4 current call sites
- Add `_add_metadata_annotation!(ax, run_meta)` using `run_meta` NamedTuple (ARCHITECTURE.md run configuration handling)
- Pass `run_meta` to all 4 assemblers from `run_optimization` call site (Pitfall 10)
- Minimum annotation content per figure: fiber type, L [m], P₀ [W], λ₀ [nm], J before/after

**Avoids:**
- Future bug requiring fixes in 3+ separate functions
- Figures that cannot be identified without the filename
- Color inconsistency regressions when a new plot function is added

**Research flag:** Standard patterns — panel builder extraction is mechanical refactoring. `run_meta` NamedTuple pattern is straightforward Julia.

---

### Phase 5: Merged Evolution Figure and Polish

**Rationale:** The last visible-output change: replace two separate evolution PNG files with one merged 4-panel comparison figure. This is last because it requires the panel builder (`_panel_evolution_heatmap!`) to be stable from Phase 4, and it requires the shared colorbar and `constrained_layout` migration to be tested from Phase 3.

**Delivers:** Three final output files per run (down from 4): `opt.png`, `opt_phase.png`, `opt_evolution.png`. The evolution comparison is now immediate — unshaped and optimized are side by side on one figure.

**Addresses:**
- New `plot_evolution_comparison(sol_unshaped, sol_shaped, sim, fiber, run_meta)` assembler with 2×2 layout (ARCHITECTURE.md proposed layout)
- Shared colorbar across all 4 evolution panels
- Increase spectral dB floor to 60 dB for evolution heatmaps (Pitfall 8 — 40 dB hides Raman suppression > 40 dB)
- Migrate to journal-appropriate figure sizes: `figsize=(6.77, 5.0)` for 4-panel evolution (STACK.md section 3)
- Remove legend entries for Raman band and Raman onset — use `ax.text()` annotation instead (Pitfall 13)
- Verify output pixel dimensions of all saved figures at 300 DPI (Pitfall 14)

**Avoids:**
- Two separate files that must be opened and mentally overlaid for comparison
- Raman suppression improvement invisible in evolution heatmap due to 40 dB floor

**Research flag:** The 60 dB vs 40 dB floor decision needs validation against actual run data — confirm the Raman lobe is within the 40–60 dB range (below peak) before changing the default. Check one saved run from `results/raman/smf28/`.

---

### Phase Ordering Rationale

- **Phases 1 before 2:** Raman shading and colormap bugs are in the same functions that need axis/normalization fixes. Doing colormap and color identity first avoids touching the same lines twice.
- **Phases 1–2 before 3:** Phase diagnostic masking threshold (−40 dB) must match the heatmap normalization floor established in Phase 2.
- **Phases 1–3 before 4:** Panel builder extraction should happen after all per-panel bugs are fixed. Extracting broken code into a shared function propagates the bug to every caller; extracting correct code makes the fix permanent.
- **Phase 4 before 5:** The merged evolution figure requires `_panel_evolution_heatmap!` to be the stable extracted panel builder from Phase 4.
- **Phases 1 and 2 can partially overlap:** The rcParams fix (Phase 1) and the pcolormesh grid fix (Phase 2) are independent of each other and of the Raman/colormap fixes.

### Research Flags

**Needs deeper attention during implementation:**
- **Phase 3 (masking before unwrapping):** Verify `_manual_unwrap` correctness on arrays with leading/trailing zeros. Test with a synthetic pulse with known phase before applying to real data. Risk: an off-by-one in the zero-padding could shift the unwrapped result.
- **Phase 5 (60 dB floor):** Validate against one real run output that the Raman lobe is actually in the 40–60 dB range below peak before changing the default. If the lobe is at −35 dB, the current 40 dB floor is adequate and the pitch is moot.

**Standard patterns (no additional research needed):**
- **Phase 1 (colormap, color identity):** Direct code changes with known-correct targets.
- **Phase 2 (axis sharing, normalization):** Standard matplotlib/scientific visualization practice; pattern is documented in PITFALLS.md and ARCHITECTURE.md.
- **Phase 4 (panel builders, annotation):** Mechanical refactoring; Julia NamedTuple pattern is standard.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | rcParams bug confirmed via PyPlot.jl issue #417; colormap recommendation from matplotlib official docs + Dudley SCGBookCode + gnlse-python community; figure size from Optica style guide (MEDIUM for exact pixel specs, HIGH for 8.4 cm single-column width) |
| Features | HIGH | Table stakes bugs are confirmed by direct codebase audit; group delay vs wrapped phase backed by rp-photonics + Agrawal + Dudley 2006 reference set; community consensus from gnlse-python, Luna.jl |
| Architecture | HIGH | Code structure from direct observation of 1016-line file; caller pattern from direct observation of `raman_optimization.jl`; layer pattern is standard practice for plot code with this structure |
| Pitfalls | HIGH | Critical pitfalls (jet, Raman shading, phase masking, normalization, axis mismatch) confirmed by direct codebase audit; Raman shading bug is visible in current output; pcolormesh warning confirmed in v7 run log |

**Overall confidence:** HIGH

### Gaps to Address

- **inferno vs magma choice:** Both are correct. STACK.md favors inferno (physical argument), FEATURES.md cites gnlse-python using magma. Recommend: commit to `inferno` as project default, document in `STYLE[:evolution_cmap]`, and revisit only if the group has a strong aesthetic preference for magma. Not a blocking decision.
- **60 dB vs 40 dB evolution floor:** Needs runtime validation against actual suppression depths before changing default. Check one run from `results/raman/smf28/` to confirm where the Raman lobe sits relative to peak.
- **Solver decoupling in `plot_optimization_result_v2`:** Architecturally wrong (solver inside plotting function) but works. Deferred from this milestone. The Phase 2 axis-sharing fix requires lifting solver calls to the caller, which is the first step of decoupling. Full decoupling (changing function signature to accept pre-computed `sol` dicts) can follow in a later iteration.
- **`text.usetex` LaTeX rendering:** STACK.md recommends against it for batch environments. Confirm the current codebase does not set `text.usetex = true` anywhere — if it does, it is a silent failure risk in non-interactive runs.

---

## Sources

### Primary (HIGH confidence)
- `scripts/visualization.jl` (direct audit, 1016 lines) — confirmed jet colormap, axvspan bug, color literal inconsistencies, phase masking order
- `scripts/raman_optimization.jl` (direct audit) — confirmed solver call location inside `plot_optimization_result_v2`
- `results/raman/raman_run_20260324_v7.log` — confirmed pcolormesh non-monotonic grid warning
- [Matplotlib Colormap Documentation](https://matplotlib.org/stable/users/explain/colors/colormaps.html) — perceptually uniform colormap family; jet/hot as explicit cautionary examples
- [BIDS Colormap Design (viridis/inferno)](https://bids.github.io/colormap/) — inferno design rationale, monotonic L*
- [Kenneth Moreland Color Advice](https://www.kennethmoreland.com/color-advice/) — blackbody/inferno for sequential intensity
- [PyPlot.jl GitHub Issue #417](https://github.com/JuliaPy/PyPlot.jl/issues/417) — rcParams direct assignment fails silently; PyDict pattern required
- [SCGBookCode: test_Dudley.m](https://github.com/jtravs/SCGBookCode) — 40 dB range standard; wavelength [nm] axis; confirms jet was inherited from MATLAB default
- [gnlse-python WUST-FOG](https://github.com/WUST-FOG/gnlse-python) — `magma` default, −40 dB floor confirmed in source
- [Crameri et al. 2021, HESS 25:4549](https://hess.copernicus.org/articles/25/4549/2021/hess-25-4549-2021.html) — quantified 7.5% data variation error from rainbow colormaps
- [Matplotlib Constrained Layout Guide](https://matplotlib.org/stable/users/explain/axes/constrainedlayout_guide.html) — replacement for tight_layout + subplots_adjust conflict
- [rp-photonics: Group Delay](https://www.rp-photonics.com/group_delay.html) — group delay as primary phase representation; more direct than φ(ω)
- [rp-photonics: Spectral Phase](https://www.rp-photonics.com/spectral_phase.html) — deviations from flat phase as the informative measure

### Secondary (MEDIUM confidence)
- [Optica Publishing Group Style Guide](https://opg.optica.org/submit/style/osa-styleguide.cfm) — 8.4 cm single-column width; 17.2 cm double-column; 300/600 DPI requirements (PDF access blocked; derived from search result extraction)
- [Luna.jl](https://github.com/LupoLab/Luna.jl) — dBmin=−40, wavelength range parameter; perceptually uniform colormap usage
- [Wilke: Fundamentals of Data Visualization, Ch. 21](https://clauswilke.com/dataviz/multi-panel-figures.html) — side-by-side column layout for before/after comparison

### Tertiary (LOW confidence — validate during implementation)
- rcParams font size 10 pt at 3.31 in → ~9 pt after Optica figure reduction: derived calculation, not directly verified against a submission
- 60 dB as correct floor for evolution heatmaps: logical inference from J-function suppression depths seen in logs; not directly confirmed against saved heatmap output

---

*Research completed: 2026-03-24*
*Ready for roadmap: yes*
