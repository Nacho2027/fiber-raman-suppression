# MMF Presentation Notes

Use one clean before/after pair and one caveat slide. The point is not that MMF
is solved; the point is that there is a plausible constrained candidate and a
clear list of remaining gates.

## Slide Hook

- Conservative headline: shared spectral phase reduced the summed Raman metric
  from `-17.37 dB` to `-41.25 dB` in the accepted high-resolution six-mode
  GRIN-50 simulation.
- Trust hook: the accepted run passed raw temporal-edge diagnostics with max
  edge fraction `3.59e-13`.
- Taste rule: show the rejected unregularized run briefly as the reason the
  trust gate matters, then show the accepted before/after pair.

## Caveat Slide

- This is simulation evidence, not a lab claim.
- Launch composition, random/degenerate coupling, and phase-actuator realism
  remain open gates.
- The optimized phase is a structured waveform, not yet a simple SLM-ready
  prescription.

Use the final `Nt=8192`, `TW=96 ps` run as the current evidence point:
`J_ref=-17.37 dB`, `J_opt=-41.25 dB`, improvement `23.88 dB`, and max edge
fraction `3.59e-13`. Keep the caveats explicit: launch sensitivity, random or
degenerate coupling, and phase-actuator realism are still open.
