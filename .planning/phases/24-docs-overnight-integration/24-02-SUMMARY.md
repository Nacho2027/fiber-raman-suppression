---
phase: 24
plan: 02
subsystem: docs
tags: [docs, latex, corrective-pass, physics-verification, literature-anchors]
dependency_graph:
  requires:
    - .planning/phases/24-docs-overnight-integration/24-01-PLAN.md
    - .planning/phases/24-docs-overnight-integration/24-01-SUMMARY.md
    - .planning/phases/24-docs-overnight-integration/24-RESEARCH-external.md
  provides:
    - docs-with-fact-corrected-phase-attributions
    - docs-with-mamyshev-prior-art-acknowledged
    - docs-with-gauge-vs-indefinite-separation-explicit
    - physics-verification-appendix-with-soliton-arithmetic
    - rebuilt-pdfs-current-with-tex
  affects:
    - docs/companion_explainer.tex
    - docs/verification_document.tex
    - docs/*.pdf
    - .planning/phases/24-docs-overnight-integration/24-PHYSICS-VERIFICATION.md
key-files:
  created:
    - .planning/phases/24-docs-overnight-integration/24-PHYSICS-VERIFICATION.md
    - .planning/phases/24-docs-overnight-integration/24-02-SUMMARY.md
  modified:
    - docs/companion_explainer.tex
    - docs/verification_document.tex
    - docs/companion_explainer.pdf
    - docs/verification_document.pdf
    - docs/physics_verification.pdf
metrics:
  completed: 2026-04-20
---

# Phase 24 Plan 02: Corrective Pass on Overnight-Integration Docs Summary

Single corrective commit that fixes plan 24-01's misattributions,
integrates the pending external-research items from
`24-RESEARCH-external.md`, adds the physics verification appendix
the user asked for, and rebuilds all three PDFs cleanly.

## What Landed (14 items)

### Bug fixes (M/F tasks)

- **M1** (`docs/companion_explainer.tex` overnight-update box): Phase
  22's `plain` row reproduced the canonical $-76.86$ dB SMF-28
  optimum; Phase 21 re-anchored a *different* operating point
  ($L{=}2$ m, $P{=}0.2$ W → $-66.61$ dB) and reproduced Session F's
  100 m warm start at $-54.77$ dB. Original text misattributed the
  $-76.86$ dB reproduction to Phase 21.
- **M2** (`docs/verification_document.tex` §sec:april-sharpness
  advisory): replaced dominated Pareto-57 `trH, λ=3e-3` recommendation
  with the full Pareto frontier — `MC, λ=7.5e-2` at $+0.066$ rad
  tolerance for $14.58$ dB (best combined), `trH, λ=1e-3` at matched
  $+0.066$ rad for $16.12$ dB, `trH, λ=3e-3` at $+0.032$ rad for
  $13.18$ dB (dominated-in-tolerance).
- **F1** (`docs/verification_document.tex` 100 m advisory): orphan
  `phase21_100m_phase_profile.png` now included at 0.82\textwidth
  before the Phase 23 overlay; caption records BC edge
  $8.47\times10^{-6}$, $\Delta E/E \le 4.91\times10^{-4}$.

### Missing-info additions (X tasks)

- **X1** best-trades table row + companion callout: Pareto-57,
  `MC, λ=7.5e-2`: $-67.98$ dB, $\sigma_{3\text{dB}} = 0.077$ rad,
  $|\lambda_\text{min}|/\lambda_\text{max} = 7.87\times10^{-2}$.
- **X2** 100 m advisory: explicit BC-edge / energy-drift numbers
  for all three trusted Phase 23 runs (warm BC $9.09\times10^{-7}$,
  matched $+4$ ps$^2$ BC $3.23\times10^{-6}$, matched $+1$ ps$^2$
  BC $2.84\times10^{-7}$, each with $\Delta E/E$).
- **X3** best-trades table row + footnote: Canonical, `trH, λ=1e-3`:
  $-73.83$ dB, $\sigma_{3\text{dB}} = 0.037$ rad (curve-knee row),
  $|\lambda_\text{min}|/\lambda_\text{max}$ marked as not reported.
- **X4** §sec:april-sharpness survives-Sweep-1 sentence: Phase 21
  re-anchored the retired Sweep-1 `L=2m, P=0.2W` point to
  $J = -66.03$ dB on honest $N_t{=}16{,}384$, $T{=}54$ ps grid.

### Research integration (R tasks)

- **R6** new `\newtcolorbox{update}[1]{colback=cyan!5,...title=\textbf{Overnight update --- #1}}`
  registered in companion preamble (dynamic-title variant per
  CORRECTION F); inline yellow+orange box at L76 replaced with
  `\begin{update}{2026-04-19/20}...\end{update}`.
- **R4** Phase 23 physics rewrite (both docs) with explicit
  arithmetic — $T_0 \approx 105$ fs, $P_\text{peak} \approx 2959$ W,
  $N_\text{sol} \approx 1.4$, $L_D \approx 0.507$ m, $L_\text{NL}
  \approx 0.260$ m. Pre-chirp stretch $\approx 362\times$
  (asymptotic large-chirp regime $|\text{GDD}|/T_0^2 = 363$),
  stretched peak $\sim 8$ W, $\Phi_\text{NL,100m} \approx 1.3$ rad
  vs $\Phi_\text{NL,canonical} \approx 1.92$ rad (peak) /
  $1.63$ rad (envelope-averaged). Retracts "non-polynomial structural
  adaptation across $50\times$" framing; attributes $\sim 0.5$ dB
  of the 45 dB to a genuine non-quadratic residual.
- **R1** Mamyshev-oscillator literature anchor in verification_doc:
  Liu et al., *Optica* 4, 649 (2017) + Wise group Mamyshev design
  guide. Frames the depth as novel; the mechanism is standing
  design wisdom.
- **R2** SAM null result reframed as three-failure-mode expected
  behaviour: deterministic SAM loses minibatch m-sharpness
  (Andriushchenko & Flammarion ICML 2022, arXiv:2206.06232);
  indefinite-saddle hallucinate-minimiser pathology (arXiv:2509.21818,
  2025); gauge-direction $\rho$-ball partial-null.
- **R3** trH indefinite-Hessian caveat advisory inserted after the
  keyresult box: $+\lambda \mathrm{Tr}(H)$ on indefinite spectrum can
  flatten positives OR sharpen negatives; flat-basin mechanism
  provisional until post-trH Lanczos. Cites Liu arXiv:2208.05924
  (2023) and Ju arXiv:2306.08553 (2023).
- **R5** gauge-symmetry vs indefinite-Hessian separated explicitly
  at top of §sec:april-sharpness: gauge → 2 exact-zero eigenvalues
  (topological); indefiniteness → additional empirical fact from
  nonlinear physics. L-BFGS halts because of (b), not (a).
- **R7** undefined `\ref{sec:gauge}` at L707 replaced with prose
  cross-doc reference to `physics_verification.tex` §"Gauge symmetry
  of $J$ and its consequences for the Hessian" (option (b) per plan).

### New deliverable

- **V1** `24-PHYSICS-VERIFICATION.md` (309 lines) with the 9-section
  structure specified in the plan. Incorporates CORRECTIONS A–D:
  - §4: Gaussian RMS formula called out as a large-chirp asymptotic
    (both Gaussian and sech$^2$ → $|\text{GDD}|/T_0$ when
    $|\text{GDD}|/T_0^2 \gg 1$; our ratio is 363); full arithmetic
    for $T_\text{chirped} = 38.1$ ps, $363\times$ stretch.
  - §5: Peak-power rescaling derived from unitarity of the GDD
    transformation (energy conservation, shape-independent to
    leading order); no false sech$^2$ identity.
  - §6: Clean $\Phi_\text{NL}$ derivations — 100 m stretched
    $\approx 1.3$ rad, canonical peak $\approx 1.92$ rad (audit's
    1.63 rad is the envelope-averaged form, factor $\approx 0.88$).
  - §7: Raman gain section rewritten per CORRECTION D — deleted the
    wrong exponential $g_R P L_\text{eff}$ framework (CW Stokes
    seed amplification); replaced with correct time-domain GNLSE
    Raman-source integral framing. Scaling argument: $363\times$
    drop in $|u|^2$ collapses Raman generation by $\sim 10^5$.

## Build Result

Three PDFs rebuilt with two-pass pdflatex:

| PDF                        | Size      | Undefined refs | Fatal errors |
| -------------------------- | --------- | -------------- | ------------ |
| `companion_explainer.pdf`  | 2.7 MB    | 0              | 0            |
| `verification_document.pdf`| 3.3 MB    | 0              | 0            |
| `physics_verification.pdf` | 210 KB    | 0              | 0            |

R7 eliminated the pre-existing `sec:gauge` warning. A new
`sec:april-hessian` warning appeared in `companion_explainer.pdf`
(my M1 rewrite initially referenced a verification_document label
from the companion); I caught it in the first build, swapped the
`\S\ref{sec:april-hessian}` for a prose section name, and rebuilt.
Final log shows 0 undefined references in all three docs.

## Deviations from Plan

1. **M1 companion `\ref{sec:april-hessian}` scope bug.** The plan
   text specified `\S\ref{sec:april-hessian}` inside the companion
   overnight-update box, but that label lives in the verification
   document, so it renders undefined in the companion. Applied
   the R7 pattern to the companion as well (prose section name
   instead of cross-doc label reference). This is a Rule 3
   blocking-issue auto-fix and matches the plan's R7 methodology.
2. **CORRECTION E self-correction cleanup.** The plan's X3 text
   said "insert AFTER ... NO wait, insert BEFORE"; I applied the
   clean final version (trH, λ=1e-3 row inserted immediately
   before the existing trH, λ=3e-3 row so strengths appear in
   ascending order). No actual deviation from plan intent.
3. **CORRECTION F dynamic title.** Used
   `\newtcolorbox{update}[1]{... title=\textbf{Overnight update --- #1}}`
   and invoked as `\begin{update}{2026-04-19/20}`, keeping the
   date in the title (more prominent) rather than migrating it to
   the body text as the plan originally suggested. Preserves
   visual convention.

## Commit

Single commit on `sessions/D-docs`:

- Hash: `f2c7a4b`
- Message: `docs(24.2): fix misquotes + integrate external research + physics appendix`
- Files changed: 5 tex/pdf + 3 markdown (plan, summary, physics appendix)
- Pushed: `origin/sessions/D-docs`

## Self-Check

Files created:
- FOUND: `.planning/phases/24-docs-overnight-integration/24-PHYSICS-VERIFICATION.md`
- FOUND: `.planning/phases/24-docs-overnight-integration/24-02-SUMMARY.md`

Files modified (verified via `git status` and `test -nt`):
- FOUND: `docs/companion_explainer.tex` (newer than pre-plan state)
- FOUND: `docs/verification_document.tex` (newer)
- FOUND: `docs/companion_explainer.pdf` (newer than .tex)
- FOUND: `docs/verification_document.pdf` (newer than .tex)
- FOUND: `docs/physics_verification.pdf` (newer than .tex)

All 9 R-task / M-task / F-task / X-task grep acceptance criteria
passed in-session (re-verified after R7 rebuild).

## Self-Check: PASSED
