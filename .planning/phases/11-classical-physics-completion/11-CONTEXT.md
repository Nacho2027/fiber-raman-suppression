# Phase 11: Classical Physics Completion - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning
**Mode:** Auto-selected (all gray areas, recommended defaults)

<domain>
## Phase Boundary

Complete the classical Raman suppression physics story by testing Phase 10's hypotheses, analyzing multi-start z-dynamics, identifying spectral divergence points, explaining the long-fiber degradation, and producing a synthesis document. This phase runs NEW simulations (multi-start z-propagations) and performs analysis. No optimizer modifications.

Phase 9 answered: "universal vs arbitrary" → structured but complex, configuration-specific.
Phase 10 answered: "what happens inside the fiber" → suppression prevents Raman onset throughout z; fragile to perturbations.
Phase 11 answers: "do different solutions work the same way" and "can we close all remaining questions."

</domain>

<decisions>
## Implementation Decisions

### Multi-Start Z-Dynamics
- **D-01:** Re-propagate all 10 multi-start phi_opt profiles (SMF-28 L=2m P=0.20W, N=2.6) with 50 z-save points each. This directly tests whether structurally different solutions (mean correlation 0.109 from Phase 9) create similar or divergent J(z) evolution.
- **D-02:** Also propagate each multi-start with flat phase (unshaped) as baseline — though these should all be identical since the fiber/pulse params are the same, it validates consistency.
- **D-03:** Cluster the 10 J(z) trajectories and compare with the phi_opt correlation matrix from Phase 9 — do solutions that are structurally similar in phase space also have similar z-dynamics?

### Spectral Divergence Analysis
- **D-04:** For each of the 6 Phase 10 configs, compute the z-resolved spectral difference between shaped and unshaped: D(z,f) = |S_shaped(z,f) - S_unshaped(z,f)| in dB. Find the z-position where D first exceeds 3 dB at any frequency.
- **D-05:** Produce spectral difference heatmaps (z vs frequency, colored by dB difference) for the 6 configs. These show exactly where and at what frequency the optimizer's effect first becomes visible.

### Phase 10 Hypothesis Testing
- **D-06:** H1 (spectrally distributed suppression): Compare critical band maps between SMF-28 and HNLF from Phase 10 data — already answered but formalize the verdict.
- **D-07:** H2 (sub-THz spectral features): Use Phase 10 shift sensitivity data to quantify the characteristic spectral scale. Compare with Raman gain bandwidth (13.2 THz) and pulse bandwidth.
- **D-08:** H3 (amplitude-sensitive nonlinear interference): Use Phase 10 scaling data. Verdict is clear (confirmed) but produce a figure comparing scaling curves with a CPA-like model prediction.
- **D-09:** H4 (SMF-28 vs HNLF spectral strategies): Overlay critical band maps from Phase 10 ablation. Determine overlap fraction.

