# Online Research Notes - MMF Raman / Window Trust

Date: 2026-04-27

## Sources

- Melchert & Demircan, `py-fmas`, arXiv:2104.11649:
  https://arxiv.org/abs/2104.11649
  - Relevant note: their ultrashort-pulse propagation package solves on a
    periodic temporal domain using pseudospectral methods. This supports the
    repo rule that temporal edge energy is not a cosmetic diagnostic; energy at
    the edge can wrap and contaminate nonlinear dynamics.
- RP Photonics, pulse propagation modeling:
  https://www.rp-photonics.com/pulse_propagation_modeling.html
  - Relevant note: fiber pulse models repeatedly switch between frequency
    domain for dispersion and time domain for nonlinear effects. This reinforces
    that transform-direction conventions must be explicit in diagnostics.
- RP Photonics, numerical beam propagation:
  https://www.rp-photonics.com/numerical_beam_propagation.html
  - Relevant note: grid ranges must comfortably contain the field; fields
    reaching numerical edges cause artifacts, and grid refinement/ladders are a
    standard trust check.
- Pourbeyram, Agrawal, Mafi, "Stimulated Raman scattering cascade spanning the
  wavelength range of 523 to 1750 nm using a graded-index multimode optical
  fiber", arXiv:1301.6203 / APL 102, 201107 (2013):
  https://arxiv.org/abs/1301.6203
  - Relevant note: in GRIN MMF, Raman peaks can be generated in specific modes
    despite highly multimode pump launch. Mode-resolved spectra are therefore
    not optional.
- Sidelnikov et al., "Random Mode Coupling Assists Kerr Beam Self-Cleaning in a
  Graded-Index Multimode Optical Fiber", arXiv:1908.07745:
  https://arxiv.org/abs/1908.07745
  - Relevant note: random linear mode coupling can materially change GRIN
    self-cleaning. This repo's deterministic fixed-mode model should not be
    overinterpreted as generic experimental MMF behavior until launch/coupling
    sensitivity is checked.
- Nature Communications, "Statistics of modal condensation in nonlinear
  multimode fibers":
  https://www.nature.com/articles/s41467-024-45185-3
  - Relevant note: their coupled-mode GNLSE simulations include chromatic
    dispersion, modal dispersion, Kerr/Raman nonlinearities, and random mode
    coupling; reported dynamics include temporal separation by modal dispersion,
    nonlinear compression, power transfer to lower-order modes, and Raman
    delayed soliton-like pulses concentrated in the fundamental. This supports
    diagnostics that track temporal output and per-mode power, not only summed
    Raman fraction.
- "Spatio-Temporal Dynamics of Pulses in Multimode Fibers", Photonics 2024:
  https://www.mdpi.com/2304-6732/11/7/591
  - Relevant note: mode-resolved experiments can use LP multiplexers to launch
    and separate modes. For this project, the `:fundamental`, `:worst_mode`,
    and per-mode reports are physically meaningful detector/launch variants,
    not just numerical variants.
- Krupa et al., "Spatial beam self-cleaning in multimode fiber", arXiv:1603.02972
  / Nature Photonics 11, 234-241 (2017):
  https://arxiv.org/abs/1603.02972
  - Relevant note: GRIN MMF nonlinear propagation can reshape a speckled
    multimode beam into a lower-order/fundamental-like spatial output through
    Kerr dynamics even without Raman/Brillouin scattering. For this project,
    LP01-heavy output is physically plausible, but it is also launch- and
    coupling-sensitive.
- Deliancourt et al., "Wavefront shaping for optimized many-mode Kerr beam
  self-cleaning in graded-index multimode fiber", arXiv:1902.04453 / Optics
  Express 27, 17311-17321 (2019):
  https://arxiv.org/abs/1902.04453
  - Relevant note: experiments used adaptive transverse phase shaping to steer
    nonlinear MMF self-cleaning into selected low-order modes. This supports
    treating input shaping as a real control variable, but their control is
    transverse spatial phase; this repo currently applies shared spectral phase
    across modes.
- Sidelnikov et al., "Random Mode Coupling Assists Kerr Beam Self-Cleaning in
  a Graded-Index Multimode Optical Fiber", arXiv:1908.07745 / Optical Fiber
  Technology 53, 101994 (2019):
  https://arxiv.org/abs/1908.07745
  - Relevant note: random linear coupling between modes materially affects
    GRIN self-cleaning, with degenerate-mode coupling giving reliable agreement
    with experiment in their study. A deterministic fixed-mode model should be
    described as an idealized controlled-launch model until random-coupling
    sensitivity is added.
- Melchert & Demircan, "A python package for ultrashort optical pulse
  propagation in terms of forward models for the analytic signal",
  arXiv:2104.11649 / Computer Physics Communications 273, 108257 (2022):
  https://arxiv.org/abs/2104.11649
  - Relevant note: modern ultrashort-pulse propagation codes still solve on a
    periodic temporal domain when using pseudospectral methods. This directly
    supports the boundary/edge-fraction diagnostic used here and argues against
    accepting any result whose field reaches the temporal edge.
- RP Fiber Power example, "Stimulated Raman Scattering in a Multimode Fiber":
  https://www.rp-photonics.com/rp_fiber_power_demos_srs_mm.html
  - Relevant note: even beam-propagation models that do not solve directly in a
    modal basis still report mode powers via overlap integrals. This reinforces
    that summed spectra are insufficient for MMF Raman claims.

## Immediate Takeaways For This Repo

- The existing `boundary_ok=false` result could not be accepted, but the first
  code-level finding is a diagnostic bug: the MMF trust path used `ifft(uωf, 1)`
  even though this codebase stores `uω = ifft(ut)` and recovers time with
  `fft(uω, 1)`.
- The MMF trust path also used the legacy attenuator-recovery check. The
  repository docs for `check_boundary_conditions` already warn that optimization
  trust reports should prefer `check_raw_temporal_edges` to avoid amplifying
  harmless edge roundoff.
- After fixing diagnostics, the minimum defensible rerun is the exact completed
  threshold case (`L=2 m`, `P=0.20 W`, `Nt=4096`, `TW=96 ps`, `max_iter=4`) to
  separate "false invalid-window" from true boundary ejection.
- If raw-edge trust passes, the next scientific issue is not just window size:
  run a ladder over objective/regularization choices and mode views:
  `:sum`, `:fundamental`, `:worst_mode`, GDD/boundary regularized phase, and
  launch coefficients.
- If raw-edge trust fails even after the transform fix, do not optimize mode
  coefficients yet. The objective must be reformulated or constrained so the
  optimizer cannot win by temporal ejection.
- Literature framing for the current E5 candidate should be conservative:
  "spectral phase shaping in an idealized GRIN-50 multimode model suppresses
  the simulated Raman-band fraction under strict temporal-edge diagnostics."
  Do not claim experimental Raman suppression in generic MMF until launch
  composition, random mode coupling, and model fidelity are tested.
- A paper/presentation should explicitly separate three layers of evidence:
  1. numerical hygiene: transform convention, raw temporal edges, standard
     images, and grid/refinement checks;
  2. physical plausibility: GRIN Raman beam cleanup, Kerr self-cleaning, and
     mode-resolved output diagnostics;
  3. open generality: launch weights, random coupling, more modes, and
     experimental phase-realization constraints.
