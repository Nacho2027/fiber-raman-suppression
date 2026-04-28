# Cost Audit, Numerics Coherence, and Trust Diagnostics

- status: `production-ready methodology note; audit matrix incomplete`
- compiled note: `05-cost-numerics-trust.pdf`
- evidence snapshot: `2026-04-26`

## Purpose

This note is the methods backbone for the research-note series. It explains the Raman cost function, objective-scale convention, gauge fixing, trust-report gates, standard-image requirements, and what remains missing from the cost-audit evidence matrix.

## Primary Sources

- `agent-docs/current-agent-context/NUMERICS.md`
- `agent-docs/current-agent-context/METHODOLOGY.md`
- `scripts/lib/raman_optimization.jl`
- `scripts/lib/objective_surface.jl`
- `scripts/research/analysis/numerical_trust.jl`
- `scripts/research/cost_audit/cost_audit_driver.jl`
- `scripts/lib/standard_images.jl`
- numerics regression tests under `test/`

## Local Assets

- `tables/cost_audit_summary.csv`
- `tables/cost_audit_summary.md`
- `tables/cost_audit_gaps.md`
- `figures/*`

## Quality Bar

The PDF should compile cleanly, avoid internal milestone labels, include a no-optimization control, pair each representative phase diagnostic with its corresponding heat map, and state missing evidence explicitly.

This note is allowed to remain audit-matrix-incomplete because that is a
scientific status, not a document-quality problem. Future edits should preserve
that distinction.
