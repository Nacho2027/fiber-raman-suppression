# Architecture Patterns: Visualization Code Organization

**Domain:** Nonlinear fiber optics simulation visualization (Julia + PyPlot)
**Researched:** 2026-03-24
**Scope:** Restructuring `scripts/visualization.jl` (~1016 lines, ~12 public functions)

---

## Current State Inventory

### Functions in visualization.jl

| Section | Function | Role | Lines (approx) |
|---------|----------|------|----------------|
| 0 | rcParams block | Global style config | 1–41 |
| 1 | `wrap_phase`, `set_phase_yticks!` | Phase display helpers | 56–65 |
| 2 | `_length_display`, `_freq_to_wavelength`, `_auto_time_limits`, `_energy_window` | Axis/grid utilities | 68–130 |
| 2b | `_manual_unwrap`, `_central_diff`, `_second_central_diff`, `_spectral_omega_step`, `_apply_dB_mask`, `compute_group_delay`, `compute_gdd`, `compute_instantaneous_frequency` | Phase math | 132–243 |
| 2b | `plot_phase_diagnostic` | Phase panel figure | 245–318 |
| 3 | `plot_spectral_evolution` | Heatmap figure | 320–379 |
| 4 | `plot_temporal_evolution` | Heatmap figure | 381–438 |
| 5 | `plot_combined_evolution` | Two-panel evolution | 440–481 |
| 6 | `plot_spectrogram` | STFT figure (unused in current runs) | 483–566 |
| 7 | `plot_spectrum_comparison` | Before/after spectra | 568–635 |
| 8 | `plot_optimization_result_v2` | 3×2 comparison figure | 637–775 |
| 9 | `plot_amplitude_result_v2` | 3×2 amplitude variant | 777–892 |
| 10 | `plot_boundary_diagnostic` | Single-panel diagnostic | 894–953 |
| 11 | `plot_convergence` | Cost curve | 955–986 |
| 12 | `propagate_and_plot_evolution` | Re-propagate + evolution | 988–1014 |

### Callers (in raman_optimization.jl `run_optimization`)

```
run_optimization(...)
  ├── plot_optimization_result_v2(...)   → opt.png
  ├── propagate_and_plot_evolution(...)  → opt_evolution_unshaped.png
  ├── propagate_and_plot_evolution(...)  → opt_evolution_optimized.png
  └── plot_phase_diagnostic(...)         → opt_phase.png
```

`plot_optimization_result_v2` itself internally calls `MultiModeNoise.solve_disp_mmf` twice (before and after). This is a hidden side effect — the comparison figure re-runs the solver.

---

## Recommended Architecture

### One file vs. multiple files

**Recommendation: Keep one file, reorganize internally with explicit section headers.**

Rationale:
- Julia's `include()` mechanism has no module namespace isolation between included files. Multiple files would either (a) pollute the top-level namespace equally, or (b) require converting to a proper module/package — a scope change beyond this milestone.
- The 1016-line size is manageable. The problem is not file length; it is the lack of layered structure within the file.
- A helper module approach (`module VizHelpers ... end` inside the same file) adds complexity without benefit since all downstream callers are in the same script context.
- The include guard pattern already in use (`_VISUALIZATION_JL_LOADED`) works correctly for a single file.

**Do not split into multiple files for this milestone.** The refactoring order and internal layering described below achieves the same goals without import complexity.

### Internal Layer Structure (within the single file)

Reorganize the file into four explicit layers, separated by section banners:

