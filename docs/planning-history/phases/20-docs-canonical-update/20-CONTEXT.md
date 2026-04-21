# Phase 20: Canonical Docs Update — Context

**Gathered:** 2026-04-19
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous-mode context injection)

<domain>
## Phase Boundary

Edit `docs/companion_explainer.tex`, `docs/physics_verification.tex`,
and `docs/verification_document.tex` so that only Phase-19-defensible
claims enter as new assertions, shaky claims enter with explicit
caveat, and wrong claims do NOT enter. Every new assertion must be
sourced to file:line, phase summary, or validation markdown.
Rebuild each PDF with two pdflatex passes so TOC and cross-refs
resolve. Commit .tex + .pdf together.

`results/raman/*.md` is INPUT-ONLY for this phase.
</domain>

<decisions>
## Implementation Decisions

### Build on the prior pass — make targeted refinements, not rewrites

A prior partial pass (commit `3e69c7a`) already added §9 "Integration
Pass — April 2026" to `verification_document.tex`, §16 "What the
April 2026 Parallel-Session Push Actually Showed" to
`companion_explainer.tex`, and a §"April 2026 audit" scope-limitation
paragraph to `physics_verification.tex`. Those edits are already
substantively correct and aligned with the audit. Phase 20 makes
the **five remaining refinements** that the Phase-19 §X1
cross-check and the §W1 wording fix uncovered.

### The five .tex changes to make (per Phase 19 audit §"Docs update plan")

(1) **`companion_explainer.tex` §16.5 ("What did *not* survive")** —
    Refine the first bullet (the W1 polynomial-fit critique): replace
    "ratio of noise" framing with "misspecified quadratic model —
    96–98% of φ_opt is non-quadratic residual structure" framing.
    Verdict and "didn't survive" status unchanged.

(2) **`physics_verification.tex`** — NO CHANGE. The existing April
    2026 audit scope-limitation paragraph at lines 300–316 already
    correctly captures S6 (Taylor-remainder test scope at the
    optimum). Verified in the Phase-19 audit cross-check.

(3) **`verification_document.tex` §sec:april-wrong (W1 paragraph)** —
    Refine the W1 paragraph wording in the same way as
    `companion_explainer`: preserve the verdict, swap "ratio of noise"
    for "ratio of two coefficients in a misspecified quadratic model
    — 96–98% of weighted variance is non-quadratic residual
    structure".

(4) **`verification_document.tex` §sec:april-hessian** — Append a
    one-paragraph J-anchoring caveat citing §X1 of
    `PHYSICS_AUDIT_2026-04-19.md` and the two Phase 18 validation
    files. The eigenstructure verdict (|λmin|/λmax = 2.6%/0.41%,
    indefinite, 100% same-sign wings) is correct as stated; the
    implied -60.5 dB / -74.4 dB anchoring of the canonical optima
    is overstated by 12–30 dB due to time-window edge bleed. The
    recomputed honest values are -48.2 dB (SMF-28) and -44.0 dB
    (HNLF). Quote both alongside the eigenstructure result.

(5) **`verification_document.tex` §sec:april2026 (Integration Pass
    intro)** — Append a one-line cross-reference to the Phase 18
    reproducibility audit at `results/validation/REPORT.md` so the
    reader knows the integration-pass numbers have been
    independently re-run on a controlled grid.

### Rebuild + commit discipline

After all five edits, rebuild each PDF with two pdflatex passes per
file (so TOC and cross-refs resolve correctly):

```bash
cd docs && for f in companion_explainer physics_verification verification_document; do
  pdflatex -interaction=nonstopmode "$f.tex" >/dev/null
  pdflatex -interaction=nonstopmode "$f.tex" >/dev/null
done
```

Commit .tex AND .pdf together in a single commit so anyone reading
the PDF can verify it's current with the source.

### Out of scope for this phase

