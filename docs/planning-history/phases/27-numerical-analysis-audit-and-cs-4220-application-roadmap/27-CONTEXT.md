# Phase 27: Numerical analysis audit and CS 4220 application roadmap — Context

**Gathered:** 2026-04-20  
**Status:** Ready for execution  
**Mode:** Autonomous research + mapping only  
**Owner:** `sessions/numerics`

<domain>
## Phase Boundary

This phase is a numerical-analysis audit, not an implementation phase.
Its job is to study the current Raman-suppression codebase together with the
Cornell CS 4220 Spring 2026 course material, identify what numerics concepts
actually matter here, and turn that into a high-signal report plus future-phase
seeds.

The target is not "find clever math ideas in the abstract." The target is:
- what is numerically fragile in this project today,
- what the course material suggests doing differently,
- which items are small follow-ups versus phase-sized initiatives,
- and which apparent problems are already solved and should not be re-opened.

This phase therefore stays on the research / planning side of the boundary:
no refactors to `src/**`, no shared-utility rewrites, no optimizer replacement,
and no "drive-by" physics edits hidden inside the audit.

</domain>

<decisions>
## Locked Decisions

### D25-01: Research and mapping only
- Do not refactor `src/**`.
- Do not modify shared execution scripts such as `scripts/common.jl`,
  `scripts/visualization.jl`, or `scripts/raman_optimization.jl`.
- Deliverables are planning artifacts only: context, research, report, review,
  summary, roadmap/state updates, and seeds.

### D25-02: Use the Cornell CS 4220 material as the external numerics frame
- The external reference corpus is `https://github.com/dbindel/cs4220-s26`
  plus the published Cornell course site derived from it.
- The audit should cover the full course at a high level, but spend most depth
  on the topics that actually connect to this codebase:
  floating-point/error analysis, conditioning/scaling, regularization,
  Krylov/Lanczos, nonlinear solves, globalization, Gauss-Newton/Newton variants,
  continuation, and quasi-Newton ideas.

### D25-03: Distinguish "already fixed" from "still structurally missing"
- The audit must not recommend old fixes as if they are still open.
- Examples already handled and therefore treated as prior lessons:
  FFTW determinism, the dB/linear mismatch, the SPM time-window formula, and
  the Raman-response overflow.
- The value of this phase is to unify those lessons into a forward strategy,
  not to rediscover them.

### D25-04: Treat planning drift itself as a numerical-trust blocker
- If planning state points to missing files, stale statuses, or inconsistent
  execution records, that counts as a real blocker because it degrades trust in
  numerical claims and makes recovery/integration work error-prone.
- Document such drift explicitly in the report.

### D25-05: Plant seeds for phase-sized ideas only
- A seed belongs in `.planning/seeds/` only if it is large enough to deserve
  its own future phase with design and execution work.
- Smaller improvements stay in the report's recommended-actions section and do
  not get promoted to seeds automatically.

</decisions>

<canonical_refs>
## Canonical References

### External numerics corpus
- `https://github.com/dbindel/cs4220-s26`
- `https://www.cs.cornell.edu/courses/cs4220/2026sp/`

### Core local code paths
- `scripts/common.jl`
- `scripts/raman_optimization.jl`
- `scripts/determinism.jl`
- `scripts/phase13_hvp.jl`
- `scripts/phase13_hessian_eigspec.jl`
- `scripts/benchmark_threading.jl`
- `src/helpers/helpers.jl`
- `src/simulation/simulate_disp_mmf.jl`
- `src/simulation/sensitivity_disp_mmf.jl`
- `src/analysis/analysis.jl`

### Planning / audit context already in-repo
- `.planning/PROJECT.md`
- `.planning/STATE.md`
- `.planning/ROADMAP.md`
- `.planning/codebase/CONCERNS.md`
- `.planning/phases/21-numerical-recovery/21-RESEARCH.md`

</canonical_refs>

<specifics>
## Specific Questions This Phase Must Answer

1. Which CS 4220 topics have direct leverage on Raman-suppression optimization,
   and which are interesting but low-priority here?
2. What current problems are best understood as conditioning, scaling,
   globalization, regularization, or reproducibility failures?
3. What does the codebase already have in place that could be extended rather
   than replaced?
4. What future work should be broken into separate numerics phases?
5. What planning or workflow drift is currently making the numerical work
   harder to trust or integrate?

</specifics>

<deferred>
## Explicitly Deferred

- Any optimizer replacement or new numerical method implementation
- Shared-file cleanup outside `.planning/**`
- Re-running heavy compute campaigns just to support this audit
- Revising physics claims in papers/docs directly

</deferred>

---

*Phase: 25-numerical-analysis-audit-and-cs-4220-application-roadmap*  
*Context gathered: 2026-04-20 in autonomous audit mode*