```
Layer 0: CONFIG
  - rcParams block (currently lines 29-41)
  - Color constants
  - Physical constants
  - Style dict (new: centralized style configuration)

Layer 1: MATH PRIMITIVES  [no pyplot calls]
  - _manual_unwrap
  - _central_diff
  - _second_central_diff
  - _spectral_omega_step
  - _apply_dB_mask
  - _freq_to_wavelength
  - _length_display
  - _auto_time_limits
  - _energy_window
  - wrap_phase
  - set_phase_yticks!
  - compute_group_delay
  - compute_gdd
  - compute_instantaneous_frequency

Layer 2: PANEL BUILDERS  [draw into an existing ax; return nothing]
  - _panel_spectrum!(ax, ...)
  - _panel_temporal!(ax, ...)
  - _panel_group_delay!(ax, ...)
  - _panel_amplitude!(ax, ...)
  - _panel_phase_unwrapped!(ax, ...)
  - _panel_gdd!(ax, ...)
  - _panel_instfreq!(ax, ...)
  - _panel_evolution_heatmap!(ax, ...)
  - _add_raman_markers!(ax, ...)      ← fixes the axvspan bug
  - _add_metadata_annotation!(ax, ...) ← fiber/pulse params

Layer 3: FIGURE ASSEMBLERS  [create figure, lay out panels, save]
  - plot_optimization_result_v2(...)  → opt.png
  - plot_phase_diagnostic(...)        → opt_phase.png
  - plot_combined_evolution(...)      → (used by propagate_and_plot_evolution)
  - plot_spectral_evolution(...)
  - plot_temporal_evolution(...)
  - plot_spectrogram(...)
  - plot_spectrum_comparison(...)
  - plot_amplitude_result_v2(...)
  - plot_boundary_diagnostic(...)
  - plot_convergence(...)
  - propagate_and_plot_evolution(...)
```

### Component Boundaries

| Component | Responsibility | Allowed to Call | Must NOT call |
|-----------|---------------|-----------------|---------------|
| Layer 0 (Config) | Define constants and style dict | Nothing | PyPlot, FFTW |
| Layer 1 (Math) | Pure numerical transforms | Layer 0 constants | PyPlot, solver |
| Layer 2 (Panels) | Draw single subplot | Layer 0, Layer 1 | Figure creation, solver |
| Layer 3 (Figures) | Assemble multi-panel figures | Layer 0, 1, 2 | Solver (see note) |

**Note on solver calls in Layer 3:** `plot_optimization_result_v2` and `plot_amplitude_result_v2` currently call `MultiModeNoise.solve_disp_mmf` internally. This violates the boundary between visualization and simulation. The fix (lower priority, deferred to a later phase) is to accept pre-computed solution data as arguments instead of raw phase/amplitude. For this milestone, the solver calls stay but should be documented explicitly.

---

## Plot Output Set Recommendation

### Current output (4 files per run)

| File | Content | Size |
|------|---------|------|
| `opt.png` | 3×2: spectra × 2, temporal × 2, group delay × 2 | 12×12 in |
| `opt_phase.png` | 2×2: unwrapped phase, group delay, GDD, inst. freq | 12×9 in |
| `opt_evolution_optimized.png` | 2-panel: temporal + spectral heatmaps | 8×10 in |
| `opt_evolution_unshaped.png` | 2-panel: temporal + spectral heatmaps | 8×10 in |

### Recommended output (3 files per run)

**Merge the two evolution plots into one figure. Keep the other three files.**

| File | Content | Change |
|------|---------|--------|
| `opt.png` | 3×2 comparison (unchanged layout, fixed content) | Existing — fix bugs |
| `opt_phase.png` | 2×2 phase diagnostic (unchanged layout) | Existing — fix bugs |
| `opt_evolution.png` | 4-panel: unshaped temporal, unshaped spectral, shaped temporal, shaped spectral | New merged figure |

**Rationale for merging evolution plots:**
- The primary purpose of both evolution files is comparison between unshaped and shaped propagation. Placing them side-by-side in one figure makes the comparison immediate and eliminates the need to open two files.
- A 2×2 or 4×1 layout with shared colorbars and labeled columns ("Unshaped" / "Optimized") is the standard format in Dudley et al. (2006) and subsequent supercontinuum literature when comparing two conditions.
- Four separate PNG files per run creates cognitive overhead during lab meetings.
- Three files is the natural decomposition: comparison (opt.png), phase physics (opt_phase.png), propagation physics (opt_evolution.png).

**Proposed `opt_evolution.png` layout:**

```
┌──────────────────────┬──────────────────────┐
│  Unshaped            │  Optimized           │
│  Temporal evolution  │  Temporal evolution  │
│  (t vs z heatmap)    │  (t vs z heatmap)    │
├──────────────────────┼──────────────────────┤
│  Unshaped            │  Optimized           │
│  Spectral evolution  │  Spectral evolution  │
│  (λ vs z heatmap)    │  (λ vs z heatmap)    │
└──────────────────────┴──────────────────────┘
         shared colorbar (right side)
```

Column labels and a supertitle carry the fiber + pulse metadata annotation.

---

## Style Configuration Pattern

### Recommended: centralized style dict

Replace the scattered hardcoded color strings (`"b--"`, `"darkgreen"`, `"r-"`, `COLOR_REF`) with a single style dictionary defined in Layer 0:

