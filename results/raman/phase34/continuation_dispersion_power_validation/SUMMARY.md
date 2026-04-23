# Phase 34 Power Validation Summary

Generated: 2026-04-23T19:22:24Z

This bounded validation reruns the short continuation ladder at nearby powers to test whether the `:dispersion` advantage is stable.

## Proposed success metric

Primary metric:
- final `J` on the hardest rung (`1.0 -> 2.0 m`), because that is the closest bounded proxy for whether the method is buying better suppression where the path is most stressed.

Secondary metrics:
- accepted-step count on the hardest rung, as a reliability proxy
- accepted-step `rho`, as a local model-quality proxy
- HVP count, as a bounded inner-solve cost proxy

A power setting counts as a `:dispersion` win only if it improves the primary metric; the others are supporting evidence, not substitutes.

## Hardest-rung summary

| Power [W] | none J_final | dispersion J_final | Better final J | none accepted | dispersion accepted | More accepted |
|-----------:|-------------:|-------------------:|----------------|--------------:|--------------------:|---------------|
| 0.08 | 1.446758e-06 | 6.027732e-05 | none | 4 | 2 | none |
| 0.10 | 5.166700e-06 | 3.895665e-06 | dispersion | 3 | 5 | dispersion |
| 0.12 | 3.169606e-05 | 3.169219e-05 | dispersion | 0 | 0 | tie |

## Power `0.08 W`

- Base `0.5 m` L-BFGS: `J = 4.878426e-09` in `32` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.748608e-06 | 0 | 1 | 137 |
| 1.0 -> 2.0 m | Nt=2048, tw=16.0 ps | MAX_ITER | 1.446758e-06 | 4 | 6 | 26 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.748608e-06 | 0 | 1 | 227 |
| 1.0 -> 2.0 m | Nt=2048, tw=16.0 ps | MAX_ITER | 6.027732e-05 | 2 | 8 | 21 |

## Power `0.10 W`

- Base `0.5 m` L-BFGS: `J = 8.144472e-08` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.288581e-06 | 4 | 2 | 182 |
| 1.0 -> 2.0 m | Nt=2048, tw=18.0 ps | MAX_ITER | 5.166700e-06 | 3 | 7 | 22 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.181068e-06 | 4 | 2 | 349 |
| 1.0 -> 2.0 m | Nt=2048, tw=18.0 ps | MAX_ITER | 3.895665e-06 | 5 | 5 | 35 |

## Power `0.12 W`

- Base `0.5 m` L-BFGS: `J = 7.436365e-07` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 4.713608e-06 | 2 | 1 | 170 |
| 1.0 -> 2.0 m | Nt=2048, tw=20.0 ps | RADIUS_COLLAPSE | 3.169606e-05 | 0 | 10 | 20 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 4.739877e-06 | 2 | 1 | 328 |
| 1.0 -> 2.0 m | Nt=2048, tw=20.0 ps | RADIUS_COLLAPSE | 3.169219e-05 | 0 | 10 | 20 |

## Validation takeaway

- `:dispersion` improved the hardest-rung final objective in `2/3` nearby power settings.
- If that primary-metric pattern holds, `:dispersion` is the right default Phase 34 comparison branch and `:none` remains the baseline.
