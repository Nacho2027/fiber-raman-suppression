# Phase 23 — Matched Quadratic-Chirp 100m Baseline Research

**Researched:** 2026-04-20  
**Status:** Ready for execution  
**Owner:** Session `M-matched100m`

## Summary

Audit §S5 identified a specific interpretive gap in Session F's 100 m result:
the measured warm-start transfer `J = -51.50 dB` may be mostly the effect of
launching any sufficiently strong dispersive pre-chirp, rather than evidence
that the detailed non-quadratic `phi_opt` structure transfers across a 50×
length increase. Phase 23 exists to settle that point with a controlled
baseline.

The governing physics is straightforward. At `L = 100 m`, `P_cont = 0.05 W`,
and SMF-28 `β₂ < 0`, the propagation is strongly dispersion-dominated on the
simulation-length scale. A large input quadratic spectral phase broadens the
pulse temporally before substantial nonlinear phase accumulates, which lowers
peak power and can suppress Raman-band energy transfer simply by keeping the
pulse below the effective nonlinear threshold over much of the fiber. That
means a generic quadratic chirp is a serious null model and cannot be skipped.

The right comparison is not "does a quadratic fit explain `phi_opt(ω)`?" The
audit already showed the low-order polynomial fit is misspecified (`R² ≈ 0.02`
on the signal band). The right comparison is operational: can a pure quadratic
phase, tuned to produce a similar broadening / peak-power trajectory, reproduce
roughly the same `J_dB` and qualitative spectral evolution at 100 m?

## Theory Expectations

1. In anomalous-dispersion fiber, a strong imposed quadratic chirp can delay or
   weaken pulse compression / soliton formation by stretching the pulse at the
   input. If the nonlinear response depends mainly on instantaneous peak power,
   that alone can dramatically reduce Raman generation.
2. If the warm-start advantage is mostly this generic pre-chirp effect, a
   matched quadratic chirp should land within a few dB of the warm-start's
   `-51.50 dB`, and its `P(z)` and spectral-evolution plots should look
   qualitatively similar.
3. If detailed non-quadratic phase structure is doing real work, the best
   matched quadratic should still be materially worse even after matching
   broadening metrics; the divergence should show up in both endpoint `J_dB`
   and the evolution overlay.
4. Because Phase 16 used `Nt = 32768`, `T = 160 ps`, and achieved
   `BC edge fraction = 7.53e-07` for the warm-start validation, Phase 23 must
   stay on an equally honest or stricter grid. Phase 18's trust criterion is
   `< 1e-3`; the Phase 21/23 session framing tightens the practical target to
   `< 1e-3` and preferably well below that before drawing conclusions.

## Experiment Design

### Primary comparison

- Reproduce the Session F warm-start forward run at `L = 100 m` from the stored
  `phi_opt@2m` seed, using the long-fiber wrapper and standard-image set.
- Construct a pure quadratic phase
  `φ_quad(ω) = 0.5 * a₂ * (ω - ω_ref)^2`, centered on the simulation carrier.
- Choose `a₂` by one of two acceptable methods:
  - Preferred: coarse threaded sweep over `a₂` and select the chirp that best
    matches the warm-start's peak-power trajectory `P(z)` or an equivalent
    broadening metric.
  - Fallback: directly fit `a₂` so a scalar trajectory metric
    (peak-power suppression, temporal RMS width, or `P(z)` least squares)
    matches the warm-start run.
- Propagate the selected quadratic baseline at the same 100 m configuration.

### Verdict thresholds

- `|J_quad_dB - J_warm_dB| <= 3 dB`: the S5 "structural adaptation" framing
  fails; the effect is mostly generic dispersive pre-chirp.
- `J_quad_dB` worse by `>= 10 dB`: S5 survives; non-quadratic structure matters.
- Intermediate gap: partial explanation; the honest wording is
  "pre-chirp explains a large part, but not all, of the transfer."

### Required observables

- Endpoint `J_dB` for warm-start and quadratic baseline.
- Boundary-condition edge fraction and energy drift for both runs.
- A `P(z)`-style comparison metric used to define the "matched" quadratic.
- Standard image sets for:
  - warm-start rerun
  - best matched quadratic
  - each sweep point, if the sweep route is used
- One overlay figure directly comparing warm-start and matched-quadratic
  spectral evolutions.

## Risks And Interpretation Traps

1. Matching only endpoint `J_dB` is not enough. A quadratic chirp could win or
   lose accidentally for the wrong dynamical reason, so the evolution overlay
   and broadening metric are part of the acceptance condition.
2. A direct polynomial fit to `phi_opt` is not the right baseline selector.
   Audit W1 already showed the warm-start phase is mostly non-quadratic on the
   signal band, so projection coefficients alone are not physically decisive.
3. The chosen grid must remain trusted. If a candidate quadratic chirp pushes
   edge fraction upward, that candidate cannot be used for the verdict until
   the run is repeated on a larger window.
4. The comparison should stay on the same fiber model as the audited claim:
   SMF-28, `β_order = 2`, `L = 100 m`, `P_cont = 0.05 W`.

## Practical Recommendation

- Use Session F's `scripts/longfiber_setup.jl` and standard-image workflow as
  the numerical backbone.
- Prefer the coarse `a₂` sweep, because it is robust to the trajectory not
  being exactly quadratic-compatible and parallelizes cleanly over 8 threads.
- Select the final quadratic by minimizing a trajectory mismatch metric first,
  then report its `J_dB` honestly against `-51.50 dB`.
- If the best quadratic unexpectedly beats the warm-start, extend the sweep and
  test both chirp signs before finalizing the verdict.
