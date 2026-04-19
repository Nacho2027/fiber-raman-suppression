# Seed: Joint phase + {c_m} optimization at M=6 — Phase 17 candidate

**Planted:** 2026-04-17 by Session C (sessions/C-multimode)
**Trigger:** once Phase 16 Plan 01 passes tests and the baseline M=6 optimization improves J by ≥5 dB, so the phase-only path is validated as a baseline against which joint optimization can be compared.

## Motivation

Direct connection to **Rivera Lab arXiv:2509.03482 (2025)** — "Programmable control of the spatiotemporal quantum noise of light." That paper demonstrates that reshaping the input SPATIAL WAVEFRONT (equivalent to changing `{c_m}`) in a multimode fiber reduces output quantum noise by 12 dB, with cross-phase modulation identified as the dominant noise mechanism.

The classical analog — can changing `{c_m}` in addition to the spectral phase suppress Raman beyond phase-only shaping? — is this seed.

## Hypothesis

Joint (φ, {c_m}) optimization beats phase-only by a factor that grows with Raman strength. Rationale:

- **Phase-only** controls which frequencies reach which z: temporal overlap of Kerr peaks with Raman resonance determines the SRS gain.
- **{c_m} control** additionally steers which mode carries the pump at any given z (via modal walk-off). A launch that puts most energy in a high-β₁ mode (LP11, LP21) can outrun the LP01 Kerr "attractor" and resist self-cleaning → less peak intensity on any single mode → less SRS.

Prediction: at L=1m, P=0.05W, GRIN-50, joint beats phase-only by 3–8 dB in `J_dB`. At L=5m (solitonic regime), the advantage either grows (more XPM to play with) or collapses (soliton fission wipes out the launch-condition degrees of freedom).

## Algorithm sketch

Parameters to optimize:
- φ ∈ ℝ^Nt            — shared spectral phase (Nt dof)
- c_m ∈ ℂ^M, |c|=1     — input mode content (2M-1 real dof after unit-norm constraint + global phase gauge fix)

Cost + gradient chain rule — the existing adjoint already gives `∂J/∂uω0_shaped[ω, m]`. Chain to `c_m`:

    uω0_shaped[ω, m] = pulse(ω) · c_m · exp(iφ(ω))
    ⇒ ∂J/∂c_m = Σ_ω conj(pulse(ω) · exp(iφ(ω))) · ∂J/∂uω0_shaped[ω, m]

L-BFGS on the concatenated vector `[φ; Re(c_m[2:M]); Im(c_m[2:M])]` (LP01 amplitude fixed to real and sign-fixed — gauge).

Constraint: |c|=1 enforced by projected gradient OR by parametrizing `c_m = exp(iα_m) · cos(θ_m) · (hierarchical parametrization of S^(2M-1))` — the former is simpler, use it first.

## Protocol

1. Run the Phase 16 baseline at canonical config → get φ_opt_phase_only, `J_opt_phase_only`.
2. Warm-start joint optimization from (φ_opt_phase_only, MMF_DEFAULT_MODE_WEIGHTS). 30 more L-BFGS iters.
3. Report ΔJ_dB(joint) - ΔJ_dB(phase-only).
4. Gauge-fix the resulting c_m (global phase, LP01 positive real).
5. Characterize the optimal mode content: how far did it move from the default? Is the result "mostly LP01" or "spread across modes"?
6. Side experiment: c_m-only optimization (fix φ=0). How much of the gain comes from each knob?

## What this seed does NOT do

- Spatial-phase-per-mode optimization (that is Rivera's setup, not captured by our 1D mode basis).
- Optimization at the quantum noise level — stays classical.
- Experimentally-constrained launch (no fidelity model for an actual SLM — assumes perfect {c_m} control).

## Dependencies

- Phase 16 Plan 01 passing.
- A new `scripts/mmf_joint_optimization.jl` wrapping `cost_and_gradient_mmf` with the c_m gradient chain + joint parameter vector.
- ~2 hrs compute on burst VM.

## Promotion

This is the **option (a)** free exploration thread from the session prompt. Session C is running Phase 16 Plan 01 as a baseline; if time allows within this session it will also execute Plan 02 (this seed). Otherwise promote to Phase 17.
