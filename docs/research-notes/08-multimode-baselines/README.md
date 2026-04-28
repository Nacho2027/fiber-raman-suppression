# Multimode Raman Baselines and Cost Choice

- status: `qualified simulation result / closed-exploring`
- evidence snapshot: `2026-04-28`

## Purpose

Document the accepted constrained GRIN-50 MMF simulation result, the rejected
temporal-window artifact, the current cost choice, and the evidence boundary
before anyone promotes MMF more broadly.

## Primary sources

- `docs/status/multimode-baseline-status-2026-04-22.md`
- `agent-docs/multimode-baseline-stabilization/SUMMARY.md`
- `scripts/research/mmf/baseline.jl`
- `scripts/research/mmf/mmf_raman_optimization.jl`
- `src/mmf_cost.jl`
- `docs/reports/mmf-raman-readiness-2026-04-28/REPORT.md`
- accepted MMF window-validation summary and standard images

## Generated tables in this directory

- none yet

## Verification

- The note uses real accepted/rejected MMF result images.
- The accepted result is the constrained boundary+GDD run:
  `-17.96 -> -49.69 dB`, edge fraction near `2e-11`.
- The unregularized result is explicitly rejected as temporal-window
  contaminated.
- Compile and visual-PDF inspection should be rerun after every substantive
  edit.

## Writing rule

Keep the note presentation-ready but narrow. The current defensible claim is an
idealized six-mode GRIN-50 simulation result, not generic experimental MMF Raman
suppression.
