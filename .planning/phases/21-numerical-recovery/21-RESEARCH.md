# Phase 21 Research — Numerical Recovery of SUSPECT Results

## Standard Stack

- Use the existing Julia + `PyPlot` stack; do not add new dependencies.
- Reuse the codebase's validated forward/adjoint pipeline:
  `MultiModeNoise.solve_disp_mmf`, `solve_adjoint_disp_mmf`,
  `spectral_band_cost`, `optimize_spectral_phase`.
- Reuse `scripts/longfiber_setup.jl` for exact `(Nt, time_window)` control.
- Reuse `scripts/sweep_simple_param.jl` for low-dimensional `N_phi` recovery.
- Reuse `scripts/mmf_setup.jl` and `scripts/mmf_raman_optimization.jl` for the
  opportunistic MMF aggressive run.
- Validate all recovered phases with the same boundary-energy diagnostic used by
  the audit: `check_boundary_conditions(...)`.

## Architecture Patterns

### 1. Formula first, direct validation second

The literature and this codebase agree on the pattern:
- start from a physically motivated bandwidth / walk-off estimate,
- then validate the chosen grid by re-running the actual propagation and
  checking whether the pulse remains well-contained.

For Phase 21 that means:
- estimate the minimum useful time window from `|β₂| L Δω` plus SPM broadening,
- choose `Nt` to preserve few-femtosecond resolution,
- then forward-propagate the flat pulse and the warm-start `phi_opt`,
- enlarge the grid if the output edge fraction is not `< 1e-3`.

### 2. Convergence claims must be separated from “best achieved J”

The Sinkin et al. SSFM study emphasizes that accuracy and efficiency are ruled
by the numerical error budget, not by optimizer status labels alone. In this
project, the physics audit already showed the complementary failure mode: a
stationary point on a bad grid is still a bad answer. So Phase 21 reports both:
- whether a run converged numerically as an optimizer,
- and whether the recovered `J_dB` is honest on a pulse-contained grid.

### 3. Multimode validation is solver-first, science-second

The Optics Express multimode-solver paper and Session C's existing context both
use the same validation pattern:
- verify the multimode solver against a simpler limit case,
- then only interpret aggressive-regime behavior as physics.

Phase 21 follows that rule by reusing Session C's already-validated M=6 path
and treating the aggressive MMF run as opportunistic science, not a new solver
development task.

## Don't Hand-Roll

- Do not invent a new optimizer for recovery. The point is to re-anchor old
  results with the existing trusted optimization path.
- Do not create a new plotting stack. `save_standard_set(...)` is already the
  project-standard sanity check.
- Do not hand-roll new MMF propagation utilities. Session C already produced the
  required wrappers and numerical checks.
- Do not infer recovered values from stored metadata alone when a `phi_opt`
  exists. Re-run the forward solve on the intended honest grid.

## Common Pitfalls

### Silent grid mutation

`scripts/common.jl::setup_raman_problem(...)` silently overrides undersized
windows. That behavior is correct for normal runs but wrong for a recovery
phase whose purpose is to make the sizing decision explicit. Use
`setup_longfiber_problem(...)` instead.

### Trusting `J_reported` without checking pulse containment

The audit result is clear: several dramatic dB numbers were obtained on grids
with 1–10% boundary energy. Recovery must gate on edge fraction before any dB
is accepted.

### Confusing “stationary on this grid” with “physically meaningful”

The Phase 13 hessian points are already a cautionary example: the saved
gradients are small on the old grid, but the old grid was still too small.

### Overusing full-resolution reruns when a low-dimensional basis exists

Sweep-1 is about the `N_phi` story. Re-anchoring it with full-grid
optimizations would answer a different question. Use the low-dimensional basis
machinery for the `N_phi < Nt` cases.

## External Literature Notes

### Pulse-on-grid / SSFM efficiency and accuracy

- Sinkin et al., *Journal of Lightwave Technology* 21 (2003), “Optimization of
  the Split-Step Fourier Method in Modeling Optical-Fiber Communications
  Systems,” compare step-size selection strategies and argue that numerical
  efficiency has to be evaluated against an explicit accuracy target rather than
  a one-size-fits-all heuristic. That supports Phase 21's choice to validate the
  actual recovered runs rather than assume the original grid was fine.
  Link: https://opg.optica.org/jlt/abstract.cfm?uri=jlt-21-1-61

- A 2025 *Optical Fiber Technology* paper on SSFM parameter efficiency in
  mode-locked fiber-laser simulation explicitly studies the impact of Fourier
  step size, time window, and time resolution, reinforcing that time-window and
  resolution choices are major simulation parameters, not incidental details.
  Link: https://www.sciencedirect.com/science/article/abs/pii/S1068520025002305

### Multimode propagation validation practice

- Wright et al., *Optics Express* 21 (2013), “Numerical solver for
  supercontinuum generation in multimode optical fibers,” present the standard
  MM-GNLSE solver workflow and explicitly verify the solver against the simplest
  multimode case before using it for broader physics claims.
  Link: https://opg.optica.org/abstract.cfm?uri=oe-21-12-14388

- Renninger and Wise, *Optics Express* 23 (2015), “Spatiotemporal dynamics of
  multimode optical solitons,” combine simulation and experiment and treat
  multimode nonlinear propagation as a phenomenon that must be checked against
  experimentally plausible structure, not only against solver output.
  Link: https://opg.optica.org/oe/fulltext.cfm?uri=oe-23-3-3492

## Prescriptive Recovery Guidance

1. Use a larger safety factor than the original sweep for window sizing.
   The existing formula in `recommended_time_window(...)` underpredicted the
   high-power `L=2 m, P=0.2 W` Sweep-1 family, so Phase 21 starts from a more
   conservative estimate and validates directly.
2. For Sweep-1, determine one honest grid for the whole `L=2 m, P=0.2 W`
   family by testing the flat pulse and all 7 stored warm-start phases.
3. For Phase 13, determine one honest grid per fiber config using the original
   `phi_opt` as the stress test.
4. For Session F 100 m, prefer schema normalization over expensive reruns
   because the stored run already satisfies the pulse-containment criterion.
5. For MMF aggressive, keep the scope to one scientifically meaningful run with
   the standard image set and edge checks; do not turn Phase 21 into a new MMF
   development phase.

## Confidence

- High confidence on the local codebase constraints and recovery workflow.
- Medium confidence on the exact “best” formula for minimum time window; that is
  why the phase uses formula + direct edge-fraction validation rather than a
  formula alone.

---

*Compiled 2026-04-20 for Phase 21 recovery work.*
