# Phase 28 Context — Conditioning and backward-error framework for Raman optimization

**Gathered:** 2026-04-20  
**Status:** Ready for execution  
**Mode:** Strict GSD execution (discuss --auto → plan → execute → verify)

## Phase Boundary

This phase turns the Phase 27 numerics-governance recommendation into a real,
execution-ready roadmap phase. The deliverable is not code in `src/**`; it is
the contract future numerical-method phases must satisfy before their results
are trusted.

## Locked Decisions

- The first implementation target is a reusable trust-report utility shared by
  optimization drivers and validation scripts.
- The framework must explicitly cover determinism, edge fraction before
  attenuation, energy drift, gradient-check status, and cost-surface coherence.
- Error taxonomy uses forward / backward / mixed error language rather than
  vague "looks stable" reporting.
- Phase 28's first execution slice is intentionally narrow:
  - create a reusable `scripts/numerical_trust.jl` utility,
  - wire the trust report into the canonical single-mode optimizer path in
    `scripts/raman_optimization.jl`,
  - align the heavy validation audit in `scripts/validation/validate_results.jl`
    to the shared thresholds,
  - add dedicated regression coverage under `test/`.
- Do not broaden this pass into amplitude, multivariable, or MMF-wide rollout.
  Those inherit the contract later once the canonical SMF path is stable.

## Canonical Inputs

- `.planning/seeds/numerics-conditioning-and-backward-error-framework.md`
- `.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-RESEARCH.md`
- `.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md`
- `scripts/common.jl`
- `scripts/raman_optimization.jl`
- `scripts/validation/validate_results.jl`
- `scripts/determinism.jl`
- `scripts/polish_output_format.jl`
- `test/test_phase27_numerics_regressions.jl`
