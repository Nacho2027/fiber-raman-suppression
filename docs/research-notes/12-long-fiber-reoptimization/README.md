# Warm-Start Re-Optimization for Long-Fiber Raman Suppression

This note documents the long-fiber strategy where a short-fiber optimized phase
mask is transferred to a longer grid and then re-optimized on the long target.
It is intentionally shorter than the full long-fiber note because the central
idea is methodological: use a cheaper short solve to initialize the expensive
long solve.

## Status

- Compiled PDF: `12-long-fiber-reoptimization.pdf`
- Evidence status: provisional but important
- Main result: a 2 m warm-start mask evaluated at 100 m gives about `-51.50 dB`,
  and 100 m re-optimization improves to the mid-`-50 dB` range in current runs.
- Caveat: the 100 m re-optimized result is not yet a strict convergence claim.

## Included Figures

- Warm-start workflow diagram
- No-optimization 100 m evolution control
- 100 m re-optimized phase diagnostic
- 100 m re-optimized spectral evolution heat map

The figures are copied under public-facing filenames so the note does not expose
old internal milestone labels.
