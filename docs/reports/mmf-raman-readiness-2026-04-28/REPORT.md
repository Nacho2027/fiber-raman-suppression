# Multimode Raman Suppression Readiness Report

Date: 2026-04-28

## Executive Claim

The current MMF result is **presentation-ready as a qualified simulation
finding**:

> In an idealized six-mode GRIN-50 multimode model, shared spectral phase
> shaping can strongly reduce the simulated Raman-band fraction while passing
> corrected temporal-window diagnostics.

It is **not yet paper-ready as a broad experimental or universal MMF claim**.
The strongest current result is a constrained numerical candidate, not a
validated general law. The paper-ready path is now clear: finish grid
refinement, launch-composition sensitivity, and random-coupling/model-scope
checks.

## Literature Positioning

Relevant literature supports three facts that shape the claim.

1. GRIN MMF Raman dynamics are mode-resolved. Pourbeyram, Agrawal, and Mafi
   observed Raman cascades in GRIN MMF where Raman peaks appear in specific
   modes despite multimode pumping, so per-mode spectra are required for a
   credible MMF Raman result:
   https://arxiv.org/abs/1301.6203

2. Nonlinear GRIN MMF propagation can self-organize spatial content. Kerr
   self-cleaning and Raman beam-cleanup literature shows that low-order-mode
   concentration is physically plausible, but it depends on launch and coupling:
   https://arxiv.org/abs/1603.02972
   https://www.nature.com/articles/s41598-021-01491-0

3. Mode coupling and wavefront control are first-order variables, not details.
   Adaptive transverse phase shaping can steer self-cleaning into selected
   low-order modes, and random linear mode coupling can alter GRIN self-cleaning:
   https://arxiv.org/abs/1902.04453
   https://arxiv.org/abs/1908.07745

Numerical literature also justifies the temporal-window skepticism. Modern
pseudospectral fiber-propagation tools solve on a periodic temporal domain, so
edge energy can wrap and contaminate nonlinear propagation:
https://arxiv.org/abs/2104.11649

## Model And Objective

Current model:

- Fiber: `GRIN_50`, 50 um core, NA 0.2, parabolic GRIN, six scalar modes.
- Length and power for accepted candidate: `L=2.0 m`, `P=0.20 W`.
- Pulse: 1550 nm, 185 fs FWHM, default repo pulse setup.
- Control: one shared spectral phase `phi(omega)` applied across all modes.
- Default launch: LP01-dominant mode vector from
  `scripts/research/mmf/mmf_fiber_presets.jl`.
- Objective: minimize Raman-band fraction below `Delta f < -5 THz`.
- Accepted constrained surface: `10*log10(J_mmf_sum + lambda_gdd*R_gdd +
  lambda_boundary*R_boundary)`.

Important caveat: the current shared spectral phase is a temporal/spectral
control, not the same as a transverse SLM wavefront used in many MMF
self-cleaning experiments.

## Numerical Hygiene

The earlier `invalid-window` result was not dismissed. It was decomposed into
two separate issues:

- A diagnostic bug: MMF output-time diagnostics used `ifft(uomega)` even though
  the repo convention is `uomega = ifft(ut)` and `ut = fft(uomega)`.
- A real failure mode: after fixing the transform, the unregularized optimum
  still had about 5 percent temporal-edge energy, so it remained invalid.

The accepted result uses:

- raw temporal-edge diagnostics, not attenuator-recovered diagnostics;
- separate shaped-input and propagated-output edge fractions;
- mandatory standard image sets;
- mode-resolved spectra;
- GDD and boundary regularization in the best candidate.

Regression coverage:

- `test/phases/test_phase16_mmf.jl` covers the transform convention and the
  regularized MMF objective/gradient path.
- `scripts/research/mmf/mmf_window_validation.jl` exposes
  `MMF_VALIDATION_F_CALLS_LIMIT` and `MMF_VALIDATION_TIME_LIMIT_SECONDS`.
  `optimize_mmf_phase` also enforces the function-evaluation limit before each
  expensive MMF propagation call, because Optim.jl's own `f_calls_limit` is
  checked only after an iteration and can permit many line-search evaluations.

## Experiment Table

