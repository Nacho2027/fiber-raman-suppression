# Phase 10: Propagation-Resolved Physics & Phase Ablation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-02
**Phase:** 10-propagation-resolved-physics
**Areas discussed:** Z-resolution, Configuration selection, Phase ablation strategy, Perturbation types, New simulation scope
**Mode:** Auto (--auto flag, all recommended defaults selected)

---

## Z-Resolution

| Option | Description | Selected |
|--------|-------------|----------|
| 20 points | Coarse — fast but may miss dynamics | |
| 50 points | Balanced resolution and memory | ✓ |
| 100 points | Fine — good detail but 2x memory | |

**User's choice:** [auto] 50 points (recommended default)
**Notes:** For 5m fiber gives 10cm resolution. Raman buildup length scales are ~10-50cm, so 50 points resolves the relevant dynamics.

---

## Configuration Selection

| Option | Description | Selected |
|--------|-------------|----------|
| All 24 sweep points | Comprehensive but expensive (48 propagations) | |
| 6 representative (3+3) | Covers both fibers and N_sol range | ✓ |
| 2 canonical only | Minimal but may miss regime differences | |

**User's choice:** [auto] 6 representative + full ablation on 2 canonical (recommended default)
**Notes:** 6 representative configs span low/medium/high N_sol for both fiber types. Full ablation on 2 canonical configs keeps ablation tractable.

---

## Phase Ablation Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Frequency-band zeroing | Zero phi_opt in one sub-band at a time | ✓ |
| Random masking | Randomly zero N% of frequency bins | |
| Polynomial subtraction | Remove polynomial component, keep residual | |

**User's choice:** [auto] Frequency-band zeroing with smooth windows (recommended default)
**Notes:** Most physically interpretable — directly answers "which frequencies matter." Super-Gaussian roll-off avoids Gibbs artifacts.

---

## Perturbation Types

| Option | Description | Selected |
|--------|-------------|----------|
| Global scaling (0-200%) | Scale entire phi_opt | ✓ |
| Spectral shift (±1-5 THz) | Translate phi_opt on frequency grid | ✓ |
| Phase noise addition | Add random phase noise | |
| Frequency truncation | Progressively narrow phi_opt bandwidth | ✓ |

**User's choice:** [auto] Scaling + shift + truncation (recommended default, no noise)
**Notes:** Deterministic perturbations isolate mechanisms better than stochastic noise.

---

## New Simulation Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Re-propagate only | Use existing phi_opt, just add zsave | ✓ |
| Re-propagate + new configs | Also optimize at new (L,P) points | |
| Re-propagate + new cost functions | Optimize with z-resolved cost | |

**User's choice:** [auto] Re-propagate existing phi_opt only (recommended default)
**Notes:** Phase 10 is about understanding, not discovering new solutions. New optimization belongs in future phases.

---

## Claude's Discretion

- Specific (L,P) configuration selection from sweep data
- Figure layout for z-resolved plots
- Whether to add spectrogram analysis at selected z-points
- Statistical presentation of ablation results

## Deferred Ideas

- Multimode M>1 extension
- Quantum noise computation
- New optimization cost functions (z-resolved minimization)
- FROG/XFROG time-frequency analysis
