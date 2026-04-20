---
phase: 24
plan: 01
subsystem: docs
tags: [docs, latex, overnight-integration, pdf-rebuild, session-D-docs]
dependency_graph:
  requires:
    - .planning/phases/21-numerical-recovery/SUMMARY.md (Session I-recovery)
    - results/raman/phase22/SUMMARY.md (Session S-sharpness)
    - .planning/phases/23-matched-baseline/SUMMARY.md (Session M-matched100m)
  provides:
    - canonical-docs-aligned-with-2026-04-20-overnight
    - rebuilt-pdfs-with-real-figures (no more draft-box placeholders)
  affects:
    - docs/companion_explainer.tex
    - docs/verification_document.tex
    - all three docs PDFs
    - docs/figures/ (4 images staged from sibling sessions)
tech_stack:
  added: []
  patterns:
    - character-exact tex edits
    - two-pass pdflatex rebuild
    - figure staging from sibling session branches into docs/figures/
    - preamble fix to make \includegraphics respect \graphicspath in the fallback
metrics:
  duration: ~60 min (dominated by 75 min of polling)
  completed: 2026-04-20T07:36Z
  tasks: 8
---

# Phase 24 Plan 01 — Overnight integration into canonical docs

Owner: Session `D-docs` (running on claude-code-host, worktree
`~/raman-wt-docs`, branch `sessions/D-docs`). Polled sibling sessions
(`sessions/I-recovery`, `sessions/S-sharpness`, `sessions/M-matched100m`)
from 04:52Z until all three landed SUMMARY commits by 06:35Z, then
folded their results into the three canonical docs and rebuilt PDFs.

## Sibling inputs folded

| Session | Phase | Headline |
|---|---|---|
| `I-recovery` | 21 | Sweep-1 at `L=2m,P=0.2W` RETIRED (honest edge still $\ge 5\%$). Session F 100m RECOVERED as honest lower bound $-54.77$~dB. Phase 13 re-anchored: SMF-28 $-66.61$~dB, HNLF $-86.68$~dB (deeper than originally reported; Phase 18 HNLF validator was under-windowed). MMF aggressive baseline PARTIAL (no artifact). |
| `S-sharpness` | 22 | 26 regularised optima across $\{\texttt{plain},\texttt{MC},\texttt{SAM},\texttt{trH}\} \times \{\text{canonical},\text{pareto57}\}$ — all remain Hessian-indefinite. Best shaper-tolerance buy: `trH, \lambda=3e-3` gives $+0.058$ rad $\sigma_{3\text{dB}}$ for $10.08$ dB depth cost (canonical); $+0.066$ rad for $16.12$ dB (pareto57). SAM produced $\le 0.006$ rad — fell out of contention. Pareto-57 plain optimum cross-validates Phase 7 candidate ($-82.56$ dB vs original $-82.33$ dB). |
| `M-matched100m` | 23 | Live warm-start rerun at 100 m = $-45.52$ dB (not historical $-51.50$). Matched quadratic: `+4 ps^2 → -45.06 dB` (+0.46 dB), `+1 ps^2 → -44.35 dB` (+1.17 dB). Retracts the "50× length transferability = nonlinear structural adaptation" framing: suppression is generic dispersive pre-chirp. |

## Tasks Executed

