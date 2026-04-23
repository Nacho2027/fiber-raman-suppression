---
title: Independent numerics audit of fiber-raman-suppression (docs-only)
status: in_progress
created: 2026-04-20
owner: sessions/numerics
---

# Quick Task 260420-oyg — Independent numerics audit (second opinion)

## Goal

Produce a **skeptical, code-verified second opinion** on Phase 25's numerical
audit, using Cornell CS 4220 s26 and Bindel's *Numerical Methods for Data
Science* (NMDS) as authoritative references, by actually reading the code
instead of trusting the existing audit text.

The deliverable is an **update in place** of the Phase 25 docs (`25-REPORT.md`,
`25-RESEARCH.md`, `25-REVIEWS.md`, `SUMMARY.md`) plus any **new seeds** under
`.planning/seeds/` for substantial future phases that Phase 25 missed.

This is **research + docs only. No `src/**` edits. No refactors.** Project-wide
constraint D25-01 applies.

## must_haves

1. **Code-verified findings.** Every claim of the form "X is fragile / X is
   fine" in the updated docs must cite a specific file + line (or clearly mark
   "not verified in this pass"). If Phase 25 said something and the code says
   otherwise, that gets called out explicitly.
2. **Skeptical corrections in place.** Edits to `25-REPORT.md` and
   `25-RESEARCH.md` note where the original audit was right, wrong,
   under-instrumented, or misframed. Do not rewrite history — append a
   "Second-opinion addendum" section (or per-topic annotations) rather than
   deleting the original findings.
3. **Explicit topic coverage.** The addendum covers, for each of the user's
   named concern areas: conditioning, scaling, backward-vs-forward error,
   globalization, Newton/Krylov/preconditioning opportunities, FFT-aware
   numerics, continuation, extrapolation, performance modeling. Say "verified /
   partially verified / not verified" per topic.
4. **New seeds iff genuinely new.** Seeds already in `.planning/seeds/`
   (conditioning-and-backward-error, globalized-second-order,
   truncated-newton-krylov-preconditioning, reduced-basis-phase-regularization,
   continuation-and-homotopy-schedules, performance-modeling-and-roofline,
   extrapolation-and-acceleration) should NOT be duplicated. New seeds only if
   the audit finds phase-sized gaps these do not already cover.
5. **Concise ranking at the end.** The addendum closes with:
   (a) top 5 numerical risks ranked,
   (b) top 5 highest-leverage improvements ranked,
   (c) the single most important next numerics phase — named, justified.

## Scope

In scope (editable):
- `.planning/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/*.md`
- `.planning/seeds/*.md` — new ones only; existing ones treated as read-only
  unless outright wrong
- `.planning/quick/260420-oyg-*/` — this quick task's own artifacts
- `.planning/STATE.md` — only the Quick Tasks Completed table row per gsd-quick

Out of scope (do NOT touch):
- Any `src/**` file
- `scripts/common.jl`, `scripts/visualization.jl`, other shared scripts
- `.planning/ROADMAP.md`
- Any other Phase's docs
- `.planning/seeds/*.md` that already exist

## Files to read (verification targets)

- `scripts/common.jl`
- `scripts/raman_optimization.jl`
- `scripts/amplitude_optimization.jl`
- `scripts/run_benchmarks.jl`
- `scripts/hessian_eigspec.jl`
- `scripts/hvp.jl` (referenced by Phase 25 — verify it exists)
- `scripts/determinism.jl`
- `scripts/benchmark_threading.jl`
- `src/simulation/simulate_disp_mmf.jl`
- `src/simulation/sensitivity_disp_mmf.jl`
- `src/simulation/simulate_disp_gain_smf.jl` (if relevant)
- `src/helpers/helpers.jl`
- `src/analysis/analysis.jl`

External reference frame:
- https://github.com/dbindel/cs4220-s26/
- https://www.cs.cornell.edu/~bindel/nmds/

## Tasks

### Task 1 — Verify Phase 25 claims against the code (no edits yet)

**action:** Read each target file. For each concrete claim made in
`25-REPORT.md` / `25-RESEARCH.md` (e.g., "ESTIMATE plan used", "HVP machinery
in Phase 13", "Dict{String,Any} parameter passing", "`src/analysis/analysis.jl`
broken"), mark it verified / partially verified / wrong, with file:line
evidence. Keep working notes in this quick task's directory.

**verify:** A working-notes file with ≥ 1 file:line citation per Phase 25
headline claim, written to
`.planning/quick/260420-oyg-.../260420-oyg-NOTES.md`.

**done:** Notes file exists and covers every "What is actually going wrong"
bullet of `25-REPORT.md`.

### Task 2 — Write the skeptical addendum into Phase 25 docs + SUMMARY

**action:** Edit `25-REPORT.md`, `25-RESEARCH.md`, `25-REVIEWS.md`,
`SUMMARY.md` in place by appending clearly-marked addendum sections (not
rewriting). The addendum covers all nine user-requested topics, cross-references
the verification notes, calls out specific misframings / omissions, and closes
with the three required rankings.

**verify:** Each of the four Phase 25 docs shows a new
`## Second-Opinion Addendum (2026-04-20)` section (or equivalent). The ranking
block exists in at least `25-REPORT.md` and `SUMMARY.md`.

**done:** `grep -n "Second-Opinion Addendum" .planning/phases/25-*/*.md`
returns matches in all four files.

### Task 3 — Add new seeds iff warranted

**action:** For any phase-sized gap that existing seeds do not already cover,
write a new seed file in `.planning/seeds/`. Must be a clearly distinct idea
from the existing seven. If nothing new is warranted, document that in the
addendum ("No new seeds — existing seven cover the space.").

**verify:** Either new seed file(s) exist with frontmatter (name, rationale,
scope sketch), or the addendum explicitly states no new seeds are needed and
why.

**done:** `.planning/seeds/*.md` count either increased OR the addendum states
"No new seeds needed" with a one-sentence justification.

### Task 4 — Commit and wrap (orchestrator step)

**action:** Write `260420-oyg-SUMMARY.md` per gsd-quick convention. Stage and
commit all touched `.planning/**` files through `gsd-sdk query commit`. Update
STATE.md's Quick Tasks Completed table.

**verify:** `git log --oneline -1` shows a `docs(quick-260420-oyg)` commit.
`.planning/STATE.md` has a new row in Quick Tasks Completed.

**done:** The commit exists; SUMMARY.md has `status: complete` in frontmatter.

## Risks

- **Scope creep into re-planning.** Mitigation: addendum only appends; original
  Phase 25 text preserved.
- **Overfitting the second opinion to whatever the code makes obvious.**
  Mitigation: every topic in the user's list gets a verdict, even if the
  verdict is "nothing new to add."
- **Missing an existing seed and duplicating it.** Mitigation: Task 3 lists all
  seven existing seed slugs before writing any new one.

## Non-goals

- Fixing the numerics themselves
- Touching ROADMAP.md
- Rewriting the Phase 25 docs from scratch
- Re-verifying physics — only numerics
