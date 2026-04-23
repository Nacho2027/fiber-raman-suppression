# Phase 34 Power Validation Summary

Generated: 2026-04-23T21:56:47Z

This bounded validation reruns the short continuation ladder at nearby powers to test whether the `:dispersion` advantage is stable.
- TR max_iter = 20, PCG max_iter = 30

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
| 0.09 | 1.062929e-05 | 2.131252e-05 | none | 1 | 0 | none |
| 0.10 | 5.179230e-06 | 5.084325e-06 | dispersion | 2 | 6 | dispersion |
| 0.11 | 2.916919e-05 | 2.969546e-05 | none | 1 | 1 | tie |

## Power `0.09 W`

- Base `0.5 m` L-BFGS: `J = 2.803573e-07` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | RADIUS_COLLAPSE | 1.341749e-05 | 4 | 10 | 28 |
| 1.0 -> 2.0 m | Nt=2048, tw=17.0 ps | RADIUS_COLLAPSE | 1.062929e-05 | 1 | 10 | 24 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | RADIUS_COLLAPSE | 1.409564e-05 | 4 | 10 | 28 |
| 1.0 -> 2.0 m | Nt=2048, tw=17.0 ps | RADIUS_COLLAPSE | 2.131252e-05 | 0 | 10 | 20 |

## Power `0.10 W`

- Base `0.5 m` L-BFGS: `J = 8.144472e-08` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.225614e-06 | 4 | 2 | 234 |
| 1.0 -> 2.0 m | Nt=2048, tw=18.0 ps | RADIUS_COLLAPSE | 5.179230e-06 | 2 | 10 | 25 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 1.115590e-06 | 4 | 2 | 304 |
| 1.0 -> 2.0 m | Nt=2048, tw=18.0 ps | CONVERGED_1ST_ORDER_SADDLE | 5.084325e-06 | 6 | 3 | 188 |

## Power `0.11 W`

- Base `0.5 m` L-BFGS: `J = 4.791678e-07` in `40` iterations

### Variant `:none`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 8.364380e-06 | 3 | 2 | 149 |
| 1.0 -> 2.0 m | Nt=2048, tw=19.0 ps | CONVERGED_1ST_ORDER_SADDLE | 2.916919e-05 | 1 | 1 | 229 |

### Variant `:dispersion`

| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |
|------|-------------|------|---------:|---------:|---------:|-----:|
| 0.5 -> 1.0 m | Nt=256, tw=10.0 ps | CONVERGED_1ST_ORDER_SADDLE | 8.338033e-06 | 3 | 2 | 151 |
| 1.0 -> 2.0 m | Nt=2048, tw=19.0 ps | CONVERGED_1ST_ORDER_SADDLE | 2.969546e-05 | 1 | 1 | 201 |

## Validation takeaway

- `:dispersion` improved the hardest-rung final objective in `1/3` nearby power settings.
- If that primary-metric pattern holds, `:dispersion` is the right default Phase 34 comparison branch and `:none` remains the baseline.