```julia
const STYLE = Dict(
    # Lines
    :input         => Dict("color" => COLOR_INPUT,  "lw" => 1.5, "ls" => "--", "alpha" => 0.8),
    :output        => Dict("color" => COLOR_OUTPUT, "lw" => 1.2, "ls" => "-",  "alpha" => 0.9),
    :shaped_input  => Dict("color" => COLOR_INPUT,  "lw" => 1.5, "ls" => "-",  "alpha" => 0.8),
    :shaped_output => Dict("color" => COLOR_OUTPUT, "lw" => 1.2, "ls" => "-",  "alpha" => 0.9),
    :reference     => Dict("color" => COLOR_REF,    "lw" => 0.8, "ls" => "-",  "alpha" => 1.0),
    :raman_vline   => Dict("color" => COLOR_RAMAN,  "lw" => 0.8, "ls" => "--", "alpha" => 0.6),
    :raman_span    => Dict("color" => COLOR_RAMAN,  "alpha" => 0.08),

    # Heatmaps (to be determined by colormap research)
    :evolution_cmap => "inferno",   # placeholder — replace after STACK.md colormap decision

    # Annotations
    :annotation_box => Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
    :annotation_fs  => 9,
)
```

**Why this matters:** The current code has `"b--"` hardcoded in at least 4 separate functions and `"darkgreen"` in 3. When the colormap research (see STACK.md) resolves the correct Okabe-Ito mapping, there is one place to change instead of twelve.

---

## Run Configuration Handling

### Problem: functions ignore fiber identity

`plot_optimization_result_v2` and `plot_phase_diagnostic` currently receive `uω0_base`, `fiber`, `sim`, `band_mask`, `Δf`, `raman_threshold` but produce no fiber-identifying annotation. When a lab member looks at `opt.png` for `hnlf/L2m_P005W`, nothing in the plot tells them the fiber type or parameters.

### Recommended pattern: metadata annotation struct

Define a lightweight named tuple (not a full struct — avoids type system complexity):

```julia
# Example call site in run_optimization:
run_meta = (
    fiber_name  = "HNLF",
    L_m         = fiber["L"],
    gamma       = fiber["γ"][1],
    beta2_ps2m  = ...,
    P_cont_W    = P_cont,
    pulse_fwhm_fs = pulse_fwhm * 1e15,
    lambda0_nm  = C_NM_THZ / sim["f0"],
    N_soliton   = N_sol,
)
```

Pass `run_meta` to all figure assemblers. The `_add_metadata_annotation!` panel-level function (Layer 2) formats it as a figure subtitle or top-right text box using a consistent template. This handles varying fiber types and lengths gracefully because the annotation is data-driven, not hardcoded.

### Axis range handling for different configurations

The current `λ0_nm ± 300/500 nm` hardcoded range in multiple functions fails for HNLF runs where the spectrum broadens much more aggressively. Recommended fix:

```julia
function _spectral_xlim(sim; margin_short=300.0, margin_long=600.0)
    λ0 = C_NM_THZ / sim["f0"]
    # Return conservative window; caller can override with explicit wavelength_limits
    return (λ0 - margin_short, λ0 + margin_long)
end
```

All panel builders call `_spectral_xlim(sim)` as default, but Layer 3 assemblers can pass `wavelength_limits` to override when they have seen the actual spectral data extent.

---

## Data Flow Direction

```
run_optimization(kwargs...)
    │
    ├─ setup_raman_problem(...) → uω0, fiber, sim, band_mask
    │
    ├─ optimize_spectral_phase(...) → φ_after
    │
    └─ VISUALIZATION ENTRY POINTS
         │
         ├─ plot_optimization_result_v2(φ_before, φ_after, uω0, fiber, sim, ...)
         │    │
         │    ├─ [solver call ×2 — side effect, see note above]
         │    │
         │    └─ _panel_spectrum!(ax, ...)
         │       _panel_temporal!(ax, ...)
         │       _panel_group_delay!(ax, ...)
         │       _add_raman_markers!(ax, ...)
         │       _add_metadata_annotation!(ax, run_meta)
         │
         ├─ propagate_and_plot_evolution(uω0, fiber, sim, ...) [unshaped]
         │    └─ solve_disp_mmf → sol
         │         └─ plot_combined_evolution(sol, sim, fiber, ...)
         │              └─ _panel_evolution_heatmap!(ax, ...)  ×4
         │
         ├─ propagate_and_plot_evolution(uω0_opt, fiber, sim, ...) [shaped]
         │    └─ (same as above)
         │
         └─ plot_phase_diagnostic(φ_after, uω0, sim, ...)
              └─ _panel_phase_unwrapped!(ax, ...)
                 _panel_group_delay!(ax, ...)
                 _panel_gdd!(ax, ...)
                 _panel_instfreq!(ax, ...)
```

