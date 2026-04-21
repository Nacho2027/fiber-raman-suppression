# Phase 9: Physics of Raman Suppression - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning
**Source:** Direct user input

## User Vision

Understand the physics of WHY the optimizer's spectral phase patterns suppress Raman scattering. This is a research/analysis phase — not building new optimization capability, but understanding what the existing optimizer discovered.

## Locked Decisions

### D-01: Research-grounded explanations only
Everything must be backed by literature or rigorous analysis of the data. No hand-waving. If we propose a mechanism (e.g., "GDD delays soliton fission"), we must show evidence from both the literature AND our phi_opt data.

### D-02: Universal vs arbitrary is the central question
The phase must deliver a clear answer: Do optimal phases have predictable structure from fiber parameters, or is each solution an arbitrary point in a high-dimensional landscape? Evidence must come from cross-sweep comparison of phi_opt profiles.

### D-03: Build on existing Phase 6.1 infrastructure
Phase 6.1 Plan 01 built data loading, phase normalization, and Figures 1-4 (phi_opt overlays, detail panels, correlation scatter). Phase 6.1 Plan 02 (Figures 5-8: group delay, before/after Raman, residual, Raman zoom) was never executed. This phase should complete that work and extend it with deeper analysis.

### D-04: Analyze ALL 24 sweep points + 10 multi-start
The sweep produced 24 (L,P) configurations across SMF-28 and HNLF, plus 10 multi-start runs at one config. All should be analyzed for structural similarity/divergence.

### D-05: Physical basis decomposition is required
Project phi_opt onto interpretable physical components (polynomial chirp: GDD, TOD, FOD; sinusoidal modulation) and report explained variance. This tells us whether the optimizer discovered a simple physical rule or a complex pattern.

### D-06: Output should be paper-quality
Figures and analysis should be at the level of a paper section (methods + results). This isn't exploratory prototyping — it's the scientific analysis of the project.

## Claude's Discretion

- Choice of clustering/similarity metrics for phi_opt comparison
- Whether to include PCA/SVD analysis of the phase profiles
- Which literature to cite and how deep to go
- Figure layout and panel arrangement
- Whether polynomial projection uses weighted or unweighted least squares

## Deferred Ideas

- Multimode (M>1) extension — separate future phase
- Quantum noise computation on top of classical solution — separate future phase
