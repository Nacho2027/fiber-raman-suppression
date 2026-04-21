---
phase: 24
subsystem: docs
tags: [docs, latex, overnight-integration]
inputs:
  - .planning/phases/21-numerical-recovery/SUMMARY.md (Session I-recovery)
  - results/raman/phase22/SUMMARY.md (Session S-sharpness)
  - .planning/phases/23-matched-baseline/SUMMARY.md (Session M-matched100m)
  - docs/verification_document.tex
  - docs/companion_explainer.tex
  - docs/physics_verification.tex
  - results/PHYSICS_AUDIT_2026-04-19.md
scope: fold overnight Phase 21/22/23 results into the canonical three-doc set
---

# Phase 24 Research

## Overnight inputs synthesised

### Phase 21 — Numerical recovery (Session I-recovery)

Drives dB re-anchoring in the canonical docs. Replaces the Phase 18
validator numbers that §X1 of PHYSICS_AUDIT_2026-04-19.md carried into
the existing `flagged` block at §sec:april-hessian.

| Item | Doc treatment |
|---|---|
| Sweep-1 at `L=2m,P=0.2W` — **RETIRED**. Even at `Nt=65536, T=216 ps` every recovered point has output edge fraction $\geq 5\%$; the best is `-66.03 dB` at full resolution. | Update/remove Sweep-1 knee narrative. The doc currently does not frame `phase_sweep_simple/candidates.md` as a Sweep-1 knee story; the cited point is `L=0.25m,P=0.10W` (pareto57) which is *not* what Phase 21 retired. The retirement applies to the `L=2m,P=0.2W` anchor specifically. Note the distinction. |
| Session F 100 m — **RECOVERED** as honest lower bound. `-54.77 dB` unconverged, BC edge `8.47e-06`, $\|\nabla J\| \approx 0.48$. Schema fix: `phi_opt` lives in `100m_opt_full_result.jld2` (the scalar summary was missing the full state). | §april-wrong W2 already treats this correctly as "lower bound". Add schema fix note. |
| Phase 13 SMF-28 re-anchor — **RECOVERED** at `-66.61 dB` (`Nt=16384, T=54 ps`, BC `8.10e-04`). | Replace the §X1 flagged-block Phase 18 value (`-48.2 dB`) with `-66.61 dB`. |
| Phase 13 HNLF re-anchor — **RECOVERED** at `-86.68 dB` (`Nt=65536, T=320 ps`, BC `2.24e-04`, 50-iter unconverged). Deeper than both the originally reported `-74.45 dB` and the Phase 18 revalidation `-44.0 dB`. | Replace the HNLF §X1 value. Note that Phase 18 validator was under-sized for HNLF. |
| MMF aggressive `(M=6, L=2m, P=0.5W)` — **PARTIAL**. No artifact produced. | Keep §april-mmf's current "negative control, aggressive baseline unrun" framing. |

### Phase 22 — Sharpness research (Session S-sharpness)

Drives a new "we tried to flatten the basin" paragraph in both
§sec:april-hessian / §sec:april-sigma3db of verification_document and
in the companion explainer's §16.2 (razor's edge).

Key results (all 26 optima remain Hessian-indefinite):

- **Canonical point** (SMF-28 L=0.5m P=0.05W, the -76.86 dB anchor):
  - Plain baseline: `-76.86 dB`, $\sigma_{3\text{dB}} = 0.025$ rad
  - Best robustness: `trH, \lambda=3e-3`: $\sigma_{3\text{dB}} = 0.083$ rad (+0.058 rad), $J = -66.79$ dB (10.08 dB depth cost)
  - Cheap robustness: `MC, \lambda=7.5e-2`: $\sigma_{3\text{dB}} = 0.039$ rad (+0.014 rad), $J = -73.01$ dB (3.85 dB depth cost)
  - SAM produced `\leq 0.006` rad $\sigma$-shift — not useful.
- **Pareto-57 point** (SMF-28 L=0.25m P=0.10W):
  - Plain: `-82.56 dB`, $\sigma_{3\text{dB}} = 0.011$ rad
  - Best robustness: `trH, \lambda=3e-3`: `-69.38 dB`, $\sigma_{3\text{dB}} = 0.043$ rad (+0.032 rad), 13.18 dB cost. (Note: `trH,1e-3` gives $\sigma_{3\text{dB}} = 0.077$ rad at `-66.44 dB` — different trade point.)
- **Verdict**: Sharpness regularization produces a real Pareto between
  depth and shaper tolerance but does not convert the indefinite-saddle
  geometry into a PD minimum. The default plain log-dB objective stays;
  `trH` / `MC` become optional modes when tolerance matters more than
  depth.

