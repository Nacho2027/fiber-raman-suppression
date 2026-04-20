# Phase 28 Summary

## Verdict

Genuine minima do exist, but only after aggressive control-space restriction
that destroys the competitive Raman-suppression depth. The high-performing
branch remains saddle-dominated.

## Core Evidence

1. On the canonical SMF-28 `N_phi` ladder, only `N_phi = 4` is minimum-like,
   at `-47.3 dB`.
2. By `N_phi = 128`, the branch reaches `-68.0 dB`, essentially the same depth
   as full resolution, but the Hessian is still indefinite.
3. Negative-curvature escape from the `N_phi = 128` saddle improves depth by
   `0.19–0.48 dB`, but every escaped endpoint remains indefinite.

## Recommendation

The next serious optimizer path should be reduced-basis continuation plus a
globalized second-order method with negative-curvature handling
(trust-region / Newton-CG or cubic-regularized Newton). A simple
negative-curvature restart wrapper is worthwhile as a cheaper interim upgrade.

## Advisor Narrative

Do not frame the problem as "we just have not found the minima yet." The
competitive Raman branch looks like a saddle branch. Minima appear only after
severe dimensional restriction and large depth loss.
