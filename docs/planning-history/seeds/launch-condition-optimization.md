---
title: Joint spectral-phase + launch-condition optimization for multimode Raman suppression
type: seed
planted_date: 2026-04-16
trigger_condition: "Advisor confirms Rivera Lab setup includes a spatial SLM for mode-selective launch (question Q1 in .planning/research/advisor-meeting-questions.md answered YES to spatial SLM)."
surface_when: "Immediately after advisor meeting if Q1 answer is positive"
---

# Seed: Joint optimization of spectral phase + input mode coefficients

## The idea

If Rivera Lab has a spatial SLM for launch control (in addition to the spectral pulse shaper), the input mode coefficients `{c_m}` become real optimization parameters — not just boundary conditions. Jointly optimize:

- Spectral phase `φ(ω)` — existing knob, Nt_φ ≈ 64–256 DOFs
- Input mode coefficients `{c_m}` — new knob, 2(M-1) = 10 real DOFs at M=6

Target: minimize `J = E_band / E_total` (or whichever multimode cost function is picked per advisor Q4).

## Why this is novel

I don't know of systematic published work on "does launching into a non-LP01 mode superposition reduce Raman in a multimode fiber?" — the classical assumption is LP01 launch, but in a multimode fiber there's no reason this is the Raman-optimal choice. Nonlinear interference between modes could potentially reduce Raman gain in unintuitive ways.

This is a physics question that's both theoretically interesting and experimentally tractable if the hardware supports it.

## Implementation work required

1. **Adjoint gradient w.r.t. `{c_m}`.** The current adjoint is derived for `∂J/∂φ`. Need to derive `∂J/∂c_m` — straightforward but requires care at the boundary (z=0 condition).
   - Gradient structure: `∂J/∂c_m = λ(0)·∂u(0, x)/∂c_m` where `∂u(0,x)/∂c_m` is the spatial mode profile. Simple inner product.
2. **SLM-realistic parameterization.** If phase-only SLM (per Q2), parameterize with a unit-norm constraint on amplitudes and free phases. If complex-amplitude SLM, unconstrained. Amplitude parameterization via `c_m = |c_m| exp(i θ_m)` with a global-phase gauge fix.
3. **Cost function choice.** Per advisor Q4.
4. **Multi-parameter Newton.** The Hessian grows to include mixed `∂²J/∂φ∂c_m` terms. N_φ + 10 parameters → N_φ+10 Hessian columns per Newton iter. Small overhead.
5. **Experimental comparison target.** Baseline = LP01-only launch with phase-optimized shaping. Proposed = `{c_m}`-optimized launch with phase co-optimized. Metric = dB improvement in Raman suppression.

## Risks / pitfalls

- **Local minima.** `{c_m}` space is non-convex (amplitudes × phases), and Newton/L-BFGS are local methods. Multi-start with random initial mode content is probably necessary.
- **Experimental realization accuracy.** Even a perfect optimizer result is only as good as the SLM's achievable fidelity for the target mode superposition. Phase-only SLMs lose 30–80% of power to diffraction orders when synthesizing complex modes. Worth estimating expected experimental achievable vs. simulation optimum.
- **Mode coupling in the fiber.** If the fiber has significant random linear mode coupling, the optimized input mode content may get scrambled before Raman sets in. Would need to measure or model mode coupling.
- **"Magic" solutions aren't always physical.** The optimizer might find a launch condition that's mathematically optimal but can't be produced by any realistic SLM pattern. Need to constrain or post-filter.

## Quick feasibility estimate

At M=6, adding 10 parameters to N_φ=256 gives ~266-dim Newton (vs 256 without mode content). Hessian column count: 266 instead of 256. Cost increase: ~4%.

Forward+adjoint at M=6 dominates cost; adding mode-coefficient gradient is negligible marginal cost.

**Bottom line: almost free to add if the advisor confirms the hardware exists.** Implementation would take maybe 2–3 days after the Newton optimizer is working.

## Trigger action

When advisor confirms spatial SLM:
1. Move this seed content into an active phase or plan.
2. Use `/gsd-insert-phase` to add as a phase after the multimode Raman baseline is working (not parallel — needs the baseline code to build on).
3. Derive and implement `∂J/∂c_m` gradient.
4. Extend the optimizer driver to take a joint parameter vector.