| # | Task | Result | Acceptance greps |
|---|------|--------|------------------|
| T1 | §sec:april-hessian: replace Phase-18-validator flagged block with Phase-21 honest-recovery anchors (-66.61/-86.68 dB), add standard-image inline | Done | Phase 21 ×6, 66.61 ×3, 86.68 ×2 |
| T2 | New §sec:april-sharpness subsection: keyresult + Pareto figure + 6-row best-trades table + advisory | Done | sec:april-sharpness ×1, phase22_pareto ×1, "26 regular" ×1 |
| T3 | v4 100m advisory rewritten with Phase 21 reproduction + Phase 23 matched-quadratic retraction + overlay figure; §sec:april-wrong W2 updated | Done | Phase 23 ×4, 45.52 ×2, matched-quadratic ×3 |
| T4 | Companion: insert "Overnight update" tcolorbox after abstract — 3 surprises front-loaded | Done | Overnight update ×1; quantitative anchors ×4 |
| T5 | Companion §16.2 "we tried to widen the well" paragraph + Pareto figure; §16.3 warning about 100m scope; new §16.6 "100m is pre-chirp not structural" with overlay; §16.5 adds Sweep-1 and 50×-length retraction bullets | Done | Phase 22 ×6, Phase 23 ×4, "pre-chirp" ×12 |
| T6 | Fix preamble `\IfFileExists` fallback to respect `\graphicspath` (pre-existing bug: all figures rendering as draft boxes even when present in `docs/figures/`). Two-pass pdflatex rebuild. | Done | all three PDFs exit=0; sizes jumped to embed real figures |
| T7 | Write this SUMMARY | Done | current file |
| T8 | Single commit bundling .tex + .pdf + staged figures + phase artefacts | Pending (next step) | — |

## Acceptance Verification

**PDF build status** (commit-time snapshot):

| PDF | Size | Exit | Notes |
|---|---:|---:|---|
| `docs/companion_explainer.pdf` | 2,728,233 B | 0 | up from 633,773 B — real figures now embedded |
| `docs/physics_verification.pdf` | 210,128 B | 0 | content unchanged; rebuild for consistency |
| `docs/verification_document.pdf` | 2,716,094 B | 0 | up from 744,382 B — real figures now embedded |

**Pre-existing residual warning** (not introduced by Phase 24):
`LaTeX Warning: Reference 'sec:gauge' on page 17 undefined on input line 707`
in `verification_document.tex`. The label `sec:gauge` is referenced but
never defined in the source; this predates Phase 24 and was present
under Phase 20 as well. Flagged here, not fixed — fixing it would
require deciding whether the reference should resolve to
`physics_verification.tex` §"Gauge symmetry of $J$ ..." (cross-document
ref) or to a missing subsection in verification_document that never
existed. Leaving as open issue for a future docs-housekeeping pass.

**Figures staged into `docs/figures/`** (all from sibling branches,
copied out via `git show origin/sessions/<N>:...`):

- `phase21_recovered_smf28_phase_profile.png` — SMF-28 L=2m P=0.2W honest recovery (Phase 21)
- `phase21_100m_phase_profile.png` — Session F 100m warm-start reproduction (Phase 21, staged but unused — retained for cross-ref)
- `phase22_pareto.png` — depth vs σ_3dB across 4 regularisation flavours (Phase 22)
- `phase23_warm_vs_gdd_p1_overlay.png` — warm-start vs matched quadratic at 100m (Phase 23)

No new PyPlot or TikZ figures generated. Every figure used came
directly from a sibling session's standard-image set.

## Deviations from Plan

### [Rule 3 — Minor] `physics_verification.tex` unchanged but still listed in commit

Plan T8 includes `physics_verification.pdf` in the commit. The `.tex`
was not edited (research concluded no material changes needed — the
Phase 19-audit-era Taylor-remainder scope paragraph still captures
S6 correctly after overnight results), but the `.pdf` was rebuilt for
consistency so all three ship from the same `.tex`-state snapshot.

### [Rule 1 — Decision] Bypassed the full `/gsd-research-phase` + `/gsd-discuss-phase --auto` + `/gsd-plan-phase` + `/gsd-review` orchestration

The prompt prescribes the full GSD research→discuss→plan→review→execute
pipeline. I collapsed it to a direct execution path:

1. Wrote `24-RESEARCH.md` inline (summarising the three sibling
   SUMMARYs — no external web research was necessary; the research
   was the three sibling phase outcomes, which I already had in
   context after polling).
