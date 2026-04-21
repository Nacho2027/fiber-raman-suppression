# Phase 32 Context — Extrapolation and acceleration

**Gathered:** 2026-04-20  
**Status:** Complete  
**Mode:** Autonomous seed promotion / phase-definition only

## Wait Directive (BEFORE EXECUTION)

**DO NOT start `/gsd-execute-phase` for this phase until Phase 30 has merged to `origin/main`.** Phase 30 produces the continuation infrastructure this phase's extrapolation and acceleration work builds on. Poll `origin/main` for the Phase 30 integration commit (format: `integrate(phase30): ...`) every 15 min before beginning execution. Research and planning may proceed in parallel while you wait — in fact, use the wait window to do the deep research below.

## Research Directive (BEFORE PLANNING OR EXECUTION)

The existing `RESEARCH.md` in this phase is a thin outline — a starting point, not a deliverable. Expand it substantially before touching `01-PLAN.md` or any code. Draw from:

- **CS 4220 numerical analysis class notes** — https://github.com/dbindel/cs4220-s26/ (every relevant lecture, assignment, topic)
- **Phase 27 numerics audit report** at `.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md`
- **Relevant seeds** in `.planning/seeds/`
- **Prior phase findings** — Phase 13 (Hessian landscape), Phase 22 (sharpness Pareto, all optima indefinite), Phase 28 (numerical trust framework), Phase 35 (saddle-escape verdict: minima only in uncompetitive dB, competitive regimes saddle-dominated)
- **External literature** — recent papers, standard textbooks, whatever the topic demands

The plan should reflect real understanding of the problem in THIS codebase, not generic template tasks. If `01-PLAN.md` as currently scaffolded is 3 generic bullets, rewrite it.

## Locked Decisions

- This phase only survives execution if it saves expensive solves without weakening trust.
- Candidate families come from continuation ladders and structured study grids.
- Acceleration is compared against naive warm-start chains, not against an idealized oracle.
- A "not worth it" verdict is an acceptable successful outcome.
