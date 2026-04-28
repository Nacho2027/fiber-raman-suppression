# Context

## Goal

Create a documentation-production plan for a small series of LaTeX research
notes that makes the repo's major scientific lanes legible without collapsing
everything into one long report.

## Sources reviewed

- `AGENTS.md`
- `CLAUDE.md`
- `README.md`
- `scripts/README.md`
- `docs/synthesis/recent-phase-synthesis-29-34.md`
- `agent-docs/multi-session-roadmap/SESSION-PROMPTS.md`
- `agent-docs/current-agent-context/{INDEX,METHODOLOGY,NUMERICS,LONGFIBER,MULTIVAR,PERFORMANCE}.md`
- `docs/README.md`
- `docs/architecture/{cost-function-physics,cost-convention}.md`
- `docs/status/{phase-30-status,phase-32-status,multimode-baseline-status-2026-04-22,phase-34-preconditioning-caveat,phase-34-bounded-rerun-status,lab-readiness-proposal-2026-04-23}.md`
- `docs/synthesis/{why-phase-31-changed-the-roadmap,why-phase-34-still-points-back-to-phase-31}.md`
- `agent-docs/phase31-reduced-basis/FINDINGS.md`
- `agent-docs/multimode-baseline-stabilization/SUMMARY.md`
- `agent-docs/cost-convention-consistency/SUMMARY.md`
- research subtree READMEs under `scripts/research/`
- selected research drivers in `scripts/research/{sweep_simple,simple_profile,cost_audit,multivar,mmf,longfiber,trust_region,recovery}/`
- selected result summaries under `results/raman/{phase16,phase22,phase31,phase33,phase34}/`

## Repo observations that affect the note plan

- The requested file `docs/recent-phase-synthesis-29-34.md` has moved to
  `docs/synthesis/recent-phase-synthesis-29-34.md`.
- The repo already has strong human-facing docs, but the science narrative is
  distributed across synthesis docs, status notes, planning-history material,
  result summaries, and research drivers.
- Some important research lanes are code-complete but artifact-incomplete in the
  synced workspace:
  - multimode `phase36` baseline results are not present locally
  - simple-profile / Phase 17 synthesis artifacts are not present locally
  - multivar JLD2 artifacts are present, but the expected standard PNG set is
    not visible in the synced tree
- Some lanes are methodologically important but empirically incomplete:
  - Phase 30 continuation methodology is implemented, flagship evidence is not
  - Phase 32 Richardson has a real negative result, but the broader acceleration
    verdict is incomplete
- Some note candidates are better handled as sections inside broader notes than
  as standalone documents:
  - Phase 30 and Phase 32 belong inside the continuation note
  - Phase 34 dispersion-preconditioning closure belongs inside the trust-region
    / second-order note

## Planning stance

- Prefer a note series of roughly 8-10 main notes, plus 1-2 short methods
  appendices if needed.
- Use one shared LaTeX skeleton and common macro file.
- Avoid duplicating the full forward-adjoint derivation in every note; instead
  give each note a short common setup recap plus a "math delta" section.
