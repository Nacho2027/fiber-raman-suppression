# T01: 02-axis-normalization-and-phase-correctness 01

**Slice:** S02 — **Milestone:** M001

## Description

Rewrite the phase diagnostic figure and add spectral auto-zoom infrastructure.

Purpose: Fix the phase-before-unwrap bug (BUG-03) that contaminates group delay/GDD with noise floor phase, expand the diagnostic from 2x2 to 3x2 adding wrapped phase (PHASE-02, PHASE-04), clip GDD to percentiles (PHASE-03), and add the `_spectral_signal_xlim` helper (AXIS-02) used by both this plan and Plan 02.

Output: Rewritten `plot_phase_diagnostic` function, new `_spectral_signal_xlim` helper, synthetic test validating mask-before-unwrap correctness.

## Must-Haves

- [ ] "Phase diagnostic shows 5 panels: wrapped phase, unwrapped phase, group delay, GDD, instantaneous frequency"
- [ ] "Wrapped phase panel has pi-labeled y-ticks (0, pi/2, pi, 3pi/2, 2pi)"
- [ ] "GDD panel y-axis is clipped to 2nd-98th percentile of valid samples, not dominated by edge spikes"
- [ ] "Phase unwrapping operates on pre-masked (zeroed noise floor) phase array, not full noisy array"
- [ ] "Spectral panels in phase diagnostic auto-zoom to signal-bearing region, not fixed +/-300/+500 nm offset"
- [ ] "Synthetic mask-before-unwrap test passes, recovering known GDD to within 1%"

## Files

- `scripts/visualization.jl`
- `scripts/test_visualization_smoke.jl`
