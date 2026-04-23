# Phase 35 Report — Genuine Minima Reachability vs. Saddle-Dominated Raman Optima

## Executive Verdict

**Genuine minima exist, but not in the competitive Raman-suppression region we
care about.**

The new control-space Hessian ladder shows:

- `N_phi = 4` is minimum-like, but only at **-47.3 dB** Raman suppression.
- By `N_phi = 8`, the canonical branch is already Hessian-indefinite.
- At `N_phi = 128`, the depth is **-68.0 dB**, essentially identical to the
  full-resolution branch, and the Hessian is still indefinite.
- Escaping the `N_phi = 128` saddle along negative curvature improves depth by
  **0.19–0.48 dB**, but every escaped endpoint remains **indefinite**.

That is the key answer to the advisor question:

**we are not merely failing to find a nearby clean minimum by bad luck.**
The high-performing branch appears to be a **strict-saddle branch**. True
minima show up only after aggressive control-space restriction, and they are
roughly **20 dB worse** than the competitive saddle branch.

## What Phase 35 Measured

### 1. Reduced-basis Hessian ladder at the canonical SMF-28 point

Operating point:
- fiber: `SMF28`
- `L = 2.0 m`
- `P = 0.2 W`
- `Nt = 2^14`
- basis kind: cubic for low-resolution levels

Dense control-space Hessians were computed for the locally available
`N_phi` ladder from `results/raman/phase_sweep_simple/sweep1_Nphi.jld2`.

| N_phi | J_dB | Hessian class | lambda_min | lambda_max | |lambda_min|/lambda_max |
|---:|---:|---|---:|---:|---:|
| 4 | -47.34 | minimum-like | 3.354e-07 | 9.604e-06 | 3.49e-02 |
| 8 | -46.89 | indefinite | -9.869e-10 | 6.195e-06 | 1.59e-04 |
| 16 | -53.11 | indefinite | -4.265e-07 | 5.836e-06 | 7.31e-02 |
| 32 | -58.18 | indefinite | -1.648e-05 | 1.553e-05 | 1.06e+00 |
| 64 | -59.81 | indefinite | -2.068e-05 | 1.008e-05 | 2.05e+00 |
| 128 | -68.01 | indefinite | -1.162e-05 | 1.396e-05 | 8.32e-01 |

Full-space anchor:
- `N_phi = 16384` from the sweep bundle reaches **-68.01 dB**
- Phase 13 already established that the corresponding full-space point is
  Hessian-indefinite

### Interpretation of the ladder

This is the cleanest geometry story the project has had so far:

1. A true minimum does exist in a very restricted control space.
2. The moment the control space gets even modestly richer, negative curvature
   appears.
3. The competitive Raman-depth branch is already saddle-dominated by `N_phi = 8`
   and remains so all the way through `128` and then full resolution.

So the good branch is not "a minimum we have not quite located." It is a
different geometric object.

### 2. Negative-curvature escape from the `N_phi = 128` saddle

The best-performing dense ladder point was the `N_phi = 128` saddle at
`-68.01 dB`. Phase 35 perturbed it along the most negative eigenvectors and
re-ran the original low-resolution optimizer.

Results:

| tag | start eig | alpha | sign | final J_dB | delta vs baseline | final class | lambda_min |
|---|---:|---:|---:|---:|---:|---|---:|
| `smf28_canonical_nphi128_escape_pos_a0p200` | 1 | 0.20 | + | -68.49 | -0.48 | indefinite | -5.245e-06 |
| `smf28_canonical_nphi128_escape_pos_a0p100` | 1 | 0.10 | + | -68.34 | -0.33 | indefinite | -5.176e-06 |
| `smf28_canonical_nphi128_escape_neg_a0p200` | 2 | 0.20 | - | -68.29 | -0.27 | indefinite | -3.119e-06 |
| `smf28_canonical_nphi128_escape_pos_a0p050` | 1 | 0.05 | + | -68.20 | -0.19 | indefinite | -2.952e-06 |

All fresh `phi_opt` outputs were saved with the mandatory standard image set
under `results/raman/phase35/images/`.

