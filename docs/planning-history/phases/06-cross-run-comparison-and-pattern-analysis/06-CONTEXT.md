# Phase 6: Cross-Run Comparison and Pattern Analysis - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Compare all 5 optimization runs in overlay figures and a summary table, decompose each optimized phase profile onto a physical polynomial basis, and annotate soliton number N. Requires re-running the 5 configs first to generate JLD2 files (Phase 5 added serialization but the runs haven't been executed yet). Does NOT add new optimization configs, parameter sweeps, or modify the optimizer itself.

</domain>

<decisions>
## Implementation Decisions

### Run Generation
- **D-01:** Phase 6 includes re-running all 5 production configs as its first step. The comparison script is self-contained — it calls `raman_optimization.jl` (which now saves JLD2 + manifest via Phase 5) to generate data, then loads and analyzes it. No manual user intervention needed.

### Summary Table
- **D-02:** Cross-run summary table rendered as a PNG figure via matplotlib (same quality as other plots, presentation-ready). Columns: fiber type, L, P, J_before, J_after, ΔdB, iterations, wall time, soliton number N. Saved to `results/images/`. No markdown file — keep output consistent with existing visualization pipeline.

### Overlay Plot Design
- **D-03:** Produce both views:
  - **All-runs convergence overlay**: Single figure, all 5 runs on shared axes, J vs iteration, color-coded by config with clear legend. Shows relative optimization difficulty.
  - **Per-fiber spectral overlays**: Separate SMF-28 and HNLF figures, each showing optimized output spectra on shared dB axes. Enables within-fiber-type comparison of length/power effects.
  - Total: 3 overlay figures (1 convergence + 2 spectral).
  - Color scheme: Use distinguishable colors per config (not COLOR_INPUT/COLOR_OUTPUT which are for single-run before/after). Suggest a 5-color palette from Okabe-Ito extended set.

### Phase Decomposition
- **D-04:** Claude's discretion on decomposition method. Recommended approach: least-squares polynomial fit of φ_opt(ω) up to 3rd order in the signal-bearing spectral region. Report GDD coefficient (fs²), TOD coefficient (fs³), and residual fraction (1 - R² or norm ratio). If residual is small, the optimizer found a physically interpretable chirp. If residual is large, the phase has non-polynomial structure worth investigating.

### Soliton Number
- **D-05:** Compute N = √(γ × P_peak × T₀² / |β₂|) for each run. Add to manifest.json and include in the summary table figure. T₀ = FWHM / (2 × acosh(√2)) for sech pulse assumption.

### Claude's Discretion
- Script organization: whether to create one `scripts/run_comparison.jl` or split into multiple files
- Exact color palette for the 5-config overlay
- Phase decomposition method details (polynomial fit vs Taylor expansion)
- Whether to include convergence history in the summary table figure or keep it separate
- Figure sizes and DPI (follow existing 300 DPI convention)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Data Source (Phase 5 Output)
- `scripts/raman_optimization.jl` (lines 485-570) — JLD2 save block and manifest update logic. Shows exact field names and types saved per run.
- `scripts/raman_optimization.jl` (lines 640-710 approx) — The 5 production run configs in the main block. Each calls `run_optimization()` with specific kwargs.

### Visualization Patterns
- `scripts/visualization.jl` — Existing plotting functions. Follow established patterns: 300 DPI, inferno colormap for heatmaps, Okabe-Ito colors, metadata annotation, `fig.savefig()` with `bbox_inches="tight"`.
- `scripts/common.jl` — `FIBER_PRESETS`, `setup_raman_problem` (for re-running configs)

### Phase 4 Findings
- `results/raman/validation/verification_20260325_173537.md` — Photon number drift data per config. Context for interpreting cross-run J values.
- `.planning/phases/04-correctness-verification/04-CONTEXT.md` — sim["ωs"] already includes ω₀

### Research
- `.planning/research/FEATURES.md` (lines 213-242) — Cross-run metadata JSON schema, overlay plot specifications
- `.planning/research/PITFALLS.md` — Phase profile comparison requires removing global offset and linear term before overlaying. Grid mismatch invalidates J comparison.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `plot_optimization_result_v2()` in visualization.jl — existing comparison plot pattern (3×2 grid). Phase 6 overlay plots should follow similar figure construction patterns.
- `_spectral_signal_xlim()` in visualization.jl — auto-zoom helper for spectral axes. Reuse for consistent spectral axis limits across overlay panels.
- `COLOR_INPUT`, `COLOR_OUTPUT`, `COLOR_RAMAN`, `COLOR_REF` constants — for single-run plots. Phase 6 needs a DIFFERENT palette for multi-run overlays (5 distinguishable colors).
- `run_meta` NamedTuple saved in JLD2 — load directly for figure annotations.
- `add_caption!()` pattern in visualization.jl — metadata annotation on figures.

### Established Patterns
- Figures at 300 DPI, `bbox_inches="tight"`
- Results to `results/images/` for comparison figures (separate from per-run `results/raman/` PNGs)
- `using PyPlot; ENV["MPLBACKEND"] = "Agg"` for headless rendering
- Include guards: `_COMMON_JL_LOADED`, `_VISUALIZATION_JL_LOADED`

### Integration Points
- Load JLD2 files via `JLD2.load("path")` → Dict with string keys
- Load manifest via `JSON3.read(read("manifest.json", String))`
- New script `scripts/run_comparison.jl` includes common.jl and visualization.jl
- Output directory: `results/images/` (create if needed via `mkpath`)

</code_context>

<specifics>
## Specific Ideas

- Phase profile overlay: before comparing φ_opt across runs, remove global phase offset (φ_opt[1]) and linear trend (group delay) so only the physically meaningful chirp structure remains. This is from the pitfalls research — without normalization, identical physics looks like random noise when overlaid.
- For spectral overlays: show both input and optimized output spectra per run, so the viewer sees how much each config suppresses Raman relative to its starting point.
- Soliton number N can be computed from run_meta fields already in JLD2 (P_cont, fwhm, fiber betas, gamma). No need to re-run propagation.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 06-cross-run-comparison-and-pattern-analysis*
*Context gathered: 2026-03-25*
