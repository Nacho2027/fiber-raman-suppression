---
phase: 03-structure-annotation-and-final-assembly
plan: 02
subsystem: optimization-scripts
tags: [metadata, annotation, evolution, merged-figure, raman, amplitude]
dependency_graph:
  requires: [03-01-SUMMARY.md]
  provides: [metadata threading in raman_optimization.jl, metadata threading in amplitude_optimization.jl, plot_merged_evolution call sites]
  affects: [scripts/raman_optimization.jl, scripts/amplitude_optimization.jl]
tech_stack:
  added: []
  patterns: [run_meta NamedTuple constructed from kwargs, fiber_name kwarg on both run functions]
key_files:
  modified:
    - scripts/raman_optimization.jl
    - scripts/amplitude_optimization.jl
decisions:
  - "run_meta NamedTuple uses get(kwargs, :key, default) pattern — matches setup_raman_problem/setup_amplitude_problem kwarg names exactly (λ0, P_cont, pulse_fwhm, L_fiber)"
  - "K-sweep call sites in amplitude_optimization.jl also receive fiber_name — future K-sweep runs will carry metadata annotations"
  - "fiber_evo deepcopy with LinRange zsave constructed in run functions before merged evolution call — avoids fiber dict mutation from optimization"
metrics:
  duration: 4 minutes
  completed_date: "2026-03-25"
  tasks_completed: 2
  files_modified: 2
---

# Phase 3 Plan 2: Metadata Threading and Merged Evolution Call Sites Summary

**One-liner:** Metadata NamedTuple construction and threading into all plotting calls in both optimization scripts, replacing the broken `plot_evolution_comparison` and the two-file evolution pattern with `plot_merged_evolution`.

## Completed Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Wire metadata and merged evolution in raman_optimization.jl | 0334460 | scripts/raman_optimization.jl |
| 2 | Wire metadata and merged evolution in amplitude_optimization.jl | 04baad6 | scripts/amplitude_optimization.jl |

## What Was Built

### Task 1: raman_optimization.jl (META-01, META-03, ORG-01, ORG-02)

Added `fiber_name="Custom"` keyword argument to `run_optimization`. After `setup_raman_problem`, constructs a `run_meta` NamedTuple by extracting `λ0`, `P_cont`, `pulse_fwhm`, `L_fiber` from `kwargs` (with defaults matching `setup_raman_problem` defaults). The NamedTuple fields match the `_add_metadata_block!` interface: `fiber_name`, `L_m`, `P_cont_W`, `lambda0_nm`, `fwhm_fs`.

Passes `metadata=run_meta` to all three plotting calls:
- `plot_optimization_result_v2` — main 3x2 comparison panel
- `plot_phase_diagnostic` — wrapped/unwrapped phase + GDD + group delay
- `plot_merged_evolution` — the new merged 2x2 evolution figure

Replaced the two separate `propagate_and_plot_evolution(..., save_path=..._evolution_unshaped.png)` and `propagate_and_plot_evolution(..., save_path=..._evolution_optimized.png)` calls with:
1. Two `propagate_and_plot_evolution` calls without save (returns `sol` objects, closes intermediate figures)
2. One `plot_merged_evolution` call saving to `$(save_prefix)_evolution.png`

Output per run is now exactly 3 files: `opt.png`, `opt_phase.png`, `opt_evolution.png`.

Updated all 5 run call sites: Runs 1, 2, 5 → `fiber_name="SMF-28"`, Runs 3, 4 → `fiber_name="HNLF"`.

### Task 2: amplitude_optimization.jl (META-01, ORG-01, ORG-02)

Applied the same pattern to both `run_amplitude_optimization_lowdim` and `run_amplitude_optimization`.

Added `fiber_name="Custom"` to both function signatures. Constructed `run_meta` NamedTuple in each. Passed `metadata=run_meta` to `plot_amplitude_result_v2` and `plot_merged_evolution` in both functions (4 metadata-annotated plotting calls total).

Replaced the broken `plot_evolution_comparison` calls (function does not exist in visualization.jl) in both run functions with the same `propagate_and_plot_evolution` + `plot_merged_evolution` pattern.

Updated all call sites in the main execution block: Runs 1, 2, K-sweep → `fiber_name="SMF-28"`, Run 3 (lowdim), Run 4 (lowdim) → `fiber_name="SMF-28"`.

## Verification Results

```
grep "evolution_unshaped|evolution_optimized" raman_optimization.jl  => 0 (PASS)
grep "plot_evolution_comparison" amplitude_optimization.jl           => 0 (PASS)
grep "plot_merged_evolution" raman+amplitude combined                 => 3 total (PASS)
grep "metadata=run_meta" raman+amplitude combined                    => 7 total (PASS)
grep "fiber_name=" raman+amplitude combined                          => 13 total (PASS)
grep -rn "evolution_unshaped|evolution_optimized|plot_evolution_comparison" scripts/ => 0 (PASS)
```

## Deviations from Plan

### Auto-fixed Issues

None. Plan executed exactly as written.

### Prerequisite Deviation

Plan 01 commits (`fe726c9`, `53e0d25`) were not present in the worktree branch `worktree-agent-a464310c`. The visualization.jl and test_visualization_smoke.jl from the main repo's `main` branch (post-Plan 01 state) were copied into the worktree and committed (`74e53cd`) as a prerequisite before executing Plan 02 tasks. This is not a deviation from Plan 02's scope — it was a worktree branch isolation issue from the parallel execution setup.

## Known Stubs

None. The `run_meta` NamedTuple is constructed from actual kwargs values at every call site, not from hardcoded placeholders.

## Self-Check: PASSED

Files exist:
- scripts/raman_optimization.jl: FOUND
- scripts/amplitude_optimization.jl: FOUND
- .planning/phases/03-structure-annotation-and-final-assembly/03-02-SUMMARY.md: FOUND (this file)

Commits exist:
- 0334460: FOUND (feat(03-02): wire metadata and merged evolution in raman_optimization.jl)
- 04baad6: FOUND (feat(03-02): wire metadata and merged evolution in amplitude_optimization.jl)