After the evolution merge, `propagate_and_plot_evolution` is called once per condition and the two resulting `sol` dicts are passed to a single `plot_evolution_comparison` assembler:

```
plot_evolution_comparison(sol_unshaped, sol_shaped, sim, fiber, run_meta)
    └─ _panel_evolution_heatmap!(ax_t_unshaped, sol_unshaped, sim, fiber, :temporal)
       _panel_evolution_heatmap!(ax_s_unshaped, sol_unshaped, sim, fiber, :spectral)
       _panel_evolution_heatmap!(ax_t_shaped,   sol_shaped,   sim, fiber, :temporal)
       _panel_evolution_heatmap!(ax_s_shaped,   sol_shaped,   sim, fiber, :spectral)
```

---

## Refactoring Order (Build Dependencies)

The layers must be built bottom-up. Each step is independently testable.

### Phase 1 — Foundation (no visible change to output)

1. **Extract Layer 0 style dict.** Add `STYLE` constant. Replace all hardcoded color strings in existing functions with `STYLE[...]` lookups. Run smoke test (`test_visualization_smoke.jl`) to confirm no regression.
2. **Consolidate `_add_raman_markers!`.** Fix the `axvspan` bug (currently shades the wrong λ range — uses `Δf_shifted .< raman_threshold` which selects the wrong-sign side). Extract into a single tested function. All four current call sites (`plot_optimization_result_v2`, `plot_amplitude_result_v2`, `plot_spectrum_comparison`, `plot_phase_diagnostic`) call this one function.
3. **Standardize time/spectral axis helpers.** Consolidate the duplicated `λ0_nm ± 300/500` hardcodings into `_spectral_xlim`. Fix `_auto_time_limits` so before/after panels share the same computed range (current: each column computes independently).

   *Why first:* These are pure utility changes. They are the foundation everything else builds on and have no external API change.

### Phase 2 — Panel Builders (internal refactor)

4. **Extract `_panel_spectrum!`, `_panel_temporal!`, `_panel_group_delay!`.** The 3×2 body of `plot_optimization_result_v2` duplicates a large `for (col, ...) in enumerate(...)` loop. Extract the per-panel drawing logic into panel builders with consistent signatures: `_panel_X!(ax, data, sim; kwargs...)`. The assembler loop becomes 6 lines.
5. **Extract `_panel_evolution_heatmap!`.** Used by both spectral and temporal evolution functions, already quasi-isolated.
6. **Extract `_add_metadata_annotation!`.** Takes `run_meta` NamedTuple, renders it as a figure text box in a consistent position.

   *Why second:* Panel builders cannot be extracted before the utility layer is stabilized (Phase 1), because they depend on the corrected axis helpers.

### Phase 3 — Figure Assemblers (visible output changes)

7. **Fix `opt.png` content:** colormap (pending research), Raman shading (bug fix from Phase 1), metadata annotation (from Phase 2), shared time axis range (from Phase 1).
8. **Fix `opt_phase.png` content:** dB masking threshold tuning, axis ranges, annotation.
9. **New `plot_evolution_comparison`.** Replace the two separate `propagate_and_plot_evolution` calls in `run_optimization` with one call that produces the merged 4-panel `opt_evolution.png`. Remove the old `opt_evolution_optimized.png` and `opt_evolution_unshaped.png` outputs.
10. **Update `run_optimization` call site** to pass `run_meta` to all assemblers.

   *Why third:* Figure assemblers depend on panel builders being correct. The evolution merge is last because it changes the output file set — the most visible change and the one most likely to need iteration.

---

## Before/After Comparison Structure

### Current problem

`plot_optimization_result_v2` runs the solver inside the plotting function, once for "before" and once for "after", in a `for (col, ...) in enumerate(...)` loop. This means:
- Time axis ranges are computed per-column independently. The before panel and after panel show different time windows, making comparison difficult.
- The solver is called twice inside a plotting function, hiding the cost.

