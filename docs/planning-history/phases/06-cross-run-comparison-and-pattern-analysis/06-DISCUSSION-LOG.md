# Phase 6: Cross-Run Comparison and Pattern Analysis - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 06-cross-run-comparison-and-pattern-analysis
**Areas discussed:** Run generation, Summary table format, Overlay plot design, Phase decomposition approach

---

## Run Generation

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 6 re-runs all 5 configs | Include a plan that executes raman_optimization.jl to generate JLD2 files as first step. Self-contained. | ✓ |
| User runs manually first | User runs julia scripts/raman_optimization.jl before Phase 6. | |
| Phase 6 script auto-detects | run_comparison.jl checks for JLD2 files, runs missing configs automatically. | |

**User's choice:** Phase 6 re-runs all 5 configs

---

## Summary Table Format

| Option | Description | Selected |
|--------|-------------|----------|
| PNG figure (Recommended) | Matplotlib-rendered table as figure. Presentation-ready. | ✓ |
| Markdown file | results/raman/comparison_summary.md | |
| Both PNG + markdown | Generate both formats. | |

**User's choice:** PNG figure

---

## Overlay Plot Design

| Option | Description | Selected |
|--------|-------------|----------|
| Split by fiber type | Separate panels for SMF-28 and HNLF. | |
| All on shared axes | All 5 runs overlaid on one axes. | |
| Both views | All-runs convergence + per-fiber spectral overlays. 3 figures. | ✓ |

**User's choice:** Both views (all-runs convergence overlay + separate SMF-28/HNLF spectral overlays)
**Notes:** User asked if Phase 7 would have its own analysis. Confirmed: Phase 7 produces heatmaps and multi-start plots — different kind of analysis (parameter space mapping vs config comparison).

---

## Phase Decomposition Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Polynomial fit (Recommended) | Least-squares fit up to 3rd order. Report GDD, TOD, residual. | |
| Taylor expansion at center | Compute derivatives at omega_0. | |
| You decide | Claude's discretion. | ✓ |

**User's choice:** You decide

---

## Claude's Discretion

- Phase decomposition method (polynomial fit vs Taylor expansion)
- Script organization (single file vs multiple)
- 5-config color palette
- Figure sizes and layouts

## Deferred Ideas

None.
