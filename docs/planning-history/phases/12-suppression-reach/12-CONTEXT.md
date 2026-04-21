# Phase 12: Suppression Reach & Long-Fiber Behavior - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning
**Mode:** Auto-selected (all gray areas, recommended defaults)

<domain>
## Phase Boundary

Characterize the finite reach of spectral phase Raman suppression. Propagate short-fiber-optimized phases through much longer fibers (10m, 30m), map how the suppression horizon scales with fiber parameters, and explore whether segmented optimization can extend the reach. This phase corrects the overclaimed "prevents Raman onset" narrative from earlier phases.

Key user insight: "There's no way the underlying physics allows for no Raman to show up ever on a 30 meter fiber if all we did was optimize and eliminate it for the first meter."

</domain>

<decisions>
## Implementation Decisions

### Long-Fiber Propagation
- **D-01:** Propagate existing phi_opt from L=0.5m and L=2m optimizations through L=10m and L=30m fibers. Use 100 z-save points (not 50) for finer resolution over longer distances.
- **D-02:** Test both SMF-28 (P=0.2W, N≈2.6) and HNLF (P=0.01W, N≈3.6) — the two canonical configs from Phase 10.
- **D-03:** Always compare shaped vs flat phase. The key question: at 10x-60x the optimization length, does phi_opt still give ANY benefit over no shaping at all?
- **D-04:** Use the multi-start phi_opt profiles (the best-performing one, start with highest suppression) for long-fiber tests.

### Suppression Horizon Mapping
- **D-05:** Define suppression horizon L_XdB as the fiber length at which J(z) first crosses X dB. Map L_50dB and L_30dB (two thresholds) vs power P for both fiber types.
- **D-06:** Sweep at least 4 power levels per fiber type. For SMF-28: P = 0.05, 0.1, 0.2, 0.5 W. For HNLF: P = 0.005, 0.01, 0.02, 0.05 W.
- **D-07:** For each sweep point, re-optimize at that (L_target, P) to get the best possible phi_opt, then propagate with z-saves through 2x L_target to see the decay beyond the optimization point.
- **D-08:** Report scaling: does L_50dB scale as 1/P, 1/P^2, or something else? Compare with analytical Raman critical power scaling (Smith 1972).

### Reach Extension
- **D-09:** Test segmented optimization: optimize phi_opt for L=2m, propagate to z=2m, take the output field, re-optimize the spectral phase at that point, propagate another 2m, repeat. This tests whether "refreshing" the phase at intermediate points can extend suppression indefinitely.
- **D-10:** Use 3-4 segments (total 6-8m) to demonstrate the concept. If it works, the implication is that a multi-stage pulse shaper could maintain suppression over arbitrary lengths.
- **D-11:** Compare segmented (re-optimized at each stage) vs single-shot (optimized once for full length) vs flat phase (no optimization).

### Output & Corrections
- **D-12:** All new figures use prefix `physics_12_XX_`. Save to `results/images/`.
- **D-13:** All new JLD2 data goes to `results/raman/phase12/`.
- **D-14:** Update the synthesis document `CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md` with a new section on finite reach and long-fiber behavior. The corrected narrative must be clear: spectral phase shaping has a finite suppression horizon, not unlimited reach.
- **D-15:** Script prefix: `PR_` (propagation reach) or `P12_`.

### Claude's Discretion
- Whether to also test intermediate lengths (5m, 15m) or just 10m and 30m
- Figure layout for the horizon mapping plots
- Whether segmented optimization uses the same Nt or adapts per segment
- How to handle time window expansion for 30m propagation (SPM broadening at long L)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 11 Findings (PRIMARY)
- `results/raman/CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md` — Synthesis document (corrected); suppression horizon L_50dB ≈ 3.33m baseline
- `results/raman/PHASE10_ZRESOLVED_FINDINGS.md` — Z-resolved findings, 5m breakdown at z=0.20m
- `results/raman/PHASE10_ABLATION_FINDINGS.md` — Ablation results confirming fragility

### Existing Infrastructure
- `scripts/propagation_z_resolved.jl` — Phase 10 z-resolved propagation (reuse `pz_load_and_repropagate` pattern)
- `scripts/physics_completion.jl` — Phase 11 analysis (multi-start data loading pattern)
- `scripts/common.jl` — `setup_raman_problem()`, `spectral_band_cost()`, fiber presets
- `scripts/raman_optimization.jl` — `optimize_spectral_phase()` for segmented re-optimization
- `src/simulation/simulate_disp_mmf.jl` — Forward solver with zsave (lines 181-197)

### Data Sources
- `results/raman/sweeps/smf28/L0.5m_P0.2W/opt_result.jld2` — Short-fiber phi_opt
- `results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2` — Medium-fiber phi_opt (if exists)
- `results/raman/sweeps/multistart/start_*/opt_result.jld2` — Multi-start phi_opt profiles
- `results/raman/phase10/` and `results/raman/phase11/` — Prior z-resolved data

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`pz_load_and_repropagate()`** — loads JLD2, sets zsave, propagates. Needs modification for L >> original L (time window must expand).
- **`setup_raman_problem()`** — returns full problem setup. For long fibers, auto-sizing will expand time_window and Nt.
- **`optimize_spectral_phase()`** — needed for segmented optimization (D-09). Takes phi_init, runs L-BFGS.
- **`spectral_band_cost()`** — compute J at any z-slice.

### Key Challenge: Long-Fiber Time Windows
- `recommended_time_window()` auto-sizes based on dispersive walk-off + SPM broadening
- At L=30m, the time window will be much larger than at L=0.5m, requiring larger Nt
- The phi_opt was optimized at a specific Nt — applying it to a larger grid requires interpolation or zero-padding
- This grid mismatch is a critical implementation detail

### Established Patterns
- Script prefix per file: `PR_` for this phase
- Include guard, `@__FILE__` guard, `deepcopy(fiber)` before mutation
- 300 DPI PNG, Okabe-Ito colors, metadata annotations
- `beta_order=3` always with fiber presets

</code_context>

<specifics>
## Specific Ideas

### From User Discussion
- The user specifically wants to see what happens at 30m — far beyond any optimization horizon. Does the shaped pulse still look different from flat phase at that distance, or does it converge to the same Raman-dominated state?
- The user's physical intuition is correct: single-pass input shaping has a finite reach. The question is how that reach scales and whether segmented optimization can overcome it.

### Physics Questions
1. At L=30m (60x the 0.5m optimization length), is J_shaped still lower than J_flat? By how much?
2. Does the suppression benefit decay exponentially, linearly, or as a power law with distance?
3. Can segmented optimization (re-shaping at intermediate points) maintain deep suppression indefinitely?
4. How does the horizon scale with power? If L_50dB ∝ 1/P, that's consistent with a nonlinear phase accumulation limit.

</specifics>

<deferred>
## Deferred Ideas

- Multimode (M>1) extension — next milestone
- Quantum noise on top of classical optimization — next milestone
- Experimental pulse shaper design based on suppression horizon — future work
- Adaptive/feedback optimization during propagation — future work (requires different experimental setup)

</deferred>

---

*Phase: 12-suppression-reach*
*Context gathered: 2026-04-04*