Figure: `phase22_pareto.png` — J_dB vs $\sigma_{3\text{dB}}$ for both
operating points across `plain, MC, SAM, trH` flavors. This is a
first-class new figure for the docs.

### Phase 23 — Matched quadratic 100 m baseline (Session M-matched100m)

Kills the S5 "50× length transferability proves nonlinear structural
adaptation" framing that currently lives as a v4 advisory at
verification_document.tex lines ~731–768.

Key facts (on live reproducible main-checkout state):

- Warm-start rerun at 100 m: $J = -45.52$ dB (not the historical
  `-51.50 dB` from Phase 16).
- Best trusted quadratic GDD scan by endpoint $J$:
  `GDD = +4.00 ps^2` $\to$ $J = -45.06$ dB (only `+0.46 dB` shy of the
  live warm-start).
- Trajectory-matched quadratic `GDD = +1.00 ps^2` $\to$ $J = -44.35$ dB
  (`+1.17 dB` shy).
- All trusted runs clean on energy drift and BC edge.

Net: the 100 m transfer result is "generic dispersive pre-chirp suppresses
Raman on this length scale" — it is not evidence for non-polynomial
structural adaptation. The audit S5 bullet is therefore promoted from
"report with mechanism caveat" to "withdrawn on the quantitative
transferability framing."

Figure: `phase23_warm_vs_gdd_p1_overlay.png` shows the spectral evolution
of the warm-start vs the matched quadratic. Useful for the companion.

**Caveat the doc must carry**: the live warm-start rerun at `-45.52 dB`
disagrees with the historical Phase 16 number (`-51.50 dB`) by ~6 dB
*on the same seed*. The gap itself is unexplained — plausibly another
edge-fraction / time-window effect on the stored Phase 16 result, but
Phase 23 did not diagnose it. Report both numbers, flag the discrepancy.

## LaTeX conventions I will apply

- Use the existing `keyresult` / `flagged` / `advisory` tcolorbox
  environments. Do not invent new environment names.
- Use `\texttt{path/to/file.md}` for artifact references, with `\_`
  escaped underscores.
- Cite dB numbers with source JLD2 or SUMMARY.md path + line range
  where available.
- Preserve all `\label{sec:april-*}` anchors; cross-references in the
  text rely on them.
- When citing a sibling session's standard-image path, give the full
  `.planning/phases/NN-<topic>/images/<basename>.png` path so future
  readers can cross-reference. Keep a local copy in `docs/figures/`
  for the PDF build.

## Figure inventory (additions)

1. `docs/figures/phase22_pareto.png` — already staged.
   **Use in**: verification_document §sec:april-hessian-sharpness (new
   subsection); companion §16.2 callout.
2. `docs/figures/phase21_recovered_smf28_phase_profile.png` — already
   staged.
   **Use in**: verification_document §sec:april-hessian flagged block
   (replacing the Phase 18 dB numbers).
3. `docs/figures/phase21_100m_phase_profile.png` — already staged.
   **Use in**: optional, in the 100m advisory alongside the Phase 23
   overlay.
4. `docs/figures/phase23_warm_vs_gdd_p1_overlay.png` — already staged.
   **Use in**: companion §16 long-fiber subsection; verification_document
   100m advisory.

No TikZ additions; existing diagrams are sufficient. No regeneration of
any optimization PNGs — every figure I need was produced by a sibling
session.

## Open ambiguities / decisions

- **First-three-pages front-load.** The prompt requires the companion's
  opening pages to communicate what happened overnight. Options:
  (a) add an "Overnight 2026-04-19/20 update" `tcolorbox` right after
  the abstract; (b) append a new §16.0 "What happened in April 2026,
  in one page" that comes before the existing §16 subsections. I will
  go with (a) — a concise tcolorbox right after the abstract, listing
  the three surprises (the -77 dB baseline is stable, the Hessian is
  saddle everywhere we checked, the 100m story is pre-chirp not
  structural). The tcolorbox points at §16 for detail.

- **Physics_verification.tex**: per Phase 20, no changes were needed.
  Phase 24 also finds no material change — the Taylor-remainder
  scope-limitation paragraph still captures the S6 story. No edits.

- **Sweep-1 retirement**: the doc's pareto-57 anchor (`candidates.md`,
  `L=0.25m, P=0.10W, -82.33 dB`) is NOT what Phase 21 retired. Phase 21
  retired `L=2m, P=0.2W` specifically. I will add a scope flag noting
  that the Sweep-1 knee at `L=2m P=0.2W` is withdrawn; the
  `L=0.25m P=0.10W` Pareto candidate stands until independently
  re-validated, and the Phase 22 sharpness work cross-validates it at
  the plain optimum (`-82.56 dB` consistent with the original
  `-82.33 dB` within 0.23 dB).
