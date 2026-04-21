# Phase 26: Verification document bug reconciliation - Context

**Gathered:** 2026-04-20
**Status:** Ready for planning
**Source:** `docs/verification_document.tex` issue/advisory sections plus live code/doc grep

<domain>
## Phase Boundary

This phase reconciles the bug claims embedded in the verification document with the current repository state.

In scope:
- audit whether each documented bug is still open, resolved, or misstated
- patch stale or misleading prose in `docs/verification_document.tex`
- update roadmap/state to record the reconciliation pass
- plant seeds for implementation bugs that remain real but are too large for an inline docs pass

Out of scope:
- fully redesigning the adjoint to include the attenuator
- fixing the multivariable optimizer convergence path
- broad rewriting of all project docs beyond what is needed to reconcile the verification document

</domain>

<decisions>
## Implementation Decisions

### Decision 1
- Treat `Issue 2` (attenuator omitted from adjoint) as still open unless code evidence shows otherwise.

### Decision 2
- Treat `Issue 3` as a documentation-scope bug, not a missing-code bug, because the broader penalty family exists in other optimizer paths.

### Decision 3
- Fix stale summary language that still implies `Issue 1` is open.

### Decision 4
- Seed unresolved implementation work rather than forcing a risky physics-core edit inside a docs reconciliation pass.

</decisions>

<specifics>
## Specific Targets

- `docs/verification_document.tex`
- `.planning/ROADMAP.md`
- `.planning/STATE.md`
- `src/simulation/sensitivity_disp_mmf.jl`
- `scripts/raman_optimization.jl`
- `scripts/amplitude_optimization.jl`
- `scripts/multivar_optimization.jl`

</specifics>

<deferred>
## Deferred Ideas

- Carry the attenuator through the adjoint exactly or remove it from the forward model path used for optimization.
- Fix the multivariable optimizer preconditioning bug documented as W3.

</deferred>

---

*Phase: 26-verification-document-bug-reconciliation*
*Context gathered: 2026-04-20*
