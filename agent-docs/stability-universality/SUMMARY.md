---
topic: stability-universality
status: summary
created: 2026-04-23
---

# Stability And Universality Summary

## Short Answer

A "good" Raman-suppression phase profile is not just the one with the lowest `J_dB`. For this project, a good profile should be:

- honest: no time-window, attenuator, drift, or objective-scale artifact
- simple: describable after removing constant phase and linear group delay
- robust: survives phase noise, pixelation, smoothing, and finite shaper resolution
- transferable: still helps under small changes in length, power, pulse width, dispersion, or fiber
- interpretable: changes propagation in a visible physical way, such as stretching the pulse, lowering peak power, delaying compression/fission, or suppressing Raman-band growth along `z`
- reproducible: specified compactly enough that another group could test it

The project now has evidence for multiple useful classes, not one universal winner.

## Undergrad-Level Synthesis

The input spectral phase tells each color in the pulse when to arrive. A flat phase makes the shortest pulse, which has high peak power. High peak power makes nonlinear fiber effects strong, including Raman transfer to longer wavelengths. If we add phase curvature, the pulse stretches in time. That lowers peak intensity and changes where the pulse compresses during propagation.

That is why a simple chirp can help: it is like spreading the same pulse energy over a longer time so the fiber sees a less violent pulse. But this project has also found that the deepest suppression often needs more than a pure chirp. Some good profiles have local structure that a global polynomial cannot explain. That structure may time different parts of the spectrum so Kerr broadening, dispersion, and Raman response do not reinforce each other in the Raman band.

The scientific problem is deciding which structures are real. A jagged full-grid phase can lower the simulated Raman band, but if it fails after 0.05 rad of phase noise, or only works at one exact fiber length and power, it is probably a numerical or optimizer-specific mask. A phase that is a little shallower but simple, stable, and transferable may be more publishable.

## Literature Context

The fiber-optics literature supports the main mechanisms:

- Gordon's 1986 theory of soliton self-frequency shift shows Raman effects red-shift soliton pulses and depend strongly on pulse width. Shorter, stronger pulses are more vulnerable. Source: <https://opg.optica.org/abstract.cfm?uri=ol-11-10-662>
- Mitschke and Mollenauer experimentally discovered soliton self-frequency shift in 1986. Source: <https://www.scirp.org/reference/referencespapers?referenceid=579262>
- Dudley, Genty, and Coen's supercontinuum review connects anomalous-dispersion femtosecond propagation to soliton fission, stimulated Raman scattering, dispersive waves, and coherence/stability. Source: <https://journals.aps.org/rmp/abstract/10.1103/RevModPhys.78.1135>
- Strickland and Mourou's chirped-pulse amplification work is the classic example of using spectral phase to stretch pulses and reduce damaging nonlinear effects before recompression. Source: <https://doi.ericoc.com/?doi=10.1016%2F0030-4018%2885%2990120-8>
- Weiner's femtosecond pulse-shaping review grounds the hardware reality: finite-pixel SLMs, phase-only masks, wrapping, and calibration error matter. Source: <https://engineering.purdue.edu/~fsoptics/articles/Femtosecond_pulse_shaping-Weiner.pdf>
- Recent and related chirp-control work shows pre-chirp can tune soliton self-frequency shift or soliton fission, so testing GDD/TOD/FOD families is physically justified. Sources: <https://opg.optica.org/ol/upcoming_pdf.cfm?id=551176> and <https://opg.optica.org/abstract.cfm?uri=cleo-2005-CWC7>

No cited source proves this repo's exact phase-only Raman-suppression result. The useful literature message is narrower: chirp and spectral phase are credible physical control levers, and robustness/implementability must be part of the claim.

## Existing Profiles: Promising Versus Fragile

### Promising: low-order polynomial / quadratic chirp

Phase 31 polynomial `N_phi = 3` reached only `-26.50 dB`, but transferred almost unchanged to HNLF, with an HNLF gap near `+0.29 dB`. This is the best simple, interpretable, fiber-transferable baseline.

Use it as the "universal simple mechanism" reference, not as the deepest result.

### Promising but local: cubic reduced-basis continuation

Phase 31 cubic `N_phi = 128` reached `-67.60 dB`, and `cubic32 -> full-grid` reached `-67.16 dB`. This proves reduced-basis continuation can access a deep full-grid basin that zero-start full-grid L-BFGS misses.

