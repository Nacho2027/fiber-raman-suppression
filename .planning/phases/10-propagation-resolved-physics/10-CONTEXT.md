# Phase 10: Propagation-Resolved Physics & Phase Ablation - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning
**Mode:** Auto-selected (all gray areas, recommended defaults)

<domain>
## Phase Boundary

Understand the 84% of Raman suppression that Phase 9 attributed to "configuration-specific nonlinear interference" by running NEW forward propagations with z-resolved diagnostics and conducting spectral phase ablation experiments. This phase runs simulations and analyzes results — it does NOT modify the optimizer or core solver code (except to configure zsave).

Key question from Phase 9: "Further analysis of the optimizer's strategy requires propagation-resolved diagnostics (tracking Raman energy buildup along z), which was deferred from this phase (H5)."

</domain>

<decisions>
## Implementation Decisions

### Z-Resolved Propagation
- **D-01:** Use 50 z-save points per fiber (LinRange(0, L, 50)). Good balance of z-resolution vs memory. For a 5m fiber this gives 10cm resolution — sufficient to track Raman energy buildup.
- **D-02:** Compute Raman band energy E_band(z) / E_total(z) at each z-point using the existing `band_mask` and `spectral_band_cost` pattern. This gives a direct z-resolved suppression curve.
- **D-03:** Also compute the full spectral evolution along z (for heatmap visualization), not just the scalar Raman fraction.

### Configuration Selection
- **D-04:** Re-propagate 6 representative configurations (3 SMF-28 + 3 HNLF) spanning the N_sol range: low N (~1.5), medium N (~3), high N (~5-6). These should include the best and worst suppression points from Phase 9.
- **D-05:** Full phase ablation experiments on 2 canonical configurations: one SMF-28 (N≈2.6, the multi-start config) and one HNLF (best suppression point).
- **D-06:** Each configuration propagated twice: once with flat phase (unshaped) and once with phi_opt (shaped), to get both baselines.

### Phase Ablation Strategy
- **D-07:** Frequency-band zeroing: divide the signal band into 8-10 equal-width sub-bands, zero out phi_opt in one sub-band at a time, propagate, and measure suppression loss. This directly answers "which spectral regions of phi_opt matter most?"
- **D-08:** Use smooth windowing (super-Gaussian roll-off) at band edges to avoid Gibbs ringing artifacts when zeroing bands.
- **D-09:** Also test cumulative ablation: zero out bands from the edges inward, tracking suppression degradation as phi_opt is progressively truncated to narrower bandwidth.

### Perturbation Studies
- **D-10:** Global scaling: multiply phi_opt by factors [0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0] and propagate. Identifies the 3 dB robustness envelope.
- **D-11:** Spectral shift: translate phi_opt by ±1, ±2, ±5 THz on the frequency grid and propagate. Tests whether the phase is tuned to specific spectral features.
- **D-12:** No noise-addition perturbations — keep the phase deterministic to isolate mechanisms.

### New Simulation Scope
- **D-13:** Re-propagate existing phi_opt with z-saves only. No new optimization runs in this phase. The goal is understanding, not discovering new solutions.
- **D-14:** Save all z-resolved data to JLD2 files in `results/raman/phase10/` for future analysis.
- **D-15:** All new figures go to `results/images/` with prefix `physics_10_XX_`.

### Claude's Discretion
- Choice of which 6 specific (L,P) configurations from the sweep to use as representatives
- Figure layout and panel arrangement for z-resolved plots
- Whether to add a spectrogram-style (time-frequency) analysis at selected z-points
- Whether to compute z-resolved group delay evolution
- Statistical presentation of ablation results (bar charts vs heatmaps vs tables)

### Folded Todos
None.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 9 Findings (PRIMARY)
- `results/raman/PHASE9_FINDINGS.md` — Central findings document; H5 deferred hypothesis is the motivation for this phase
- `.planning/phases/09-physics-of-raman-suppression/09-RESEARCH.md` — Research with 7 hypotheses; H5 (propagation diagnostics) was deferred
- `.planning/phases/09-physics-of-raman-suppression/09-CONTEXT.md` — Phase 9 decisions (paper-quality figures, research-grounded)

