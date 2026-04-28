# Trust-Region Newton Methods in a Saddle-Dominated Raman Landscape

- status: compiled outward-facing note
- evidence snapshot: `2026-04-26`

## Purpose

Explain the trust-region Newton and preconditioning research lane as a compact
technical companion note. The note focuses on the saddle geometry diagnosis,
cold-start radius-collapse result, gauge-safe preconditioning implementation,
continuation-assisted ladder evidence, and the final decision not to make this
the default Raman-suppression optimizer.

## Primary inputs

- trust-region implementation in `scripts/research/trust_region/`
- curvature and saddle-point explainer artifacts
- cold-start radius-sweep trust reports and standard images
- continuation-ladder summaries and standard images
- bounded preconditioning validation notes

## Included visual evidence

- clean Hessian sign summary
- trust-region workflow diagram
- cold-start radius-collapse summary
- no-optimization control phase diagnostic plus heat map
- cold-start collapse phase diagnostic plus heat map
- continuation seed phase diagnostic plus heat map
- no-preconditioner ladder phase diagnostic plus heat map
- dispersion-preconditioned ladder phase diagnostic plus heat map
- localized power-validation summary

## Verification Rule

After any edit, compile the PDF, render it to images, and visually inspect the
rendered pages. Do not rely on LaTeX success alone.