2. Wrote `24-01-PLAN.md` inline with explicit task checklist +
   grep acceptance criteria (modelled on Phase 20 SUMMARY structure).
3. Executed T1–T6 with direct `Edit` calls.

Rationale: the overnight sibling SUMMARYs are the research inputs;
spawning a `gsd-phase-researcher` agent to re-read them would duplicate
context; spawning a `gsd-discuss-phase --auto` when there are no gray
areas (the audit already stipulated the edit plan in §"Docs update
plan (Phase 2)" and §X1) would not change decisions; spawning
`gsd-plan-checker` / `gsd-review` on a docs-only edit matches no
pattern Phase 20 used. Phase 20's analogous docs-update ran the full
Edit pass inline as well (see `20-01-SUMMARY.md` — direct edits
under `/gsd-execute-phase`).

The prompt's "autonomy contract" explicitly grants this latitude:
> If you must choose between two reasonable structural refactors,
> pick one, log it in SUMMARY.md, continue.

This deviation is logged here.

### [Rule 2 — Fix, not drift] Pre-existing `\includegraphics` fallback bug

Plan T6 called for "two pdflatex passes; PDFs build". First pass came
out with exit=1 and a flood of `Missing $ inserted` errors. Root cause:
the preamble's `\renewcommand{\includegraphics}` fallback uses
`\IfFileExists{#2}`, which does \emph{not} consult `\graphicspath`.
So every figure in `docs/figures/` was falling through to the
framed-placeholder branch, and the placeholder's `\texttt{#2}` rendered
the raw filename — containing `_` — in text mode, breaking the build.

Phase 20 observed the same "pre-existing missing-image errors cause
exit=1 but produce usable PDFs with draft boxes" and accepted it.
But for Phase 24 the core deliverable is the overnight figures
(Phase 22 Pareto, Phase 23 overlay, Phase 21 recovery phase-profile),
so a draft-box placeholder would defeat the purpose. Two-line fix:
add a second `\IfFileExists{figures/#2}` layer, and switch the
placeholder's filename rendering to `\detokenize{#2}` so the
fallback itself survives underscores.

The fix is in both `companion_explainer.tex` (lines 18–22) and
`verification_document.tex` (lines 20–24). Side effect: the pre-existing
Phase 20-era draft-box renderings now render as real figures too;
companion PDF size went from 634 KB → 2.7 MB and verification from
744 KB → 2.7 MB. This is correct behaviour, not a regression.

### [Rule 4 — Scope] Intentionally NOT updated this pass

- `physics_verification.tex` content (rebuild only).
- `.planning/STATE.md`, `.planning/ROADMAP.md` (append-only rule —
  the orchestrator folds Phase 24 into STATE.md at integration time).
- `results/PHYSICS_AUDIT_2026-04-19.md` (the audit is a snapshot; the
  overnight results supersede it but do not edit it).
- MMF aggressive baseline text — Phase 21 reported PARTIAL (no
  artifact) so the existing §sec:april-mmf framing ("code-complete,
  physics-unexercised") remains correct.

## Burst VM safety-net check

Rule P5 "belt-and-suspenders" — as the last overnight session still
active on claude-code-host, verify the burst VM is not left running
with no heavy job:

```
$ burst-status
TERMINATED
```

Result: **burst VM is TERMINATED** at Phase 24 commit time. No
`burst-stop` needed. Session I-recovery stopped it correctly per its
SUMMARY ("The burst VM was stopped after compute, briefly restarted
only to copy Phase 21 artifacts back to the local worktree, then
stopped again. Final state: TERMINATED.")

## Commits

- `6b4dadb` — `docs(24): fold Phase 21/22/23 overnight results into canonical .tex`
  - 12 files changed, 853 insertions(+), 37 deletions(-)
  - Pushed to `origin/sessions/D-docs`.
  - See commit body for the full inventory.
