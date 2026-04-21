# Phase 3: Structure, Annotation, and Final Assembly - Research

**Researched:** 2026-03-24
**Domain:** Julia/PyPlot figure annotation, multi-panel layout assembly, metadata propagation
**Confidence:** HIGH

## Summary

Phase 3 is purely a visualization layer change. No physics, no solver code, and no new dependencies are involved. The codebase already has a functioning annotation pattern (`ax.annotate` with `bbox` dict, `fig.text` for figure-level captions), a shared-colorbar pattern (`fig.add_axes` + `fig.colorbar`), and a 2-column layout established in Phases 1–2. The work divides cleanly into two sub-problems:

**Sub-problem A — Metadata annotation (META-01, META-02, META-03):** Every figure needs a visible parameter block identifying the physical setup. The data already flows through `run_optimization` — fiber params come from `fiber["L"]`, `fiber["γ"]`, and the `setup_raman_problem` kwargs (`λ0`, `P_cont`, `pulse_fwhm`). The challenge is that `plot_optimization_result_v2` and `propagate_and_plot_evolution` currently accept only physics objects, not the human-readable metadata strings. A lightweight `metadata` NamedTuple or keyword argument must thread the relevant strings into the plotting functions without breaking their signatures.

**Sub-problem B — Merged evolution figure (ORG-01, ORG-02):** The two separate calls to `propagate_and_plot_evolution` in `run_optimization` each produce an independent `plot_combined_evolution` figure (2-panel: temporal top, spectral bottom). ORG-01 requires replacing these with one 4-panel figure (2×2: rows = temporal/spectral, columns = optimized/unshaped). The existing `plot_temporal_evolution` and `plot_spectral_evolution` functions already accept `ax` and `fig` injection parameters, making this straightforward to assemble without duplicating rendering logic. The shared-colorbar pattern already exists in `plot_combined_evolution`.

**Primary recommendation:** Implement a `_add_metadata_block!` helper in visualization.jl that takes a figure and a metadata NamedTuple and adds a single `fig.text` annotation. Add a `plot_merged_evolution` function that calls the existing low-level evolution plotters into a 2×2 grid. Update `run_optimization` to pass metadata through and call the new merged function.

## Project Constraints (from CLAUDE.md)

- Tech stack: Julia + PyPlot only. No new visualization dependencies.
- Keep the same function signatures where possible; provide clear migration if changing.
- Output format: PNG at 300 DPI via `savefig(..., dpi=300, bbox_inches="tight")`.
- Naming: `snake_case` functions, `!` suffix for mutating, `_` prefix for private helpers.
- `@assert` for preconditions and postconditions.
- 4-space indentation, no formatter configured.
- Include guard pattern already in place (`_VISUALIZATION_JL_LOADED`).
- `add_caption!` already exists for figure-level text — reuse or extend it.
- All GSD workflow rules apply: no direct edits outside `/gsd:execute-phase`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| META-01 | Every figure includes annotation block: fiber type, L, P0, lambda0, FWHM | `fig.text` at figure level; data available from `fiber["L"]`, `fiber["γ"]`, and setup kwargs |
| META-02 | Optimization cost J (before/after, in dB) annotated on comparison figures | J values already computed in `plot_optimization_result_v2`; `J_values` array already populated — need to move/extend the existing `ΔJ` annotation into a dedicated block |
| META-03 | Evolution figures include fiber length and title identifying optimized vs unshaped | `propagate_and_plot_evolution` already accepts `title` kwarg; merged figure needs explicit column titles |
| ORG-01 | Merge two separate evolution PNGs into single 4-panel comparison figure | New `plot_merged_evolution` function; existing `plot_temporal_evolution` and `plot_spectral_evolution` support `ax` injection |
| ORG-02 | Each run produces exactly 3 output files: opt.png, opt_phase.png, opt_evolution.png | `run_optimization` currently saves 4 files (`opt.png`, `opt_evolution_optimized.png`, `opt_evolution_unshaped.png`, `opt_phase.png`); remove two, add one |
</phase_requirements>

## Standard Stack

