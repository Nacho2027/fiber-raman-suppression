# Phase 31 Research — Reduced-basis phase models

Phase 27 reframed regularization as model selection. This phase therefore asks
which basis families deserve comparison against the current full-grid phase:

- polynomial chirp ladders
- DCT / band-limited bases
- spline-like smooth bases
- penalty-regularized full-grid baselines

The first implementation should reuse the repo's existing DCT machinery rather
than start from a greenfield reduced-basis library.
