# Lab-Readiness Transition Context

## Task

Define what "lab-ready" should mean for this repository, assuming the highest-
value science lanes should still be finished before the lab depends on the repo
as shared instrument software.

## Files reviewed

- `AGENTS.md`
- `CLAUDE.md`
- `README.md`
- `scripts/README.md`
- `docs/architecture/output-format.md`
- `docs/synthesis/recent-phase-synthesis-29-34.md`
- `agent-docs/multi-session-roadmap/SESSION-PROMPTS.md`
- `agent-docs/current-agent-context/*`
- `docs/guides/{installation,quickstart-optimization,quickstart-sweep}.md`
- `docs/status/{phase-30-status,phase-32-status,phase-34-*.md,multimode-baseline-status-2026-04-22.md}`
- `docs/synthesis/{why-phase-31-changed-the-roadmap,why-phase-34-still-points-back-to-phase-31}.md`
- `scripts/canonical/README.md`
- `scripts/lib/raman_optimization.jl`
- `src/MultiModeNoise.jl`
- `src/io/results.jl`
- `notebooks/README.md`

## Current-state findings that matter for rollout planning

1. The repo has a real maintained surface, but it is still narrow:
   - canonical scripts
   - fast/slow/full test tiers
   - documented output schema
   - result manifest and JSON sidecars

2. The repo is not yet honestly "lab-ready":
   - major research questions are still open in continuation/globalization,
     acceleration, multimode baseline selection, long-fiber support, and
     multivariable optimization
   - the package layer does not yet expose a stable user-facing run API; its
     public exports are mostly result I/O and determinism helpers
   - notebooks are explicitly exploratory, not maintained workflow surface
   - most maintained run configuration is still encoded as script constants,
     not a user-editable config system

3. There is at least one trust-breaking interface mismatch right now:
   - `scripts/canonical/optimize_raman.jl` is documented as the canonical
     single-run entry point
   - it currently delegates to `scripts/lib/raman_optimization.jl::main()`
   - that `main()` still launches a five-run heavy-duty suite plus chirp
     sensitivity, not one canonical run
   - this should be treated as a rollout blocker, not papered over by docs

4. The best-supported science lane today is still single-mode phase-only Raman
   suppression around the maintained SMF-28/HNLF workflows.

5. Several attractive extensions remain explicitly research-grade:
   - reduced-basis continuation is scientifically important but not yet closed
     as a stable maintained method
   - trust-region/preconditioning is promising only after better path quality
   - multimode has a recommended baseline regime but not yet a durable shared
     workflow
   - long-fiber is credible for 50-100 m single-mode exploration, not yet
     group-grade
   - multivariable optimization exists but still underperforms phase-only on
     the reference case and should stay experimental

## Product-design interpretation

The repo should transition in two layers:

- first, a narrow trusted lab surface for canonical single-mode work
- later, promoted research extensions only after they win scientifically and
  stabilize operationally

The proposal should optimize for:

- simplicity
- trust
- reproducibility
- explicit supported/experimental boundaries

## Likely lab-facing use cases

- run one canonical single-mode optimization and inspect the standard images
- rerun a small set of approved single-mode configs for comparison to old runs
- run approved sweeps on burst and regenerate reports from saved artifacts
- inspect, validate, and compare archived runs without rerunning optimization
- export one approved run into an experiment-facing handoff bundle
- use notebooks for post hoc inspection, not as the primary compute driver

## Likely non-goals for initial rollout

- general-purpose arbitrary experiment authoring through notebooks
- multimode as a default first-user surface
- long-fiber as a generally supported production workflow
- multivariable optimization as a default lab tool
- exposing trust-region / Newton research internals as user-facing controls