No new libraries required. All work uses existing stack:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PyPlot.jl | (project pinned) | Figure rendering, annotation, subplots | Already the only visualization library; PyCall bridge to Matplotlib |
| FFTW.jl | (project pinned) | FFT for evolution propagation | Already used by all evolution helpers |
| MultiModeNoise | 1.0.0-DEV | solve_disp_mmf for evolution propagation | Project's own solver |

**No installation required.** All packages already in Project.toml/Manifest.toml.

## Architecture Patterns

### Current File Topology
```
scripts/
├── visualization.jl        # All plotting functions (include-guarded)
├── common.jl               # Fiber presets + setup functions
├── raman_optimization.jl   # Runs + calls to viz functions, saves files
└── amplitude_optimization.jl  # Same pattern
```

### Pattern 1: Metadata Block via `fig.text`
**What:** Place a single `fig.text` call at a fixed figure-relative position (e.g., bottom-left) that prints the key physical parameters as a multi-line string.
**When to use:** All three output figures (opt.png, opt_phase.png, opt_evolution.png).
**Why `fig.text` over `ax.annotate`:** `fig.text` uses figure coordinates (0–1 range), making it immune to axis rescaling and subplot layout changes. It always appears at the same visual position regardless of the number of subplots.

```julia
# Source: PyPlot/Matplotlib fig.text API (already used in add_caption!)
function _add_metadata_block!(fig, meta; fontsize=8, x=0.01, y=0.01)
    lines = [
        @sprintf("Fiber: %s  L = %.1f m", meta.fiber_name, meta.L_m),
        @sprintf("P₀ = %.0f mW  λ₀ = %.0f nm  FWHM = %.0f fs",
            meta.P_cont_W * 1000, meta.lambda0_nm, meta.fwhm_fs),
    ]
    fig.text(x, y, join(lines, "\n");
        ha="left", va="bottom", fontsize=fontsize,
        color="dimgray", transform=fig.transFigure,
        bbox=Dict("boxstyle" => "round,pad=0.2", "facecolor" => "white",
                  "alpha" => 0.7, "edgecolor" => "lightgray"))
end
```

**Confidence:** HIGH — uses the same `fig.text` + `fig.transFigure` approach already used by `add_caption!` in the codebase.

### Pattern 2: Metadata NamedTuple Threading
**What:** Define a `RunMetadata` NamedTuple in visualization.jl and pass it as an optional `metadata=nothing` keyword argument to plotting functions. Functions check `!isnothing(metadata)` before calling `_add_metadata_block!`.
**When to use:** All three plotting functions that save files: `plot_optimization_result_v2`, `plot_phase_diagnostic`, and the new `plot_merged_evolution`.

```julia
# Constructed in run_optimization, passed to all three plotting calls
struct RunMetadata
    fiber_name::String   # e.g. "SMF-28" or "HNLF"
    L_m::Float64         # fiber length in meters
    P_cont_W::Float64    # average power in Watts
    lambda0_nm::Float64  # center wavelength in nm
    fwhm_fs::Float64     # pulse FWHM in femtoseconds
end
```

Alternatively use a `NamedTuple` (lighter weight, consistent with codebase Dict pattern). The codebase uses NamedTuples for `FIBER_PRESETS` entries. Either works; `@kwdef struct` is also used for `YDFAParams`. A plain NamedTuple is the lightest option and avoids adding a new type definition to the include-guarded block.

### Pattern 3: 2×2 Merged Evolution Figure
**What:** A new `plot_merged_evolution(sol_opt, sol_unshaped, sim, fiber; ...)` function that builds a 2×2 grid using the existing low-level plotters.

**Layout:**
```
              Optimized          Unshaped
           ┌──────────────┬──────────────┐
Temporal   │ plot_temporal │ plot_temporal │
           ├──────────────┼──────────────┤
Spectral   │ plot_spectral │ plot_spectral │
           └──────────────┴──────────────┘
                    [shared colorbar]
```

