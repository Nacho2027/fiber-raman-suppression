---
title: Independent numerics audit — second-opinion pass on Phase 25
status: complete
created: 2026-04-20
branch: sessions/numerics
---

# Quick Task 260420-oyg — Summary

## Goal

Deliver a skeptical, code-verified second opinion on Phase 25's numerical
audit, update the Phase 25 docs in place, plant new seeds for phase-sized
gaps, and rank the numerical risks and next steps.

Working directory: `/home/ignaciojlizama/raman-wt-numerics` (branch
`sessions/numerics`). No `src/**` edits. Docs + seeds only.

## What was done

1. **Read** Phase 25 artifacts (`25-CONTEXT.md`, `25-01-PLAN.md`,
   `25-RESEARCH.md`, `25-REPORT.md`, `25-REVIEWS.md`, `SUMMARY.md`) and all
   seven existing seeds under `.planning/seeds/`.

2. **Verified** Phase 25 claims against actual code: `scripts/common.jl`,
   `scripts/raman_optimization.jl`, `scripts/amplitude_optimization.jl`,
   `scripts/determinism.jl`, `scripts/phase13_hvp.jl`,
   `scripts/phase13_hessian_eigspec.jl`, `scripts/benchmark_threading.jl`,
   `src/simulation/simulate_disp_mmf.jl`,
   `src/simulation/sensitivity_disp_mmf.jl`, `src/helpers/helpers.jl`,
   `src/analysis/analysis.jl`. Full code audit trail in
   `260420-oyg-NOTES.md` — every Phase 25 headline claim tied to file:line.

3. **Wrote second-opinion addenda** into the four Phase 25 docs:
   - `25-REPORT.md` — added per-topic "what Phase 25 got right / missed /
     misframed", specific code-verified defects (chirp sensitivity bug,
     cost-surface incoherence, absorbing-boundary mass loss, ODE abstol,
     FD-HVP ε), and the three required rankings (top 5 risks, top 5
     improvements, single most important next phase).
   - `25-RESEARCH.md` — topic-by-topic crosswalk refinements with file:line
     citations, two new failure modes, five updated prescriptive items,
     refreshed confidence levels.
   - `25-REVIEWS.md` — raised overall risk LOW-MEDIUM → MEDIUM, added
     two new MEDIUM concerns, refined globalization framing.
   - `SUMMARY.md` — top-level ranking plus pointer to the new seeds.

4. **Planted two new seeds**:
   - `.planning/seeds/cost-surface-coherence-and-log-scale-audit.md` —
     fixes the defect where `cost_and_gradient`, `phase13_hvp::build_oracle`,
     regularizers, and `chirp_sensitivity` each differentiate a different
     cost surface; folds in the latent `lin_to_dB`-on-dB bug and the
     missing Taylor-remainder-2 slope test.
   - `.planning/seeds/absorbing-boundary-and-honest-edge-energy.md` —
     treats the super-Gaussian attenuator as a tracked absorbing boundary,
     adds running edge-absorption telemetry, investigates PML alternatives.

5. **Did NOT touch**: any `src/**` file, any `scripts/common.jl` or other
   shared script, `.planning/ROADMAP.md`, any other phase's docs, or any
   existing seed file.

## Top-level findings

### Top 5 numerical risks (code-verified)
1. Cost-surface incoherence across optimizer / HVP / regularizer / diagnostic paths.
2. Super-Gaussian attenuator silently absorbs edge energy; no running metric.
3. `plot_chirp_sensitivity` applies `lin_to_dB` to values already in dB (DomainError).
4. Planning drift (unchanged from Phase 25).
5. Scaling / conditioning of full-grid φ with mixed-unit `sim` dict
   (`helpers.jl:51-57`).

### Top 5 highest-leverage improvements
1. Cost-surface coherence + log-scale unification.
2. Extend DCT reduced-basis from amplitude to phase (infrastructure
   already exists at `amplitude_optimization.jl:180-209`).
3. Trust-report bundle with edge-absorption metric + condition-number probe.
4. Adaptive FD-HVP step `ε = sqrt(eps_mach · ‖∇J‖) / ‖v‖`.
5. Taylor-remainder-2 slope tests across all gradient-validation paths.

### Single most important next numerics phase

**Numerical-governance bundle** — a refinement, not replacement, of
Phase 25's `numerics-conditioning-and-backward-error-framework` seed,
explicitly scoped to include:
(a) log / linear cost convention unification across all gradient paths;
(b) adaptive FD-HVP ε;
(c) running edge-absorption metric;
(d) per-run condition-number probe reusing Arpack;
(e) Taylor-remainder-2 slope tests.

Without this bundle, truncated-Newton / sharpness / globalization phases
will compare methods on an unstable objective surface.

## Artifacts produced / modified

- `.planning/phases/25-*/25-REPORT.md` (addendum appended)
- `.planning/phases/25-*/25-RESEARCH.md` (addendum appended)
- `.planning/phases/25-*/25-REVIEWS.md` (addendum appended)
- `.planning/phases/25-*/SUMMARY.md` (addendum appended)
- `.planning/seeds/cost-surface-coherence-and-log-scale-audit.md` (new)
- `.planning/seeds/absorbing-boundary-and-honest-edge-energy.md` (new)
- `.planning/quick/260420-oyg-.../260420-oyg-PLAN.md`
- `.planning/quick/260420-oyg-.../260420-oyg-NOTES.md` (full audit trail)
- `.planning/quick/260420-oyg-.../260420-oyg-SUMMARY.md` (this file)
- `.planning/STATE.md` — Quick Tasks Completed row appended

Total new content: ~2000 lines of markdown additions; zero `src/**`
changes.

## Verification (self-check against must_haves in PLAN.md)

- [x] Every claim in the addenda cites a specific file:line or is
      explicitly marked as a framing observation.
- [x] Addenda are appended as `Second-Opinion Addendum (2026-04-20)`
      sections in all four Phase 25 docs (grep confirms: 4/4).
- [x] Each of the user's nine named concern areas (conditioning,
      scaling, backward-vs-forward error, globalization, Newton /
      Krylov / preconditioning, FFT-aware numerics, continuation,
      extrapolation, performance modeling) has a verdict.
- [x] No duplicate seeds — the two new seeds are orthogonal to the
      existing seven.
- [x] Final ranking block present in `25-REPORT.md` and `SUMMARY.md`.
- [x] `src/**` untouched (verified by scope review; no Edit or Write
      calls touched anything outside `.planning/`).

## Status

**Complete.** Ready for commit.