The problem is robustness: `sigma_3dB` is about `0.07 rad`, and HNLF transfer gaps are about `+21 dB`. This is a strong canonical result, not a universal fixed mask yet.

### Useful as prior, not fixed mask: Phase 17 simple phase

The Phase 17 simple phase reached `-76.862 dB`, but `sigma_3dB = 0.025 rad`. Direct transfer failed; reoptimization from that profile succeeded broadly.

Treat it as an initialization prior and a clue about nearby basins, not as an experimentally robust universal mask.

### Scientifically interesting but unsettled: 100 m long-fiber phase

The Phase 16 100 m result reached `-54.77 dB`, while flat phase was only `-0.20 dB`. Its weighted quadratic fit had `R^2 = 0.015`, so pure GVD compensation is not an adequate explanation.

This could be publishable nonlinear structural adaptation, but it needs multistart and stability checks before making that claim.

### Probably not useful as final masks

Full-grid zero-start saddle optima are useful landscape diagnostics but not good final candidates unless they pass smoothing, quantization, and transfer tests. High-penalty Branch B degenerates that collapse toward `phi approx 0` should not be counted as Raman-suppression profiles. Any deep profile with tiny `sigma_3dB` should be considered fragile until proven otherwise.

## Proposed Simple Phase Families

Test these families before inventing more optimizer machinery:

1. `GDD only`: one quadratic coefficient after gauge removal. Baseline for pulse stretching.
2. `GDD + TOD`: quadratic plus cubic. Tests whether third-order timing can compensate asymmetric spectra or fiber `beta3`.
3. `GDD + TOD + FOD`: low-order polynomial through fourth order. Still experimentally interpretable.
4. `chirp ladder`: a small family of analytically chosen chirps around dispersion-length and nonlinear-length scales.
5. `piecewise-linear group delay`: simple local timing with bounded slope; closer to what cubic/linear bases seem to exploit.
6. `low-k DCT residual on top of GDD`: chirp core plus a few smooth global corrections.
7. `localized spline bumps on group delay`: chirp core plus one or two smooth local features near the active spectral band.
8. `wrapped hardware masks`: same families after finite-pixel, finite-bit, wrapped-phase constraints.

The most important comparison is not "which family reaches the lowest native `J`?" It is "which family stays useful after transfer, perturbation, and smoothing?"

## Concrete Stability Tests

Run these on saved profiles first:

1. Fixed-mask transfer matrix across `L`, `P`, FWHM, `beta2`, and HNLF.
2. Hardware perturbations: Gaussian phase noise, finite pixels, finite bit depth, phase wrapping, and smoothing.
3. Gauge-fixed complexity audit: polynomial `R^2`, DCT concentration, group-delay total variation, curvature, stationary points.
4. Low-pass survival: truncate DCT modes or resample splines and see when `J` collapses.
5. Propagation diagnostics: peak power, temporal width, spectral centroid, Raman-band energy versus `z`.
6. Warm-start versus fixed-mask comparison: does the profile transfer as a mask or only as a starting guess?
7. Ambient Hessian/negative-curvature probe only for finalists.

`NEXT_TESTS.md` has a concrete candidate panel and pass/fail framing.

## Recommended Ranking Today

| Use case | Best current pick | Why |
|---|---|---|
| simple publishable mechanism | Phase 31 polynomial `N_phi = 3` | chirp-like, transferable, robust, shallow |
| deepest canonical profile | Phase 31 cubic `N_phi = 128` or `cubic32 -> full-grid` | deepest documented branch, but local |
| robust-ish compromise | Phase 31 cubic `N_phi = 32` before full-grid polish | less deep but wider basin than cubic128 |
| warm-start prior | Phase 17 simple phase | bad fixed transfer, strong reoptimization seed |
| long-fiber physics hypothesis | Phase 16 100 m profile | strong non-quadratic suppression, needs validation |

## Bottom Line

The likely publishable story is not "we found one magic phase mask." It is:

1. low-order chirp gives a transferable first-order suppression mechanism;
2. local, piecewise-smooth phase structure unlocks much deeper suppression in a specific regime;
3. the deepest profiles are narrow and saddle-rich, so robustness and universality must be reported as separate axes;
4. the next experiments should identify the simplest phase family that survives hardware and transfer tests, even if it gives up some dB.