**How to build using existing primitives:**
```julia
function plot_merged_evolution(sol_opt, sol_unshaped, sim, fiber;
    dB_range=40.0, cmap="inferno", figsize=(14, 10),
    length_unit=:auto, metadata=nothing,
    save_path=nothing)

    fig, axs = subplots(2, 2, figsize=figsize)

    # Column 1: optimized
    _, _, im1 = plot_temporal_evolution(sol_opt, sim, fiber;
        ax=axs[1,1], fig=fig, dB_range=dB_range, cmap=cmap)
    axs[1,1].set_title("Optimized — temporal")

    _, _, _   = plot_spectral_evolution(sol_opt, sim, fiber;
        ax=axs[2,1], fig=fig, dB_range=dB_range, cmap=cmap)
    axs[2,1].set_title("Optimized — spectral")

    # Column 2: unshaped
    _, _, im3 = plot_temporal_evolution(sol_unshaped, sim, fiber;
        ax=axs[1,2], fig=fig, dB_range=dB_range, cmap=cmap)
    axs[1,2].set_title("Unshaped — temporal")

    _, _, _   = plot_spectral_evolution(sol_unshaped, sim, fiber;
        ax=axs[2,2], fig=fig, dB_range=dB_range, cmap=cmap)
    axs[2,2].set_title("Unshaped — spectral")

    # Shared colorbar on the right (same pattern as plot_combined_evolution)
    fig.subplots_adjust(right=0.88)
    cbar_ax = fig.add_axes([0.90, 0.15, 0.025, 0.7])
    cb = fig.colorbar(im1, cax=cbar_ax)
    cb.set_label("Power [dB]")

    # Fiber length in suptitle (META-03)
    fig.suptitle(@sprintf("Evolution comparison — L = %.1f m", fiber["L"]),
        fontsize=13, y=0.99)

    if !isnothing(metadata)
        _add_metadata_block!(fig, metadata)
    end
    ...
end
```

**Key insight:** `plot_temporal_evolution` and `plot_spectral_evolution` already accept `ax=` and `fig=` kwargs for axis injection. This pattern is established in `plot_combined_evolution`. The merged function does not need to duplicate any rendering logic.

### Pattern 4: Cost Annotation Block on opt.png (META-02)
The existing `plot_optimization_result_v2` already computes `J_values` and places a `ΔJ` annotation on the After column. META-02 requires making the before/after J values visible as a pair on the figure.

**Current state:** Single annotation on `axs[1,2]` at `xy=(0.05, 0.85)` shows ΔJ.
**Target:** Each spectral panel shows its own J (already done: `axs[1,col]` at `xy=(0.05, 0.95)`) plus a combined before/after summary somewhere on the figure.

The simplest compliant approach: keep the per-column J annotations exactly as-is, and augment the ΔJ annotation on `axs[1,2]` to include the absolute before/after values:

```julia
# Replace current ΔJ-only annotation with full before/after summary
axs[1, 2].annotate(
    @sprintf("J_before = %.1f dB\nJ_after  = %.1f dB\nΔJ = %.1f dB",
        MultiModeNoise.lin_to_dB(J_values[1]),
        MultiModeNoise.lin_to_dB(J_values[2]),
        -ΔJ_dB),   # negative because ΔJ_dB = J_after_dB - J_before_dB < 0 = improvement
    xy=(0.05, 0.85), xycoords="axes fraction", va="top", fontsize=9,
    color=ΔJ < 0 ? "darkgreen" : "darkred",
    bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))
```

**Confidence:** HIGH — the J_values array and lin_to_dB are already in the function.

