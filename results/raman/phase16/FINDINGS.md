# Phase 16 — Long-Fiber Raman Suppression at L = 100 m

*Session F — generated 2026-04-17T18:52:24.351 by `longfiber_validate_100m.jl`.*

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

## Checkpoint-resume validation

- resume result JLD2 not found; skipped parity check.

## Energy conservation

| Run | Photon-number drift | BC edge fraction |
|---|---|---|
| flat       | 4.85e-02 | 6.82e-01 |
| phi@2m     | 2.04e-03 | 7.53e-07 |
| phi@100m   | 4.91e-04 | 8.46e-06 |

## φ(ω) quadratic-fit fingerprint

Fit model: φ(ω) ≈ a₀ + a₁·ω + a₂·ω² + Δφ(ω), weighted by |phi(ω)| > 1e-8.

| Phase | a₀ [rad] | a₁ [s] | a₂ [s²] | R² |
|---|---|---|---|---|
| phi@2m warm  | 5.225e-03 | 1.207e-04 | -1.165e-06 | 0.001 |
| phi@100m opt | 4.765e-03 | 1.053e-04 | -7.827e-07 | 0.000 |

### a₂ scaling — structural-adaptation fingerprint

- Observed ratio a₂(100 m) / a₂(2 m) = 0.672
- Pure-GVD prediction (100 m / 2 m) = 50.000
- Deviation = -98.66% from pure GVD rescale

**Interpretation**: If the ratio is close to the pure-GVD prediction, the
optimal φ@100 m is a simple quadratic rescale of φ@2 m (pure-GVD hypothesis).
A significant deviation (> ~20%) signals nonlinear structural adaptation —
the publishable physics thread for Session F (D-F-07).

## Open questions for Phase 17

- Does the warm-start basin coincide with the global minimum at L=100 m?
  A multi-start repeat of Phase 16 would nail this.
- Scaling to L=200 m: does a₂(200)/a₂(100) = 2 (pure GVD)?
- HNLF analogue at equivalent dispersion length: same physics?
- Multimode generalization (M > 1): does the shape universality survive?
