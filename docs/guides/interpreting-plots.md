# Interpreting Plots

Use plots to check physics and artifacts, not just to decorate a report.

## Standard images

- `phase_profile`: input/output before-and-after phase comparison.
- `evolution`: optimized spectral evolution along the fiber.
- `phase_diagnostic`: wrapped phase, unwrapped phase, and group delay for
  `phi_opt`.
- `evolution_unshaped`: control run with no phase shaping.

## What to look for

- The optimized and unshaped evolutions should use comparable axes.
- The Raman band should be visibly reduced when the reported dB value improves.
- Phase diagnostics should not be blank, wrapped beyond recognition, or cropped
  into a misleading view.
- Sweep heatmaps should have labeled axes, clear units, and enough contrast to
  compare points.

For an OSA comparison, the upper panel is a display of independently area-
normalized shape; it is not absolute power. Gray regions are outside the
predeclared evaluation band. Downward triangles sit at the transformed
measurement upper limit, not at an arbitrary plotting floor. The lower panel
shows the linear area-normalized shape difference. Read the footer for the
assumed Gaussian RBW, its finite numerical support, censor-limit violations,
and the fact that no wavelength shift was fitted.

## Red flags

- Empty panels or single-color images.
- Axis labels that hide the plotted range.
- A plot that only proves the file exists.
- A claimed best point whose standard images were never opened.
- OSA metrics reported despite an unknown floor, censored evaluation samples,
  inadequate measurement sampling, or an unresolved simulation grid.
