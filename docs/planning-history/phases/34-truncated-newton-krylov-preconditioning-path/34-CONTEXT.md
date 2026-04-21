# Phase 34 Context — Truncated-Newton Krylov preconditioning

**Gathered:** 2026-04-20  
**Status:** Planned  
**Mode:** Autonomous seed promotion / phase-definition only

## Wait Directive (BEFORE EXECUTION)

**DO NOT start `/gsd-execute-phase` for this phase until Phase 33 has merged to `origin/main`.** Phase 33 produces the globalized second-order optimizer and the benchmark framework this phase's truncated-Newton/Krylov path extends. Poll `origin/main` for the Phase 33 integration commit (format: `integrate(phase33): ...`) every 15 min before beginning execution. Research and planning may proceed in parallel while you wait — in fact, use the wait window to do the deep research below.

## Research Directive (BEFORE PLANNING OR EXECUTION)

The existing `RESEARCH.md` in this phase is a thin outline — a starting point, not a deliverable. Expand it substantially before touching `01-PLAN.md` or any code. Draw from:

- **CS 4220 numerical analysis class notes** — https://github.com/dbindel/cs4220-s26/ (every relevant lecture, assignment, topic)
- **Phase 27 numerics audit report** at `.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md`
- **Relevant seeds** in `.planning/seeds/`
- **Prior phase findings** — Phase 13 (Hessian landscape), Phase 22 (sharpness Pareto, all optima indefinite), Phase 28 (numerical trust framework), Phase 35 (saddle-escape verdict: minima only in uncompetitive dB, competitive regimes saddle-dominated)
- **External literature** — recent papers, standard textbooks, whatever the topic demands

The plan should reflect real understanding of the problem in THIS codebase, not generic template tasks. If `01-PLAN.md` as currently scaffolded is 3 generic bullets, rewrite it.

## Locked Decisions

- This phase is matrix-free by default.
- HVP reuse from Phase 13 is mandatory.
- Preconditioning is part of the experiment design, not a deferred optional.
- Comparison baselines are L-BFGS and Phase 33's safeguarded second-order path.
