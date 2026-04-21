# Seed: Does optimal MMF spectral phase generalize across fiber lengths?

**Planted:** 2026-04-17 by Session C (sessions/C-multimode)
**Trigger:** after Phase 16 baseline converges at M=6, L=1m. Promote when a clean φ_opt exists for one length and the research question "does this φ_opt transfer?" becomes load-bearing for an experimental plan.

## Hypothesis

At M=6 in GRIN-50, the spectral phase that minimizes `E_band/E_total` at L=1m will NOT transfer cleanly to L=0.5, 2, or 5m because:

1. **Soliton regime crossover** (Renninger/Wise 2013, Wright+ 2020). At L=0.5m the pulse is still dispersion-limited (below 1 soliton period); at L=5m with P_cont=0.05W, the fundamental-mode N_sol ≈ 3 and soliton fission + Raman SSFS dominate.
2. **Intermodal walk-off** accumulates with L. The higher-order modes have a different β₁ from LP01, so what looks like a Raman-producing temporal overlap at L=1m becomes a walk-off-separated non-interaction at L=5m.
3. **Attenuator boundary** absorbs more at longer L because SPM + dispersive broadening widens the pulse. The φ_opt found at L=1m is tuned to the attenuator's profile at that L.

A priori guess: φ_opt(L=1m) → gives ≤ 50% of the achievable `ΔJ_dB` at L=2m, ≤ 20% at L=5m, <10% at L=0.5m (different regime entirely).

## Suggested protocol

1. Use `scripts/mmf_baseline_run.jl` to get φ_opt at L=1m, seed=42.
2. Evaluate `cost_and_gradient_mmf(φ_opt(1m), c_m, ...)` at L ∈ {0.5, 2, 5} m WITHOUT re-optimizing.
3. Independently re-optimize at each L (30 iters) to get the reference φ_opt(L) and its `J_ref_L`.
4. Report `transfer_ratio(L) = (J_zero(L) - J_transfer(L)) / (J_zero(L) - J_ref_L)`.
5. If transfer_ratio stays > 0.8 across all four lengths, the seed is FALSIFIED — there's a gauge-like structure that generalizes, and the advisor will want to see polynomial projection in that basis.

## Notes

- Needs 4 L-BFGS runs at M=6, Nt=2^13 — ~40 min on burst VM with -t auto.
- Could piggyback on the Phase 16 plan 01 sweep if extended.
- No new code needed — just a driver script wrapping existing `cost_and_gradient_mmf`.

## Out of scope for Phase 16 Plan 01

This is the "option (b)" of the free-exploration budget the session prompt offered. Session C picked option (a) for this sprint — this seed captures option (b) for future work (Phase 18+).
