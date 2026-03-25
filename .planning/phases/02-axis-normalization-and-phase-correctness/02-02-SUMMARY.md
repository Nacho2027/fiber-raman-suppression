---
phase: 02-axis-normalization-and-phase-correctness
plan: 02
subsystem: visualization
tags: [julia, pyplot, matplotlib, axis-normalization, global-p-ref, two-pass, before-after-comparison]

# Dependency graph
requires:
  - phase: 02-axis-normalization-and-phase-correctness
    plan: 01
    provides: "_spectral_signal_xlim helper, plot_phase_diagnostic with BUG-03 fix"
provides:
  - "plot_optimization_result_v2 with global P_ref and shared axes (two-pass architecture)"
  - "plot_amplitude_result_v2 with global P_ref and shared axes (two-pass architecture)"
  - "plot_spectral_evolution AXIS-02 auto-zoom (input spectrum as reference)"
  - "plot_spectrum_comparison AXIS-02 auto-zoom (union of input+output)"
  - "plot_spectrogram AXIS-02 auto-zoom (spectral marginal sum)"
affects:
  - "raman_optimization.jl output — opt.png now shows true dB improvement between columns"
  - "amplitude_optimization.jl output — amp_opt.png now shows true dB improvement"
  - "Any caller of plot_spectral_evolution, plot_spectrum_comparison, plot_spectrogram"

# Tech stack
tech_stack:
  added: []
  patterns:
    - "Two-pass Before/After comparison: simulate all columns first, compute global shared quantities, then render"
    - "_energy_window used instead of _auto_time_limits in amplitude comparison for dispersed-pulse robustness"
    - "spec_union = maximum(hcat(all_specs...), dims=2)[:] to get element-wise max across all spectra"

# Key files
key_files:
  created: []
  modified:
    - scripts/visualization.jl
    - scripts/test_visualization_smoke.jl
    - .planning/REQUIREMENTS.md

# Decisions
decisions:
  - "Use _energy_window (not _auto_time_limits) for temporal limits in both comparison functions — more robust for amplitude-shaped pulses that may be dispersed"
  - "plot_spectral_evolution auto-zooms to z=0 input spectrum, not the output — input is stable reference; output may over-expand the zoom window if strongly broadened"
  - "PHASE-01 confirmed complete (no code change needed) — group delay row was implemented before this plan"
  - "Keep P_ref = max(maximum(P_in), maximum(P_out)) in plot_spectrum_comparison (standalone function, single call-site, not a Before/After loop)"

# Metrics
metrics:
  duration_minutes: 8
  completed_date: "2026-03-25T02:58:33Z"
  tasks_completed: 2
  files_modified: 3
---

# Phase 02 Plan 02: Global P_ref and Shared-Axes Two-Pass Comparison Summary

**One-liner:** Two-pass Before/After comparison functions with global P_ref normalization, shared temporal xlim/ylim, and _spectral_signal_xlim auto-zoom replacing all fixed ±300/±500 nm offsets.

## What Was Built

Both optimization comparison functions (`plot_optimization_result_v2` and `plot_amplitude_result_v2`) were refactored from a single render loop into a three-pass architecture:

**Pass 1 — Simulate:** Iterate over `[(phi/A_before, "Before"), (phi/A_after, "After")]`, run `MultiModeNoise.solve_disp_mmf` for each, store results in `Vector{NamedTuple}` (`col_data`).

**Pass 2 — Compute shared quantities:**
- `P_ref_global`: maximum spectral power across ALL columns and input/output — ensures the dB offset between Before and After columns reflects the true optimization improvement (BUG-04 fix)
- `t_lo_shared` / `t_hi_shared`: union of `_energy_window` results across all columns — pulse compression is visible as narrowing rather than axis rescaling (AXIS-01 fix)
- `P_max_shared`: maximum peak power across all columns — shared ylim prevents power scale from hiding improvements
- `spec_xlim`: `_spectral_signal_xlim` applied to the element-wise maximum of all spectra (AXIS-02)

**Pass 3 — Render:** Loop over `enumerate(col_data)`, apply shared quantities to each column.

Additionally, three standalone spectral functions received AXIS-02 auto-zoom:
- `plot_spectral_evolution`: uses z=0 input spectrum as reference
- `plot_spectrum_comparison`: uses `max.(P_in, P_out)` union
- `plot_spectrogram`: uses spectral marginal `vec(sum(S, dims=2))` fftshifted

PHASE-01 was confirmed already implemented (group delay `τ(ω)` with correct title/ylabel was present before this plan) and marked complete in REQUIREMENTS.md.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Refactor plot_optimization_result_v2 two-pass | df5d080 | scripts/visualization.jl |
| 2 | Refactor plot_amplitude_result_v2 two-pass, AXIS-02 standalone funcs, PHASE-01 complete | 79c8b63 | scripts/visualization.jl, scripts/test_visualization_smoke.jl, .planning/REQUIREMENTS.md |

## Requirements Completed

| Requirement | Description | Status |
|-------------|-------------|--------|
| BUG-04 | Global P_ref across Before/After columns | Complete |
| AXIS-01 | Shared xlim and ylim for Before/After panels | Complete |
| AXIS-02 | Auto-zoom to signal-bearing region (all spectral plots) | Complete (extended from Plan 01) |
| PHASE-01 | Group delay τ(ω) as primary phase display in opt.png row 3 | Confirmed complete |

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Clarifications (not deviations)

**1. _energy_window instead of _auto_time_limits for plot_amplitude_result_v2**
- **Found during:** Task 2
- **Note:** Plan explicitly called for this switch ("Switch to `_energy_window` for consistency"). Implemented as specified.

**2. P_ref = max(maximum(P_in), maximum(P_out)) kept in plot_spectrum_comparison**
- **Found during:** Task 2
- **Note:** This is a standalone function (single call-site, not a Before/After loop). Its local `P_ref` correctly uses both input and output of the same simulation run. Not the BUG-04 pattern. Correctly left unchanged.

**3. PHASE-01 marked complete without code change**
- **Found during:** Task 2 research
- **Note:** The group delay row (row 3) with title "Group delay τ(ω)" and ylabel "Group delay [fs]" was already present in `plot_optimization_result_v2`. Marking complete in REQUIREMENTS.md only.

## Verification Results

```
julia scripts/test_visualization_smoke.jl → All 21 tests passed

grep -c "P_ref_global" scripts/visualization.jl → 8 (>= 2)
grep "P_ref = max(maximum(spec_in)" scripts/visualization.jl → no matches
grep -c "_spectral_signal_xlim" scripts/visualization.jl → 8 (>= 6)
grep "t_lo_shared" scripts/visualization.jl → matches in both comparison functions
grep "[x] **PHASE-01**" .planning/REQUIREMENTS.md → match found
grep "lambda0_nm - 400" scripts/visualization.jl → no matches
```

## Known Stubs

None — all spectral zoom, normalization, and axis-sharing patterns are fully wired.

## Self-Check: PASSED
