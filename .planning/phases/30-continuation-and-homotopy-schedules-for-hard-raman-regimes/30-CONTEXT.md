# Phase 30 Context — Continuation and homotopy schedules

**Gathered:** 2026-04-20  
**Status:** Planned  
**Mode:** Autonomous seed promotion / phase-definition only

## Research Directive (BEFORE PLANNING OR EXECUTION)

The existing `RESEARCH.md` in this phase is a thin outline — a starting point, not a deliverable. Expand it substantially before touching `01-PLAN.md` or any code. Draw from:

- **CS 4220 numerical analysis class notes** — https://github.com/dbindel/cs4220-s26/ (every relevant lecture, assignment, topic)
- **Phase 27 numerics audit report** at `.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md`
- **Relevant seeds** in `.planning/seeds/`
- **Prior phase findings** — Phase 13 (Hessian landscape), Phase 22 (sharpness Pareto, all optima indefinite), Phase 28 (numerical trust framework), Phase 35 (saddle-escape verdict: minima only in uncompetitive dB, competitive regimes saddle-dominated)
- **External literature** — recent papers, standard textbooks, whatever the topic demands

The plan should reflect real understanding of the problem in THIS codebase, not generic template tasks. If `01-PLAN.md` as currently scaffolded is 3 generic bullets, rewrite it.

## Locked Decisions

- Continuation is treated as a numerical method, not an ad hoc warm-start habit.
- Candidate ladders include fiber length, power, basis size, and regularization.
- Every path must carry explicit failure detectors and trust metrics.
- Cold-start baselines are mandatory for hard-regime comparisons.