### Anti-Patterns to Avoid
- **Passing `fiber` dict directly to plotting functions for metadata:** The `fiber` dict contains non-serializable ODE objects (Dω, γ, hRω). Threading the full dict just for metadata is fragile. Use a lightweight metadata struct/NamedTuple extracted in `run_optimization` before calling plotting.
- **Adding metadata inside the low-level evolution plotters (`plot_temporal_evolution`, `plot_spectral_evolution`):** These are called in multi-panel contexts where only one metadata block per figure is appropriate. Keep metadata addition at the top-level figure-building functions only.
- **Using `ax.annotate` with `xycoords="figure fraction"` for figure-level metadata:** `ax.annotate` transforms through a specific axis, causing issues when axes are repositioned during `tight_layout`. Use `fig.text(..., transform=fig.transFigure)` instead.
- **Calling `tight_layout()` after `fig.add_axes` for the colorbar:** This displaces manually positioned axes. The existing pattern uses `fig.subplots_adjust(right=0.88)` before `add_axes`; do not call `tight_layout` after `add_axes`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Figure-level text annotation | Custom text-box overlay | `fig.text(..., transform=fig.transFigure)` | Already in codebase via `add_caption!`; handles figure coordinate system correctly |
| Multi-panel layout | Manual axis positioning via `fig.add_axes` for all panels | `subplots(2, 2)` + `fig.subplots_adjust` for colorbar only | `subplots` handles spacing; only the colorbar needs manual axis positioning |
| Shared colorbar across 4 panels | One colorbar per panel | `fig.colorbar(im, cax=cbar_ax)` with `add_axes` | Already the established pattern in `plot_combined_evolution` |
| Evolution propagation in merged figure | Re-implementing solve logic | `propagate_and_plot_evolution` returning `sol`, then passing `sol` to `plot_merged_evolution` | Avoids duplicating the `deepcopy(fiber)` + zsave setup already in `propagate_and_plot_evolution` |

## Common Pitfalls

### Pitfall 1: tight_layout displaces manual colorbar axis
**What goes wrong:** Calling `fig.tight_layout()` after `fig.add_axes([0.90, ...])` moves the manually placed colorbar axis into the subplots region.
**Why it happens:** `tight_layout` recalculates all axes positions, including manually placed ones that were added after the subplot grid.
**How to avoid:** Always call `fig.subplots_adjust(right=0.88)` instead of `tight_layout` when a manual colorbar axis is present. This is the pattern already used in `plot_combined_evolution`.
**Warning signs:** Colorbar appears overlapping a subplot panel rather than to the right.

### Pitfall 2: Metadata parameters not available inside visualization.jl
**What goes wrong:** `plot_optimization_result_v2` and `plot_merged_evolution` need fiber_name, λ0_nm, P_cont_W, fwhm_fs — but these are human-readable scalars that don't live in the `fiber` or `sim` dicts at call time (sim["f0"] is in THz, not nm; sim has no P_cont; fiber["L"] is available but fiber["γ"] is a 4D tensor not a scalar).
**Why it happens:** The physics dicts are designed for numerical computation, not display.
**How to avoid:** Construct the metadata NamedTuple in `run_optimization` from the scalar kwargs (`λ0`, `L_fiber`, `P_cont`, `pulse_fwhm`) before they are passed to setup functions. Pass metadata explicitly to all three `save_path` calls.
**Warning signs:** Missing or wrong values in annotation (e.g., lambda in THz, power in wrong units).

### Pitfall 3: Evolution figure re-runs the solver twice unnecessarily
**What goes wrong:** Current code calls `propagate_and_plot_evolution` twice (once for unshaped, once for optimized). Each call does a full ODE solve. A naive merged figure approach calls them twice again.
**Why it happens:** `propagate_and_plot_evolution` encapsulates both the solve and the plot. The merged figure needs solutions from both to be available simultaneously.
**How to avoid:** Run two calls to the standalone solver (or keep two `propagate_and_plot_evolution` calls to get the `sol` return values), then pass both solutions to `plot_merged_evolution`. The existing `propagate_and_plot_evolution` already returns `(sol, fig, axes)` — reuse the `sol` returns rather than solving again. Alternatively, restructure `run_optimization` to call the solver twice and pass sols to a pure plotting function.
**Warning signs:** Optimization script wall time roughly doubles because the evolution solver runs 4 times instead of 2.

### Pitfall 4: ORG-02 file naming mismatch with existing call sites
**What goes wrong:** Other scripts or result-copying logic (e.g., the `cp(joinpath(dir1, "opt.png"), ...)` lines in `raman_optimization.jl`) may reference the old `_evolution_optimized.png` and `_evolution_unshaped.png` names. Removing them without updating all call sites causes missing-file errors.
**Why it happens:** File names are hardcoded in `run_optimization` via `"$(save_prefix)_evolution_unshaped.png"`.
**How to avoid:** Search for all occurrences of `evolution_optimized` and `evolution_unshaped` in scripts before deletion. The only call site currently is `run_optimization` in `raman_optimization.jl`; `amplitude_optimization.jl` may have a similar block.
**Warning signs:** File-not-found errors during the `cp(...)` summary copy at the end of a run.

