# Phase 33 Research — Safeguarded second-order methods

The repo already has curvature-aware ingredients, but a real second-order
optimizer phase needs safeguarded steps, benchmark basins, and explicit trust
metrics. Without those, occasional lower dB values are numerically meaningless.

## Candidate globalization families

- backtracking line search
- trust-region control
- hybrid policies with explicit reject/fallback reporting