| ID | Settings | Result | Trust | Interpretation |
|---|---|---:|---:|---|
| E2 unregularized | `Nt=4096`, `TW=96 ps`, `lambda_boundary=0`, `lambda_gdd=0` | `-17.96 -> -45.07 dB` | edge `5.02e-2`, fail | reject as temporal-window artifact |
| E4 boundary | `Nt=4096`, `TW=96 ps`, `lambda_boundary=0.05`, `lambda_gdd=0` | `-17.96 -> -45.04 dB` | edge `2.74e-7`, pass | gain survives raw-edge penalty |
| E5 boundary+GDD | `Nt=4096`, `TW=96 ps`, `lambda_boundary=0.05`, `lambda_gdd=1e-4` | `-17.96 -> -49.69 dB` | edge `2.07e-11`, pass | strongest current candidate |
| E6 grid refinement | `Nt=8192`, `TW=96 ps`, same E5 penalties | inconclusive; best observed penalized objective plateaued near `-30.38 dB` | no final standard images; result archive did not sync after manual termination | not accepted; rerun with evaluation/time limits |

For E5, the diagnostic report also gives `J_fund=-49.65 dB` and
`J_worst=-45.35 dB`, so the improvement is not only hidden in the summed
detector objective.

## Figure Set

Current presentation figures:

- E5 phase/profile:
  `results/raman/phase36_window_validation_gdd/mmf_grin_50_l2m_p0p2w_seed42_phase_profile.png`
- E5 phase diagnostic:
  `results/raman/phase36_window_validation_gdd/mmf_grin_50_l2m_p0p2w_seed42_phase_diagnostic.png`
- E5 total spectrum:
  `results/raman/phase36_window_validation_gdd/mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_total_spectrum.png`
- E5 per-mode spectrum:
  `results/raman/phase36_window_validation_gdd/mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_per_mode_spectrum.png`
- E5 convergence:
  `results/raman/phase36_window_validation_gdd/mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_convergence.png`

These have been visually inspected. The E5 phase is physically less pathological
than the rejected result, but still contains engineered sub-ps to roughly
1.2 ps group-delay structure.

## Paper-Readiness Gate

A manuscript can honestly claim the following now:

- Corrected diagnostics reject the original boundary-artifact solution.
- Boundary and GDD regularization recover strong suppression in the same
  physical regime.
- The accepted candidate passes raw input/output temporal-edge tests and
  mode-resolved spectral inspection.

For a full research-paper claim, the grid-refinement gate remains open. The
first `Nt=8192`, `TW=96 ps` attempt found a comparable constrained basin but
did not exit cleanly or produce standard images, so it is not accepted evidence.

Do not claim yet:

- robustness to arbitrary MMF launch;
- robustness to random mode coupling;
- experimental feasibility of the exact spectral phase;
- a complete GMMNLSE model with many modes and random coupling;
- superiority over all SMF/multivar controls.

## Remaining Work To Be Paper-Grade

Required:

- Rerun E6 (`Nt=8192`, `TW=96 ps`) with explicit function-evaluation/time
  limits, for example
  `MMF_VALIDATION_F_CALLS_LIMIT=80 MMF_VALIDATION_TIME_LIMIT_SECONDS=10800`,
  and inspect its standard images.
- Add a small launch-composition sensitivity matrix: default, LP01-only,
  balanced low-order, and reduced LP01 launch.
- Run mode-coefficient gradient preflight now that MMF window trust passes.
- Add an explicit claim-boundary paragraph to any manuscript abstract.

Recommended:

- Add a reduced/smoothed phase-basis run to test whether the effect survives a
  simpler phase actuator.
- Add one randomized/degenerated-mode-coupling model or clearly state that the
  current model excludes random coupling.
- Compare against the best single-mode/multivar candidate with the same
  temporal-edge report format.

## Suggested Paper Abstract

We investigate whether spectral phase shaping can suppress simulated
Raman-band generation in a short graded-index multimode fiber. A six-mode
GRIN-50 model is optimized with adjoint gradients under an integrating
mode-summed Raman objective, with additional diagnostics for mode-resolved
Raman fractions and temporal-window contamination. An initial large-gain result
is rejected after corrected raw-edge diagnostics reveal boundary contamination.
After adding boundary and GDD penalties, the same physical regime shows a
31.7 dB reduction in Raman-band fraction at `L=2 m`, `P=0.20 W`, `Nt=4096`,
and `TW=96 ps`, with raw input/output edge fractions below `3e-11` and
suppression across the launched modes. A first `Nt=8192` refinement attempt
found a similar constrained optimization basin but did not complete with
standard artifacts. These results identify a plausible spectral-phase control
mechanism in an idealized GRIN-MMF model while motivating follow-up tests over
launch composition, bounded grid refinement, random mode coupling, and
phase-actuator constraints before experimental generalization.