### Pitfall 5: PyPlot `fig.text` vs `fig.suptitle` vertical spacing conflict
**What goes wrong:** If `fig.suptitle(...)` is used for the fiber-length title AND `fig.text(0.01, 0.01, ...)` for the metadata block, `tight_layout` or `subplots_adjust` may push the suptitle into the plot area or leave too much whitespace.
**Why it happens:** `suptitle` reserves space at y=0.98–1.0 and shifts the subplot grid down; the metadata block at y=0.01 needs enough bottom margin too.
**How to avoid:** Use `fig.subplots_adjust(top=0.95, bottom=0.06)` to explicitly reserve space at both ends, then use `fig.suptitle(..., y=0.98)` and `fig.text(0.01, 0.01, ...)`. Do not call `tight_layout` after suptitle when the layout has both elements.
**Warning signs:** Metadata text clipped by the bottom edge of the saved PNG.

## Code Examples

Verified patterns from the existing codebase:

### Existing `add_caption!` pattern (fig.text with transform)
```julia
# Source: scripts/visualization.jl line 237–241 (current codebase)
function add_caption!(fig, caption; fontsize=9, y=0.01)
    fig.text(0.5, y, caption; ha="center", va="bottom",
             fontsize=fontsize, color="dimgray",
             transform=fig.transFigure)
end
```

### Existing per-axis annotation pattern (ax.annotate with bbox)
```julia
# Source: scripts/visualization.jl lines 865–867 (plot_optimization_result_v2)
axs[1, col].annotate(@sprintf("J = %.4f (%.1f dB)", J_val, MultiModeNoise.lin_to_dB(J_val)),
    xy=(0.05, 0.95), xycoords="axes fraction", va="top", fontsize=10,
    bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8))
```

### Existing shared colorbar pattern (the pattern to replicate in merged figure)
```julia
# Source: scripts/visualization.jl lines 570–573 (plot_combined_evolution)
fig.subplots_adjust(right=0.88)
cbar_ax = fig.add_axes([0.90, 0.15, 0.025, 0.7])
cb = fig.colorbar(im_s, cax=cbar_ax)
cb.set_label("Power [dB]")
```

### Existing ax-injection pattern (confirms low-level plotters can be composed)
```julia
# Source: scripts/visualization.jl lines 556–566 (plot_combined_evolution)
_, ax_t, im_t = plot_temporal_evolution(sol, sim, fiber;
    mode_idx=mode_idx, dB_range=dB_range, time_limits=time_limits,
    cmap=cmap, length_unit=length_unit, ax=axes[1], fig=fig)

_, ax_s, im_s = plot_spectral_evolution(sol, sim, fiber;
    mode_idx=mode_idx, dB_range=dB_range, wavelength_limits=wavelength_limits,
    cmap=cmap, length_unit=length_unit, ax=axes[2], fig=fig)
```

### Existing file-save pattern (to be replicated for merged evolution)
```julia
# Source: scripts/visualization.jl lines 933–935 (plot_optimization_result_v2)
if !isnothing(save_path)
    savefig(save_path, dpi=300, bbox_inches="tight")
    @info "Saved optimization result to $save_path"
end
```

## Call Site Inventory (ORG-02 impact)

Current calls in `run_optimization` that produce evolution files (lines 473–479 of raman_optimization.jl):

```julia
# CURRENT (produces 2 files)
propagate_and_plot_evolution(uω0, fiber, sim;
    title="Unshaped pulse evolution (L=$(fiber["L"])m)",
    save_path="$(save_prefix)_evolution_unshaped.png")
propagate_and_plot_evolution(uω0_opt, fiber, sim;
    title="Optimized pulse evolution (L=$(fiber["L"])m)",
    save_path="$(save_prefix)_evolution_optimized.png")
```