### Recommended structure

```julia
# Caller (run_optimization) pre-computes both solutions:
sol_before = solve_disp_mmf(uω0, fiber_bc, sim)
sol_after  = solve_disp_mmf(uω0_opt, fiber_bc, sim)

# Then calls assembler with both:
plot_optimization_result_v2(
    φ_before, φ_after,
    sol_before, sol_after,   # ← pre-computed, no solver inside
    uω0, fiber, sim,
    band_mask, Δf, raman_threshold;
    run_meta = run_meta,
    save_path = ...
)
```

Inside the assembler, shared axis limits are computed once from the union of both solutions before any drawing occurs:

```julia
# Compute shared time window from both conditions
t_lims_before = _energy_window(P_in_before, ts_ps)
t_lims_after  = _energy_window(P_in_after,  ts_ps)
t_shared = (min(t_lims_before[1], t_lims_after[1]),
            max(t_lims_before[2], t_lims_after[2]))
# Apply to both columns
axs[2, 1].set_xlim(t_shared...)
axs[2, 2].set_xlim(t_shared...)
```

This is the correct pattern for before/after comparison clarity.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Panel-level solver calls

**What:** `plot_optimization_result_v2` and `plot_amplitude_result_v2` call `solve_disp_mmf` internally.
**Why bad:** Makes plotting slow and non-deterministic (solver adds runtime). Hides the coupling in the call chain. Prevents reuse of the visualization functions without re-solving.
**Instead:** Accept pre-computed `sol` dicts. The run_optimization caller already has the solutions.

### Anti-Pattern 2: Duplicated axis limit logic

**What:** `λ0_nm - 300, λ0_nm + 500` appears 7+ times in the file as a literal, each independently.
**Why bad:** HNLF runs have wider spectra. When a run's spectrum exceeds the hardcoded range, the heatmap is silently clipped. There is no single place to change the convention.
**Instead:** `_spectral_xlim(sim)` as the single source, overridable per-call.

### Anti-Pattern 3: Color strings mixed with semantic roles

**What:** `"b--"` for input, `"darkgreen"` for output, `"r-"` in some plots, `COLOR_INPUT` (Okabe-Ito blue) in others. Input is not a consistent color across all plot types.
**Why bad:** A reader attending a lab meeting sees blue input in `opt.png` and a different color in `opt_phase.png`. The visual identity of "unshaped input" should be the same in every figure.
**Instead:** `STYLE[:input]` always maps to `COLOR_INPUT` (#0072B2). Never use matplotlib color shorthand strings in figure assemblers.

### Anti-Pattern 4: Independent figure saves inside panel builders

**What:** Not currently present, but the refactoring must not introduce it.
**Why bad:** `savefig` must only be called at Layer 3 (figure assemblers), never inside panel builders. Panel builders draw to axes they do not own.
**Instead:** Layer 3 assembler receives `save_path` and calls `savefig` after all panels are drawn.

---

## Scalability Considerations

| Concern | Current | After refactor |
|---------|---------|---------------|
| Adding a new panel type | Edit 1–3 large functions | Add one `_panel_X!` function in Layer 2 |
| Changing colormap globally | Edit 6+ `cmap="jet"` occurrences | Edit `STYLE[:evolution_cmap]` once |
| Adding a new fiber config | Plot axes silently wrong if spectrum exceeds hardcoded range | `_spectral_xlim` adapts; `run_meta` carries fiber identity |
| Adding a third condition (e.g. warm-start) | Fork another column in large function | Add a column to assembler; panel builders unchanged |
| Changing output resolution | Edit `dpi=300` in 5+ `savefig` calls | Edit rcParam once in Layer 0 |

---

## Sources

- Code structure analysis: `scripts/visualization.jl` (read directly, 1016 lines)
- Caller pattern: `scripts/raman_optimization.jl`, `run_optimization` function (lines 332–453)
- Output files observed: `results/raman/smf28/L1m_P005W/` (4 files per run confirmed)
- Dudley, J. M., Genty, G., & Coen, S. (2006). Supercontinuum generation in photonic crystal fiber. *Rev. Mod. Phys.* 78, 1135. — Referenced in file docstring as standard for evolution figure layout.
- Confidence: HIGH for code structure (direct observation). MEDIUM for panel-builder pattern (standard matplotlib/PyPlot practice, not Julia-specific literature).