- Edits to `results/PHYSICS_AUDIT_2026-04-19.md` (Phase 19 owns it; locked post-19-01-T4 commit `af317e3`).
- Edits to `results/raman/*.md` (input-only per the user's prompt).
- Edits to `src/**` or `scripts/**` (this is a docs-only phase).
- New burst-VM forward solves.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing:**

### The audit (input)
- `results/PHYSICS_AUDIT_2026-04-19.md` — verdict-classified findings (refined in Phase 19)

### The .tex files being edited
- `docs/companion_explainer.tex` — undergrad-pedagogical voice
- `docs/physics_verification.tex` — derivations reference
- `docs/verification_document.tex` — full verification artifact

### Cross-check sources
- `results/validation/phase13_hessian_smf28.md` — for the hessian J-anchoring caveat
- `results/validation/phase13_hessian_hnlf.md` — same
- `results/validation/REPORT.md` — Phase 18 top-level

### Project rules
- `CLAUDE.md` — multi-machine sync, GSD strict mode
</canonical_refs>

<specifics>
## Specific Edits with Locator Anchors

For each edit, the executor should grep first to confirm the exact
text, then use the Edit tool with character-exact `old_string`.

### Edit 1: companion_explainer.tex W1 refinement

Locate the bulleted list under `\subsection{What did \emph{not} survive}` (line ~1079). The first bullet currently reads:

> A polynomial-fit comparison of $\varphi_{\text{opt}}$ between $L = 2$~m and $L = 100$~m was used to argue for ``nonlinear structural adaptation.'' The fit's $R^2$ was $0.015$ at 100~m and $0.037$ at 2~m --- in both cases the quadratic model explained less than 4\% of the phase variance, so the extracted $a_2$ coefficients are noise. A ratio of noise is noise. (See \texttt{PHYSICS\_AUDIT\_2026-04-19.md} §W1.)

Replace with:

> A polynomial-fit comparison of $\varphi_{\text{opt}}$ between $L = 2$~m and $L = 100$~m was used to argue for ``nonlinear structural adaptation.'' The weighted quadratic fit's $R^2$ was $0.015$ at 100~m and $0.037$ at 2~m --- in both cases the quadratic model explained less than 4\% of the weighted variance on the signal band, so $96$--$98\%$ of $\varphi_{\text{opt}}(\omega)$ is non-quadratic residual structure orthogonal to $\{1, \omega, \omega^2\}$. The extracted $a_2$ is the projection of a non-quadratic signal onto a misspecified basis; its sign and magnitude have no scaling-law content, and the sign-flip across $L$ is the direct consequence of the underlying coefficient being near zero. (See \texttt{PHYSICS\_AUDIT\_2026-04-19.md} §W1.)

### Edit 2: verification_document.tex W1 refinement

Locate the W1 paragraph under `\subsection{What did NOT survive the audit}` (line ~1349, label `sec:april-wrong`). The W1 block currently reads:

> The weighted quadratic fit of $\varphi_\text{opt}(\omega)$ over the $\pm 5$~THz signal band has $R^2 = 0.015$ at 100~m and $R^2 = 0.037$ at 2~m. A quadratic model explaining $< 4\%$ of the variance does not constrain $a_2$; the extracted coefficients are fit noise, and their ratio is a ratio of noise. The sign flip is consistent with a true $a_2$ near zero perturbed by independent residuals at each length.

Replace with:

> The weighted quadratic fit of $\varphi_\text{opt}(\omega)$ over the $\pm 5$~THz signal band has $R^2 = 0.015$ at 100~m and $R^2 = 0.037$ at 2~m. A quadratic model explaining $< 4\%$ of the weighted variance is misspecified: $96$--$98\%$ of $\varphi_\text{opt}(\omega)$ on the signal band is non-quadratic residual structure orthogonal to $\{1, \omega, \omega^2\}$. The extracted $a_2$ is the projection of a non-quadratic signal onto that misspecified basis. The sign flip across $L$ is the direct consequence of the underlying coefficient being near zero --- exactly what $R^2 \to 0$ reports.

### Edit 3: verification_document.tex hessian J-anchoring caveat

Locate `\subsection{Hessian is indefinite at L-BFGS optima}` with label `sec:april-hessian` (line ~1255). After the existing `\begin{keyresult}...\end{keyresult}` block (which currently ends with "trust-region Newton on the 57-dim subspace ... is the principled next step."), insert a new paragraph BEFORE the next `\subsection{Determinism}`:

```latex
\begin{flagged}
\textbf{Caveat on the dB anchoring of the Hessian-study optima
(Phase 18 cross-check, 2026-04-19).}
The Phase 18 numerical-trustworthiness audit
(\texttt{results/validation/REPORT.md}) re-ran the saved
\texttt{phase13/hessian\_smf28\_canonical.jld2} and
\texttt{phase13/hessian\_hnlf\_canonical.jld2} on a
validator-controlled grid and recovered
$J = -48.2$~dB (SMF-28) and $J = -44.0$~dB (HNLF), versus the
$-60.5$~dB and $-74.4$~dB originally reported in the JLD2
metadata. The discrepancy is the time-window edge-bleed
artefact discussed in §\ref{sec:april-boundary} (output edge
fraction $1.0\%$ and $2.1\%$ respectively, just past the
SUSPECT threshold). \emph{The eigenstructure result above is
unaffected}: the saved $\varphi_\text{opt}$ files are true
stationary points on the recomputed grid (adjoint
$\|g\| \sim 10^{-5}$), so the Hessian was computed at a real
optimum --- just at a different $J$ value than originally
quoted. When citing this result alongside a dB number, use the
recomputed values $-48.2$~dB / $-44.0$~dB; when citing only
the eigenstructure, the original ratios stand. Audit:
\texttt{PHYSICS\_AUDIT\_2026-04-19.md} §X1. Source:
\texttt{results/validation/phase13\_hessian\_\{smf28,hnlf\}.md}.
\end{flagged}
```

(The `flagged` environment is already used elsewhere in this
section — see `\subsection{Multimode optimizer is code-complete,
physics-unexercised}` for the prior usage.)

### Edit 4: verification_document.tex Phase 18 cross-reference at §sec:april2026 intro

Locate `\section{Integration Pass --- April 2026}` with label
`sec:april2026` (line ~1175). The opening paragraph currently ends:

> ...a physics audit filtering those claims is \texttt{results/PHYSICS\_AUDIT\_2026-04-19.md} (2026-04-19). This section records only the claims that survived the audit, with scope caveats where the audit narrowed the original framing.

Replace the trailing sentence ("This section records only...") with:

> An independent numerical-trustworthiness audit re-ran every
> JLD2 under \texttt{results/raman/} on a validator-controlled
> grid and is reported at \texttt{results/validation/REPORT.md}
> (2026-04-19) — its findings drive the boundary-energy and
> Hessian-anchoring caveats in §\ref{sec:april-boundary} and
> §\ref{sec:april-hessian}. This section records only the
> claims that survived both audits, with scope caveats where
> either narrowed the original framing.

### Edit 5: PDF rebuild and verify

After Edits 1–4, rebuild all three PDFs:

```bash
cd docs && for f in companion_explainer physics_verification verification_document; do
  pdflatex -interaction=nonstopmode "$f.tex" >/dev/null 2>&1
  pdflatex -interaction=nonstopmode "$f.tex" >/dev/null 2>&1
done
```

Verify each .pdf was regenerated (mtime newer than .tex) and that
no LaTeX errors broke the build:

```bash
for f in companion_explainer physics_verification verification_document; do
  test "docs/$f.pdf" -nt "docs/$f.tex" || echo "STALE: $f"
  grep -E "^! " "docs/$f.log" || echo "$f: clean build"
done
```

### Edit 6: Commit

```bash
git add docs/companion_explainer.tex docs/companion_explainer.pdf \
        docs/physics_verification.tex docs/physics_verification.pdf \
        docs/verification_document.tex docs/verification_document.pdf \
        .planning/phases/20-docs-canonical-update/
git commit -m "docs(20): propagate Phase 19 audit refinements into canonical .tex + rebuild PDFs"
```

(Only `verification_document.tex` and `companion_explainer.tex` are
expected to change among the .tex files; `physics_verification.tex`
will only change if pdflatex regenerates the timestamp metadata.
Include all three PDFs since they all rebuild.)
</specifics>

<deferred>
## Deferred Ideas

- A separate "limitations and future work" appendix to
  `verification_document.tex` consolidating the four open
  research questions from `SYNTHESIS-2026-04-19.md` §4. Out of
  scope here — would expand the doc beyond audit propagation.
- Rewrite of the §"Summary and Conclusions" "strongest evidence"
  paragraph at line 1421 to soften the "Taylor remainder slopes
  of 2.00 and 2.04" claim now that S6 has scoped it. The
  scope-limitation paragraph at §sec:april-taylor already does
  this work indirectly; an additional softening of the headline
  is cosmetic and can wait for the next major doc revision.
</deferred>