### Existing Infrastructure
- `scripts/phase_analysis.jl` — Phase 9 analysis script (~1989 lines); data loading, polynomial decomposition, temporal analysis
- `scripts/common.jl` — Setup functions, band_mask, spectral_band_cost, fiber presets
- `scripts/visualization.jl` — Plotting functions including spectral/temporal evolution heatmaps
- `src/simulation/simulate_disp_mmf.jl` — Forward solver with zsave support (lines 181-196)

### Solver z-save mechanism
- `src/helpers/helpers.jl` — fiber dict construction, zsave field (lines 129, 192)
- `scripts/verification.jl` — Example of setting zsave and extracting z-resolved data (lines 112-122)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`fiber["zsave"]`** mechanism: Set to `LinRange(0, L, N)` before calling `solve_disp_mmf` and the solver automatically saves at those z-points. Returns `sol["uω_z"][Nz × Nt × M]` and `sol["ut_z"][Nz × Nt × M]`.
- **`spectral_band_cost(uωf, band_mask)`**: Computes E_band/E_total. Can be applied at each z-slice: `spectral_band_cost(uω_z[i, :, :], band_mask)`.
- **`setup_raman_problem()`**: Returns `(uω0, fiber, sim, band_mask, Δf, raman_threshold)` — complete problem setup. Just set `fiber["zsave"]` after calling this.
- **Phase 9 data loading pattern** in `phase_analysis.jl`: Walks sweep directories, loads JLD2, computes soliton numbers. Directly reusable.
- **`plot_spectral_evolution()`** and **`plot_temporal_evolution()`** in visualization.jl: Already plot [Nz × Nt] heatmaps. Can be reused for z-resolved diagnostics.

### Established Patterns
- Scripts use `PA_` prefix for phase_analysis constants; Phase 10 should use `PZ_` (propagation z-resolved) or `P10_` prefix
- Include guard pattern: `if !(@isdefined _SCRIPT_LOADED)`
- `if abspath(PROGRAM_FILE) == @__FILE__` guard for main execution block
- 300 DPI PNG output, Okabe-Ito colors, metadata annotations

### Integration Points
- Data loaded from `results/raman/sweeps/{smf28,hnlf}/L*_P*/opt_result.jld2`
- Multi-start data from `results/raman/sweeps/multistart/start_*/opt_result.jld2`
- New z-resolved data saved to `results/raman/phase10/`
- Figures saved to `results/images/physics_10_*.png`

</code_context>

<specifics>
## Specific Ideas

### From Phase 9 Findings
- The 84% "configuration-specific nonlinear interference" MUST be investigated via z-resolved data. Phase 9 could only analyze input/output — Phase 10 sees what happens INSIDE the fiber.
- Multi-start phases (mean correlation 0.109) achieved similar suppression via different mechanisms — z-resolved data should reveal whether these different phi_opt profiles create similar z-evolution or diverge then reconverge.
- N_sol > 2 vs N_sol <= 2 showed the best clustering — z-resolved data should show qualitatively different propagation dynamics in these two regimes.

### Key Physics Questions
1. At what z-position does Raman energy begin to grow for the unshaped pulse? Does the optimal phase delay this onset?
2. Is there a "critical z" beyond which Raman suppression breaks down even with optimal phase?
3. Do the ablation experiments reveal a small number of "critical frequencies" in phi_opt, or is suppression distributed across the full bandwidth?
4. How does the z-resolved spectral evolution differ between the two N_sol regimes?

</specifics>

<deferred>
## Deferred Ideas

- **Multimode (M>1) extension** — separate future phase, requires different solver configuration
- **Quantum noise on top of classical optimization** — requires adjoint noise analysis, separate phase
- **New optimization cost functions** (e.g., minimize Raman at specific z, not just fiber end) — would be interesting but is scope creep for this analysis phase
- **FROG/XFROG-style time-frequency analysis** — could add in future phase if z-resolved data warrants it

</deferred>

---

*Phase: 10-propagation-resolved-physics*
*Context gathered: 2026-04-02*
