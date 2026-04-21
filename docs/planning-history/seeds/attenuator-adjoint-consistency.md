# Seed: Carry the forward attenuator through the adjoint exactly

**Planted:** 2026-04-20 by Phase 26
**Trigger:** promote when single-mode gradient fidelity near boundary-stretched solutions becomes load-bearing, or when a docs-only caveat is no longer acceptable.

## Problem

The forward single-mode path applies `sim["attenuator"]` in `simulate_disp_mmf.jl`, but `sensitivity_disp_mmf.jl` does not carry the same operator through the adjoint. The verification document correctly treats this as the main remaining single-mode model inconsistency.

## Why this is seed-sized, not doc-sized

- It touches the physics core, not just the writeup.
- Any fix needs a fresh derivation or at least a careful operator-level audit.
- A half-fix would be worse than leaving the caveat explicit.

## Candidate directions

1. Derive the exact adjoint of the attenuated forward step and thread it into `adjoint_disp_mmf!`.
2. Move the attenuator entirely out of the optimization dynamics and treat it purely as a diagnostic/boundary check.
3. Add dedicated Taylor-remainder tests at boundary-stretched operating points to quantify the real error budget before changing the core.