**Target (produces 1 file):**
```julia
# NEW: two solves + one merged save
sol_unshaped, _, _ = propagate_and_plot_evolution(uω0, fiber, sim)      # solve only, no save
sol_opt, _, _      = propagate_and_plot_evolution(uω0_opt, fiber, sim)  # solve only, no save
plot_merged_evolution(sol_opt, sol_unshaped, sim, fiber;
    metadata=run_meta,
    save_path="$(save_prefix)_evolution.png")
```

Check `amplitude_optimization.jl` for the same pattern — it likely has an identical evolution-plotting block that also needs updating.

## Pending Requirements from Earlier Phases (Not Phase 3)

The following requirements are pending per REQUIREMENTS.md but NOT assigned to Phase 3. The planner should not include them:

- **BUG-02** (Phase 1, pending): jet colormap replacement — skip
- **AXIS-03** (Phase 1, pending): disable grid on pcolormesh axes — skip
- **STYLE-03** (Phase 1, pending): evolution heatmaps -40 dB floor + inferno + shared colorbar label — skip

The planner should verify these remain out-of-scope for this phase even though they are still pending. They belong to Phase 1's remaining work.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Two separate evolution PNGs | Merged 2×2 comparison PNG | Phase 3 (this phase) | Side-by-side comparison without mental stitching |
| No metadata on figures | Parameter annotation block + J annotations | Phase 3 (this phase) | Figure is self-documenting |
| Separate `add_caption!` for captions | Unified `_add_metadata_block!` for physics metadata | Phase 3 (this phase) | Consistent placement across all 3 output types |

## Open Questions

1. **Evolution floor: 40 dB vs 60 dB**
   - What we know: STATE.md flags "Validate 60 dB vs 40 dB evolution floor against one real run from results/raman/smf28/"
   - What's unclear: The current `plot_temporal_evolution` and `plot_spectral_evolution` default to `dB_range=40.0`. The flag asks whether 60 dB gives more useful dynamic range for real data.
   - Recommendation: The planner should include a task to inspect existing output PNGs in `results/raman/smf28/L1m_P005W/` and decide the default before finalizing `plot_merged_evolution`. This is a one-liner parameter change but should not be deferred — the merged evolution figure is new code, so this is the right time to decide. Default to 40 dB unless inspection shows meaningful signal between -40 and -60 dB.

2. **Does amplitude_optimization.jl have the same evolution-plotting call pattern?**
   - What we know: `raman_optimization.jl` calls `propagate_and_plot_evolution` twice; `amplitude_optimization.jl` likely does too.
   - What's unclear: The file was not fully read — the specific call site at the end of its `run_optimization` equivalent was not confirmed.
   - Recommendation: The planner should include a task to read the relevant section of `amplitude_optimization.jl` before modifying it, to verify the call pattern matches.

## Environment Availability

Step 2.6: SKIPPED — Phase 3 is code/config changes only. All dependencies are already installed and verified working by Phases 1 and 2.

## Validation Architecture

Step 4: SKIPPED — `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`.

## Sources

### Primary (HIGH confidence)
- Direct code reading: `scripts/visualization.jl` (lines 237–241, 556–573, 762–938, 1223–1239) — confirmed annotation patterns, ax-injection pattern, shared colorbar pattern, `propagate_and_plot_evolution` return values
- Direct code reading: `scripts/raman_optimization.jl` (lines 463–488) — confirmed current 4-file save pattern and exact save_path strings
- Direct code reading: `scripts/common.jl` — confirmed metadata field names available from `setup_raman_problem` kwargs
- Direct code reading: `.planning/REQUIREMENTS.md` — confirmed requirement scope and pending status
- Direct code reading: `.planning/STATE.md` — confirmed Phase 3 flag re evolution floor

### Secondary (MEDIUM confidence)
- PyPlot/Matplotlib `fig.text` API with `transform=fig.transFigure` — inferred from existing `add_caption!` implementation which uses the same pattern; no external doc lookup needed

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries, all existing
- Architecture patterns: HIGH — all patterns read directly from current codebase
- Pitfalls: HIGH — pitfalls 1–3 derived from direct code reading; pitfall 4 from explicit filename grep; pitfall 5 from known Matplotlib behavior

**Research date:** 2026-03-24
**Valid until:** Stable — no external dependencies, no fast-moving ecosystem concerns
