# Presentation Deck: MMF Raman Suppression Readiness

Date: 2026-04-28

## Slide 1 - Title

**Spectral-phase control of Raman-band generation in a GRIN multimode fiber**

Subtitle: from invalid-window artifact to constrained MMF candidate.

## Slide 2 - One-Sentence Result

In a six-mode GRIN-50 simulation, boundary- and GDD-constrained spectral phase
optimization reduces the Raman-band fraction by **31.7 dB** while passing raw
temporal-edge diagnostics.

Speaker note: call this closed / exploring and a qualified simulation result,
not an experimental claim.

## Slide 3 - Why MMF Is Subtle

- Raman in GRIN MMF is mode-resolved.
- Kerr/Raman self-cleaning can concentrate energy in low-order modes.
- Launch composition and random mode coupling can change the outcome.
- A summed spectrum alone is not enough evidence.

## Slide 4 - Literature Anchor

- Pourbeyram/Agrawal/Mafi: Raman peaks in GRIN MMF appear in specific modes.
- Krupa et al.: GRIN MMF Kerr self-cleaning can reshape multimode beams.
- Deliancourt et al.: wavefront shaping can steer nonlinear self-cleaning.
- Sidelnikov et al.: random mode coupling affects GRIN self-cleaning.
- Melchert/Demircan: pseudospectral pulse propagation uses periodic temporal
  domains, so edge trust matters.

## Slide 5 - Model And Control

- `GRIN_50`: six scalar modes, 50 um core, NA 0.2.
- `L=2 m`, `P=0.20 W`, 1550 nm, 185 fs.
- Shared spectral phase `phi(omega)` across modes.
- Objective: Raman-band fraction below `Delta f < -5 THz`.
- Accepted run uses `lambda_boundary=0.05`, `lambda_gdd=1e-4`.

## Slide 6 - What Failed First

Show:

`results/raman/phase36_window_validation/mmf_grin_50_l2m_p0p2w_seed42_phase_diagnostic.png`

Message:

- Original large suppression was not accepted.
- Corrected transform diagnostic still found edge energy around 5 percent.
- This was a real temporal-window artifact.

## Slide 7 - Diagnostic Fix

- Repo convention: `uomega = ifft(ut)`, so recover time with `fft(uomega)`.
- Use raw temporal edges instead of attenuator-recovered edge estimates.
- Check both shaped input and propagated output.
- Keep standard image visual inspection mandatory.

## Slide 8 - Boundary-Constrained Recovery

Show:

`results/raman/phase36_window_validation_boundary/mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_total_spectrum.png`

Message:

- `-17.96 -> -45.04 dB`
- edge fraction `2.74e-7`
- suppression survives boundary regularization.

## Slide 9 - Best Candidate

Show:

`results/raman/phase36_window_validation_gdd/mmf_grin_50_l2m_p0p2w_seed42_phase_profile.png`

Message:

- `-17.96 -> -49.69 dB`
- `Delta=31.73 dB`
- edge fraction `2.07e-11`
- GDD penalty enabled.

## Slide 10 - Mode-Resolved Evidence

Show:

`results/raman/phase36_window_validation_gdd/mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_per_mode_spectrum.png`

Message:

- Suppression is visible in the launched modes.
- `J_fund=-49.65 dB`
- `J_worst=-45.35 dB`
- Not merely a summed-detector accounting artifact.

## Slide 11 - Remaining Skepticism

- Phase is engineered and oscillatory.
- Current model excludes random coupling.
- Launch is LP01-heavy by default.
- The optimizer seed is not a true multistart in this validation path because
  the run starts from `phi=0`.
- A first `Nt=8192`, `TW=96 ps` refinement attempt found a comparable
  constrained basin but did not complete with standard images.
- A bounded retry hit the `c3-highcpu-22` memory ceiling before producing
  standard images; larger-memory shapes were blocked by stock/quota.

## Slide 12 - Paper-Readiness Gate

Paper-grade claim after:

- E6 grid refinement is rerun on larger-memory compute, or after reducing
  solver memory use, with `MMF_VALIDATION_F_CALLS_LIMIT` /
  `MMF_VALIDATION_TIME_LIMIT_SECONDS` and images are inspected.
- launch sensitivity is measured;
- mode-coefficient preflight passes;
- random-coupling/model-scope limitation is explicitly stated.

## Slide 13 - Honest Claim

Claim:

> Spectral phase shaping suppresses Raman-band generation in an idealized
> GRIN-50 MMF simulation under strict temporal-edge diagnostics.

Not claim:

> Generic experimental Raman suppression in arbitrary multimode fibers.

## Slide 14 - Close

The MMF lane is no longer blocked by `invalid-window`. It has a credible
candidate and a clear validation ladder.
