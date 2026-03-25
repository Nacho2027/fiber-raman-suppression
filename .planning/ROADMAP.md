# Roadmap: SMF Gain-Noise Visualization Overhaul

## Overview

Three phases refactor `scripts/visualization.jl` bottom-up by dependency: first eliminate the confirmed bugs that make current plots scientifically unreadable (wrong colormap, wrong Raman shading, color literal inconsistency); then fix axis, normalization, and phase representation so before/after panels are actually comparable; then extract shared panel builders, add metadata annotation, and assemble the final merged evolution figure. Every phase delivers plots that are observably better than the previous phase with no step requiring a later step to make sense.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Stop Actively Misleading** - Fix confirmed rendering bugs: jet colormap, Raman axvspan bounds, color literal inconsistencies, rcParams mutation (completed 2026-03-25)
- [ ] **Phase 2: Axis, Normalization, and Phase Correctness** - Shared axis limits, global dB normalization, correct phase representation with masking-before-unwrapping
- [ ] **Phase 3: Structure, Annotation, and Final Assembly** - Panel builder extraction, metadata annotation on every figure, merged 4-panel evolution figure

## Phase Details

### Phase 1: Stop Actively Misleading
**Goal**: Plots no longer contain confirmed rendering bugs that actively mislead physics interpretation
**Depends on**: Nothing (first phase)
**Requirements**: BUG-01, BUG-02, STYLE-01, STYLE-02, STYLE-03, AXIS-03
**Success Criteria** (what must be TRUE):
  1. Evolution heatmaps display in inferno colormap — no yellow/cyan banding from jet that creates false ~3 dB perceptual features
  2. Raman band shading on spectral plots covers only the ~13 THz gain band (~1600-1700 nm for 1550 nm center), not the entire red-shifted half of the spectrum
  3. All input curves render in #0072B2 (blue) and all output curves in #D55E00 (vermillion) — no "b--", "darkgreen", or "r-" string literals anywhere
  4. Raman shading is visually subtle and does not obscure the spectral curves underneath
  5. rcParams is mutated via PyPlot.PyDict and savefig.bbox is set to "tight" — no silent rcParams failures in batch runs
**Plans**: 2 plans

Plans:
- [ ] 01-PLAN-01.md — Fix rcParams (PyDict pattern + savefig.bbox), replace jet with inferno in all 4 heatmap functions, disable grid on pcolormesh axes
- [ ] 01-PLAN-02.md — Fix Raman axvspan bounds (two-sided frequency window), standardize all color literals to COLOR_INPUT / COLOR_OUTPUT

### Phase 2: Axis, Normalization, and Phase Correctness
**Goal**: Before/after comparison panels and phase diagnostics communicate the actual optimization result faithfully
**Depends on**: Phase 1
**Requirements**: BUG-03, BUG-04, AXIS-01, AXIS-02, PHASE-01, PHASE-02, PHASE-03, PHASE-04
**Success Criteria** (what must be TRUE):
  1. Before and after temporal panels share identical x-axis range — pulse compression is visible as narrowing within the same window, not as an axis rescaling artifact
  2. Before and after spectral panels reference the same global P_ref — the dB offset between columns reflects the actual optimization improvement J
  3. Spectral plots auto-zoom to the signal-bearing region — noise floor is not the dominant feature of the wavelength axis
  4. Phase diagnostic (opt_phase.png) shows group delay as the primary phase display, with wrapped phase, unwrapped phase, GDD, and instantaneous frequency all masked to the signal region before any derivative computation
  5. GDD panel y-axis is clipped to the 2nd-98th percentile of valid samples — no +/-10^6 fs^2 spikes that flatten the physically meaningful range
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md — Add _spectral_signal_xlim helper, synthetic mask-before-unwrap test, rewrite plot_phase_diagnostic to 3x2 layout with mask-before-unwrap and all 5 phase views
- [x] 02-02-PLAN.md — Refactor plot_optimization_result_v2 and plot_amplitude_result_v2 to two-pass with global P_ref and shared axes, apply auto-zoom to standalone functions, mark PHASE-01 complete

### Phase 3: Structure, Annotation, and Final Assembly
**Goal**: Every saved figure is self-documenting and the two evolution PNGs are replaced by one merged comparison figure
**Depends on**: Phase 2
**Requirements**: META-01, META-02, META-03, ORG-01, ORG-02
**Success Criteria** (what must be TRUE):
  1. Every saved figure (opt.png, opt_phase.png, opt_evolution.png) contains a visible annotation block with fiber type, length L, peak power P0, center wavelength lambda0, and pulse FWHM — figure is identifiable without the filename
  2. Optimization cost J (before and after, in dB) is annotated directly on opt.png
  3. Each run produces exactly 3 output files: opt.png, opt_phase.png, opt_evolution.png — the two separate evolution PNGs no longer exist
  4. opt_evolution.png is a single 2x2 figure showing temporal and spectral evolution for both optimized and unshaped propagation side by side with a shared colorbar
**Plans**: 2 plans

Plans:
- [ ] 03-01-PLAN.md — Add _add_metadata_block! helper, expand J annotation to show before/after/delta, create plot_merged_evolution 2x2 function, add metadata= kwarg to 3 top-level plotters
- [ ] 03-02-PLAN.md — Wire metadata construction and plot_merged_evolution into run_optimization (raman) and both run functions (amplitude), enforce 3-file output naming

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Stop Actively Misleading | 0/2 | Complete    | 2026-03-25 |
| 2. Axis, Normalization, and Phase Correctness | 0/2 | In progress | - |
| 3. Structure, Annotation, and Final Assembly | 0/2 | Not started | - |
