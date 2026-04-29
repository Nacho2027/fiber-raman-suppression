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

## Red flags

- Empty panels or single-color images.
- Axis labels that hide the plotted range.
- A plot that only proves the file exists.
- A claimed best point whose standard images were never opened.
