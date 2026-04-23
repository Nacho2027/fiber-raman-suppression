# Phase 34 Power Validation Summary

Generated: 2026-04-23T19:52:26Z

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
| 0.07 | 1.224313e-03 | 2.057849e-03 | none | 5 | 5 | tie |
| 0.08 | 2.152223e-06 | 6.027731e-05 | none | 3 | 2 | none |
| 0.09 | 1.062929e-05 | 2.131252e-05 | none | 1 | 0 | none |
| 0.10 | 5.179230e-06 | 5.084325e-06 | dispersion | 2 | 6 | dispersion |
| 0.11 | 3.044794e-05 | 2.845331e-05 | dispersion | 1 | 1 | tie |
| 0.12 | 3.168005e-05 | 3.167554e-05 | dispersion | 0 | 0 | tie |
| 0.13 | 4.213998e-05 | 4.213998e-05 | none | 0 | 0 | tie |

## Power `0.07 W`

- Base `0.5 m` L-BFGS: `J = 1.391787e-08` in `20` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 2.322045e-07 | 0 | 1 | 140 |
| 1.0 -> 2.0 m | Nt=2048, tw=15.0 ps | MAX_ITER | 1.224313e-03 | 5 | 5 | 22 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 2.322045e-07 | 0 | 1 | 201 |
| 1.0 -> 2.0 m | Nt=2048, tw=15.0 ps | MAX_ITER | 2.057849e-03 | 5 | 5 | 27 |

## Power `0.08 W`

- Base `0.5 m` L-BFGS: `J = 4.878426e-09` in `32` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.748608e-06 | 0 | 1 | 122 |
| 1.0 -> 2.0 m | Nt=2048, tw=16.0 ps | MAX_ITER | 2.152223e-06 | 3 | 7 | 23 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.748608e-06 | 0 | 1 | 137 |
| 1.0 -> 2.0 m | Nt=2048, tw=16.0 ps | MAX_ITER | 6.027731e-05 | 2 | 8 | 21 |

## Power `0.09 W`

- Base `0.5 m` L-BFGS: `J = 2.803573e-07` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | MAX_ITER | 1.341749e-05 | 4 | 6 | 20 |
| 1.0 -> 2.0 m | Nt=2048, tw=17.0 ps | MAX_ITER | 1.062929e-05 | 1 | 9 | 22 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | MAX_ITER | 1.409564e-05 | 4 | 6 | 20 |
| 1.0 -> 2.0 m | Nt=2048, tw=17.0 ps | RADIUS_COLLAPSE | 2.131252e-05 | 0 | 10 | 20 |

## Power `0.10 W`

- Base `0.5 m` L-BFGS: `J = 8.144472e-08` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.225614e-06 | 4 | 2 | 261 |
| 1.0 -> 2.0 m | Nt=2048, tw=18.0 ps | MAX_ITER | 5.179230e-06 | 2 | 8 | 21 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.115590e-06 | 4 | 2 | 248 |
| 1.0 -> 2.0 m | Nt=2048, tw=18.0 ps | CONVERGED_1ST_ORDER_SADDLE | 5.084325e-06 | 6 | 3 | 175 |

## Power `0.11 W`

- Base `0.5 m` L-BFGS: `J = 4.791678e-07` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 8.364380e-06 | 3 | 2 | 134 |
| 1.0 -> 2.0 m | Nt=2048, tw=19.0 ps | MAX_ITER | 3.044794e-05 | 1 | 9 | 109 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 8.338033e-06 | 3 | 2 | 179 |
| 1.0 -> 2.0 m | Nt=2048, tw=19.0 ps | CONVERGED_1ST_ORDER_SADDLE | 2.845331e-05 | 1 | 1 | 205 |

## Power `0.12 W`

- Base `0.5 m` L-BFGS: `J = 7.433705e-07` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 4.721205e-06 | 2 | 1 | 377 |
| 1.0 -> 2.0 m | Nt=2048, tw=20.0 ps | RADIUS_COLLAPSE | 3.168005e-05 | 0 | 10 | 20 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 4.742081e-06 | 2 | 1 | 305 |
| 1.0 -> 2.0 m | Nt=2048, tw=20.0 ps | RADIUS_COLLAPSE | 3.167554e-05 | 0 | 10 | 20 |

## Power `0.13 W`

- Base `0.5 m` L-BFGS: `J = 4.578678e-08` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | RADIUS_COLLAPSE | 2.898424e-05 | 0 | 10 | 20 |
| 1.0 -> 2.0 m | Nt=2048, tw=21.0 ps | RADIUS_COLLAPSE | 4.213998e-05 | 0 | 10 | 20 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | RADIUS_COLLAPSE | 2.898424e-05 | 0 | 10 | 20 |
| 1.0 -> 2.0 m | Nt=2048, tw=21.0 ps | RADIUS_COLLAPSE | 4.213998e-05 | 0 | 10 | 20 |

## Validation takeaway

- `:dispersion` improved the hardest-rung final objective in `3/7` nearby power settings.
- If that primary-metric pattern holds, `:dispersion` is the right default Phase 34 comparison branch and `:none` remains the baseline.
