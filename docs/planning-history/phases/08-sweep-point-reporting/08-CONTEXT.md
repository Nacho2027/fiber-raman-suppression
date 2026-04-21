# Phase 8: Sweep Point Reporting - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Generate human-readable per-point outputs (report card figure + markdown summary) for every sweep configuration, plus a sweep-level ranked summary table. Outputs go in existing per-point directories (`results/raman/sweeps/<fiber>/L*_P*/`). Post-hoc script reads JLD2 — no re-running optimization.

</domain>

<decisions>
## Implementation Decisions

### Per-Point Plot Set
- **D-01:** Single 4-panel "report card" figure per point (NOT the full 6-PNG set). Panels: (1) spectral before/after in dB, (2) optimized phase profile (all 3 views: wrapped, unwrapped, group delay per professor's requirement), (3) convergence trace J(iter) in dB, (4) text box with key metrics.
- **D-02:** The report card does NOT require re-propagation. Spectral before/after can be computed from uomega0 + phi_opt without solving the ODE (input spectrum is just |uomega0|², output spectrum requires applying phase then FFT but the Raman band energy fraction is already in J_after). For the spectral panel, show input spectrum + band_mask region only (not propagated output). The convergence and phase panels use stored data directly.

### Sweep-Level Summary
- **D-03:** A single markdown file per fiber type (`results/raman/sweeps/<fiber>/SWEEP_SUMMARY.md`) with a ranked table sorted by suppression quality (best first). Columns: L, P, J_after (dB), quality label, converged, iterations, drift%, N_sol, Nt, time_window.
- **D-04:** A combined `results/raman/sweeps/SWEEP_REPORT.md` that includes both fiber summaries + the multistart results in one document.

### Trigger Mechanism
- **D-05:** Post-hoc script `scripts/generate_sweep_reports.jl` that reads aggregate + per-point JLD2 files. Fully decoupled from sweep execution. Can be re-run any time.
- **D-06:** Script also generates a top-level summary figure: 2x1 grid of heatmaps (SMF-28 | HNLF) with quality annotations, reusing existing `plot_sweep_heatmap`.

### Per-Point Documentation
- **D-07:** Each per-point directory gets a `report.md` with: fiber name, L, P, J_before/after (linear + dB), quality label, convergence status, iterations, photon drift, N_sol, Nt, time_window. Machine-parseable YAML frontmatter + human-readable body.

### Claude's Discretion
- Figure size, colormap, font sizing for the report card panels
- Whether to include a thumbnail index HTML file (probably not — markdown is sufficient)
- Exact text layout in the metrics panel

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Infrastructure
- `scripts/visualization.jl` — All plotting functions; reuse `plot_phase_diagnostic`, `plot_convergence`, spectral comparison utilities
- `scripts/run_sweep.jl` — Sweep runner; defines per-point JLD2 structure and aggregate save format
- `scripts/raman_optimization.jl` §489-525 — Per-point JLD2 schema (phi_opt, uomega0, band_mask, convergence_history, etc.)
- `scripts/common.jl` — FIBER_PRESETS, setup_raman_problem, spectral_band_cost

### Data Format
- `results/raman/sweeps/sweep_results_smf28.jld2` — Aggregate grid data (J_after_grid, N_sol_grid, converged_grid, etc.)
- `results/raman/sweeps/<fiber>/L*_P*/opt_result.jld2` — Per-point full data

### Prior Art (non-sweep runs)
- `results/raman/smf28/L1m_P005W/` — Example of full per-run output (7 files including 6 PNGs)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `plot_phase_diagnostic()` — 3-panel phase view (wrapped, unwrapped, group delay). Can extract individual panel logic.
- `plot_convergence()` — J vs iteration plot. Works with convergence_history from JLD2.
- `_apply_dB_mask()`, `_spectral_signal_xlim()` — Spectral plotting utilities.
- `compute_group_delay()`, `compute_gdd()` — Phase analysis functions.
- `plot_sweep_heatmap()` — Already exists for aggregate view.
- `MultiModeNoise.lin_to_dB()` — dB conversion.

### Established Patterns
- PyPlot with `Agg` backend, `savefig` at 300 DPI
- Include guards for script files
- JLD2 for structured data persistence
- `@sprintf` for formatted logging

### Integration Points
- Per-point directories already exist from sweep: `results/raman/sweeps/<fiber>/L*_P*/`
- JLD2 aggregate files exist with grid indices mapping to per-point directories
- `FIBER_PRESETS` in common.jl for fiber parameter lookup

</code_context>

<specifics>
## Specific Ideas

- Report card should be compact enough to print 4 per page for lab meeting handouts
- Quality labels (excellent/good/acceptable/poor) from the sweep reporting code should be consistent
- Professor specifically wants all three phase views (memory: project_prof_phase.md)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-sweep-point-reporting*
*Context gathered: 2026-03-31*
