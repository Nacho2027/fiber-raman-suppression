# Session E — Simple-Profile Candidate Handoff

**Generated:** 2026-04-17T11:11:38.598
**Source:** Sweep 2 results, low-resolution phase parameterization

Each candidate is a non-dominated point on (J_dB, N_eff) whose J is within
3 dB of the best J achieved at its (fiber, L, P) operating point. Sorted by
N_eff (simpler first).

| # | Fiber | L (m) | P (W) | N_φ | J (dB) | ΔJ (dB) | N_eff | TV | curv. |
|---|-------|-------|-------|-----|--------|---------|-------|----|-------|
| 1 | SMF28 | 0.25 | 0.020 | 57 | -63.02 | 0.00 | 1.75 | 0.13 | 1.45e-01 |
| 2 | SMF28 | 1.00 | 0.100 | 57 | -73.06 | 0.00 | 2.07 | 0.58 | 4.68e+03 |
| 3 | SMF28 | 0.25 | 0.100 | 57 | -82.33 | 0.00 | 2.33 | 0.13 | 2.63e+00 |

## Handoff notes

- φ_opt profiles are stored in `results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2` as
  `phi_opt` arrays (length Nt=16384). Use `JLD2.load(...)` and filter by `config`.
- Simplicity metrics (`N_eff`, `TV`, `curvature`) were computed on the pulse bandwidth
  mask; see `scripts/sweep_simple_param.jl` for definitions.
- Recommended Session D stability-test protocol: perturb φ by σ·n, n ~ N(0, I), σ in
  {0.01, 0.05, 0.1, 0.2} rad; report mean and max ΔJ. 10 trials per σ.
- For comparison, Session D should also test the corresponding full-resolution optima
  (Nt-dim phase) at the same operating points so the robustness gap can be quantified.

