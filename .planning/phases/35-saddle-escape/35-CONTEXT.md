# Phase 35: Saddle escape and genuine minima reachability study — Context

**Gathered:** 2026-04-20  
**Status:** Ready for execution  
**Mode:** Autonomous (`--auto` equivalent)

<domain>
## Phase Boundary

Phase 13 and Phase 22 already established the starting fact pattern:

- canonical full-resolution `phi_opt` points are Hessian-indefinite,
- sharpness-aware regularization did not turn the completed Phase 22 optima
  into positive-definite minima,
- and the open question is no longer "are these saddles?" but
  "do genuine minima exist anywhere near the physically relevant Raman-depth
  regime, and what algorithm would actually reach them if they do?"

This phase answers that by combining:

1. a **control-space Hessian ladder** on the existing low-resolution
   `N_phi` sweep for the SMF-28 canonical operating point
   (`L = 2 m`, `P = 0.2 W`),
2. a **negative-curvature escape study** from selected saddle points in that
   ladder,
3. and a **methods recommendation** grounded in both the project's evidence
   and the saddle-rich nonconvex optimization literature.

The deliverable is a report that states plainly whether genuine minima are:

- absent in reachable high-performance Raman territory,
- present but only after unacceptable depth degradation,
- or reachable with a practical escape method.

</domain>

<decisions>
## Locked Decisions

### Session namespace and file ownership

- New code lives only under `scripts/saddle_phase35_*`.
- New planning artifacts live only under
  `.planning/phases/35-saddle-escape`.
- Shared files remain read-only.

### Primary local dataset

- Use `results/raman/phase_sweep_simple/sweep1_Nphi.jld2` as the main local
  source for the SMF-28 canonical `N_phi` ladder.
- Analyze the control dimensions that are small enough for dense Hessians:
  `N_phi in {4, 8, 16, 32, 64, 128}` if present in the bundle.
- Use Phase 13 full-resolution Hessian findings as the production-space anchor
  rather than rerunning the 16384-dimensional canonical Hessian.

### Objective convention

- For geometry, use the same physical-loss Hessian convention as Phase 13:
  `log_cost = false` inside the Hessian oracle.
- For human-readable outcome comparison, report Raman suppression as
  `J_dB = 10 log10(J_plain)` recomputed post hoc.

### Reachability test design

- First question: for each `N_phi` baseline, is the Hessian in control space
  positive-definite, semidefinite, or indefinite?
- Second question: for the best-performing indefinite cases, perturb along the
  most negative eigenvector and re-run the original low-resolution optimizer.
- Third question: classify the destination as:
  - another saddle with similar `J_dB`,
  - a better saddle,
  - or a genuine local minimum with nonnegative Hessian.

### New optimization runs

- Any new run that produces a fresh `phi_opt` must call
  `save_standard_set(...)`.
- All Phase 35 standard images go under:
  `results/raman/phase35/images/`
- Tag convention:
  - `smf28_canonical_nphi64_escape_pos_a0p050`
  - `smf28_canonical_nphi64_escape_neg_a0p050`
  - etc.

### Methods comparison policy

- Treat saddle-free Newton as a literature reference point, not the default
  recommendation.
- Prefer methods with explicit negative-curvature handling and globalization:
  perturbed descent, trust-region / Newton-CG with negative-curvature
  detection, or cubic regularization.
- The report must distinguish:
  - "best method to diagnose the geometry,"
  - and "best method to actually deploy next in this repo."

### Advisor-meeting framing

- The advisor-facing narrative must state whether "we have not found minima
  yet" is still defensible.
- If minima only appear after large `J_dB` degradation or aggressive
  dimensional restriction, say so directly.
- If the competitive Raman solutions remain saddles, the narrative should be
  that the physically interesting operating region is saddle-dominated and
  needs explicit curvature-aware escape or basis restriction, not more plain
  L-BFGS restarts.

</decisions>

<canonical_refs>
## Canonical References

- `results/raman/phase13/FINDINGS.md`
- `.planning/phases/13-optimization-landscape-diagnostics-gauge-fixing-polynomial-p/13-01-SUMMARY.md`
- `.planning/phases/13-optimization-landscape-diagnostics-gauge-fixing-polynomial-p/13-02-SUMMARY.md`
- `.planning/phases/22-sharpness-research/22-CONTEXT.md`
- `.planning/phases/22-sharpness-research/22-RESEARCH.md`
- `.planning/phases/22-sharpness-research/SUMMARY.md`
- `.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md`
- `scripts/sweep_simple_param.jl`
- `scripts/phase13_hvp.jl`
- `scripts/phase13_hessian_eigspec.jl`
- `scripts/standard_images.jl`
- `results/raman/phase_sweep_simple/sweep1_Nphi.jld2`

</canonical_refs>

<success_criteria>
## Success Criteria

- The `N_phi` ladder is classified by Hessian sign structure in control space.
- At least one negative-curvature escape study is run on a competitive saddle.
- Every new `phi_opt` produced in Phase 35 has a full standard-image set.
- The final report gives a clear verdict on whether genuine minima are
  reachable in physically relevant `J_dB` territory.
- The report recommends a concrete next optimizer path for the repo and
  explains why.

</success_criteria>
