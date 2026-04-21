# Phase 25: Project-wide bug squash and concern triage - Context

**Gathered:** 2026-04-20
**Status:** Ready for planning
**Source:** Autonomous bug audit from `.planning/STATE.md`, `.planning/codebase/CONCERNS.md`, and live code grep

<domain>
## Phase Boundary

This phase is a bug-squash pass, not a redesign sprint.

In scope:
- confirm which reported issues are still real
- patch low-risk correctness bugs in live code
- remove dead files that are no longer part of the runtime
- fix stale planning/docs that now mislead future sessions
- add regression coverage for any bug fixed here
- plant seeds for structural hazards that are too large or risky for an inline bug fix

Out of scope:
- refactoring the `fiber` / `sim` Dict architecture
- removing `PyPlot` from the core module in the same pass
- adding CI, new dependencies, or large workflow changes
- forcing heavy numerical runs just to satisfy documentation cleanup

</domain>

<decisions>
## Implementation Decisions

### Scope control
- Prefer code changes that are obviously correct from local context and can be verified by the fast tier.
- If an item is really architectural debt rather than a localized bug, do not patch around it. Seed it.

### Verification bar
- Run `julia --project=. test/tier_fast.jl` after patching.
- If tests fail because the environment is not instantiated, run `Pkg.instantiate()` and retry before judging the patch.

### Documentation policy
- Historical phase summaries may keep historical references.
- Canonical living docs (`STATE.md`, `ROADMAP.md`, `CLAUDE.md`, `.planning/codebase/*.md`) should be updated when they are objectively stale.

### the agent's Discretion
- Choose the smallest useful set of fixes rather than maximizing diff size.
- Ignore “missing standard images” claims for scripts that only post-process existing `phi_opt` data.

</decisions>

<specifics>
## Specific Audit Targets

- `src/simulation/simulate_disp_mmf.jl`
- `src/simulation/simulate_disp_gain_mmf.jl`
- `src/simulation/simulate_disp_gain_smf.jl`
- `scripts/phase15_benchmark.jl`
- `test/tier_fast.jl`
- `.planning/STATE.md`
- `.planning/codebase/CONCERNS.md`
- `.planning/codebase/STRUCTURE.md`
- `.planning/codebase/ARCHITECTURE.md`
- `CLAUDE.md`

</specifics>

<deferred>
## Deferred Ideas

- Thread-safe `fiber` handling without caller-side `deepcopy(fiber)`
- Removing `PyPlot` from `src/MultiModeNoise.jl`
- CI automation for the fast tier

</deferred>

---

*Phase: 25-project-wide-bug-squash-and-concern-triage*
*Context gathered: 2026-04-20*