### Interpretation of the escape study

The practical lesson is sharp:

- negative-curvature escape **does** matter,
- because it finds a better branch than the baseline saddle,
- but it currently finds **better saddles**, not minima.

This rules out the simplistic story that "once we step off the saddle we will
drop into a nearby clean basin." At least in the tested competitive branch, the
nearby geometry is still saddle-rich.

## What This Means Scientifically

### Reachable minima

The project now has evidence for two regimes:

1. **Minimum regime:** aggressively restricted control spaces
   (`N_phi = 4`) with much worse Raman depth.
2. **Competitive regime:** `N_phi >= 8`, especially `32–128` and full
   resolution, where the good solutions are Hessian-indefinite.

So the right statement is:

**genuine minima are reachable only after enough dimensional restriction that
the solution quality degrades substantially.**

### Why Phase 22 did not fix it

Phase 22 already showed that robustness regularization alone does not change the
headline geometry. Phase 35 now explains why:

- the problem is not merely that the saddles are too sharp,
- it is that the high-performing branch itself remains on the indefinite side
  of the landscape.

A flatness penalty can make a saddle less sharp without turning it into a true
minimum.

## Method Recommendation

### Best next optimizer path for this repo

**Do not start with full-space saddle-free Newton.**

The best next serious method is:

1. **reduced-basis continuation in `N_phi`**, starting from minimum-like low
   dimensions,
2. coupled to a **globalized second-order method** with explicit
   negative-curvature handling:
   - Newton-CG + trust region, or
   - cubic-regularized Newton.

Why this is the right next step:

- Phase 35 shows minima exist in low dimension, so continuation has something
  real to follow.
- Phase 35 also shows that simply escaping one saddle in the high-performing
  branch lands at another saddle, so the method needs repeated curvature-aware
  basin management, not one perturbation.
- Phase 27 already argued that any second-order rollout must include
  globalization and trust safeguards.

### Best cheap upgrade before that

Add a near-convergence escape wrapper to the existing optimizer:

1. run L-BFGS until gradient norm is small,
2. estimate the leftmost Hessian eigenpair,
3. if `lambda_min < 0`, take a signed negative-curvature step,
4. restart first-order optimization.

Phase 35 showed this is useful, but it should be described as
**"better-saddle hunting"**, not as a proven minimum finder.

### Why not recommend SAM / more sharpness as the answer?

Because both project evidence and the literature say it is the wrong level of
explanation here:

- Phase 22: robust optima remained indefinite.
- Phase 35: explicit negative-curvature escape also remained on indefinite
  points, even after improving depth.
- The geometry problem is stronger than "insufficient flatness."

## Advisor-Meeting Narrative

Recommended wording:

> We now have direct evidence that the good Raman-suppression branch is
> saddle-dominated, not a missed local minimum. True minima exist only under
> aggressive dimensional restriction, and they are about 20 dB worse. When we
> explicitly step off the high-performing saddle along negative curvature, we
> find better saddles, not minima. So the next question is not "more random
> restarts vs. L-BFGS," but whether a globalized second-order method plus basis
> continuation can track the best branch honestly.

What not to say:

- "We just need Newton to find the real minima."
- "Flatness regularization failed, so minima probably do not exist anywhere."

Both are too crude for what the data now shows.

## Residual Risks / Limits

1. This phase used one canonical operating point for the Hessian ladder.
   The geometry may vary across `(fiber, L, P)`.
2. The escape study tested the best local negative-curvature directions near
   `N_phi = 128`, not a full continuation algorithm.
3. `N_phi = 8` has a very small negative eigenvalue; it is indefinite by sign,
   but close to the numerical threshold. That does not affect the main story,
   which is dominated by the strong-indefiniteness at `32, 64, 128`, and by
   Phase 13's full-space result.

## Deliverables

- `results/raman/phase35/phase35_results.jld2`
- `results/raman/phase35/ladder_summary.md`
- `results/raman/phase35/escape_summary.md`
- `results/raman/phase35/images/*`
- `scripts/saddle_run.jl`
