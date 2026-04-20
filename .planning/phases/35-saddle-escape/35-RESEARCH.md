# Phase 35 Research — Saddle-Rich Nonconvex Optimization and Reachable Minima

**Researched:** 2026-04-20  
**Confidence:** High on the geometry framing and method ranking; medium on
whether this repo's best practical route lands at true minima without a basis
restriction step

## Summary

The external literature and the project's own evidence point to the same
conclusion: when a nonconvex problem is saddle-rich, the main challenge is not
"more random restarts" but **escaping strict saddles and controlling the basin
after escape**.

For this repo specifically:

- Phase 13 already established strict negative curvature at the canonical
  full-resolution optima.
- Phase 22 showed that sharpness-aware objectives did not convert the measured
  optima into minima, even when robustness improved.
- Phase 27 argued that any serious second-order path now needs
  globalization/trust logic, not just richer curvature diagnostics.

That makes the method ranking fairly clear:

1. **Best diagnosis / next implementation target:** globalized second-order
   methods that explicitly detect and use negative curvature
   (Newton-CG / trust-region or cubic-regularized Newton).
2. **Cheap baseline escape mechanism:** perturbed descent around low-gradient
   saddles.
3. **Heuristic reference, not first recommendation:** saddle-free Newton.
4. **What not to trust as the main answer:** SAM-style sharpness penalties on
   their own. They can help robustness, but they do not reliably resolve the
   saddle-vs-minimum question.

## What Prior Phases Already Settled

### Phase 13

- Full-resolution canonical optima are Hessian-indefinite with
  `lambda_min < 0 < lambda_max`.
- The negative wing is small relative to the top wing but numerically robust,
  not noise.
- The multiplicity across starts is not explained by gauge equivalence or
  low-order polynomial equivalence.

Interpretation:
- the repo is already past the "maybe these are just minima with funny
  symmetries" stage.
- the relevant open question is whether nearby genuine minima exist at similar
  Raman depth, not whether saddles exist.

### Phase 22

- Across all resolved Hessian spectra in the sharpness sweep, every measured
  optimum remained indefinite.
- Robustness could be bought, especially with trace and stronger MC penalties,
  but only by paying substantial Raman-depth cost.
- SAM did not produce a compelling robustness/depth Pareto here.

Interpretation:
- "regularize for flatness" is not enough to infer or enforce genuine minima in
  this landscape.
- if minima exist, they were not reached by the sharpness penalties already
  tested.

### Phase 27

- The numerics audit elevated globalization and negative-curvature-aware
  second-order methods over ad hoc optimizer experimentation.
- It also argued that basis restriction / reduced models may have more leverage
  than immediately throwing more sophistication at the full-grid phase space.

Interpretation:
- the right next experiment is a controlled reduced-space study with explicit
  curvature information, not another unstructured full-space optimizer bakeoff.

## External Optimization Literature

### Saddle-rich geometry is a real obstacle, especially in high dimension

Dauphin, Pascanu, Gulcehre, Cho, Ganguli, and Bengio argue that the dominant
difficulty in many high-dimensional nonconvex problems is the proliferation of
saddles rather than poor local minima, and they proposed saddle-free Newton as
a response.  
Source: arXiv 1405.4604, "On the saddle point problem for non-convex
optimization." https://arxiv.org/abs/1405.4604

Why it matters here:
- this matches Phase 13 and Phase 22 unusually well.
- the repo has repeated evidence for many good-but-indefinite stopping points
  and no confirmed high-quality minima.

### Small perturbations are enough to escape strict saddles in principle

Jin, Ge, Netrapalli, Kakade, and Jordan show that perturbed gradient descent
escapes strict saddles and reaches second-order stationary points with only
logarithmic overhead in dimension relative to first-order stationarity.  
Source: PMLR 70 (ICML 2017), "How to Escape Saddle Points Efficiently."
https://proceedings.mlr.press/v70/jin17a.html

Why it matters here:
- if the repo's saddles are strict, then escaping them does not require exotic
  theory.
- but the theorem only guarantees a second-order stationary point, not that the
  resulting minimum is still in the desirable Raman-depth regime.

### Negative-curvature descent is an efficient local-minima finder when used only in small-gradient regions

Yu, Zou, and Gu show that algorithms can save work by using gradient descent in
large-gradient regions and a negative-curvature step only after entering a
small-gradient region.  
Source: arXiv 1712.03950, "Saving Gradient and Negative Curvature
Computations: Finding Local Minima More Efficiently."
https://arxiv.org/abs/1712.03950

Why it matters here:
- this is almost exactly the repo's situation: L-BFGS gets to a tiny-gradient
  point, but the Hessian says "still a saddle."
- the natural next step is therefore not to replace the whole optimization
  pipeline, but to add a curvature-triggered escape phase near convergence.

### Newton-CG with explicit negative-curvature handling has stronger footing than pure saddle-free heuristics

