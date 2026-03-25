# Visualization Overhaul: SMF Gain-Noise Plotting

## What This Is

A comprehensive fix of all plotting and visualization in the smf-gain-noise project (MultiModeNoise.jl). The goal is to produce clean, readable, physically informative plots for nonlinear fiber optics simulations — specifically Raman suppression optimization via spectral phase and amplitude shaping. Plots are for internal research group use (lab meetings, advisor reviews).

## Core Value

Every plot must clearly communicate the underlying physics so that a reader can understand what happened during propagation and optimization without needing the filename or external context.

## Requirements

### Validated

- ✓ Spectral comparison (input vs output, dB scale, wavelength axis) — existing
- ✓ Temporal pulse shape comparison (before/after optimization) — existing
- ✓ Spectral and temporal evolution heatmaps along fiber length — existing
- ✓ Phase diagnostic panel (spectral phase, group delay, GDD, instantaneous frequency) — existing
- ✓ Raman band region marking on spectral plots — existing
- ✓ Boundary condition diagnostic plot — existing
- ✓ Optimization convergence plot — existing

### Active

- [ ] Fix colormap choice across all evolution plots (research best practice for nonlinear optics)
- [ ] Fix spectral phase representation (research wrapped vs unwrapped vs group delay conventions)
- [ ] Add fiber + pulse parameter annotations to every figure (fiber type, L, P, λ₀, pulse width)
- [ ] Reduce Raman band shading opacity to not dominate spectral plots
- [ ] Standardize color scheme across all plot types (input/output consistent everywhere)
- [ ] Fix time axis alignment so before/after panels share same range for visual comparison
- [ ] Fix phase diagnostic readability (oscillatory artifacts, empty panels)
- [ ] Fix evolution plot spectral/temporal axis ranges to focus on physics (not noise floor)
- [ ] Research and implement optimal plot set per run (number of figures, what to show)
- [ ] Ensure all plots are self-documenting (title, annotations, metadata)

### Out of Scope

- Changing the simulation physics or optimization algorithm — visualization only
- Interactive/web-based plots — static PNG/PDF output only
- Notebook-specific plotting — focus on the scripts/visualization.jl pipeline
- Changing the underlying data format or solver output structure

## Context

- **Stack**: Julia + PyPlot (matplotlib backend). All visualization in `scripts/visualization.jl` (~1016 lines).
- **Current state**: 4 plot types per run: opt.png (3×2 comparison), opt_phase.png (2×2 phase diagnostic), opt_evolution_optimized.png, opt_evolution_unshaped.png (2-panel heatmaps each).
- **Runs**: Multiple fiber configs (SMF-28, HNLF) × (lengths, powers). Results saved to `results/raman/{fiber}/{config}/`.
- **Known issues**: Jet colormap, aggressive Raman shading, inconsistent colors, empty/unreadable phase panels, missing metadata annotations, mismatched axis ranges, wasted plot space.
- **BUG**: Raman band shading covers the entire graph — the `axvspan` logic uses incorrect wavelength bounds, shading from the Raman onset all the way to the plot edge instead of just the Raman gain band (~13 THz offset window).
- **User explicitly asked to research**: optimal colormap for supercontinuum/nonlinear optics, wrapped vs unwrapped phase conventions, optimal plot set per run.
- **Colorblind-safe palette already defined** in code (Okabe-Ito) but not consistently applied.
- **Audience**: Research group — annotations and detailed labeling welcome.

## Constraints

- **Tech stack**: Must stay in Julia + PyPlot (matplotlib). No new visualization dependencies.
- **Backward compatibility**: Keep the same function signatures where possible, or provide clear migration.
- **Output format**: PNG at 300 DPI for archival, must look good at both screen and print resolution.
- **Performance**: Plotting should not add significant overhead to optimization runs.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Research colormap choice | User wants evidence-based decision, not default | — Pending |
| Research phase representation | Wrapped vs unwrapped vs group delay has physics implications | — Pending |
| Research optimal plot set | User wants research-driven decision on what to show | — Pending |
| Keep Raman shading, reduce opacity | User explicitly chose this option | — Pending |
| Fiber + pulse params as annotations | User wants self-documenting plots | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-24 after initialization*
