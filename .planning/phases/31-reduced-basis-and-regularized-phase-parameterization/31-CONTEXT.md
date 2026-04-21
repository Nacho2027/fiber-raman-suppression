# Phase 31 Context — Reduced-basis and regularized phase parameterization

**Gathered:** 2026-04-20  
**Status:** Complete  
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

- This phase extends existing basis infrastructure before inventing new basis code.
- The amplitude DCT path is the first reuse target for phase reduction.
- Explicit basis restriction and penalty-based regularization are compared, not conflated.
- Interpretability, robustness, and transferability matter as much as best dB.
