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
