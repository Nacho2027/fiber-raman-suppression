# Phase 34 Continuation Ladder Summary

Generated: 2026-04-23T19:01:22Z

Short continuation ladder benchmark:
- base solve at `L = 0.5 m` with L-BFGS
- trust-region continuation steps at `L = 1.0 m` and `L = 2.0 m`
- fixed `P = 0.1 W`, requested `Nt = 256`, requested `time_window = 10 ps`
- each variant carries its own previous-rung solution forward

- Base L-BFGS objective: `8.144472e-08` in `40` iterations

## Variant `:none`

| Rung | Actual grid | Exit | J_final | Iter | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|-----:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.288581e-06 | 5 | 4 | 2 | 182 |

Accepted-step rho: `[0.928202, 0.611057, 1.106847, 0.294081]`

| 1.0 -> 2.0 m | Nt=2048, tw=18.0 ps | MAX_ITER | 5.166700e-06 | 10 | 3 | 7 | 22 |

Accepted-step rho: `[1.044701, 0.292415, 0.702976]`

## Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Iter | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|-----:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.181068e-06 | 5 | 4 | 2 | 245 |

Accepted-step rho: `[0.930901, 0.609029, 1.100309, 0.334408]`

| 1.0 -> 2.0 m | Nt=2048, tw=18.0 ps | MAX_ITER | 3.895665e-06 | 10 | 5 | 5 | 35 |

Accepted-step rho: `[0.760764, 0.320658, 0.3469, 1.688112, 0.365521]`

## Interpretation

- This benchmark is meant to test whether a small `:dispersion` advantage compounds across a short continuation path.
- The comparison is intentionally narrow: `:none` vs `:dispersion` only.