### Long-Fiber Degradation
- **D-10:** Investigate the SMF-28 5m breakdown at z=0.20m. Re-propagate at Nt=2^14 (vs current 2^13) to test if higher spectral resolution helps.
- **D-11:** Also re-optimize at L=5m with max_iter=100 (vs sweep's 30) to test if the optimizer just needs more iterations for long fibers.
- **D-12:** If degradation persists, compute the "suppression horizon" — the maximum L at which the optimizer can maintain >50 dB suppression for SMF-28 at this power level.

### Synthesis Document
- **D-13:** Produce a comprehensive `CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md` merging Phases 9+10+11 into a single coherent narrative. Structure: Abstract, Methods, Results by hypothesis, Discussion, Implications for quantum noise, References.
- **D-14:** All new figures use prefix `physics_11_XX_`. Save to `results/images/`.
- **D-15:** All new JLD2 data goes to `results/raman/phase11/`.

### Claude's Discretion
- Exact figure layouts and panel arrangements
- Whether to include a "phase portrait" style visualization (J(z) vs spectral bandwidth vs z)
- Statistical tests for J(z) trajectory clustering
- How deep to go in the CPA comparison for H3
- Whether the synthesis document should include Phase 6.1 findings or start from Phase 9

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 10 Findings (PRIMARY)
- `results/raman/PHASE10_ZRESOLVED_FINDINGS.md` — Z-resolved findings, onset analysis, 3 preliminary hypotheses
- `results/raman/PHASE10_ABLATION_FINDINGS.md` — Ablation results, H1-H4 hypotheses, critical band data
- `.planning/phases/10-propagation-resolved-physics/10-CONTEXT.md` — Phase 10 decisions

### Phase 9 Findings
- `results/raman/PHASE9_FINDINGS.md` — Central findings: 7 hypotheses tested, universal vs arbitrary verdict
- `.planning/phases/09-physics-of-raman-suppression/09-RESEARCH.md` — Literature review, 5 candidate mechanisms

### Existing Infrastructure
- `scripts/propagation_z_resolved.jl` — Phase 10 z-resolved propagation script (reuse data loading, zsave pattern)
- `scripts/phase_ablation.jl` — Phase 10 ablation script (reuse data loading pattern)
- `scripts/phase_analysis.jl` — Phase 9 analysis script (polynomial decomposition, temporal analysis)
- `scripts/common.jl` — Setup functions, spectral_band_cost, fiber presets
- `scripts/raman_optimization.jl` — Optimizer (needed for D-11 re-optimization at L=5m)

### Data Sources
- `results/raman/sweeps/multistart/start_*/opt_result.jld2` — 10 multi-start phi_opt profiles
- `results/raman/phase10/*_zsolved.jld2` — Phase 10 z-resolved data (6 configs x 2 conditions)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`pz_load_and_repropagate()`** from propagation_z_resolved.jl — loads JLD2, sets zsave, propagates, returns sol with z-resolved fields. Directly reusable for multi-start propagations.
- **`spectral_band_cost()`** from common.jl — computes J at any z-slice.
- **`setup_raman_problem()`** from common.jl — full problem setup for re-optimization (D-11).
- **`optimize_spectral_phase()`** from raman_optimization.jl — for re-optimization at L=5m with max_iter=100.
- Phase 9 `PA_all_points` data loading pattern from phase_analysis.jl.

### Established Patterns
- Constant prefix per script: `PZ_` (propagation_z_resolved), `PAB_` (phase_ablation), `PA_` (phase_analysis). Phase 11 should use `PC_` (physics completion) or `P11_`.
- 300 DPI PNG output, Okabe-Ito colors, metadata annotations.
- `deepcopy(fiber)` before mutation.
- `if abspath(PROGRAM_FILE) == @__FILE__` guard.

### Integration Points
- Multi-start data: `results/raman/sweeps/multistart/start_{01..10}/opt_result.jld2`
- Phase 10 z-data: `results/raman/phase10/`
- New data: `results/raman/phase11/`
- Figures: `results/images/physics_11_*.png`

</code_context>

<specifics>
## Specific Ideas

### From Phase 10 Findings
- The 10 multi-start solutions had mean pairwise phi_opt correlation of 0.109 but achieved suppression from -49.9 to -60.8 dB. Do their J(z) trajectories also diverge, or do they converge to similar z-dynamics despite different phase shapes?
- Phase 10 found the 5m SMF-28 breakdown at z=0.20m. Is this a fundamental limit (the optimizer can't suppress Raman beyond a certain propagation distance) or a computational artifact (Nt too small, iterations too few)?
- The razor-thin 3 dB scaling envelope (single point at alpha=1.0) is the strongest evidence for amplitude-sensitive nonlinear interference. A CPA comparison figure would make this point visually compelling for a paper.

### Key Physics Questions for Phase 11
1. Do structurally different multi-start solutions create the same J(z) trajectory? If yes → the z-dynamics are determined by fiber physics, not by the specific phase. If no → multiple distinct suppression strategies exist.
2. At what z-position does the shaped pulse's spectrum first visibly differ from the unshaped? Is this before or after the Raman onset point?
3. Is the L=5m degradation a resolution issue (fixable with higher Nt) or a fundamental horizon?
4. Can we write a complete classical physics story that's paper-ready?

</specifics>

<deferred>
## Deferred Ideas

- Multimode (M>1) extension — next milestone
- Quantum noise computation — next milestone
- New optimization cost functions (z-resolved, partial-fiber) — future work
- Interactive pulse shaper design tool — future work

</deferred>

---

*Phase: 11-classical-physics-completion*
*Context gathered: 2026-04-03*