Royer, O'Neill, and Wright analyze a Newton-CG method for smooth nonconvex
optimization that explicitly detects and uses negative curvature directions,
with complexity guarantees to approximate second-order optimality.  
Source: arXiv 1803.02924, "A Newton-CG Algorithm with Complexity Guarantees for
Smooth Unconstrained Optimization." https://arxiv.org/abs/1803.02924

Why it matters here:
- this is a better algorithmic fit for the repo than plain saddle-free Newton.
- it respects the numerics-audit recommendation that second-order work must
  include explicit globalization / safeguard logic.

### Cubic regularization is a principled way to globalize Newton in nonconvex problems

Nesterov and Polyak analyzed cubic regularization of Newton's method and gave
global performance guarantees, making it one of the standard ways to turn local
second-order information into a nonconvex local-minima method.  
Source: Mathematical Programming 108 (2006), "Cubic regularization of Newton
method and its global performance."
Bibliographic landing page: https://EconPapers.repec.org/RePEc:cor:louvrp:1927

Why it matters here:
- if Phase 35 finds that minima do exist but are hard to enter stably, cubic
  regularization is the cleanest "serious next method" to recommend.
- it naturally handles indefinite Hessians better than raw Newton steps.

### Saddle-free Newton is relevant but still a heuristic choice here

Paternain, Mokhtari, and Ribeiro propose a Newton-type method that replaces
negative eigenvalues by their absolute values and show fast saddle evasion in a
theoretical model.  
Source: arXiv 1707.08028, "A Newton-Based Method for Nonconvex Optimization
with Fast Evasion of Saddle Points." https://arxiv.org/abs/1707.08028

Why it matters here:
- it is the closest direct answer to the advisor's "what about Newton?" prompt.
- but in this repo it is not the first recommendation because it requires
  stronger Hessian manipulation, is less directly aligned with the numerics
  audit, and still needs globalization to be operationally trustworthy.

### Modern SAM variants explicitly acknowledge saddle oscillation as a weakness

Yu, Zhang, and Kwok note that SAM can oscillate around saddle points and propose
lookahead-style modifications to reduce that behavior.  
Source: PMLR 235 (ICML 2024), "Improving Sharpness-Aware Minimization by
Lookahead." https://proceedings.mlr.press/v235/yu24q.html

Why it matters here:
- Phase 22's empirical result that SAM did not solve the geometry problem is
  consistent with the literature.
- this reinforces that Phase 35 should not recommend "do more SAM" as the
  main next move.

## Prescriptive Guidance for This Repo

### Best next scientific question

Do genuine minima appear only after enough control-space restriction that the
phase profile loses the high-performance Raman-suppression structure?

That is a better question than "can Newton beat L-BFGS?" because it separates:

- geometry of the objective,
- from method choice.

### Best next algorithm to prototype after Phase 35

If Phase 35 confirms that competitive solutions remain saddles while lower-depth
reduced models become minima, the next optimizer should be:

- **reduced-basis Newton-CG or trust-region / cubic-regularized Newton**,
- with explicit negative-curvature detection,
- and continuation in `N_phi` or basis richness.

That path is better than full-space saddle-free Newton because:

- dense or matrix-free Hessian control is more realistic in reduced space,
- globalization is easier to implement honestly,
- and Phase 27 already identified basis restriction as a likely leverage point.

### Minimal viable escape mechanism

Even before a full second-order rollout, a practical near-term upgrade is:

1. run plain L-BFGS until gradient norm is small,
2. estimate the leftmost Hessian eigenpair,
3. if `lambda_min < -tol`, take a signed negative-curvature escape step,
4. re-enter first-order optimization from the escaped point.

That directly targets the failure mode Phases 13 and 22 exposed.

## Sources

- Dauphin et al. (2014), "On the saddle point problem for non-convex
  optimization": https://arxiv.org/abs/1405.4604
- Jin et al. (2017), "How to Escape Saddle Points Efficiently":
  https://proceedings.mlr.press/v70/jin17a.html
- Yu, Zou, Gu (2017), "Saving Gradient and Negative Curvature Computations:
  Finding Local Minima More Efficiently": https://arxiv.org/abs/1712.03950
- Royer, O'Neill, Wright (2018), "A Newton-CG Algorithm with Complexity
  Guarantees for Smooth Unconstrained Optimization":
  https://arxiv.org/abs/1803.02924
- Nesterov, Polyak (2006), "Cubic regularization of Newton method and its
  global performance": https://EconPapers.repec.org/RePEc:cor:louvrp:1927
- Paternain, Mokhtari, Ribeiro (2017), "A Newton-Based Method for Nonconvex
  Optimization with Fast Evasion of Saddle Points":
  https://arxiv.org/abs/1707.08028
- Yu, Zhang, Kwok (2024), "Improving Sharpness-Aware Minimization by
  Lookahead": https://proceedings.mlr.press/v235/yu24q.html
