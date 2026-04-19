# Phase 16 — Long-Fiber Raman Suppression at L = 100 m

*Session F — FINDINGS.md regenerated 2026-04-17 (postprocess fix: amplitude-weighted φ fit).*

## Configuration

| Quantity | Value |
|---|---|
| Fiber | SMF-28 (β₂ only, β₂ = -2.17e-26 s²/m) |
| Length | 100.0 m |
| P_cont | 0.05 W |
| Pulse | 185 fs sech² @ 1550 nm, 80.5 MHz |
| Grid | Nt = 32768, T = 160.0 ps |
| β_order | 2 |
| Warm-start seed | `results/raman/sweeps/smf28/L2m_P0.05W/opt_result.jld2` |

## Headline numbers

| Quantity | Value |
|---|---|
| J_flat(L=100 m) | -0.20 dB |
| J_warm@2m(L=100 m) | -51.50 dB |
| J_opt@100m (Phase 16 result) | -54.77 dB |
| Δ (opt vs flat) | -54.56 dB |
| Δ (opt vs warm) | -3.26 dB |

## Convergence

| Quantity | Value |
|---|---|
| L-BFGS iterations | 25 |
| converged flag | false |
| final ‖∇J‖ | 4.791e-01 |
| wall time (fresh) | 68.2 min |

## Energy conservation

| Run | Photon-number drift | BC edge fraction |
|---|---|---|
| flat       | 4.85e-02 | 6.82e-01 |
| phi@2m     | 2.04e-03 | 7.53e-07 |
| phi@100m   | 4.91e-04 | 8.46e-06 |

## φ(ω) quadratic-fit fingerprint *(corrected)*

Fit model: φ(ω) ≈ a₀ + a₁·ω + a₂·ω² + Δφ(ω), **weighted by analytic
sech² pulse amplitude |U(ω)|** over bins with |U|/|U|_max > 1e-3
(~±5 THz signal band).

Weight drops all bins below 1e-3 of peak amplitude. Active bins: 2349 / 32768 (7.2% of grid).

| Phase | a₀ [rad] | a₁ [s] | a₂ [s²] | R² |
|---|---|---|---|---|
| phi@2m warm  | 1.455e-01 | 1.693e-14 | -2.403e-28 | 0.037 |
| phi@100m opt | -1.662e-01 | 1.798e-14 | 7.936e-28 | 0.015 |

### a₂ scaling — structural-adaptation fingerprint

- Observed ratio a₂(100 m) / a₂(2 m) = -3.303
- Pure-GVD prediction (100 m / 2 m) = 50.000
- Deviation = -106.61% from pure GVD rescale

**Interpretation**: Pure-GVD pre-compensation predicts the optimal φ(ω)
scales with L, so a₂(L_new) = (L_new/L_old)·a₂(L_old). A significant
deviation signals nonlinear structural adaptation — the publishable
physics thread (D-F-07).

R² values close to 1 indicate the phase IS mostly quadratic over
the pulse bandwidth; values far from 1 indicate non-polynomial
residual structure.

## Open questions for Phase 17

- Does the warm-start basin coincide with the global minimum at L=100 m?
  A multi-start repeat of Phase 16 would nail this.
- Scaling to L=200 m: does a₂(200)/a₂(100) = 2 (pure GVD)?
- HNLF analogue at equivalent dispersion length: same physics?
- Multimode generalization (M > 1): does the shape universality survive?
- Segmented / piecewise shaping (re-optimize every 5–10 m) — likely much
  deeper suppression per segment, but requires in-line shapers.
