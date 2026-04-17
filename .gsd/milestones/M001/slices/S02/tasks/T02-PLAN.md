# T02: 02-axis-normalization-and-phase-correctness 02

**Slice:** S02 — **Milestone:** M001

## Description

Restructure both optimization comparison functions to use two-pass rendering with global normalization and shared axes.

Purpose: Fix the per-column P_ref normalization (BUG-04) that hides optimization improvements in Before/After dB comparison, enforce shared temporal xlim/ylim (AXIS-01) so pulse compression is visible as narrowing rather than axis rescaling, apply spectral auto-zoom (AXIS-02) to the remaining comparison function call sites, and confirm PHASE-01 is already satisfied.

Output: Refactored `plot_optimization_result_v2` and `plot_amplitude_result_v2` with two-pass architecture (simulate -> compute shared quantities -> render), updated tests, PHASE-01 marked complete in REQUIREMENTS.md.

## Must-Haves

- [ ] "Before and After spectral panels reference the same global P_ref so dB offset reflects actual optimization improvement"
- [ ] "Before and After temporal panels share identical x-axis range so pulse compression is visible as narrowing, not axis rescaling"
- [ ] "Before and After temporal panels share identical y-axis range so peak power difference is visible"
- [ ] "Spectral panels in comparison figures auto-zoom to signal-bearing region"
- [ ] "Group delay is confirmed as primary phase display in opt.png row 3 (PHASE-01 already implemented)"

## Files

- `scripts/visualization.jl`
- `scripts/test_visualization_smoke.jl`
- `.planning/REQUIREMENTS.md`
