# S02: Axis Normalization And Phase Correctness

**Goal:** Rewrite the phase diagnostic figure and add spectral auto-zoom infrastructure.
**Demo:** Rewrite the phase diagnostic figure and add spectral auto-zoom infrastructure.

## Must-Haves


## Tasks

- [x] **T01: 02-axis-normalization-and-phase-correctness 01** `est:17min`
  - Rewrite the phase diagnostic figure and add spectral auto-zoom infrastructure.

Purpose: Fix the phase-before-unwrap bug (BUG-03) that contaminates group delay/GDD with noise floor phase, expand the diagnostic from 2x2 to 3x2 adding wrapped phase (PHASE-02, PHASE-04), clip GDD to percentiles (PHASE-03), and add the `_spectral_signal_xlim` helper (AXIS-02) used by both this plan and Plan 02.

Output: Rewritten `plot_phase_diagnostic` function, new `_spectral_signal_xlim` helper, synthetic test validating mask-before-unwrap correctness.
- [x] **T02: 02-axis-normalization-and-phase-correctness 02**
  - Restructure both optimization comparison functions to use two-pass rendering with global normalization and shared axes.

Purpose: Fix the per-column P_ref normalization (BUG-04) that hides optimization improvements in Before/After dB comparison, enforce shared temporal xlim/ylim (AXIS-01) so pulse compression is visible as narrowing rather than axis rescaling, apply spectral auto-zoom (AXIS-02) to the remaining comparison function call sites, and confirm PHASE-01 is already satisfied.

Output: Refactored `plot_optimization_result_v2` and `plot_amplitude_result_v2` with two-pass architecture (simulate -> compute shared quantities -> render), updated tests, PHASE-01 marked complete in REQUIREMENTS.md.

## Files Likely Touched

- `scripts/visualization.jl`
- `scripts/test_visualization_smoke.jl`
- `scripts/visualization.jl`
- `scripts/test_visualization_smoke.jl`
- `.planning/REQUIREMENTS.md`
