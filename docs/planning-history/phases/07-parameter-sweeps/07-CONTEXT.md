# Phase 7: Parameter Sweeps - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Systematically explore the L×P parameter space with optimization sweeps for both fiber types, fix the power-blind time window function, validate every sweep point with photon number drift, produce J_final heatmaps, and quantify multi-start robustness. Does NOT modify the optimizer algorithm itself, add new fiber types, or change the cost function.

</domain>

<decisions>
## Implementation Decisions

### Time Window Fix (CRITICAL PREREQUISITE)
- **D-01:** Both: fix `recommended_time_window()` with a power-aware SPM broadening estimate AND validate every sweep point with photon number drift <5%. Belt and suspenders.
  - The function in `scripts/common.jl` currently only uses `beta2 * L * Δω_raman` (linear walk-off). Add an SPM broadening term: SPM bandwidth ≈ γ × P_peak × L, convert to temporal broadening via β₂, add to total window estimate.
  - Every sweep point gets a post-run photon number check. Points with >5% drift are flagged as "window-limited" in the results, not treated as valid suppression measurements.
  - Phase 4 evidence: `results/raman/validation/verification_20260325_173537.md` shows 2.7-49% drift across existing configs.

### Sweep Grid Design
- **D-02:** Claude's discretion on grid design. Recommended approach:
  - Both SMF-28 and HNLF fiber types.
  - Grid should span from low-N (easy, mildly nonlinear) to high-N (hard, strongly nonlinear) regimes.
  - Include the existing 5 production configs as grid points for continuity.
  - Suggested: 4-5 L values × 4-5 P values per fiber type, ~20-25 points per fiber, ~40-50 total.
  - Use the fixed `recommended_time_window()` to size each point's time window adaptively.
  - No time limit on compute.

### Compute Budget
- **D-03:** No time limit. Run the full grid even if it takes 1-2 hours. Results are worth the wait. Runs can execute sequentially — no parallelization needed within the sweep (single-threaded Julia).

### Multi-Start Design
- **D-04:** Claude's discretion. Recommended:
  - 10 random starts on SMF-28 L=2m P=0.30W (N=3.1, didn't converge in Phase 6 at 50 iterations — interesting landscape).
  - Initial phases: small random Gaussian φ₀ ~ N(0, σ²) with σ ∈ {0.1, 0.5, 1.0} to explore different regions of phase space.
  - Report: distribution of J_final values, convergence iteration counts, and whether all starts converge to the same basin.

### Claude's Discretion
- Exact L and P grid values (within the "span low-N to high-N" constraint)
- Whether to increase max_iter beyond 50 for sweep points (Phase 6 showed most runs hit max_iter)
- Heatmap visualization details (colormap, axis labels, convergence tagging markers)
- Whether to save full JLD2 per sweep point or just scalars in an aggregate file
- Multi-start config selection and random seed strategy
- Script organization (single run_sweep.jl or split)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Critical Prerequisite
- `scripts/common.jl` (line 182-191) — `recommended_time_window()` function that must be fixed. Currently: `walk_off_ps = beta2 * L_fiber * Δω_raman * 1e12`. Needs SPM broadening term.
- `results/raman/validation/verification_20260325_173537.md` — Quantitative photon number drift evidence (2.7-49%) motivating the fix.

### Sweep Infrastructure
- `scripts/raman_optimization.jl` — `run_optimization()` with JLD2 save (Phase 5), `optimize_spectral_phase()` with `store_trace=true`
- `scripts/common.jl` — `FIBER_PRESETS`, `setup_raman_problem`, `spectral_band_cost`, `check_boundary_conditions`
- `scripts/run_comparison.jl` — Pattern for running multiple configs and loading results. Phase 7 sweep follows similar structure.
- `scripts/verification.jl` — Photon number computation pattern (for per-point drift validation)

### Visualization
- `scripts/visualization.jl` — Existing plotting infrastructure (300 DPI, inferno colormap, COLORS_5_RUNS)
- Phase 6.1 findings — Higher N → worse suppression, all phase structure in signal region

### Research
- `.planning/research/FEATURES.md` — Parameter sweep heatmap specification
- `.planning/research/PITFALLS.md` — Dict mutation in sweep loops, grid mismatch, convergence tagging

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `run_optimization()` — already saves JLD2 + updates manifest. Sweep can call this directly per grid point.
- `FIBER_PRESETS` — named tuples with (gamma, betas) for SMF28, HNLF variants.
- `compute_soliton_number()` — from visualization.jl, can annotate heatmap with N contours.
- `Optim.converged(result)` — boolean convergence flag already saved in JLD2.

### Established Patterns
- `deepcopy(fiber)` before mutating — critical for sweep loops to avoid Dict cross-contamination.
- `RC_` prefix for fiber constants in scripts (prevents Julia const redefinition).
- Results to `results/raman/sweeps/` directory (new, per ROADMAP success criteria).
- Manifest pattern from Phase 5 — append-safe JSON update.

### Integration Points
- New script `scripts/run_sweep.jl`
- Fix `recommended_time_window()` in `scripts/common.jl` (existing function, modify in place)
- Output heatmaps to `results/images/`
- Aggregate sweep results to `results/raman/sweeps/sweep_results.jld2`
- Per-point JLD2 to `results/raman/sweeps/{fiber}_{L}m_{P}W/`

</code_context>

<specifics>
## Specific Ideas

- Photon number drift check per point: compute N_ph_in and N_ph_out from the forward propagation result, flag if drift > 5%. Use the same formula as verification.jl (abs.(sim["ωs"]) for absolute frequency).
- Heatmap should use inferno colormap (consistent with project convention). Non-converged points marked with a distinct hatching or "X" overlay.
- SPM broadening estimate for time window: Δω_SPM ≈ γ × P_peak × L_eff (where L_eff = (1-exp(-α×L))/α ≈ L for low-loss fiber). Convert to temporal broadening: Δt_SPM ≈ |β₂| × L × Δω_SPM. Add to walk-off estimate.
- Consider logging N (soliton number) for each sweep point — enables overlaying N contour lines on the L×P heatmap for physical interpretation.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 07-parameter-sweeps*
*Context gathered: 2026-03-26*
